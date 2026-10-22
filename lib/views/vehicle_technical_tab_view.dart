import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/vehicle_technical_data.dart';
import '../providers/vehicle_detail_provider.dart';

/// Technical detail view shown in the Vehicle Info Card.
/// Automatically renders either the vagonWEB train composition (for MÁV trains)
/// or the HBweb vehicle fleet technical sheet (for BKK vehicles).
class VehicleTechnicalTabView extends ConsumerStatefulWidget {
  final Map<String, dynamic> props;

  const VehicleTechnicalTabView({
    super.key,
    required this.props,
  });

  @override
  ConsumerState<VehicleTechnicalTabView> createState() =>
      _VehicleTechnicalTabViewState();
}

class _VehicleTechnicalTabViewState
    extends ConsumerState<VehicleTechnicalTabView> {
  int _activeCompositionTab = 0; // 0: Tervezett, 1: Tényleges
  final ScrollController _trainScrollController = ScrollController();

  @override
  void dispose() {
    _trainScrollController.dispose();
    super.dispose();
  }

  double _getCarriageCardWidth(CarriageInfo carriage) {
    final meters = carriage.effectiveLengthMeters;
    // vagonWEB méretarány: 1 méter ~ 7.5 px
    // mozdony (~19m) -> ~150px, személykocsi (26.4m) -> ~200px
    return (meters * 7.5).clamp(150.0, 750.0);
  }

  @override
  Widget build(BuildContext context) {
    final op = (widget.props['operator'] as String? ?? 'BKK').toUpperCase();
    final vType = widget.props['vehicle_type'] as String? ?? 'bus';
    final lineName = widget.props['line_name'] as String? ?? '';
    final dest = widget.props['destination'] as String? ?? '';
    final tripId = widget.props['trip_id'] as String? ?? '';
    final tripShortName = widget.props['trip_short_name'] as String?;
    final vehicleId = widget.props['id'] as String? ?? '';

    // Route HÉV (H5..H9) suburban trains to HBweb technical sheet (MXA) instead of MÁV VagonWeb FLIRT
    final isHev = vType == 'suburban_rail' ||
        RegExp(r'^h[5-9]\b', caseSensitive: false).hasMatch(lineName) ||
        RegExp(r'^h[5-9]\b', caseSensitive: false).hasMatch(tripShortName ?? '') ||
        lineName.toLowerCase().contains('hév') ||
        (tripShortName?.toLowerCase().contains('hév') ?? false) ||
        lineName.toLowerCase().contains('hev');

    final isMav = !isHev && (op == 'MAV' || vType == 'train');

    if (isMav) {
      return _buildMavTrainView(lineName, tripId, dest, tripShortName);
    } else {
      return _buildBkkTechnicalView(
        vehicleId,
        lineName,
        isHev ? 'suburban_rail' : vType,
        isHev ? 'BKK' : op,
      );
    }
  }

  // ===========================================================================
  // MÁV VAGONWEB TRAIN COMPOSITION
  // ===========================================================================
  Widget _buildMavTrainView(
    String lineName,
    String tripId,
    String destination, [
    String? tripShortName,
  ]) {
    final theme = Theme.of(context);
    final params = TrainCompositionParams(
      lineName: lineName,
      tripId: tripId,
      destination: destination,
      tripShortName: tripShortName,
    );

    final compositionAsync = ref.watch(trainCompositionProvider(params));

    return compositionAsync.when(
      data: (comp) {
        if (comp == null ||
            (comp.carriages.isEmpty && comp.actualCarriages.isEmpty)) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.train_outlined,
                      size: 44,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ehhez a vonathoz nem található összeállítási információ a vagonWEB adatbázisában.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (comp != null && comp.vagonwebUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _openUrl(comp.vagonwebUrl),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'vagonWEB megnyitása',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.open_in_new,
                                size: 12, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        final activeCarriages = _activeCompositionTab == 0
            ? comp.carriages
            : comp.actualCarriages;

        final totalSeats =
            activeCarriages.fold(0, (sum, c) => sum + c.seatCount);
        final totalBikes =
            activeCarriages.fold(0, (sum, c) => sum + c.bikeSpaces);
        final hasBistro = activeCarriages.any((c) => c.hasBistro);
        final hasWifi = activeCarriages.any((c) => c.hasWifi);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Direction & Service Header
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.train,
                            size: 13, color: theme.colorScheme.onPrimaryContainer),
                        const SizedBox(width: 4),
                        Text(
                          comp.trainNumber.isNotEmpty
                              ? '${comp.category} ${comp.trainNumber}'.trim()
                              : comp.category,
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      comp.trainName.isNotEmpty
                          ? comp.trainName
                          : 'Vonatösszeállítás',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Menetirány',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward,
                          size: 14, color: Color(0xFF22C55E)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Material 3 Two-tab Segmented Button (Tervezett vs Tényleges)
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    const ButtonSegment<int>(
                      value: 0,
                      label: Text(
                        'Tervezett összeállítás',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      icon: Icon(Icons.calendar_month, size: 14),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      label: Text(
                        comp.actualDateLabel != null &&
                                comp.actualDateLabel!.isNotEmpty
                            ? 'Tényleges (${comp.actualDateLabel})'
                            : 'Legutóbbi tényleges',
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      icon: const Icon(Icons.history, size: 14),
                    ),
                  ],
                  selected: {_activeCompositionTab},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _activeCompositionTab = newSelection.first;
                    });
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Summary Badges (calculated for active carriages)
              if (activeCarriages.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildSummaryBadge(
                      Icons.directions_railway,
                      '${activeCarriages.length} egység',
                      Colors.indigoAccent,
                    ),
                    if (totalSeats > 0)
                      _buildSummaryBadge(
                        Icons.event_seat,
                        '$totalSeats ülőhely',
                        Colors.blueGrey,
                      ),
                    if (totalBikes > 0)
                      _buildSummaryBadge(
                        Icons.directions_bike,
                        '$totalBikes kerékpár',
                        Colors.teal,
                      ),
                    if (hasBistro)
                      _buildSummaryBadge(
                        Icons.restaurant,
                        'Utasellátó',
                        Colors.orangeAccent,
                      ),
                    if (hasWifi)
                      _buildSummaryBadge(
                        Icons.wifi,
                        'Wi-Fi',
                        Colors.lightBlueAccent,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Content based on whether active carriages exist
              if (activeCarriages.isEmpty)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline,
                          size: 28, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 8),
                      Text(
                        _activeCompositionTab == 0
                            ? 'Nincs tervezett összeállítási adat a vagonWEB-en.'
                            : 'Nincs jelentett eltérés / valós összeállítási adat a vagonWEB-en.',
                        style:
                            TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else ...[
                // Horizontal Scrollable Train Formation with Linked Carriages (Zero Gaps)
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  child: Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        final delta = pointerSignal.scrollDelta.dy != 0
                            ? pointerSignal.scrollDelta.dy
                            : pointerSignal.scrollDelta.dx;
                        if (delta != 0 && _trainScrollController.hasClients) {
                          final targetOffset =
                              (_trainScrollController.offset + delta).clamp(
                            0.0,
                            _trainScrollController.position.maxScrollExtent,
                          );
                          _trainScrollController.jumpTo(targetOffset);
                        }
                      }
                    },
                    child: Scrollbar(
                      controller: _trainScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: SingleChildScrollView(
                        controller: _trainScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (int idx = 0;
                                  idx < activeCarriages.length;
                                  idx++)
                                _buildCarriageColumn(
                                    activeCarriages[idx], comp),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Source & Web Link
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Forrás: vagonWEB.cz',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                  ),
                  InkWell(
                    onTap: () => _openUrl(comp.vagonwebUrl),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'vagonWEB megnyitása',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_new,
                              size: 10, color: theme.colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              const SizedBox(height: 10),
              Text(
                'Kocsiösszeállítás letöltése a vagonWEB-ről...',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      error: (_, __) => const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Nem sikerült betölteni a vagonWEB adatokat.',
            style: TextStyle(color: Colors.amber, fontSize: 12),
          ),
        ),
      ),
    );
  }

  /// Builds a single carriage column with connected vehicle graphics and persistent under-car specs.
  Widget _buildCarriageColumn(CarriageInfo carriage, TrainComposition comp) {
    final theme = Theme.of(context);
    final colWidth = _getCarriageCardWidth(carriage);

    return SizedBox(
      width: colWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Carriage graphic: ZERO margins, couplers touching flush
          // Mozdonyok és motorvonatok magassága 48px, a vagonok arányosan 33px és a sínre fekszenek fel
          SizedBox(
            height: 48,
            width: colWidth,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: carriage.isWagon ? 33.0 : 48.0,
                width: colWidth,
                child: carriage.imageUrl.isNotEmpty
                    ? Image.network(
                        carriage.imageUrl,
                        fit: BoxFit.fill,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.directions_railway,
                              size: 26,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                        ),
                      )
                    : Center(
                        child: Icon(Icons.directions_railway,
                            size: 26,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                      ),
              ),
            ),
          ),

          // 2. Continuous rail track line under wheels/couplers
          Container(
            height: 3,
            width: colWidth,
            color: const Color(0xFF64748B),
          ),

          const SizedBox(height: 6),

          // 3. Direction plate / Route header (if available)
          if ((carriage.originDestination != null &&
                  carriage.originDestination!.isNotEmpty) ||
              (carriage.routeHeader != null &&
                  carriage.routeHeader!.isNotEmpty) ||
              comp.route.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A8A),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFF3B82F6), width: 0.8),
              ),
              child: Text(
                carriage.originDestination ??
                    carriage.routeHeader ??
                    comp.route,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),

          const SizedBox(height: 2),

          // 4. Coach number square + Series & Operator name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (carriage.coachNumber.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(right: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      carriage.coachNumber,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                  )
                else if (carriage.isLocomotive)
                  const Padding(
                    padding: EdgeInsets.only(right: 3),
                    child:
                        Icon(Icons.bolt, size: 13, color: Colors.amberAccent),
                  ),
                Flexible(
                  child: Text(
                    _formatSeriesWithOperator(carriage),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 3),

          // 5. Class badge + Seat capacity
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _getClassColor(carriage.className)
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _getClassColor(carriage.className),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    _formatClassShort(carriage.className),
                    style: TextStyle(
                      color: _getClassColor(carriage.className),
                      fontWeight: FontWeight.bold,
                      fontSize: 8.5,
                    ),
                  ),
                ),
                if (carriage.seatCapacity != null || carriage.seatCount > 0) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.event_seat,
                      size: 10, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 2),
                  Text(
                    carriage.seatCapacity ?? '${carriage.seatCount}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 3),

          // 6. Amenities micro-pictograms
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 2,
            children: [
              if (carriage.hasWifi)
                Icon(Icons.wifi, size: 10, color: theme.colorScheme.onSurfaceVariant),
              if (carriage.hasAc)
                const Icon(Icons.ac_unit, size: 10, color: Colors.cyanAccent),
              if (carriage.has230v)
                const Icon(Icons.power, size: 10, color: Colors.amberAccent),
              if (carriage.hasUsb)
                const Icon(Icons.usb, size: 10, color: Colors.limeAccent),
              if (carriage.bikeSpaces > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_bike,
                        size: 10, color: Colors.greenAccent),
                    Text(
                      '${carriage.bikeSpaces}',
                      style: const TextStyle(
                          color: Colors.greenAccent, fontSize: 8),
                    ),
                  ],
                ),
              if (carriage.isAccessible)
                const Icon(Icons.accessible,
                    size: 10, color: Colors.lightBlueAccent),
              if (carriage.hasBistro)
                const Icon(Icons.restaurant,
                    size: 10, color: Colors.deepOrangeAccent),
            ],
          ),

          if (carriage.notes.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                carriage.notes,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 7.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatSeriesWithOperator(CarriageInfo c) {
    if (c.operatorCode != null && c.operatorCode!.isNotEmpty) {
      if (c.series.toUpperCase().contains(c.operatorCode!.toUpperCase())) {
        return c.series;
      }
      return '${c.operatorCode} ${c.series}';
    }
    return c.series;
  }

  // ===========================================================================
  // BKK HBWEB TECHNICAL SHEET
  // ===========================================================================
  Widget _buildBkkTechnicalView(
    String vehicleId,
    String lineName,
    String vehicleType,
    String operatorName,
  ) {
    final theme = Theme.of(context);
    final params = BkkTechnicalParams(
      vehicleId: vehicleId,
      lineName: lineName,
      vehicleType: vehicleType,
      operatorName: operatorName,
    );

    final info = ref.watch(bkkTechnicalDataProvider(params));

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Model Name Title
          Text(
            info.modelName,
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${info.manufacturer} (${info.manufacturingPeriod})',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
          ),

          const SizedBox(height: 8),

          // Badges Row
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _buildBadge(info.operator, Colors.cyan),
              _buildBadge(info.depot, Colors.indigoAccent),
              if (info.isLowFloor)
                _buildBadge('${info.lowFloorPercent}% alacsonypadló', Colors.green),
              if (info.hasAirConditioning)
                _buildBadge('Klíma', Colors.lightBlue),
              if (info.hasUsbChargers)
                _buildBadge('USB töltők', Colors.amber),
            ],
          ),

          const SizedBox(height: 12),

          Text(
            'MŰSZAKI ADATOK (HBWEB):',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),

          const SizedBox(height: 6),

          // Technical Parameter Grid
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                _buildParamRow('Pályaszám / Rendszám', info.fleetNumberOrPlate),
                _buildParamRow('Telephely / Kocsiszín', info.depot),
                _buildParamRow(
                  'Befogadóképesség',
                  '${info.totalCapacity} fő (${info.seats} ülő, ${info.standing} álló)',
                ),
                _buildParamRow(
                  'Méretek (H × Sz × M)',
                  '${info.lengthMeters} m × ${info.widthMeters} m × ${info.heightMeters} m',
                ),
                _buildParamRow('Saját tömeg', '${info.curbWeightTonnes} tonna'),
                _buildParamRow('Hajtásrendszer / Motor', info.engineAndPower),
                _buildParamRow('Váltó / Hajtásvezérlés', info.transmission),
                _buildParamRow('Max. sebesség', '${info.maxSpeedKmH} km/h'),
                _buildParamRow('Fedélzeti rendszer', info.futarOBU),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Vehicle Description Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Text(
              info.description,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Source and HBweb link
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Forrás: HBweb.hu járműállomány',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
              ),
              InkWell(
                onTap: () => _openUrl(info.hbwebUrl),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'HBweb adatlap',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 10, color: theme.colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPER WIDGETS
  // ===========================================================================
  Widget _buildSummaryBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildParamRow(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getClassColor(String cls) {
    final lower = cls.toLowerCase();
    if (lower.contains('1+') || lower.contains('prémium')) return const Color(0xFFC084FC);
    if (lower.contains('1')) return const Color(0xFFFBBF24);
    if (lower.contains('étkező') || lower.contains('bisztró')) return const Color(0xFFFB7185);
    if (lower.contains('mozdony')) return const Color(0xFF38BDF8);
    return const Color(0xFF34D399);
  }

  String _formatClassShort(String cls) {
    final lower = cls.toLowerCase();
    if (lower.contains('1+') || lower.contains('prémium')) return '1+';
    if (lower.contains('1')) return '1. oszt.';
    if (lower.contains('étkező') || lower.contains('bisztró')) return 'Bisztró';
    if (lower.contains('mozdony')) return 'Mozdony';
    return '2. oszt.';
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
