use anyhow::Result;
use rusqlite::params;

use crate::gtfs_rt::models::{BoundingBox, Operator, StopNode, UnifiedVehicle};
use crate::static_db::repository::StaticTransitRepository;

impl StaticTransitRepository {
    /// Queries the SQLite R-Tree spatial index (`stops_rtree`) for stop groups / station hubs inside `bbox`,
    /// grouped by physical station hub and ordered from the viewport center outward.
    pub fn query_stop_groups_in_bbox(&self, bbox: BoundingBox, limit: usize) -> Result<Vec<StopNode>> {
        let conn = self.get_conn()?;
        let center_lat = (bbox.min_lat + bbox.max_lat) * 0.5;
        let center_lon = (bbox.min_lon + bbox.max_lon) * 0.5;

        let mut stmt = conn.prepare_cached(
            r#"
            SELECT
                COALESCE(s.hub_id, s.id) AS id,
                s.hub_id,
                COALESCE(h.name, s.name) AS name,
                AVG(s.lat) AS lat,
                AVG(s.lon) AS lon,
                s.operator_type,
                s.platform_code,
                CASE WHEN COUNT(s.id) > 1 OR COALESCE(h.has_bkk AND h.has_mav, 0) != 0 THEN 1 ELSE 0 END AS is_multimodal
            FROM stops_rtree rt
            JOIN stops s ON s.rowid = rt.id
            LEFT JOIN station_hubs h ON h.hub_id = s.hub_id
            WHERE rt.min_lat >= ?1 AND rt.max_lat <= ?2
              AND rt.min_lon >= ?3 AND rt.max_lon <= ?4
              AND EXISTS (SELECT 1 FROM stop_times st WHERE st.stop_id = s.id LIMIT 1)
            GROUP BY COALESCE(s.hub_id, s.id)
            ORDER BY ((AVG(s.lat) - ?6)*(AVG(s.lat) - ?6) + (AVG(s.lon) - ?7)*(AVG(s.lon) - ?7)) ASC
            LIMIT ?5
            "#,
        )?;

        let rows = stmt.query_map(
            params![
                bbox.min_lat,
                bbox.max_lat,
                bbox.min_lon,
                bbox.max_lon,
                limit as i64,
                center_lat,
                center_lon,
            ],
            |row| {
                let op_str: String = row.get(5)?;
                let is_mm: i64 = row.get(7)?;
                Ok(StopNode {
                    id: row.get(0)?,
                    hub_id: row.get(1)?,
                    name: row.get(2)?,
                    lat: row.get(3)?,
                    lon: row.get(4)?,
                    operator: Operator::from_prefix(&op_str),
                    platform_code: row.get(6)?,
                    is_multimodal_hub: is_mm != 0,
                    vehicle_type: Some("hub".to_string()),
                    served_routes: None,
                    direction: None,
                })
            },
        )?;

        let mut out = Vec::new();
        for r in rows {
            out.push(r?);
        }
        Ok(out)
    }

    /// Queries the SQLite R-Tree spatial index for individual platforms/posts inside `bbox`
    /// (separate perons/directions with served routes and headsigns).
    pub fn query_platforms_in_bbox(&self, bbox: BoundingBox, limit: usize) -> Result<Vec<StopNode>> {
        let conn = self.get_conn()?;
        let center_lat = (bbox.min_lat + bbox.max_lat) * 0.5;
        let center_lon = (bbox.min_lon + bbox.max_lon) * 0.5;

        let mut stmt = conn.prepare_cached(
            r#"
            SELECT
                s.id,
                s.hub_id,
                s.name,
                s.lat,
                s.lon,
                s.operator_type,
                s.platform_code,
                COALESCE(d.vehicle_type, 'bus') AS vehicle_type,
                d.served_routes,
                d.direction_headsigns
            FROM stops_rtree rt
            JOIN stops s ON s.rowid = rt.id
            LEFT JOIN stop_platform_details d ON d.stop_id = s.id
            WHERE rt.min_lat >= ?1 AND rt.max_lat <= ?2
              AND rt.min_lon >= ?3 AND rt.max_lon <= ?4
            ORDER BY ((s.lat - ?6)*(s.lat - ?6) + (s.lon - ?7)*(s.lon - ?7)) ASC
            LIMIT ?5
            "#,
        )?;

        let rows = stmt.query_map(
            params![
                bbox.min_lat,
                bbox.max_lat,
                bbox.min_lon,
                bbox.max_lon,
                limit as i64,
                center_lat,
                center_lon,
            ],
            |row| {
                let op_str: String = row.get(5)?;
                Ok(StopNode {
                    id: row.get(0)?,
                    hub_id: row.get(1)?,
                    name: row.get(2)?,
                    lat: row.get(3)?,
                    lon: row.get(4)?,
                    operator: Operator::from_prefix(&op_str),
                    platform_code: row.get(6)?,
                    is_multimodal_hub: false,
                    vehicle_type: row.get(7)?,
                    served_routes: row.get(8)?,
                    direction: row.get(9)?,
                })
            },
        )?;

        let mut out = Vec::new();
        for r in rows {
            out.push(r?);
        }
        Ok(out)
    }

    pub fn query_stops_in_bbox(&self, bbox: BoundingBox, limit: usize) -> Result<Vec<StopNode>> {
        self.query_stop_groups_in_bbox(bbox, limit)
    }
}

/// Filters a slice of `UnifiedVehicle` items to only those within the active viewport `BoundingBox`.
pub fn filter_vehicles_in_bbox(
    vehicles: &[UnifiedVehicle],
    bbox: BoundingBox,
) -> Vec<UnifiedVehicle> {
    vehicles
        .iter()
        .filter(|v| bbox.contains(v.lat, v.lon))
        .cloned()
        .collect()
}

/// Serializes a list of `UnifiedVehicle` structs directly into a MapLibre-ready GeoJSON FeatureCollection string.
/// Includes `delay_bucket` (`"on_time"`, `"minor_delay"`, `"major_delay"`) for GPU-driven circle/symbol styling.
pub fn vehicles_to_geojson(vehicles: &[UnifiedVehicle]) -> String {
    let features: Vec<serde_json::Value> = vehicles
        .iter()
        .map(|v| {
            let delay_bucket = if v.delay_seconds <= 60 {
                "on_time"
            } else if v.delay_seconds <= 300 {
                "minor_delay"
            } else {
                "major_delay"
            };
            let delay_color = match delay_bucket {
                "on_time" => "#22C55E",     // Green: On time
                "minor_delay" => "#EAB308", // Yellow: 1-5 min delay
                _ => "#EF4444",             // Red: > 5 min delay
            };

            serde_json::json!({
                "type": "Feature",
                "id": v.id,
                "geometry": {
                    "type": "Point",
                    "coordinates": [v.lon, v.lat]
                },
                "properties": {
                    "id": v.id,
                    "operator": v.operator.as_str(),
                    "trip_id": v.trip_id,
                    "route_id": v.route_id,
                    "line_name": v.line_name,
                    "destination": v.destination,
                    "bearing": v.bearing,
                    "delay_seconds": v.delay_seconds,
                    "delay_minutes": (v.delay_seconds as f32 / 60.0).round() as i32,
                    "delay_bucket": delay_bucket,
                    "delay_color": delay_color,
                    "route_color": format!("#{}", v.route_color.trim_start_matches('#')),
                    "timestamp": v.timestamp,
                    "vehicle_type": v.vehicle_type
                }
            })
        })
        .collect();

    serde_json::json!({
        "type": "FeatureCollection",
        "features": features
    })
    .to_string()
}
