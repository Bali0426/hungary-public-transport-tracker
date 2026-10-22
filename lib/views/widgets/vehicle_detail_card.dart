import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_generated.dart';
import '../../providers/timetable_provider.dart';
import '../../utils/transit_display_utils.dart';
import '../vehicle_technical_tab_view.dart';

/// Top-Right Floating Vehicle Detail Card with Schedule / Timetable and Technical Specs.
class VehicleDetailCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> props;
  final VoidCallback onClose;

  const VehicleDetailCard({
    super.key,
    required this.props,
    required this.onClose,
  });

  @override
  ConsumerState<VehicleDetailCard> createState() => _VehicleDetailCardState();
}

class _VehicleDetailCardState extends ConsumerState<VehicleDetailCard> {
  int _activeTab = 0; // 0 = Menetrend, 1 = Műszaki infó / Kocsiösszeállítás
  final ScrollController _scrollController = ScrollController();
  bool _hasAutoScrolled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  DateTime _parseTime(String timeStr, DateTime now) {
    final parts = timeStr.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    return DateTime(now.year, now.month, now.day, h % 24, m, s);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final lineName = props['line_name'] as String? ?? 'Transit';
    final tripShortName = props['trip_short_name'] as String? ?? props['label'] as String? ?? '';
    final dest = props['destination'] as String? ?? '';
    final op = props['operator'] as String? ?? 'BKK';
    final vType = props['vehicle_type'] as String? ?? 'bus';
    final delay = (props['delay_seconds'] as num? ?? 0).toInt();
    final delayBucket = props['delay_bucket'] as String? ?? 'on_time';
    final delayCause = props['delay_cause'] as String? ?? '';
    final tripId = props['trip_id'] as String? ?? '';
    final vehicleId = props['id'] as String? ?? '';
    final speedKmh = (props['speed_kmh'] as num?)?.toInt() ??
        (((props['speed_mps'] as num?) ?? 0) * 3.6).round();

    final mins = (delay / 60).round();
    final delayLabel = mins <= 0 ? 'Pontos' : '+$mins perc késés';
    final Color delayBadgeColor = switch (delayBucket) {
      'minor_delay' => const Color(0xFFEAB308),
      'major_delay' => const Color(0xFFEF4444),
      _ => const Color(0xFF22C55E),
    };

    final Color badgeBg = getModeBadgeColor(vType);
    final isMav = op == 'MAV' || vType == 'train';

    final scheduleAsync = tripId.isNotEmpty
        ? ref.watch(tripScheduleProvider(tripId))
        : null;

    return Container(
      constraints: const BoxConstraints(maxHeight: 580),
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
                      Icon(getModeIconData(vType), size: 16, color: Colors.white),
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
                const SizedBox(width: 8),
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
                if (speedKmh > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4), width: 1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.speed, size: 12, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Text(
                          '$speedKmh km/h',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

          // Destination & Train Name & Disruption Banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tripShortName.isNotEmpty && tripShortName != lineName) ...[
                  Text(
                    tripShortName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  dest.isNotEmpty ? '$dest felé' : 'Menetrend szerinti útvonal',
                  style: TextStyle(
                    color: (tripShortName.isNotEmpty && tripShortName != lineName) ? Colors.white70 : Colors.white,
                    fontWeight: (tripShortName.isNotEmpty && tripShortName != lineName) ? FontWeight.w500 : FontWeight.w700,
                    fontSize: (tripShortName.isNotEmpty && tripShortName != lineName) ? 13 : 15,
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
                if (delayCause.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFFCA5A5)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            delayCause,
                            style: const TextStyle(
                              color: Color(0xFFFECACA),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

          // Content Area: Live Dynamic Schedule or Technical Tab
          Expanded(
            child: _activeTab == 1
                ? VehicleTechnicalTabView(props: widget.props)
                : _buildDynamicScheduleTab(
                    scheduleAsync: scheduleAsync,
                    badgeBg: badgeBg,
                    delay: delay,
                    delayBadgeColor: delayBadgeColor,
                    delayLabel: delayLabel,
                    vType: vType,
                    tripId: tripId,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicScheduleTab({
    required AsyncValue<List<TripStopSchedule>>? scheduleAsync,
    required Color badgeBg,
    required int delay,
    required Color delayBadgeColor,
    required String delayLabel,
    required String vType,
    required String tripId,
  }) {
    if (scheduleAsync == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Valós idejű GPS adatfolyam (statikus menetrendi adat nélkül)',
            style: TextStyle(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return scheduleAsync.when(
      data: (stops) {
        if (stops.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'A menetrendi megállók nem találhatók a helyi adatbázisban.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final now = DateTime.now();

        // 1. Calculate active stop index and progress along the route from GPS coordinates
        final vLat = (widget.props['lat'] as num?)?.toDouble();
        final vLon = (widget.props['lon'] as num?)?.toDouble();

        int activeIndex = -1;
        String? segmentLabel;
        bool isAtStation = false;
        int activeStationIdx = -1;
        int activeFromIdx = -1;
        int activeToIdx = -1;
        double segmentProgress = 0.0; // 0.0 at fromIdx, 1.0 at toIdx

        if (vLat != null && vLon != null && stops.any((s) => s.lat != null && s.lon != null)) {
          double minDistance = double.infinity;
          int closestIdx = 0;
          for (int i = 0; i < stops.length; i++) {
            final s = stops[i];
            if (s.lat != null && s.lon != null) {
              final dLat = s.lat! - vLat;
              final dLon = (s.lon! - vLon) * math.cos(vLat * math.pi / 180.0);
              final distSq = dLat * dLat + dLon * dLon;
              if (distSq < minDistance) {
                minDistance = distSq;
                closestIdx = i;
              }
            }
          }

          final distMeters = math.sqrt(minDistance) * 111139.0;
          if (distMeters <= 350) {
            isAtStation = true;
            activeStationIdx = closestIdx;
            activeIndex = closestIdx;
            segmentLabel = 'Állomáson: ${stops[closestIdx].stopName}';
          } else {
            // Check if vehicle is traveling towards closestIdx + 1
            if (closestIdx < stops.length - 1) {
              final curr = stops[closestIdx];
              final next = stops[closestIdx + 1];
              if (curr.lat != null && curr.lon != null && next.lat != null && next.lon != null) {
                final segDx = (next.lon! - curr.lon!) * math.cos(vLat * math.pi / 180.0);
                final segDy = next.lat! - curr.lat!;
                final vDx = (vLon - curr.lon!) * math.cos(vLat * math.pi / 180.0);
                final vDy = vLat - curr.lat!;
                final segLenSq = segDx * segDx + segDy * segDy;
                final proj = segLenSq > 0 ? (vDx * segDx + vDy * segDy) / segLenSq : 0.0;
                if (proj > 0.02 && proj < 1.05) {
                  isAtStation = false;
                  activeFromIdx = closestIdx;
                  activeToIdx = closestIdx + 1;
                  segmentProgress = proj.clamp(0.08, 0.92);
                  activeIndex = closestIdx + 1;
                  segmentLabel = '${curr.stopName} és ${next.stopName} között';
                }
              }
            }

            // Check if vehicle was between closestIdx - 1 and closestIdx
            if (activeIndex == -1 && closestIdx > 0) {
              final prev = stops[closestIdx - 1];
              final curr = stops[closestIdx];
              if (prev.lat != null && prev.lon != null && curr.lat != null && curr.lon != null) {
                final pDx = (curr.lon! - prev.lon!) * math.cos(vLat * math.pi / 180.0);
                final pDy = curr.lat! - prev.lat!;
                final pvDx = (vLon - prev.lon!) * math.cos(vLat * math.pi / 180.0);
                final pvDy = vLat - prev.lat!;
                final pLenSq = pDx * pDx + pDy * pDy;
                final pProj = pLenSq > 0 ? (pvDx * pDx + pvDy * pDy) / pLenSq : 0.0;
                if (pProj > -0.05 && pProj < 0.98) {
                  isAtStation = false;
                  activeFromIdx = closestIdx - 1;
                  activeToIdx = closestIdx;
                  segmentProgress = pProj.clamp(0.08, 0.92);
                  activeIndex = closestIdx;
                  segmentLabel = '${prev.stopName} és ${curr.stopName} között';
                }
              }
            }

            if (activeIndex == -1) {
              isAtStation = true;
              activeStationIdx = closestIdx;
              activeIndex = closestIdx;
            }
          }
        }

        // Fallback to timetable comparison only if GPS coordinates were not available
        if (activeIndex == -1) {
          for (int i = 0; i < stops.length; i++) {
            final schedDt = _parseTime(stops[i].departureTime, now);
            final estDt = schedDt.add(Duration(seconds: delay));
            if (estDt.isAfter(now.subtract(const Duration(seconds: 45)))) {
              activeIndex = i;
              isAtStation = true;
              activeStationIdx = i;
              break;
            }
          }
        }
        if (activeIndex == -1) {
          activeIndex = stops.length - 1; // At destination terminal
          isAtStation = true;
          activeStationIdx = stops.length - 1;
        }

        // Auto-scroll once so the active stop is visible
        if (!_hasAutoScrolled && activeIndex > 1) {
          _hasAutoScrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final target = ((activeIndex - 1) * 50.0).clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              );
              _scrollController.animateTo(
                target,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }

        final activeStop = stops[activeIndex];
        final activeSchedDt = _parseTime(activeStop.departureTime, now);
        final activeEstDt = activeSchedDt.add(Duration(seconds: delay));
        final minutesUntil = activeEstDt.difference(now).inMinutes;
        final arrivalCountdown = segmentLabel ??
            (minutesUntil <= 0 ? 'Azonnal érkezik' : 'kb. $minutesUntil perc múlva');

        return Column(
          children: [
            // Live Status Banner (BudapestGO / MÁV+ style)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: delay.abs() > 60 ? delayBadgeColor : const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isAtStation
                                  ? 'Állomáson: ${activeStop.stopName}'
                                  : 'Következő: ${activeStop.stopName}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        Text(
                          '$arrivalCountdown • $delayLabel',
                          style: TextStyle(
                            color: delay.abs() > 60 ? delayBadgeColor : const Color(0xFF38BDF8),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${activeIndex + 1}/${stops.length}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),

            // Column Header: Érkezés / Indulás (MÁV+ style)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: const [
                  SizedBox(
                    width: 44,
                    child: Text(
                      'Érkezés',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  SizedBox(width: 20),
                  SizedBox(
                    width: 48,
                    child: Text(
                      'Indulás',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),

            // Timeline List of Stops (MÁV+ style)
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: stops.length,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                itemBuilder: (context, idx) {
                  final stop = stops[idx];
                  final isPassed = idx < activeIndex;
                  final isFirst = idx == 0;
                  final isLast = idx == stops.length - 1;

                  final stopDelay = stop.delaySeconds != 0 ? stop.delaySeconds : delay;
                  final isDelayed = stopDelay.abs() >= 60;
                  final departedOnTime = isPassed && !isDelayed;
                  const delayColor = Color(0xFFE05244); // Exact reddish-orange from MÁV+ app

                  final schedDepDt = _parseTime(stop.departureTime, now);
                  final estDepDt = (stop.predictedDepartureTime != null && stop.predictedDepartureTime!.isNotEmpty)
                      ? _parseTime(stop.predictedDepartureTime!, now)
                      : schedDepDt.add(Duration(seconds: stopDelay));

                  final schedArrDt = (stop.arrivalTime != null && stop.arrivalTime!.isNotEmpty)
                      ? _parseTime(stop.arrivalTime!, now)
                      : schedDepDt.subtract(const Duration(minutes: 1));
                  final estArrDt = (stop.predictedArrivalTime != null && stop.predictedArrivalTime!.isNotEmpty)
                      ? _parseTime(stop.predictedArrivalTime!, now)
                      : schedArrDt.add(Duration(seconds: stopDelay));

                  // Determine vehicle icon position along the track
                  bool showVehicleHere = false;
                  double vehicleTop = 16.0;

                  if (isAtStation && activeStationIdx == idx) {
                    showVehicleHere = true;
                    vehicleTop = 16.0; // Centered on dot: 25 - 9
                  } else if (!isAtStation) {
                    if (activeFromIdx == idx && segmentProgress <= 0.5) {
                      showVehicleHere = true;
                      vehicleTop = 25.0 + segmentProgress * 50.0 - 9.0;
                    } else if (activeToIdx == idx && segmentProgress > 0.5) {
                      showVehicleHere = true;
                      vehicleTop = 25.0 - (1.0 - segmentProgress) * 50.0 - 9.0;
                    }
                  }

                  // Platform code (only show if present, no fake numbers)
                  final hasPlatform = stop.platformCode != null && stop.platformCode!.trim().isNotEmpty;
                  final isGreenPlatform = departedOnTime || !isDelayed;

                  return SizedBox(
                    height: 50,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 1. Érkezés Column
                        SizedBox(
                          width: 44,
                          child: isFirst
                              ? const SizedBox()
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (isDelayed)
                                      Text(
                                        _formatTime(schedArrDt),
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 10,
                                          decoration: TextDecoration.lineThrough,
                                          decorationColor: Colors.white60,
                                        ),
                                      ),
                                    Text(
                                      isDelayed ? _formatTime(estArrDt) : _formatTime(schedArrDt),
                                      style: TextStyle(
                                        color: isDelayed
                                            ? delayColor
                                            : (departedOnTime
                                                ? const Color(0xFF22C55E)
                                                : (isPassed ? Colors.white38 : Colors.white)),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        // 2. Vertical Line Track with Stop Dot & Proportional Vehicle Badge
                        SizedBox(
                          width: 20,
                          height: 50,
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Positioned(
                                top: isFirst ? 25 : 0,
                                bottom: isLast ? 25 : 0,
                                width: 2,
                                child: Container(
                                  color: const Color(0xFF0077D4),
                                ),
                              ),
                              // Stop Dot
                              Positioned(
                                top: 22,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              // Active Vehicle Badge placed proportionally along the track
                              if (showVehicleHere)
                                Positioned(
                                  top: vehicleTop,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0057B8),
                                      borderRadius: BorderRadius.circular(3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Icon(
                                        getModeIconData(vType),
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // 3. Indulás Column
                        SizedBox(
                          width: 48,
                          child: isLast
                              ? const SizedBox()
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isDelayed)
                                      Text(
                                        _formatTime(schedDepDt),
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 10,
                                          decoration: TextDecoration.lineThrough,
                                          decorationColor: Colors.white60,
                                        ),
                                      ),
                                    Text(
                                      isDelayed ? _formatTime(estDepDt) : _formatTime(schedDepDt),
                                      style: TextStyle(
                                        color: isDelayed
                                            ? delayColor
                                            : ((departedOnTime || isFirst)
                                                ? const Color(0xFF22C55E) // Green for on-time departure
                                                : (isPassed ? Colors.white38 : Colors.white)),
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        const SizedBox(width: 4),

                        // 4. Station Name & connecting line
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  stop.stopName,
                                  style: TextStyle(
                                    color: isPassed ? Colors.white54 : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: const Color(0xFF374151),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),

                        // 5. Platform / Vágány Box on Far Right (Only real platforms, else aligned space)
                        hasPlatform
                            ? Container(
                                width: 28,
                                height: 22,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isGreenPlatform
                                        ? const Color(0xFF10B981) // Green border from MÁV+ app
                                        : Colors.white70,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  stop.platformCode!.trim(),
                                  style: TextStyle(
                                    color: isGreenPlatform
                                        ? const Color(0xFF10B981)
                                        : Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11.5,
                                  ),
                                ),
                              )
                            : const SizedBox(width: 28, height: 22),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
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
    );
  }
}
