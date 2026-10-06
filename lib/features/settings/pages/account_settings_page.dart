import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../theme/design_tokens.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late final TextEditingController _nicknameController;
  bool _savingNickname = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nicknameController = TextEditingController(
      text: user?.nickname ?? user?.username ?? _emailPrefix(user?.email),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  static String _emailPrefix(String? email) => email?.split('@').first ?? '';

  String _formatGiB(int bytes) =>
      (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

  Future<bool> _saveNickname() async {
    if (_savingNickname) return false;
    final l10n = AppLocalizations.of(context)!;
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      _showMessage(l10n.authSettingsNicknameEmpty);
      return false;
    }
    if (nickname.runes.length > 64) {
      _showMessage(l10n.authSettingsNicknameTooLong);
      return false;
    }

    setState(() => _savingNickname = true);
    final saved = await context.read<AuthProvider>().setNickname(nickname);
    if (!mounted) return false;
    setState(() => _savingNickname = false);
    _showMessage(
      saved
          ? l10n.authSettingsNicknameSaved
          : l10n.authSettingsNicknameSaveFailed,
    );
    return saved;
  }

  Future<void> _showNicknameDialog() async {
    final user = context.read<AuthProvider>().user;
    _nicknameController.text =
        user?.nickname ?? user?.username ?? _emailPrefix(user?.email);
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AppAlertDialog(
          title: Text(l10n.authSettingsNickname),
          content: IosFormTextField(
            label: l10n.authSettingsNickname,
            controller: _nicknameController,
            hintText: l10n.authSettingsNicknameHint,
            inlineLabel: false,
            showLabel: false,
            textInputAction: TextInputAction.done,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).cancelButtonLabel,
              ),
            ),
            TextButton(
              onPressed: () async {
                if (await _saveNickname() && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: Text(l10n.authSettingsSave),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setAutoCleanupMedia(bool enabled) async {
    final saved = await context.read<AuthProvider>().setAutoCleanupMedia(
      enabled,
    );
    if (!saved && mounted) {
      _showMessage(AppLocalizations.of(context)!.authSettingsCleanupSaveFailed);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await context.read<AuthProvider>().logout(
      context.read<ChatService>(),
      context.read<AssistantProvider>(),
    );
    if (navigator.mounted) navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final cleanupEnabled = user?.autoCleanupMedia ?? true;
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );

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
      title: AppScaffoldTitle(l10n.authSettingsProfileTitle),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppScaffold.scrollContentTop(context),
          AppSpacing.md,
          AppScaffold.scrollContentBottom(context),
        ),
        children: [
          AppListGroupHeader(
            title: l10n.authSettingsAccountSection,
            first: true,
          ),
          AppListGroup.list(
            children: [
              AppListTile(
                onTap: _savingNickname ? null : _showNicknameDialog,
                leading: Icon(
                  Lucide.Pencil,
                  size: 22,
                  color: AppColors.secondaryLabel(brightness),
                ),
                title: Text(l10n.authSettingsNickname),
                subtitle: Text(
                  user?.nickname ?? user?.username ?? _emailPrefix(user?.email),
                  style: subtitleStyle,
                ),
                trailing: Icon(
                  Lucide.ChevronRight,
                  size: 18,
                  color: AppColors.secondaryLabel(brightness),
                ),
              ),
              AppListDivider(height: 1, thickness: 1),
              AppListTile(
                leading: Icon(
                  Lucide.AtSign,
                  size: 22,
                  color: AppColors.secondaryLabel(brightness),
                ),
                title: Text(l10n.authSettingsEmail),
                subtitle: Text(
                  user?.email ?? '',
                  style: subtitleStyle,
                ),
              ),
            ],
          ),
          AppListGroupHeader(title: l10n.authSettingsStorageSection),
          AppListGroup.list(
            children: [
              AppListTile(
                onTap: () => _setAutoCleanupMedia(!cleanupEnabled),
                leading: Icon(
                  Lucide.Trash2,
                  size: 22,
                  color: AppColors.secondaryLabel(brightness),
                ),
                title: Text(l10n.authSettingsAutoCleanupMedia),
                subtitle: Text(
                  l10n.authSettingsMediaUsage(
                    _formatGiB(user?.mediaUsedBytes ?? 0),
                    _formatGiB(user?.mediaQuotaBytes ?? 0),
                  ),
                  style: subtitleStyle,
                ),
                trailing: AppSwitch(
                  value: cleanupEnabled,
                  activeTrackColor: cs.primary,
                  semanticLabel: l10n.authSettingsAutoCleanupMedia,
                  onChanged: _setAutoCleanupMedia,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppListGroup.list(
            children: [
              AppListTile(
                leading: Icon(
                  Lucide.LogOut,
                  color: AppColors.destructiveRed,
                  size: 22,
                ),
                title: Text(
                  l10n.authSettingsLogout,
                  style: TextStyle(color: AppColors.destructiveRed),
                ),
                onTap: _logout,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
