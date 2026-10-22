import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/live_vehicles_provider.dart';

/// Floating Action Button to center map to user's current GPS location or default Budapest center.
class MyLocationButton extends StatelessWidget {
  final VoidCallback? onLocationRequested;
  final void Function(double lat, double lon)? onMoveToLocation;

  const MyLocationButton({
    super.key,
    this.onLocationRequested,
    this.onMoveToLocation,
  });

  static const double defaultLat = 47.4979; // Central Budapest
  static const double defaultLon = 19.0402;

  void _handleLocation(BuildContext context) {
    if (onMoveToLocation != null) {
      onMoveToLocation!(defaultLat, defaultLon);
    } else {
      onLocationRequested?.call();
    }

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ugrás a jelenlegi pozícióra (Budapest)'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FloatingActionButton.small(
      heroTag: 'my_location_fab',
      tooltip: 'Jelenlegi pozíció (GPS)',
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      foregroundColor: theme.colorScheme.primary,
      onPressed: () => _handleLocation(context),
      child: const Icon(Icons.my_location, size: 20),
    );
  }
}

/// Floating toggle button legacy alias/wrapper converted to GPS location button.
class StopsLayerToggleButton extends StatelessWidget {
  final VoidCallback? onToggle;
  final void Function(double lat, double lon)? onMoveToLocation;

  const StopsLayerToggleButton({
    super.key,
    this.onToggle,
    this.onMoveToLocation,
  });

  @override
  Widget build(BuildContext context) {
    return MyLocationButton(
      onLocationRequested: onToggle,
      onMoveToLocation: onMoveToLocation,
    );
  }
}

/// Floating toggle button for Map dark mode / standard light mode.
class DarkModeToggleButton extends ConsumerWidget {
  const DarkModeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(mapDarkModeProvider);
    final theme = Theme.of(context);

    return FloatingActionButton.small(
      heroTag: 'dark_mode_toggle',
      tooltip: isDark ? 'Világos mód' : 'Sötét térkép mód',
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      foregroundColor: isDark ? Colors.amber : theme.colorScheme.onSurfaceVariant,
      onPressed: () {
        ref.read(mapDarkModeProvider.notifier).state = !isDark;
      },
      child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, size: 20),
    );
  }
}
