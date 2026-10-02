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

/// Asks for a required reason, then runs [onConfirm] with it.
///
/// [onConfirm] returns null on success, or the message to show. On failure
/// the dialog stays open so the typed reason is kept. Returns true once
/// [onConfirm] has succeeded.
Future<bool> showReasonDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required Future<String?> Function(String reason) onConfirm,
  String reasonLabel = 'Reason *',
}) async {
  final controller = TextEditingController();
  String? errorMessage;
  var busy = false;
  var confirmed = false;
  StateSetter? setDialogState;

  await showPrototypeDialog<void>(
    context: context,
    title: title,
    width: 480,
    content: StatefulBuilder(
      builder: (_, setState) {
        setDialogState = setState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: AppTextStyles.body),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: InputDecoration(labelText: reasonLabel),
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                errorMessage!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
              ),
            ],
          ],
        );
      },
    ),
    actions: [
      Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
      ),
      Builder(
        builder: (dialogContext) => ElevatedButton(
          onPressed: () async {
            if (busy) return;

            final reason = controller.text.trim();
            if (reason.isEmpty) {
              setDialogState?.call(() {
                errorMessage = 'Enter a reason.';
              });
              return;
            }

            busy = true;
            final failure = await onConfirm(reason);
            busy = false;

            if (failure != null) {
              setDialogState?.call(() {
                errorMessage = failure;
              });
              return;
            }

            confirmed = true;
            if (dialogContext.mounted) Navigator.pop(dialogContext);
          },
          child: Text(confirmLabel),
        ),
      ),
    ],
  );

  controller.dispose();
  return confirmed;
}
