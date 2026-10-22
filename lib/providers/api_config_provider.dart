import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bridge/bridge_generated.dart';
import 'live_vehicles_provider.dart';

class ApiConfigState {
  final String bkkApiKey;
  final String mavGtfsRtUrl;
  final bool isCustomBkkKey;
  final bool isCustomMavUrl;

  const ApiConfigState({
    required this.bkkApiKey,
    required this.mavGtfsRtUrl,
    this.isCustomBkkKey = false,
    this.isCustomMavUrl = false,
  });

  static const String defaultBkkKey = 'b4beebb5-1ecb-45fd-a83d-3374edb83a2b';
  static const String defaultMavUrl = '';

  ApiConfigState copyWith({
    String? bkkApiKey,
    String? mavGtfsRtUrl,
    bool? isCustomBkkKey,
    bool? isCustomMavUrl,
  }) {
    return ApiConfigState(
      bkkApiKey: bkkApiKey ?? this.bkkApiKey,
      mavGtfsRtUrl: mavGtfsRtUrl ?? this.mavGtfsRtUrl,
      isCustomBkkKey: isCustomBkkKey ?? this.isCustomBkkKey,
      isCustomMavUrl: isCustomMavUrl ?? this.isCustomMavUrl,
    );
  }
}

class ApiConfigNotifier extends StateNotifier<ApiConfigState> {
  final Ref ref;

  ApiConfigNotifier(this.ref)
      : super(const ApiConfigState(
          bkkApiKey: ApiConfigState.defaultBkkKey,
          mavGtfsRtUrl: ApiConfigState.defaultMavUrl,
        ));

  Future<void> updateBkkApiKey(String newKey) async {
    final trimmed = newKey.trim();
    final effectiveKey =
        trimmed.isNotEmpty ? trimmed : ApiConfigState.defaultBkkKey;
    state = state.copyWith(
      bkkApiKey: effectiveKey,
      isCustomBkkKey: trimmed.isNotEmpty && trimmed != ApiConfigState.defaultBkkKey,
    );

    await TransitRustBridge.instance.initEngine(
      sqliteDbPath: '', // Preserves already loaded database repo in Rust
      bkkApiKey: effectiveKey,
    );
    ref.invalidate(liveVehiclesGeoJsonProvider);
  }

  Future<void> updateMavGtfsRtUrl(String newUrl) async {
    final trimmed = newUrl.trim();
    state = state.copyWith(
      mavGtfsRtUrl: trimmed,
      isCustomMavUrl: trimmed.isNotEmpty,
    );

    await TransitRustBridge.instance.initEngine(
      sqliteDbPath: '',
      mavGtfsRtUrl: trimmed,
    );
    ref.invalidate(liveVehiclesGeoJsonProvider);
  }

  Future<void> resetToDefaults() async {
    state = const ApiConfigState(
      bkkApiKey: ApiConfigState.defaultBkkKey,
      mavGtfsRtUrl: ApiConfigState.defaultMavUrl,
      isCustomBkkKey: false,
      isCustomMavUrl: false,
    );

    await TransitRustBridge.instance.initEngine(
      sqliteDbPath: '',
      bkkApiKey: ApiConfigState.defaultBkkKey,
      mavGtfsRtUrl: '',
    );
    ref.invalidate(liveVehiclesGeoJsonProvider);
  }
}

final apiConfigProvider =
    StateNotifierProvider<ApiConfigNotifier, ApiConfigState>((ref) {
  return ApiConfigNotifier(ref);
});
