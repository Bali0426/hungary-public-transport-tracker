import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bridge/bridge_generated.dart';
import '../../providers/timetable_provider.dart';
import '../../utils/transit_display_utils.dart';
import '../vehicle_technical_tab_view.dart';

/// Top-Right Floating Vehicle Detail Card with Schedule / Timetable and Technical Specs in Material 3.
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
    final theme = Theme.of(context);

    final scheduleAsync = tripId.isNotEmpty
        ? ref.watch(tripScheduleProvider(tripId))
        : null;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TransitModeCircleIcon(mode: vType, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          lineName,
                          style: TextStyle(
                            color: getModeForegroundColor(vType),
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
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
                      borderRadius: BorderRadius.circular(5),
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
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed, size: 13, color: theme.colorScheme.onSecondaryContainer),
                          const SizedBox(width: 4),
                          Text(
                            '$speedKmh km/h',
                            style: TextStyle(
                              color: theme.colorScheme.onSecondaryContainer,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: delayBadgeColor.withValues(alpha: 0.18),
                      border: Border.all(color: delayBadgeColor.withValues(alpha: 0.7), width: 1),
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
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onClose,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Destination & Train Name & Disruption Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tripShortName.isNotEmpty && tripShortName != lineName) ...[
                    Text(
                      tripShortName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    dest.isNotEmpty ? '$dest felé' : 'Menetrend szerinti útvonal',
                    style: TextStyle(
                      color: (tripShortName.isNotEmpty && tripShortName != lineName)
                          ? theme.colorScheme.onSurfaceVariant
                          : theme.colorScheme.onSurface,
                      fontWeight: (tripShortName.isNotEmpty && tripShortName != lineName)
                          ? FontWeight.w500
                          : FontWeight.w700,
                      fontSize: (tripShortName.isNotEmpty && tripShortName != lineName) ? 13 : 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Jármű ID: $vehicleId ${tripId.isNotEmpty ? "• Menet ID: $tripId" : ""}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (delayCause.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              delayCause,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
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

            // Material 3 SegmentedButton Switcher (Menetrend vs Műszaki infó)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    const ButtonSegment<int>(
                      value: 0,
                      icon: Icon(Icons.schedule, size: 16),
                      label: Text('Menetrend', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      icon: Icon(isMav ? Icons.train : Icons.build_circle_outlined, size: 16),
                      label: Text(
                        isMav ? 'vagonWEB szerelvény' : 'HBweb műszaki adatok',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  selected: {_activeTab},
                  onSelectionChanged: (Set<int> newSelection) {
                    setState(() => _activeTab = newSelection.first);
                  },
                ),
              ),
            ),

            const Divider(height: 1),

            // Content Area: Live Dynamic Schedule or Technical Tab
            Expanded(
              child: _activeTab == 1
                  ? VehicleTechnicalTabView(props: widget.props)
                  : _buildDynamicScheduleTab(
                      theme: theme,
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
      ),
    );
  }

  Widget _buildDynamicScheduleTab({
    required ThemeData theme,
    required AsyncValue<List<TripStopSchedule>>? scheduleAsync,
    required Color badgeBg,
    required int delay,
    required Color delayBadgeColor,
    required String delayLabel,
    required String vType,
    required String tripId,
  }) {
    if (scheduleAsync == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Valós idejű GPS adatfolyam (statikus menetrendi adat nélkül)',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return scheduleAsync.when(
      data: (stops) {
        if (stops.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'A menetrendi megállók nem találhatók a helyi adatbázisban.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
            // Live Status Banner (Material 3 surfaceContainerHigh)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
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
                        Text(
                          isAtStation
                              ? 'Állomáson: ${activeStop.stopName}'
                              : 'Következő: ${activeStop.stopName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$arrivalCountdown • $delayLabel',
                          style: TextStyle(
                            color: delay.abs() > 60 ? delayBadgeColor : theme.colorScheme.primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${activeIndex + 1}/${stops.length}',
                      style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Column Header: Érkezés / Indulás (MÁV+ style)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      'Érkezés',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 48,
                    child: Text(
                      'Indulás',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),

            // Timeline List of Stops
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
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontSize: 10,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                    Text(
                                      isDelayed ? _formatTime(estArrDt) : _formatTime(schedArrDt),
                                      style: TextStyle(
                                        color: isDelayed
                                            ? delayColor
                                            : (departedOnTime
                                                ? const Color(0xFF22C55E)
                                                : (isPassed
                                                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                                                    : theme.colorScheme.onSurface)),
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
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              // Stop Dot
                              Positioned(
                                top: 22,
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onSurface,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              // Active Vehicle Badge placed proportionally along the track
                              if (showVehicleHere)
                                Positioned(
                                  top: vehicleTop,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.35),
                                          blurRadius: 3,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: TransitModeCircleIcon(
                                      mode: vType,
                                      size: 18,
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
                                        style: TextStyle(
                                          color: theme.colorScheme.onSurfaceVariant,
                                          fontSize: 10,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                    Text(
                                      isDelayed ? _formatTime(estDepDt) : _formatTime(schedDepDt),
                                      style: TextStyle(
                                        color: isDelayed
                                            ? delayColor
                                            : ((departedOnTime || isFirst)
                                                ? const Color(0xFF22C55E) // Green for on-time departure
                                                : (isPassed
                                                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                                                    : theme.colorScheme.onSurface)),
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
                                    color: isPassed
                                        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                                        : theme.colorScheme.onSurface,
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
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
                                        : theme.colorScheme.outline,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  stop.platformCode!.trim(),
                                  style: TextStyle(
                                    color: isGreenPlatform
                                        ? const Color(0xFF10B981)
                                        : theme.colorScheme.onSurface,
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
      error: (_, __) => Center(
        child: Text(
          'Menetrend betöltése sikertelen',
          style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
        ),
      ),
    );
  }
}
