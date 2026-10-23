import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/bridge/bridge_generated.dart';
import 'package:hungary_public_transport_tracker/utils/transit_display_utils.dart';
import 'package:hungary_public_transport_tracker/views/line_search_delegate.dart';
import 'package:hungary_public_transport_tracker/views/widgets/map_control_buttons.dart';
import 'package:hungary_public_transport_tracker/views/widgets/map_layers_menu.dart';

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
}
