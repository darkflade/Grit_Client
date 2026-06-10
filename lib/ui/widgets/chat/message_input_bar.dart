import 'package:flutter/material.dart';

import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extension.dart';

/// Sticky bottom composer: an attachment button on the left, a text field on
/// a raised surface in the middle and an accent "send" pill on the right.
///
/// Purely presentational — sending/attaching/typing are delegated to the
/// provided callbacks.
class MessageInputBar extends StatelessWidget {
  const MessageInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    this.onChanged,
    this.sending = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final ValueChanged<String>? onChanged;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extra = context.appColors;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: extra.surfaceRaised,
            borderRadius: const BorderRadius.all(Radius.circular(28)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  color: scheme.primary,
                ),
                tooltip: 'Attach',
                onPressed: sending ? null : onAttach,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !sending,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  onChanged: onChanged,
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: AppRadii.brLg,
                ),
                child: IconButton(
                  icon: sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.onPrimary,
                            ),
                          ),
                        )
                      : Icon(Icons.send_rounded, color: scheme.onPrimary),
                  onPressed: sending ? null : onSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
