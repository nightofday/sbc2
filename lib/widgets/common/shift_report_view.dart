import 'package:flutter/material.dart';

import '../../core/export/copy_text.dart';
import '../../core/error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/reporting.dart';
import '../../models/shift_report.dart';
import 'app_dialog.dart';
import '../../core/theme/app_spacing.dart';

/// Shows the end-of-shift report in a dialog, loading it first.
Future<void> showShiftReportDialog({
  required BuildContext context,
  required Future<ShiftReport> report,
}) {
  return showPrototypeDialog(
    context: context,
    title: 'Shift Report',
    width: 520,
    content: FutureBuilder<ShiftReport>(
      future: report,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Text(
            'Unable to load the shift report.\n${errorText(snapshot.error)}',
            style: AppTextStyles.body,
          );
        }

        return SingleChildScrollView(
          child: ShiftReportView(report: snapshot.data!),
        );
      },
    ),
  );
}

class ShiftReportView extends StatelessWidget {
  final ShiftReport report;

  const ShiftReportView({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final variance = report.variance;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Shift #${report.number} · ${report.employeeName}',
          style: AppTextStyles.h3,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          report.isOpen
              ? 'Opened ${formatShiftTime(report.startedAt)} · still open'
              : '${formatShiftTime(report.startedAt)} to '
                    '${formatShiftTime(report.endedAt)}',
          style: AppTextStyles.caption,
        ),
        const Divider(height: 26),
        _heading('Sales'),
        _row(
          'Orders',
          report.voidedCount > 0
              ? '${report.orderCount} (${report.voidedCount} voided)'
              : '${report.orderCount}',
        ),
        _money('Gross sales', report.grossSales),
        _money('Discounts', -report.discounts),
        _money('Refunds', -report.refunds),
        _money('Net sales', report.netSales, strong: true),
        const Divider(height: 26),
        _heading('Payments received'),
        if (report.payments.isEmpty)
          const Text('No payments in this shift.', style: AppTextStyles.caption)
        else
          for (final payment in report.payments)
            _money(
              payment.refunded > 0
                  ? '${payment.paymentMethod} (less '
                        '${formatReportMoney(payment.refunded)} refunded)'
                  : payment.paymentMethod,
              payment.net,
            ),
        const Divider(height: 26),
        _heading('Cash drawer'),
        _money('Opening cash', report.openingCash),
        _money('Cash sales', report.cashSales),
        _money('Cash refunds', -report.cashRefunds),
        _money('Cash in', report.cashIn),
        _money('Cash out', -report.cashOut),
        _money('Expected in drawer', report.expectedCash, strong: true),
        if (report.countedCash != null)
          _money('Counted', report.countedCash!, strong: true),
        if (variance != null)
          _money(
            variance == 0
                ? 'Difference'
                : variance < 0
                ? 'Short'
                : 'Over',
            variance.abs(),
            strong: true,
            color: variance == 0
                ? AppColors.success
                : variance < 0
                ? AppColors.primary
                : AppColors.warning,
          ),
        if (report.cashMovements.isNotEmpty) ...[
          const Divider(height: 26),
          _heading('Cash in and out'),
          for (final movement in report.cashMovements)
            _money(
              '${movement.typeLabel} · ${movement.reason}',
              movement.addsCash ? movement.amount : -movement.amount,
            ),
        ],
        if (report.closingNotes.isNotEmpty) ...[
          const Divider(height: 26),
          _heading('Closing notes'),
          Text(report.closingNotes, style: AppTextStyles.body),
        ],
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: () async {
            final copied = await copyText(report.toText());
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  copied
                      ? 'Shift report copied.'
                      : 'Copying did not work on this device. Try again.',
                ),
              ),
            );
          },
          icon: const Icon(Icons.copy_outlined, size: 17),
          label: const Text('Copy Report'),
        ),
      ],
    );
  }

  Widget _heading(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text.toUpperCase(),
        style: AppTextStyles.caption.copyWith(
          color: AppColors.gray500,
          fontWeight: FontWeight.w700,
          letterSpacing: .6,
        ),
      ),
    );
  }

  Widget _money(
    String label,
    double value, {
    bool strong = false,
    Color? color,
  }) {
    return _row(label, formatReportMoney(value), strong: strong, color: color);
  }

  Widget _row(String label, String value, {bool strong = false, Color? color}) {
    final style = (strong ? AppTextStyles.bodyMedium : AppTextStyles.body)
        .copyWith(color: color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: AppSpacing.md),
          Text(value, style: style),
        ],
      ),
    );
  }
}
