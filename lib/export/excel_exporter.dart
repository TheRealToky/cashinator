import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../core/app_exception.dart';
import 'export_data.dart';
import 'export_format.dart';
import 'expense_export_data.dart';
import 'expense_export_format.dart';
import 'production_export_data.dart';
import 'production_export_format.dart';
import 'unsold_export_data.dart';
import 'unsold_export_format.dart';

/// Writes an export out as `.xlsx`: [ExportWorkbookData] in the legacy sales
/// layout, or [ExpenseWorkbookData] in the expenses layout.
///
/// This class does no aggregation — [ExportDataBuilder] and
/// [ExpenseExportBuilder] decided every value. All that happens here is
/// placement and formatting, which is why both workbooks share one writer.
class ExcelExporter {
  const ExcelExporter();

  /// Renders the workbook and returns its bytes.
  List<int> buildWorkbookBytes(ExportWorkbookData data) {
    final workbook = Workbook();
    try {
      final salesSheet = workbook.worksheets[0];
      salesSheet.name = kSalesLinesSheetName;
      _writeSalesLines(salesSheet, data);

      final summarySheet = workbook.worksheets.addWithName(kDaySummarySheetName);
      _writeDaySummary(summarySheet, data);

      return _normaliseFormulaBytes(workbook.saveAsStream());
    } on Object catch (error) {
      throw StorageException(
        'Could not generate the Excel file.',
        cause: error,
      );
    } finally {
      // xlsio holds native-ish buffers; not disposing leaks them for the life
      // of the process, and this runs on a tablet that stays open all day.
      workbook.dispose();
    }
  }

  /// Renders the expenses workbook and returns its bytes.
  ///
  /// A file of its own rather than a third sheet in the sales workbook: the
  /// shop's downstream script parses that file, and a sale and an expense are
  /// two different kinds of money that should not have to be told apart by a
  /// reader who opened the wrong tab.
  List<int> buildExpenseWorkbookBytes(ExpenseWorkbookData data) {
    final workbook = Workbook();
    try {
      final expensesSheet = workbook.worksheets[0];
      expensesSheet.name = kExpensesSheetName;
      _writeExpenses(expensesSheet, data);

      final summarySheet =
          workbook.worksheets.addWithName(kExpenseDaySummarySheetName);
      _writeExpenseDaySummary(summarySheet, data);

      return _normaliseFormulaBytes(workbook.saveAsStream());
    } on Object catch (error) {
      throw StorageException(
        'Could not generate the Excel file.',
        cause: error,
      );
    } finally {
      workbook.dispose();
    }
  }

  /// Renders the production workbook and returns its bytes.
  ///
  /// Two sheets: a `Production Lines` detail sheet (one row per product per
  /// session) and a `Day Summary` sheet (one row per business day). Same
  /// shape as the expenses workbook so whoever reads both each month is reading
  /// the same structure twice.
  List<int> buildProductionWorkbookBytes(ProductionWorkbookData data) {
    final workbook = Workbook();
    try {
      final linesSheet = workbook.worksheets[0];
      linesSheet.name = kProductionLinesSheetName;
      _writeProductionLines(linesSheet, data);

      final summarySheet =
          workbook.worksheets.addWithName(kProductionDaySummarySheetName);
      _writeProductionDaySummary(summarySheet, data);

      return _normaliseFormulaBytes(workbook.saveAsStream());
    } on Object catch (error) {
      throw StorageException(
        'Could not generate the Excel file.',
        cause: error,
      );
    } finally {
      workbook.dispose();
    }
  }

