import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/bridge_generated.dart';
import 'views/map_screen.dart';

/// Extracts the bundled `assets/db/transit_static.db` to local application storage
/// on first boot so the Rust `rusqlite` engine can open it with an `r2d2` connection pool.
Future<String> _ensureLocalStaticDatabase() async {
  final docDir = await getApplicationSupportDirectory();
  final dbFile = File(p.join(docDir.path, 'transit_static.db'));

  if (!dbFile.existsSync()) {
    await dbFile.parent.create(recursive: true);
    final byteData = await rootBundle.load('assets/db/transit_static.db');
    await dbFile.writeAsBytes(
      byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      ),
      flush: true,
    );
  }
  return dbFile.path;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    const ProviderScope(
      child: HungaryTransitApp(),
    ),
  );

  // Initialize DB and Rust native engine in background so first frame renders immediately
  unawaited(() async {
    const dartDefineBkkKey = String.fromEnvironment('BKK_API_KEY');
    const dartDefineMavUrl = String.fromEnvironment('MAV_GTFS_RT_URL');

    final bkkApiKey = dartDefineBkkKey.isNotEmpty
        ? dartDefineBkkKey
        : Platform.environment['BKK_API_KEY'];
    final mavGtfsRtUrl = dartDefineMavUrl.isNotEmpty
        ? dartDefineMavUrl
        : Platform.environment['MAV_GTFS_RT_URL'];

    try {
      final dbPath = await _ensureLocalStaticDatabase();
      await TransitRustBridge.instance.initEngine(
        sqliteDbPath: dbPath,
        bkkApiKey: bkkApiKey,
        mavGtfsRtUrl: mavGtfsRtUrl,
      );
      debugPrint('Transit Rust engine initialized successfully at $dbPath');
    } catch (e) {
      debugPrint('Warning: Rust engine init error: $e');
    }
  }());
}

class HungaryTransitApp extends StatelessWidget {
  const HungaryTransitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hungary Public Transport Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF009EE3),
          brightness: Brightness.dark,
        ),
      ),
      home: const MapScreen(),
    );
  }
}
