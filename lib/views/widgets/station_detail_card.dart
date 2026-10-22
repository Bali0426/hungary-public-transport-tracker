import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_generated.dart';
import '../../providers/live_vehicles_provider.dart';
import '../../providers/timetable_provider.dart';

/// Floating Station Detail Pop-up Card matching Image 3 & Image 4 (BKK / OSM Public Transport style).
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

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final isHub = station.isMultimodalHub;
    final hasHubId = station.hubId != null && station.hubId!.isNotEmpty;
    final isDarkMode = ref.watch(mapDarkModeProvider);

    final lookupKey = isHub
        ? (station.hubId ?? station.id)
        : (_queryHub && hasHubId ? station.hubId! : station.id);

    final departuresAsync = ref.watch(stationDepartureBoardProvider(lookupKey));

    final stopCode = station.id.replaceAll('BKK_', '').replaceAll('BKK:', '');

    final cardBg = isDarkMode ? const Color(0xF50F172A) : Colors.white;
    final textDark = isDarkMode ? Colors.white : const Color(0xFF0F172A);
    final textSub = isDarkMode ? Colors.white60 : const Color(0xFF475569);
    final dividerColor = isDarkMode ? Colors.white12 : const Color(0xFFE2E8F0);

    return Container(
      constraints: const BoxConstraints(maxHeight: 520),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF475569) : const Color(0xFF94A3B8),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.6 : 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Header Row: Station Name & Action Icons (Image 3 & 4 style)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    station.name,
                    style: TextStyle(
                      color: textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Platform vs Hub switcher icon (Image 3/4 copy icon)
                if (hasHubId)
                  IconButton(
                    tooltip: _queryHub ? 'Váltás peronra' : 'Váltás teljes csomópontra',
                    icon: Icon(
                      Icons.copy,
                      size: 16,
                      color: _queryHub ? const Color(0xFF009EE3) : textSub,
                    ),
                    onPressed: () => setState(() => _queryHub = !_queryHub),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 6),
                // Clock icon in solid blue circle (Image 3/4 style)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0077D4),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.schedule,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Close button (Image 3/4 X icon)
                IconButton(
                  tooltip: 'Bezárás',
                  icon: Icon(Icons.close, size: 18, color: textDark),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // 2. Subheader Row: Stop Code + Travel From/To Links + Timestamp (Image 3 & 4 style)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Row(
              children: [
                Text(
                  '#$stopCode',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Indulás innen',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Érkezés ide',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const Spacer(),
                Text(
                  'Frissítve 0 perce',
                  style: TextStyle(
                    color: textSub,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // 3. Route Badges Bar (Járatok a megállóban - Image 3 & 4 style)
          _buildServedRoutesBar(departuresAsync.valueOrNull ?? const []),

          Divider(height: 1, thickness: 1, color: dividerColor),

          // 4. Live Departures List (Image 3 & 4 style)
          Expanded(
            child: departuresAsync.when(
              data: (departures) {
                if (departures.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Nincs menetrend szerinti indulás a következő 90 percben.',
                        style: TextStyle(color: textSub, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: departures.length,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.8,
                    color: dividerColor.withValues(alpha: 0.6),
                  ),
                  itemBuilder: (context, idx) {
                    final dep = departures[idx];
                    final isMav = dep.operator == Operator.mav;
                    final line = dep.lineName;
                    final isNightBus = line.startsWith('9');
                    final isTram = dep.routeColor.toLowerCase().contains('ffd') ||
                        dep.routeColor.toLowerCase().contains('ffa') ||
                        line == '4' ||
                        line == '6' ||
                        line == '4-6' ||
                        (station.vehicleType == 'tram');

                    // Colors according to transit mode
                    final Color modeBg = isTram
                        ? const Color(0xFFFFC000) // Tram yellow
                        : (isNightBus
                            ? const Color(0xFF1E232B) // Night bus black
                            : (isMav
                                ? const Color(0xFF0057B8) // MÁV blue
                                : const Color(0xFF009EE3))); // BKK bus blue
                    final Color modeTextColor = isTram ? Colors.black : Colors.white;

                    // Countdown in minutes (with apostrophe from Image 3 & 4)
                    final now = DateTime.now();
                    final depTime = _parseDepartureTime(dep.estimatedTimeFormatted, now);
                    final diffMin = depTime.difference(now).inMinutes;
                    final countdownStr = '${diffMin <= 0 ? 1 : diffMin}\'';

                    final isDelayed = dep.delaySeconds > 120;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Row(
                        children: [
                          // Mode circle icon (Image 3 & 4 style)
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: modeBg,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                isTram
                                    ? Icons.tram
                                    : (isMav ? Icons.train : Icons.directions_bus),
                                size: 14,
                                color: modeTextColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Route Number Badge Pill (Image 3 & 4 style)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: modeBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              line,
                              style: TextStyle(
                                color: modeTextColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Warning Disruption Badge ! (Image 3 style)
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

                          // Low-floor Wheelchair Icon (Image 3 & 4 style)
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDarkMode ? Colors.white38 : const Color(0xFF64748B),
                                width: 1.2,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.accessible,
                                size: 11,
                                color: isDarkMode ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Minutes Countdown (GREEN, Image 3 & 4 style)
                          Text(
                            countdownStr,
                            style: const TextStyle(
                              color: Color(0xFF00875A), // Green countdown
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Destination / Headsign (GREEN, Image 3 & 4 style)
                          Expanded(
                            child: Text(
                              dep.headsign,
                              style: const TextStyle(
                                color: Color(0xFF00875A), // Green headsign from screenshots
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

  /// Builds the top route badges bar (Image 3 & 4: row of mode icon + route pills)
  Widget _buildServedRoutesBar(List<UnifiedDeparture> departures) {
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
    final isTramStop = widget.station.vehicleType == 'tram' ||
        sortedRoutes.any((r) => r == '4' || r == '6' || r == '4-6');

    final Color badgeColor = isTramStop ? const Color(0xFFFFC000) : const Color(0xFF009EE3);
    final Color badgeTextColor = isTramStop ? Colors.black : Colors.white;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Mode circle icon
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isTramStop ? Icons.tram : Icons.directions_bus,
                size: 14,
                color: badgeTextColor,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Route badges
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: sortedRoutes.take(7).map((route) {
                final isNight = route.startsWith('9');
                final bg = isNight ? const Color(0xFF1E232B) : badgeColor;
                final fg = isNight ? Colors.white : badgeTextColor;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    route,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
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
