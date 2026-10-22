import 'package:flutter/material.dart';

/// Returns standard Material icon for a transit mode.
IconData getModeIconData(String mode) {
  final m = mode.toLowerCase();
  return switch (m) {
    'tram' => Icons.tram,
    'metro' || 'subway' => Icons.subway,
    'trolley' || 'trolleybus' => Icons.electric_bolt,
    'train' || 'rail' => Icons.train,
    'suburban_rail' || 'hev' => Icons.directions_railway,
    'boat' || 'ferry' => Icons.directions_boat,
    _ => Icons.directions_bus,
  };
}

/// Returns authentic BKK / MÁV branding color for a transit mode (Chapter 3).
Color getModeBadgeColor(String mode) {
  final m = mode.toLowerCase();
  return switch (m) {
    'metro' || 'subway' => const Color(0xFF6D6E71), // BKK Metro grey
    'suburban_rail' || 'hev' => const Color(0xFF007A33), // BKK HÉV dark green (#007A33)
    'boat' || 'ferry' => const Color(0xFFE52082), // BKK Boat magenta/pink (#E52082)
    'tram' => const Color(0xFFFFD800), // BKK Tram vibrant yellow (#FFD800)
    'trolley' || 'trolleybus' => const Color(0xFFE41F18), // BKK Trolley red (#E41F18)
    'train' || 'rail' => const Color(0xFF003B7A), // MÁV Train royal navy blue (#003B7A)
    'night' || 'night_bus' => const Color(0xFF1A1A1A), // BKK Night bus (#1A1A1A)
    'bubi' => const Color(0xFF84BD00), // MOL Bubi apple green (#84BD00)
    _ => const Color(0xFF009EE3), // BKK Bus sky blue (#009EE3)
  };
}

/// Official BKK and BudapestGO line-specific color resolver (Chapter 3).
/// Resolves colors for Metro (M1-M4), HÉV (H5-H9), Night lines (900s),
/// Cogwheel (60), Boat (D11, D12), Airport Express (100E/200E) and modes.
Color getLineOrRouteColor(String lineName, {String? mode}) {
  final clean = lineName.toUpperCase().replaceAll(' ', '').trim();

  // 1. Metro lines (Chapter 3.1)
  if (clean == 'M1') return const Color(0xFFFFD800);
  if (clean == 'M2') return const Color(0xFFE41F18);
  if (clean == 'M3') return const Color(0xFF005CA5);
  if (clean == 'M4') return const Color(0xFF439539);

  // 2. HÉV lines (Chapter 3.2)
  if (clean == 'H5') return const Color(0xFF821380);
  if (clean == 'H6') return const Color(0xFF86421B);
  if (clean == 'H7') return const Color(0xFFEE7203);
  if (clean == 'H8' || clean == 'H9') return const Color(0xFFE52320);
  if (clean.startsWith('H') && clean.length <= 3) return const Color(0xFF007A33);

  // 3. Fogaskerekű (60)
  if (clean == '60') return const Color(0xFF821380);

  // 4. Night buses (900-999)
  if (RegExp(r'^9\d\d[A-Z]?$').hasMatch(clean)) return const Color(0xFF1A1A1A);

  // 5. Airport express
  if (clean == '100E' || clean == '200E') return const Color(0xFF007BBF);

  // 6. Boat lines
  if (clean.startsWith('D') && clean.length <= 4) return const Color(0xFFE52082);

  // 7. Fallback to mode color if specified
  if (mode != null && mode.isNotEmpty) {
    return getModeBadgeColor(mode);
  }

  // 8. Default fallback based on general transit conventions
  return const Color(0xFF009EE3);
}

/// Returns appropriate text/icon contrast color for a line/route badge.
Color getRouteForegroundColor(Color backgroundColor) {
  return backgroundColor.computeLuminance() > 0.55
      ? const Color(0xFF1E1E1E)
      : Colors.white;
}

/// Returns high-contrast text and icon color for transit mode badges and pills.
/// Yellow tram (#FFD800) gets dark (#1E1E1E), all others get white.
Color getModeForegroundColor(String mode) {
  final m = mode.toLowerCase();
  if (m == 'tram') {
    return const Color(0xFF1E1E1E);
  }
  return Colors.white;
}

