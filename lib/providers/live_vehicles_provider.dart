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

/// Foreground-aware periodic stream of GeoJSON FeatureCollections from the Rust engine.
/// Polls every 12 seconds and immediately whenever the user pans/zooms the viewport.
final liveVehiclesGeoJsonProvider = StreamProvider.autoDispose<String>((ref) {
  final bbox = ref.watch(viewportBboxProvider);
  final controller = StreamController<String>();
  Timer? timer;
  bool isDisposed = false;

  Future<void> pollOnce() async {
    if (isDisposed) return;
    try {
      final geoJson = await TransitRustBridge.instance.pollLiveVehiclesGeoJson(
        minLat: bbox.minLat,
        minLon: bbox.minLon,
        maxLat: bbox.maxLat,
        maxLon: bbox.maxLon,
      );
      if (!isDisposed) {
        controller.add(geoJson);
      }
    } catch (e, st) {
      if (!isDisposed) {
        controller.addError(e, st);
      }
    }
  }

  pollOnce();
  timer = Timer.periodic(const Duration(seconds: 12), (_) => pollOnce());

  ref.onDispose(() {
    isDisposed = true;
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Queries R-Tree indexed static stops inside the current map viewport.
final viewportStopsProvider = FutureProvider.autoDispose<List<StopNode>>((ref) {
  final bbox = ref.watch(viewportBboxProvider);
  return TransitRustBridge.instance.getStopsInBbox(
    minLat: bbox.minLat,
    minLon: bbox.minLon,
    maxLat: bbox.maxLat,
    maxLon: bbox.maxLon,
    limit: 250,
  );
});
