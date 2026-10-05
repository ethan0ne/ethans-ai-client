import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../icons/lucide_adapter.dart';

/// Selection-mode navigation content rendered by the shared [AppScaffold].
class ChatSelectionAppBar {
  const ChatSelectionAppBar({
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

  List<Widget> leadingButtons(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      AppButtonIslandButton(
        icon: Lucide.X,
        size: 20,
        semanticLabel: l10n.homePageCancel,
        onTap: onClose,
      ),
      if (onOpenMiniMap != null)
        AppButtonIslandButton(
          key: miniMapKey,
          icon: Lucide.Map,
          size: 20,
          semanticLabel: l10n.miniMapTooltip,
          onTap: onOpenMiniMap,
        ),
    ];
  }

  Widget title(BuildContext context) {
    return AppScaffoldTitle(
      AppLocalizations.of(
        context,
      )!.chatSelectionSelectedCountTitle(selectedCount),
    );
  }

  List<Widget> actions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      AppButtonIslandButton(
        icon: Lucide.Repeat,
        size: 20,
        semanticLabel: l10n.modelFetchInvertTooltip,
        onTap: onInvertSelection,
      ),
      AppButtonIslandButton(
        icon: allSelected ? Lucide.CheckSquare : Lucide.Square,
        size: 20,
        semanticLabel: allSelected
            ? l10n.storageSpaceClearSelection
            : l10n.storageSpaceSelectAll,
        onTap: onToggleSelectAll,
      ),
    ];
  }
}
