import urllib.request, json

# Bounding box for Hungary: lat 45.7 to 48.6, lon 16.0 to 23.0
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

with urllib.request.urlopen(req, timeout=15) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    stops = data['data']['stopsByBbox']
    mav_rail = [s for s in stops if s['gtfsId'].startswith('1:')]
    print(f"Total stops in bbox: {len(stops)}, MÁV rail stops: {len(mav_rail)}")
    for s in mav_rail[:10]:
        print(" ", s['gtfsId'], s['name'].encode('ascii', 'replace').decode(), s['lat'], s['lon'])
