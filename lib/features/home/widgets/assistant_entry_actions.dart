import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/tag_provider.dart';
import '../../../desktop/desktop_context_menu.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/frosted_popup_menu.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../assistant/pages/assistant_settings_edit_page.dart';
import '../../assistant/pages/tags_manager_page.dart';
import '../../assistant/widgets/tags_manager_dialog.dart';

class AssistantEntryActions {
  const AssistantEntryActions._();

  static bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  static void openAssistantSettings(
    BuildContext context,
    String assistantId, {
    VoidCallback? beforeAction,
  }) {
    beforeAction?.call();
    if (_isDesktopPlatform) {
      showAssistantDesktopDialog(context, assistantId: assistantId);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AssistantSettingsEditPage(assistantId: assistantId),
      ),
    );
  }

  static Future<void> showAssistantItemMenu({
    required BuildContext context,
    required Assistant assistant,
    Offset? globalPosition,
    VoidCallback? beforeAction,
  }) async {
    if (_isDesktopPlatform) {
      if (globalPosition == null) return;
      await _showAssistantItemMenuDesktop(
        context: context,
        assistant: assistant,
        globalPosition: globalPosition,
        beforeAction: beforeAction,
      );
      return;
    }
    await _showAssistantItemMenuMobile(
      context: context,
      assistant: assistant,
      globalPosition: globalPosition,
      beforeAction: beforeAction,
    );
  }

  static Future<void> _duplicateAssistantFromMenu(
    BuildContext context,
    Assistant assistant,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    String? newId;
    try {
      newId = await context.read<AssistantProvider>().duplicateAssistant(
        assistant.id,
        l10n: l10n,
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: l10n.assistantCloudCreateFailed,
          type: NotificationType.error,
        );
      }
      return;
    }
    if (!context.mounted || newId == null) return;
    showAppSnackBar(
      context,
      message: l10n.assistantSettingsCopySuccess,
      type: NotificationType.success,
    );
  }

  static Future<void> _showAssistantItemMenuDesktop({
    required BuildContext context,
    required Assistant assistant,
    required Offset globalPosition,
    VoidCallback? beforeAction,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final tagProvider = context.read<TagProvider>();
    final hasTag = tagProvider.tagOfAssistant(assistant.id) != null;

    await showDesktopContextMenuAt(
      context,
      globalPosition: globalPosition,
      items: [
        DesktopContextMenuItem(
          icon: Lucide.Pencil,
          label: l10n.assistantTagsContextMenuEditAssistant,
          onTap: () => openAssistantSettings(
            context,
            assistant.id,
            beforeAction: beforeAction,
          ),
        ),
        DesktopContextMenuItem(
          icon: Lucide.Copy,
          label: l10n.assistantSettingsCopyButton,
          onTap: () async {
            beforeAction?.call();
            await _duplicateAssistantFromMenu(context, assistant);
          },
        ),
        if (hasTag)
          DesktopContextMenuItem(
            icon: Lucide.Eraser,
            label: l10n.assistantTagsClearTag,
            onTap: () async {
              beforeAction?.call();
              await context.read<TagProvider>().unassignAssistant(assistant.id);
            },
          ),
        DesktopContextMenuItem(
          icon: Lucide.Bookmark,
          label: l10n.assistantTagsContextMenuManageTags,
          onTap: () async {
            beforeAction?.call();
            await showAssistantTagsManagerDialog(
              context,
              assistantId: assistant.id,
            );
          },
        ),
        DesktopContextMenuItem(
          icon: Lucide.Trash2,
          label: l10n.assistantTagsContextMenuDeleteAssistant,
          danger: true,
          onTap: () async {
            beforeAction?.call();
            await _deleteAssistant(context, assistant);
          },
        ),
      ],
    );
  }

  static Future<void> _showAssistantItemMenuMobile({
    required BuildContext context,
    required Assistant assistant,
    Offset? globalPosition,
    VoidCallback? beforeAction,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final tagProvider = context.read<TagProvider>();
    final hasTag = tagProvider.tagOfAssistant(assistant.id) != null;

    await showFrostedPopupMenuAt(
      context,
      globalPosition: globalPosition ?? popupMenuAnchorForContext(context),
      items: [
        FrostedPopupMenuItem(
          icon: Lucide.Pencil,
          label: l10n.assistantTagsContextMenuEditAssistant,
          onPressed: () => openAssistantSettings(
            context,
            assistant.id,
            beforeAction: beforeAction,
          ),
        ),
        FrostedPopupMenuItem(
          icon: Lucide.Copy,
          label: l10n.assistantSettingsCopyButton,
          onPressed: () async {
            beforeAction?.call();
            await _duplicateAssistantFromMenu(context, assistant);
          },
        ),
        if (hasTag)
          FrostedPopupMenuItem(
            icon: Lucide.Eraser,
            label: l10n.assistantTagsClearTag,
            onPressed: () async {
              beforeAction?.call();
              await context.read<TagProvider>().unassignAssistant(assistant.id);
            },
          ),
        FrostedPopupMenuItem(
          icon: Lucide.Bookmark,
          label: l10n.assistantTagsContextMenuManageTags,
          onPressed: () async {
            beforeAction?.call();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TagsManagerPage(assistantId: assistant.id),
              ),
            );
          },
        ),
        FrostedPopupMenuItem(
          icon: Lucide.Trash2,
          label: l10n.assistantTagsContextMenuDeleteAssistant,
          destructive: true,
          onPressed: () async {
            beforeAction?.call();
            await _deleteAssistant(context, assistant);
          },
        ),
      ],
    );
  }

  static Future<void> _deleteAssistant(
    BuildContext context,
    Assistant assistant,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final assistantProvider = context.read<AssistantProvider>();
    final tagProvider = context.read<TagProvider>();
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(l10n.assistantSettingsDeleteDialogTitle),
        content: Text(l10n.assistantSettingsDeleteDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.assistantSettingsDeleteDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.assistantSettingsDeleteDialogConfirm),
          ),
        ],
      ),
    );

    if (!context.mounted || confirmed != true) return;
    final ok = await assistantProvider.deleteAssistant(assistant.id);
    if (!context.mounted) return;

    if (!ok) {
      showAppSnackBar(
        context,
        message: l10n.assistantSettingsAtLeastOneAssistantRequired,
        type: NotificationType.warning,
      );
      return;
    }

    try {
      await tagProvider.unassignAssistant(assistant.id);
    } catch (_) {}
  }
}
