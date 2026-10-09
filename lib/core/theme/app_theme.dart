import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_text_styles.dart';

class AppTheme {
  const AppTheme._();

  static const _shape = RoundedRectangleBorder(borderRadius: AppRadius.all);

  static ThemeData get light {
    const border = OutlineInputBorder(
      borderRadius: AppRadius.all,
      borderSide: BorderSide(color: AppColors.gray300),
    );

    // Every Material text slot maps to the app's scale, so widgets that pick
    // their own slot (fields, list tiles, chips, menus, snack bars) use the
    // same font sizes and weights as the screens around them.
    const textTheme = TextTheme(
      displayLarge: AppTextStyles.display,
      displayMedium: AppTextStyles.display,
      displaySmall: AppTextStyles.display,
      headlineLarge: AppTextStyles.h1,
      headlineMedium: AppTextStyles.h2,
      headlineSmall: AppTextStyles.h3,
      titleLarge: AppTextStyles.h2,
      titleMedium: AppTextStyles.h3,
      titleSmall: AppTextStyles.bodyMedium,
      bodyLarge: AppTextStyles.body,
      bodyMedium: AppTextStyles.body,
      bodySmall: AppTextStyles.caption,
      labelLarge: AppTextStyles.bodyMedium,
      labelMedium: AppTextStyles.bodyMedium,
      labelSmall: AppTextStyles.caption,
    );

    final buttonText = WidgetStatePropertyAll(AppTextStyles.bodyMedium);

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTextStyles.fontFamily,
      scaffoldBackgroundColor: AppColors.gray100,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.white,
        secondary: AppColors.orange,
        onSecondary: AppColors.white,
        surface: AppColors.white,
        onSurface: AppColors.black,
        onSurfaceVariant: AppColors.gray700,
        outline: AppColors.gray300,
        outlineVariant: AppColors.gray200,
        error: AppColors.error,
        onError: AppColors.white,
      ),
      textTheme: textTheme,
      dividerColor: AppColors.gray200,
      dividerTheme: const DividerThemeData(
        color: AppColors.gray200,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: _shape,
          textStyle: AppTextStyles.bodyMedium,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: _shape,
          textStyle: AppTextStyles.bodyMedium,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.black,
          side: const BorderSide(color: AppColors.gray300),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: _shape,
          textStyle: AppTextStyles.bodyMedium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: _shape,
          textStyle: AppTextStyles.bodyMedium,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: _shape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: AppTextStyles.body.copyWith(color: AppColors.gray700),
        floatingLabelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.gray900,
        ),
        hintStyle: AppTextStyles.body.copyWith(color: AppColors.gray500),
        helperStyle: AppTextStyles.caption,
        errorStyle: AppTextStyles.caption.copyWith(color: AppColors.error),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppTextStyles.body,
        menuStyle: const MenuStyle(shape: WidgetStatePropertyAll(_shape)),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(shape: WidgetStatePropertyAll(_shape)),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(textStyle: buttonText),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: _shape,
        textStyle: AppTextStyles.body,
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.all,
          side: BorderSide(color: AppColors.gray300),
        ),
        side: const BorderSide(color: AppColors.gray300),
        backgroundColor: AppColors.white,
        selectedColor: AppColors.primarySoft,
        labelStyle: AppTextStyles.bodyMedium,
        checkmarkColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        shape: _shape,
        titleTextStyle: AppTextStyles.bodyMedium,
        subtitleTextStyle: AppTextStyles.caption,
        leadingAndTrailingTextStyle: AppTextStyles.body,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.gray700,
        ),
        dataTextStyle: AppTextStyles.body,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: AppTextStyles.bodyMedium,
        unselectedLabelStyle: AppTextStyles.body,
        labelColor: AppColors.black,
        unselectedLabelColor: AppColors.gray700,
        indicatorColor: AppColors.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: _shape,
        backgroundColor: AppColors.black,
        contentTextStyle: AppTextStyles.body.copyWith(color: AppColors.white),
        actionTextColor: AppColors.yellow,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: AppColors.gray900,
          borderRadius: AppRadius.all,
        ),
        textStyle: AppTextStyles.caption.copyWith(color: AppColors.white),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all,
          side: BorderSide(color: AppColors.gray200),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: _shape,
        titleTextStyle: AppTextStyles.h2,
        contentTextStyle: AppTextStyles.body,
      ),
    );
  }
}
