import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/live_vehicles_provider.dart';

/// Bottom-Right Floating Menu to toggle transit mode filters and stop/platform layers.
class MapLayersFloatingMenu extends ConsumerWidget {
  final VoidCallback onClose;
  final VoidCallback? onStopsEnabled;

  const MapLayersFloatingMenu({
    super.key,
    required this.onClose,
    this.onStopsEnabled,
  });

  static const Map<String, ({String label, IconData icon})> _modes = {
    'bus': (label: 'Busz', icon: Icons.directions_bus),
    'tram': (label: 'Villamos', icon: Icons.tram),
    'metro': (label: 'Metró', icon: Icons.subway),
    'trolley': (label: 'Trolibusz', icon: Icons.electric_bolt),
    'train': (label: 'MÁV Vonat', icon: Icons.train),
    'suburban_rail': (label: 'HÉV', icon: Icons.directions_railway),
    'boat': (label: 'Hajó', icon: Icons.directions_boat),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final showStopGroups = ref.watch(showStopGroupsProvider);
    final showPlatforms = ref.watch(showPlatformsProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF50F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.layers, size: 16, color: Color(0xFF38BDF8)),
                    SizedBox(width: 8),
                    Text(
                      'Térképrétegek és szűrők',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white60),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.70,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1 Header: Transit Modes (Vehicles)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_transit, size: 13, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 6),
                        Text(
                          'KÖZLEKEDÉSI MÓDOK (JÁRMŰVEK)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Vehicle Mode Checkboxes
                  ..._modes.entries.map((entry) {
                    final key = entry.key;
                    final item = entry.value;
                    final isChecked = enabledModes.contains(key);

                    return InkWell(
                      onTap: () {
                        final updated = Set<String>.from(enabledModes);
                        if (isChecked) {
                          updated.remove(key);
                        } else {
                          updated.add(key);
                        }
                        ref.read(enabledTransitModesProvider.notifier).state = updated;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        child: Row(
                          children: [
                            Icon(
                              isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 17,
                              color: isChecked ? const Color(0xFF009EE3) : Colors.white38,
                            ),
                            const SizedBox(width: 10),
                            Icon(item.icon, size: 17, color: isChecked ? Colors.white : Colors.white54),
                            const SizedBox(width: 8),
                            Text(
                              item.label,
                              style: TextStyle(
                                color: isChecked ? Colors.white : Colors.white60,
                                fontSize: 12.5,
                                fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Divider(height: 1, color: Colors.white12),
                  ),

                  // Section 2 Header: Stops & Platforms (OSM)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.place, size: 13, color: Color(0xFF818CF8)),
                        const SizedBox(width: 6),
                        Text(
                          'MEGÁLLÓK & ÁLLOMÁSOK (OSM)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Stop Groups Toggle
                  InkWell(
                    onTap: () {
                      final next = !showStopGroups;
                      ref.read(showStopGroupsProvider.notifier).state = next;
                      if (next) onStopsEnabled?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            showStopGroups ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 17,
                            color: showStopGroups ? const Color(0xFF818CF8) : Colors.white38,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.hub,
                            size: 17,
                            color: showStopGroups ? const Color(0xFF818CF8) : Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Megállócsoportok',
                                  style: TextStyle(
                                    color: showStopGroups ? Colors.white : Colors.white60,
                                    fontSize: 12.5,
                                    fontWeight: showStopGroups ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  'Összevont állomáscsomópontok',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Individual Platforms / Directions Toggle
                  InkWell(
                    onTap: () {
                      final next = !showPlatforms;
                      ref.read(showPlatformsProvider.notifier).state = next;
                      if (next) onStopsEnabled?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            showPlatforms ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 17,
                            color: showPlatforms ? const Color(0xFF38BDF8) : Colors.white38,
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.signpost_outlined,
                            size: 17,
                            color: showPlatforms ? const Color(0xFF38BDF8) : Colors.white54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Peronok / Irányok',
                                  style: TextStyle(
                                    color: showPlatforms ? Colors.white : Colors.white60,
                                    fontSize: 12.5,
                                    fontWeight: showPlatforms ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                Text(
                                  'Külön menetirányok és vágányok',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
