import json
import math
import re
import sqlite3
from collections import defaultdict, deque

DB_PATH = "assets/db/transit_static.db"
OUT_JSON_PATH = "assets/db/stop_groups_prebaked.json"
BUFFER_METERS = 20.0

RE_M_PLUS_H = re.compile(r"\s+M\+H\b", re.IGNORECASE)
RE_M = re.compile(r"\s+M\b")
RE_H = re.compile(r"\s+H\b")


def clean_station_name(name: str) -> str:
    s = name.strip()
    if s.endswith(")"):
        idx = s.rfind("(")
        if idx != -1:
            s = s[:idx].strip()
    if s.endswith("]"):
        idx = s.rfind("[")
        if idx != -1:
            s = s[:idx].strip()
    s = RE_M_PLUS_H.sub("", s)
    s = RE_M.sub("", s)
    s = RE_H.sub("", s)
    res = s.strip()
    return res if res else name.strip()


def distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    d_lat = (lat1 - lat2) * 111133.0
    d_lon = (lon1 - lon2) * 75150.0
    return math.sqrt(d_lat * d_lat + d_lon * d_lon)


def convex_hull_2d(points):
    pts = sorted(points, key=lambda p: (p[0], p[1]))
    unique = []
    for p in pts:
        if not unique or abs(unique[-1][0] - p[0]) > 1e-6 or abs(unique[-1][1] - p[1]) > 1e-6:
            unique.append(p)
    if len(unique) <= 2:
        return unique

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower = []
    for p in unique:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)

    upper = []
    for p in reversed(unique):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)

    return lower[:-1] + upper[:-1]


def create_buffered_convex_hull(stops, buffer_m: float = BUFFER_METERS):
    if not stops:
        return []
    unique_stops = []
    for s in stops:
        if not any(abs(u["lat"] - s["lat"]) < 1e-5 and abs(u["lon"] - s["lon"]) < 1e-5 for u in unique_stops):
            unique_stops.append(s)
    if len(unique_stops) < 2:
        return []

    center_lat = sum(s["lat"] for s in unique_stops) / len(unique_stops)
    center_lon = sum(s["lon"] for s in unique_stops) / len(unique_stops)
    lat_rad = center_lat * math.pi / 180.0
    meters_per_deg_lat = 111132.954 - 559.822 * math.cos(2.0 * lat_rad)
    meters_per_deg_lon = 111412.84 * math.cos(lat_rad)

    pts = [
        ((s["lon"] - center_lon) * meters_per_deg_lon, (s["lat"] - center_lat) * meters_per_deg_lat)
        for s in unique_stops
    ]

    hull = [pts[0], pts[1]] if len(pts) == 2 else convex_hull_2d(pts)
    if len(hull) < 2:
        return []

    buffered_pts = []
    n = len(hull)
    if n == 2:
        p1, p2 = hull[0], hull[1]
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        dist = math.sqrt(dx * dx + dy * dy)
        if dist < 1e-4:
            return []
        angle_base = math.atan2(dy, dx)
        for i in range(9):
            a = angle_base - math.pi / 2.0 + (i / 8.0) * math.pi
            buffered_pts.append((p2[0] + buffer_m * math.cos(a), p2[1] + buffer_m * math.sin(a)))
        for i in range(9):
            a = angle_base + math.pi / 2.0 + (i / 8.0) * math.pi
            buffered_pts.append((p1[0] + buffer_m * math.cos(a), p1[1] + buffer_m * math.sin(a)))
    else:
        for i in range(n):
            prev_pt = hull[(i - 1 + n) % n]
            curr_pt = hull[i]
            next_pt = hull[(i + 1) % n]

            d1x = curr_pt[0] - prev_pt[0]
            d1y = curr_pt[1] - prev_pt[1]
            len1 = math.sqrt(d1x * d1x + d1y * d1y)
            n1x = d1y / len1 if len1 > 1e-4 else 0.0
            n1y = -d1x / len1 if len1 > 1e-4 else 0.0

            d2x = next_pt[0] - curr_pt[0]
            d2y = next_pt[1] - curr_pt[1]
            len2 = math.sqrt(d2x * d2x + d2y * d2y)
            n2x = d2y / len2 if len2 > 1e-4 else 0.0
            n2y = -d2x / len2 if len2 > 1e-4 else 0.0

            a1 = math.atan2(n1y, n1x)
            a2 = math.atan2(n2y, n2x)
            while a2 < a1:
                a2 += 2.0 * math.pi

            steps = 3
            for s_idx in range(steps + 1):
                t = s_idx / steps
                a = a1 + t * (a2 - a1)
                buffered_pts.append((curr_pt[0] + buffer_m * math.cos(a), curr_pt[1] + buffer_m * math.sin(a)))

    return [
        [round(center_lat + (p[1] / meters_per_deg_lat), 6), round(center_lon + (p[0] / meters_per_deg_lon), 6)]
        for p in buffered_pts
    ]


