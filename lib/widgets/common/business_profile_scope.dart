import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/business_profile.dart';

/// Makes the business details available to every screen and dialog, and
/// rebuilds what shows them when management changes them.
class BusinessProfileScope
    extends InheritedNotifier<ValueNotifier<BusinessProfile>> {
  const BusinessProfileScope({
    super.key,
    required ValueNotifier<BusinessProfile> super.notifier,
    required super.child,
  });

  /// The current details, or the fallback where no scope is present.
  static BusinessProfile of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<BusinessProfileScope>();
    return scope?.notifier?.value ?? BusinessProfile.fallback;
  }
}

/// The top of a receipt: business name, then address, phone and TIN.
class ReceiptHeader extends StatelessWidget {
  const ReceiptHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = BusinessProfileScope.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          profile.tradeName,
          textAlign: TextAlign.center,
          style: AppTextStyles.h2,
        ),
        for (final line in profile.receiptLines)
          Text(
            line,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: AppColors.gray700),
          ),
      ],
    );
  }
}
