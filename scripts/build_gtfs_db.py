#!/usr/bin/env python3
"""
Offline Static Transit Database Builder (BKK + MÁV)
===================================================
Builds `assets/db/transit_static.db` from official BKK GTFS and MÁV GTFS archives.

Features:
- Automatic download of official BKK GTFS (`https://go.bkk.hu/api/static/v1/public-gtfs/budapest_gtfs.zip`)
- Ingests local or remote MÁV GTFS (`mav_gtfs.zip`)
- Prunes inactive calendar services outside a configurable 14-day window
- Normalizes stop coordinates, route colors, and operator namespaces (`BKK:` / `MAV:`)
- Builds an SQLite R-Tree spatial index (`stops_rtree`) for instant bounding-box queries
- Computes `station_hubs` by clustering physical stops within 150 meters with normalized name matching
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import math
import os
import re
import sqlite3
import sys
import unicodedata
import urllib.request
import zipfile
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple

BKK_DEFAULT_GTFS_URL = "https://go.bkk.hu/api/static/v1/public-gtfs/budapest_gtfs.zip"
HUB_DISTANCE_THRESHOLD_METERS = 150.0


def normalize_station_name(name: str) -> str:
    """Normalizes Hungarian station names for multimodal hub matching."""
    text = unicodedata.normalize("NFKD", name.lower())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    # Remove common transit suffixes/designators
    stopwords = [
        r"\bvasutallomas\b",
        r"\bvasutall\.?\b",
        r"\bpalyudvar\b",
        r"\bpu\.?\b",
        r"\ballomas\b",
        r"\bmegallohely\b",
        r"\bmh\.?\b",
        r"\bbudapest[- ]*",
        r"\bm\b",
        r"\bh\b",
    ]
    for pattern in stopwords:
        text = re.sub(pattern, " ", text)
    text = re.sub(r"[^a-z0-9]+", " ", text).strip()
    return text


def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Returns great-circle distance in meters between two WGS84 coordinates."""
    r = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = (
        math.sin(dphi / 2.0) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2.0) ** 2
    )
    return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def create_schema(conn: sqlite3.Connection) -> None:
    """Initializes the SQLite schema, indexes, and R-Tree virtual table."""
    cur = conn.cursor()
    cur.executescript(
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        PRAGMA temp_store = MEMORY;
        PRAGMA cache_size = -128000;

        DROP TABLE IF EXISTS stop_times;
        DROP TABLE IF EXISTS trips;
        DROP TABLE IF EXISTS routes;
        DROP TABLE IF EXISTS stops_rtree;
        DROP TABLE IF EXISTS stops;
        DROP TABLE IF EXISTS station_hubs;
        DROP TABLE IF EXISTS calendar_active_dates;
        DROP TABLE IF EXISTS metadata;

        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE station_hubs (
            hub_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            normalized_name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            has_bkk INTEGER NOT NULL DEFAULT 0,
            has_mav INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE stops (
            rowid INTEGER PRIMARY KEY AUTOINCREMENT,
            id TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL,
            lat REAL NOT NULL,
            lon REAL NOT NULL,
            operator_type TEXT NOT NULL, -- 'BKK' or 'MAV'
            hub_id TEXT,
            platform_code TEXT,
            FOREIGN KEY (hub_id) REFERENCES station_hubs(hub_id)
        );

        CREATE VIRTUAL TABLE stops_rtree USING rtree(
            id,
            min_lat, max_lat,
            min_lon, max_lon
        );

        CREATE TABLE routes (
            id TEXT PRIMARY KEY,
            operator_type TEXT NOT NULL,
            short_name TEXT NOT NULL,
            long_name TEXT NOT NULL,
            route_color TEXT NOT NULL,
            route_text_color TEXT NOT NULL,
            route_type INTEGER NOT NULL
        );

        CREATE TABLE trips (
            id TEXT PRIMARY KEY,
            route_id TEXT NOT NULL,
            service_id TEXT NOT NULL,
            trip_headsign TEXT NOT NULL,
            trip_short_name TEXT,
            direction_id INTEGER,
            FOREIGN KEY (route_id) REFERENCES routes(id)
        );

        CREATE TABLE stop_times (
            trip_id TEXT NOT NULL,
            stop_id TEXT NOT NULL,
            stop_sequence INTEGER NOT NULL,
            arrival_seconds INTEGER NOT NULL,
            departure_seconds INTEGER NOT NULL,
            departure_time TEXT NOT NULL,
            FOREIGN KEY (trip_id) REFERENCES trips(id),
            FOREIGN KEY (stop_id) REFERENCES stops(id)
        );

        CREATE TABLE calendar_active_dates (
            service_id TEXT NOT NULL,
            service_date TEXT NOT NULL, -- YYYYMMDD
            PRIMARY KEY (service_id, service_date)
        );
        """
    )
    conn.commit()


def parse_gtfs_time_to_seconds(t_str: str) -> Optional[int]:
    """Converts GTFS HH:MM:SS (supporting >24h service day times) to seconds since midnight."""
    parts = t_str.strip().split(":")
    if len(parts) != 3:
        return None
    try:
        h, m, s = int(parts[0]), int(parts[1]), int(parts[2])
        return h * 3600 + m * 60 + s
    except ValueError:
        return None


def read_csv_from_zip(zf: zipfile.ZipFile, filename: str) -> Iterable[Dict[str, str]]:
    """Streams a UTF-8 (or BOM-prefixed) CSV file from inside a GTFS zip archive."""
    target = None
    for name in zf.namelist():
        if Path(name).name.lower() == filename.lower():
            target = name
            break
    if target is None:
        return []

    def _generator() -> Iterable[Dict[str, str]]:
        with zf.open(target, "r") as raw:
            wrapper = io.TextIOWrapper(raw, encoding="utf-8-sig", errors="replace")
            reader = csv.DictReader(wrapper)
            for row in reader:
                yield row

    return _generator()


def compute_active_services(
    zf: zipfile.ZipFile,
    prefix: str,
    window_start: dt.date,
    window_days: int,
) -> Dict[str, Set[str]]:
    """
    Determines active `service_id`s and their active `YYYYMMDD` dates within
    [window_start, window_start + window_days].
    """
    target_dates = [
        window_start + dt.timedelta(days=offset) for offset in range(window_days)
    ]
    weekday_cols = [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
    ]
    active_dates_by_service: Dict[str, Set[str]] = {}

    for row in read_csv_from_zip(zf, "calendar.txt"):
        raw_sid = (row.get("service_id") or "").strip()
        if not raw_sid:
            continue
        sid = f"{prefix}:{raw_sid}"
        try:
            start_d = dt.datetime.strptime(row["start_date"].strip(), "%Y%m%d").date()
            end_d = dt.datetime.strptime(row["end_date"].strip(), "%Y%m%d").date()
        except (KeyError, ValueError):
            continue

        for d in target_dates:
            if start_d <= d <= end_d:
                col = weekday_cols[d.weekday()]
                if row.get(col, "0").strip() == "1":
                    active_dates_by_service.setdefault(sid, set()).add(
                        d.strftime("%Y%m%d")
                    )

    for row in read_csv_from_zip(zf, "calendar_dates.txt"):
        raw_sid = (row.get("service_id") or "").strip()
        date_str = (row.get("date") or "").strip()
        exc_type = (row.get("exception_type") or "").strip()
        if not raw_sid or len(date_str) != 8:
            continue
        try:
            d = dt.datetime.strptime(date_str, "%Y%m%d").date()
        except ValueError:
            continue
        if not (window_start <= d < window_start + dt.timedelta(days=window_days)):
            continue

        sid = f"{prefix}:{raw_sid}"
        if exc_type == "1":
            active_dates_by_service.setdefault(sid, set()).add(date_str)
        elif exc_type == "2":
            if sid in active_dates_by_service:
                active_dates_by_service[sid].discard(date_str)

    # Filter out services with zero active dates in window
    return {k: v for k, v in active_dates_by_service.items() if v}


def ingest_gtfs_archive(
    conn: sqlite3.Connection,
    zip_path: Path,
    operator: str,
    window_start: dt.date,
    window_days: int,
) -> None:
    """Ingests a single GTFS zip archive (BKK or MAV) into the SQLite database."""
    print(f"[{operator}] Opening GTFS archive: {zip_path}")
    cur = conn.cursor()

    with zipfile.ZipFile(zip_path, "r") as zf:
        active_services = compute_active_services(zf, operator, window_start, window_days)
        print(
            f"[{operator}] Found {len(active_services):,} active service_ids in "
            f"{window_days}-day window starting {window_start.isoformat()}"
        )

        # If a feed has no calendar rows inside the window (e.g. slightly stale local archive),
        # fall back to accepting all services so the database isn't empty.
        accept_all_services = len(active_services) == 0
        if accept_all_services:
            print(
                f"[{operator}] WARNING: No services matched date window; ingesting all services as fallback."
            )
        else:
            cal_rows = [
                (sid, d_str)
                for sid, dates in active_services.items()
                for d_str in sorted(dates)
            ]
            cur.executemany(
                "INSERT OR IGNORE INTO calendar_active_dates (service_id, service_date) VALUES (?, ?)",
                cal_rows,
            )

        # 1. Stops
        stops_batch: List[Tuple[str, str, float, float, str, Optional[str]]] = []
        valid_stop_ids: Set[str] = set()
        for row in read_csv_from_zip(zf, "stops.txt"):
            raw_id = (row.get("stop_id") or "").strip()
            name = (row.get("stop_name") or "").strip()
            lat_str = (row.get("stop_lat") or "").strip()
            lon_str = (row.get("stop_lon") or "").strip()
            if not raw_id or not name or not lat_str or not lon_str:
                continue
            try:
                lat = float(lat_str)
                lon = float(lon_str)
            except ValueError:
                continue

            stop_id = f"{operator}:{raw_id}"
            platform = (row.get("platform_code") or "").strip() or None
            stops_batch.append((stop_id, name, lat, lon, operator, platform))
            valid_stop_ids.add(stop_id)

        cur.executemany(
            """
            INSERT OR REPLACE INTO stops (id, name, lat, lon, operator_type, platform_code)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            stops_batch,
        )
        print(f"[{operator}] Inserted {len(stops_batch):,} stops.")

        # 2. Routes
        routes_batch: List[Tuple[str, str, str, str, str, str, int]] = []
        valid_route_ids: Set[str] = set()
        default_color = "0057B8" if operator == "MAV" else "009EE3"
        for row in read_csv_from_zip(zf, "routes.txt"):
            raw_id = (row.get("route_id") or "").strip()
            if not raw_id:
                continue
            route_id = f"{operator}:{raw_id}"
            short_name = (row.get("route_short_name") or "").strip()
            long_name = (row.get("route_long_name") or "").strip()
            if not short_name and long_name:
                short_name = long_name[:12]
            color = (row.get("route_color") or "").strip().lstrip("#") or default_color
            text_color = (
                row.get("route_text_color") or ""
            ).strip().lstrip("#") or "FFFFFF"
            try:
                route_type = int((row.get("route_type") or "3").strip())
            except ValueError:
                route_type = 3

            routes_batch.append(
                (
                    route_id,
                    operator,
                    short_name,
                    long_name,
                    color.upper(),
                    text_color.upper(),
                    route_type,
                )
            )
            valid_route_ids.add(route_id)

        cur.executemany(
            """
            INSERT OR REPLACE INTO routes
            (id, operator_type, short_name, long_name, route_color, route_text_color, route_type)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            routes_batch,
        )
        print(f"[{operator}] Inserted {len(routes_batch):,} routes.")

        # 3. Trips
        trips_batch: List[Tuple[str, str, str, str, Optional[str], Optional[int]]] = []
        valid_trip_ids: Set[str] = set()
        for row in read_csv_from_zip(zf, "trips.txt"):
            raw_trip_id = (row.get("trip_id") or "").strip()
            raw_route_id = (row.get("route_id") or "").strip()
            raw_service_id = (row.get("service_id") or "").strip()
            if not raw_trip_id or not raw_route_id or not raw_service_id:
                continue

            route_id = f"{operator}:{raw_route_id}"
            service_id = f"{operator}:{raw_service_id}"
            if route_id not in valid_route_ids:
                continue
            if not accept_all_services and service_id not in active_services:
                continue

            trip_id = f"{operator}:{raw_trip_id}"
            headsign = (row.get("trip_headsign") or "").strip()
            short_name = (row.get("trip_short_name") or "").strip() or None
            dir_raw = (row.get("direction_id") or "").strip()
            direction_id = int(dir_raw) if dir_raw in ("0", "1") else None

            trips_batch.append(
                (trip_id, route_id, service_id, headsign, short_name, direction_id)
            )
            valid_trip_ids.add(trip_id)

        cur.executemany(
            """
            INSERT OR REPLACE INTO trips
            (id, route_id, service_id, trip_headsign, trip_short_name, direction_id)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            trips_batch,
        )
        print(f"[{operator}] Inserted {len(trips_batch):,} active trips.")

        # 4. Stop Times (streamed in chunks to keep memory footprint low)
        stop_times_batch: List[Tuple[str, str, int, int, int, str]] = []
        total_stop_times = 0
        batch_size = 50_000

        for row in read_csv_from_zip(zf, "stop_times.txt"):
            raw_trip_id = (row.get("trip_id") or "").strip()
            if not raw_trip_id:
                continue
            trip_id = f"{operator}:{raw_trip_id}"
            if trip_id not in valid_trip_ids:
                continue

            raw_stop_id = (row.get("stop_id") or "").strip()
            stop_id = f"{operator}:{raw_stop_id}"
            if stop_id not in valid_stop_ids:
                continue

            dep_str = (row.get("departure_time") or row.get("arrival_time") or "").strip()
            arr_str = (row.get("arrival_time") or dep_str).strip()
            dep_sec = parse_gtfs_time_to_seconds(dep_str)
            arr_sec = parse_gtfs_time_to_seconds(arr_str)
            if dep_sec is None or arr_sec is None:
                continue

            try:
                seq = int((row.get("stop_sequence") or "0").strip())
            except ValueError:
                seq = 0

            stop_times_batch.append(
                (trip_id, stop_id, seq, arr_sec, dep_sec, dep_str)
            )
            if len(stop_times_batch) >= batch_size:
                cur.executemany(
                    """
                    INSERT INTO stop_times
                    (trip_id, stop_id, stop_sequence, arrival_seconds, departure_seconds, departure_time)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    stop_times_batch,
                )
                total_stop_times += len(stop_times_batch)
                stop_times_batch.clear()

        if stop_times_batch:
            cur.executemany(
                """
                INSERT INTO stop_times
                (trip_id, stop_id, stop_sequence, arrival_seconds, departure_seconds, departure_time)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                stop_times_batch,
            )
            total_stop_times += len(stop_times_batch)
            stop_times_batch.clear()

        print(f"[{operator}] Inserted {total_stop_times:,} stop_times rows.")
    conn.commit()


def build_spatial_index_and_hubs(conn: sqlite3.Connection) -> None:
    """
    Populates the R-Tree index (`stops_rtree`) and clusters stops within 150m
    that share a normalized station name into `station_hubs`.
    """
    cur = conn.cursor()
    print("[Index] Populating R-Tree spatial index on stops(lat, lon)...")
    cur.execute(
        """
        INSERT INTO stops_rtree (id, min_lat, max_lat, min_lon, max_lon)
        SELECT rowid, lat, lat, lon, lon FROM stops;
        """
    )

    print("[Hubs] Clustering multimodal station hubs (150m threshold)...")
    cur.execute("SELECT rowid, id, name, lat, lon, operator_type FROM stops")
    all_stops = cur.fetchall()

    # Group candidate stops by normalized station name
    by_norm_name: Dict[str, List[Tuple[int, str, str, float, float, str]]] = {}
    for rowid, sid, name, lat, lon, op in all_stops:
        norm = normalize_station_name(name)
        if not norm:
            norm = name.lower().strip()
        by_norm_name.setdefault(norm, []).append((rowid, sid, name, lat, lon, op))

    hubs_to_insert: List[Tuple[str, str, str, float, float, int, int]] = []
    stop_hub_updates: List[Tuple[str, int]] = []
    hub_counter = 0

    for norm_name, members in by_norm_name.items():
        # Greedy spatial clustering within 150 meters
        unassigned = list(members)
        while unassigned:
            seed = unassigned.pop(0)
            cluster = [seed]
            remaining = []
            for candidate in unassigned:
                dist = haversine_meters(
                    seed[3], seed[4], candidate[3], candidate[4]
                )
                if dist <= HUB_DISTANCE_THRESHOLD_METERS:
                    cluster.append(candidate)
                else:
                    remaining.append(candidate)
            unassigned = remaining

            hub_counter += 1
            hub_id = f"HUB:{hub_counter:06d}"
            avg_lat = sum(m[3] for m in cluster) / len(cluster)
            avg_lon = sum(m[4] for m in cluster) / len(cluster)
            has_bkk = int(any(m[5] == "BKK" for m in cluster))
            has_mav = int(any(m[5] == "MAV" for m in cluster))
            # Prefer cleaner/shorter display name
            canonical_name = min((m[2] for m in cluster), key=len)

            hubs_to_insert.append(
                (
                    hub_id,
                    canonical_name,
                    norm_name,
                    avg_lat,
                    avg_lon,
                    has_bkk,
                    has_mav,
                )
            )
            for m in cluster:
                stop_hub_updates.append((hub_id, m[0]))

    cur.executemany(
        """
        INSERT INTO station_hubs
        (hub_id, name, normalized_name, lat, lon, has_bkk, has_mav)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        hubs_to_insert,
    )
    cur.executemany(
        "UPDATE stops SET hub_id = ? WHERE rowid = ?",
        stop_hub_updates,
    )
    conn.commit()
    print(f"[Hubs] Created {len(hubs_to_insert):,} station hubs across {len(all_stops):,} stops.")


def build_stop_platform_details(conn: sqlite3.Connection) -> None:
    """Precomputes vehicle types, served lines, and directional headsigns per individual stop platform."""
    cur = conn.cursor()
    print("[Platforms] Computing served lines and headsigns for individual stop platforms...")
    cur.execute(
        """
        SELECT
            st.stop_id,
            r.route_type,
            r.short_name,
            t.trip_headsign
        FROM stop_times st
        JOIN trips t ON t.id = st.trip_id
        JOIN routes r ON r.id = t.route_id
        GROUP BY st.stop_id, r.route_type, r.short_name, t.trip_headsign
        """
    )
    rows = cur.fetchall()

    def map_route_type(rt: int, short_name: str) -> str:
        if rt == 0:
            return "tram"
        if rt == 1:
            return "metro"
        if rt == 2:
            return "train"
        if rt in (11, 800) or (
            rt == 3
            and short_name
            and short_name.isdigit()
            and int(short_name) in [70, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83]
        ):
            return "trolley"
        if rt == 109:
            return "suburban_rail"
        if rt == 4:
            return "boat"
        return "bus"

    by_stop: Dict[str, Dict[str, Set[str]]] = {}
    for stop_id, rt, short_name, headsign in rows:
        if stop_id not in by_stop:
            by_stop[stop_id] = {"types": set(), "routes": set(), "headsigns": set()}
        vtype = map_route_type(rt, short_name or "")
        by_stop[stop_id]["types"].add(vtype)
        if short_name:
            by_stop[stop_id]["routes"].add(short_name)
        if headsign:
            by_stop[stop_id]["headsigns"].add(headsign)

    to_insert: List[Tuple[str, str, str, str]] = []
    for stop_id, data in by_stop.items():
        primary_type = "bus"
        for pt in ["metro", "train", "suburban_rail", "tram", "trolley", "boat", "bus"]:
            if pt in data["types"]:
                primary_type = pt
                break
        sorted_routes = sorted(data["routes"], key=lambda x: (len(x), x))
        routes_str = ", ".join(sorted_routes[:10])
        headsigns_str = " / ".join(list(data["headsigns"])[:2])
        to_insert.append((stop_id, primary_type, routes_str, headsigns_str))

    cur.execute("DROP TABLE IF EXISTS stop_platform_details")
    cur.execute(
        """
        CREATE TABLE stop_platform_details (
            stop_id TEXT PRIMARY KEY,
            vehicle_type TEXT,
            served_routes TEXT,
            direction_headsigns TEXT
        )
        """
    )
    cur.executemany("INSERT INTO stop_platform_details VALUES (?, ?, ?, ?)", to_insert)
    conn.commit()
    print(f"[Platforms] Indexed {len(to_insert):,} stop platform details.")


def create_lookup_indexes_and_optimize(conn: sqlite3.Connection) -> None:
    """Creates high-performance composite indexes for timetable and stop lookups."""
    cur = conn.cursor()
    print("[Optimize] Creating B-Tree lookup indexes and running VACUUM...")
    cur.executescript(
        """
        CREATE INDEX idx_stops_hub_id ON stops(hub_id);
        CREATE INDEX idx_stops_name ON stops(name COLLATE NOCASE);
        CREATE INDEX idx_station_hubs_norm_name ON station_hubs(normalized_name);
        CREATE INDEX idx_trips_route_id ON trips(route_id);
        CREATE INDEX idx_trips_service_id ON trips(service_id);
        CREATE INDEX idx_stop_times_stop_dep ON stop_times(stop_id, departure_seconds);
        CREATE INDEX idx_stop_times_trip_seq ON stop_times(trip_id, stop_sequence);
        CREATE INDEX idx_calendar_date ON calendar_active_dates(service_date, service_id);
        ANALYZE;
        """
    )
    conn.commit()
    conn.isolation_level = None
    cur.execute("VACUUM;")


def download_file(url: str, target_path: Path) -> Path:
    """Downloads a remote GTFS zip archive with a progress indicator."""
    target_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[Download] Fetching {url} -> {target_path} ...")
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "HungaryPublicTransportTracker/1.0 (GTFS-Builder)"},
    )
    with urllib.request.urlopen(req, timeout=120) as resp, open(
        target_path, "wb"
    ) as out:
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            out.write(chunk)
    size_mb = target_path.stat().st_size / (1024 * 1024)
    print(f"[Download] Completed {target_path.name} ({size_mb:.2f} MB)")
    return target_path


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build indexed SQLite static transit DB (transit_static.db) for BKK & MÁV."
    )
    parser.add_argument(
        "--bkk-zip",
        type=Path,
        default=None,
        help="Path to local budapest_gtfs.zip (if omitted, downloads from official BKK OpenData URL)",
    )
    parser.add_argument(
        "--bkk-url",
        type=str,
        default=BKK_DEFAULT_GTFS_URL,
        help=f"Official BKK GTFS download URL (default: {BKK_DEFAULT_GTFS_URL})",
    )
    parser.add_argument(
        "--mav-zip",
        type=Path,
        default=None,
        help="Path to local mav_gtfs.zip (from MÁV-START developer GTFS portal)",
    )
    parser.add_argument(
        "--mav-url",
        type=str,
        default=None,
        help="Direct download URL for MÁV GTFS zip (if hosted or signed link)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/db/transit_static.db"),
        help="Output SQLite database path (default: assets/db/transit_static.db)",
    )
    parser.add_argument(
        "--window-days",
        type=int,
        default=14,
        help="Number of days of schedule data to retain starting from today (default: 14)",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(".cache/gtfs"),
        help="Cache directory for downloaded GTFS archives",
    )
    args = parser.parse_args()

    window_start = dt.date.today()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()

    bkk_zip_path: Optional[Path] = args.bkk_zip
    if bkk_zip_path is None and args.bkk_url:
        cached_bkk = args.cache_dir / "budapest_gtfs.zip"
        if cached_bkk.exists():
            print(f"[Cache] Using cached BKK GTFS archive at {cached_bkk}")
            bkk_zip_path = cached_bkk
        else:
            bkk_zip_path = download_file(args.bkk_url, cached_bkk)

    mav_zip_path: Optional[Path] = args.mav_zip
    if mav_zip_path is None and args.mav_url:
        cached_mav = args.cache_dir / "mav_gtfs.zip"
        mav_zip_path = download_file(args.mav_url, cached_mav)

    if (bkk_zip_path is None or not bkk_zip_path.exists()) and (
        mav_zip_path is None or not mav_zip_path.exists()
    ):
        print(
            "ERROR: Neither a valid BKK GTFS zip nor a MÁV GTFS zip was provided or downloaded.",
            file=sys.stderr,
        )
        return 1

    conn = sqlite3.connect(str(args.output))
    try:
        create_schema(conn)

        if bkk_zip_path and bkk_zip_path.exists():
            ingest_gtfs_archive(
                conn, bkk_zip_path, "BKK", window_start, args.window_days
            )

        if mav_zip_path and mav_zip_path.exists():
            ingest_gtfs_archive(
                conn, mav_zip_path, "MAV", window_start, args.window_days
            )
        else:
            print(
                "[MAV] Note: No --mav-zip / --mav-url supplied. Proceeding with BKK dataset only."
            )

        build_spatial_index_and_hubs(conn)
        build_stop_platform_details(conn)
        create_lookup_indexes_and_optimize(conn)

        cur = conn.cursor()
        cur.execute(
            "INSERT INTO metadata (key, value) VALUES (?, ?), (?, ?)",
            (
                "built_at_utc",
                dt.datetime.now(dt.timezone.utc).isoformat(),
                "window_start",
                window_start.isoformat(),
            ),
        )
        conn.commit()
    finally:
        conn.close()

    size_mb = args.output.stat().st_size / (1024 * 1024)
    print(f"[Done] Built {args.output} ({size_mb:.2f} MB)")
    if size_mb > 60.0:
        print(
            f"[Warning] Database size ({size_mb:.2f} MB) exceeds the 60 MB target. "
            "Consider reducing --window-days (e.g. --window-days 7)."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
