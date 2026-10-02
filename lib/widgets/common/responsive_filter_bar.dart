import 'package:flutter/material.dart';

/// Keeps list filters consistent and prevents narrow-screen row overflows.
class ResponsiveFilterBar extends StatelessWidget {
  final Widget primary;
  final List<Widget> filters;
  final List<double> filterWidths;
  final double breakpoint;
  final double gap;

  const ResponsiveFilterBar({
    super.key,
    required this.primary,
    required this.filters,
    required this.filterWidths,
    this.breakpoint = 760,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    assert(filters.length == filterWidths.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              for (final filter in filters) ...[SizedBox(height: gap), filter],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: primary),
            for (int index = 0; index < filters.length; index++) ...[
              SizedBox(width: gap),
              SizedBox(width: filterWidths[index], child: filters[index]),
            ],
          ],
        );
      },
    );
  }
}
