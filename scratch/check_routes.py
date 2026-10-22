import sqlite3

conn = sqlite3.connect('assets/db/transit_static.db')
c = conn.cursor()

c.execute("""
    SELECT r.short_name, r.route_type, r.route_color, count(distinct t.id)
    FROM routes r
    JOIN trips t ON t.route_id = r.id
    WHERE r.short_name IN ('M1', 'M2', 'M3', 'M4', 'H5', 'H6', 'H7', 'H8', 'H9')
    GROUP BY r.short_name, r.route_type, r.route_color
""")
print("Metro and HEV routes:")
for row in c.fetchall():
    print(" ", row)

c.execute("""
    SELECT r.route_type, count(distinct r.id)
    FROM routes r
    GROUP BY r.route_type
""")
print("Route types:")
for row in c.fetchall():
    print(" ", row)
