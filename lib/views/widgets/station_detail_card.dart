import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_generated.dart';
import '../../providers/timetable_provider.dart';
import '../../utils/transit_display_utils.dart';

final _originStationExpando = Expando<String>();
final _arrivalTimeExpando = Expando<String>();

extension UnifiedDepartureArrivalsExtension on UnifiedDeparture {
  String? get estimatedArrivalTimeFormatted => _arrivalTimeExpando[this];
  set estimatedArrivalTimeFormatted(String? value) =>
      _arrivalTimeExpando[this] = value;

  String? get originStation {
    final explicit = _originStationExpando[this];
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return null;
  }
  set originStation(String? value) => _originStationExpando[this] = value;
}

bool _isTerminatingAtCurrentStation(UnifiedDeparture dep, String stationName) {
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
  if (s1 == s2) return true;
  if (s1.contains(s2) || s2.contains(s1)) return true;
  return false;
}

String _simplifyStationName(String name) {
  return name
      .toLowerCase()
      .replaceAll('budapest-', '')
      .replaceAll('budapest ', '')
      .replaceAll(RegExp(r'\b(vasútállomás|pályaudvar|pu\.|vá\.|m\b|h\b)\b'), '')
      .replaceAll(RegExp(r'[^a-záéíóöőúüű0-9]'), '')
      .trim();
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
  if (operator == Operator.mav ||
      vehicleType == 'train' ||
      vehicleType == 'rail' ||
      upper.startsWith('IC') ||
      upper.startsWith('IR') ||
      upper.startsWith('EC') ||
      upper.startsWith('EN') ||
      upper.startsWith('RJ') ||
      upper.startsWith('S1') ||
      upper.startsWith('S2') ||
      upper.startsWith('S3') ||
      upper.startsWith('S5') ||
      upper.startsWith('S6') ||
      upper.startsWith('S7') ||
      upper.startsWith('S8') ||
      upper.startsWith('G1') ||
      upper.startsWith('G4') ||
      upper.startsWith('G6') ||
      upper.startsWith('G8') ||
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

/// Floating Station Detail Pop-up Card matching BKK / OSM Public Transport style in Material 3.
class StationDetailCard extends ConsumerStatefulWidget {
  final StopNode station;
  final VoidCallback onClose;

  const StationDetailCard({
    super.key,
    required this.station,
    required this.onClose,
  });

  @override
  ConsumerState<StationDetailCard> createState() => _StationDetailCardState();
}

class _StationDetailCardState extends ConsumerState<StationDetailCard> {
  bool _queryHub = false;
  bool _showArrivals = false;

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final isInitialHub = station.isMultimodalHub ||
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

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
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
                        onTap: () => setState(() => _showArrivals = false),
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
                        onTap: () => setState(() => _showArrivals = true),
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
                ],
              ),
            ),

            // 3. Route Badges Bar (Járatok a megállóban)
            _buildServedRoutesBar(
              theme,
              (departuresAsync.valueOrNull ?? const []).where((dep) {
                if (_showArrivals) {
                  if (dep.originStation != null &&
                      _matchesStation(dep.originStation!, widget.station.name)) {
                    return false;
                  }
                  return true;
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
                  final displayedDepartures = departures.where((dep) {
                    if (_showArrivals) {
                      if (dep.originStation != null &&
                          _matchesStation(dep.originStation!, widget.station.name)) {
                        return false;
                      }
                      return true;
                    } else {
                      if (_isTerminatingAtCurrentStation(dep, widget.station.name)) {
                        return false;
                      }
                      return true;
                    }
                  }).toList();

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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _showArrivals
                              ? 'Nincs menetrend szerinti érkezés a következő 90 percben.'
                              : 'Nincs menetrend szerinti indulás a következő 90 percben.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: displayedDepartures.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      thickness: 0.8,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    itemBuilder: (context, idx) {
                      final dep = displayedDepartures[idx];
                      final style = resolveRouteBadgeStyle(
                        line: dep.lineName,
                        operator: dep.operator,
                        vehicleType: widget.station.vehicleType,
                        routeColor: dep.routeColor,
                      );

                      // Countdown in minutes (NOW or min')
                      final now = DateTime.now();
                      final displayEstimatedTime = _showArrivals
                          ? (dep.estimatedArrivalTimeFormatted ?? dep.estimatedTimeFormatted)
                          : dep.estimatedTimeFormatted;
                      final depTime = _parseDepartureTime(displayEstimatedTime, now);
                      final diffMin = depTime.difference(now).inMinutes;
                      final countdownStr = diffMin <= 0 ? 'NOW' : '$diffMin\'';

                      final isDelayed = dep.delaySeconds > 120;
                      final destinationText = _showArrivals
                          ? ((dep.originStation != null && dep.originStation!.isNotEmpty)
                              ? 'Honnan: ${dep.originStation}'
                              : '${dep.lineName} ide érkezik')
                          : dep.headsign;

                      final platformText = dep.platformCode == null || dep.platformCode!.isEmpty
                          ? null
                          : ((style.mode == 'train' || dep.operator == Operator.mav)
                              ? (dep.platformCode!.contains('vágány')
                                  ? dep.platformCode!
                                  : '${dep.platformCode}. vágány')
                              : dep.platformCode!);

                      return Padding(
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
                            if (dep.isRealtime && dep.delaySeconds > 120) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '+${(dep.delaySeconds / 60).round()}p',
                                  style: const TextStyle(
                                    color: Color(0xFFEF4444),
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

                            if (isDelayed && dep.scheduledTimeFormatted.isNotEmpty) ...[
                              Text(
                                dep.scheduledTimeFormatted,
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
                                  color: theme.colorScheme.onSurface,
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
                    },
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

  /// Builds the top route badges bar (row of mode icon + route pills)
  Widget _buildServedRoutesBar(ThemeData theme, List<UnifiedDeparture> departures) {
    final routesSet = <String>{};
    if (widget.station.servedRoutes != null && widget.station.servedRoutes!.isNotEmpty) {
      for (final r in widget.station.servedRoutes!.split(RegExp(r'[,; /]+'))) {
        final trimmed = r.trim();
        if (trimmed.isNotEmpty) routesSet.add(trimmed);
      }
    }
    for (final d in departures) {
      routesSet.add(d.lineName);
    }

    if (routesSet.isEmpty) {
      return const SizedBox(height: 6);
    }

    final sortedRoutes = routesSet.toList();
    final firstStyle = resolveRouteBadgeStyle(
      line: sortedRoutes.first,
      vehicleType: widget.station.vehicleType,
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
              children: sortedRoutes.take(7).map((route) {
                final style = resolveRouteBadgeStyle(
                  line: route,
                  vehicleType: widget.station.vehicleType,
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

  DateTime _parseDepartureTime(String hhmm, DateTime now) {
    try {
      final parts = hhmm.split(':');
      if (parts.length >= 2) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        return DateTime(now.year, now.month, now.day, h, m);
      }
    } catch (_) {}
    return now.add(const Duration(minutes: 5));
  }
}
