import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_date.dart';
import '../core/app_exception.dart';
import '../export/excel_exporter.dart';
import '../export/expense_export_data.dart';
import '../export/export_data.dart';
import '../export/production_export_data.dart';
import '../export/unsold_export_data.dart';
import 'expense_repository.dart';
import 'order_repository.dart';
import 'production_repository.dart';
import 'unsold_repository.dart';

/// The result of a successful export.
class ExportResult {
  const ExportResult({
    required this.file,
    required this.orderCount,
    required this.lineCount,
    required this.dayCount,
  });

  final File file;
  final int orderCount;
  final int lineCount;
  final int dayCount;

  String get fileName => p.basename(file.path);
}

/// The result of a successful expenses export.
class ExpenseExportResult {
  const ExpenseExportResult({
    required this.file,
    required this.expenseCount,
    required this.dayCount,
    required this.totalSpend,
  });

  final File file;
  final int expenseCount;
  final int dayCount;

  /// Whole RWF across the range, voided expenses excluded — the same figure
  /// the workbook's `TOTAL` row adds up to.
  final int totalSpend;

  String get fileName => p.basename(file.path);
}

/// The result of a successful production export.
class ProductionExportResult {
  const ProductionExportResult({
    required this.file,
    required this.rowCount,
    required this.dayCount,
    required this.totalValue,
  });

  final File file;

  /// Number of product lines exported.
  final int rowCount;

  final int dayCount;

  /// Whole RWF value of all produced units across the range.
  final int totalValue;

  String get fileName => p.basename(file.path);
}

/// The result of a successful unsold export.
class UnsoldExportResult {
  const UnsoldExportResult({
    required this.file,
    required this.rowCount,
    required this.dayCount,
    required this.totalValue,
  });

  final File file;

  /// Number of product lines exported.
  final int rowCount;

  final int dayCount;

  /// Whole RWF value of all unsold units across the range.
  final int totalValue;

  String get fileName => p.basename(file.path);
}

/// The result of a successful all-in-one export compiling sales, expenses,
/// production, and unsold data.
class AllExportResult {
  const AllExportResult({
    required this.file,
    required this.orderCount,
    required this.salesLineCount,
    required this.expenseCount,
    required this.productionRowCount,
    required this.unsoldRowCount,
    required this.dayCount,
  });

  final File file;
  final int orderCount;
  final int salesLineCount;
  final int expenseCount;
  final int productionRowCount;
  final int unsoldRowCount;
  final int dayCount;

  String get fileName => p.basename(file.path);
}

/// Pulls orders, expenses, production logs or unsold logs for a date range,
/// renders the workbook and writes it to disk.
class ExportRepository {
  ExportRepository(
    this._orders,
    this._expenses,
    this._production,
    this._unsold, {
    ExportDataBuilder builder = const ExportDataBuilder(),
    ExpenseExportBuilder expenseBuilder = const ExpenseExportBuilder(),
    ProductionExportBuilder productionBuilder = const ProductionExportBuilder(),
    UnsoldExportBuilder unsoldBuilder = const UnsoldExportBuilder(),
    ExcelExporter exporter = const ExcelExporter(),
    Directory? exportDirectoryOverride,
  })  : _builder = builder,
        _expenseBuilder = expenseBuilder,
        _productionBuilder = productionBuilder,
        _unsoldBuilder = unsoldBuilder,
        _exporter = exporter,
        _directoryOverride = exportDirectoryOverride;

  final OrderRepository _orders;
  final ExpenseRepository _expenses;
  final ProductionRepository _production;
  final UnsoldRepository _unsold;
  final ExportDataBuilder _builder;
  final ExpenseExportBuilder _expenseBuilder;
  final ProductionExportBuilder _productionBuilder;
  final UnsoldExportBuilder _unsoldBuilder;
  final ExcelExporter _exporter;
  final Directory? _directoryOverride;

