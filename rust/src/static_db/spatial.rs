use std::collections::HashMap;
use anyhow::Result;
use rusqlite::params;

use crate::gtfs_rt::models::{BoundingBox, Operator, StopNode, UnifiedVehicle};
use crate::static_db::repository::{clean_station_name, StaticTransitRepository};

impl StaticTransitRepository {
    /// Queries the SQLite R-Tree spatial index (`stops_rtree`) for stop groups / station hubs inside `bbox`,
    /// clustering physical station hubs (e.g. Széll Kálmán tér, Örs vezér tere, Nyugati pályaudvar,
    /// Kelenföld, Blaha Lujza tér) into unified single stop groups and ordered outward from viewport center.
    pub fn query_stop_groups_in_bbox(&self, bbox: BoundingBox, limit: usize) -> Result<Vec<StopNode>> {
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
                COALESCE(h.name, s.name) AS hub_name,
                COALESCE(h.has_bkk AND h.has_mav, 0) AS is_hub_multimodal
            FROM stops_rtree rt
            JOIN stops s ON s.rowid = rt.id
            LEFT JOIN station_hubs h ON h.hub_id = s.hub_id
            WHERE rt.min_lat >= ?1 AND rt.max_lat <= ?2
              AND rt.min_lon >= ?3 AND rt.max_lon <= ?4
              AND (s.operator_type = 'MAV' OR EXISTS (SELECT 1 FROM stop_times st WHERE st.stop_id = s.id LIMIT 1))
            "#,
        )?;

        struct StopRecord {
            id: String,
            hub_id: Option<String>,
            name: String,
            lat: f64,
            lon: f64,
            op: String,
            platform_code: Option<String>,
            is_hub_multimodal: bool,
        }

        let rows = stmt.query_map(
            params![bbox.min_lat, bbox.max_lat, bbox.min_lon, bbox.max_lon],
            |row| {
                Ok(StopRecord {
                    id: row.get(0)?,
                    hub_id: row.get(1)?,
                    name: row.get(2)?,
                    lat: row.get(3)?,
                    lon: row.get(4)?,
                    op: row.get(5)?,
                    platform_code: row.get(6)?,
                    is_hub_multimodal: row.get::<_, i64>(8)? != 0,
                })
            },
        )?;

        struct GroupAccum {
            canonical_id: String,
            hub_id: Option<String>,
            name: String,
            sum_lat: f64,
            sum_lon: f64,
            count: usize,
            operator: Operator,
            platform_code: Option<String>,
            is_multimodal: bool,
        }

        let mut groups: HashMap<String, GroupAccum> = HashMap::new();

        for r in rows {
            let record = r?;
            let (group_key, canon_hub_id, disp_name) = if let Some(ref h_id) = record.hub_id {
                let canon = self.resolve_canonical_hub_id(h_id);
                let name = self
                    .get_hub_display_name(&canon)
                    .unwrap_or_else(|| clean_station_name(&record.name));
                (canon.clone(), Some(canon), name)
            } else {
                let c_name = clean_station_name(&record.name);
                let grid_lat = (record.lat * 350.0).round() as i32;
                let grid_lon = (record.lon * 350.0).round() as i32;
                let key = format!("NAMED_{}_{}_{}", c_name, grid_lat, grid_lon);
                (key, None, c_name)
            };

            let entry = groups.entry(group_key).or_insert_with(|| GroupAccum {
                canonical_id: canon_hub_id.clone().unwrap_or_else(|| record.id.clone()),
                hub_id: canon_hub_id,
                name: disp_name,
                sum_lat: 0.0,
                sum_lon: 0.0,
                count: 0,
                operator: Operator::from_prefix(&record.op),
                platform_code: record.platform_code.clone(),
                is_multimodal: record.is_hub_multimodal,
            });

            entry.sum_lat += record.lat;
            entry.sum_lon += record.lon;
            entry.count += 1;
            if record.is_hub_multimodal {
                entry.is_multimodal = true;
            }
        }

        let mut out: Vec<StopNode> = groups
            .into_values()
            .map(|g| {
                let lat = g.sum_lat / (g.count as f64);
                let lon = g.sum_lon / (g.count as f64);
                let is_multimodal = g.is_multimodal || g.count > 1;
                StopNode {
                    id: g.canonical_id,
                    hub_id: g.hub_id,
                    name: g.name,
                    lat,
                    lon,
                    operator: g.operator,
                    platform_code: g.platform_code,
                    is_multimodal_hub: is_multimodal,
                    vehicle_type: Some("hub".to_string()),
                    served_routes: None,
                    direction: None,
                }
            })
            .collect();

        out.sort_by(|a, b| {
            let da = (a.lat - center_lat).powi(2) + (a.lon - center_lon).powi(2);
            let db = (b.lat - center_lat).powi(2) + (b.lon - center_lon).powi(2);
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        });

        if out.len() > limit {
            out.truncate(limit);
        }
        Ok(out)
    }

    /// Queries the SQLite R-Tree spatial index for individual platforms/posts inside `bbox`
    /// (separate perons/directions with served routes and headsigns), with hub_id mapped to canonical hubs.
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
                let raw_hub: Option<String> = row.get(1)?;
                let canon_hub = raw_hub.as_deref().map(|h| self.resolve_canonical_hub_id(h));
                Ok(StopNode {
                    id: row.get(0)?,
                    hub_id: canon_hub,
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
                    "trip_short_name": v.trip_short_name,
                    "delay_cause": v.delay_cause,
                    "speed_mps": v.speed_mps,
                    "speed_kmh": v.speed_mps.map(|s| (s * 3.6).round() as i32),
                    "destination": v.destination,
                    "bearing": v.bearing,
                    "delay_seconds": v.delay_seconds,
                    "delay_minutes": (v.delay_seconds as f32 / 60.0).round() as i32,
                    "delay_bucket": delay_bucket,
                    "delay_color": delay_color,
                    "route_color": format!("#{}", v.route_color.trim_start_matches('#')),
                    "timestamp": v.timestamp,
                    "vehicle_type": v.vehicle_type,
                    "lat": v.lat,
                    "lon": v.lon
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
