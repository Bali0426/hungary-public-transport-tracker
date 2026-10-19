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
  int _selectedCarriageIdx = 0;

  @override
  Widget build(BuildContext context) {
    final op = (widget.props['operator'] as String? ?? 'BKK').toUpperCase();
    final vType = widget.props['vehicle_type'] as String? ?? 'bus';
    final lineName = widget.props['line_name'] as String? ?? '';
    final dest = widget.props['destination'] as String? ?? '';
    final tripId = widget.props['trip_id'] as String? ?? '';
    final vehicleId = widget.props['id'] as String? ?? '';

    final isMav = op == 'MAV' || vType == 'train';

    if (isMav) {
      return _buildMavTrainView(lineName, tripId, dest);
    } else {
      return _buildBkkTechnicalView(vehicleId, lineName, vType, op);
    }
  }

  // ===========================================================================
  // MÁV VAGONWEB TRAIN COMPOSITION
  // ===========================================================================
  Widget _buildMavTrainView(String lineName, String tripId, String destination) {
    final params = TrainCompositionParams(
      lineName: lineName,
      tripId: tripId,
      destination: destination,
    );

    final compositionAsync = ref.watch(trainCompositionProvider(params));

    return compositionAsync.when(
      data: (comp) {
        if (comp == null || comp.carriages.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'A kocsiösszeállítás nem érhető el ehhez a járathoz a vagonWEB-en.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final carriages = comp.carriages;
        final selectedCarriage = (_selectedCarriageIdx < carriages.length)
            ? carriages[_selectedCarriageIdx]
            : carriages.first;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Direction & Service Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0057B8).withValues(alpha: 0.3),
                      border: Border.all(color: const Color(0xFF0057B8)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.train, size: 13, color: Colors.cyanAccent),
                        const SizedBox(width: 4),
                        Text(
                          '${comp.category} ${comp.trainNumber}',
                          style: const TextStyle(
                            color: Colors.cyanAccent,
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
                      comp.trainName.isNotEmpty ? comp.trainName : 'Vonatösszeállítás',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Menetirány',
                        style: TextStyle(color: Colors.white60, fontSize: 10),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 14, color: Colors.greenAccent),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Summary Badges
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildSummaryBadge(
                    Icons.directions_railway,
                    '${comp.carriages.length} egység',
                    Colors.indigoAccent,
                  ),
                  if (comp.totalSeats > 0)
                    _buildSummaryBadge(
                      Icons.event_seat,
                      '${comp.totalSeats} ülőhely',
                      Colors.blueGrey,
                    ),
                  if (comp.totalBikes > 0)
                    _buildSummaryBadge(
                      Icons.directions_bike,
                      '${comp.totalBikes} kerékpár',
                      Colors.teal,
                    ),
                  if (comp.hasBistro)
                    _buildSummaryBadge(
                      Icons.restaurant,
                      'Utasellátó',
                      Colors.orangeAccent,
                    ),
                  if (comp.hasWifi)
                    _buildSummaryBadge(
                      Icons.wifi,
                      'Wi-Fi',
                      Colors.lightBlueAccent,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              const Text(
                'SZERELVÉNY ÖSSZEÁLLÍTÁS (VAGONWEB):',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),

              const SizedBox(height: 6),

              // Horizontal Scrollable Train Formation with Carriage Images
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B132B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  itemCount: carriages.length,
                  itemBuilder: (context, idx) {
                    final carriage = carriages[idx];
                    final isSelected = idx == _selectedCarriageIdx;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedCarriageIdx = idx),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        width: carriage.isLocomotive ? 110 : 130,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.cyanAccent : Colors.white12,
                            width: isSelected ? 1.8 : 1.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.cyanAccent.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Top Row: Coach Number & Class
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (carriage.coachNumber.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${carriage.coachNumber}.',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  )
                                else
                                  const Icon(Icons.flash_on,
                                      size: 13, color: Colors.amber),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getClassColor(carriage.className)
                                        .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _formatClassShort(carriage.className),
                                    style: TextStyle(
                                      color: _getClassColor(carriage.className),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const Spacer(),

                            // Carriage Illustration Image from vagonWEB
                            if (carriage.imageUrl.isNotEmpty)
                              SizedBox(
                                height: 38,
                                child: Image.network(
                                  carriage.imageUrl,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.directions_railway,
                                    size: 32,
                                    color: Colors.white38,
                                  ),
                                ),
                              )
                            else
                              const Icon(
                                Icons.directions_railway,
                                size: 32,
                                color: Colors.white38,
                              ),

                            const Spacer(),

                            // Series Name
                            Text(
                              carriage.series,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),

                            // Micro Pictograms Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (carriage.hasWifi)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 1.5),
                                    child: Icon(Icons.wifi, size: 10, color: Colors.white70),
                                  ),
                                if (carriage.hasAc)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 1.5),
                                    child: Icon(Icons.ac_unit, size: 10, color: Colors.cyanAccent),
                                  ),
                                if (carriage.has230v)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 1.5),
                                    child: Icon(Icons.power, size: 10, color: Colors.amberAccent),
                                  ),
                                if (carriage.bikeSpaces > 0)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 1.5),
                                    child: Icon(Icons.directions_bike, size: 10, color: Colors.greenAccent),
                                  ),
                                if (carriage.isAccessible)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 1.5),
                                    child: Icon(Icons.accessible, size: 10, color: Colors.lightBlueAccent),
                                  ),
                                if (carriage.hasBistro)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 1.5),
                                    child: Icon(Icons.restaurant, size: 10, color: Colors.deepOrangeAccent),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Selected Carriage Detailed Inspection Sheet
              Container(
                padding: const EdgeInsets.all(12),
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
                        if (selectedCarriage.coachNumber.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${selectedCarriage.coachNumber}. kocsi',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedCarriage.typeName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'Típus / Sorozat: ${selectedCarriage.series} • Osztály: ${selectedCarriage.className}',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),

                    if (selectedCarriage.notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        selectedCarriage.notes,
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 10),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Amenities Badges
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (selectedCarriage.seatCount > 0)
                          _buildDetailChip(
                            Icons.event_seat,
                            '${selectedCarriage.seatCount} ülőhely',
                            Colors.white,
                          ),
                        if (selectedCarriage.bikeSpaces > 0)
                          _buildDetailChip(
                            Icons.directions_bike,
                            '${selectedCarriage.bikeSpaces} kerékpárhely',
                            Colors.greenAccent,
                          ),
                        if (selectedCarriage.hasWifi)
                          _buildDetailChip(Icons.wifi, 'Wi-Fi internet', Colors.cyanAccent),
                        if (selectedCarriage.hasAc)
                          _buildDetailChip(Icons.ac_unit, 'Klímatizált', Colors.lightBlueAccent),
                        if (selectedCarriage.has230v)
                          _buildDetailChip(Icons.power, '230 V csatlakozó', Colors.amberAccent),
                        if (selectedCarriage.hasUsb)
                          _buildDetailChip(Icons.usb, '5 V USB töltő', Colors.limeAccent),
                        if (selectedCarriage.isAccessible)
                          _buildDetailChip(
                              Icons.accessible, 'Kerekesszékes lift', Colors.cyanAccent),
                        if (selectedCarriage.hasBistro)
                          _buildDetailChip(
                              Icons.restaurant, 'Utasellátó étkező/büfé', Colors.deepOrangeAccent),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Source & Web Link
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Forrás: vagonWEB.cz (${2026})',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                  InkWell(
                    onTap: () => _openUrl(comp.vagonwebUrl),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'vagonWEB megnyitása',
                            style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.open_in_new, size: 10, color: Colors.lightBlueAccent),
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
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
              SizedBox(height: 10),
              Text(
                'Kocsiösszeállítás letöltése a vagonWEB-ről...',
                style: TextStyle(color: Colors.white70, fontSize: 11),
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

  // ===========================================================================
  // BKK HBWEB TECHNICAL SHEET
  // ===========================================================================
  Widget _buildBkkTechnicalView(
    String vehicleId,
    String lineName,
    String vehicleType,
    String operatorName,
  ) {
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
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${info.manufacturer} (${info.manufacturingPeriod})',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
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

          const Text(
            'MŰSZAKI ADATOK (HBWEB):',
            style: TextStyle(
              color: Colors.white60,
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
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
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
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              info.description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Source and HBweb link
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Forrás: HBweb.hu járműállomány',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              InkWell(
                onTap: () => _openUrl(info.hbwebUrl),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'HBweb adatlap',
                        style: TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.open_in_new, size: 10, color: Colors.lightBlueAccent),
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

  Widget _buildDetailChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
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
