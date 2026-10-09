import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/state/stock_alerts_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/inventory_item.dart';
import '../../models/stock_alerts.dart';
import 'app_dialog.dart';

/// Opens the list of stock alerts. [onOpenStockOverview], when given, adds a
/// button that closes the list and shows the stock overview.
Future<void> showStockAlertsPanel({
  required BuildContext context,
  required StockAlertsController controller,
  VoidCallback? onOpenStockOverview,
}) async {
  var openOverview = false;

  await showPrototypeDialog<void>(
    context: context,
    title: 'Stock alerts',
    width: 480,
    content: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _StockAlertsList(controller: controller),
    ),
    actions: [
      Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ),
      if (onOpenStockOverview != null)
        Builder(
          builder: (dialogContext) => ElevatedButton(
            onPressed: () {
              openOverview = true;
              Navigator.pop(dialogContext);
            },
            child: const Text('Open stock overview'),
          ),
        ),
    ],
  );

  if (openOverview) onOpenStockOverview?.call();
}

/// A bell with the number of items that need attention. Shown in the
/// sidebar, as an icon only when the sidebar is [compact].
class StockAlertsButton extends StatelessWidget {
  final StockAlertsController controller;
  final VoidCallback? onOpenStockOverview;
  final bool compact;

  const StockAlertsButton({
    super.key,
    required this.controller,
    this.onOpenStockOverview,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = controller.alerts.itemCount;
        final label = count == 0
            ? 'Stock alerts, none'
            : 'Stock alerts, $count ${count == 1 ? 'item needs' : 'items need'} attention';

        void open() => showStockAlertsPanel(
          context: context,
          controller: controller,
          onOpenStockOverview: onOpenStockOverview,
        );

        final bell = Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              count == 0
                  ? Icons.notifications_none_outlined
                  : Icons.notifications_active_outlined,
              size: 22,
              color: count == 0 ? AppColors.gray700 : AppColors.black,
            ),
            if (count > 0)
              Positioned(top: -7, right: -10, child: _CountBadge(count: count)),
          ],
        );

        if (compact) {
          return Tooltip(
            message: label,
            child: Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: IconButton(onPressed: open, icon: bell),
            ),
          );
        }

        return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: open,
            borderRadius: AppRadius.all,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  bell,
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Stock alerts',
                      style: AppTextStyles.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A warning strip for the top of the dashboard. Shows nothing while no
/// stock needs attention.
class StockAlertsBanner extends StatelessWidget {
  final StockAlertsController controller;
  final VoidCallback? onOpenStockOverview;

  const StockAlertsBanner({
    super.key,
    required this.controller,
    this.onOpenStockOverview,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final alerts = controller.alerts;
        if (alerts.isEmpty) return const SizedBox.shrink();

        final count = alerts.itemCount;
        final message = Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text:
                    '$count stock ${count == 1 ? 'item needs' : 'items need'} '
                    'attention: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: '${alerts.summary}.'),
            ],
          ),
          style: AppTextStyles.body.copyWith(color: _warningInk),
        );
        final review = OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.black,
            backgroundColor: AppColors.white,
            side: const BorderSide(color: AppColors.black),
          ),
          onPressed: () => showStockAlertsPanel(
            context: context,
            controller: controller,
            onOpenStockOverview: onOpenStockOverview,
          ),
          child: const Text('Review'),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.lg),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: _warningFill,
            borderRadius: AppRadius.all,
            border: Border.all(color: _warningBorder),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const icon = Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: message),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(alignment: Alignment.centerRight, child: review),
                  ],
                );
              }
              return Row(
                children: [
                  icon,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: message),
                  const SizedBox(width: AppSpacing.lg),
                  review,
                ],
              );
            },
          ),
        );
      },
    );
  }
}

const _warningFill = Color(0xFFFDF1E3);
const _warningBorder = Color(0xFFE7B77A);
const _warningInk = Color(0xFF5C3000);

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadius.all,
        border: Border.all(color: AppColors.white, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _StockAlertsList extends StatelessWidget {
  final StockAlertsController controller;

  const _StockAlertsList({required this.controller});

  @override
  Widget build(BuildContext context) {
    final alerts = controller.alerts;
    final today = manilaToday();

    if (controller.error != null && alerts.isEmpty) {
      return Text(
        'Could not check stock. ${errorText(controller.error)}',
        style: AppTextStyles.body.copyWith(color: AppColors.error),
      );
    }

    if (alerts.isEmpty) {
      return Text(
        controller.loading
            ? 'Checking stock…'
            : 'Nothing needs attention. No stock is expired, expiring within '
                  '${StockAlerts.expiringWithinDays} days or below its '
                  'reorder level.',
        style: AppTextStyles.body.copyWith(color: AppColors.gray700),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Could not refresh; showing the last check. '
              '${errorText(controller.error)}',
              style: AppTextStyles.caption.copyWith(color: AppColors.error),
            ),
          ),
        if (alerts.expired.isNotEmpty)
          _AlertGroup(
            title: 'Expired · dispose to clear',
            color: AppColors.error,
            children: [
              for (final item in alerts.expired)
                _AlertRow(
                  name: item.name,
                  detail: '${item.expiredStock} expired',
                  trailing: 'Expired',
                  color: AppColors.error,
                ),
            ],
          ),
        if (alerts.expiringSoon.isNotEmpty)
          _AlertGroup(
            title:
                'Expiring within ${StockAlerts.expiringWithinDays} days · '
                'use first',
            color: AppColors.warning,
            children: [
              for (final item in alerts.expiringSoon)
                _AlertRow(
                  name: item.name,
                  detail:
                      '${item.usableStock} usable · next lot expires '
                      '${item.expiration}',
                  trailing: _daysLeftLabel(item, today),
                  color: AppColors.warning,
                ),
            ],
          ),
        if (alerts.belowReorder.isNotEmpty)
          _AlertGroup(
            title: 'Below reorder level · buy soon',
            color: AppColors.gray700,
            children: [
              for (final item in alerts.belowReorder)
                _AlertRow(
                  name: item.name,
                  detail:
                      '${item.usableStock} usable · reorder at '
                      '${_reorderLabel(item)}',
                  trailing: item.usableQuantity <= 0 ? 'None left' : 'Low',
                  color: AppColors.gray700,
                ),
            ],
          ),
      ],
    );
  }

  static String _daysLeftLabel(InventoryItem item, DateTime today) {
    final days = StockAlerts.daysUntilExpiry(item, today: today) ?? 0;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    return 'In $days days';
  }

  static String _reorderLabel(InventoryItem item) {
    final level = item.reorderLevel;
    final value = level == level.roundToDouble()
        ? level.toInt().toString()
        : level.toStringAsFixed(2);
    return item.baseUomCode.isEmpty ? value : '$value ${item.baseUomCode}';
  }
}

class _AlertGroup extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;

  const _AlertGroup({
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...children,
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final String name;
  final String detail;
  final String trailing;
  final Color color;

  const _AlertRow({
    required this.name,
    required this.detail,
    required this.trailing,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.gray200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.bodyMedium),
                Text(detail, style: AppTextStyles.caption),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            trailing,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
