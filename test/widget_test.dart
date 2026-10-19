import 'package:flutter_test/flutter_test.dart';
import 'package:hungary_public_transport_tracker/main.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    expect(const HungaryTransitApp(), isNotNull);
  });
}
