import urllib.request, json

query = """{
  stop(id: "1:005510009") {
    name
    stoptimesWithoutPatterns(numberOfDepartures: 1) {
      scheduledDeparture
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
    print(json.dumps(data, indent=2))
