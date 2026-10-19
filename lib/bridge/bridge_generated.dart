// Native FFI bindings between Flutter (Dart) and the `transit_engine` Rust crate.
// Uses direct C-ABI dynamic library bindings (`dart:ffi`) out of the box and can be
// regenerated via `flutter_rust_bridge_codegen generate`.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

enum Operator { bkk, mav }

class UnifiedVehicle {
  final String id;
  final Operator operator;
  final String? tripId;
  final String? routeId;
  final String lineName;
  final String destination;
  final double lat;
  final double lon;
  final double bearing;
  final int delaySeconds;
  final int timestamp;
  final String routeColor;
  final String vehicleType;

  const UnifiedVehicle({
    required this.id,
    required this.operator,
    this.tripId,
    this.routeId,
    required this.lineName,
    required this.destination,
    required this.lat,
    required this.lon,
    required this.bearing,
    required this.delaySeconds,
    required this.timestamp,
    required this.routeColor,
    required this.vehicleType,
  });

  factory UnifiedVehicle.fromJson(Map<String, dynamic> json) {
    final opStr = (json['operator'] as String? ?? 'BKK').toUpperCase();
    return UnifiedVehicle(
      id: json['id'] as String,
      operator: opStr == 'MAV' ? Operator.mav : Operator.bkk,
      tripId: json['trip_id'] as String?,
      routeId: json['route_id'] as String?,
      lineName: json['line_name'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      bearing: (json['bearing'] as num? ?? 0.0).toDouble(),
      delaySeconds: (json['delay_seconds'] as num? ?? 0).toInt(),
      timestamp: (json['timestamp'] as num? ?? 0).toInt(),
      routeColor: json['route_color'] as String? ?? '009EE3',
      vehicleType: json['vehicle_type'] as String? ?? 'bus',
    );
  }
}

class StopNode {
  final String id;
  final String? hubId;
  final String name;
  final double lat;
  final double lon;
  final Operator operator;
  final String? platformCode;
  final bool isMultimodalHub;

  const StopNode({
    required this.id,
    this.hubId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.operator,
    this.platformCode,
    required this.isMultimodalHub,
  });

  factory StopNode.fromJson(Map<String, dynamic> json) {
    final opStr = (json['operator'] as String? ?? 'BKK').toUpperCase();
    return StopNode(
      id: json['id'] as String,
      hubId: json['hub_id'] as String?,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      operator: opStr == 'MAV' ? Operator.mav : Operator.bkk,
      platformCode: json['platform_code'] as String?,
      isMultimodalHub: json['is_multimodal_hub'] as bool? ?? false,
    );
  }
}

class UnifiedDeparture {
  final String tripId;
  final String stopId;
  final Operator operator;
  final String lineName;
  final String headsign;
  final String routeColor;
  final String routeTextColor;
  final int scheduledDepartureSeconds;
  final String scheduledTimeFormatted;
  final int delaySeconds;
  final int estimatedDepartureSeconds;
  final String estimatedTimeFormatted;
  final bool isRealtime;
  final String? platformCode;

  const UnifiedDeparture({
    required this.tripId,
    required this.stopId,
    required this.operator,
    required this.lineName,
    required this.headsign,
    required this.routeColor,
    required this.routeTextColor,
    required this.scheduledDepartureSeconds,
    required this.scheduledTimeFormatted,
    required this.delaySeconds,
    required this.estimatedDepartureSeconds,
    required this.estimatedTimeFormatted,
    required this.isRealtime,
    this.platformCode,
  });

  factory UnifiedDeparture.fromJson(Map<String, dynamic> json) {
    final opStr = (json['operator'] as String? ?? 'BKK').toUpperCase();
    return UnifiedDeparture(
      tripId: json['trip_id'] as String,
      stopId: json['stop_id'] as String,
      operator: opStr == 'MAV' ? Operator.mav : Operator.bkk,
      lineName: json['line_name'] as String,
      headsign: json['headsign'] as String,
      routeColor: json['route_color'] as String? ?? '009EE3',
      routeTextColor: json['route_text_color'] as String? ?? 'FFFFFF',
      scheduledDepartureSeconds:
          (json['scheduled_departure_seconds'] as num).toInt(),
      scheduledTimeFormatted: json['scheduled_time_formatted'] as String,
      delaySeconds: (json['delay_seconds'] as num? ?? 0).toInt(),
      estimatedDepartureSeconds:
          (json['estimated_departure_seconds'] as num).toInt(),
      estimatedTimeFormatted: json['estimated_time_formatted'] as String,
      isRealtime: json['is_realtime'] as bool? ?? false,
      platformCode: json['platform_code'] as String?,
    );
  }
}

// C-ABI FFI typedefs
typedef _InitEngineNative = Int32 Function(
  Pointer<Utf8> dbPath,
  Pointer<Utf8> bkkKey,
  Pointer<Utf8> mavUrl,
);
typedef _InitEngineDart = int Function(
  Pointer<Utf8> dbPath,
  Pointer<Utf8> bkkKey,
  Pointer<Utf8> mavUrl,
);

typedef _PollGeoJsonNative = Pointer<Utf8> Function(
  Double minLat,
  Double minLon,
  Double maxLat,
  Double maxLon,
);
typedef _PollGeoJsonDart = Pointer<Utf8> Function(
  double minLat,
  double minLon,
  double maxLat,
  double maxLon,
);

typedef _GetStopsInBboxNative = Pointer<Utf8> Function(
  Double minLat,
  Double minLon,
  Double maxLat,
  Double maxLon,
  IntPtr limit,
);
typedef _GetStopsInBboxDart = Pointer<Utf8> Function(
  double minLat,
  double minLon,
  double maxLat,
  double maxLon,
  int limit,
);

typedef _SearchStopsNative = Pointer<Utf8> Function(
  Pointer<Utf8> query,
  IntPtr limit,
);
typedef _SearchStopsDart = Pointer<Utf8> Function(
  Pointer<Utf8> query,
  int limit,
);

typedef _GetDepartureBoardNative = Pointer<Utf8> Function(
  Pointer<Utf8> stopOrHubId,
  Int32 horizonMinutes,
  IntPtr limit,
);
typedef _GetDepartureBoardDart = Pointer<Utf8> Function(
  Pointer<Utf8> stopOrHubId,
  int horizonMinutes,
  int limit,
);

typedef _FreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

class TransitRustBridge {
  TransitRustBridge._();
  static final TransitRustBridge instance = TransitRustBridge._();

