import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/order_repository.dart';
import '../../models/reporting.dart';
import '../../models/shift_report.dart';
import '../../widgets/common/data_table_card.dart';
import '../../widgets/common/shift_report_view.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/layout/app_page.dart';

enum _Period { today, last7, last30, custom }

/// Shift history: who worked, when, and how each drawer count compared with
/// what was expected. Opens the full report for any shift.
class ShiftsScreen extends StatefulWidget {
  final OrderRepository orderRepository;
  final Listenable? refreshListenable;

  const ShiftsScreen({
    super.key,
    required this.orderRepository,
    this.refreshListenable,
  });

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  _Period _period = _Period.last7;
  late DateTime _from;
  late DateTime _to;
  late Future<List<ShiftSummary>> _shiftsFuture;

  static const _periodLabels = {
    _Period.today: 'Today',
    _Period.last7: 'Last 7 Days',
    _Period.last30: 'Last 30 Days',
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
  void didUpdateWidget(covariant ShiftsScreen oldWidget) {
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
    final today = DateUtils.dateOnly(DateTime.now());

    switch (period) {
      case _Period.today:
        _from = today;
        _to = today;
      case _Period.last7:
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case _Period.last30:
        _from = today.subtract(const Duration(days: 29));
        _to = today;
      case _Period.custom:
        // Keeps the dates already chosen.
        break;
    }
  }

  void _reload() {
    _shiftsFuture = widget.orderRepository.getShifts(from: _from, to: _to);
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
        helpText: 'Choose the shift dates',
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

  String get _rangeLabel => _from == _to
      ? formatReportDate(_from)
      : '${formatReportDate(_from)} to ${formatReportDate(_to)}';

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Shifts',
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
            child: FutureBuilder<List<ShiftSummary>>(
              future: _shiftsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Unable to load shifts.\n'
                          '${errorText(snapshot.error)}',
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

                final shifts = snapshot.data!;
                if (shifts.isEmpty) {
                  return const Center(
                    child: Text(
                      'No shifts were opened in these dates.',
                      style: AppTextStyles.body,
                    ),
                  );
                }

                return SingleChildScrollView(child: _buildTable(shifts));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<ShiftSummary> shifts) {
    return DataTableCard(
      headers: const [
        'Shift',
        'Opened',
        'Closed',
        'Orders',
        'Expected Cash',
        'Counted',
        'Difference',
        'Status',
        '',
      ],
      flexes: const [3, 3, 3, 2, 2, 2, 2, 2, 2],
      rows: [
        for (final shift in shifts)
          [
            Text(
              '#${shift.number} · ${shift.employeeName}',
              style: AppTextStyles.bodyMedium,
            ),
            Text(formatShiftTime(shift.startedAt), style: AppTextStyles.body),
            Text(
              shift.isOpen ? '—' : formatShiftTime(shift.endedAt),
              style: AppTextStyles.body,
            ),
            Text('${shift.orderCount}', style: AppTextStyles.body),
            Text(_optionalMoney(shift.expectedCash), style: AppTextStyles.body),
            Text(_optionalMoney(shift.countedCash), style: AppTextStyles.body),
            _difference(shift.variance),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(shift.statusLabel),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showShiftReportDialog(
                  context: context,
                  report: widget.orderRepository.getShiftReport(shift.id),
                ),
                child: const Text('Report'),
              ),
            ),
          ],
      ],
    );
  }

  String _optionalMoney(double? value) =>
      value == null ? '—' : formatReportMoney(value);

  Widget _difference(double? variance) {
    if (variance == null) return const Text('—', style: AppTextStyles.body);

    final label = variance == 0
        ? 'None'
        : variance < 0
        ? '${formatReportMoney(variance.abs())} short'
        : '${formatReportMoney(variance)} over';

    return Text(
      label,
      style: AppTextStyles.bodyMedium.copyWith(
        color: variance == 0
            ? AppColors.success
            : variance < 0
            ? AppColors.primary
            : AppColors.warning,
      ),
    );
  }
}
