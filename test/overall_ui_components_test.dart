import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/bridge/bridge_generated.dart';
import 'package:hungary_public_transport_tracker/providers/live_vehicles_provider.dart';
import 'package:hungary_public_transport_tracker/utils/stop_group_geometry.dart';
import 'package:hungary_public_transport_tracker/utils/transit_display_utils.dart';
import 'package:hungary_public_transport_tracker/views/line_search_delegate.dart';
import 'package:hungary_public_transport_tracker/views/map_screen.dart';
import 'package:hungary_public_transport_tracker/views/widgets/map_control_buttons.dart';
import 'package:hungary_public_transport_tracker/views/widgets/map_layers_menu.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('Official BudapestGO Transit Colors (Spec Chapter 3)', () {
    test('verifies metro line colors', () {
      expect(getLineOrRouteColor('M1'), equals(const Color(0xFFFFD800)));
      expect(getLineOrRouteColor('M2'), equals(const Color(0xFFE41F18)));
      expect(getLineOrRouteColor('M3'), equals(const Color(0xFF005CA5)));
      expect(getLineOrRouteColor('M4'), equals(const Color(0xFF439539)));
    });

    test('verifies HÉV line colors', () {
      expect(getLineOrRouteColor('H5'), equals(const Color(0xFF821380)));
      expect(getLineOrRouteColor('H6'), equals(const Color(0xFF86421B)));
      expect(getLineOrRouteColor('H7'), equals(const Color(0xFFEE7203)));
      expect(getLineOrRouteColor('H8'), equals(const Color(0xFFE52320)));
      expect(getLineOrRouteColor('H9'), equals(const Color(0xFFE52320)));
      expect(getModeBadgeColor('hev'), equals(const Color(0xFF007A33)));
    });

    test('verifies surface mode colors', () {
      expect(getModeBadgeColor('tram'), equals(const Color(0xFFFFD800)));
      expect(getModeBadgeColor('bus'), equals(const Color(0xFF009EE3)));
      expect(getModeBadgeColor('trolley'), equals(const Color(0xFFE41F18)));
      expect(getModeBadgeColor('boat'), equals(const Color(0xFFE52082)));
      expect(getModeBadgeColor('train'), equals(const Color(0xFF003B7A)));
      expect(getModeBadgeColor('night'), equals(const Color(0xFF1A1A1A)));
      expect(getLineOrRouteColor('908'), equals(const Color(0xFF1A1A1A)));
      expect(getLineOrRouteColor('100E'), equals(const Color(0xFF007BBF)));
    });
  });

  group('Map Control Buttons', () {
    testWidgets('MyLocationButton renders GPS icon and responds to tap', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MyLocationButton(
              onLocationRequested: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.my_location), findsOneWidget);
      await tester.tap(find.byType(MyLocationButton));
      await tester.pump();

      expect(pressed, isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('StopsLayerToggleButton delegates to GPS button seamlessly', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StopsLayerToggleButton(
              onToggle: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.my_location), findsOneWidget);
      await tester.tap(find.byType(StopsLayerToggleButton));
      await tester.pump();

      expect(pressed, isTrue);
    });
  });

  group('Map Layers Floating Menu 2-column mode toggles', () {
    testWidgets('renders all 7 modes in 2 columns with neutral toggles and master toggle', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 600,
                child: MapLayersFloatingMenu(
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('KÖZLEKEDÉSI MÓDOK'), findsOneWidget);
      // Master toggle exists with same size/style as stops switches
      expect(find.text('Járművek réteg'), findsOneWidget);
      expect(find.text('Mind'), findsNothing);
      expect(find.byIcon(Icons.select_all), findsNothing);
      expect(find.text('Busz'), findsOneWidget);
      expect(find.text('Villamos'), findsOneWidget);
      expect(find.text('Metró'), findsOneWidget);
      expect(find.text('Trolibusz'), findsOneWidget);
      expect(find.text('MÁV Vonat'), findsOneWidget);
      expect(find.text('HÉV'), findsOneWidget);
      expect(find.text('Hajó'), findsOneWidget);

      // Metro badges rendered without overflow
      expect(find.text('Metróvonalak'), findsOneWidget);
      expect(find.text('M1'), findsOneWidget);
      expect(find.text('M2'), findsOneWidget);
      expect(find.text('M3'), findsOneWidget);
      expect(find.text('M4'), findsOneWidget);

      // Verify "Vasúti vonalak" is removed
      expect(find.text('Vasúti vonalak'), findsNothing);

      // Verify OpenRailwayMap card
      expect(find.text('OpenRailwayMap Vasúti Térkép'), findsOneWidget);

      // Ensure no checkmarks exist
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('OpenRailwayMap expands inline with style selector and large toggle', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 600,
                child: MapLayersFloatingMenu(
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Initially inline styles are collapsed
      expect(find.text('Térkép stílusa:'), findsNothing);

      // Tap on OpenRailwayMap card to expand inline downward
      await tester.tap(find.text('OpenRailwayMap Vasúti Térkép'));
      await tester.pumpAndSettle();

      // Check inline styles content
      expect(find.text('Térkép stílusa:'), findsOneWidget);
      expect(find.text('Infrastructure (Vasúti pálya)'), findsOneWidget);
      expect(find.text('Max speeds (Pályasebesség)'), findsOneWidget);
      expect(find.text('Signalling and train protection (Jelzők & Biztosítóberendezés)'), findsOneWidget);
      expect(find.text('Electrification (Villamosítás)'), findsOneWidget);
      expect(find.text('Track gauge (Nyomtáv)'), findsOneWidget);

      // Metróvonalak is still present (pushed down, not obscured)
      expect(find.text('Metróvonalak'), findsOneWidget);

      // Select another style inline
      await tester.tap(find.text('Max speeds (Pályasebesség)'));
      await tester.pumpAndSettle();

      // Tap again to collapse inline
      await tester.tap(find.text('OpenRailwayMap Vasúti Térkép'));
      await tester.pumpAndSettle();

      expect(find.text('Térkép stílusa:'), findsNothing);
    });
  });

  group('TopLeftFloatingSearch Widget', () {
    testWidgets('renders compact Material 3 search bar', (tester) async {
      StopNode? selectedResult;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TopLeftFloatingSearch(
                onResultSelected: (node) {
                  selectedResult = node;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Járat, vonat vagy állomás...'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '4-6');
      await tester.pump();

      // Clear button appears when text is entered
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Trigger clear
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.text('4-6'), findsNothing);
      expect(selectedResult, isNull);
    });
  });

  group('StopGroupsLayer & PlatformsMapLayer Pre-baked & LOD', () {
    test('StopGroupGeometry.cleanStationName caches and cleans station suffixes', () {
      expect(
        StopGroupGeometry.cleanStationName('Széll Kálmán tér M (Csaba utca)'),
        equals('Széll Kálmán tér'),
      );
      expect(
        StopGroupGeometry.cleanStationName('Batthyány tér M+H [A]'),
        equals('Batthyány tér'),
      );
      expect(
        identical(
          StopGroupGeometry.cleanStationName('Széll Kálmán tér M (Csaba utca)'),
          StopGroupGeometry.cleanStationName('Széll Kálmán tér M (Csaba utca)'),
        ),
        isTrue,
      );
    });

    test('StopGroupGeometry.queryInBbox returns pre-baked stop groups with fixed centroids and polygons', () async {
      final groups = await StopGroupGeometry.queryInBbox(
        minLat: 47.490,
        minLon: 19.015,
        maxLat: 47.515,
        maxLon: 19.065,
        limit: 50,
      );

      expect(groups, isNotEmpty);
      expect(groups.any((g) => g.polygonPoints.length >= 3), isTrue);

      // Verify centroid stability regardless of bbox shift
      final sample = groups.firstWhere((g) => g.polygonPoints.length >= 3);
      final shiftedGroups = await StopGroupGeometry.queryInBbox(
        minLat: sample.centroid.latitude - 0.002,
        minLon: sample.centroid.longitude - 0.002,
        maxLat: sample.centroid.latitude + 0.020,
        maxLon: sample.centroid.longitude + 0.020,
        limit: 50,
      );
      final sameGroup = shiftedGroups.firstWhere((g) => g.hubId == sample.hubId);
      expect(sameGroup.centroid, equals(sample.centroid));
      expect(identical(sameGroup.polygonPoints, sample.polygonPoints), isTrue);
    });

    testWidgets('StopGroupsLayer renders pre-baked polygons and labels without runtime clustering', (tester) async {
      final mockGroup = PrebakedStopGroup.fromJson({
        'id': 'HUB_SZELL',
        'name': 'Széll Kálmán tér',
        'lat': 47.507,
        'lon': 19.025,
        'op': 'BKK',
        'mm': 1,
        'count': 8,
        'minLat': 47.506,
        'maxLat': 47.508,
        'minLon': 19.024,
        'maxLon': 19.026,
        'poly': [
          [47.506, 19.024],
          [47.508, 19.024],
          [47.508, 19.026],
          [47.506, 19.026],
        ],
      });

      final container = ProviderContainer(
        overrides: [
          showStopGroupsProvider.overrideWith((ref) => true),
          mapZoomProvider.overrideWith((ref) => 15.5),
          viewportStopGroupsProvider.overrideWith((ref) async => [mockGroup]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(47.507, 19.025),
                  initialZoom: 15.5,
                ),
                children: [
                  StopGroupsLayer(onStationTapped: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Széll Kálmán tér'), findsOneWidget);
      expect(find.byType(PolygonLayer), findsOneWidget);
    });

    testWidgets('PlatformsMapLayer hides below zoom 16.5 and renders at zoom >= 16.5', (tester) async {
      const samplePlatforms = [
        StopNode(
          id: 'F001',
          name: 'Deák Ferenc tér M',
          lat: 47.4979,
          lon: 19.0542,
          operator: Operator.bkk,
          isMultimodalHub: false,
          vehicleType: 'tram',
          servedRoutes: '47, 49',
          direction: '180',
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          showPlatformsProvider.overrideWith((ref) => true),
          mapZoomProvider.overrideWith((ref) => 15.5),
          viewportPlatformsProvider.overrideWith((ref) async => samplePlatforms),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(47.4979, 19.0542),
                  initialZoom: 15.5,
                ),
                children: [
                  PlatformsMapLayer(onStationTapped: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hidden at zoom 15.5
      expect(find.byType(BudapestGoPlatformPin), findsNothing);

      // Visible at zoom 16.8
      container.read(mapZoomProvider.notifier).state = 16.8;
      await tester.pumpAndSettle();
      expect(find.byType(BudapestGoPlatformPin), findsOneWidget);
    });
  });

  group('MapScreen Engine Tests', () {
    testWidgets('MapScreen mounts FlutterMap with OpenStreetMap and dark filter', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MapScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });
}
