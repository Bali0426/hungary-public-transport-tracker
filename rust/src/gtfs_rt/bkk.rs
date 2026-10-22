use std::collections::HashMap;
use anyhow::{Context, Result};
use prost::Message;
use reqwest::Client;

use crate::gtfs_rt::models::{Operator, UnifiedVehicle};
use crate::gtfs_rt::proto::FeedMessage;
use crate::static_db::repository::StaticTransitRepository;

pub const BKK_VEHICLE_POSITIONS_URL: &str =
    "https://go.bkk.hu/api/query/v1/ws/gtfs-rt/full/VehiclePositions.pb";
pub const BKK_TRIP_UPDATES_URL: &str =
    "https://go.bkk.hu/api/query/v1/ws/gtfs-rt/full/TripUpdates.pb";

/// Fetches and decodes BKK FUTÁR GTFS-RT `VehiclePositions.pb` and `TripUpdates.pb` feeds,
/// enriching each vehicle with static route metadata and real-time trip delays.
pub async fn fetch_bkk_live_vehicles(
    client: &Client,
    api_key: &str,
    repo: Option<&StaticTransitRepository>,
) -> Result<(Vec<UnifiedVehicle>, HashMap<String, i32>)> {
    let vp_url = format!("{}?key={}", BKK_VEHICLE_POSITIONS_URL, api_key);
    let tu_url = format!("{}?key={}", BKK_TRIP_UPDATES_URL, api_key);

    let (vp_res, tu_res) = tokio::join!(
        client.get(&vp_url).send(),
        client.get(&tu_url).send()
    );

    let mut trip_delays: HashMap<String, i32> = HashMap::new();

    if let Ok(resp) = tu_res {
        if resp.status().is_success() {
            if let Ok(bytes) = resp.bytes().await {
                if let Ok(feed) = FeedMessage::decode(bytes.as_ref()) {
                    for entity in feed.entity {
                        if let Some(tu) = entity.trip_update {
                            if let Some(raw_trip_id) = tu.trip.trip_id {
                                let full_trip_id = format!("BKK:{}", raw_trip_id);
                                let delay = tu.delay.or_else(|| {
                                    // Search for first non-zero delay or last reported stop delay
                                    tu.stop_time_update
                                        .iter()
                                        .filter_map(|stu| {
                                            stu.departure
                                                .as_ref()
                                                .and_then(|d| d.delay)
                                                .or_else(|| stu.arrival.as_ref().and_then(|a| a.delay))
                                        })
                                        .find(|&d| d != 0)
                                        .or_else(|| {
                                            tu.stop_time_update.last().and_then(|stu| {
                                                stu.departure
                                                    .as_ref()
                                                    .and_then(|d| d.delay)
                                                    .or_else(|| stu.arrival.as_ref().and_then(|a| a.delay))
                                            })
                                        })
                                }).unwrap_or(0);
                                trip_delays.insert(full_trip_id, delay);
                            }
                        }
                    }
                }
            }
        }
    }

    let vp_resp = vp_res.context("Failed to reach BKK VehiclePositions.pb endpoint")?;
    let vp_status = vp_resp.status();
    if !vp_status.is_success() {
        anyhow::bail!("BKK VehiclePositions.pb returned HTTP {}", vp_status);
    }

    let vp_bytes = vp_resp
        .bytes()
        .await
        .context("Failed to read BKK VehiclePositions.pb body")?;
    let vehicles = decode_bkk_vehicle_positions_bytes(vp_bytes.as_ref(), &trip_delays, repo)?;

    Ok((vehicles, trip_delays))
}

