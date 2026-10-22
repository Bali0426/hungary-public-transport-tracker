import urllib.request, json

# First get a live trip gtfsId from stop 1:005510009 (Keleti)
query = """{
  stop(id: "1:005510009") {
    stoptimesWithoutPatterns(numberOfDepartures: 1) {
      trip {
        gtfsId
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
    print("Pattern geom points count:", len(data['data']['stop']['stoptimesWithoutPatterns'][0]['trip']['pattern']['geometry']))
    for p in data['data']['stop']['stoptimesWithoutPatterns'][0]['trip']['pattern']['geometry'][:5]:
        print(" ", p)
