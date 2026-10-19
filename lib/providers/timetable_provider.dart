import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/bridge_generated.dart';

/// Currently selected station or multimodal hub for the bottom sheet departure board.
final selectedStationProvider = StateProvider<StopNode?>((ref) => null);

/// Unified BKK + MÁV departure board for a given `stopId` or `hubId`.
final stationDepartureBoardProvider = FutureProvider.autoDispose
    .family<List<UnifiedDeparture>, String>((ref, stopOrHubId) async {
  return TransitRustBridge.instance.getStationDepartureBoard(
    stopOrHubId: stopOrHubId,
    horizonMinutes: 90,
    limit: 50,
  );
});

/// Search results across BKK and MÁV stops & station hubs.
final stopSearchProvider = FutureProvider.autoDispose
    .family<List<StopNode>, String>((ref, query) async {
  if (query.trim().isEmpty) {
    return const [];
  }
  return TransitRustBridge.instance.searchStops(
    query: query,
    limit: 30,
  );
});

/// Scheduled stop sequence and departure times for a trip.
final tripScheduleProvider = FutureProvider.autoDispose
    .family<List<TripStopSchedule>, String>((ref, tripId) async {
  if (tripId.trim().isEmpty) {
    return const [];
  }
  return TransitRustBridge.instance.getTripSchedule(tripId: tripId);
});

