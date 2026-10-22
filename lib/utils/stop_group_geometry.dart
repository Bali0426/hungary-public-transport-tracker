import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';

/// Calculates convex hulls with metric rounded buffer zones for OSM-style station cluster enclosures ("bekerítve").
class StopGroupGeometry {
  static const double _bufferMeters = 24.0;

  static List<Polygon> buildHubPolygons(
    List<StopNode> platforms, {
    required bool isDarkMode,
  }) {
    if (platforms.isEmpty) return const [];

    final Map<String, List<StopNode>> hubGroups = {};
    for (final p in platforms) {
      if (p.hubId != null && p.hubId!.isNotEmpty) {
        hubGroups.putIfAbsent(p.hubId!, () => []).add(p);
      } else {
        // Group by name + spatial proximity (within ~300 meters)
        bool added = false;
        for (final entry in hubGroups.entries) {
          if (entry.value.first.name == p.name) {
            final first = entry.value.first;
            final dLat = (first.lat - p.lat).abs();
            final dLon = (first.lon - p.lon).abs();
            if (dLat < 0.003 && dLon < 0.004) {
              entry.value.add(p);
              added = true;
              break;
            }
          }
        }
        if (!added) {
          hubGroups['${p.name}_${p.lat.toStringAsFixed(3)}_${p.lon.toStringAsFixed(3)}'] = [p];
        }
      }
    }

    final polygons = <Polygon>[];
    final fillColor = isDarkMode
        ? const Color(0x3064748B) // Slate translucent fill (~19% opacity)
        : const Color(0x2864748B);
    final strokeColor = isDarkMode
        ? const Color(0x8C94A3B8) // Slate subtle stroke
        : const Color(0xA6475569);

    for (final entry in hubGroups.entries) {
      final stops = entry.value;
      if (stops.length < 2) continue; // Multi-platform hubs receive an enclosed station boundary

      final points = _createBufferedConvexHull(stops, _bufferMeters);
      if (points.length >= 3) {
        polygons.add(
          Polygon(
            points: points,
            color: fillColor,
            borderColor: strokeColor,
            borderStrokeWidth: 1.5,
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

    double sumLat = 0;
    double sumLon = 0;
    for (final s in stops) {
      sumLat += s.lat;
      sumLon += s.lon;
    }
    final centerLat = sumLat / stops.length;
    final centerLon = sumLon / stops.length;
    final latRad = centerLat * math.pi / 180.0;
    final metersPerDegLat = 111132.954 - 559.822 * math.cos(2 * latRad);
    final metersPerDegLon = 111412.84 * math.cos(latRad);

    final pts = stops.map((s) {
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
