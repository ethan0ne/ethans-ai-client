import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/services/storage/storage_usage_service.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_checkbox.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../utils/platform_utils.dart';
import '../../chat/pages/image_viewer_page.dart';
import 'log_viewer_page.dart';
import '../../../theme/app_font_weights.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';

class StorageSpacePage extends StatefulWidget {
  const StorageSpacePage({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<StorageSpacePage> createState() => _StorageSpacePageState();
}

class _StorageSpacePageState extends State<StorageSpacePage> {
  StorageUsageReport? _report;
  bool _loading = false;
  bool _clearing = false;
  StorageUsageCategoryKey _selected = StorageUsageCategoryKey.images;

  @override
  void initState() {
    super.initState();
    _refreshReport();
  }

  Future<StorageUsageReport?> _refreshReport() async {
    if (_loading) return _report;
    setState(() => _loading = true);
    try {
      final rep = await StorageUsageService.computeReport();
      if (!mounted) return rep;
      setState(() {
        _report = rep;
        _loading = false;
        final keys = rep.categories.map((c) => c.key).toSet();
        if (!keys.contains(_selected)) {
          _selected = StorageUsageCategoryKey.images;
        }
      });
      return rep;
    } catch (_) {
      if (!mounted) return null;
      setState(() => _loading = false);
      return null;
    }
  }

  String _fmtBytes(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(2)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  Color _barColorFor(StorageUsageCategoryKey key, ColorScheme cs) {
    switch (key) {
      case StorageUsageCategoryKey.images:
        return const Color(0xFF6366F1); // indigo
      case StorageUsageCategoryKey.files:
        return const Color(0xFFA855F7); // purple
      case StorageUsageCategoryKey.chatData:
        return const Color(0xFF22C55E);
      case StorageUsageCategoryKey.assistantData:
        return const Color(0xFF3B82F6); // blue (distinct from chat green)
      case StorageUsageCategoryKey.cache:
        return const Color(0xFFEF4444); // red
      case StorageUsageCategoryKey.logs:
        return const Color(0xFFEAB308); // yellow
      case StorageUsageCategoryKey.other:
        return cs.onSurface.withValues(alpha: 0.22);
    }
  }

  IconData _iconFor(StorageUsageCategoryKey key) {
    switch (key) {
      case StorageUsageCategoryKey.images:
        return Lucide.Image;
      case StorageUsageCategoryKey.files:
        return Lucide.Paperclip;
      case StorageUsageCategoryKey.chatData:
        return Lucide.MessagesSquare;
      case StorageUsageCategoryKey.assistantData:
        return Lucide.Bot;
      case StorageUsageCategoryKey.cache:
        return Lucide.Boxes;
      case StorageUsageCategoryKey.logs:
        return Lucide.FileText;
      case StorageUsageCategoryKey.other:
        return Lucide.Box;
    }
  }

  String _titleFor(StorageUsageCategoryKey key, AppLocalizations l10n) {
    switch (key) {
      case StorageUsageCategoryKey.images:
        return l10n.storageSpaceCategoryImages;
      case StorageUsageCategoryKey.files:
        return l10n.storageSpaceCategoryFiles;
      case StorageUsageCategoryKey.chatData:
        return l10n.storageSpaceCategoryChatData;
      case StorageUsageCategoryKey.assistantData:
        return l10n.storageSpaceCategoryAssistantData;
      case StorageUsageCategoryKey.cache:
        return l10n.storageSpaceCategoryCache;
      case StorageUsageCategoryKey.logs:
        return l10n.storageSpaceCategoryLogs;
      case StorageUsageCategoryKey.other:
        return l10n.storageSpaceCategoryOther;
    }
  }

  String _subTitleFor(String id, AppLocalizations l10n) {
    switch (id) {
      case 'messages':
        return l10n.storageSpaceSubChatMessages;
      case 'conversations':
        return l10n.storageSpaceSubChatConversations;
      case 'tool_events_v1':
        return l10n.storageSpaceSubChatToolEvents;
      case 'avatars':
        return l10n.storageSpaceSubAssistantAvatars;
      case 'images':
        return l10n.storageSpaceSubAssistantImages;
      case 'avatar_cache':
        return l10n.storageSpaceSubCacheAvatars;
      case 'other_cache':
        return l10n.storageSpaceSubCacheOther;
      case 'system_cache':
        return l10n.storageSpaceSubCacheSystem;
      case 'flutter_logs':
        return l10n.storageSpaceSubLogsFlutter;
      case 'request_logs':
        return l10n.storageSpaceSubLogsRequests;
      case 'other_logs':
        return l10n.storageSpaceSubLogsOther;
      default:
        return id;
    }
  }

  Future<bool> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return AppAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.homePageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  Future<void> _doClearCache({required bool avatarsOnly}) async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = avatarsOnly
        ? l10n.storageSpaceSubCacheAvatars
        : l10n.storageSpaceCategoryCache;
    final ok = await _confirmAction(
      context,
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearCache(avatarsOnly: avatarsOnly);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refreshReport();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _doClearOtherCache() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceSubCacheOther;
    final ok = await _confirmAction(
      context,
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearOtherCache();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refreshReport();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _doClearSystemCache() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceSubCacheSystem;
    final ok = await _confirmAction(
      context,
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearSystemCache();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refreshReport();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _doClearLogs() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryLogs;
    final ok = await _confirmAction(
      context,
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearLogs();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refreshReport();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _openCategoryDetail(StorageUsageCategoryKey key) async {
    final report = _report;
    if (report == null) return;
    final l10n = AppLocalizations.of(context)!;
    final title = _titleFor(key, l10n);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _StorageCategoryPage(
          title: title,
          categoryKey: key,
          initialReport: report,
          fmtBytes: _fmtBytes,
          subTitleFor: (id) => _subTitleFor(id, l10n),
          refreshReport: _refreshReport,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDesktop = PlatformUtils.isDesktopTarget;

    final body = _loading && _report == null
        ? const Center(child: CircularProgressIndicator())
        : _report == null
        ? Center(
            child: Text(
              l10n.storageSpaceLoadFailed,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
            ),
          )
        : isDesktop
        ? _buildDesktop(context, _report!)
        : _buildMobile(context, _report!);

    if (widget.embedded) {
      // Desktop pages in the main IndexedStack are not wrapped by Scaffold/AppBar.
      // Ensure a Material ancestor + correct background to avoid odd text artifacts
      // (e.g., yellow underlines) and unreadable contrast in light mode.
      if (isDesktop) {
        return Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: body,
        );
      }
      return body;
    }

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(l10n.storageSpacePageTitle),
      actions: [
        AppButtonIslandButton(
          icon: Lucide.RefreshCw,
          semanticLabel: l10n.storageSpaceRefreshTooltip,
          onTap: _loading ? null : _refreshReport,
        ),
      ],
      body: body,
    );
  }

  Widget _buildDesktop(BuildContext context, StorageUsageReport report) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final total = report.totalBytes;
    final clearable = report.clearable.bytes;
    final showTopBar = widget.embedded;

    StorageUsageCategory cat(StorageUsageCategoryKey k) =>
        report.categories.firstWhere((c) => c.key == k);

    final selectedCat = cat(_selected);

    final topBar = SizedBox(
      height: 36,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Text(
              l10n.storageSpacePageTitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: AppFontWeights.semibold,
                color: cs.onSurface,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 2),
            child: IosIconButton(
              icon: Lucide.RefreshCw,
              size: 18,
              enabled: !_loading,
              onTap: _loading ? null : _refreshReport,
              semanticLabel: l10n.storageSpaceRefreshTooltip,
            ),
          ),
        ],
      ),
    );

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${l10n.storageSpaceTotalLabel}: ${_fmtBytes(total)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.7),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (clearable > 0) ...[
                    const SizedBox(width: 12),
                    Text(
                      l10n.storageSpaceClearableLabel(_fmtBytes(clearable)),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurface.withValues(alpha: 0.7),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 280,
                      child: _CategoryMenu(
                        categories: report.categories,
                        selected: _selected,
                        iconFor: _iconFor,
                        titleFor: (k) => _titleFor(k, l10n),
                        fmtBytes: _fmtBytes,
                        onSelect: (k) => setState(() => _selected = k),
                      ),
                    ),
                    VerticalDivider(
                      width: 24,
                      color: cs.onSurface.withValues(alpha: 0.08),
                    ),
                    Expanded(
                      child: _CategoryDetail(
                        category: selectedCat,
                        title: _titleFor(selectedCat.key, l10n),
                        fmtBytes: _fmtBytes,
                        subTitleFor: (id) => _subTitleFor(id, l10n),
                        clearing: _clearing,
                        onClearCache: _clearing ? null : _doClearCache,
                        onClearOtherCache: _clearing
                            ? null
                            : _doClearOtherCache,
                        onClearSystemCache: _clearing
                            ? null
                            : _doClearSystemCache,
                        onClearLogs: _clearing ? null : _doClearLogs,
                        refreshReport: _refreshReport,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (showTopBar) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topBar,
          Expanded(child: content),
        ],
      );
    }

    return content;
  }

  Widget _buildMobile(BuildContext context, StorageUsageReport report) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final total = report.totalBytes;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.embedded ? 16 : AppScaffold.scrollContentTop(context),
        16,
        AppScaffold.scrollContentBottom(context),
      ),
      children: [
        _iosSectionCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.storageSpaceTotalLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _fmtBytes(total),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: AppFontWeights.emphasis,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 10),
                _UsageBar(
                  categories: report.categories,
                  totalBytes: total,
                  colorFor: (k) => _barColorFor(k, cs),
                ),
                const SizedBox(height: 10),
                _UsageLegend(
                  categories: report.categories,
                  colorFor: (k) => _barColorFor(k, cs),
                  titleFor: (k) => _titleFor(k, l10n),
                ),
                if (report.clearable.bytes > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.storageSpaceClearableHint(
                      _fmtBytes(report.clearable.bytes),
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _iosSectionCard(
          child: Column(
            children: [
              for (int i = 0; i < report.categories.length; i++) ...[
                _iosNavRow(
                  context,
                  icon: _iconFor(report.categories[i].key),
                  label: _titleFor(report.categories[i].key, l10n),
                  detailText:
                      '${_fmtBytes(report.categories[i].stats.bytes)} · ${l10n.storageSpaceFilesCount(report.categories[i].stats.fileCount)}',
                  onTap: () => _openCategoryDetail(report.categories[i].key),
                ),
                if (i != report.categories.length - 1) _iosDivider(context),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StorageCategoryPage extends StatefulWidget {
  const _StorageCategoryPage({
    required this.title,
    required this.categoryKey,
    required this.initialReport,
    required this.fmtBytes,
    required this.subTitleFor,
    required this.refreshReport,
  });

  final String title;
  final StorageUsageCategoryKey categoryKey;
  final StorageUsageReport initialReport;
  final String Function(int) fmtBytes;
  final String Function(String) subTitleFor;
  final Future<StorageUsageReport?> Function() refreshReport;

  @override
  State<_StorageCategoryPage> createState() => _StorageCategoryPageState();
}

class _StorageCategoryPageState extends State<_StorageCategoryPage> {
  late StorageUsageReport _report = widget.initialReport;
  bool _refreshing = false;
  bool _clearing = false;

  StorageUsageCategory _cat(StorageUsageCategoryKey k) =>
      _report.categories.firstWhere((c) => c.key == k);

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final next = await widget.refreshReport();
      if (!mounted) return;
      if (next != null) setState(() => _report = next);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    required String actionLabel,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return AppAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.homePageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  Future<void> _clearCache({required bool avatarsOnly}) async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = avatarsOnly
        ? l10n.storageSpaceSubCacheAvatars
        : l10n.storageSpaceCategoryCache;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearCache(avatarsOnly: avatarsOnly);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearOtherCache() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceSubCacheOther;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearOtherCache();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearSystemCache() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceSubCacheSystem;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearSystemCache();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _clearLogs() async {
    if (_clearing) return;
    final l10n = AppLocalizations.of(context)!;
    final targetName = l10n.storageSpaceCategoryLogs;
    final ok = await _confirmAction(
      title: l10n.storageSpaceClearConfirmTitle,
      message: l10n.storageSpaceClearConfirmMessage(targetName),
      actionLabel: l10n.storageSpaceClearButton,
    );
    if (!ok) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearLogs();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearDone(targetName),
        type: NotificationType.success,
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.storageSpaceClearFailed(e.toString()),
        type: NotificationType.error,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final category = _cat(widget.categoryKey);

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(widget.title),
      actions: [
        AppButtonIslandButton(
          icon: Lucide.RefreshCw,
          semanticLabel: l10n.storageSpaceRefreshTooltip,
          onTap: _refreshing ? null : _refresh,
        ),
      ],
      body: Builder(
        builder: (context) => _CategoryDetail(
          category: category,
          title: widget.title,
          fmtBytes: widget.fmtBytes,
          subTitleFor: widget.subTitleFor,
          clearing: _clearing,
          onClearCache: (category.key == StorageUsageCategoryKey.cache)
              ? _clearCache
              : null,
          onClearOtherCache: (category.key == StorageUsageCategoryKey.cache)
              ? _clearOtherCache
              : null,
          onClearSystemCache: (category.key == StorageUsageCategoryKey.cache)
              ? _clearSystemCache
              : null,
          onClearLogs: (category.key == StorageUsageCategoryKey.logs)
              ? _clearLogs
              : null,
          refreshReport: _refresh,
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.categories,
    required this.totalBytes,
    required this.colorFor,
  });

  final List<StorageUsageCategory> categories;
  final int totalBytes;
  final Color Function(StorageUsageCategoryKey) colorFor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = categories.where((c) => c.stats.bytes > 0).toList();
    if (items.isEmpty || totalBytes <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 12,
          color: cs.onSurface.withValues(alpha: 0.08),
        ),
      );
    }

    int flexFor(int bytes) {
      final f = ((bytes / totalBytes) * 1000).round();
      return f <= 0 ? 1 : f;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          for (final c in items)
            Expanded(
              flex: flexFor(c.stats.bytes),
              child: Container(height: 12, color: colorFor(c.key)),
            ),
        ],
      ),
    );
  }
}

class _UsageLegend extends StatelessWidget {
  const _UsageLegend({
    required this.categories,
    required this.colorFor,
    required this.titleFor,
  });

  final List<StorageUsageCategory> categories;
  final Color Function(StorageUsageCategoryKey) colorFor;
  final String Function(StorageUsageCategoryKey) titleFor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = categories.where((c) => c.stats.bytes > 0).toList();
    if (items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final c in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorFor(c.key),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                titleFor(c.key),
                style: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({
    required this.categories,
    required this.selected,
    required this.iconFor,
    required this.titleFor,
    required this.fmtBytes,
    required this.onSelect,
  });

  final List<StorageUsageCategory> categories;
  final StorageUsageCategoryKey selected;
  final IconData Function(StorageUsageCategoryKey) iconFor;
  final String Function(StorageUsageCategoryKey) titleFor;
  final String Function(int) fmtBytes;
  final ValueChanged<StorageUsageCategoryKey> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      children: [
        for (final c in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppListGroup(
              backgroundColor: c.key == selected
                  ? cs.onSurface.withValues(alpha: 0.06)
                  : cs.onSurface.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              child: IosCardPress(
                onTap: () => onSelect(c.key),
                haptics: false,
                pressedScale: 1.0,
                borderRadius: BorderRadius.circular(10),
                baseColor: c.key == selected
                    ? cs.onSurface.withValues(alpha: 0.06)
                    : cs.onSurface.withValues(alpha: 0.03),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      iconFor(c.key),
                      size: 18,
                      color: c.key == selected
                          ? cs.onSurface.withValues(alpha: 0.9)
                          : cs.onSurface.withValues(alpha: 0.82),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        titleFor(c.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: AppFontWeights.semibold,
                          color: c.key == selected
                              ? cs.onSurface.withValues(alpha: 0.92)
                              : cs.onSurface.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fmtBytes(c.stats.bytes),
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.65),
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

class _CategoryDetail extends StatelessWidget {
  const _CategoryDetail({
    required this.category,
    required this.title,
    required this.fmtBytes,
    required this.subTitleFor,
    required this.clearing,
    required this.onClearCache,
    required this.onClearOtherCache,
    required this.onClearSystemCache,
    required this.onClearLogs,
    required this.refreshReport,
  });

  final StorageUsageCategory category;
  final String title;
  final String Function(int) fmtBytes;
  final String Function(String) subTitleFor;
  final bool clearing;
  final Future<void> Function({required bool avatarsOnly})? onClearCache;
  final Future<void> Function()? onClearOtherCache;
  final Future<void> Function()? onClearSystemCache;
  final Future<void> Function()? onClearLogs;
  final Future<void> Function() refreshReport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final subtitle =
        '${fmtBytes(category.stats.bytes)} · ${l10n.storageSpaceFilesCount(category.stats.fileCount)}';
    final bool safeToClear =
        category.key == StorageUsageCategoryKey.cache ||
        category.key == StorageUsageCategoryKey.logs;
    final String hint = safeToClear
        ? l10n.storageSpaceSafeToClearHint
        : l10n.storageSpaceNotSafeToClearHint;

    Widget? actions;
    if (category.key == StorageUsageCategoryKey.cache) {
      actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          IosTileButton(
            label: l10n.storageSpaceClearAvatarCacheButton,
            icon: Lucide.User,
            backgroundColor: cs.primary,
            enabled: !clearing && onClearCache != null,
            onTap: () => onClearCache?.call(avatarsOnly: true),
          ),
          IosTileButton(
            label: l10n.storageSpaceClearCacheButton,
            icon: Lucide.Trash2,
            backgroundColor: cs.primary,
            enabled: !clearing && onClearCache != null,
            onTap: () => onClearCache?.call(avatarsOnly: false),
          ),
        ],
      );
    } else if (category.key == StorageUsageCategoryKey.logs) {
      actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          IosTileButton(
            label: l10n.storageSpaceViewLogsButton,
            icon: Lucide.Eye,
            backgroundColor: cs.primary,
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LogViewerPage()));
            },
          ),
          IosTileButton(
            label: l10n.storageSpaceClearLogsButton,
            icon: Lucide.Trash2,
            backgroundColor: cs.primary,
            enabled: !clearing && onClearLogs != null,
            onTap: () => onClearLogs?.call(),
          ),
        ],
      );
    }

    final pagePadding = AppScaffold.scrollPadding(context, EdgeInsets.zero);
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: AppFontWeights.emphasis),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12.5,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 14),
        if (actions != null) actions,
        if (actions != null) const SizedBox(height: 14),
      ],
    );
    if (category.key == StorageUsageCategoryKey.images ||
        category.key == StorageUsageCategoryKey.files) {
      final uploads = _UploadManager(
        key: ValueKey(category.key),
        images: category.key == StorageUsageCategoryKey.images,
        refreshReport: refreshReport,
        fmtBytes: fmtBytes,
        header: pagePadding.top > 0 ? header : null,
      );
      if (pagePadding.top > 0) return uploads;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Expanded(child: uploads),
        ],
      );
    }
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (category.subcategories.isNotEmpty) ...[
          Text(
            l10n.storageSpaceBreakdownTitle,
            style: TextStyle(fontSize: 13, fontWeight: AppFontWeights.emphasis),
          ),
          const SizedBox(height: 8),
          for (final s in category.subcategories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppListGroup(
                backgroundColor: cs.onSurface.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subTitleFor(s.id),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: AppFontWeights.semibold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${fmtBytes(s.stats.bytes)} · ${l10n.storageSpaceFilesCount(s.stats.fileCount)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          if (s.path != null && s.path!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              s.path!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: cs.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (category.key == StorageUsageCategoryKey.cache &&
                        s.id == 'avatar_cache')
                      _MiniActionButton(
                        label: l10n.storageSpaceClearButton,
                        enabled: !clearing,
                        onTap: () => onClearCache?.call(avatarsOnly: true),
                      ),
                    if (category.key == StorageUsageCategoryKey.cache &&
                        s.id == 'other_cache')
                      _MiniActionButton(
                        label: l10n.storageSpaceClearButton,
                        enabled: !clearing,
                        onTap: () => onClearOtherCache?.call(),
                      ),
                    if (category.key == StorageUsageCategoryKey.cache &&
                        s.id == 'system_cache')
                      _MiniActionButton(
                        label: l10n.storageSpaceClearButton,
                        enabled: !clearing,
                        onTap: () => onClearSystemCache?.call(),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
    if (pagePadding.top > 0) {
      return ListView(
        padding: pagePadding.copyWith(
          left: 16,
          right: 16,
          bottom: AppScaffold.scrollContentBottom(context),
        ),
        children: [header, details],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        Expanded(child: SingleChildScrollView(child: details)),
      ],
    );
  }
}

class _UploadManager extends StatefulWidget {
  const _UploadManager({
    super.key,
    this.header,
    required this.images,
    required this.refreshReport,
    required this.fmtBytes,
  });

  final Widget? header;
  final bool images;
  final Future<void> Function() refreshReport;
  final String Function(int) fmtBytes;

  @override
  State<_UploadManager> createState() => _UploadManagerState();
}

class _UploadManagerState extends State<_UploadManager> {
  bool _loading = false;
  List<StorageFileEntry> _entries = const <StorageFileEntry>[];
  final Set<String> _selected = <String>{};

  bool get _selectMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _UploadManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.images != widget.images) {
      // When switching between Images <-> Files on desktop, ensure we reload with the new filter.
      setState(() {
        _selected.clear();
        _entries = const <StorageFileEntry>[];
        _loading = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final list = await StorageUsageService.listUploadEntries(
        images: widget.images,
      );
      if (!mounted) return;
      setState(() {
        _entries = list;
        final paths = _entries.map((e) => e.path).toSet();
        _selected.removeWhere((p) => !paths.contains(p));
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(_entries.map((e) => e.path));
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final count = _selected.length;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return AppAlertDialog(
          title: Text(l10n.storageSpaceDeleteConfirmTitle),
          content: Text(l10n.storageSpaceDeleteUploadsConfirmMessage(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.homePageCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.homePageDelete),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    final deleted = await StorageUsageService.deleteUploadFiles(
      _selected,
      images: widget.images,
    );
    if (!mounted) return;

    _clearSelection();
    showAppSnackBar(
      context,
      message: l10n.storageSpaceDeletedUploadsDone(deleted),
      type: NotificationType.success,
    );
    await _load();
    await widget.refreshReport();
  }

  Future<void> _openImageViewer(String path) async {
    // ImageViewerPage only knows how to render images — hosted videos share
    // this grid but are excluded from its list, otherwise it'd try to
    // decode an mp4 as an image and fail.
    final imageEntries = _entries.where((e) => !e.isVideo).toList();
    final images = imageEntries.map((e) => e.path).toList(growable: false);
    final initialIndex = imageEntries.indexWhere((e) => e.path == path);
    if (initialIndex < 0) return;
    final route = PlatformUtils.isDesktopTarget
        ? PageRouteBuilder(
            pageBuilder: (_, __, ___) =>
                ImageViewerPage(images: images, initialIndex: initialIndex),
            transitionDuration: const Duration(milliseconds: 180),
            reverseTransitionDuration: const Duration(milliseconds: 160),
            transitionsBuilder: (ctx, anim, sec, child) {
              final curved = CurvedAnimation(
                parent: anim,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(opacity: curved, child: child);
            },
          )
        : MaterialPageRoute(
            builder: (_) =>
                ImageViewerPage(images: images, initialIndex: initialIndex),
          );
    await Navigator.of(context).push(route);
  }

  Future<void> _openFile(String path) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final res = await OpenFilex.open(path);
      if (res.type != ResultType.done) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: l10n.chatMessageWidgetCannotOpenFile(res.message),
          type: NotificationType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.chatMessageWidgetOpenFileError(e.toString()),
        type: NotificationType.error,
      );
    }
  }

  Widget _emptyState(BuildContext context, Widget child) {
    final header = widget.header;
    if (header == null) return Center(child: child);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: AppScaffold.scrollPadding(
            context,
            const EdgeInsets.fromLTRB(16, 12, 16, 16),
          ),
          sliver: SliverToBoxAdapter(child: header),
        ),
        SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    if (_loading && _entries.isEmpty) {
      return _emptyState(context, const CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return _emptyState(
        context,
        Text(
          l10n.storageSpaceNoUploads,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
        ),
      );
    }

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        IosTileButton(
          label: _selectMode
              ? l10n.storageSpaceClearSelection
              : l10n.storageSpaceSelectAll,
          icon: _selectMode ? Lucide.XCircle : Lucide.CheckSquare,
          backgroundColor: cs.primary,
          onTap: _selectMode ? _clearSelection : _selectAll,
        ),
        IosTileButton(
          label: l10n.homePageDelete,
          icon: Lucide.Trash2,
          backgroundColor: cs.error,
          enabled: _selected.isNotEmpty,
          onTap: _deleteSelected,
        ),
      ],
    );

    final header = widget.header;
    final slivers = <Widget>[
      if (header != null) SliverToBoxAdapter(child: header),
      if (header != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: actions,
          ),
        ),

      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _selectMode
                ? l10n.storageSpaceSelectedCount(_selected.length)
                : l10n.storageSpaceUploadsCount(_entries.length),
            style: TextStyle(
              fontSize: 12.5,
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
      if (widget.images)
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final e = _entries[index];
              final selected = _selected.contains(e.path);
              return _ImageTile(
                path: e.path,
                isVideo: e.isVideo,
                selected: selected,
                onToggle: () => _toggleSelect(e.path),
                onTap: () {
                  if (_selectMode) {
                    _toggleSelect(e.path);
                  } else if (e.isVideo) {
                    _openFile(e.path);
                  } else {
                    _openImageViewer(e.path);
                  }
                },
                onLongPress: () => _toggleSelect(e.path),
              );
            }, childCount: _entries.length),
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final e = _entries[index];
            final selected = _selected.contains(e.path);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FileRow(
                entry: e,
                selected: selected,
                fmtBytes: widget.fmtBytes,
                onTap: () {
                  if (_selectMode) {
                    _toggleSelect(e.path);
                  } else {
                    _openFile(e.path);
                  }
                },
                onLongPress: () => _toggleSelect(e.path),
                onToggle: () => _toggleSelect(e.path),
              ),
            );
          }, childCount: _entries.length),
        ),
    ];
    if (header != null) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AppScaffold.scrollPadding(
              context,
              const EdgeInsets.fromLTRB(16, 12, 16, 16),
            ),
            sliver: SliverMainAxisGroup(slivers: slivers),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        actions,
        const SizedBox(height: 12),
        Expanded(child: CustomScrollView(slivers: slivers)),
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.path,
    this.isVideo = false,
    required this.selected,
    required this.onToggle,
    required this.onTap,
    required this.onLongPress,
  });

  final String path;
  final bool isVideo;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cs = Theme.of(context).colorScheme;
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final side = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 140.0;
        final int cachePx = (side * dpr).clamp(64.0, 1024.0).round();

        return AppListGroup(
          backgroundColor: cs.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          outlineColor: selected ? cs.primary.withValues(alpha: 0.55) : null,
          clipBehavior: Clip.antiAlias,
          child: IosCardPress(
            onTap: onTap,
            onLongPress: onLongPress,
            haptics: false,
            pressedScale: 1.0,
            borderRadius: BorderRadius.circular(12),
            baseColor: cs.onSurface.withValues(alpha: 0.03),
            padding: EdgeInsets.zero,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isVideo)
                  Container(
                    color: Colors.black.withValues(alpha: 0.82),
                    alignment: Alignment.center,
                    child: Icon(
                      Lucide.Play,
                      size: 28,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  )
                else
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: cachePx,
                    cacheHeight: cachePx,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        color: cs.onSurface.withValues(alpha: 0.04),
                        alignment: Alignment.center,
                        child: Icon(
                          Lucide.ImageOff,
                          size: 18,
                          color: cs.onSurface.withValues(alpha: 0.55),
                        ),
                      );
                    },
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: IosCheckbox(
                    value: selected,
                    size: 20,
                    hitTestSize: 22,
                    borderWidth: 1.6,
                    activeColor: cs.primary,
                    borderColor: cs.primary.withValues(alpha: 0.55),
                    onChanged: (_) => onToggle(),
                    enableHaptics: false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.entry,
    required this.selected,
    required this.fmtBytes,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });

  final StorageFileEntry entry;
  final bool selected;
  final String Function(int) fmtBytes;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AppListGroup(
      backgroundColor: cs.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: IosCardPress(
        onTap: onTap,
        onLongPress: onLongPress,
        haptics: false,
        pressedScale: 1.0,
        borderRadius: BorderRadius.circular(12),
        baseColor: cs.onSurface.withValues(alpha: 0.03),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            IosCheckbox(
              value: selected,
              size: 20,
              hitTestSize: 22,
              borderWidth: 1.6,
              activeColor: cs.primary,
              borderColor: cs.primary.withValues(alpha: 0.55),
              onChanged: (_) => onToggle(),
              enableHaptics: false,
            ),
            const SizedBox(width: 10),
            Icon(
              Lucide.Paperclip,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.82),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: AppFontWeights.semibold,
                      color: cs.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${fmtBytes(entry.bytes)} · ${_fmtTime(entry.modifiedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color fg = enabled
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.35);
    final Color bg = enabled
        ? cs.primary.withValues(alpha: 0.12)
        : cs.onSurface.withValues(alpha: 0.03);
    final Color border = enabled
        ? cs.primary.withValues(alpha: 0.35)
        : cs.onSurface.withValues(alpha: 0.10);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: AppFontWeights.semibold,
            color: fg,
          ),
        ),
      ),
    );
  }
}

Widget _iosSectionCard({required Widget child}) {
  return AppListGroup(child: child);
}

Widget _iosDivider(BuildContext context) {
  return AppListDivider(indent: 54, endIndent: 12, height: 1, thickness: 1);
}

Widget _iosNavRow(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String detailText,
  required VoidCallback onTap,
}) {
  return AppSettingsNavTile(
    icon: icon,
    label: label,
    onTap: onTap,
    detailText: detailText,
  );
}
