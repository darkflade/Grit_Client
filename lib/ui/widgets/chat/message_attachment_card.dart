import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../data/api/rest.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme_extension.dart';

/// Renders a single message attachment: an image/video preview (when the
/// content type matches) plus a file card with icon, name, size and a download
/// action.
///
/// This widget only handles presentation; loading bytes/metadata and the
/// actual download are delegated to [apiClient] and [onDownload].
class MessageAttachmentCard extends StatelessWidget {
  const MessageAttachmentCard({
    super.key,
    required this.attachment,
    required this.apiClient,
    required this.onDownload,
  });

  /// Either a `Map` (raw json) or a typed attachment object exposing
  /// `url` / `originalName` / `sizeBytes` / `contentType`.
  final dynamic attachment;
  final ApiClient apiClient;
  final void Function(String url, String fileName) onDownload;

  static bool isImage(dynamic a) {
    String type = "";
    String name = "";
    if (a is Map) {
      type = (a['content_type'] ?? a['contentType'])?.toString() ?? "";
      name = (a['original_name'] ?? a['originalName'])?.toString() ?? "";
    } else {
      type = a.contentType?.toString() ?? "";
      name = a.originalName?.toString() ?? "";
    }
    type = type.toLowerCase();
    name = name.toLowerCase();

    if (type.startsWith("image/")) return true;
    final ext = name.split('.').last;
    return ["jpg", "jpeg", "png", "gif", "webp", "bmp"].contains(ext);
  }

  static bool isVideo(dynamic a) {
    String type = "";
    String name = "";
    if (a is Map) {
      type = (a['content_type'] ?? a['contentType'])?.toString() ?? "";
      name = (a['original_name'] ?? a['originalName'])?.toString() ?? "";
    } else {
      type = a.contentType?.toString() ?? "";
      name = a.originalName?.toString() ?? "";
    }
    type = type.toLowerCase();
    name = name.toLowerCase();

    if (type.startsWith("video/")) return true;
    final ext = name.split('.').last;
    return [
      "mp4",
      "mov",
      "wmv",
      "avi",
      "avchd",
      "flv",
      "f4v",
      "swf",
      "mkv",
      "webm",
    ].contains(ext);
  }

  static bool isAudio(dynamic a) {
    String type = "";
    String name = "";
    if (a is Map) {
      type = (a['content_type'] ?? a['contentType'])?.toString() ?? "";
      name = (a['original_name'] ?? a['originalName'])?.toString() ?? "";
    } else {
      type = a.contentType?.toString() ?? "";
      name = a.originalName?.toString() ?? "";
    }
    type = type.toLowerCase();
    name = name.toLowerCase();

    if (type.startsWith("audio/")) return true;
    final ext = name.split('.').last;
    return ["mp3", "m4a", "aac", "wav", "ogg", "opus", "flac"].contains(ext);
  }

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return "${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = isImage(attachment);
    final video = isVideo(attachment);
    final audio = isAudio(attachment);

    final String urlStr =
        (attachment is Map ? attachment['url'] : attachment.url) ?? "";
    final fullUrl = urlStr.startsWith("http")
        ? urlStr
        : "${apiClient.baseUrl}$urlStr";
    final String originalName =
        (attachment is Map
            ? (attachment['original_name'] ?? attachment['originalName'])
            : attachment.originalName) ??
        "File";
    final int sizeBytes =
        (attachment is Map
            ? (attachment['size_bytes'] ?? attachment['sizeBytes'])
            : attachment.sizeBytes) ??
        0;

