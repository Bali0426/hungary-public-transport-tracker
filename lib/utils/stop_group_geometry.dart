import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';

/// Represents a clustered station hub with its platforms and centroid.
class HubClusterInfo {
  final String name;
  final LatLng centroid;
  final List<StopNode> stops;
  final bool isMultimodal;

  const HubClusterInfo({
    required this.name,
    required this.centroid,
    required this.stops,
    required this.isMultimodal,
  });
}

/// Calculates convex hulls with ~20m rounded buffer zones for BudapestGO-style station hulls.
class StopGroupGeometry {
  static const double _bufferMeters = 20.0;

  /// Fast metric distance approximation around Budapest (~47.5° lat).
  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    final dLat = (lat1 - lat2) * 111133.0;
    final dLon = (lon1 - lon2) * 75150.0;
    return math.sqrt(dLat * dLat + dLon * dLon);
  }

  /// Strips transport suffixes, platform brackets, and parentheticals
  /// e.g. "Széll Kálmán tér M (Csaba utca)" -> "Széll Kálmán tér".
  static String cleanStationName(String name) {
    var s = name.trim();
    if (s.endsWith(')')) {
      final idx = s.lastIndexOf('(');
      if (idx != -1) s = s.substring(0, idx).trim();
    }
    if (s.endsWith(']')) {
      final idx = s.lastIndexOf('[');
      if (idx != -1) s = s.substring(0, idx).trim();
    }
    s = s.replaceAll(RegExp(r'\s+M\+H\b', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\s+M\b'), '');
    s = s.replaceAll(RegExp(r'\s+H\b'), '');
    return s.trim();
  }

  /// Clusters platforms by clean name / hub ID within 150-250m (~220m).
  /// Different named adjacent hubs (e.g. Boráros tér vs Mester utca) remain separate.
  static List<HubClusterInfo> getHubClusters(List<StopNode> platforms) {
    if (platforms.isEmpty) return const [];

    final List<List<StopNode>> clusters = [];

    for (final p in platforms) {
      final pName = cleanStationName(p.name).toLowerCase();
      bool added = false;
      for (final cluster in clusters) {
        final first = cluster.first;
        final clusterName = cleanStationName(first.name).toLowerCase();
        final sameIdentity = (p.hubId != null && p.hubId!.isNotEmpty && p.hubId == first.hubId) ||
            (pName == clusterName);
        if (sameIdentity) {
          final isClose = cluster.any((s) => distanceMeters(s.lat, s.lon, p.lat, p.lon) <= 220.0);
          if (isClose) {
            cluster.add(p);
            added = true;
            break;
          }
        }
      }
      if (!added) {
        clusters.add([p]);
      }
    }

    // Merge clusters that share identity and are within 220m
    bool mergedAny = true;
    while (mergedAny) {
      mergedAny = false;
      for (int i = 0; i < clusters.length; i++) {
        for (int j = i + 1; j < clusters.length; j++) {
          final c1 = clusters[i];
          final c2 = clusters[j];
          final name1 = cleanStationName(c1.first.name).toLowerCase();
          final name2 = cleanStationName(c2.first.name).toLowerCase();
          final sameIdentity = (c1.first.hubId != null && c1.first.hubId!.isNotEmpty && c1.first.hubId == c2.first.hubId) ||
              (name1 == name2);
          if (sameIdentity) {
            final isClose = c1.any((s1) => c2.any((s2) => distanceMeters(s1.lat, s1.lon, s2.lat, s2.lon) <= 220.0));
            if (isClose) {
              c1.addAll(c2);
              clusters.removeAt(j);
              mergedAny = true;
              break;
            }
          }
        }
        if (mergedAny) break;
      }
    }

    return clusters.map((group) {
      double sumLat = 0;
      double sumLon = 0;
      bool isMm = false;
      for (final s in group) {
        sumLat += s.lat;
        sumLon += s.lon;
        if (s.isMultimodalHub) isMm = true;
      }
      final centroid = LatLng(sumLat / group.length, sumLon / group.length);
      return HubClusterInfo(
        name: cleanStationName(group.first.name),
        centroid: centroid,
        stops: group,
        isMultimodal: isMm,
      );
    }).toList();
  }

  static final Map<String, List<LatLng>> _prebakedHullCache = {};

  /// Builds buffered hull polygons styled according to BudapestGO LOD specs.
  static List<Polygon> buildHubPolygons(
    List<StopNode> platforms, {
    required bool isDarkMode,
    double zoom = 15.0,
  }) {
    if (platforms.isEmpty || zoom < 15.0) return const [];

    final clusters = getHubClusters(platforms);

    // Stop group polygon fills: grayish in light mode, brownish in dark mode
    final fillColor = isDarkMode
        ? const Color.fromRGBO(145, 95, 45, 0.28)
        : const Color.fromRGBO(120, 120, 120, 0.22);
    final strokeColor = isDarkMode
        ? const Color(0xFFC48246)
        : const Color(0xFF707070);
    const strokeWidth = 1.2;

    final polygons = <Polygon>[];

    for (final cluster in clusters) {
      if (cluster.stops.length < 2) continue; // Multi-platform hubs receive boundary hull

      final clusterKey = '${cluster.name}_${cluster.stops.length}_${cluster.stops.first.id}';
      final points = _prebakedHullCache.putIfAbsent(
        clusterKey,
        () => _createBufferedConvexHull(cluster.stops, _bufferMeters),
      );

      if (points.length >= 3) {
        polygons.add(
          Polygon(
            points: points,
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

  static List<LatLng> _createBufferedConvexHull(List<StopNode> stops, double bufferM) {
    if (stops.isEmpty) return const [];

    // Filter duplicate or near-identical coordinates
    final uniqueStops = <StopNode>[];
    for (final s in stops) {
      if (!uniqueStops.any((u) => (u.lat - s.lat).abs() < 1e-5 && (u.lon - s.lon).abs() < 1e-5)) {
        uniqueStops.add(s);
      }
    }
    if (uniqueStops.length < 2) return const [];

    double sumLat = 0;
    double sumLon = 0;
    for (final s in uniqueStops) {
      sumLat += s.lat;
      sumLon += s.lon;
    }
    final centerLat = sumLat / uniqueStops.length;
    final centerLon = sumLon / uniqueStops.length;
    final latRad = centerLat * math.pi / 180.0;
    final metersPerDegLat = 111132.954 - 559.822 * math.cos(2 * latRad);
    final metersPerDegLon = 111412.84 * math.cos(latRad);

    final pts = uniqueStops.map((s) {
      final x = (s.lon - centerLon) * metersPerDegLon;
      final y = (s.lat - centerLat) * metersPerDegLat;
      return math.Point<double>(x, y);
    }).toList();

    List<math.Point<double>> hull;
    if (pts.length == 2) {
      hull = [pts[0], pts[1]];
    } else {
      hull = _convexHull2D(pts);
    }

    if (hull.length < 2) return const [];

    final bufferedPts = <math.Point<double>>[];
    final n = hull.length;

    if (n == 2) {
      // 2 points: Rounded stadium capsule
      final p1 = hull[0];
      final p2 = hull[1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 1e-4) return const [];
      final angleBase = math.atan2(dy, dx);

      for (int i = 0; i <= 8; i++) {
        final a = angleBase - math.pi / 2 + (i / 8) * math.pi;
        bufferedPts.add(math.Point<double>(
          p2.x + bufferM * math.cos(a),
          p2.y + bufferM * math.sin(a),
        ));
      }
      for (int i = 0; i <= 8; i++) {
        final a = angleBase + math.pi / 2 + (i / 8) * math.pi;
        bufferedPts.add(math.Point<double>(
          p1.x + bufferM * math.cos(a),
          p1.y + bufferM * math.sin(a),
        ));
      }
    } else {
      // n >= 3: Buffered polygon with rounded corner arcs
      for (int i = 0; i < n; i++) {
        final prev = hull[(i - 1 + n) % n];
        final curr = hull[i];
        final next = hull[(i + 1) % n];

        final d1x = curr.x - prev.x;
        final d1y = curr.y - prev.y;
        final len1 = math.sqrt(d1x * d1x + d1y * d1y);
        final n1x = (len1 > 1e-4) ? d1y / len1 : 0.0;
        final n1y = (len1 > 1e-4) ? -d1x / len1 : 0.0;

        final d2x = next.x - curr.x;
        final d2y = next.y - curr.y;
        final len2 = math.sqrt(d2x * d2x + d2y * d2y);
        final n2x = (len2 > 1e-4) ? d2y / len2 : 0.0;
        final n2y = (len2 > 1e-4) ? -d2x / len2 : 0.0;

        var a1 = math.atan2(n1y, n1x);
        var a2 = math.atan2(n2y, n2x);
        while (a2 < a1) {
          a2 += 2 * math.pi;
        }

        const steps = 3;
        for (int s = 0; s <= steps; s++) {
          final t = s / steps;
          final a = a1 + t * (a2 - a1);
          bufferedPts.add(math.Point<double>(
            curr.x + bufferM * math.cos(a),
            curr.y + bufferM * math.sin(a),
          ));
        }
      }
    }

    return bufferedPts.map((p) {
      final lat = centerLat + (p.y / metersPerDegLat);
      final lon = centerLon + (p.x / metersPerDegLon);
      return LatLng(lat, lon);
    }).toList();
  }

  static List<math.Point<double>> _convexHull2D(List<math.Point<double>> points) {
    final pts = List<math.Point<double>>.from(points);
    pts.sort((a, b) {
      if (a.x != b.x) return a.x.compareTo(b.x);
      return a.y.compareTo(b.y);
    });

    final unique = <math.Point<double>>[];
    for (final p in pts) {
      if (unique.isEmpty || (unique.last.x - p.x).abs() > 1e-6 || (unique.last.y - p.y).abs() > 1e-6) {
        unique.add(p);
      }
    }
    if (unique.length <= 2) return unique;

    double cross(math.Point<double> o, math.Point<double> a, math.Point<double> b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final lower = <math.Point<double>>[];
    for (final p in unique) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <math.Point<double>>[];
    for (int i = unique.length - 1; i >= 0; i--) {
      final p = unique[i];
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }
}
