import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/bridge/bridge_generated.dart';
import 'package:hungary_public_transport_tracker/providers/timetable_provider.dart';
import 'package:hungary_public_transport_tracker/views/widgets/map_legend_dialog.dart';
import 'package:hungary_public_transport_tracker/views/widgets/station_detail_card.dart';

void main() {
  group('StationDetailCard Arrivals and Departures Separation', () {
    const testStation = StopNode(
      id: 'BKK_F01234',
      name: 'Szeged vasútállomás',
      lat: 46.253,
      lon: 20.141,
      operator: Operator.mav,
      isMultimodalHub: false,
      vehicleType: 'train',
      platformCode: '2',
    );

    final dep1Departing = UnifiedDeparture(
      tripId: 'TRIP_1',
      stopId: 'BKK_F01234',
      operator: Operator.mav,
      lineName: 'IC 718 NAPFÉNY',
      headsign: 'Budapest-Nyugati',
      routeColor: '003B7A',
      routeTextColor: 'FFFFFF',
      scheduledDepartureSeconds: 50400,
      scheduledTimeFormatted: '14:00',
      delaySeconds: 900, // 15 min delay
      estimatedDepartureSeconds: 51300,
      estimatedTimeFormatted: '14:15',
      isRealtime: true,
      platformCode: '4',
    );

    final dep2Terminating = UnifiedDeparture(
      tripId: 'TRIP_2',
      stopId: 'BKK_F01234',
      operator: Operator.mav,
      lineName: 'IC 702 TORONTÁL',
      headsign: 'Szeged vasútállomás',
      routeColor: '003B7A',
      routeTextColor: 'FFFFFF',
      scheduledDepartureSeconds: 51000,
      scheduledTimeFormatted: '14:10',
      delaySeconds: 0,
      estimatedDepartureSeconds: 51000,
      estimatedTimeFormatted: '14:10',
      isRealtime: true,
      platformCode: '2',
    );

    final dep3ArrivingWithOrigin = UnifiedDeparture(
      tripId: 'TRIP_3',
      stopId: 'BKK_F01234',
      operator: Operator.mav,
      lineName: 'IR 85',
      headsign: 'Szeged',
      routeColor: '003B7A',
      routeTextColor: 'FFFFFF',
      scheduledDepartureSeconds: 49800,
      scheduledTimeFormatted: '13:50',
      delaySeconds: 180,
      estimatedDepartureSeconds: 49980,
      estimatedTimeFormatted: '13:53',
      isRealtime: true,
      platformCode: '1',
    );

    dep3ArrivingWithOrigin.originStation = 'Kiskunfélegyháza';
    dep3ArrivingWithOrigin.estimatedArrivalTimeFormatted = '13:55';

    final mockDepartures = [
      dep1Departing,
      dep2Terminating,
      dep3ArrivingWithOrigin,
    ];

    testWidgets('Departures mode (_showArrivals == false) filters out terminating trips and displays MÁV platform', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith((ref, arg) async => mockDepartures),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: testStation,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      // Let Riverpod FutureProvider resolve
      await tester.pumpAndSettle();

      // Heading should show station name
      expect(find.text('Szeged vasútállomás'), findsOneWidget);

      // Departures tab active
      expect(find.text('Indulások'), findsOneWidget);

      // dep1Departing (IC 718 to Budapest-Nyugati) SHOULD be present
      expect(find.text('IC 718 NAPFÉNY'), findsAtLeastNWidgets(1));
      expect(find.text('Budapest-Nyugati'), findsOneWidget);
      // MÁV platform display: "4. vágány"
      expect(find.text('4. vágány'), findsOneWidget);

      // Delay display: +15 perc késés badge and crossed out scheduled time 14:00
      expect(find.text('+15 perc késés'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('14:15'), findsOneWidget);
      // Ensure "NOW" is NOT displayed for a train scheduled/estimated at 14:15
      expect(find.text('NOW'), findsNothing);

      // dep2Terminating (to Szeged vasútállomás) MUST BE FILTERED OUT in Departures
      expect(find.text('IC 702 TORONTÁL'), findsNothing);
    });

    testWidgets('Arrivals mode (_showArrivals == true) displays arrivals, originStation, and sorts by arrival time', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith((ref, arg) async => mockDepartures),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: testStation,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Érkezések
      await tester.tap(find.text('Érkezések'));
      await tester.pumpAndSettle();

      // dep2Terminating is now visible as it arrives at Szeged
      expect(find.text('IC 702 TORONTÁL'), findsAtLeastNWidgets(1));
      // Without originStation, it displays "${dep.lineName} ide érkezik"
      expect(find.text('IC 702 TORONTÁL ide érkezik'), findsOneWidget);

      // dep3ArrivingWithOrigin displays "Honnan: Kiskunfélegyháza"
      expect(find.text('Honnan: Kiskunfélegyháza'), findsOneWidget);
      expect(find.text('13:55'), findsOneWidget);
    });

    testWidgets('Multimodal Hub tabs [Összes járat], [Vasúti menetrend (MÁV)], [Helyi járatok (BKK)] switch and filter properly', (tester) async {
      const hubStation = StopNode(
        id: 'HUB:KELETI',
        name: 'Budapest-Keleti',
        lat: 47.500,
        lon: 19.083,
        operator: Operator.mav,
        isMultimodalHub: true,
        vehicleType: 'train',
        platformCode: '6',
      );

      final mavTrain = UnifiedDeparture(
        tripId: 'TRIP_MAV_1',
        stopId: 'HUB:KELETI',
        operator: Operator.mav,
        lineName: 'RJ 62',
        headsign: 'München Hbf',
        routeColor: '003B7A',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 36000,
        scheduledTimeFormatted: '10:00',
        delaySeconds: 0,
        estimatedDepartureSeconds: 36000,
        estimatedTimeFormatted: '10:00',
        isRealtime: true,
        platformCode: '6',
      );

      final bkkMetro = UnifiedDeparture(
        tripId: 'TRIP_BKK_1',
        stopId: 'BKK_M4_KELETI',
        operator: Operator.bkk,
        lineName: 'M4',
        headsign: 'Kelenföld vasútállomás',
        routeColor: '439539',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 36300,
        scheduledTimeFormatted: '10:05',
        delaySeconds: 180,
        estimatedDepartureSeconds: 36480,
        estimatedTimeFormatted: '10:08',
        isRealtime: true,
      );

      final bkkBus = UnifiedDeparture(
        tripId: 'TRIP_BKK_2',
        stopId: 'BKK_BUS_KELETI',
        operator: Operator.bkk,
        lineName: '7',
        headsign: 'Újpalota, Nyírpalota út',
        routeColor: '009EE3',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 36600,
        scheduledTimeFormatted: '10:10',
        delaySeconds: 0,
        estimatedDepartureSeconds: 36600,
        estimatedTimeFormatted: '10:10',
        isRealtime: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith((ref, arg) async => [mavTrain, bkkMetro, bkkBus]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: hubStation,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // All 3 multimodal filter tabs should be present
      expect(find.text('Összes járat'), findsOneWidget);
      expect(find.text('Vasúti menetrend (MÁV)'), findsOneWidget);
      expect(find.text('Helyi járatok (BKK)'), findsOneWidget);

      // Default: Összes járat -> all 3 trips visible
      expect(find.text('RJ 62'), findsAtLeastNWidgets(1));
      expect(find.text('M4'), findsAtLeastNWidgets(1));
      expect(find.text('7'), findsAtLeastNWidgets(1));

      // Tap "Vasúti menetrend (MÁV)"
      await tester.tap(find.text('Vasúti menetrend (MÁV)'));
      await tester.pumpAndSettle();

      expect(find.text('RJ 62'), findsAtLeastNWidgets(1));
      expect(find.text('M4'), findsNothing);
      expect(find.text('7'), findsNothing);

      // Tap "Helyi járatok (BKK)"
      await tester.tap(find.text('Helyi járatok (BKK)'));
      await tester.pumpAndSettle();

      expect(find.text('RJ 62'), findsNothing);
      expect(find.text('M4'), findsAtLeastNWidgets(1));
      expect(find.text('7'), findsAtLeastNWidgets(1));
      // Local transit delay badge (+3p)
      expect(find.text('+3p'), findsOneWidget);

      // Switch back to "Összes járat"
      await tester.tap(find.text('Összes járat'));
      await tester.pumpAndSettle();
      expect(find.text('RJ 62'), findsAtLeastNWidgets(1));
      expect(find.text('M4'), findsAtLeastNWidgets(1));
      expect(find.text('7'), findsAtLeastNWidgets(1));
    });

    testWidgets('Déli pályaudvar Vasúti menetrend (MÁV) + Érkezések excludes arriving M2 metro and shows arriving trains', (tester) async {
      const deliStation = StopNode(
        id: 'GROUP:Déli pályaudvar:47.500:19.025',
        name: 'Déli pályaudvar',
        lat: 47.500,
        lon: 19.025,
        operator: Operator.bkk,
        isMultimodalHub: true,
        vehicleType: 'hub',
      );

      final arrivingTrain = UnifiedDeparture(
        tripId: 'MAV:1:967',
        stopId: 'MAV:1:005501016_0',
        operator: Operator.mav,
        lineName: 'GÖCSEJ IC',
        headsign: 'Budapest-Déli',
        routeColor: '0057B8',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 46740,
        scheduledTimeFormatted: '12:59',
        delaySeconds: 0,
        estimatedDepartureSeconds: 46740,
        estimatedTimeFormatted: '12:59',
        isRealtime: true,
        platformCode: '5',
        isArrival: true,
        originStation: 'Zalaegerszeg',
        scheduledArrivalTimeFormatted: '12:59',
        estimatedArrivalTimeFormatted: '12:59',
      );

      final arrivingMetro = UnifiedDeparture(
        tripId: 'BKK:M2_ARR',
        stopId: 'BKK:F00022',
        operator: Operator.bkk,
        lineName: 'M2',
        headsign: 'Déli pályaudvar',
        routeColor: 'E41F18',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 46800,
        scheduledTimeFormatted: '13:00',
        delaySeconds: 0,
        estimatedDepartureSeconds: 46800,
        estimatedTimeFormatted: '13:00',
        isRealtime: true,
        isArrival: true,
        originStation: 'Örs vezér tere M+H',
        scheduledArrivalTimeFormatted: '13:00',
        estimatedArrivalTimeFormatted: '13:00',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith(
              (ref, arg) async => [arrivingTrain, arrivingMetro],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: deliStation,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Vasúti menetrend (MÁV)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Érkezések'));
      await tester.pumpAndSettle();

      expect(find.text('GÖCSEJ IC'), findsAtLeastNWidgets(1));
      expect(find.text('Honnan: Zalaegerszeg'), findsOneWidget);
      expect(find.text('M2'), findsNothing);
    });

    testWidgets('Train schedule with elapsed scheduled time does not show NOW and displays delay badge', (tester) async {
      const trainStation = StopNode(
        id: 'MAV_12345',
        name: 'Budapest-Nyugati',
        lat: 47.510,
        lon: 19.057,
        operator: Operator.mav,
        isMultimodalHub: true,
        vehicleType: 'train',
      );

      final delayedTrain = UnifiedDeparture(
        tripId: 'TRIP_DELAYED',
        stopId: 'MAV_12345',
        operator: Operator.mav,
        lineName: 'IC 618 NYÍRSÉG',
        headsign: 'Záhony',
        routeColor: '003B7A',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 28800,
        scheduledTimeFormatted: '08:00',
        delaySeconds: 1860, // 31 min delay -> +31 perc késés
        estimatedDepartureSeconds: 30660,
        estimatedTimeFormatted: '08:31',
        isRealtime: true,
        platformCode: '3',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith((ref, arg) async => [delayedTrain]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: trainStation,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Station name
      expect(find.text('Budapest-Nyugati'), findsOneWidget);

      // Train line name and destination
      expect(find.text('IC 618 NYÍRSÉG'), findsAtLeastNWidgets(1));
      expect(find.text('Záhony'), findsOneWidget);

      // Platform
      expect(find.text('3. vágány'), findsOneWidget);

      // Delay badge
      expect(find.text('+31 perc késés'), findsOneWidget);

      // Times: scheduled 08:00 (crossed out) and estimated 08:31
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('08:31'), findsOneWidget);

      // Must NEVER display NOW
      expect(find.text('NOW'), findsNothing);
    });

    testWidgets('Tapping train departure opens detailed trip schedule sheet (Image 2 style)', (tester) async {
      const trainStation = StopNode(
        id: 'MAV_12345',
        name: 'Budapest-Nyugati',
        lat: 47.510,
        lon: 19.057,
        operator: Operator.mav,
        isMultimodalHub: true,
        vehicleType: 'train',
      );

      final trainDep = UnifiedDeparture(
        tripId: 'TRIP_TEST_DETAILS',
        stopId: 'MAV_12345',
        operator: Operator.mav,
        lineName: 'IR 87 AGRIÁT',
        headsign: 'Eger',
        routeColor: '007A78',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 61200,
        scheduledTimeFormatted: '17:00',
        delaySeconds: 120, // 2 min delay
        estimatedDepartureSeconds: 61320,
        estimatedTimeFormatted: '17:02',
        isRealtime: true,
        platformCode: '2',
      );

      final mockStops = [
        const TripStopSchedule(
          stopSequence: 1,
          stopId: 'MAV_12345',
          stopName: 'Budapest-Nyugati',
          departureTime: '17:00',
          operator: 'MAV',
          predictedDepartureTime: '17:02',
          delaySeconds: 120,
          platformCode: '2',
        ),
        const TripStopSchedule(
          stopSequence: 2,
          stopId: 'MAV_99999',
          stopName: 'Füzesabony',
          departureTime: '18:15',
          arrivalTime: '18:14',
          operator: 'MAV',
          predictedDepartureTime: '18:17',
          predictedArrivalTime: '18:16',
          delaySeconds: 120,
          platformCode: '1',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith((ref, arg) async => [trainDep]),
            tripScheduleProvider('TRIP_TEST_DETAILS').overrideWith((ref) async => mockStops),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: trainStation,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify row layout and rolling stock
      expect(find.text('IR 87 AGRIÁT'), findsAtLeastNWidgets(1));
      expect(find.text('Eger'), findsOneWidget);
      expect(find.text('2. vágány'), findsOneWidget);
      expect(find.text('Pontos'), findsOneWidget); // 2 min is on-time (< 120s is on-time)
      expect(find.text(', Stadler FLIRT'), findsOneWidget);

      // Tap on the train row to open detailed trip schedule modal
      await tester.tap(find.text('IR 87 AGRIÁT').last);
      await tester.pumpAndSettle();

      // Trip details modal should be open
      expect(find.text('Eger felé'), findsOneWidget);
      expect(find.text('Menetrend szerinti közlekedés'), findsOneWidget);
      expect(find.text('Állomás'), findsOneWidget);
      expect(find.text('Tervezett'), findsOneWidget);
      expect(find.text('Tény/Becsült'), findsOneWidget);
      expect(find.text('Füzesabony'), findsOneWidget);
    });

    testWidgets('StationDetailCard invokes onDepartureTapped callback when provided instead of opening bottom sheet', (tester) async {
      UnifiedDeparture? tappedDep;

      final testStation = StopNode(
        id: 'BKK_F04567',
        name: 'Déli pályaudvar',
        lat: 47.500,
        lon: 19.025,
        operator: Operator.mav,
        isMultimodalHub: true,
        vehicleType: 'train',
        platformCode: '10',
      );

      final depTrain = UnifiedDeparture(
        tripId: 'TRIP_S10',
        stopId: 'BKK_F04567',
        operator: Operator.mav,
        lineName: 'S10',
        headsign: 'Győr',
        routeColor: '0057B8',
        routeTextColor: 'FFFFFF',
        scheduledDepartureSeconds: 66600,
        scheduledTimeFormatted: '18:30',
        delaySeconds: 420,
        estimatedDepartureSeconds: 67020,
        estimatedTimeFormatted: '18:37',
        isRealtime: true,
        platformCode: '10',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stationDepartureBoardProvider.overrideWith(
              (ref, arg) async => [depTrain],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StationDetailCard(
                station: testStation,
                onClose: () {},
                onDepartureTapped: (dep) => tappedDep = dep,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('S10'), findsAtLeastNWidgets(1));

      // Tap on the S10 train departure row
      await tester.tap(find.text('S10').last);
      await tester.pumpAndSettle();

      // Verify callback received the departure
      expect(tappedDep, isNotNull);
      expect(tappedDep!.lineName, 'S10');
      expect(tappedDep!.tripId, 'TRIP_S10');

      // Bottom sheet should NOT be opened
      expect(find.text('Állomás'), findsNothing);
    });
  });

  group('MapLegendDialog', () {
    testWidgets('renders all 3 required sections and transit modes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MapLegendDialog(),
          ),
        ),
      );

      // Header
      expect(find.text('Jelmagyarázat'), findsOneWidget);
      expect(find.text('Térképi rétegek, járművek és jelölések'), findsOneWidget);

      // Section 1: Közlekedési és Vasúti Vonalak
      expect(find.text('Közlekedési és Vasúti Vonalak'), findsOneWidget);
      expect(find.text('OpenRailwayMap vasúti vágányhálózat'), findsOneWidget);
      expect(find.text('M1 sárga'), findsOneWidget);
      expect(find.text('M2 piros'), findsOneWidget);
      expect(find.text('M3 kék'), findsOneWidget);
      expect(find.text('M4 zöld'), findsOneWidget);
      expect(find.text('H5 lila'), findsOneWidget);
      expect(find.text('H6 barna'), findsOneWidget);
      expect(find.text('H7 narancs'), findsOneWidget);
      expect(find.text('H8/H9 bordó'), findsOneWidget);
      expect(find.text('Villamos (sárga)'), findsOneWidget);
      expect(find.text('Busz (kék)'), findsOneWidget);
      expect(find.text('Trolibusz (piros)'), findsOneWidget);
      expect(find.text('Éjszakai járat (fekete)'), findsOneWidget);
      expect(find.text('MÁV vonat (kék)'), findsOneWidget);

      // Section 2: Késések és Menetrendi Állapotok
      expect(find.text('Késések és Menetrendi Állapotok'), findsOneWidget);
      expect(find.text('Zöld: Pontos jármű (0–2 perc késés)'), findsOneWidget);
      expect(find.text('Sárga: Kisebb késés (2–5 perc késés)'), findsOneWidget);
      expect(find.text('Piros: Jelentős késés (5+ perc késés)'), findsOneWidget);
      expect(find.textContaining('Menetrendi idő áthúzva'), findsOneWidget);
      expect(find.textContaining('késésgyűrű'), findsOneWidget);

      // Section 3: Megállók és Állomások Jelölései
      expect(find.text('Megállók és Állomások Jelölései'), findsOneWidget);
      expect(find.textContaining('Megállócsoport'), findsOneWidget);
      expect(find.textContaining('Egyedi megállópont'), findsOneWidget);
      expect(find.textContaining('Vágányszám és peronjelzés'), findsOneWidget);
    });

    testWidgets('MapLegendDialog.show() displays modal dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => MapLegendDialog.show(ctx),
                child: const Text('Megnyitás'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Megnyitás'));
      await tester.pumpAndSettle();

      expect(find.byType(MapLegendDialog), findsOneWidget);

      // Tap close button in footer
      await tester.tap(find.text('Bezárás'));
      await tester.pumpAndSettle();

      expect(find.byType(MapLegendDialog), findsNothing);
    });
  });
}
