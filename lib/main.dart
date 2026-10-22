import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bridge/bridge_generated.dart';
import 'providers/live_vehicles_provider.dart';
import 'views/map_screen.dart';

/// Prepares the local `transit_static.db` so the Rust `rusqlite` engine can open it.
Future<String> _ensureLocalStaticDatabase() async {
  // If running on desktop and assets/db/transit_static.db exists in working directory, use it directly
  final localDb = File('assets/db/transit_static.db');
  if (localDb.existsSync() && localDb.lengthSync() > 1000000) {
    return localDb.path;
  }

  final docDir = await getApplicationSupportDirectory();
  final dbFile = File(p.join(docDir.path, 'transit_static_v2.db'));

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

class HungaryTransitApp extends ConsumerWidget {
  const HungaryTransitApp({super.key});

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0077D4),
      brightness: brightness,
      surface: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: CardThemeData(
        elevation: isDark ? 4 : 2,
        color: isDark ? colorScheme.surfaceContainer : colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide.none,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(mapDarkModeProvider);

    return MaterialApp(
      title: 'Hungary Public Transport Tracker',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const MapScreen(),
    );
  }
}
