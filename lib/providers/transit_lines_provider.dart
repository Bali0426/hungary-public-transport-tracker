import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';
import '../models/transit_route_geometry.dart';
import 'timetable_provider.dart';

export '../models/transit_route_geometry.dart';

/// OpenRailwayMap style presets (infrastructure, speeds, signals, electrification, gauge).
enum OpenRailwayMapStyle {
  standard,
  maxspeed,
  signals,
  electrification,
  gauge;

  String get tileUrl {
    switch (this) {
      case OpenRailwayMapStyle.standard:
        return 'https://{s}.tile.openrailwaymap.org/standard/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.maxspeed:
        return 'https://{s}.tile.openrailwaymap.org/maxspeed/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.signals:
        return 'https://{s}.tile.openrailwaymap.org/signals/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.electrification:
        return 'https://{s}.tile.openrailwaymap.org/electrification/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.gauge:
        return 'https://{s}.tile.openrailwaymap.org/gauge/{z}/{x}/{y}.png';
    }
  }

  String get labelHu {
    switch (this) {
      case OpenRailwayMapStyle.standard:
        return 'Infrastruktúra (Alapértelmezett)';
      case OpenRailwayMapStyle.maxspeed:
        return 'Sebességkorlátozások (Max speed)';
      case OpenRailwayMapStyle.signals:
        return 'Jelzők és biztosítóberendezések (Signalling)';
      case OpenRailwayMapStyle.electrification:
        return 'Villamosítás (Electrification)';
      case OpenRailwayMapStyle.gauge:
        return 'Nyomtáv (Track gauge)';
    }
  }
}

/// OpenRailwayMap active style layer selector provider.
final openRailwayMapStyleProvider = StateProvider<OpenRailwayMapStyle>((ref) => OpenRailwayMapStyle.standard);

/// OpenRailwayMap railway infrastructure tile layer switch.
final showOpenRailwayMapProvider = StateProvider<bool>((ref) => false);

/// MÁV railway mainline corridors switch (deprecated: replaced by OpenRailwayMap tiles and vehicle track polylines).
@Deprecated('Use OpenRailwayMap tile layer and vehicleRoutePolylineProvider instead')
final showRailwayLinesProvider = StateProvider<bool>((ref) => false);

/// Budapest Metro network lines (M1-M4) switch.
final showMetroLinesProvider = StateProvider<bool>((ref) => false);

/// Budapest major tram corridors switch.
final showTramLinesProvider = StateProvider<bool>((ref) => false);

/// Budapest suburban railway (HÉV) lines switch.
final showHevLinesProvider = StateProvider<bool>((ref) => false);

/// Extracts ordered route stop coordinates for the selected vehicle's trip.
///
/// When the trip is a train (MÁV) or suburban rail (HÉV), or when stations are separated
/// by several kilometers, snaps and interpolates the route coordinates along physical
/// railway track curves instead of drawing straight straight-line chords.
final vehicleRoutePolylineProvider =
    FutureProvider.autoDispose.family<List<LatLng>, String>((ref, tripId) async {
  if (tripId.trim().isEmpty) {
    return const [];
  }

  // 1. Direct vágánygeometria (pl. trip.pattern.geometry vagy OTP2 cache)
  final directGeom = TransitRouteGeometry.getDirectTripGeometry(tripId);
  if (directGeom != null && directGeom.isNotEmpty) {
    return directGeom;
  }

  // 2. Query exact track geometry from OTP2 (OpenRailwayMap track curves)
  try {
    final liveCoords = await TransitRustBridge.instance.getTripGeometry(tripId: tripId);
    if (liveCoords.isNotEmpty) {
      final points = liveCoords.map((c) => LatLng(c.lat, c.lon)).toList();
      TransitRouteGeometry.registerDirectTripGeometry(tripId, points);
      return points;
    }
  } catch (_) {
    // Fallback to schedule stops
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

  final stopCoords = validStops.map((stop) => LatLng(stop.lat!, stop.lon!)).toList();

  final isMav = validStops.any((s) => s.operator.toUpperCase().contains('MAV')) ||
      tripId.startsWith('MAV:') ||
      validStops.any((s) => s.stopId.startsWith('CS'));

  final isHev = tripId.toUpperCase().contains('H5') ||
      tripId.toUpperCase().contains('H6') ||
      tripId.toUpperCase().contains('H7') ||
      tripId.toUpperCase().contains('H8') ||
      tripId.toUpperCase().contains('H9') ||
      tripId.toLowerCase().contains('hev') ||
      validStops.any((s) => s.stopName.contains('HÉV'));

  final isMetroOrTram = tripId.toUpperCase().contains('M1') ||
      tripId.toUpperCase().contains('M2') ||
      tripId.toUpperCase().contains('M3') ||
      tripId.toUpperCase().contains('M4') ||
      tripId.contains('5100') ||
      tripId.contains('5200') ||
      tripId.contains('5300') ||
      tripId.contains('5400') ||
      tripId.contains('3010') ||
      tripId.contains('3020') ||
      tripId.contains('3040') ||
      tripId.contains('3060') ||
      validStops.any((s) => s.stopName.contains(' [M]') || s.stopName.contains(' M'));

  bool hasLongDistance = false;
  for (int i = 0; i < stopCoords.length - 1; i++) {
    if (TransitRouteGeometry.distanceMeters(stopCoords[i], stopCoords[i + 1]) > 3500.0) {
      hasLongDistance = true;
      break;
    }
  }

  if (isMav || isHev || isMetroOrTram || hasLongDistance) {
    return TransitRouteGeometry.fitToRailwayTracks(stopCoords);
  }

  return stopCoords;
});
