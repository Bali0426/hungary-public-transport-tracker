import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/bridge_generated.dart';
import '../providers/timetable_provider.dart';

/// Unified Station Departure Board bottom sheet showing both BKK (metro/tram/bus)
/// and MÁV (rail) departures with colour-coded real-time delay badges:
/// - Green: On time (<= 1 min)
/// - Yellow: 1–5 min delay
/// - Red: > 5 min delay
class StationDetailSheet extends ConsumerWidget {
  final StopNode station;

  const StationDetailSheet({super.key, required this.station});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lookupKey = station.hubId ?? station.id;
    final departuresAsync = ref.watch(stationDepartureBoardProvider(lookupKey));

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    _OperatorBadge(
                      operator: station.operator,
                      isMultimodal: station.isMultimodalHub,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            station.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            station.isMultimodalHub
                                ? 'Multimodal Transfer Hub (BKK + MÁV)'
                                : 'Stop ID: ${station.id}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70),
                      onPressed: () =>
                          ref.invalidate(stationDepartureBoardProvider(lookupKey)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              Expanded(
                child: departuresAsync.when(
                  data: (departures) {
                    if (departures.isEmpty) {
                      return const Center(
                        child: Text(
                          'No upcoming departures in the next 90 minutes.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: departures.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (context, idx) {
                        return _DepartureRow(departure: departures[idx]);
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Failed to load departures: $err',
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OperatorBadge extends StatelessWidget {
  final Operator operator;
  final bool isMultimodal;

  const _OperatorBadge({required this.operator, required this.isMultimodal});

  @override
  Widget build(BuildContext context) {
    final label = isMultimodal
        ? 'BKK+MÁV'
        : (operator == Operator.mav ? 'MÁV' : 'BKK');
    final color = isMultimodal
        ? const Color(0xFF6366F1)
        : (operator == Operator.mav
            ? const Color(0xFF0057B8)
            : const Color(0xFF009EE3));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  final UnifiedDeparture departure;

  const _DepartureRow({required this.departure});

  Color _parseHexColor(String hex, Color fallback) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      final val = int.tryParse('FF$cleaned', radix: 16);
      if (val != null) return Color(val);
    }
    return fallback;
  }

  /// Blueprint Section 5 Phase 4 delay tag colors:
  /// - Green: On time (<= 60s)
  /// - Yellow: 1–5 min delay (61..300s)
  /// - Red: > 5 min delay (> 300s)
  Color _delayColor(int delaySec) {
    if (delaySec <= 60) return const Color(0xFF22C55E);
    if (delaySec <= 300) return const Color(0xFFEAB308);
    return const Color(0xFFEF4444);
  }

  String _delayLabel(int delaySec) {
    final mins = (delaySec / 60).round();
    if (mins <= 0) return 'On time';
    return '+$mins min';
  }

  @override
  Widget build(BuildContext context) {
    final badgeBg = _parseHexColor(
      departure.routeColor,
      departure.operator == Operator.mav
          ? const Color(0xFF0057B8)
          : const Color(0xFF009EE3),
    );
    final badgeFg = _parseHexColor(departure.routeTextColor, Colors.white);
    final delayColor = _delayColor(departure.delaySeconds);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        constraints: const BoxConstraints(minWidth: 54),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          departure.lineName,
          style: TextStyle(
            color: badgeFg,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(
        departure.headsign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Row(
        children: [
          Text(
            departure.operator == Operator.mav ? 'MÁV Rail' : 'BKK Transit',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (departure.platformCode != null &&
              departure.platformCode!.isNotEmpty) ...[
            const Text(' • ', style: TextStyle(color: Colors.white38)),
            Text(
              'Plat. ${departure.platformCode}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            departure.estimatedTimeFormatted,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: delayColor.withValues(alpha: 0.18),
              border: Border.all(color: delayColor, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _delayLabel(departure.delaySeconds),
              style: TextStyle(
                color: delayColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
