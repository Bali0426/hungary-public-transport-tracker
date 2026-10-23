import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/live_vehicles_provider.dart';
import '../../providers/transit_lines_provider.dart';
import '../../utils/transit_display_utils.dart';

/// Extension to format OpenRailwayMap style titles and tile URLs.
extension OpenRailwayMapStyleDisplay on OpenRailwayMapStyle {
  String get displayTitle {
    switch (this) {
      case OpenRailwayMapStyle.standard:
        return 'Infrastructure (Vasúti pálya)';
      case OpenRailwayMapStyle.maxspeed:
        return 'Max speeds (Pályasebesség)';
      case OpenRailwayMapStyle.signals:
        return 'Signalling and train protection (Jelzők & Biztosítóberendezés)';
      case OpenRailwayMapStyle.electrification:
        return 'Electrification (Villamosítás)';
      case OpenRailwayMapStyle.gauge:
        return 'Track gauge (Nyomtáv)';
    }
  }

  String get tileUrlTemplate {
    switch (this) {
      case OpenRailwayMapStyle.standard:
        return 'https://{s}.tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.maxspeed:
        return 'https://{s}.tiles.openrailwaymap.org/maxspeed/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.signals:
        return 'https://{s}.tiles.openrailwaymap.org/signals/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.electrification:
        return 'https://{s}.tiles.openrailwaymap.org/electrification/{z}/{x}/{y}.png';
      case OpenRailwayMapStyle.gauge:
        return 'https://{s}.tiles.openrailwaymap.org/gauge/{z}/{x}/{y}.png';
    }
  }
}

/// Bottom-Right Floating Menu to toggle transit mode filters, stop layers, and railway/transit lines.
class MapLayersFloatingMenu extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final VoidCallback? onStopsEnabled;

  const MapLayersFloatingMenu({
    super.key,
    required this.onClose,
    this.onStopsEnabled,
  });

  @override
  ConsumerState<MapLayersFloatingMenu> createState() => _MapLayersFloatingMenuState();
}

class _MapLayersFloatingMenuState extends ConsumerState<MapLayersFloatingMenu> {
  bool _isRailwayStylesExpanded = false;

  static const Map<String, String> _modes = {
    'bus': 'Busz',
    'tram': 'Villamos',
    'metro': 'Metró',
    'trolley': 'Trolibusz',
    'train': 'MÁV Vonat',
    'suburban_rail': 'HÉV',
    'boat': 'Hajó',
  };

