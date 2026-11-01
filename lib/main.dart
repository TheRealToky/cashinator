import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/app_exception.dart';
import 'data/db/app_database.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // The Tab S9 sits in a landscape stand at the counter. Locking the
  // orientation keeps the grid/cart split stable when staff knock the tablet.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  try {
    final database = await AppDatabase.open();
    runApp(CashinatorApp(database: database));
  } on AppException catch (error) {
    // Without a database there is no app, so show why rather than a blank
    // screen or a crash dialog the shop cannot interpret.
    runApp(_StartupFailureApp(message: error.message));
  }
}

/// Shown only when the database could not be opened at launch.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cashinator',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Cashinator could not start',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
