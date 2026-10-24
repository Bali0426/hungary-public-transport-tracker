import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../bridge/bridge_generated.dart';
import '../providers/live_vehicles_provider.dart';
import '../providers/timetable_provider.dart';
import '../providers/transit_lines_provider.dart';
import '../utils/stop_group_geometry.dart';
import '../utils/transit_display_utils.dart';
import 'widgets/data_sources_card.dart';
import 'widgets/live_feed_status_pill.dart';
import 'widgets/map_control_buttons.dart';
import 'widgets/map_layers_menu.dart';
import 'widgets/map_legend_dialog.dart';
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

  double _currentZoom = 12.5;
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

  int _getLodTier(double zoom) {
    if (zoom >= 16.8) return 3;
    if (zoom >= 14.5) return 2;
    if (zoom >= 11.0) return 1;
    return 0;
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    final newZoom = camera.zoom;
    if ((newZoom - _currentZoom).abs() >= 0.15 || _getLodTier(newZoom) != _getLodTier(_currentZoom)) {
      setState(() {
        _currentZoom = newZoom;
      });
      ref.read(mapZoomProvider.notifier).state = newZoom;
    }

    if (!hasGesture) return;
    if (_currentZoom < 14.5) return;
    if (!ref.read(showStopGroupsProvider) && !ref.read(showPlatformsProvider)) return;

    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 300), () {
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
    if (!mounted) return;
    try {
      final bounds = _mapController.camera.visibleBounds;
      ref.read(viewportBboxProvider.notifier).state = ViewportBbox(
        minLat: bounds.south,
        minLon: bounds.west,
        maxLat: bounds.north,
        maxLon: bounds.east,
      );
    } catch (_) {
      ref.read(viewportBboxProvider.notifier).state = const ViewportBbox(
        minLat: 47.45,
        minLon: 18.98,
        maxLat: 47.55,
        maxLon: 19.12,
      );
    }
  }

  void _moveCamera(LatLng center, double zoom) {
    _mapController.move(center, zoom);
    setState(() {
      _currentZoom = zoom;
    });
    ref.read(mapZoomProvider.notifier).state = zoom;
  }

  void _onMapTapped(double tapLat, double tapLon) {
    // 1. Check live vehicles near tap (within ~0.0025 degrees / ~180 meters)
    if (ref.read(showLiveVehiclesProvider)) {
      Map<String, dynamic>? closestVehicle;
      double minVehicleDist = 0.0025;

      for (final f in _cachedFeatures) {
        final feat = f as Map<String, dynamic>;
        final geom = feat['geometry'] as Map<String, dynamic>?;
        final props = feat['properties'] as Map<String, dynamic>?;
        if (geom == null || props == null) continue;
        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.length < 2) continue;

        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        final dist = (lat - tapLat).abs() + (lon - tapLon).abs();
        if (dist <= minVehicleDist) {
          minVehicleDist = dist;
          props['lat'] = lat;
          props['lon'] = lon;
          closestVehicle = props;
        }
      }

      if (closestVehicle != null) {
        _onVehicleTapped(closestVehicle);
        return;
      }
    }

    // 2. Check platforms near tap (within ~0.0018 degrees)
    if (ref.read(showPlatformsProvider) && _currentZoom >= 16.5) {
      final platforms = ref.read(viewportPlatformsProvider).valueOrNull ?? const <StopNode>[];
      StopNode? closestPlatform;
      double minPlatformDist = 0.0018;

      for (final s in platforms) {
        final dist = (s.lat - tapLat).abs() + (s.lon - tapLon).abs();
        if (dist <= minPlatformDist) {
          minPlatformDist = dist;
          closestPlatform = s;
        }
      }

      if (closestPlatform != null) {
        final platformNode = closestPlatform.isMultimodalHub
            ? StopNode(
                id: closestPlatform.id,
                hubId: closestPlatform.hubId,
                name: closestPlatform.name,
                lat: closestPlatform.lat,
                lon: closestPlatform.lon,
                operator: closestPlatform.operator,
                platformCode: closestPlatform.platformCode,
                isMultimodalHub: false,
                vehicleType: closestPlatform.vehicleType,
                servedRoutes: closestPlatform.servedRoutes,
                direction: closestPlatform.direction,
              )
            : closestPlatform;
        _onStationTapped(platformNode);
        return;
      }
    }

    // 3. Check stop groups near tap (within ~0.0028 degrees)
    if (ref.read(showStopGroupsProvider) && _currentZoom >= 14.5) {
      final stopGroups = ref.read(viewportStopGroupsProvider).valueOrNull ?? const <PrebakedStopGroup>[];
      PrebakedStopGroup? closestGroup;
      double minGroupDist = 0.0028;

      for (final g in stopGroups) {
        final dist = (g.centroid.latitude - tapLat).abs() + (g.centroid.longitude - tapLon).abs();
        if (dist <= minGroupDist) {
          minGroupDist = dist;
          closestGroup = g;
        }
      }

      if (closestGroup != null) {
        _onStationTapped(closestGroup.groupNode);
        return;
      }
    }

    // Deselect if tapped empty space
    if (_selectedVehicle != null || _selectedStation != null) {
      setState(() {
        _selectedVehicle = null;
        _selectedStation = null;
      });
    }
  }

  void _onStationTapped(StopNode station) {
    final targetZoom = _currentZoom.clamp(14.0, 18.0);
    setState(() {
      _selectedStation = station;
      _selectedVehicle = null;
      _currentZoom = targetZoom;
    });
    ref.read(mapZoomProvider.notifier).state = targetZoom;
    _moveCamera(LatLng(station.lat, station.lon), targetZoom);
  }

  void _onVehicleTapped(Map<String, dynamic> props) {
    setState(() {
      _selectedVehicle = props;
      _selectedStation = null;
    });
  }

  Map<String, dynamic> _departureToProps(UnifiedDeparture dep) {
    for (final feat in _cachedFeatures) {
      final p = feat['properties'] as Map<String, dynamic>?;
      if (p != null) {
        final tId = p['trip_id']?.toString();
        if (tId != null && tId.isNotEmpty && tId == dep.tripId) {
          return Map<String, dynamic>.from(p);
        }
      }
    }

    final isTrain = dep.operator == Operator.mav;
    final mins = (dep.delaySeconds / 60).round();
    final delayBucket = mins > 5
        ? 'major_delay'
        : (mins > 2 ? 'minor_delay' : 'on_time');

    final modeStyle = resolveRouteBadgeStyle(line: dep.lineName);

    return {
      'id': dep.tripId,
      'trip_id': dep.tripId,
      'line_name': dep.lineName,
      'trip_short_name': dep.lineName,
      'destination': dep.headsign,
      'operator': isTrain ? 'MAV' : 'BKK',
      'vehicle_type': isTrain ? 'train' : modeStyle.mode,
      'delay_seconds': dep.delaySeconds,
      'delay_bucket': delayBucket,
      'delay_cause': dep.delaySeconds > 120 ? 'Menetrendi eltérés / Forgalmi ok' : '',
      'is_realtime': dep.isRealtime,
      'platform': dep.platformCode,
      'speed_kmh': 0,
    };
  }

  void _onDepartureTapped(UnifiedDeparture dep) {
    final props = _departureToProps(dep);
    setState(() {
      _selectedVehicle = props;
    });
  }

  void _onSearchVehicleSelected(Map<String, dynamic> props) {
    final lat = (props['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (props['lon'] as num?)?.toDouble() ?? 0.0;
    if (lat != 0.0 && lon != 0.0) {
      _moveCamera(LatLng(lat, lon), 15.0);
    }
    _onVehicleTapped(props);
  }

  List<Marker> _buildVehicleMarkers(
    String geoJsonStr,
    Set<String> enabledModes,
    double zoom,
    bool isDarkMode,
    LatLngBounds? visibleBounds,
  ) {
    if (geoJsonStr.isEmpty) return const [];
    try {
      if (geoJsonStr != _lastDecodedGeoJson) {
        final data = jsonDecode(geoJsonStr) as Map<String, dynamic>;
        _cachedFeatures = data['features'] as List<dynamic>? ?? const [];
        _lastDecodedGeoJson = geoJsonStr;
      }

      final isDetailed = zoom >= 15.0;
      final markers = <Marker>[];
      final seenHevKeys = <String>{};

      // Viewport culling bounding box (+15% margin around camera view)
      double minLat = -90.0, maxLat = 90.0, minLon = -180.0, maxLon = 180.0;
      if (visibleBounds != null) {
        final latMargin = (visibleBounds.north - visibleBounds.south).abs() * 0.15;
        final lonMargin = (visibleBounds.east - visibleBounds.west).abs() * 0.15;
        minLat = visibleBounds.south - latMargin;
        maxLat = visibleBounds.north + latMargin;
        minLon = visibleBounds.west - lonMargin;
        maxLon = visibleBounds.east + lonMargin;
      }

      for (final f in _cachedFeatures) {
        final feat = f as Map<String, dynamic>;
        final geom = feat['geometry'] as Map<String, dynamic>?;
        final props = feat['properties'] as Map<String, dynamic>? ?? {};
        if (geom == null) continue;

        final coords = geom['coordinates'] as List<dynamic>?;
        if (coords == null || coords.length < 2) continue;

        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();

        // 1. Viewport Culling: discard items outside camera bounds immediately
        if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
          continue;
        }

        props['lat'] = lat;
        props['lon'] = lon;
        final rawLineName = props['line_name'] as String? ?? '';
        final delayBucket = props['delay_bucket'] as String? ?? 'on_time';
        var vType = props['vehicle_type'] as String? ?? 'bus';
        final op = props['operator'] as String? ?? '';
        final tripShort = props['trip_short_name'] as String? ?? '';

        final isHev = vType == 'suburban_rail' ||
            RegExp(r'^H[5-9]\b', caseSensitive: false).hasMatch(rawLineName) ||
            RegExp(r'^H[5-9]\b', caseSensitive: false).hasMatch(tripShort) ||
            rawLineName.toLowerCase().contains('hév') ||
            tripShort.toLowerCase().contains('hév');

        var lineName = rawLineName;
        if (isHev) {
          vType = 'suburban_rail';
          props['vehicle_type'] = 'suburban_rail';
          final hMatch = RegExp(r'\b(H[5-9])\b', caseSensitive: false).firstMatch('$rawLineName $tripShort');
          if (hMatch != null) {
            lineName = hMatch.group(1)!.toUpperCase();
            props['line_name'] = lineName;
          }

          final dupKey = '${lineName.toUpperCase()}_${(lat * 150).round()}_${(lon * 150).round()}';
          if (seenHevKeys.contains(dupKey)) {
            continue;
          }
          seenHevKeys.add(dupKey);
        }

        if (!enabledModes.contains(vType)) {
          continue;
        }

        final isTrain = vType == 'train' || op == 'MAV';
        final isSuburban = vType == 'suburban_rail';
        final isMetro = vType == 'metro';
        final isTramOrBoat = vType == 'tram' || vType == 'boat';
        final isLargeVehicle = isTrain || isSuburban || isMetro;

        if (zoom < 8.0) {
          continue;
        } else if (zoom < 10.0) {
          if (!isTrain) continue;
        } else if (zoom < 12.0) {
          if (!isLargeVehicle) continue;
        } else if (zoom < 13.5) {
          if (!isLargeVehicle && !isTramOrBoat) continue;
        }

        final bool showDelayIndicator = isTrain || isSuburban;

        final Color dotColor = switch (delayBucket) {
          'minor_delay' => const Color(0xFFEAB308),
          'major_delay' => const Color(0xFFEF4444),
          _ => const Color(0xFF22C55E),
        };

        final Color pillBgColor = getModeBadgeColor(vType);
        final Color pillFgColor = getModeForegroundColor(vType);

        if (isDetailed) {
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
                            border: Border.all(
                              color: vType == 'tram' ? const Color(0xFF1E1E1E) : Colors.white70,
                              width: 1.2,
                            ),
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
                              Icon(typeIcon, size: 11, color: pillFgColor),
                              const SizedBox(width: 3),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 44),
                                child: Text(
                                  lineName,
                                  style: TextStyle(
                                    color: pillFgColor,
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
                        if (showDelayIndicator) ...[
                          const SizedBox(height: 2),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black87, width: 1.0),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        } else {
          markers.add(
            Marker(
              point: LatLng(lat, lon),
              width: 12,
              height: 12,
              child: GestureDetector(
                onTap: () => _onVehicleTapped(props),
                child: Container(
                  decoration: BoxDecoration(
                    color: pillBgColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
          );
        }
      }
      return markers;
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveVehiclesAsync = ref.watch(liveVehiclesGeoJsonProvider);
    final isDarkMode = ref.watch(mapDarkModeProvider);
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final showLiveVehicles = ref.watch(showLiveVehiclesProvider);
    final showOpenRailwayMap = ref.watch(showOpenRailwayMapProvider);
    final railwayStyle = ref.watch(openRailwayMapStyleProvider);

    final showMetroLines = ref.watch(showMetroLinesProvider);
    final showHevLines = ref.watch(showHevLinesProvider);
    final showTramLines = ref.watch(showTramLinesProvider);
    final showRailwayLines = ref.watch(showRailwayLinesProvider);

    // Selected vehicle route geometry polyline
    Polyline? selectedVehicleRoutePolyline;
    final selectedTripId = _selectedVehicle?['trip_id']?.toString() ??
        _selectedVehicle?['id']?.toString() ??
        '';
    final selectedRouteCoords = ref.watch(vehicleRoutePolylineProvider(selectedTripId)).valueOrNull ?? const [];
    if (showLiveVehicles && _selectedVehicle != null && selectedRouteCoords.length >= 2) {
      final vType = _selectedVehicle?['vehicle_type']?.toString().toLowerCase() ?? 'bus';
      final modeColor = getModeBadgeColor(vType);
      selectedVehicleRoutePolyline = Polyline(
        points: selectedRouteCoords,
        strokeWidth: 4.0,
        color: modeColor.withValues(alpha: 0.85),
        borderStrokeWidth: 1.5,
        borderColor: isDarkMode ? Colors.black54 : Colors.white70,
      );
    }

    final List<Polyline> networkPolylines = [
      if (showMetroLines) ...ref.watch(metroPolylinesProvider),
      if (showHevLines) ...ref.watch(hevPolylinesProvider),
      if (showTramLines) ...ref.watch(tramPolylinesProvider),
      if (showRailwayLines) ...ref.watch(railwayPolylinesProvider),
    ];

    final geojson = liveVehiclesAsync.valueOrNull ?? '';
    LatLngBounds? visibleBounds;
    try {
      visibleBounds = _mapController.camera.visibleBounds;
    } catch (_) {}

    final vehicleMarkers = (showLiveVehicles && geojson.isNotEmpty)
        ? _buildVehicleMarkers(geojson, enabledModes, _currentZoom, isDarkMode, visibleBounds)
        : const <Marker>[];

    final renderedCount = vehicleMarkers.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final current = ref.read(renderedVehiclesCountProvider);
        if (current != renderedCount) {
          ref.read(renderedVehiclesCountProvider.notifier).state = renderedCount;
        }
      }
    });

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 1. Base Interactive Map (OpenStreetMap with custom dark mode matrix filter)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _budapestCenter,
              initialZoom: 12.5,
              onPositionChanged: _onPositionChanged,
              onTap: (tapPosition, point) => _onMapTapped(point.latitude, point.longitude),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // OpenStreetMap Tile Layer with dark mode matrix filter
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

              // OpenRailwayMap railway infrastructure overlay
              if (showOpenRailwayMap)
                ColorFiltered(
                  colorFilter: isDarkMode
                      ? const ColorFilter.matrix(<double>[
                          -1.0, 0.0, 0.0, 0.0, 255.0,
                          0.0, -1.0, 0.0, 0.0, 255.0,
                          0.0, 0.0, -1.0, 0.0, 255.0,
                          0.0, 0.0, 0.0, 1.0, 0.0,
                        ])
                      : const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        ),
                  child: TileLayer(
                    urlTemplate: railwayStyle.tileUrl,
                    subdomains: const ['a', 'b', 'c'],
                    userAgentPackageName: 'hungary.public.transport.tracker',
                  ),
                ),

              // Infrastructure transit polylines
              if (networkPolylines.isNotEmpty)
                PolylineLayer(polylines: networkPolylines),

              // Selected vehicle route polyline
              if (selectedVehicleRoutePolyline != null)
                PolylineLayer(polylines: [selectedVehicleRoutePolyline]),

              // Pre-baked Stop Groups & Station Labels
              StopGroupsLayer(onStationTapped: _onStationTapped),

              // Directional Platforms Layer (LOD >= 16.8)
              PlatformsMapLayer(onStationTapped: _onStationTapped),

              // Live Vehicle Markers (Viewport Culled)
              if (showLiveVehicles && vehicleMarkers.isNotEmpty)
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

          // Bottom-Left Map Legend FAB (positioned directly above LiveFeedStatusPill)
          Positioned(
            left: 16,
            bottom: 76,
            child: FloatingActionButton.small(
              heroTag: 'map_legend_fab',
              tooltip: 'Jelmagyarázat',
              backgroundColor: isDarkMode ? const Color(0xE80F172A) : const Color(0xF2FFFFFF),
              foregroundColor: isDarkMode ? Colors.white70 : const Color(0xFF334155),
              onPressed: () => MapLegendDialog.show(context),
              child: const Icon(Icons.info_outline, size: 20),
            ),
          ),

          // Bottom-Left Data Sources Directory Card (when expanded)
          if (_showDataSourcesModal)
            Positioned(
              left: 16,
              bottom: 128,
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
                FloatingActionButton.small(
                  heroTag: 'gps_current_location_fab',
                  tooltip: 'Jelenlegi pozíció (GPS)',
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                  onPressed: () {
                    _moveCamera(_budapestCenter, 15.0);
                    _updateViewportNow();
                  },
                  child: const Icon(Icons.my_location, size: 20),
                ),
                const SizedBox(height: 10),
                const DarkModeToggleButton(),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'modes_filter_fab',
                  tooltip: 'Térképrétegek és szűrők',
                  backgroundColor: _showLayersMenu
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHigh,
                  foregroundColor: _showLayersMenu
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  onPressed: () {
                    setState(() => _showLayersMenu = !_showLayersMenu);
                  },
                  child: const Icon(Icons.layers, size: 20),
                ),
              ],
            ),
          ),

          // Bottom-Right Map Layers & Transit Modes Floating Menu (opens left of control buttons)
          if (_showLayersMenu)
            Positioned(
              right: 76,
              bottom: 24,
              width: math.min(520.0, MediaQuery.sizeOf(context).width - 90.0),
              child: MapLayersFloatingMenu(
                onClose: () => setState(() => _showLayersMenu = false),
                onStopsEnabled: _updateViewportNow,
              ),
            ),

          // Top-Left Non-Fullscreen Floating Search Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            left: 16,
            child: _TopLeftFloatingSearchBar(
              isDarkMode: isDarkMode,
              onVehicleSelected: _onSearchVehicleSelected,
              onStopSelected: _onStationTapped,
            ),
          ),

          // Top-Right Selected Detail Cards
          if (_selectedVehicle != null || _selectedStation != null)
            Builder(
              builder: (ctx) {
                final screenWidth = MediaQuery.sizeOf(ctx).width;
                final availableHeight = MediaQuery.sizeOf(ctx).height -
                    (MediaQuery.of(ctx).padding.top + 90);
                final canShowBothSideBySide = _selectedVehicle != null &&
                    _selectedStation != null &&
                    screenWidth >= 880;

                final cardWidth = canShowBothSideBySide
                    ? math.min(430.0, (screenWidth - 48) / 2)
                    : math.min(440.0, screenWidth - 32);

                return Positioned(
                  top: MediaQuery.of(ctx).padding.top + 14,
                  right: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Vehicle Detail Card (positioned to the left of the station card)
                      if (_selectedVehicle != null) ...[
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: cardWidth,
                            maxHeight: availableHeight,
                          ),
                          child: VehicleDetailCard(
                            props: _selectedVehicle!,
                            onClose: () => setState(() => _selectedVehicle = null),
                          ),
                        ),
                        if (canShowBothSideBySide) const SizedBox(width: 14),
                      ],

                      // Station Detail Card
                      if (_selectedStation != null &&
                          (_selectedVehicle == null || canShowBothSideBySide))
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: cardWidth,
                            maxHeight: availableHeight,
                          ),
                          child: StationDetailCard(
                            key: ValueKey(_selectedStation!.id),
                            station: _selectedStation!,
                            onClose: () => setState(() => _selectedStation = null),
                            onDepartureTapped: _onDepartureTapped,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Isolated ConsumerWidget for Stop Group boundary polygons and station name labels.
/// Renders pre-baked convex hull polygons and fixed station centroids without runtime clustering.
typedef StopGroupsMapLayer = StopGroupsLayer;

class StopGroupsLayer extends ConsumerStatefulWidget {
  final ValueChanged<StopNode> onStationTapped;

  const StopGroupsLayer({
    super.key,
    required this.onStationTapped,
  });

  @override
  ConsumerState<StopGroupsLayer> createState() => _StopGroupsLayerState();
}

class _StopGroupsLayerState extends ConsumerState<StopGroupsLayer> {
  List<PrebakedStopGroup>? _lastStopGroups;
  bool? _lastDark;
  List<Polygon> _cachedPolygons = const [];
  List<Marker> _cachedLabelMarkers = const [];

  static const _darkShadows = [
    Shadow(color: Colors.black, blurRadius: 3),
    Shadow(color: Colors.black, blurRadius: 3),
  ];
  static const _lightShadows = [
    Shadow(color: Colors.white, blurRadius: 3),
    Shadow(color: Colors.white, blurRadius: 3),
  ];

  List<Marker> _buildLabelMarkers(List<PrebakedStopGroup> stopGroups, bool isDarkMode) {
    if (stopGroups.isEmpty) return const [];

    final candidates = <_StationLabelCandidate>[];
    final processedNames = <String>{};

    for (final sg in stopGroups) {
      final lower = sg.name.toLowerCase();
      if (processedNames.contains(lower)) continue;
      processedNames.add(lower);
      final score = (sg.isMultimodal ? 100 : 0) +
          (sg.operator == Operator.mav ? 50 : 0) +
          (sg.stopCount * 10);
      candidates.add(_StationLabelCandidate(
        name: sg.name,
        centroid: sg.centroid,
        stop: sg.groupNode,
        score: score,
      ));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    const double minDistanceMeters = 90.0;
    final accepted = <_StationLabelCandidate>[];

    for (final cand in candidates) {
      final collision = accepted.any((acc) =>
          StopGroupGeometry.distanceMeters(
            acc.centroid.latitude,
            acc.centroid.longitude,
            cand.centroid.latitude,
            cand.centroid.longitude,
          ) < minDistanceMeters);
      if (!collision) {
        accepted.add(cand);
      }
    }

    final labelStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
      shadows: isDarkMode ? _darkShadows : _lightShadows,
    );

    final markers = <Marker>[];
    for (final cand in accepted) {
      markers.add(
        Marker(
          point: cand.centroid,
          width: 170,
          height: 32,
          alignment: Alignment.center,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onStationTapped(cand.stop),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                cand.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
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
    final showStopGroups = ref.watch(showStopGroupsProvider);
    final zoomOk = ref.watch(mapZoomProvider.select((z) => z >= 15.0));
    if (!showStopGroups || !zoomOk) return const SizedBox.shrink();

    final isDarkMode = ref.watch(mapDarkModeProvider);
    final stopGroups = ref.watch(viewportStopGroupsProvider).valueOrNull ?? const <PrebakedStopGroup>[];

    if (!identical(stopGroups, _lastStopGroups) || _lastDark != isDarkMode) {
      _cachedPolygons = StopGroupGeometry.buildPrebakedPolygons(
        stopGroups,
        isDarkMode: isDarkMode,
      );
      _cachedLabelMarkers = _buildLabelMarkers(stopGroups, isDarkMode);
      _lastStopGroups = stopGroups;
      _lastDark = isDarkMode;
    }

    if (_cachedPolygons.isEmpty && _cachedLabelMarkers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        if (_cachedPolygons.isNotEmpty) PolygonLayer(polygons: _cachedPolygons),
        if (_cachedLabelMarkers.isNotEmpty) MarkerLayer(markers: _cachedLabelMarkers),
      ],
    );
  }
}

/// Isolated ConsumerWidget for individual directional platform pins.
/// Only loads and renders at high zoom (zoom >= 16.8) and never rebuilds on vehicle stream ticks.
class PlatformsMapLayer extends ConsumerStatefulWidget {
  final ValueChanged<StopNode>? onStationTapped;

  const PlatformsMapLayer({
    super.key,
    this.onStationTapped,
  });

  @override
  ConsumerState<PlatformsMapLayer> createState() => _PlatformsMapLayerState();
}

class _PlatformsMapLayerState extends ConsumerState<PlatformsMapLayer> {
  static final RegExp _routeSplitRegex = RegExp(r'[,;\s/]+');
  static final Map<String, List<Color>> _platformColorsCache = {};

  List<StopNode>? _lastPlatforms;
  Set<String>? _lastEnabledModes;
  bool? _lastIsLod3;
  bool? _lastDark;
  List<Marker> _cachedMarkers = const [];

  static Color _getBudapestGoModeColor(StopNode stop) {
    if (stop.operator == Operator.mav) return const Color(0xFF003B7A);
    return getModeBadgeColor(stop.vehicleType ?? 'bus');
  }

  static List<Color> _getPlatformColors(StopNode stop) {
    if (stop.operator == Operator.mav) {
      return const [Color(0xFF003B7A)];
    }
    final routesStr = stop.servedRoutes;
    final mode = stop.vehicleType ?? 'bus';
    final cacheKey = '$mode|${routesStr ?? ''}';

    return _platformColorsCache.putIfAbsent(cacheKey, () {
      if (routesStr == null || routesStr.trim().isEmpty) {
        return [_getBudapestGoModeColor(stop)];
      }

      final tokens = routesStr
          .split(_routeSplitRegex)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty);

      final colors = <Color>[];
      for (final t in tokens) {
        final c = getLineOrRouteColor(t, mode: stop.vehicleType);
        if (!colors.contains(c)) {
          colors.add(c);
        }
      }

      if (colors.isEmpty) {
        colors.add(_getBudapestGoModeColor(stop));
      }
      return List<Color>.unmodifiable(colors.take(4));
    });
  }

  List<Marker> _buildMarkers(
    List<StopNode> platforms,
    Set<String> enabledModes,
    bool isLod3,
    bool isDarkMode,
  ) {
    if (platforms.isEmpty) return const [];

    final markers = <Marker>[];
    final double diameter = isLod3 ? 15.0 : 13.0;
    final double strokeWidth = isLod3 ? 2.8 : 1.5;
    final double arrowSize = isLod3 ? 5.5 : 4.5;
    final double markerBoxSize = isLod3 ? 34.0 : 28.0;

    for (final s in platforms) {
      final mode = s.vehicleType ?? 'bus';
      if (s.vehicleType != null && !enabledModes.contains(mode)) {
        continue;
      }

      final platformColors = _getPlatformColors(s);
      final double angle;
      final parsedDir = double.tryParse(s.direction ?? '');
      if (parsedDir != null) {
        angle = parsedDir * math.pi / 180.0;
      } else {
        angle = ((s.direction ?? s.id).hashCode % 360) * math.pi / 180.0;
      }

      final platformPin = BudapestGoPlatformPin(
        colors: platformColors,
        angle: angle,
        diameter: diameter,
        strokeWidth: strokeWidth,
        strokeColor: const Color(0xFF212121),
        showArrow: true,
        arrowSize: arrowSize,
        isLod3: isLod3,
        isDarkMode: isDarkMode,
      );

      markers.add(
        Marker(
          point: LatLng(s.lat, s.lon),
          width: markerBoxSize,
          height: markerBoxSize,
          alignment: Alignment.center,
          child: widget.onStationTapped != null
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final platformNode = s.isMultimodalHub
                        ? StopNode(
                            id: s.id,
                            hubId: s.hubId,
                            name: s.name,
                            lat: s.lat,
                            lon: s.lon,
                            operator: s.operator,
                            platformCode: s.platformCode,
                            isMultimodalHub: false,
                            vehicleType: s.vehicleType,
                            servedRoutes: s.servedRoutes,
                            direction: s.direction,
                          )
                        : s;
                    widget.onStationTapped!(platformNode);
                  },
                  child: platformPin,
                )
              : platformPin,
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final showPlatforms = ref.watch(showPlatformsProvider);
    final zoomTier = ref.watch(mapZoomProvider.select((z) => z < 16.8 ? 0 : (z >= 17.5 ? 2 : 1)));
    if (!showPlatforms || zoomTier == 0) return const SizedBox.shrink();

    final isLod3 = zoomTier == 2;
    final isDarkMode = ref.watch(mapDarkModeProvider);
    final enabledModes = ref.watch(enabledTransitModesProvider);
    final platforms = ref.watch(viewportPlatformsProvider).valueOrNull ?? const <StopNode>[];

    if (!identical(platforms, _lastPlatforms) ||
        !identical(enabledModes, _lastEnabledModes) ||
        _lastIsLod3 != isLod3 ||
        _lastDark != isDarkMode) {
      _cachedMarkers = _buildMarkers(platforms, enabledModes, isLod3, isDarkMode);
      _lastPlatforms = platforms;
      _lastEnabledModes = enabledModes;
      _lastIsLod3 = isLod3;
      _lastDark = isDarkMode;
    }

    if (_cachedMarkers.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(markers: _cachedMarkers);
  }
}

class _StationLabelCandidate {
  final String name;
  final LatLng centroid;
  final StopNode stop;
  final int score;

  const _StationLabelCandidate({
    required this.name,
    required this.centroid,
    required this.stop,
    required this.score,
  });
}

/// Circular platform stop marker with theme-dependent inner core, segmented outer ring and black bearing arrow.
class BudapestGoPlatformPin extends StatelessWidget {
  final List<Color> colors;
  final double angle;
  final double diameter;
  final double strokeWidth;
  final Color strokeColor;
  final bool showArrow;
  final double arrowSize;
  final bool isLod3;
  final bool isDarkMode;

  const BudapestGoPlatformPin({
    super.key,
    this.colors = const [Color(0xFF009EE3)],
    this.angle = 0,
    required this.diameter,
    this.strokeWidth = 1.0,
    this.strokeColor = const Color(0xFF212121),
    this.showArrow = false,
    this.arrowSize = 5.0,
    this.isLod3 = false,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final totalSize = diameter + (showArrow ? arrowSize * 2 : 4.0);
    return CustomPaint(
      size: Size(totalSize, totalSize),
      painter: _BudapestGoPlatformPainter(
        colors: colors,
        angle: angle,
        diameter: diameter,
        strokeWidth: strokeWidth,
        strokeColor: strokeColor,
        showArrow: showArrow,
        arrowSize: arrowSize,
        isLod3: isLod3,
        isDarkMode: isDarkMode,
      ),
    );
  }
}

class _BudapestGoPlatformPainter extends CustomPainter {
  final List<Color> colors;
  final double angle;
  final double diameter;
  final double strokeWidth;
  final Color strokeColor;
  final bool showArrow;
  final double arrowSize;
  final bool isLod3;
  final bool isDarkMode;

  _BudapestGoPlatformPainter({
    required this.colors,
    required this.angle,
    required this.diameter,
    required this.strokeWidth,
    required this.strokeColor,
    required this.showArrow,
    required this.arrowSize,
    required this.isLod3,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Platform pin has consistent inner core (White in light mode, #1A1A1A in dark mode)
    // + colored ring (multi-branch segmented if multiple colors)
    // ensuring it never flashes or turns into a solid single-color fill when zooming out.
    final ringStrokeWidth = isLod3 ? 2.8 : (diameter >= 12.0 ? 2.0 : 1.4);
    final coreRadius = math.max(1.0, (diameter / 2.0) - (ringStrokeWidth / 2.0));
    final ringRadius = coreRadius;
    final totalOuterRadius = coreRadius + ringStrokeWidth / 2.0;

    // Subtle drop shadow under pin
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawCircle(center.translate(0, 0.8), totalOuterRadius, shadowPaint);

    // 1. Inner core fill (theme dependent: White in light mode, #1A1A1A in dark mode)
    final coreColor = isDarkMode ? const Color(0xFF1A1A1A) : const Color(0xFFFFFFFF);
    final corePaint = Paint()
      ..color = coreColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, corePaint);

    // 2. Colored ring (equal segments if multi-branch)
    final ringRect = Rect.fromCircle(center: center, radius: ringRadius);
    final nSegments = math.max(1, colors.length);
    final sweepAngle = (2 * math.pi) / nSegments;

    for (int i = 0; i < nSegments; i++) {
      final segPaint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringStrokeWidth
        ..strokeCap = StrokeCap.butt;

      final startAngle = -math.pi / 2 + i * sweepAngle;
      canvas.drawArc(ringRect, startAngle, sweepAngle, false, segPaint);
    }

    // 3. Directional bearing triangle (#000000) on outer rim
    if (showArrow && arrowSize > 0) {
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final tipX = center.dx + (totalOuterRadius + arrowSize) * cosA;
      final tipY = center.dy + (totalOuterRadius + arrowSize) * sinA;

      final baseHalf = arrowSize * 0.55;
      final baseCenterX = center.dx + (totalOuterRadius - 0.5) * cosA;
      final baseCenterY = center.dy + (totalOuterRadius - 0.5) * sinA;

      final p1X = baseCenterX - baseHalf * sinA;
      final p1Y = baseCenterY + baseHalf * cosA;
      final p2X = baseCenterX + baseHalf * sinA;
      final p2Y = baseCenterY - baseHalf * cosA;

      final arrowPath = ui.Path()
        ..moveTo(tipX, tipY)
        ..lineTo(p1X, p1Y)
        ..lineTo(p2X, p2Y)
        ..close();

      final arrowPaint = Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.fill;
      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BudapestGoPlatformPainter old) {
    return old.colors != colors ||
        old.angle != angle ||
        old.diameter != diameter ||
        old.strokeWidth != strokeWidth ||
        old.strokeColor != strokeColor ||
        old.showArrow != showArrow ||
        old.arrowSize != arrowSize ||
        old.isLod3 != isLod3 ||
        old.isDarkMode != isDarkMode;
  }
}

/// Non-fullscreen top-left floating search bar with Material 3 styling.
class _TopLeftFloatingSearchBar extends ConsumerStatefulWidget {
  final bool isDarkMode;
  final ValueChanged<Map<String, dynamic>> onVehicleSelected;
  final ValueChanged<StopNode> onStopSelected;

  const _TopLeftFloatingSearchBar({
    required this.isDarkMode,
    required this.onVehicleSelected,
    required this.onStopSelected,
  });

  @override
  ConsumerState<_TopLeftFloatingSearchBar> createState() => _TopLeftFloatingSearchBarState();
}

class _TopLeftFloatingSearchBarState extends ConsumerState<_TopLeftFloatingSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _query = val.trim();
        });
      }
    });
  }

  void _clearSearch() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 500;
    final searchWidth = isCompact ? MediaQuery.sizeOf(context).width - 32 : 360.0;
    final isDark = widget.isDarkMode;

    final bgColor = theme.colorScheme.surfaceContainerHigh;
    final borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.7);

    return SizedBox(
      width: searchWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top search bar
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onChanged,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      hintText: isCompact ? 'Keresés...' : 'Járat vagy megálló keresése...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty || _query.isNotEmpty)
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: _clearSearch,
                    splashRadius: 18,
                  )
                else
                  const SizedBox(width: 10),
              ],
            ),
          ),

          // Dropdown results panel
          if (_query.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _SearchDropdownResults(
                    query: _query,
                    isDarkMode: isDark,
                    onVehicleSelected: (props) {
                      _clearSearch();
                      widget.onVehicleSelected(props);
                    },
                    onStopSelected: (stop) {
                      _clearSearch();
                      widget.onStopSelected(stop);
                    },
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchDropdownResults extends ConsumerWidget {
  final String query;
  final bool isDarkMode;
  final ValueChanged<Map<String, dynamic>> onVehicleSelected;
  final ValueChanged<StopNode> onStopSelected;

  const _SearchDropdownResults({
    required this.query,
    required this.isDarkMode,
    required this.onVehicleSelected,
    required this.onStopSelected,
  });

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ő', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ű', 'u');
  }

  List<Map<String, dynamic>> _filterVehicles(String geoJsonStr, String normQ) {
    if (geoJsonStr.isEmpty) return const [];
    try {
      final data = jsonDecode(geoJsonStr) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      final matches = <Map<String, dynamic>>[];

      for (final f in features) {
        final feat = f as Map<String, dynamic>;
        final props = (feat['properties'] as Map<String, dynamic>?) ?? {};
        final geom = feat['geometry'] as Map<String, dynamic>?;
        final coords = geom?['coordinates'] as List<dynamic>?;
        if (coords != null && coords.length >= 2) {
          props['lon'] = (coords[0] as num).toDouble();
          props['lat'] = (coords[1] as num).toDouble();
        }

        final lineName = (props['line_name'] as String? ?? '').trim();
        final tripShortName = (props['trip_short_name'] as String? ?? '').trim();
        final dest = (props['destination'] as String? ?? '').trim();

        final nLine = _normalize(lineName);
        final nTrip = _normalize(tripShortName);
        final nDest = _normalize(dest);

        if (nLine.contains(normQ) || nTrip.contains(normQ) || nDest.contains(normQ)) {
          matches.add(props);
        }
      }

      matches.sort((a, b) {
        final lA = _normalize(a['line_name'] as String? ?? '');
        final lB = _normalize(b['line_name'] as String? ?? '');
        final exactA = lA == normQ;
        final exactB = lB == normQ;
        if (exactA != exactB) return exactA ? -1 : 1;
        final prefA = lA.startsWith(normQ);
        final prefB = lB.startsWith(normQ);
        if (prefA != prefB) return prefA ? -1 : 1;
        return lA.compareTo(lB);
      });

      return matches.take(15).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normQ = _normalize(query.trim());
    final rawGeoJson = ref.watch(liveVehiclesGeoJsonProvider).valueOrNull ?? '';
    final liveMatches = _filterVehicles(rawGeoJson, normQ);
    final stopsAsync = ref.watch(stopSearchProvider(query.trim()));

    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final subtextColor = theme.colorScheme.onSurfaceVariant;

    return stopsAsync.when(
      data: (stops) {
        if (liveMatches.isEmpty && stops.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Center(
              child: Text(
                'Nem található járat vagy megálló.',
                style: TextStyle(color: subtextColor, fontSize: 13),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          children: [
            if (liveMatches.isNotEmpty) ...[
              _buildSectionHeader(
                icon: Icons.sensors,
                title: 'ÉLŐ JÁRATOK ÉS VONATOK',
                count: liveMatches.length,
                color: const Color(0xFF38BDF8),
              ),
              ...liveMatches.map((props) => _buildVehicleTile(context, props, textColor, subtextColor)),
              const Divider(height: 12, thickness: 0.5),
            ],
            if (stops.isNotEmpty) ...[
              _buildSectionHeader(
                icon: Icons.location_on_outlined,
                title: 'ÁLLOMÁSOK ÉS MEGÁLLÓK',
                count: stops.length,
                color: const Color(0xFF818CF8),
              ),
              ...stops.map((stop) => _buildStopTile(context, stop, textColor, subtextColor)),
            ],
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(20.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: Text('Hiba: $e', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$title ($count)',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleTile(
    BuildContext context,
    Map<String, dynamic> props,
    Color textColor,
    Color subtextColor,
  ) {
    final lineName = (props['line_name'] as String? ?? '').trim();
    final tripShort = (props['trip_short_name'] as String? ?? '').trim();
    final dest = (props['destination'] as String? ?? '').trim();
    final vType = props['vehicle_type'] as String? ?? 'bus';
    final op = (props['operator'] as String? ?? 'BKK').toUpperCase();
    final badge = lineName.isNotEmpty ? lineName : (tripShort.isNotEmpty ? tripShort : 'JÁRAT');

    final badgeBg = getModeBadgeColor(vType);
    final badgeFg = getModeForegroundColor(vType);

    final delaySec = (props['delay_seconds'] as num?)?.toInt() ?? 0;
    final delayMin = (props['delay_minutes'] as num?)?.toInt() ?? (delaySec / 60).round();
    final isDelayed = delaySec > 60;
    final delayColor = isDelayed
        ? (delaySec > 300 ? const Color(0xFFEF4444) : const Color(0xFFEAB308))
        : const Color(0xFF22C55E);
    final delayLabel = isDelayed ? '+$delayMin p' : 'Pontos';

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          badge,
          style: TextStyle(
            color: badgeFg,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
      title: Text(
        dest.isNotEmpty ? '$dest felé' : badge,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(op, style: TextStyle(color: subtextColor, fontSize: 11)),
          const SizedBox(width: 6),
          Text('•', style: TextStyle(color: subtextColor, fontSize: 11)),
          const SizedBox(width: 6),
          Text(
            delayLabel,
            style: TextStyle(color: delayColor, fontWeight: FontWeight.w600, fontSize: 11),
          ),
        ],
      ),
      onTap: () => onVehicleSelected(props),
    );
  }

  Widget _buildStopTile(
    BuildContext context,
    StopNode stop,
    Color textColor,
    Color subtextColor,
  ) {
    final isMav = stop.operator == Operator.mav;
    final isMm = stop.isMultimodalHub;

    final IconData icon = isMm
        ? Icons.hub_outlined
        : (isMav ? Icons.train : Icons.directions_transit);

    final Color iconColor = isMm
        ? const Color(0xFF818CF8)
        : (isMav ? const Color(0xFF38BDF8) : const Color(0xFF22D3EE));

    final served = stop.servedRoutes?.trim() ?? '';

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 17),
      ),
      title: Text(
        stop.name,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: served.isNotEmpty
          ? Text(
              served,
              style: TextStyle(color: subtextColor, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: () => onStopSelected(stop),
    );
  }
}
