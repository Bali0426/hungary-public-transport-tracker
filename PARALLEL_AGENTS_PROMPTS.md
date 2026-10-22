# Párhuzamos Agent Promptok (4 Agent – 0% Fájl-ütközés)

Az alábbi **4 agent** fájlszinten **teljesen szeparált** (egyik sem szerkeszti a másik fájljait), így egyszerre, teljesen párhuzamosan elindíthatod őket.
A widget-interfészek és adatmodellek előre rögzítettek, így az agentek munkája azonnal, ütközésmentesen fog együttműködni.

### Fájlkiosztási Mátrix (100% Ütközésmentes)

| Agent | Feladat fókusz | Kizárólagos fájlok (csak ezekhez nyúlhat) |
| :--- | :--- | :--- |
| **Agent 1** | **Vasúti Vágánygeometria Követése & Jármű Útvonal**: Vasúti útvonalak valódi vágánykövetése (ne csak a megállókat kössék össze egyenes vonalakkal!), MÁV és BKK vágányvonal-geometriák integrációja a `vehicleRoutePolylineProvider`-be | `lib/providers/transit_lines_provider.dart`<br>`lib/models/transit_route_geometry.dart`<br>`test/transit_lines_and_route_test.dart` |
| **Agent 2** | **Rust Backend: MÁV Vágánygeometria Lekérdezés & Idő/Menetrend Javítás**: Valós vágánygeometria lekérdezése az OTP2 `pattern { geometry { lat lon } }` végpontról, MÁV érkezési/indulási idők pontossága, multimodális hub vasút+helyi jelölése, DLL fordítás | `rust/src/gtfs_rt/mav.rs`<br>`rust/src/static_db/repository.rs`<br>`rust/src/api.rs`<br>`transit_engine.dll`<br>`windows/runner/transit_engine.dll` |
| **Agent 3** | **StationDetailCard: NOW Hiba Megszűntetése, MÁV vs. BKK Fülek, Strukturált Vasúti Menetrend**: NOW felirat javítása, multimodális csomópontoknál (pl. Nyugati, Keleti, Déli, Kelenföld, Zugló, Kőbánya-Kispest) külön "Vasúti menetrend (MÁV)" és "Helyi járatok (BKK)" fül, tervezett vs valós idő késési színekkel, vonatszám, irány, vágány | `lib/views/widgets/station_detail_card.dart`<br>`lib/views/widgets/map_legend_dialog.dart`<br>`test/station_schedule_and_legend_test.dart` |
| **Agent 4** | **Rétegmenü & UI Egységesítés**: Master toggle a közlekedési módokhoz, metróvonalak pixelhiba javítása, nagyvasút vonalak toggle törlése, OpenRailwayMap stílusválasztó ablak (Infrastructure, Max speeds, Signalling, Electrification, Track gauge) & sötét mód fehér keretének eltávolítása | `lib/views/widgets/map_layers_menu.dart`<br>`lib/views/map_screen.dart`<br>`test/overall_ui_components_test.dart` |

---

## AGENT 1 PROMPT (Vasúti Vágánygeometria Követése & Jármű Útvonal Polyline)

Másold be az **1. Agentnek**:

