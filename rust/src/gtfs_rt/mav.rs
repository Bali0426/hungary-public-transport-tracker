use std::collections::HashMap;
use anyhow::{Context, Result};
use prost::Message;
use reqwest::Client;
use serde::{Deserialize, Serialize};

use crate::gtfs_rt::models::{BoundingBox, Operator, UnifiedVehicle};
use crate::gtfs_rt::proto::FeedMessage;

pub const EMMA_GRAPHQL_URL: &str =
    "https://emma.mav.hu/otp2-backend/otp/routers/default/index/graphql";

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
}

#[derive(Debug, Deserialize)]
struct EmmaStoptime {
    #[serde(rename = "arrivalDelay")]
    arrival_delay: Option<i32>,
}

/// Fetches live MÁV vehicles via either an optional NAP GTFS-RT Protobuf URL
/// or the official MÁV EMMA OTP2 GraphQL endpoint (`https://emma.mav.hu/...`).
pub async fn fetch_mav_live_vehicles(
    client: &Client,
    gtfs_rt_url: Option<&str>,
    bbox: Option<BoundingBox>,
) -> Result<(Vec<UnifiedVehicle>, HashMap<String, i32>)> {
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
) -> Result<(Vec<UnifiedVehicle>, HashMap<String, i32>)> {
    let resp = client
        .get(pb_url)
        .send()
        .await
        .context("Failed to request MÁV GTFS-RT protobuf feed")?;
    if !resp.status().is_success() {
        anyhow::bail!("MÁV GTFS-RT endpoint returned HTTP {}", resp.status());
    }
    let bytes = resp.bytes().await?;
    let feed = FeedMessage::decode(bytes.as_ref()).context("Failed to decode MÁV GTFS-RT protobuf")?;
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
                route_id: vp.trip.as_ref().and_then(|t| t.route_id.as_ref().map(|r| format!("MAV:{}", r))),
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
            });
        }
    }

    Ok((vehicles, delays))
}

/// Queries the live MÁV EMMA OTP2 GraphQL endpoint for active rail, suburban rail, and tram-train vehicles.
pub async fn fetch_mav_emma_graphql(
    client: &Client,
    bbox: BoundingBox,
) -> Result<(Vec<UnifiedVehicle>, HashMap<String, i32>)> {
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
              arrivalStoptime {{
                arrivalDelay
              }}
            }}
          }}
        }}"#,
        bbox.min_lat, bbox.min_lon, bbox.max_lat, bbox.max_lon
    );

    let resp = client
        .post(EMMA_GRAPHQL_URL)
        .header("Content-Type", "application/json")
        .header("Origin", "https://emma.mav.hu")
        .header("Referer", "https://emma.mav.hu/")
        .json(&GraphQlRequest { query })
        .send()
        .await
        .context("Failed to query MÁV EMMA GraphQL endpoint")?;

    if !resp.status().is_success() {
        anyhow::bail!("MÁV EMMA GraphQL returned HTTP {}", resp.status());
    }

    let body: GraphQlResponse = resp
        .json()
        .await
        .context("Failed to deserialize MÁV EMMA GraphQL response")?;

    let mut vehicles = Vec::new();
    let mut delays = HashMap::new();

    if let Some(items) = body.data.and_then(|d| d.vehicle_positions) {
        for item in items {
            let (Some(lat), Some(lon)) = (item.lat, item.lon) else {
                continue;
            };
            let vid = item.vehicle_id.unwrap_or_else(|| format!("{:.4}_{:.4}", lat, lon));
            let delay = item
                .trip
                .as_ref()
                .and_then(|t| t.arrival_stoptime.as_ref())
                .and_then(|s| s.arrival_delay)
                .unwrap_or(0);

            let trip_id = item
                .trip
                .as_ref()
                .and_then(|t| t.gtfs_id.as_ref())
                .map(|id| format!("MAV:{}", id));

            if let Some(ref tid) = trip_id {
                delays.insert(tid.clone(), delay);
            }

            let line_name = item
                .trip
                .as_ref()
                .and_then(|t| {
                    t.trip_short_name
                        .clone()
                        .or_else(|| t.domestic_train_number.clone())
                })
                .or(item.label)
                .unwrap_or_else(|| "MÁV".to_string());

            let destination = item
                .trip
                .as_ref()
                .and_then(|t| t.trip_headsign.clone())
                .unwrap_or_default();

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
            });
        }
    }

    Ok((vehicles, delays))
}
