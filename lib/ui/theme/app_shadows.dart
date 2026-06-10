import 'package:flutter/widgets.dart';

/// Elevation / shadow tokens. Shadows are tinted per-theme by passing the
/// appropriate base color (usually `colorScheme.shadow`).
class AppShadows {
  AppShadows._();

  /// Subtle shadow for raised cards and panels.
  static List<BoxShadow> soft(Color base) => [
    BoxShadow(
      color: base.withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  /// Stronger shadow for floating elements (incoming call card, dialogs).
  static List<BoxShadow> elevated(Color base) => [
    BoxShadow(
      color: base.withValues(alpha: 0.20),
      blurRadius: 20,
      offset: const Offset(0, 10),
    ),
  ];
}