def main():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    # Load all active stops with their hub metadata
    cur.execute(
        """
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
        FROM stops s
        LEFT JOIN station_hubs h ON h.hub_id = s.hub_id
        WHERE s.operator_type = 'MAV'
           OR EXISTS (SELECT 1 FROM stop_times st WHERE st.stop_id = s.id LIMIT 1)
        """
    )
    rows = cur.fetchall()

    # Group stops by clean station name (or hub_id), clustering stops within 220m
    by_clean_name = defaultdict(list)
    for r in rows:
        stop = {
            "id": r[0],
            "hub_id": r[1],
            "name": r[2],
            "clean_name": clean_station_name(r[2]),
            "lat": float(r[3]),
            "lon": float(r[4]),
            "op": r[5],
            "platform_code": r[6],
            "is_mm": bool(r[8]),
        }
        by_clean_name[stop["clean_name"].lower()].append(stop)

    clusters = []
    for _, group_stops in by_clean_name.items():
        n = len(group_stops)
        if n == 1:
            clusters.append(group_stops)
            continue

        # Connected components within 220m (or same non-empty hub_id within 400m)
        adj = [[] for _ in range(n)]
        for i in range(n):
            for j in range(i + 1, n):
                dist = distance_meters(
                    group_stops[i]["lat"],
                    group_stops[i]["lon"],
                    group_stops[j]["lat"],
                    group_stops[j]["lon"],
                )
                same_hub = (
                    group_stops[i]["hub_id"]
                    and group_stops[i]["hub_id"] == group_stops[j]["hub_id"]
                )
                if dist <= 220.0 or (same_hub and dist <= 400.0):
                    adj[i].append(j)
                    adj[j].append(i)

        visited = [False] * n
        for i in range(n):
            if not visited[i]:
                comp = []
                q = deque([i])
                visited[i] = True
                while q:
                    curr = q.popleft()
                    comp.append(group_stops[curr])
                    for nb in adj[curr]:
                        if not visited[nb]:
                            visited[nb] = True
                            q.append(nb)
                clusters.append(comp)

    records = []
    for comp in clusters:
        comp.sort(key=lambda x: x["id"])
        first = comp[0]
        c_name = first["clean_name"]
        c_lat = sum(s["lat"] for s in comp) / len(comp)
        c_lon = sum(s["lon"] for s in comp) / len(comp)
        has_mav = any(s["op"] == "MAV" for s in comp)
        has_bkk = any(s["op"] != "MAV" for s in comp)
        n_lower = c_name.lower()
        is_mm = (
            any(s["is_mm"] for s in comp)
            or (has_mav and has_bkk)
            or len(comp) > 1
            or any(
                kw in n_lower
                for kw in (
                    "keleti",
                    "nyugati",
                    "déli",
                    "kelenföld",
                    "kőbánya-kispest",
                    "zugló",
                    "ferihegy",
                    "pályaudvar",
                    "vasútállomás",
                )
            )
        )
        op = "MAV" if (has_mav and not has_bkk) else "BKK"
        hub_id = first["hub_id"] or first["id"]
        poly = create_buffered_convex_hull(comp, BUFFER_METERS) if len(comp) >= 2 else []

        if poly:
            min_lat = min(p[0] for p in poly)
            max_lat = max(p[0] for p in poly)
            min_lon = min(p[1] for p in poly)
            max_lon = max(p[1] for p in poly)
        else:
            min_lat = max_lat = c_lat
            min_lon = max_lon = c_lon

        records.append(
            {
                "id": hub_id,
                "name": c_name,
                "lat": round(c_lat, 6),
                "lon": round(c_lon, 6),
                "op": op,
                "mm": 1 if is_mm else 0,
                "count": len(comp),
                "minLat": round(min_lat, 6),
                "maxLat": round(max_lat, 6),
                "minLon": round(min_lon, 6),
                "maxLon": round(max_lon, 6),
                "poly": poly,
            }
        )

    # Also store in SQLite table `stop_group_geometries` as requested
    cur.execute("DROP TABLE IF EXISTS stop_group_geometries")
    cur.execute(
        """
        CREATE TABLE stop_group_geometries (
            hub_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            centroid_lat REAL NOT NULL,
            centroid_lon REAL NOT NULL,
            operator_type TEXT NOT NULL,
            is_multimodal INTEGER NOT NULL,
            stop_count INTEGER NOT NULL,
            polygon_geojson TEXT NOT NULL,
            min_lat REAL NOT NULL,
            max_lat REAL NOT NULL,
            min_lon REAL NOT NULL,
            max_lon REAL NOT NULL
        )
        """
    )
    cur.execute(
        "CREATE INDEX idx_stop_group_geom_bbox ON stop_group_geometries (min_lat, max_lat, min_lon, max_lon)"
    )

    for idx, rec in enumerate(records):
        unique_key = f"{rec['id']}_{idx}" if any(r["id"] == rec["id"] for r in records[:idx]) else rec["id"]
        rec["id"] = unique_key
        cur.execute(
            """
            INSERT INTO stop_group_geometries (
                hub_id, name, centroid_lat, centroid_lon, operator_type,
                is_multimodal, stop_count, polygon_geojson,
                min_lat, max_lat, min_lon, max_lon
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                rec["id"],
                rec["name"],
                rec["lat"],
                rec["lon"],
                rec["op"],
                rec["mm"],
                rec["count"],
                json.dumps(rec["poly"], separators=(",", ":")),
                rec["minLat"],
                rec["maxLat"],
                rec["minLon"],
                rec["maxLon"],
            ),
        )
    conn.commit()
    conn.close()

    with open(OUT_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, separators=(",", ":"))

    multi_count = sum(1 for r in records if len(r["poly"]) >= 3)
    print(f"Pre-baked {len(records)} stop groups ({multi_count} with buffered convex hulls) -> {OUT_JSON_PATH}")


if __name__ == "__main__":
    main()
