use std::collections::{HashMap, VecDeque};
use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result};
use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::{params, OpenFlags, OptionalExtension};

use crate::gtfs_rt::models::{Operator, StopNode, UnifiedDeparture};

/// Strips transportation suffixes, platform brackets, and parentheticals to produce a clean base station name
/// e.g. "Széll Kálmán tér M (Csaba utca)" -> "Széll Kálmán tér", "Nyugati pályaudvar [M]" -> "Nyugati pályaudvar".
pub fn clean_station_name(name: &str) -> String {
    let mut s = name.trim();
    if s.ends_with(')') {
        if let Some(idx) = s.rfind('(') {
            s = s[..idx].trim();
        }
    }
    if s.ends_with(']') {
        if let Some(idx) = s.rfind('[') {
            s = s[..idx].trim();
        }
    }
    let mut res = s.to_string();
    let suffixes = [" M+H", " m+h", " M", " m", " H", " h"];
    for suf in suffixes {
        if res.ends_with(suf) {
            res.truncate(res.len() - suf.len());
            res = res.trim().to_string();
            break;
        }
    }
    if res.is_empty() {
        name.trim().to_string()
    } else {
        res
    }
}

/// Normalizes a station name to its core comparison token (e.g. "Budapest-Déli" -> "déli",
/// "Déli pályaudvar M" -> "déli", "Kőbánya alsó vasútállomás" -> "kőbánya alsó").
pub fn normalize_station_core_name(name: &str) -> String {
    let base = clean_station_name(name).to_lowercase();
    let base = base.split('/').next().unwrap_or(&base).trim();
    let mut s = base
        .trim_start_matches("budapest-")
        .trim_start_matches("budapest ")
        .trim()
        .to_string();
    for suffix in &[
        " vasútállomás",
        " pályaudvar",
        " pu.",
        " vá.",
        " pu",
        " vá",
        " m+h",
        " m",
        " h",
    ] {
        if s.ends_with(suffix) {
            s.truncate(s.len() - suffix.len());
            s = s.trim().to_string();
        }
    }
    s
}

/// Normalizes a raw MÁV stop ID (e.g. "MAV:1:005510447_4a", "MAV:1:v.005501024_0") to its parent OTP2 gtfsId ("1:005510447_0").
pub fn normalize_mav_otp2_id(raw_id: &str) -> String {
    let mut s = raw_id.trim();
    for prefix in &["STOP:", "HUB:", "MAV_", "MAV:"] {
        if let Some(stripped) = s.strip_prefix(prefix) {
            s = stripped;
        }
    }
    let owned = if let Some(rest) = s.strip_prefix("1:v.") {
        format!("1:{}", rest)
    } else {
        s.to_string()
    };
    if owned.starts_with("1:") {
        if let Some(idx) = owned.rfind('_') {
            return format!("{}_0", &owned[..idx]);
        }
    }
    owned
}