  static DynamicLibrary _openLibrary() {
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir\\transit_engine.dll',
        'transit_engine.dll',
        'rust/target/release/transit_engine.dll',
        'rust/target/debug/transit_engine.dll',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) {
          return DynamicLibrary.open(path);
        }
      }
      return DynamicLibrary.open('transit_engine.dll');
    } else if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libtransit_engine.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  Future<void> initEngine({
    required String sqliteDbPath,
    String? bkkApiKey,
    String? mavGtfsRtUrl,
  }) async {
    await Isolate.run(() {
      final lib = _openLibrary();
      final fn =
          lib.lookupFunction<_InitEngineNative, _InitEngineDart>('transit_init_engine');
      final dbPtr = sqliteDbPath.toNativeUtf8();
      final keyPtr = (bkkApiKey ?? '').toNativeUtf8();
      final mavPtr = (mavGtfsRtUrl ?? '').toNativeUtf8();
      try {
        final code = fn(dbPtr, keyPtr, mavPtr);
        if (code != 0) {
          throw StateError('transit_init_engine failed with code $code');
        }
      } finally {
        calloc.free(dbPtr);
        calloc.free(keyPtr);
        calloc.free(mavPtr);
      }
    });
  }

  Future<String> pollLiveVehiclesGeoJson({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
  }) async {
    return Isolate.run(() {
      final lib = _openLibrary();
      final pollFn = lib.lookupFunction<_PollGeoJsonNative, _PollGeoJsonDart>(
        'transit_poll_live_vehicles_geojson',
      );
      final freeFn = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'transit_free_string',
      );
      final ptr = pollFn(minLat, minLon, maxLat, maxLon);
      try {
        return ptr.toDartString();
      } finally {
        freeFn(ptr);
      }
    });
  }

  Future<List<StopNode>> getStopsInBbox({
    required double minLat,
    required double minLon,
    required double maxLat,
    required double maxLon,
    int limit = 250,
  }) async {
    final rawJson = await Isolate.run(() {
      final lib = _openLibrary();
      final fn = lib.lookupFunction<_GetStopsInBboxNative, _GetStopsInBboxDart>(
        'transit_get_stops_in_bbox_json',
      );
      final freeFn = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'transit_free_string',
      );
      final ptr = fn(minLat, minLon, maxLat, maxLon, limit);
      try {
        return ptr.toDartString();
      } finally {
        freeFn(ptr);
      }
    });
    final decoded = jsonDecode(rawJson) as List<dynamic>;
    return decoded
        .map((e) => StopNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<StopNode>> searchStops({
    required String query,
    int limit = 30,
  }) async {
    final rawJson = await Isolate.run(() {
      final lib = _openLibrary();
      final fn = lib.lookupFunction<_SearchStopsNative, _SearchStopsDart>(
        'transit_search_stops_json',
      );
      final freeFn = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'transit_free_string',
      );
      final qPtr = query.toNativeUtf8();
      final ptr = fn(qPtr, limit);
      try {
        return ptr.toDartString();
      } finally {
        calloc.free(qPtr);
        freeFn(ptr);
      }
    });
    final decoded = jsonDecode(rawJson) as List<dynamic>;
    return decoded
        .map((e) => StopNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<UnifiedDeparture>> getStationDepartureBoard({
    required String stopOrHubId,
    int horizonMinutes = 90,
    int limit = 40,
  }) async {
    final rawJson = await Isolate.run(() {
      final lib = _openLibrary();
      final fn = lib
          .lookupFunction<_GetDepartureBoardNative, _GetDepartureBoardDart>(
            'transit_get_departure_board_json',
          );
      final freeFn = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
        'transit_free_string',
      );
      final idPtr = stopOrHubId.toNativeUtf8();
      final ptr = fn(idPtr, horizonMinutes, limit);
      try {
        return ptr.toDartString();
      } finally {
        calloc.free(idPtr);
        freeFn(ptr);
      }
    });
    final decoded = jsonDecode(rawJson) as List<dynamic>;
    return decoded
        .map((e) => UnifiedDeparture.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
