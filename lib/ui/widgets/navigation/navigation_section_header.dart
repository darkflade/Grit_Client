import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Uppercase section label for the navigation drawer, with optional trailing
/// action buttons (e.g. "create server" / "accept invite").
///
/// Discord-style: muted text, generous letter spacing, compact actions.
class NavigationSectionHeader extends StatelessWidget {
  const NavigationSectionHeader({
    super.key,
    required this.label,
    this.actions = const [],
  });

  final String label;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
