import 'package:flutter/material.dart';

import 'status_dot.dart';

/// Avatar sizes used across the app.
enum AppAvatarSize { small, medium, large }

/// A circular avatar that shows an [image] when provided and otherwise falls
/// back to the first initial of [name]. An optional presence [status] renders
/// a [StatusDot] in the bottom-right corner.
///
/// The widget is intentionally decoupled from networking: callers that load
/// avatar bytes themselves (e.g. via an API client + `FutureBuilder`) pass the
/// resulting [ImageProvider] in [image].
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.image,
    this.status,
    this.size = AppAvatarSize.medium,
  });

  final String name;
  final ImageProvider? image;

  /// Presence status; when non-null a [StatusDot] is overlaid.
  final String? status;

  final AppAvatarSize size;

  double get _radius {
    switch (size) {
      case AppAvatarSize.small:
        return 16;
      case AppAvatarSize.medium:
        return 24;
      case AppAvatarSize.large:
        return 32;
    }
  }

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = _radius;

    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      backgroundImage: image,
      child: image == null
          ? Text(
              _initial,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );

    if (status == null) return avatar;

    final dotSize = (radius * 0.55).clamp(8.0, 16.0).toDouble();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: StatusDot(
            status: status!,
            size: dotSize,
            ringColor: scheme.surface,
          ),
        ),
      ],
    );
  }
}