/// Clusters Budapest and national station hubs that share the same base station name
/// and are within 400 meters of each other into a single canonical station hub.
fn build_canonical_hub_mappings(
    conn: &rusqlite::Connection,
) -> (
    HashMap<String, String>,
    HashMap<String, Vec<String>>,
    HashMap<String, String>,
) {
    let mut canonical_map = HashMap::new();
    let mut members_map = HashMap::new();
    let mut display_map = HashMap::new();

    let mut stmt = match conn.prepare("SELECT hub_id, name, lat, lon FROM station_hubs") {
        Ok(s) => s,
        Err(_) => return (canonical_map, members_map, display_map),
    };

    struct HubRaw {
        hub_id: String,
        name: String,
        lat: f64,
        lon: f64,
    }

    let rows = match stmt.query_map([], |row| {
        Ok(HubRaw {
            hub_id: row.get(0)?,
            name: row.get(1)?,
            lat: row.get(2)?,
            lon: row.get(3)?,
        })
    }) {
        Ok(r) => r,
        Err(_) => return (canonical_map, members_map, display_map),
    };

    let mut by_name: HashMap<String, Vec<HubRaw>> = HashMap::new();
    for r in rows.flatten() {
        let key = clean_station_name(&r.name).to_lowercase();
        by_name.entry(key).or_default().push(r);
    }

    for (_name_key, hubs) in by_name {
        if hubs.len() == 1 {
            let h = &hubs[0];
            let clean = clean_station_name(&h.name);
            canonical_map.insert(h.hub_id.clone(), h.hub_id.clone());
            members_map.insert(h.hub_id.clone(), vec![h.hub_id.clone()]);
            display_map.insert(h.hub_id.clone(), clean);
            continue;
        }

        let n = hubs.len();
        let mut adj = vec![Vec::new(); n];
        for i in 0..n {
            for j in (i + 1)..n {
                let dlat = (hubs[i].lat - hubs[j].lat) * 111_000.0;
                let dlon = (hubs[i].lon - hubs[j].lon) * 75_000.0;
                let dist = (dlat * dlat + dlon * dlon).sqrt();
                if dist <= 400.0 {
                    adj[i].push(j);
                    adj[j].push(i);
                }
            }
        }

        let mut visited = vec![false; n];
        for i in 0..n {
            if !visited[i] {
                let mut comp_indices = Vec::new();
                let mut queue = VecDeque::new();
                visited[i] = true;
                queue.push_back(i);
                while let Some(curr) = queue.pop_front() {
                    comp_indices.push(curr);
                    for &neighbor in &adj[curr] {
                        if !visited[neighbor] {
                            visited[neighbor] = true;
                            queue.push_back(neighbor);
                        }
                    }
                }

                comp_indices.sort_by(|&a, &b| hubs[a].hub_id.cmp(&hubs[b].hub_id));
                let canon_id = hubs[comp_indices[0]].hub_id.clone();
                let display_name = clean_station_name(&hubs[comp_indices[0]].name);
                let member_ids: Vec<String> = comp_indices
                    .iter()
                    .map(|&idx| hubs[idx].hub_id.clone())
                    .collect();

                for idx in comp_indices {
                    canonical_map.insert(hubs[idx].hub_id.clone(), canon_id.clone());
                }
                members_map.insert(canon_id.clone(), member_ids);
                display_map.insert(canon_id, display_name);
            }
        }
    }

    (canonical_map, members_map, display_map)
}

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
    pub canonical_hub_map: Arc<HashMap<String, String>>,
    pub hub_members_map: Arc<HashMap<String, Vec<String>>>,
    pub hub_display_names: Arc<HashMap<String, String>>,
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

        let conn = pool.get().context("Failed to checkout connection from SQLite pool")?;
        let (canonical_map, members_map, display_map) = build_canonical_hub_mappings(&conn);

        Ok(Self {
            pool,
            canonical_hub_map: Arc::new(canonical_map),
            hub_members_map: Arc::new(members_map),
            hub_display_names: Arc::new(display_map),
        })
    }

    pub fn resolve_canonical_hub_id(&self, hub_id: &str) -> String {
        self.canonical_hub_map
            .get(hub_id)
            .cloned()
            .unwrap_or_else(|| hub_id.to_string())
    }

    pub fn get_hub_members(&self, canonical_hub_id: &str) -> Vec<String> {
        self.hub_members_map
            .get(canonical_hub_id)
            .cloned()
            .unwrap_or_else(|| vec![canonical_hub_id.to_string()])
    }

    pub fn get_hub_display_name(&self, canonical_hub_id: &str) -> Option<String> {
        self.hub_display_names.get(canonical_hub_id).cloned()
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

    /// Fuzzy/prefix stop and station hub search across both BKK and MÁV,
    /// grouped by stop hub / name so multiple platforms of the same interchange don't duplicate.
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
                COALESCE(s.hub_id, MIN(s.id)) AS id,
                s.hub_id,
                COALESCE(h.name, s.name) AS name,
                AVG(s.lat) AS lat,
                AVG(s.lon) AS lon,
                CASE
                    WHEN MAX(h.has_bkk = 1 AND h.has_mav = 1) = 1 THEN 'BKK'
                    WHEN MAX(s.operator_type = 'MAV') = 1 AND MAX(s.operator_type = 'BKK') = 1 THEN 'BKK'
                    WHEN MAX(s.operator_type = 'MAV') = 1 THEN 'MAV'
                    ELSE 'BKK'
                END AS operator_type,
                MIN(s.platform_code) AS platform_code,
                CASE
                    WHEN MAX(h.has_bkk = 1 AND h.has_mav = 1) = 1 THEN 1
                    WHEN MAX(s.operator_type = 'MAV') = 1 AND MAX(s.operator_type = 'BKK') = 1 THEN 1
                    WHEN s.name LIKE '%pályaudvar%' OR s.name LIKE '%vasútállomás%' THEN 1
                    WHEN s.name LIKE '%Keleti%' OR s.name LIKE '%Nyugati%' OR s.name LIKE '%Déli%'
                         OR s.name LIKE '%Kelenföld%' OR s.name LIKE '%Kőbánya-Kispest%'
                         OR s.name LIKE '%Zugló%' OR s.name LIKE '%Ferihegy%' THEN 1
                    ELSE 0
                END AS is_multimodal,
                GROUP_CONCAT(d.served_routes, ', ') AS served_routes,
                COALESCE(d.vehicle_type, 'bus') AS vehicle_type
            FROM stops s
            LEFT JOIN station_hubs h ON h.hub_id = s.hub_id
            LEFT JOIN stop_platform_details d ON d.stop_id = s.id
            WHERE s.name LIKE ?1 COLLATE NOCASE
               OR h.normalized_name LIKE ?1 COLLATE NOCASE
            GROUP BY COALESCE(s.hub_id, s.name)
            ORDER BY
                CASE WHEN (s.name LIKE ?2 COLLATE NOCASE OR COALESCE(h.name, '') LIKE ?2 COLLATE NOCASE) THEN 0 ELSE 1 END,
                CASE
                    WHEN MAX(h.has_bkk AND h.has_mav) = 1 THEN 0
                    WHEN s.name LIKE '%pályaudvar%' OR s.name LIKE '%vasútállomás%' THEN 1
                    WHEN s.name LIKE '% M' OR s.name LIKE '% M+H' OR s.name LIKE '% H' THEN 2
                    ELSE 3
                END,
                LENGTH(COALESCE(h.name, s.name)) ASC
            LIMIT ?3
            "#,
        )?;

        let fetch_limit = (limit * 4) as i64;
        let rows = stmt.query_map(params![pattern, prefix_pattern, fetch_limit], |row| {
            let op_str: String = row.get(5)?;
            let raw_hub: Option<String> = row.get(1)?;
            let canon_hub = raw_hub.as_deref().map(|h| self.resolve_canonical_hub_id(h));
            let raw_name: String = row.get(2)?;
            let disp_name = canon_hub
                .as_ref()
                .and_then(|h| self.get_hub_display_name(h))
                .unwrap_or_else(|| clean_station_name(&raw_name));
            let is_mm: i64 = row.get(7)?;
            let is_mm_name = {
                let n1 = raw_name.to_lowercase();
                let n2 = disp_name.to_lowercase();
                n1.contains("keleti")
                    || n1.contains("nyugati")
                    || n1.contains("déli")
                    || n1.contains("kelenföld")
                    || n1.contains("kőbánya-kispest")
                    || n1.contains("zugló")
                    || n1.contains("ferihegy")
                    || n1.contains("pályaudvar")
                    || n1.contains("vasútállomás")
                    || n2.contains("keleti")
                    || n2.contains("nyugati")
                    || n2.contains("déli")
                    || n2.contains("kelenföld")
                    || n2.contains("kőbánya-kispest")
                    || n2.contains("zugló")
                    || n2.contains("ferihegy")
                    || n2.contains("pályaudvar")
                    || n2.contains("vasútállomás")
            };
            let raw_routes: Option<String> = row.get(8)?;
            let v_type: Option<String> = row.get(9)?;
            let node_id = canon_hub.clone().unwrap_or_else(|| row.get(0).unwrap_or_default());

            Ok(StopNode {
                id: node_id,
                hub_id: canon_hub,
                name: disp_name,
                lat: row.get(3)?,
                lon: row.get(4)?,
                operator: Operator::from_prefix(&op_str),
                platform_code: row.get(6)?,
                is_multimodal_hub: is_mm != 0 || is_mm_name,
                vehicle_type: v_type,
                served_routes: raw_routes,
                direction: None,
            })
        })?;

        let mut results: Vec<StopNode> = Vec::new();
        let mut hub_index_map: HashMap<String, usize> = HashMap::new();

        for r in rows {
            let mut node = r?;
            let key = if let Some(ref hid) = node.hub_id {
                format!("HUB:{}", hid)
            } else {
                format!("{}:{:.3}:{:.3}", node.name, node.lat, node.lon)
            };

            if let Some(&existing_idx) = hub_index_map.get(&key) {
                // Merge multiple stop groups that belong to the same canonical hub
                if let Some(new_routes) = node.served_routes {
                    let existing_routes = results[existing_idx].served_routes.take().unwrap_or_default();
                    let mut combined = existing_routes;
                    if !combined.is_empty() && !new_routes.is_empty() {
                        combined.push_str(", ");
                    }
                    combined.push_str(&new_routes);
                    results[existing_idx].served_routes = Some(dedup_route_str(&combined));
                }
                if node.is_multimodal_hub {
                    results[existing_idx].is_multimodal_hub = true;
                }
            } else {
                if let Some(ref routes) = node.served_routes {
                    node.served_routes = Some(dedup_route_str(routes));
                }
                hub_index_map.insert(key, results.len());
                results.push(node);
                if results.len() >= limit {
                    break;
                }
            }
        }
        Ok(results)
    }

    /// Resolves a MÁV OTP2 station gtfsId (e.g. "1:005501016_0") directly from the local SQLite `stops` table
    /// by stop ID, coordinate proximity (~650m), or normalized station name.
    pub fn resolve_mav_stop_id_from_db(&self, stop_or_hub_id: &str) -> Option<String> {
        if let Some(sync_id) = crate::gtfs_rt::mav::resolve_mav_otp2_stop_id_sync(stop_or_hub_id) {
            return Some(sync_id.to_string());
        }

        let conn = self.get_conn().ok()?;
        let mut query_name = String::new();
        let mut query_coords: Option<(f64, f64)> = None;

        if let Some(payload) = stop_or_hub_id.strip_prefix("GROUP:") {
            let parts: Vec<&str> = payload.rsplitn(3, ':').collect();
            if parts.len() == 3 {
                if let (Ok(lon), Ok(lat)) = (parts[0].parse::<f64>(), parts[1].parse::<f64>()) {
                    query_name = parts[2].to_string();
                    if lat > 1.0 && lon > 1.0 {
                        query_coords = Some((lat, lon));
                    }
                } else {
                    query_name = payload.to_string();
                }
            } else {
                query_name = payload.to_string();
            }
        } else {
            let unprefix = crate::gtfs_rt::mav::strip_transit_prefixes(stop_or_hub_id.trim());
            if unprefix.starts_with("1:") && !unprefix.starts_with("1:0036") {
                return Some(normalize_mav_otp2_id(unprefix));
            }
            let p1 = unprefix.to_string();
            let p2 = format!("MAV:{}", unprefix);
            let p3 = format!("BKK:{}", unprefix);
            let p4 = format!("HUB:{}", unprefix);
            let p5 = format!("HUB:MAV_{}", unprefix);
            if let Ok(mut stmt) = conn.prepare_cached(
                "SELECT id, name, lat, lon, operator_type FROM stops WHERE id IN (?1, ?2, ?3) OR hub_id IN (?1, ?4, ?5) ORDER BY (operator_type = 'MAV') DESC LIMIT 1",
            ) {
                if let Ok(Some((id, name, lat, lon, op))) = stmt
                    .query_row(params![p1, p2, p3, p4, p5], |r| {
                        Ok((
                            r.get::<_, String>(0)?,
                            r.get::<_, String>(1)?,
                            r.get::<_, f64>(2)?,
                            r.get::<_, f64>(3)?,
                            r.get::<_, String>(4)?,
                        ))
                    })
                    .optional()
                {
                    if op == "MAV" && !id.starts_with("MAV:1:0036") {
                        return Some(normalize_mav_otp2_id(&id));
                    }
                    query_name = name;
                    if lat > 1.0 && lon > 1.0 {
                        query_coords = Some((lat, lon));
                    }
                }
            }
        }

        if !query_name.is_empty() {
            if let Some(sync_id) = crate::gtfs_rt::mav::resolve_mav_otp2_stop_id_sync(&query_name) {
                return Some(sync_id.to_string());
            }
        }

        let target_core = normalize_station_core_name(&query_name);
        let q_lower = query_name.to_lowercase();
        let has_rail_keyword = q_lower.contains("vasútállomás")
            || q_lower.contains("pályaudvar")
            || q_lower.contains("vá.")
            || q_lower.contains("pu.");

        // 1. Coordinate proximity lookup (~650m around stop/hub)
        if let Some((lat, lon)) = query_coords {
            if let Ok(mut stmt) = conn.prepare_cached(
                r#"
                SELECT id, name, lat, lon
                FROM stops
                WHERE operator_type = 'MAV'
                  AND id NOT LIKE 'MAV:1:0036%'
                  AND lat BETWEEN ?1 AND ?2
                  AND lon BETWEEN ?3 AND ?4
                ORDER BY (id LIKE 'MAV:1:0055%') DESC, ((lat - ?5)*(lat - ?5) + (lon - ?6)*(lon - ?6)) ASC
                "#,
            ) {
                if let Ok(rows) = stmt.query_map(
                    params![lat - 0.006, lat + 0.006, lon - 0.008, lon + 0.008, lat, lon],
                    |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)),
                ) {
                    let candidates: Vec<(String, String)> = rows.flatten().collect();
                    for (mid, mname) in &candidates {
                        let m_core = normalize_station_core_name(mname);
                        if !target_core.is_empty() && !m_core.is_empty() && m_core == target_core {
                            return Some(normalize_mav_otp2_id(mid));
                        }
                    }
                    if has_rail_keyword {
                        if let Some((mid, _)) = candidates.first() {
                            return Some(normalize_mav_otp2_id(mid));
                        }
                    }
                }
            }
        }

        // 2. Exact / normalized station name lookup in SQLite `stops`
        if !target_core.is_empty() {
            let like_pat = format!("%{}%", target_core);
            if let Ok(mut stmt) = conn.prepare_cached(
                r#"
                SELECT id, name
                FROM stops
                WHERE operator_type = 'MAV'
                  AND id NOT LIKE 'MAV:1:0036%'
                  AND name LIKE ?1 COLLATE NOCASE
                ORDER BY (id LIKE 'MAV:1:0055%') DESC, LENGTH(name) ASC
                "#,
            ) {
                if let Ok(rows) = stmt.query_map(params![like_pat], |r| {
                    Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
                }) {
                    for (mid, mname) in rows.flatten() {
                        let m_core = normalize_station_core_name(&mname);
                        if m_core == target_core {
                            return Some(normalize_mav_otp2_id(&mid));
                        }
                    }
                }
            }
        }

        None
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

        // Separate Single Stop (exact platform) vs Station Hub / Group
        let (filter_column, filter_values) = if stop_or_hub_id.starts_with("GROUP:") {
            let payload = stop_or_hub_id.strip_prefix("GROUP:").unwrap();
            let parts: Vec<&str> = payload.rsplitn(3, ':').collect();
            let (raw_name, coords) = if parts.len() == 3 {
                if let (Ok(lon), Ok(lat)) = (parts[0].parse::<f64>(), parts[1].parse::<f64>()) {
                    (parts[2], Some((lat, lon)))
                } else {
                    (payload, None)
                }
            } else {
                (payload, None)
            };

            let clean_name = clean_station_name(raw_name);
            let mut stop_ids = Vec::new();
            let mut hub_ids = Vec::new();

            if let Some((lat, lon)) = coords {
                let lat_min = lat - 0.0045;
                let lat_max = lat + 0.0045;
                let lon_min = lon - 0.0060;
                let lon_max = lon + 0.0060;

                let mut stmt = conn.prepare_cached(
                    r#"
                    SELECT id, hub_id, name
                    FROM stops
                    WHERE lat BETWEEN ?1 AND ?2
                      AND lon BETWEEN ?3 AND ?4
                    "#,
                )?;
                let rows = stmt.query_map(params![lat_min, lat_max, lon_min, lon_max], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, Option<String>>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                })?;

                let target_clean = clean_station_name(&clean_name).to_lowercase();
                let target_core = normalize_station_core_name(&clean_name);
                for r in rows {
                    let (id, hub_id, name) = r?;
                    let c_name = clean_station_name(&name).to_lowercase();
                    let c_core = normalize_station_core_name(&name);
                    let name_lower = name.to_lowercase();
                    if c_name == target_clean
                        || (!target_core.is_empty() && c_core == target_core)
                        || name_lower.starts_with(&target_clean)
                        || target_clean.starts_with(&c_name)
                    {
                        stop_ids.push(id);
                        if let Some(h) = hub_id {
                            hub_ids.push(h);
                        }
                    }
                }
            } else {
                let prefix = format!("{}%", clean_name);
                let mut stmt = conn.prepare_cached(
                    r#"
                    SELECT id, hub_id, name
                    FROM stops
                    WHERE name LIKE ?1 COLLATE NOCASE
                    "#,
                )?;
                let rows = stmt.query_map(params![prefix], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, Option<String>>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                })?;

                let target_clean = clean_station_name(&clean_name).to_lowercase();
                let target_core = normalize_station_core_name(&clean_name);
                for r in rows {
                    let (id, hub_id, name) = r?;
                    let c_name = clean_station_name(&name).to_lowercase();
                    let c_core = normalize_station_core_name(&name);
                    let name_lower = name.to_lowercase();
                    if c_name == target_clean
                        || (!target_core.is_empty() && c_core == target_core)
                        || name_lower.starts_with(&target_clean)
                        || target_clean.starts_with(&c_name)
                    {
                        stop_ids.push(id);
                        if let Some(h) = hub_id {
                            hub_ids.push(h);
                        }
                    }
                }
            }

            // Include any stops belonging to the same canonical hub as the matched platforms
            if !hub_ids.is_empty() {
                let mut all_member_hubs = Vec::new();
                for h in hub_ids {
                    let canon = self.resolve_canonical_hub_id(&h);
                    for m in self.get_hub_members(&canon) {
                        all_member_hubs.push(m);
                    }
                }
                all_member_hubs.sort();
                all_member_hubs.dedup();

                if !all_member_hubs.is_empty() {
                    let placeholders = all_member_hubs
                        .iter()
                        .enumerate()
                        .map(|(i, _)| format!("?{}", i + 1))
                        .collect::<Vec<_>>()
                        .join(", ");
                    let sql = format!("SELECT id FROM stops WHERE hub_id IN ({})", placeholders);
                    let mut stmt = conn.prepare(&sql)?;
                    let p_refs: Vec<&dyn rusqlite::ToSql> = all_member_hubs
                        .iter()
                        .map(|m| m as &dyn rusqlite::ToSql)
                        .collect();
                    let rows = stmt.query_map(rusqlite::params_from_iter(p_refs), |r| {
                        r.get::<_, String>(0)
                    })?;
                    for r in rows {
                        stop_ids.push(r?);
                    }
                }
            }

            stop_ids.sort();
            stop_ids.dedup();
            ("s.id", stop_ids)
        } else if stop_or_hub_id.starts_with("HUB:")
            || stop_or_hub_id.starts_with("STOP:HUB:")
            || (stop_or_hub_id.strip_prefix("STOP:").unwrap_or(stop_or_hub_id).len() == 6
                && stop_or_hub_id.strip_prefix("STOP:").unwrap_or(stop_or_hub_id).chars().all(|c| c.is_ascii_digit()))
        {
            let unprefix = stop_or_hub_id.strip_prefix("STOP:").unwrap_or(stop_or_hub_id);
            let canonical_hub = self.resolve_canonical_hub_id(unprefix);
            let member_hubs = self.get_hub_members(&canonical_hub);
            ("s.hub_id", member_hubs)
        } else {
            // Single stop / platform query: STRICTLY filter by s.id, DO NOT resolve to hub_id!
            let stop_id = stop_or_hub_id.strip_prefix("STOP:").unwrap_or(stop_or_hub_id);
            let mut ids = vec![stop_id.to_string()];
            if let Some(stripped) = stop_id.strip_prefix("BKK:") {
                ids.push(stripped.to_string());
                ids.push(format!("BKK_{}", stripped));
            } else if let Some(stripped) = stop_id.strip_prefix("BKK_") {
                ids.push(stripped.to_string());
                ids.push(format!("BKK:{}", stripped));
            } else {
                ids.push(format!("BKK:{}", stop_id));
                ids.push(format!("BKK_{}", stop_id));
            }
            ("s.id", ids)
        };

        if filter_values.is_empty() {
            return Ok(Vec::new());
        }

        let placeholders = filter_values
            .iter()
            .enumerate()
            .map(|(i, _)| format!("?{}", i + 1))
            .collect::<Vec<_>>()
            .join(", ");
        let p_start = filter_values.len() + 1;

        let sql = format!(
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
                s.platform_code,
                st.arrival_seconds,
                NOT EXISTS (
                    SELECT 1 FROM stop_times st2
                    WHERE st2.trip_id = st.trip_id AND st2.stop_sequence > st.stop_sequence
                ) AS is_last_stop,
                (
                    SELECT s_first.name
                    FROM stop_times st_first
                    JOIN stops s_first ON s_first.id = st_first.stop_id
                    WHERE st_first.trip_id = st.trip_id
                    ORDER BY st_first.stop_sequence ASC
                    LIMIT 1
                ) AS origin_station
            FROM stops s
            JOIN stop_times st ON st.stop_id = s.id
            JOIN trips t ON t.id = st.trip_id
            JOIN routes r ON r.id = t.route_id
            WHERE {} IN ({})
              AND st.departure_seconds BETWEEN ?{} AND ?{}
              AND (
                  NOT EXISTS (SELECT 1 FROM calendar_active_dates LIMIT 1)
                  OR EXISTS (
                      SELECT 1 FROM calendar_active_dates cad
                      WHERE cad.service_id = t.service_id AND cad.service_date = ?{}
                  )
              )
            ORDER BY st.departure_seconds ASC
            LIMIT ?{}
            "#,
            filter_column,
            placeholders,
            p_start,
            p_start + 1,
            p_start + 2,
            p_start + 3
        );

        let mut params_vec: Vec<&dyn rusqlite::ToSql> =
            Vec::with_capacity(filter_values.len() + 4);
        for m in &filter_values {
            params_vec.push(m);
        }
        let lim = limit as i64;
        params_vec.push(&from_seconds_since_midnight);
        params_vec.push(&max_seconds);
        params_vec.push(&service_date_yyyymmdd);
        params_vec.push(&lim);

        let mut stmt = conn.prepare(&sql)?;
        let rows = stmt.query_map(rusqlite::params_from_iter(params_vec), |row| {
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
            let arr_sec_opt: Option<i32> = row.get(10).ok();
            let is_last_stop: bool = row.get::<_, i32>(11).map(|v| v != 0).unwrap_or(false);
            let origin_station: Option<String> = row.get(12).ok();

            let delay_opt = live_trip_delays.get(&trip_id).copied();
            let delay_seconds = delay_opt.unwrap_or(0);
            let est_sec = (sched_sec + delay_seconds).max(0);

            let (sched_arr_fmt, est_arr_fmt) = if let Some(arr_sec) = arr_sec_opt {
                let s_fmt = format_hhmm(arr_sec, &sched_fmt);
                let e_fmt = format_hhmm((arr_sec + delay_seconds).max(0), &sched_fmt);
                (Some(s_fmt), Some(e_fmt))
            } else {
                (None, None)
            };

            let is_arrival = is_last_stop
                || clean_station_name(&headsign).eq_ignore_ascii_case(&clean_station_name(&stop_id));

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
                is_arrival,
                origin_station,
                scheduled_arrival_time_formatted: sched_arr_fmt,
                estimated_arrival_time_formatted: est_arr_fmt,
            })
        })?;

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

