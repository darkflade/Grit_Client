import 'package:flutter/material.dart';

import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../common/app_avatar.dart';
import '../common/app_badge.dart';

/// A navigation tile representing a server: rounded server icon/avatar, name,
/// a selected state with a left accent indicator + tinted background, ripple
/// feedback, and an optional unread badge (rendered only when [unreadCount]
/// is greater than zero).
class ServerTile extends StatelessWidget {
  const ServerTile({
    super.key,
    required this.name,
    required this.selected,
    required this.onTap,
    this.icon,
    this.unreadCount,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  /// Optional server icon image; falls back to initials.
  final ImageProvider? icon;

  final int? unreadCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showBadge = unreadCount != null && unreadCount! > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.brMd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
              borderRadius: AppRadii.brMd,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _AccentIndicator(visible: selected),
                const SizedBox(width: AppSpacing.sm),
                AppAvatar(name: name, image: icon, size: AppAvatarSize.small),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ),
                if (showBadge) ...[
                  const SizedBox(width: AppSpacing.sm),
                  AppBadge(count: unreadCount, variant: AppBadgeVariant.error),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin rounded vertical bar shown to the left of a selected navigation tile.
class _AccentIndicator extends StatelessWidget {
  const _AccentIndicator({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 4,
      height: visible ? 22 : 0,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: AppRadii.brSm,
      ),
    );
  }
}
