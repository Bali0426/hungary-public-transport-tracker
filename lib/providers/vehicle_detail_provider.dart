import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vehicle_technical_data.dart';
import '../services/hbweb_service.dart';
import '../services/vagonweb_service.dart';

/// Parameters passed to query train compositions.
class TrainCompositionParams {
  final String lineName;
  final String? tripId;
  final String? destination;
  final String? tripShortName;

  const TrainCompositionParams({
    required this.lineName,
    this.tripId,
    this.destination,
    this.tripShortName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrainCompositionParams &&
          runtimeType == other.runtimeType &&
          lineName == other.lineName &&
          tripId == other.tripId &&
          destination == other.destination &&
          tripShortName == other.tripShortName;

  @override
  int get hashCode =>
      lineName.hashCode ^
      tripId.hashCode ^
      destination.hashCode ^
      tripShortName.hashCode;
}

/// Fetches the train composition with carriage illustrations from vagonWEB (for MÁV trains).
final trainCompositionProvider =
    FutureProvider.autoDispose.family<TrainComposition?, TrainCompositionParams>(
        (ref, params) async {
  return VagonwebService.instance.getTrainComposition(
    lineName: params.lineName,
    tripId: params.tripId,
    destination: params.destination,
    tripShortName: params.tripShortName,
  );
});

/// Parameters passed to query BKK vehicle technical specs.
class BkkTechnicalParams {
  final String vehicleId;
  final String lineName;
  final String vehicleType;
  final String? operatorName;

  const BkkTechnicalParams({
    required this.vehicleId,
    required this.lineName,
    required this.vehicleType,
    this.operatorName,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BkkTechnicalParams &&
          runtimeType == other.runtimeType &&
          vehicleId == other.vehicleId &&
          lineName == other.lineName &&
          vehicleType == other.vehicleType &&
          operatorName == other.operatorName;

  @override
  int get hashCode =>
      vehicleId.hashCode ^
      lineName.hashCode ^
      vehicleType.hashCode ^
      operatorName.hashCode;
}

/// Provides detailed technical specs for BKK vehicles from HBweb.hu.
final bkkTechnicalDataProvider =
    Provider.autoDispose.family<BkkVehicleTechnicalInfo, BkkTechnicalParams>(
        (ref, params) {
  return HbwebService.instance.getVehicleTechnicalInfo(
    vehicleId: params.vehicleId,
    lineName: params.lineName,
    vehicleType: params.vehicleType,
    operatorName: params.operatorName,
  );
});
