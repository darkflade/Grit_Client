import 'package:flutter/material.dart';

import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../common/app_avatar.dart';

/// A navigation tile representing a direct message room: avatar (with a
/// presence status dot for 1:1 chats), title/username, selected accent state
/// and ripple feedback.
class DirectRoomTile extends StatelessWidget {
  const DirectRoomTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.avatar,
    this.status,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  /// Optional avatar image; falls back to initials.
  final ImageProvider? avatar;

  /// Presence status of the counterpart (1:1 only); null hides the dot.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                AppAvatar(
                  name: title,
                  image: avatar,
                  status: status,
                  size: AppAvatarSize.small,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
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
