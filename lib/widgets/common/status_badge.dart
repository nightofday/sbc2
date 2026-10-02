import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// A short state label such as "Completed" or "Voided", in a tinted
/// container whose colour tells the kind of state at a glance.
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

    // Success unless the label says otherwise.
    var background = const Color(0xFFD9F2DF);
    var foreground = const Color(0xFF0E4D25);

    if (lower.contains('refund')) {
      background = const Color(0xFFD1E4FF);
      foreground = const Color(0xFF00325A);
    } else if (lower.contains('low') ||
        lower.contains('void') ||
        lower.contains('reversed') ||
        lower.contains('attention') ||
        lower.contains('inactive') ||
        lower.contains('archived') ||
        lower.contains('out of stock')) {
      background = const Color(0xFFFFDAD6);
      foreground = const Color(0xFF7A0006);
    } else if (lower.contains('expir') ||
        lower.contains('waiting') ||
        lower.contains('open') ||
        lower.contains('draft') ||
        lower.contains('pending') ||
        lower.contains('not available')) {
      background = const Color(0xFFFFE8B8);
      foreground = const Color(0xFF5A3A00);
    } else if (lower.contains('reversal') || lower.contains('cancel')) {
      background = AppColors.gray200;
      foreground = AppColors.gray700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _displayLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          color: foreground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
