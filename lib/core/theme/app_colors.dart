import 'package:flutter/material.dart';

/// Colour tokens. They are the Material 3 colour roles of [AppTheme], kept
/// as constants so widgets that style text directly match the theme.
///
/// The brand red is darkened slightly from the logo red (#F40002) so white
/// text on it meets the 4.5:1 contrast minimum.
class AppColors {
  const AppColors._();

  // Brand -----------------------------------------------------------------
  static const primary = Color(0xFFD70002);
  static const primaryDark = Color(0xFFAE0002);

  /// Tinted fill behind brand content: selected items, soft badges.
  static const primarySoft = Color(0xFFFFDAD5);
  static const onPrimarySoft = Color(0xFF410001);

  // Accents used for figures and states -----------------------------------
  static const orange = Color(0xFFB45309);
  static const yellow = Color(0xFFF5C451);

  // Neutrals (surface and text roles) -------------------------------------
  /// Main text. Material `onSurface`.
  static const black = Color(0xFF1D1B1B);
  static const gray900 = Color(0xFF322F2F);

  /// Secondary text and icons. Material `onSurfaceVariant`.
  static const gray700 = Color(0xFF524747);

  /// Placeholder text and quiet icons. Material `outline`.
  static const gray500 = Color(0xFF857575);

  /// Field and control borders. Material `outlineVariant`.
  static const gray300 = Color(0xFFD8CFCE);

  /// Dividers and card borders.
  static const gray200 = Color(0xFFEAE4E3);

  /// Page background. Material `surface`.
  static const gray100 = Color(0xFFF8F5F4);

  /// Cards, dialogs and sheets. Material `surfaceContainerLowest`.
  static const white = Color(0xFFFFFFFF);

  // States ------------------------------------------------------------------
  static const success = Color(0xFF1B7A3A);
  static const warning = Color(0xFF8F5B00);
  static const info = Color(0xFF0061A4);
  static const error = Color(0xFFBA1A1A);
}