  static Widget _metroDot(String label, Color color, Color textColor) {
    return Container(
      margin: const EdgeInsets.only(right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 0.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLiveVehicles = ref.watch(showLiveVehiclesProvider);
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final showStopGroups = ref.watch(showStopGroupsProvider);
    final showPlatforms = ref.watch(showPlatformsProvider);

    final showOpenRailwayMap = ref.watch(showOpenRailwayMapProvider);
    final railwayStyle = ref.watch(openRailwayMapStyleProvider);
    final showMetroLines = ref.watch(showMetroLinesProvider);
    final showHevLines = ref.watch(showHevLinesProvider);
    final showTramLines = ref.watch(showTramLinesProvider);

    final theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.layers, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Térképrétegek és szűrők',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(420.0, MediaQuery.sizeOf(context).height - 90.0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Oszlop: Járművek és Megállók
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 380,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section 1 Header: Transit Modes (Vehicles)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                              child: Row(
                                children: [
                                  Icon(Icons.directions_transit, size: 14, color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'KÖZLEKEDÉSI MÓDOK',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Overall live vehicles master toggle (matching stop switch size & style)
                            SwitchListTile.adaptive(
                              value: showLiveVehicles,
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              secondary: Icon(
                                Icons.directions_bus,
                                size: 16,
                                color: showLiveVehicles ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              ),
                              title: const Text(
                                'Járművek réteg',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                showLiveVehicles ? 'Járművek megjelenítve' : 'Járművek kikapcsolva',
                                style: const TextStyle(fontSize: 9.5),
                              ),
                              onChanged: (val) {
                                ref.read(showLiveVehiclesProvider.notifier).state = val;
                              },
                            ),
                            const SizedBox(height: 4),

                            // Vehicle Mode 2-column cards with neutral toggle switches (7 individual modes, no "Mind")
                            Opacity(
                              opacity: showLiveVehicles ? 1.0 : 0.45,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final itemWidth = math.max(
                                    80.0,
                                    ((constraints.maxWidth - 6) / 2).floorToDouble(),
                                  );
                                  return Wrap(
                                    spacing: 6,
                                    runSpacing: 5,
                                    children: _modes.entries.map((entry) {
                                      final key = entry.key;
                                      final label = entry.value;
                                      final isChecked = enabledModes.contains(key);
                                      final badgeColor = getModeBadgeColor(key);

                                      return SizedBox(
                                        width: itemWidth,
                                        child: InkWell(
                                          onTap: () {
                                            final updated = Set<String>.from(enabledModes);
                                            if (!isChecked) {
                                              updated.add(key);
                                            } else {
                                              updated.remove(key);
                                            }
                                            ref.read(enabledTransitModesProvider.notifier).state = updated;
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 150),
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: isChecked
                                                  ? badgeColor.withValues(alpha: 0.10)
                                                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isChecked
                                                    ? badgeColor.withValues(alpha: 0.7)
                                                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                                                width: 1.2,
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                TransitModeCircleIcon(mode: key, size: 15),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    label,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: isChecked ? FontWeight.w600 : FontWeight.w500,
                                                      color: theme.colorScheme.onSurface,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 2),
                                                _CompactNeutralToggle(
                                                  value: isChecked,
                                                  onChanged: (val) {
                                                    final updated = Set<String>.from(enabledModes);
                                                    if (val) {
                                                      updated.add(key);
                                                    } else {
                                                      updated.remove(key);
                                                    }
                                                    ref.read(enabledTransitModesProvider.notifier).state = updated;
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ),

                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(height: 1),
                            ),

                            // Section 2 Header: Stops & Platforms (OSM)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                              child: Row(
                                children: [
                                  Icon(Icons.place, size: 14, color: theme.colorScheme.secondary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'MEGÁLLÓK & ÁLLOMÁSOK',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Stop Groups Switch
                            SwitchListTile.adaptive(
                              value: showStopGroups,
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              secondary: Icon(
                                Icons.hub,
                                size: 16,
                                color: showStopGroups ? theme.colorScheme.secondary : theme.colorScheme.onSurfaceVariant,
                              ),
                              title: const Text('Megállócsoportok', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Összevont csomópontok', style: TextStyle(fontSize: 9.5)),
                              onChanged: (next) {
                                ref.read(showStopGroupsProvider.notifier).state = next;
                                if (next) widget.onStopsEnabled?.call();
                              },
                            ),

                            // Individual Platforms Switch
                            SwitchListTile.adaptive(
                              value: showPlatforms,
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              secondary: Icon(
                                Icons.signpost_outlined,
                                size: 16,
                                color: showPlatforms ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                              ),
                              title: const Text('Peronok / Irányok', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                              subtitle: const Text('Külön vágányok és táblák', style: TextStyle(fontSize: 9.5)),
                              onChanged: (next) {
                                ref.read(showPlatformsProvider.notifier).state = next;
                                if (next) widget.onStopsEnabled?.call();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Vertical divider between the two columns
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      width: 1,
                      height: 360,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),

                  // 2. Oszlop: Vasúti & Hálózati Vonalak (Infrastruktúra)
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 380,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
                              child: Row(
                                children: [
                                  Icon(Icons.alt_route, size: 14, color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'VASÚTI & HÁLÓZATI VONALAK',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // OpenRailwayMap inline expandable tile with large toggle
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: showOpenRailwayMap
                                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: showOpenRailwayMap
                                      ? theme.colorScheme.primary.withValues(alpha: 0.45)
                                      : Colors.transparent,
                                  width: 1,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _isRailwayStylesExpanded = !_isRailwayStylesExpanded;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.layers,
                                            size: 16,
                                            color: showOpenRailwayMap
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'OpenRailwayMap Vasúti Térkép',
                                                  style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w600),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  _isRailwayStylesExpanded
                                                      ? '▲ ${railwayStyle.displayTitle.split(' (')[0]}'
                                                      : '▼ ${railwayStyle.displayTitle.split(' (')[0]}',
                                                  style: TextStyle(
                                                    fontSize: 9.0,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch.adaptive(
                                            value: showOpenRailwayMap,
                                            onChanged: (val) {
                                              ref.read(showOpenRailwayMapProvider.notifier).state = val;
                                              if (val && !_isRailwayStylesExpanded) {
                                                setState(() {
                                                  _isRailwayStylesExpanded = true;
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_isRailwayStylesExpanded) ...[
                                    const Divider(height: 1, indent: 8, endIndent: 8),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Térkép stílusa:',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          ...OpenRailwayMapStyle.values.map((style) {
                                            final isSelected = style == railwayStyle;
                                            return InkWell(
                                              onTap: () {
                                                ref.read(openRailwayMapStyleProvider.notifier).state = style;
                                                ref.read(showOpenRailwayMapProvider.notifier).state = true;
                                              },
                                              borderRadius: BorderRadius.circular(6),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                                      size: 14,
                                                      color: isSelected
                                                          ? theme.colorScheme.primary
                                                          : theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        style.displayTitle,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                          color: isSelected
                                                              ? theme.colorScheme.primary
                                                              : theme.colorScheme.onSurface,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                              // Metróvonalak toggle (M1 sárga, M2 piros, M3 kék, M4 zöld) - pixelhiba mentes, tördelhető pettyekkel
                              SwitchListTile.adaptive(
                                value: showMetroLines,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                secondary: Icon(
                                  Icons.directions_subway,
                                  size: 16,
                                  color: showMetroLines ? const Color(0xFFE41F18) : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: const Text(
                                  'Metróvonalak',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Wrap(
                                    spacing: 2,
                                    runSpacing: 2,
                                    children: [
                                      _metroDot('M1', const Color(0xFFFFD800), Colors.black),
                                      _metroDot('M2', const Color(0xFFE41F18), Colors.white),
                                      _metroDot('M3', const Color(0xFF005CA5), Colors.white),
                                      _metroDot('M4', const Color(0xFF439539), Colors.white),
                                    ],
                                  ),
                                ),
                                onChanged: (val) {
                                  ref.read(showMetroLinesProvider.notifier).state = val;
                                },
                              ),

                              // HÉV vonalak toggle
                              SwitchListTile.adaptive(
                                value: showHevLines,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                secondary: Icon(
                                  Icons.directions_railway,
                                  size: 16,
                                  color: showHevLines ? const Color(0xFF821380) : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('HÉV vonalak', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                subtitle: const Text('H5, H6, H7, H8, H9', style: TextStyle(fontSize: 9.5)),
                                onChanged: (val) {
                                  ref.read(showHevLinesProvider.notifier).state = val;
                                },
                              ),

                              // Villamosvonalak toggle
                              SwitchListTile.adaptive(
                                value: showTramLines,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                secondary: Icon(
                                  Icons.tram,
                                  size: 16,
                                  color: showTramLines ? const Color(0xFFFFD900) : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: const Text('Villamosvonalak', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                                subtitle: const Text('Főbb villamosvonalak', style: TextStyle(fontSize: 9.5)),
                                onChanged: (val) {
                                  ref.read(showTramLinesProvider.notifier).state = val;
                                },
                              ),
                            ],
                          ),
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

/// Neutral Material You style compact toggle switch.
class _CompactNeutralToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactNeutralToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackColor = value
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
        : theme.colorScheme.surfaceContainerHighest;
    final thumbColor = value
        ? theme.colorScheme.onSurface
        : theme.colorScheme.outline;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 30,
        height: 17,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: trackColor,
          border: Border.all(
            color: value
                ? theme.colorScheme.outline.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: thumbColor,
          ),
        ),
      ),
    );
  }
}
