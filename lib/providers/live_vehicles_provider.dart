import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/bridge_generated.dart';

/// Represents the current map camera bounding box (defaulting to central Budapest).
class ViewportBbox {
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  const ViewportBbox({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });


  const ViewportBbox._({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  factory ViewportBbox.budapest() => const ViewportBbox._(
        minLat: 47.4200,
        minLon: 18.9800,
        maxLat: 47.5600,
        maxLon: 19.1600,
      );
}

final viewportBboxProvider = StateProvider<ViewportBbox>(
  (ref) => ViewportBbox.budapest(),
);

/// Map dark mode toggle provider (true = dark tiles/inverted, false = standard light tiles)
final mapDarkModeProvider = StateProvider<bool>((ref) => true);

/// Transit mode filter: set of enabled transit types (bus, tram, metro, trolley, train, suburban_rail, boat)
final enabledTransitModesProvider = StateProvider<Set<String>>((ref) => {
  'bus',
  'tram',
  'metro',
  'trolley',
  'train',
  'suburban_rail',
  'boat',
});

/// Whether static stops and station hubs should be displayed on the map
final showStopsProvider = StateProvider<bool>((ref) => true);

/// Cache of the last successfully polled GeoJSON to prevent flickering when camera moves
String _lastEmittedGeoJson = '';

/// Foreground-aware periodic stream of GeoJSON FeatureCollections from the Rust engine.
/// Keeps existing vehicles on screen while new coordinates are polled.
final liveVehiclesGeoJsonProvider = StreamProvider.autoDispose<String>((ref) {
  final bbox = ref.watch(viewportBboxProvider);
  final controller = StreamController<String>();
  Timer? timer;
  bool isDisposed = false;

  // Emit last known vehicles immediately to avoid any flickering/disappearance on camera move
  if (_lastEmittedGeoJson.isNotEmpty) {
    controller.add(_lastEmittedGeoJson);
  }

  Future<void> pollOnce() async {
    if (isDisposed) return;
    try {
      final geoJson = await TransitRustBridge.instance.pollLiveVehiclesGeoJson(
        minLat: bbox.minLat,
        minLon: bbox.minLon,
        maxLat: bbox.maxLat,
        maxLon: bbox.maxLon,
      );
      if (!isDisposed && geoJson.isNotEmpty) {
        _lastEmittedGeoJson = geoJson;
        controller.add(geoJson);
      }
    } catch (e, st) {
      if (!isDisposed && _lastEmittedGeoJson.isEmpty) {
        controller.addError(e, st);
      }
    }
  }

  pollOnce();
  timer = Timer.periodic(const Duration(seconds: 10), (_) => pollOnce());

  ref.onDispose(() {
    isDisposed = true;
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Queries R-Tree indexed static stops inside the current map viewport.
final viewportStopsProvider = FutureProvider.autoDispose<List<StopNode>>((ref) {
  final showStops = ref.watch(showStopsProvider);
  if (!showStops) return Future.value(const <StopNode>[]);

  final bbox = ref.watch(viewportBboxProvider);
  return TransitRustBridge.instance.getStopsInBbox(
    minLat: bbox.minLat,
    minLon: bbox.minLon,
    maxLat: bbox.maxLat,
    maxLon: bbox.maxLon,
    limit: 250,
  );
});
