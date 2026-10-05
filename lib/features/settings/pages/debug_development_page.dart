import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../theme/design_tokens.dart';

class DebugDevelopmentPage extends StatelessWidget {
  const DebugDevelopmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.settingsPageDebugAndDevelopment),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppScaffold.scrollContentTop(context),
          AppSpacing.md,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          AppListGroup.list(
            children: [
              AppSettingsNavTile(
                icon: Lucide.Globe,
                label: l10n.settingsServerAddress,
                detailText: settings.clientBackendBaseUrlOverride ?? '',
                onTap: () => _showOriginDialog(
                  context,
                  title: l10n.settingsServerAddress,
                  initialAddress: settings.clientBackendBaseUrlOverride ?? '',
                  description: l10n.settingsServerAddressDescription,
                  saveFailedMessage: l10n.settingsServerAddressSaveFailed,
                  onSave: settings.setClientBackendBaseUrlOverride,
                ),
              ),
              AppSettingsNavTile(
                icon: Lucide.Image,
                label: l10n.settingsMediaServerAddress,
                detailText: settings.clientMediaBaseUrlOverride ?? '',
                onTap: () => _showOriginDialog(
                  context,
                  title: l10n.settingsMediaServerAddress,
                  initialAddress: settings.clientMediaBaseUrlOverride ?? '',
                  description: l10n.settingsMediaServerAddressDescription,
                  saveFailedMessage: l10n.settingsMediaServerAddressSaveFailed,
                  onSave: settings.setClientMediaBaseUrlOverride,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showOriginDialog(
    BuildContext context, {
    required String title,
    required String initialAddress,
    required String description,
    required String saveFailedMessage,
    required Future<void> Function(String? value) onSave,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    await showAppDialog<void>(
      context: context,
      builder: (_) => _OriginAddressDialog(
        title: title,
        initialAddress: initialAddress,
        description: description,
        invalidMessage: l10n.settingsServerAddressInvalid,
        saveFailedMessage: saveFailedMessage,
        saveLabel: l10n.settingsServerAddressSave,
        onSave: onSave,
      ),
    );
  }
}

class _OriginAddressDialog extends StatefulWidget {
  const _OriginAddressDialog({
    required this.title,
    required this.initialAddress,
    required this.description,
    required this.invalidMessage,
    required this.saveFailedMessage,
    required this.saveLabel,
    required this.onSave,
  });

  final String title;
  final String initialAddress;
  final String description;
  final String invalidMessage;
  final String saveFailedMessage;
  final String saveLabel;
  final Future<void> Function(String? value) onSave;

  @override
  State<_OriginAddressDialog> createState() => _OriginAddressDialogState();
}

class _OriginAddressDialogState extends State<_OriginAddressDialog> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialAddress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final entered = _controller.text.trim();
    final normalized = entered.isEmpty ? null : _normalizeOrigin(entered);
    if (entered.isNotEmpty && normalized == null) {
      setState(() => _errorMessage = widget.invalidMessage);
      return;
    }

    final override = normalized;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.onSave(override);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = widget.saveFailedMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IosFormTextField(
            label: widget.title,
            controller: _controller,
            hintText: 'https://example.com',
            inlineLabel: false,
            showLabel: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autofocus: true,
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _errorMessage ?? widget.description,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: _errorMessage == null
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.error,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: _isSaving ? null : _save,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}

String? _normalizeOrigin(String value) {
  if (RegExp(r'\s').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  try {
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return null;
  } on FormatException {
    return null;
  }
  return uri.origin;
}
