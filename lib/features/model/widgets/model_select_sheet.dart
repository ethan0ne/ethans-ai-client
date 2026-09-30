import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/model_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/chat/chat_service.dart';
import '../../../icons/lucide_adapter.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'model_detail_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/provider_grouping_logic.dart';
import '../../../shared/widgets/frosted_popup_menu.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/popup_content_frame.dart';
import '../../../shared/widgets/model_tag_wrap.dart';
import '../../provider/widgets/provider_avatar.dart';
import '../../provider/widgets/provider_balance_badge.dart';
import '../../../core/services/model_override_resolver.dart';
import '../../../core/services/api/client_backend_session.dart';
import '../../../theme/app_font_weights.dart';

class ModelSelection {
  final String providerKey;
  final String modelId;
  ModelSelection(this.providerKey, this.modelId);
}

const double _modelPickerPillHeight = 32;

// Prevent re-entrant model selector dialogs
bool _modelSelectorOpen = false;

/// Stale-while-revalidate cache shared by the mobile and desktop model
/// pickers below. Each sheet open used to start from an empty list and show
/// a spinner until the (network + isolate) reload finished, even though the
/// previous open had already computed the exact same groups a moment ago —
/// this keeps the last successful result in memory so a reopen renders it
/// immediately while `_loadModelsAsync`/`_loadModels` refreshes in the
/// background. Intentionally process-lifetime only (no disk persistence):
/// it's just smoothing over the picker's own repeat opens, not a source of
/// truth.
class _ModelSelectCache {
  static Map<String, _ProviderGroup>? groups;
  static List<String>? orderedKeys;
}

// Data class for compute function
class _ModelProcessingData {
  final Map<String, dynamic> providerConfigs;
  final Set<String> pinnedModels;
  final String currentModelKey;
  final List<String> providersOrder;
  final String? limitProviderKey;
  final bool disableResolverPlatformLogging;

  _ModelProcessingData({
    required this.providerConfigs,
    required this.pinnedModels,
    required this.currentModelKey,
    required this.providersOrder,
    this.limitProviderKey,
    required this.disableResolverPlatformLogging,
  });
}

class _ModelProcessingResult {
  final Map<String, _ProviderGroup> groups;
  final List<_ModelItem> favItems;
  final List<String> orderedKeys;

  _ModelProcessingResult({
    required this.groups,
    required this.favItems,
    required this.orderedKeys,
  });
}

// Lightweight brand asset resolver usable in isolates
String? _assetForNameStatic(String n) {
  return BrandAssets.assetForName(n);
}

List<String> _buildDisplayProvidersOrder(
  SettingsProvider settings,
  Iterable<String> providerKeys,
) {
  final knownKeys = providerKeys.where((e) => e.trim().isNotEmpty);
  final providerGroupMap = <String, String>{};
  for (final key in knownKeys) {
    final groupId = settings.groupIdForProvider(key);
    if (groupId != null) providerGroupMap[key] = groupId;
  }
  return buildProviderKeysInGroupedDisplayOrder(
    providersOrder: settings.providersOrder,
    groups: settings.providerGroups,
    ungroupedIndex: settings.providerUngroupedDisplayIndex,
    providerGroupMap: providerGroupMap,
    knownProviderKeys: providerKeys,
  );
}

