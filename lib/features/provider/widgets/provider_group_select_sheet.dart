import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/app_list_group.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../pages/provider_groups_page.dart';

Future<String?> showProviderGroupSelectSheet(
  BuildContext context, {
  required BuildContext rootContext,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  return showAppPopupSheet<String?>(
    context: context,
    title: l10n.providerGroupsPickerTitle,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => ProviderGroupSelectSheet(rootContext: rootContext),
  );
}

class ProviderGroupSelectSheet extends StatelessWidget {
  const ProviderGroupSelectSheet({super.key, required this.rootContext});

  final BuildContext rootContext;

  Future<void> _createGroup(BuildContext context, SettingsProvider sp) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(l10n.providerGroupsCreateDialogTitle),
        content: AppTextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.providerGroupsNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.providerGroupsCreateDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.providerGroupsCreateDialogOk),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final id = await sp.createGroup(name);
    if (id.isEmpty) return;
    if (context.mounted) Navigator.of(context).pop(id);
  }

  Future<void> _openGroupManager(BuildContext context) async {
    await Navigator.of(
      rootContext,
    ).push(MaterialPageRoute(builder: (_) => const ProviderGroupsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final sp = context.watch<SettingsProvider>();
    final groups = sp.providerGroups;

    Widget tile({required String title, required VoidCallback onTap}) {
      return AppListTile(
        onTap: onTap,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, color: cs.onSurface),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Spacer(),
                IosIconButton(
                  icon: Lucide.Plus,
                  minSize: 40,
                  size: 20,
                  semanticLabel: l10n.providerGroupsCreateNewGroupAction,
                  onTap: () => unawaited(_createGroup(context, sp)),
                ),
                IosIconButton(
                  icon: Lucide.Settings,
                  minSize: 40,
                  size: 20,
                  semanticLabel: l10n.providerGroupsManageAction,
                  onTap: () => unawaited(_openGroupManager(context)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: [
                  AppListGroup.list(
                    children: [
                      tile(
                        title: l10n.providerGroupsOtherUngroupedOption,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(SettingsProvider.providerUngroupedGroupKey),
                      ),
                      for (final g in groups)
                        tile(
                          title: g.name,
                          onTap: () => Navigator.of(context).pop(g.id),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
