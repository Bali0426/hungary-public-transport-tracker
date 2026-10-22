import urllib.request, json

query = """{
  __type(name: "Coordinates") {
    fields {
      name
      type {
        name
        kind
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
