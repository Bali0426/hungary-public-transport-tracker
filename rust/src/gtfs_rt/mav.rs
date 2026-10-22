use std::collections::HashMap;
use anyhow::{Context, Result};
use prost::Message;
use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::gtfs_rt::models::{BoundingBox, Operator, UnifiedVehicle};
use crate::gtfs_rt::proto::FeedMessage;
use crate::static_db::repository::{format_hhmm, TripStopSchedule};

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
    #[serde(rename = "arrivalStoptime")]
    arrival_stoptime: Option<EmmaStoptime>,
    alerts: Option<Vec<EmmaAlert>>,
    stoptimes: Option<Vec<EmmaStoptimeEntry>>,
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

            let full_trip_name = item
                .trip
                .as_ref()
                .and_then(|t| t.trip_short_name.clone())
                .or_else(|| item.trip.as_ref().and_then(|t| t.domestic_train_number.clone()));

            let line_name = if let Some(d_num) = item
                .trip
                .as_ref()
                .and_then(|t| t.domestic_train_number.as_deref())
            {
                if !d_num.trim().is_empty() {
                    d_num.to_string()
                } else {
                    extract_short_line_name(full_trip_name.as_deref().unwrap_or("MÁV"))
                }
            } else {
                extract_short_line_name(full_trip_name.as_deref().unwrap_or("MÁV"))
            };

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

            vehicles.push(UnifiedVehicle {
                id: format!("MAV:{}", vid),
                operator: Operator::MAV,
                trip_id,
                route_id: None,
                line_name,
                destination,
                lat,
                lon,
                bearing: item.heading.unwrap_or(0.0),
                speed_mps: item.speed,
                delay_seconds: delay,
                timestamp: item.last_updated.unwrap_or(0),
                route_color: "0057B8".to_string(),
                vehicle_type: "train".to_string(),
                trip_short_name: full_trip_name,
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
