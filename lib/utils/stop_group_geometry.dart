import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';

/// Pre-baked stop group / station hub with fixed centroid and buffered convex hull polygon.
class PrebakedStopGroup {
  final String hubId;
  final String name;
  final LatLng centroid;
  final Operator operator;
  final bool isMultimodal;
  final int stopCount;
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;
  final List<LatLng> polygonPoints;
  final StopNode groupNode;

  const PrebakedStopGroup({
    required this.hubId,
    required this.name,
    required this.centroid,
    required this.operator,
    required this.isMultimodal,
    required this.stopCount,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.polygonPoints,
    required this.groupNode,
  });

  factory PrebakedStopGroup.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final name = json['name'] as String;
    final lat = (json['lat'] as num).toDouble();
    final lon = (json['lon'] as num).toDouble();
    final opStr = (json['op'] as String? ?? 'BKK').toUpperCase();
    final op = opStr == 'MAV' ? Operator.mav : Operator.bkk;
    final isMm = (json['mm'] as num? ?? 0) != 0;
    final count = (json['count'] as num? ?? 1).toInt();
    final minLat = (json['minLat'] as num).toDouble();
    final maxLat = (json['maxLat'] as num).toDouble();
    final minLon = (json['minLon'] as num).toDouble();
    final maxLon = (json['maxLon'] as num).toDouble();

    final rawPoly = json['poly'] as List<dynamic>? ?? const [];
    final polyPts = rawPoly.isEmpty
        ? const <LatLng>[]
        : List<LatLng>.unmodifiable(
            rawPoly.map((pt) {
              final pair = pt as List<dynamic>;
              return LatLng((pair[0] as num).toDouble(), (pair[1] as num).toDouble());
            }),
          );

    return PrebakedStopGroup(
      hubId: id,
      name: name,
      centroid: LatLng(lat, lon),
      operator: op,
      isMultimodal: isMm,
      stopCount: count,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      polygonPoints: polyPts,
      groupNode: StopNode(
        id: 'GROUP:$name:$lat:$lon',
        hubId: id,
        name: name,
        lat: lat,
        lon: lon,
        operator: op,
        platformCode: null,
        isMultimodalHub: true,
        vehicleType: 'hub',
        servedRoutes: null,
        direction: null,
      ),
    );
  }
}

/// Manages pre-baked station hub geometries and R-Tree / BBox spatial lookups.
class StopGroupGeometry {
  static final Map<String, String> _cleanNameCache = {};
  static final RegExp _reMPlusH = RegExp(r'\s+M\+H\b', caseSensitive: false);
  static final RegExp _reM = RegExp(r'\s+M\b');
  static final RegExp _reH = RegExp(r'\s+H\b');

  static List<PrebakedStopGroup>? _prebakedGroups;
  static Future<List<PrebakedStopGroup>>? _loadingFuture;

  /// Fast metric distance approximation around Budapest (~47.5° lat).
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    final dLat = (lat1 - lat2) * 111133.0;
    final dLon = (lon1 - lon2) * 75150.0;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  /// Strips transport suffixes, platform brackets, and parentheticals
  /// e.g. "Széll Kálmán tér M (Csaba utca)" -> "Széll Kálmán tér".
  static String cleanStationName(String name) {
    return _cleanNameCache.putIfAbsent(name, () {
      var s = name.trim();
      if (s.endsWith(')')) {
        final idx = s.lastIndexOf('(');
        if (idx != -1) s = s.substring(0, idx).trim();
      }
      if (s.endsWith(']')) {
        final idx = s.lastIndexOf('[');
        if (idx != -1) s = s.substring(0, idx).trim();
      }
      s = s.replaceAll(_reMPlusH, '');
      s = s.replaceAll(_reM, '');
      s = s.replaceAll(_reH, '');
      return s.trim();
    });
  }

  /// Loads pre-baked stop groups once from `assets/db/stop_groups_prebaked.json`.
  static Future<List<PrebakedStopGroup>> ensureLoaded() {
    if (_prebakedGroups != null) return Future.value(_prebakedGroups!);
    return _loadingFuture ??= _loadInternal();
  }

  static Future<List<PrebakedStopGroup>> _loadInternal() async {
    try {
      String raw;
      final localFile = File('assets/db/stop_groups_prebaked.json');
      if (localFile.existsSync()) {
        raw = await localFile.readAsString();
      } else {
        raw = await rootBundle.loadString('assets/db/stop_groups_prebaked.json');
      }
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = List<PrebakedStopGroup>.unmodifiable(
        decoded.map((e) => PrebakedStopGroup.fromJson(e as Map<String, dynamic>)),
      );
      _prebakedGroups = list;
      return list;
    } catch (_) {
      _prebakedGroups = const [];
      return const [];
    }
  }

  /// Queries pre-baked stop groups intersecting the viewport bounding box, ordered from center.
  static Future<List<PrebakedStopGroup>> queryInBbox({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int limit = 90,
  }) async {
    final all = await ensureLoaded();
    if (all.isEmpty) return const [];

    final centerLat = (minLat + maxLat) * 0.5;
    final centerLon = (minLon + maxLon) * 0.5;

    final matches = <PrebakedStopGroup>[];
    for (final g in all) {
      if (g.maxLat >= minLat && g.minLat <= maxLat && g.maxLon >= minLon && g.minLon <= maxLon) {
        matches.add(g);
      }
    }

    matches.sort((a, b) {
      final dA = (a.centroid.latitude - centerLat) * (a.centroid.latitude - centerLat) +
          (a.centroid.longitude - centerLon) * (a.centroid.longitude - centerLon);
      final dB = (b.centroid.latitude - centerLat) * (b.centroid.latitude - centerLat) +
          (b.centroid.longitude - centerLon) * (b.centroid.longitude - centerLon);
      return dA.compareTo(dB);
    });

    if (matches.length > limit) {
      return List<PrebakedStopGroup>.unmodifiable(matches.take(limit));
    }
    return List<PrebakedStopGroup>.unmodifiable(matches);
  }

  /// Builds FlutterMap `Polygon` widgets directly from pre-baked hull coordinates (O(1) per group).
  static List<Polygon> buildPrebakedPolygons(
    List<PrebakedStopGroup> groups, {
    required bool isDarkMode,
  }) {
    if (groups.isEmpty) return const [];

    final fillColor = isDarkMode
        ? const Color.fromRGBO(145, 95, 45, 0.28)
        : const Color.fromRGBO(120, 120, 120, 0.22);
    final strokeColor = isDarkMode
        ? const Color(0xFFC48246)
        : const Color(0xFF707070);
    const strokeWidth = 1.2;

    final polygons = <Polygon>[];
    for (final g in groups) {
      if (g.polygonPoints.length >= 3) {
        polygons.add(
          Polygon(
            points: g.polygonPoints,
            color: fillColor,
            borderColor: strokeColor,
            borderStrokeWidth: strokeWidth,
            strokeJoin: StrokeJoin.round,
            strokeCap: StrokeCap.round,
          ),
        );
      }
    }
    return polygons;
  }
}
