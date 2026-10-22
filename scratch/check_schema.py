import urllib.request
import json

url = 'https://mavplusz.hu/otp2-backend/otp/routers/default/index/graphql'

q = '''{
  vehiclePositions(
    swLat: 45.70
    swLon: 16.10
    neLat: 48.60
    neLon: 22.95
    modes: [RAIL, RAIL_REPLACEMENT_BUS, SUBURBAN_RAILWAY, TRAMTRAIN]
  ) {
    vehicleId
    trip {
      gtfsId
      tripShortName
      arrivalStoptime {
        arrivalDelay
      }
      stoptimes {
        arrivalDelay
        departureDelay
      }
    }
  }
}'''

req = urllib.request.Request(
    url,
    data=json.dumps({'query': q}).encode('utf-8'),
    headers={'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0'}
)
resp = urllib.request.urlopen(req)
d = json.loads(resp.read().decode('utf-8'))
vps = d.get('data', {}).get('vehiclePositions', [])
print(f"Total vehicles: {len(vps)}")

arr_delays = []
st_delays = []

for v in vps:
    t = v.get('trip') or {}
    arr_d = (t.get('arrivalStoptime') or {}).get('arrivalDelay') or 0
    if arr_d > 0:
        arr_delays.append(arr_d)
    
    # max delay in stoptimes
    st_d_list = [s.get('departureDelay') or s.get('arrivalDelay') or 0 for s in t.get('stoptimes', [])]
    max_st_d = max(st_d_list) if st_d_list else 0
    if max_st_d > 0:
        st_delays.append(max_st_d)

print(f"Vehicles with arrivalStoptime delay > 0: {len(arr_delays)}")
print(f"Vehicles with stoptimes delay > 0: {len(st_delays)}")
if st_delays:
    print(f"Max stoptimes delay: {max(st_delays)} s ({max(st_delays)//60} mins)")
