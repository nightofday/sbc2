import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';

/// A page inside the app shell: a title bar with the page's title, a short
/// line under it, and the page's main action on the right, then the content.
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final margin = compact ? 16.0 : AppSpacing.page;
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h1),
            const SizedBox(height: 2),
            Text(effectiveSubtitle, style: AppTextStyles.caption),
          ],
        );

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(margin, 20, margin, margin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact && action != null) ...[
                  titleBlock,
                  const SizedBox(height: 12),
                  if (constraints.maxWidth < 420)
                    SizedBox(width: double.infinity, child: action!)
                  else
                    Align(alignment: Alignment.centerLeft, child: action!),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: titleBlock),
                      ?action,
                    ],
                  ),
                const SizedBox(height: 20),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
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
