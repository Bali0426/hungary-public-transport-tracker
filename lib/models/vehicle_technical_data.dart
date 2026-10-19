// Models for detailed technical rolling stock data and train compositions
// sourced from vagonWEB (for MÁV trains) and HBweb (for BKK vehicles).

/// A single rail car or locomotive in a MÁV train composition (vagonWEB).
class CarriageInfo {
  final String coachNumber; // e.g. "20", "21" (empty for locomotive)
  final String series; // e.g. "Bbdpmz 8491.41", "630", "815", "415"
  final String typeName; // e.g. "2. osztályú többcélú IC+ kocsi", "Villamos mozdony"
  final String className; // e.g. "2. osztály", "1. osztály", "Prémium / 1+", "Bisztró / Étkező", "Mozdony"
  final String imageUrl; // URL to carriage graphic diagram from vagonWEB
  final int seatCount;
  final int bikeSpaces;
  final bool hasWifi;
  final bool hasAc;
  final bool has230v;
  final bool hasUsb;
  final bool isAccessible;
  final bool hasBistro;
  final bool hasQuietZone;
  final String notes;

  const CarriageInfo({
    required this.coachNumber,
    required this.series,
    required this.typeName,
    required this.className,
    required this.imageUrl,
    this.seatCount = 0,
    this.bikeSpaces = 0,
    this.hasWifi = false,
    this.hasAc = false,
    this.has230v = false,
    this.hasUsb = false,
    this.isAccessible = false,
    this.hasBistro = false,
    this.hasQuietZone = false,
    this.notes = '',
  });

  bool get isLocomotive =>
      className.toLowerCase().contains('mozdony') || coachNumber.isEmpty;
}

/// A complete train composition (vagonWEB).
class TrainComposition {
  final String trainNumber; // e.g. "562", "2834"
  final String trainName; // e.g. "Tokaj", "Z50"
  final String category; // e.g. "IC", "Sz", "IR", "EC", "RJX"
  final String route; // e.g. "Budapest-Keleti - Miskolc - Nyíregyháza"
  final String operatorName; // "MÁV-START Zrt."
  final List<CarriageInfo> carriages;
  final String vagonwebUrl;
  final int year;
  final int? totalLengthMeters;

  const TrainComposition({
    required this.trainNumber,
    required this.trainName,
    required this.category,
    required this.route,
    required this.operatorName,
    required this.carriages,
    required this.vagonwebUrl,
    required this.year,
    this.totalLengthMeters,
  });

  int get totalSeats => carriages.fold(0, (sum, c) => sum + c.seatCount);
  int get totalBikes => carriages.fold(0, (sum, c) => sum + c.bikeSpaces);
  bool get hasBistro => carriages.any((c) => c.hasBistro);
  bool get hasWifi => carriages.any((c) => c.hasWifi);
  bool get hasAc => carriages.any((c) => c.hasAc);
}

/// Detailed vehicle technical specifications for BKK fleet (HBweb.hu).
class BkkVehicleTechnicalInfo {
  final String modelName; // e.g. "Siemens Combino Supra Budapest NF12B"
  final String manufacturer; // e.g. "Siemens Transportation Systems (Bécs/Krefeld)"
  final String operator; // "BKV Zrt." / "ArrivaBus Kft." / "Volánbusz Zrt."
  final String depot; // "Hungária kocsiszín", "Kelenföldi autóbuszgarázs"
  final String fleetNumberOrPlate; // "2001", "SKR-951"
  final String manufacturingPeriod; // "2006-2007"
  final double lengthMeters;
  final double widthMeters;
  final double heightMeters;
  final double curbWeightTonnes;
  final int seats;
  final int standing;
  final String engineAndPower; // "8 × 100 kW vízhűtéses 3-fázisú aszinkron motor"
  final String transmission; // "IGBT inverter, visszatápláló fék"
  final int maxSpeedKmH;
  final bool isLowFloor;
  final int lowFloorPercent; // e.g. 100
  final bool hasAirConditioning;
  final bool hasWheelchairRamp;
  final bool hasUsbChargers;
  final String futarOBU;
  final String hbwebUrl;
  final String description;

  const BkkVehicleTechnicalInfo({
    required this.modelName,
    required this.manufacturer,
    required this.operator,
    required this.depot,
    required this.fleetNumberOrPlate,
    required this.manufacturingPeriod,
    required this.lengthMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.curbWeightTonnes,
    required this.seats,
    required this.standing,
    required this.engineAndPower,
    required this.transmission,
    required this.maxSpeedKmH,
    required this.isLowFloor,
    required this.lowFloorPercent,
    required this.hasAirConditioning,
    required this.hasWheelchairRamp,
    required this.hasUsbChargers,
    required this.futarOBU,
    required this.hbwebUrl,
    required this.description,
  });

  int get totalCapacity => seats + standing;
}
