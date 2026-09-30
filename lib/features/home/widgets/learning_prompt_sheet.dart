import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/models/instruction_injection.dart';
import '../../assistant/utils/assistant_prompt_asset_sync.dart';
import '../../../l10n/app_localizations.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

/// Bottom sheet for editing the active instruction injection prompt.
///
/// This widget allows users to edit the prompt text of an instruction
/// injection item directly.
class LearningPromptSheet extends StatefulWidget {
  const LearningPromptSheet({super.key, required this.target});

  /// The instruction injection item to edit.
  final InstructionInjection target;

  @override
  State<LearningPromptSheet> createState() => _LearningPromptSheetState();
}

class _LearningPromptSheetState extends State<LearningPromptSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.target.prompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.bottomToolsSheetPrompt,
              style: TextStyle(
                fontSize: 16,
                fontWeight: AppFontWeights.semibold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: l10n.bottomToolsSheetPromptHint,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white10
                    : const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final updated = widget.target.copyWith(
                      prompt: _controller.text.trim(),
                    );
                    final provider = context.read<AssistantProvider>();
                    final assistant = provider.currentAssistant;
                    if (assistant != null) {
                      await saveAssistantPromptAssets(
                        context,
                        assistant.copyWith(
                          instructionInjections: assistant.instructionInjections
                              .map(
                                (item) =>
                                    item.id == updated.id ? updated : item,
                              )
                              .toList(),
                        ),
                      );
                    }
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(l10n.bottomToolsSheetSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the learning prompt bottom sheet.
///
/// This function initializes the provider and shows the sheet for editing
/// the active instruction injection item's prompt.
Future<void> showLearningPromptSheet(BuildContext context) async {
  final assistant = context.read<AssistantProvider>().currentAssistant;
  final items =
      assistant?.instructionInjections ?? const <InstructionInjection>[];
  if (items.isEmpty) return;
  final activeIds =
      assistant?.activeInstructionInjectionIds.toSet() ?? <String>{};
  final target = items.firstWhere(
    (item) => activeIds.contains(item.id),
    orElse: () => items.first,
  );
  final cs = Theme.of(context).colorScheme;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return LearningPromptSheet(target: target);
    },
  );
}
