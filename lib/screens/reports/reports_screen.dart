import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/export/copy_text.dart';
import '../../core/export/export_file.dart';
import '../../core/export/report_workbook.dart';
import '../../core/export/xlsx.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../models/reporting.dart';
import '../../widgets/common/business_profile_scope.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/common/summary_card.dart';
import '../../widgets/layout/app_page.dart';
import '../../core/theme/app_spacing.dart';

enum _Period { today, yesterday, last7, last30, thisMonth, custom }

class ReportsScreen extends StatefulWidget {
  final ReportingRepository reportingRepository;
  final Listenable? refreshListenable;

  const ReportsScreen({
    super.key,
    required this.reportingRepository,
    this.refreshListenable,
  });

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Period _period = _Period.last7;
  late DateTime _from;
  late DateTime _to;
  late Future<BusinessReport> _reportFuture;

  static const _periodLabels = {
    _Period.today: 'Today',
    _Period.yesterday: 'Yesterday',
    _Period.last7: 'Last 7 Days',
    _Period.last30: 'Last 30 Days',
    _Period.thisMonth: 'This month',
    _Period.custom: 'Custom dates',
  };

  @override
  void initState() {
    super.initState();
    _applyPeriod(_period);
    _reload();
    widget.refreshListenable?.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_refresh);
      widget.refreshListenable?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_refresh);
    super.dispose();
  }

  void _applyPeriod(_Period period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (period) {
      case _Period.today:
        _from = today;
        _to = today;
      case _Period.yesterday:
        _from = today.subtract(const Duration(days: 1));
        _to = _from;
      case _Period.last7:
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case _Period.last30:
        _from = today.subtract(const Duration(days: 29));
        _to = today;
      case _Period.thisMonth:
        _from = DateTime(today.year, today.month);
        _to = today;
      case _Period.custom:
        // Keeps the dates already chosen.
        break;
    }
  }

  void _reload() {
    _reportFuture = widget.reportingRepository.getBusinessReport(
      from: _from,
      to: _to,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _choosePeriod(_Period period) async {
    if (period == _Period.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _from, end: _to),
        helpText: 'Choose the report dates',
      );
      if (picked == null || !mounted) return;

      setState(() {
        _period = _Period.custom;
        _from = DateUtils.dateOnly(picked.start);
        _to = DateUtils.dateOnly(picked.end);
        _reload();
      });
      return;
    }

    setState(() {
      _period = period;
      _applyPeriod(period);
      _reload();
    });
  }

  Future<void> _copy(String text, String what) async {
    final copied = await copyText(text);
    if (!mounted) return;

    _showMessage(
      copied
          ? '$what copied. Paste it into Google Sheets or Excel: each value '
                'goes into its own cell.'
          : 'Copying did not work here. Use $exportExcelLabel instead.',
    );
  }

  /// Saves or shares a formatted Excel workbook built by [build], which is
  /// given the business name and the time of the export.
  Future<void> _exportExcel(
    String fileTitle,
    Uint8List Function(String businessName, DateTime exportedAt) build,
  ) async {
    final businessName = BusinessProfileScope.of(context).tradeName;
    final exported = await exportBytesFile(
      fileName: reportFileName(fileTitle, _from, _to, extension: 'xlsx'),
      bytes: build(businessName, DateTime.now()),
      mimeType: XlsxWorkbook.mimeType,
    );
    if (!mounted) return;

    // On a tablet or phone the share sheet speaks for itself.
    if (exported && !exportSavesToDownloads) return;
    _showMessage(
      exported
          ? 'Saved to your downloads. It opens in Excel or Google Sheets.'
          : 'The file could not be exported. Use Copy for Sheets instead.',
    );
  }

  IconData get _exportIcon =>
      exportSavesToDownloads ? Icons.download_outlined : Icons.share_outlined;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _rangeLabel => _from == _to
      ? formatReportDate(_from)
      : '${formatReportDate(_from)} to ${formatReportDate(_to)}';

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Reports',
      subtitle: _rangeLabel,
      action: OutlinedButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh, size: 17),
        label: const Text('Refresh'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final period in _Period.values)
                ChoiceChip(
                  label: Text(_periodLabels[period]!),
                  selected: _period == period,
                  onSelected: (_) => _choosePeriod(period),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: FutureBuilder<BusinessReport>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Unable to load the report.\n'
                          '${errorText(error)}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  );
                }

                return _buildReport(snapshot.data!);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReport(BusinessReport report) {
    final summary = report.summary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SummaryCardGrid(
            children: [
              SummaryCard(
                label: 'Gross sales',
                value: formatReportMoney(summary.grossSales),
                subtitle: 'At menu prices, before discounts',
                accentColor: AppColors.black,
              ),
              SummaryCard(
                label: 'Discounts',
                value: formatReportMoney(summary.discounts),
                subtitle: 'Given on those sales',
                accentColor: AppColors.orange,
              ),
              SummaryCard(
                label: 'Refunds',
                value: formatReportMoney(summary.refunds),
                subtitle:
                    '${summary.refundCount} '
                    '${summary.refundCount == 1 ? 'refund' : 'refunds'} made '
                    'in this period',
                accentColor: AppColors.warning,
              ),
              SummaryCard(
                label: 'Net sales',
                value: formatReportMoney(summary.netSales),
                subtitle: 'Gross sales less discounts and refunds',
                accentColor: AppColors.primary,
              ),
              SummaryCard(
                label: 'Orders',
                value: '${summary.orders}',
                subtitle:
                    'Average ${formatReportMoney(summary.averageOrder)} '
                    'after discounts',
                accentColor: AppColors.info,
              ),
              SummaryCard(
                label: 'Expenses',
                value: formatReportMoney(summary.expenses),
                subtitle: 'Posted in this period',
                accentColor: AppColors.gray700,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Money In and Out', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'These are separate figures. They are not added together '
                  'and none of them is profit.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: AppSpacing.md),
                _moneyRow(
                  'Net sales less expenses',
                  summary.netSalesLessExpenses,
                ),
                _moneyRow('Stock received from suppliers', summary.purchases),
                _moneyRow('Paid to suppliers', summary.supplierPayments),
                _moneyRow(
                  'Cost of stock recorded as lost',
                  summary.stockLossCost,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              ElevatedButton.icon(
                onPressed: () => _exportExcel(
                  'report',
                  (businessName, exportedAt) => businessReportWorkbook(
                    report,
                    exportedAt: exportedAt,
                    businessName: businessName,
                  ),
                ),
                icon: Icon(_exportIcon, size: 18),
                label: Text(
                  exportSavesToDownloads
                      ? 'Download Whole Report (Excel)'
                      : 'Share Whole Report (Excel)',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _copy(report.toTsv(), 'The whole report was'),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copy Whole Report for Sheets'),
              ),
            ],
          ),
          for (final section in report.sections) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildSection(section),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body)),
          const SizedBox(width: AppSpacing.md),
          Text(formatReportMoney(value), style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildSection(ReportSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(section.title, style: AppTextStyles.h3),
            if (section.rows.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _exportExcel(
                  section.title,
                  (businessName, exportedAt) => reportSectionWorkbook(
                    section,
                    from: _from,
                    to: _to,
                    exportedAt: exportedAt,
                    businessName: businessName,
                  ),
                ),
                icon: Icon(_exportIcon, size: 16),
                label: Text(exportExcelLabel),
              ),
            if (section.rows.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _copy(section.toTsv(), '${section.title} was'),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy for Sheets'),
              ),
          ],
        ),
        if (section.note.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(section.note, style: AppTextStyles.caption),
        ],
        const SizedBox(height: AppSpacing.sm),
        if (section.rows.isEmpty)
          SectionCard(
            child: Text(
              section.emptyText,
              style: AppTextStyles.body.copyWith(color: AppColors.gray500),
            ),
          )
        else
          DataTableCard(
            headers: section.columns.map((column) => column.label).toList(),
            rows: [
              for (final row in section.rows)
                [
                  for (final column in section.columns)
                    Text(
                      section.display(row, column),
                      style: column == section.columns.first
                          ? AppTextStyles.bodyMedium
                          : AppTextStyles.body,
                    ),
                ],
            ],
          ),
      ],
    );
  }
}
