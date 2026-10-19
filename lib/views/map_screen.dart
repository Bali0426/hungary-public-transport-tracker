import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';
import '../providers/live_vehicles_provider.dart';
import 'line_search_delegate.dart';
import 'station_detail_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();

  static const LatLng _budapestCenter = LatLng(47.4979, 19.0402);

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    final bounds = camera.visibleBounds;
    ref.read(viewportBboxProvider.notifier).state = ViewportBbox(
      minLat: bounds.south,
      minLon: bounds.west,
      maxLat: bounds.north,
      maxLon: bounds.east,
    );
  }

  void _openStationSheet(StopNode station) {
    _mapController.move(LatLng(station.lat, station.lon), 15.0);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StationDetailSheet(station: station),
    );
  }

  void _onVehicleTapped(Map<String, dynamic> props) {
    final lineName = props['line_name'] ?? 'Transit';
    final dest = props['destination'] ?? '';
    final operator = props['operator'] ?? 'BKK';
    final type = props['vehicle_type'] ?? 'bus';
    final delay = props['delay_seconds'] ?? 0;
    final mins = (delay / 60).round();
    final delayText = mins <= 0 ? 'Pontos' : '+$mins perc késés';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        content: Row(
          children: [
            _getModeIcon(type, color: Colors.lightBlueAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '[$operator] $lineName -> ${dest.isNotEmpty ? dest : "Menetrend szerinti út"} ($delayText)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  List<Marker> _buildVehicleMarkers(String geoJsonStr, Set<String> enabledModes) {
    if (geoJsonStr.isEmpty) return const [];
    try {
      final data = jsonDecode(geoJsonStr) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      final markers = <Marker>[];

      for (final f in features) {
        final feat = f as Map<String, dynamic>;
        final geom = feat['geometry'] as Map<String, dynamic>?;
        final props = feat['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;

        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.length < 2) continue;

        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        final lineName = props['line_name'] as String? ?? '';
        final delayBucket = props['delay_bucket'] as String? ?? 'on_time';
        final vType = props['vehicle_type'] as String? ?? 'bus';

        // Apply transit mode filter
        if (!enabledModes.contains(vType)) {
          continue;
        }

        final Color dotColor = switch (delayBucket) {
          'minor_delay' => const Color(0xFFEAB308),
          'major_delay' => const Color(0xFFEF4444),
          _ => const Color(0xFF22C55E),
        };

        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 46,
            height: 38,
            child: GestureDetector(
              onTap: () => _onVehicleTapped(props),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: dotColor, width: 1.5),
                    ),
                    child: Text(
                      lineName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: dotColor.withValues(alpha: 0.7),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return markers;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveVehiclesAsync = ref.watch(liveVehiclesGeoJsonProvider);
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final isDarkMode = ref.watch(mapDarkModeProvider);

    final vehicleMarkers = liveVehiclesAsync.maybeWhen(
      data: (geojson) => _buildVehicleMarkers(geojson, enabledModes),
      orElse: () => const <Marker>[],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: const Text(
          'Hungary Transit Tracker (BKK + MÁV)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            tooltip: 'Search Stations & Multimodal Hubs',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final selected = await showSearch<StopNode?>(
                context: context,
                delegate: LineAndStopSearchDelegate(ref),
              );
              if (selected != null && mounted) {
                _openStationSheet(selected);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _budapestCenter,
              initialZoom: 12.5,
              onPositionChanged: _onPositionChanged,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: isDarkMode
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: isDarkMode ? const ['a', 'b', 'c', 'd'] : const [],
                userAgentPackageName: 'hungary.public.transport.tracker',
              ),
              MarkerLayer(markers: vehicleMarkers),
            ],
          ),

          // Bottom-Left Status Pill with Expandable Data Source details
          const Positioned(
            left: 16,
            bottom: 24,
            child: _LiveFeedStatusPill(),
          ),

          // Top-Right & Bottom-Right Control Panel
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Dark Mode Toggle Button
                _DarkModeToggleButton(),
                const SizedBox(height: 12),
                // Transit Modes Visibility Filter Menu Button
                _TransitModesFilterMenu(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dark Mode Toggle Button
// ---------------------------------------------------------------------------
class _DarkModeToggleButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(mapDarkModeProvider);

    return FloatingActionButton.small(
      heroTag: 'map_theme_toggle',
      tooltip: isDark ? 'Váltás világos térképre' : 'Váltás sötét térképre',
      backgroundColor: const Color(0xE60F172A),
      foregroundColor: isDark ? const Color(0xFFFACC15) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white24, width: 1),
      ),
      onPressed: () {
        ref.read(mapDarkModeProvider.notifier).state = !isDark;
      },
      child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, size: 20),
    );
  }
}

// ---------------------------------------------------------------------------
// Transit Modes Filter Menu (Bus, Tram, Metro, Trolley, Train, HÉV, Boat)
// ---------------------------------------------------------------------------
class _TransitModesFilterMenu extends ConsumerWidget {
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

    return PopupMenuButton<String>(
      tooltip: 'Közlekedési módok szűrése',
      offset: const Offset(0, -290),
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white24, width: 1),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xE60F172A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              'Módok (${enabledModes.length}/${_modes.length})',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        return [
          const PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'Közlekedési módok',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ..._modes.entries.map((entry) {
            final key = entry.key;
            final item = entry.value;
            final isSelected = enabledModes.contains(key);

            return PopupMenuItem<String>(
              value: key,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return InkWell(
                    onTap: () {
                      final updated = Set<String>.from(enabledModes);
                      if (isSelected) {
                        updated.remove(key);
                      } else {
                        updated.add(key);
                      }
                      ref.read(enabledTransitModesProvider.notifier).state = updated;
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 18,
                            color: isSelected ? const Color(0xFF009EE3) : Colors.white38,
                          ),
                          const SizedBox(width: 10),
                          Icon(item.icon, size: 18, color: Colors.white70),
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ];
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom-Left Status Pill with Expandable Data Source Details
// ---------------------------------------------------------------------------
class _LiveFeedStatusPill extends ConsumerStatefulWidget {
  const _LiveFeedStatusPill();

  @override
  ConsumerState<_LiveFeedStatusPill> createState() => _LiveFeedStatusPillState();
}

class _LiveFeedStatusPillState extends ConsumerState<_LiveFeedStatusPill> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(liveVehiclesGeoJsonProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF20F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: feedAsync.when(
        data: (raw) {
          int bkkCount = 0;
          int mavCount = 0;
          try {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final features = map['features'] as List<dynamic>? ?? const [];
            for (final f in features) {
              final p = (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
              if (p['operator'] == 'MAV') {
                mavCount++;
              } else {
                bkkCount++;
              }
            }
          } catch (_) {}
          final total = bkkCount + mavCount;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 10, color: Color(0xFF22C55E)),
                      const SizedBox(width: 8),
                      Text(
                        '$total aktív jármű',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                        size: 18,
                        color: Colors.white60,
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const Divider(height: 1, color: Colors.white12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ADATFORRÁSOK',
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _DataSourceRow(
                        operatorName: 'BKK FUTÁR',
                        count: bkkCount,
                        badgeColor: const Color(0xFF009EE3),
                        status: 'Élő Protobuf (GTFS-RT)',
                      ),
                      const SizedBox(height: 6),
                      _DataSourceRow(
                        operatorName: 'MÁV-START',
                        count: mavCount,
                        badgeColor: const Color(0xFF0057B8),
                        status: 'Élő EMMA / GTFS-RT',
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'BKK & MÁV járművek lekérése...',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        error: (err, _) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber, size: 14, color: Colors.amber),
              SizedBox(width: 6),
              Text(
                'Adatfolyam elérhetetlen',
                style: TextStyle(color: Colors.amber, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DataSourceRow extends StatelessWidget {
  final String operatorName;
  final int count;
  final Color badgeColor;
  final String status;

  const _DataSourceRow({
    required this.operatorName,
    required this.count,
    required this.badgeColor,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            operatorName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$count db',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '($status)',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

Icon _getModeIcon(String mode, {Color? color, double size = 16}) {
  final icon = switch (mode) {
    'tram' => Icons.tram,
    'metro' => Icons.subway,
    'trolley' => Icons.electric_bolt,
    'train' => Icons.train,
    'suburban_rail' => Icons.directions_railway,
    'boat' => Icons.directions_boat,
    _ => Icons.directions_bus,
  };
  return Icon(icon, color: color, size: size);
}
