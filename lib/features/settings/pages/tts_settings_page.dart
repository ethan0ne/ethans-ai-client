import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/services/tts/tts_text_selection.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/app_list_tile.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final l10n = AppLocalizations.of(context)!;

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      extendBodyBehindAppBar: false,
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.ttsServicesPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.ttsSettingsPageTitle),
      body: const TtsSettingsContent(),
    );
  }
}

class TtsSettingsContent extends StatelessWidget {
  const TtsSettingsContent({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();

    return ListView(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _SettingsSection(
          title: l10n.ttsSettingsPlaybackSection,
          children: [
            AppListTile(
              onTap: () => context
                  .read<SettingsProvider>()
                  .setTtsAutoPlayAssistantReplies(
                    !settings.ttsAutoPlayAssistantReplies,
                  ),
              title: Text(
                l10n.ttsSettingsAutoPlayTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                l10n.ttsSettingsAutoPlayDescription,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.25,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: AppSwitch(
                value: settings.ttsAutoPlayAssistantReplies,
                semanticLabel: l10n.ttsSettingsAutoPlayTitle,
                onChanged: (value) => context
                    .read<SettingsProvider>()
                    .setTtsAutoPlayAssistantReplies(value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SettingsSection(
          title: l10n.ttsSettingsTextSelectionSection,
          footer: l10n.ttsSettingsTextSelectionFallbackDescription,
          children: [
            for (final mode in TtsTextSelectionMode.values)
              _TextSelectionRow(
                mode: mode,
                selected: settings.ttsTextSelectionMode == mode,
                onTap: () => context
                    .read<SettingsProvider>()
                    .setTtsTextSelectionMode(mode),
              ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? Colors.white10 : Colors.white.withValues(alpha: 0.96);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
              width: 0.6,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) _SettingsDivider(),
              ],
            ],
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12,
                height: 1.25,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TextSelectionRow extends StatelessWidget {
  const _TextSelectionRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final TtsTextSelectionMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return AppListTile(
      onTap: onTap,
      title: Text(
        _modeTitle(mode, l10n),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        _modeDescription(mode, l10n),
        style: TextStyle(
          fontSize: 12,
          height: 1.25,
          color: cs.onSurfaceVariant,
        ),
      ),
      trailing: AnimatedOpacity(
        opacity: selected ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Icon(Lucide.Check, size: 18, color: cs.primary),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.6,
      indent: 14,
      endIndent: 12,
      color: cs.outlineVariant.withValues(alpha: 0.18),
    );
  }
}

String _modeTitle(TtsTextSelectionMode mode, AppLocalizations l10n) {
  return switch (mode) {
    TtsTextSelectionMode.fullText => l10n.ttsSettingsTextSelectionFullTextTitle,
    TtsTextSelectionMode.quotedOnly =>
      l10n.ttsSettingsTextSelectionQuotedOnlyTitle,
    TtsTextSelectionMode.outsideParentheses =>
      l10n.ttsSettingsTextSelectionOutsideParenthesesTitle,
    TtsTextSelectionMode.italicOnly =>
      l10n.ttsSettingsTextSelectionItalicOnlyTitle,
    TtsTextSelectionMode.nonItalic =>
      l10n.ttsSettingsTextSelectionNonItalicTitle,
  };
}

String _modeDescription(TtsTextSelectionMode mode, AppLocalizations l10n) {
  return switch (mode) {
    TtsTextSelectionMode.fullText =>
      l10n.ttsSettingsTextSelectionFullTextDescription,
    TtsTextSelectionMode.quotedOnly =>
      l10n.ttsSettingsTextSelectionQuotedOnlyDescription,
    TtsTextSelectionMode.outsideParentheses =>
      l10n.ttsSettingsTextSelectionOutsideParenthesesDescription,
    TtsTextSelectionMode.italicOnly =>
      l10n.ttsSettingsTextSelectionItalicOnlyDescription,
    TtsTextSelectionMode.nonItalic =>
      l10n.ttsSettingsTextSelectionNonItalicDescription,
  };
}
