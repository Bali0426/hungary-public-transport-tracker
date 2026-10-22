import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/bridge_generated.dart';
import '../providers/live_vehicles_provider.dart';
import '../providers/timetable_provider.dart';
import '../utils/transit_display_utils.dart';

/// Normalize text by lowercasing and stripping Hungarian diacritics.
String _normalizeText(String input) {
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

/// Helper to parse hex color safely.
Color _parseHexColor(String? hexString, Color fallback) {
  if (hexString == null || hexString.isEmpty) return fallback;
  final clean = hexString.replaceAll('#', '').trim();
  if (clean.length == 6) {
    final val = int.tryParse('FF$clean', radix: 16);
    if (val != null) return Color(val);
  } else if (clean.length == 8) {
    final val = int.tryParse(clean, radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}

/// Convert vehicle GeoJSON feature properties to a StopNode representation.
StopNode vehiclePropsToStopNode(Map<String, dynamic> props) {
  final id = props['id'] as String? ?? '';
  final lineName = (props['line_name'] as String? ?? '').trim();
  final tripShortName = (props['trip_short_name'] as String? ?? '').trim();
  final displayName = lineName.isNotEmpty
      ? lineName
      : (tripShortName.isNotEmpty ? tripShortName : 'Élő jármű');
  final lat = (props['lat'] as num?)?.toDouble() ?? 0.0;
  final lon = (props['lon'] as num?)?.toDouble() ?? 0.0;
  final opStr = (props['operator'] as String? ?? 'BKK').toUpperCase();

  return StopNode(
    id: 'VEHICLE:$id',
    hubId: null,
    name: displayName,
    lat: lat,
    lon: lon,
    operator: opStr == 'MAV' ? Operator.mav : Operator.bkk,
    platformCode: null,
    isMultimodalHub: false,
    vehicleType: props['vehicle_type'] as String?,
    servedRoutes: lineName.isNotEmpty ? lineName : null,
    direction: props['destination'] as String?,
  );
}

/// Filter live vehicles from the real-time GeoJSON stream.
List<Map<String, dynamic>> filterLiveVehicles(String geoJsonStr, String normQ) {
  if (geoJsonStr.isEmpty || normQ.isEmpty) return const [];
  try {
    final map = jsonDecode(geoJsonStr) as Map<String, dynamic>;
    final features = map['features'] as List<dynamic>? ?? const [];
    final matches = <Map<String, dynamic>>[];

    for (final f in features) {
      final feature = f as Map<String, dynamic>;
      final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
      final lineName = (props['line_name'] as String? ?? '').trim();
      final tripShortName = (props['trip_short_name'] as String? ?? '').trim();
      final destination = (props['destination'] as String? ?? '').trim();

      final normLine = _normalizeText(lineName);
      final normTrip = _normalizeText(tripShortName);
      final normDest = _normalizeText(destination);

      if (normLine.contains(normQ) ||
          normTrip.contains(normQ) ||
          normDest.contains(normQ)) {
        matches.add(props);
      }
    }

    // Rank exact matches and prefix matches higher
    matches.sort((a, b) {
      final lA = _normalizeText(a['line_name'] as String? ?? '');
      final lB = _normalizeText(b['line_name'] as String? ?? '');
      final tA = _normalizeText(a['trip_short_name'] as String? ?? '');
      final tB = _normalizeText(b['trip_short_name'] as String? ?? '');

      final exactA = lA == normQ;
      final exactB = lB == normQ;
      if (exactA != exactB) return exactA ? -1 : 1;

      final prefLineA = lA.startsWith(normQ);
      final prefLineB = lB.startsWith(normQ);
      if (prefLineA != prefLineB) return prefLineA ? -1 : 1;

      final prefTripA = tA.startsWith(normQ);
      final prefTripB = tB.startsWith(normQ);
      if (prefTripA != prefTripB) return prefTripA ? -1 : 1;

      final lenDiff = lA.length.compareTo(lB.length);
      if (lenDiff != 0) return lenDiff;

      return lA.compareTo(lB);
    });

    return matches.take(20).toList();
  } catch (_) {
    return const [];
  }
}

/// Provider aliases for route and stop searches.
final searchStopsProvider = stopSearchProvider;

/// Provider that extracts matching active live vehicles from the real-time GeoJSON stream.
final searchActiveVehiclesProvider = Provider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, query) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];
  final rawGeoJson = ref.watch(liveVehiclesGeoJsonProvider).valueOrNull ?? '';
  return filterLiveVehicles(rawGeoJson, _normalizeText(trimmed));
});

