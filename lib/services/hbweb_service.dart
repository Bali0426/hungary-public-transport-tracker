import '../models/vehicle_technical_data.dart';

/// Technical rolling stock database for Budapest (BKK / BKV / ArrivaBus / MÁV-HÉV)
/// based on the HBweb.hu vehicle fleet encyclopedia.
class HbwebService {
  static final HbwebService instance = HbwebService._();
  HbwebService._();

  /// Looks up detailed technical parameters for a vehicle given its BKK ID, line, and mode.
  BkkVehicleTechnicalInfo getVehicleTechnicalInfo({
    required String vehicleId,
    required String lineName,
    required String vehicleType,
    String? operatorName,
  }) {
    // Strip "BKK:" prefix if present
    final cleanId = vehicleId.replaceFirst('BKK:', '').trim().toUpperCase();
    final cleanLine = lineName.trim().toUpperCase();
    final vType = vehicleType.toLowerCase();

    // 1. TRAMS (Villamosok)
    if (vType == 'tram') {
      return _matchTram(cleanId, cleanLine);
    }

    // 2. METRO (Metrók)
    if (vType == 'metro' || cleanLine.startsWith('M')) {
      return _matchMetro(cleanId, cleanLine);
    }

    // 3. SUBURBAN RAIL / HÉV (H5, H6, H7, H8, H9)
    if (vType == 'suburban_rail' || cleanLine.startsWith('H')) {
      return _matchHev(cleanId, cleanLine);
    }

    // 4. TROLLEYBUS (Trolibuszok)
    if (vType == 'trolley' || _isTrolleyLine(cleanLine)) {
      return _matchTrolley(cleanId, cleanLine);
    }

    // 5. BOAT / HAJÓ
    if (vType == 'boat' || cleanLine.startsWith('D')) {
      return _matchBoat(cleanId, cleanLine);
    }

    // 6. BUS (Autóbuszok - BKV, ArrivaBus, Volánbusz)
    return _matchBus(cleanId, cleanLine, operatorName);
  }

  bool _isTrolleyLine(String line) {
    final num = int.tryParse(line);
    return num != null && num >= 70 && num <= 83;
  }

  // ---------------------------------------------------------------------------
  // TRAM MATCHING (HBweb)
  // ---------------------------------------------------------------------------
  BkkVehicleTechnicalInfo _matchTram(String id, String line) {
    final trackNum = int.tryParse(id) ?? 0;

    // Siemens Combino Supra Budapest (2001-2040)
    if ((trackNum >= 2001 && trackNum <= 2040) ||
        line == '4' ||
        line == '6' ||
        line == '4-6') {
      final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '2001-2040');
      return BkkVehicleTechnicalInfo(
        modelName: 'Siemens Combino Supra Budapest NF12B',
        manufacturer: 'Siemens Transportation Systems (Bécs / Krefeld)',
        operator: 'BKV Zrt. Vasúti Járműjavító Kft.',
        depot: 'Hungária kocsiszín (Nagykörút 4-6 vonalcsoport)',
        fleetNumberOrPlate: numStr,
        manufacturingPeriod: '2006 – 2007',
        lengthMeters: 53.99,
        widthMeters: 2.40,
        heightMeters: 3.62,
        curbWeightTonnes: 69.7,
        seats: 64,
        standing: 289,
        engineAndPower:
            '8 × 100 kW vízhűtéses 3-fázisú aszinkron motor (800 kW összteljesítmény)',
        transmission: 'IGBT tranzisztoros inverteres közvetlen hajtás, visszatápláló fék',
        maxSpeedKmH: 60,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR fedélzeti számítógép (GPS + GSM-R + TETRA)',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_comb_cim.htm',
        description:
            'A világ egyik legnagyobb forgalmú villamosvonalára készült 6 részes, csuklós, 100%-ban alacsonypadlós szerelvény.',
      );
    }