    final canPreview = image || video || audio;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.brMd,
          onTap: canPreview
              ? () => _openAttachmentPreview(
                  context,
                  url: fullUrl,
                  fileName: originalName,
                  image: image,
                  video: video,
                  audio: audio,
                )
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.05),
              borderRadius: AppRadii.brMd,
            ),
            constraints: const BoxConstraints(maxWidth: 400),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image)
                  _ImageAttachmentPreview(apiClient: apiClient, url: fullUrl)
                else if (video)
                  _VideoAttachmentPlayer(
                    apiClient: apiClient,
                    url: fullUrl,
                    fileName: originalName,
                  )
                else if (audio)
                  _AudioAttachmentPlayer(
                    apiClient: apiClient,
                    url: fullUrl,
                    fileName: originalName,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadii.brSm,
                        ),
                        child: Icon(
                          image
                              ? Icons.image_rounded
                              : video
                              ? Icons.movie_rounded
                              : audio
                              ? Icons.audiotrack_rounded
                              : Icons.insert_drive_file_rounded,
                          color: scheme.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              originalName,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            _buildSizeLabel(context, sizeBytes, fullUrl),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      IconButton(
                        icon: const Icon(
                          Icons.download_for_offline_rounded,
                          size: 22,
                        ),
                        tooltip: "Download",
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onDownload(fullUrl, originalName),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openAttachmentPreview(
    BuildContext context, {
    required String url,
    required String fileName,
    required bool image,
    required bool video,
    required bool audio,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: image
                        ? _ZoomableImagePreview(apiClient: apiClient, url: url)
                        : video
                        ? _VideoAttachmentPlayer(
                            apiClient: apiClient,
                            url: url,
                            fileName: fileName,
                            expanded: true,
                          )
                        : _AudioAttachmentPlayer(
                            apiClient: apiClient,
                            url: url,
                            fileName: fileName,
                            expanded: true,
                          ),
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: IconButton.filled(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSizeLabel(BuildContext context, int sizeBytes, String fullUrl) {
    final mutedStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted);

    if (sizeBytes > 0) {
      return Text(formatFileSize(sizeBytes), style: mutedStyle);
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: apiClient.getFileMetadata(fullUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Text("Calculating...", style: mutedStyle);
        }
        if (snapshot.hasData &&
            snapshot.data != null &&
            snapshot.data!['size'] != null &&
            snapshot.data!['size'] > 0) {
          return Text(
            formatFileSize(snapshot.data!['size']),
            style: mutedStyle,
          );
        }
        return Text("0 B", style: mutedStyle);
      },
    );
  }
}

class _ImageAttachmentPreview extends StatelessWidget {
  final ApiClient apiClient;
  final String url;

  const _ImageAttachmentPreview({required this.apiClient, required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List?>(
      future: apiClient.getFileBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 180,
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
          );
        }
        return Container(
          height: 100,
          width: double.infinity,
          color: scheme.errorContainer,
          child: Center(
            child: Icon(
              Icons.broken_image,
              size: 32,
              color: scheme.onErrorContainer,
            ),
          ),
        );
      },
    );
  }
}

class _ZoomableImagePreview extends StatelessWidget {
  final ApiClient apiClient;
  final String url;

  const _ZoomableImagePreview({required this.apiClient, required this.url});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: apiClient.getFileBytes(url),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const CircularProgressIndicator(strokeWidth: 2);
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const _MediaErrorPreview(icon: Icons.broken_image_rounded);
        }
        return InteractiveViewer(
          minScale: 0.6,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      },
    );
  }
}

class _VideoAttachmentPlayer extends StatefulWidget {
  final ApiClient apiClient;
  final String url;
  final String fileName;
  final bool expanded;

  const _VideoAttachmentPlayer({
    required this.apiClient,
    required this.url,
    required this.fileName,
    this.expanded = false,
  });

  @override
  State<_VideoAttachmentPlayer> createState() => _VideoAttachmentPlayerState();
}

class _VideoAttachmentPlayerState extends State<_VideoAttachmentPlayer> {
  late Future<File?> _file;

  @override
  void initState() {
    super.initState();
    _file = widget.apiClient.getCachedFile(
      widget.url,
      fileName: widget.fileName,
    );
  }

  @override
  void didUpdateWidget(covariant _VideoAttachmentPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.fileName != widget.fileName) {
      _file = widget.apiClient.getCachedFile(
        widget.url,
        fileName: widget.fileName,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: widget.expanded ? 260 : 180,
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final file = snapshot.data;
        if (file == null) {
          return _MediaErrorPreview(icon: Icons.movie_rounded);
        }
        return _LocalVideoAttachmentPlayer(
          key: ValueKey(file.path),
          file: file,
          expanded: widget.expanded,
        );
      },
    );
  }
}

