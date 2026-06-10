import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme extension carrying semantic colors that don't fit the Material
/// [ColorScheme] cleanly (message bubbles, status colors, muted text, etc.).
///
/// Access from widgets via:
/// ```dart
/// final c = Theme.of(context).extension<AppThemeColors>()!;
/// ```
@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  const AppThemeColors({
    required this.surfaceRaised,
    required this.textMuted,
    required this.divider,
    required this.myMessageBubble,
    required this.otherMessageBubble,
    required this.success,
    required this.warning,
    required this.overlay,
    required this.onAccent,
  });

  final Color surfaceRaised;
  final Color textMuted;
  final Color divider;
  final Color myMessageBubble;
  final Color otherMessageBubble;
  final Color success;
  final Color warning;
  final Color overlay;

  /// Foreground color drawn on top of strongly saturated status/action
  /// surfaces (call accept/decline buttons, media thumbnails). Stays a neutral
  /// light tone in both themes so icons/text remain legible on colored fills.
  final Color onAccent;

  static const AppThemeColors dark = AppThemeColors(
    surfaceRaised: AppColors.darkSurfaceRaised,
    textMuted: AppColors.darkTextMuted,
    divider: AppColors.darkDivider,
    myMessageBubble: AppColors.darkMyMessageBubble,
    otherMessageBubble: AppColors.darkOtherMessageBubble,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    overlay: AppColors.darkOverlay,
    onAccent: AppColors.onPrimaryLight,
  );

  static const AppThemeColors light = AppThemeColors(
    surfaceRaised: AppColors.lightSurfaceRaised,
    textMuted: AppColors.lightTextMuted,
    divider: AppColors.lightDivider,
    myMessageBubble: AppColors.lightMyMessageBubble,
    otherMessageBubble: AppColors.lightOtherMessageBubble,
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    overlay: AppColors.lightOverlay,
    onAccent: AppColors.onPrimaryLight,
  );

  @override
  AppThemeColors copyWith({
    Color? surfaceRaised,
    Color? textMuted,
    Color? divider,
    Color? myMessageBubble,
    Color? otherMessageBubble,
    Color? success,
    Color? warning,
    Color? overlay,
    Color? onAccent,
  }) {
    return AppThemeColors(
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      textMuted: textMuted ?? this.textMuted,
      divider: divider ?? this.divider,
      myMessageBubble: myMessageBubble ?? this.myMessageBubble,
      otherMessageBubble: otherMessageBubble ?? this.otherMessageBubble,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      overlay: overlay ?? this.overlay,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      myMessageBubble: Color.lerp(
        myMessageBubble,
        other.myMessageBubble,
        t,
      )!,
      otherMessageBubble: Color.lerp(
        otherMessageBubble,
        other.otherMessageBubble,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// Convenience accessor for the semantic colors extension.
extension AppThemeColorsX on BuildContext {
  AppThemeColors get appColors =>
      Theme.of(this).extension<AppThemeColors>() ?? AppThemeColors.dark;

  /// Maps a user presence status (`online` / `idle` / `dnd` / anything else)
  /// to a theme-aware semantic color. Centralizes the previously duplicated
  /// `Colors.green/orange/red/grey` logic so presence dots stay consistent.
  Color presenceColor(String status) {
    final colors = appColors;
    switch (status.toLowerCase()) {
      case 'online':
        return colors.success;
      case 'idle':
        return colors.warning;
      case 'dnd':
        return Theme.of(this).colorScheme.error;
      default:
        return colors.textMuted;
    }
  }
}
