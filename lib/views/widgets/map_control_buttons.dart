import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/live_vehicles_provider.dart';

/// Floating toggle button to cycle stops/platform layers on the map.
class StopsLayerToggleButton extends ConsumerWidget {
  final VoidCallback? onToggle;

  const StopsLayerToggleButton({super.key, this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGroups = ref.watch(showStopGroupsProvider);
    final showPlatforms = ref.watch(showPlatformsProvider);
    final anyActive = showGroups || showPlatforms;

    return FloatingActionButton.small(
      heroTag: 'stops_toggle_fab',
      tooltip: anyActive
          ? (showGroups && showPlatforms
              ? 'Megállók kikapcsolása'
              : 'Peronok bekapcsolása')
          : 'Megállók bekapcsolása (OSM)',
      backgroundColor: anyActive ? const Color(0xFF818CF8) : const Color(0xE60F172A),
      foregroundColor: Colors.white,
      onPressed: () {
        if (!showGroups && !showPlatforms) {
          ref.read(showStopGroupsProvider.notifier).state = true;
        } else if (showGroups && !showPlatforms) {
          ref.read(showPlatformsProvider.notifier).state = true;
        } else {
          ref.read(showStopGroupsProvider.notifier).state = false;
          ref.read(showPlatformsProvider.notifier).state = false;
        }
        onToggle?.call();
      },
      child: Icon(anyActive ? Icons.place : Icons.place_outlined, size: 20),
    );
  }
}

/// Floating toggle button for Map dark mode / standard light mode.
class DarkModeToggleButton extends ConsumerWidget {
  const DarkModeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(mapDarkModeProvider);

    return FloatingActionButton.small(
      heroTag: 'dark_mode_toggle',
      tooltip: isDark ? 'Világos mód' : 'Sötét térkép mód',
      backgroundColor: const Color(0xE60F172A),
      foregroundColor: isDark ? const Color(0xFFEAB308) : Colors.white70,
      onPressed: () {
        ref.read(mapDarkModeProvider.notifier).state = !isDark;
      },
      child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, size: 20),
    );
  }
}
