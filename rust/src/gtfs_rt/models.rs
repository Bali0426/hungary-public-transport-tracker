use serde::{Deserialize, Serialize};

/// Supported Hungarian public transit operators.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Operator {
    BKK,
    MAV,
}

impl Operator {
    pub fn as_str(&self) -> &'static str {
        match self {
            Operator::BKK => "BKK",
            Operator::MAV => "MAV",
        }
    }

    pub fn from_prefix(s: &str) -> Self {
        if s.eq_ignore_ascii_case("MAV") {
            Operator::MAV
        } else {
            Operator::BKK
        }
    }
}

/// Unified real-time vehicle model decoded from BKK GTFS-RT or MÁV feeds.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnifiedVehicle {
    pub id: String,
    pub operator: Operator,
    pub trip_id: Option<String>,
    pub route_id: Option<String>,
    pub line_name: String,
    pub destination: String,
    pub lat: f64,
    pub lon: f64,
    pub bearing: f32,
    pub speed_mps: Option<f32>,
    pub delay_seconds: i32,
    pub timestamp: u64,
    pub route_color: String,
    pub vehicle_type: String, // "bus", "tram", "metro", "trolley", "train", "suburban_rail", "boat", "other"
    #[serde(default)]
    pub trip_short_name: Option<String>,
    #[serde(default)]
    pub delay_cause: Option<String>,
}

/// Geographic bounding box used to filter vehicles and stops to the active MapLibre viewport.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct BoundingBox {
    pub min_lat: f64,
    pub min_lon: f64,
    pub max_lat: f64,
    pub max_lon: f64,
}

impl BoundingBox {
    pub fn contains(&self, lat: f64, lon: f64) -> bool {
        lat >= self.min_lat && lat <= self.max_lat && lon >= self.min_lon && lon <= self.max_lon
    }
}

/// A physical stop or multimodal station hub returned to Flutter.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StopNode {
    pub id: String,
    pub hub_id: Option<String>,
    pub name: String,
    pub lat: f64,
    pub lon: f64,
    pub operator: Operator,
    pub platform_code: Option<String>,
    pub is_multimodal_hub: bool,
    #[serde(default)]
    pub vehicle_type: Option<String>,
    #[serde(default)]
    pub served_routes: Option<String>,
    #[serde(default)]
    pub direction: Option<String>,
}

/// A single row on the unified station departure board (combining static schedule + live delay).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnifiedDeparture {
    pub trip_id: String,
    pub stop_id: String,
    pub operator: Operator,
    pub line_name: String,
    pub headsign: String,
    pub route_color: String,
    pub route_text_color: String,
    pub scheduled_departure_seconds: i32,
    pub scheduled_time_formatted: String,
    pub delay_seconds: i32,
    pub estimated_departure_seconds: i32,
    pub estimated_time_formatted: String,
    pub is_realtime: bool,
    pub platform_code: Option<String>,
    #[serde(default)]
    pub is_arrival: bool,
    #[serde(default)]
    pub origin_station: Option<String>,
    #[serde(default)]
    pub scheduled_arrival_time_formatted: Option<String>,
    #[serde(default)]
    pub estimated_arrival_time_formatted: Option<String>,
}
