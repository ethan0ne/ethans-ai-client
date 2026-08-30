import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/api/client_backend_api.dart';
import '../../../core/services/api/client_backend_config.dart';
import '../../../core/services/api/client_backend_session.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/markdown_with_highlight.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../utils/hosted_image_cache.dart';

Future<void> showRequestContextDialog(
  BuildContext context, {
  required Future<ClientRequestContext?> Function() loadHostedContext,
}) {
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  if (isDesktop) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          _RequestContextDialog(loadHostedContext: loadHostedContext),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _RequestContextSheet(loadHostedContext: loadHostedContext),
  );
}

class _RequestContextDialog extends StatelessWidget {
  const _RequestContextDialog({required this.loadHostedContext});

  final Future<ClientRequestContext?> Function() loadHostedContext;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width - 48).clamp(420.0, 900.0),
          maxHeight: (size.height - 80).clamp(420.0, 900.0),
        ),
        child: _RequestContextContent(loadHostedContext: loadHostedContext),
      ),
    );
  }
}

class _RequestContextSheet extends StatelessWidget {
  const _RequestContextSheet({required this.loadHostedContext});

  final Future<ClientRequestContext?> Function() loadHostedContext;

  @override
  Widget build(BuildContext context) {
    // Let the draggable sheet occupy the bottom inset as well. Wrapping the
    // sheet itself in SafeArea shortens its viewport, leaving an unused strip
    // below the message list that cannot be reached by scrolling.
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.58,
      minChildSize: 0.38,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return _RequestContextContent(
          loadHostedContext: loadHostedContext,
          scrollController: scrollController,
          showDragHandle: true,
        );
      },
    );
  }
}

class _RequestContextContent extends StatefulWidget {
  const _RequestContextContent({
    required this.loadHostedContext,
    this.scrollController,
    this.showDragHandle = false,
  });

  final Future<ClientRequestContext?> Function() loadHostedContext;
  final ScrollController? scrollController;
  final bool showDragHandle;

  @override
  State<_RequestContextContent> createState() => _RequestContextContentState();
}

class _RequestContextContentState extends State<_RequestContextContent> {
  late final Future<ClientRequestContext?> _contextFuture;
  bool _showRawText = false;

  @override
  void initState() {
    super.initState();
    // One request per popup. Attachments are represented by placeholders in
    // the returned body and are never fetched separately.
    _contextFuture = widget.loadHostedContext();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(6, widget.showDragHandle ? 10 : 16, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showDragHandle) ...[
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.forum_outlined, size: 19, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.requestContextDialogTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: AppFontWeights.emphasis,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _showRawText
                      ? l10n.requestContextBubbleMode
                      : l10n.requestContextRawTextMode,
                  onPressed: () => setState(() {
                    _showRawText = !_showRawText;
                  }),
                  icon: Icon(
                    _showRawText ? Icons.forum_outlined : Icons.code_outlined,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<ClientRequestContext?>(
              future: _contextFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data;
                if (data == null) {
                  return Center(
                    child: Text(l10n.requestContextDialogUnavailable),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: _RequestMeta(contextData: data, color: cs),
                    ),
                    if (_showRawText)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _copyAll(data),
                            icon: const Icon(Icons.copy_all_outlined, size: 17),
                            label: Text(l10n.requestContextCopyAll),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _showRawText
                          ? _RawRequestText(
                              body: data.body,
                              controller: widget.scrollController,
                            )
                          : _RequestTurns(
                              body: data.body,
                              requestId: data.requestId,
                              colorScheme: cs,
                              controller: widget.scrollController,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAll(ClientRequestContext data) async {
    final copiedMessage = AppLocalizations.of(context)!.requestContextCopiedAll;
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert(data.body),
      ),
    );
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: copiedMessage,
      type: NotificationType.success,
    );
  }
}

class _RequestMeta extends StatelessWidget {
  const _RequestMeta({required this.contextData, required this.color});

  final ClientRequestContext contextData;
  final ColorScheme color;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (contextData.provider.isNotEmpty) contextData.provider,
      if (contextData.model.isNotEmpty) contextData.model,
      contextData.path,
    ];
    return Text(
      parts.join(' · '),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: color.onSurfaceVariant),
    );
  }
}

class _RawRequestText extends StatelessWidget {
  const _RawRequestText({required this.body, this.controller});

  final Map<String, dynamic> body;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.only(
        bottom: 8 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SelectableText(
        _prettyJson(body),
        style: const TextStyle(fontSize: 13, height: 1.45),
      ),
    );
  }
}

class _RequestTurns extends StatelessWidget {
  const _RequestTurns({
    required this.body,
    required this.requestId,
    required this.colorScheme,
    this.controller,
  });

