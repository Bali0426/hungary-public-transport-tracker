use std::collections::HashMap;
use std::path::Path;

use anyhow::{Context, Result};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::{params, OpenFlags, OptionalExtension};

use crate::gtfs_rt::models::{Operator, StopNode, UnifiedDeparture};

#[derive(Debug, Clone)]
pub struct RouteMetadata {
    pub short_name: String,
    pub long_name: String,
    pub route_color: String,
    pub route_text_color: String,
    pub route_type: i32,
    pub representative_trip_id: Option<String>,
    pub representative_headsign: Option<String>,
}

#[derive(Debug, Clone)]
pub struct TripMetadata {
    pub route_id: String,
    pub short_name: String,
    pub headsign: String,
    pub route_color: String,
    pub route_type: i32,
}

/// Thread-safe SQLite connection pool for querying `transit_static.db`.
#[derive(Clone)]
pub struct StaticTransitRepository {
    pool: Pool<SqliteConnectionManager>,
}

impl StaticTransitRepository {
    /// Opens an existing `transit_static.db` SQLite database in read-only / shared cache mode.
    pub fn open<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let flags = OpenFlags::SQLITE_OPEN_READ_ONLY
            | OpenFlags::SQLITE_OPEN_NO_MUTEX
            | OpenFlags::SQLITE_OPEN_URI;
        let manager = SqliteConnectionManager::file(db_path.as_ref()).with_flags(flags);
        let pool = Pool::builder()
            .max_size(8)
            .build(manager)
            .context("Failed to initialize r2d2 SQLite connection pool")?;
        Ok(Self { pool })
    }

    pub fn get_conn(&self) -> Result<r2d2::PooledConnection<SqliteConnectionManager>> {
        self.pool
            .get()
            .context("Failed to checkout connection from SQLite pool")
    }

    /// Looks up route display name, hex color, and a representative trip/headsign for a given `route_id`.
    pub fn lookup_route_metadata(&self, route_id: &str) -> Result<Option<RouteMetadata>> {
        let conn = self.get_conn()?;
        let mut stmt = conn.prepare_cached(
            r#"
            SELECT
                r.short_name,
                r.long_name,
                r.route_color,
                r.route_text_color,
                r.route_type,
                (SELECT t.id FROM trips t WHERE t.route_id = r.id LIMIT 1) AS rep_trip_id,
                (SELECT t.trip_headsign FROM trips t WHERE t.route_id = r.id AND t.trip_headsign != '' LIMIT 1) AS rep_headsign
            FROM routes r
            WHERE r.id = ?1
            "#,
        )?;
        let res = stmt
            .query_row(params![route_id], |row| {
                Ok(RouteMetadata {
                    short_name: row.get(0)?,
                    long_name: row.get(1)?,
                    route_color: row.get(2)?,
                    route_text_color: row.get(3)?,
                    route_type: row.get(4)?,
                    representative_trip_id: row.get(5)?,
                    representative_headsign: row.get(6)?,
                })
            })
            .optional()?;
        Ok(res)
    }

    /// Looks up trip headsign, route short_name, and color for a given `trip_id`.
    /// Automatically strips operative date suffixes (e.g., `BKK:D113623178-20261019-02` -> `BKK:D113623178`).
    pub fn lookup_trip_metadata(&self, trip_id: &str) -> Result<Option<TripMetadata>> {
        let conn = self.get_conn()?;
        let mut stmt = conn.prepare_cached(
            r#"
            SELECT t.route_id, r.short_name, t.trip_headsign, r.route_color, r.route_type
            FROM trips t
            JOIN routes r ON r.id = t.route_id
            WHERE t.id = ?1
            "#,
        )?;
        let res = stmt
            .query_row(params![trip_id], |row| {
                Ok(TripMetadata {
                    route_id: row.get(0)?,
                    short_name: row.get(1)?,
                    headsign: row.get(2)?,
                    route_color: row.get(3)?,
                    route_type: row.get(4)?,
                })
            })
            .optional()?;
        if res.is_some() {
            return Ok(res);
        }
        if let Some((base_id, _)) = trip_id.split_once('-') {
            let res2 = stmt
                .query_row(params![base_id], |row| {
                    Ok(TripMetadata {
                        route_id: row.get(0)?,
                        short_name: row.get(1)?,
                        headsign: row.get(2)?,
                        route_color: row.get(3)?,
                        route_type: row.get(4)?,
                    })
                })
                .optional()?;
            return Ok(res2);
        }
        Ok(None)
    }

    /// Fuzzy/prefix stop and station hub search across both BKK and MÁV.
    pub fn search_stops(&self, query: &str, limit: usize) -> Result<Vec<StopNode>> {
        let trimmed = query.trim();
        if trimmed.is_empty() {
            return Ok(Vec::new());
        }
        let pattern = format!("%{}%", trimmed);
        let prefix_pattern = format!("{}%", trimmed);
        let conn = self.get_conn()?;

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
                COALESCE(h.has_bkk AND h.has_mav, 0) AS is_multimodal
            FROM stops s
            LEFT JOIN station_hubs h ON h.hub_id = s.hub_id
            WHERE s.name LIKE ?1 COLLATE NOCASE
               OR h.normalized_name LIKE ?1 COLLATE NOCASE
            ORDER BY
                CASE WHEN s.name LIKE ?2 COLLATE NOCASE THEN 0 ELSE 1 END,
                is_multimodal DESC,
                length(s.name) ASC
            LIMIT ?3
            "#,
        )?;

        let rows = stmt.query_map(params![pattern, prefix_pattern, limit as i64], |row| {
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
                vehicle_type: None,
                served_routes: None,
                direction: None,
            })
        })?;

        let mut results = Vec::new();
        for r in rows {
            results.push(r?);
        }
        Ok(results)
    }

    /// Queries the unified departure board for either a specific `stop_id` or an entire multimodal `hub_id`
    /// (combining BKK metros/trams/buses and MÁV trains at the same physical station hub).
    pub fn get_unified_departures(
        &self,
        stop_or_hub_id: &str,
        service_date_yyyymmdd: &str,
        from_seconds_since_midnight: i32,
        horizon_seconds: i32,
        live_trip_delays: &HashMap<String, i32>,
        limit: usize,
    ) -> Result<Vec<UnifiedDeparture>> {
        let conn = self.get_conn()?;
        let max_seconds = from_seconds_since_midnight + horizon_seconds;

        // Resolve hub_id if a stop_id was passed so the user sees all multimodal transfers at that hub
        let resolved_hub_id: Option<String> = if stop_or_hub_id.starts_with("HUB:") {
            Some(stop_or_hub_id.to_string())
        } else {
            conn.query_row(
                "SELECT hub_id FROM stops WHERE id = ?1",
                params![stop_or_hub_id],
                |r| r.get::<_, Option<String>>(0),
            )
            .optional()?
            .flatten()
        };

        let sql = if resolved_hub_id.is_some() {
            r#"
            SELECT
                st.trip_id,
                st.stop_id,
                s.operator_type,
                r.short_name,
                COALESCE(NULLIF(t.trip_headsign, ''), r.long_name) AS headsign,
                r.route_color,
                r.route_text_color,
                st.departure_seconds,
                st.departure_time,
                s.platform_code
            FROM stops s
            JOIN stop_times st ON st.stop_id = s.id
            JOIN trips t ON t.id = st.trip_id
            JOIN routes r ON r.id = t.route_id
            WHERE s.hub_id = ?1
              AND st.departure_seconds BETWEEN ?2 AND ?3
              AND (
                  NOT EXISTS (SELECT 1 FROM calendar_active_dates LIMIT 1)
                  OR EXISTS (
                      SELECT 1 FROM calendar_active_dates cad
                      WHERE cad.service_id = t.service_id AND cad.service_date = ?4
                  )
              )
            ORDER BY st.departure_seconds ASC
            LIMIT ?5
            "#
        } else {
            r#"
            SELECT
                st.trip_id,
                st.stop_id,
                s.operator_type,
                r.short_name,
                COALESCE(NULLIF(t.trip_headsign, ''), r.long_name) AS headsign,
                r.route_color,
                r.route_text_color,
                st.departure_seconds,
                st.departure_time,
                s.platform_code
            FROM stops s
            JOIN stop_times st ON st.stop_id = s.id
            JOIN trips t ON t.id = st.trip_id
            JOIN routes r ON r.id = t.route_id
            WHERE s.id = ?1
              AND st.departure_seconds BETWEEN ?2 AND ?3
              AND (
                  NOT EXISTS (SELECT 1 FROM calendar_active_dates LIMIT 1)
                  OR EXISTS (
                      SELECT 1 FROM calendar_active_dates cad
                      WHERE cad.service_id = t.service_id AND cad.service_date = ?4
                  )
              )
            ORDER BY st.departure_seconds ASC
            LIMIT ?5
            "#
        };

        let key_param = resolved_hub_id.as_deref().unwrap_or(stop_or_hub_id);
        let mut stmt = conn.prepare_cached(sql)?;
        let rows = stmt.query_map(
            params![
                key_param,
                from_seconds_since_midnight,
                max_seconds,
                service_date_yyyymmdd,
                limit as i64
            ],
            |row| {
                let trip_id: String = row.get(0)?;
                let stop_id: String = row.get(1)?;
                let op_str: String = row.get(2)?;
                let line_name: String = row.get(3)?;
                let headsign: String = row.get(4)?;
                let route_color: String = row.get(5)?;
                let route_text_color: String = row.get(6)?;
                let sched_sec: i32 = row.get(7)?;
                let sched_fmt: String = row.get(8)?;
                let platform_code: Option<String> = row.get(9)?;

                let delay_opt = live_trip_delays.get(&trip_id).copied();
                let delay_seconds = delay_opt.unwrap_or(0);
                let est_sec = (sched_sec + delay_seconds).max(0);

                Ok(UnifiedDeparture {
                    trip_id,
                    stop_id,
                    operator: Operator::from_prefix(&op_str),
                    line_name,
                    headsign,
                    route_color,
                    route_text_color,
                    scheduled_departure_seconds: sched_sec,
                    scheduled_time_formatted: format_hhmm(sched_sec, &sched_fmt),
                    delay_seconds,
                    estimated_departure_seconds: est_sec,
                    estimated_time_formatted: format_hhmm(est_sec, &sched_fmt),
                    is_realtime: delay_opt.is_some(),
                    platform_code,
                })
            },
        )?;

        let mut departures = Vec::new();
        for r in rows {
            departures.push(r?);
        }
        departures.sort_by_key(|d| d.estimated_departure_seconds);
        Ok(departures)
    }

    /// Queries the scheduled stop sequence and departure times for a given trip_id.
    pub fn get_trip_schedule(&self, trip_id: &str) -> Result<Vec<TripStopSchedule>> {
        let conn = self.get_conn()?;
        let mut stmt = conn.prepare_cached(r#"
            SELECT
                st.stop_sequence,
                st.stop_id,
                s.name,
                st.departure_time,
                s.operator_type,
                s.platform_code,
                st.arrival_seconds,
                s.lat,
                s.lon
            FROM stop_times st
            JOIN stops s ON s.id = st.stop_id
            WHERE st.trip_id = ?1
            ORDER BY st.stop_sequence ASC
        "#)?;

        let rows = stmt.query_map(params![trip_id], |row| {
            let dep_time: String = row.get(3)?;
            let arr_sec: Option<i32> = row.get(6).ok();
            let arr_time = arr_sec.map(|s| format_hhmm(s, &dep_time));
            Ok(TripStopSchedule {
                stop_sequence: row.get(0)?,
                stop_id: row.get(1)?,
                stop_name: row.get(2)?,
                departure_time: dep_time,
                operator: row.get(4)?,
                platform_code: row.get(5)?,
                arrival_time: arr_time,
                lat: row.get(7).ok(),
                lon: row.get(8).ok(),
                predicted_departure_time: None,
                predicted_arrival_time: None,
                delay_seconds: 0,
            })
        })?;

        let mut list = Vec::new();
        for r in rows {
            list.push(r?);
        }

        // If not found and trip_id has an operative suffix (e.g. -20261019-01), strip it
        if list.is_empty() {
            if let Some((base_id, _)) = trip_id.split_once('-') {
                let rows2 = stmt.query_map(params![base_id], |row| {
                    let dep_time: String = row.get(3)?;
                    let arr_sec: Option<i32> = row.get(6).ok();
                    let arr_time = arr_sec.map(|s| format_hhmm(s, &dep_time));
                    Ok(TripStopSchedule {
                        stop_sequence: row.get(0)?,
                        stop_id: row.get(1)?,
                        stop_name: row.get(2)?,
                        departure_time: dep_time,
                        operator: row.get(4)?,
                        platform_code: row.get(5)?,
                        arrival_time: arr_time,
                        lat: row.get(7).ok(),
                        lon: row.get(8).ok(),
                        predicted_departure_time: None,
                        predicted_arrival_time: None,
                        delay_seconds: 0,
                    })
                })?;
                for r in rows2 {
                    list.push(r?);
                }
            }
        }

        // If not found and trip_id lacks BKK: or MAV: prefix, retry with prefix
        if list.is_empty() && !trip_id.starts_with("BKK:") && !trip_id.starts_with("MAV:") {
            let bkk_id = format!("BKK:{}", trip_id);
            return self.get_trip_schedule(&bkk_id);
        }

        Ok(list)
    }
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct TripStopSchedule {
    pub stop_sequence: i32,
    pub stop_id: String,
    pub stop_name: String,
    pub departure_time: String,
    pub operator: String,
    pub platform_code: Option<String>,
    pub arrival_time: Option<String>,
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    #[serde(default)]
    pub predicted_departure_time: Option<String>,
    #[serde(default)]
    pub predicted_arrival_time: Option<String>,
    #[serde(default)]
    pub delay_seconds: i32,
}

pub fn format_hhmm(seconds: i32, fallback: &str) -> String {
    if seconds < 0 {
        return fallback.to_string();
    }
    let total_minutes = (seconds / 60) % (24 * 60);
    let h = total_minutes / 60;
    let m = total_minutes % 60;
    format!("{:02}:{:02}", h, m)
}
