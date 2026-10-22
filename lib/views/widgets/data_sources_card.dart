import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_config_provider.dart';
import '../../providers/live_vehicles_provider.dart';
import '../../utils/transit_display_utils.dart';

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
    final theme = Theme.of(context);

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: theme.colorScheme.surfaceContainer,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.alt_route, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'API-k és Térképi Elemek Forrásai',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. BKK FUTÁR GTFS-RT API
                _buildApiCard(
                  theme: theme,
                  title: 'BKK FUTÁR GTFS-RT API',
                  badgeColor: getModeBadgeColor('bus'),
                  badgeTextColor: getModeForegroundColor('bus'),
                  modeIcon: 'bus',
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
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
                              size: 14,
                            ),
                            label: Text(
                              _editingBkk ? 'Mégse' : 'Kulcs megadása',
                              style: const TextStyle(fontSize: 11),
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
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'BKK FUTÁR API kulcs beillesztése...',
                                    hintStyle: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                onPressed: () {
                                  ref
                                      .read(apiConfigProvider.notifier)
                                      .updateBkkApiKey(_bkkController.text);
                                  setState(() => _editingBkk = false);
                                },
                                child: const Text('Mentés',
                                    style: TextStyle(fontSize: 11.5)),
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
                  theme: theme,
                  title: 'MÁV-START & GYSEV GTFS-RT API',
                  badgeColor: getModeBadgeColor('train'),
                  badgeTextColor: getModeForegroundColor('train'),
                  modeIcon: 'train',
                  statusText: counts.mav > 0
                      ? 'ÉLŐ CSATLAKOZÁS (${counts.mav} vonat)'
                      : 'KÉSZENLÉTBEN',
                  statusColor: counts.mav > 0
                      ? const Color(0xFF0284C7)
                      : theme.colorScheme.onSurfaceVariant,
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
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
                              _editingMav ? Icons.close : Icons.link,
                              size: 14,
                            ),
                            label: Text(
                              _editingMav ? 'Mégse' : 'URL módosítása',
                              style: const TextStyle(fontSize: 11),
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
                                  style: const TextStyle(fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText:
                                        'https://nap.kozut.hu/.../gtfs-rt/feed',
                                    hintStyle: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                onPressed: () {
                                  ref
                                      .read(apiConfigProvider.notifier)
                                      .updateMavGtfsRtUrl(_mavController.text);
                                  setState(() => _editingMav = false);
                                },
                                child: const Text('Mentés',
                                    style: TextStyle(fontSize: 11.5)),
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
                  theme: theme,
                  title: 'BKK + MÁV Statikus Menetrendi DB',
                  badgeColor: const Color(0xFF6366F1),
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
                  theme: theme,
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
                  theme: theme,
                  title: 'OpenStreetMap Kartográfia',
                  badgeColor: const Color(0xFF475569),
                  statusText: 'TÉRKÉP ALAPRÉTEG',
                  statusColor: theme.colorScheme.onSurfaceVariant,
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
    required ThemeData theme,
    required String title,
    required Color badgeColor,
    Color badgeTextColor = Colors.white,
    String? modeIcon,
    required String statusText,
    required Color statusColor,
    required List<String> elements,
    Widget? configSection,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (modeIcon != null) ...[
                          TransitModeCircleIcon(mode: modeIcon, size: 14),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: badgeTextColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    border: Border.all(color: statusColor.withValues(alpha: 0.6), width: 1),
                    borderRadius: BorderRadius.circular(6),
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
            Text(
              'Térképen megjelenített elemek:',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            ...elements.map(
              (e) {
                String? itemMode;
                final lower = e.toLowerCase();
                if (lower.contains('buszok') || lower.contains('bkk járatok')) {
                  itemMode = 'bus';
                } else if (lower.contains('villamosok')) {
                  itemMode = 'tram';
                } else if (lower.contains('trolibuszok')) {
                  itemMode = 'trolley';
                } else if (lower.contains('metrók')) {
                  itemMode = 'metro';
                } else if (lower.contains('hév')) {
                  itemMode = 'suburban_rail';
                } else if (lower.contains('átkelőhajók') || lower.contains('hajó')) {
                  itemMode = 'boat';
                } else if (lower.contains('vonatok') || lower.contains('vonat')) {
                  itemMode = 'train';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (itemMode != null) ...[
                        TransitModeCircleIcon(mode: itemMode, size: 12),
                        const SizedBox(width: 5),
                      ] else ...[
                        Text(' • ',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 11)),
                      ],
                      Expanded(
                        child: Text(
                          e,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (configSection != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Divider(height: 1),
              ),
              configSection,
            ],
          ],
        ),
      ),
    );
  }
}
