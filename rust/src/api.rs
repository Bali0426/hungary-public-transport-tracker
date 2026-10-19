use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::RwLock;
use std::time::Duration;

use anyhow::Result;
use chrono::{Local, Timelike};
use once_cell::sync::Lazy;
use reqwest::Client;
use tokio::runtime::Runtime;

use crate::gtfs_rt::bkk::fetch_bkk_live_vehicles;
use crate::gtfs_rt::mav::fetch_mav_live_vehicles;
use crate::gtfs_rt::models::{BoundingBox, StopNode, UnifiedDeparture, UnifiedVehicle};
use crate::static_db::repository::StaticTransitRepository;
use crate::static_db::spatial::{filter_vehicles_in_bbox, vehicles_to_geojson};

struct EngineState {
    repo: Option<StaticTransitRepository>,
    bkk_api_key: Option<String>,
    mav_gtfs_rt_url: Option<String>,
    http_client: Client,
    cached_vehicles: Vec<UnifiedVehicle>,
    cached_trip_delays: HashMap<String, i32>,
}

static ENGINE_STATE: Lazy<RwLock<EngineState>> = Lazy::new(|| {
    let client = Client::builder()
        .timeout(Duration::from_secs(12))
        .user_agent("HungaryPublicTransportTracker/1.0 (Rust-Engine)")
        .build()
        .expect("Failed to initialize reqwest HTTP client");

    RwLock::new(EngineState {
        repo: None,
        bkk_api_key: std::env::var("BKK_API_KEY").ok(),
        mav_gtfs_rt_url: std::env::var("MAV_GTFS_RT_URL").ok(),
        http_client: client,
        cached_vehicles: Vec::new(),
        cached_trip_delays: HashMap::new(),
    })
});

static TOKIO_RT: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .expect("Failed to start Tokio runtime")
});

/// Initializes the Rust engine with the local SQLite database path and live feed credentials.
pub fn init_engine(
    sqlite_db_path: String,
    bkk_api_key: Option<String>,
    mav_gtfs_rt_url: Option<String>,
) -> Result<()> {
    let repo = StaticTransitRepository::open(&sqlite_db_path)?;
    let mut guard = ENGINE_STATE.write().unwrap();
    guard.repo = Some(repo);
    if let Some(key) = bkk_api_key.filter(|k| !k.trim().is_empty()) {
        guard.bkk_api_key = Some(key);
    }
    if let Some(url) = mav_gtfs_rt_url.filter(|u| !u.trim().is_empty()) {
        guard.mav_gtfs_rt_url = Some(url);
    }
    Ok(())
}

/// Polls both BKK FUTÁR (`VehiclePositions.pb` + `TripUpdates.pb`) and MÁV live feeds,
/// updates internal state, and returns the viewport-filtered `UnifiedVehicle` list.
pub async fn poll_live_vehicles_in_bbox(
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
) -> Result<Vec<UnifiedVehicle>> {
    let bbox = BoundingBox {
        min_lat,
        min_lon,
        max_lat,
        max_lon,
    };

    let (client, repo, bkk_key, mav_url) = {
        let guard = ENGINE_STATE.read().unwrap();
        (
            guard.http_client.clone(),
            guard.repo.clone(),
            guard.bkk_api_key.clone(),
            guard.mav_gtfs_rt_url.clone(),
        )
    };

    let bkk_fut = async {
        if let Some(ref key) = bkk_key {
            fetch_bkk_live_vehicles(&client, key, repo.as_ref()).await
        } else {
            Ok((Vec::new(), HashMap::new()))
        }
    };

    let mav_fut = fetch_mav_live_vehicles(&client, mav_url.as_deref(), Some(bbox));

    let (bkk_res, mav_res) = tokio::join!(bkk_fut, mav_fut);

    let mut combined_vehicles = Vec::new();
    let mut combined_delays = HashMap::new();

    if let Ok((bkk_v, bkk_d)) = bkk_res {
        combined_vehicles.extend(bkk_v);
        combined_delays.extend(bkk_d);
    }
    if let Ok((mav_v, mav_d)) = mav_res {
        combined_vehicles.extend(mav_v);
        combined_delays.extend(mav_d);
    }

    let filtered = filter_vehicles_in_bbox(&combined_vehicles, bbox);

    {
        let mut guard = ENGINE_STATE.write().unwrap();
        guard.cached_vehicles = combined_vehicles;
        guard.cached_trip_delays = combined_delays;
    }

    Ok(filtered)
}

/// Polls live feeds and returns a MapLibre-ready GeoJSON FeatureCollection string for the viewport.
pub async fn poll_live_vehicles_geojson(
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
) -> Result<String> {
    let vehicles = poll_live_vehicles_in_bbox(min_lat, min_lon, max_lat, max_lon).await?;
    Ok(vehicles_to_geojson(&vehicles))
}

