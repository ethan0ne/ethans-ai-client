import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../icons/lucide_adapter.dart';

class ChatSelectionAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ChatSelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    this.onOpenMiniMap,
    this.miniMapKey,
    required this.onToggleSelectAll,
    required this.onInvertSelection,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback? onOpenMiniMap;
  final Key? miniMapKey;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onInvertSelection;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leadingWidth: onOpenMiniMap != null ? 108 : 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: AppButtonIsland(
          children: [
            AppButtonIslandButton(
              icon: Lucide.X,
              semanticLabel: l10n.homePageCancel,
              onTap: onClose,
            ),
            if (onOpenMiniMap != null)
              AppButtonIslandButton(
                key: miniMapKey,
                icon: Lucide.Map,
                semanticLabel: l10n.miniMapTooltip,
                onTap: onOpenMiniMap,
              ),
          ],
        ),
      ),
      title: AppScaffoldTitle(
        l10n.chatSelectionSelectedCountTitle(selectedCount),
        color: cs.onSurface,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: AppButtonIsland(
            children: [
              AppButtonIslandButton(
                label: l10n.modelFetchInvertTooltip,
                labelColor: cs.onSurface,
                semanticLabel: l10n.modelFetchInvertTooltip,
                onTap: onInvertSelection,
              ),
              AppButtonIslandButton(
                icon: allSelected ? Lucide.CheckSquare : Lucide.Square,
                size: 18,
                label: l10n.storageSpaceSelectAll,
                labelColor: cs.onSurface,
                semanticLabel: l10n.storageSpaceSelectAll,
                onTap: onToggleSelectAll,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
