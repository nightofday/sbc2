import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The one type scale used across the app. Every style is Inter, the font
/// bundled in `assets/fonts/`, with tabular figures so amounts and
/// quantities line up in columns.
class AppTextStyles {
  const AppTextStyles._();

  static const fontFamily = 'Inter';
  static const _figures = [FontFeature.tabularFigures()];

  /// Page titles.
  static const display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -.2,
    fontFeatures: _figures,
    color: AppColors.black,
  );

  static const h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    fontFeatures: _figures,
    color: AppColors.black,
  );

  /// Section and dialog titles.
  static const h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _figures,
    color: AppColors.black,
  );

  /// Card titles and item names.
  static const h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    fontFeatures: _figures,
    color: AppColors.black,
  );

  /// Body text, table cells and form input.
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.45,
    fontFeatures: _figures,
    color: AppColors.black,
  );

  /// Emphasised body text, field labels and button labels.
  static const bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.45,
    fontFeatures: _figures,
    color: AppColors.black,
  );

  /// Helper text, secondary details and badges.
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontFeatures: _figures,
    color: AppColors.gray700,
  );

  /// Small group headings, such as sidebar sections.
  static const overline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: .6,
    fontFeatures: _figures,
    color: AppColors.primary,
  );
}