/// Pure decoder function for BKK `VehiclePositions.pb` binary payloads.
pub fn decode_bkk_vehicle_positions_bytes(
    bytes: &[u8],
    trip_delays: &HashMap<String, i32>,
    repo: Option<&StaticTransitRepository>,
) -> Result<Vec<UnifiedVehicle>> {
    let feed = FeedMessage::decode(bytes).context("Invalid GTFS-RT VehiclePositions protobuf")?;
    let feed_ts = feed.header.timestamp.unwrap_or(0);
    let mut results = Vec::with_capacity(feed.entity.len());

    for entity in feed.entity {
        let Some(vp) = entity.vehicle else {
            continue;
        };
        let Some(pos) = vp.position else {
            continue;
        };

        let raw_trip_id = vp.trip.as_ref().and_then(|t| t.trip_id.clone());
        let raw_route_id = vp.trip.as_ref().and_then(|t| t.route_id.clone());

        // Skip parked / out-of-service depot vehicles that have neither trip_id nor route_id
        if raw_trip_id.is_none() && raw_route_id.is_none() {
            continue;
        }

        let vehicle_id = vp
            .vehicle
            .as_ref()
            .and_then(|v| v.id.clone())
            .unwrap_or(entity.id);
        let raw_label = vp
            .vehicle
            .as_ref()
            .and_then(|v| v.label.clone())
            .unwrap_or_default();

        let prefixed_trip_id = raw_trip_id.as_ref().map(|t| format!("BKK:{}", t));
        let prefixed_route_id = raw_route_id.as_ref().map(|r| format!("BKK:{}", r));

        let delay_seconds = prefixed_trip_id
            .as_ref()
            .and_then(|tid| {
                trip_delays.get(tid).copied().or_else(|| {
                    tid.split_once('-')
                        .and_then(|(base, _)| trip_delays.get(base).copied())
                })
            })
            .unwrap_or(0);

        // Enrich line_name, headsign, and route_color from the bundled SQLite static DB if available
        let mut line_name = if !raw_label.is_empty() {
            raw_label.clone()
        } else {
            raw_route_id.clone().unwrap_or_else(|| "BKK".to_string())
        };
        let mut destination = String::new();
        let mut route_color = "009EE3".to_string();
        let mut route_type: Option<i32> = None;
        let mut resolved_trip_id = prefixed_trip_id.clone();

        if let Some(db) = repo {
            if let Some(ref tid) = prefixed_trip_id {
                if let Ok(Some(meta)) = db.lookup_trip_metadata(tid) {
                    if !meta.short_name.is_empty() {
                        line_name = meta.short_name;
                    }
                    destination = meta.headsign;
                    route_color = meta.route_color;
                    route_type = Some(meta.route_type);
                }
            }
            if route_type.is_none() {
                if let Some(ref rid) = prefixed_route_id {
                    if let Ok(Some(rmeta)) = db.lookup_route_metadata(rid) {
                        if !rmeta.short_name.is_empty() {
                            line_name = rmeta.short_name;
                        }
                        if destination.is_empty() {
                            destination = rmeta
                                .representative_headsign
                                .unwrap_or(rmeta.long_name);
                        }
                        if rmeta.representative_trip_id.is_some() {
                            resolved_trip_id = rmeta.representative_trip_id;
                        }
                        route_color = rmeta.route_color;
                        route_type = Some(rmeta.route_type);
                    }
                }
            }
        }

        // Detect MÁV-START / GYSEV national & suburban rail trains included in the GTFS-RT feed
        let r_str = raw_route_id.as_deref().unwrap_or("");
        let is_uic_train_id =
            vehicle_id.len() == 12 && vehicle_id.chars().all(|c| c.is_ascii_digit());
        let is_rail_route_code = matches!(
            r_str,
            "IC" | "EC" | "EN" | "IR" | "ER" | "RJ" | "RJX" | "S" | "GY" | "EX" | "SZ"
        ) || ((r_str.starts_with('S')
            || r_str.starts_with('G')
            || r_str.starts_with('Z'))
            && r_str.len() >= 2
            && r_str.len() <= 4
            && r_str[1..].chars().all(|c| c.is_ascii_digit()));

        let is_mav_train = route_type.is_none() && (is_uic_train_id || is_rail_route_code);

        let mut operator = Operator::BKK;
        let vehicle_type: String;
        let mut trip_short_name: Option<String> = None;

        if is_mav_train {
            operator = Operator::MAV;
            vehicle_type = "train".to_string();
            route_color = "0057B8".to_string();

            let train_num = raw_trip_id
                .as_deref()
                .and_then(|t| t.split('_').next())
                .unwrap_or("");

            let is_suburban = (r_str.starts_with('S')
                || r_str.starts_with('G')
                || r_str.starts_with('Z')
                || r_str.starts_with('X'))
                && r_str.len() >= 2
                && r_str.len() <= 5
                && r_str[1..].chars().all(|c| c.is_ascii_digit());

            if is_suburban {
                line_name = r_str.to_string();
                trip_short_name = if !train_num.is_empty() {
                    Some(format!("{} ({})", r_str, train_num))
                } else {
                    Some(r_str.to_string())
                };
            } else if r_str.eq_ignore_ascii_case("RJ")
                || r_str.eq_ignore_ascii_case("RJX")
                || raw_label.to_lowercase().contains("railjet")
            {
                line_name = "Railjet".to_string();
                trip_short_name = if !train_num.is_empty() {
                    Some(format!("Railjet {}", train_num))
                } else {
                    Some("Railjet".to_string())
                };
            } else if matches!(r_str, "IC" | "EC" | "EN" | "IR" | "EX") {
                let cat = match r_str {
                    "IC" => "IC",
                    "EC" => "EC",
                    "EN" => "EN",
                    "IR" => "IR",
                    _ => "Ex",
                };
                if !raw_label.is_empty() && !raw_label.eq_ignore_ascii_case(cat) {
                    let clean_label = raw_label.split('/').next().unwrap_or(&raw_label).trim();
                    line_name = format!("{} {}", clean_label, cat);
                } else if !train_num.is_empty() {
                    line_name = format!("{} {}", cat, train_num);
                } else {
                    line_name = cat.to_string();
                }
                trip_short_name = if !train_num.is_empty() {
                    Some(format!("{} ({})", line_name, train_num))
                } else {
                    Some(line_name.clone())
                };
            } else if !train_num.is_empty() {
                line_name = format!("Sz {}", train_num);
                trip_short_name = Some(format!("{} személyvonat", train_num));
            } else if !r_str.is_empty() {
                line_name = r_str.to_string();
                trip_short_name = Some(r_str.to_string());
            } else {
                line_name = "MÁV".to_string();
            }

            destination = if !raw_label.is_empty() && !train_num.is_empty() && !raw_label.contains(train_num) {
                format!("{} ({}. sz. vonat)", raw_label, train_num)
            } else if !raw_label.is_empty() {
                raw_label
            } else {
                "MÁV-START vasúti járat".to_string()
            };

            resolved_trip_id = raw_trip_id.as_ref().map(|t| format!("MAV:{}", t));
        } else {
            // If an unmatched BKK replacement bus (e.g. HP61) has raw_route_id and raw_label
            if route_type.is_none() && !r_str.is_empty() && !raw_label.is_empty() && raw_label != r_str {
                line_name = r_str.to_string();
                if destination.is_empty() {
                    destination = raw_label;
                }
            }

            let matched_type = match route_type {
                Some(0) => "tram",
                Some(1) => "metro",
                Some(2) => "train",
                Some(3) => "bus",
                Some(4) => "boat",
                Some(11) => "trolley",
                Some(109) => "suburban_rail", // HÉV
                _ => classify_bkk_vehicle_type(r_str, &line_name),
            };

            // If color wasn't resolved from DB, assign authentic BKK default mode colors
            if route_type.is_none() {
                route_color = match matched_type {
                    "tram" => "D97706".to_string(),
                    "metro" => "2563EB".to_string(),
                    "trolley" => "DC2626".to_string(),
                    "suburban_rail" => "16A34A".to_string(),
                    "boat" => "7C3AED".to_string(),
                    _ => "0284C7".to_string(),
                };
            }

            vehicle_type = matched_type.to_string();
        }

        let final_id = match operator {
            Operator::MAV => format!("MAV:{}", vehicle_id),
            Operator::BKK => format!("BKK:{}", vehicle_id),
        };
        let final_route_id = raw_route_id.map(|r| match operator {
            Operator::MAV => format!("MAV:{}", r),
            Operator::BKK => format!("BKK:{}", r),
        });

        results.push(UnifiedVehicle {
            id: final_id,
            operator,
            trip_id: resolved_trip_id,
            route_id: final_route_id,
            line_name,
            destination,
            lat: pos.latitude as f64,
            lon: pos.longitude as f64,
            bearing: pos.bearing.unwrap_or(0.0),
            speed_mps: pos.speed,
            delay_seconds,
            timestamp: vp.timestamp.unwrap_or(feed_ts),
            route_color,
            vehicle_type,
            trip_short_name,
            delay_cause: None,
        });
    }

    Ok(results)
}

