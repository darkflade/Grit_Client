import 'package:flutter/material.dart';

import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extension.dart';

/// A surface container with a unified background, radius and padding.
///
/// Supports an optional [border] and an optional [onTap] (adds ink feedback).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadii.lg,
    this.border = false,
    this.backgroundColor,
    this.onTap,
    this.clipContent = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool border;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  /// When true the content is clipped to the rounded corners (useful when the
  /// child paints to the edges, e.g. a [Column] of list tiles).
  final bool clipContent;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.all(Radius.circular(radius));
    final scheme = Theme.of(context).colorScheme;

    Widget content = Padding(padding: padding, child: child);

    if (border) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: context.appColors.divider),
        ),
        child: content,
      );
    }

    return Material(
      color: backgroundColor ?? scheme.surface,
      borderRadius: borderRadius,
      clipBehavior: clipContent ? Clip.antiAlias : Clip.none,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: content,
            ),
    );
  }
}
