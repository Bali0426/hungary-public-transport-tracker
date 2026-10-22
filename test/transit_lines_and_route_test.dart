import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/bridge/bridge_generated.dart';
import 'package:hungary_public_transport_tracker/providers/timetable_provider.dart';
import 'package:hungary_public_transport_tracker/providers/transit_lines_provider.dart';

void main() {
  group('State Providers Default & Mutation Tests', () {
    test('All layer switches default to false and can be toggled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(showOpenRailwayMapProvider), isFalse);
      expect(container.read(showRailwayLinesProvider), isFalse);
      expect(container.read(showMetroLinesProvider), isFalse);
      expect(container.read(showTramLinesProvider), isFalse);
      expect(container.read(showHevLinesProvider), isFalse);

      container.read(showMetroLinesProvider.notifier).state = true;
      expect(container.read(showMetroLinesProvider), isTrue);

      container.read(showOpenRailwayMapProvider.notifier).state = true;
      expect(container.read(showOpenRailwayMapProvider), isTrue);

      container.read(showRailwayLinesProvider.notifier).state = true;
      expect(container.read(showRailwayLinesProvider), isTrue);

      container.read(showTramLinesProvider.notifier).state = true;
      expect(container.read(showTramLinesProvider), isTrue);

      container.read(showHevLinesProvider.notifier).state = true;
      expect(container.read(showHevLinesProvider), isTrue);
    });
  });

  group('Metro Polylines & Colors Verification', () {
    test('metroPolylinesProvider contains exactly 4 lines with official colors and 3.5px width', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final polylines = container.read(metroPolylinesProvider);
      expect(polylines.length, equals(4));

      // M1 (Yellow: #FFD800)
      final m1 = polylines[0];
      expect(m1.color, equals(const Color(0xFFFFD800)));
      expect(m1.strokeWidth, equals(3.5));
      expect(m1.points.length, greaterThanOrEqualTo(10));
      expect(m1.points.first.latitude, closeTo(47.496, 0.01)); // Vörösmarty tér
      expect(m1.points.last.latitude, closeTo(47.519, 0.01)); // Mexikói út

      // M2 (Red: #E41F18)
      final m2 = polylines[1];
      expect(m2.color, equals(const Color(0xFFE41F18)));
      expect(m2.strokeWidth, equals(3.5));
      expect(m2.points.length, greaterThanOrEqualTo(10));
      expect(m2.points.first.latitude, closeTo(47.500, 0.01)); // Déli pu
      expect(m2.points.last.latitude, closeTo(47.502, 0.01)); // Örs vezér tere

      // M3 (Blue: #005CA5)
      final m3 = polylines[2];
      expect(m3.color, equals(const Color(0xFF005CA5)));
      expect(m3.strokeWidth, equals(3.5));
      expect(m3.points.length, greaterThanOrEqualTo(15));
      expect(m3.points.first.latitude, closeTo(47.560, 0.01)); // Újpest-központ
      expect(m3.points.last.latitude, closeTo(47.463, 0.01)); // Kőbánya-Kispest

      // M4 (Green: #439539)
      final m4 = polylines[3];
      expect(m4.color, equals(const Color(0xFF439539)));
      expect(m4.strokeWidth, equals(3.5));
      expect(m4.points.length, greaterThanOrEqualTo(10));
      expect(m4.points.first.latitude, closeTo(47.464, 0.01)); // Kelenföld
      expect(m4.points.last.latitude, closeTo(47.500, 0.01)); // Keleti pu
    });
  });

  group('HÉV, Tram and Railway Polylines Verification', () {
    test('hevPolylinesProvider contains H5, H6, H7, H8, H9 with official colors', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final polylines = container.read(hevPolylinesProvider);
      expect(polylines.length, equals(5));

      // H5: Purple (#821380)
      expect(polylines[0].color, equals(const Color(0xFF821380)));
      expect(polylines[0].points.first.latitude, closeTo(47.506, 0.01)); // Batthyány tér
      expect(polylines[0].points.last.latitude, closeTo(47.661, 0.01)); // Szentendre

      // H6: Brown (#86421B)
      expect(polylines[1].color, equals(const Color(0xFF86421B)));
      expect(polylines[1].points.first.latitude, closeTo(47.466, 0.01)); // Közvágóhíd
      expect(polylines[1].points.last.latitude, closeTo(47.175, 0.01)); // Ráckeve

      // H7: Orange (#EE7203)
      expect(polylines[2].color, equals(const Color(0xFFEE7203)));
      expect(polylines[2].points.first.latitude, closeTo(47.479, 0.01)); // Boráros tér
      expect(polylines[2].points.last.latitude, closeTo(47.421, 0.01)); // Csepel

      // H8: Bordeaux (#E52320)
      expect(polylines[3].color, equals(const Color(0xFFE52320)));
      expect(polylines[3].points.first.latitude, closeTo(47.502, 0.01)); // Örs vezér tere
      expect(polylines[3].points.last.latitude, closeTo(47.593, 0.01)); // Gödöllő

      // H9: Bordeaux (#E52320)
      expect(polylines[4].color, equals(const Color(0xFFE52320)));
      expect(polylines[4].points.last.latitude, closeTo(47.545, 0.01)); // Csömör
    });

    test('tramPolylinesProvider and railwayPolylinesProvider contain valid corridors', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tramLines = container.read(tramPolylinesProvider);
      expect(tramLines.isNotEmpty, isTrue);
      for (final tram in tramLines) {
        expect(tram.points.length, greaterThanOrEqualTo(2));
        expect(tram.color, equals(const Color(0xFFFFD800)));
      }

      final railLines = container.read(railwayPolylinesProvider);
      expect(railLines.isNotEmpty, isTrue);
      for (final rail in railLines) {
        expect(rail.points.length, greaterThanOrEqualTo(2));
        expect(rail.color, equals(const Color(0xFF004B93)));
      }
    });
  });

  group('vehicleRoutePolylineProvider Tests', () {
    test('returns empty list when tripId is empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final result = await container.read(vehicleRoutePolylineProvider('').future);
      expect(result, isEmpty);
    });

    test('returns empty list when fewer than 2 valid points exist', () async {
      final container = ProviderContainer(
        overrides: [
          tripScheduleProvider.overrideWith((ref, tripId) async {
            return [
              const TripStopSchedule(
                stopSequence: 1,
                stopId: 'STOP_1',
                stopName: 'Single Stop',
                departureTime: '10:00',
                operator: 'bkk',
                lat: 47.497,
                lon: 19.054,
              ),
              const TripStopSchedule(
                stopSequence: 2,
                stopId: 'STOP_2',
                stopName: 'Invalid Stop',
                departureTime: '10:05',
                operator: 'bkk',
                lat: null,
                lon: null,
              ),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);

      final points = await container.read(vehicleRoutePolylineProvider('TRIP_ONE_POINT').future);
      expect(points, isEmpty);
    });

    test('sorts stops by stop_sequence and filters out invalid points', () async {
      final container = ProviderContainer(
        overrides: [
          tripScheduleProvider.overrideWith((ref, tripId) async {
            return [
              const TripStopSchedule(
                stopSequence: 3,
                stopId: 'STOP_3',
                stopName: 'Third Stop',
                departureTime: '10:10',
                operator: 'bkk',
                lat: 47.505,
                lon: 19.063,
              ),
              const TripStopSchedule(
                stopSequence: 1,
                stopId: 'STOP_1',
                stopName: 'First Stop',
                departureTime: '10:00',
                operator: 'bkk',
                lat: 47.496,
                lon: 19.050,
              ),
              const TripStopSchedule(
                stopSequence: 2,
                stopId: 'STOP_NULL',
                stopName: 'Missing Coords',
                departureTime: '10:05',
                operator: 'bkk',
                lat: null,
                lon: null,
              ),
              const TripStopSchedule(
                stopSequence: 4,
                stopId: 'STOP_4',
                stopName: 'Fourth Stop',
                departureTime: '10:15',
                operator: 'bkk',
                lat: 47.519,
                lon: 19.091,
              ),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);

      final points = await container.read(vehicleRoutePolylineProvider('TRIP_VALID').future);
      expect(points.length, equals(3));
      expect(points[0].latitude, closeTo(47.496, 0.001));
      expect(points[1].latitude, closeTo(47.505, 0.001));
      expect(points[2].latitude, closeTo(47.519, 0.001));
    });
  });
}
