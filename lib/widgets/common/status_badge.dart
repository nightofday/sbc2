import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_spacing.dart';

class StatusBadge extends StatelessWidget {
  final String label;

  const StatusBadge(this.label, {super.key});

  /// Database status codes such as `PARTIALLY_PAID` are shown as words.
  String get _displayLabel {
    if (label != label.toUpperCase() || !label.contains(RegExp('[A-Z]'))) {
      return label;
    }

    return label
        .split('_')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0] + word.substring(1).toLowerCase())
        .join(' ');
  }

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
        lower.contains('reversed') ||
        lower.contains('attention') ||
        lower.contains('inactive')) {
      foreground = AppColors.primary;
      background = AppColors.primarySoft;
    } else if (lower.contains('expir') ||
        lower.contains('waiting') ||
        lower.contains('open')) {
      foreground = AppColors.warning;
      background = AppColors.yellow.withValues(alpha: .14);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(color: background, borderRadius: AppRadius.all),
      child: Text(
        _displayLabel,
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
