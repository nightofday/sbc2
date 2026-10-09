import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/order_item.dart';
import '../../core/theme/app_spacing.dart';

/// One line of a receipt or an order: quantity and name, the options and
/// note chosen for it underneath, and the line total on the right.
class OrderLine extends StatelessWidget {
  final OrderItem item;
  final String total;

  const OrderLine({super.key, required this.item, required this.total});

  @override
  Widget build(BuildContext context) {
    final detail = [
      if (item.options.isNotEmpty) item.options.join(', '),
      if (item.note.trim().isNotEmpty) 'Note: ${item.note.trim()}',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantity} × ${item.productName}',
                  style: AppTextStyles.body,
                ),
                for (final line in detail)
                  Text(
                    line,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(total, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}
