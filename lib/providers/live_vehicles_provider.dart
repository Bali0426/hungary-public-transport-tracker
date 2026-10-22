import 'dart:async';
import 'dart:convert';

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

  factory ViewportBbox.budapest() => const ViewportBbox(
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

/// Number of vehicles currently rendered on screen in the camera viewport
final renderedVehiclesCountProvider = StateProvider<int>((ref) => 0);

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
  final showGroups = ref.watch(showStopGroupsProvider);
  final showPlatforms = ref.watch(showPlatformsProvider);
  if (!showGroups && !showPlatforms) return const <StopNode>[];

  final bbox = ref.watch(viewportBboxProvider);
  try {
    final platforms = await TransitRustBridge.instance.getPlatformsInBbox(
      minLat: bbox.minLat,
      minLon: bbox.minLon,
      maxLat: bbox.maxLat,
      maxLon: bbox.maxLon,
      limit: 600,
    );
    _lastPlatformsCache = platforms;
    return platforms;
  } catch (_) {
    return _lastPlatformsCache;
  }
});

typedef VehicleCounts = ({
  int total,
  int bkk,
  int mav,
  int bus,
  int tram,
  int metro,
  int trolley,
  int suburbanRail,
  int boat,
  int train,
});

/// Memoized provider computing live vehicle breakdown by mode and operator once per stream tick.
final liveVehicleCountsProvider = Provider<VehicleCounts>((ref) {
  final rawAsync = ref.watch(liveVehiclesGeoJsonProvider);
  final raw = rawAsync.valueOrNull ?? '';
  if (raw.isEmpty) {
    return (
      total: 0,
      bkk: 0,
      mav: 0,
      bus: 0,
      tram: 0,
      metro: 0,
      trolley: 0,
      suburbanRail: 0,
      boat: 0,
      train: 0,
    );
  }

  int bkk = 0, mav = 0, bus = 0, tram = 0, metro = 0, trolley = 0, suburbanRail = 0, boat = 0, train = 0;
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final features = map['features'] as List<dynamic>? ?? const [];
    for (final f in features) {
      final p = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
      final op = p['operator'] as String? ?? 'BKK';
      final vType = p['vehicle_type'] as String? ?? 'bus';
      if (op == 'MAV' || vType == 'train') {
        mav++;
        train++;
      } else {
        bkk++;
        switch (vType) {
          case 'tram':
            tram++;
            break;
          case 'metro':
            metro++;
            break;
          case 'trolley':
            trolley++;
            break;
          case 'suburban_rail':
            suburbanRail++;
            break;
          case 'boat':
            boat++;
            break;
          default:
            bus++;
            break;
        }
      }
    }
  } catch (_) {}

  return (
    total: bkk + mav,
    bkk: bkk,
    mav: mav,
    bus: bus,
    tram: tram,
    metro: metro,
    trolley: trolley,
    suburbanRail: suburbanRail,
    boat: boat,
    train: train,
  );
});

