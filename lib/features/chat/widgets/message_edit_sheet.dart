import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:flutter/material.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../core/models/chat_message.dart';
import '../models/message_edit_result.dart';
import '../../../l10n/app_localizations.dart';

Future<MessageEditResult?> showMessageEditSheet(
  BuildContext context, {
  required ChatMessage message,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  final editorKey = GlobalKey<_MessageEditSheetState>();
  return showAppPopupSheet<MessageEditResult?>(
    context: context,
    title: l10n.messageEditPageTitle,
    actions: [
      AppButtonIslandButton(
        icon: Icons.send_rounded,
        semanticLabel: l10n.messageEditPageSaveAndSend,
        onTap: () => editorKey.currentState?._submit(shouldSend: true),
      ),
      appPopupDoneAction(
        semanticLabel: l10n.messageEditPageSave,
        onTap: () => editorKey.currentState?._submit(shouldSend: false),
      ),
    ],
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: _MessageEditSheet(key: editorKey, message: message),
    ),
  );
}

class _MessageEditSheet extends StatefulWidget {
  const _MessageEditSheet({super.key, required this.message});
  final ChatMessage message;
  @override
  State<_MessageEditSheet> createState() => _MessageEditSheetState();
}

class _MessageEditSheetState extends State<_MessageEditSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit({required bool shouldSend}) {
    Navigator.of(context).pop(
      MessageEditResult(
        content: _controller.text.trim(),
        shouldSend: shouldSend,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      // Ensure keyboard-safe bottom inset for the sheet
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (c, sc) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  child: AppTextField(
                    controller: _controller,
                    autofocus: false,
                    keyboardType: TextInputType.multiline,
                    minLines: 8,
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: l10n.messageEditPageHint,
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : const Color(0xFFF2F3F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.transparent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(color: Colors.transparent),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
