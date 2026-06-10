import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_theme_extension.dart';
import 'app_typography.dart';

/// Single source of truth for the application's [ThemeData].
///
/// Use [AppTheme.light] and [AppTheme.dark] in [MaterialApp]. All colors are
/// pulled from [AppColors]; semantic extras live in [AppThemeColors].
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
    brightness: Brightness.light,
    primary: AppColors.lightPrimary,
    onPrimary: AppColors.onPrimaryLight,
    scaffold: AppColors.lightScaffold,
    surface: AppColors.lightSurface,
    surfaceRaised: AppColors.lightSurfaceRaised,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    divider: AppColors.lightDivider,
    error: AppColors.lightError,
    extension: AppThemeColors.light,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.onPrimaryDark,
    scaffold: AppColors.darkScaffold,
    surface: AppColors.darkSurface,
    surfaceRaised: AppColors.darkSurfaceRaised,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    divider: AppColors.darkDivider,
    error: AppColors.darkError,
    extension: AppThemeColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color scaffold,
    required Color surface,
    required Color surfaceRaised,
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
    required Color error,
    required AppThemeColors extension,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primary.withValues(alpha: 0.18),
      onPrimaryContainer: textPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      secondaryContainer: surfaceRaised,
      onSecondaryContainer: textPrimary,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceRaised,
      surfaceContainerHigh: surfaceRaised,
      onSurfaceVariant: textSecondary,
      error: error,
      onError: AppColors.onPrimaryLight,
      outline: divider,
      outlineVariant: divider,
      shadow: const Color(0xFF000000),
    );

    final textTheme = AppTypography.textTheme(
      primary: textPrimary,
      secondary: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: divider,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[extension],

      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 1,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: AppRadii.rXl),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brXl),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(color: extension.textMuted),
        labelStyle: TextStyle(color: textSecondary),
        border: const OutlineInputBorder(
          borderRadius: AppRadii.brXl,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.brXl,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.brXl,
          borderSide: BorderSide(color: primary, width: 1.2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadii.brXl,
          borderSide: BorderSide(color: AppColors.transparent),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
          textStyle: textTheme.labelLarge,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: textTheme.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.brMd),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textPrimary),
      ),

      iconTheme: IconThemeData(color: textPrimary),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brXxl),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brSheet),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceRaised,
        contentTextStyle: TextStyle(color: textPrimary),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.brLg),
      ),

      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        selectedColor: primary,
        selectedTileColor: primary.withValues(alpha: 0.1),
      ),
    );
  }
}
