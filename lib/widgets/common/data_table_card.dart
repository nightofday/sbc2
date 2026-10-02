import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'section_card.dart';

class DataTableCard extends StatelessWidget {
  final List<String> headers;
  final List<List<Widget>> rows;
  final List<int>? flexes;

  const DataTableCard({
    super.key,
    required this.headers,
    required this.rows,
    this.flexes,
  });

  @override
  Widget build(BuildContext context) {
    final columnFlexes = flexes ?? List.filled(headers.length, 1);

    return SectionCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minimumTableWidth = headers.length * 132.0;
          final tableWidth = math.max(constraints.maxWidth, minimumTableWidth);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        for (int i = 0; i < headers.length; i++)
                          Expanded(
                            flex: columnFlexes[i],
                            child: Text(
                              headers[i],
                              style: AppTextStyles.caption.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.gray200),
                  for (
                    int rowIndex = 0;
                    rowIndex < rows.length;
                    rowIndex++
                  ) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          for (int i = 0; i < rows[rowIndex].length; i++)
                            Expanded(
                              flex: columnFlexes[i],
                              child: rows[rowIndex][i],
                            ),
                        ],
                      ),
                    ),
                    if (rowIndex != rows.length - 1)
                      const Divider(height: 1, color: AppColors.gray200),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
