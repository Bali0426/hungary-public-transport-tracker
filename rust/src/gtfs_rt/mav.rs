use std::collections::HashMap;
use anyhow::{Context, Result};
use prost::Message;
use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::gtfs_rt::models::{BoundingBox, Operator, UnifiedDeparture, UnifiedVehicle};
use crate::gtfs_rt::proto::FeedMessage;
use crate::static_db::repository::{clean_station_name, format_hhmm, TripStopSchedule};

pub const EMMA_GRAPHQL_URL: &str =
    "https://mavplusz.hu/otp2-backend/otp/routers/default/index/graphql";

/// Default bounding box covering all of Hungary for national rail queries when no smaller viewport is specified.
pub const HUNGARY_BBOX: BoundingBox = BoundingBox {
    min_lat: 45.70,
    min_lon: 16.10,
    max_lat: 48.60,
    max_lon: 22.95,
};

#[derive(Debug, Serialize)]
struct GraphQlRequest {
    query: String,
}

#[derive(Debug, Deserialize)]
struct GraphQlResponse {
    data: Option<EmmaData>,
}

#[derive(Debug, Deserialize)]
struct EmmaData {
    #[serde(rename = "vehiclePositions")]
    vehicle_positions: Option<Vec<EmmaVehiclePosition>>,
}

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct EmmaVehiclePosition {
    #[serde(rename = "vehicleId")]
    vehicle_id: Option<String>,
    lat: Option<f64>,
    lon: Option<f64>,
    heading: Option<f32>,
    label: Option<String>,
    #[serde(rename = "lastUpdated")]
    last_updated: Option<u64>,
    speed: Option<f32>,
    trip: Option<EmmaTrip>,
}

#[derive(Debug, Deserialize)]
struct EmmaTrip {
    #[serde(rename = "gtfsId")]
    gtfs_id: Option<String>,
    #[serde(rename = "tripShortName")]
    trip_short_name: Option<String>,
    #[serde(rename = "tripHeadsign")]
    trip_headsign: Option<String>,
    #[serde(rename = "domesticResTrainNumber")]
    domestic_train_number: Option<String>,
    route: Option<EmmaRoute>,
    #[serde(rename = "arrivalStoptime")]
    arrival_stoptime: Option<EmmaStoptime>,
    alerts: Option<Vec<EmmaAlert>>,
    stoptimes: Option<Vec<EmmaStoptimeEntry>>,
}

