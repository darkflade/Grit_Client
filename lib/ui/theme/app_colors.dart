import 'package:flutter/material.dart';

/// Centralized color tokens for the application.
///
/// All raw color values live here and nowhere else. Widgets must never use
/// `Colors.*` or `Color(0x...)` directly — they should read colors from the
/// active [ThemeData] / [ColorScheme] or from [AppThemeColors] (theme
/// extension) instead.
class AppColors {
  AppColors._();

  // ---------------------------------------------------------------------------
  // Dark palette
  // ---------------------------------------------------------------------------
  static const Color darkPrimary = Color(0xFFF4A524);
  static const Color darkScaffold = Color(0xFF090A0C);
  static const Color darkSurface = Color(0xFF121317);
  static const Color darkSurfaceRaised = Color(0xFF1A1B20);
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF9A9BA1);
  static const Color darkTextMuted = Color(0xFF5C5D63);
  static const Color darkDivider = Color(0xFF26272E);
  static const Color darkMyMessageBubble = Color(0xFF3A2608);
  static const Color darkOtherMessageBubble = Color(0xFF1A1B20);
  static const Color darkError = Color(0xFFE5484D);
  static const Color darkSuccess = Color(0xFF3DD68C);
  static const Color darkWarning = Color(0xFFF4A524);
  static const Color darkOverlay = Color(0x99000000);

  // ---------------------------------------------------------------------------
  // Light palette
  // ---------------------------------------------------------------------------
  static const Color lightPrimary = Color(0xFFD6770B);
  static const Color lightScaffold = Color(0xFFE3EAF4);
  static const Color lightSurface = Color(0xFFFBFCFF);
  static const Color lightSurfaceRaised = Color(0xFFDFE7F2);
  static const Color lightTextPrimary = Color(0xFF0D1117);
  static const Color lightTextSecondary = Color(0xFF5A6473);
  static const Color lightTextMuted = Color(0xFF7F8A99);
  static const Color lightDivider = Color(0xFFCFD8E6);
  static const Color lightMyMessageBubble = Color(0xFFFFE3B3);
  static const Color lightOtherMessageBubble = Color(0xFFFBFCFF);
  static const Color lightError = Color(0xFFD92D20);
  static const Color lightSuccess = Color(0xFF2A9D63);
  static const Color lightWarning = Color(0xFFD6770B);
  static const Color lightOverlay = Color(0x554B5B70);

  // ---------------------------------------------------------------------------
  // Shared / neutral helpers
  // ---------------------------------------------------------------------------
  /// Color drawn on top of [darkPrimary] / [lightPrimary] (buttons, icons).
  static const Color onPrimaryDark = Color(0xFF1A1206);
  static const Color onPrimaryLight = Color(0xFFFFFFFF);

  static const Color transparent = Color(0x00000000);
}
