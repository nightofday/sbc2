import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../domain/repositories/offline_sales_queue.dart';
import '../../models/offline_sale.dart';
import 'app_dialog.dart';
import '../../core/theme/app_radius.dart';

/// A strip above the page that says when the till is working offline, how
/// many sales are still on this device, and lets a refused sale be resolved.
/// It takes no space while everything is online and sent.
class OfflineStatusBanner extends StatelessWidget {
  final OfflineSalesQueue queue;

  const OfflineStatusBanner({super.key, required this.queue});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final waiting = queue.waitingSales.length;
        final rejected = queue.rejectedSales.length;

        if (rejected > 0) {
          return _strip(
            icon: Icons.error_outline,
            color: AppColors.primary,
            background: AppColors.primarySoft,
            message: rejected == 1
                ? '1 offline sale was not accepted and needs attention.'
                : '$rejected offline sales were not accepted and need '
                      'attention.',
            action: TextButton(
              onPressed: () => _showRejectedSales(context),
              child: const Text('Review'),
            ),
          );
        }

        if (waiting > 0) {
          return _strip(
            icon: queue.isOffline ? Icons.cloud_off_outlined : Icons.sync,
            color: AppColors.gray900,
            background: AppColors.yellow.withValues(alpha: .22),
            message: queue.isOffline
                ? 'Offline. ${_sales(waiting)} saved on this device and will '
                      'be sent when the connection returns.'
                : '${_sales(waiting)} waiting to be sent.',
            action: queue.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: queue.syncPending,
                    child: const Text('Send now'),
                  ),
          );
        }

        if (queue.isOffline) {
          return _strip(
            icon: Icons.cloud_off_outlined,
            color: AppColors.gray900,
            background: AppColors.gray200,
            message:
                'Offline. Sales can still be taken and are sent when the '
                'connection returns. Other screens need the internet.',
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  String _sales(int count) => count == 1 ? '1 sale' : '$count sales';

  Widget _strip({
    required IconData icon,
    required Color color,
    required Color background,
    required String message,
    Widget? action,
  }) {
    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.caption.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      ),
    );
  }

  Future<void> _showRejectedSales(BuildContext context) async {
    await showPrototypeDialog(
      context: context,
      title: 'Offline sales needing attention',
      width: 560,
      content: ListenableBuilder(
        listenable: queue,
        builder: (context, _) {
          final sales = queue.rejectedSales;

          if (sales.isEmpty) {
            return const Text(
              'Nothing left to resolve.',
              style: AppTextStyles.body,
            );
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'These sales were taken offline and the customer has paid, '
                  'but the server did not accept them. Fix the cause and send '
                  'again. Remove a sale only after it has been entered '
                  'another way.',
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: 14),
                for (final sale in sales) _rejectedSale(context, sale),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rejectedSale(BuildContext context, OfflineSale sale) {
    final record = sale.toOrderRecord();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.gray200),
        borderRadius: AppRadius.all,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${sale.reference} · ${record.time} · '
            '₱${sale.total.toStringAsFixed(2)}',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            sale.lines
                .map((line) => '${line.quantity} × ${line.productName}')
                .join(', '),
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: 6),
          Text(
            sale.rejection,
            style: AppTextStyles.caption.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _confirmRemove(context, sale),
                child: const Text('Remove'),
              ),
              FilledButton(
                onPressed: () => queue.retrySale(sale.requestId),
                child: const Text('Send again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, OfflineSale sale) async {
    final confirmed = await showSettledDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this sale?'),
        content: Text(
          '${sale.reference} for ₱${sale.total.toStringAsFixed(2)} will be '
          'deleted from this device and will not appear in any report. '
          'Only do this if it has been recorded another way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) await queue.discardSale(sale.requestId);
  }
}
