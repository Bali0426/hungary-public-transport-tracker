import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/live_vehicles_provider.dart';

/// Bottom-Left Status Pill displaying real-time live vehicle metrics and opening the API Hub.
class LiveFeedStatusPill extends ConsumerWidget {
  final VoidCallback onToggleDirectory;

  const LiveFeedStatusPill({
    super.key,
    required this.onToggleDirectory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(liveVehiclesGeoJsonProvider);
    final counts = ref.watch(liveVehicleCountsProvider);
    final renderedCount = ref.watch(renderedVehiclesCountProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: theme.colorScheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: feedAsync.when(
        data: (_) {
          return InkWell(
            onTap: onToggleDirectory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 9, color: Color(0xFF22C55E)),
                  const SizedBox(width: 8),
                  Text(
                    '$renderedCount megjelenítve / ${counts.total} aktív (BKK: ${counts.bkk} | MÁV: ${counts.mav})',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: onToggleDirectory,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.tune, size: 13),
                    label: const Text('API & Források', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          );
        },
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'BKK & MÁV járművek lekérése...',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        error: (err, _) => InkWell(
          onTap: onToggleDirectory,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'API kapcsolat ellenőrzése',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: onToggleDirectory,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Beállítás', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