```markdown
/ponytail full

FONTOS SZABÁLYOK:
1. Kövesd a `ponytail` (level: `full`) elveket: a lehető legkisebb, legtisztább kódmódosítással oldd meg a feladatot, kerüld a túlbonyolítást (YAGNI).
2. A `graphify` szabály alapján: mielőtt kódot olvasol vagy módosítasz, futtasd a `graphify query "vehicleRoutePolylineProvider transit_route_geometry Polyline"` parancsot (vagy használd a `graphify-out/` tudásgráfot), a módosítások végén pedig futtasd le a `graphify update .` parancsot!
3. PÁRHUZAMOS AGENT KORLÁTOZÁS: KIZÁRÓLAG az alábbi fájlokat módosíthatod (más fájlokhoz TILOS hozzányúlni!):
   - `lib/providers/transit_lines_provider.dart`
   - `lib/models/transit_route_geometry.dart`
   - `test/transit_lines_and_route_test.dart`

FELADATOK:

1. **Vasúti útvonalak vágánykövetése (ne csak egyenes vonalakkal kösse össze a megállókat!)**:
   - Jelenleg a `vehicleRoutePolylineProvider` egy vonatra kattintva csak a távoli megállók pontjait kötötte össze egyenes szakaszokkal, ami hegyeken, tavakon és erdőkön vágott át a valódi sínpár helyett.
   - **Vágánykövető útvonal generálása**:
     - Bővítsd a `vehicleRoutePolylineProvider`-t:
       - Ha a jármű MÁV vonat vagy HÉV (vagy ha a megállók távolsága nagyobb pár kilométernél), a pontok összekötése kövesse a valós vasúti pálya vonalvezetését!
       - A `TransitRouteGeometry`-ben definiálj a főbb vasúti korridorokhoz (pl. Budapest – Győr – Hegyeshalom, Budapest – Székesfehérvár – Balaton/Keszthely, Budapest – Debrecen – Nyíregyháza, Budapest – Szeged, Budapest – Pécs, Budapest – Miskolc) és a HÉV vonalakhoz sűrű, valódi vasúti pálya menti koordináta-láncokat.
       - Amikor a vonat megállói ezen korridorok mentén helyezkednek el, a `vehicleRoutePolylineProvider` illessze a megállók közötti szakaszokat a valós vasúti vágány koordináta-pontjaira (vágánygeometria mentén haladó vonal), így a kirajzolt vonal pontosan a síneken fut!
       - Ha van az adott járműhöz közvetlen vágánygeometria (pl. `trip.pattern.geometry`), használja azt közvetlenül.

2. **Nagyvasúti vonalak toggle eltávolításának lekövetése**:
   - A `showRailwayLinesProvider` helyett biztosítsd, hogy a vasúti pálya megjelenítését az OpenRailwayMap csemperéteg és a konkrét járművek aktív vágánykövető vonala szolgálja ki.
   - Tartsd meg a `showOpenRailwayMapProvider`, `showMetroLinesProvider`, `showHevLinesProvider`, `showTramLinesProvider` állapotokat, és egészítsd ki a stílusválasztó providerekkel:
     ```dart
     enum OpenRailwayMapStyle {
       standard,
       maxspeed,
       signals,
       electrification,
       gauge,
     }

     final openRailwayMapStyleProvider = StateProvider<OpenRailwayMapStyle>((ref) => OpenRailwayMapStyle.standard);
     ```

3. **Tesztek frissítése (`test/transit_lines_and_route_test.dart`)**:
   - Írj tesztet, amely igazolja, hogy a `vehicleRoutePolylineProvider` vasúti járat esetén sűrű, vágányt követő pontokat ad vissza (több pontot, mint csupán a megállók száma).

Ellenőrzés a végén:
- Futtasd: `flutter test test/transit_lines_and_route_test.dart`
- Futtasd: `flutter analyze lib/providers/transit_lines_provider.dart lib/models/transit_route_geometry.dart`
- Futtasd: `graphify update .`
```

---

## AGENT 2 PROMPT (Rust Backend: MÁV Vágánygeometria & Idő/Menetrend Pontosítás)

Másold be a **2. Agentnek**:

