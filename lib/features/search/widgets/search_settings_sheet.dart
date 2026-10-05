import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:Kelivo/shared/widgets/app_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/search/search_service.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/api/builtin_tools.dart';
import '../../../icons/lucide_adapter.dart';
import '../pages/search_services_page.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../core/services/haptics.dart';
import '../../../theme/app_font_weights.dart';

Future<void> showSearchSettingsSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  await showAppPopupSheet(
    context: context,
    title: l10n.searchSettingsSheetTitle,
    showCloseButton: false,
    actions: [
      appPopupDoneAction(
        semanticLabel: l10n.homePageDone,
        onTap: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
    isScrollControlled: true,
    builder: (ctx) => const _SearchSettingsSheet(),
  );
}

class _SearchSettingsSheet extends StatelessWidget {
  const _SearchSettingsSheet();

  String _nameOf(BuildContext context, SearchServiceOptions s) {
    final svc = SearchService.getService(s);
    return svc.name;
  }

  Future<void> _setBuiltInSearchEnabled({
    required SettingsProvider settings,
    required ProviderConfig providerCfg,
    required String providerKey,
    required String modelId,
    required bool enabled,
  }) async {
    final overrides = Map<String, dynamic>.from(providerCfg.modelOverrides);
    final rawMo = overrides[modelId];
    final baseMo = rawMo is Map ? rawMo : null;
    final mo = Map<String, dynamic>.from(
      baseMo?.map((k, val) => MapEntry(k.toString(), val)) ??
          const <String, dynamic>{},
    );
    final builtIns = BuiltInToolNames.parseAndNormalize(mo['builtInTools']);
    if (enabled) {
      builtIns.add(BuiltInToolNames.search);
    } else {
      builtIns.remove(BuiltInToolNames.search);
    }
    if (builtIns.isEmpty) {
      mo.remove('builtInTools');
    } else {
      mo['builtInTools'] = BuiltInToolNames.orderedForStorage(builtIns);
    }
    overrides[modelId] = mo;
    await settings.setProviderConfig(
      providerKey,
      providerCfg.copyWith(modelOverrides: overrides),
    );
  }

  Future<void> _setClaudeDynamicWebSearchEnabled({
    required SettingsProvider settings,
    required ProviderConfig providerCfg,
    required String providerKey,
    required String modelId,
    required bool enabled,
  }) async {
    final overrides = Map<String, dynamic>.from(providerCfg.modelOverrides);
    final rawMo = overrides[modelId];
    final baseMo = rawMo is Map ? rawMo : null;
    final mo = Map<String, dynamic>.from(
      baseMo?.map((k, val) => MapEntry(k.toString(), val)) ??
          const <String, dynamic>{},
    );
    final rawWs = mo['webSearch'];
    final ws = Map<String, dynamic>.from(
      rawWs is Map
          ? rawWs.map((k, val) => MapEntry(k.toString(), val))
          : const <String, dynamic>{},
    );
    if (enabled) {
      ws['toolVersion'] = 'web_search_20260209';
    } else {
      ws.remove('toolVersion');
      ws.remove('tool_version');
    }
    if (ws.isEmpty) {
      mo.remove('webSearch');
    } else {
      mo['webSearch'] = ws;
    }
    overrides[modelId] = mo;
    await settings.setProviderConfig(
      providerKey,
      providerCfg.copyWith(modelOverrides: overrides),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final settingsNotifier = context.read<SettingsProvider>();
    final ap = context.watch<AssistantProvider>();
    final assistantNotifier = context.read<AssistantProvider>();
    final a = ap.currentAssistant;
    final services = settings.searchServices;
    final selected = settings.searchServiceSelected.clamp(
      0,
      services.isNotEmpty ? services.length - 1 : 0,
    );
    final enabled = ap.currentSearchEnabled;

    // Determine if current selected model supports built-in search
    final providerKey = a?.chatModelProvider ?? settings.currentModelProvider;
    final modelId = a?.chatModelId ?? settings.currentModelId;
    final cfg = (providerKey != null)
        ? settings.getProviderConfig(providerKey)
        : null;
    final supportsBuiltInSearch =
        BuiltInToolsHelper.supportsBuiltInSearchForModel(
          cfg: cfg,
          modelId: modelId,
        );
    final supportsClaudeDynamicWebSearch =
        BuiltInToolsHelper.supportsClaudeDynamicWebSearchForModel(
          cfg: cfg,
          modelId: modelId,
        );

    // Read current built-in search toggle from modelOverrides
    final hasBuiltInSearch = BuiltInToolsHelper.isBuiltInSearchEnabled(
      cfg: cfg,
      modelId: modelId,
    );
    final hasClaudeDynamicWebSearch =
        BuiltInToolsHelper.isClaudeDynamicWebSearchEnabled(
          cfg: cfg,
          modelId: modelId,
        );
    final builtInMode = hasBuiltInSearch;

    Widget searchToggleTile({
      required IconData icon,
      required String title,
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      Widget? accessory,
    }) => AppListTile(
      onTapFeedback: Haptics.light,
      onTap: () => onChanged(!value),
      leading: Icon(icon, size: 24, color: cs.primary),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accessory != null) accessory,
          if (accessory != null) const SizedBox(width: 4),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );

    final modelSearchTiles = <Widget>[];
    if (cfg != null &&
        supportsBuiltInSearch &&
        providerKey != null &&
        (modelId ?? '').isNotEmpty) {
      final providerCfg = cfg;
      final mid = modelId!;
      modelSearchTiles.add(
        searchToggleTile(
          icon: Lucide.Search,
          title: l10n.searchSettingsSheetBuiltinSearchTitle,
          value: hasBuiltInSearch,
          onChanged: (value) async {
            await _setBuiltInSearchEnabled(
              settings: settingsNotifier,
              providerCfg: providerCfg,
              providerKey: providerKey,
              modelId: mid,
              enabled: value,
            );
            if (value) {
              await assistantNotifier.setSearchEnabledForCurrentAssistant(
                false,
              );
            }
          },
        ),
      );
      if (supportsClaudeDynamicWebSearch) {
        modelSearchTiles.add(const AppListDivider.forTile(hasLeading: true));
        modelSearchTiles.add(
          searchToggleTile(
            icon: Lucide.Search,
            title: l10n.searchSettingsSheetClaudeDynamicSearchTitle,
            subtitle: l10n.searchSettingsSheetClaudeDynamicSearchDescription,
            value: hasClaudeDynamicWebSearch,
            onChanged: (value) => _setClaudeDynamicWebSearchEnabled(
              settings: settingsNotifier,
              providerCfg: providerCfg,
              providerKey: providerKey,
              modelId: mid,
              enabled: value,
            ),
          ),
        );
      }
    }

    final serviceRows = <Widget>[];
    if (a?.cloudHosted == true) {
      final serverSelected = a?.searchProviderMode != 'client';
      serviceRows.add(
        AppListTile(
          selected: serverSelected,
          onTapFeedback: Haptics.light,
          onTap: () {
            context
                .read<AssistantProvider>()
                .setSearchProviderModeForCurrentAssistant('server');
            Navigator.of(context).maybePop();
          },
          leading: Icon(Lucide.Network, size: 24, color: cs.primary),
          title: Text(
            l10n.searchServiceNameServerSearch,
            style: const TextStyle(fontSize: 16),
          ),
          trailing: serverSelected
              ? Icon(Lucide.Check, size: 18, color: cs.primary)
              : null,
        ),
      );
    }
    for (var i = 0; i < services.length; i++) {
      if (serviceRows.isNotEmpty) {
        serviceRows.add(const AppListDivider.forTile(hasLeading: true));
      }
      final service = services[i];
      final isSelected =
          i == selected &&
          !(a?.cloudHosted == true && a?.searchProviderMode != 'client');
      serviceRows.add(
        AppListTile(
          selected: isSelected,
          onTapFeedback: Haptics.light,
          onTap: () {
            context.read<SettingsProvider>().setSearchServiceSelected(i);
            if (a?.cloudHosted == true) {
              context
                  .read<AssistantProvider>()
                  .setSearchProviderModeForCurrentAssistant('client');
            }
            Navigator.of(context).maybePop();
          },
          leading: _BrandBadge.forService(service, size: 24),
          title: Text(
            _nameOf(context, service),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16),
          ),
          trailing: isSelected
              ? Icon(Lucide.Check, size: 18, color: cs.primary)
              : null,
        ),
      );
    }

    final maxHeight = MediaQuery.of(context).size.height * 0.8;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (modelSearchTiles.isNotEmpty) ...[
                  AppListGroup.list(children: modelSearchTiles),
                  const SizedBox(height: 14),
                ],

                // Toggle card
                if (!builtInMode) ...[
                  AppListGroup(
                    child: searchToggleTile(
                      icon: Lucide.Globe,
                      title: l10n.searchSettingsSheetWebSearchTitle,
                      value: enabled,
                      accessory: IconButton(
                        tooltip:
                            l10n.searchSettingsSheetOpenSearchServicesTooltip,
                        icon: Icon(Lucide.Settings, size: 20),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SearchServicesPage(),
                            ),
                          );
                        },
                      ),
                      onChanged: (value) => context
                          .read<AssistantProvider>()
                          .setSearchEnabledForCurrentAssistant(value),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                // Services list (iOS-style rows like learning mode)
                if (!builtInMode &&
                    (services.isNotEmpty || a?.cloudHosted == true)) ...[
                  // [kelivo-hosted] "服务器搜索" — fixed, non-configurable
                  // entry, only for a hosted assistant (BYOK never routes
                  // through a server that could act on this). Not a stored
                  // `SearchServiceOptions`, so there's nothing to add/edit/
                  // delete — just a mode flag on the current assistant.
                  // Defaults to selected for a hosted assistant that hasn't
                  // explicitly picked a device-local provider yet
                  // (`searchProviderMode == null`) — mirrors the backend's
                  // own default (`client_chat_task.py`, anything other than
                  // explicit `"client"` executes server-side).
                  AppListGroup.list(children: serviceRows),
                  const SizedBox(height: 8),
                ] else if (!builtInMode) ...[
                  Text(
                    l10n.searchSettingsSheetNoServicesMessage,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Brand badge for known services using assets/icons; falls back to letter if unknown
class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.name, this.size = 20});
  final String name;
  final double size;

  static Widget forService(SearchServiceOptions s, {double size = 24}) {
    final n = _nameForService(s);
    return _BrandBadge(name: n, size: size);
  }

  static String _nameForService(SearchServiceOptions s) {
    if (s is BingLocalOptions) return 'bing';
    if (s is DuckDuckGoOptions) return 'duckduckgo';
    if (s is TavilyOptions) return 'tavily';
    if (s is ExaOptions) return 'exa';
    if (s is ZhipuOptions) return 'zhipu';
    if (s is SearXNGOptions) return 'searxng';
    if (s is LinkUpOptions) return 'linkup';
    if (s is BraveOptions) return 'brave';
    if (s is MetasoOptions) return 'metaso';
    if (s is OllamaOptions) return 'ollama';
    if (s is JinaOptions) return 'jina';
    if (s is PerplexityOptions) return 'perplexity';
    if (s is BochaOptions) return 'bocha';
    if (s is SerperOptions) return 'serper';
    if (s is GrokOptions) return 'grok';
    return 'search';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use BrandAssets to get the icon path
    final asset = BrandAssets.assetForName(name);
    final bg = isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1);
    if (asset != null) {
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final ColorFilter? tint = (isDark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: SvgPicture.asset(
            asset,
            width: size * 0.62,
            height: size * 0.62,
            colorFilter: tint,
          ),
        );
      } else {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Image.asset(
            asset,
            width: size * 0.62,
            height: size * 0.62,
            fit: BoxFit.contain,
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
