import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Presentational scaffold for the app's navigation drawer.
///
/// Provides a themed surface panel with a [header], a scrollable list of
/// section [children] and an optional [footer] (e.g. logout). All business
/// logic stays in the screen that composes these slots.
class AppDrawerPanel extends StatelessWidget {
  const AppDrawerPanel({
    super.key,
    required this.header,
    required this.children,
    this.footer,
    this.width,
  });

  final Widget header;
  final List<Widget> children;
  final Widget? footer;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: width,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          header,
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: children,
            ),
          ),
          if (footer != null) ...[
            Divider(
              height: 1,
              color: Theme.of(context).dividerColor,
            ),
            SafeArea(top: false, child: footer!),
          ],
        ],
      ),
    );
  }
}
