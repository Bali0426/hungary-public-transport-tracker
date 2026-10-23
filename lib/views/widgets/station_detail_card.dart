import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_generated.dart';
import '../../providers/timetable_provider.dart';
import '../../utils/transit_display_utils.dart';

bool _isTerminatingAtCurrentStation(UnifiedDeparture dep, String stationName) {
  if (dep.isArrival) return true;
  final h = dep.headsign.trim().toLowerCase();
  if (h == 'nem szállít utasokat' ||
      h == 'garázsmenet' ||
      h == 'csak leszállás' ||
      h == 'végállomás') {
    return true;
  }
  return _matchesStation(dep.headsign, stationName);
}

bool _matchesStation(String name1, String name2) {
  final s1 = _simplifyStationName(name1);
  final s2 = _simplifyStationName(name2);
  if (s1.isEmpty || s2.isEmpty) return false;
  return s1 == s2;
}

String _simplifyStationName(String name) {
  var s = name.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
  if (s.contains('/')) {
    s = s.split('/').first.trim();
  }
  s = s.replaceAll('budapest-', ' ').replaceAll('budapest ', ' ');
  for (final suffix in const [
    'vasútállomás',
    'pályaudvar',
    'pu.',
    'vá.',
    'm+h',
  ]) {
    s = s.replaceAll(suffix, ' ');
  }
  final tokens = s
      .split(RegExp(r'[^a-záéíóöőúüű0-9]+'))
      .where((t) => t.isNotEmpty && t != 'm' && t != 'h' && t != 'pu' && t != 'vá')
      .toList();
  return tokens.join();
}

/// Style configuration for a transit route badge according to the official BudapestGO spec.
class RouteBadgeStyle {
  final Color bg;
  final Color fg;
  final String mode;

  const RouteBadgeStyle({
    required this.bg,
    required this.fg,
    required this.mode,
  });
}

