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
                                    tu.stop_time_update.first().and_then(|stu| {
                                        stu.departure
                                            .as_ref()
                                            .and_then(|d| d.delay)
                                            .or_else(|| stu.arrival.as_ref().and_then(|a| a.delay))
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

        let prefixed_trip_id = raw_trip_id.as_ref().map(|t| format!("BKK:{}", t));
        let prefixed_route_id = raw_route_id.as_ref().map(|r| format!("BKK:{}", r));

        let delay_seconds = prefixed_trip_id
            .as_ref()
            .and_then(|tid| trip_delays.get(tid).copied())
            .unwrap_or(0);

        // Enrich line_name, headsign, and route_color from the bundled SQLite static DB if available
        let mut line_name = vp
            .vehicle
            .as_ref()
            .and_then(|v| v.label.clone())
            .or_else(|| raw_route_id.clone())
            .unwrap_or_else(|| "BKK".to_string());
        let mut destination = String::new();
        let mut route_color = "009EE3".to_string();
        let mut route_type: Option<i32> = None;

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
                        route_color = rmeta.route_color;
                        route_type = Some(rmeta.route_type);
                    }
                }
            }
        }

        // Map GTFS route_type to clean category names
        let vehicle_type = match route_type {
            Some(0) => "tram",
            Some(1) => "metro",
            Some(2) => "train",
            Some(3) => "bus",
            Some(4) => "boat",
            Some(11) => "trolley",
            Some(109) => "suburban_rail", // HÉV
            _ => {
                let lower = line_name.to_lowercase();
                if lower.starts_with('m') && lower.len() <= 3 {
                    "metro"
                } else if lower.starts_with('h') && lower.len() <= 3 {
                    "suburban_rail"
                } else {
                    "bus"
                }
            }
        }.to_string();

        let vehicle_id = vp
            .vehicle
            .as_ref()
            .and_then(|v| v.id.clone())
            .unwrap_or(entity.id);

        results.push(UnifiedVehicle {
            id: format!("BKK:{}", vehicle_id),
            operator: Operator::BKK,
            trip_id: prefixed_trip_id,
            route_id: prefixed_route_id,
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
        });
    }

    Ok(results)
}