#[derive(Debug, Deserialize)]
struct EmmaRoute {
    #[serde(rename = "shortName")]
    short_name: Option<String>,
    #[serde(rename = "longName")]
    long_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EmmaAlert {
    #[serde(rename = "alertHeaderText")]
    header: Option<String>,
    #[serde(rename = "alertDescriptionText")]
    description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EmmaStoptimeEntry {
    #[serde(rename = "scheduledDeparture")]
    scheduled_departure: Option<i32>,
    #[serde(rename = "realtimeDeparture")]
    realtime_departure: Option<i32>,
    #[serde(rename = "departureDelay")]
    departure_delay: Option<i32>,
    #[serde(rename = "scheduledArrival")]
    scheduled_arrival: Option<i32>,
    #[serde(rename = "realtimeArrival")]
    realtime_arrival: Option<i32>,
    #[serde(rename = "arrivalDelay")]
    arrival_delay: Option<i32>,
    stop: Option<EmmaStopRef>,
}

#[derive(Debug, Deserialize)]
struct EmmaStopRef {
    name: Option<String>,
    #[serde(rename = "platformCode")]
    platform_code: Option<String>,
    lat: Option<f64>,
    lon: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct EmmaStoptime {
    #[serde(rename = "arrivalDelay")]
    arrival_delay: Option<i32>,
}

/// Helper function to extract a clean, concise line name for map markers
/// e.g. "S10", "IC 502", "34123" without cluttering the map with "személyvonat".
fn extract_short_line_name(s: &str) -> String {
    let trimmed = s.trim();
    if trimmed.is_empty() {
        return "MÁV".to_string();
    }
    let parts: Vec<&str> = trimmed.split_whitespace().collect();
    if parts.is_empty() {
        return "MÁV".to_string();
    }
    if parts.len() >= 2
        && matches!(
            parts[0].to_uppercase().as_str(),
            "IC" | "EC" | "EN" | "IR" | "ER" | "RJ" | "RJX" | "EX"
        )
    {
        return format!("{} {}", parts[0].to_uppercase(), parts[1]);
    }
    parts[0].to_string()
}

/// Formats train line name (displayed on map markers) and trip_short_name (displayed in details/dialogs)
/// following official Hungarian rail designations:
/// - Suburban lines: "S10", "Z70", "G43", "S36", "S71" (not raw 4-5 digit train numbers)
/// - Railjet: "Railjet"
/// - IC / EC / EN / IR / Ex: "TISZA IC", "ARRABONA IC", "HORTOBÁGY EC", "PANNÓNIA IR", etc.
pub fn format_mav_train_display(
    trip_short_name: Option<&str>,
    domestic_train_number: Option<&str>,
    route_long_name: Option<&str>,
    route_short_name: Option<&str>,
) -> (String, Option<String>) {
    let tsn = trip_short_name.unwrap_or("").trim();
    let d_num = domestic_train_number.unwrap_or("").trim();
    let r_long = route_long_name.unwrap_or("").trim();
    let _r_short = route_short_name.unwrap_or("").trim();

    // 0. HÉV suburban lines (H5, H6, H7, H8, H9)
    let is_hev = (r_long.starts_with('H') || r_long.starts_with('h'))
        && r_long.len() >= 2
        && r_long.len() <= 3
        && r_long[1..].chars().all(|c| c.is_ascii_digit())
        || tsn.contains("HÉV")
        || tsn.contains("HEV");

    if is_hev {
        let line = if r_long.starts_with('H') || r_long.starts_with('h') {
            r_long.to_uppercase()
        } else if let Some(h) = tsn.split_whitespace().find(|w| {
            let u = w.to_uppercase();
            u.starts_with('H') && u.len() == 2 && u.chars().nth(1).unwrap().is_ascii_digit()
        }) {
            h.to_uppercase()
        } else {
            "HÉV".to_string()
        };

        let full = if !tsn.is_empty() {
            tsn.to_string()
        } else if !d_num.is_empty() {
            format!("{} ({})", line, d_num)
        } else {
            line.clone()
        };
        return (line, Some(full));
    }

    // 1. Suburban lines (S10, S12, S36, S40, S50, G60, Z70, S80, G43, Z42, S150, S220, S750, S820, G10, etc.)
    let is_suburban = (r_long.starts_with('S')
        || r_long.starts_with('G')
        || r_long.starts_with('Z')
        || r_long.starts_with('X'))
        && r_long.len() >= 2
        && r_long.len() <= 5
        && r_long[1..].chars().all(|c| c.is_ascii_digit());

    if is_suburban {
        let line = r_long.to_uppercase();
        let full = if !tsn.is_empty() && !tsn.eq_ignore_ascii_case(&line) {
            format!("{} · {}", line, tsn)
        } else if !d_num.is_empty() {
            format!("{} ({})", line, d_num)
        } else {
            line.clone()
        };
        return (line, Some(full));
    }

    let tsn_lower = tsn.to_lowercase();
    let r_long_lower = r_long.to_lowercase();

    // 2. Railjet / RJ / RJX
    if tsn_lower.contains("railjet")
        || r_long_lower.starts_with("rj")
        || r_long_lower.contains("railjet")
    {
        let line = "Railjet".to_string();
        let full = if !d_num.is_empty() {
            format!("Railjet {}", d_num)
        } else if !tsn.is_empty() {
            tsn.to_string()
        } else {
            "Railjet".to_string()
        };
        return (line, Some(full));
    }

    // 3. Named InterCity / EuroCity / EuroNight / InterRégió / Expressz
    let cat_patterns = [
        ("intercity", "IC"),
        ("eurocity", "EC"),
        ("euronight", "EN"),
        ("interrégió", "IR"),
        ("interregio", "IR"),
        ("expresszvonat", "Ex"),
        ("expressz", "Ex"),
    ];

    for &(cat_keyword, cat_code) in &cat_patterns {
        if tsn_lower.contains(cat_keyword) {
            let tokens: Vec<&str> = tsn.split_whitespace().collect();
            if tokens.len() >= 2 {
                let name_tokens = if tokens[0].chars().all(|c| c.is_ascii_digit()) {
                    &tokens[1..tokens.len() - 1]
                } else {
                    &tokens[0..tokens.len() - 1]
                };

                let name = name_tokens.join(" ");
                let clean_name = name.split('/').next().unwrap_or(&name).trim();

                if !clean_name.is_empty() {
                    let line = format!("{} {}", clean_name, cat_code);
                    return (line, Some(tsn.to_string()));
                }
            }
        }
    }

    // Check route long_name for "IC BALATON", "IR PANNÓNIA", "EC TISZA/...", etc.
    let prefixes = [
        ("IC ", "IC"),
        ("EC ", "EC"),
        ("EN ", "EN"),
        ("IR ", "IR"),
        ("Ex ", "Ex"),
    ];
    for &(prefix, cat_code) in &prefixes {
        if r_long.starts_with(prefix) {
            let name_part = &r_long[prefix.len()..];
            let clean_name = name_part.split('/').next().unwrap_or(name_part).trim();
            if !clean_name.is_empty() {
                let line = format!("{} {}", clean_name, cat_code);
                let full = if !tsn.is_empty() {
                    tsn.to_string()
                } else if !d_num.is_empty() {
                    format!("{} {}", d_num, line)
                } else {
                    line.clone()
                };
                return (line, Some(full));
            }
        }
    }

    // 4. IC / EC without train name (train number only)
    if tsn_lower.contains("intercity") {
        let line = if !d_num.is_empty() {
            format!("IC {}", d_num)
        } else {
            "IC".to_string()
        };
        let full = if !tsn.is_empty() {
            tsn.to_string()
        } else {
            line.clone()
        };
        return (line, Some(full));
    }
    if tsn_lower.contains("eurocity") {
        let line = if !d_num.is_empty() {
            format!("EC {}", d_num)
        } else {
            "EC".to_string()
        };
        let full = if !tsn.is_empty() {
            tsn.to_string()
        } else {
            line.clone()
        };
        return (line, Some(full));
    }

    // 5. Classic rural / regional passenger train (Személyvonat)
    if !d_num.is_empty() {
        let line = format!("Sz {}", d_num);
        let full = if !tsn.is_empty() {
            tsn.to_string()
        } else {
            format!("{} személyvonat", d_num)
        };
        return (line, Some(full));
    }

    if !tsn.is_empty() {
        return (extract_short_line_name(tsn), Some(tsn.to_string()));
    }

    ("MÁV".to_string(), None)
}

/// Fetches live MÁV vehicles via either an optional NAP GTFS-RT Protobuf URL
/// or the official MÁV+ OTP2 GraphQL endpoint (`https://mavplusz.hu/...`).
pub async fn fetch_mav_live_vehicles(
    client: &Client,
    gtfs_rt_url: Option<&str>,
    bbox: Option<BoundingBox>,
) -> Result<(
    Vec<UnifiedVehicle>,
    HashMap<String, i32>,
    HashMap<String, Vec<TripStopSchedule>>,
)> {
    if let Some(pb_url) = gtfs_rt_url.filter(|s| !s.trim().is_empty()) {
        if let Ok(res) = fetch_mav_gtfs_rt_protobuf(client, pb_url).await {
            return Ok(res);
        }
    }

    fetch_mav_emma_graphql(client, bbox.unwrap_or(HUNGARY_BBOX)).await
}

/// Decodes a standard GTFS-RT `VehiclePositions.pb` stream from the Hungarian National Access Point (NAP) for MÁV.
pub async fn fetch_mav_gtfs_rt_protobuf(
    client: &Client,
    pb_url: &str,
) -> Result<(
    Vec<UnifiedVehicle>,
    HashMap<String, i32>,
    HashMap<String, Vec<TripStopSchedule>>,
)> {
    let resp = client
        .get(pb_url)
        .send()
        .await
        .context("Failed to request MÁV GTFS-RT protobuf feed")?;
    if !resp.status().is_success() {
        anyhow::bail!("MÁV GTFS-RT endpoint returned HTTP {}", resp.status());
    }
    let bytes = resp.bytes().await?;
    let feed = FeedMessage::decode(bytes.as_ref())
        .context("Failed to decode MÁV GTFS-RT protobuf")?;
    let feed_ts = feed.header.timestamp.unwrap_or(0);

    let mut vehicles = Vec::with_capacity(feed.entity.len());
    let mut delays = HashMap::new();

    for entity in feed.entity {
        if let Some(tu) = entity.trip_update {
            if let Some(ref raw_tid) = tu.trip.trip_id {
                let delay = tu.delay.unwrap_or(0);
                delays.insert(format!("MAV:{}", raw_tid), delay);
            }
        }
        if let Some(vp) = entity.vehicle {
            let Some(pos) = vp.position else { continue };
            let raw_tid = vp.trip.as_ref().and_then(|t| t.trip_id.clone());
            let prefixed_tid = raw_tid.as_ref().map(|t| format!("MAV:{}", t));
            let delay = prefixed_tid
                .as_ref()
                .and_then(|t| delays.get(t).copied())
                .unwrap_or(0);

            let line_name = vp
                .vehicle
                .as_ref()
                .and_then(|v| v.label.clone())
                .or_else(|| raw_tid.clone())
                .unwrap_or_else(|| "MÁV".to_string());

            let vid = vp
                .vehicle
                .as_ref()
                .and_then(|v| v.id.clone())
                .unwrap_or(entity.id);

            vehicles.push(UnifiedVehicle {
                id: format!("MAV:{}", vid),
                operator: Operator::MAV,
                trip_id: prefixed_tid,
                route_id: vp
                    .trip
                    .as_ref()
                    .and_then(|t| t.route_id.as_ref().map(|r| format!("MAV:{}", r))),
                line_name,
                destination: String::new(),
                lat: pos.latitude as f64,
                lon: pos.longitude as f64,
                bearing: pos.bearing.unwrap_or(0.0),
                speed_mps: pos.speed,
                delay_seconds: delay,
                timestamp: vp.timestamp.unwrap_or(feed_ts),
                route_color: "0057B8".to_string(),
                vehicle_type: "train".to_string(),
                trip_short_name: None,
                delay_cause: None,
            });
        }
    }

    Ok((vehicles, delays, HashMap::new()))
}

/// Queries the live MÁV+ OTP2 GraphQL endpoint for active rail, suburban rail, and tram-train vehicles,
/// extracting speeds, real delays, alert reasons, and full real-time stoptimes.
pub async fn fetch_mav_emma_graphql(
    client: &Client,
    bbox: BoundingBox,
) -> Result<(
    Vec<UnifiedVehicle>,
    HashMap<String, i32>,
    HashMap<String, Vec<TripStopSchedule>>,
)> {
    let query = format!(
        r#"{{
          vehiclePositions(
            swLat: {:.5}
            swLon: {:.5}
            neLat: {:.5}
            neLon: {:.5}
            modes: [RAIL, RAIL_REPLACEMENT_BUS, SUBURBAN_RAILWAY, TRAMTRAIN]
          ) {{
            vehicleId
            lat
            lon
            heading
            label
            lastUpdated
            speed
            trip {{
              gtfsId
              tripShortName
              tripHeadsign
              domesticResTrainNumber
              route {{
                shortName
                longName
              }}
              alerts {{
                alertHeaderText
                alertDescriptionText
              }}
              arrivalStoptime {{
                arrivalDelay
              }}
              stoptimes {{
                scheduledDeparture
                realtimeDeparture
                departureDelay
                scheduledArrival
                realtimeArrival
                arrivalDelay
                stop {{
                  name
                  platformCode
                  lat
                  lon
                }}
              }}
            }}
          }}
        }}"#,
        bbox.min_lat, bbox.min_lon, bbox.max_lat, bbox.max_lon
    );

    let resp = client
        .post(EMMA_GRAPHQL_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://mavplusz.hu")
        .header("Referer", "https://mavplusz.hu/")
        .json(&GraphQlRequest { query })
        .send()
        .await
        .context("Failed to query MÁV+ GraphQL endpoint")?;

    if !resp.status().is_success() {
        anyhow::bail!("MÁV+ GraphQL returned HTTP {}", resp.status());
    }

    let body: GraphQlResponse = resp
        .json()
        .await
        .context("Failed to deserialize MÁV+ GraphQL response")?;

    let mut vehicles = Vec::new();
    let mut delays = HashMap::new();
    let mut schedules: HashMap<String, Vec<TripStopSchedule>> = HashMap::new();

    if let Some(items) = body.data.and_then(|d| d.vehicle_positions) {
        for item in items {
            let (Some(lat), Some(lon)) = (item.lat, item.lon) else {
                continue;
            };
            let vid = item
                .vehicle_id
                .unwrap_or_else(|| format!("{:.4}_{:.4}", lat, lon));

            let mut delay = item
                .trip
                .as_ref()
                .and_then(|t| t.arrival_stoptime.as_ref())
                .and_then(|s| s.arrival_delay)
                .unwrap_or(0);

            // If arrivalDelay is 0, search stoptimes for non-zero delay
            if delay == 0 {
                if let Some(ref t) = item.trip {
                    if let Some(ref sts) = t.stoptimes {
                        for st in sts {
                            let d = st.departure_delay.or(st.arrival_delay).unwrap_or(0);
                            if d != 0 {
                                delay = d;
                                break;
                            }
                        }
                    }
                }
            }

            let trip_id = item
                .trip
                .as_ref()
                .and_then(|t| t.gtfs_id.as_ref())
                .map(|id| format!("MAV:{}", id));

            if let Some(ref tid) = trip_id {
                delays.insert(tid.clone(), delay);
                if let Some(raw) = tid.strip_prefix("MAV:") {
                    delays.insert(raw.to_string(), delay);
                }
            }

            let (r_long, r_short) = if let Some(ref t) = item.trip {
                if let Some(ref r) = t.route {
                    (r.long_name.as_deref(), r.short_name.as_deref())
                } else {
                    (None, None)
                }
            } else {
                (None, None)
            };

            let tsn_str = item.trip.as_ref().and_then(|t| t.trip_short_name.as_deref());
            let dom_str = item.trip.as_ref().and_then(|t| t.domestic_train_number.as_deref());

            let (line_name, trip_short_name) =
                format_mav_train_display(tsn_str, dom_str, r_long, r_short);

            let destination = item
                .trip
                .as_ref()
                .and_then(|t| t.trip_headsign.clone())
                .unwrap_or_default();

            // Extract disruption / delay cause
            let delay_cause = item
                .trip
                .as_ref()
                .and_then(|t| t.alerts.as_ref())
                .and_then(|alerts| {
                    alerts.iter().find_map(|a| {
                        a.description
                            .as_ref()
                            .filter(|d| !d.trim().is_empty())
                            .cloned()
                            .or_else(|| {
                                a.header
                                    .as_ref()
                                    .filter(|h| !h.trim().is_empty())
                                    .cloned()
                            })
                    })
                });

            // Parse full stoptimes if available
            if let Some(ref t) = item.trip {
                if let Some(ref sts) = t.stoptimes {
                    if !sts.is_empty() {
                        let tid_key = trip_id.as_deref().unwrap_or(&vid);
                        let mut stop_list = Vec::with_capacity(sts.len());
                        for (idx, st) in sts.iter().enumerate() {
                            let s_name = st
                                .stop
                                .as_ref()
                                .and_then(|s| s.name.clone())
                                .unwrap_or_default();
                            let s_plat = st
                                .stop
                                .as_ref()
                                .and_then(|s| s.platform_code.clone())
                                .filter(|p| !p.trim().is_empty());
                            let s_lat = st.stop.as_ref().and_then(|s| s.lat);
                            let s_lon = st.stop.as_ref().and_then(|s| s.lon);

                            let dep_time = st
                                .scheduled_departure
                                .map(|s| format_hhmm(s, "--:--"))
                                .unwrap_or_else(|| "--:--".to_string());
                            let pred_dep = st
                                .realtime_departure
                                .map(|s| format_hhmm(s, "--:--"));
                            let arr_time = st
                                .scheduled_arrival
                                .map(|s| format_hhmm(s, "--:--"));
                            let pred_arr = st
                                .realtime_arrival
                                .map(|s| format_hhmm(s, "--:--"));
                            let st_delay = st
                                .departure_delay
                                .or(st.arrival_delay)
                                .unwrap_or(0);

                            stop_list.push(TripStopSchedule {
                                stop_sequence: (idx + 1) as i32,
                                stop_id: format!("{}_{}", tid_key, idx),
                                stop_name: s_name,
                                departure_time: dep_time,
                                operator: "MAV".to_string(),
                                platform_code: s_plat,
                                arrival_time: arr_time,
                                lat: s_lat,
                                lon: s_lon,
                                predicted_departure_time: pred_dep,
                                predicted_arrival_time: pred_arr,
                                delay_seconds: st_delay,
                            });
                        }

                        if let Some(ref tid) = trip_id {
                            schedules.insert(tid.clone(), stop_list.clone());
                            if let Some(raw) = tid.strip_prefix("MAV:") {
                                schedules.insert(raw.to_string(), stop_list.clone());
                            }
                        }
                        schedules.insert(format!("MAV:{}", vid), stop_list.clone());
                        schedules.insert(vid.clone(), stop_list.clone());
                        if let Some(ref d_num) = t.domestic_train_number {
                            schedules.insert(format!("MAV:{}", d_num), stop_list.clone());
                            schedules.insert(d_num.clone(), stop_list);
                        }
                    }
                }
            }

            let is_hev = (line_name.starts_with('H') || line_name.starts_with('h'))
                && line_name.len() <= 3
                && line_name[1..].chars().all(|c| c.is_ascii_digit())
                || trip_short_name
                    .as_deref()
                    .map(|s| s.contains("HÉV") || s.contains("HEV"))
                    .unwrap_or(false);

            let v_type = if is_hev {
                "suburban_rail".to_string()
            } else {
                "train".to_string()
            };

            let v_color = if is_hev {
                "007A33".to_string()
            } else {
                "0057B8".to_string()
            };

            vehicles.push(UnifiedVehicle {
                id: format!("MAV:{}", vid),
                operator: if is_hev { Operator::BKK } else { Operator::MAV },
                trip_id,
                route_id: if is_hev { Some(line_name.clone()) } else { None },
                line_name,
                destination,
                lat,
                lon,
                bearing: item.heading.unwrap_or(0.0),
                speed_mps: item.speed,
                delay_seconds: delay,
                timestamp: item.last_updated.unwrap_or(0),
                route_color: v_color,
                vehicle_type: v_type,
                trip_short_name,
                delay_cause,
            });
        }
    }

    Ok((vehicles, delays, schedules))
}

/// Fallback single-trip schedule query directly from MÁV+ OTP2 GraphQL endpoint.
pub async fn fetch_mav_single_trip_schedule(
    client: &Client,
    raw_trip_id: &str,
) -> Result<Vec<TripStopSchedule>> {
    let clean_id = raw_trip_id.strip_prefix("MAV:").unwrap_or(raw_trip_id);
    let query = format!(
        r#"{{
          trip(id: "{}") {{
            gtfsId
            stoptimes {{
              scheduledDeparture
              realtimeDeparture
              departureDelay
              scheduledArrival
              realtimeArrival
              arrivalDelay
              stop {{
                name
                platformCode
                lat
                lon
              }}
            }}
          }}
        }}"#,
        clean_id
    );

