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

/// Whether stop groups / station hubs should be displayed on the map
final showStopGroupsProvider = StateProvider<bool>((ref) => false);

/// Whether individual platforms / stop posts (directions) should be displayed on the map
final showPlatformsProvider = StateProvider<bool>((ref) => false);

/// Legacy stops toggle provider
final showStopsProvider = StateProvider<bool>((ref) => false);

/// Cache of the last successfully polled GeoJSON to prevent any flickering
String _lastEmittedGeoJson = '';

/// Periodic stream of GeoJSON FeatureCollections covering all active BKK and MÁV vehicles in Hungary.
/// Decoupled from camera movements (`viewportBboxProvider`) so panning/zooming never reloads or drops vehicles.
final liveVehiclesGeoJsonProvider = StreamProvider<String>((ref) {
  final controller = StreamController<String>();
  Timer? timer;
  bool isDisposed = false;

  if (_lastEmittedGeoJson.isNotEmpty) {
    controller.add(_lastEmittedGeoJson);
  }

  Future<void> pollOnce() async {
    if (isDisposed) return;
    try {
      // Poll the full Hungary bounding box once every 10s so camera pan/zoom is 100% lag-free
      final geoJson = await TransitRustBridge.instance.pollLiveVehiclesGeoJson(
        minLat: 45.70,
        minLon: 16.00,
        maxLat: 48.65,
        maxLon: 23.00,
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

List<StopNode> _lastStopGroupsCache = const [];

/// Queries R-Tree indexed static stop groups inside the current map viewport (debounced on camera idle).
final viewportStopGroupsProvider = FutureProvider<List<StopNode>>((ref) async {
  final showGroups = ref.watch(showStopGroupsProvider);
  if (!showGroups) return const <StopNode>[];

  final bbox = ref.watch(viewportBboxProvider);
  try {
    final groups = await TransitRustBridge.instance.getStopGroupsInBbox(
      minLat: bbox.minLat,
      minLon: bbox.minLon,
      maxLat: bbox.maxLat,
      maxLon: bbox.maxLon,
      limit: 250,
    );
    _lastStopGroupsCache = groups;
    return groups;
  } catch (_) {
    return _lastStopGroupsCache;
  }
});

List<StopNode> _lastPlatformsCache = const [];

/// Queries R-Tree indexed individual platforms/directions inside the current map viewport (debounced on camera idle).
final viewportPlatformsProvider = FutureProvider<List<StopNode>>((ref) async {
  final showPlatforms = ref.watch(showPlatformsProvider);
  if (!showPlatforms) return const <StopNode>[];

  final bbox = ref.watch(viewportBboxProvider);
  try {
    final platforms = await TransitRustBridge.instance.getPlatformsInBbox(
      minLat: bbox.minLat,
      minLon: bbox.minLon,
      maxLat: bbox.maxLat,
      maxLon: bbox.maxLon,
      limit: 300,
    );
    _lastPlatformsCache = platforms;
    return platforms;
  } catch (_) {
    return _lastPlatformsCache;
  }
});

/// Legacy / general stops provider alias for backward compatibility
final viewportStopsProvider = viewportStopGroupsProvider;
