# Hungary Public Transport Tracker (MÁV + BKK)

Client-only multimodal transit tracker for **BKK** (Budapest public transport) and **MÁV** (Hungarian State Railways), built with **Flutter (MapLibre GL)** and a **Rust Native Engine (FFI + SQLite R-Tree + Prost GTFS-RT)**.

## Architecture

- **Offline Static Database (`scripts/build_gtfs_db.py`)**: Downloads/ingests official BKK (`budapest_gtfs.zip`) and MÁV (`mav_gtfs.zip`) schedules, prunes inactive services outside a 14-day window, builds an SQLite R-Tree spatial index (`stops_rtree`), and clusters multimodal transfer stations within 150 meters (`station_hubs`).
- **Rust Native Engine (`rust/`)**:
  - `src/gtfs_rt/bkk.rs`: Non-blocking `reqwest` + `prost` decoder for BKK FUTÁR `VehiclePositions.pb` and `TripUpdates.pb`.
  - `src/gtfs_rt/mav.rs`: Supports both Hungarian National Access Point (NAP) GTFS-RT Protobuf feeds and the live MÁV EMMA OTP2 GraphQL vehicle positions API.
  - `src/static_db/`: Pooled `r2d2` + `rusqlite` queries, R-Tree viewport lookups, and MapLibre GeoJSON serialization.
- **Flutter Shell (`lib/`)**:
  - Riverpod state providers (`lib/providers/`), C-ABI FFI bridge (`lib/bridge/bridge_generated.dart`), GPU-accelerated MapLibre GL map (`lib/views/map_screen.dart`), multimodal stop search (`lib/views/line_search_delegate.dart`), and unified departure boards (`lib/views/station_detail_sheet.dart`).

## Quick Start

### 1. Build the Static SQLite Database (`assets/db/transit_static.db`)
```powershell
# Automatically downloads official BKK GTFS and builds the indexed SQLite DB:
python scripts/build_gtfs_db.py

# Include a local MÁV GTFS archive (from https://www.mavcsoport.hu/mav-szemelyszallitas/belfoldi-utazas/fejlesztoknek-gtfs):
python scripts/build_gtfs_db.py --mav-zip path/to/mav_gtfs.zip
```

### 2. Build & Test the Rust Engine
```powershell
cargo test --manifest-path rust/Cargo.toml
cargo build --release --manifest-path rust/Cargo.toml
```

### 3. Run the Flutter App
```powershell
flutter pub get
flutter run -d windows --dart-define=BKK_API_KEY=your_bkk_futar_api_key
```