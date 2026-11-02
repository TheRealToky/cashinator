import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cashinator/core/app_date.dart';
import 'package:cashinator/data/models/order.dart';
import 'package:cashinator/export/excel_exporter.dart';
import 'package:cashinator/export/expense_export_data.dart';
import 'package:cashinator/export/export_data.dart';
import 'package:cashinator/export/export_format.dart';
import 'package:cashinator/export/production_export_data.dart';
import 'package:cashinator/export/unsold_export_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'export_data_test.dart' show makeOrder;

/// Writes a real `.xlsx` so the file can be opened and diffed against the
/// shop's existing exports.
///
/// The bytes are checked here for the things Dart can see cheaply; the
/// structural comparison against `pastry_sales_2026-06-19.xlsx` is done by
/// `tool/verify_export.py`, which reads this file back with openpyxl.
void main() {
  const builder = ExportDataBuilder();
  const exporter = ExcelExporter();
  final day = parseIsoDate('2026-07-20')!;

  ExportWorkbookData sampleData() => builder.build(
        orders: [
          makeOrder(
            id: 1,
            date: '2026-07-20',
            paymentMethod: 'MoMo',
            lines: [('Chicken Sandwich', 1, 7500), ('Chicken Bread', 1, 5000)],
            hour: 7,
            minute: 31,
          ),
          makeOrder(
            id: 2,
            date: '2026-07-20',
            paymentMethod: 'Cash',
            lines: [('Croissant', 2, 3000)],
            hour: 8,
            minute: 43,
          ),
          makeOrder(
            id: 3,
            date: '2026-07-20',
            paymentMethod: 'Card',
            lines: [('Cappuccino', 1, 3500), ('Takeaway', 1, 500)],
            hour: 8,
            minute: 39,
          ),
          makeOrder(
            id: 4,
            date: '2026-07-21',
            paymentMethod: 'MoMo',
            lines: [('Muffin', 3, 2000)],
            hour: 9,
            minute: 15,
          ),
          makeOrder(
            id: 5,
            date: '2026-07-21',
            paymentMethod: 'CEVR',
            lines: [('Pain Suisse', 1, 3000)],
            hour: 10,
            minute: 0,
            status: OrderStatus.voided,
            voidReason: 'Unusual entry — possible cash exchange',
          ),
        ],
        from: day,
        to: parseIsoDate('2026-07-21')!,
      );

  test('produces a non-trivial xlsx file', () {
    final bytes = exporter.buildWorkbookBytes(sampleData());

    expect(bytes, isNotEmpty);
    // xlsx is a zip: "PK\x03\x04".
    expect(bytes.take(4).toList(), [0x50, 0x4B, 0x03, 0x04]);
  });

  test('writes the workbook to disk for structural verification', () async {
    final data = sampleData();
    final bytes = exporter.buildWorkbookBytes(data);

    final outputDir = Directory('build/test_exports');
    await outputDir.create(recursive: true);
    final file = File('${outputDir.path}/sample_export.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(2000));

    // Recorded alongside the file so the Python check knows what to expect
    // without duplicating the layout rules.
    final manifest = File('${outputDir.path}/sample_export.expected.txt');
    await manifest.writeAsString([
      'sales_line_count=${data.salesLines.length}',
      'day_count=${data.daySummaries.length}',
      'payment_columns=${data.paymentColumns.join(",")}',
      'day_summary_header=${data.daySummaryHeader.join(",")}',
    ].join('\n'));
  });

  test('writes conformant formula elements, not xlsio\'s doubled "=="', () {
    // Regression guard: xlsio bakes a leading '=' into every <f> element, which
    // openpyxl-based readers surface as `==SUM(...)`. The exporter strips it so
    // the file matches the legacy `<f>SUM(...)</f>` shape.
    final bytes = exporter.buildWorkbookBytes(sampleData());
    final archive = ZipDecoder().decodeBytes(bytes);

    var formulaCount = 0;
    for (final file in archive.files) {
      if (!file.name.startsWith('xl/worksheets/') ||
          !file.name.endsWith('.xml')) {
        continue;
      }
      final xml = utf8.decode(file.content as List<int>);
      for (final match in RegExp(r'<f[^>]*>(.*?)</f>').allMatches(xml)) {
        formulaCount++;
        final formula = match.group(1)!;
        expect(
          formula.startsWith('='),
          isFalse,
          reason: 'the <f> element must not carry a leading "=" ($formula)',
        );
        expect(formula, startsWith('SUM('));
      }
    }

    expect(formulaCount, greaterThan(0),
        reason: 'the TOTAL row should contribute SUM formulas');
  });

  test('an empty day range still yields a valid workbook', () {
    final empty = builder.build(orders: const [], from: day, to: day);
    final bytes = exporter.buildWorkbookBytes(empty);

    expect(bytes, isNotEmpty);
    expect(empty.daySummaries, isEmpty);
    expect(empty.isEmpty, isTrue);
  });

  test('buildAllWorkbookBytes produces a workbook with all 8 sheets and valid zip', () {
    const expenseBuilder = ExpenseExportBuilder();
    const productionBuilder = ProductionExportBuilder();
    const unsoldBuilder = UnsoldExportBuilder();

    final salesData = sampleData();
    final expenseData = expenseBuilder.build(expenses: const [], from: day, to: day);
    final productionData = productionBuilder.build(logs: const [], from: day, to: day);
    final unsoldData = unsoldBuilder.build(logs: const [], from: day, to: day);

    final bytes = exporter.buildAllWorkbookBytes(
      sales: salesData,
      expenses: expenseData,
      production: productionData,
      unsold: unsoldData,
    );

    expect(bytes, isNotEmpty);
    expect(bytes.take(4).toList(), [0x50, 0x4B, 0x03, 0x04]);

    final archive = ZipDecoder().decodeBytes(bytes);
    final workbookXmlFile = archive.files.firstWhere((f) => f.name == 'xl/workbook.xml');
    final xml = utf8.decode(workbookXmlFile.content as List<int>);

    expect(xml, contains('name="$kAllSalesLinesSheetName"'));
    expect(xml, contains('name="$kAllSalesSummarySheetName"'));
    expect(xml, contains('name="$kAllExpensesSheetName"'));
    expect(xml, contains('name="$kAllExpensesSummarySheetName"'));
    expect(xml, contains('name="$kAllProductionLinesSheetName"'));
    expect(xml, contains('name="$kAllProductionSummarySheetName"'));
    expect(xml, contains('name="$kAllUnsoldLinesSheetName"'));
    expect(xml, contains('name="$kAllUnsoldSummarySheetName"'));
  });
}

