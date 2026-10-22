import sqlite3, json, urllib.request

db_path = 'assets/db/transit_static.db'
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Check current count
cur.execute("SELECT count(*) FROM stops")
print("Stops before:", cur.fetchone()[0])
cur.execute("SELECT count(*) FROM stops WHERE operator_type = 'MAV'")
print("MAV stops before:", cur.fetchone()[0])

# Fetch MAV stations from OTP2
query = """{
  stopsByBbox(minLat: 45.7, minLon: 16.0, maxLat: 48.6, maxLon: 23.0) {
    gtfsId
    name
    lat
    lon
  }
}"""

req = urllib.request.Request(
    'https://mavplusz.hu/otp2-backend/otp/routers/default/index/graphql',
    data=json.dumps({'query': query}).encode('utf-8'),
    headers={'Content-Type': 'application/json', 'Origin': 'https://mavplusz.hu', 'Referer': 'https://mavplusz.hu/'}
)

with urllib.request.urlopen(req, timeout=20) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    stops = data['data']['stopsByBbox']

# Filter MAV rail stations (gtfsId starts with '1:') in Hungary
mav_stations = {}
for s in stops:
    gid = s['gtfsId']
    if not gid.startswith('1:'):
        continue
    lat, lon = s['lat'], s['lon']
    if not (45.7 <= lat <= 48.6 and 16.0 <= lon <= 22.9):
        continue
    name = s['name'].strip()
    key = (name.lower(), round(lat, 3), round(lon, 3))
    if key not in mav_stations:
        mav_stations[key] = {
            'id': f"MAV:{gid}",
            'name': name,
            'lat': lat,
            'lon': lon,
            'hub_id': f"HUB:MAV_{gid}",
        }

print(f"Inserting {len(mav_stations)} MAV stations...")
inserted = 0
for s in mav_stations.values():
    # Insert station hub
    cur.execute("""
        INSERT OR IGNORE INTO station_hubs (hub_id, name, normalized_name, lat, lon, has_bkk, has_mav)
        VALUES (?, ?, ?, ?, ?, 0, 1)
    """, (s['hub_id'], s['name'], s['name'].lower(), s['lat'], s['lon']))

    # Insert stop
    try:
        cur.execute("""
            INSERT OR IGNORE INTO stops (id, name, lat, lon, operator_type, hub_id, platform_code)
            VALUES (?, ?, ?, ?, 'MAV', ?, NULL)
        """, (s['id'], s['name'], s['lat'], s['lon'], s['hub_id']))

        # Get rowid for rtree
        rowid = cur.lastrowid
        if rowid and rowid > 0:
            cur.execute("""
                INSERT OR IGNORE INTO stops_rtree (id, min_lat, max_lat, min_lon, max_lon)
                VALUES (?, ?, ?, ?, ?)
            """, (rowid, s['lat'], s['lat'], s['lon'], s['lon']))
            inserted += 1
    except Exception as e:
        pass

conn.commit()

cur.execute("SELECT count(*) FROM stops")
print("Stops after:", cur.fetchone()[0])
cur.execute("SELECT count(*) FROM stops WHERE operator_type = 'MAV'")
print("MAV stops after:", cur.fetchone()[0])

# Verify search for Debrecen, Győr, Pécs, Szeged
for test_name in ['Debrecen', 'Győr', 'Pécs', 'Szeged', 'Siófok', 'Miskolc']:
    cur.execute("SELECT id, name, lat, lon FROM stops WHERE name LIKE ? AND operator_type = 'MAV'", (f"%{test_name}%",))
    rows = cur.fetchall()
    print(f"Found {len(rows)} MAV stops for '{test_name}'")

conn.close()
print("Done!")
