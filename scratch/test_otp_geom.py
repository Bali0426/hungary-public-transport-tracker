import urllib.request, json

# Test if OTP2 has trip/pattern geometry
query = """{
  trip(id: "1:000586") {
    gtfsId
    tripHeadsign
    pattern {
      geometry {
        points
      }
    }
    stops {
      name
      lat
      lon
    }
  }
}"""

req = urllib.request.Request(
    'https://mavplusz.hu/otp2-backend/otp/routers/default/index/graphql',
    data=json.dumps({'query': query}).encode('utf-8'),
    headers={'Content-Type': 'application/json', 'Origin': 'https://mavplusz.hu', 'Referer': 'https://mavplusz.hu/'}
)

try:
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        print("Response:", json.dumps(data, indent=2)[:500])
except Exception as e:
    print("Error:", e)
