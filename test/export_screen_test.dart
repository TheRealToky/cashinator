import 'dart:io';

import 'package:cashinator/data/db/app_database.dart';
import 'package:cashinator/repositories/expense_repository.dart';
import 'package:cashinator/repositories/export_repository.dart';
import 'package:cashinator/repositories/order_repository.dart';
import 'package:cashinator/repositories/production_repository.dart';
import 'package:cashinator/repositories/unsold_repository.dart';
import 'package:cashinator/ui/backoffice/export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late AppDatabase database;
  late OrderRepository orders;
  late ExpenseRepository expenses;
  late ProductionRepository production;
  late UnsoldRepository unsold;
  late ExportRepository exportRepo;
  late Directory tempDir;

  setUp(() async {
    database = await AppDatabase.open(fileName: inMemoryDatabasePath);
    orders = OrderRepository(database);
    expenses = ExpenseRepository(database);
    production = ProductionRepository(database);
    unsold = UnsoldRepository(database);
    tempDir = await Directory.systemTemp.createTemp('cashinator_screen_test_');
    exportRepo = ExportRepository(
      orders,
      expenses,
      production,
      unsold,
      exportDirectoryOverride: tempDir,
    );
  });

  tearDown(() async {
    await database.close();
    tempDir.delete(recursive: true).ignore();
  });

  Widget buildScreen({ExportRepository? repo}) {
    return MultiProvider(
      providers: [
        Provider<OrderRepository>.value(value: orders),
        Provider<ExpenseRepository>.value(value: expenses),
        Provider<ProductionRepository>.value(value: production),
        Provider<UnsoldRepository>.value(value: unsold),
        Provider<ExportRepository>.value(value: repo ?? exportRepo),
      ],
      child: const MaterialApp(
        home: ExportScreen(),
      ),
    );
  }

  testWidgets('renders ExportScreen with export buttons', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Excel export'), findsOneWidget);
    expect(find.text('Export all'), findsOneWidget);
    expect(find.text('Sales Excel file'), findsOneWidget);
    expect(find.text('Expenses Excel file'), findsOneWidget);
    expect(find.text('Production Excel file'), findsOneWidget);
    expect(find.text('Unsold Excel file'), findsOneWidget);
  });

  testWidgets('shows share button when existing export file is found',
      (tester) async {
    final today = DateTime.now();
    final todayIso =
        "${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final existingFile =
        File(p.join(tempDir.path, 'pastry_sales_$todayIso.xlsx'));
    existingFile.writeAsStringSync('test content');

    await tester.pumpWidget(buildScreen());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Date range'), findsOneWidget);
    expect(find.text('Sales export already saved on device'), findsOneWidget);
    expect(find.text('Share file (WhatsApp, Xender, …)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows share button when existing export all file is found',
      (tester) async {
    final today = DateTime.now();
    final todayIso =
        "${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final existingFile =
        File(p.join(tempDir.path, 'pastry_all_$todayIso.xlsx'));
    existingFile.writeAsStringSync('test content');

    await tester.pumpWidget(buildScreen());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Date range'), findsOneWidget);
    expect(find.text('Export all already saved on device'), findsOneWidget);
    expect(find.text('Share file (WhatsApp, Xender, …)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}


