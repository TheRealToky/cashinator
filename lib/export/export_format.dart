/// Constants describing the legacy Excel layout.
///
/// The shop's downstream automation script was written against OCR'd paper
/// ledgers and parses these sheets by column position. Every value here was
/// read back off the reference workbook
/// (`pastry_sales_2026-06-19.xlsx`) rather than invented, so treat changes to
/// this file as a breaking change to that script.
library;

/// Sheet names, exactly as the reference workbook spells them.
const String kSalesLinesSheetName = 'Sales Lines';
const String kDaySummarySheetName = 'Day Summary';

/// Sheet names used when compiling all four exports into one single workbook.
const String kAllSalesLinesSheetName = 'Sales Lines';
const String kAllSalesSummarySheetName = 'Sales Day Summary';
const String kAllExpensesSheetName = 'Expenses';
const String kAllExpensesSummarySheetName = 'Expenses Day Summary';
const String kAllProductionLinesSheetName = 'Production Lines';
const String kAllProductionSummarySheetName = 'Production Day Summary';
const String kAllUnsoldLinesSheetName = 'Unsold Lines';
const String kAllUnsoldSummarySheetName = 'Unsold Day Summary';


/// `Sales Lines` header, in order. All 22 sample exports agree on this row.
const List<String> kSalesLinesHeader = [
  'Line Id',
  'Order Id',
  'Order Label',
  'Product Name',
  'Qty',
  'Payment Method',
  'Time',
  'Date',
  'Source Image',
  'Total Price',
  'Status',
  'Confidence',
  'Notes',
];

/// Column widths from the reference workbook, `Sales Lines`, columns A–M.
const List<double> kSalesLinesColumnWidths = [
  8, 9, 11, 24, 6, 15, 8, 12, 11, 13, 10, 11, 40,
];

/// Fixed part of the `Day Summary` header, before the payment columns.
const List<String> kDaySummaryLeadingHeader = [
  'Source Image',
  'Orders',
  'Lines',
  'Total Sales (RWF)',
];

/// Fixed part after the payment columns.
const List<String> kDaySummaryTrailingHeader = ['Low Confidence Lines'];

/// Payment columns the reference workbook always carries, in its order.
///
/// These are emitted whether or not the exported range contains sales on them,
/// so a normal export is byte-identical to the legacy layout. Any additional
/// method used in the range is appended after these, before the trailing
/// `Low Confidence Lines` column.
const List<String> kBaselinePaymentColumns = ['MoMo', 'Card', 'Cash'];

/// Legacy OCR columns the POS has no real value for.
///
/// The script still reads them, so they are written with fixed values rather
/// than dropped.
///
/// `Source Image` pointed at which photograph of the paper ledger a row came
/// from. Live POS data has no photograph, so `Sales Lines` hardcodes 1.
const int kSourceImageForSalesLines = 1;

/// `Confidence` graded how sure the OCR was of a row. Typed sales are exact,
/// but the column is not optional, so every row claims the middle grade.
const String kConfidenceValue = 'medium';

/// `Low Confidence Lines` counted OCR rows needing review. Always none here.
const int kLowConfidenceLines = 0;

/// The label on the summing row at the bottom of `Day Summary`.
const String kTotalRowLabel = 'TOTAL';

/// Styling, matching the reference workbook.
const String kHeaderBackColor = '#1F4E79';
const String kHeaderFontColor = '#FFFFFF';
const String kSummaryRowBackColor = '#D9E1F2';
const double kBodyFontSize = 10;
