import 'dart:async';

import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/mcp_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';

Future<void> showMcpTimeoutSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final mcp = context.read<McpProvider>();
  final controller = TextEditingController(
    text: mcp.requestTimeoutSeconds.toString(),
  );

  Future<void> handleSave() async {
    FocusScope.of(context).unfocus();
    final raw = controller.text.trim();
    final seconds = int.tryParse(raw);
    if (seconds == null || seconds <= 0) {
      showAppSnackBar(
        context,
        message: l10n.mcpTimeoutInvalid,
        type: NotificationType.warning,
      );
      return;
    }
    await mcp.updateRequestTimeout(Duration(seconds: seconds));
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  await showAppPopupSheet<void>(
    context: context,
    title: l10n.mcpTimeoutDialogTitle,
    actions: [
      appPopupDoneAction(
        semanticLabel: l10n.mcpServerEditSheetSave,
        onTap: () => unawaited(handleSave()),
      ),
    ],
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      final bottom = MediaQuery.of(ctx).viewInsets.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.mcpTimeoutSecondsLabel,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 6),
            AppTextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: l10n.mcpTimeoutSecondsLabel,
                suffixText: 's',
                filled: true,
                fillColor: isDark ? Colors.white10 : Colors.white,
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onSubmitted: (_) => handleSave(),
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
}
