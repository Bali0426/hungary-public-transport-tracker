import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/vehicle_technical_data.dart';

class VagonwebService {
  static final VagonwebService instance = VagonwebService._();
  VagonwebService._();

  static const String _baseUrl = 'https://www.vagonweb.cz/razeni';
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) HungaryPublicTransportTracker/1.0',
    'Accept': 'text/html,application/json,*/*',
    'Accept-Language': 'hu,en;q=0.9',
  };

  /// In-memory cache for fetched compositions to make the UI instant.
  final Map<String, TrainComposition> _cache = {};

  /// Helper to extract a train number from a string.
  String? _extractNumberFromString(String text) {
    if (text.isEmpty) return null;

    // 1. Leading number: e.g. "856 TÓPART InterCity", "34123 személyvonat"
    final leadingMatch = RegExp(r'^\s*(\d{1,5})\b').firstMatch(text);
    if (leadingMatch != null) {
      return leadingMatch.group(1);
    }

    // 2. Category prefix + number: e.g. "IC 856", "RJX 60", "EC 140", "IR 8513"
    final catMatch = RegExp(
      r'\b(?:IC|EC|EN|IR|ER|RJ|RJX)\s*(\d{1,5})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (catMatch != null) {
      return catMatch.group(1);
    }

    // 3. Spaced number after word/token: e.g. "Tokaj 562", "Z50 2834"
    final spacedMatch =
        RegExp(r'[A-Za-z0-9]+[\s-](\d{2,5})\b').firstMatch(text);
    if (spacedMatch != null) {
      return spacedMatch.group(1);
    }

    // 4. Standalone 3-5 digit number
    final digits3Match = RegExp(r'\b(\d{3,5})\b').firstMatch(text);
    if (digits3Match != null) {
      return digits3Match.group(1);
    }

    return null;
  }

  /// Extracts the train number from tripShortName, lineName, tripId, or destination.
  String? extractTrainNumber(
    String lineName,
    String? tripId,
    String? dest, [
    String? tripShortName,
  ]) {
    // 1. Primary source: tripShortName (e.g. "856 TÓPART InterCity", "IC 856", "34123 személyvonat")
    if (tripShortName != null && tripShortName.trim().isNotEmpty) {
      final num = _extractNumberFromString(tripShortName.trim());
      if (num != null) return num;
    }

    // 2. Secondary source: lineName (e.g. "IC 562", "IC 562 Tokaj", "Z50 2834")
    if (lineName.trim().isNotEmpty) {
      final num = _extractNumberFromString(lineName.trim());
      if (num != null) return num;
    }

    // 3. Fallback: tripId (e.g. "MAV:2814_100")
    if (tripId != null && tripId.isNotEmpty) {
      final tripClean = tripId.replaceFirst('MAV:', '');
      final tripMatch =
          RegExp(r'(?:^|[^0-9])(\d{3,5})(?:[^0-9]|$)').firstMatch(tripClean);
      if (tripMatch != null) {
        return tripMatch.group(1);
      }
    }

    // 4. Fallback: destination (e.g. "Debrecen (582. sz. vonat)")
    if (dest != null && dest.isNotEmpty) {
      final destMatch = RegExp(r'\((\d{2,5})\.').firstMatch(dest);
      if (destMatch != null) {
        return destMatch.group(1);
      }
    }

    return null;
  }

  /// Extracts the train name (e.g. "Tokaj", "Nyírség", "Balaton", "Z50", "Tópart")
  String extractTrainName(String lineName, [String? tripShortName]) {
    final candidate =
        (tripShortName != null && tripShortName.trim().isNotEmpty)
            ? tripShortName
            : lineName;

    // Remove leading train number if present (e.g. "856 TÓPART InterCity" -> "TÓPART InterCity")
    var cleaned = candidate.replaceFirst(RegExp(r'^\d{1,5}\s+'), '');

    cleaned = cleaned
        .replaceFirst(
          RegExp(
            r'^(IC|EC|EN|IR|ER|RJ|RJX|Sz|S|G|Z)\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\b\d{2,5}\b'), '')
        .trim();

    return cleaned.isNotEmpty
        ? cleaned
        : (candidate.isNotEmpty ? candidate : lineName);
  }

  /// Fetches a train composition from vagonWEB, falling back to a rich offline model if needed.
  Future<TrainComposition?> getTrainComposition({
    required String lineName,
    String? tripId,
    String? destination,
    String? tripShortName,
  }) async {
    // HÉVs (H5-H9, MXA) are managed via BKK / HBweb and never have MÁV VagonWeb compositions
    final lowerCheck = '${lineName.toLowerCase()} ${tripShortName?.toLowerCase() ?? ""}';
    final isHev = lowerCheck.contains('hév') ||
        lowerCheck.contains('hev') ||
        RegExp(r'\bh[5-9]\b', caseSensitive: false).hasMatch(lowerCheck) ||
        RegExp(r'^sz\s*h[5-9]', caseSensitive: false).hasMatch(lowerCheck);
    if (isHev) {
      return null;
    }

    final trainNum =
        extractTrainNumber(lineName, tripId, destination, tripShortName);
    final trainName = extractTrainName(lineName, tripShortName);

    final cacheKey =
        '${trainNum ?? ""}_${lineName}_${tripShortName ?? ""}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    if (trainNum != null && trainNum.isNotEmpty) {
      try {
        final onlineComp =
            await _fetchOnlineVagonweb(trainNum, trainName, lineName);
        if (onlineComp != null) {
          _cache[cacheKey] = onlineComp;
          return onlineComp;
        }
      } catch (_) {
        // Online network failure or timeout
      }
    }

    // Csak ha nem volt online keresési találat (pl. offline teszt vagy vonatszám nélküli keresés)
    final fallback =
        _getPredefinedComposition(lineName, trainNum, trainName, destination);
    if (fallback != null) {
      _cache[cacheKey] = fallback;
    }
    return fallback;
  }

  String _extractCategory(String lineName) {
    final match = RegExp(
      r'\b(IC|EC|EN|IR|ER|RJ|RJX|Sz|S|G|Z)\b',
      caseSensitive: false,
    ).firstMatch(lineName);
    return match?.group(1)?.toUpperCase() ?? 'IC';
  }

  /// Ellenőrzi, hogy egy vagonWEB keresési találat magyar vonathoz tartozik-e.
  /// Kiszűri a tisztán külföldi (pl. ČD, ZSSK, PKP, HŽ, HŽPP, CFR, DB) belföldi vonatokat.
  bool _isHungarianTrainEntry(Map<String, dynamic> item) {
    final zeme = (item['zeme']?.toString() ?? '').toUpperCase();
    final nazev = (item['nazev']?.toString() ?? '').toUpperCase();
    final trasa = (item['trasa']?.toString() ?? '').toUpperCase();
    final value = (item['value']?.toString() ?? '').toUpperCase();
    final fullContext = '$zeme $nazev $trasa $value';

    // 1. Explicit magyar operátorok és országkódok
    final hasHungarianOperator = zeme.contains('START') ||
        zeme.contains('MÁV') ||
        zeme.contains('MAV') ||
        zeme.contains('GYSEV') ||
        zeme.contains('H-') ||
        fullContext.contains('H-START') ||
        fullContext.contains('H-GYSEV') ||
        fullContext.contains('MAGYARORSZÁG') ||
        fullContext.contains('MAGYARORSZAG') ||
        fullContext.contains('HUNGARY');

    // 2. Ismert magyar állomások / helyszínek
    const hungarianKeywords = [
      'BUDAPEST', 'KELETI', 'NYUGATI', 'DÉLI', 'DELI', 'KELENFÖLD', 'KELENFOLD',
      'SZEGED', 'DEBRECEN', 'MISKOLC', 'GYŐR', 'GYOR', 'PÉCS', 'PECS',
      'KESZTHELY', 'ZÁHONY', 'ZAHONY', 'SZOMBATHELY', 'BÉKÉSCSABA', 'BEKESCSABA',
      'SOPRON', 'BALATON', 'SIÓFOK', 'SIOFOK', 'SZOLNOK', 'NYÍREGYHÁZA', 'NYIREGYHAZA',
      'SZÉKESFEHÉRVÁR', 'SZEKESFEHERVAR', 'CEGLÉD', 'CEGLED', 'HEGYESHALOM',
      'NAGYKANIZSA', 'FONYÓD', 'FONYOD', 'TAPOLCA', 'SZOB', 'KOMÁROM', 'KOMAROM',
      'EGER', 'BAJA', 'VESZPRÉM', 'VESZPREM', 'ZALAEGERSZEG'
    ];

    final hasHungarianStation =
        hungarianKeywords.any((kw) => fullContext.contains(kw));

    if (hasHungarianOperator || hasHungarianStation) {
      return true;
    }

    // 3. Tisztán külföldi belföldi társaságok explicit kizárása
    const foreignOperators = [
      'ČD', 'CD', 'ZSSK', 'PKP', 'HŽ', 'HZ', 'HŽPP', 'HZPP',
      'CFR', 'SŽ', 'SZ', 'BDŽ', 'BDZ', 'DB', 'CP', 'SNCB', 'RENFE', 'FS', 'SBB'
    ];
    final isForeign = foreignOperators.any(
      (op) => zeme == op || zeme.startsWith('$op ') || zeme.endsWith(' $op'),
    );
    if (isForeign) {
      return false;
    }

    return false;
  }

  /// Queries vagonWEB's `json_vlaky.php` and `ajax_dalsi_razeni_vlak.php`.
  Future<TrainComposition?> _fetchOnlineVagonweb(
    String trainNum,
    String trainName,
    String rawLineName,
  ) async {
    const years = [2026, 2025, 2024];
    bool searchPerformed = false;

    for (final year in years) {
      final searchUri = Uri.parse(
        '$_baseUrl/json_vlaky.php?jmeno=$trainNum&rok=$year',
      );

      final http.Response searchResp;
      try {
        searchResp = await http.get(searchUri, headers: _headers).timeout(
              const Duration(seconds: 4),
            );
      } catch (_) {
        continue;
      }

      if (searchResp.statusCode != 200 || searchResp.body.isEmpty) {
        continue;
      }

      searchPerformed = true;

      final cleanJson = searchResp.body.replaceFirst('\uFEFF', '').trim();
      final dynamic decoded = jsonDecode(cleanJson);
      if (decoded is! List || decoded.isEmpty) {
        continue;
      }

      Map<String, dynamic>? entry;
      // 1. Prioritás: Explicit MÁV / START / GYSEV bejegyzés
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final zeme = (item['zeme'] as String? ?? '').toUpperCase();
          if (zeme.contains('START') ||
              zeme.contains('MÁV') ||
              zeme.contains('MAV') ||
              zeme.contains('GYSEV') ||
              zeme.startsWith('H-')) {
            entry = item;
            break;
          }
        }
      }

      // 2. Prioritás: Magyar kontextussal rendelkező egyéb vonat
      if (entry == null) {
        for (final item in decoded) {
          if (item is Map<String, dynamic> && _isHungarianTrainEntry(item)) {
            entry = item;
            break;
          }
        }
      }

      // Ha nincs magyar vonatkozású bejegyzés, NEM fogadunk el külföldi találatot!
      if (entry == null) continue;

      final cislo = entry['cislo']?.toString() ?? trainNum;
      final zeme = entry['zeme']?.toString() ?? 'START';
      final druh = entry['druh']?.toString() ?? 'IC';
      final foundName = entry['nazev']?.toString() ?? trainName;
      final trasa = entry['trasa']?.toString() ?? '';

      final carriages = <CarriageInfo>[];
      final actualCarriages = <CarriageInfo>[];
      String? actualDateLabel;

      final ajaxUri = Uri.parse('$_baseUrl/ajax_dalsi_razeni_vlak.php');

      // 1. Tervezett összeállítás lekérése
      try {
        final ajaxResp = await http.post(
          ajaxUri,
          headers: {
            ..._headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'rok': year.toString(),
            'zeme': zeme,
            'cislo': cislo,
            'nazev': '_n_',
            'styl': 'r',
            'aktualni_rok': '2026',
            'vsechny_planovane': '1',
          },
        ).timeout(const Duration(seconds: 5));

        if (ajaxResp.statusCode == 200 && ajaxResp.body.isNotEmpty) {
          carriages.addAll(_parseVagonwebHtmlCarriages(ajaxResp.body));
        }
      } catch (_) {}

      // 2. Legutóbbi tényleges / valós összeállítás lekérése (datum: 'vse')
      try {
        final actualResp = await http.post(
          ajaxUri,
          headers: {
            ..._headers,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'rok': year.toString(),
            'zeme': zeme,
            'cislo': cislo,
            'nazev': '_n_',
            'styl': 'r',
            'aktualni_rok': '2026',
            'datum': 'vse',
          },
        ).timeout(const Duration(seconds: 4));

        if (actualResp.statusCode == 200 && actualResp.body.isNotEmpty) {
          final body = actualResp.body;
          if (body.contains("<table class='vlacek'")) {
            // Dátum és helyszín címke kinyerése a legelső valódi blokkból
            final dateMatch = RegExp(
              r'<h4[^>]*class=["\x27]?color-ex["\x27]?[^>]*>(.*?)</h4>',
              caseSensitive: false,
              dotAll: true,
            ).firstMatch(body);

            if (dateMatch != null) {
              final rawDate = dateMatch.group(1) ?? '';
              actualDateLabel = rawDate
                  .replaceAll(RegExp(r'<[^>]*>'), ' ')
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .replaceFirst(RegExp(r'^Skutečné\s*řazení\s*(?:vlaku\s*)?(?:dne:?)?', caseSensitive: false), '')
                  .trim();
            }

            actualCarriages.addAll(_parseVagonwebHtmlCarriages(body));
          }
        }
      } catch (_) {}

      if (carriages.isNotEmpty || actualCarriages.isNotEmpty) {
        final directUrl =
            '$_baseUrl/vlak.php?zeme=$zeme&kategorie=$druh&cislo=$cislo&rok=$year&lang=hu';

        return TrainComposition(
          trainNumber: cislo,
          trainName: foundName.isNotEmpty ? foundName : rawLineName,
          category: druh,
          route: trasa,
          operatorName: zeme.contains('ÖBB') || zeme.contains('OBB')
              ? 'ÖBB / MÁV-START'
              : 'MÁV-START Zrt.',
          carriages: carriages,
          actualCarriages: actualCarriages,
          actualDateLabel: actualDateLabel,
          vagonwebUrl: directUrl,
          year: year,
        );
      }
    }

    if (searchPerformed) {
      // Sikeres vagonWEB lekérdezés lezajlott, de nem található magyar vonat erre a számra.
      // KIZÁRÓLAG üres összeállítást adunk vissza, hogy NE legyen kamu fallback vonat!
      return TrainComposition(
        trainNumber: trainNum,
        trainName: trainName.isNotEmpty ? trainName : rawLineName,
        category: _extractCategory(rawLineName),
        route: '',
        operatorName: 'MÁV-START Zrt.',
        carriages: const [],
        actualCarriages: const [],
        vagonwebUrl:
            '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=$trainNum&lang=hu',
        year: 2026,
      );
    }

    return null;
  }

  /// Parses carriage blocks (`<td class='bunka_vozu' ...>`) from vagonWEB's HTML response.
  List<CarriageInfo> _parseVagonwebHtmlCarriages(String html) {
    final carriages = <CarriageInfo>[];

    final vlacekIdx = html.indexOf("<table class='vlacek'");
    if (vlacekIdx == -1) return carriages;

    final nextVlacekIdx = html.indexOf("<table class='vlacek'", vlacekIdx + 1);
    final tableHtml = nextVlacekIdx != -1
        ? html.substring(vlacekIdx, nextVlacekIdx)
        : html.substring(vlacekIdx);

    final cellSplits = tableHtml.split(RegExp(r"<td class='bunka_vozu'"));

    for (int i = 1; i < cellSplits.length; i++) {
      final cell = cellSplits[i];

      // Vehicle length from cell width (vagonWEB scale: 10px = 1 meter)
      final widthMatch = RegExp(r'width=["\x27]?(\d+)px').firstMatch(cell);
      final pixelWidth = double.tryParse(widthMatch?.group(1) ?? '');
      final lengthMeters = pixelWidth != null ? pixelWidth / 10.0 : null;

      // Extract carriage image URL and resolve path
      final imgMatch = RegExp(r'<img[^>]+src=["\x27]([^"\x27]+)["\x27]').firstMatch(cell);
      String imageUrl = '';
      if (imgMatch != null) {
        final rawSrc = imgMatch.group(1) ?? '';
        if (rawSrc.isNotEmpty) {
          imageUrl = Uri.parse('$_baseUrl/').resolve(rawSrc).toString();
        }
      }

      // Coach number
      final coachNumMatch =
          RegExp(r'raz-cislo[^>]*>\s*([^<]+)').firstMatch(cell);
      final coachNumber = coachNumMatch?.group(1)?.trim() ?? '';

      // Series & subCode
      final seriesMatch =
          RegExp(r'tab-radam[^>]*>\s*([^<]+)').firstMatch(cell);
      final rawSeries = seriesMatch?.group(1)?.trim() ?? '';

      final subCodeMatch = RegExp(r'<small>([^<]*)</small>').firstMatch(cell);
      final subCode = subCodeMatch?.group(1)?.trim() ?? '';
      final fullSeries = '$rawSeries $subCode'.trim();

      // Determine vehicle class and type
      final isLoco = cell.contains('tab-radam') &&
          (fullSeries.contains('630') ||
              fullSeries.contains('470') ||
              fullSeries.contains('480') ||
              fullSeries.contains('431') ||
              fullSeries.contains('432') ||
              fullSeries.contains('433') ||
              fullSeries.contains('418') ||
              fullSeries.contains('182') ||
              fullSeries.contains('1116') ||
              fullSeries.contains('1216') ||
              fullSeries.contains('380') ||
              imageUrl.contains('lok') ||
              imageUrl.contains('182-') ||
              (coachNumber.isEmpty &&
                  !fullSeries.contains('815') &&
                  !fullSeries.contains('415')));

      String className = '2. osztály';
      String typeName = 'Személykocsi';

      if (isLoco) {
        className = 'Mozdony';
        typeName = _resolveLocomotiveName(fullSeries);
      } else if (cell.contains('tab-jidel') || cell.contains('bar.svg')) {
        className = 'Bisztró / Étkező';
        typeName = 'Étkezőkocsi / Utasellátó';
      } else if (cell.contains('tab-club') || cell.contains('tr1p.svg')) {
        className = 'Prémium / 1+';
        typeName = '1. osztályú prémium szakasz';
      } else if (cell.contains('tab-1tr') || cell.contains('tr1.svg')) {
        className = '1. osztály';
        typeName = '1. osztályú személykocsi';
      } else {
        className = '2. osztály';
        typeName = fullSeries.isNotEmpty
            ? '$fullSeries személykocsi'
            : '2. osztályú személykocsi';
      }

      // Amenities
      final hasWifi = cell.contains('wifi.svg');
      final hasAc = cell.contains('klima.svg');
      final has230v = cell.contains('230V.svg');
      final hasUsb = cell.contains('usb.svg');
      final isAccessible =
          cell.contains('inv') || cell.contains('inv_plos.svg');
      final hasBistro = cell.contains('bar.svg') ||
          cell.contains('jidel') ||
          cell.contains('Utasellátó');

      // Seats & Bikes
      int seatCount = 0;
      String? seatCapacity;
      final seatsMatch =
          RegExp(r'(?:1sed|2sed)\.svg[^>]*>\s*([0-9+]+)').firstMatch(cell);
      if (seatsMatch != null) {
        seatCapacity = seatsMatch.group(1)?.trim();
        if (seatCapacity != null) {
          seatCount = int.tryParse(seatCapacity.split('+').first) ?? 0;
        }
      }

      int bikeSpaces = 0;
      final bikeMatch = RegExp(r'kolo\.svg[^>]*>\s*(\d+)').firstMatch(cell);
      if (bikeMatch != null) {
        bikeSpaces = int.tryParse(bikeMatch.group(1) ?? '0') ?? 0;
      }

      // Operator code from span title or text
      final opMatch = RegExp(
        r'<span[^>]*title=["\x27][^"\x27]*["\x27]>([A-Za-z0-9/_-]+)</span>\s*<span[^>]*class=["\x27]?tab-radam',
      ).firstMatch(cell);
      final operatorCode = opMatch?.group(1)?.trim() ??
          (cell.contains('START') ? 'START' : (cell.contains('MÁV') ? 'MÁV' : null));

      // Origin - Destination route text from carriage table
      final destMatch = RegExp(
        r'<div><b>([^<]+(?:\s*-\s*|\s*–\s*|\s*->\s*)[^<]+)</b></div>',
      ).firstMatch(cell);
      final originDestination = destMatch?.group(1)?.trim();

      carriages.add(CarriageInfo(
        coachNumber: coachNumber,
        series: fullSeries.isNotEmpty
            ? fullSeries
            : (isLoco ? 'MÁV Mozdony' : 'Személykocsi'),
        typeName: typeName,
        className: className,
        imageUrl: imageUrl,
        seatCount: seatCount,
        bikeSpaces: bikeSpaces,
        hasWifi: hasWifi,
        hasAc: hasAc,
        has230v: has230v,
        hasUsb: hasUsb,
        isAccessible: isAccessible,
        hasBistro: hasBistro,
        lengthMeters: lengthMeters,
        operatorCode: operatorCode,
        originDestination: originDestination,
        seatCapacity: seatCapacity,
      ));
    }

    return carriages;
  }

  String _resolveLocomotiveName(String series) {
    if (series.contains('630')) return 'START 630 (Gigant villamos mozdony)';
    if (series.contains('470') || series.contains('182')) {
      return 'START 470 (Taurus villamos mozdony)';
    }
    if (series.contains('1116') || series.contains('1216')) {
      return 'ÖBB 1116 / 1216 (Taurus villamos mozdony)';
    }
    if (series.contains('380')) return 'ČD 380 (Škoda 109E villamos mozdony)';
    if (series.contains('480')) return 'START 480 (TRAXX villamos mozdony)';
    if (series.contains('431') ||
        series.contains('432') ||
        series.contains('433')) {
      return 'START 431 (V43 Szili villamos mozdony)';
    }
    if (series.contains('418')) return 'START 418 (M41 Csörgő dízel mozdony)';
    if (series.contains('415')) return 'START 415 (Stadler FLIRT motorvonat)';
    if (series.contains('815')) return 'START 815 (Stadler KISS emeletes motorvonat)';
    if (series.contains('426')) return 'START 426 (Siemens Desiro dízel motorvonat)';
    if (series.contains('117')) return 'START 117 (Bzmot dízel motorkocsi)';
    return 'Villamos / dízel mozdony ($series)';
  }

  /// High-fidelity realistic Hungarian train fallback compositions with official vagonweb graphics.
  TrainComposition? _getPredefinedComposition(
    String lineName,
    String? trainNum,
    String trainName,
    String? destination,
  ) {
    final lower = lineName.toLowerCase();

    // 1. Railjet (RJX / RJ / Railjet)
    if (lower.startsWith('rj') || lower.contains('railjet')) {
      return TrainComposition(
        trainNumber: trainNum ?? '60',
        trainName: trainName.isNotEmpty ? trainName : 'Railjet Xpress',
        category: 'RJX',
        route: 'Budapest-Keleti – Győr – Wien Hbf – Salzburg – München Hbf',
        operatorName: 'ÖBB / MÁV-START',
        year: 2026,
        vagonwebUrl:
            '$_baseUrl/vlak.php?rok=2026&zeme=%C3%96BB&cislo=${trainNum ?? "60"}&lang=hu',
        carriages: const [
          CarriageInfo(
            coachNumber: '',
            series: 'ÖBB 1116 (Taurus)',
            typeName: 'Siemens ES64U2 villamos mozdony (6400 kW, 230 km/h)',
            className: 'Mozdony',
            imageUrl: 'https://www.vagonweb.cz/popisy/img/OeBB/RJ-1116-2-b.gif',
            lengthMeters: 19.3,
          ),
          CarriageInfo(
            coachNumber: '21',
            series: 'ÖBB Bmpvz 22-90',
            typeName: '2. osztályú többcélú személykocsi (Kerékpárhelyek)',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/Bmpz-2290-1-rj-2016-b.gif',
            seatCount: 60,
            bikeSpaces: 6,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            isAccessible: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '22',
            series: 'ÖBB Bmpz 22-90',
            typeName: '2. osztályú termes személykocsi',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/Bmpz-2290-2-rj-2019-b.gif',
            seatCount: 80,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '23',
            series: 'ÖBB Bmpz 22-90',
            typeName: '2. osztályú termes személykocsi',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/Bmpz-2290-3-rj-2019-b.gif',
            seatCount: 80,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '24',
            series: 'ÖBB Bmpz 22-90',
            typeName: '2. osztályú termes személykocsi (Családi szakasz)',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/Bmpz-2290-3-4-rj-2016-b.gif',
            seatCount: 80,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '25',
            series: 'ÖBB ARbmpz 85-90',
            typeName: 'Railjet Bistro / Étkező & 1. osztály',
            className: 'Bisztró / Étkező',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/ARbmpz-8590-5-rj-2016-b.gif',
            seatCount: 24,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            hasBistro: true,
            lengthMeters: 26.5,
          ),
          CarriageInfo(
            coachNumber: '26',
            series: 'ÖBB Ampz 19-90',
            typeName: '1. osztályú First Class termes személykocsi',
            className: '1. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/Ampz-1990-6-rj-2016-b.gif',
            seatCount: 54,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.5,
          ),
          CarriageInfo(
            coachNumber: '27',
            series: 'ÖBB Afmpz 80-90',
            typeName: 'Business & First Class vezérlőkocsi',
            className: 'Prémium / 1+',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/OeBB/Afmpz-8090-7-rj-2019-b.gif',
            seatCount: 32,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.8,
          ),
        ],
      );
    }

    // 2. EuroCity (EC / EN)
    if (lower.startsWith('ec') ||
        lower.startsWith('en') ||
        lower.contains('eurocity')) {
      return TrainComposition(
        trainNumber: trainNum ?? '140',
        trainName: trainName.isNotEmpty ? trainName : 'Hortobágy EuroCity',
        category: 'EC',
        route: destination != null && destination.isNotEmpty
            ? destination
            : 'Záhony – Debrecen – Budapest-Keleti – Győr – Wien Hbf',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        vagonwebUrl:
            '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=${trainNum ?? "140"}&lang=hu',
        carriages: const [
          CarriageInfo(
            coachNumber: '',
            series: 'START 470 (Taurus)',
            typeName: 'Siemens ES64U2 villamos mozdony (6400 kW, 230 km/h)',
            className: 'Mozdony',
            imageUrl: 'https://www.vagonweb.cz/popisy/img/H-/MAVRT/182-a.gif',
            lengthMeters: 19.3,
          ),
          CarriageInfo(
            coachNumber: '410',
            series: 'START Amz 19-91',
            typeName: '1. osztályú EC fülkés személykocsi',
            className: '1. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/START/Amz-1991-3-m-a.gif',
            seatCount: 54,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '411',
            series: 'START WRRmz 88-71',
            typeName: 'Étkezőkocsi (Utasellátó Étterem)',
            className: 'Bisztró / Étkező',
            imageUrl: 'https://www.vagonweb.cz/popisy/img/START/WRRmz-m-a.gif',
            seatCount: 30,
            hasWifi: true,
            hasAc: true,
            hasBistro: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '412',
            series: 'START Bbdpmz 84-91 (IC+)',
            typeName: '2. osztályú többcélú IC+ kocsi (Akadálymentes)',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/START/Bbdpmz-8491-4-a.gif',
            seatCount: 54,
            bikeSpaces: 8,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            hasUsb: true,
            isAccessible: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '413',
            series: 'START Bmz 21-91',
            typeName: '2. osztályú EC fülkés személykocsi',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/START/Bmz-2191-3-m-a.gif',
            seatCount: 66,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.4,
          ),
          CarriageInfo(
            coachNumber: '414',
            series: 'START Bpmz 20-91',
            typeName: '2. osztályú EC termes személykocsi',
            className: '2. osztály',
            imageUrl:
                'https://www.vagonweb.cz/popisy/img/START/Bpmz-2091-1-m-a.gif',
            seatCount: 80,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            lengthMeters: 26.4,
          ),
        ],
      );
    }

    // 3. Named Hungarian InterCity / EuroCity routes (Tópart, Balaton, Mecsek, Napfény, Savaria, etc.)
    final search = '$lineName $trainName ${destination ?? ""}'.toLowerCase();

    for (final entry in _namedTrainRoutes.entries) {
      if (search.contains(entry.key)) {
        final cfg = entry.value;
        final resolvedNum = (trainNum != null && trainNum.isNotEmpty)
            ? trainNum
            : cfg.defaultNumber;
        final resolvedName =
            trainName.isNotEmpty ? trainName : cfg.defaultName;
        final resolvedRoute = destination != null && destination.isNotEmpty
            ? destination
            : cfg.defaultRoute;

        return TrainComposition(
          trainNumber: resolvedNum,
          trainName: resolvedName,
          category: cfg.category,
          route: resolvedRoute,
          operatorName: cfg.operatorName ?? 'MÁV-START Zrt.',
          year: 2026,
          vagonwebUrl:
              '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=$resolvedNum&lang=hu',
          carriages: cfg.carriages ?? _standardMavIcCarriages,
        );
      }
    }

    // 4. Stadler KISS Double-Decker EMU (Z50, Z60, etc.)
    if (RegExp(r'^z\d', caseSensitive: false).hasMatch(lower) ||
        lower.contains('kiss') ||
        lower.contains('815') ||
        (trainNum != null &&
            ['2834', '2814', '2824', '2524', '2414'].contains(trainNum))) {
      return TrainComposition(
        trainNumber: trainNum ?? '2834',
        trainName: trainName.isNotEmpty ? trainName : 'Z50 Elővárosi Zónázó',
        category: 'Sz',
        route: 'Budapest-Nyugati – Cegléd – Szolnok',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        vagonwebUrl:
            '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=${trainNum ?? "2834"}&lang=hu',
        carriages: const [
          CarriageInfo(
            coachNumber: '1',
            series: 'START 815 (KISS)',
            typeName: 'Stadler KISS 6 részes emeletes motorvonat',
            className: '2. osztály (Alacsonypadlós)',
            imageUrl: 'https://www.vagonweb.cz/popisy/img/START/815-a.gif',
            seatCount: 600,
            bikeSpaces: 12,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            hasUsb: true,
            isAccessible: true,
            lengthMeters: 155.8,
            notes:
                '100% klimatizált, akadálymentes mosdó, modern utastájékoztató',
          ),
        ],
      );
    }

    // 5. Siemens Desiro DMU (S72, 142 Lajosmizse, etc.)
    if (lower.contains('desiro') || lower.contains('426')) {
      return TrainComposition(
        trainNumber: trainNum ?? '2014',
        trainName: trainName.isNotEmpty ? trainName : 'S72 Személyvonat',
        category: 'S',
        route: destination != null && destination.isNotEmpty
            ? destination
            : 'Budapest-Nyugati – Esztergom',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        vagonwebUrl:
            '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=${trainNum ?? "2014"}&lang=hu',
        carriages: const [
          CarriageInfo(
            coachNumber: '1',
            series: 'START 426 (Desiro)',
            typeName: 'Siemens Desiro Classic 2 részes dízel motorvonat',
            className: '2. osztály (Alacsonypadlós)',
            imageUrl: 'https://www.vagonweb.cz/popisy/img/START/426-a.gif',
            seatCount: 110,
            bikeSpaces: 4,
            hasWifi: true,
            hasAc: true,
            isAccessible: true,
            lengthMeters: 41.7,
            notes: 'Klímatizált, alacsonypadlós beszállás, zárt rendszerű WC',
          ),
        ],
      );
    }

    // HÉVs (H5-H9, MXA) should never be returned as MÁV FLIRT EMUs
    final isHev = lower.contains('hév') ||
        lower.contains('hev') ||
        RegExp(r'\bh[5-9]\b', caseSensitive: false).hasMatch(lower) ||
        RegExp(r'^sz\s*h[5-9]', caseSensitive: false).hasMatch(lower);
    if (isHev) {
      return null;
    }

    // 6. Stadler FLIRT EMU (S-vonatok, S10, S30, S40, S42, S76, G43, etc.)
    if (RegExp(r'^(s\d|g\d|z\d)', caseSensitive: false).hasMatch(lower) ||
        lower.contains('flirt') ||
        lower.contains('415')) {
      return TrainComposition(
        trainNumber: trainNum ?? '4814',
        trainName: trainName.isNotEmpty ? trainName : 'S50 Személyvonat',
        category: 'S',
        route: destination != null && destination.isNotEmpty
            ? destination
            : 'Budapest – Elővárosi szakasz',
        operatorName: 'MÁV-START Zrt.',
        year: 2026,
        vagonwebUrl:
            '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=${trainNum ?? "4814"}&lang=hu',
        carriages: const [
          CarriageInfo(
            coachNumber: '1',
            series: 'START 415 (FLIRT)',
            typeName: 'Stadler FLIRT 4 részes villamos motorvonat',
            className: '2. osztály (Alacsonypadlós)',
            imageUrl: 'https://www.vagonweb.cz/popisy/img/START/415-a.gif',
            seatCount: 200,
            bikeSpaces: 6,
            hasWifi: true,
            hasAc: true,
            has230v: true,
            isAccessible: true,
            lengthMeters: 74.3,
            notes:
                'Többcélú tér kerékpároknak és kerekesszékeknek, zárt rendszerű WC',
          ),
        ],
      );
    }

    // 7. Generic InterCity fallback (when train is IC but no specific route matched)
    // NEVER fall back to '562' for an unknown IC train!
    final genericNum = trainNum ?? '';
    final genericName = trainName.isNotEmpty
        ? trainName
        : (genericNum.isNotEmpty ? 'IC $genericNum' : 'InterCity');
    final genericUrl = genericNum.isNotEmpty
        ? '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&cislo=$genericNum&lang=hu'
        : '$_baseUrl/vlak.php?rok=2026&zeme=M%C3%81V&lang=hu';

    return TrainComposition(
      trainNumber: genericNum,
      trainName: genericName,
      category: 'IC',
      route: destination != null && destination.isNotEmpty
          ? destination
          : 'MÁV-START InterCity viszonylat',
      operatorName: 'MÁV-START Zrt.',
      year: 2026,
      vagonwebUrl: genericUrl,
      carriages: const [], // Üres állapot – nincs kamu kocsiösszeállítás
      actualCarriages: const [],
    );
  }

  static const List<CarriageInfo> _standardMavIcCarriages = [
    CarriageInfo(
      coachNumber: '',
      series: 'START 470 (Taurus)',
      typeName: 'Siemens ES64U2 villamos mozdony (6400 kW, 230 km/h)',
      className: 'Mozdony',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/H-/MAVRT/182-a.gif',
      lengthMeters: 19.3,
    ),
    CarriageInfo(
      coachNumber: '18',
      series: 'START Apee 10-44',
      typeName: '1. osztályú termes személykocsi',
      className: '1. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/Apee-1044-a.gif',
      seatCount: 60,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      lengthMeters: 24.5,
      notes: 'Kényelmes dönthető bőrülések, olvasólámpák',
    ),
    CarriageInfo(
      coachNumber: '19',
      series: 'START ARmz 85-91 (IC+)',
      typeName: '1. osztályú Prémium szakasz és Utasellátó Bisztró',
      className: 'Prémium / 1+ & Bisztró',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/ARmz-8591-4-a.gif',
      seatCount: 35,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      hasUsb: true,
      hasBistro: true,
      lengthMeters: 26.4,
      notes:
          'Prémium 1+ fülkék, kávé, hideg-meleg ételek, Utasellátó személyzet',
    ),
    CarriageInfo(
      coachNumber: '20',
      series: 'START Bbdpmz 84-91 (IC+)',
      typeName: '2. osztályú többcélú IC+ kocsi (Akadálymentes)',
      className: '2. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/Bbdpmz-8491-4-a.gif',
      seatCount: 54,
      bikeSpaces: 8,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      hasUsb: true,
      isAccessible: true,
      lengthMeters: 26.4,
      notes:
          'Kerekesszékes emelő, tágas akadálymentes mosdó, kerékpártároló',
    ),
    CarriageInfo(
      coachNumber: '21',
      series: 'START Bpee 20-44',
      typeName: '2. osztályú termes személykocsi',
      className: '2. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/Bpee-2044-m-a.gif',
      seatCount: 78,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      lengthMeters: 24.5,
      notes: 'Klimatizált, csendes utastér nagy csomagtartókkal',
    ),
    CarriageInfo(
      coachNumber: '22',
      series: 'START Bpmee 20-76',
      typeName: '2. osztályú IC termes személykocsi',
      className: '2. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/Bpmee-2076-a.gif',
      seatCount: 80,
      bikeSpaces: 2,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      lengthMeters: 26.4,
      notes: 'InterCity minőség, kerékpárhelyek az előtérben',
    ),
  ];

  static const List<CarriageInfo> _herkulesCarriages = [
    CarriageInfo(
      coachNumber: '',
      series: 'START 480 (TRAXX)',
      typeName: 'Bombardier TRAXX villamos mozdony (5600 kW, 160 km/h)',
      className: 'Mozdony',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/480-a.gif',
      lengthMeters: 18.9,
    ),
    CarriageInfo(
      coachNumber: '421',
      series: 'CFR Amz 19-76',
      typeName: '1. osztályú fülkés személykocsi',
      className: '1. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/CFR/Amz-1976-a.gif',
      seatCount: 54,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      lengthMeters: 26.4,
    ),
    CarriageInfo(
      coachNumber: '422',
      series: 'START Bbdpmz 84-91 (IC+)',
      typeName: '2. osztályú többcélú IC+ kocsi (Akadálymentes)',
      className: '2. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/START/Bbdpmz-8491-4-a.gif',
      seatCount: 54,
      bikeSpaces: 8,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      hasUsb: true,
      isAccessible: true,
      lengthMeters: 26.4,
      notes: 'Kerekesszékes emelő, tágas akadálymentes mosdó, kerékpártároló',
    ),
    CarriageInfo(
      coachNumber: '423',
      series: 'CFR Bmz 21-76',
      typeName: '2. osztályú fülkés személykocsi',
      className: '2. osztály',
      imageUrl: 'https://www.vagonweb.cz/popisy/img/CFR/Bmz-2176-a.gif',
      seatCount: 66,
      hasWifi: true,
      hasAc: true,
      has230v: true,
      lengthMeters: 26.4,
    ),
  ];

  static final Map<String, _NamedTrainRoute> _namedTrainRoutes = {
    'tópart': const _NamedTrainRoute(
      defaultNumber: '856',
      defaultName: 'Tópart InterCity',
      defaultRoute:
          'Budapest-Déli – Székesfehérvár – Siófok – Fonyód – Nagykanizsa / Keszthely',
    ),
    'topart': const _NamedTrainRoute(
      defaultNumber: '856',
      defaultName: 'Tópart InterCity',
      defaultRoute:
          'Budapest-Déli – Székesfehérvár – Siófok – Fonyód – Nagykanizsa / Keszthely',
    ),
    'balaton': const _NamedTrainRoute(
      defaultNumber: '864',
      defaultName: 'Balaton InterCity',
      defaultRoute:
          'Budapest-Déli – Székesfehérvár – Siófok – Fonyód – Keszthely',
    ),
    'mecsek': const _NamedTrainRoute(
      defaultNumber: '804',
      defaultName: 'Mecsek InterCity',
      defaultRoute: 'Budapest-Keleti – Sárbogárd – Dombóvár – Pécs',
    ),
    'napfény': const _NamedTrainRoute(
      defaultNumber: '702',
      defaultName: 'Napfény InterCity',
      defaultRoute: 'Budapest-Nyugati – Cegléd – Kecskemét – Szeged',
    ),
    'napfeny': const _NamedTrainRoute(
      defaultNumber: '702',
      defaultName: 'Napfény InterCity',
      defaultRoute: 'Budapest-Nyugati – Cegléd – Kecskemét – Szeged',
    ),
    'tisza': const _NamedTrainRoute(
      defaultNumber: '628',
      defaultName: 'Tisza InterCity',
      defaultRoute:
          'Budapest-Nyugati – Debrecen – Nyíregyháza – Záhony – Chop',
    ),
    'tokaj': const _NamedTrainRoute(
      defaultNumber: '562',
      defaultName: 'Tokaj InterCity',
      defaultRoute:
          'Budapest-Keleti – Miskolc – Nyíregyháza – Debrecen – Budapest-Nyugati',
    ),
    'nyírség': const _NamedTrainRoute(
      defaultNumber: '612',
      defaultName: 'Nyírség InterCity',
      defaultRoute: 'Budapest-Nyugati – Debrecen – Nyíregyháza',
    ),
    'nyirseg': const _NamedTrainRoute(
      defaultNumber: '612',
      defaultName: 'Nyírség InterCity',
      defaultRoute: 'Budapest-Nyugati – Debrecen – Nyíregyháza',
    ),
    'arrabona': const _NamedTrainRoute(
      defaultNumber: '982',
      defaultName: 'Arrabona InterCity',
      defaultRoute: 'Budapest-Keleti – Győr – Hegyeshalom',
    ),
    'savaria': const _NamedTrainRoute(
      defaultNumber: '924',
      defaultName: 'Savaria InterCity',
      defaultRoute: 'Budapest-Keleti – Győr – Csorna – Szombathely',
    ),
    'göcsej': const _NamedTrainRoute(
      defaultNumber: '954',
      defaultName: 'Göcsej InterCity',
      defaultRoute:
          'Budapest-Déli – Székesfehérvár – Veszprém – Zalaegerszeg',
    ),
    'gocsej': const _NamedTrainRoute(
      defaultNumber: '954',
      defaultName: 'Göcsej InterCity',
      defaultRoute:
          'Budapest-Déli – Székesfehérvár – Veszprém – Zalaegerszeg',
    ),
    'bakony': const _NamedTrainRoute(
      defaultNumber: '904',
      defaultName: 'Bakony InterCity',
      defaultRoute:
          'Budapest-Déli – Székesfehérvár – Veszprém – Szombathely',
    ),
    'békés': const _NamedTrainRoute(
      defaultNumber: '7402',
      defaultName: 'Békés InterCity',
      defaultRoute: 'Budapest-Keleti – Szolnok – Békéscsaba – Lőkösháza',
    ),
    'bekes': const _NamedTrainRoute(
      defaultNumber: '7402',
      defaultName: 'Békés InterCity',
      defaultRoute: 'Budapest-Keleti – Szolnok – Békéscsaba – Lőkösháza',
    ),
    'herkules': const _NamedTrainRoute(
      defaultNumber: '373',
      defaultName: 'Herkules InterCity',
      defaultRoute:
          'Budapest-Keleti – Szolnok – Békéscsaba – Lőkösháza – Curtici – Timisoara',
      operatorName: 'MÁV-START / CFR Călători',
      carriages: _herkulesCarriages,
    ),
  };
}

class _NamedTrainRoute {
  final String defaultNumber;
  final String defaultName;
  final String defaultRoute;
  String get category => 'IC';
  final String? operatorName;
  final List<CarriageInfo>? carriages;

  const _NamedTrainRoute({
    required this.defaultNumber,
    required this.defaultName,
    required this.defaultRoute,
    this.operatorName,
    this.carriages,
  });
}