/// Alias for transit routes search.
final searchTransitRoutesProvider = searchActiveVehiclesProvider;

/// Material You (M3) floating search bar positioned in the top-left corner
/// with a dropdown card directly below displaying live vehicles and stops.
class TopLeftFloatingSearch extends ConsumerStatefulWidget {
  final void Function(StopNode selected) onResultSelected;

  const TopLeftFloatingSearch({
    super.key,
    required this.onResultSelected,
  });

  @override
  ConsumerState<TopLeftFloatingSearch> createState() => _TopLeftFloatingSearchState();
}

class _TopLeftFloatingSearchState extends ConsumerState<TopLeftFloatingSearch> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounceTimer;
  String _debouncedQuery = '';
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() => _isOpen = true);
    }
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _debouncedQuery = query.trim();
          _isOpen = true;
        });
      }
    });
    setState(() {}); // Updates clear icon visibility
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() {
      _debouncedQuery = '';
      _isOpen = false;
    });
    _focusNode.unfocus();
  }

  void _selectStop(StopNode stop) {
    _debounceTimer?.cancel();
    _focusNode.unfocus();
    setState(() => _isOpen = false);
    widget.onResultSelected(stop);
  }

  void _selectVehicle(Map<String, dynamic> props) {
    _debounceTimer?.cancel();
    _focusNode.unfocus();
    setState(() => _isOpen = false);
    widget.onResultSelected(vehiclePropsToStopNode(props));
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive width: 360-400 on tablet/desktop, adaptively bound on mobile screens
    final double searchWidth = screenWidth < 440 ? (screenWidth - 32) : 380.0;
    final showClear = _controller.text.isNotEmpty || _isOpen;

    return SizedBox(
      width: searchWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact, rounded Material 3 SearchBar / Surface
          Material(
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 22,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onChanged: _onQueryChanged,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Járat, vonat vagy állomás...',
                        hintStyle: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (showClear)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: theme.colorScheme.onSurfaceVariant,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Törlés',
                      onPressed: _clearSearch,
                    ),
                ],
              ),
            ),
          ),

          // Dropdown Card with results directly beneath
          if (_isOpen && _debouncedQuery.isNotEmpty) ...[
            const SizedBox(height: 6),
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              color: theme.colorScheme.surfaceContainerHigh,
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: _SearchResultsView(
                  query: _debouncedQuery,
                  onStopSelected: _selectStop,
                  onVehicleSelected: _selectVehicle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// SearchDelegate that queries real-time vehicles/trains and local SQLite stop hubs across BKK and MÁV.
/// Kept for backward compatibility.
class LineAndStopSearchDelegate extends SearchDelegate<StopNode?> {
  final WidgetRef ref;

  LineAndStopSearchDelegate(this.ref)
      : super(
          searchFieldLabel: 'Járat, vonat vagy állomás keresése (BKK, MÁV)...',
        );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.white54),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResultsView(
      query: query,
      onStopSelected: (stop) => close(context, stop),
      onVehicleSelected: (props) => close(context, vehiclePropsToStopNode(props)),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _SearchResultsView(
      query: query,
      onStopSelected: (stop) => close(context, stop),
      onVehicleSelected: (props) => close(context, vehiclePropsToStopNode(props)),
    );
  }
}

class _SearchResultsView extends ConsumerWidget {
  final String query;
  final ValueChanged<StopNode> onStopSelected;
  final ValueChanged<Map<String, dynamic>> onVehicleSelected;

  const _SearchResultsView({
    required this.query,
    required this.onStopSelected,
    required this.onVehicleSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Text(
            'Írj be egy járatot (pl. 4, 6, 100E, S10, Z70, TÓPART) vagy állomást (pl. Keleti, Deák Ferenc tér, Kelenföld)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // 1. Filter live vehicles from the real-time stream
    final liveMatches = ref.watch(searchActiveVehiclesProvider(trimmedQuery));

    // 2. Fetch stops from local SQLite database
    final stopsAsync = ref.watch(searchStopsProvider(trimmedQuery));

    return stopsAsync.when(
      data: (stops) {
        if (liveMatches.isEmpty && stops.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Nem található járat vagy állomás ezzel a névvel.',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          children: [
            // --- SECTION 1: ROUTES & VEHICLES ---
            if (liveMatches.isNotEmpty) ...[
              _buildSectionHeader(
                context: context,
                icon: Icons.directions_transit,
                title: 'JÁRATOK',
                count: liveMatches.length,
                color: theme.colorScheme.primary,
              ),
              ...liveMatches.map((props) => _buildVehicleTile(context, props)),
              const SizedBox(height: 6),
            ],

            // --- SECTION 2: STOPS & STATIONS ---
            if (stops.isNotEmpty) ...[
              _buildSectionHeader(
                context: context,
                icon: Icons.place,
                title: 'MEGÁLLÓK ÉS ÁLLOMÁSOK',
                count: stops.length,
                color: theme.colorScheme.secondary,
              ),
              ...stops.map((stop) => _buildStopTile(context, stop)),
            ],
          ],
        );
      },
      loading: () {
        if (liveMatches.isNotEmpty) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            children: [
              _buildSectionHeader(
                context: context,
                icon: Icons.directions_transit,
                title: 'JÁRATOK',
                count: liveMatches.length,
                color: theme.colorScheme.primary,
              ),
              ...liveMatches.map((props) => _buildVehicleTile(context, props)),
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ],
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      },
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Keresési hiba: $err',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
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
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleTile(BuildContext context, Map<String, dynamic> props) {
    final theme = Theme.of(context);
    final lineName = (props['line_name'] as String? ?? '').trim();
    final tripShortName = (props['trip_short_name'] as String? ?? '').trim();
    final destination = (props['destination'] as String? ?? '').trim();
    final opStr = (props['operator'] as String? ?? 'BKK').toUpperCase();
    final isMav = opStr == 'MAV';

    final badgeText = lineName.isNotEmpty ? lineName : tripShortName;
    final fallbackBadgeColor = isMav ? const Color(0xFF003B7A) : getLineOrRouteColor(badgeText);
    final badgeColor = _parseHexColor(props['route_color'] as String?, fallbackBadgeColor);
    final textColor = getRouteForegroundColor(badgeColor);

    final delaySec = (props['delay_seconds'] as num?)?.toInt() ?? 0;
    final delayMin = (props['delay_minutes'] as num?)?.toInt() ?? (delaySec / 60).round();
    final isDelayed = delaySec > 60;
    final delayColor = isDelayed
        ? (delaySec > 300 ? const Color(0xFFEF4444) : const Color(0xFFEAB308))
        : const Color(0xFF22C55E);
    final delayText = isDelayed ? '+$delayMin perc késés' : 'Pontos';

    final hasDetailedTrip = tripShortName.isNotEmpty && tripShortName != lineName;
    final titleText = hasDetailedTrip
        ? '$tripShortName ➔ ${destination.isNotEmpty ? destination : "Végállomás"}'
        : (destination.isNotEmpty ? '$destination felé' : badgeText);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          badgeText.isEmpty ? (isMav ? 'VONAT' : 'JÁRAT') : badgeText,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
          ),
        ),
      ),
      title: Text(
        titleText,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Text(
            isMav ? 'MÁV-START' : 'BKK',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(width: 5),
          Text('•', style: TextStyle(color: theme.colorScheme.outlineVariant, fontSize: 11)),
          const SizedBox(width: 5),
          Text(
            delayText,
            style: TextStyle(
              color: delayColor,
              fontWeight: isDelayed ? FontWeight.w600 : FontWeight.normal,
              fontSize: 11,
            ),
          ),
        ],
      ),
      trailing: Icon(
        Icons.sensors,
        size: 16,
        color: delayColor.withValues(alpha: 0.8),
      ),
      onTap: () => onVehicleSelected(props),
    );
  }

  Widget _buildStopTile(BuildContext context, StopNode stop) {
    final theme = Theme.of(context);
    final isMav = stop.operator == Operator.mav;
    final isMm = stop.isMultimodalHub;

    final IconData icon = isMm
        ? Icons.hub_outlined
        : (isMav ? Icons.train : Icons.directions_transit);

    final Color iconColor = isMm
        ? const Color(0xFF818CF8)
        : (isMav ? const Color(0xFF003B7A) : const Color(0xFF009EE3));

    final String opText = isMm
        ? 'Multimodális csomópont (BKK + MÁV)'
        : (isMav ? 'MÁV-START vasútállomás' : 'BKK megállócsoport');

    final servedRoutes = stop.servedRoutes?.trim() ?? '';

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: iconColor.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        stop.name,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            opText,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
          ),
          if (servedRoutes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Járatok: $servedRoutes',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        size: 18,
      ),
      onTap: () => onStopSelected(stop),
    );
  }
}
