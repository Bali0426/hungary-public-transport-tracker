import urllib.request, json

def test_board(stop_id):
    clean_id = stop_id.replace("MAV:", "")
    query = f"""{{
      stop(id: "{clean_id}") {{
        name
        stoptimesWithoutPatterns(numberOfDepartures: 10) {{
          scheduledDeparture
          realtimeDeparture
          departureDelay
          scheduledArrival
          realtimeArrival
          arrivalDelay
          realtime
          trip {{
            gtfsId
            tripShortName
            tripHeadsign
            domesticResTrainNumber
            route {{
              shortName
              longName
            }}
          }}
          stop {{
            name
            platformCode
          }}
        }}
      }}
    }}"""
    req = urllib.request.Request(
        'https://mavplusz.hu/otp2-backend/otp/routers/default/index/graphql',
        data=json.dumps({'query': query}).encode('utf-8'),
        headers={'Content-Type': 'application/json', 'Origin': 'https://mavplusz.hu', 'Referer': 'https://mavplusz.hu/'}
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        st = data['data']['stop']
        if not st:
            print("Stop not found:", stop_id)
            return
        print(f"Station: {st['name']}")
        for dep in st['stoptimesWithoutPatterns'][:6]:
            dep_s = dep.get('scheduledDeparture') or dep.get('scheduledArrival') or 0
            h = (dep_s // 3600) % 24
            m = (dep_s % 3600) // 60
            sched_str = f"{h:02d}:{m:02d}"
            delay = (dep.get('departureDelay') or dep.get('arrivalDelay') or 0) // 60
            plat = dep.get('stop', {}).get('platformCode') or '-'
            headsign = dep.get('trip', {}).get('tripHeadsign') or ''
            tname = dep.get('trip', {}).get('tripShortName') or dep.get('trip', {}).get('domesticResTrainNumber') or 'Vonat'
            delay_str = f"+{delay}'" if delay > 0 else "Pontos"
            print(f"  [{sched_str}] ({delay_str}) {tname} -> {headsign} (Vagany: {plat})")

print("Testing Debrecen:")
test_board("1:005513912_0")

print("\nTesting Szeged:")
test_board("1:005517228_0")

print("\nTesting Pécs:")
test_board("1:005507294_0")
