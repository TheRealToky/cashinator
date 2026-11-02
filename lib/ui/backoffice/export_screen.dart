import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_date.dart';
import '../../core/app_exception.dart';
import '../../core/money.dart';
import '../../repositories/export_repository.dart';
import '../widgets/async_value_view.dart';

/// Which of the workbooks a run is producing.
enum _ExportKind { all, sales, expenses, production, unsold }

/// Date-range picker plus the export triggers and share functionality.
///
/// One range, separate files or one compiled workbook. Sales, expenses,
/// production and unsold can be exported individually or compiled into a single file.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late DateTime _from;
  late DateTime _to;

  /// The export currently running, or null while idle. Only one runs at a
  /// time, so the other buttons grey out rather than queueing a second write.
  _ExportKind? _running;

  AllExportResult? _allResult;
  ExportResult? _salesResult;
  ExpenseExportResult? _expenseResult;
  ProductionExportResult? _productionResult;
  UnsoldExportResult? _unsoldResult;

  File? _existingAllFile;
  File? _existingSalesFile;
  File? _existingExpenseFile;
  File? _existingProductionFile;
  File? _existingUnsoldFile;
  List<File> _recentExports = const [];

  @override
  void initState() {
    super.initState();
    // Defaults to today, the most common export. "This month" is one tap away.
    final today = startOfDay(DateTime.now());
    _from = today;
    _to = today;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFiles());
  }

  void _applyPreset({required DateTime from, required DateTime to}) {
    setState(() {
      _from = from;
      _to = to;
      _clearResults();
    });
    unawaited(_checkExistingForRange());
  }

  /// Results name a range, so they stop being true the moment it changes.
  void _clearResults() {
    _allResult = null;
    _salesResult = null;
    _expenseResult = null;
    _productionResult = null;
    _unsoldResult = null;
  }

  Future<void> _refreshFiles() async {
    await Future.wait([
      _checkExistingForRange(),
      _loadRecentExports(),
    ]);
  }

  Future<void> _checkExistingForRange() async {
    if (!mounted) return;
    final repo = context.read<ExportRepository>();
    final from = _from;
    final to = _to;

    final results = await Future.wait([
      repo.findExistingAllExport(from: from, to: to),
      repo.findExistingSalesExport(from: from, to: to),
      repo.findExistingExpenseExport(from: from, to: to),
      repo.findExistingProductionExport(from: from, to: to),
      repo.findExistingUnsoldExport(from: from, to: to),
    ]);

    if (!mounted) return;
    if (from == _from && to == _to) {
      setState(() {
        _existingAllFile = results[0];
        _existingSalesFile = results[1];
        _existingExpenseFile = results[2];
        _existingProductionFile = results[3];
        _existingUnsoldFile = results[4];
      });
    }
  }

  Future<void> _loadRecentExports() async {
    if (!mounted) return;
    final repo = context.read<ExportRepository>();
    final list = await repo.listRecentExports(limit: 6);
    if (!mounted) return;
    setState(() {
      _recentExports = list;
    });
  }

  Future<void> _pick({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;

    setState(() {
      final day = startOfDay(picked);
      if (isStart) {
        _from = day;
        // Keep the range valid rather than rejecting the tap afterwards.
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = day;
        if (_to.isBefore(_from)) _from = _to;
      }
      _clearResults();
    });
    unawaited(_checkExistingForRange());
  }

  Future<void> _exportAll() async {
    setState(() {
      _running = _ExportKind.all;
      _allResult = null;
    });

    try {
      final result = await context
          .read<ExportRepository>()
          .exportAllRange(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _allResult = result;
        _existingAllFile = result.file;
      });
      unawaited(_loadRecentExports());
      showAppSnackBar(
        context,
        'Exported ${result.fileName}.',
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => _shareFile(result.file),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _export() async {
    setState(() {
      _running = _ExportKind.sales;
      _salesResult = null;
    });

    try {
      final result = await context
          .read<ExportRepository>()
          .exportRange(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _salesResult = result;
        _existingSalesFile = result.file;
      });
      unawaited(_loadRecentExports());
      showAppSnackBar(
        context,
        'Exported ${result.fileName}.',
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => _shareFile(result.file),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _exportExpenses() async {
    setState(() {
      _running = _ExportKind.expenses;
      _expenseResult = null;
    });

    try {
      final result = await context
          .read<ExportRepository>()
          .exportExpenseRange(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _expenseResult = result;
        _existingExpenseFile = result.file;
      });
      unawaited(_loadRecentExports());
      showAppSnackBar(
        context,
        'Exported ${result.fileName}.',
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => _shareFile(result.file),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _exportProduction() async {
    setState(() {
      _running = _ExportKind.production;
      _productionResult = null;
    });

    try {
      final result = await context
          .read<ExportRepository>()
          .exportProductionRange(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _productionResult = result;
        _existingProductionFile = result.file;
      });
      unawaited(_loadRecentExports());
      showAppSnackBar(
        context,
        'Exported ${result.fileName}.',
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => _shareFile(result.file),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _exportUnsold() async {
    setState(() {
      _running = _ExportKind.unsold;
      _unsoldResult = null;
    });

    try {
      final result = await context
          .read<ExportRepository>()
          .exportUnsoldRange(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _unsoldResult = result;
        _existingUnsoldFile = result.file;
      });
      unawaited(_loadRecentExports());
      showAppSnackBar(
        context,
        'Exported ${result.fileName}.',
        action: SnackBarAction(
          label: 'Share',
          onPressed: () => _shareFile(result.file),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) return;
      showAppSnackBar(context, error.message, isError: true);
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  Future<void> _shareFile(File file, [BuildContext? buttonContext]) async {
    if (!await file.exists()) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Export file not found on device.',
        isError: true,
      );
      return;
    }

    try {
      final fileName = p.basename(file.path);
      Rect? sharePositionOrigin;
      if (buttonContext != null && buttonContext.mounted) {
        final box = buttonContext.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          sharePositionOrigin = box.localToGlobal(Offset.zero) & box.size;
        }
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: fileName,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          text: fileName,
          subject: fileName,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Could not share file: $error',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Excel export')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date range',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _PresetChip(
                  label: 'Today',
                  onTap: () => _applyPreset(from: today, to: today),
                ),
                _PresetChip(
                  label: 'Yesterday',
                  onTap: () {
                    final yesterday =
                        startOfDay(today.subtract(const Duration(hours: 23)));
                    _applyPreset(from: yesterday, to: yesterday);
                  },
                ),
                _PresetChip(
                  label: 'This month',
                  onTap: () =>
                      _applyPreset(from: startOfMonth(today), to: today),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'From',
                    value: _from,
                    onTap: () => _pick(isStart: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _DateField(
                    label: 'To',
                    value: _to,
                    onTap: () => _pick(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            // Export buttons in a Wrap so they reflow on narrow screens.
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: _ExportButton(
                    label: 'Export all',
                    icon: Icons.layers_outlined,
                    running: _running == _ExportKind.all,
                    onPressed: _running != null ? null : _exportAll,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: _ExportButton(
                    label: 'Sales Excel file',
                    icon: Icons.table_view_outlined,
                    running: _running == _ExportKind.sales,
                    onPressed: _running != null ? null : _export,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: _ExportButton(
                    label: 'Expenses Excel file',
                    icon: Icons.account_balance_wallet_outlined,
                    running: _running == _ExportKind.expenses,
                    onPressed: _running != null ? null : _exportExpenses,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: _ExportButton(
                    label: 'Production Excel file',
                    icon: Icons.inventory_2_outlined,
                    running: _running == _ExportKind.production,
                    onPressed: _running != null ? null : _exportProduction,
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: _ExportButton(
                    label: 'Unsold Excel file',
                    icon: Icons.remove_shopping_cart_outlined,
                    running: _running == _ExportKind.unsold,
                    onPressed: _running != null ? null : _exportUnsold,
                  ),
                ),
              ],
            ),
            if (_allResult != null) ...[
              const SizedBox(height: 28),
              _ResultCard(
                title: 'Export all ready',
                summary: '${_allResult!.orderCount} '
                    'order${_allResult!.orderCount == 1 ? '' : 's'} · '
                    '${_allResult!.expenseCount} '
                    'expense${_allResult!.expenseCount == 1 ? '' : 's'} · '
                    '${_allResult!.productionRowCount} '
                    'production line${_allResult!.productionRowCount == 1 ? '' : 's'} · '
                    '${_allResult!.unsoldRowCount} '
                    'unsold line${_allResult!.unsoldRowCount == 1 ? '' : 's'}',
                path: _allResult!.file.path,
                onShare: (ctx) => _shareFile(_allResult!.file, ctx),
              ),
            ] else if (_existingAllFile != null) ...[
              const SizedBox(height: 28),
              _ExistingExportCard(
                title: 'Export all already saved on device',
                file: _existingAllFile!,
                onShare: (ctx) => _shareFile(_existingAllFile!, ctx),
                onReExport: _running != null ? null : _exportAll,
              ),
            ],
            if (_salesResult != null) ...[
              const SizedBox(height: 28),
              _ResultCard(
                title: 'Sales export ready',
                summary: '${_salesResult!.orderCount} '
                    'order${_salesResult!.orderCount == 1 ? '' : 's'} · '
                    '${_salesResult!.lineCount} '
                    'line${_salesResult!.lineCount == 1 ? '' : 's'} · '
                    '${_salesResult!.dayCount} '
                    'day${_salesResult!.dayCount == 1 ? '' : 's'}',
                path: _salesResult!.file.path,
                onShare: (ctx) => _shareFile(_salesResult!.file, ctx),
              ),
            ] else if (_existingSalesFile != null) ...[
              const SizedBox(height: 28),
              _ExistingExportCard(
                title: 'Sales export already saved on device',
                file: _existingSalesFile!,
                onShare: (ctx) => _shareFile(_existingSalesFile!, ctx),
                onReExport: _running != null ? null : _export,
              ),
            ],
            if (_expenseResult != null) ...[
              const SizedBox(height: 28),
              _ResultCard(
                title: 'Expenses export ready',
                summary: '${_expenseResult!.expenseCount} '
                    'expense${_expenseResult!.expenseCount == 1 ? '' : 's'} · '
                    '${_expenseResult!.dayCount} '
                    'day${_expenseResult!.dayCount == 1 ? '' : 's'} · '
                    '${formatRwfWithUnit(_expenseResult!.totalSpend)}',
                path: _expenseResult!.file.path,
                onShare: (ctx) => _shareFile(_expenseResult!.file, ctx),
              ),
            ] else if (_existingExpenseFile != null) ...[
              const SizedBox(height: 28),
              _ExistingExportCard(
                title: 'Expenses export already saved on device',
                file: _existingExpenseFile!,
                onShare: (ctx) => _shareFile(_existingExpenseFile!, ctx),
                onReExport: _running != null ? null : _exportExpenses,
              ),
            ],
            if (_productionResult != null) ...[
              const SizedBox(height: 28),
              _ResultCard(
                title: 'Production export ready',
                summary: '${_productionResult!.rowCount} '
                    'line${_productionResult!.rowCount == 1 ? '' : 's'} · '
                    '${_productionResult!.dayCount} '
                    'day${_productionResult!.dayCount == 1 ? '' : 's'} · '
                    '${formatRwfWithUnit(_productionResult!.totalValue)}',
                path: _productionResult!.file.path,
                onShare: (ctx) => _shareFile(_productionResult!.file, ctx),
              ),
            ] else if (_existingProductionFile != null) ...[
              const SizedBox(height: 28),
              _ExistingExportCard(
                title: 'Production export already saved on device',
                file: _existingProductionFile!,
                onShare: (ctx) => _shareFile(_existingProductionFile!, ctx),
                onReExport: _running != null ? null : _exportProduction,
              ),
            ],
            if (_unsoldResult != null) ...[
              const SizedBox(height: 28),
              _ResultCard(
                title: 'Unsold export ready',
                summary: '${_unsoldResult!.rowCount} '
                    'line${_unsoldResult!.rowCount == 1 ? '' : 's'} · '
                    '${_unsoldResult!.dayCount} '
                    'day${_unsoldResult!.dayCount == 1 ? '' : 's'} · '
                    '${formatRwfWithUnit(_unsoldResult!.totalValue)}',
                path: _unsoldResult!.file.path,
                onShare: (ctx) => _shareFile(_unsoldResult!.file, ctx),
              ),
            ] else if (_existingUnsoldFile != null) ...[
              const SizedBox(height: 28),
              _ExistingExportCard(
                title: 'Unsold export already saved on device',
                file: _existingUnsoldFile!,
                onShare: (ctx) => _shareFile(_existingUnsoldFile!, ctx),
                onReExport: _running != null ? null : _exportUnsold,
              ),
            ],
            const SizedBox(height: 28),
            const _FormatNote(),
            if (_recentExports.isNotEmpty) ...[
              const SizedBox(height: 28),
              _RecentExportsCard(
                files: _recentExports,
                onShareFile: _shareFile,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 16)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatIsoDate(value),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(Icons.calendar_today_outlined, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the three export triggers. They share a shape so none reads as the
/// main one.
class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.label,
    required this.icon,
    required this.running,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: running
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : Icon(icon, size: 26),
        label: Text(running ? 'Generating…' : label),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.summary,
    required this.path,
    required this.onShare,
  });

  final String title;
  final String summary;
  final String path;
  final void Function(BuildContext context) onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline,
                  color: scheme.onPrimaryContainer, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            summary,
            style: TextStyle(fontSize: 17, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 10),
          Text(
            path,
            style: TextStyle(fontSize: 14, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 18),
          Builder(
            builder: (btnContext) {
              return SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => onShare(btnContext),
                  icon: const Icon(Icons.share, size: 22),
                  label: const Text(
                    'Share file (WhatsApp, Xender, …)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ExistingExportCard extends StatelessWidget {
  const _ExistingExportCard({
    required this.title,
    required this.file,
    required this.onShare,
    this.onReExport,
  });

  final String title;
  final File file;
  final void Function(BuildContext context) onShare;
  final VoidCallback? onReExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fileName = p.basename(file.path);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.file_present_outlined,
                  color: scheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            file.path,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Builder(
                builder: (btnContext) {
                  return SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () => onShare(btnContext),
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text(
                        'Share file (WhatsApp, Xender, …)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (onReExport != null)
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: onReExport,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Re-generate'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentExportsCard extends StatelessWidget {
  const _RecentExportsCard({
    required this.files,
    required this.onShareFile,
  });

  final List<File> files;
  final void Function(File file, BuildContext context) onShareFile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_outlined, color: scheme.primary, size: 26),
              const SizedBox(width: 12),
              const Text(
                'Recent exported files on tablet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final file in files) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Builder(
                builder: (rowContext) {
                  final fileName = p.basename(file.path);
                  final isAll = fileName.contains('all');
                  final isExpenses = fileName.contains('expenses');
                  final isProduction = fileName.contains('production');
                  final isUnsold = fileName.contains('unsold');
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isAll
                              ? Icons.layers_outlined
                              : isUnsold
                                  ? Icons.remove_shopping_cart_outlined
                                  : isProduction
                                      ? Icons.inventory_2_outlined
                                      : isExpenses
                                          ? Icons.account_balance_wallet_outlined
                                          : Icons.table_view_outlined,
                          size: 24,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 44,
                          child: FilledButton.tonalIcon(
                            onPressed: () => onShareFile(file, rowContext),
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Share'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormatNote extends StatelessWidget {
  const _FormatNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'The sales file keeps the layout the existing ledger exports '
              'use: a "Sales Lines" sheet with one row per item, and a '
              '"Day Summary" sheet with one row per day. Expenses, '
              'production, and unsold each go to their own file of the same '
              'shape, or use "Export all" to compile all four into a single '
              'multi-sheet workbook. In all files, voided rows stay visible '
              'but are left out of summary totals.',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
