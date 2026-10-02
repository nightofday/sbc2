import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'section_card.dart';

/// One headline figure, such as net sales, with what it means underneath.
class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;

  /// Marks which figure this is, so cards can be told apart at a glance.
  final Color accentColor;

  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.gray700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: AppTextStyles.h1.copyWith(fontSize: 28),
                ),
              ),
            ),
            const Spacer(),
            Text(
              subtitle,
              style: AppTextStyles.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class SummaryCardGrid extends StatelessWidget {
  final List<Widget> children;

  const SummaryCardGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int columns = constraints.maxWidth < 560
            ? 1
            : constraints.maxWidth < 1050
            ? 2
            : children.isEmpty
            ? 1
            : children.length > 4
            ? 4
            : children.length;
        const gap = 16.0;
        final itemWidth =
            (constraints.maxWidth - (gap * (columns - 1))) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
