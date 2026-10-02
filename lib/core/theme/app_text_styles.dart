import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Text styles on the Material 3 type scale, in the platform's own font
/// (Roboto on Android). Each one names the Material role it stands for.
class AppTextStyles {
  const AppTextStyles._();

  /// Android's system font. Where it is not installed the platform's own
  /// font is used instead.
  static const fontFamily = 'Roboto';

  /// Large figures such as today's sales. Material `headlineLarge`.
  static const display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: AppColors.black,
  );

  /// Page titles. Material `headlineSmall`.
  static const h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.33,
    color: AppColors.black,
  );

  /// Dialog and section titles. Material `titleLarge`.
  static const h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.black,
  );

  /// Card titles and emphasised labels. Material `titleMedium`.
  static const h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: .15,
    color: AppColors.black,
  );

  /// Body text. Material `bodyMedium`.
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: .25,
    color: AppColors.black,
  );

  /// Emphasised body text and values. Material `titleSmall`.
  static const bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.43,
    letterSpacing: .1,
    color: AppColors.black,
  );

  /// Supporting text. Material `bodySmall`.
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: .4,
    color: AppColors.gray700,
  );

  /// Section labels in navigation and forms. Material `labelSmall`.
  static const overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.45,
    letterSpacing: .5,
    color: AppColors.gray700,
  );
}