    // CAF Urbos 3 (9 modulos hosszú, 2201-2212)
    if ((trackNum >= 2201 && trackNum <= 2220) || line == '1') {
      final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '2201-2212');
      return BkkVehicleTechnicalInfo(
        modelName: 'CAF Urbos 3 (56 m – 9 modulos)',
        manufacturer: 'Construcciones y Auxiliar de Ferrocarriles (CAF, Spanyolország)',
        operator: 'BKV Zrt.',
        depot: 'Hungária kocsiszín (1-es villamosvonal)',
        fleetNumberOrPlate: numStr,
        manufacturingPeriod: '2015 – 2021',
        lengthMeters: 55.91,
        widthMeters: 2.40,
        heightMeters: 3.40,
        curbWeightTonnes: 69.4,
        seats: 81,
        standing: 264,
        engineAndPower: '6 × 85 kW 3-fázisú aszinkron motor (510 kW összteljesítmény)',
        transmission: 'IGBT inverteres mikroprocesszoros hajtásrendszer',
        maxSpeedKmH: 50,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: true,
        futarOBU: 'BKK FUTÁR OBU fedélzeti egység',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_caf_cim.htm',
        description:
            'A világ egyik leghosszabb villamosa, 56 méteres hosszal és 345 fős utaskapacitással az 1-es körgyűrűs vonalon.',
      );
    }

    // CAF Urbos 3 (5 modulos rövid, 2101-2147)
    if ((trackNum >= 2101 && trackNum <= 2199) ||
        ['3', '14', '17', '19', '41', '42', '50', '56', '61', '69'].contains(line)) {
      final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '2101-2147');
      return BkkVehicleTechnicalInfo(
        modelName: 'CAF Urbos 3 (34 m – 5 modulos)',
        manufacturer: 'Construcciones y Auxiliar de Ferrocarriles (CAF, Zaragoza/Beasain)',
        operator: 'BKV Zrt.',
        depot: 'Baross kocsiszín / Száva kocsiszín',
        fleetNumberOrPlate: numStr,
        manufacturingPeriod: '2015 – 2024',
        lengthMeters: 34.17,
        widthMeters: 2.40,
        heightMeters: 3.40,
        curbWeightTonnes: 43.0,
        seats: 46,
        standing: 154,
        engineAndPower: '4 × 85 kW 3-fázisú aszinkron motor (340 kW)',
        transmission: 'IGBT mikroprocesszoros hajtás, elektro-dinamikus visszatápláló fék',
        maxSpeedKmH: 50,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: true,
        futarOBU: 'BKK FUTÁR érintőképernyős fedélzeti számítógép',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_caf_cim.htm',
        description:
            'Korszerű 5 részes, 100%-ban akadálymentesített villamos teljes körű utastéri klímával.',
      );
    }

    // ČKD Tatra T5C5 / T5C5K2 / T5C5K2M (4000-4349)
    if ((trackNum >= 4000 && trackNum <= 4349) ||
        ['1', '12', '14', '28', '37', '56', '59', '61'].contains(line)) {
      final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '4000-es sorozat');
      return BkkVehicleTechnicalInfo(
        modelName: 'ČKD Tatra T5C5K2 / T5C5K2M',
        manufacturer: 'ČKD Tatra Smíchov (Prága), korszerűsítette a BKV VJSZ Kft.',
        operator: 'BKV Zrt.',
        depot: 'Szépilona kocsiszín / Angyalföld kocsiszín / Baross kocsiszín',
        fleetNumberOrPlate: numStr,
        manufacturingPeriod: '1979 – 1984 (modernizálva: 2002 – 2022)',
        lengthMeters: 14.70,
        widthMeters: 2.50,
        heightMeters: 3.14,
        curbWeightTonnes: 19.5,
        seats: 28,
        standing: 72,
        engineAndPower:
            '4 × 45 kW egyenáramú motor (180 kW / motorkocsi, 2 vagy 3 kocsis szerelvény)',
        transmission: 'IGBT tranzisztoros szaggató (Ganz-Transelektro / VJSZ)',
        maxSpeedKmH: 65,
        isLowFloor: false,
        lowFloorPercent: 0,
        hasAirConditioning: false,
        hasWheelchairRamp: false,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR fedélzeti berendezés',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_t5_cim.htm',
        description:
            'A budapesti villamoshálózat megbízható igáslova, korszerűsített vezérléssel és dinamikus hajtással.',
      );
    }

    // DÜWAG / LHB TW6000 "Hannoveri" (1500-1624)
    if ((trackNum >= 1500 && trackNum <= 1624) ||
        ['3', '42', '50', '51', '51A', '52', '62', '69'].contains(line)) {
      final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '1500-as sorozat');
      return BkkVehicleTechnicalInfo(
        modelName: 'DÜWAG / LHB TW6000 ("Hannoveri")',
        manufacturer: 'Duewag / Linke-Hofmann-Busch (Hannover, Németország)',
        operator: 'BKV Zrt.',
        depot: 'Száva kocsiszín / Zugló kocsiszín',
        fleetNumberOrPlate: numStr,
        manufacturingPeriod: '1975 – 1983 (BKV beszerzés: 2001-től)',
        lengthMeters: 28.28,
        widthMeters: 2.40,
        heightMeters: 3.30,
        curbWeightTonnes: 38.8,
        seats: 46,
        standing: 104,
        engineAndPower: '2 × 217 kW = 434 kW monomotoros hajtás',
        transmission: 'Tirisztoros szaggatós hajtásvezérlés, rekuperációs villamosfék',
        maxSpeedKmH: 70,
        isLowFloor: false,
        lowFloorPercent: 0,
        hasAirConditioning: false,
        hasWheelchairRamp: false,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR OBU egység',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_tw_cim.htm',
        description:
            'Eredetileg a hannoveri Stadtbahn vonalaira épült csuklós villamos, csendes futás és robusztus kialakítás jellemzi.',
      );
    }

    // Ganz CSMG2 / KCSV7 (1300-1499)
    final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : 'Ganz CSMG');
    return BkkVehicleTechnicalInfo(
      modelName: 'Ganz CSMG2 / KCSV7 "Ipari Csuklós"',
      manufacturer: 'Ganz Villamossági Művek / Ganz-MÁVAG (modernizálva Ganz-Ansaldo)',
      operator: 'BKV Zrt.',
      depot: 'Ferencváros kocsiszín / Kelenföld kocsiszín',
      fleetNumberOrPlate: numStr,
      manufacturingPeriod: '1970 – 1978 (KCSV7 átépítés: 1996 – 1999)',
      lengthMeters: 26.90,
      widthMeters: 2.30,
      heightMeters: 3.10,
      curbWeightTonnes: 26.0,
      seats: 34,
      standing: 147,
      engineAndPower: '2 × 110 kW = 220 kW egyenáramú motor',
      transmission: 'Marokcsapágyas hajtás (KCSV7: IGBT szaggató)',
      maxSpeedKmH: 50,
      isLowFloor: false,
      lowFloorPercent: 0,
      hasAirConditioning: false,
      hasWheelchairRamp: false,
      hasUsbChargers: false,
      futarOBU: 'BKK FUTÁR OBU egység',
      hbwebUrl: 'http://hbweb.hu/jarmu/bkv_csmg_cim.htm',
      description:
          'Klasszikus budapesti ipari csuklós villamos, a Duna-parti vonalak (2, 2B, 23, 47, 49) emblematikus járműve.',
    );
  }

  // ---------------------------------------------------------------------------
  // METRO MATCHING (HBweb)
  // ---------------------------------------------------------------------------
  BkkVehicleTechnicalInfo _matchMetro(String id, String line) {
    // M1 Millenniumi Földalatti (11-33)
    if (line == 'M1' || line == '1') {
      return const BkkVehicleTechnicalInfo(
        modelName: 'Ganz FAV (Millenniumi Földalatti csuklós)',
        manufacturer: 'Ganz Villamossági Művek / Ganz-MÁVAG',
        operator: 'BKV Zrt. Metró Üzemigazgatóság',
        depot: 'Mexikói úti járműtelep',
        fleetNumberOrPlate: '11 – 33',
        manufacturingPeriod: '1973 – 1987',
        lengthMeters: 29.56,
        widthMeters: 2.01,
        heightMeters: 2.60,
        curbWeightTonnes: 36.8,
        seats: 48,
        standing: 113,
        engineAndPower: '4 × 67 kW = 268 kW Ganz motor',
        transmission: 'Közvetlen kapcsolású, tirisztoros korszerűsített szaggató',
        maxSpeedKmH: 60,
        isLowFloor: true,
        lowFloorPercent: 75,
        hasAirConditioning: false,
        hasWheelchairRamp: false,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR földalatti fedélzeti egység',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_favcs_cim.htm',
        description:
            'A kontinens legelső földalatti vasútjának 3 részes csuklós szerelvénye, alacsony belmagassághoz méretezve.',
      );
    }

    // M3 Metrovagonmas 81-717.2K / 81-714.2K (6000-es széria)
    if (line == 'M3' || line == '3') {
      return BkkVehicleTechnicalInfo(
        modelName: 'Metrovagonmas 81-717.2K / 81-714.2K ("Fehér Metró")',
        manufacturer: 'Metrovagonmas (Mitiscsi, Oroszország)',
        operator: 'BKV Zrt. Metró Üzemigazgatóság',
        depot: 'Kőér utcai járműtelep',
        fleetNumberOrPlate: id.isNotEmpty ? id : '6000-es sorozat',
        manufacturingPeriod: '2016 – 2018 (felújítás)',
        lengthMeters: 115.0,
        widthMeters: 2.67,
        heightMeters: 3.65,
        curbWeightTonnes: 195.0,
        seats: 216,
        standing: 1044,
        engineAndPower: '24 × 110 kW = 2640 kW aszinkron motor (6 kocsis szerelvény)',
        transmission: 'Hitachi IGBT frekvenciaváltós hajtásrendszer',
        maxSpeedKmH: 80,
        isLowFloor: false,
        lowFloorPercent: 0,
        hasAirConditioning: false,
        hasWheelchairRamp: false,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR + vonatbefolyásoló (AVR)',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_81714_cim.htm',
        description:
            'A 3-as metróvonal felújított 6 kocsis szerelvénye, modern hajtásrendszerrel és fokozott szellőzéssel.',
      );
    }

    // M2 / M4 Alstom Metropolis
    final isM4 = line == 'M4' || line == '4';
    return BkkVehicleTechnicalInfo(
      modelName: isM4 ? 'Alstom Metropolis AM4-M4 (Automata)' : 'Alstom Metropolis AM5-M2',
      manufacturer: 'Alstom Transport (Valenciennes / Chorzów)',
      operator: 'BKV Zrt. Metró Üzemigazgatóság',
      depot: isM4 ? 'Kelenföldi járműtelep' : 'Fehér úti főműhely',
      fleetNumberOrPlate: id.isNotEmpty ? id : (isM4 ? '540 – 580' : '410 – 444'),
      manufacturingPeriod: '2012 – 2014',
      lengthMeters: isM4 ? 80.0 : 100.0,
      widthMeters: 2.78,
      heightMeters: 3.55,
      curbWeightTonnes: isM4 ? 130.0 : 165.0,
      seats: isM4 ? 164 : 208,
      standing: isM4 ? 650 : 815,
      engineAndPower: isM4
          ? '16 × 150 kW = 2400 kW 3-fázisú aszinkron motor'
          : '20 × 150 kW = 3000 kW 3-fázisú aszinkron motor',
      transmission: 'Alstom ONIX IGBT hajtás, teljes visszatápláló fékrendszer',
      maxSpeedKmH: 80,
      isLowFloor: false,
      lowFloorPercent: 0,
      hasAirConditioning: true,
      hasWheelchairRamp: false,
      hasUsbChargers: false,
      futarOBU: isM4 ? 'Siemens Trainguard MT GoA4 automata vezérlés' : 'BKK FUTÁR + MATRA PZC',
      hbwebUrl: 'http://hbweb.hu/jarmu/bkv_met_alst.htm',
      description: isM4
          ? 'Teljesen automata (GoA4 fokozatú), vezetőfülke nélküli metrókocsi-szerelvény az M4 zöld vonalon.'
          : '5 kocsis, egybefüggő átjárható, klimatizált modern metrószerelvény az M2 kelet-nyugati vonalon.',
    );
  }

  // ---------------------------------------------------------------------------
  // HÉV MATCHING (HBweb)
  // ---------------------------------------------------------------------------
  BkkVehicleTechnicalInfo _matchHev(String id, String line) {
    return BkkVehicleTechnicalInfo(
      modelName: 'MÁV-HÉV LEW MXA motorkocsi és pótkocsi',
      manufacturer: 'Lokomotivbau Elektrotechnische Werke „Hans Beimler” (Hennigsdorf, NDK)',
      operator: 'MÁV-HÉV Zrt.',
      depot: line == 'H5'
          ? 'Szentendrei kocsiszín'
          : (line == 'H6' ? 'Ráckevei fűtőház' : 'Cinkotai járműtelep'),
      fleetNumberOrPlate: id.isNotEmpty ? id : '800 / 600 sorozat',
      manufacturingPeriod: '1975 – 1983',
      lengthMeters: 53.40,
      widthMeters: 2.88,
      heightMeters: 3.80,
      curbWeightTonnes: 74.0,
      seats: 120,
      standing: 248,
      engineAndPower: '4 × 100 kW = 400 kW (egységenként: motorkocsi + pótkocsi + motorkocsi)',
      transmission: 'Egyenáramú marokcsapágyas hajtás, elektropneumatikus kontaktoros vezérlés',
      maxSpeedKmH: 80,
      isLowFloor: false,
      lowFloorPercent: 0,
      hasAirConditioning: false,
      hasWheelchairRamp: false,
      hasUsbChargers: false,
      futarOBU: 'BKK FUTÁR HÉV fedélzeti egység',
      hbwebUrl: 'http://hbweb.hu/jarmu/bkv_mxa_cim.htm',
      description:
          'A budapesti elővárosi HÉV-hálózat robusztus villamos motorvonata, 3 vagy 6 kocsis csatolt szerelvényként közlekedik.',
    );
  }

  // ---------------------------------------------------------------------------
  // TROLLEY MATCHING (HBweb)
  // ---------------------------------------------------------------------------
  BkkVehicleTechnicalInfo _matchTrolley(String id, String line) {
    final trackNum = int.tryParse(id) ?? 0;
    final isArticulated = (trackNum >= 9000 && trackNum <= 9125) ||
        ['75', '75A', '76', '77', '80', '82', '82A'].contains(line);

    if (isArticulated) {
      final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '9000-es sorozat');
      return BkkVehicleTechnicalInfo(
        modelName: 'Solaris-Škoda Trollino 18 (Csuklós, önjáró)',
        manufacturer: 'Solaris Bus & Coach (Bolechowo) + Škoda Electric (Plzeň)',
        operator: 'BKV Zrt. Trolibusz Divízió',
        depot: 'Pongrácz telephely (Kőbánya)',
        fleetNumberOrPlate: numStr,
        manufacturingPeriod: '2015 – 2023',
        lengthMeters: 18.00,
        widthMeters: 2.55,
        heightMeters: 3.49,
        curbWeightTonnes: 18.8,
        seats: 43,
        standing: 92,
        engineAndPower:
            'Škoda 250 kW aszinkron villanymotor + LTO lítium-titanát akkumulátor (min. 4 km önjárás)',
        transmission: 'IGBT frekvenciaváltós közvetlen villamos hajtás',
        maxSpeedKmH: 65,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: true,
        futarOBU: 'BKK FUTÁR OBU érintőképernyős számítógép',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_strol18_cim.htm',
        description:
            'Modern 18 méteres csuklós trolibusz, felsővezeték nélküli akkumulátoros önjáró képességgel és teljes utastéri klímával.',
      );
    }

    final numStr = trackNum > 0 ? trackNum.toString() : (id.isNotEmpty ? id : '8000-es sorozat');
    return BkkVehicleTechnicalInfo(
      modelName: 'Solaris-Škoda Trollino 12 (Szóló, önjáró)',
      manufacturer: 'Solaris Bus & Coach + Škoda Electric',
      operator: 'BKV Zrt. Trolibusz Divízió',
      depot: 'Pongrácz telephely',
      fleetNumberOrPlate: numStr,
      manufacturingPeriod: '2015 – 2023',
      lengthMeters: 12.00,
      widthMeters: 2.55,
      heightMeters: 3.49,
      curbWeightTonnes: 12.8,
      seats: 28,
      standing: 52,
      engineAndPower: 'Škoda 160 kW aszinkron villanymotor + lítium-titanát akkumulátor',
      transmission: 'IGBT villamos közvetlen hajtás, rekuperáció',
      maxSpeedKmH: 65,
      isLowFloor: true,
      lowFloorPercent: 100,
      hasAirConditioning: true,
      hasWheelchairRamp: true,
      hasUsbChargers: true,
      futarOBU: 'BKK FUTÁR fedélzeti számítógép',
      hbwebUrl: 'http://hbweb.hu/jarmu/bkv_strol12_cim.htm',
      description:
          '12 méteres szóló alacsonypadlós trolibusz, beépített vonóakkumulátorral elterelések és felsővezeték-mentes szakaszok leküzdésére.',
    );
  }

  // ---------------------------------------------------------------------------
  // BOAT MATCHING (HBweb)
  // ---------------------------------------------------------------------------
  BkkVehicleTechnicalInfo _matchBoat(String id, String line) {
    return BkkVehicleTechnicalInfo(
      modelName: 'BKK Dunai Átkelőhajó (Hófehérke / Budapest típus)',
      manufacturer: 'Balatonfüredi Hajógyár / Váci Hajógyár',
      operator: 'BKV Zrt. Hajózási Divízió',
      depot: 'Kikötő telephely (Újpest)',
      fleetNumberOrPlate: id.isNotEmpty ? id : 'D-11 / D-12',
      manufacturingPeriod: '2012 – 2014',
      lengthMeters: 22.0,
      widthMeters: 5.2,
      heightMeters: 3.2,
      curbWeightTonnes: 32.0,
      seats: 60,
      standing: 40,
      engineAndPower: 'Iveco / Cummins 180 kW tengeri dízelmotor',
      transmission: 'Hajócsavaros közvetlen tengelyhajtás irányváltóval',
      maxSpeedKmH: 22,
      isLowFloor: true,
      lowFloorPercent: 60,
      hasAirConditioning: true,
      hasWheelchairRamp: true,
      hasUsbChargers: false,
      futarOBU: 'BKK FUTÁR Hajózási terminál',
      hbwebUrl: 'http://hbweb.hu/jarmu/bkv_hajo.htm',
      description:
          'Kétfedélzetes panoráma dunai személyhajó, kerékpárszállítási lehetőséggel és panorámaablakokkal.',
    );
  }

  // ---------------------------------------------------------------------------
  // BUS MATCHING (HBweb)
  // ---------------------------------------------------------------------------
  BkkVehicleTechnicalInfo _matchBus(String id, String line, String? op) {
    final upperId = id.toUpperCase();

    // 1. MAN Lion's City 12C / 18C EfficientHybrid (AA-LC, AA-MD szériák - ArrivaBus Kft.)
    if (upperId.startsWith('AA-LC') ||
        upperId.startsWith('AALC') ||
        upperId.startsWith('AA-MD') ||
        upperId.startsWith('AAMD') ||
        (op != null && op.toLowerCase().contains('arriva'))) {
      final isArticulated = upperId.contains('MD') ||
          ['7', '8E', '108E', '133E', '30', '30A', '230'].contains(line);

      return BkkVehicleTechnicalInfo(
        modelName: isArticulated
            ? "MAN Lion's City 18C EfficientHybrid (Csuklós)"
            : "MAN Lion's City 12C EfficientHybrid (Szóló)",
        manufacturer: 'MAN Truck & Bus SE (Starachowice, Lengyelország)',
        operator: 'ArrivaBus Kft.',
        depot: 'Andor utcai telephely / Bogáncs utcai telephely',
        fleetNumberOrPlate: id.isNotEmpty ? id : 'AA-LC / AA-MD sorozat',
        manufacturingPeriod: '2023',
        lengthMeters: isArticulated ? 18.06 : 12.18,
        widthMeters: 2.55,
        heightMeters: 3.16,
        curbWeightTonnes: isArticulated ? 16.5 : 11.2,
        seats: isArticulated ? 42 : 31,
        standing: isArticulated ? 110 : 73,
        engineAndPower:
            'MAN D1556 LOH Euro 6d dízelmotor (243 kW / 330 LE) + 48V EfficientHybrid szuperkondenzátoros modul',
        transmission: 'Voith DIWA NXT / ZF EcoLife 6-fokozatú automata sebességváltó',
        maxSpeedKmH: 85,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: true,
        futarOBU: 'BKK FUTÁR 2. generációs OBU érintőképernyővel',
        hbwebUrl: 'http://hbweb.hu/jarmu/vta_manlc_cim.htm',
        description:
            '2023-as beszerzésű ultramodern budapesti flotta, rekuperációs 48V hibrid modullal és USB gyorstöltőkkel.',
      );
    }

    // 2. Mercedes-Benz Conecto Next Gen G LF (Csuklós - SKR, AAE, AAK - BKV Zrt.)
    if (upperId.startsWith('SKR') ||
        upperId.startsWith('AAE') ||
        upperId.startsWith('AAK') ||
        upperId.startsWith('RVY') ||
        ['5', '7', '8E', '9', '20E', '30', '85', '100E', '200E'].contains(line)) {
      final isSolo = upperId.startsWith('SKR-9') ||
          upperId.startsWith('SKR9') ||
          upperId.startsWith('RVY') ||
          ['15', '16', '105', '178', '210'].contains(line);

      if (isSolo) {
        return BkkVehicleTechnicalInfo(
          modelName: 'Mercedes-Benz Conecto Next Gen LF (Szóló)',
          manufacturer: 'Mercedes-Benz Türk A.Ş. (Hosdere, Isztambul) / Daimler Buses',
          operator: 'BKV Zrt. Autóbusz Divízió',
          depot: 'Kelenföldi autóbuszgarázs / Dél-Pesti garázs',
          fleetNumberOrPlate: id.isNotEmpty ? id : 'SKR-951...970',
          manufacturingPeriod: '2019 – 2023',
          lengthMeters: 12.13,
          widthMeters: 2.55,
          heightMeters: 3.12,
          curbWeightTonnes: 11.5,
          seats: 26,
          standing: 73,
          engineAndPower: 'Mercedes-Benz OM 936 Euro VI dízelmotor (220 kW / 299 LE, 1200 Nm)',
          transmission: 'ZF EcoLife 6-fokozatú automata sebességváltó hidrodinamikus retarderrel',
          maxSpeedKmH: 80,
          isLowFloor: true,
          lowFloorPercent: 100,
          hasAirConditioning: true,
          hasWheelchairRamp: true,
          hasUsbChargers: true,
          futarOBU: 'BKK FUTÁR fedélzeti számítógép',
          hbwebUrl: 'http://hbweb.hu/jarmu/bkv_mbcon_cim.htm',
          description:
              'A BKV 100%-ban alacsonypadlós, nagy teljesítményű klímával felszerelt korszerű városi szóló busza.',
        );
      }

      return BkkVehicleTechnicalInfo(
        modelName: 'Mercedes-Benz Conecto Next Gen G LF (Csuklós)',
        manufacturer: 'Mercedes-Benz Türk A.Ş. (Hosdere, Isztambul) / Daimler Buses',
        operator: 'BKV Zrt. Autóbusz Divízió',
        depot: 'Óbudai autóbuszgarázs / Cinkotai garázs / Kelenföldi garázs',
        fleetNumberOrPlate: id.isNotEmpty ? id : 'SKR / AAE sorozat',
        manufacturingPeriod: '2020 – 2023',
        lengthMeters: 18.13,
        widthMeters: 2.55,
        heightMeters: 3.12,
        curbWeightTonnes: 16.8,
        seats: 37,
        standing: 111,
        engineAndPower:
            'Mercedes-Benz OM 470 Euro VI Step E dízelmotor (265 kW / 360 LE, 1700 Nm)',
        transmission: 'ZF EcoLife 6-fokozatú automata váltó integrált retarderrel',
        maxSpeedKmH: 80,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: true,
        futarOBU: 'BKK FUTÁR 2 OBU rendszer',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_mbcon_cim.htm',
        description:
            'Nagy befogadóképességű (148 fő), 4 ajtós, 100% alacsonypadlós csuklós autóbusz a legforgalmasabb járatokra.',
      );
    }

    // 3. Mercedes-Benz Citaro (C1, Facelift, C2)
    if (upperId.contains('CITARO') ||
        upperId.startsWith('NCV') ||
        upperId.startsWith('PDN') ||
        upperId.startsWith('MHU')) {
      return BkkVehicleTechnicalInfo(
        modelName: 'Mercedes-Benz Citaro (O530 / Facelift / C2)',
        manufacturer: 'EvoBus GmbH (Mannheim, Németország)',
        operator: 'BKV Zrt. / ArrivaBus Kft.',
        depot: 'Kelenföldi garázs / Dél-Pesti garázs',
        fleetNumberOrPlate: id.isNotEmpty ? id : 'Citaro flotta',
        manufacturingPeriod: '2005 – 2018',
        lengthMeters: 12.00,
        widthMeters: 2.55,
        heightMeters: 3.10,
        curbWeightTonnes: 11.2,
        seats: 29,
        standing: 71,
        engineAndPower: 'Mercedes-Benz OM 906 hLA / OM 936 Euro 5/6 dízelmotor (210 kW)',
        transmission: 'Voith Diwa 5 / ZF Ecomat automata sebességváltó',
        maxSpeedKmH: 80,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR egység',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_mbcit_cim.htm',
        description:
            'Európa legsikeresebb városi autóbuszcsaládja, kifinomult futóművel és kényelmes utastérrel.',
      );
    }

    // 4. Volvo 7700A (FJX, FKU, FLR rendszámok)
    if (upperId.startsWith('FJX') || upperId.startsWith('FKU') || upperId.startsWith('FLR')) {
      return BkkVehicleTechnicalInfo(
        modelName: 'Volvo 7700A (Csuklós)',
        manufacturer: 'Volvo Bus Corporation (Wrocław, Lengyelország)',
        operator: 'BKV Zrt.',
        depot: 'Cinkotai garázs / Kelenföldi garázs',
        fleetNumberOrPlate: id.isNotEmpty ? id : 'FJX / FKU / FLR széria',
        manufacturingPeriod: '2004 – 2006',
        lengthMeters: 17.95,
        widthMeters: 2.55,
        heightMeters: 3.18,
        curbWeightTonnes: 15.9,
        seats: 38,
        standing: 112,
        engineAndPower: 'Volvo D7C / D7E dízelmotor (202 kW / 275 LE)',
        transmission: 'ZF 5HP-592 / Voith D864.3 automata váltó',
        maxSpeedKmH: 75,
        isLowFloor: true,
        lowFloorPercent: 100,
        hasAirConditioning: true,
        hasWheelchairRamp: true,
        hasUsbChargers: false,
        futarOBU: 'BKK FUTÁR OBU',
        hbwebUrl: 'http://hbweb.hu/jarmu/bkv_v7700a_cim.htm',
        description:
            'A budapesti flotta első nagyszériás alacsonypadlós csuklós busztípusa, 150 darabos állománnyal állt forgalomba.',
      );
    }

    // Default / General Budapest Urban Bus
    return BkkVehicleTechnicalInfo(
      modelName: 'Mercedes-Benz Conecto / Citaro városi autóbusz',
      manufacturer: 'Daimler Buses / EvoBus GmbH',
      operator: 'BKV Zrt. / ArrivaBus Kft.',
      depot: 'Budapesti autóbuszgarázs',
      fleetNumberOrPlate: id.isNotEmpty ? id : 'Budapesti autóbusz',
      manufacturingPeriod: '2016 – 2023',
      lengthMeters: 12.10,
      widthMeters: 2.55,
      heightMeters: 3.12,
      curbWeightTonnes: 11.8,
      seats: 30,
      standing: 70,
      engineAndPower: 'Euro VI alacsony károsanyag-kibocsátású dízelmotor (220 kW / 300 LE)',
      transmission: 'ZF EcoLife / Voith automata sebességváltó',
      maxSpeedKmH: 80,
      isLowFloor: true,
      lowFloorPercent: 100,
      hasAirConditioning: true,
      hasWheelchairRamp: true,
      hasUsbChargers: true,
      futarOBU: 'BKK FUTÁR integrált járműfedélzeti rendszer',
      hbwebUrl: 'http://hbweb.hu/jarmu/bkv_mbcon_cim.htm',
      description:
          '100%-ban akadálymentesített, légkondicionált, környezetbarát budapesti közösségi közlekedési autóbusz.',
    );
  }
}
