import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';

class SelectCopyPage extends StatelessWidget {
  const SelectCopyPage({super.key, required this.message});
  final ChatMessage message;

  void _copyAll(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    // Ensure there is a text input connection on iOS before showing system copy UI
    // Here we bypass system menu by writing directly to clipboard and showing a snackbar
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: l10n.selectCopyPageCopiedAll,
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return AppScaffold(
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.selectCopyPageTitle),
      actions: [
        AppButtonIslandButton(
          icon: Lucide.Copy,
          label: l10n.selectCopyPageCopyAll,
          labelColor: cs.primary,
          semanticLabel: l10n.selectCopyPageCopyAll,
          onTap: () => _copyAll(context),
        ),
      ],
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                AppScaffold.scrollContentTop(context),
                16,
                16,
              ),
              child: SelectionArea(
                child: Text(
                  message.content,
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