/// Returns human-readable Hungarian display name for a transit mode.
String getTransitModeDisplayName(String mode) {
  final m = mode.toLowerCase();
  return switch (m) {
    'tram' => 'Villamos',
    'metro' || 'subway' => 'Metró',
    'trolley' || 'trolleybus' => 'Trolibusz',
    'train' || 'rail' => 'Vonat',
    'suburban_rail' || 'hev' => 'HÉV',
    'boat' || 'ferry' => 'Hajó',
    _ => 'Busz',
  };
}

/// Returns authentic delay color based on seconds or delay bucket.
Color getDelayColor(int delaySeconds) {
  final mins = (delaySeconds / 60).round();
  if (mins <= 1) return const Color(0xFF22C55E); // On time / green
  if (mins <= 5) return const Color(0xFFEAB308); // Minor delay / amber
  return const Color(0xFFEF4444); // Major delay / red
}

/// Vector-based official BKK / BudapestGO circle icon widget.
class TransitModeCircleIcon extends StatelessWidget {
  final String mode;
  final double size;

  const TransitModeCircleIcon({
    super.key,
    required this.mode,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _TransitModeIconPainter(mode: mode),
      ),
    );
  }
}

class _TransitModeIconPainter extends CustomPainter {
  final String mode;

  _TransitModeIconPainter({required this.mode});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final radius = s / 2;
    final m = mode.toLowerCase();

