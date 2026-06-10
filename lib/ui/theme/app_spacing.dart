import 'package:flutter/widgets.dart';

/// Spacing scale used across the app. Prefer these tokens over magic numbers
/// for paddings, margins and gaps so spacing stays consistent.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  // Common ready-made EdgeInsets to avoid repeated inline allocations.
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);

  static const EdgeInsets screen = EdgeInsets.all(lg);
  static const EdgeInsets listItem = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: sm,
  );
}
