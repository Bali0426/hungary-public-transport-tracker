import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/models/vehicle_technical_data.dart';
import 'package:hungary_public_transport_tracker/providers/vehicle_detail_provider.dart';
import 'package:hungary_public_transport_tracker/services/hbweb_service.dart';
import 'package:hungary_public_transport_tracker/services/vagonweb_service.dart';
import 'package:hungary_public_transport_tracker/views/vehicle_technical_tab_view.dart';

void main() {
  group('VagonwebService Tests', () {
    final vagonweb = VagonwebService.instance;

    test('extractTrainNumber correctly extracts numbers from various lineName and tripId formats', () {
      expect(vagonweb.extractTrainNumber('IC 562', null, null), equals('562'));
      expect(vagonweb.extractTrainNumber('IC 562 Tokaj', null, null), equals('562'));
      expect(vagonweb.extractTrainNumber('Z50 2834', null, null), equals('2834'));
      expect(vagonweb.extractTrainNumber('S50', 'MAV:2814_100', null), equals('2814'));
      expect(vagonweb.extractTrainNumber('MÁV', null, 'Debrecen (582. sz. vonat)'), equals('582'));
    });

    test('extractTrainName cleans category prefixes and numbers', () {
      expect(vagonweb.extractTrainName('IC 562 Tokaj'), equals('Tokaj'));
      expect(vagonweb.extractTrainName('IC 500 Nyírség'), equals('Nyírség'));
      expect(vagonweb.extractTrainName('Z50'), equals('Z50'));
    });

    test('getTrainComposition returns realistic fallback with carriage diagrams for MÁV trains', () async {
      final comp = await vagonweb.getTrainComposition(
        lineName: 'IC 562 Tokaj',
        destination: 'Budapest-Keleti – Nyíregyháza',
      );

      expect(comp, isNotNull);
      expect(comp!.carriages, isNotEmpty);
      expect(comp.carriages.first.isLocomotive, isTrue);
      expect(comp.carriages.any((c) => c.className.contains('1.')), isTrue);
      expect(comp.carriages.any((c) => c.className.contains('2.')), isTrue);
      expect(comp.carriages.any((c) => c.hasWifi), isTrue);
      expect(comp.vagonwebUrl, contains('vagonweb.cz'));
    });

    test('getTrainComposition returns Stadler KISS for Z50 commuter train', () async {
      final comp = await vagonweb.getTrainComposition(
        lineName: 'Z50 2834',
        destination: 'Szolnok',
      );

      expect(comp, isNotNull);
      expect(comp!.carriages, isNotEmpty);
      expect(comp.carriages.first.series, contains('815'));
      expect(comp.carriages.first.seatCount, equals(600));
      expect(comp.carriages.first.isAccessible, isTrue);
    });
  });

  group('HbwebService Tests', () {
    final hbweb = HbwebService.instance;

    test('matches Siemens Combino Budapest tram on Nagykörút lines 4-6', () {
      final info = hbweb.getVehicleTechnicalInfo(
        vehicleId: 'BKK:2001',
        lineName: '4-6',
        vehicleType: 'tram',
      );

      expect(info.modelName, contains('Siemens Combino'));
      expect(info.depot, contains('Hungária'));
      expect(info.lengthMeters, closeTo(53.99, 0.1));
      expect(info.seats, equals(64));
      expect(info.standing, equals(289));
      expect(info.totalCapacity, equals(353));
      expect(info.lowFloorPercent, equals(100));
      expect(info.hasAirConditioning, isTrue);
      expect(info.hbwebUrl, contains('hbweb.hu'));
    });

    test('matches CAF Urbos 3 56m tram for 1-es villamos', () {
      final info = hbweb.getVehicleTechnicalInfo(
        vehicleId: 'BKK:2205',
        lineName: '1',
        vehicleType: 'tram',
      );

      expect(info.modelName, contains('CAF Urbos 3 (56 m'));
      expect(info.lengthMeters, closeTo(55.91, 0.1));
      expect(info.totalCapacity, equals(345));
      expect(info.hasUsbChargers, isTrue);
    });

    test('matches MAN Lion\'s City EfficientHybrid for ArrivaBus lines', () {
      final info = hbweb.getVehicleTechnicalInfo(
        vehicleId: 'BKK:AA-LC-812',
        lineName: '105',
        vehicleType: 'bus',
        operatorName: 'ArrivaBus Kft.',
      );

      expect(info.modelName, contains("MAN Lion's City"));
      expect(info.operator, equals('ArrivaBus Kft.'));
      expect(info.hasAirConditioning, isTrue);
      expect(info.hasUsbChargers, isTrue);
      expect(info.hbwebUrl, contains('hbweb.hu'));
    });

    test('matches Solaris-Škoda Trollino for trolley lines', () {
      final info = hbweb.getVehicleTechnicalInfo(
        vehicleId: 'BKK:9002',
        lineName: '75',
        vehicleType: 'trolley',
      );

      expect(info.modelName, contains('Solaris-Škoda Trollino 18'));
      expect(info.depot, contains('Pongrácz'));
      expect(info.engineAndPower, contains('akkumulátor'));
    });

    test('matches Alstom Metropolis for M4 automated metro line', () {
      final info = hbweb.getVehicleTechnicalInfo(
        vehicleId: 'BKK:545',
        lineName: 'M4',
        vehicleType: 'metro',
      );

      expect(info.modelName, contains('Alstom Metropolis AM4-M4'));
      expect(info.futarOBU, contains('GoA4'));
      expect(info.hasAirConditioning, isTrue);
    });
  });

  group('VehicleTechnicalTabView Widget Tests', () {
    testWidgets('renders BKK HBweb technical specs sheet', (tester) async {
      final bkkProps = {
        'id': 'BKK:2001',
        'line_name': '4',
        'destination': 'Újbuda-központ M',
        'operator': 'BKK',
        'vehicle_type': 'tram',
        'delay_seconds': 0,
        'delay_bucket': 'on_time',
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 440,
                height: 520,
                child: VehicleTechnicalTabView(props: bkkProps),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Siemens Combino'), findsOneWidget);
      expect(find.textContaining('Hungária kocsiszín'), findsWidgets);
      expect(find.textContaining('HBweb.hu'), findsOneWidget);
    });

    testWidgets('renders MÁV vagonWEB train composition sheet', (tester) async {
      final mavProps = {
        'id': 'MAV:562',
        'line_name': 'IC 562 Tokaj',
        'destination': 'Budapest-Keleti – Nyíregyháza',
        'operator': 'MAV',
        'vehicle_type': 'train',
        'delay_seconds': 120,
        'delay_bucket': 'minor_delay',
      };

      const testComposition = TrainComposition(
        trainNumber: '562',
        trainName: 'Tokaj InterCity',
        category: 'IC',
        route: 'Budapest-Keleti – Nyíregyháza',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        vagonwebUrl: 'https://www.vagonweb.cz/razeni/vlak.php?rok=2026&cislo=562',
        carriages: [
          CarriageInfo(
            coachNumber: '',
            series: 'START 470 (Taurus)',
            typeName: 'Siemens ES64U2 villamos mozdony',
            className: 'Mozdony',
            imageUrl: '',
          ),
          CarriageInfo(
            coachNumber: '20',
            series: 'START Bbdpmz 84-91 (IC+)',
            typeName: '2. osztályú többcélú IC+ kocsi',
            className: '2. osztály',
            imageUrl: '',
            seatCount: 54,
            hasWifi: true,
            hasAc: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainCompositionProvider.overrideWith(
              (ref, params) async => testComposition,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 440,
                height: 520,
                child: VehicleTechnicalTabView(props: mavProps),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Tokaj'), findsWidgets);
      expect(find.textContaining('vagonWEB'), findsWidgets);
      expect(find.text('Menetirány'), findsOneWidget);
    });
  });
}
