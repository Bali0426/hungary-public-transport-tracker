import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/bridge_generated.dart';
import 'views/map_screen.dart';

/// Prepares the local `transit_static.db` so the Rust `rusqlite` engine can open it.
Future<String> _ensureLocalStaticDatabase() async {
  // If running on desktop and assets/db/transit_static.db exists in working directory, use it directly
  final localDb = File('assets/db/transit_static.db');
  if (localDb.existsSync() && localDb.lengthSync() > 1000000) {
    return localDb.path;
  }

  final docDir = await getApplicationSupportDirectory();
  final dbFile = File(p.join(docDir.path, 'transit_static.db'));

  if (!dbFile.existsSync() || dbFile.lengthSync() < 1000000) {
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

  // Initialize DB and Rust native engine before running app so initial queries have static DB ready
  try {
    final dbPath = await _ensureLocalStaticDatabase();
    await TransitRustBridge.instance.initEngine(sqliteDbPath: dbPath);
    debugPrint('Transit Rust engine initialized successfully at $dbPath');
  } catch (e) {
    debugPrint('Warning: Rust engine init error: $e');
  }

  runApp(
    const ProviderScope(
      child: HungaryTransitApp(),
    ),
  );
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
