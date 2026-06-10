import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import '../../theme/app_spacing.dart';

/// Compact horizontal bar listing pinned messages as tappable chips.
///
/// Rendering only; [onTap] surfaces the selected pinned message back to the
/// caller (which owns the pin/unpin logic).
class PinnedMessagesBar extends StatelessWidget {
  const PinnedMessagesBar({
    super.key,
    required this.pinned,
    required this.onTap,
  });

  final List<ChatMessage> pinned;
  final void Function(ChatMessage message) onTap;

  @override
  Widget build(BuildContext context) {
    if (pinned.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                "Pinned messages",
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pinned.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final message = pinned[index];
                return ActionChip(
                  avatar: const Icon(Icons.push_pin_rounded, size: 14),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      message.content.isEmpty ? "Attachment" : message.content,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: () => onTap(message),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