  final Map<String, dynamic> body;
  final String requestId;
  final ColorScheme colorScheme;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final rawMessages = body['messages'];
    final bottomScrollInset = 8 + MediaQuery.paddingOf(context).bottom;
    if (rawMessages is! List || rawMessages.isEmpty) {
      return SingleChildScrollView(
        controller: controller,
        padding: EdgeInsets.only(bottom: bottomScrollInset),
        child: SelectableText(_prettyJson(body)),
      );
    }
    return ListView.separated(
      controller: controller,
      padding: EdgeInsets.fromLTRB(0, 2, 0, bottomScrollInset),
      itemCount: rawMessages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final value = rawMessages[index];
        final item = value is Map
            ? value.cast<String, dynamic>()
            : <String, dynamic>{'content': value};
        return _RequestBubble(
          role: (item['role'] ?? 'message').toString(),
          content: item['content'] ?? item,
          requestId: requestId,
          colorScheme: colorScheme,
        );
      },
    );
  }
}

class _RequestBubble extends StatelessWidget {
  const _RequestBubble({
    required this.role,
    required this.content,
    required this.requestId,
    required this.colorScheme,
  });

  final String role;
  final dynamic content;
  final String requestId;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final presentation = _RequestContentPresentation.fromValue(content);
    final l10n = AppLocalizations.of(context)!;
    final normalizedRole = role.trim().toLowerCase();
    final isUser = normalizedRole == 'user';
    final isSystem = normalizedRole == 'system';
    final contentChildren = <Widget>[];

    final unknownAttachmentCount =
        presentation.attachmentCount - presentation.mediaRefs.length;
    if (unknownAttachmentCount > 0) {
      contentChildren.add(
        _AttachmentPill(
          count: unknownAttachmentCount,
          colorScheme: colorScheme,
          label: l10n.requestContextAttachmentsIncluded,
        ),
      );
    }
    if (presentation.mediaRefs.isNotEmpty) {
      contentChildren.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presentation.mediaRefs
              .map(
                (ref) => _RequestMediaAttachment(
                  requestId: requestId,
                  ref: ref,
                  colorScheme: colorScheme,
                ),
              )
              .toList(),
        ),
      );
    }
    if (presentation.text.isNotEmpty) {
      contentChildren.add(
        MarkdownWithCodeHighlight(
          text: presentation.text,
          baseStyle: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width >= 600 ? 14 : 15.7,
            height: 1.5,
            color: isSystem
                ? colorScheme.onSurface.withValues(alpha: 0.58)
                : null,
          ),
        ),
      );
    }

    final bubbleBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < contentChildren.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          contentChildren[i],
        ],
      ],
    );

    // Match the normal chat body: user messages use the same outer spacing
    // and 75% right-aligned bubble, while assistant/tool messages use the
    // same left spacing and configured chat background surface.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isUser ? 8 : 10, vertical: 12),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (isSystem)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                'SYSTEM',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: AppFontWeights.emphasis,
                  letterSpacing: 0.3,
                  color: colorScheme.onSurface.withValues(alpha: 0.52),
                ),
              ),
            ),
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isUser
                    ? MediaQuery.sizeOf(context).width * 0.75
                    : MediaQuery.sizeOf(context).width,
              ),
              child: _buildRequestChatSurface(
                context,
                isUser: isUser,
                isSystem: isSystem,
                child: bubbleBody,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildRequestChatSurface(
  BuildContext context, {
  required bool isUser,
  required bool isSystem,
  required Widget child,
}) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final radius = BorderRadius.circular(16);
  final padding = const EdgeInsets.all(12.0);
  final style = context.watch<SettingsProvider>().chatMessageBackgroundStyle;
  final paddedChild = Padding(padding: padding, child: child);

  if (style == ChatMessageBackgroundStyle.defaultStyle) {
    final background = isUser
        ? (isDark
              ? cs.primary.withValues(alpha: 0.15)
              : cs.primary.withValues(alpha: 0.08))
        : isSystem
        ? cs.onSurface.withValues(alpha: isDark ? 0.055 : 0.035)
        : cs.surfaceContainerHighest.withValues(alpha: isDark ? 0.58 : 0.72);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: isUser
            ? null
            : Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.18),
                width: 0.8,
              ),
      ),
      child: paddedChild,
    );
  }

  final background = style == ChatMessageBackgroundStyle.frosted
      ? (isDark
            ? const Color(0xFF1C1C1E).withValues(alpha: 0.66)
            : Colors.white.withValues(alpha: 0.66))
      : (isDark ? const Color(0xFF1C1C1E) : Colors.white);
  final surface = DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: radius,
      border: Border.all(
        color: cs.outlineVariant.withValues(
          alpha: style == ChatMessageBackgroundStyle.frosted ? 0.14 : 0.16,
        ),
        width: 0.8,
      ),
    ),
    child: paddedChild,
  );
  if (style != ChatMessageBackgroundStyle.frosted) return surface;
  return ClipRRect(
    borderRadius: radius,
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      child: surface,
    ),
  );
}

class _AttachmentPill extends StatelessWidget {
  const _AttachmentPill({
    required this.count,
    required this.colorScheme,
    required this.label,
  });

