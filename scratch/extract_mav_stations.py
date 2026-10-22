import urllib.request, json, sqlite3

# Fetch stops from OTP2
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

# Filter MAV rail stations (gtfsId starts with '1:0055' or '1:' in Hungary)
mav_stations = {}
for s in stops:
    gid = s['gtfsId']
    if not gid.startswith('1:'):
        continue
    # Only keep Hungarian stations (lat between 45.7 and 48.6, lon between 16.0 and 22.9)
    lat, lon = s['lat'], s['lon']
    if not (45.7 <= lat <= 48.6 and 16.0 <= lon <= 22.9):
        continue
    name = s['name'].strip()
    # Normalize station by name and approximate location
    key = (name.lower(), round(lat, 3), round(lon, 3))
    if key not in mav_stations:
        # Canonical id: use the base station id ending in _0 if available
        mav_stations[key] = {
            'id': f"MAV:{gid}",
            'name': name,
            'lat': lat,
            'lon': lon,
            'raw_id': gid,
        }

print(f"Found {len(mav_stations)} unique MÁV rail stations in Hungary.")
sample = list(mav_stations.values())[:10]
for s in sample:
    print(" ", s['name'].encode('ascii', 'replace').decode(), s['id'], s['lat'], s['lon'])
