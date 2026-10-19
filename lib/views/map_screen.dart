import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';
import '../providers/live_vehicles_provider.dart';
import '../providers/timetable_provider.dart';
import 'line_search_delegate.dart';
import 'vehicle_technical_tab_view.dart';

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
  void dispose() {
    _cameraDebounce?.cancel();
    super.dispose();
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    // Only update viewport bbox if either stop groups or platforms layer is visible, and debounce by 350ms
    // so dragging the map never triggers lag or reloads during a gesture.
    if (!ref.read(showStopGroupsProvider) && !ref.read(showPlatformsProvider) && !ref.read(showStopsProvider)) return;
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

        final Color pillBgColor = _getModeBadgeColor(vType);
        final typeIcon = _getModeIconData(vType);

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

  List<Marker> _buildStopGroupMarkers(List<StopNode> stopGroups) {
    final markers = <Marker>[];
    for (final s in stopGroups) {
      final isHub = s.isMultimodalHub;
      final Color markerColor = isHub
          ? const Color(0xFF818CF8) // Indigo for Multimodal Hub
          : (s.operator == Operator.mav
              ? const Color(0xFF38BDF8) // Sky blue for MÁV
              : const Color(0xFF22D3EE)); // Cyan for BKK

      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: isHub ? 26 : 22,
          height: isHub ? 26 : 22,
          child: Tooltip(
            message: '${s.name}\n${isHub ? "Multimodális átszállási csomópont (OSM)" : "Megállócsoport (OSM)"}',
            child: GestureDetector(
              onTap: () => _onStationTapped(s),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xF20F172A),
                  shape: BoxShape.circle,
                  border: Border.all(color: markerColor, width: isHub ? 2.2 : 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Icon(
                  isHub ? Icons.hub : Icons.location_city,
                  size: isHub ? 14 : 12,
                  color: markerColor,
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
      // Filter out platforms whose transport mode is disabled
      if (s.vehicleType != null && !enabledModes.contains(mode)) {
        continue;
      }

      final Color badgeColor = _getModeBadgeColor(mode);
      final IconData modeIcon = _getModeIconData(mode);

      final tooltipMsg = StringBuffer(s.name);
      if (s.platformCode != null && s.platformCode!.isNotEmpty) {
        tooltipMsg.write('\nPeron / Vágány: ${s.platformCode}');
      }
      if (s.servedRoutes != null && s.servedRoutes!.isNotEmpty) {
        tooltipMsg.write('\nJáratok: ${s.servedRoutes}');
      }
      if (s.direction != null && s.direction!.isNotEmpty) {
        tooltipMsg.write('\nIrány: ${s.direction}');
      }

      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: 22,
          height: 22,
          child: Tooltip(
            message: tooltipMsg.toString(),
            child: GestureDetector(
              onTap: () => _onStationTapped(s),
              child: Container(
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    modeIcon,
                    size: 12,
                    color: Colors.white,
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

  @override
  Widget build(BuildContext context) {
    final liveVehiclesAsync = ref.watch(liveVehiclesGeoJsonProvider);
    final stopGroupsAsync = ref.watch(viewportStopGroupsProvider);
    final platformsAsync = ref.watch(viewportPlatformsProvider);
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final isDarkMode = ref.watch(mapDarkModeProvider);

    final geojson = liveVehiclesAsync.valueOrNull ?? '';
    final vehicleMarkers = _buildVehicleMarkers(geojson, enabledModes);

    final stopGroupsList = stopGroupsAsync.valueOrNull ?? const <StopNode>[];
    final stopGroupMarkers = _buildStopGroupMarkers(stopGroupsList);

    final platformsList = platformsAsync.valueOrNull ?? const <StopNode>[];
    final platformMarkers = _buildPlatformMarkers(platformsList, enabledModes);

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
                        // R' : Táj #5a5858 (90), Víz #616e74 (97), Park #698577 (105), Utak #474747 (71)
                        -0.0974, -0.1457, -0.3575, 0.0, 223.6,
                        // G' : Diszkrét szürkészöld növényzet/parkok (#698577), lila elnyomása
                        -0.5140, 0.5102, -0.6455, 0.0, 233.8,
                        // B' : Kékes-palaszürke vizek (#616e74), világos feliratok (#e0e9f2)
                        -0.5194, 0.2168, -0.3797, 0.0, 243.0,
                        // A' : Alfa változatlan
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

              // Static Stop Groups Layer (Megállócsoportok)
              MarkerLayer(markers: stopGroupMarkers),

              // Static Platforms / Directions Layer (Peronok / Irányok)
              MarkerLayer(markers: platformMarkers),

              // Live Vehicle Positions Layer
              MarkerLayer(markers: vehicleMarkers),
            ],
          ),

          // Bottom-Left Status Pill
          Positioned(
            left: 16,
            bottom: 24,
            child: _LiveFeedStatusPill(
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
              child: _DataSourcesDirectoryCard(
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
                _StopsLayerToggleButton(),
                const SizedBox(height: 10),
                _DarkModeToggleButton(),
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
              child: _MapLayersFloatingMenu(
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
              child: _VehicleDetailCard(
                props: _selectedVehicle!,
                onClose: () => setState(() => _selectedVehicle = null),
              ),
            ),

          // Top-Right Station Info Card
          if (_selectedStation != null)
            Positioned(
              top: 16,
              right: 16,
              width: 400,
              child: _StationDetailCard(
                station: _selectedStation!,
                onClose: () => setState(() => _selectedStation = null),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top-Right Floating Vehicle Detail Card with Schedule / Timetable
// ---------------------------------------------------------------------------
class _VehicleDetailCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> props;
  final VoidCallback onClose;

  const _VehicleDetailCard({
    required this.props,
    required this.onClose,
  });

  @override
  ConsumerState<_VehicleDetailCard> createState() => _VehicleDetailCardState();
}

class _VehicleDetailCardState extends ConsumerState<_VehicleDetailCard> {
  int _activeTab = 0; // 0 = Menetrend, 1 = Műszaki infó / Kocsiösszeállítás

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final lineName = props['line_name'] as String? ?? 'Transit';
    final dest = props['destination'] as String? ?? '';
    final op = props['operator'] as String? ?? 'BKK';
    final vType = props['vehicle_type'] as String? ?? 'bus';
    final delay = (props['delay_seconds'] as num? ?? 0).toInt();
    final delayBucket = props['delay_bucket'] as String? ?? 'on_time';
    final tripId = props['trip_id'] as String? ?? '';
    final vehicleId = props['id'] as String? ?? '';

    final mins = (delay / 60).round();
    final delayLabel = mins <= 0 ? 'Pontos' : '+$mins perc késés';
    final Color delayBadgeColor = switch (delayBucket) {
      'minor_delay' => const Color(0xFFEAB308),
      'major_delay' => const Color(0xFFEF4444),
      _ => const Color(0xFF22C55E),
    };

    final Color badgeBg = _getModeBadgeColor(vType);
    final isMav = op == 'MAV' || vType == 'train';

    final scheduleAsync = tripId.isNotEmpty
        ? ref.watch(tripScheduleProvider(tripId))
        : null;

    return Container(
      constraints: const BoxConstraints(maxHeight: 560),
      decoration: BoxDecoration(
        color: const Color(0xF70F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: badgeBg.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getModeIconData(vType), size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        lineName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: op == 'MAV' ? const Color(0xFF0057B8) : const Color(0xFF009EE3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    op,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: delayBadgeColor.withValues(alpha: 0.2),
                    border: Border.all(color: delayBadgeColor, width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    delayLabel,
                    style: TextStyle(
                      color: delayBadgeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Destination & IDs
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dest.isNotEmpty ? dest : 'Menetrend szerinti útvonal',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  'Jármű ID: $vehicleId ${tripId.isNotEmpty ? "• Menet ID: $tripId" : ""}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Navigation Segmented Switcher (Menetrend vs Műszaki infó)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeTab == 0
                              ? Colors.white.withValues(alpha: 0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: _activeTab == 0 ? Colors.cyanAccent : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Menetrend',
                              style: TextStyle(
                                color: _activeTab == 0 ? Colors.white : Colors.white60,
                                fontWeight: _activeTab == 0 ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _activeTab = 1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _activeTab == 1
                              ? (isMav ? const Color(0xFF0057B8) : const Color(0xFF009EE3)).withValues(alpha: 0.35)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: _activeTab == 1
                              ? Border.all(
                                  color: isMav ? const Color(0xFF38BDF8) : const Color(0xFF009EE3),
                                  width: 1,
                                )
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isMav ? Icons.train : Icons.build_circle_outlined,
                              size: 14,
                              color: _activeTab == 1
                                  ? (isMav ? Colors.cyanAccent : Colors.lightBlueAccent)
                                  : Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isMav ? 'vagonWEB szerelvény' : 'HBweb műszaki adatok',
                              style: TextStyle(
                                color: _activeTab == 1 ? Colors.white : Colors.white60,
                                fontWeight: _activeTab == 1 ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
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

          const Divider(height: 1, color: Colors.white12),

          // Content Area: Either Schedule Stops or Technical Sheet / Composition
          Expanded(
            child: _activeTab == 1
                ? VehicleTechnicalTabView(props: widget.props)
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule, size: 14, color: Colors.white70),
                            const SizedBox(width: 6),
                            const Text(
                              'MENETREND ÉS MEGÁLLÓK',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            if (tripId.isNotEmpty)
                              Text(
                                'GTFS-RT',
                                style: TextStyle(
                                  color: Colors.cyan.shade300,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: scheduleAsync == null
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text(
                                    'Valós idejű GPS adatfolyam (statikus menetrendi adat nélkül)',
                                    style: TextStyle(color: Colors.white54, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : scheduleAsync.when(
                                data: (stops) {
                                  if (stops.isEmpty) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'A menetrendi megállók nem találhatók a helyi adatbázisban.',
                                          style: TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                      ),
                                    );
                                  }
                                  return ListView.builder(
                                    itemCount: stops.length,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 6),
                                    itemBuilder: (context, idx) {
                                      final stop = stops[idx];
                                      final isLast = idx == stops.length - 1;

                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Column(
                                            children: [
                                              Container(
                                                width: 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                  color: idx == 0
                                                      ? const Color(0xFF22C55E)
                                                      : (isLast
                                                          ? const Color(0xFFEF4444)
                                                          : badgeBg),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              if (!isLast)
                                                Container(
                                                  width: 2,
                                                  height: 24,
                                                  color: Colors.white24,
                                                ),
                                            ],
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      stop.stopName,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    stop.departureTime,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                                loading: () => const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                error: (_, __) => const Center(
                                  child: Text(
                                    'Menetrend betöltése sikertelen',
                                    style: TextStyle(color: Colors.amber, fontSize: 12),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Top-Right Floating Station Detail Card (Zero Darkening, Zero Freezing)
// ---------------------------------------------------------------------------
class _StationDetailCard extends ConsumerWidget {
  final StopNode station;
  final VoidCallback onClose;

  const _StationDetailCard({
    required this.station,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookupKey = station.hubId ?? station.id;
    final departuresAsync = ref.watch(stationDepartureBoardProvider(lookupKey));

    final isHub = station.isMultimodalHub;

    return Container(
      constraints: const BoxConstraints(maxHeight: 520),
      decoration: BoxDecoration(
        color: const Color(0xF70F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHub ? const Color(0xFF818CF8) : Colors.white24,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHub
                        ? const Color(0xFF6366F1)
                        : (station.operator == Operator.mav
                            ? const Color(0xFF0057B8)
                            : const Color(0xFF009EE3)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isHub
                        ? 'BKK+MÁV HUB'
                        : (station.vehicleType != null && station.vehicleType != 'hub'
                            ? '${station.operator == Operator.mav ? "MÁV" : "BKK"} • ${station.vehicleType!.toUpperCase()}'
                            : (station.operator == Operator.mav ? 'MÁV' : 'BKK')),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        isHub
                            ? 'Multimodális átszállási csomópont (150m klaszter)'
                            : (station.direction != null && station.direction!.isNotEmpty
                                ? 'Irány: ${station.direction}'
                                : (station.servedRoutes != null && station.servedRoutes!.isNotEmpty
                                    ? 'Járatok: ${station.servedRoutes}'
                                    : 'Azonosító: ${station.id}')),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isHub && station.servedRoutes != null && station.servedRoutes!.isNotEmpty && station.direction != null && station.direction!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Járatok: ${station.servedRoutes}',
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Frissítés',
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                  onPressed: () => ref.invalidate(stationDepartureBoardProvider(lookupKey)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Departures list
          Expanded(
            child: departuresAsync.when(
              data: (departures) {
                if (departures.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nincs menetrend szerinti indulás a következő 90 percben.',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: departures.length,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (context, idx) {
                    final dep = departures[idx];
                    final delaySec = dep.delaySeconds;
                    final Color delayColor = delaySec <= 60
                        ? const Color(0xFF22C55E)
                        : (delaySec <= 300 ? const Color(0xFFEAB308) : const Color(0xFFEF4444));
                    final delayText = delaySec <= 60 ? 'Pontos' : '+${(delaySec / 60).round()}p';

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: dep.operator == Operator.mav
                              ? const Color(0xFF0057B8)
                              : const Color(0xFF009EE3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          dep.lineName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      title: Text(
                        dep.headsign,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${dep.operator == Operator.mav ? "MÁV Vasút" : "BKK Járat"}${dep.platformCode != null ? " • ${dep.platformCode}. vágány" : ""}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            dep.estimatedTimeFormatted,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            delayText,
                            style: TextStyle(
                              color: delayColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Nem sikerült betölteni az indulásokat: $err',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom-Right Map Layers & Transit Modes Floating Menu
// ---------------------------------------------------------------------------
class _MapLayersFloatingMenu extends ConsumerWidget {
  final VoidCallback onClose;
  final VoidCallback? onStopsEnabled;

  const _MapLayersFloatingMenu({
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

// ---------------------------------------------------------------------------
// Bottom-Left Status Pill
// ---------------------------------------------------------------------------
class _LiveFeedStatusPill extends ConsumerWidget {
  final VoidCallback onToggleDirectory;

  const _LiveFeedStatusPill({required this.onToggleDirectory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              final op = p['operator'] as String? ?? 'BKK';
              final vType = p['vehicle_type'] as String? ?? 'bus';
              if (op == 'MAV' || vType == 'train') {
                mavCount++;
              } else {
                bkkCount++;
              }
            }
          } catch (_) {}
          final total = bkkCount + mavCount;

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggleDirectory,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 10, color: Color(0xFF22C55E)),
                  const SizedBox(width: 8),
                  Text(
                    '$total aktív jármű (BKK: $bkkCount | MÁV: $mavCount)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Adatforrások',
                          style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.open_in_new, size: 10, color: Colors.white70),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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

// ---------------------------------------------------------------------------
// Comprehensive Hungary Transit Data Directory Card (based on architecture .md)
// ---------------------------------------------------------------------------
class _DataSourcesDirectoryCard extends StatelessWidget {
  final VoidCallback onClose;

  const _DataSourcesDirectoryCard({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF70F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.alt_route, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Magyarországi Közlekedési Adatforrások',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Content body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Országos Főszolgáltatók
                _buildSectionHeader('1. ORSZÁGOS ÉS REGIONÁLIS FŐSZOLGÁLTATÓK'),
                const SizedBox(height: 8),
                _buildProviderTile(
                  name: 'BKK (Budapest)',
                  coverage: 'Metró, villamos, troli, helyi busz, HÉV, hajó',
                  staticSource: 'BKK OpenData (budapest_gtfs.zip)',
                  realtimeSource: 'BKK FUTÁR GTFS-RT (VehiclePositions, TripUpdates)',
                  statusLabel: 'Aktív Élő Stream',
                  statusColor: const Color(0xFF22C55E),
                  badgeColor: const Color(0xFF009EE3),
                ),
                const SizedBox(height: 8),
                _buildProviderTile(
                  name: 'MÁV-START & GYSEV',
                  coverage: 'Országos vasúthálózat, nemzetközi vonatok',
                  staticSource: 'MÁV GTFS csomag',
                  realtimeSource: 'GTFS-RT NAP portál / EMMA OTP2 / utas.hu',
                  statusLabel: 'Csatlakoztatva',
                  statusColor: const Color(0xFF0284C7),
                  badgeColor: const Color(0xFF0057B8),
                ),
                const SizedBox(height: 8),
                _buildProviderTile(
                  name: 'Volánbusz',
                  coverage: 'Országos távolsági és regionális helyközi buszok',
                  staticSource: 'MÁV-Volán integrált GTFS csomag',
                  realtimeSource: 'EMMA GraphQL / utas.hu API / menetrendek.hu',
                  statusLabel: 'Integrált csomag',
                  statusColor: const Color(0xFFEAB308),
                  badgeColor: const Color(0xFFD97706),
                ),
                const SizedBox(height: 8),
                _buildProviderTile(
                  name: 'Nemzeti Adathozzáférési Pont (NAP)',
                  coverage: 'Országos ITS metaadat-katalógus',
                  staticSource: 'napportal.kozut.hu',
                  realtimeSource: 'Központi GTFS-RT feedek',
                  statusLabel: 'Katalógus aktív',
                  statusColor: const Color(0xFF10B981),
                  badgeColor: const Color(0xFF059669),
                ),

                const SizedBox(height: 18),
                // 2. Önálló Városi Hálózatok
                _buildSectionHeader('2. ÖNÁLLÓ VÁROSI KÖZLEKEDÉSI VÁLLALATOK'),
                const SizedBox(height: 8),
                _buildCityGrid([
                  'Debrecen (DKV Zrt.)',
                  'Szeged (SzKT / Volán)',
                  'Miskolc (MVK Zrt.)',
                  'Pécs (Tüke Busz / Biokom)',
                  'Kecskemét (KeKo)',
                  'Veszprém (V-Busz)',
                  'Tatabánya (T-Busz)',
                  'Kaposvár (KK Zrt.)',
                ]),

                const SizedBox(height: 18),
                // 3. Volánbusz Megyeszékhelyek
                _buildSectionHeader('3. VOLÁNBUSZ ÁLTAL ÜZEMELTETETT MEGYESZÉKHELYEK'),
                const SizedBox(height: 6),
                const Text(
                  'Győr, Székesfehérvár, Szombathely, Szolnok, Zalaegerszeg, Nyíregyháza, Békéscsaba, Eger, Salgótarján, Szekszárd (országos MÁV-Volán GTFS és EMMA integráció).',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),

                const SizedBox(height: 18),
                // 4. Deduplikáció
                _buildSectionHeader('4. DEDUPLIKÁCIÓ ÉS ADATINTEGRITÁS'),
                const SizedBox(height: 6),
                _buildFeatureBullet('HÉV szűrés: BKK FUTÁR az elsődleges GPS forrás (MÁV párhuzamok kizárva).'),
                _buildFeatureBullet('Fizikai csomópontok: 150m térbeli klaszterezés (2,900+ csomópont egyesítve).'),
                _buildFeatureBullet('Névtér-kezelés: bkk:, mav:, volan:, dkv:, szkt: ID ütközésvédelem.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF38BDF8),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildProviderTile({
    required String name,
    required String coverage,
    required String staticSource,
    required String realtimeSource,
    required String statusLabel,
    required Color statusColor,
    required Color badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  border: Border.all(color: statusColor, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Lefedettség: $coverage', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          Text('Statikus: $staticSource', style: const TextStyle(color: Colors.white54, fontSize: 10)),
          Text('Élő: $realtimeSource', style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildCityGrid(List<String> cities) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: cities.map((c) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            c,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFeatureBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stops Layer Toggle Button
// ---------------------------------------------------------------------------
class _StopsLayerToggleButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showGroups = ref.watch(showStopGroupsProvider);
    final showPlatforms = ref.watch(showPlatformsProvider);
    final anyActive = showGroups || showPlatforms;

    return FloatingActionButton.small(
      heroTag: 'stops_layer_toggle',
      tooltip: anyActive ? 'Megállók és peronok elrejtése' : 'Megállók gyors megjelenítése',
      backgroundColor: const Color(0xE60F172A),
      foregroundColor: anyActive ? const Color(0xFF38BDF8) : Colors.white54,
      onPressed: () {
        if (anyActive) {
          ref.read(showStopGroupsProvider.notifier).state = false;
          ref.read(showPlatformsProvider.notifier).state = false;
        } else {
          ref.read(showStopGroupsProvider.notifier).state = true;
          ref.read(showPlatformsProvider.notifier).state = true;
        }
      },
      child: const Icon(Icons.place, size: 20),
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

IconData _getModeIconData(String mode) {
  return switch (mode) {
    'tram' => Icons.tram,
    'metro' => Icons.subway,
    'trolley' => Icons.electric_bolt,
    'train' => Icons.train,
    'suburban_rail' => Icons.directions_railway,
    'boat' => Icons.directions_boat,
    _ => Icons.directions_bus,
  };
}

Color _getModeBadgeColor(String mode) {
  return switch (mode) {
    'tram' => const Color(0xFFD97706), // BKK Tram amber/yellow
    'metro' => const Color(0xFF2563EB), // Metro deep blue
    'trolley' => const Color(0xFFDC2626), // BKK Trolley red
    'train' => const Color(0xFF0057B8), // MÁV Train royal blue
    'suburban_rail' => const Color(0xFF16A34A), // HÉV green
    'boat' => const Color(0xFF7C3AED), // Boat purple
    _ => const Color(0xFF0284C7), // BKK Bus sky blue
  };
}

