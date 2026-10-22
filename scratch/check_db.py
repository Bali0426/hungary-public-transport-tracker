import sqlite3

conn = sqlite3.connect('assets/db/transit_static.db')
c = conn.cursor()

c.execute("SELECT count(*) FROM stops")
print("Total stops:", c.fetchone()[0])

c.execute("SELECT DISTINCT operator_type FROM stops")
print("Operators:", c.fetchall())

c.execute("SELECT id, name, lat, lon, operator_type FROM stops WHERE operator_type = 'MAV' LIMIT 15")
print("MAV stops:")
for r in c.fetchall():
    print(" ", r)

c.execute("SELECT id, name, lat, lon, operator_type FROM stops WHERE name LIKE '%Debrecen%' OR name LIKE '%Győr%' OR name LIKE '%Szeged%' OR name LIKE '%Pécs%'")
print("Rural search:")
for r in c.fetchall():
    print(" ", r)

c.execute("SELECT count(*) FROM stops WHERE operator_type = 'MAV'")
print("Total MAV stops in db:", c.fetchone()[0])