    switch (m) {
      case 'metro' || 'subway':
        _drawMetro(canvas, s, center, radius);
      case 'suburban_rail' || 'hev':
        _drawHev(canvas, s, center, radius);
      case 'boat' || 'ferry':
        _drawBoat(canvas, s, center, radius);
      case 'tram':
        _drawTram(canvas, s, center, radius);
      case 'trolley' || 'trolleybus':
        _drawTrolley(canvas, s, center, radius);
      case 'train' || 'rail':
        _drawTrain(canvas, s, center, radius);
      default:
        _drawBus(canvas, s, center, radius);
    }
  }

  /// Metró: Fehér kör fekete szegéllyel, benne a jellegzetes vastag fekete M betűvel
  void _drawMetro(Canvas canvas, double s, Offset center, double radius) {
    // Fehér kitöltés
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Fekete szegély
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08;
    canvas.drawCircle(center, radius - (s * 0.04), borderPaint);

    // Vastag fekete M betű
    final mPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.14
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    final mPath = Path()
      ..moveTo(s * 0.28, s * 0.72)
      ..lineTo(s * 0.28, s * 0.28)
      ..lineTo(s * 0.50, s * 0.58)
      ..lineTo(s * 0.72, s * 0.28)
      ..lineTo(s * 0.72, s * 0.72);

    canvas.drawPath(mPath, mPaint);
  }

  /// HÉV: Fehér kör fekete szegéllyel, benne a jellegzetes dupla-szárú fekete H betűvel
  void _drawHev(Canvas canvas, double s, Offset center, double radius) {
    // Fehér kitöltés
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Fekete szegély
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08;
    canvas.drawCircle(center, radius - (s * 0.04), borderPaint);

    // Dupla-szárú fekete H betű
    final hPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.square;

    // Bal dupla szár
    canvas.drawLine(Offset(s * 0.26, s * 0.26), Offset(s * 0.26, s * 0.74), hPaint);
    canvas.drawLine(Offset(s * 0.36, s * 0.26), Offset(s * 0.36, s * 0.74), hPaint);

    // Jobb dupla szár
    canvas.drawLine(Offset(s * 0.64, s * 0.26), Offset(s * 0.64, s * 0.74), hPaint);
    canvas.drawLine(Offset(s * 0.74, s * 0.26), Offset(s * 0.74, s * 0.74), hPaint);

    // Vízszintes összekötő vonal
    canvas.drawLine(Offset(s * 0.26, s * 0.50), Offset(s * 0.74, s * 0.50), hPaint);
  }

  /// Hajó: Fehér kör fekete szegéllyel, benne a hullámos aljú fekete D betűvel
  void _drawBoat(Canvas canvas, double s, Offset center, double radius) {
    // Fehér kitöltés
    final bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Fekete szegély
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.08;
    canvas.drawCircle(center, radius - (s * 0.04), borderPaint);

    // Hullámos aljú fekete D betű
    final dPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.085
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dPath = Path()
      ..moveTo(s * 0.30, s * 0.66)
      ..lineTo(s * 0.30, s * 0.26)
      ..lineTo(s * 0.48, s * 0.26)
      ..cubicTo(s * 0.73, s * 0.26, s * 0.73, s * 0.64, s * 0.48, s * 0.64)
      ..cubicTo(s * 0.42, s * 0.60, s * 0.36, s * 0.70, s * 0.30, s * 0.66);

    canvas.drawPath(dPath, dPaint);

    // Kiegészítő víz hullám a D betű alatt
    final wavePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round;

    final wavePath = Path()
      ..moveTo(s * 0.27, s * 0.77)
      ..cubicTo(s * 0.38, s * 0.71, s * 0.44, s * 0.83, s * 0.55, s * 0.77)
      ..cubicTo(s * 0.63, s * 0.73, s * 0.69, s * 0.81, s * 0.73, s * 0.77);

    canvas.drawPath(wavePath, wavePaint);
  }

  /// Villamos: Sárga kör (#FFD800) benne fekete villamos-homlokfal sziluettel és áramszedővel
  void _drawTram(Canvas canvas, double s, Offset center, double radius) {
    // Sárga kör kitöltés
    final bgPaint = Paint()
      ..color = const Color(0xFFFFD800)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.fill;

    final fgStroke = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round;

    // Áramszedő (pantográf) a tetőn
    canvas.drawLine(Offset(s * 0.50, s * 0.32), Offset(s * 0.50, s * 0.26), fgStroke);
    final pantoPath = Path()
      ..moveTo(s * 0.50, s * 0.26)
      ..lineTo(s * 0.42, s * 0.21)
      ..lineTo(s * 0.50, s * 0.16)
      ..lineTo(s * 0.58, s * 0.21)
      ..close();
    canvas.drawPath(pantoPath, fgStroke);
    canvas.drawLine(Offset(s * 0.37, s * 0.16), Offset(s * 0.63, s * 0.16), fgStroke);

    // Villamos homlokfal test
    final bodyRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(s * 0.30, s * 0.32, s * 0.70, s * 0.76),
      topLeft: Radius.circular(s * 0.08),
      topRight: Radius.circular(s * 0.08),
      bottomLeft: Radius.circular(s * 0.04),
      bottomRight: Radius.circular(s * 0.04),
    );
    canvas.drawRRect(bodyRect, fgPaint);

    // Szélvédő (sárga kivágás)
    final winPaint = Paint()
      ..color = const Color(0xFFFFD800)
      ..style = PaintingStyle.fill;
    final winRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.36, s * 0.38, s * 0.64, s * 0.52),
      Radius.circular(s * 0.03),
    );
    canvas.drawRRect(winRect, winPaint);

    // Fényszórók
    canvas.drawCircle(Offset(s * 0.39, s * 0.66), s * 0.035, winPaint);
    canvas.drawCircle(Offset(s * 0.61, s * 0.66), s * 0.035, winPaint);
  }

  /// Trolibusz: Piros kör (#E41F18) benne fehér trolibusz-homlokfal sziluettel és dupla áramszedő szarvval
  void _drawTrolley(Canvas canvas, double s, Offset center, double radius) {
    // Piros kör kitöltés
    final bgPaint = Paint()
      ..color = const Color(0xFFE41F18)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final fgStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;

    // Dupla áramszedő szarv a tetőről rézsútosan
    canvas.drawLine(Offset(s * 0.44, s * 0.33), Offset(s * 0.31, s * 0.16), fgStroke);
    canvas.drawLine(Offset(s * 0.56, s * 0.33), Offset(s * 0.69, s * 0.16), fgStroke);

    // Troli karosszéria
    final bodyRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(s * 0.30, s * 0.33, s * 0.70, s * 0.76),
      topLeft: Radius.circular(s * 0.08),
      topRight: Radius.circular(s * 0.08),
      bottomLeft: Radius.circular(s * 0.04),
      bottomRight: Radius.circular(s * 0.04),
    );
    canvas.drawRRect(bodyRect, fgPaint);

    // Osztott szélvédő (piros kivágás)
    final winPaint = Paint()
      ..color = const Color(0xFFE41F18)
      ..style = PaintingStyle.fill;
    final winRect1 = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.35, s * 0.39, s * 0.485, s * 0.53),
      Radius.circular(s * 0.02),
    );
    final winRect2 = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.515, s * 0.39, s * 0.65, s * 0.53),
      Radius.circular(s * 0.02),
    );
    canvas.drawRRect(winRect1, winPaint);
    canvas.drawRRect(winRect2, winPaint);

    // Fényszórók
    canvas.drawCircle(Offset(s * 0.38, s * 0.66), s * 0.035, winPaint);
    canvas.drawCircle(Offset(s * 0.62, s * 0.66), s * 0.035, winPaint);
  }

  /// Autóbusz: Világoskék kör (#009EE3) benne fehér autóbusz-homlokfal sziluettel
  void _drawBus(Canvas canvas, double s, Offset center, double radius) {
    // Világoskék kör kitöltés
    final bgPaint = Paint()
      ..color = const Color(0xFF009EE3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final winPaint = Paint()
      ..color = const Color(0xFF009EE3)
      ..style = PaintingStyle.fill;

    // Busz karosszéria
    final bodyRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(s * 0.28, s * 0.26, s * 0.72, s * 0.74),
      topLeft: Radius.circular(s * 0.08),
      topRight: Radius.circular(s * 0.08),
      bottomLeft: Radius.circular(s * 0.05),
      bottomRight: Radius.circular(s * 0.05),
    );
    canvas.drawRRect(bodyRect, fgPaint);

    // Felső viszonylatjelző
    final signRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.38, s * 0.31, s * 0.62, s * 0.36),
      Radius.circular(s * 0.02),
    );
    canvas.drawRRect(signRect, winPaint);

    // Nagy szélvédő
    final winRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(s * 0.34, s * 0.40, s * 0.66, s * 0.54),
      Radius.circular(s * 0.03),
    );
    canvas.drawRRect(winRect, winPaint);

    // Fényszórók
    canvas.drawCircle(Offset(s * 0.37, s * 0.64), s * 0.035, winPaint);
    canvas.drawCircle(Offset(s * 0.63, s * 0.64), s * 0.035, winPaint);

    // Alsó kerekek
    canvas.drawRect(Rect.fromLTRB(s * 0.33, s * 0.74, s * 0.41, s * 0.78), fgPaint);
    canvas.drawRect(Rect.fromLTRB(s * 0.59, s * 0.74, s * 0.67, s * 0.78), fgPaint);
  }

  /// Vonat: Királykék kör (#003B7A) fehér vonat piktogrammal
  void _drawTrain(Canvas canvas, double s, Offset center, double radius) {
    // Királykék kör kitöltés
    final bgPaint = Paint()
      ..color = const Color(0xFF003B7A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final winPaint = Paint()
      ..color = const Color(0xFF003B7A)
      ..style = PaintingStyle.fill;

    // Vonat test
    final bodyPath = Path()
      ..moveTo(s * 0.34, s * 0.74)
      ..lineTo(s * 0.32, s * 0.40)
      ..cubicTo(s * 0.32, s * 0.27, s * 0.40, s * 0.22, s * 0.50, s * 0.22)
      ..cubicTo(s * 0.60, s * 0.22, s * 0.68, s * 0.27, s * 0.68, s * 0.40)
      ..lineTo(s * 0.66, s * 0.74)
      ..close();
    canvas.drawPath(bodyPath, fgPaint);

    // Szélvédő
    final winPath = Path()
      ..moveTo(s * 0.37, s * 0.49)
      ..lineTo(s * 0.37, s * 0.38)
      ..cubicTo(s * 0.37, s * 0.33, s * 0.43, s * 0.31, s * 0.50, s * 0.31)
      ..cubicTo(s * 0.57, s * 0.31, s * 0.63, s * 0.33, s * 0.63, s * 0.38)
      ..lineTo(s * 0.63, s * 0.49)
      ..close();
    canvas.drawPath(winPath, winPaint);

    // MÁV 3-as fényszóró elrendezés (felső csúcsfény + 2 alsó lámpa)
    canvas.drawCircle(Offset(s * 0.50, s * 0.265), s * 0.025, winPaint);
    canvas.drawCircle(Offset(s * 0.39, s * 0.61), s * 0.035, winPaint);
    canvas.drawCircle(Offset(s * 0.61, s * 0.61), s * 0.035, winPaint);

    // Alsó sín vonal
    final railStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(s * 0.26, s * 0.78), Offset(s * 0.74, s * 0.78), railStroke);
  }

  @override
  bool shouldRepaint(covariant _TransitModeIconPainter oldDelegate) {
    return oldDelegate.mode != mode;
  }
}