  /// Renders the unsold workbook and returns its bytes.
  ///
  /// Two sheets: an `Unsold Lines` detail sheet and a `Day Summary` sheet.
  List<int> buildUnsoldWorkbookBytes(UnsoldWorkbookData data) {
    final workbook = Workbook();
    try {
      final linesSheet = workbook.worksheets[0];
      linesSheet.name = kUnsoldLinesSheetName;
      _writeUnsoldLines(linesSheet, data);

      final summarySheet =
          workbook.worksheets.addWithName(kUnsoldDaySummarySheetName);
      _writeUnsoldDaySummary(summarySheet, data);

      return _normaliseFormulaBytes(workbook.saveAsStream());
    } on Object catch (error) {
      throw StorageException(
        'Could not generate the Excel file.',
        cause: error,
      );
    } finally {
      workbook.dispose();
    }
  }

  /// Renders a single workbook compiling all four datasets (sales, expenses,
  /// production, unsold) across the date range.
  ///
  /// Each dataset gets its own detail and summary sheets with distinct names,
  /// preserving the column formats and summary calculations of each domain.
  List<int> buildAllWorkbookBytes({
    required ExportWorkbookData sales,
    required ExpenseWorkbookData expenses,
    required ProductionWorkbookData production,
    required UnsoldWorkbookData unsold,
  }) {
    final workbook = Workbook();
    try {
      final salesSheet = workbook.worksheets[0];
      salesSheet.name = kAllSalesLinesSheetName;
      _writeSalesLines(salesSheet, sales);

      final salesSummarySheet =
          workbook.worksheets.addWithName(kAllSalesSummarySheetName);
      _writeDaySummary(salesSummarySheet, sales);

      final expensesSheet =
          workbook.worksheets.addWithName(kAllExpensesSheetName);
      _writeExpenses(expensesSheet, expenses);

      final expenseSummarySheet =
          workbook.worksheets.addWithName(kAllExpensesSummarySheetName);
      _writeExpenseDaySummary(expenseSummarySheet, expenses);

      final productionSheet =
          workbook.worksheets.addWithName(kAllProductionLinesSheetName);
      _writeProductionLines(productionSheet, production);

      final productionSummarySheet =
          workbook.worksheets.addWithName(kAllProductionSummarySheetName);
      _writeProductionDaySummary(productionSummarySheet, production);

      final unsoldSheet =
          workbook.worksheets.addWithName(kAllUnsoldLinesSheetName);
      _writeUnsoldLines(unsoldSheet, unsold);

      final unsoldSummarySheet =
          workbook.worksheets.addWithName(kAllUnsoldSummarySheetName);
      _writeUnsoldDaySummary(unsoldSummarySheet, unsold);

      return _normaliseFormulaBytes(workbook.saveAsStream());
    } on Object catch (error) {
      throw StorageException(
        'Could not generate the Excel file.',
        cause: error,
      );
    } finally {
      workbook.dispose();
    }
  }

  /// Removes the non-standard leading `=` xlsio writes inside worksheet `<f>`

  /// formula elements.
  ///
  /// OOXML stores a formula without its leading equals sign — the reference
  /// ledger export contains `<f>SUM(B2:B6)</f>`. xlsio 30.x instead writes
  /// `<f>=SUM(...)</f>`, which openpyxl-based readers (the shop's downstream
  /// script is one) surface doubled as `==SUM(...)`, and which some strict
  /// readers reject outright. Neither xlsio API (`setFormula`, the `formula`
  /// setter) avoids it, so the saved zip is patched here: every worksheet part
  /// has `<f>=` rewritten to `<f>`. Nothing else in the archive is touched.
  ///
  /// If the archive can't be parsed for any reason, the original bytes are
  /// returned rather than failing the whole export — a doubled formula is a
  /// cosmetic defect in one footer row, not worth losing the file over.
  static List<int> _normaliseFormulaBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final pattern = RegExp(r'(<f[^>]*>)=');
      var changed = false;

      final rebuilt = Archive();
      for (final file in archive.files) {
        final isWorksheet = file.isFile &&
            file.name.startsWith('xl/worksheets/') &&
            file.name.endsWith('.xml');

        if (isWorksheet) {
          final xml = utf8.decode(file.content as List<int>);
          final fixed = xml.replaceAllMapped(pattern, (m) => m.group(1)!);
          if (fixed != xml) changed = true;
          final data = utf8.encode(fixed);
          rebuilt.addFile(ArchiveFile(file.name, data.length, data));
        } else {
          rebuilt.addFile(file);
        }
      }