class _LocalVideoAttachmentPlayer extends StatefulWidget {
  final File file;
  final bool expanded;

  const _LocalVideoAttachmentPlayer({
    super.key,
    required this.file,
    required this.expanded,
  });

  @override
  State<_LocalVideoAttachmentPlayer> createState() =>
      _LocalVideoAttachmentPlayerState();
}

class _LocalVideoAttachmentPlayerState
    extends State<_LocalVideoAttachmentPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    _initialize = _controller.initialize().then((_) {
      _controller.setLooping(false);
      if (mounted) setState(() {});
    });
    _controller.addListener(_onVideoChanged);
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<void>(
      future: _initialize,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MediaErrorPreview(icon: Icons.movie_rounded);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: 180,
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final value = _controller.value;
        final duration = value.duration;
        final position = value.position > duration ? duration : value.position;
        final video = AspectRatio(
          aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(_controller),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    },
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.84),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.scrim.withValues(alpha: 0.55),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          value.isPlaying
                              ? _controller.pause()
                              : _controller.play();
                        },
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble(),
                            min: 0,
                            max: duration.inMilliseconds
                                .clamp(1, double.infinity)
                                .toDouble(),
                            onChanged: (value) => _controller.seekTo(
                              Duration(milliseconds: value.round()),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: Text(
                          _formatDuration(duration),
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        if (widget.expanded) {
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
            child: video,
          );
        }
        return video;
      },
    );
  }
}

class _AudioAttachmentPlayer extends StatefulWidget {
  final ApiClient apiClient;
  final String url;
  final String fileName;
  final bool expanded;

  const _AudioAttachmentPlayer({
    required this.apiClient,
    required this.url,
    required this.fileName,
    this.expanded = false,
  });

  @override
  State<_AudioAttachmentPlayer> createState() => _AudioAttachmentPlayerState();
}

class _AudioAttachmentPlayerState extends State<_AudioAttachmentPlayer> {
  late final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  late Future<File?> _file;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _state = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _file = widget.apiClient.getCachedFile(
      widget.url,
      fileName: widget.fileName,
    );
    _subscriptions.addAll([
      _player.onDurationChanged.listen((duration) {
        if (mounted) setState(() => _duration = duration);
      }),
      _player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _state = state);
      }),
    ]);
    unawaited(_loadSource());
  }

  @override
  void didUpdateWidget(covariant _AudioAttachmentPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.fileName != widget.fileName) {
      _position = Duration.zero;
      _duration = Duration.zero;
      _file = widget.apiClient.getCachedFile(
        widget.url,
        fileName: widget.fileName,
      );
      unawaited(_loadSource());
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> _loadSource() async {
    final file = await _file;
    if (!mounted || file == null) return;
    await _player.setSource(DeviceFileSource(file.path));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMs = _duration.inMilliseconds.clamp(1, double.infinity).toDouble();
    final positionMs = _position.inMilliseconds.clamp(0, maxMs).toDouble();
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: widget.expanded ? 120 : 64,
            width: double.infinity,
            color: scheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (snapshot.data == null) {
          return _MediaErrorPreview(icon: Icons.audiotrack_rounded);
        }
        return Container(
          width: widget.expanded ? 520 : double.infinity,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            widget.expanded ? AppSpacing.md : AppSpacing.sm,
            AppSpacing.md,
            widget.expanded ? AppSpacing.md : 0,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: widget.expanded ? AppRadii.brMd : BorderRadius.zero,
          ),
          child: Row(
            children: [
              IconButton.filledTonal(
                icon: Icon(
                  _state == PlayerState.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: () => unawaited(_togglePlayback()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Slider(
                  value: positionMs,
                  min: 0,
                  max: maxMs,
                  onChanged: (value) => unawaited(
                    _player.seek(Duration(milliseconds: value.round())),
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  _formatDuration(_duration),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaErrorPreview extends StatelessWidget {
  final IconData icon;

  const _MediaErrorPreview({required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 140,
      width: double.infinity,
      color: scheme.errorContainer,
      child: Icon(icon, size: 36, color: scheme.onErrorContainer),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}