  final int count;
  final ColorScheme colorScheme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.attach_file,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _RequestMediaRef {
  const _RequestMediaRef({required this.kind, required this.digest});

  final String kind;
  final String digest;
}

class _RequestMediaAttachment extends StatefulWidget {
  const _RequestMediaAttachment({
    required this.requestId,
    required this.ref,
    required this.colorScheme,
  });

  final String requestId;
  final _RequestMediaRef ref;
  final ColorScheme colorScheme;

  @override
  State<_RequestMediaAttachment> createState() =>
      _RequestMediaAttachmentState();
}

class _RequestMediaAttachmentState extends State<_RequestMediaAttachment> {
  late final Future<String?> _cachedPath;

  String get _url =>
      '$clientBackendBaseUrl/__client/request-media/${widget.ref.kind}/${widget.ref.digest}/file?request_id=${Uri.encodeComponent(widget.requestId)}';

  @override
  void initState() {
    super.initState();
    final token = ClientBackendSession.token;
    _cachedPath = token == null
        ? Future<String?>.value(null)
        : HostedImageCache.getPath(
            _url,
            headers: {'Authorization': 'Bearer $token'},
            cacheKey: 'request-media:${widget.ref.kind}:${widget.ref.digest}',
          );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ref.kind != 'image') {
      return _AttachmentPill(
        count: 1,
        colorScheme: widget.colorScheme,
        label: AppLocalizations.of(context)!.requestContextAttachmentFile,
      );
    }

    return FutureBuilder<String?>(
      future: _cachedPath,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null) {
          return Container(
            width: 112,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              snapshot.connectionState == ConnectionState.waiting
                  ? Icons.downloading_outlined
                  : Icons.broken_image_outlined,
              color: widget.colorScheme.onSurfaceVariant,
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            width: 112,
            height: 112,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 112,
              height: 72,
              alignment: Alignment.center,
              color: widget.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image_outlined,
                color: widget.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequestContentPresentation {
  const _RequestContentPresentation({
    required this.text,
    required this.attachmentCount,
    this.mediaRefs = const [],
  });

  final String text;
  final int attachmentCount;
  final List<_RequestMediaRef> mediaRefs;

  static _RequestContentPresentation fromValue(dynamic value) {
    if (value is String) {
      var attachmentCount = 0;
      var text = value;
      final attachmentPattern = RegExp(
        r'inspector://(image|attachment|video)/sha256:([0-9a-f]{64})',
      );
      final mediaRefs = attachmentPattern
          .allMatches(text)
          .map(
            (match) => _RequestMediaRef(
              kind: match.group(1)!,
              digest: match.group(2)!,
            ),
          )
          .toList();
      attachmentCount += mediaRefs.length;
      text = text.replaceAll(attachmentPattern, '');
      final imageMarkdownPattern = RegExp(r'!\[[^\]]*\]\([^)]*\)');
      final imageMarkdownCount = imageMarkdownPattern.allMatches(text).length;
      attachmentCount += imageMarkdownCount;
      text = text.replaceAll(imageMarkdownPattern, '');
      final dataPattern = RegExp(r'data:[^,\s]+;base64,[A-Za-z0-9+/=_-]+');
      attachmentCount += dataPattern.allMatches(text).length;
      text = text.replaceAll(dataPattern, '');
      return _RequestContentPresentation(
        text: text.trim(),
        attachmentCount: attachmentCount,
        mediaRefs: mediaRefs,
      );
    }
    if (value is List) {
      final textParts = <String>[];
      var attachmentCount = 0;
      final mediaRefs = <_RequestMediaRef>[];
      for (final part in value) {
        final presentation = fromValue(part);
        textParts.add(presentation.text);
        attachmentCount += presentation.attachmentCount;
        mediaRefs.addAll(presentation.mediaRefs);
      }
      return _RequestContentPresentation(
        text: textParts.where((e) => e.isNotEmpty).join('\n'),
        attachmentCount: attachmentCount,
        mediaRefs: mediaRefs,
      );
    }
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      if (map['text'] != null) return fromValue(map['text']);
      for (final key in const [
        'url',
        'image_url',
        'image',
        'input_image',
        'file_url',
        'file_data',
        'input_file',
        'input_audio',
        'data',
      ]) {
        if (map[key] != null) {
          final nested = fromValue(map[key]);
          if (nested.mediaRefs.isNotEmpty || nested.attachmentCount > 0) {
            return nested;
          }
        }
      }
      final type = (map['type'] ?? '').toString().toLowerCase();
      if (type.contains('image') ||
          type.contains('file') ||
          type.contains('audio')) {
        return const _RequestContentPresentation(text: '', attachmentCount: 1);
      }
      return _RequestContentPresentation(
        text: _prettyJson(map),
        attachmentCount: 0,
      );
    }
    return _RequestContentPresentation(
      text: value.toString(),
      attachmentCount: 0,
    );
  }

  static String _prettyJson(dynamic value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}

String _prettyJson(dynamic value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}