pub fn dedup_route_str(routes: &str) -> String {
    let mut seen = std::collections::HashSet::new();
    let mut list = Vec::new();
    for r in routes.split(',') {
        let t = r.trim();
        if !t.is_empty() && seen.insert(t.to_string()) {
            list.push(t);
        }
    }
    list.join(", ")
}

pub fn format_hhmm(seconds: i32, fallback: &str) -> String {
    if seconds <= 0 && fallback == "--:--" {
        return fallback.to_string();
    }
    let normalized = (seconds % 86400 + 86400) % 86400;
    let total_minutes = normalized / 60;
    let h = total_minutes / 60;
    let m = total_minutes % 60;
    format!("{:02}:{:02}", h, m)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dedup_route_str() {
        assert_eq!(
            dedup_route_str("47, 48, 49, 9, 72, 47, 49, M3, M3"),
            "47, 48, 49, 9, 72, M3"
        );
        assert_eq!(dedup_route_str(""), "");
    }

    #[test]
    fn test_clean_station_name() {
        assert_eq!(clean_station_name("Széll Kálmán tér M"), "Széll Kálmán tér");
        assert_eq!(clean_station_name("Széll Kálmán tér"), "Széll Kálmán tér");
        assert_eq!(
            clean_station_name("Széll Kálmán tér M (Csaba utca)"),
            "Széll Kálmán tér"
        );
        assert_eq!(clean_station_name("Örs vezér tere M+H"), "Örs vezér tere");
        assert_eq!(
            clean_station_name("Örs vezér tere M+H (Kerepesi út)"),
            "Örs vezér tere"
        );
        assert_eq!(
            clean_station_name("Nyugati pályaudvar M"),
            "Nyugati pályaudvar"
        );
        assert_eq!(
            clean_station_name("Nyugati pályaudvar [H]"),
            "Nyugati pályaudvar"
        );
        assert_eq!(
            clean_station_name("Nyugati pályaudvar [M]"),
            "Nyugati pályaudvar"
        );
        assert_eq!(
            clean_station_name("Nyugati pályaudvar M (Podmaniczky utca)"),
            "Nyugati pályaudvar"
        );
        assert_eq!(clean_station_name("Blaha Lujza tér M"), "Blaha Lujza tér");
        assert_eq!(clean_station_name("Blaha Lujza tér [A]"), "Blaha Lujza tér");
        assert_eq!(
            clean_station_name("Blaha Lujza tér M (Népszínház utca)"),
            "Blaha Lujza tér"
        );
        assert_eq!(
            clean_station_name("Blaha Lujza tér M (Dohány utca)"),
            "Blaha Lujza tér"
        );
        assert_eq!(
            clean_station_name("Kelenföld vasútállomás M"),
            "Kelenföld vasútállomás"
        );
        assert_eq!(
            clean_station_name("Kelenföld vasútállomás (Őrmező)"),
            "Kelenföld vasútállomás"
        );
        assert_eq!(
            clean_station_name("Deák Ferenc tér M"),
            "Deák Ferenc tér"
        );
    }

    #[test]
    fn test_unified_departures_single_stop_vs_group() {
        if let Ok(repo) = StaticTransitRepository::open("../assets/db/transit_static.db") {
            let delays = HashMap::new();
            // 1. Single Stop mode (with STOP: prefix and raw stop_id)
            let single_res = repo.get_unified_departures(
                "STOP:BKK_F01007",
                "20261022",
                12 * 3600,
                3600,
                &delays,
                20,
            );
            if let Ok(deps) = single_res {
                for d in &deps {
                    assert!(
                        d.stop_id == "BKK_F01007" || d.stop_id == "BKK:F01007",
                        "Single stop query must strictly return departures for F01007, got {}",
                        d.stop_id
                    );
                }
            }

            // 2. Group mode
            let group_res = repo.get_unified_departures(
                "GROUP:Petőfi híd, budai hídfő:47.478:19.060",
                "20261022",
                12 * 3600,
                3600,
                &delays,
                20,
            );
            assert!(group_res.is_ok(), "GROUP departures query should succeed");
        }
    }

    #[test]
    fn test_live_nyugati_get_station_departure_board() {
        let _ = crate::api::init_engine(
            "../assets/db/transit_static.db".to_string(),
            None,
            None,
        );
        let deps = crate::api::get_station_departure_board(
            "GROUP:Nyugati pályaudvar:47.5106:19.0573".to_string(),
            90,
            50,
        ).unwrap();
        println!("TOTAL DEPARTURES: {}", deps.len());
        let mav_count = deps.iter().filter(|d| d.operator == crate::gtfs_rt::models::Operator::MAV).count();
        let bkk_count = deps.iter().filter(|d| d.operator == crate::gtfs_rt::models::Operator::BKK).count();
        println!("MAV COUNT: {}, BKK COUNT: {}", mav_count, bkk_count);
        for d in deps.iter().filter(|d| d.operator == crate::gtfs_rt::models::Operator::MAV).take(5) {
            println!("  MAV: {} -> {} at {}", d.line_name, d.headsign, d.scheduled_time_formatted);
        }
    }

    #[test]
    fn test_otp2_platforms() {
        let _ = crate::api::init_engine(
            "../assets/db/transit_static.db".to_string(),
            None,
            None,
        );
        let nyugati_deps = crate::api::get_station_departure_board("STOP:MAV:1:005510033_5".to_string(), 90, 50).unwrap();
        assert!(!nyugati_deps.is_empty(), "Nyugati departures must not be empty");
        let keleti_deps = crate::api::get_station_departure_board("GROUP:Budapest-Keleti:47.500:19.083".to_string(), 90, 50).unwrap();
        assert!(!keleti_deps.is_empty(), "Keleti departures must not be empty");
        let deli_deps = crate::api::get_station_departure_board("GROUP:Déli pályaudvar:47.500:19.025".to_string(), 90, 50).unwrap();
        assert!(!deli_deps.is_empty(), "Déli departures must not be empty");
        let kelenfold_deps = crate::api::get_station_departure_board("GROUP:Kelenföld vasútállomás:47.464:19.021".to_string(), 90, 50).unwrap();
        assert!(!kelenfold_deps.is_empty(), "Kelenföld departures must not be empty");
        let blaha_deps = crate::api::get_station_departure_board("STOP:HUB:000323".to_string(), 90, 50).unwrap();
        assert!(!blaha_deps.is_empty(), "Blaha departures must not be empty");
    }
}
