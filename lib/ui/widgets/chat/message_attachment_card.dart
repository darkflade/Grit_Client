import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

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

    final String urlStr = (attachment is Map ? attachment['url'] : attachment.url) ?? "";
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

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
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
              FutureBuilder<Uint8List?>(
                future: apiClient.getFileBytes(fullUrl),
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
              )
            else if (video)
              Container(
                height: 180,
                width: double.infinity,
                color: scheme.shadow,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.play_circle_fill_rounded,
                      size: 64,
                      color: context.appColors.onAccent.withValues(alpha: 0.7),
                    ),
                  ],
                ),
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
    );
  }

  Widget _buildSizeLabel(BuildContext context, int sizeBytes, String fullUrl) {
    final mutedStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: context.appColors.textMuted,
    );

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
          return Text(formatFileSize(snapshot.data!['size']), style: mutedStyle);
        }
        return Text("0 B", style: mutedStyle);
      },
    );
  }
}