      if (!changed) return bytes;
      return ZipEncoder().encode(rebuilt);
    } on Object {
      return bytes;
    }
  }

  void _writeSalesLines(Worksheet sheet, ExportWorkbookData data) {
    for (var column = 0; column < kSalesLinesHeader.length; column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(kSalesLinesHeader[column]);
      _styleHeaderCell(cell);
      sheet.getRangeByIndex(1, column + 1).columnWidth =
          kSalesLinesColumnWidths[column];
    }

    var row = 2;
    for (final line in data.salesLines) {
      final cells = line.toCells();
      for (var column = 0; column < cells.length; column++) {
        _writeCell(sheet.getRangeByIndex(row, column + 1), cells[column]);
      }
      row++;
    }

    // Header stays visible while scrolling a long day, and the filter row lets
    // management sort by product or status without touching the data.
    sheet.getRangeByName('A2').freezePanes();
    sheet.autoFilters.filterRange = sheet.getRangeByName(
      'A1:${_columnLetter(kSalesLinesHeader.length)}1',
    );
  }

  void _writeDaySummary(Worksheet sheet, ExportWorkbookData data) {
    final header = data.daySummaryHeader;

    for (var column = 0; column < header.length; column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(header[column]);
      _styleHeaderCell(cell);
    }

    // Widths from the reference workbook for the fixed columns; payment columns
    // reuse its MoMo/Card width, and the trailing column its 22.
    sheet.getRangeByIndex(1, 1).columnWidth = 13;
    sheet.getRangeByIndex(1, 2).columnWidth = 9;
    sheet.getRangeByIndex(1, 3).columnWidth = 8;
    sheet.getRangeByIndex(1, 4).columnWidth = 18;
    for (var i = 0; i < data.paymentColumns.length; i++) {
      sheet.getRangeByIndex(1, kDaySummaryLeadingHeader.length + 1 + i)
          .columnWidth = 12;
    }
    sheet.getRangeByIndex(1, header.length).columnWidth = 22;

    var row = 2;
    for (final summary in data.daySummaries) {
      final cells = summary.toCells(data.paymentColumns);
      for (var column = 0; column < cells.length; column++) {
        final cell = sheet.getRangeByIndex(row, column + 1);
        _writeCell(cell, cells[column]);
        cell.cellStyle.backColor = kSummaryRowBackColor;
        cell.cellStyle.hAlign = HAlignType.center;
        cell.cellStyle.fontSize = kBodyFontSize;
      }
      row++;
    }

    _writeTotalRow(sheet, header.length, data.daySummaries.length);

    sheet.getRangeByName('A2').freezePanes();
  }

  /// The bold `TOTAL` row of `SUM()` formulas over the day rows.
  ///
  /// Formulas rather than computed values, matching the reference workbook —
  /// management edits these files by hand and expects the total to follow.
  void _writeTotalRow(Worksheet sheet, int columnCount, int dayCount) {
    final totalRow = dayCount + 2;
    final firstDataRow = 2;
    final lastDataRow = dayCount + 1;

    final labelCell = sheet.getRangeByIndex(totalRow, 1);
    labelCell.setText(kTotalRowLabel);
    labelCell.cellStyle.bold = true;
    labelCell.cellStyle.fontSize = kBodyFontSize;

    for (var column = 2; column <= columnCount; column++) {
      final letter = _columnLetter(column);
      final cell = sheet.getRangeByIndex(totalRow, column);

      if (dayCount == 0) {
        // An empty range would produce `=SUM(B2:B1)`, which Excel rejects.
        cell.setNumber(0);
      } else {
        // The leading '=' xlsio bakes into the <f> element is stripped later
        // by _normaliseFormulaBytes; see that method for why.
        cell.formula = '=SUM($letter$firstDataRow:$letter$lastDataRow)';
      }

      cell.cellStyle.bold = true;
      cell.cellStyle.fontSize = kBodyFontSize;
    }
  }

  void _writeExpenses(Worksheet sheet, ExpenseWorkbookData data) {
    for (var column = 0; column < kExpensesHeader.length; column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(kExpensesHeader[column]);
      _styleHeaderCell(cell);
      sheet.getRangeByIndex(1, column + 1).columnWidth =
          kExpensesColumnWidths[column];
    }

    var row = 2;
    for (final expense in data.expenses) {
      final cells = expense.toCells();
      for (var column = 0; column < cells.length; column++) {
        _writeCell(sheet.getRangeByIndex(row, column + 1), cells[column]);
      }
      row++;
    }

    sheet.getRangeByName('A2').freezePanes();
    sheet.autoFilters.filterRange = sheet.getRangeByName(
      'A1:${_columnLetter(kExpensesHeader.length)}1',
    );
  }

  void _writeExpenseDaySummary(Worksheet sheet, ExpenseWorkbookData data) {
    final header = data.daySummaryHeader;

    for (var column = 0; column < header.length; column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(header[column]);
      _styleHeaderCell(cell);
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 13;
    sheet.getRangeByIndex(1, 2).columnWidth = 11;
    sheet.getRangeByIndex(1, 3).columnWidth = 19;
    for (var i = 0; i < data.paymentColumns.length; i++) {
      sheet
          .getRangeByIndex(
            1,
            kExpenseDaySummaryLeadingHeader.length + 1 + i,
          )
          .columnWidth = 12;
    }

    var row = 2;
    for (final summary in data.daySummaries) {
      final cells = summary.toCells(data.paymentColumns);
      for (var column = 0; column < cells.length; column++) {
        final cell = sheet.getRangeByIndex(row, column + 1);
        _writeCell(cell, cells[column]);
        cell.cellStyle.backColor = kSummaryRowBackColor;
        cell.cellStyle.hAlign = HAlignType.center;
        cell.cellStyle.fontSize = kBodyFontSize;
      }
      row++;
    }

    _writeTotalRow(sheet, header.length, data.daySummaries.length);

    sheet.getRangeByName('A2').freezePanes();
  }

  void _writeProductionLines(Worksheet sheet, ProductionWorkbookData data) {
    for (var column = 0;
        column < kProductionLinesHeader.length;
        column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(kProductionLinesHeader[column]);
      _styleHeaderCell(cell);
      sheet.getRangeByIndex(1, column + 1).columnWidth =
          kProductionLinesColumnWidths[column];
    }

    var row = 2;
    for (final line in data.lines) {
      final cells = line.toCells();
      for (var column = 0; column < cells.length; column++) {
        _writeCell(sheet.getRangeByIndex(row, column + 1), cells[column]);
      }
      row++;
    }

    sheet.getRangeByName('A2').freezePanes();
    sheet.autoFilters.filterRange = sheet.getRangeByName(
      'A1:${_columnLetter(kProductionLinesHeader.length)}1',
    );
  }

  void _writeProductionDaySummary(
      Worksheet sheet, ProductionWorkbookData data) {
    for (var column = 0;
        column < kProductionDaySummaryHeader.length;
        column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(kProductionDaySummaryHeader[column]);
      _styleHeaderCell(cell);
    }

    // Column widths matching the header constants.
    sheet.getRangeByIndex(1, 1).columnWidth = 13;
    sheet.getRangeByIndex(1, 2).columnWidth = 18;
    sheet.getRangeByIndex(1, 3).columnWidth = 11;
    sheet.getRangeByIndex(1, 4).columnWidth = 18;

    var row = 2;
    for (final summary in data.daySummaries) {
      final cells = summary.toCells();
      for (var column = 0; column < cells.length; column++) {
        final cell = sheet.getRangeByIndex(row, column + 1);
        _writeCell(cell, cells[column]);
        cell.cellStyle.backColor = kSummaryRowBackColor;
        cell.cellStyle.hAlign = HAlignType.center;
        cell.cellStyle.fontSize = kBodyFontSize;
      }
      row++;
    }

    _writeTotalRow(
        sheet, kProductionDaySummaryHeader.length, data.daySummaries.length);

    sheet.getRangeByName('A2').freezePanes();
  }

  void _writeUnsoldLines(Worksheet sheet, UnsoldWorkbookData data) {
    for (var column = 0; column < kUnsoldLinesHeader.length; column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(kUnsoldLinesHeader[column]);
      _styleHeaderCell(cell);
      sheet.getRangeByIndex(1, column + 1).columnWidth =
          kUnsoldLinesColumnWidths[column];
    }

    var row = 2;
    for (final line in data.lines) {
      final cells = line.toCells();
      for (var column = 0; column < cells.length; column++) {
        _writeCell(sheet.getRangeByIndex(row, column + 1), cells[column]);
      }
      row++;
    }

    sheet.getRangeByName('A2').freezePanes();
    sheet.autoFilters.filterRange = sheet.getRangeByName(
      'A1:${_columnLetter(kUnsoldLinesHeader.length)}1',
    );
  }

  void _writeUnsoldDaySummary(Worksheet sheet, UnsoldWorkbookData data) {
    for (var column = 0;
        column < kUnsoldDaySummaryHeader.length;
        column++) {
      final cell = sheet.getRangeByIndex(1, column + 1);
      cell.setText(kUnsoldDaySummaryHeader[column]);
      _styleHeaderCell(cell);
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 13;
    sheet.getRangeByIndex(1, 2).columnWidth = 18;
    sheet.getRangeByIndex(1, 3).columnWidth = 11;
    sheet.getRangeByIndex(1, 4).columnWidth = 18;

    var row = 2;
    for (final summary in data.daySummaries) {
      final cells = summary.toCells();
      for (var column = 0; column < cells.length; column++) {
        final cell = sheet.getRangeByIndex(row, column + 1);
        _writeCell(cell, cells[column]);
        cell.cellStyle.backColor = kSummaryRowBackColor;
        cell.cellStyle.hAlign = HAlignType.center;
        cell.cellStyle.fontSize = kBodyFontSize;
      }
      row++;
    }

    _writeTotalRow(
        sheet, kUnsoldDaySummaryHeader.length, data.daySummaries.length);

    sheet.getRangeByName('A2').freezePanes();
  }

  void _writeCell(Range cell, Object? value) {
    switch (value) {
      case final int number:
        cell.setNumber(number.toDouble());
        // RWF has no subunit; the ledger has always shown bare integers.
        cell.numberFormat = '0';
      case final String text:
        // setText keeps `Order Label` and `Time` as text. Without it, xlsio
        // would coerce "07:31" into a time serial and "1" into a number,
        // changing the types the downstream script reads.
        cell.setText(text);
      case null:
        cell.setText('');
      default:
        cell.setText(value.toString());
    }
    cell.cellStyle.fontSize = kBodyFontSize;
  }

  void _styleHeaderCell(Range cell) {
    cell.cellStyle
      ..bold = true
      ..fontSize = kBodyFontSize
      ..backColor = kHeaderBackColor
      ..fontColor = kHeaderFontColor
      ..hAlign = HAlignType.center;
  }

  /// 1 -> A, 26 -> Z, 27 -> AA.
  static String _columnLetter(int index) {
    var remaining = index;
    final buffer = StringBuffer();
    while (remaining > 0) {
      final rem = (remaining - 1) % 26;
      buffer.write(String.fromCharCode(65 + rem));
      remaining = (remaining - 1) ~/ 26;
    }
    return String.fromCharCodes(buffer.toString().codeUnits.reversed);
  }
}
