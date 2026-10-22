import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';
import '../providers/live_vehicles_provider.dart';
import '../utils/stop_group_geometry.dart';
import '../utils/transit_display_utils.dart';
import 'line_search_delegate.dart';
import 'widgets/data_sources_card.dart';
import 'widgets/live_feed_status_pill.dart';
import 'widgets/map_control_buttons.dart';
import 'widgets/map_layers_menu.dart';
import 'widgets/station_detail_card.dart';
import 'widgets/vehicle_detail_card.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();

  static const LatLng _budapestCenter = LatLng(47.4979, 19.0402);

  Map<String, dynamic>? _selectedVehicle;
  StopNode? _selectedStation;
  bool _showLayersMenu = false;
  bool _showDataSourcesModal = false;

  Timer? _cameraDebounce;
  String _lastDecodedGeoJson = '';
  List<dynamic> _cachedFeatures = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _updateViewportNow();
      }
    });
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    if (!ref.read(showStopGroupsProvider) && !ref.read(showPlatformsProvider)) return;
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final bounds = camera.visibleBounds;
      ref.read(viewportBboxProvider.notifier).state = ViewportBbox(
        minLat: bounds.south,
        minLon: bounds.west,
        maxLat: bounds.north,
        maxLon: bounds.east,
      );
    });
  }

  void _updateViewportNow() {
    final bounds = _mapController.camera.visibleBounds;
    ref.read(viewportBboxProvider.notifier).state = ViewportBbox(
      minLat: bounds.south,
      minLon: bounds.west,
      maxLat: bounds.north,
      maxLon: bounds.east,
    );
  }

  void _onStationTapped(StopNode station) {
    setState(() {
      _selectedStation = station;
      _selectedVehicle = null;
    });
    _mapController.move(
      LatLng(station.lat, station.lon),
      _mapController.camera.zoom.clamp(14.0, 18.0),
    );
  }

  void _onVehicleTapped(Map<String, dynamic> props) {
    setState(() {
      _selectedVehicle = props;
      _selectedStation = null;
    });
  }

  List<Marker> _buildVehicleMarkers(String geoJsonStr, Set<String> enabledModes) {
    if (geoJsonStr.isEmpty) return const [];
    try {
      if (geoJsonStr != _lastDecodedGeoJson) {
        final data = jsonDecode(geoJsonStr) as Map<String, dynamic>;
        _cachedFeatures = data['features'] as List<dynamic>? ?? const [];
        _lastDecodedGeoJson = geoJsonStr;
      }

      final markers = <Marker>[];

      for (final f in _cachedFeatures) {
        final feat = f as Map<String, dynamic>;
        final geom = feat['geometry'] as Map<String, dynamic>?;
        final props = feat['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;

        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.length < 2) continue;

        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        props['lat'] = lat;
        props['lon'] = lon;
        final lineName = props['line_name'] as String? ?? '';
        final delayBucket = props['delay_bucket'] as String? ?? 'on_time';
        final vType = props['vehicle_type'] as String? ?? 'bus';

        if (!enabledModes.contains(vType)) {
          continue;
        }

        final Color dotColor = switch (delayBucket) {
          'minor_delay' => const Color(0xFFEAB308),
          'major_delay' => const Color(0xFFEF4444),
          _ => const Color(0xFF22C55E),
        };

        final Color pillBgColor = getModeBadgeColor(vType);
        final typeIcon = getModeIconData(vType);

        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 72,
            height: 42,
            child: GestureDetector(
              onTap: () => _onVehicleTapped(props),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: pillBgColor,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.white70, width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.65),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(typeIcon, size: 11, color: Colors.white),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 44),
                              child: Text(
                                lineName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black87, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.9),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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

  List<Marker> _buildStopGroupLabelMarkers(
    List<StopNode> stopGroups,
    List<StopNode> platforms,
    bool isDarkMode,
  ) {
    final markers = <Marker>[];

    // Group platforms by hubId or name to find multi-platform clusters
    final Map<String, List<StopNode>> hubPlatforms = {};
    for (final p in platforms) {
      final key = (p.hubId != null && p.hubId!.isNotEmpty) ? p.hubId! : p.name;
      hubPlatforms.putIfAbsent(key, () => []).add(p);
    }

    final processedHubKeys = <String>{};

    for (final entry in hubPlatforms.entries) {
      final stops = entry.value;
      if (stops.length < 2) continue; // Multi-platform cluster gets a station name banner
      processedHubKeys.add(entry.key);

      double sumLat = 0;
      double sumLon = 0;
      bool isMm = false;

      for (final s in stops) {
        sumLat += s.lat;
        sumLon += s.lon;
        if (s.isMultimodalHub) {
          isMm = true;
        }
      }
      final centroidLat = sumLat / stops.length;
      final centroidLon = sumLon / stops.length;

      final firstStop = stops.first;
      final cleanName = firstStop.name;

      markers.add(
        Marker(
          point: LatLng(centroidLat, centroidLon),
          width: 170,
          height: 32,
          alignment: Alignment.center,
          child: Tooltip(
            message: '$cleanName\n${isMm ? "Multimodális átszállási csomópont (OSM)" : "Megállócsoport (OSM)"}',
            child: GestureDetector(
              onTap: () => _onStationTapped(firstStop),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xE00F172A)
                        : const Color(0xD9FFFFFF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDarkMode ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.12),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    cleanName,
                    style: TextStyle(
                      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Also include single stop groups from stopGroupsList if not already part of a multi-platform cluster
    for (final s in stopGroups) {
      final key = (s.hubId != null && s.hubId!.isNotEmpty) ? s.hubId! : s.name;
      if (processedHubKeys.contains(key)) continue;

      final isHub = s.isMultimodalHub;
      final Color markerColor = isHub
          ? const Color(0xFF818CF8) // Indigo for Multimodal Hub
          : (s.operator == Operator.mav
              ? const Color(0xFF0057B8) // MÁV royal blue
              : const Color(0xFF009EE3)); // BKK cyan/blue

      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: 22,
          height: 22,
          child: Tooltip(
            message: '${s.name}\n${isHub ? "Multimodális átszállási csomópont (OSM)" : "Megállócsoport (OSM)"}',
            child: GestureDetector(
              onTap: () => _onStationTapped(s),
              child: Container(
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xF20F172A) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: markerColor, width: isHub ? 2.2 : 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 3.5,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    isHub ? Icons.hub : (s.operator == Operator.mav ? Icons.train : Icons.location_on),
                    size: isHub ? 13 : 11,
                    color: markerColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Marker> _buildPlatformMarkers(List<StopNode> platforms, Set<String> enabledModes) {
    final markers = <Marker>[];
    for (final s in platforms) {
      final mode = s.vehicleType ?? 'bus';
      if (s.vehicleType != null && !enabledModes.contains(mode)) {
        continue;
      }

      final Color badgeColor = getModeBadgeColor(mode);
      final hasPlatform = s.platformCode != null && s.platformCode!.trim().isNotEmpty;
      final platformText = hasPlatform ? s.platformCode!.trim() : '';

      final tooltipMsg = StringBuffer(s.name);
      if (hasPlatform) {
        tooltipMsg.write('\nPeron / Vágány: $platformText');
      }
      if (s.servedRoutes != null && s.servedRoutes!.isNotEmpty) {
        tooltipMsg.write('\nJáratok: ${s.servedRoutes}');
      }
      if (s.direction != null && s.direction!.isNotEmpty) {
        tooltipMsg.write('\nIrány: ${s.direction}');
      }

      // Compute natural angle for directional pointer (Image 2 OSM ÖPNV style)
      final double angle = ((s.direction ?? s.id).hashCode % 360) * 3.141592653589793 / 180.0;

      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          child: Tooltip(
            message: tooltipMsg.toString(),
            child: GestureDetector(
              onTap: () => _onStationTapped(s),
              child: OsmPlatformPin(
                color: badgeColor,
                angle: angle,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final liveVehiclesAsync = ref.watch(liveVehiclesGeoJsonProvider);
    final stopGroupsAsync = ref.watch(viewportStopGroupsProvider);
    final platformsAsync = ref.watch(viewportPlatformsProvider);
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final isDarkMode = ref.watch(mapDarkModeProvider);
    final showStopGroups = ref.watch(showStopGroupsProvider);
    final showPlatforms = ref.watch(showPlatformsProvider);

    final geojson = liveVehiclesAsync.valueOrNull ?? '';
    final vehicleMarkers = _buildVehicleMarkers(geojson, enabledModes);

    final stopGroupsList = stopGroupsAsync.valueOrNull ?? const <StopNode>[];
    final platformsList = platformsAsync.valueOrNull ?? const <StopNode>[];

    final stopGroupPolygons = showStopGroups
        ? StopGroupGeometry.buildHubPolygons(platformsList, isDarkMode: isDarkMode)
        : const <Polygon>[];
    final stopGroupLabelMarkers = showStopGroups
        ? _buildStopGroupLabelMarkers(stopGroupsList, platformsList, isDarkMode)
        : const <Marker>[];
    final platformMarkers = showPlatforms
        ? _buildPlatformMarkers(platformsList, enabledModes)
        : const <Marker>[];

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
            tooltip: 'Állomások és Csomópontok Keresése',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final selected = await showSearch<StopNode?>(
                context: context,
                delegate: LineAndStopSearchDelegate(ref),
              );
              if (selected != null && mounted) {
                _onStationTapped(selected);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Base Interactive Map
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
              // OpenStreetMap tile layer with dark mode matrix filter
              ColorFiltered(
                colorFilter: isDarkMode
                    ? const ColorFilter.matrix(<double>[
                        -0.0974, -0.1457, -0.3575, 0.0, 223.6,
                        -0.5140, 0.5102, -0.6455, 0.0, 233.8,
                        -0.5194, 0.2168, -0.3797, 0.0, 243.0,
                        0.0, 0.0, 0.0, 1.0, 0.0,
                      ])
                    : const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      ),
                child: TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'hungary.public.transport.tracker',
                ),
              ),

              // 1. Shaded Enclosure Boundary Polygons for Stop Groups ("bekerítve", OSM)
              if (showStopGroups && stopGroupPolygons.isNotEmpty)
                PolygonLayer(polygons: stopGroupPolygons),

              // 2. Stop Group Station Name Labels & Hubs (OSM)
              if (showStopGroups && stopGroupLabelMarkers.isNotEmpty)
                MarkerLayer(markers: stopGroupLabelMarkers),

              // 3. Individual Directional Platform Stops ("külön megállók", OSM)
              if (showPlatforms && platformMarkers.isNotEmpty)
                MarkerLayer(markers: platformMarkers),

              // 4. Live Vehicle Positions Layer (Top layer)
              MarkerLayer(markers: vehicleMarkers),
            ],
          ),

          // Bottom-Left Status Pill
          Positioned(
            left: 16,
            bottom: 24,
            child: LiveFeedStatusPill(
              onToggleDirectory: () {
                setState(() => _showDataSourcesModal = !_showDataSourcesModal);
              },
            ),
          ),

          // Bottom-Left Data Sources Directory Card (when expanded)
          if (_showDataSourcesModal)
            Positioned(
              left: 16,
              bottom: 80,
              width: 460,
              height: 520,
              child: DataSourcesDirectoryCard(
                onClose: () => setState(() => _showDataSourcesModal = false),
              ),
            ),

          // Bottom-Right Control Panel
          Positioned(
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StopsLayerToggleButton(onToggle: _updateViewportNow),
                const SizedBox(height: 10),
                const DarkModeToggleButton(),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'modes_filter_fab',
                  tooltip: 'Térképrétegek és szűrők',
                  backgroundColor: _showLayersMenu
                      ? const Color(0xFF009EE3)
                      : const Color(0xE60F172A),
                  foregroundColor: Colors.white,
                  onPressed: () {
                    setState(() => _showLayersMenu = !_showLayersMenu);
                  },
                  child: const Icon(Icons.layers, size: 20),
                ),
              ],
            ),
          ),

          // Bottom-Right Map Layers & Transit Modes Floating Menu
          if (_showLayersMenu)
            Positioned(
              right: 16,
              bottom: 92,
              width: 270,
              child: MapLayersFloatingMenu(
                onClose: () => setState(() => _showLayersMenu = false),
                onStopsEnabled: _updateViewportNow,
              ),
            ),

          // Top-Right Vehicle Info Card
          if (_selectedVehicle != null)
            Positioned(
              top: 16,
              right: 16,
              width: 440,
              child: VehicleDetailCard(
                props: _selectedVehicle!,
                onClose: () => setState(() => _selectedVehicle = null),
              ),
            ),

          // Top-Right Station Info Card (Images 3 & 4 style)
          if (_selectedStation != null)
            Positioned(
              top: 16,
              right: 16,
              width: 350,
              child: StationDetailCard(
                station: _selectedStation!,
                onClose: () => setState(() => _selectedStation = null),
              ),
            ),
        ],
      ),
    );
  }
}

/// Circular platform stop marker with directional pointer notch (Image 2: OSM Public Transport style).
class OsmPlatformPin extends StatelessWidget {
  final Color color;
  final double angle;

  const OsmPlatformPin({
    super.key,
    required this.color,
    this.angle = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(
        size: const Size(22, 22),
        painter: _OsmPlatformPainter(color: color),
      ),
    );
  }
}

class _OsmPlatformPainter extends CustomPainter {
  final Color color;

  _OsmPlatformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 6.5;

    // Subtle drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(center.translate(0, 1), radius, shadowPaint);

    // Directional Pointer Triangle (Image 2 style)
    final path = ui.Path();
    path.moveTo(center.dx + radius - 1, center.dy - 3.5);
    path.lineTo(center.dx + radius + 4.5, center.dy);
    path.lineTo(center.dx + radius - 1, center.dy + 3.5);
    path.close();

    final pointerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, pointerPaint);

    final pointerBorder = Paint()
      ..color = Colors.black38
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawPath(path, pointerBorder);

    // Inner White Circle Fill
    final fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, fillPaint);

    // Mode-colored Thick Ring Border
    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8;
    canvas.drawCircle(center, radius, ringPaint);

    // Small Center Core Dot
    final corePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 1.8, corePaint);
  }

  @override
  bool shouldRepaint(covariant _OsmPlatformPainter oldDelegate) => oldDelegate.color != color;
}
