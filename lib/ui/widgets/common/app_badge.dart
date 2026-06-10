import 'package:flutter/material.dart';

import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extension.dart';

/// Visual emphasis of a badge.
enum AppBadgeVariant { accent, error, muted }

/// A compact pill used for unread counts or short text labels.
///
/// Provide either [count] (rendered as a number, with optional [maxCount]
/// overflow as `N+`) or [text]. [count] takes precedence when both are set.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    this.text,
    this.count,
    this.variant = AppBadgeVariant.accent,
    this.maxCount = 99,
  }) : assert(text != null || count != null, 'Provide text or count');

  final String? text;
  final int? count;
  final AppBadgeVariant variant;
  final int maxCount;

  String get _label {
    if (count != null) {
      return count! > maxCount ? '$maxCount+' : '$count';
    }
    return text ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.appColors;

    late final Color background;
    late final Color foreground;
    switch (variant) {
      case AppBadgeVariant.accent:
        background = scheme.primary;
        foreground = scheme.onPrimary;
        break;
      case AppBadgeVariant.error:
        background = scheme.error;
        foreground = scheme.onError;
        break;
      case AppBadgeVariant.muted:
        background = extra.surfaceRaised;
        foreground = extra.textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
      ),
      child: Text(
        _label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
