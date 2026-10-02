import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/reporting_repository.dart';
import '../../models/reporting.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/section_card.dart';
import '../../widgets/common/summary_card.dart';
import '../../widgets/layout/app_page.dart';

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
    _Period.thisMonth: 'This Month',
    _Period.custom: 'Custom Dates',
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
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$what copied. Paste it into Google Sheets or Excel: each value '
          'goes into its own cell.',
        ),
      ),
    );
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
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in _Period.values)
                ChoiceChip(
                  label: Text(_periodLabels[period]!),
                  selected: _period == period,
                  onSelected: (_) => _choosePeriod(period),
                ),
            ],
          ),
          const SizedBox(height: 18),
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
                          '${error is PostgrestException ? error.message : error}',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _refresh,
                          child: const Text('Try Again'),
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
                label: 'Gross Sales',
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
                label: 'Net Sales',
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
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Money In and Out', style: AppTextStyles.h3),
                const SizedBox(height: 4),
                Text(
                  'These are separate figures. They are not added together '
                  'and none of them is profit.',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: () => _copy(report.toTsv(), 'The whole report was'),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Copy Whole Report for Sheets'),
            ),
          ),
          for (final section in report.sections) ...[
            const SizedBox(height: 26),
            _buildSection(section),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTextStyles.body)),
          const SizedBox(width: 12),
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
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(section.title, style: AppTextStyles.h3),
            if (section.rows.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _copy(section.toTsv(), '${section.title} was'),
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('Copy for Sheets'),
              ),
          ],
        ),
        if (section.note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(section.note, style: AppTextStyles.caption),
        ],
        const SizedBox(height: 10),
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