/// Queries the SQLite R-Tree index for all stops inside the bounding box.
pub fn get_stops_in_bbox(
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
    limit: usize,
) -> Result<Vec<StopNode>> {
    let guard = ENGINE_STATE.read().unwrap();
    let Some(ref repo) = guard.repo else {
        anyhow::bail!("Static database is not initialized");
    };
    repo.query_stops_in_bbox(
        BoundingBox {
            min_lat,
            min_lon,
            max_lat,
            max_lon,
        },
        limit,
    )
}

/// Searches stops and multimodal station hubs across BKK and MÁV by name.
pub fn search_stops_by_name(query: String, limit: usize) -> Result<Vec<StopNode>> {
    let guard = ENGINE_STATE.read().unwrap();
    let Some(ref repo) = guard.repo else {
        anyhow::bail!("Static database is not initialized");
    };
    repo.search_stops(&query, limit)
}

/// Returns the unified departure board for a stop or multimodal station hub, merging real-time delays.
pub fn get_station_departure_board(
    stop_or_hub_id: String,
    horizon_minutes: i32,
    limit: usize,
) -> Result<Vec<UnifiedDeparture>> {
    let guard = ENGINE_STATE.read().unwrap();
    let Some(ref repo) = guard.repo else {
        anyhow::bail!("Static database is not initialized");
    };

    let now = Local::now();
    let service_date = now.format("%Y%m%d").to_string();
    let seconds_since_midnight =
        (now.hour() * 3600 + now.minute() * 60 + now.second()) as i32;

    repo.get_unified_departures(
        &stop_or_hub_id,
        &service_date,
        seconds_since_midnight - 120, // Include trains/buses departing in the last 2 minutes
        (horizon_minutes.max(15)) * 60,
        &guard.cached_trip_delays,
        limit,
    )
}

// ============================================================================
// Direct C-ABI FFI Exports (for zero-codegen `dart:ffi` / Windows & Android)
// ============================================================================

fn into_c_string_ptr(s: String) -> *mut c_char {
    CString::new(s)
        .unwrap_or_else(|_| CString::new("{}").unwrap())
        .into_raw()
}

unsafe fn from_c_str(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

#[no_mangle]
pub unsafe extern "C" fn transit_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub unsafe extern "C" fn transit_init_engine(
    db_path_ptr: *const c_char,
    bkk_key_ptr: *const c_char,
    mav_url_ptr: *const c_char,
) -> i32 {
    let db_path = from_c_str(db_path_ptr);
    let bkk_key = {
        let s = from_c_str(bkk_key_ptr);
        if s.is_empty() { None } else { Some(s) }
    };
    let mav_url = {
        let s = from_c_str(mav_url_ptr);
        if s.is_empty() { None } else { Some(s) }
    };
    match init_engine(db_path, bkk_key, mav_url) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn transit_poll_live_vehicles_geojson(
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
) -> *mut c_char {
    let res = TOKIO_RT.block_on(poll_live_vehicles_geojson(
        min_lat, min_lon, max_lat, max_lon,
    ));
    match res {
        Ok(geojson) => into_c_string_ptr(geojson),
        Err(e) => into_c_string_ptr(
            serde_json::json!({
                "type": "FeatureCollection",
                "features": [],
                "error": e.to_string()
            })
            .to_string(),
        ),
    }
}

#[no_mangle]
pub extern "C" fn transit_get_stops_in_bbox_json(
    min_lat: f64,
    min_lon: f64,
    max_lat: f64,
    max_lon: f64,
    limit: usize,
) -> *mut c_char {
    match get_stops_in_bbox(min_lat, min_lon, max_lat, max_lon, limit) {
        Ok(stops) => into_c_string_ptr(serde_json::to_string(&stops).unwrap_or_else(|_| "[]".into())),
        Err(_) => into_c_string_ptr("[]".to_string()),
    }
}

#[no_mangle]
pub unsafe extern "C" fn transit_search_stops_json(
    query_ptr: *const c_char,
    limit: usize,
) -> *mut c_char {
    let query = from_c_str(query_ptr);
    match search_stops_by_name(query, limit) {
        Ok(stops) => into_c_string_ptr(serde_json::to_string(&stops).unwrap_or_else(|_| "[]".into())),
        Err(_) => into_c_string_ptr("[]".to_string()),
    }
}

#[no_mangle]
pub unsafe extern "C" fn transit_get_departure_board_json(
    stop_or_hub_id_ptr: *const c_char,
    horizon_minutes: i32,
    limit: usize,
) -> *mut c_char {
    let id = from_c_str(stop_or_hub_id_ptr);
    match get_station_departure_board(id, horizon_minutes, limit) {
        Ok(deps) => into_c_string_ptr(serde_json::to_string(&deps).unwrap_or_else(|_| "[]".into())),
        Err(_) => into_c_string_ptr("[]".to_string()),
    }
}