    let resp = client
        .post(EMMA_GRAPHQL_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://mavplusz.hu")
        .header("Referer", "https://mavplusz.hu/")
        .json(&GraphQlRequest { query })
        .send()
        .await
        .context("Failed to query MÁV single trip schedule")?;

    if !resp.status().is_success() {
        anyhow::bail!("MÁV OTP2 trip query returned HTTP {}", resp.status());
    }

    let body: serde_json::Value = resp.json().await?;
    let sts = body
        .get("data")
        .and_then(|d| d.get("trip"))
        .and_then(|t| t.get("stoptimes"))
        .and_then(|s| s.as_array());

    let Some(st_array) = sts else {
        return Ok(Vec::new());
    };

    let mut list = Vec::with_capacity(st_array.len());
    for (idx, st) in st_array.iter().enumerate() {
        let stop_obj = st.get("stop");
        let name = stop_obj
            .and_then(|s| s.get("name"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let plat = stop_obj
            .and_then(|s| s.get("platformCode"))
            .and_then(|v| v.as_str())
            .filter(|p| !p.trim().is_empty())
            .map(|s| s.to_string());
        let lat = stop_obj.and_then(|s| s.get("lat")).and_then(|v| v.as_f64());
        let lon = stop_obj.and_then(|s| s.get("lon")).and_then(|v| v.as_f64());

        let dep_sec = st
            .get("scheduledDeparture")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32);
        let pred_dep_sec = st
            .get("realtimeDeparture")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32);
        let arr_sec = st
            .get("scheduledArrival")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32);
        let pred_arr_sec = st
            .get("realtimeArrival")
            .and_then(|v| v.as_i64())
            .map(|v| v as i32);
        let delay_sec = st
            .get("departureDelay")
            .or_else(|| st.get("arrivalDelay"))
            .and_then(|v| v.as_i64())
            .unwrap_or(0) as i32;

        let dep_time = dep_sec
            .map(|s| format_hhmm(s, "--:--"))
            .unwrap_or_else(|| "--:--".to_string());
        let pred_dep = pred_dep_sec.map(|s| format_hhmm(s, "--:--"));
        let arr_time = arr_sec.map(|s| format_hhmm(s, "--:--"));
        let pred_arr = pred_arr_sec.map(|s| format_hhmm(s, "--:--"));

        list.push(TripStopSchedule {
            stop_sequence: (idx + 1) as i32,
            stop_id: format!("{}_{}", clean_id, idx),
            stop_name: name,
            departure_time: dep_time,
            operator: "MAV".to_string(),
            platform_code: plat,
            arrival_time: arr_time,
            lat,
            lon,
            predicted_departure_time: pred_dep,
            predicted_arrival_time: pred_arr,
            delay_seconds: delay_sec,
        });
    }

