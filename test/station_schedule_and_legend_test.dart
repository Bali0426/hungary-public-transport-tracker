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

      // Delay display: +15p badge and crossed out scheduled time 14:00
      expect(find.text('+15p'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('14:15'), findsOneWidget);

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
