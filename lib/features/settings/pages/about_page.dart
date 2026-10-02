import 'dart:io';
import 'package:Kelivo/theme/app_font_weights.dart';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../icons/lucide_adapter.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../main.dart' show kAppName;
import '../../../shared/widgets/app_switch.dart';
import '../../../core/services/haptics.dart';
import 'debug_page.dart';
import 'log_viewer_page.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';
  String _buildNumber = '';
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final pkg = await PackageInfo.fromPlatform();
    setState(() {
      _version = pkg.version;
      _buildNumber = pkg.buildNumber;
    });
  }

  void _onVersionTap() {
    final now = DateTime.now();
    // Reset the counter if taps are spaced too far apart
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;

    const threshold = 7;
    if (_versionTapCount < threshold) return;

    _versionTapCount = 0; // reset after unlock
    _showEasterEgg();
  }

  void _showEasterEgg() {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        minWidth: MediaQuery.of(context).size.width,
        maxWidth: MediaQuery.of(context).size.width,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.7,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Lucide.Sparkles, size: 28, color: cs.primary),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              if (Platform.isAndroid || Platform.isIOS) ...[
                                const SizedBox(height: 24),
                                const Divider(),
                                const SizedBox(height: 16),
                                AppListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minVerticalPadding: 6,
                                  title: Text(
                                    l10n.requestLogSettingTitle,
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n.requestLogSettingSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.25,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const LogViewerPage(
                                                    initialTab: 0,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Icon(
                                            Lucide.FolderOpen,
                                            size: 20,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AppSwitch(
                                        value: dialogContext
                                            .watch<SettingsProvider>()
                                            .requestLogEnabled,
                                        onChanged: (v) => dialogContext
                                            .read<SettingsProvider>()
                                            .setRequestLogEnabled(v),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                AppListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  minVerticalPadding: 6,
                                  title: Text(
                                    l10n.flutterLogSettingTitle,
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.9,
                                      ),
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  subtitle: Text(
                                    l10n.flutterLogSettingSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.25,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(6),
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const LogViewerPage(
                                                    initialTab: 1,
                                                  ),
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Icon(
                                            Lucide.FolderOpen,
                                            size: 20,
                                            color: cs.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      AppSwitch(
                                        value: dialogContext
                                            .watch<SettingsProvider>()
                                            .flutterLogEnabled,
                                        onChanged: (v) => dialogContext
                                            .read<SettingsProvider>()
                                            .setFlutterLogEnabled(v),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),
                              const Divider(),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).maybePop(),
                        child: Text(l10n.aboutPageEasterEggButton),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openDebugPage() {
    Haptics.medium();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DebugPage()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      extendBodyBehindAppBar: false,
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.settingsPageAbout),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          // Header card: left icon + right title/description
          _iosSectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: _openDebugPage,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Image.asset(
                            'assets/app_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kAppName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: AppFontWeights.semibold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.aboutPageAppDescription,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.65),
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // iOS-style list card
          _iosSectionCard(
            children: [
              // Version (tap 7x to unlock easter egg) — logic unchanged
              _iosNavRow(
                context,
                icon: Lucide.Code,
                label: l10n.aboutPageVersion,
                detailBuilder: (_) => Text(
                  _version.isEmpty ? '...' : '$_version / $_buildNumber',
                ),
                onTap: _onVersionTap,
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// --- iOS-style helpers (mirroring Settings/Display pages) ---

Widget _iosSectionCard({required List<Widget> children}) {
  return Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final Color bg = isDark
          ? Colors.white10
          : Colors.white.withValues(alpha: 0.96);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: isDark ? 0.08 : 0.06),
            width: 0.6,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      );
    },
  );
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  VoidCallback? onTap,
  String? detailText,
  Widget Function(BuildContext ctx)? detailBuilder,
}) {
  return AppSettingsNavTile(
    icon: icon,
    label: label,
    onTap: onTap,
    detailText: detailText,
    detailBuilder: detailBuilder,
  );
}
