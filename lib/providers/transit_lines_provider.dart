import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'timetable_provider.dart';

export '../models/transit_route_geometry.dart';

/// OpenRailwayMap railway infrastructure tile layer switch.
final showOpenRailwayMapProvider = StateProvider<bool>((ref) => false);

/// MÁV railway mainline corridors switch.
final showRailwayLinesProvider = StateProvider<bool>((ref) => false);

/// Budapest Metro network lines (M1-M4) switch.
final showMetroLinesProvider = StateProvider<bool>((ref) => false);

/// Budapest major tram corridors switch.
final showTramLinesProvider = StateProvider<bool>((ref) => false);

/// Budapest suburban railway (HÉV) lines switch.
final showHevLinesProvider = StateProvider<bool>((ref) => false);

/// Extracts ordered route stop coordinates for the selected vehicle's trip.
final vehicleRoutePolylineProvider =
    FutureProvider.autoDispose.family<List<LatLng>, String>((ref, tripId) async {
  if (tripId.trim().isEmpty) {
    return const [];
  }

  final schedule = await ref.watch(tripScheduleProvider(tripId).future);
  if (schedule.isEmpty) {
    return const [];
  }

  final validStops = schedule.where((stop) {
    final lat = stop.lat;
    final lon = stop.lon;
    if (lat == null || lon == null) return false;
    if (lat == 0.0 && lon == 0.0) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.stopSequence.compareTo(b.stopSequence));

  if (validStops.length < 2) {
    return const [];
  }

  return validStops.map((stop) => LatLng(stop.lat!, stop.lon!)).toList();
});
