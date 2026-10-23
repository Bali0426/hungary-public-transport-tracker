import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/bridge/bridge_generated.dart';
import 'package:hungary_public_transport_tracker/providers/live_vehicles_provider.dart';
import 'package:hungary_public_transport_tracker/providers/timetable_provider.dart';
import 'package:hungary_public_transport_tracker/providers/transit_lines_provider.dart';
import 'package:latlong2/latlong.dart';

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
      expect(container.read(openRailwayMapStyleProvider), equals(OpenRailwayMapStyle.standard));

      container.read(openRailwayMapStyleProvider.notifier).state = OpenRailwayMapStyle.maxspeed;
      expect(container.read(openRailwayMapStyleProvider), equals(OpenRailwayMapStyle.maxspeed));
      expect(OpenRailwayMapStyle.maxspeed.tileUrl, contains('maxspeed'));
      expect(OpenRailwayMapStyle.maxspeed.labelHu, contains('Sebesség'));

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

    test('returns dense track-aligned points for MÁV railway trip (more points than stop count)', () async {
      final container = ProviderContainer(
        overrides: [
          tripScheduleProvider.overrideWith((ref, tripId) async {
            return [
              const TripStopSchedule(
                stopSequence: 1,
                stopId: 'CS_005510009',
                stopName: 'Budapest-Keleti',
                departureTime: '08:00',
                operator: 'MAV',
                lat: 47.5004,
                lon: 19.0838,
              ),
              const TripStopSchedule(
                stopSequence: 2,
                stopId: 'CS_005510405',
                stopName: 'Tatabánya',
                departureTime: '08:45',
                operator: 'MAV',
                lat: 47.5850,
                lon: 18.3970,
              ),
              const TripStopSchedule(
                stopSequence: 3,
                stopId: 'CS_005510801',
                stopName: 'Győr',
                departureTime: '09:20',
                operator: 'MAV',
                lat: 47.6830,
                lon: 17.6350,
              ),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);

      final points = await container.read(vehicleRoutePolylineProvider('MAV:IC_920').future);

      // Verify that dense points along the track corridor are returned, far exceeding the 3 stop points!
      expect(points.length, greaterThan(3));
      expect(points.length, greaterThanOrEqualTo(15));

      // The line starts at Keleti and ends at Győr
      expect(points.first.latitude, closeTo(47.5004, 0.01));
      expect(points.first.longitude, closeTo(19.0838, 0.01));
      expect(points.last.latitude, closeTo(47.6830, 0.01));
      expect(points.last.longitude, closeTo(17.6350, 0.01));
    });

    test('returns dense track-aligned points for HÉV suburban train trips', () async {
      final container = ProviderContainer(
        overrides: [
          tripScheduleProvider.overrideWith((ref, tripId) async {
            return [
              const TripStopSchedule(
                stopSequence: 1,
                stopId: 'BKK_00551',
                stopName: 'Batthyány tér H',
                departureTime: '12:00',
                operator: 'BKK',
                lat: 47.5067,
                lon: 19.0393,
              ),
              const TripStopSchedule(
                stopSequence: 2,
                stopId: 'BKK_00559',
                stopName: 'Szentendre H',
                departureTime: '12:40',
                operator: 'BKK',
                lat: 47.6610,
                lon: 19.0756,
              ),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);

      final points = await container.read(vehicleRoutePolylineProvider('BKK:H5_TRIP_01').future);

      // Even with only 2 terminus stops, track corridor interpolation gives full curve coordinates!
      expect(points.length, greaterThan(2));
      expect(points.length, greaterThanOrEqualTo(10));
      expect(points.first.latitude, closeTo(47.5067, 0.01));
      expect(points.last.latitude, closeTo(47.6610, 0.01));
    });

    test('uses direct trip geometry when registered in TransitRouteGeometry (e.g. trip.pattern.geometry)', () async {
      final directPoints = [
        const LatLng(47.5000, 19.0000),
        const LatLng(47.5100, 19.0100),
        const LatLng(47.5200, 19.0200),
        const LatLng(47.5300, 19.0300),
      ];

      TransitRouteGeometry.registerDirectTripGeometry('MAV_DIRECT_GEOM_TRIP', directPoints);
      addTearDown(TransitRouteGeometry.clearDirectTripGeometries);

      final container = ProviderContainer(
        overrides: [
          tripScheduleProvider.overrideWith((ref, tripId) async {
            // Even if schedule has completely different coarse points, direct geometry takes precedence!
            return [
              const TripStopSchedule(
                stopSequence: 1,
                stopId: 'STOP_1',
                stopName: 'Coarse 1',
                departureTime: '10:00',
                operator: 'MAV',
                lat: 47.0,
                lon: 19.0,
              ),
              const TripStopSchedule(
                stopSequence: 2,
                stopId: 'STOP_2',
                stopName: 'Coarse 2',
                departureTime: '11:00',
                operator: 'MAV',
                lat: 48.0,
                lon: 20.0,
              ),
            ];
          }),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(vehicleRoutePolylineProvider('MAV_DIRECT_GEOM_TRIP').future);
      expect(result, equals(directPoints));
    });

    test('TransitRouteGeometry.fitToRailwayTracks correctly interpolates main rail corridors', () {
      // Budapest-Nyugati to Debrecen
      final stops = [
        const LatLng(47.5109, 19.0569), // Nyugati
        const LatLng(47.1680, 20.1800), // Szolnok
        const LatLng(47.5210, 21.6250), // Debrecen
      ];

      final fitted = TransitRouteGeometry.fitToRailwayTracks(stops);
      expect(fitted.length, greaterThan(3));
      expect(fitted.length, greaterThanOrEqualTo(15));
      expect(fitted.first.latitude, closeTo(47.5109, 0.01));
      expect(fitted.last.latitude, closeTo(47.5210, 0.01));
    });

    test('showLiveVehiclesProvider master toggle enables or disables vehicle rendering', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(showLiveVehiclesProvider), isTrue);
      expect(container.read(enabledTransitModesProvider), contains('metro'));

      container.read(showLiveVehiclesProvider.notifier).state = false;
      expect(container.read(showLiveVehiclesProvider), isFalse);
      // Mode is still configured
      expect(container.read(enabledTransitModesProvider), contains('metro'));
    });
  });
}