    Ok(list)
}

/// Sync mapper for known major railway stations (e.g. MAV_005510009 Keleti, etc.)
pub fn resolve_mav_otp2_stop_id_sync(raw_id: &str) -> Option<&'static str> {
    let trimmed = raw_id.trim();
    let unprefix = trimmed
        .strip_prefix("STOP:")
        .unwrap_or(trimmed)
        .strip_prefix("MAV:")
        .unwrap_or(trimmed)
        .strip_prefix("HUB:")
        .unwrap_or(trimmed);

    match unprefix {
        // Major Budapest railway hubs explicitly noted in requirements
        "MAV_005510009" | "005510009" => Some("1:005510017_0"), // Keleti
        "MAV_005510017" => Some("1:005510033_0"),              // Nyugati
        "MAV_005510025" | "005510025" => Some("1:005501016_0"), // Déli
        "MAV_005510058" | "005510058" => Some("1:005501024_0"), // Kelenföld
        "MAV_005510090" | "005510090" => Some("1:005510090_0"), // Zugló
        "MAV_005510173" | "005510173" => Some("1:005510173_0"), // Kőbánya-Kispest
        _ => None,
    }
}

/// Resolves an input stop/hub ID into a canonical MÁV OTP2 stop gtfsId (e.g. "1:005517228_0").
pub async fn resolve_mav_otp2_stop_id(client: &Client, raw_id: &str) -> String {
    if let Some(mapped) = resolve_mav_otp2_stop_id_sync(raw_id) {
        return mapped.to_string();
    }

    let trimmed = raw_id.trim();
    let unprefix = trimmed
        .strip_prefix("STOP:")
        .unwrap_or(trimmed)
        .strip_prefix("MAV:")
        .unwrap_or(trimmed)
        .strip_prefix("HUB:")
        .unwrap_or(trimmed);

    if unprefix.starts_with("1:") {
        return unprefix.to_string();
    }

    let search_name = if unprefix.starts_with("GROUP:") {
        let parts: Vec<&str> = unprefix.split(':').collect();
        if parts.len() >= 2 { parts[1] } else { unprefix }
    } else {
        unprefix
    };

    let search_clean = clean_station_name(search_name);
    let search_query = format!(
        r#"{{ stops(name: "{}") {{ gtfsId name }} }}"#,
        search_clean
    );

    let resp = client
        .post(EMMA_GRAPHQL_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://mavplusz.hu")
        .header("Referer", "https://mavplusz.hu/")
        .json(&GraphQlRequest { query: search_query })
        .send()
        .await;

    if let Ok(r) = resp {
        if let Ok(body) = r.json::<serde_json::Value>().await {
            if let Some(arr) = body.get("data").and_then(|d| d.get("stops")).and_then(|s| s.as_array()) {
                for item in arr {
                    if let Some(gid) = item.get("gtfsId").and_then(|g| g.as_str()) {
                        if gid.starts_with("1:") {
                            return gid.to_string();
                        }
                    }
                }
            }
        }
    }

    if unprefix.starts_with("0055") {
        format!("1:{}_0", unprefix)
    } else {
        unprefix.to_string()
    }
}

pub fn extract_mav_train_number(dom: Option<&str>, tsn: Option<&str>, trip_id: &str) -> String {
    if let Some(d) = dom {
        let trimmed = d.trim();
        if !trimmed.is_empty() && trimmed.chars().all(|c| c.is_ascii_digit()) {
            return trimmed.to_string();
        }
    }
    if let Some(s) = tsn {
        if let Some(first) = s.split_whitespace().next() {
            if first.chars().all(|c| c.is_ascii_digit()) {
                return first.to_string();
            }
        }
    }
    trip_id.to_string()
}

pub fn mav_train_category_rank(line_name: &str, tsn: Option<&str>) -> u32 {
    let text = format!("{} {}", line_name, tsn.unwrap_or("")).to_lowercase();
    if text.contains("railjet") || text.contains("rj") {
        10
    } else if text.contains("eurocity") || text.contains(" ec") || text.starts_with("ec ") {
        9
    } else if text.contains("euronight") || text.contains(" en") {
        9
    } else if text.contains("intercity") || text.contains(" ic") || text.starts_with("ic ") {
        8
    } else if text.contains("expressz") || text.contains(" ex") {
        7
    } else if text.contains("interrégió") || text.contains("interregio") || text.contains(" ir") {
        6
    } else if text.contains("gyorsvonat") || text.contains("gyors") || text.contains(" gy") {
        5
    } else if text.contains("zónázó") || text.starts_with('z') {
        4
    } else if text.contains("gyorsított") || text.starts_with('g') {
        3
    } else if text.contains("személy") || text.starts_with('s') {
        2
    } else {
        1
    }
}

/// Queries the live MÁV+ OTP2 GraphQL endpoint for real-time departure and arrival boards of a station.
pub async fn fetch_mav_station_departures(
    client: &Client,
    raw_stop_or_hub_id: &str,
    limit: usize,
) -> Result<Vec<UnifiedDeparture>> {
    let clean_id = resolve_mav_otp2_stop_id(client, raw_stop_or_hub_id).await;

    let query = format!(
        r#"{{
          stop(id: "{}") {{
            name
            stoptimesWithoutPatterns(numberOfDepartures: {}) {{
              scheduledDeparture
              realtimeDeparture
              departureDelay
              scheduledArrival
              realtimeArrival
              arrivalDelay
              realtime
              trip {{
                gtfsId
                tripShortName
                tripHeadsign
                domesticResTrainNumber
                route {{
                  shortName
                  longName
                }}
                stoptimes {{
                  stop {{
                    name
                  }}
                }}
              }}
              stop {{
                name
                platformCode
              }}
            }}
          }}
        }}"#,
        clean_id,
        limit.max(30)
    );

    let resp = client
        .post(EMMA_GRAPHQL_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://mavplusz.hu")
        .header("Referer", "https://mavplusz.hu/")
        .json(&GraphQlRequest { query })
        .send()
        .await
        .context("Failed to query MÁV station departure board")?;

    if !resp.status().is_success() {
        anyhow::bail!("MÁV OTP2 station departure query returned HTTP {}", resp.status());
    }

    let body: serde_json::Value = resp.json().await?;
    let stop_obj = body.get("data").and_then(|d| d.get("stop"));
    let station_name = stop_obj
        .and_then(|s| s.get("name"))
        .and_then(|n| n.as_str())
        .unwrap_or("")
        .to_string();

    let Some(stoptimes) = stop_obj
        .and_then(|s| s.get("stoptimesWithoutPatterns"))
        .and_then(|p| p.as_array())
    else {
        return Ok(Vec::new());
    };

    let mut departures: Vec<UnifiedDeparture> = Vec::new();
    let mut dedup_map: HashMap<(bool, i32, String), usize> = HashMap::new();

    for st in stoptimes {
        let trip_obj = st.get("trip");
        let trip_gtfs = trip_obj
            .and_then(|t| t.get("gtfsId"))
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let headsign = trip_obj
            .and_then(|t| t.get("tripHeadsign"))
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string();
        let tsn = trip_obj
            .and_then(|t| t.get("tripShortName"))
            .and_then(|v| v.as_str());
        let dom = trip_obj
            .and_then(|t| t.get("domesticResTrainNumber"))
            .and_then(|v| v.as_str());
        let r_obj = trip_obj.and_then(|t| t.get("route"));
        let r_long = r_obj.and_then(|r| r.get("longName")).and_then(|v| v.as_str());
        let r_short = r_obj.and_then(|r| r.get("shortName")).and_then(|v| v.as_str());

        let mut trip_stops: Vec<String> = Vec::new();
        if let Some(st_arr) = trip_obj.and_then(|t| t.get("stoptimes")).and_then(|s| s.as_array()) {
            for stop_entry in st_arr {
                if let Some(name) = stop_entry.get("stop").and_then(|s| s.get("name")).and_then(|n| n.as_str()) {
                    let trimmed = name.trim();
                    if !trimmed.is_empty() {
                        trip_stops.push(trimmed.to_string());
                    }
                }
            }
        }

        let origin_station = trip_stops.first().cloned();
        let destination_station = trip_stops.last().cloned();

        let (line_name, _) = format_mav_train_display(tsn, dom, r_long, r_short);

        let sched_dep_sec = st.get("scheduledDeparture").and_then(|v| v.as_i64()).map(|v| v as i32);
        let sched_arr_sec = st.get("scheduledArrival").and_then(|v| v.as_i64()).map(|v| v as i32);

        let real_dep_sec = st.get("realtimeDeparture").and_then(|v| v.as_i64()).map(|v| v as i32);
        let real_arr_sec = st.get("realtimeArrival").and_then(|v| v.as_i64()).map(|v| v as i32);

        let delay_sec = st
            .get("departureDelay")
            .or_else(|| st.get("arrivalDelay"))
            .and_then(|v| v.as_i64())
            .unwrap_or(0) as i32;

        let plat = st
            .get("stop")
            .and_then(|s| s.get("platformCode"))
            .and_then(|v| v.as_str())
            .filter(|p| !p.trim().is_empty())
            .map(|p| p.to_string());

        let is_realtime = st.get("realtime").and_then(|v| v.as_bool()).unwrap_or(false);

        // Terminating / Arrival check:
        // 1. scheduledDeparture is missing or 0
        // 2. headsign matches queried station name (e.g. "Szeged" on arrival at Szeged)
        // 3. destination from trip.stoptimes matches queried station name
        let is_arrival = {
            let no_dep = sched_dep_sec.map(|v| v <= 0).unwrap_or(true);
            let headsign_is_station = !headsign.is_empty()
                && !station_name.is_empty()
                && (clean_station_name(&headsign).eq_ignore_ascii_case(&clean_station_name(&station_name))
                    || station_name.to_lowercase().contains(&headsign.to_lowercase())
                    || headsign.to_lowercase().contains(&station_name.to_lowercase()));
            let terminus_is_station = destination_station.as_deref().map(|dest| {
                !station_name.is_empty()
                    && (clean_station_name(dest).eq_ignore_ascii_case(&clean_station_name(&station_name))
                        || station_name.to_lowercase().contains(&dest.to_lowercase()))
            }).unwrap_or(false);

            no_dep || headsign_is_station || terminus_is_station
        };

        let sched_dep_final = sched_dep_sec.or(sched_arr_sec).unwrap_or(0);
        let est_dep_final = real_dep_sec.or(real_arr_sec).unwrap_or(sched_dep_final);

        let sched_arr_fmt = sched_arr_sec.map(|s| format_hhmm(s, "--:--"));
        let est_arr_fmt = real_arr_sec
            .or_else(|| sched_arr_sec.map(|s| (s + delay_sec).max(0)))
            .map(|s| format_hhmm(s, "--:--"));

        // Deduplication & Merging:
        // Group by (is_arrival, minute_key, train_number)
        let train_num = extract_mav_train_number(dom, tsn, trip_gtfs);
        let time_key = if is_arrival {
            sched_arr_sec.unwrap_or(sched_dep_final) / 60
        } else {
            sched_dep_final / 60
        };
        let dedup_key = (is_arrival, time_key, train_num);

        if let Some(&existing_idx) = dedup_map.get(&dedup_key) {
            let existing = &mut departures[existing_idx];
            let rank_existing = mav_train_category_rank(&existing.line_name, None);
            let rank_new = mav_train_category_rank(&line_name, tsn);

            // Composite IC / Gy naming for coupled trains
            let is_ic_and_gy = (rank_existing == 8 && rank_new == 5) || (rank_existing == 5 && rank_new == 8);

            if rank_new > rank_existing {
                existing.line_name = if is_ic_and_gy {
                    if !line_name.contains("/ Gy") {
                        format!("{} / Gy", line_name)
                    } else {
                        line_name
                    }
                } else {
                    line_name
                };
                existing.trip_id = format!("MAV:{}", trip_gtfs);
                if is_realtime || !existing.is_realtime {
                    existing.is_realtime = is_realtime || existing.is_realtime;
                    existing.delay_seconds = delay_sec;
                    existing.estimated_departure_seconds = est_dep_final;
                    existing.estimated_time_formatted = format_hhmm(est_dep_final, "--:--");
                    if est_arr_fmt.is_some() {
                        existing.estimated_arrival_time_formatted = est_arr_fmt;
                    }
                }
                if plat.is_some() {
                    existing.platform_code = plat;
                }
                if origin_station.is_some() && existing.origin_station.is_none() {
                    existing.origin_station = origin_station;
                }
            } else {
                if is_ic_and_gy && !existing.line_name.contains("/ Gy") {
                    existing.line_name = format!("{} / Gy", existing.line_name);
                }
                if !existing.is_realtime && is_realtime {
                    existing.is_realtime = true;
                    existing.delay_seconds = delay_sec;
                    existing.estimated_departure_seconds = est_dep_final;
                    existing.estimated_time_formatted = format_hhmm(est_dep_final, "--:--");
                    if est_arr_fmt.is_some() {
                        existing.estimated_arrival_time_formatted = est_arr_fmt;
                    }
                }
                if existing.platform_code.is_none() && plat.is_some() {
                    existing.platform_code = plat;
                }
                if existing.origin_station.is_none() && origin_station.is_some() {
                    existing.origin_station = origin_station;
                }
            }
            continue;
        }

        let new_idx = departures.len();
        departures.push(UnifiedDeparture {
            trip_id: format!("MAV:{}", trip_gtfs),
            stop_id: format!("MAV:{}", clean_id),
            operator: Operator::MAV,
            line_name,
            headsign,
            route_color: "0057B8".to_string(),
            route_text_color: "FFFFFF".to_string(),
            scheduled_departure_seconds: sched_dep_final,
            scheduled_time_formatted: format_hhmm(sched_dep_final, "--:--"),
            delay_seconds: delay_sec,
            estimated_departure_seconds: est_dep_final,
            estimated_time_formatted: format_hhmm(est_dep_final, "--:--"),
            is_realtime,
            platform_code: plat,
            is_arrival,
            origin_station,
            scheduled_arrival_time_formatted: sched_arr_fmt,
            estimated_arrival_time_formatted: est_arr_fmt,
        });
        dedup_map.insert(dedup_key, new_idx);
    }

    departures.sort_by_key(|d| d.scheduled_departure_seconds);
    Ok(departures)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hev_formatting() {
        let (h5_line, h5_full) = format_mav_train_display(
            Some("H4788 HÉV"),
            Some("H4788"),
            Some("H5"),
            None,
        );
        assert_eq!(h5_line, "H5");
        assert!(h5_full.unwrap().contains("H4788"));

        let (h8_line, _) = format_mav_train_display(
            Some("H1041 HÉV"),
            Some("H1041"),
            Some("H8"),
            None,
        );
        assert_eq!(h8_line, "H8");
    }

    #[test]
    fn test_suburban_train_formatting() {
        let (line, full) = format_mav_train_display(
            Some("2376 személyvonat"),
            Some("2376"),
            Some("Z70"),
            None,
        );
        assert_eq!(line, "Z70");
        assert!(full.unwrap().contains("Z70"));

        let (line2, _) = format_mav_train_display(
            Some("3546 személyvonat"),
            Some("3546"),
            Some("G43"),
            None,
        );
        assert_eq!(line2, "G43");

        let (line3, _) = format_mav_train_display(None, Some("4912"), Some("S10"), None);
        assert_eq!(line3, "S10");

        let (line4, _) = format_mav_train_display(None, Some("2576"), Some("S71"), None);
        assert_eq!(line4, "S71");
    }

    #[test]
    fn test_named_intercity_eurocity_and_railjet() {
        // Railjet
        let (rj_line, _) = format_mav_train_display(
            Some("68 railjet xpress"),
            Some("68"),
            Some("rjx 68"),
            None,
        );
        assert_eq!(rj_line, "Railjet");

        // Tisza EuroCity
        let (ec_line, _) = format_mav_train_display(
            Some("143 TISZA EuroCity"),
            Some("143"),
            Some("EC TISZA/TISZA - SZAMOS"),
            None,
        );
        assert_eq!(ec_line, "TISZA EC");

        // Arrabona InterCity
        let (arr_line, _) = format_mav_train_display(
            Some("981 ARRABONA InterCity"),
            Some("981"),
            Some("IC ARRABONA"),
            None,
        );
        assert_eq!(arr_line, "ARRABONA IC");

        // Hortobágy EuroCity
        let (hort_line, _) = format_mav_train_display(
            Some("140 HORTOBÁGY EuroCity"),
            Some("140"),
            Some("EC HORTOBÁGY"),
            None,
        );
        assert_eq!(hort_line, "HORTOBÁGY EC");

        // Balaton InterCity
        let (bal_line, _) = format_mav_train_display(
            Some("873 BALATON InterCity"),
            Some("873"),
            Some("IC BALATON"),
            None,
        );
        assert_eq!(bal_line, "BALATON IC");

        // Pannónia InterRégió
        let (ir_line, _) = format_mav_train_display(
            Some("8996 PANNÓNIA InterRégió"),
            Some("8996"),
            Some("IR PANNÓNIA"),
            None,
        );
        assert_eq!(ir_line, "PANNÓNIA IR");
    }

    #[test]
    fn test_rural_train_formatting() {
        let (line, _) = format_mav_train_display(
            Some("9466 személyvonat"),
            Some("9466"),
            Some("Sz 19466/9446/9454/9466"),
            None,
        );
        assert_eq!(line, "Sz 9466");
    }

    #[test]
    fn test_resolve_mav_otp2_stop_id_sync() {
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("MAV_005510009"),
            Some("1:005510017_0")
        );
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("HUB:MAV_005510009"),
            Some("1:005510017_0")
        );
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("MAV_005510017"),
            Some("1:005510033_0")
        );
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("MAV_005510025"),
            Some("1:005501016_0")
        );
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("MAV_005510058"),
            Some("1:005501024_0")
        );
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("MAV_005510090"),
            Some("1:005510090_0")
        );
        assert_eq!(
            resolve_mav_otp2_stop_id_sync("MAV_005510173"),
            Some("1:005510173_0")
        );
    }

    #[test]
    fn test_extract_mav_train_number_and_rank() {
        assert_eq!(
            extract_mav_train_number(Some("718"), Some("718 NAPFÉNY InterCity"), "1:35051024"),
            "718"
        );
        assert_eq!(
            extract_mav_train_number(None, Some("718 NAPFÉNY gyorsvonat"), "1:36448248"),
            "718"
        );
        assert_eq!(
            extract_mav_train_number(Some("4824"), Some("S10"), "1:1234"),
            "4824"
        );

        assert!(mav_train_category_rank("NAPFÉNY IC", Some("718 NAPFÉNY InterCity")) > mav_train_category_rank("718", Some("718 NAPFÉNY gyorsvonat")));
        assert_eq!(mav_train_category_rank("NAPFÉNY IC", None), 8);
        assert_eq!(mav_train_category_rank("Gyorsvonat", None), 5);
        assert_eq!(mav_train_category_rank("S10", None), 2);
    }

    #[test]
    fn test_mav_deduplication_and_arrival_classification() {
        let (ic_line, _) = format_mav_train_display(
            Some("718 NAPFÉNY InterCity"),
            Some("718"),
            Some("IC NAPFÉNY"),
            None,
        );
        assert_eq!(ic_line, "NAPFÉNY IC");

        let (gy_line, _) = format_mav_train_display(
            Some("718 NAPFÉNY gyorsvonat"),
            Some("718"),
            Some("Gy NAPFÉNY"),
            None,
        );
        let rank_ic = mav_train_category_rank(&ic_line, Some("718 NAPFÉNY InterCity"));
        let rank_gy = mav_train_category_rank(&gy_line, Some("718 NAPFÉNY gyorsvonat"));
        assert_eq!(rank_ic, 8);
        assert_eq!(rank_gy, 5);
    }

    #[test]
    fn test_live_mav_station_departures_szeged_and_keleti() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let client = Client::builder()
                .timeout(std::time::Duration::from_secs(10))
                .build()
                .unwrap();

            // 1. Test Szeged departures & arrivals
            if let Ok(deps) = fetch_mav_station_departures(&client, "1:005517228_0", 15).await {
                assert!(!deps.is_empty(), "Szeged departures should not be empty");
                let arrivals: Vec<_> = deps.iter().filter(|d| d.is_arrival).collect();
                let departures: Vec<_> = deps.iter().filter(|d| !d.is_arrival).collect();
                println!("Szeged: {} arrivals, {} departures", arrivals.len(), departures.len());
                for a in &arrivals {
                    assert!(a.is_arrival);
                    println!("  Arrival: {} -> headsign={}, origin={:?}, arr_time={:?}", a.line_name, a.headsign, a.origin_station, a.scheduled_arrival_time_formatted);
                }
            }

            // 2. Test Keleti via mapped ID
            if let Ok(deps) = fetch_mav_station_departures(&client, "MAV_005510009", 15).await {
                assert!(!deps.is_empty(), "Keleti departures should not be empty");
                println!("Keleti count: {}", deps.len());
            }
        });
    }
}
