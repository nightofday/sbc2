import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTextStyles {
  const AppTextStyles._();

  static const display = TextStyle(
    fontFamily: 'Inter',
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.black,
  );

  static const h1 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.black,
  );

  static const h2 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.black,
  );

  static const h3 = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.black,
  );

  static const body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.black,
  );

  static const bodyMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.45,
    color: AppColors.black,
  );

  static const caption = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.gray700,
  );

  static const overline = TextStyle(
    fontFamily: 'Inter',
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: .7,
    color: AppColors.primary,
  );
}
