import urllib.request, json

query = """{
  stop(id: "1:005513912_0") {
    name
    stoptimesWithoutPatterns(numberOfDepartures: 1) {
      trip {
        gtfsId
        tripShortName
        pattern {
          geometry {
            lat
            lon
          }
        }
      }
    }
  }
}"""

req = urllib.request.Request(
    'https://mavplusz.hu/otp2-backend/otp/routers/default/index/graphql',
    data=json.dumps({'query': query}).encode('utf-8'),
    headers={'Content-Type': 'application/json', 'Origin': 'https://mavplusz.hu', 'Referer': 'https://mavplusz.hu/'}
)

with urllib.request.urlopen(req, timeout=10) as resp:
    data = json.loads(resp.read().decode('utf-8'))
    dep = data['data']['stop']['stoptimesWithoutPatterns'][0]
    trip = dep['trip']
    geom = trip['pattern']['geometry']
    print("Trip:", trip['gtfsId'], trip['tripShortName'])
    print("Total pattern geometry points along the tracks:", len(geom))
    print("First 3 points:", geom[:3])
    print("Last 3 points:", geom[-3:])
