import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../desktop/html_preview_dialog.dart';
import '../../../desktop/menu_anchor.dart';
import '../../../desktop/select_copy_dialog.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/pages/webview_page.dart';
import '../../../shared/widgets/frosted_popup_menu.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/markdown_media_sanitizer.dart';
import '../../../utils/markdown_preview_html.dart';
import 'select_copy_sheet.dart';

enum MessageMoreAction {
  viewRequest,
  edit,
  speak,
  fork,
  deleteCurrentVersion,
  deleteAllVersions,
  share,
  selectMessages,
}

Future<MessageMoreAction?> showMessageMoreSheet(
  BuildContext context,
  ChatMessage message, {
  required bool canDeleteAllVersions,
  bool readOnly = false,
}) async {
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  final l10n = AppLocalizations.of(context)!;
  MessageMoreAction? selected;

  await showFrostedPopupMenuAt(
    context,
    globalPosition: DesktopMenuAnchor.positionOrCenter(context),
    items: [
      FrostedPopupMenuItem(
        icon: Lucide.TextSelect,
        label: l10n.messageMoreSheetSelectCopy,
        onPressed: () {
          if (isDesktop) {
            showSelectCopyDesktopDialog(context, message: message);
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                showSelectCopySheet(context, message: message);
              }
            });
          }
        },
      ),
      FrostedPopupMenuItem(
        icon: Lucide.BookOpenText,
        label: l10n.messageMoreSheetRenderWebView,
        onPressed: () async {
          try {
            final raw = message.content.trim();
            if (raw.isEmpty) return;
            final scheme = Theme.of(context).colorScheme;
            final processed =
                await MarkdownMediaSanitizer.inlineLocalImagesToBase64(raw);
            final html =
                await MarkdownPreviewHtmlBuilder.buildFromMarkdownWithColorScheme(
                  scheme,
                  processed,
                );
            if (!context.mounted) return;
            if (isDesktop) {
              showHtmlPreviewDesktopDialog(context, html: html);
            } else {
              final contentBase64 = base64Encode(utf8.encode(html));
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WebViewPage(contentBase64: contentBase64),
                ),
              );
            }
          } catch (error) {
            if (!context.mounted) return;
            showAppSnackBar(
              context,
              message: error.toString(),
              type: NotificationType.error,
            );
          }
        },
      ),
      if (!readOnly && message.role != 'user')
        FrostedPopupMenuItem(
          icon: Lucide.Pencil,
          label: l10n.messageMoreSheetEdit,
          onPressed: () => selected = MessageMoreAction.edit,
        ),
      if (message.role == 'assistant')
        FrostedPopupMenuItem(
          icon: Lucide.Volume2,
          label: l10n.chatMessageWidgetSpeakTooltip,
          onPressed: () => selected = MessageMoreAction.speak,
        ),
      if (message.role == 'assistant' && message.hostedRequestContextAvailable)
        FrostedPopupMenuItem(
          icon: Lucide.FileText,
          label: l10n.messageMoreSheetViewRequest,
          onPressed: () => selected = MessageMoreAction.viewRequest,
        ),
      if (!readOnly || isDesktop)
        FrostedPopupMenuItem(
          icon: Lucide.Share,
          label: l10n.messageMoreSheetShare,
          onPressed: () => selected = MessageMoreAction.share,
        ),
      if (!readOnly)
        FrostedPopupMenuItem(
          icon: Lucide.CheckSquare,
          label: l10n.messageMoreSheetSelectMessages,
          onPressed: () => selected = MessageMoreAction.selectMessages,
        ),
      FrostedPopupMenuItem(
        icon: Lucide.GitFork,
        label: l10n.messageMoreSheetCreateBranch,
        onPressed: () => selected = MessageMoreAction.fork,
      ),
      if (!readOnly)
        FrostedPopupMenuItem(
          icon: Lucide.Trash2,
          label: l10n.messageMoreSheetDelete,
          destructive: true,
          onPressed: () => selected = MessageMoreAction.deleteCurrentVersion,
        ),
      if (!readOnly && canDeleteAllVersions)
        FrostedPopupMenuItem(
          icon: Lucide.Trash,
          label: l10n.messageMoreSheetDeleteAllVersions,
          destructive: true,
          onPressed: () => selected = MessageMoreAction.deleteAllVersions,
        ),
    ],
  );

  return selected;
}
