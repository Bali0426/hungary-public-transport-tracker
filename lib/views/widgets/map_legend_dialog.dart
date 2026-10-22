import 'package:flutter/material.dart';

import '../../utils/transit_display_utils.dart';

/// Material 3 Responsive Map Legend Dialog describing transit lines, delays,
/// and station/stop symbols used across the public transport map.
class MapLegendDialog extends StatelessWidget {
  const MapLegendDialog({super.key});

  /// Static helper to display the dialog from anywhere in the UI.
  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const MapLegendDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: theme.colorScheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.map_outlined,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Jelmagyarázat',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Térképi rétegek, járművek és jelölések',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Bezárás',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 2. Scrollable Content Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Közlekedési és Vasúti Vonalak
                    _buildSectionHeader(
                      context: context,
                      icon: Icons.alt_route,
                      title: 'Közlekedési és Vasúti Vonalak',
                    ),
                    const SizedBox(height: 10),

                    // OpenRailwayMap vasúti vágányhálózat
                    _buildLegendCard(
                      context: context,
                      child: Row(
                        children: [
                          _buildRailwayTrackSwatch(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'OpenRailwayMap vasúti vágányhálózat',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Fekete/sötétszürke sínpár a MÁV teljes hálózatán',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Metróvonalak
                    _buildLegendCard(
                      context: context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Metróvonalak a hivatalos színükkel:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: const [
                              _MetroBadge(label: 'M1 sárga', color: Color(0xFFFFD800), darkText: true),
                              _MetroBadge(label: 'M2 piros', color: Color(0xFFE41F18)),
                              _MetroBadge(label: 'M3 kék', color: Color(0xFF005CA5)),
                              _MetroBadge(label: 'M4 zöld', color: Color(0xFF439539)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // HÉV vonalak
                    _buildLegendCard(
                      context: context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HÉV vonalak:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: const [
                              _MetroBadge(label: 'H5 lila', color: Color(0xFF821380)),
                              _MetroBadge(label: 'H6 barna', color: Color(0xFF86421B)),
                              _MetroBadge(label: 'H7 narancs', color: Color(0xFFEE7203)),
                              _MetroBadge(label: 'H8/H9 bordó', color: Color(0xFFE52320)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Felszíni járművek
                    _buildLegendCard(
                      context: context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Felszíni járművek:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: const [
                              _SurfaceVehicleItem(mode: 'tram', label: 'Villamos (sárga)', color: Color(0xFFFFD800), darkText: true),
                              _SurfaceVehicleItem(mode: 'bus', label: 'Busz (kék)', color: Color(0xFF009EE3)),
                              _SurfaceVehicleItem(mode: 'trolley', label: 'Trolibusz (piros)', color: Color(0xFFE41F18)),
                              _SurfaceVehicleItem(mode: 'night', label: 'Éjszakai járat (fekete)', color: Color(0xFF1A1A1A)),
                              _SurfaceVehicleItem(mode: 'train', label: 'MÁV vonat (kék)', color: Color(0xFF003B7A)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Section 2: Késések és Menetrendi Állapotok
                    _buildSectionHeader(
                      context: context,
                      icon: Icons.access_time_outlined,
                      title: 'Késések és Menetrendi Állapotok',
                    ),
                    const SizedBox(height: 10),

                    _buildLegendCard(
                      context: context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDelayRow(
                            color: const Color(0xFF22C55E),
                            title: 'Zöld: Pontos jármű (0–2 perc késés)',
                            subtitle: 'A jármű menetrend szerint közlekedik.',
                          ),
                          const Divider(height: 14),
                          _buildDelayRow(
                            color: const Color(0xFFEAB308),
                            title: 'Sárga: Kisebb késés (2–5 perc késés)',
                            subtitle: 'Kismértékű menetrendi eltérés.',
                          ),
                          const Divider(height: 14),
                          _buildDelayRow(
                            color: const Color(0xFFEF4444),
                            title: 'Piros: Jelentős késés (5+ perc késés)',
                            subtitle: 'Jelentős menetrendi késés vagy forgalmi zavar.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Menetrendi idő áthúzva + becsült idő
                    _buildLegendCard(
                      context: context,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '14:10',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                    decoration: TextDecoration.lineThrough,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '14:25',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Menetrendi idő áthúzva, fölötte a becsült valós idejű indulási/érkezési idő',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Késés esetén megjelenik a várható indulás és az eltérés mértéke (+15p).',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Késésgyűrű
                    _buildLegendCard(
                      context: context,
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFEF4444),
                                width: 3,
                              ),
                            ),
                            child: Center(
                              child: TransitModeCircleIcon(mode: 'train', size: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HÉV és MÁV vonatoknál valós idejű késésgyűrű a jármű körül',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'A jármű körüli színes kör jelzi a pillanatnyi késési fokozatot a térképen.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Section 3: Megállók és Állomások Jelölései
                    _buildSectionHeader(
                      context: context,
                      icon: Icons.place_outlined,
                      title: 'Megállók és Állomások Jelölései',
                    ),
                    const SizedBox(height: 10),

                    // Megállócsoport
                    _buildLegendCard(
                      context: context,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.hub_outlined,
                                size: 20,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Megállócsoport (burkoló felhő a csomópont peronjai körül)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'A csomóponthoz tartozó összes peront és indulást egybefogó felület.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Egyedi megállópont
                    _buildLegendCard(
                      context: context,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStopMarkerGraphic(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Egyedi megállópont: témafüggő belső mag + ágazati színű gyűrű (több ágazat esetén szegmensek) + haladási irányt mutató fekete iránytüske',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pontos peronhelyzet a járatok ágazati színeivel és az utazási iránnyal.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Vágányszám és peronjelzés
                    _buildLegendCard(
                      context: context,
                      child: Row(
                        children: [
                          Wrap(
                            spacing: 6,
                            children: [
                              _buildPill('#1', theme),
                              _buildPill('A2 peron', theme),
                              _buildPill('4. vágány', theme),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Vágányszám és peronjelzés (#1, A2 peron)',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // 3. Footer Action
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Bezárás'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
    required IconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  Widget _buildLegendCard({
    required BuildContext context,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: child,
    );
  }

  Widget _buildDelayRow({
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRailwayTrackSwatch() {
    return CustomPaint(
      size: const Size(36, 20),
      painter: _RailwayTrackPainter(),
    );
  }

  Widget _buildStopMarkerGraphic() {
    return CustomPaint(
      size: const Size(34, 34),
      painter: _StopMarkerGraphicPainter(),
    );
  }

  Widget _buildPill(String text, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.8,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MetroBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool darkText;

  const _MetroBadge({
    required this.label,
    required this.color,
    this.darkText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: darkText ? const Color(0xFF1A1A1A) : Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SurfaceVehicleItem extends StatelessWidget {
  final String mode;
  final String label;
  final Color color;
  final bool darkText;

  const _SurfaceVehicleItem({
    required this.mode,
    required this.label,
    required this.color,
    this.darkText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TransitModeCircleIcon(mode: mode, size: 20),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: darkText ? const Color(0xFF1A1A1A) : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _RailwayTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = const Color(0xFF222222)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final tiePaint = Paint()
      ..color = const Color(0xFF444444)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Cross ties
    const tieCount = 4;
    for (int i = 0; i <= tieCount; i++) {
      final x = (size.width / tieCount) * i;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), tiePaint);
    }

    // Top and bottom parallel rails
    canvas.drawLine(Offset(0, 4), Offset(size.width, 4), trackPaint);
    canvas.drawLine(Offset(0, size.height - 4), Offset(size.width, size.height - 4), trackPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StopMarkerGraphicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Multi-color sector outer ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    // Segment 1 (Tram yellow)
    ringPaint.color = const Color(0xFFFFD800);
    canvas.drawArc(Rect.fromCircle(center: center, radius: 12), -1.5, 3.14, false, ringPaint);

    // Segment 2 (Bus blue)
    ringPaint.color = const Color(0xFF009EE3);
    canvas.drawArc(Rect.fromCircle(center: center, radius: 12), 1.64, 3.14, false, ringPaint);

    // Inner core
    final corePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 7.5, corePaint);

    final coreBorder = Paint()
      ..color = const Color(0xFF333333)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, 7.5, coreBorder);

    // Direction needle pointer
    final needlePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(center.dx, center.dy - 16)
      ..lineTo(center.dx - 3.5, center.dy - 10)
      ..lineTo(center.dx + 3.5, center.dy - 10)
      ..close();
    canvas.drawPath(path, needlePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