  /// Exports [from]..[to] inclusive.
  ///
  /// Throws [NotFoundException] when the range holds no orders, so the UI can
  /// say "nothing to export" instead of handing over an empty file.
  Future<ExportResult> exportRange({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    final orders = await _orders.ordersInRange(from: from, to: to);
    if (orders.isEmpty) {
      throw const NotFoundException(
        'There are no sales in that date range yet.',
      );
    }

    final data = _builder.build(orders: orders, from: from, to: to);
    final bytes = _exporter.buildWorkbookBytes(data);

    final directory = directoryOverride ?? await _exportDirectory();
    final file = File(p.join(directory.path, _fileNameFor(from, to)));

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageException(
        'Could not write the export file. Check that the tablet has free '
        'storage space.',
        cause: error,
      );
    }

    return ExportResult(
      file: file,
      orderCount: orders.length,
      lineCount: data.salesLines.length,
      dayCount: data.daySummaries.length,
    );
  }

  /// Exports the expenses recorded in [from]..[to] inclusive.
  ///
  /// A separate workbook from the sales one, and deliberately so: the sales
  /// file's layout is fixed by the shop's downstream script, and adding sheets
  /// to it would put that script's input at risk for no gain.
  ///
  /// Throws [NotFoundException] when the range holds no expenses, so the UI
  /// can say "nothing to export" instead of handing over an empty file.
  Future<ExpenseExportResult> exportExpenseRange({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    final expenses = await _expenses.expensesInRange(from: from, to: to);
    if (expenses.isEmpty) {
      throw const NotFoundException(
        'There are no expenses in that date range yet.',
      );
    }

    final data = _expenseBuilder.build(expenses: expenses, from: from, to: to);
    final bytes = _exporter.buildExpenseWorkbookBytes(data);

    final directory = directoryOverride ?? await _exportDirectory();
    final file = File(
      p.join(directory.path, _expenseFileNameFor(from, to)),
    );

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageException(
        'Could not write the export file. Check that the tablet has free '
        'storage space.',
        cause: error,
      );
    }

    return ExpenseExportResult(
      file: file,
      expenseCount: expenses.length,
      dayCount: data.daySummaries.length,
      totalSpend: data.daySummaries
          .fold(0, (sum, summary) => sum + summary.totalSpend),
    );
  }

  /// Exports the production logs recorded in [from]..[to] inclusive.
  ///
  /// A separate workbook from the sales and expenses files, consistent with the
  /// principle that each kind of data ships in its own file so readers don't
  /// have to hunt across sheets for what they need.
  ///
  /// Throws [NotFoundException] when the range holds no logs.
  Future<ProductionExportResult> exportProductionRange({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    final logs = await _production.logsInRange(from: from, to: to);
    if (logs.isEmpty) {
      throw const NotFoundException(
        'There are no production records in that date range yet.',
      );
    }

    final data = _productionBuilder.build(logs: logs, from: from, to: to);
    final bytes = _exporter.buildProductionWorkbookBytes(data);

    final directory = directoryOverride ?? await _exportDirectory();
    final file = File(
      p.join(directory.path, _productionFileNameFor(from, to)),
    );

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageException(
        'Could not write the export file. Check that the tablet has free '
        'storage space.',
        cause: error,
      );
    }

    return ProductionExportResult(
      file: file,
      rowCount: data.lines.length,
      dayCount: data.daySummaries.length,
      totalValue: data.daySummaries.fold(
        0,
        (sum, summary) => sum + summary.totalValue,
      ),
    );
  }

