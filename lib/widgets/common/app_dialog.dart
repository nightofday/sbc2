import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Shows a dialog whose future completes only after the closing transition
/// has finished and the route is gone.
///
/// Callers create controllers before the dialog and dispose them after the
/// awaited call. `showDialog` completes at the pop, while the dialog is still
/// animating out and rebuilding with those controllers.
Future<T?> showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  navigator.push(route);
  return route.completed;
}

Future<T?> showPrototypeDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  double width = 520,
  bool barrierDismissible = true,
}) {
  return showSettledDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final viewport = MediaQuery.sizeOf(dialogContext);
      final compact = viewport.width < 600;
      final horizontalInset = compact ? 16.0 : 40.0;
      final contentHorizontalPadding = compact ? 18.0 : 24.0;
      final availableWidth = math.max(
        0.0,
        viewport.width - (horizontalInset * 2) - (contentHorizontalPadding * 2),
      );

      return AlertDialog(
        scrollable: true,
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: 24,
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.h2,
        ),
        contentPadding: EdgeInsets.fromLTRB(
          contentHorizontalPadding,
          18,
          contentHorizontalPadding,
          8,
        ),
        content: SizedBox(
          width: width.clamp(0.0, availableWidth).toDouble(),
          child: content,
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actionsOverflowButtonSpacing: 8,
        actions: actions.isEmpty
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ]
            : actions,
      );
    },
  );
}

Widget dialogField(
  String label, {
  String? value,
  String? hint,
  int maxLines = 1,
  TextEditingController? controller,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.gray700,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          initialValue: controller == null ? value : null,
          maxLines: maxLines,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    ),
  );
}
