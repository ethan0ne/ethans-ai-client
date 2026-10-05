import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../core/models/instruction_injection.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/instruction_injection_group_provider.dart';
import '../../assistant/utils/assistant_prompt_asset_sync.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../core/services/haptics.dart';
import '../../../features/instruction_injection/pages/instruction_injection_page.dart';

/// Bottom sheet for displaying instruction injection items on mobile/tablet.
///
/// This widget shows a list of instruction injection prompts that can be
/// toggled on/off for the current assistant.
class InstructionInjectionSheet extends StatelessWidget {
  const InstructionInjectionSheet({super.key, required this.assistantId});

  final String? assistantId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        minChildSize: 0.45,
        builder: (ctx, controller) {
          final cs = Theme.of(ctx).colorScheme;
          final assistantProvider = ctx.watch<AssistantProvider>();
          final assistant = assistantProvider.getById(
            assistantId ?? assistantProvider.currentAssistantId ?? '',
          );
          final groupUi = ctx.watch<InstructionInjectionGroupProvider>();

          final items =
              assistant?.instructionInjections ??
              const <InstructionInjection>[];
          final activeIds =
              assistant?.activeInstructionInjectionIds.toSet() ?? <String>{};

          final Map<String, List<InstructionInjection>> grouped =
              <String, List<InstructionInjection>>{};
          for (final item in items) {
            final g = item.group.trim();
            (grouped[g] ??= <InstructionInjection>[]).add(item);
          }
          final groupNames = grouped.keys.toList()
            ..sort((a, b) {
              final aa = a.trim();
              final bb = b.trim();
              if (aa.isEmpty && bb.isNotEmpty) return -1;
              if (aa.isNotEmpty && bb.isEmpty) return 1;
              return aa.toLowerCase().compareTo(bb.toLowerCase());
            });

          return Column(
            children: [
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 32, bottom: 24),
                        child: Center(
                          child: Text(
                            l10n.instructionInjectionEmptyMessage,
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      )
                    else
                      for (final groupName in groupNames) ...[
                        _GroupHeader(
                          title: groupName.trim().isEmpty
                              ? l10n.instructionInjectionUngroupedGroup
                              : groupName.trim(),
                          collapsed: groupUi.isCollapsed(groupName),
                          onToggle: () => ctx
                              .read<InstructionInjectionGroupProvider>()
                              .toggleCollapsed(groupName),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOutCubic,
                          alignment: Alignment.topCenter,
                          child: groupUi.isCollapsed(groupName)
                              ? const SizedBox.shrink()
                              : Column(
                                  children: [
                                    for (
                                      int i = 0;
                                      i < (grouped[groupName]?.length ?? 0);
                                      i++
                                    )
                                      Padding(
                                        padding: EdgeInsets.only(
                                          bottom:
                                              i ==
                                                  (grouped[groupName]!.length -
                                                      1)
                                              ? 12
                                              : 8,
                                        ),
                                        child: _InstructionInjectionRow(
                                          label:
                                              (grouped[groupName]![i].title)
                                                  .trim()
                                                  .isEmpty
                                              ? l10n.instructionInjectionDefaultTitle
                                              : grouped[groupName]![i].title,
                                          selected: activeIds.contains(
                                            grouped[groupName]![i].id,
                                          ),
                                          onTap: () async {
                                            Haptics.light();
                                            final current = ctx
                                                .read<AssistantProvider>()
                                                .getById(assistant!.id);
                                            if (current == null) return;
                                            final ids = current
                                                .activeInstructionInjectionIds
                                                .toSet();
                                            final id =
                                                grouped[groupName]![i].id;
                                            if (!ids.add(id)) ids.remove(id);
                                            await saveAssistantPromptAssets(
                                              ctx,
                                              current.copyWith(
                                                activeInstructionInjectionIds:
                                                    ids.toList(),
                                              ),
                                            );
                                          },
                                          onLongPress: () async {
                                            Haptics.medium();
                                            final item = grouped[groupName]![i];
                                            final result =
                                                await showAppPopupSheet<
                                                  Map<String, String>?
                                                >(
                                                  context: ctx,
                                                  title: AppLocalizations.of(
                                                    ctx,
                                                  )!.instructionInjectionEditTitle,
                                                  isScrollControlled: true,
                                                  backgroundColor: cs.surface,
                                                  shape: const RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.vertical(
                                                          top: Radius.circular(
                                                            16,
                                                          ),
                                                        ),
                                                  ),
                                                  builder: (_) =>
                                                      InstructionInjectionEditSheet(
                                                        item: item,
                                                      ),
                                                );
                                            if (result != null) {
                                              if (!ctx.mounted) return;
                                              final title =
                                                  result['title']?.trim() ?? '';
                                              final prompt =
                                                  result['prompt']?.trim() ??
                                                  '';
                                              final group =
                                                  result['group']?.trim() ?? '';
                                              if (title.isEmpty ||
                                                  prompt.isEmpty) {
                                                return;
                                              }
                                              final current = ctx
                                                  .read<AssistantProvider>()
                                                  .getById(assistant!.id);
                                              if (current == null) return;
                                              await saveAssistantPromptAssets(
                                                ctx,
                                                current.copyWith(
                                                  instructionInjections: current
                                                      .instructionInjections
                                                      .map(
                                                        (candidate) =>
                                                            candidate.id ==
                                                                item.id
                                                            ? item.copyWith(
                                                                title: title,
                                                                prompt: prompt,
                                                                group: group,
                                                              )
                                                            : candidate,
                                                      )
                                                      .toList(),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.collapsed,
    required this.onToggle,
  });

  final String title;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: AppListGroupHeader(
        title: title,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: AnimatedRotation(
              turns: collapsed ? 0.0 : 0.25,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: Icon(
                Lucide.ChevronRight,
                size: 16,
                color: textBase.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstructionInjectionRow extends StatelessWidget {
  const _InstructionInjectionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onColor = selected ? cs.primary : cs.onSurface;
    return AppListTile(
      selected: selected,
      onTapFeedback: Haptics.light,
      onLongPressFeedback: Haptics.light,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Icon(Lucide.Layers, size: 20, color: onColor),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: onColor,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected
          ? Icon(Lucide.Check, size: 18, color: cs.primary)
          : const SizedBox(width: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minLeadingWidth: 20,
      horizontalTitleGap: 10,
      dense: true,
      minVerticalPadding: 4,
    );
  }
}

/// Shows the instruction injection bottom sheet.
///
/// This is a convenience function to show the sheet with proper styling.
Future<void> showInstructionInjectionSheet(
  BuildContext context, {
  required String? assistantId,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  await showAppPopupSheet<void>(
    context: context,
    title: l10n.instructionInjectionTitle,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return InstructionInjectionSheet(assistantId: assistantId);
    },
  );
}
