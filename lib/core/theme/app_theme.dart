import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

/// The app's Material 3 theme. Components take their look from here, so
/// screens use stock Flutter widgets and get the platform's native feel.
class AppTheme {
  const AppTheme._();

  static const colorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.onPrimarySoft,
    secondary: Color(0xFF775652),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFE0DC),
    onSecondaryContainer: Color(0xFF2C1512),
    tertiary: AppColors.info,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD1E4FF),
    onTertiaryContainer: Color(0xFF001D36),
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: AppColors.gray100,
    onSurface: AppColors.black,
    onSurfaceVariant: AppColors.gray700,
    surfaceContainerLowest: AppColors.white,
    surfaceContainerLow: Color(0xFFF3EFEE),
    surfaceContainer: Color(0xFFEFEAE9),
    surfaceContainerHigh: Color(0xFFE9E4E3),
    surfaceContainerHighest: Color(0xFFE3DEDD),
    outline: AppColors.gray500,
    outlineVariant: AppColors.gray300,
    inverseSurface: Color(0xFF322F2F),
    onInverseSurface: Color(0xFFF6EFEE),
    inversePrimary: Color(0xFFFFB4A9),
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  static const _textTheme = TextTheme(
    headlineLarge: AppTextStyles.display,
    headlineMedium: TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 28,
      fontWeight: FontWeight.w500,
      height: 1.29,
      color: AppColors.black,
    ),
    headlineSmall: AppTextStyles.h1,
    titleLarge: AppTextStyles.h2,
    titleMedium: AppTextStyles.h3,
    titleSmall: AppTextStyles.bodyMedium,
    bodyLarge: TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      letterSpacing: .5,
      color: AppColors.black,
    ),
    bodyMedium: AppTextStyles.body,
    bodySmall: AppTextStyles.caption,
    labelLarge: TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.43,
      letterSpacing: .1,
    ),
    labelMedium: TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.33,
      letterSpacing: .5,
    ),
    labelSmall: AppTextStyles.overline,
  );

  static ThemeData get light {
    const scheme = colorScheme;
    final fieldRadius = BorderRadius.circular(8);
    const buttonShape = StadiumBorder();
    const buttonSize = Size(64, 44);
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20);
    const buttonText = TextStyle(
      fontFamily: AppTextStyles.fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: .1,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTextStyles.fontFamily,
      colorScheme: scheme,
      textTheme: _textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      dividerColor: AppColors.gray200,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      // Buttons: filled for the main action, outlined for secondary ones,
      // text for low-emphasis actions. All pill-shaped, as on Android.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        // Existing screens use ElevatedButton for their main action; it is
        // drawn as a Material 3 filled button.
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: .12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: .38),
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          minimumSize: const Size.square(AppSpacing.touchTarget),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
      ),

      // Fields: Material 3 outlined text fields.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(
            color: scheme.onSurface.withValues(alpha: .12),
          ),
        ),
        labelStyle: AppTextStyles.body.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: AppTextStyles.body.copyWith(color: scheme.outline),
        helperStyle: AppTextStyles.caption,
        helperMaxLines: 3,
        errorMaxLines: 3,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.white),
        ),
      ),

      // Surfaces.
      cardTheme: CardThemeData(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: const BorderSide(color: AppColors.gray200),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: AppTextStyles.h1,
        contentTextStyle: AppTextStyles.body.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: AppTextStyles.body,
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.white),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.gray200,
        thickness: 1,
        space: 1,
      ),

      // Chips: filter chips for periods and categories.
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: scheme.secondaryContainer,
        checkmarkColor: scheme.onSecondaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        secondaryLabelStyle: AppTextStyles.bodyMedium.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
        ),
      ),

      // Feedback.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTextStyles.body.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        width: 560,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: AppTextStyles.caption.copyWith(
          color: scheme.onInverseSurface,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Icon(Icons.check, size: 16)
              : null,
        ),
      ),

      // Lists and navigation.
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: AppTextStyles.body.copyWith(fontSize: 16),
        subtitleTextStyle: AppTextStyles.caption.copyWith(fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 8,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.h2.copyWith(fontSize: 22),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        // The highlight spans the drawer less its 12 dp side padding.
        indicatorSize: const Size(AppSpacing.sidebarWidth - 24, 52),
        tileHeight: 52,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTextStyles.bodyMedium.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        width: AppSpacing.sidebarWidth,
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: scheme.primary,
        dividerColor: AppColors.gray200,
        labelStyle: AppTextStyles.bodyMedium,
        unselectedLabelStyle: AppTextStyles.bodyMedium,
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
