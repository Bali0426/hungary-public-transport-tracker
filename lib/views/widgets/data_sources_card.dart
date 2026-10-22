import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_config_provider.dart';
import '../../providers/live_vehicles_provider.dart';

/// Comprehensive interactive API Directory and In-App Key Configuration Card.
/// Explains precisely which API provides which map elements, and allows in-app key updates.
class DataSourcesDirectoryCard extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const DataSourcesDirectoryCard({super.key, required this.onClose});

  @override
  ConsumerState<DataSourcesDirectoryCard> createState() =>
      _DataSourcesDirectoryCardState();
}

class _DataSourcesDirectoryCardState
    extends ConsumerState<DataSourcesDirectoryCard> {
  bool _editingBkk = false;
  bool _editingMav = false;

  late final TextEditingController _bkkController;
  late final TextEditingController _mavController;

  @override
  void initState() {
    super.initState();
    final config = ref.read(apiConfigProvider);
    _bkkController = TextEditingController(text: config.bkkApiKey);
    _mavController = TextEditingController(text: config.mavGtfsRtUrl);
  }

  @override
  void dispose() {
    _bkkController.dispose();
    _mavController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(apiConfigProvider);
    final counts = ref.watch(liveVehicleCountsProvider);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF70F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.alt_route, color: Color(0xFF38BDF8), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'API-k és Térképi Elemek Forrásai',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white60),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Content body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. BKK FUTÁR GTFS-RT API
                _buildApiCard(
                  title: 'BKK FUTÁR GTFS-RT API',
                  badgeColor: const Color(0xFF009EE3),
                  statusText: counts.bkk > 0
                      ? 'ÉLŐ CSATLAKOZÁS (${counts.bkk} jármű)'
                      : 'CSATLAKOZÁS...',
                  statusColor: counts.bkk > 0
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEAB308),
                  elements: [
                    'Budapesti valós idejű buszok (${counts.bus} db)',
                    'Budapesti villamosok (${counts.tram} db - Nagykörút, fonódó)',
                    'Trolibuszok (${counts.trolley} db - 70-83-as vonalak)',
                    'Metrók (${counts.metro} db - M1, M2, M3, M4)',
                    'HÉV vonatok (${counts.suburbanRail} db - H5, H6, H7, H8, H9)',
                    'Dunai átkelőhajók (${counts.boat} db)',
                    'Valós idejű késési percek és GTFS-RT menetrendi frissítések',
                  ],
                  configSection: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Aktív kulcs: ${_maskKey(config.bkkApiKey)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: Icon(
                              _editingBkk ? Icons.close : Icons.key,
                              size: 13,
                              color: const Color(0xFF38BDF8),
                            ),
                            label: Text(
                              _editingBkk ? 'Mégse' : 'Kulcs megadása',
                              style: const TextStyle(
                                  color: Color(0xFF38BDF8), fontSize: 11),
                            ),
                            onPressed: () {
                              setState(() {
                                _editingBkk = !_editingBkk;
                                if (_editingBkk) {
                                  _bkkController.text = config.bkkApiKey;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      if (_editingBkk)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _bkkController,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText: 'BKK FUTÁR API kulcs beillesztése...',
                                    hintStyle: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide:
                                          const BorderSide(color: Colors.white24),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF009EE3),
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                onPressed: () {
                                  ref
                                      .read(apiConfigProvider.notifier)
                                      .updateBkkApiKey(_bkkController.text);
                                  setState(() => _editingBkk = false);
                                },
                                child: const Text('Mentés',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 2. MÁV-START & GYSEV GTFS-RT API
                _buildApiCard(
                  title: 'MÁV-START & GYSEV GTFS-RT API',
                  badgeColor: const Color(0xFF0057B8),
                  statusText: counts.mav > 0
                      ? 'ÉLŐ CSATLAKOZÁS (${counts.mav} vonat)'
                      : 'KÉSZENLÉTBEN',
                  statusColor: counts.mav > 0
                      ? const Color(0xFF0284C7)
                      : Colors.white54,
                  elements: [
                    'Országos vasúti személyszállító vonatok (${counts.train} db)',
                    'InterCity, EuroCity, Railjet és gyorsvonat GPS pozíciók',
                    'Elővárosi vonatok (S10, S21, S50, Z50, G60, stb.)',
                    'Valós idejű vonatkésések és vágányszámok a csomópontokon',
                  ],
                  configSection: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              config.mavGtfsRtUrl.isNotEmpty
                                  ? 'Egyéni végpont: ${config.mavGtfsRtUrl}'
                                  : 'Alapértelmezett: MÁV-START EMMA / NAP portál',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: Icon(
                              _editingMav ? Icons.close : Icons.link,
                              size: 13,
                              color: const Color(0xFF38BDF8),
                            ),
                            label: Text(
                              _editingMav ? 'Mégse' : 'URL módosítása',
                              style: const TextStyle(
                                  color: Color(0xFF38BDF8), fontSize: 11),
                            ),
                            onPressed: () {
                              setState(() {
                                _editingMav = !_editingMav;
                                if (_editingMav) {
                                  _mavController.text = config.mavGtfsRtUrl;
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      if (_editingMav)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _mavController,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11),
                                  decoration: InputDecoration(
                                    hintText:
                                        'https://nap.kozut.hu/.../gtfs-rt/feed',
                                    hintStyle: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide:
                                          const BorderSide(color: Colors.white24),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0057B8),
                                  foregroundColor: Colors.white,
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                onPressed: () {
                                  ref
                                      .read(apiConfigProvider.notifier)
                                      .updateMavGtfsRtUrl(_mavController.text);
                                  setState(() => _editingMav = false);
                                },
                                child: const Text('Mentés',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Statikus Helyi SQLite Adatbázis (R-Tree)
                _buildApiCard(
                  title: 'BKK + MÁV Statikus Menetrendi DB',
                  badgeColor: const Color(0xFF818CF8),
                  statusText: 'OFFLINE MOTOR AKTÍV',
                  statusColor: const Color(0xFF22C55E),
                  elements: [
                    '2,900+ Multimodális állomáscsomópont (lila körök)',
                    'Egyedi peronok és menetirányok (autentikus OSM stílusú pöttyök)',
                    'Állomáscsoportok bekerítése (geometriai konvex burok poligonok)',
                    '90 perces állomási indulási jegyzékek (BKK járatok + MÁV vonatok)',
                    'Menetrendi megállósorrendek minden járathoz és vonathoz',
                  ],
                ),

                const SizedBox(height: 12),

                // 4. HBweb és vagonWEB
                _buildApiCard(
                  title: 'HBweb.hu & vagonWEB.cz Rendszerek',
                  badgeColor: const Color(0xFFD97706),
                  statusText: 'INTEGRÁLVA',
                  statusColor: const Color(0xFF10B981),
                  elements: [
                    'HBweb: Budapesti jármű műszaki paraméterek (Combino, CAF, Citaro)',
                    'vagonWEB: MÁV szerelvény- és kocsiösszeállítások (KISS, FLIRT, IC+)',
                    'Kocsiosztály, bisztrókocsi, biciklihely és alacsonypadló adatok',
                  ],
                ),

                const SizedBox(height: 12),

                // 5. OpenStreetMap
                _buildApiCard(
                  title: 'OpenStreetMap Kartográfia',
                  badgeColor: const Color(0xFF475569),
                  statusText: 'TÉRKÉP ALAPRÉTEG',
                  statusColor: Colors.white70,
                  elements: [
                    'Standard és sötétített vektor csempék',
                    'Országos vasútvonalak, utcahálózat és közigazgatási határok',
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _maskKey(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}••••••••${key.substring(key.length - 4)}';
  }

  Widget _buildApiCard({
    required String title,
    required Color badgeColor,
    required String statusText,
    required Color statusColor,
    required List<String> elements,
    Widget? configSection,
  }) {
    return Container(
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
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  border: Border.all(color: statusColor, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Térképen megjelenített elemek:',
            style: TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          ...elements.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(' • ',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Expanded(
                    child: Text(
                      e,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (configSection != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: Colors.white12),
            ),
            configSection,
          ],
        ],
      ),
    );
  }
}
