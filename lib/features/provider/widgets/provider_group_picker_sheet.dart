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

Future<void> showProviderGroupPickerSheet(
  BuildContext context, {
  required String providerKey,
}) async {
  final cs = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  await showAppPopupSheet<void>(
    context: context,
    title: l10n.providerGroupsPickerTitle,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => ProviderGroupPickerSheet(
      providerKey: providerKey,
      rootContext: context,
    ),
  );
}

class ProviderGroupPickerSheet extends StatelessWidget {
  const ProviderGroupPickerSheet({
    super.key,
    required this.providerKey,
    required this.rootContext,
  });

  final String providerKey;
  final BuildContext rootContext;

  Future<void> _createAndAssign(
    BuildContext context,
    SettingsProvider sp,
  ) async {
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
    await sp.setProviderGroup(providerKey, id);
    if (context.mounted) Navigator.of(context).pop(); // close sheet
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
    final current = sp.groupIdForProvider(providerKey);

    Widget tile({
      required String title,
      required bool selected,
      required VoidCallback onTap,
    }) {
      final Color onColor = selected ? cs.primary : cs.onSurface;
      return AppListTile(
        onTap: onTap,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, color: onColor),
        ),
        trailing: selected
            ? Icon(Lucide.Check, size: 18, color: cs.primary)
            : const SizedBox(width: 18),
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
                  onTap: () => unawaited(_createAndAssign(context, sp)),
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
                        selected: current == null,
                        onTap: () => unawaited(() async {
                          await sp.setProviderGroup(providerKey, null);
                          if (context.mounted) Navigator.of(context).pop();
                        }()),
                      ),
                      for (final g in groups)
                        tile(
                          title: g.name,
                          selected: current == g.id,
                          onTap: () => unawaited(() async {
                            await sp.setProviderGroup(providerKey, g.id);
                            if (context.mounted) Navigator.of(context).pop();
                          }()),
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
