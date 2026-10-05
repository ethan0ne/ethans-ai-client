import 'package:flutter/material.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/ios_tactile.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

class ChatSelectionDeleteBar extends StatelessWidget {
  const ChatSelectionDeleteBar({
    super.key,
    required this.hasMultiVersionSelection,
    required this.onDeleteCurrentVersions,
    required this.onDeleteAllVersions,
  });

  final bool hasMultiVersionSelection;
  final VoidCallback onDeleteCurrentVersions;
  final VoidCallback onDeleteAllVersions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 380;
            if (!hasMultiVersionSelection) {
              return Center(
                child: _DeleteButton(
                  icon: Lucide.Trash2,
                  label: l10n.homePageDelete,
                  color: cs.error,
                  foregroundColor: cs.onError,
                  onTap: onDeleteCurrentVersions,
                  dense: compact,
                ),
              );
            }

            return Row(
              children: [
                Expanded(
                  child: Center(
                    child: _DeleteButton(
                      icon: Lucide.Trash2,
                      label: l10n.homePageDeleteMessage,
                      color: cs.error,
                      foregroundColor: cs.onError,
                      onTap: onDeleteCurrentVersions,
                      dense: compact,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 4 : 10),
                Expanded(
                  child: Center(
                    child: _DeleteButton(
                      icon: Lucide.Trash,
                      label: l10n.homePageDeleteAllVersions,
                      color: cs.error,
                      foregroundColor: cs.onError,
                      onTap: onDeleteAllVersions,
                      dense: compact,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.foregroundColor,
    required this.onTap,
    required this.dense,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foregroundColor;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AppButtonIsland(
      children: [
        Semantics(
          button: true,
          label: label,
          child: IosCardPress(
            onTap: onTap,
            baseColor: color,
            borderRadius: BorderRadius.circular(999),
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 14 : 18,
              vertical: dense ? 11 : 12,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: dense ? 17 : 19, color: foregroundColor),
                  SizedBox(width: dense ? 6 : 9),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: dense ? 14 : 15,
                      fontWeight: AppFontWeights.semibold,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
