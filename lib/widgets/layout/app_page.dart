import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import 'app_header_scope.dart';
import 'header_brand_motif.dart';

class AppPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  const AppPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSubtitle = subtitle ?? _todayLabel();
    final trailing = AppHeaderScope.trailingOf(context);

    return ColoredBox(
      color: AppColors.gray100,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final pagePadding = compact ? 16.0 : AppSpacing.page;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.h1),
              const SizedBox(height: AppSpacing.xs),
              Text(
                effectiveSubtitle,
                style: AppTextStyles.caption.copyWith(color: AppColors.gray500),
              ),
            ],
          );

          return Stack(
            children: [
              const Positioned(
                top: 0,
                right: 0,
                left: 0,
                child: HeaderBrandMotif(),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(pagePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact && action != null) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleBlock),
                            ?trailing,
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (constraints.maxWidth < 420)
                          SizedBox(width: double.infinity, child: action!)
                        else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: action!,
                          ),
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: titleBlock),
                            ?action,
                            if (trailing != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              trailing,
                            ],
                          ],
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _todayLabel() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, '
        '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}
