import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import '../../../icons/lucide_adapter.dart';
import 'provider_detail_page.dart';
import '../widgets/import_provider_sheet.dart';
import '../widgets/add_provider_sheet.dart';
// grid reorder removed in favor of iOS-style list reordering
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../core/services/haptics.dart';
import '../widgets/share_provider_sheet.dart';
import '../../../core/providers/assistant_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'dart:ui' as ui show ImageFilter;
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../widgets/provider_avatar.dart';
import '../widgets/provider_group_select_sheet.dart';
import '../../../utils/provider_grouping_logic.dart';
import '../../../theme/app_font_weights.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/widgets/app_list_tile.dart';

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  static const Duration _groupReorderRestoreDelay = Duration(milliseconds: 300);

  final Set<String> _settleKeys = {};
  bool _selectMode = false;
  final Set<String> _selected = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _groupReorderRestoreTimer;
  bool _temporarilyCollapseGroupedProviders = false;
  bool _groupHeaderDragActive = false;
  bool _groupHeaderReorderInFlight = false;
  bool _groupHeaderRestorePending = false;

  @override
  void dispose() {
    _groupReorderRestoreTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _effectiveGroupCollapsed(SettingsProvider settings, String groupKey) =>
      _temporarilyCollapseGroupedProviders ||
      settings.isGroupCollapsed(groupKey);

  void _startTemporaryGroupCollapse({bool lockReorder = false}) {
    _groupReorderRestoreTimer?.cancel();
    setState(() {
      _temporarilyCollapseGroupedProviders = true;
      _groupHeaderRestorePending = lockReorder;
    });
  }

  void _scheduleTemporaryGroupRestore() {
    _groupReorderRestoreTimer?.cancel();
    _groupReorderRestoreTimer = Timer(_groupReorderRestoreDelay, () {
      if (!mounted) return;
      setState(() {
        _temporarilyCollapseGroupedProviders = false;
        _groupHeaderRestorePending = false;
      });
    });
  }

  Future<void> _handleAddProvider() async {
    final l10n = AppLocalizations.of(context)!;
    final createdKey = await showAddProviderSheet(context);
    if (!mounted || createdKey == null || createdKey.isEmpty) {
      return;
    }
    setState(() {});
    showAppSnackBar(
      context,
      message: l10n.providersPageProviderAddedSnackbar,
      type: NotificationType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Base, fixed providers (recompute each build so dynamic additions reflect immediately)
    final base = _providers(l10n: l10n);

    // Dynamic providers from settings
    final settings = context.watch<SettingsProvider>();
    final cfgs = settings.providerConfigs;
    final baseKeys = {for (final p in base) p.keyName};
    final dynamicItems = <_Provider>[];
    cfgs.forEach((key, cfg) {
      if (!baseKeys.contains(key)) {
        dynamicItems.add(
          _Provider(
            name: (cfg.name.isNotEmpty ? cfg.name : key),
            keyName: key,
            enabled: cfg.enabled,
            modelCount: cfg.models.length,
          ),
        );
      }
    });

    // Merge base + dynamic, then apply saved order
    final merged = <_Provider>[...base, ...dynamicItems];
    final order = settings.providersOrder;
    final map = {for (final p in merged) p.keyName: p};
    final tmp = <_Provider>[];
    for (final k in order) {
      final p = map.remove(k);
      if (p != null) tmp.add(p);
    }
    // Append any remaining providers not recorded in order
    tmp.addAll(map.values);
    final items = tmp;
    final filteredItems = _applySearchToProviders(
      items: items,
      settings: settings,
      normalizedQuery: _searchQuery,
    );

    final groupingActive = settings.providerGroupingActive;
    final groupingRows = groupingActive
        ? _buildProviderGroupingRows(
            l10n: l10n,
            settings: settings,
            items: items,
            isGroupCollapsed: (groupKey) =>
                _effectiveGroupCollapsed(settings, groupKey),
            normalizedQuery: _searchQuery,
          )
        : const <_ProviderGroupingRowVM>[];
    final visibleProviderKeys = groupingActive
        ? {
            for (final row in groupingRows)
              if (row is _ProviderGroupingProviderVM) row.provider.keyName,
          }
        : {for (final p in filteredItems) p.keyName};

    return AppScaffold(
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.providersPageTitle),
      actions: [
        AppButtonIslandButton(
          icon: _selectMode ? Lucide.Check : Lucide.circleDot,
          semanticLabel: _selectMode
              ? l10n.searchServicesPageDone
              : l10n.providersPageMultiSelectTooltip,
          onTap: () {
            setState(() {
              if (_selectMode) _selected.clear();
              _selectMode = !_selectMode;
            });
          },
        ),
        AppButtonIslandButton(
          icon: Lucide.cloudDownload,
          semanticLabel: l10n.providersPageImportTooltip,
          onTap: () async {
            await showImportProviderSheet(context);
            if (!mounted) return;
            setState(() {});
          },
        ),
        AppButtonIslandButton(
          icon: Lucide.Plus,
          semanticLabel: l10n.providersPageAddTooltip,
          onTap: _handleAddProvider,
        ),
      ],
      body: Stack(
        children: [
          !groupingActive
              ? _ProvidersList(
                  header: _ProvidersSearchField(
                    controller: _searchController,
                    hintText: l10n.providersPageSearchHint,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = _normalizeSearchQuery(value);
                      });
                    },
                    onClear: () {
                      if (_searchController.text.isEmpty) return;
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                  items: filteredItems,
                  selectMode: _selectMode,
                  selectedKeys: _selected,
                  reorderEnabled: !_selectMode && _searchQuery.isEmpty,
                  onToggleSelect: (key) {
                    setState(() {
                      if (_selected.contains(key)) {
                        _selected.remove(key);
                      } else {
                        _selected.add(key);
                      }
                    });
                  },
                  onReorder: (oldIndex, newIndex) async {
                    if (_searchQuery.isNotEmpty || _selectMode) return;
                    final moved = items[oldIndex];
                    final mut = List<_Provider>.of(items);
                    final item = mut.removeAt(oldIndex);
                    mut.insert(newIndex, item);
                    setState(() => _settleKeys.add(moved.keyName));
                    await context.read<SettingsProvider>().setProvidersOrder([
                      for (final p in mut) p.keyName,
                    ]);
                    Future.delayed(const Duration(milliseconds: 220), () {
                      if (!mounted) return;
                      setState(() => _settleKeys.remove(moved.keyName));
                    });
                  },
                  settlingKeys: _settleKeys,
                )
              : _GroupedProvidersList(
                  header: _ProvidersSearchField(
                    controller: _searchController,
                    hintText: l10n.providersPageSearchHint,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = _normalizeSearchQuery(value);
                      });
                    },
                    onClear: () {
                      if (_searchController.text.isEmpty) return;
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                  rows: groupingRows,
                  selectMode: _selectMode,
                  searchActive: _searchQuery.isNotEmpty,
                  freezeContainerHeight:
                      _groupHeaderDragActive ||
                      _temporarilyCollapseGroupedProviders,
                  persistedIsGroupCollapsed: settings.isGroupCollapsed,
                  selectedKeys: _selected,
                  reorderEnabled:
                      !_selectMode &&
                      _searchQuery.isEmpty &&
                      !_groupHeaderRestorePending,
                  onToggleSelect: (key) {
                    setState(() {
                      if (_selected.contains(key)) {
                        _selected.remove(key);
                      } else {
                        _selected.add(key);
                      }
                    });
                  },
                  onReorder: (oldIndex, newIndex) async {
                    if (_selectMode || _searchQuery.isNotEmpty) return;
                    if (groupingRows.isEmpty) return;
                    final sp = context.read<SettingsProvider>();

                    final logicRows = <ProviderGroupingRowVM>[
                      for (final r in groupingRows)
                        if (r is _ProviderGroupingHeaderVM)
                          ProviderGroupingHeaderVM(groupKey: r.groupKey)
                        else if (r is _ProviderGroupingProviderVM)
                          ProviderGroupingProviderVM(
                            providerKey: r.provider.keyName,
                            groupKey: r.groupKey,
                          ),
                    ];

                    if (logicRows[oldIndex] is ProviderGroupingHeaderVM) {
                      _groupHeaderReorderInFlight = true;
                      final intent = analyzeProviderGroupingHeaderReorder(
                        rows: logicRows,
                        oldIndex: oldIndex,
                        newIndex: newIndex,
                      );
                      if (intent == null) {
                        _groupHeaderReorderInFlight = false;
                        return;
                      }

                      final visibleHeaderKeys = [
                        for (final row in groupingRows)
                          if (row is _ProviderGroupingHeaderVM) row.groupKey,
                      ];
                      final fullDisplayKeys = buildProviderGroupDisplayKeys(
                        groups: sp.providerGroups,
                        ungroupedIndex: sp.providerUngroupedDisplayIndex,
                      );
                      final oldActualIndex = fullDisplayKeys.indexOf(
                        intent.groupKey,
                      );
                      if (oldActualIndex < 0) {
                        _groupHeaderReorderInFlight = false;
                        return;
                      }

                      final targetInsertIndex =
                          mapVisibleGroupTargetToActualInsertIndex(
                            fullDisplayKeys: fullDisplayKeys,
                            visibleHeaderKeys: visibleHeaderKeys,
                            movedGroupKey: intent.groupKey,
                            targetVisibleIndex: intent.targetDisplayIndex,
                          );
                      final rawNewIndex = targetInsertIndex > oldActualIndex
                          ? targetInsertIndex + 1
                          : targetInsertIndex;

                      _startTemporaryGroupCollapse(lockReorder: true);
                      try {
                        await sp.reorderProviderGroupsWithUngrouped(
                          oldActualIndex,
                          rawNewIndex,
                        );
                      } finally {
                        _groupHeaderDragActive = false;
                        _groupHeaderReorderInFlight = false;
                        _scheduleTemporaryGroupRestore();
                      }
                      return;
                    }

                    final analysis = analyzeProviderGroupingReorder(
                      rows: logicRows,
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                      isGroupCollapsed: sp.isGroupCollapsed,
                    );

                    if (analysis.blockedReason ==
                        ProviderGroupingReorderBlockedReason
                            .targetGroupCollapsed) {
                      showAppSnackBar(
                        context,
                        message: l10n.providerGroupsExpandToMoveToast,
                        type: NotificationType.info,
                      );
                      if (mounted) setState(() {});
                      return;
                    }

                    final intent = analysis.intent;
                    if (intent == null) return;

                    final targetGroupId =
                        intent.targetGroupKey ==
                            SettingsProvider.providerUngroupedGroupKey
                        ? null
                        : intent.targetGroupKey;

                    setState(() => _settleKeys.add(intent.providerKey));
                    await sp.moveProvider(
                      intent.providerKey,
                      targetGroupId,
                      intent.targetPos,
                    );
                    Future.delayed(const Duration(milliseconds: 220), () {
                      if (!mounted) return;
                      setState(() => _settleKeys.remove(intent.providerKey));
                    });
                  },
                  onReorderStart: (index) {
                    if (index < 0 || index >= groupingRows.length) return;
                    if (groupingRows[index] is! _ProviderGroupingHeaderVM) {
                      return;
                    }
                    _groupHeaderDragActive = true;
                    _groupHeaderReorderInFlight = false;
                    _startTemporaryGroupCollapse();
                  },
                  onReorderEnd: (_) {
                    if (!_groupHeaderDragActive ||
                        _groupHeaderReorderInFlight) {
                      return;
                    }
                    _groupHeaderDragActive = false;
                    _scheduleTemporaryGroupRestore();
                  },
                  settlingKeys: _settleKeys,
                ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SelectionBar(
              visible: _selectMode,
              count: _selected.length,
              total: visibleProviderKeys.length,
              onExport: _onExportSelected,
              onDelete: _onDeleteSelected,
              onMoveToGroup: _onMoveSelectedToGroup,
              onSelectAll: () {
                setState(() {
                  // Select all deletable (non-built-in) providers
                  final baseKeys = {for (final p in base) p.keyName};
                  final deletable = [
                    for (final key in visibleProviderKeys)
                      if (!baseKeys.contains(key)) key,
                  ];
                  final allSelected =
                      deletable.isNotEmpty &&
                      deletable.every(_selected.contains) &&
                      _selected.length == deletable.length;
                  _selected.removeWhere((k) => !deletable.contains(k));
                  if (allSelected) {
                    // Unselect all deletable
                    for (final k in deletable) {
                      _selected.remove(k);
                    }
                  } else {
                    // Select all deletable
                    _selected
                      ..removeWhere((k) => !deletable.contains(k))
                      ..addAll(deletable);
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // [kelivo-hosted] kelivo-arch.md §8 — upstream hardcodes a placeholder
  // row for ~13 built-in BYOK providers here regardless of persisted
  // config state (disabling the seeding in
  // `SettingsProvider._load()` alone doesn't hide these). Our product
  // doesn't want users bringing/seeing their own providers, so this list
  // stays empty; user-added custom providers (via `dynamicItems` below)
  // still show up normally.
  List<_Provider> _providers({required AppLocalizations l10n}) => [];

  List<_ProviderGroupingRowVM> _buildProviderGroupingRows({
    required AppLocalizations l10n,
    required SettingsProvider settings,
    required List<_Provider> items,
    required bool Function(String groupKey) isGroupCollapsed,
    String normalizedQuery = '',
  }) {
    final ungroupedKey = SettingsProvider.providerUngroupedGroupKey;
    final groups = settings.providerGroups;
    final groupById = {for (final g in groups) g.id: g};
    final providersByGroupKey = <String, List<_Provider>>{
      for (final g in groups) g.id: <_Provider>[],
      ungroupedKey: <_Provider>[],
    };

    for (final p in items) {
      final gid = settings.groupIdForProvider(p.keyName);
      final groupKey = (gid != null && groupById.containsKey(gid))
          ? gid
          : ungroupedKey;
      (providersByGroupKey[groupKey] ??= <_Provider>[]).add(p);
    }

    final rows = <_ProviderGroupingRowVM>[];
    final searching = normalizedQuery.isNotEmpty;

    List<_Provider> providersForGroup(String groupKey, String title) {
      final list = providersByGroupKey[groupKey] ?? const <_Provider>[];
      if (!searching) return list;
      final groupMatched = _matchesQuery(title, normalizedQuery);
      if (groupMatched) return list;
      return [
        for (final provider in list)
          if (_providerMatches(provider, settings, normalizedQuery)) provider,
      ];
    }

    final displayKeys = buildProviderGroupDisplayKeys(
      groups: groups,
      ungroupedIndex: settings.providerUngroupedDisplayIndex,
    );

    for (final groupKey in displayKeys) {
      final isUngrouped = groupKey == ungroupedKey;
      final title = isUngrouped
          ? l10n.providerGroupsOther
          : groupById[groupKey]?.name;
      if (title == null) continue;
      final list = providersForGroup(groupKey, title);
      if (list.isEmpty) continue; // hide empty groups on list page
      final collapsed = searching ? false : isGroupCollapsed(groupKey);
      rows.add(
        _ProviderGroupingHeaderVM(
          groupKey: groupKey,
          title: title,
          count: list.length,
          collapsed: collapsed,
        ),
      );
      for (final p in list) {
        rows.add(_ProviderGroupingProviderVM(provider: p, groupKey: groupKey));
      }
    }
    return rows;
  }

  List<_Provider> _applySearchToProviders({
    required List<_Provider> items,
    required SettingsProvider settings,
    required String normalizedQuery,
  }) {
    if (normalizedQuery.isEmpty) return items;
    return [
      for (final provider in items)
        if (_providerMatches(provider, settings, normalizedQuery)) provider,
    ];
  }

  bool _providerMatches(
    _Provider provider,
    SettingsProvider settings,
    String normalizedQuery,
  ) {
    if (normalizedQuery.isEmpty) return true;
    final cfg = settings.getProviderConfig(
      provider.keyName,
      defaultName: provider.name,
    );
    final displayName = (cfg.name.isNotEmpty ? cfg.name : provider.name);
    return _matchesQuery(displayName, normalizedQuery);
  }

  bool _matchesQuery(String value, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    return value.toLowerCase().contains(normalizedQuery);
  }

  String _normalizeSearchQuery(String value) => value.trim().toLowerCase();

  Future<void> _onExportSelected() async {
    if (_selected.isEmpty) return;
    final keys = _selected.toList(growable: false);
    if (keys.length == 1) {
      await showShareProviderSheet(context, keys.first);
      return;
    }
    await _showMultiExportSheet(context, keys);
  }

  Future<void> _onMoveSelectedToGroup() async {
    if (_selected.isEmpty) return;
    final picked = await showProviderGroupSelectSheet(
      context,
      rootContext: context,
    );
    if (!mounted) return;
    if (picked == null) return;
    final targetGroupId = picked == SettingsProvider.providerUngroupedGroupKey
        ? null
        : picked;
    await context.read<SettingsProvider>().moveProvidersToGroup(
      _selected,
      targetGroupId,
    );
    if (!mounted) return;
    setState(() => _selected.clear());
  }

  Future<void> _onDeleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final assistantProvider = context.read<AssistantProvider>();
    final settingsProvider = context.read<SettingsProvider>();
    // Skip built-in providers (default ones)
    final builtInKeys = {for (final p in _providers(l10n: l10n)) p.keyName};
    final keysToDelete = _selected
        .where((k) => !builtInKeys.contains(k))
        .toList(growable: false);

    if (keysToDelete.isEmpty) {
      // Nothing deletable selected
      return;
    }

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(
          '${l10n.providerDetailPageDeleteProviderTitle} (${keysToDelete.length})',
        ),
        content: Text(l10n.providersPageDeleteSelectedConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.providerDetailPageCancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.providerDetailPageDeleteButton,
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    // 尽可能复用 ProviderDetailPage 删除前的清理逻辑：清理引用该 provider 的助手模型选择
    for (final assistant in assistantProvider.assistants) {
      if (keysToDelete.contains(assistant.chatModelProvider)) {
        await assistantProvider.updateAssistant(
          assistant.copyWith(clearChatModel: true),
        );
      }
    }
    for (final key in keysToDelete) {
      await settingsProvider.removeProviderConfig(key);
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selectMode = false;
    });
    showAppSnackBar(
      context,
      message: l10n.providersPageDeleteSelectedSnackbar,
      type: NotificationType.success,
    );
  }
}

sealed class _ProviderGroupingRowVM {
  const _ProviderGroupingRowVM();
}

class _ProviderGroupingHeaderVM extends _ProviderGroupingRowVM {
  const _ProviderGroupingHeaderVM({
    required this.groupKey,
    required this.title,
    required this.count,
    required this.collapsed,
  });

  /// groupId or `__ungrouped__`
  final String groupKey;
  final String title;
  final int count;
  final bool collapsed;
}

class _ProviderGroupingProviderVM extends _ProviderGroupingRowVM {
  const _ProviderGroupingProviderVM({
    required this.provider,
    required this.groupKey,
  });

  final _Provider provider;

  /// groupId or `__ungrouped__`
  final String groupKey;
}

// iOS-style providers list (reorderable by long-press)
Widget _providerGroupItem(Widget child, int index, int count) {
  return KeyedSubtree(
    key: child.key,
    child: AppListGroup(
      borderRadius: BorderRadius.vertical(
        top: index == 0 ? const Radius.circular(AppRadius.md) : Radius.zero,
        bottom: index == count - 1
            ? const Radius.circular(AppRadius.md)
            : Radius.zero,
      ),
      child: child,
    ),
  );
}

class _ProvidersList extends StatelessWidget {
  const _ProvidersList({
    required this.header,
    required this.items,
    required this.onReorder,
    required this.settlingKeys,
    required this.selectMode,
    required this.reorderEnabled,
    required this.selectedKeys,
    required this.onToggleSelect,
  });
  final List<_Provider> items;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Set<String> settlingKeys;
  final bool selectMode;
  final bool reorderEnabled;
  final Set<String> selectedKeys;
  final void Function(String key) onToggleSelect;

  final Widget header;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: AppScaffold.scrollContentTop(context)),
          sliver: SliverToBoxAdapter(child: header),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            AppScaffold.scrollContentBottom(
              context,
              spacing: selectMode
                  ? 100
                  : AppScaffold.defaultScrollContentBottomSpacing,
            ),
          ),
          sliver: SliverReorderableList(
            itemCount: items.length,
            onReorderItem: reorderEnabled ? onReorder : (_, __) {},
            proxyDecorator: (child, index, animation) => Opacity(
              opacity: 0.95,
              child: Transform.scale(scale: 0.98, child: child),
            ),
            itemBuilder: (context, index) {
              final p = items[index];
              return _providerGroupItem(
                KeyedSubtree(
                  key: ValueKey(p.keyName),
                  child: _SettleAnim(
                    active: settlingKeys.contains(p.keyName),
                    child: _ProviderRow(
                      provider: p,
                      index: index,
                      selectMode: selectMode,
                      reorderEnabled: reorderEnabled,
                      selected: selectedKeys.contains(p.keyName),
                      onToggleSelect: onToggleSelect,
                      showDivider: index != items.length - 1,
                    ),
                  ),
                ),
                index,
                items.length,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupedProvidersList extends StatelessWidget {
  const _GroupedProvidersList({
    required this.header,
    required this.rows,
    required this.onReorder,
    required this.onReorderStart,
    required this.onReorderEnd,
    required this.settlingKeys,
    required this.selectMode,
    required this.searchActive,
    required this.freezeContainerHeight,
    required this.persistedIsGroupCollapsed,
    required this.reorderEnabled,
    required this.selectedKeys,
    required this.onToggleSelect,
  });

  final List<_ProviderGroupingRowVM> rows;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onReorderStart;
  final void Function(int index) onReorderEnd;
  final Set<String> settlingKeys;
  final bool selectMode;
  final bool searchActive;
  final bool freezeContainerHeight;
  final bool Function(String groupKey) persistedIsGroupCollapsed;
  final bool reorderEnabled;
  final Set<String> selectedKeys;
  final void Function(String key) onToggleSelect;

  final Widget header;

  @override
  Widget build(BuildContext context) {
    final collapsedByGroupKey = <String, bool>{
      for (final row in rows)
        if (row is _ProviderGroupingHeaderVM) row.groupKey: row.collapsed,
    };
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: AppScaffold.scrollContentTop(context)),
          sliver: SliverToBoxAdapter(child: header),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            AppScaffold.scrollContentBottom(
              context,
              spacing: selectMode
                  ? 100
                  : AppScaffold.defaultScrollContentBottomSpacing,
            ),
          ),
          sliver: SliverReorderableList(
            itemCount: rows.length,
            onReorderItem: reorderEnabled ? onReorder : (_, __) {},
            onReorderStart: reorderEnabled ? onReorderStart : null,
            onReorderEnd: reorderEnabled ? onReorderEnd : null,
            proxyDecorator: (child, index, animation) => Opacity(
              opacity: 0.95,
              child: Transform.scale(scale: 0.98, child: child),
            ),
            itemBuilder: (context, index) {
              final row = rows[index];
              if (row is _ProviderGroupingHeaderVM) {
                Widget header = _ProviderGroupHeaderRow(
                  groupKey: row.groupKey,
                  title: row.title,
                  count: row.count,
                  collapsed: row.collapsed,
                  canToggleCollapse: !searchActive,
                );
                if (reorderEnabled) {
                  header = ReorderableDelayedDragStartListener(
                    index: index,
                    child: header,
                  );
                }
                return _providerGroupItem(
                  KeyedSubtree(
                    key: ValueKey('provider-group-header-${row.groupKey}'),
                    child: header,
                  ),
                  index,
                  rows.length,
                );
              }
              if (row is _ProviderGroupingProviderVM) {
                final p = row.provider;
                final collapsed = collapsedByGroupKey[row.groupKey] ?? false;
                final next = (index + 1 < rows.length) ? rows[index + 1] : null;
                final showDivider =
                    !collapsed &&
                    next is _ProviderGroupingProviderVM &&
                    next.groupKey == row.groupKey;
                return _providerGroupItem(
                  KeyedSubtree(
                    key: ValueKey(p.keyName),
                    child: _SettleAnim(
                      active: settlingKeys.contains(p.keyName),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child: collapsed
                            ? const SizedBox.shrink()
                            : _ProviderRow(
                                provider: p,
                                index: index,
                                selectMode: selectMode,
                                reorderEnabled: reorderEnabled,
                                selected: selectedKeys.contains(p.keyName),
                                onToggleSelect: onToggleSelect,
                                showDivider: showDivider,
                              ),
                      ),
                    ),
                  ),
                  index,
                  rows.length,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }
}

class _ProvidersSearchField extends StatelessWidget {
  const _ProvidersSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final hasText = controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: AppTextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 14,
        ),
        cursorColor: cs.primary,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.5),
            fontSize: 13.5,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          prefixIcon: Icon(
            Lucide.Search,
            size: 16,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: hasText
              ? IconButton(
                  onPressed: onClear,
                  icon: Icon(
                    Lucide.X,
                    size: 14,
                    color: cs.onSurface.withValues(alpha: 0.48),
                  ),
                  tooltip: hintText,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFEBEBEB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _ProviderGroupHeaderRow extends StatelessWidget {
  const _ProviderGroupHeaderRow({
    required this.groupKey,
    required this.title,
    required this.count,
    required this.collapsed,
    required this.canToggleCollapse,
  });

  final String groupKey;
  final String title;
  final int count;
  final bool collapsed;
  final bool canToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final pillBg = cs.primary.withValues(alpha: 0.12);
    final pillFg = cs.primary;

    return AppListTile(
      leading: AnimatedRotation(
        turns: collapsed ? 0.0 : 0.25,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: Icon(
          Lucide.ChevronRight,
          size: 16,
          color: AppColors.secondaryLabel(brightness),
        ),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.secondaryLabel(brightness),
          fontWeight: AppFontWeights.semibold,
        ),
      ),
      trailing: _Pill(text: '$count', bg: pillBg, fg: pillFg),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minLeadingWidth: 16,
      horizontalTitleGap: 6,
      minVerticalPadding: 6,
      onTap: canToggleCollapse
          ? () => unawaited(
              context.read<SettingsProvider>().toggleGroupCollapsed(groupKey),
            )
          : null,
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.index,
    required this.selectMode,
    required this.reorderEnabled,
    required this.selected,
    required this.onToggleSelect,
    required this.showDivider,
  });
  final _Provider provider;
  final int index;
  final bool selectMode;
  final bool reorderEnabled;
  final bool selected;
  final void Function(String key) onToggleSelect;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final cfg = settings.getProviderConfig(
      provider.keyName,
      defaultName: provider.name,
    );
    final enabled = cfg.enabled;
    final l10n = AppLocalizations.of(context)!;

    final statusBg = enabled
        ? Colors.green.withValues(alpha: 0.12)
        : Colors.orange.withValues(alpha: 0.15);
    final statusFg = enabled ? Colors.green : Colors.orange;

    return Column(
      children: [
        AppListTile(
          onTapFeedback: selectMode ? Haptics.light : null,
          onTap: () {
            if (selectMode) {
              onToggleSelect(provider.keyName);
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProviderDetailPage(
                    keyName: provider.keyName,
                    displayName: provider.name,
                  ),
                ),
              );
            }
          },
          leading: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: selectMode ? 28 : 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: selectMode ? 1 : 0,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IosCheckbox(
                        value: selected,
                        size: 20,
                        hitTestSize: 22,
                        borderWidth: 1.6,
                        activeColor: cs.primary,
                        borderColor: cs.onSurface.withValues(alpha: 0.35),
                        onChanged: (_) => onToggleSelect(provider.keyName),
                      ),
                    ),
                  ),
                ),
                if (selectMode) const SizedBox(width: 4),
                SizedBox(
                  width: 36,
                  child: Center(
                    child: ProviderAvatar(
                      providerKey: provider.keyName,
                      displayName: cfg.name.isNotEmpty
                          ? cfg.name
                          : provider.keyName,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            cfg.name.isNotEmpty ? cfg.name : provider.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: selected ? cs.primary : cs.onSurface,
              fontWeight: FontWeight.w400,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  enabled
                      ? l10n.providersPageEnabledStatus
                      : l10n.providersPageDisabledStatus,
                  style: TextStyle(fontSize: 11, color: statusFg),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: anim, child: child),
                ),
                child: selectMode
                    ? const SizedBox.shrink(key: ValueKey('none'))
                    : Icon(
                        Lucide.ChevronRight,
                        size: 16,
                        color: cs.onSurfaceVariant,
                        key: const ValueKey('chev'),
                      ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          minLeadingWidth: 36,
          horizontalTitleGap: 12,
          minVerticalPadding: 11,
          selected: selected,
        ),
        if (showDivider) _iosDivider(context),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.visible,
    required this.count,
    required this.total,
    required this.onExport,
    required this.onDelete,
    required this.onMoveToGroup,
    required this.onSelectAll,
  });
  final bool visible;
  final int count;
  final int total;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onMoveToGroup;
  final VoidCallback onSelectAll;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !visible,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 46),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GlassCircleButton(
                      icon: Lucide.Trash2,
                      color: const Color(0xFFFF3B30),
                      semanticLabel: l10n.providersPageDeleteAction,
                      onTap: onDelete,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.checkCheck,
                      color: cs.primary,
                      semanticLabel: null,
                      onTap: onSelectAll,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.Folder,
                      color: cs.primary,
                      semanticLabel: l10n.providerGroupsPickerTitle,
                      onTap: onMoveToGroup,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.Share2,
                      color: cs.primary,
                      semanticLabel: l10n.providersPageExportAction,
                      onTap: onExport,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCircleButton extends StatefulWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.semanticLabel,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  State<_GlassCircleButton> createState() => _GlassCircleButtonState();
}

class _GlassCircleButtonState extends State<_GlassCircleButton> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassBase = isDark
        ? Colors.black.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.06);
    final overlay = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final tileColor = _pressed
        ? Color.alphaBlend(overlay, glassBase)
        : glassBase;
    final borderColor = cs.outlineVariant.withValues(alpha: 0.10);

    final child = SizedBox(
      width: 46,
      height: 46,
      child: Center(child: Icon(widget.icon, size: 18, color: widget.color)),
    );

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          Haptics.light();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: Container(
                decoration: BoxDecoration(
                  color: tileColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showMultiExportSheet(
  BuildContext context,
  List<String> keys,
) async {
  final cs = Theme.of(context).colorScheme;
  final settings = context.read<SettingsProvider>();
  final l10n = AppLocalizations.of(context)!;
  final entries = [
    for (final k in keys)
      () {
        final cfg =
            settings.providerConfigs[k] ?? settings.getProviderConfig(k);
        final name = (cfg.name.isNotEmpty ? cfg.name : k);
        final code = encodeProviderConfig(cfg);
        return {'name': name, 'code': code};
      }(),
  ];
  final text = entries.map((e) => e['code']).join('\n');
  await showAppPopupSheet<void>(
    context: context,
    title: AppLocalizations.of(context)!.providersPageExportSelectedTitle(
      keys.length,
    ),
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bool showQr = keys.length <= 4;
      Rect shareAnchorRect(BuildContext bctx) {
        try {
          final ro = bctx.findRenderObject();
          if (ro is RenderBox &&
              ro.hasSize &&
              ro.size.width > 0 &&
              ro.size.height > 0) {
            final origin = ro.localToGlobal(Offset.zero);
            return origin & ro.size;
          }
        } catch (_) {}
        final size = MediaQuery.of(bctx).size;
        return Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: 1,
          height: 1,
        );
      }

      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            10,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Show QR only when selection is small to avoid overlong input
              if (showQr) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: SizedBox.square(
                      dimension: 180,
                      child: PrettyQrView.data(
                        data: text,
                        errorCorrectLevel: QrErrorCorrectLevel.M,
                        decoration: const PrettyQrDecoration(
                          shape: PrettyQrSmoothSymbol(roundFactor: 1),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Limited preview of codes (6-7 lines), full content still copied/shared
              SizedBox(
                height: 128,
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    maxLines: 7,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.Copy,
                      label: l10n.providersPageExportCopyButton,
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: text));
                        showAppSnackBar(
                          context,
                          message: l10n.providersPageExportCopiedSnackbar,
                          type: NotificationType.success,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: IosTileButton(
                      icon: Lucide.Share2,
                      label: l10n.providersPageExportShareButton,
                      onTap: () async {
                        final rect = shareAnchorRect(ctx);
                        await SharePlus.instance.share(
                          ShareParams(
                            text: text,
                            subject: l10n.providersPageExportSelectedTitle(
                              keys.length,
                            ),
                            sharePositionOrigin: rect,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

// Drag handle removed per design; dragging is triggered by long-pressing the card.

// Replaced custom reorder grid with reorderable_grid_view for
// smoother, battle-tested drag animations and reordering.

class _SettleAnim extends StatelessWidget {
  const _SettleAnim({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tween = Tween<double>(begin: active ? 0.94 : 1.0, end: 1.0);
    return TweenAnimationBuilder<double>(
      tween: tween,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, scale, _) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: 1.0,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11)),
    );
  }
}

class _Provider {
  final String name;
  final String keyName;
  final bool enabled;
  final int modelCount;
  _Provider({
    required this.name,
    required this.keyName,
    required this.enabled,
    required this.modelCount,
  });
}

// Row tactile wrapper for iOS-style lists: no ripple, optional haptics, color-only press feedback
class _TactileRow extends StatefulWidget {
  const _TactileRow({
    required this.builder,
    this.onTap,
    this.pressedScale = 1.00,
  });
  final Widget Function(bool pressed) builder;
  final VoidCallback? onTap;
  final double pressedScale;
  @override
  State<_TactileRow> createState() => _TactileRowState();
}

class _TactileRowState extends State<_TactileRow> {
  bool _pressed = false;
  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (context.read<SettingsProvider>().hapticsOnListItemTap) {
                Haptics.soft();
              }
              widget.onTap!.call();
            },
      child: widget.builder(_pressed),
    );
  }
}

class _AnimatedPressColor extends StatelessWidget {
  const _AnimatedPressColor({
    required this.pressed,
    required this.base,
    required this.builder,
  });
  final bool pressed;
  final Color base;
  final Widget Function(Color color) builder;
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final target = pressed
        ? (Color.lerp(base, isDark ? Colors.black : Colors.white, 0.55) ?? base)
        : base;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, color, _) => builder(color ?? base),
    );
  }
}

Widget _iosDivider(BuildContext context) {
  return const AppListDivider(indent: 60, endIndent: 12);
}