  /// Exports the unsold logs recorded in [from]..[to] inclusive.
  ///
  /// Throws [NotFoundException] when the range holds no logs.
  Future<UnsoldExportResult> exportUnsoldRange({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    final logs = await _unsold.logsInRange(from: from, to: to);
    if (logs.isEmpty) {
      throw const NotFoundException(
        'There are no unsold records in that date range yet.',
      );
    }

    final data = _unsoldBuilder.build(logs: logs, from: from, to: to);
    final bytes = _exporter.buildUnsoldWorkbookBytes(data);

    final directory = directoryOverride ?? await _exportDirectory();
    final file = File(
      p.join(directory.path, _unsoldFileNameFor(from, to)),
    );

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageException(
        'Could not write the export file. Check that the tablet has free '
        'storage space.',
        cause: error,
      );
    }

    return UnsoldExportResult(
      file: file,
      rowCount: data.lines.length,
      dayCount: data.daySummaries.length,
      totalValue: data.daySummaries.fold(
        0,
        (sum, summary) => sum + summary.totalValue,
      ),
    );
  }

  /// Exports all records (sales, expenses, production, unsold) recorded in
  /// [from]..[to] inclusive into a single compiled workbook.
  ///
  /// Throws [NotFoundException] when the range holds no records in any category.
  Future<AllExportResult> exportAllRange({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    final orders = await _orders.ordersInRange(from: from, to: to);
    final expenses = await _expenses.expensesInRange(from: from, to: to);
    final productionLogs = await _production.logsInRange(from: from, to: to);
    final unsoldLogs = await _unsold.logsInRange(from: from, to: to);

    if (orders.isEmpty &&
        expenses.isEmpty &&
        productionLogs.isEmpty &&
        unsoldLogs.isEmpty) {
      throw const NotFoundException(
        'There are no records in that date range yet.',
      );
    }

    final salesData = _builder.build(orders: orders, from: from, to: to);
    final expenseData =
        _expenseBuilder.build(expenses: expenses, from: from, to: to);
    final productionData =
        _productionBuilder.build(logs: productionLogs, from: from, to: to);
    final unsoldData =
        _unsoldBuilder.build(logs: unsoldLogs, from: from, to: to);

    final bytes = _exporter.buildAllWorkbookBytes(
      sales: salesData,
      expenses: expenseData,
      production: productionData,
      unsold: unsoldData,
    );

    final directory = directoryOverride ?? await _exportDirectory();
    final file = File(p.join(directory.path, _allFileNameFor(from, to)));

    try {
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageException(
        'Could not write the export file. Check that the tablet has free '
        'storage space.',
        cause: error,
      );
    }

    return AllExportResult(
      file: file,
      orderCount: orders.length,
      salesLineCount: salesData.salesLines.length,
      expenseCount: expenses.length,
      productionRowCount: productionData.lines.length,
      unsoldRowCount: unsoldData.lines.length,
      dayCount: salesData.daySummaries.length,
    );
  }

  /// Where exports land on the tablet.
  ///
  /// Uses the app's external files directory on Android, which is reachable
  /// over USB from a laptop without root — that is how the shop moves the file
  /// to whoever runs the downstream script.
  Future<Directory> _exportDirectory() async {
    final override = _directoryOverride;
    if (override != null) return override;

    try {
      Directory? base;
      if (Platform.isAndroid) {
        final candidates = await getExternalStorageDirectories();
        base = (candidates != null && candidates.isNotEmpty)
            ? candidates.first
            : null;
      }
      base ??= await getApplicationDocumentsDirectory();
      return Directory(p.join(base.path, 'exports'));
    } on Object catch (error) {
      throw StorageException(
        'Could not find a place to save the export.',
        cause: error,
      );
    }
  }

  /// The file name that would be used for an all-in-one export across [from]..[to].
  String allFileName({required DateTime from, required DateTime to}) =>
      _allFileNameFor(from, to);

  /// The file name that would be used for a sales export across [from]..[to].
  String salesFileName({required DateTime from, required DateTime to}) =>
      _fileNameFor(from, to);

  /// The file name that would be used for an expense export across [from]..[to].
  String expenseFileName({required DateTime from, required DateTime to}) =>
      _expenseFileNameFor(from, to);

  /// The file name that would be used for a production export across [from]..[to].
  String productionFileName({required DateTime from, required DateTime to}) =>
      _productionFileNameFor(from, to);

  /// The file name that would be used for an unsold export across [from]..[to].
  String unsoldFileName({required DateTime from, required DateTime to}) =>
      _unsoldFileNameFor(from, to);

  /// Checks if a sales export file already exists on disk for [from]..[to].
  Future<File?> findExistingSalesExport({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    try {
      final directory = directoryOverride ?? await _exportDirectory();
      final file = File(p.join(directory.path, _fileNameFor(from, to)));
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks if an expense export file already exists on disk for [from]..[to].
  Future<File?> findExistingExpenseExport({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    try {
      final directory = directoryOverride ?? await _exportDirectory();
      final file = File(p.join(directory.path, _expenseFileNameFor(from, to)));
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks if a production export file already exists on disk for [from]..[to].
  Future<File?> findExistingProductionExport({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    try {
      final directory = directoryOverride ?? await _exportDirectory();
      final file =
          File(p.join(directory.path, _productionFileNameFor(from, to)));
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks if an unsold export file already exists on disk for [from]..[to].
  Future<File?> findExistingUnsoldExport({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    try {
      final directory = directoryOverride ?? await _exportDirectory();
      final file =
          File(p.join(directory.path, _unsoldFileNameFor(from, to)));
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks if an all-in-one export file already exists on disk for [from]..[to].
  Future<File?> findExistingAllExport({
    required DateTime from,
    required DateTime to,
    Directory? directoryOverride,
  }) async {
    try {
      final directory = directoryOverride ?? await _exportDirectory();
      final file = File(p.join(directory.path, _allFileNameFor(from, to)));
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Lists `.xlsx` files currently saved in the exports directory, newest first.
  Future<List<File>> listRecentExports({
    Directory? directoryOverride,
    int limit = 10,
  }) async {
    try {
      final directory = directoryOverride ?? await _exportDirectory();
      if (!await directory.exists()) return const [];
      final entities = await directory.list().toList();
      final files = entities
          .whereType<File>()
          .where((f) => f.path.endsWith('.xlsx'))
          .toList();
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return b.path.compareTo(a.path);
        }
      });
      return files.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  /// `pastry_all_YYYY-MM-DD.xlsx`. Sorts alongside sales, expenses, production and unsold.
  String _allFileNameFor(DateTime from, DateTime to) =>
      _rangeFileName('pastry_all', from, to);

  /// Mirrors the legacy naming: `pastry_sales_YYYY-MM-DD.xlsx` for one day,
  /// `pastry_sales_YYYY-MM-DD_to_YYYY-MM-DD.xlsx` for a range.
  String _fileNameFor(DateTime from, DateTime to) =>
      _rangeFileName('pastry_sales', from, to);

  /// The same naming, one word along: `pastry_expenses_YYYY-MM-DD.xlsx`. The
  /// two files sort next to each other in the tablet's export folder.
  String _expenseFileNameFor(DateTime from, DateTime to) =>
      _rangeFileName('pastry_expenses', from, to);

  /// `pastry_production_YYYY-MM-DD.xlsx`. Sorts alongside sales and expenses.
  String _productionFileNameFor(DateTime from, DateTime to) =>
      _rangeFileName('pastry_production', from, to);

  /// `pastry_unsold_YYYY-MM-DD.xlsx`. Sorts alongside sales, expenses and production.
  String _unsoldFileNameFor(DateTime from, DateTime to) =>
      _rangeFileName('pastry_unsold', from, to);

  String _rangeFileName(String prefix, DateTime from, DateTime to) {
    final fromIso = formatIsoDate(from);
    final toIso = formatIsoDate(to);
    return fromIso == toIso
        ? '${prefix}_$fromIso.xlsx'
        : '${prefix}_${fromIso}_to_$toIso.xlsx';
  }
}
