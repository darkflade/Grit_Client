import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';

/// Scrollable message list.
///
/// Keeps the original reversed list + [scrollController] wiring intact (so
/// auto-scroll / pagination behavior is unchanged) and adds grouping: a
/// message is flagged as the first of its group when the previous (older)
/// message has a different sender, letting the caller hide repeated
/// avatars / author names.
class MessagesView extends StatelessWidget {
  const MessagesView({
    super.key,
    required this.scrollController,
    required this.messages,
    required this.currentUserId,
    required this.isLoading,
    required this.loadingFooter,
    required this.itemBuilder,
  });

  final ScrollController scrollController;
  final List<ChatMessage> messages;
  final String currentUserId;
  final bool isLoading;

  /// Footer widget shown at the end of the (reversed) list, e.g. a
  /// "load more" spinner.
  final Widget loadingFooter;

  /// Builds a single row. [isFirstOfGroup] is true when this message starts a
  /// new run from its author.
  final Widget Function(ChatMessage msg, bool isMe, bool isFirstOfGroup)
  itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !isLoading) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: AppRadii.brXl,
          ),
          child: Text(
            "No messages yet.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      reverse: true,
      itemCount: messages.length + 1,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return loadingFooter;
        }
        final msg = messages[index];
        final isMe = msg.senderId == currentUserId;
        // Reversed list: the visually-previous (older) message is at index + 1.
        final older = index + 1 < messages.length ? messages[index + 1] : null;
        final isFirstOfGroup = older == null || older.senderId != msg.senderId;
        return Padding(
          padding: EdgeInsets.only(
            top: isFirstOfGroup ? AppSpacing.sm : 1,
          ),
          child: itemBuilder(msg, isMe, isFirstOfGroup),
        );
      },
    );
  }
}
