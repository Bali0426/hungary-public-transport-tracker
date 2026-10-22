import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/bridge/bridge_generated.dart';
import 'package:hungary_public_transport_tracker/models/vehicle_technical_data.dart';
import 'package:hungary_public_transport_tracker/providers/vehicle_detail_provider.dart';
import 'package:hungary_public_transport_tracker/services/hbweb_service.dart';
import 'package:hungary_public_transport_tracker/services/vagonweb_service.dart';
import 'package:hungary_public_transport_tracker/views/vehicle_technical_tab_view.dart';
import 'package:hungary_public_transport_tracker/views/widgets/station_detail_card.dart';

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

    test('extractTrainNumber prioritizes tripShortName over internal OTP tripId', () {
      final num = vagonweb.extractTrainNumber(
        'TÓPART IC',
        'MAV:1:36362214',
        null,
        '856 TÓPART InterCity',
      );
      expect(num, equals('856'));
      expect(num, isNot(equals('562')));

      expect(
        vagonweb.extractTrainNumber('IC', null, null, 'IC 856'),
        equals('856'),
      );
      expect(
        vagonweb.extractTrainNumber('Személy', null, null, '34123 személyvonat'),
        equals('34123'),
      );
    });

    test('getTrainComposition resolves 856 Tópart IC with tripShortName and does not fallback to 562', () async {
      final comp = await vagonweb.getTrainComposition(
        lineName: 'TÓPART IC',
        tripId: 'MAV:1:36362214',
        tripShortName: '856 TÓPART InterCity',
      );

      expect(comp, isNotNull);
      expect(comp!.trainNumber, equals('856'));
      expect(comp.trainNumber, isNot(equals('562')));
      expect(comp.vagonwebUrl, contains('cislo=856'));
      expect(comp.category, equals('IC'));
    });

    test('getTrainComposition resolves Hungarian named IC routes when no number is given', () async {
      final topart = await vagonweb.getTrainComposition(lineName: 'TÓPART IC');
      expect(topart?.trainNumber, equals('856'));
      expect(topart?.trainNumber, isNot(equals('562')));

      final balaton = await vagonweb.getTrainComposition(lineName: 'BALATON IC');
      expect(balaton?.trainNumber, equals('864'));

      final mecsek = await vagonweb.getTrainComposition(lineName: 'MECSEK IC');
      expect(mecsek?.trainNumber, equals('804'));

      final napfeny = await vagonweb.getTrainComposition(lineName: 'NAPFÉNY IC');
      expect(napfeny?.trainNumber, equals('702'));

      final tisza = await vagonweb.getTrainComposition(lineName: 'TISZA IC');
      expect(tisza?.trainNumber, equals('628'));

      final arrabona = await vagonweb.getTrainComposition(lineName: 'ARRABONA IC');
      expect(arrabona?.trainNumber, equals('982'));

      final savaria = await vagonweb.getTrainComposition(lineName: 'SAVARIA IC');
      expect(savaria?.trainNumber, equals('924'));

      final gocsej = await vagonweb.getTrainComposition(lineName: 'GÖCSEJ IC');
      expect(gocsej?.trainNumber, equals('954'));

      final bakony = await vagonweb.getTrainComposition(lineName: 'BAKONY IC');
      expect(bakony?.trainNumber, equals('904'));

      final bekes = await vagonweb.getTrainComposition(lineName: 'BÉKÉS IC');
      expect(bekes?.trainNumber, equals('7402'));

      final herkules = await vagonweb.getTrainComposition(lineName: 'HERKULES');
      expect(herkules?.trainNumber, equals('373'));
      expect(herkules?.operatorName, contains('CFR'));
    });

    test('getTrainComposition never falls back to 562 for unknown IC', () async {
      final unknownIc = await vagonweb.getTrainComposition(lineName: 'IC');
      expect(unknownIc?.trainNumber, equals(''));
      expect(unknownIc?.trainNumber, isNot(equals('562')));
      expect(unknownIc?.vagonwebUrl, isNot(contains('cislo=562')));
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
      expect(comp.carriages.first.effectiveLengthMeters, equals(155.8));
    });

    test('getTrainComposition returns Railjet Xpress for RJX line', () async {
      final comp = await vagonweb.getTrainComposition(
        lineName: 'RJX 60',
        destination: 'München Hbf',
      );

      expect(comp, isNotNull);
      expect(comp!.category, equals('RJX'));
      expect(comp.carriages.length, equals(8));
      expect(comp.carriages.first.series, contains('1116'));
      expect(comp.carriages.any((c) => c.series.contains('Afmpz')), isTrue);
      expect(comp.hasBistro, isTrue);
    });

    test('getTrainComposition returns EuroCity for EC line', () async {
      final comp = await vagonweb.getTrainComposition(
        lineName: 'EC 140 Hortobágy',
        destination: 'Wien Hbf',
      );

      expect(comp, isNotNull);
      expect(comp!.category, equals('EC'));
      expect(comp.carriages.first.isLocomotive, isTrue);
      expect(comp.carriages.any((c) => c.series.contains('WRRmz')), isTrue);
      expect(comp.hasBistro, isTrue);
    });

    test('getTrainComposition returns Stadler FLIRT for S50 train', () async {
      final comp = await vagonweb.getTrainComposition(
        lineName: 'S50',
        tripId: 'MAV:4814_100',
        destination: 'Szolnok',
      );

      expect(comp, isNotNull);
      expect(comp!.carriages.first.series, contains('415'));
      expect(comp.carriages.first.effectiveLengthMeters, equals(74.3));
    });

    test('getTrainComposition never returns FLIRT for HÉV lines', () async {
      final h5Comp = await vagonweb.getTrainComposition(
        lineName: 'H5',
        tripShortName: 'H4788 HÉV',
      );
      expect(h5Comp, isNull);

      final szHComp = await vagonweb.getTrainComposition(
        lineName: 'Sz H4788',
        tripShortName: 'H4788 HÉV',
      );
      expect(szHComp, isNull);
    });

    test('CarriageInfo calculates effectiveLengthMeters correctly for scale display', () {
      const kiss = CarriageInfo(
        coachNumber: '1',
        series: 'START 815 (KISS)',
        typeName: 'Stadler KISS emeletes motorvonat',
        className: '2. osztály',
        imageUrl: '',
      );
      expect(kiss.effectiveLengthMeters, equals(155.8));

      const flirt = CarriageInfo(
        coachNumber: '1',
        series: 'START 415 (FLIRT)',
        typeName: 'Stadler FLIRT villamos motorvonat',
        className: '2. osztály',
        imageUrl: '',
      );
      expect(flirt.effectiveLengthMeters, equals(74.3));

      const desiro = CarriageInfo(
        coachNumber: '1',
        series: 'START 426 (Desiro)',
        typeName: 'Siemens Desiro dízel motorvonat',
        className: '2. osztály',
        imageUrl: '',
      );
      expect(desiro.effectiveLengthMeters, equals(41.7));

      const loco = CarriageInfo(
        coachNumber: '',
        series: 'START 470 (Taurus)',
        typeName: 'Villamos mozdony',
        className: 'Mozdony',
        imageUrl: '',
      );
      expect(loco.effectiveLengthMeters, equals(19.3));

      const coach = CarriageInfo(
        coachNumber: '20',
        series: 'START Bbdpmz',
        typeName: '2. osztályú személykocsi',
        className: '2. osztály',
        imageUrl: '',
      );
      expect(coach.effectiveLengthMeters, equals(26.4));
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

    testWidgets('renders horizontal scrollbar and responds to mouse wheel scrolling', (tester) async {
      final mavProps = {
        'id': 'MAV:562',
        'line_name': 'IC 562 Tokaj',
        'destination': 'Budapest-Keleti – Nyíregyháza',
        'operator': 'MAV',
        'vehicle_type': 'train',
      };

      await tester.pumpWidget(
        ProviderScope(
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

      expect(find.byType(Scrollbar), findsOneWidget);
      expect(find.byType(Listener), findsWidgets);
    });

    testWidgets('VehicleTechnicalTabView displays IC 856 and not IC 562 for Tópart train with trip_short_name', (tester) async {
      final topartProps = {
        'id': 'MAV:856',
        'line_name': 'TÓPART IC',
        'trip_short_name': '856 TÓPART InterCity',
        'trip_id': 'MAV:1:36362214',
        'destination': 'Nagykanizsa',
        'operator': 'MAV',
        'vehicle_type': 'train',
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 440,
                height: 520,
                child: VehicleTechnicalTabView(props: topartProps),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('IC 856'), findsOneWidget);
      expect(find.text('IC 562'), findsNothing);
      expect(find.textContaining('TÓPART'), findsWidgets);
    });

    testWidgets('displays Material 3 empty state when no composition found', (tester) async {
      final emptyProps = {
        'id': 'MAV:99999',
        'line_name': 'Személy 99999',
        'operator': 'MAV',
        'vehicle_type': 'train',
      };

      const emptyComposition = TrainComposition(
        trainNumber: '99999',
        trainName: 'Személy 99999',
        category: 'Sz',
        route: '',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        vagonwebUrl: 'https://www.vagonweb.cz/razeni/vlak.php?rok=2026&cislo=99999',
        carriages: [],
        actualCarriages: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainCompositionProvider.overrideWith(
              (ref, params) async => emptyComposition,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 440,
                height: 520,
                child: VehicleTechnicalTabView(props: emptyProps),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('Ehhez a vonathoz nem található összeállítási információ a vagonWEB adatbázisában.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.train_outlined), findsOneWidget);
    });

    testWidgets('routes MÁV-labeled HÉVs to HBweb MXA technical sheet instead of FLIRT', (tester) async {
      final hevMavProps = {
        'id': 'MAV:1:1135',
        'line_name': 'H5',
        'operator': 'MAV',
        'vehicle_type': 'train',
        'trip_short_name': 'H4788 HÉV',
      };

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 440,
                height: 520,
                child: VehicleTechnicalTabView(props: hevMavProps),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Must find MXA motorvonat, NOT FLIRT
      expect(find.textContaining('MXA'), findsOneWidget);
      expect(find.textContaining('FLIRT'), findsNothing);
    });

    testWidgets('allows switching between planned and actual composition tabs and shows under-carriage specs', (tester) async {
      final mavProps = {
        'id': 'MAV:868',
        'line_name': 'IC 868 Balaton',
        'operator': 'MAV',
        'vehicle_type': 'train',
      };

      const detailedComposition = TrainComposition(
        trainNumber: '868',
        trainName: 'Balaton InterCity',
        category: 'IC',
        route: 'Budapest-Déli - Keszthely',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        actualDateLabel: '2026.10.19',
        vagonwebUrl: 'https://www.vagonweb.cz/razeni/vlak.php?rok=2026&cislo=868',
        carriages: [
          CarriageInfo(
            coachNumber: '',
            series: '480',
            operatorCode: 'START',
            typeName: 'TRAXX villamos mozdony',
            className: 'Mozdony',
            imageUrl: '',
          ),
          CarriageInfo(
            coachNumber: '5',
            series: 'By/Byee',
            operatorCode: 'START',
            typeName: '2. osztályú személykocsi',
            className: '2. osztály',
            imageUrl: '',
            seatCapacity: '80+6',
            originDestination: 'Budapest-Déli - Keszthely',
            hasWifi: true,
            hasAc: true,
          ),
        ],
        actualCarriages: [
          CarriageInfo(
            coachNumber: '',
            series: '193',
            operatorCode: 'ELOC',
            typeName: 'Vectron villamos mozdony',
            className: 'Mozdony',
            imageUrl: '',
          ),
          CarriageInfo(
            coachNumber: '5',
            series: 'Byee',
            operatorCode: 'START',
            typeName: '2. osztályú személykocsi',
            className: '2. osztály',
            imageUrl: '',
            seatCapacity: '80+6',
            originDestination: 'Budapest-Déli - Keszthely',
            hasWifi: true,
            hasAc: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainCompositionProvider.overrideWith(
              (ref, params) async => detailedComposition,
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

      // Planned tab is active initially
      expect(find.text('Tervezett összeállítás'), findsOneWidget);
      expect(find.textContaining('Tényleges (2026.10.19)'), findsOneWidget);
      expect(find.text('START 480'), findsOneWidget);
      expect(find.text('80+6'), findsOneWidget);
      expect(find.text('Budapest-Déli - Keszthely'), findsWidgets);

      // Switch to actual composition tab
      await tester.tap(find.textContaining('Tényleges (2026.10.19)'));
      await tester.pumpAndSettle();

      // Now actual composition is displayed with ELOC 193
      expect(find.text('ELOC 193'), findsOneWidget);
    });
  });

  group('TripStopSchedule Real-Time Delay Tests', () {
    test('deserializes real platformCode, predicted times and stop delay correctly', () {
      final json = {
        'stop_sequence': 3,
        'stop_id': 'MAV:1:28518948_2',
        'stop_name': 'Székesfehérvár',
        'departure_time': '16:17',
        'operator': 'MAV',
        'platform_code': '9',
        'arrival_time': '16:15',
        'lat': 47.1895,
        'lon': 18.4231,
        'predicted_departure_time': '16:39',
        'predicted_arrival_time': '16:37',
        'delay_seconds': 1320,
      };

      final stop = TripStopSchedule.fromJson(json);

      expect(stop.stopSequence, equals(3));
      expect(stop.stopName, equals('Székesfehérvár'));
      expect(stop.platformCode, equals('9'));
      expect(stop.departureTime, equals('16:17'));
      expect(stop.predictedDepartureTime, equals('16:39'));
      expect(stop.delaySeconds, equals(1320));
      expect(stop.lat, equals(47.1895));
      expect(stop.lon, equals(18.4231));
    });
  });

  group('CarriageInfo classification & StationDetailCard layout tests', () {
    test('CarriageInfo correctly classifies locomotives, multiple units and wagons', () {
      const loco = CarriageInfo(
        coachNumber: '',
        series: '480',
        typeName: 'Villamos mozdony',
        className: 'Mozdony',
        imageUrl: 'https://www.vagonweb.cz/popisy/img/START/480-a.gif',
      );
      expect(loco.isLocomotive, isTrue);
      expect(loco.isMultipleUnit, isFalse);
      expect(loco.isWagon, isFalse);

      const emu = CarriageInfo(
        coachNumber: '1',
        series: 'START 815 (KISS)',
        typeName: 'Stadler KISS 6 részes emeletes motorvonat',
        className: '2. osztály',
        imageUrl: 'https://www.vagonweb.cz/popisy/img/START/815-a.gif',
      );
      expect(emu.isLocomotive, isFalse);
      expect(emu.isMultipleUnit, isTrue);
      expect(emu.isWagon, isFalse);

      const wagon = CarriageInfo(
        coachNumber: '21',
        series: 'Bmz 21-91',
        typeName: '2. osztályú fülkés személykocsi',
        className: '2. osztály',
        imageUrl: 'https://www.vagonweb.cz/popisy/img/START/Bmz-2191-3-m-a.gif',
      );
      expect(wagon.isLocomotive, isFalse);
      expect(wagon.isMultipleUnit, isFalse);
      expect(wagon.isWagon, isTrue);
    });

    testWidgets('StationDetailCard stop group view renders without overflow on 380px width', (tester) async {
      tester.view.physicalSize = const Size(380, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final groupNode = StopNode(
        id: 'GROUP:Deák Ferenc tér:47.4979:19.0541',
        hubId: 'BKK_F01001',
        name: 'Deák Ferenc tér M',
        lat: 47.4979,
        lon: 19.0541,
        operator: Operator.bkk,
        platformCode: null,
        isMultimodalHub: true,
        vehicleType: 'metro',
        servedRoutes: 'M1, M2, M3, 47, 48, 49, 100E',
        direction: null,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 380,
                  child: StationDetailCard(
                    station: groupNode,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Deák Ferenc tér M'), findsOneWidget);
      expect(find.textContaining('Megállócsoport'), findsOneWidget);
      expect(find.text('Indulások'), findsOneWidget);
      expect(find.text('Érkezések'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