/// Resolves authentic BKK / BudapestGO color codes (Chapter 3 & 5):
/// - M1: #FFD800 (dark text)
/// - M2: #E41F18
/// - M3: #005CA5
/// - M4: #439539
/// - H5: #821380
/// - H6: #86421B
/// - H7: #EE7203
/// - H8/H9: #E52320
/// - Villamos: #FFD800 (dark text)
/// - Busz: #009EE3
/// - Troli: #E41F18
/// - Éjszakai (900-as): #1A1A1A
/// - Hajó: #E52082
/// - MÁV: #003B7A
RouteBadgeStyle resolveRouteBadgeStyle({
  required String line,
  Operator? operator,
  String? vehicleType,
  String? routeColor,
}) {
  final trimmed = line.trim();
  final upper = trimmed.toUpperCase();

  // 1. MÁV trains
  final isSuburbanRailLine = RegExp(r'^[SGZ]\d{2,4}$').hasMatch(upper);
  final isNamedTrain = upper.endsWith(' IC') ||
      upper.endsWith(' IR') ||
      upper.endsWith(' EC') ||
      upper.endsWith(' EN') ||
      upper.endsWith(' EX') ||
      upper.contains(' IC ') ||
      upper.contains(' IR ') ||
      upper.contains('/ GY') ||
      upper.contains('RAILJET') ||
      upper.startsWith('SZ ');
  if (operator == Operator.mav ||
      vehicleType == 'train' ||
      vehicleType == 'rail' ||
      isSuburbanRailLine ||
      isNamedTrain ||
      upper.startsWith('IC') ||
      upper.startsWith('IR') ||
      upper.startsWith('EC') ||
      upper.startsWith('EN') ||
      upper.startsWith('RJ') ||
      upper.startsWith('S1') ||
      upper.startsWith('S2') ||
      upper.startsWith('S3') ||
      upper.startsWith('S4') ||
      upper.startsWith('S5') ||
      upper.startsWith('S6') ||
      upper.startsWith('S7') ||
      upper.startsWith('S8') ||
      upper.startsWith('G1') ||
      upper.startsWith('G4') ||
      upper.startsWith('G5') ||
      upper.startsWith('G6') ||
      upper.startsWith('G7') ||
      upper.startsWith('G8') ||
      upper.startsWith('Z3') ||
      upper.startsWith('Z4') ||
      upper.startsWith('Z5') ||
      upper.startsWith('Z6') ||
      upper.startsWith('Z7')) {
    return const RouteBadgeStyle(
      bg: Color(0xFF003B7A), // MÁV #003B7A
      fg: Colors.white,
      mode: 'train',
    );
  }

  // 2. Metro lines
  if (upper == 'M1') {
    return const RouteBadgeStyle(
      bg: Color(0xFFFFD800), // M1 #FFD800
      fg: Color(0xFF1A1A1A), // Dark text
      mode: 'metro',
    );
  }
  if (upper == 'M2') {
    return const RouteBadgeStyle(
      bg: Color(0xFFE41F18), // M2 #E41F18
      fg: Colors.white,
      mode: 'metro',
    );
  }
  if (upper == 'M3') {
    return const RouteBadgeStyle(
      bg: Color(0xFF005CA5), // M3 #005CA5
      fg: Colors.white,
      mode: 'metro',
    );
  }
  if (upper == 'M4') {
    return const RouteBadgeStyle(
      bg: Color(0xFF439539), // M4 #439539
      fg: Colors.white,
      mode: 'metro',
    );
  }
  if (upper.startsWith('M') && upper.length <= 3) {
    return const RouteBadgeStyle(
      bg: Color(0xFF005CA5),
      fg: Colors.white,
      mode: 'metro',
    );
  }

  // 3. HÉV lines
  if (upper == 'H5') {
    return const RouteBadgeStyle(
      bg: Color(0xFF821380), // H5 #821380
      fg: Colors.white,
      mode: 'suburban_rail',
    );
  }
  if (upper == 'H6') {
    return const RouteBadgeStyle(
      bg: Color(0xFF86421B), // H6 #86421B
      fg: Colors.white,
      mode: 'suburban_rail',
    );
  }
  if (upper == 'H7') {
    return const RouteBadgeStyle(
      bg: Color(0xFFEE7203), // H7 #EE7203
      fg: Colors.white,
      mode: 'suburban_rail',
    );
  }
  if (upper == 'H8' || upper == 'H9') {
    return const RouteBadgeStyle(
      bg: Color(0xFFE52320), // H8/H9 #E52320
      fg: Colors.white,
      mode: 'suburban_rail',
    );
  }
  if (upper.startsWith('H') && upper.length <= 3) {
    return const RouteBadgeStyle(
      bg: Color(0xFF007A33),
      fg: Colors.white,
      mode: 'suburban_rail',
    );
  }

  // 4. Hajó (Boat / Ferry)
  if (upper.startsWith('D') && upper.length <= 4) {
    return const RouteBadgeStyle(
      bg: Color(0xFFE52082), // Hajó #E52082
      fg: Colors.white,
      mode: 'boat',
    );
  }

  // 5. Éjszakai járatok (900-as vonalcsoport)
  if (upper.startsWith('9')) {
    return const RouteBadgeStyle(
      bg: Color(0xFF1A1A1A), // Éjszakai #1A1A1A
      fg: Colors.white,
      mode: 'bus',
    );
  }

  // 6. Trolibuszok
  final numVal = int.tryParse(trimmed);
  final isTrolleyNumber = numVal != null && numVal >= 70 && numVal <= 83;
  final isTrolleyColor = routeColor != null &&
      (routeColor.toLowerCase().contains('e41') || routeColor.toLowerCase().contains('dc2'));
  final isTrolleyType = vehicleType == 'trolley' || vehicleType == 'trolleybus';

  if (isTrolleyType || isTrolleyColor || isTrolleyNumber) {
    return const RouteBadgeStyle(
      bg: Color(0xFFE41F18), // Troli #E41F18
      fg: Colors.white,
      mode: 'trolley',
    );
  }

  // 7. Villamosok
  final isTramColor = routeColor != null &&
      (routeColor.toLowerCase().contains('ffd') || routeColor.toLowerCase().contains('ffa'));
  final isKnownTram = upper == '1' ||
      upper == '1A' ||
      upper == '2' ||
      upper == '2B' ||
      upper == '3' ||
      upper == '4' ||
      upper == '6' ||
      upper == '4-6' ||
      upper == '12' ||
      upper == '14' ||
      upper == '17' ||
      upper == '19' ||
      upper == '23' ||
      upper == '24' ||
      upper == '28' ||
      upper == '28A' ||
      upper == '37' ||
      upper == '37A' ||
      upper == '41' ||
      upper == '42' ||
      upper == '47' ||
      upper == '48' ||
      upper == '49' ||
      upper == '50' ||
      upper == '51' ||
      upper == '51A' ||
      upper == '52' ||
      upper == '56' ||
      upper == '56A' ||
      upper == '59' ||
      upper == '59A' ||
      upper == '59B' ||
      upper == '60' ||
      upper == '61' ||
      upper == '62' ||
      upper == '62A' ||
      upper == '69';
  final isTramType = vehicleType == 'tram';

  if (isTramType || isTramColor || isKnownTram) {
    return const RouteBadgeStyle(
      bg: Color(0xFFFFD800), // Villamos #FFD800
      fg: Color(0xFF1A1A1A), // Sötét szöveg a sárga háttérhez
      mode: 'tram',
    );
  }

  // 8. Autóbusz (Bus) default
  return const RouteBadgeStyle(
    bg: Color(0xFF009EE3), // Busz #009EE3
    fg: Colors.white,
    mode: 'bus',
  );
}

enum TransitFilter {
  all,
  train,
  local,
}

bool _isTrainDeparture(UnifiedDeparture dep, [String? stationVehicleType]) {
  if (dep.operator == Operator.mav) return true;
  final style = resolveRouteBadgeStyle(
    line: dep.lineName,
    operator: dep.operator,
    vehicleType: dep.operator == Operator.mav ? 'train' : null,
    routeColor: dep.routeColor,
  );
  return style.mode == 'train';
}

bool _isRailwayHubStation(StopNode station, List<UnifiedDeparture> departures) {
  final hasTrain = departures.any((d) => _isTrainDeparture(d, station.vehicleType));
  final hasLocal = departures.any((d) => !_isTrainDeparture(d, station.vehicleType));
  if (hasTrain && hasLocal) return true;

  if (station.isMultimodalHub && hasTrain) return true;
  if (station.operator == Operator.mav) return true;
  if (station.vehicleType == 'train' || station.vehicleType == 'rail') return true;

  final lower = station.name.toLowerCase();
  const hubKeywords = [
    'keleti',
    'nyugati',
    'déli',
    'deli',
    'kelenföld',
    'kelenfold',
    'kőbánya-kispest',
    'kobanya-kispest',
    'zugló',
    'zuglo',
    'ferihegy',
    'debrecen',
    'szeged',
    'győr',
    'gyor',
    'pécs',
    'pecs',
    'miskolc',
    'székesfehérvár',
    'szekesfehervar',
    'vasútállomás',
    'vasutallomas',
    'pályaudvar',
    'palyaudvar',
    'pu.',
    'vá.',
  ];
  return hubKeywords.any((k) => lower.contains(k));
}

