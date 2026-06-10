import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extension.dart';

/// A single chat message bubble.
///
/// Own messages are right-aligned and use `myMessageBubble`; others are
/// left-aligned and use `otherMessageBubble`. For grouped messages the caller
/// can hide the author name / avatar and reserve the avatar gutter via
/// [reserveAvatarSpace] to keep alignment.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.onTap,
    required this.onLongPress,
    this.showAuthor = false,
    this.authorName = '',
    this.avatar,
    this.attachments = const [],
  });

  final ChatMessage message;
  final bool isMe;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Whether to render [authorName] above the text (group/server chats).
  final bool showAuthor;
  final String authorName;

  /// Avatar widget for the author (others only); null hides it but keeps the
  /// left gutter so grouped follow-up messages stay aligned.
  final Widget? avatar;

  final List<Widget> attachments;

  static const double _avatarGutter = 40;

  /// Mobile: ~80% of the screen. Tablet/web (>= 700px): capped at 600px so
  /// bubbles stay readable instead of stretching across a wide window.
  double _maxBubbleWidth(double screenWidth) {
    if (screenWidth >= 700) return 600;
    return screenWidth * 0.8;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.appColors;
    final isSending = message.status == "sending";

    final bubbleColor = isMe
        ? extra.myMessageBubble.withValues(alpha: isSending ? 0.6 : 1.0)
        : extra.otherMessageBubble;

    const tail = Radius.circular(AppRadii.sm);
    const main = Radius.circular(AppRadii.message);
    final shape = BorderRadius.only(
      topLeft: main,
      topRight: main,
      bottomLeft: isMe ? main : tail,
      bottomRight: isMe ? tail : main,
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _maxBubbleWidth(MediaQuery.of(context).size.width),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              SizedBox(
                width: _avatarGutter,
                child: avatar == null
                    ? null
                    : Align(
                        alignment: Alignment.bottomLeft,
                        child: avatar,
                      ),
              ),
            ],
            Flexible(
              child: Material(
                color: bubbleColor,
                borderRadius: shape,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showAuthor)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Text(
                              authorName,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        if (message.content.isNotEmpty)
                          Text(
                            message.content,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ...attachments,
                        const SizedBox(height: AppSpacing.xs),
                        _buildFooter(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final extra = context.appColors;
    final isSending = message.status == "sending";
    final time =
        "${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}";

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.pinnedAt != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Icon(
              Icons.push_pin_rounded,
              size: 10,
              color: extra.warning,
            ),
          ),
        Text(
          time,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: extra.textMuted,
            letterSpacing: 0,
          ),
        ),
        if (isMe)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: Icon(
              isSending
                  ? Icons.access_time_rounded
                  : (message.status == "read"
                        ? Icons.done_all_rounded
                        : Icons.done_rounded),
              size: 14,
              color: message.status == "read"
                  ? Theme.of(context).colorScheme.primary
                  : extra.textMuted,
            ),
          ),
      ],
    );
  }
}
