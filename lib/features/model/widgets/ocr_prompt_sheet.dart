import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';

Future<void> showOcrPromptSheet(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final settings = context.read<SettingsProvider>();
  final controller = TextEditingController(text: settings.ocrPrompt);

  await showAppPopupSheet(
    context: context,
    title: l10n.defaultModelPagePromptLabel,
    actions: [
      appPopupDoneAction(
        semanticLabel: l10n.defaultModelPageSave,
        onTap: () async {
          await settings.setOcrPrompt(controller.text.trim());
          if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    ],
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: controller,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: l10n.defaultModelPageOcrPromptHint,
                  filled: true,
                  fillColor: Theme.of(ctx).brightness == Brightness.dark
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
              TextButton(
                onPressed: () async {
                  await settings.resetOcrPrompt();
                  controller.text = settings.ocrPrompt;
                },
                child: Text(l10n.defaultModelPageResetDefault),
              ),
            ],
          ),
        ),
      );
    },
  );
}