```markdown
/ponytail full

FONTOS SZABÁLYOK:
1. Kövesd a `ponytail` (level: `full`) elveket: a lehető legkisebb, legtisztább kódmódosítással oldd meg a feladatot, kerüld a túlbonyolítást (YAGNI).
2. A `graphify` szabály alapján: mielőtt kódot olvasol vagy módosítasz, futtasd a `graphify query "fetch_mav_station_departures get_trip_schedule UnifiedDeparture"` parancsot (vagy használd a `graphify-out/` tudásgráfot), a módosítások végén pedig futtasd le a `graphify update .` parancsot!
3. PÁRHUZAMOS AGENT KORLÁTOZÁS: KIZÁRÓLAG az alábbi fájlokat módosíthatod (Flutter UI fájlokhoz, mint `station_detail_card.dart` és `map_screen.dart` TILOS hozzányúlni!):
   - `rust/src/gtfs_rt/mav.rs`
   - `rust/src/static_db/repository.rs`
   - `rust/src/api.rs`
   - `transit_engine.dll` és `windows/runner/transit_engine.dll` (a `cargo build --release` után átmásolva)

FELADATOK:

1. **MÁV Valós Vágánygeometria lekérdezése (`rust/src/gtfs_rt/mav.rs` & `rust/src/api.rs`)**:
   - A MÁV OTP2 GraphQL végpont támogatja a `trip(id: "...") { pattern { geometry { lat lon } } }` lekérdezést, amely a vonat pontos fizikai vágánygeometriáját adja vissza a sínpár mentén!
   - Készíts egy új függvényt a `rust/src/gtfs_rt/mav.rs`-ben és exportáld a `rust/src/api.rs`-ben:
     ```rust
     pub async fn fetch_mav_trip_geometry(client: &Client, trip_id: &str) -> Result<Vec<(f64, f64)>>
     ```
     amely visszaadja a koordinátapárok listáját `Vec<(f64, f64)>` formában.
   - Támogasd a `get_trip_geometry(trip_id: String) -> Result<Vec<CoordinatePoint>>` hívást az API-ban.

2. **MÁV Idők és Késések Pontosítása**:
   - A `fetch_mav_station_departures`-ben biztosítsd, hogy:
     - `scheduled_departure_seconds`, `estimated_departure_seconds`, valamint az érkezési másodpercek és a formázott `HH:MM` sztringek pontosan a valós indulást/érkezést tükrözzék.
     - Ne fordulhasson elő, hogy a késés miatt múltbelinek érzékelt vonat hibás formázást kap.
     - Adja át az eredeti `departure_delay_seconds` és `arrival_delay_seconds` értékeket is tisztán.

3. **Multimodális Állomások (MÁV + BKK) Jelölése**:
   - Biztosítsd, hogy ha egy állomáson MÁV vasút és BKK járatok is megállnak (pl. Keleti, Nyugati, Déli, Kelenföld, Kőbánya-Kispest, Zugló, Ferihegy), a `StopNode` `is_multimodal_hub = true` legyen, és a megálló adatai között mindkét hálózat könnyen szűrhető maradjon.

4. **Fordítás és DLL frissítés**:
   - Futtasd a `cargo test` parancsot a `rust/` mappában.
   - Futtasd a `cargo build --release` parancsot a `rust/` mappában.
   - Másold át a friss `transit_engine.dll` fájlt a gyökérkönyvtárba (`./transit_engine.dll`) és a `windows/runner/transit_engine.dll` mappába!

Ellenőrzés a végén:
- Futtasd: `cargo test`
- Futtasd: `graphify update .`
```

---

## AGENT 3 PROMPT (StationDetailCard: NOW Hiba Javítása, MÁV vs. BKK Fülek & Vasúti Menetrend)

Másold be a **3. Agentnek**:

