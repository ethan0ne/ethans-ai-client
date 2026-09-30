import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/assistant.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import 'assistant_prompt_asset_limits.dart';

/// Saves prompt assets locally and waits for hosted assistants to sync before
/// the user returns to chat, where the backend compiles its saved copy.
Future<bool> saveAssistantPromptAssets(
  BuildContext context,
  Assistant assistant,
) async {
  if (!assistantPromptAssetsWithinHostedLimits(assistant)) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: AppLocalizations.of(
          context,
        )!.assistantPromptAssetsLimitExceededMessage,
        type: NotificationType.error,
      );
    }
    return false;
  }

  final saved = await context.read<AssistantProvider>().updateAssistantAndSync(
    assistant,
  );
  if (!saved && context.mounted) {
    showAppSnackBar(
      context,
      message: AppLocalizations.of(context)!.modelDetailSheetSaveFailedMessage,
      type: NotificationType.error,
    );
  }
  return saved;
}