/// Floating Station Detail Pop-up Card matching BKK / OSM Public Transport style in Material 3.
class StationDetailCard extends ConsumerStatefulWidget {
  final StopNode station;
  final VoidCallback onClose;
  final void Function(UnifiedDeparture departure)? onDepartureTapped;

  const StationDetailCard({
    super.key,
    required this.station,
    required this.onClose,
    this.onDepartureTapped,
  });

  @override
  ConsumerState<StationDetailCard> createState() => _StationDetailCardState();
}

class _StationDetailCardState extends ConsumerState<StationDetailCard> {
  final ScrollController _scrollController = ScrollController();
  bool _queryHub = false;
  bool _showArrivals = false;
  TransitFilter _transitFilter = TransitFilter.all;
  bool _hasScrolledToNow = false;
  int _firstUpcomingIndex = -1;
  String? _lastStationId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant StationDetailCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.station.id != widget.station.id) {
      _transitFilter = TransitFilter.all;
      _showArrivals = false;
      _hasScrolledToNow = false;
      _firstUpcomingIndex = -1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    if (_lastStationId != station.id) {
      _lastStationId = station.id;
      _hasScrolledToNow = false;
      _transitFilter = TransitFilter.all;
      _firstUpcomingIndex = -1;
    }
    final isRailwayHub = _isRailwayHubStation(station, const []);
    final isInitialHub = isRailwayHub ||
        station.isMultimodalHub ||
        station.id.startsWith('HUB:') ||
        station.id.startsWith('GROUP:');
    final isGroupView = isInitialHub ? true : _queryHub;
    final theme = Theme.of(context);

    // If viewing the entire stop group / hub, use GROUP:<name>:<lat>:<lon>.
    // Otherwise strictly query the single stop / platform (STOP:<id>).
    final lookupKey = isGroupView
        ? 'GROUP:${station.name}:${station.lat}:${station.lon}'
        : 'STOP:${station.id}';

    final departuresAsync = ref.watch(stationDepartureBoardProvider(lookupKey));
    final stopCode = station.id.replaceAll('BKK_', '').replaceAll('BKK:', '');
    final allDepartures = departuresAsync.valueOrNull ?? const [];
    final showMultimodalTabs = _isRailwayHubStation(station, allDepartures);
    if (!showMultimodalTabs && _transitFilter != TransitFilter.all) {
      _transitFilter = TransitFilter.all;
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Header Row: Station Name & Action Icons
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      station.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Platform vs Hub switcher icon (available for individual platforms)
                  if (!isInitialHub)
                    IconButton(
                      tooltip: isGroupView ? 'Váltás peronra' : 'Váltás teljes megállócsoportra',
                      icon: Icon(
                        isGroupView ? Icons.layers : Icons.layers_outlined,
                        size: 18,
                        color: isGroupView ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => setState(() => _queryHub = !_queryHub),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 6),
                  // Clock icon in M3 primary container circle
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.schedule,
                        size: 15,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Close button
                  IconButton(
                    tooltip: 'Bezárás',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // 2. Subheader Row: Stop Code / Group Badge + Platform/Direction + Links + Timestamp
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (isGroupView)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hub_outlined,
                                  size: 12,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Megállócsoport (összes peron)',
                                    style: TextStyle(
                                      color: theme.colorScheme.onPrimaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '#$stopCode${(station.platformCode != null && station.platformCode!.isNotEmpty) ? ' • ${station.platformCode}. peron' : ''}',
                            style: TextStyle(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (station.direction != null && station.direction!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              station.direction!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(width: 8),
                      const Spacer(),
                      Text(
                        'Frissítve 0 perce',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      InkWell(
                        onTap: () => setState(() {
                          _showArrivals = false;
                          _hasScrolledToNow = false;
                        }),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: !_showArrivals
                                ? theme.colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.near_me_outlined,
                                size: 12,
                                color: !_showArrivals
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Indulások',
                                style: TextStyle(
                                  color: !_showArrivals
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11.5,
                                  fontWeight: !_showArrivals ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => setState(() {
                          _showArrivals = true;
                          _hasScrolledToNow = false;
                        }),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _showArrivals
                                ? theme.colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.south_west,
                                size: 12,
                                color: _showArrivals
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Érkezések',
                                style: TextStyle(
                                  color: _showArrivals
                                      ? theme.colorScheme.onPrimaryContainer
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11.5,
                                  fontWeight: _showArrivals ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Multimodal Transit Filter Tabs (MÁV vs BKK vs Összes)
                  if (showMultimodalTabs) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTransitFilterChip(
                            theme: theme,
                            label: 'Összes járat',
                            icon: Icons.alt_route,
                            selected: _transitFilter == TransitFilter.all,
                            onTap: () => setState(() {
                              _transitFilter = TransitFilter.all;
                              _hasScrolledToNow = false;
                            }),
                          ),
                          const SizedBox(width: 6),
                          _buildTransitFilterChip(
                            theme: theme,
                            label: 'Vasúti menetrend (MÁV)',
                            icon: Icons.train,
                            selected: _transitFilter == TransitFilter.train,
                            onTap: () => setState(() {
                              _transitFilter = TransitFilter.train;
                              _hasScrolledToNow = false;
                            }),
                          ),
                          const SizedBox(width: 6),
                          _buildTransitFilterChip(
                            theme: theme,
                            label: 'Helyi járatok (BKK)',
                            icon: Icons.directions_bus,
                            selected: _transitFilter == TransitFilter.local,
                            onTap: () => setState(() {
                              _transitFilter = TransitFilter.local;
                              _hasScrolledToNow = false;
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 3. Route Badges Bar (Járatok a megállóban)
            _buildServedRoutesBar(
              theme,
              allDepartures.where((dep) {
                final isTrain = _isTrainDeparture(dep);
                if (_transitFilter == TransitFilter.train && !isTrain) return false;
                if (_transitFilter == TransitFilter.local && isTrain) return false;

                if (_showArrivals) {
                  if (dep.originStation != null &&
                      _matchesStation(dep.originStation!, widget.station.name)) {
                    return false;
                  }
                  if (isTrain) {
                    return dep.isArrival ||
                        _matchesStation(dep.headsign, widget.station.name) ||
                        dep.scheduledArrivalTimeFormatted != null ||
                        dep.estimatedArrivalTimeFormatted != null;
                  }
                  return dep.isArrival || _matchesStation(dep.headsign, widget.station.name);
                } else {
                  if (_isTerminatingAtCurrentStation(dep, widget.station.name)) {
                    return false;
                  }
                  return true;
                }
              }).toList(),
            ),

            const Divider(height: 1),

            // 4. Live Departures List
            Expanded(
              child: departuresAsync.when(
                data: (departures) {
                  var displayedDepartures = departures.where((dep) {
                    final isTrain = _isTrainDeparture(dep);
                    if (_transitFilter == TransitFilter.train && !isTrain) {
                      return false;
                    }
                    if (_transitFilter == TransitFilter.local && isTrain) {
                      return false;
                    }

                    if (_showArrivals) {
                      if (dep.originStation != null &&
                          _matchesStation(dep.originStation!, widget.station.name)) {
                        return false;
                      }
                      if (isTrain) {
                        return dep.isArrival ||
                            _matchesStation(dep.headsign, widget.station.name) ||
                            dep.scheduledArrivalTimeFormatted != null ||
                            dep.estimatedArrivalTimeFormatted != null;
                      }
                      return dep.isArrival || _matchesStation(dep.headsign, widget.station.name);
                    } else {
                      if (_isTerminatingAtCurrentStation(dep, widget.station.name)) {
                        return false;
                      }
                      return true;
                    }
                  }).toList();

                  // Fallback: If in departures mode, all trips terminate here (e.g. at a terminus platform),
                  // display them instead of a blank card.
                  if (!_showArrivals && displayedDepartures.isEmpty && departures.isNotEmpty) {
                    displayedDepartures = departures.where((dep) {
                      final isTrain = _isTrainDeparture(dep);
                      if (_transitFilter == TransitFilter.train && !isTrain) return false;
                      if (_transitFilter == TransitFilter.local && isTrain) return false;
                      return true;
                    }).toList();
                  }

                  if (_showArrivals) {
                    final now = DateTime.now();
                    displayedDepartures.sort((a, b) {
                      final timeA = a.estimatedArrivalTimeFormatted ?? a.estimatedTimeFormatted;
                      final timeB = b.estimatedArrivalTimeFormatted ?? b.estimatedTimeFormatted;
                      return _parseDepartureTime(timeA, now)
                          .compareTo(_parseDepartureTime(timeB, now));
                    });
                  }

                  if (displayedDepartures.isEmpty) {
                    final String emptyMsg = _transitFilter == TransitFilter.train
                        ? (_showArrivals
                            ? 'Nincs menetrend szerinti vasúti érkezés a következő 90 percben.'
                            : 'Nincs menetrend szerinti vasúti indulás a következő 90 percben.')
                        : (_transitFilter == TransitFilter.local
                            ? (_showArrivals
                                ? 'Nincs menetrend szerinti helyi járat érkezés a következő 90 percben.'
                                : 'Nincs menetrend szerinti helyi járat indulás a következő 90 percben.')
                            : (_showArrivals
                                ? 'Nincs menetrend szerinti érkezés a következő 90 percben.'
                                : 'Nincs menetrend szerinti indulás a következő 90 percben.'));
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          emptyMsg,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final now = DateTime.now();
                  int firstUpcoming = -1;
                  for (int i = 0; i < displayedDepartures.length; i++) {
                    final dep = displayedDepartures[i];
                    final timeStr = _showArrivals
                        ? (dep.estimatedArrivalTimeFormatted ?? dep.estimatedTimeFormatted)
                        : dep.estimatedTimeFormatted;
                    final dt = _parseDepartureTime(timeStr, now);
                    if (!dt.isBefore(now.subtract(const Duration(minutes: 1)))) {
                      firstUpcoming = i;
                      break;
                    }
                  }
                  _firstUpcomingIndex = firstUpcoming;

                  if (!_hasScrolledToNow && firstUpcoming > 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients && !_hasScrolledToNow) {
                        _hasScrolledToNow = true;
                        final itemHeight = _transitFilter == TransitFilter.train ? 68.0 : 54.0;
                        final targetOffset = (firstUpcoming * itemHeight).clamp(
                          0.0,
                          _scrollController.position.maxScrollExtent,
                        );
                        if (targetOffset > 0) {
                          _scrollController.jumpTo(targetOffset);
                        } else {
                          Future.delayed(const Duration(milliseconds: 60), () {
                            if (_scrollController.hasClients) {
                              final retryOffset = (firstUpcoming * itemHeight).clamp(
                                0.0,
                                _scrollController.position.maxScrollExtent,
                              );
                              if (retryOffset > 0) {
                                _scrollController.jumpTo(retryOffset);
                              }
                            }
                          });
                        }
                      }
                    });
                  }

                  return Column(
                    children: [
                      if (firstUpcoming > 0)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.history, size: 12, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 5),
                              Text(
                                '$firstUpcoming korábbi járat a mai napról',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              InkWell(
                                onTap: () {
                                  if (_scrollController.hasClients && _firstUpcomingIndex > 0) {
                                    final itemHeight = _transitFilter == TransitFilter.train ? 68.0 : 54.0;
                                    final targetOffset = (_firstUpcomingIndex * itemHeight).clamp(
                                      0.0,
                                      _scrollController.position.maxScrollExtent,
                                    );
                                    _scrollController.animateTo(
                                      targetOffset,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    );
                                  }
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.arrow_downward, size: 11, color: theme.colorScheme.primary),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Ugrás a most indulókhoz',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      Expanded(
                        child: ListView.separated(
                          controller: _scrollController,
                          itemCount: displayedDepartures.length,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            thickness: 0.8,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                          itemBuilder: (context, idx) {
                            final dep = displayedDepartures[idx];
                            final isTrain = _isTrainDeparture(dep);
                            final style = resolveRouteBadgeStyle(
                              line: dep.lineName,
                              operator: dep.operator,
                              vehicleType: isTrain ? 'train' : null,
                              routeColor: dep.routeColor,
                            );

                            if (isTrain) {
                              return _buildTrainDepartureRow(
                                context,
                                theme,
                                dep,
                                style,
                                _showArrivals,
                              );
                            } else {
                              return _buildLocalDepartureRow(
                                context,
                                theme,
                                dep,
                                style,
                                _showArrivals,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Nem sikerült betölteni az indulásokat: $err',
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransitFilterChip({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a structured, professional MÁV train departure row matching M3 / BudapestGO spec
  Widget _buildTrainDepartureRow(
    BuildContext context,
    ThemeData theme,
    UnifiedDeparture dep,
    RouteBadgeStyle style,
    bool showArrivals,
  ) {
    final now = DateTime.now();
    final displayEstimatedTime = showArrivals
        ? (dep.estimatedArrivalTimeFormatted ?? dep.estimatedTimeFormatted)
        : dep.estimatedTimeFormatted;
    final scheduledTime = showArrivals
        ? (dep.scheduledArrivalTimeFormatted ?? dep.scheduledTimeFormatted)
        : dep.scheduledTimeFormatted;
    final targetTimeStr = displayEstimatedTime.isNotEmpty ? displayEstimatedTime : scheduledTime;
    final targetTime = _parseDepartureTime(targetTimeStr, now);
    final diffMin = targetTime.difference(now).inMinutes;

    final isDelayed = dep.delaySeconds > 120;
    final delayMin = (dep.delaySeconds / 60).round();
    final Color delayColor = dep.delaySeconds > 300
        ? const Color(0xFFDC2626) // > 5 min: red
        : (dep.delaySeconds > 120
            ? const Color(0xFFD97706) // 2-5 min: amber/yellow
            : const Color(0xFF16A34A)); // <= 2 min: green

    final isTerminatingHere = dep.isArrival || _matchesStation(dep.headsign, widget.station.name);
    final destinationText = showArrivals
        ? ((dep.originStation != null && dep.originStation!.isNotEmpty)
            ? (isTerminatingHere || dep.headsign.isEmpty
                ? 'Honnan: ${dep.originStation}'
                : 'Honnan: ${dep.originStation} (→ ${dep.headsign})')
            : '${dep.lineName} ide érkezik')
        : dep.headsign;

    final platformText = dep.platformCode == null || dep.platformCode!.isEmpty
        ? null
        : (dep.platformCode!.contains('vágány')
            ? dep.platformCode!
            : '${dep.platformCode}. vágány');

    final schedDt = scheduledTime.isNotEmpty ? _parseDepartureTime(scheduledTime, now) : null;
    final isSchedPassed = schedDt != null && schedDt.isBefore(now);
    final shouldStrikethrough = (isDelayed || isSchedPassed) &&
        scheduledTime.isNotEmpty &&
        scheduledTime != displayEstimatedTime;

    // Immediate departure badge (ONLY if 0 <= diffMin <= 1)
    final isImmediate = diffMin >= 0 && diffMin <= 1;

    final isDark = theme.brightness == Brightness.dark;
    Color rowBgColor;
    Color rowBorderColor;

    if (dep.isRealtime) {
      if (dep.delaySeconds > 600) {
        // 10+ min delay: soft red
        rowBgColor = isDark
            ? const Color(0xFF4A151B).withValues(alpha: 0.35)
            : const Color(0xFFFFEBEE);
        rowBorderColor = isDark
            ? const Color(0xFF8B0000).withValues(alpha: 0.3)
            : const Color(0xFFFFCDD2);
      } else if (dep.delaySeconds > 120) {
        // 3-9 min delay: soft yellow / amber
        rowBgColor = isDark
            ? const Color(0xFF3E3618).withValues(alpha: 0.35)
            : const Color(0xFFFFFDE7);
        rowBorderColor = isDark
            ? const Color(0xFFB45309).withValues(alpha: 0.3)
            : const Color(0xFFFFF59D);
      } else {
        // On-time / <= 2 min: soft green
        rowBgColor = isDark
            ? const Color(0xFF1B3B2B).withValues(alpha: 0.35)
            : const Color(0xFFE8F5E9);
        rowBorderColor = isDark
            ? const Color(0xFF16A34A).withValues(alpha: 0.3)
            : const Color(0xFFC8E6C9);
      }
    } else {
      rowBgColor = theme.colorScheme.surfaceContainerLow;
      rowBorderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.25);
    }

    final rollingStock = _inferRollingStock(dep);

    return InkWell(
      onTap: () {
        if (widget.onDepartureTapped != null) {
          widget.onDepartureTapped!(dep);
        } else {
          _showTrainTripDetailsSheet(context, theme, dep);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: rowBgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: rowBorderColor, width: 0.9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Line 1: [Times: Scheduled -> Estimated] [Destination] [Platform] [Azonnal]
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (shouldStrikethrough) ...[
                  Text(
                    scheduledTime,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      decoration: TextDecoration.lineThrough,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('→', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Text(
                    displayEstimatedTime,
                    style: TextStyle(
                      color: delayColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ] else ...[
                  Text(
                    displayEstimatedTime.isNotEmpty ? displayEstimatedTime : scheduledTime,
                    style: TextStyle(
                      color: isDelayed ? delayColor : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],

                const SizedBox(width: 8),

                // Destination
                Expanded(
                  child: Text(
                    destinationText,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                const SizedBox(width: 6),

                // Platform / Peron
                if (platformText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      platformText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // Immediate departure badge (ONLY if 0 <= diffMin <= 1)
                if (isImmediate) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Azonnal',
                      style: TextStyle(
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 5),

            // Line 2: [Route Pill] [Delay / Pontos] [Rolling Stock] [Spacer] [Equipment Badges]
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Route pill badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: _resolveTrainBadgeColor(dep.lineName),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    dep.lineName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Delay / Punctual text
                if (dep.isRealtime && isDelayed) ...[
                  const SizedBox(width: 5),
                  Text(
                    '/ ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '+$delayMin perc késés',
                    style: TextStyle(
                      color: delayColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ] else if (dep.isRealtime) ...[
                  const SizedBox(width: 5),
                  Text(
                    '/ ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  const Text(
                    'Pontos',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],

                // Rolling stock
                if (rollingStock.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      rollingStock,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                const Spacer(),

                // Equipment icons (Image 1 style)
                _buildTrainEquipmentBadges(dep, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Displays the full detailed trip timetable sheet matching Image 2
  void _showTrainTripDetailsSheet(
    BuildContext context,
    ThemeData theme,
    UnifiedDeparture dep,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final delayMin = (dep.delaySeconds / 60).round();
    final isDelayed = dep.delaySeconds > 120;
    final delayColor = dep.delaySeconds > 300
        ? const Color(0xFFDC2626)
        : (dep.delaySeconds > 120 ? const Color(0xFFD97706) : const Color(0xFF16A34A));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          expand: false,
          builder: (sheetCtx, sheetScrollController) {
            return Consumer(
              builder: (consumerCtx, ref, _) {
                final tripScheduleAsync = ref.watch(tripScheduleProvider(dep.tripId));

                return Column(
                  children: [
                    // Grab handle
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header: Train Pill Badge, Destination, Platform, Close
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: _resolveTrainBadgeColor(dep.lineName),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dep.lineName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${dep.headsign} felé',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (dep.platformCode != null && dep.platformCode!.isNotEmpty)
                                  Text(
                                    dep.platformCode!.contains('vágány')
                                        ? dep.platformCode!
                                        : '${dep.platformCode}. vágány',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(modalCtx).pop(),
                          ),
                        ],
                      ),
                    ),

                    // Delay Reason / Status Banner (Image 2 style)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDelayed
                            ? (isDark
                                ? const Color(0xFF3E1C1F).withValues(alpha: 0.5)
                                : const Color(0xFFFFF1F2))
                            : (isDark
                                ? const Color(0xFF1B3B2B).withValues(alpha: 0.5)
                                : const Color(0xFFF0FDF4)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDelayed
                              ? (isDark ? const Color(0xFF8B0000) : const Color(0xFFFECDD3))
                              : (isDark ? const Color(0xFF16A34A) : const Color(0xFFBBF7D0)),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isDelayed ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            size: 20,
                            color: delayColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isDelayed ? 'Késés: +$delayMin perc' : 'Menetrend szerinti közlekedés',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: delayColor,
                                  ),
                                ),
                                Text(
                                  isDelayed
                                      ? 'Késés oka: Menetrendi eltérés / Forgalmi ok'
                                      : 'A vonat menetrend szerint pontosan közlekedik',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 10),

                    // Table Header (Image 2 style: Állomás | Tervezett (Érk. Ind.) | Tény / Becsült (Érk. Ind.))
                    Container(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 4,
                            child: Text(
                              'Állomás',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text('Tervezett', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Text('Érk.', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                                    Text('Ind.', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: const [
                                Text('Tény/Becsült', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Text('Érk.', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                                    Text('Ind.', style: TextStyle(fontSize: 9.5, color: Colors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Stop Times Table List
                    Expanded(
                      child: tripScheduleAsync.when(
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (err, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'A menetrendi részletek jelenleg nem érhetők el.',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                        data: (stops) {
                          if (stops.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Text(
                                  'Nincs részletes megállólista ehhez a járathoz.',
                                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                            );
                          }

                          final now = DateTime.now();

                          return ListView.separated(
                            controller: sheetScrollController,
                            itemCount: stops.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              thickness: 0.5,
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                            ),
                            itemBuilder: (ctx, i) {
                              final stop = stops[i];
                              final schedDep = stop.departureTime;
                              final schedArr = stop.arrivalTime ?? '-';
                              final estDep = stop.predictedDepartureTime ?? schedDep;
                              final estArr = stop.predictedArrivalTime ?? schedArr;

                              // Check if stop is passed (Image 2 green background)
                              final targetTimeStr = estDep.isNotEmpty ? estDep : schedDep;
                              final targetDt = _parseDepartureTime(targetTimeStr, now);
                              final isPassed = targetDt.isBefore(now);
                              final isCurrentStop = _matchesStation(stop.stopName, widget.station.name);

                              Color? rowBg;
                              if (isPassed) {
                                rowBg = isDark
                                    ? const Color(0xFF1B3B2B).withValues(alpha: 0.3)
                                    : const Color(0xFFE8F5E9).withValues(alpha: 0.85);
                              } else if (isCurrentStop) {
                                rowBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.25);
                              }

                              return Container(
                                color: rowBg,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                child: Row(
                                  children: [
                                    // Station name + platform
                                    Expanded(
                                      flex: 4,
                                      child: Row(
                                        children: [
                                          if (isPassed)
                                            const Padding(
                                              padding: EdgeInsets.only(right: 5),
                                              child: Icon(Icons.check_circle, size: 13, color: Color(0xFF16A34A)),
                                            )
                                          else if (isCurrentStop)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 5),
                                              child: Icon(Icons.location_on, size: 13, color: theme.colorScheme.primary),
                                            ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  stop.stopName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isCurrentStop ? FontWeight.w800 : FontWeight.w600,
                                                    color: isCurrentStop ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (stop.platformCode != null && stop.platformCode!.isNotEmpty)
                                                  Text(
                                                    '${stop.platformCode}. vágány',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Tervezett: Arr / Dep
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          Text(schedArr, style: const TextStyle(fontSize: 11)),
                                          Text(schedDep, style: const TextStyle(fontSize: 11)),
                                        ],
                                      ),
                                    ),

                                    // Tény / Becsült: Arr / Dep
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                                        children: [
                                          Text(
                                            estArr,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: stop.delaySeconds > 120 ? delayColor : theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          Text(
                                            estDep,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: stop.delaySeconds > 120 ? delayColor : theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Resolves train badge color according to MÁV categories (IR, IC, RJ, S, Z, G)
  Color _resolveTrainBadgeColor(String lineName) {
    final upper = lineName.toUpperCase();
    if (upper.startsWith('IR') || upper.contains('INTERREGIO')) {
      return const Color(0xFF00838F); // Teal
    } else if (upper.startsWith('IC') || upper.contains('INTERCITY') || upper.startsWith('EC') || upper.startsWith('EN')) {
      return const Color(0xFF6A1B9A); // Purple
    } else if (upper.startsWith('RJ') || upper.startsWith('RJX')) {
      return const Color(0xFFC62828); // Railjet Red
    } else if (upper.startsWith('Z')) {
      return const Color(0xFF1B5E20); // Zónázó Dark Green
    } else if (upper.startsWith('G')) {
      return const Color(0xFF0D47A1); // Gyorsított Dark Blue
    }
    return const Color(0xFF003B7A); // MÁV Blue
  }

  /// Infers commonly operated rolling stock by line (Stadler KISS, FLIRT, IC+, Desiro, Railjet)
  String _inferRollingStock(UnifiedDeparture dep) {
    final line = dep.lineName.toUpperCase();
    if (line.contains('KISS')) return ', Stadler KISS';
    if (line.startsWith('S70') || line.startsWith('Z70') || line.startsWith('S50') || line.startsWith('Z50')) {
      return ', Stadler KISS';
    }
    if (line.startsWith('S10') || line.startsWith('S12') || line.startsWith('S30') || line.startsWith('Z30') || line.startsWith('S40') || line.startsWith('S42')) {
      return ', Stadler FLIRT';
    }
    if (line.startsWith('IC') || line.contains('INTERCITY')) {
      return ', IC+ kocsi';
    }
    if (line.startsWith('IR') || line.contains('INTERREGIO')) {
      return ', Stadler FLIRT';
    }
    if (line.startsWith('RJ')) {
      return ', ÖBB Railjet';
    }
    if (line.startsWith('S25') || line.startsWith('S210') || line.startsWith('S750')) {
      return ', Desiro';
    }
    return '';
  }

  /// Builds equipment badges (Bicycle, 2nd/1st class, Reservation, AC, WiFi) matching Image 1
  Widget _buildTrainEquipmentBadges(UnifiedDeparture dep, ThemeData theme) {
    final line = dep.lineName.toUpperCase();
    final isIC = line.startsWith('IC') || line.contains('INTERCITY') || line.startsWith('EC') || line.startsWith('RJ');
    final isDark = theme.brightness == Brightness.dark;
    final chipBg = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final chipFg = theme.colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bike icon
        Icon(Icons.pedal_bike, size: 13, color: chipFg),
        const SizedBox(width: 4),

        // Class badge [2.] or [1-2]
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            isIC ? '1-2' : '2.',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: chipFg),
          ),
        ),
        const SizedBox(width: 4),

        // Seat reservation badge [R]
        if (isIC) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'R',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: chipFg),
            ),
          ),
          const SizedBox(width: 4),
        ],

        // AC icon
        Icon(Icons.ac_unit, size: 12, color: chipFg),
        const SizedBox(width: 4),

        // WiFi icon
        Icon(Icons.wifi, size: 12, color: chipFg),
      ],
    );
  }

  /// Builds a BKK local transit departure row (bus, tram, trolley, metro, boat)
  Widget _buildLocalDepartureRow(
    BuildContext context,
    ThemeData theme,
    UnifiedDeparture dep,
    RouteBadgeStyle style,
    bool showArrivals,
  ) {
    final now = DateTime.now();
    final displayEstimatedTime = showArrivals
        ? (dep.estimatedArrivalTimeFormatted ?? dep.estimatedTimeFormatted)
        : dep.estimatedTimeFormatted;
    final scheduledTime = showArrivals
        ? (dep.scheduledArrivalTimeFormatted ?? dep.scheduledTimeFormatted)
        : dep.scheduledTimeFormatted;
    final targetTimeStr = displayEstimatedTime.isNotEmpty ? displayEstimatedTime : scheduledTime;
    final targetTime = _parseDepartureTime(targetTimeStr, now);
    final diffMin = targetTime.difference(now).inMinutes;

    final isDelayed = dep.delaySeconds > 120;
    final delayMin = (dep.delaySeconds / 60).round();
    final Color delayColor = dep.delaySeconds > 300
        ? const Color(0xFFDC2626)
        : (dep.delaySeconds > 120 ? const Color(0xFFD97706) : const Color(0xFF16A34A));

    final destinationText = showArrivals
        ? ((dep.originStation != null && dep.originStation!.isNotEmpty)
            ? 'Honnan: ${dep.originStation}'
            : '${dep.lineName} ide érkezik')
        : dep.headsign;

    final platformText = dep.platformCode == null || dep.platformCode!.isEmpty
        ? null
        : dep.platformCode!;

    // Countdown in minutes (GREEN / NOW)
    String countdownStr;
    if (diffMin >= 0 && diffMin <= 1) {
      countdownStr = 'NOW';
    } else if (diffMin > 1 && diffMin < 60) {
      countdownStr = '$diffMin\'';
    } else if (isDelayed) {
      countdownStr = '$displayEstimatedTime (+$delayMin\')';
    } else {
      countdownStr = displayEstimatedTime;
    }

    final schedDt = scheduledTime.isNotEmpty ? _parseDepartureTime(scheduledTime, now) : null;
    final isSchedPassed = schedDt != null && schedDt.isBefore(now);
    final shouldStrikethrough = (isDelayed || isSchedPassed) &&
        scheduledTime.isNotEmpty &&
        scheduledTime != displayEstimatedTime;

    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          // Mode circle icon
          TransitModeCircleIcon(mode: style.mode, size: 24),
          const SizedBox(width: 8),

          // Route Number Badge Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
            decoration: BoxDecoration(
              color: style.bg,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              dep.lineName,
              style: TextStyle(
                color: style.fg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Warning Disruption Badge !
          if (isDelayed) ...[
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD600),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  '!',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Low-floor Wheelchair Icon
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outlineVariant,
                width: 1.2,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.accessible,
                size: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Platform code badge (if available)
          if (platformText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 0.8,
                ),
              ),
              child: Text(
                platformText,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Realtime delay badge (+Xp or Pontos)
          if (dep.isRealtime && isDelayed) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: delayColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+${delayMin}p',
                style: TextStyle(
                  color: delayColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ] else if (dep.isRealtime) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Pontos',
                style: TextStyle(
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],

          // Minutes Countdown (GREEN / NOW)
          Text(
            countdownStr,
            style: const TextStyle(
              color: Color(0xFF00875A), // Authentic transit green countdown
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),

          if (shouldStrikethrough) ...[
            Text(
              scheduledTime,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                decoration: TextDecoration.lineThrough,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              displayEstimatedTime,
              style: TextStyle(
                color: isDelayed ? delayColor : theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ] else ...[
            Text(
              displayEstimatedTime,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(width: 10),

          // Destination / Headsign or Origin
          Expanded(
            child: Text(
              destinationText,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (widget.onDepartureTapped != null) {
      return InkWell(
        onTap: () => widget.onDepartureTapped!(dep),
        borderRadius: BorderRadius.circular(8),
        child: rowContent,
      );
    }
    return rowContent;
  }

  /// Builds the top route badges bar (row of mode icon + route pills)
  Widget _buildServedRoutesBar(ThemeData theme, List<UnifiedDeparture> departures) {
    final routesSet = <String>{};
    if (_transitFilter == TransitFilter.all &&
        widget.station.servedRoutes != null &&
        widget.station.servedRoutes!.isNotEmpty) {
      for (final r in widget.station.servedRoutes!.split(RegExp(r'[,; /]+'))) {
        final trimmed = r.trim();
        if (trimmed.isNotEmpty) routesSet.add(trimmed);
      }
    }
    for (final d in departures) {
      routesSet.add(d.lineName);
    }

    final filteredRoutes = routesSet.where((route) {
      final style = resolveRouteBadgeStyle(
        line: route,
      );
      if (_transitFilter == TransitFilter.train && style.mode != 'train') return false;
      if (_transitFilter == TransitFilter.local && style.mode == 'train') return false;
      return true;
    }).toList();

    if (filteredRoutes.isEmpty) {
      return const SizedBox(height: 6);
    }

    final firstStyle = resolveRouteBadgeStyle(
      line: filteredRoutes.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Mode circle icon
          TransitModeCircleIcon(mode: firstStyle.mode, size: 24),
          const SizedBox(width: 8),

          // Route badges
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: filteredRoutes.take(7).map((route) {
                final style = resolveRouteBadgeStyle(
                  line: route,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: style.bg,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    route,
                    style: TextStyle(
                      color: style.fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  DateTime _parseDepartureTime(String timeStr, DateTime now) {
    try {
      final trimmed = timeStr.trim();
      final iso = DateTime.tryParse(trimmed);
      if (iso != null) return iso;

      final parts = trimmed.split(':');
      if (parts.length >= 2) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        var dt = DateTime(now.year, now.month, now.day, h, m);
        // Only cross over midnight if it's late night (>= 20:00) and the departure is early morning (< 05:00)
        if (now.hour >= 20 && h < 5) {
          dt = dt.add(const Duration(days: 1));
        } else if (now.hour < 5 && h >= 20) {
          dt = dt.subtract(const Duration(days: 1));
        }
        return dt;
      }
    } catch (_) {}
    return now.add(const Duration(minutes: 5));
  }
}

