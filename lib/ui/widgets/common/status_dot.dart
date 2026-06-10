import 'package:flutter/material.dart';

import '../../theme/app_theme_extension.dart';

/// A small circular presence indicator.
///
/// Resolves its color from [BuildContext.presenceColor] so the mapping
/// (`online` -> success, `idle` -> warning, `dnd` -> error,
/// `offline` / unknown -> textMuted) stays consistent everywhere.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.status,
    this.size = 12,
    this.ringColor,
    this.ringWidth = 2,
  });

  /// Presence status string (`online`, `idle`, `dnd`, `offline`, ...).
  final String status;

  /// Diameter of the dot.
  final double size;

  /// Optional ring drawn around the dot (useful over avatars / headers).
  final Color? ringColor;

  /// Width of the optional ring.
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.presenceColor(status),
        shape: BoxShape.circle,
        border: ringColor != null
            ? Border.all(color: ringColor!, width: ringWidth)
            : null,
      ),
    );
  }
}
