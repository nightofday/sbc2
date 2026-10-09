import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Brand red darkened from F40002 so white text on it, and red text on
  // white, stay readable.
  static const primary = Color(0xFFC90002);
  static const primaryDark = Color(0xFF9E0002);
  static const primarySoft = Color(0xFFFFE8E8);
  static const orange = Color(0xFFFF7A00);
  static const yellow = Color(0xFFFFC400);

  static const black = Color(0xFF171717);
  static const gray900 = Color(0xFF2B2B2B);
  static const gray700 = Color(0xFF5B5B5B);
  static const gray500 = Color(0xFF757575);
  static const gray300 = Color(0xFFCFCCC6);
  static const gray200 = Color(0xFFE2E0DC);
  static const gray100 = Color(0xFFF6F5F3);
  static const white = Color(0xFFFFFFFF);

  // Status colours are dark enough to use as text on white.
  static const success = Color(0xFF1F7A3A);
  static const warning = Color(0xFF9A5200);
  static const info = Color(0xFF1D5F99);
  static const error = primary;
}
