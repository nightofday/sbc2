import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class StatusBadge extends StatelessWidget {
  final String label;

  const StatusBadge(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    Color foreground = AppColors.success;
    Color background = AppColors.success.withValues(alpha: .10);

    if (lower.contains('refund')) {
      foreground = AppColors.info;
      background = AppColors.info.withValues(alpha: .10);
    } else if (lower.contains('low') ||
        lower.contains('void') ||
        lower.contains('inactive')) {
      foreground = AppColors.primary;
      background = AppColors.primarySoft;
    } else if (lower.contains('expir') || lower.contains('open')) {
      foreground = AppColors.warning;
      background = AppColors.yellow.withValues(alpha: .14);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
