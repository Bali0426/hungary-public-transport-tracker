import sqlite3

conn = sqlite3.connect('assets/db/transit_static.db')
c = conn.cursor()

c.execute("""
    SELECT s.name, s.lat, s.lon, st.stop_sequence
    FROM routes r
    JOIN trips t ON t.route_id = r.id
    JOIN stop_times st ON st.trip_id = t.id
    JOIN stops s ON s.id = st.stop_id
    WHERE r.short_name = 'M1'
    GROUP BY st.stop_sequence, s.name, s.lat, s.lon
    ORDER BY st.stop_sequence
    LIMIT 20
""")
for row in c.fetchall():
    print(row)