/// Robust heuristic fallback classifier when static GTFS metadata is uninitialized or missing.
pub fn classify_bkk_vehicle_type(route_id: &str, line_name: &str) -> &'static str {
    let r = route_id.trim();
    let l = line_name.trim();
    let lower_l = l.to_lowercase();

    // 1. Check route_id if available (BKK standard 4-digit route encoding)
    if (r.starts_with('3') && r.len() == 4 && r.chars().all(|c| c.is_ascii_digit()))
        || r.starts_with("N3")
        || r.starts_with("3")
    {
        // 3000-3999 are Budapest trams
        if r.len() == 4 && r.chars().all(|c| c.is_ascii_digit()) {
            return "tram";
        }
    }
    if r.starts_with('4') && r.len() == 4 && r.chars().all(|c| c.is_ascii_digit()) {
        return "trolley";
    }
    if r.starts_with('5') && r.len() == 4 && r.chars().all(|c| c.is_ascii_digit()) {
        return "metro";
    }
    if r.starts_with('H') || r.starts_with("80") {
        return "suburban_rail";
    }
    if r.starts_with('D') || r == "8140" {
        return "boat";
    }

    // 2. Check line_name
    if lower_l.starts_with('m')
        && lower_l.len() <= 3
        && lower_l[1..].chars().all(|c| c.is_ascii_digit())
    {
        return "metro";
    }
    if lower_l.starts_with('h')
        && lower_l.len() <= 3
        && lower_l[1..].chars().all(|c| c.is_ascii_digit())
    {
        return "suburban_rail";
    }
    if lower_l.starts_with('d') && lower_l.len() <= 3 {
        return "boat";
    }

    // Numeric line names
    if let Ok(num) = l.parse::<i32>() {
        if (70..=83).contains(&num) {
            return "trolley";
        }
        if matches!(
            num,
            1 | 2 | 3 | 4 | 6 | 12 | 14 | 17 | 19 | 23 | 24 | 28 | 37 | 41 | 42 | 47 | 48 | 49 | 50 | 56 | 59 | 60 | 61 | 62 | 69
        ) {
            return "tram";
        }
    }

    // Tram lines with alphanumeric variants (e.g. 1A, 2B, 4-6, 28A, 37A, 56A, 59A, 59B, 62A)
    if matches!(
        l,
        "1A" | "2B" | "4-6" | "28A" | "37A" | "56A" | "59A" | "59B" | "62A"
    ) {
        return "tram";
    }

    // Trolley variants (e.g. 74A, 75A, 80A, 82A)
    if matches!(l, "74A" | "75A" | "80A" | "82A") {
        return "trolley";
    }

    "bus"
}