```markdown
/ponytail full

FONTOS SZABÁLYOK:
1. Kövesd a `ponytail` (level: `full`) elveket: a lehető legkisebb, legtisztább kódmódosítással oldd meg a feladatot, kerüld a túlbonyolítást (YAGNI).
2. A `graphify` szabály alapján: mielőtt kódot olvasol vagy módosítasz, futtasd a `graphify query "StationDetailCard _parseDepartureTime countdownStr"` parancsot (vagy használd a `graphify-out/` tudásgráfot), a módosítások végén pedig futtasd le a `graphify update .` parancsot!
3. PÁRHUZAMOS AGENT KORLÁTOZÁS: KIZÁRÓLAG az alábbi fájlokat módosíthatod (a `map_screen.dart` és `map_layers_menu.dart` fájlokhoz TILOS hozzányúlni!):
   - `lib/views/widgets/station_detail_card.dart`
   - `lib/views/widgets/map_legend_dialog.dart`
   - `test/station_schedule_and_legend_test.dart`

FELADATOK:

1. **A "NOW" Hiba Végleges Megszüntetése a Vasútállomásoknál**:
   - **Hiba oka**: A `_parseDepartureTime` és a `countdownStr = diffMin <= 0 ? 'NOW' : '$diffMin\''` miatt bármilyen késésben lévő vonat (aminek a menetrendi ideje korábbi mint a jelenlegi pillanat, pl. 21:04 a 22:30-as időponthoz képest), vagy a reggeli/napközbeni járatok azonnal "NOW"-vá váltak!
   - **Javítás**:
     - Vasúti menetrendnél (és alapértelmezetten a járatoknál) **NE írj mindenhova NOW-t**!
     - Különítsd el a valóban ebben a percben induló járatokat (`0 <= diffMin <= 1` esetén írhat ki `NOW` vagy `Azonnal`), a késésben lévő járatoknál pedig a **valós idejű indulási/érkezési időt** és a **késés mértékét** írd ki (pl. `21:35 (+31')`)!
     - Ha a menetrendi idő eltelt, de van valós becsült idő (`estimatedTimeFormatted`), azt mutassa, a menetrendi időt pedig húzza át fölötte!

2. **Részletes, Strukturált Vasúti Menetrendi Megjelenítés**:
   - A MÁV vonatok kártya-sorai legyenek professzionálisan strukturálva az alábbi adatokkal:
     1. **Vonat azonosító és név**: Vonatszám és típus/név kiemelve (pl. `IC 618 NYÍRSÉG`, `S10 4412`, `RJ 62`).
     2. **Irány / Viszonylat**: Tisztán kiírva a célállomás (Indulásoknál) vagy a kiindulási állomás (Érkezéseknél).
     3. **Tervezett és Valós idő**: Tervezett idő (ha késik, áthúzva: `~~21:04~~`), mellette/alatta a valós becsült idő a késési színnel színezve (zöld ha pontos, sárga ha 2-5 perc, piros ha 5+ perc).
     4. **Késés jelzése**: `+15 perc késés` piros/sárga badge.
     5. **Vágányszám / Peron**: Tisztán és jól láthatóan kiírva (`4. vágány` vagy `Vágány: 4`).

3. **Multimodális Csomópontoknál Külön Fülek: "Vasúti menetrend (MÁV)" és "Helyi járatok (BKK)"**:
   - Olyan állomásoknál, ahol vasútállomás is van (pl. Budapest-Keleti, Nyugati, Déli, Kelenföld, Kőbánya-Kispest, Zugló, Ferihegy, Debrecen stb.):
     - Helyezz el egy elegáns szűrőt / fület a kártya tetején:
       - **[Összes járat]**
       - **[Vasúti menetrend (MÁV)]** (csak a nagyvasúti vonatok látszanak)
       - **[Helyi járatok (BKK)]** (csak a metró, villamos, busz, troli látszik)
     - A felhasználó így egyetlen kattintással válthat a vonatok és a csatlakozó helyi BKK járatok között!

4. **UI Egységesítése**:
   - Hangold össze a betűméreteket, paddingokat és ikonokat a Material 3 BudapestGO dizájnnal.

Ellenőrzés a végén:
- Futtasd: `flutter test test/station_schedule_and_legend_test.dart`
- Futtasd: `flutter analyze lib/views/widgets/station_detail_card.dart`
- Futtasd: `graphify update .`
```

---

## AGENT 4 PROMPT (Rétegmenü Újradolgozása, Master Toggle, Metró Pixelhiba & OpenRailwayMap Stílusválasztó)

Másold be a **4. Agentnek**:

```markdown
/ponytail full

FONTOS SZABÁLYOK:
1. Kövesd a `ponytail` (level: `full`) elveket: a lehető legkisebb, legtisztább kódmódosítással oldd meg a feladatot, kerüld a túlbonyolítást (YAGNI).
2. A `graphify` szabály alapján: mielőtt kódot olvasol vagy módosítasz, futtasd a `graphify query "MapLayersFloatingMenu showOpenRailwayMapProvider TileLayer"` parancsot (vagy használd a `graphify-out/` tudásgráfot), a módosítások végén pedig futtasd le a `graphify update .` parancsot!
3. PÁRHUZAMOS AGENT KORLÁTOZÁS: KIZÁRÓLAG az alábbi fájlokat módosíthatod (más fájlokhoz TILOS hozzányúlni!):
   - `lib/views/widgets/map_layers_menu.dart`
   - `lib/views/map_screen.dart`
   - `test/overall_ui_components_test.dart`

FELADATOK:

1. **Metróvonalak Pixelhiba Javítása (`lib/views/widgets/map_layers_menu.dart`)**:
   - A `map_layers_menu.dart:373` sor körül a `Row`-ban lévő `Text('Metróvonalak')` és a 4 metró petty (`_metroDot`) vízszintesen túlcsordul (`RenderFlex OVERFLOWING by 7.5 px`).
   - Javítsd ki: a feliratot és a pettyeket rendezd el tördelhetően (`Wrap` vagy `Column`/`subtitle`, vagy a pettyeket rakd a cím alá/mellé `Flexible` használatával), hogy semmilyen képernyőméretnél ne legyen pixelhiba!

2. **Nagyvasúti vonalak toggle törlése**:
   - Töröld a "Vasúti vonalak" (`showRailwayLines`) toggle kapcsolót a menüből a felhasználói kérésnek megfelelően. A vasúti pályát az OpenRailwayMap és az aktív vonatok vágánygeometriája képviseli.

3. **Master Toggle a Közlekedési Módokhoz**:
   - A "KÖZLEKEDÉSI MÓDOK" szekció fölé/elejére helyezz el egy **Master Toggle-t ("Összes jármű / Mind")**, amely pontosan ugyanakkora kártya és ugyanazt a stílust követi, mint az egyedi mód kapcsolók:
     - Ikon: `Icons.select_all` vagy `Icons.all_inclusive`.
     - Értéke: `true`, ha mind a 7 mód be van kapcsolva; `false`, ha bármelyik ki van kapcsolva.
     - Megnyomásakor: ha bekapcsolják, mind a 7 módot bekapcsolja (`enabledTransitModesProvider`); ha kikapcsolják, mindet lekapcsolja (vagy az alapértelmezett állapotra állítja).

4. **OpenRailwayMap Nem OSM – Külön Stílusválasztó Ablak & Sötét Mód Javítás**:
   - Az OpenRailwayMap nem OSM megállócsoport! Helyezz el neki egy kiemelt gombot / kártyát a menüben: **"OpenRailwayMap Vasúti Térkép"**.
   - Rákattintva nyisson meg egy elegáns külön felugró modális kártyát / ablakot (vagy dedikált választó panelt):
     - **"Select a map style:"**
       1. **Infrastructure (Vasúti pálya)**: `https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png`
       2. **Max speeds (Pályasebesség)**: `https://{s}.tiles.openrailwaymap.org/maxspeed/{z}/{x}/{y}.png`
       3. **Signalling and train protection (Jelzők & Biztosítóberendezés)**: `https://{s}.tiles.openrailwaymap.org/signals/{z}/{x}/{y}.png`
       4. **Electrification (Villamosítás)**: `https://{s}.tiles.openrailwaymap.org/electrification/{z}/{x}/{y}.png`
       5. **Track gauge (Nyomtáv)**: `https://{s}.tiles.openrailwaymap.org/gauge/{z}/{x}/{y}.png`
     - És egy fő ki/bekapcsoló gombot.
   - **Sötét mód fehér keretének leszedése**:
     - Sötét módban a csempék ne kapjanak fehér keretet vagy hátteret! A `TileLayer` háttere legyen tiszta átlátszó (`backgroundColor: Colors.transparent`), és ha szükséges, a sötét térkép filteréhez illeszkedve jelenjen meg fekete háttérrel és éles vágányokkal.

5. **Tesztek és Fordítás**:
   - Frissítsd a `test/overall_ui_components_test.dart` teszteket a javított menü elrendezésre.

Ellenőrzés a végén:
- Futtasd: `flutter test test/overall_ui_components_test.dart`
- Futtasd: `flutter analyze lib/views/widgets/map_layers_menu.dart lib/views/map_screen.dart`
- Futtasd: `graphify update .`
```
