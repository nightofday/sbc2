import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'section_card.dart';

/// A table that is always fully on screen. When its columns fit it is a
/// table; when they do not, each row becomes a block of labelled values.
/// It never scrolls sideways, because that hides the status and action
/// columns on tablets and phones.
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

  /// The narrowest a column may be before the table stops being readable.
  static const double _minimumColumnWidth = 84;

  /// Width given to each unit of flex when columns have different weights.
  static const double _minimumFlexUnitWidth = 44;

  /// The least width at which every column is still readable side by side.
  double get _minimumTableWidth {
    final byColumn = headers.length * _minimumColumnWidth;
    final columnFlexes = flexes;
    if (columnFlexes == null) return headers.length * 110.0;

    final byFlex =
        columnFlexes.fold<int>(0, (sum, flex) => sum + flex) *
        _minimumFlexUnitWidth;
    return math.max(byColumn, byFlex);
  }

  Widget _buildStacked(double width) {
    // One labelled value per line on a phone; two or three across where
    // there is room, so a tablet does not waste its width.
    final columns = width < 520
        ? 1
        : width < 860
        ? 2
        : 3;
    const horizontalPadding = 16.0;
    const gap = 16.0;
    final cellWidth =
        (width - horizontalPadding * 2 - gap * (columns - 1)) / columns;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rows[rowIndex].isNotEmpty) rows[rowIndex].first,
                if (rows[rowIndex].length > 1) const SizedBox(height: 6),
                Wrap(
                  spacing: gap,
                  runSpacing: 8,
                  children: [
                    for (int i = 1; i < rows[rowIndex].length; i++)
                      SizedBox(
                        width: cellWidth,
                        child: _stackedCell(
                          label: i < headers.length ? headers[i] : '',
                          value: rows[rowIndex][i],
                          labelBeside: columns == 1,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (rowIndex != rows.length - 1)
            const Divider(height: 1, color: AppColors.gray200),
        ],
      ],
    );
  }

  Widget _stackedCell({
    required String label,
    required Widget value,
    required bool labelBeside,
  }) {
    final labelText = Text(
      label,
      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
    );

    // An action column has no heading; its button stands on its own.
    if (label.isEmpty) return value;

    if (labelBeside) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: labelText),
          const SizedBox(width: 8),
          Expanded(child: value),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [labelText, const SizedBox(height: 2), value],
    );
  }

  @override
  Widget build(BuildContext context) {
    final columnFlexes = flexes ?? List.filled(headers.length, 1);

    return SectionCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < _minimumTableWidth) {
            return _buildStacked(constraints.maxWidth);
          }

          return Column(
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
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            headers[i],
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.gray200),
              for (int rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
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
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: rows[rowIndex][i],
                          ),
                        ),
                    ],
                  ),
                ),
                if (rowIndex != rows.length - 1)
                  const Divider(height: 1, color: AppColors.gray200),
              ],
            ],
          );
        },
      ),
    );
  }
}
