import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/frosted_popup_menu.dart';
import '../../home/widgets/instruction_injection_sheet.dart';
import '../../home/widgets/world_book_sheet.dart';
import '../../assistant/pages/assistant_settings_edit_page.dart';
import '../../assistant/utils/assistant_edit_tab_layout.dart';
import '../../model/widgets/ocr_prompt_sheet.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class BottomToolsSheet extends StatelessWidget {
  const BottomToolsSheet({
    super.key,
    this.onCamera,
    this.onPhotos,
    this.showImageActions = true,
    this.photosLabel,
    this.onUpload,
    this.onClear,
    this.clearLabel,
    this.assistantId,
  });

  final VoidCallback? onCamera;
  final VoidCallback? onPhotos;
  final bool showImageActions;
  // [kelivo-hosted] Overrides the "Photos" tile's label — set by the caller
  // to `l10n.chatInputBarPickMedia` when video mode is active (`onPhotos` is
  // then wired to a merged image/video picker instead of the image-only
  // one), so this sheet doesn't say "Photos" while actually also accepting
  // a video. Defaults to `l10n.bottomToolsSheetPhotos` when null.
  final String? photosLabel;
  final VoidCallback? onUpload;
  final Future<void> Function(Offset globalPosition)? onClear;
  final String? clearLabel;
  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;

    Widget roundedAction({
      required IconData icon,
      required String label,
      VoidCallback? onTap,
    }) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final cardColor = isDark ? Colors.white10 : const Color(0xFFF2F3F5);
      return Expanded(
        child: SizedBox(
          height: 72,
          child: IosCardPress(
            baseColor: cardColor,
            borderRadius: BorderRadius.circular(14),
            pressedScale: 0.98,
            duration: const Duration(milliseconds: 260),
            onTap: () {
              Haptics.light();
              onTap?.call();
            },
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (showImageActions) ...[
                          roundedAction(
                            icon: Lucide.Camera,
                            label: l10n.bottomToolsSheetCamera,
                            onTap: onCamera,
                          ),
                          if (showImageActions) const SizedBox(width: 12),
                          roundedAction(
                            icon: Lucide.Image,
                            label: photosLabel ?? l10n.bottomToolsSheetPhotos,
                            onTap: onPhotos,
                          ),
                          const SizedBox(width: 12),
                        ],
                        roundedAction(
                          icon: Lucide.Paperclip,
                          label: l10n.bottomToolsSheetUpload,
                          onTap: onUpload,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _LearningAndClearSection(
                      clearLabel: clearLabel,
                      onClear: onClear,
                      assistantId: assistantId,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningAndClearSection extends StatefulWidget {
  const _LearningAndClearSection({
    this.onClear,
    this.clearLabel,
    this.assistantId,
  });
  final Future<void> Function(Offset globalPosition)? onClear;
  final String? clearLabel;
  final String? assistantId;

  @override
  State<_LearningAndClearSection> createState() =>
      _LearningAndClearSectionState();
}

class _LearningAndClearSectionState extends State<_LearningAndClearSection> {
  Widget _row({
    required IconData icon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
    ValueChanged<Offset>? onPointerDown,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    final onColor = selected ? cs.primary : cs.onSurface;
    return Listener(
      onPointerDown: onPointerDown == null
          ? null
          : (event) => onPointerDown(event.position),
      child: AppListTile(
        leading: Icon(icon, size: 20, color: onColor),
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: AppFontWeights.medium,
            color: onColor,
          ),
        ),
        trailing:
            trailing ??
            (selected
                ? Icon(Lucide.Check, size: 18, color: cs.primary)
                : const SizedBox(width: 18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        minVerticalPadding: 8,
        selected: selected,
        selectedColor: cs.primary,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final assistantProvider = context.watch<AssistantProvider>();
    final assistant = assistantProvider.getById(
      widget.assistantId ?? assistantProvider.currentAssistantId ?? '',
    );
    final cs = Theme.of(context).colorScheme;
    final hasOcrModel =
        settings.ocrModelProvider != null && settings.ocrModelId != null;
    final hasWorldBooks = assistant?.worldBooks.isNotEmpty ?? false;
    Offset? clearMenuAnchor;
    final rows = <Widget>[
      _row(
        icon: Lucide.Layers,
        label: l10n.instructionInjectionTitle,
        selected: false,
        onTap: () async {
          Haptics.light();
          await showInstructionInjectionSheet(
            context,
            assistantId: widget.assistantId,
          );
        },
        onLongPress: () {
          Haptics.light();
          final assistantId = widget.assistantId;
          if (assistantId == null) return;
          final rootNav = Navigator.of(context, rootNavigator: true);
          rootNav.push(
            MaterialPageRoute(
              builder: (_) => AssistantSettingsEditPage(
                assistantId: assistantId,
                initialTabId: assistantEditTabInstructionInjections,
              ),
            ),
          );
        },
        trailing: Icon(
          Lucide.ChevronRight,
          size: 18,
          color: cs.onSurface.withValues(alpha: 0.55),
        ),
      ),
      if (hasWorldBooks)
        _row(
          icon: Lucide.BookOpen,
          label: l10n.worldBookTitle,
          selected: false,
          onTap: () async {
            Haptics.light();
            await showWorldBookSheet(context, assistantId: widget.assistantId);
          },
          onLongPress: () {
            Haptics.light();
            final assistantId = widget.assistantId;
            if (assistantId == null) return;
            final rootNav = Navigator.of(context, rootNavigator: true);
            rootNav.push(
              MaterialPageRoute(
                builder: (_) => AssistantSettingsEditPage(
                  assistantId: assistantId,
                  initialTabId: assistantEditTabWorldBooks,
                ),
              ),
            );
          },
          trailing: Icon(
            Lucide.ChevronRight,
            size: 18,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
      if (hasOcrModel)
        _row(
          icon: Lucide.Eye,
          label: l10n.bottomToolsSheetOcr,
          selected: settings.ocrEnabled,
          onTap: () async {
            Haptics.light();
            final sp = context.read<SettingsProvider>();
            await sp.setOcrEnabled(!sp.ocrEnabled);
            if (!context.mounted) return;
            Navigator.of(context).maybePop();
          },
          onLongPress: () => showOcrPromptSheet(context),
        ),
      _row(
        icon: Lucide.workflow,
        label: l10n.contextManagement,
        onTap: () {
          Haptics.light();
          final onClear = widget.onClear;
          if (onClear != null) {
            unawaited(
              onClear(clearMenuAnchor ?? popupMenuAnchorForContext(context)),
            );
          }
        },
        onPointerDown: (position) => clearMenuAnchor = position,
        trailing: Icon(
          Lucide.ChevronRight,
          size: 18,
          color: cs.onSurface.withValues(alpha: 0.55),
        ),
      ),
    ];
    return AppListGroup.list(
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const AppListDivider.forTile(hasLeading: true),
          rows[index],
        ],
      ],
    );
  }
}