// Static function for compute - must be top-level
_ModelProcessingResult _processModelsInBackground(_ModelProcessingData data) {
  if (data.disableResolverPlatformLogging) {
    ModelOverrideResolver.setPlatformLoggingEnabled(false);
    ModelOverrideResolver.setUnknownValueLoggingEnabled(false);
  }
  final providers = data.limitProviderKey == null
      ? data.providerConfigs
      : {
          if (data.providerConfigs.containsKey(data.limitProviderKey))
            data.limitProviderKey!:
                data.providerConfigs[data.limitProviderKey]!,
        };

  // Build data map: providerKey -> (displayName, models)
  final Map<String, _ProviderGroup> groups = {};

  providers.forEach((key, cfg) {
    // Skip disabled providers entirely so they can't be selected
    if (!(cfg['enabled'] as bool)) return;
    final models = cfg['models'] as List<dynamic>? ?? [];
    if (models.isEmpty) return;

    final name = (cfg['name'] as String?) ?? '';
    final overrides =
        (cfg['overrides'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
        const <String, dynamic>{};
    final list = <_ModelItem>[
      for (final id in models)
        () {
          final String mid = id.toString();
          final rawOv = overrides[mid];
          final Map<String, dynamic>? ov = rawOv is Map
              ? {for (final e in rawOv.entries) e.key.toString(): e.value}
              : null;
          // Use upstream/api model id for inference when available so that
          // brand assets and default capabilities stay accurate even when the
          // logical key is a custom alias.
          String baseId = mid;
          if (ov != null) {
            final raw = (ov['apiModelId'] ?? ov['api_model_id'])
                ?.toString()
                .trim();
            if (raw != null && raw.isNotEmpty) baseId = raw;
          }
          ModelInfo base = ModelRegistry.infer(
            ModelInfo(id: baseId, displayName: baseId),
          );
          if (ov != null) {
            base = ModelOverrideResolver.applyModelOverride(
              base,
              ov,
              applyDisplayName: true,
            );
          }
          return _ModelItem(
            providerKey: key,
            providerName: name.isNotEmpty ? name : key,
            id: mid,
            info: base,
            pinned: data.pinnedModels.contains('$key::$mid'),
            selected: data.currentModelKey == '$key::$mid',
            asset: _assetForNameStatic(baseId),
          );
        }(),
    ];
    groups[key] = _ProviderGroup(
      name: name.isNotEmpty ? name : key,
      items: list,
    );
  });

  // Build favorites group (duplicate items)
  final favItems = <_ModelItem>[];
  for (final k in data.pinnedModels) {
    final parts = k.split('::');
    if (parts.length < 2) continue;
    final pk = parts[0];
    final mid = parts.sublist(1).join('::');
    final g = groups[pk];
    if (g == null) continue;
    final found = g.items.firstWhere(
      (e) => e.id == mid,
      orElse: () => _ModelItem(
        providerKey: pk,
        providerName: g.name,
        id: mid,
        info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
        pinned: true,
        selected: data.currentModelKey == '$pk::$mid',
      ),
    );
    favItems.add(found.copyWith(pinned: true));
  }

  // Provider sections ordered by ProvidersPage order
  final orderedKeys = <String>[];
  for (final k in data.providersOrder) {
    if (groups.containsKey(k)) orderedKeys.add(k);
  }
  for (final k in groups.keys) {
    if (!orderedKeys.contains(k)) orderedKeys.add(k);
  }

  return _ModelProcessingResult(
    groups: groups,
    favItems: favItems,
    orderedKeys: orderedKeys,
  );
}

Future<ModelSelection?> showModelSelector(
  BuildContext context, {
  String? limitProviderKey,
  String? initialProviderKey,
  String? initialModelId,
  bool usePopupContentFrame = false,
}) async {
  if (_modelSelectorOpen) return null;
  _modelSelectorOpen = true;
  try {
    // Desktop platforms use a custom dialog.
    final platform = defaultTargetPlatform;
    if (platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux) {
      return await _showDesktopModelSelector(
        context,
        limitProviderKey: limitProviderKey,
        initialProviderKey: initialProviderKey,
        initialModelId: initialModelId,
      );
    }
    if (usePopupContentFrame) {
      return await showPopupContentFrame<ModelSelection>(
        context,
        maxWidth: 620,
        maxHeight: 700,
        largeSheet: true,
        builder: (ctx, isDialog) => _ModelSelectSheet(
          limitProviderKey: limitProviderKey,
          initialProviderKey: initialProviderKey,
          initialModelId: initialModelId,
          usePopupContentFrame: true,
          isDialog: isDialog,
        ),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return await showModalBottomSheet<ModelSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ModelSelectSheet(
        limitProviderKey: limitProviderKey,
        initialProviderKey: initialProviderKey,
        initialModelId: initialModelId,
      ),
    );
  } finally {
    _modelSelectorOpen = false;
  }
}

/// Opens the model picker for the current conversation.
///
/// The selection is scoped to [conversationId] only — it never overwrites
/// the assistant's own default model. If [conversationId] is omitted, the
/// picker falls back to updating the global default model (used by the
/// settings pages).
Future<void> showModelSelectSheet(
  BuildContext context, {
  String? conversationId,
}) async {
  final chatService = context.read<ChatService>();
  final settings = context.read<SettingsProvider>();
  final assistantProvider = context.read<AssistantProvider>();
  final assistant = assistantProvider.currentAssistant;
  final current = conversationId != null
      ? chatService.getConversationChatModel(conversationId)
      : null;
  final sel = await showModelSelector(
    context,
    initialProviderKey:
        current?.$1 ??
        assistant?.chatModelProvider ??
        settings.currentModelProvider,
    initialModelId:
        current?.$2 ?? assistant?.chatModelId ?? settings.currentModelId,
    usePopupContentFrame: true,
  );
  if (sel != null) {
    if (conversationId != null) {
      await chatService.setConversationChatModel(
        conversationId,
        sel.providerKey,
        sel.modelId,
      );
    } else {
      // No conversation in scope (e.g. called from settings): update the
      // global default model.
      await settings.setCurrentModel(sel.providerKey, sel.modelId);
    }
  }
}

class _ModelSelectSheet extends StatefulWidget {
  const _ModelSelectSheet({
    this.limitProviderKey,
    this.initialProviderKey,
    this.initialModelId,
    this.usePopupContentFrame = false,
    this.isDialog = false,
  });
  final String? limitProviderKey;
  final String? initialProviderKey;
  final String? initialModelId;
  final bool usePopupContentFrame;
  final bool isDialog;
  @override
  State<_ModelSelectSheet> createState() => _ModelSelectSheetState();
}

class _ModelSelectSheetState extends State<_ModelSelectSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  final DraggableScrollableController _sheetCtrl =
      DraggableScrollableController();
  late final AnimationController _providerLabelController;
  final ScrollController _modelFamilyScrollController = ScrollController();
  final ScrollController _providerTabsController = ScrollController();
  final GlobalKey _providerTabsViewportKey = GlobalKey(
    debugLabel: 'model-selector-provider-tabs-viewport',
  );
  final GlobalKey _providerDropdownKey = GlobalKey(
    debugLabel: 'model-selector-provider-dropdown',
  );
  final Map<String, GlobalKey> _providerTabKeys = <String, GlobalKey>{};
  static const double _initialSize = 0.8;
  static const double _maxSize = 0.8;
  static const double _stickyProviderHeaderHeight = 30;
  static const double _estimatedHeaderExtent = 39;
  static const double _estimatedModelExtent = 79;
  static const double _listBottomPadding = 12;
  static const double _popupSearchReservedExtent = 84;
  static const double _providerCollapseScrollOffset = 12;
  static const double _providerExpandScrollOffset = 2;
  // static const double _currentSelectionScrollMargin = 10;
  String _lastQuery = '';
  bool _isModelFamilyScrolledAwayFromStart = false;
  String? _selectedProviderKey;
  bool _didManuallySelectProvider = false;
  bool _showFavoritesOnly = false;
  String? _selectedModelFamilyKey;
  String? _activeProviderKey;
  int _stickySwitchDirection = 1;
  bool _activeProviderUpdateScheduled = false;
  double _listViewportHeight = 0;
  double _listTopPadding = 0;
  // ScrollablePositionedList controllers
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  // Flattened rows + index maps for precise jumps
  final List<_ListRow> _rows = <_ListRow>[];
  final Map<String, int> _headerIndexMap =
      <String, int>{}; // providerKey or '__fav__' -> index
  final Map<String, int> _modelIndexMap =
      <String, int>{}; // 'pk::modelId' in provider sections -> index
  final Map<String, int> _favModelIndexMap =
      <String, int>{}; // 'pk::modelId' in favorites -> index

  // Async loading state — seeded from the cross-open cache (see
  // _ModelSelectCache) so a reopen shows the last known list immediately
  // instead of a blank spinner while the background refresh below runs.
  bool _isLoading = _ModelSelectCache.groups == null;
  Map<String, _ProviderGroup> _groups = _ModelSelectCache.groups ?? {};
  List<String> _orderedKeys = _ModelSelectCache.orderedKeys ?? [];
  bool _autoScrolled = false; // ensure we only auto-scroll once per open

  dynamic _sanitizeJsonValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _sanitizeJsonValue(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _sanitizeJsonValue(item)];
    }
    return value.toString();
  }

  Map<String, dynamic> _sanitizeOverrides(Map<String, dynamic> overrides) {
    return {
      for (final entry in overrides.entries)
        entry.key.toString(): _sanitizeJsonValue(entry.value),
    };
  }

  Map<String, dynamic> _buildProviderConfigsPayload(SettingsProvider settings) {
    final keys = <String>{
      ...settings.providersOrder.where((e) => e.trim().isNotEmpty),
      ...settings.providerConfigs.keys.where((e) => e.trim().isNotEmpty),
    };
    if (widget.limitProviderKey != null &&
        widget.limitProviderKey!.trim().isNotEmpty) {
      keys.add(widget.limitProviderKey!);
    }
    // [kelivo-hosted] kelivo-arch.md §8 — the hosted provider isn't in
    // `providerConfigs`/`providersOrder` (see getProviderConfig's special
    // case), so it has to be added to the candidate key set explicitly.
    // Gated on being signed in so a signed-out user doesn't see an empty,
    // disabled "Kelivo Hosted" group.
    if (ClientBackendSession.token != null) {
      keys.add(kHostedProviderKey);
    }
    final out = <String, dynamic>{};
    for (final key in keys) {
      final cfg = settings.getProviderConfig(key, defaultName: key);
      out[key] = {
        'enabled': cfg.enabled,
        'name': cfg.name,
        'models': cfg.models,
        'overrides': _sanitizeOverrides(cfg.modelOverrides),
      };
    }
    return out;
  }

  String _currentModelKey(
    SettingsProvider settings,
    AssistantProvider assistantProvider,
  ) {
    final hasInitial =
        widget.initialProviderKey != null && widget.initialModelId != null;
    final provider = hasInitial
        ? widget.initialProviderKey
        : assistantProvider.currentAssistant?.chatModelProvider ??
              settings.currentModelProvider;
    final modelId = hasInitial
        ? widget.initialModelId
        : assistantProvider.currentAssistant?.chatModelId ??
              settings.currentModelId;
    return (provider != null && modelId != null) ? '$provider::$modelId' : '';
  }

  String? _preferredProviderKeyFor(
    Map<String, _ProviderGroup> groups,
    List<String> orderedKeys,
  ) {
    final initialProvider = widget.initialProviderKey;
    if (initialProvider != null && groups.containsKey(initialProvider)) {
      return initialProvider;
    }
    for (final key in orderedKeys) {
      final group = groups[key];
      if (group != null && group.items.any((item) => item.selected)) {
        return key;
      }
    }
    for (final key in orderedKeys) {
      if (groups.containsKey(key)) return key;
    }
    return null;
  }

  String? get _effectiveSelectedProviderKey {
    final selected = _selectedProviderKey;
    if (selected != null && _groups.containsKey(selected)) return selected;
    return _preferredProviderKeyFor(_groups, _orderedKeys);
  }

  void _updateSelectedProviderAfterLoad(
    Map<String, _ProviderGroup> groups,
    List<String> orderedKeys,
  ) {
    final selected = _selectedProviderKey;
    if (_didManuallySelectProvider &&
        selected != null &&
        groups.containsKey(selected)) {
      return;
    }
    _selectedProviderKey = _preferredProviderKeyFor(groups, orderedKeys);
  }

  @override
  void initState() {
    super.initState();
    _providerLabelController = AnimationController(
      vsync: this,
      value: 1,
      upperBound: 1.08,
    );
    _itemPositionsListener.itemPositions.addListener(
      _scheduleActiveProviderUpdate,
    );
    // Delay loading to allow the sheet to open first
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        _loadModelsAsync();
      }
    });
    // If the cache already seeded _groups (see _ModelSelectCache), the first
    // build renders the real list immediately — don't wait for the reload
    // above to finish before scrolling to the current selection, or the
    // list sits still for a beat after it's already visible.
    // _jumpToCurrentSelection() is a no-op (and leaves _autoScrolled false)
    // when the rows/index maps aren't populated yet, so this is harmless on
    // a cold, cache-less open too: the reload's own call further down takes
    // over in that case.
    _scheduleAutoScrollToCurrent();
  }

  Future<void> _loadModelsAsync() async {
    try {
      // [kelivo-hosted] kelivo-arch.md §8 — refresh the hosted catalog
      // before snapshotting it into the payload below; there's no push
      // notification for catalog changes, so each sheet open re-fetches.
      if (ClientBackendSession.token != null) {
        await ClientBackendSession.refresh();
        if (!mounted) return;
      }
      final settings = context.read<SettingsProvider>();
      final assistantProvider = context.read<AssistantProvider>();
      final providerConfigs = _buildProviderConfigsPayload(settings);

      final currentKey = _currentModelKey(settings, assistantProvider);

      // Prepare data for background processing
      final processingData = _ModelProcessingData(
        providerConfigs: providerConfigs,
        pinnedModels: settings.pinnedModels,
        currentModelKey: currentKey,
        providersOrder: _buildDisplayProvidersOrder(
          settings,
          providerConfigs.keys,
        ),
        limitProviderKey: widget.limitProviderKey,
        disableResolverPlatformLogging: true,
      );

      // Process in background isolate
      final result = await compute(_processModelsInBackground, processingData);

      if (mounted) {
        setState(() {
          _groups = result.groups;
          _orderedKeys = result.orderedKeys;
          _updateSelectedProviderAfterLoad(result.groups, result.orderedKeys);
          _isLoading = false;
          _activeProviderKey = null;
        });
        _ModelSelectCache.groups = result.groups;
        _ModelSelectCache.orderedKeys = result.orderedKeys;
        _scheduleAutoScrollToCurrent();
      }
    } catch (e) {
      // If compute fails (e.g., on web), fall back to synchronous processing
      if (mounted) {
        _loadModelsSynchronously();
      }
    }
  }

  Future<void> _expandSheetIfNeeded(
    double target, {
    Duration duration = const Duration(milliseconds: 300),
  }) async {
    if (widget.usePopupContentFrame) return;
    // Safely attempt to read size and animate; ignore if controller not yet attached
    try {
      final current = _sheetCtrl.size;
      if (current < target) {
        await _sheetCtrl.animateTo(
          target,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
        // allow a brief settle time after expansion
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {}
  }

  void _loadModelsSynchronously() {
    final settings = context.read<SettingsProvider>();
    final assistantProvider = context.read<AssistantProvider>();
    final providerConfigs = _buildProviderConfigsPayload(settings);

    final currentKey = _currentModelKey(settings, assistantProvider);

    final processingData = _ModelProcessingData(
      providerConfigs: providerConfigs,
      pinnedModels: settings.pinnedModels,
      currentModelKey: currentKey,
      providersOrder: _buildDisplayProvidersOrder(
        settings,
        providerConfigs.keys,
      ),
      limitProviderKey: widget.limitProviderKey,
      disableResolverPlatformLogging: false,
    );

    final result = _processModelsInBackground(processingData);

    setState(() {
      _groups = result.groups;
      _orderedKeys = result.orderedKeys;
      _updateSelectedProviderAfterLoad(result.groups, result.orderedKeys);
      _isLoading = false;
      _activeProviderKey = null;
    });
    _scheduleAutoScrollToCurrent();
  }

  void _scheduleAutoScrollToCurrent() {
    if (_autoScrolled) return;
    // Wait until the content has been laid out and offsets computed in _buildContent
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _autoScrolled) return;
      await _jumpToCurrentSelection();
    });
  }

  Future<void> _jumpToCurrentSelection() async {
    // If user has entered a search query, decouple from previous selection
    // and jump to the first matching provider group instead.
    final currentQuery = _search.text.trim();
    if (currentQuery.isNotEmpty) {
      await _scrollToFirstSearchGroup(initial: true);
      return;
    }

    // Optionally expand a bit for better context
    await _expandSheetIfNeeded(
      _initialSize.clamp(0.0, _maxSize),
      duration: const Duration(milliseconds: 200),
    );

    // Ensure the list is attached before attempting to scroll
    if (!_itemScrollController.isAttached) {
      // Try again shortly after the list attaches
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && !_autoScrolled) {
          _jumpToCurrentSelection();
        }
      });
      return;
    }

    final targetIndex = _currentSelectionTargetIndex();

    if (targetIndex != null) {
      final alignment = _currentSelectionScrollAlignment(targetIndex);
      try {
        await _itemScrollController.scrollTo(
          index: targetIndex,
          alignment: alignment,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
        _autoScrolled = true;
      } catch (_) {
        // If scroll fails for any reason, try again once.
        Future.delayed(const Duration(milliseconds: 80), () async {
          if (!mounted || _autoScrolled) return;
          try {
            await _itemScrollController.scrollTo(
              index: targetIndex,
              alignment: alignment,
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
            );
            _autoScrolled = true;
          } catch (_) {}
        });
      }
    }
  }

  int? _currentSelectionTargetIndex() {
    if (_search.text.trim().isNotEmpty) return null;

    final settings = context.read<SettingsProvider>();

    final currentKey = _currentModelKey(
      settings,
      context.read<AssistantProvider>(),
    );
    if (currentKey.isEmpty) return null;

    if (widget.limitProviderKey == null &&
        settings.pinnedModels.contains(currentKey)) {
      final favIndex = _favModelIndexMap[currentKey];
      if (favIndex != null) return favIndex;
    }

    final separator = currentKey.indexOf('::');
    final pk = separator == -1
        ? currentKey
        : currentKey.substring(0, separator);
    return _modelIndexMap[currentKey] ?? _headerIndexMap[pk];
  }

  double _currentSelectionScrollAlignment(int targetIndex) {
    if (_listViewportHeight <= 0) {
      return 0;
    }
    final topAlignment = widget.usePopupContentFrame
        ? _listTopAlignment()
        : widget.limitProviderKey == null
        ? (_stickyProviderHeaderHeight / _listViewportHeight).clamp(0.0, 0.3)
        : 0.0;
    if (_rows.length <= 1) return topAlignment;

    final remainingExtent = _estimatedRemainingExtentFrom(targetIndex);
    final topAlignedRequiredExtent = _listViewportHeight * (1 - topAlignment);
    if (remainingExtent >= topAlignedRequiredExtent) return topAlignment;

    final tailAlignment = 1.0 - (remainingExtent / _listViewportHeight);
    return tailAlignment.clamp(topAlignment, 0.72);
  }

  double _listTopAlignment() {
    if (_listViewportHeight <= 0) return 0;
    return (_listTopPadding / _listViewportHeight).clamp(0.0, 0.8);
  }

  double _estimatedRemainingExtentFrom(int targetIndex) {
    var extent = widget.usePopupContentFrame
        ? _popupSearchReservedExtent
        : _listBottomPadding;
    for (var i = targetIndex; i < _rows.length; i++) {
      final row = _rows[i];
      extent += row is _HeaderRow
          ? _estimatedHeaderExtent
          : _estimatedModelExtent;
    }
    return extent;
  }

  // Scroll to the first matching provider group when searching.
  Future<void> _scrollToFirstSearchGroup({bool initial = false}) async {
    // Expand a bit for better context
    await _expandSheetIfNeeded(
      _initialSize.clamp(0.0, _maxSize),
      duration: const Duration(milliseconds: 200),
    );

    if (!_itemScrollController.isAttached) {
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted) {
          _scrollToFirstSearchGroup(initial: initial);
        }
      });
      return;
    }

    int? targetIndex;
    // Prefer favorites section when it exists in current filtered rows
    targetIndex = _headerIndexMap['__fav__'];
    // Otherwise, use the first provider section (per ordered keys) that exists in current rows
    if (targetIndex == null) {
      for (final pk in _orderedKeys) {
        final idx = _headerIndexMap[pk];
        if (idx != null) {
          targetIndex = idx;
          break;
        }
      }
    }

    if (targetIndex == null) return;

    try {
      await _itemScrollController.scrollTo(
        index: targetIndex,
        alignment: _listTopAlignment(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      if (initial) _autoScrolled = true;
    } catch (_) {}
  }

  @override
  void dispose() {
    _providerLabelController.dispose();
    _modelFamilyScrollController.dispose();
    _itemPositionsListener.itemPositions.removeListener(
      _scheduleActiveProviderUpdate,
    );
    _search.dispose();
    _sheetCtrl.dispose();
    _providerTabsController.dispose();
    super.dispose();
  }

  // Match model name/id only (avoid provider key causing false positives)
  bool _matchesSearch(String query, _ModelItem item, String providerName) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return item.id.toLowerCase().contains(q) ||
        item.info.displayName.toLowerCase().contains(q);
  }

  // Check if a provider should be shown based on search query (match display name only)
  bool _providerMatchesSearch(String query, String providerName) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    final lowerProviderName = providerName.toLowerCase();
    return lowerProviderName.contains(lowerQuery);
  }

  GlobalKey _providerTabKeyFor(String providerKey) {
    return _providerTabKeys.putIfAbsent(
      providerKey,
      () => GlobalKey(debugLabel: 'model-selector-provider-tab-$providerKey'),
    );
  }

  String? _providerKeyForRow(int index) {
    if (index < 0 || index >= _rows.length) return null;
    final row = _rows[index];
    if (row is _HeaderRow) return row.providerKey;
    if (row is _ModelRow && !row.showProviderLabel) return row.item.providerKey;
    return null;
  }

  String? _activeProviderKeyFromVisibleRows() {
    final positions =
        _itemPositionsListener.itemPositions.value
            .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (positions.isEmpty || _rows.isEmpty) return null;

    final topIndex = positions.first.index;
    final directKey = _providerKeyForRow(topIndex);
    if (directKey != null) return directKey;

    for (var i = topIndex - 1; i >= 0; i--) {
      final key = _providerKeyForRow(i);
      if (key != null) return key;
    }
    return null;
  }

  void _scheduleActiveProviderUpdate() {
    if (!mounted || _activeProviderUpdateScheduled) return;
    _activeProviderUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeProviderUpdateScheduled = false;
      if (mounted) _syncActiveProviderFromVisibleRows();
    });
  }

  void _syncActiveProviderFromVisibleRows() {
    if (widget.usePopupContentFrame ||
        widget.limitProviderKey != null ||
        _rows.isEmpty) {
      return;
    }
    final nextKey = _activeProviderKeyFromVisibleRows();
    if (nextKey == _activeProviderKey) return;
    final previousKey = _activeProviderKey;
    final previousIndex = previousKey == null
        ? -1
        : _orderedKeys.indexOf(previousKey);
    final nextIndex = nextKey == null ? -1 : _orderedKeys.indexOf(nextKey);
    setState(() {
      if (previousIndex != -1 && nextIndex != -1) {
        _stickySwitchDirection = nextIndex >= previousIndex ? 1 : -1;
      }
      _activeProviderKey = nextKey;
    });
    if (nextKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollProviderTabIntoView(nextKey);
      });
    }
  }

  void _scrollProviderTabIntoView(String providerKey) {
    final tabContext = _providerTabKeys[providerKey]?.currentContext;
    final viewportContext = _providerTabsViewportKey.currentContext;
    if (!mounted ||
        tabContext == null ||
        viewportContext == null ||
        !_providerTabsController.hasClients) {
      return;
    }

    final tabBox = tabContext.findRenderObject();
    final viewportBox = viewportContext.findRenderObject();
    if (tabBox is! RenderBox || viewportBox is! RenderBox) return;

    final tabLeft = tabBox.localToGlobal(Offset.zero).dx;
    final tabRight = tabLeft + tabBox.size.width;
    final viewportLeft = viewportBox.localToGlobal(Offset.zero).dx;
    final viewportRight = viewportLeft + viewportBox.size.width;

    var targetOffset = _providerTabsController.offset;
    if (tabLeft < viewportLeft) {
      targetOffset += tabLeft - viewportLeft;
    } else if (tabRight > viewportRight) {
      targetOffset += tabRight - viewportRight;
    } else {
      return;
    }

    targetOffset = targetOffset.clamp(
      _providerTabsController.position.minScrollExtent,
      _providerTabsController.position.maxScrollExtent,
    );
    unawaited(
      _providerTabsController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final showPickerHeaderExtension =
        widget.usePopupContentFrame &&
        !_isLoading &&
        widget.limitProviderKey == null &&
        _effectiveSelectedProviderKey != null;
    final Widget? pickerHeaderExtension = showPickerHeaderExtension
        ? _buildModelPickerHeaderExtension(context)
        : null;

    Widget buildBody() {
      return Column(
        children: [
          // Fixed header section with rounded corners
          Container(
            decoration: widget.usePopupContentFrame
                ? null
                : BoxDecoration(
                    color: cs.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
            child: Column(
              children: [
                // Header drag indicator
                if (!widget.usePopupContentFrame)
                  Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                // Fixed search field (iOS-like input style)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    enabled: !_isLoading,
                    onChanged: _handleSearchChanged,
                    // Ensure high-contrast input text in both themes
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                    ),
                    cursorColor: cs.primary,
                    decoration: InputDecoration(
                      hintText: l10n.modelSelectSheetSearchHint,
                      prefixIcon: Icon(
                        Lucide.Search,
                        size: 18,
                        color: cs.onSurface.withValues(
                          alpha: _isLoading ? 0.35 : 0.6,
                        ),
                      ),
                      // Use IconButton for reliable alignment at the far right
                      suffixIcon:
                          (widget.limitProviderKey == null &&
                              context
                                  .watch<SettingsProvider>()
                                  .pinnedModels
                                  .isNotEmpty)
                          ? ExcludeSemantics(
                              child: IconButton(
                                icon: Icon(
                                  Lucide.Bookmark,
                                  size: 18,
                                  color: cs.onSurface.withValues(
                                    alpha: _isLoading ? 0.35 : 0.7,
                                  ),
                                ),
                                onPressed: _isLoading ? null : _jumpToFavorites,
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                tooltip: l10n.modelSelectSheetFavoritesSection,
                              ),
                            )
                          : null,
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.64),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: cs.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Scrollable content
          Expanded(
            child: Container(
              color: cs.surface, // Ensure background color continuity
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(context),
            ),
          ),
          // Fixed bottom tabs
          Container(
            color: cs.surface, // Ensure background color continuity
            child: _buildBottomTabs(context),
          ),
        ],
      );
    }

    Widget buildPopupBody() {
      final contentTopPadding = PopupContentFrame.contentTopPadding(
        context,
        widget.isDialog,
        hasHeaderExtension: pickerHeaderExtension != null,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? Padding(
                          padding: EdgeInsets.only(top: contentTopPadding),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _buildContent(context),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildPopupBottomOverlay(context),
          ),
        ],
      );
    }

    if (widget.usePopupContentFrame) {
      return PopupContentFrame(
        title: l10n.chatInputBarSelectModelTooltip,
        isDialog: widget.isDialog,
        showCloseButton: true,
        headerExtension: pickerHeaderExtension,
        child: SafeArea(top: false, child: buildPopupBody()),
      );
    }

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          controller: _sheetCtrl,
          expand: false,
          initialChildSize: _initialSize,
          maxChildSize: _maxSize,
          minChildSize: 0.4,
          builder: (c, controller) => buildBody(),
        ),
      ),
    );
  }

  List<String> _availableModelFamilies() {
    final presentFamilies = <String>{};
    final providerKey = _effectiveSelectedProviderKey;
    final group = providerKey == null ? null : _groups[providerKey];
    for (final item in group?.items ?? const <_ModelItem>[]) {
      presentFamilies.add(_modelFamilyKeyFor(item));
    }
    return [
      for (final key in _modelFamilyOrder)
        if (presentFamilies.contains(key)) key,
    ];
  }

  Widget _buildModelPickerHeaderExtension(BuildContext context) {
    final maxProviderWidth = (MediaQuery.sizeOf(context).width * 0.42)
        .clamp(120.0, 220.0)
        .toDouble();
    final showProviderDropdown =
        _orderedKeys
            .where((key) => _groups[key]?.items.isNotEmpty ?? false)
            .toSet()
            .length >
        1;
    return SizedBox(
      height: PopupContentFrame.headerExtensionHeight,
      child: Row(
        children: [
          if (showProviderDropdown)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxProviderWidth),
                child: _buildProviderDropdown(context, maxProviderWidth),
              ),
            ),
          Expanded(
            child: _buildModelFamilyChips(
              context,
              leadingPadding: showProviderDropdown ? 0 : 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderDropdown(BuildContext context, double maxProviderWidth) {
    final providerKey = _effectiveSelectedProviderKey;
    final group = providerKey == null ? null : _groups[providerKey];
    if (providerKey == null || group == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final glassFill = isDark
        ? const Color(0xCC1C1C1E)
        : const Color(0xE0FFFFFF);
    final glassBorder = isDark
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);
    return _ModelPickerLiquidPressScale(
      enabled: !_isLoading,
      child: GestureDetector(
        key: _providerDropdownKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => _showProviderMenu(context),
        child: AnimatedBuilder(
          animation: _providerLabelController,
          child: ProviderAvatar(
            providerKey: providerKey,
            displayName: group.name,
            size: _modelPickerPillHeight,
          ),
          builder: (context, avatar) {
            final expanded = _providerLabelController.value
                .clamp(0.0, 1.0)
                .toDouble();
            final avatarSlotWidth =
                _modelPickerPillHeight -
                (_modelPickerPillHeight - 18) * expanded;
            final avatarSlotHeight = _modelPickerPillHeight - 12 * expanded;
            final pillShape = BoxDecoration(
              borderRadius: BorderRadius.circular(999),
            );
            return DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: glassBorder, width: 0.75),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: DecoratedBox(
                    decoration: pillShape.copyWith(color: glassFill),
                    child: SizedBox(
                      height: _modelPickerPillHeight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 11 * expanded,
                          vertical: 6 * expanded,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: avatarSlotWidth,
                              height: avatarSlotHeight,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: avatar,
                              ),
                            ),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxProviderWidth - 40,
                              ),
                              child: ClipRect(
                                child: SizeTransition(
                                  sizeFactor: _providerLabelController,
                                  axis: Axis.horizontal,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: AnimatedOpacity(
                                    opacity: _isModelFamilyScrolledAwayFromStart
                                        ? 0
                                        : 1,
                                    duration: const Duration(milliseconds: 120),
                                    curve: Curves.easeOut,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(width: 8),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: maxProviderWidth - 69,
                                          ),
                                          child: Text(
                                            group.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: AppFontWeights.medium,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          Lucide.ChevronDown,
                                          size: 15,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showProviderMenu(BuildContext context) {
    final anchorObject = _providerDropdownKey.currentContext
        ?.findRenderObject();
    if (anchorObject is! RenderBox) return;
    final globalAnchorRect = Rect.fromPoints(
      anchorObject.localToGlobal(Offset.zero),
      anchorObject.localToGlobal(anchorObject.size.bottomRight(Offset.zero)),
    );
    final l10n = AppLocalizations.of(context)!;
    final selectedProviderKey = _effectiveSelectedProviderKey;
    final items = <FrostedPopupMenuItem>[];
    for (final key in _orderedKeys) {
      final group = _groups[key];
      if (group == null) continue;
      items.add(
        FrostedPopupMenuItem(
          icon: key == selectedProviderKey
              ? Lucide.Check
              : Icons.circle_outlined,
          label: group.name,
          onPressed: () => _selectProvider(key),
        ),
      );
    }
    if (items.isEmpty) return;

    unawaited(
      showFrostedPopupMenuAt(
        context,
        globalAnchorRect: globalAnchorRect,
        title: l10n.modelSelectSheetProviderMenuTitle,
        items: items,
      ),
    );
  }

  Widget _buildModelFamilyChips(
    BuildContext context, {
    required double leadingPadding,
  }) {
    final familyKeys = _availableModelFamilies();
    final pinnedModelKeys = context.watch<SettingsProvider>().pinnedModels;
    final providerKey = _effectiveSelectedProviderKey;
    final providerGroup = providerKey == null ? null : _groups[providerKey];
    final hasProviderFavorites =
        providerGroup?.items.any(
          (item) => pinnedModelKeys.contains('$providerKey::${item.id}'),
        ) ??
        false;
    final l10n = AppLocalizations.of(context)!;
    if (!hasProviderFavorites && _showFavoritesOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_showFavoritesOnly) return;
        setState(() {
          _showFavoritesOnly = false;
          _selectedModelFamilyKey = null;
        });
        _scrollModelListToTop();
      });
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleModelFamilyMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleModelFamilyScrollNotification,
        child: SizedBox(
          height: PopupContentFrame.headerExtensionHeight,
          child: SingleChildScrollView(
            controller: _modelFamilyScrollController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsetsDirectional.fromSTEB(leadingPadding, 2, 12, 4),
            child: Row(
              children: [
                _ModelFamilyChip(
                  label: l10n.modelSelectSheetAllFamilies,
                  selected:
                      !_showFavoritesOnly && _selectedModelFamilyKey == null,
                  onTap: () => _selectModelFamily(null),
                ),
                if (hasProviderFavorites) ...[
                  const SizedBox(width: 8),
                  _ModelFamilyChip(
                    label: l10n.modelSelectSheetFavoriteFilter,
                    selected: _showFavoritesOnly,
                    onTap: _selectFavorites,
                  ),
                ],
                for (final familyKey in familyKeys) ...[
                  const SizedBox(width: 8),
                  _ModelFamilyChip(
                    label: _modelFamilyLabel(familyKey, l10n),
                    selected:
                        !_showFavoritesOnly &&
                        _selectedModelFamilyKey == familyKey,
                    onTap: () => _selectModelFamily(familyKey),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _handleModelFamilyScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollStartNotification ||
        notification is ScrollEndNotification ||
        notification is OverscrollNotification) {
      _syncProviderPillToModelFamilyScroll(notification.metrics);
    }
    return false;
  }

  bool _handleModelFamilyMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    if (notification.depth != 0) return false;
    _syncProviderPillToModelFamilyScroll(notification.metrics);
    return false;
  }

  void _syncProviderPillToModelFamilyScroll(ScrollMetrics metrics) {
    final offsetFromStart = metrics.pixels - metrics.minScrollExtent;
    final threshold = _isModelFamilyScrolledAwayFromStart
        ? _providerExpandScrollOffset
        : _providerCollapseScrollOffset;
    _setModelFamilyScrolledAwayFromStart(offsetFromStart > threshold);
  }

  void _setModelFamilyScrolledAwayFromStart(bool scrolledAway) {
    if (_isModelFamilyScrolledAwayFromStart == scrolledAway) return;
    setState(() => _isModelFamilyScrolledAwayFromStart = scrolledAway);
    _providerLabelController.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 420, damping: 38),
        _providerLabelController.value,
        scrolledAway ? 0 : 1,
        _providerLabelController.velocity,
      ),
    );
  }

  void _selectModelFamily(String? familyKey) {
    if (_selectedModelFamilyKey == familyKey && !_showFavoritesOnly) return;
    setState(() {
      _showFavoritesOnly = false;
      _selectedModelFamilyKey = familyKey;
      _activeProviderKey = null;
    });
    _scrollModelListToTop();
  }

  void _selectFavorites() {
    if (_showFavoritesOnly) return;
    setState(() {
      _showFavoritesOnly = true;
      _selectedModelFamilyKey = null;
      _activeProviderKey = null;
    });
    _scrollModelListToTop();
  }

  void _selectProvider(String providerKey) {
    if (_effectiveSelectedProviderKey == providerKey) return;
    setState(() {
      _selectedProviderKey = providerKey;
      _didManuallySelectProvider = true;
      _showFavoritesOnly = false;
      _selectedModelFamilyKey = null;
      _activeProviderKey = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_modelFamilyScrollController.hasClients) {
        _modelFamilyScrollController.jumpTo(
          _modelFamilyScrollController.position.minScrollExtent,
        );
      }
      _setModelFamilyScrolledAwayFromStart(false);
    });
    _scrollModelListToTop();
  }

  void _scrollModelListToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      try {
        _itemScrollController.jumpTo(index: 0, alignment: _listTopAlignment());
      } catch (_) {}
    });
  }

  bool _matchesSelectedModelFamily(_ModelItem item) {
    final selectedFamily = _selectedModelFamilyKey;
    return selectedFamily == null || _modelFamilyKeyFor(item) == selectedFamily;
  }

  Widget _buildPopupBottomOverlay(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = colorScheme.surface;

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: 0),
                    background.withValues(alpha: 0.88),
                    background,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: _buildPopupSearchBar(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPopupSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(999);

    final glassFill = isDark
        ? const Color(0xCC1C1C1E)
        : const Color(0xE0FFFFFF);
    final glassBorder = isDark
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);

    return _ModelPickerLiquidPressScale(
      enabled: !_isLoading,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: isDark ? const Color(0x26000000) : const Color(0x0F000000),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: glassFill,
                borderRadius: borderRadius,
                border: Border.all(color: glassBorder, width: 0.75),
              ),
              child: SizedBox(
                height: 38,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(
                      Lucide.Search,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        enabled: !_isLoading,
                        textInputAction: TextInputAction.search,
                        onChanged: _handleSearchChanged,
                        style: theme.textTheme.bodyMedium,
                        cursorColor: colorScheme.primary,
                        decoration: InputDecoration(
                          hintText: l10n.modelSelectSheetModelSearchHint,
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_search.text.isNotEmpty)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _clearSearch,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.clear_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSearchChanged(String value) {
    final query = value.trim();
    final enteringSearch = _lastQuery.isEmpty && query.isNotEmpty;
    setState(() {});
    if (enteringSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _scrollToFirstSearchGroup();
      });
    }
    _lastQuery = query;
  }

  void _clearSearch() {
    if (_search.text.isEmpty) return;
    _search.clear();
    _handleSearchChanged('');
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _search.text.trim();
    final pinnedModelKeys = context.watch<SettingsProvider>().pinnedModels;
    final selectedProviderKey = widget.usePopupContentFrame
        ? _effectiveSelectedProviderKey
        : null;
    _listTopPadding = widget.usePopupContentFrame
        ? PopupContentFrame.contentTopPadding(
            context,
            widget.isDialog,
            hasHeaderExtension:
                widget.limitProviderKey == null && selectedProviderKey != null,
          )
        : 0;
    // Build flattened rows and index maps for precise positioning
    _rows.clear();
    _headerIndexMap.clear();
    _modelIndexMap.clear();
    _favModelIndexMap.clear();

    final Set<String> favMatchedKeys = <String>{};

    if (widget.limitProviderKey == null && !widget.usePopupContentFrame) {
      final pinned = pinnedModelKeys;
      if (pinned.isNotEmpty) {
        final favs = <_ModelItem>[];
        for (final k in pinned) {
          final parts = k.split('::');
          if (parts.length < 2) continue;
          final pk = parts[0];
          if (selectedProviderKey != null && pk != selectedProviderKey) {
            continue;
          }
          final mid = parts.sublist(1).join('::');
          final g = _groups[pk];
          if (g == null) continue;
          final found = g.items.firstWhere(
            (e) => e.id == mid,
            orElse: () => _ModelItem(
              providerKey: pk,
              providerName: g.name,
              id: mid,
              info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
              pinned: true,
              selected: false,
            ),
          );
          if (_matchesSelectedModelFamily(found) &&
              _matchesSearch(query, found, found.providerName)) {
            favs.add(found.copyWith(pinned: true));
            favMatchedKeys.add('$pk::$mid');
          }
        }
        if (favs.isNotEmpty) {
          _headerIndexMap['__fav__'] = _rows.length;
          _rows.add(
            _HeaderRow(
              l10n.modelSelectSheetFavoritesSection,
              isFavorites: true,
            ),
          );
          for (final m in favs) {
            _favModelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
            _rows.add(_ModelRow(m, showProviderLabel: true));
          }
        }
      }
    }

    for (final pk in _orderedKeys) {
      if (selectedProviderKey != null && pk != selectedProviderKey) continue;
      final g = _groups[pk]!;
      final familyItems = g.items
          .where(
            (item) =>
                _matchesSelectedModelFamily(item) &&
                (!_showFavoritesOnly ||
                    pinnedModelKeys.contains(
                      '${item.providerKey}::${item.id}',
                    )),
          )
          .toList();
      List<_ModelItem> items;
      if (query.isEmpty) {
        items = familyItems;
      } else if (widget.usePopupContentFrame) {
        items = familyItems
            .where((item) => _matchesSearch(query, item, g.name))
            .toList();
      } else {
        final providerMatches = _providerMatchesSearch(query, g.name);
        items = providerMatches
            ? familyItems
            : familyItems
                  .where((e) => _matchesSearch(query, e, g.name))
                  .toList();
        if (favMatchedKeys.isNotEmpty) {
          items = items
              .where(
                (e) => !favMatchedKeys.contains('${e.providerKey}::${e.id}'),
              )
              .toList();
        }
      }
      if (items.isEmpty) continue;
      _headerIndexMap[pk] = _rows.length;
      if (!widget.usePopupContentFrame) {
        _rows.add(_HeaderRow(g.name, providerKey: pk));
      }
      for (final m in items) {
        _modelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
        _rows.add(_ModelRow(m));
      }
    }

    if (_rows.isEmpty) return const SizedBox.shrink();

    _scheduleActiveProviderUpdate();

    return LayoutBuilder(
      builder: (context, constraints) {
        _listViewportHeight = constraints.maxHeight;
        return Stack(
          children: [
            ScrollablePositionedList.builder(
              itemCount: _rows.length,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              padding: EdgeInsets.only(
                top: _listTopPadding,
                bottom: widget.usePopupContentFrame
                    ? _popupSearchReservedExtent
                    : _listBottomPadding,
              ),
              itemBuilder: (context, index) {
                final row = _rows[index];
                if (row is _HeaderRow) {
                  return _sectionHeader(
                    context,
                    row.title,
                    providerKey: row.providerKey,
                  );
                } else if (row is _ModelRow) {
                  return _modelTile(
                    context,
                    row.item,
                    showProviderLabel: row.showProviderLabel,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            if (widget.limitProviderKey == null)
              Positioned(
                top: -1,
                left: 0,
                right: 0,
                child: ColoredBox(
                  key: const ValueKey('model-selector-top-seam-cover'),
                  color: Theme.of(context).colorScheme.surface,
                  child: const SizedBox(height: 1),
                ),
              ),
            if (!widget.usePopupContentFrame && _activeProviderKey != null)
              _stickyProviderHeader(context),
          ],
        );
      },
    );
  }

  Widget _buildBottomTabs(BuildContext context) {
    // Bottom provider tabs (ordered per ProvidersPage order)
    final List<Widget> providerTabs = <Widget>[];
    if (widget.limitProviderKey == null && !_isLoading) {
      String? selectedProviderKey;
      // Find which provider currently holds the selected model
      _groups.forEach((pk, group) {
        if (selectedProviderKey == null &&
            group.items.any(
              (m) => m.selected && _matchesSelectedModelFamily(m),
            )) {
          selectedProviderKey = pk;
        }
      });
      _providerTabKeys.removeWhere((key, _) => !_orderedKeys.contains(key));
      for (final k in _orderedKeys) {
        final g = _groups[k];
        if (g != null && g.items.any(_matchesSelectedModelFamily)) {
          providerTabs.add(
            _providerTab(
              context,
              k,
              g.name,
              selected: k == selectedProviderKey,
            ),
          );
        }
      }
    }

    if (providerTabs.isEmpty) return const SizedBox.shrink();

    return Padding(
      // SafeArea already applies bottom inset; avoid doubling it here.
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 10),
      child: SingleChildScrollView(
        key: _providerTabsViewportKey,
        controller: _providerTabsController,
        scrollDirection: Axis.horizontal,
        child: Row(children: providerTabs),
      ),
    );
  }

  Widget _stickyProviderHeader(BuildContext context) {
    if (widget.usePopupContentFrame || widget.limitProviderKey != null) {
      return const SizedBox.shrink();
    }
    final providerKey = _activeProviderKey;
    if (providerKey == null) return const SizedBox.shrink();
    final group = _groups[providerKey];
    if (group == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Positioned(
      top: -1,
      left: 0,
      right: 0,
      child: DecoratedBox(
        key: const ValueKey('model-selector-sticky-provider'),
        decoration: BoxDecoration(color: cs.surface),
        child: SizedBox(
          height: _stickyProviderHeaderHeight + 1,
          child: ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                final isIncoming =
                    child.key == ValueKey('sticky-provider-$providerKey');
                final dy = (isIncoming ? 0.65 : -0.65) * _stickySwitchDirection;
                final offsetAnimation = Tween<Offset>(
                  begin: Offset(0, dy),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  ),
                );
              },
              child: Padding(
                key: ValueKey('sticky-provider-$providerKey'),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: AppFontWeights.emphasis,
                          color: cs.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                    ),
                    ProviderBalanceBadge(
                      providerKey: providerKey,
                      displayName: group.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppFontWeights.emphasis,
                      ),
                      color: cs.primary,
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

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    String? providerKey,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (providerKey != null)
            ProviderBalanceBadge(
              providerKey: providerKey,
              displayName: title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: AppFontWeights.emphasis,
              ),
              color: cs.primary,
            ),
        ],
      ),
    );
  }

  Widget _modelTile(
    BuildContext context,
    _ModelItem m, {
    bool showProviderLabel = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final settings = context.read<SettingsProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = m.selected
        ? (isDark
              ? cs.primary.withValues(alpha: 0.12)
              : cs.primary.withValues(alpha: 0.08))
        : cs.surface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: RepaintBoundary(
        child: IosCardPress(
          baseColor: bg,
          borderRadius: BorderRadius.circular(14),
          pressedBlendStrength: 0.10,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTap: () =>
              Navigator.of(context).pop(ModelSelection(m.providerKey, m.id)),
          // [kelivo-hosted] kelivo-arch.md §4 — hosted-model capabilities are
          // admin-curated server-side and pushed down via `/__client/models`;
          // local editing would just get silently clobbered by the next
          // sync/model refresh, so the long-press edit sheet doesn't apply.
          onLongPress: m.providerKey == kHostedProviderKey
              ? null
              : () async {
                  await showModelDetailSheet(
                    context,
                    providerKey: m.providerKey,
                    modelId: m.id,
                  );
                  if (mounted) {
                    // Don't force _isLoading back to true here: _groups
                    // already holds the pre-edit list, so the refresh below
                    // can just swap it in place once done instead of
                    // blanking the list back to a spinner in between.
                    await _loadModelsAsync();
                  }
                },
          child: SizedBox(
            width: double.infinity,
            child: Row(
              children: [
                _BrandAvatar(name: m.id, assetOverride: m.asset, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!showProviderLabel)
                        Text(
                          m.info.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: AppFontWeights.semibold,
                          ),
                        )
                      else
                        Text.rich(
                          TextSpan(
                            text: m.info.displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: AppFontWeights.semibold,
                            ),
                            children: [
                              TextSpan(
                                text: ' | ${m.providerName}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      ModelTagWrap(model: m.info),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) {
                    final pinnedNow = context.select<SettingsProvider, bool>(
                      (s) => s.isModelPinned(m.providerKey, m.id),
                    );
                    final icon = pinnedNow
                        ? Icons.favorite
                        : Icons.favorite_border;
                    return Tooltip(
                      message: l10n.modelSelectSheetFavoriteTooltip,
                      child: IosIconButton(
                        icon: icon,
                        size: 20,
                        color: cs.primary,
                        onTap: () =>
                            settings.togglePinModel(m.providerKey, m.id),
                        padding: const EdgeInsets.all(6),
                        minSize: 36,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerTab(
    BuildContext context,
    String key,
    String name, {
    bool selected = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: _providerTabKeyFor(key),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: _ProviderChip(
        key: ValueKey('model-selector-provider-tab-$key'),
        avatar: ProviderAvatar(providerKey: key, displayName: name, size: 18),
        label: name,
        selected: selected,
        borderColor: cs.outlineVariant.withValues(alpha: 0.25),
        onTap: () async {
          await _jumpToProvider(key);
        },
      ),
    );
  }

  Future<void> _jumpToProvider(String pk) async {
    // Expand sheet first if needed
    await _expandSheetIfNeeded(_maxSize);

    // Use precise index jump via ScrollablePositionedList
    final idx = _headerIndexMap[pk];
    if (idx != null) {
      if (!_itemScrollController.isAttached) {
        // Retry shortly if list not yet attached
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) {
            _jumpToProvider(pk);
          }
        });
        return;
      }
      try {
        await _itemScrollController.scrollTo(
          index: idx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
  }

  Future<void> _jumpToFavorites() async {
    if (widget.limitProviderKey != null) return;
    // Expand sheet first to reveal more content
    await _expandSheetIfNeeded(_maxSize);

    // If search text hides favorites section, clear it to ensure favorites are visible
    if (_search.text.isNotEmpty) {
      _search.clear();
      _lastQuery = '';
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 150));
    }

    // Jump to favorites header index if present
    final idx = _headerIndexMap['__fav__'];
    if (idx != null) {
      if (!_itemScrollController.isAttached) {
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted) _jumpToFavorites();
        });
        return;
      }
      try {
        await _itemScrollController.scrollTo(
          index: idx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {}
    }
  }
}

/// Liquid-glass press response used by the bottom floating model search bar.
class _ModelPickerLiquidPressScale extends StatefulWidget {
  const _ModelPickerLiquidPressScale({
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<_ModelPickerLiquidPressScale> createState() =>
      _ModelPickerLiquidPressScaleState();
}

class _ModelPickerLiquidPressScaleState
    extends State<_ModelPickerLiquidPressScale> {
  bool _isPressed = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!mounted || !widget.enabled) return;
    setState(() => _isPressed = true);
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    if (!mounted || !widget.enabled) return;
    setState(() => _isPressed = false);
  }

  @override
  void didUpdateWidget(covariant _ModelPickerLiquidPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _isPressed) {
      _isPressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled && !_isPressed) return widget.child;

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUpOrCancel,
      onPointerCancel: _handlePointerUpOrCancel,
      child: AnimatedScale(
        scale: _isPressed ? 1.04 : 1.0,
        duration: _isPressed
            ? const Duration(milliseconds: 200)
            : const Duration(milliseconds: 600),
        curve: _isPressed ? Curves.easeOutCubic : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}

class _ProviderChip extends StatefulWidget {
  const _ProviderChip({
    super.key,
    required this.avatar,
    required this.label,
    required this.onTap,
    this.borderColor,
    this.selected = false,
  });
  final Widget avatar;
  final String label;
  final VoidCallback onTap;
  final Color? borderColor;
  final bool selected;

  @override
  State<_ProviderChip> createState() => _ProviderChipState();
}

class _ProviderChipState extends State<_ProviderChip> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSelected = widget.selected;
    // Subtle background tint when selected (less conspicuous)
    final Color baseBg = isSelected
        ? (isDark
              ? cs.primary.withValues(alpha: 0.08)
              : cs.primary.withValues(alpha: 0.05))
        : cs.surface;
    final Color overlay = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);
    final Color bg = _pressed ? Color.alphaBlend(overlay, baseBg) : baseBg;
    // Slightly stronger border when selected; keep label color unchanged for subtlety
    final Color borderColor =
        widget.borderColor ?? cs.outlineVariant.withValues(alpha: 0.25);
    final Color labelColor = cs.onSurface;
    return Semantics(
      label: widget.label,
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.avatar,
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: AppFontWeights.medium,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelFamilyChip extends StatefulWidget {
  const _ModelFamilyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ModelFamilyChip> createState() => _ModelFamilyChipState();
}

class _ModelFamilyChipState extends State<_ModelFamilyChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = widget.selected
        ? colorScheme.primary
        : isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFE9E9EB);
    final pressedFill = Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.055),
      fill,
    );

    return Semantics(
      label: widget.label,
      button: true,
      selected: widget.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: _modelPickerPillHeight,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: _pressed ? pressedFill : fill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                height: 1,
                fontWeight: widget.selected
                    ? AppFontWeights.semibold
                    : AppFontWeights.medium,
                color: widget.selected
                    ? Colors.white
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderGroup {
  final String name;
  final List<_ModelItem> items;
  _ProviderGroup({required this.name, required this.items});
}

class _ModelItem {
  final String providerKey;
  final String providerName;
  final String id;
  final ModelInfo info;
  final bool pinned;
  final bool selected;
  final String? asset; // pre-resolved avatar asset for performance
  _ModelItem({
    required this.providerKey,
    required this.providerName,
    required this.id,
    required this.info,
    this.pinned = false,
    this.selected = false,
    this.asset,
  });
  _ModelItem copyWith({bool? pinned, bool? selected}) => _ModelItem(
    providerKey: providerKey,
    providerName: providerName,
    id: id,
    info: info,
    pinned: pinned ?? this.pinned,
    selected: selected ?? this.selected,
    asset: asset,
  );
}

const List<String> _modelFamilyOrder = <String>[
  'claude',
  'deepseek',
  'gpt',
  'gemini',
  'qwen',
  'glm',
  'kimi',
  'minimax',
  'grok',
  'llama',
  'mistral',
  'yi',
  'doubao',
  'hunyuan',
  'command',
  'step',
  'phi',
  'internlm',
  'baichuan',
  'other',
];

final Map<String, RegExp> _modelFamilyPatterns = <String, RegExp>{
  'claude': RegExp(r'claude'),
  'deepseek': RegExp(r'deepseek|深度求索'),
  'gpt': RegExp(r'(^|[^a-z0-9])gpt([^a-z0-9]|$)'),
  'gemini': RegExp(r'gemini'),
  'qwen': RegExp(r'qwen|通义千问'),
  'glm': RegExp(r'chatglm|glm|智谱清言'),
  'kimi': RegExp(r'kimi|moonshot|月之暗面'),
  'minimax': RegExp(r'minimax|abab'),
  'grok': RegExp(r'grok'),
  'llama': RegExp(r'llama'),
  'mistral': RegExp(r'mistral|ministral|codestral|devstral|magistral'),
  'yi': RegExp(r'(^|[^a-z0-9])yi([^a-z0-9]|$)|零一万物'),
  'doubao': RegExp(r'doubao|豆包'),
  'hunyuan': RegExp(r'hunyuan|混元'),
  'command': RegExp(r'command[-_ ]?r'),
  'step': RegExp(r'step[-_ ]'),
  'phi': RegExp(r'(^|[^a-z0-9])phi([^a-z0-9]|$)'),
  'internlm': RegExp(r'internlm'),
  'baichuan': RegExp(r'baichuan'),
};

String _modelFamilyKeyFor(_ModelItem item) {
  final modelName = '${item.id} ${item.info.displayName}'.toLowerCase();
  for (final entry in _modelFamilyPatterns.entries) {
    if (entry.value.hasMatch(modelName)) return entry.key;
  }
  return 'other';
}

String _modelFamilyLabel(String key, AppLocalizations l10n) {
  if (key == 'other') return l10n.modelSelectSheetOtherFamily;
  return switch (key) {
    'claude' => 'Claude',
    'deepseek' => 'DeepSeek',
    'gpt' => 'GPT',
    'gemini' => 'Gemini',
    'qwen' => 'Qwen',
    'glm' => 'GLM',
    'kimi' => 'Kimi',
    'minimax' => 'MiniMax',
    'grok' => 'Grok',
    'llama' => 'Llama',
    'mistral' => 'Mistral',
    'yi' => 'Yi',
    'doubao' => 'Doubao',
    'hunyuan' => 'Hunyuan',
    'command' => 'Command',
    'step' => 'Step',
    'phi' => 'Phi',
    'internlm' => 'InternLM',
    'baichuan' => 'Baichuan',
    _ => key,
  };
}

// Virtualization entry: fixed height + lazy builder
// Rows for flattened list
abstract class _ListRow {}

class _HeaderRow extends _ListRow {
  final String title;
  final String? providerKey;
  final bool isFavorites;
  _HeaderRow(this.title, {this.providerKey, this.isFavorites = false});
}

class _ModelRow extends _ListRow {
  final _ModelItem item;
  final bool showProviderLabel;
  _ModelRow(this.item, {this.showProviderLabel = false});
}

// Reuse badges and avatars similar to provider detail
class _BrandAvatar extends StatelessWidget {
  const _BrandAvatar({required this.name, this.size = 20, this.assetOverride});
  final String name;
  final double size;
  final String? assetOverride;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final asset = assetOverride ?? BrandAssets.assetForName(name);
    Widget inner;
    if (asset != null) {
      final iconSize = BrandAssets.assetIsFullBleed(asset) ? size : size * 0.62;
      if (asset.endsWith('.svg')) {
        final isColorful = asset.contains('color');
        final dark = Theme.of(context).brightness == Brightness.dark;
        final ColorFilter? tint = (dark && !isColorful)
            ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
            : null;
        inner = SvgPicture.asset(
          asset,
          width: iconSize,
          height: iconSize,
          colorFilter: tint,
        );
      } else {
        inner = Image.asset(
          asset,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
        );
      }
    } else {
      inner = Text(
        name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
        style: TextStyle(
          color: cs.primary,
          fontWeight: AppFontWeights.emphasis,
          fontSize: size * 0.42,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : cs.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }
}

// ===== Desktop dialog implementation =====

Future<ModelSelection?> _showDesktopModelSelector(
  BuildContext context, {
  String? limitProviderKey,
  String? initialProviderKey,
  String? initialModelId,
}) async {
  return showGeneralDialog<ModelSelection>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'model-select-desktop',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    pageBuilder: (ctx, _, __) => _DesktopModelSelectDialogBody(
      limitProviderKey: limitProviderKey,
      initialProviderKey: initialProviderKey,
      initialModelId: initialModelId,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DesktopModelSelectDialogBody extends StatefulWidget {
  const _DesktopModelSelectDialogBody({
    this.limitProviderKey,
    this.initialProviderKey,
    this.initialModelId,
  });
  final String? limitProviderKey;
  final String? initialProviderKey;
  final String? initialModelId;
  @override
  State<_DesktopModelSelectDialogBody> createState() =>
      _DesktopModelSelectDialogBodyState();
}

class _DesktopModelSelectDialogBodyState
    extends State<_DesktopModelSelectDialogBody> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // Seeded from the cross-open cache (see _ModelSelectCache) so a reopen
  // shows the last known list immediately instead of a blank spinner while
  // the background refresh in `_loadModels` runs.
  bool _loading = _ModelSelectCache.groups == null;
  Map<String, _ProviderGroup> _groups = _ModelSelectCache.groups ?? const {};
  List<String> _orderedKeys = _ModelSelectCache.orderedKeys ?? const [];
  // Flattened rows and precise index mapping for jump
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final List<_ListRow> _rows = <_ListRow>[];
  final Map<String, int> _headerIndexMap =
      <String, int>{}; // providerKey or '__fav__' -> index
  final Map<String, int> _modelIndexMap =
      <String, int>{}; // 'pk::modelId' in provider sections -> index
  final Map<String, int> _favModelIndexMap =
      <String, int>{}; // 'pk::modelId' in favorites -> index
  bool _autoScrolled = false; // auto-scroll once when dialog opens

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusSearchField());
    Future.microtask(_loadModels);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  dynamic _sanitizeJsonValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _sanitizeJsonValue(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _sanitizeJsonValue(item)];
    }
    return value.toString();
  }

  Map<String, dynamic> _sanitizeOverrides(Map<String, dynamic> overrides) {
    return {
      for (final entry in overrides.entries)
        entry.key.toString(): _sanitizeJsonValue(entry.value),
    };
  }

  Map<String, dynamic> _buildProviderConfigsPayload(SettingsProvider settings) {
    final keys = <String>{
      ...settings.providersOrder.where((e) => e.trim().isNotEmpty),
      ...settings.providerConfigs.keys.where((e) => e.trim().isNotEmpty),
    };
    if (widget.limitProviderKey != null &&
        widget.limitProviderKey!.trim().isNotEmpty) {
      keys.add(widget.limitProviderKey!);
    }
    // [kelivo-hosted] kelivo-arch.md §8 — the hosted provider isn't in
    // `providerConfigs`/`providersOrder` (see getProviderConfig's special
    // case), so it has to be added to the candidate key set explicitly.
    // Gated on being signed in so a signed-out user doesn't see an empty,
    // disabled "Kelivo Hosted" group.
    if (ClientBackendSession.token != null) {
      keys.add(kHostedProviderKey);
    }
    final out = <String, dynamic>{};
    for (final key in keys) {
      final cfg = settings.getProviderConfig(key, defaultName: key);
      out[key] = {
        'enabled': cfg.enabled,
        'name': cfg.name,
        'models': cfg.models,
        'overrides': _sanitizeOverrides(cfg.modelOverrides),
      };
    }
    return out;
  }

  String _currentModelKey(
    SettingsProvider settings,
    AssistantProvider assistantProvider,
  ) {
    final hasInitial =
        widget.initialProviderKey != null && widget.initialModelId != null;
    final provider = hasInitial
        ? widget.initialProviderKey
        : assistantProvider.currentAssistant?.chatModelProvider ??
              settings.currentModelProvider;
    final modelId = hasInitial
        ? widget.initialModelId
        : assistantProvider.currentAssistant?.chatModelId ??
              settings.currentModelId;
    return (provider != null && modelId != null) ? '$provider::$modelId' : '';
  }

  Future<void> _loadModels() async {
    // [kelivo-hosted] kelivo-arch.md §8 — see mobile `_loadModelsAsync`'s
    // identical comment above.
    if (ClientBackendSession.token != null) {
      await ClientBackendSession.refresh();
      if (!mounted) return;
    }
    final settings = context.read<SettingsProvider>();
    final assistantProvider = context.read<AssistantProvider>();
    final providerConfigs = _buildProviderConfigsPayload(settings);
    final currentKey = _currentModelKey(settings, assistantProvider);

    final data = _ModelProcessingData(
      providerConfigs: providerConfigs,
      pinnedModels: settings.pinnedModels,
      currentModelKey: currentKey,
      providersOrder: _buildDisplayProvidersOrder(
        settings,
        providerConfigs.keys,
      ),
      limitProviderKey: widget.limitProviderKey,
      disableResolverPlatformLogging: false,
    );
    // Synchronous processing is fast enough here
    final result = _processModelsInBackground(data);
    if (!mounted) return;
    setState(() {
      _groups = result.groups;
      _orderedKeys = result.orderedKeys;
      _loading = false;
    });
    _ModelSelectCache.groups = result.groups;
    _ModelSelectCache.orderedKeys = result.orderedKeys;
    _focusSearchField(defer: true);
    // Defer auto-scroll until list is built and attached
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_autoScrolled) {
        _autoScrollToCurrent();
      }
    });
  }

  bool _matchesSearch(String query, _ModelItem item, String providerName) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return item.id.toLowerCase().contains(q) ||
        item.info.displayName.toLowerCase().contains(q);
  }

  bool _providerMatchesSearch(String query, String providerName) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    return providerName.toLowerCase().contains(lowerQuery);
  }

  void _focusSearchField({bool defer = false}) {
    if (!mounted) return;
    void request() {
      if (!mounted) return;
      if (_searchFocusNode.hasFocus) return;
      FocusScope.of(context).requestFocus(_searchFocusNode);
    }

    if (defer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => request());
    } else {
      request();
    }
  }

  void _rebuildRows() {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.read<SettingsProvider>();
    final query = _searchCtrl.text.trim();
    _rows.clear();
    _headerIndexMap.clear();
    _modelIndexMap.clear();
    _favModelIndexMap.clear();

    final Set<String> favMatchedKeys = <String>{};

    if (widget.limitProviderKey == null) {
      final pinned = settings.pinnedModels;
      if (pinned.isNotEmpty) {
        final favs = <_ModelItem>[];
        for (final k in pinned) {
          final parts = k.split('::');
          if (parts.length < 2) continue;
          final pk = parts[0];
          final mid = parts.sublist(1).join('::');
          final g = _groups[pk];
          if (g == null) continue;
          final found = g.items.firstWhere(
            (e) => e.id == mid,
            orElse: () => _ModelItem(
              providerKey: pk,
              providerName: g.name,
              id: mid,
              info: ModelRegistry.infer(ModelInfo(id: mid, displayName: mid)),
              pinned: true,
              selected: false,
            ),
          );
          if (_matchesSearch(query, found, found.providerName)) {
            favs.add(found.copyWith(pinned: true));
            favMatchedKeys.add('$pk::$mid');
          }
        }
        if (favs.isNotEmpty) {
          _headerIndexMap['__fav__'] = _rows.length;
          _rows.add(
            _HeaderRow(
              l10n.modelSelectSheetFavoritesSection,
              isFavorites: true,
            ),
          );
          for (final m in favs) {
            _favModelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
            _rows.add(_ModelRow(m, showProviderLabel: true));
          }
        }
      }
    }

    for (final pk in _orderedKeys) {
      final g = _groups[pk];
      if (g == null) continue;
      List<_ModelItem> items;
      if (query.isEmpty) {
        items = g.items;
      } else {
        final providerMatches = _providerMatchesSearch(query, g.name);
        items = providerMatches
            ? g.items
            : g.items.where((e) => _matchesSearch(query, e, g.name)).toList();
        if (favMatchedKeys.isNotEmpty) {
          items = items
              .where(
                (e) => !favMatchedKeys.contains('${e.providerKey}::${e.id}'),
              )
              .toList();
        }
      }
      if (items.isEmpty) continue;
      // When limiting to a single provider, hide the provider header (and its settings button)
      if (widget.limitProviderKey == null) {
        _headerIndexMap[pk] = _rows.length;
        _rows.add(_HeaderRow(g.name, providerKey: pk));
      }
      for (final m in items) {
        _modelIndexMap['${m.providerKey}::${m.id}'] = _rows.length;
        _rows.add(_ModelRow(m));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    final dialog = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 460,
          maxWidth: 620,
          maxHeight: 560,
        ),
        child: Material(
          color: cs.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : cs.outlineVariant.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Body
                Expanded(
                  child: Container(
                    color: cs.surface,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocusNode,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: l10n.modelSelectSheetSearchHint,
                              isDense: true,
                              filled: true,
                              fillColor: isDark
                                  ? Colors.white10
                                  : const Color(0xFFF2F3F5),
                              prefixIcon: Icon(
                                Lucide.Search,
                                size: 16,
                                color: cs.onSurface.withValues(alpha: 0.7),
                              ),
                              suffixIcon:
                                  (widget.limitProviderKey == null &&
                                      context
                                          .watch<SettingsProvider>()
                                          .pinnedModels
                                          .isNotEmpty)
                                  ? Tooltip(
                                      message:
                                          l10n.modelSelectSheetFavoritesSection,
                                      child: IconButton(
                                        icon: Icon(
                                          Lucide.Bookmark,
                                          size: 16,
                                          color: cs.onSurface.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                        onPressed: _jumpToFavorites,
                                      ),
                                    )
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.transparent,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.transparent,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: cs.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _buildList(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Material(type: MaterialType.transparency, child: dialog);
  }

  Widget _buildList(BuildContext context) {
    // Watch pinned models to keep the favorites section live when user toggles
    // favorites from any item.
    final _ = context.watch<SettingsProvider>().pinnedModels.length;
    // Build flattened rows based on current search and pinned state
    _rebuildRows();
    // After rows are rebuilt and rendered, perform initial auto-scroll
    if (!_autoScrolled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoScrolled) {
          _autoScrollToCurrent();
        }
      });
    }
    if (_rows.isEmpty) return const Center(child: SizedBox());
    return ScrollablePositionedList.builder(
      itemCount: _rows.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      itemBuilder: (context, index) {
        final row = _rows[index];
        if (row is _HeaderRow) {
          if (row.isFavorites) {
            return _favoritesHeader(context, row.title);
          }
          return _providerHeader(context, row.providerKey, row.title);
        } else if (row is _ModelRow) {
          return _desktopModelTile(
            context,
            row.item,
            showProviderLabel: row.showProviderLabel,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _autoScrollToCurrent() async {
    // Ensure controller is attached to the list before scrolling
    if (!_itemScrollController.isAttached) {
      Future.delayed(const Duration(milliseconds: 60), () {
        if (mounted && !_autoScrolled) _autoScrollToCurrent();
      });
      return;
    }

    final settings = context.read<SettingsProvider>();
    final currentKey = _currentModelKey(
      settings,
      context.read<AssistantProvider>(),
    );
    if (currentKey.isEmpty) return;

    // Rebuild to ensure index maps are current
    _rebuildRows();

    final bool showFavorites =
        widget.limitProviderKey == null && _searchCtrl.text.isEmpty;
    final bool isPinned = settings.pinnedModels.contains(currentKey);

    int? targetIndex;
    if (showFavorites && isPinned) {
      targetIndex = _favModelIndexMap[currentKey];
    }
    targetIndex ??= _modelIndexMap[currentKey];
    // If provider headers are visible, fall back to its section header
    if (widget.limitProviderKey == null) {
      final separator = currentKey.indexOf('::');
      final pk = separator == -1
          ? currentKey
          : currentKey.substring(0, separator);
      targetIndex ??= _headerIndexMap[pk];
    }

    if (targetIndex == null) return;

    try {
      await _itemScrollController.scrollTo(
        index: targetIndex,
        alignment: 0.5, // try to center the current model
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
      _autoScrolled = true;
    } catch (_) {
      // Retry once shortly after if initial scroll fails
      Future.delayed(const Duration(milliseconds: 80), () async {
        if (!mounted || _autoScrolled) return;
        try {
          await _itemScrollController.scrollTo(
            index: targetIndex!,
            alignment: 0.5,
            duration: const Duration(milliseconds: 360),
            curve: Curves.easeOutCubic,
          );
          _autoScrolled = true;
        } catch (_) {}
      });
    }
  }

  Widget _desktopModelTile(
    BuildContext context,
    _ModelItem m, {
    bool showProviderLabel = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final bg = m.selected
        ? (isDark
              ? cs.primary.withValues(alpha: 0.12)
              : cs.primary.withValues(alpha: 0.08))
        : cs.surface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: IosCardPress(
        baseColor: bg,
        borderRadius: BorderRadius.circular(14),
        pressedBlendStrength: 0.10,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        onTap: () =>
            Navigator.of(context).pop(ModelSelection(m.providerKey, m.id)),
        child: Row(
          children: [
            _BrandAvatar(name: m.id, assetOverride: m.asset, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: m.info.displayName,
                  style: TextStyle(fontSize: 12.5),
                  children: [
                    if (showProviderLabel)
                      TextSpan(
                        text: ' | ${m.providerName}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            ModelCapsulesRow(
              model: m.info,
              pillPadding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 2,
              ),
              bgOpacityDark: 0.18,
              bgOpacityLight: 0.14,
              borderOpacity: 0.22,
              itemSpacing: 4,
            ),
            const SizedBox(width: 4),
            Builder(
              builder: (context) {
                final pinnedNow = context.select<SettingsProvider, bool>(
                  (s) => s.isModelPinned(m.providerKey, m.id),
                );
                final icon = pinnedNow ? Icons.favorite : Icons.favorite_border;
                return Tooltip(
                  message: l10n.modelSelectSheetFavoriteTooltip,
                  child: IosIconButton(
                    icon: icon,
                    size: 16,
                    color: cs.primary,
                    onTap: () => context
                        .read<SettingsProvider>()
                        .togglePinModel(m.providerKey, m.id),
                    padding: const EdgeInsets.all(3),
                    minSize: 26,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _favoritesHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Icon(
            Lucide.Bookmark,
            size: 14,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _providerHeader(
    BuildContext context,
    String? providerKey,
    String displayName,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: [
          Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: AppFontWeights.semibold,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const Spacer(),
          if (providerKey != null)
            ProviderBalanceBadge(
              providerKey: providerKey,
              displayName: displayName,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: AppFontWeights.emphasis,
              ),
              color: cs.primary,
            ),
        ],
      ),
    );
  }

  Future<void> _jumpToFavorites() async {
    // Ensure rows are current
    _rebuildRows();
    final idx = _headerIndexMap['__fav__'];
    if (idx == null) return;
    if (!_itemScrollController.isAttached) {
      Future.delayed(const Duration(milliseconds: 60), _jumpToFavorites);
      return;
    }
    try {
      await _itemScrollController.scrollTo(
        index: idx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {}
  }
}

// (desktop tactile row removed in favor of IosCardPress for consistency)
