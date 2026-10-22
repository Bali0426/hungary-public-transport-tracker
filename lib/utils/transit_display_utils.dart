import 'package:flutter/material.dart';

/// Returns standard Material icon for a transit mode.
IconData getModeIconData(String mode) {
  final m = mode.toLowerCase();
  return switch (m) {
    'tram' => Icons.tram,
    'metro' || 'subway' => Icons.subway,
    'trolley' || 'trolleybus' => Icons.electric_bolt,
    'train' || 'rail' => Icons.train,
    'suburban_rail' || 'hev' => Icons.directions_railway,
    'boat' || 'ferry' => Icons.directions_boat,
    _ => Icons.directions_bus,
  };
}

/// Returns authentic BKK / MÁV branding color for a transit mode.
Color getModeBadgeColor(String mode) {
  final m = mode.toLowerCase();
  return switch (m) {
    'tram' => const Color(0xFFD97706), // BKK Tram amber/yellow
    'metro' || 'subway' => const Color(0xFF2563EB), // Metro deep blue
    'trolley' || 'trolleybus' => const Color(0xFFDC2626), // BKK Trolley red
    'train' || 'rail' => const Color(0xFF0057B8), // MÁV Train royal blue
    'suburban_rail' || 'hev' => const Color(0xFF16A34A), // HÉV green
    'boat' || 'ferry' => const Color(0xFF7C3AED), // Boat purple
    _ => const Color(0xFF009EE3), // BKK Bus sky blue
  };
}
