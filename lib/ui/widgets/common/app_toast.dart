import 'package:flutter/material.dart';

enum AppToastTone { info, clientError, serverError }

class AppToast {
  const AppToast._();

  static void show(
    BuildContext context, {
    required String message,
    int? statusCode,
    AppToastTone? tone,
  }) {
    showWithMessenger(
      ScaffoldMessenger.of(context),
      context: context,
      message: message,
      statusCode: statusCode,
      tone: tone,
    );
  }

  static void showWithMessenger(
    ScaffoldMessengerState messenger, {
    required BuildContext context,
    required String message,
    int? statusCode,
    AppToastTone? tone,
  }) {
    final resolvedTone =
        tone ??
        (statusCode != null && statusCode >= 500
            ? AppToastTone.serverError
            : statusCode != null && statusCode >= 400
            ? AppToastTone.clientError
            : AppToastTone.info);
    final colors = _ToastColors.resolve(context, resolvedTone);

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        content: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: colors.fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border, width: 1.5),
          ),
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastColors {
  final Color fill;
  final Color border;
  final Color text;

  const _ToastColors({
    required this.fill,
    required this.border,
    required this.text,
  });

  static _ToastColors resolve(BuildContext context, AppToastTone tone) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      AppToastTone.clientError => _ToastColors(
        fill: dark ? const Color(0xFF2A1D08) : const Color(0xFFFFF2D8),
        border: dark ? const Color(0xFFB56A00) : const Color(0xFFFFC86B),
        text: dark ? const Color(0xFFFFB84D) : const Color(0xFFC56300),
      ),
      AppToastTone.serverError => _ToastColors(
        fill: dark ? const Color(0xFF2B1013) : const Color(0xFFFFE3E5),
        border: dark ? const Color(0xFFD14A55) : const Color(0xFFFF9AA2),
        text: dark ? const Color(0xFFFF7A84) : const Color(0xFFC92535),
      ),
      AppToastTone.info => _ToastColors(
        fill: scheme.surfaceContainerHighest,
        border: scheme.outlineVariant,
        text: scheme.onSurface,
      ),
    };
  }
}
