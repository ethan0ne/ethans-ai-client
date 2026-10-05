import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';
import 'package:Kelivo/shared/widgets/popup_content_frame.dart';
import 'package:Kelivo/shared/widgets/app_dialog.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:Kelivo/shared/widgets/app_list_group.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/world_book.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../assistant/utils/assistant_prompt_asset_sync.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_form_text_field.dart';
import '../../../shared/widgets/app_switch.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/app_font_weights.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/frosted_popup_menu.dart';

class WorldBookPage extends StatefulWidget {
  const WorldBookPage({
    super.key,
    required this.assistantId,
    this.embedded = false,
  });

  final String assistantId;
  final bool embedded;

  @override
  State<WorldBookPage> createState() => _WorldBookPageState();
}

class _WorldBookPageState extends State<WorldBookPage> {
  final Set<String> _collapsedBooks = <String>{};

  Future<void> _saveBooks(List<WorldBook> books) async {
    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    final enabledIds = books
        .where((book) => book.enabled)
        .map((book) => book.id)
        .toSet();
    await saveAssistantPromptAssets(
      context,
      assistant.copyWith(
        worldBooks: books,
        activeWorldBookIds: assistant.activeWorldBookIds
            .where(enabledIds.contains)
            .toList(),
      ),
    );
  }

  Future<void> _replaceBook(WorldBook updated) async {
    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    final books = [...assistant.worldBooks];
    final index = books.indexWhere((book) => book.id == updated.id);
    if (index < 0) return;
    books[index] = updated;
    await _saveBooks(books);
  }

  Future<WorldBook?> _showBookConfigSheet({WorldBook? book}) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final editorKey = GlobalKey<_WorldBookEditSheetState>();
    return showAppPopupSheet<WorldBook>(
      context: context,
      title: book == null ? l10n.worldBookAdd : l10n.worldBookConfig,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.worldBookSave,
          onTap: () => editorKey.currentState?._submit(),
        ),
      ],
      isScrollControlled: true,
      extendBodyBehindHeader: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => _WorldBookEditSheet(key: editorKey, book: book),
    );
  }

  Future<WorldBookEntry?> _showEntryEditSheet({WorldBookEntry? entry}) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final editorKey = GlobalKey<_WorldBookEntryEditSheetState>();
    return showAppPopupSheet<WorldBookEntry>(
      context: context,
      title: entry == null ? l10n.worldBookAddEntry : l10n.worldBookEditEntry,
      actions: [
        appPopupDoneAction(
          semanticLabel: l10n.worldBookSave,
          onTap: () => editorKey.currentState?._submit(),
        ),
      ],
      isScrollControlled: true,
      extendBodyBehindHeader: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) =>
          _WorldBookEntryEditSheet(key: editorKey, entry: entry),
    );
  }

  Future<String?> _readPickedFileAsString(PlatformFile file) async {
    try {
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        return utf8.decode(file.bytes!, allowMalformed: true);
      }
    } catch (_) {}
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    try {
      return await File(path).readAsString();
    } catch (_) {
      try {
        final bytes = await File(path).readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
  }

  WorldBook? _parseWorldBookImport(dynamic decoded) {
    try {
      if (decoded is Map) {
        final map = decoded.cast<String, dynamic>();
        final data = map['data'];
        if (data is Map) {
          return WorldBook.fromJson(data.cast<String, dynamic>());
        }
        if (map.containsKey('entries')) {
          return WorldBook.fromJson(map);
        }
      }
    } catch (_) {}
    return null;
  }

  WorldBook _normalizeImportedBook(
    WorldBook book, {
    required Set<String> existingBookIds,
  }) {
    var bookId = book.id.trim();
    if (bookId.isEmpty || existingBookIds.contains(bookId)) {
      bookId = const Uuid().v4();
    }

    final seenEntryIds = <String>{};
    final nextEntries = <WorldBookEntry>[];
    for (final entry in book.entries) {
      var entryId = entry.id.trim();
      if (entryId.isEmpty || !seenEntryIds.add(entryId)) {
        entryId = const Uuid().v4();
      }
      nextEntries.add(entry.copyWith(id: entryId));
    }

    return book.copyWith(id: bookId, entries: nextEntries);
  }

  Future<void> _importBookFromFile() async {
    final l10n = AppLocalizations.of(context)!;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } catch (_) {
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final content = await _readPickedFileAsString(file);
    if (!mounted) return;
    if (content == null || content.trim().isEmpty) {
      showAppSnackBar(
        context,
        message: l10n.assistantEditSystemPromptImportEmpty,
        type: NotificationType.warning,
      );
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      showAppSnackBar(
        context,
        message: l10n.mcpJsonEditParseFailed,
        type: NotificationType.error,
      );
      return;
    }

    final imported = _parseWorldBookImport(decoded);
    if (imported == null) {
      showAppSnackBar(
        context,
        message: l10n.assistantEditSystemPromptImportFailed,
        type: NotificationType.error,
      );
      return;
    }

    final assistant = context.read<AssistantProvider>().getById(
      widget.assistantId,
    );
    if (assistant == null) return;
    final normalized = _normalizeImportedBook(
      imported,
      existingBookIds: assistant.worldBooks.map((e) => e.id).toSet(),
    );
    await _saveBooks([...assistant.worldBooks, normalized]);
  }

  String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.isEmpty) return path;
    return parts.last.isEmpty ? path : parts.last;
  }

  Future<void> _exportBook(WorldBook book) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final fileName = _safeFileName(
        book.name.trim().isEmpty ? 'lorebook' : book.name.trim(),
      );
      final exportName = '$fileName.json';
      final json = jsonEncode(_toRikkaHubExportJson(book));

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final String? savePath = await FilePicker.platform.saveFile(
          dialogTitle: l10n.backupPageExportToFile,
          fileName: exportName,
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (savePath == null) return;

        await File(savePath).parent.create(recursive: true);
        await File(savePath).writeAsString(json);
        if (!mounted) return;
        showAppSnackBar(
          context,
          message: l10n.messageExportSheetExportedAs(_baseName(savePath)),
          type: NotificationType.success,
        );
        return;
      }

      final bytes = Uint8List.fromList(utf8.encode(json));
      final String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: l10n.backupPageExportToFile,
        fileName: exportName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (savePath == null) return;
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.messageExportSheetExportedAs(_baseName(savePath)),
        type: NotificationType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: l10n.worldBookExportFailed(e.toString()),
        type: NotificationType.error,
      );
    }
  }

  Map<String, dynamic> _toRikkaHubExportJson(WorldBook book) {
    final data = <String, dynamic>{
      'id': book.id,
      'name': book.name,
      'description': book.description,
      'enabled': book.enabled,
      'entries': book.entries
          .map(
            (e) => <String, dynamic>{
              'id': e.id,
              'name': e.name,
              'enabled': e.enabled,
              'priority': e.priority,
              'position': e.position.toJson(),
              'content': e.content,
              'injectDepth': e.injectDepth,
              'role': e.role.toJson(),
              'keywords': e.keywords,
              'useRegex': e.useRegex,
              'caseSensitive': e.caseSensitive,
              'scanDepth': e.scanDepth,
              'constantActive': e.constantActive,
            },
          )
          .toList(growable: false),
    };
    return <String, dynamic>{'version': 1, 'type': 'lorebook', 'data': data};
  }

  String _safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'lorebook';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }

  Future<bool> _confirmDeleteBook(WorldBook book) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        return AppAlertDialog(
          title: Text(l10n.worldBookDeleteTitle),
          content: Text(
            l10n.worldBookDeleteMessage(
              book.name.trim().isEmpty
                  ? l10n.worldBookUnnamed
                  : book.name.trim(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.worldBookCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10n.worldBookDelete,
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDesktop =
        Theme.of(context).platform == TargetPlatform.macOS ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux;

    final assistant = context.watch<AssistantProvider>().getById(
      widget.assistantId,
    );
    final books = assistant?.worldBooks ?? const <WorldBook>[];

    final inPage = AppScaffold.scrollPadding(context, EdgeInsets.zero).top > 0;
    final embeddedActions = Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Tooltip(
            message: l10n.providersPageImportTooltip,
            child: IosIconButton(
              icon: Lucide.cloudDownload,
              minSize: 44,
              size: 22,
              onTap: () async {
                Haptics.light();
                await _importBookFromFile();
              },
            ),
          ),
          Tooltip(
            message: l10n.worldBookAdd,
            child: IosIconButton(
              icon: Lucide.Plus,
              minSize: 44,
              size: 22,
              onTap: () async {
                Haptics.light();
                final assistantProvider = context.read<AssistantProvider>();
                final result = await _showBookConfigSheet();
                if (!mounted || result == null) return;
                final current = assistantProvider.getById(widget.assistantId);
                if (current != null) {
                  await _saveBooks([...current.worldBooks, result]);
                }
              },
            ),
          ),
        ],
      ),
    );
    final body = books.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Lucide.BookOpen,
                  size: 64,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.embedded
                      ? l10n.assistantEditWorldBookEmptyDescription
                      : l10n.worldBookEmptyMessage,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          )
        : ReorderableListView.builder(
            header: widget.embedded && inPage ? embeddedActions : null,
            padding: EdgeInsets.fromLTRB(
              16,
              widget.embedded
                  ? AppScaffold.scrollPadding(
                      context,
                      const EdgeInsets.all(16),
                    ).top
                  : AppScaffold.scrollContentTop(context),
              16,
              AppScaffold.scrollContentBottom(context),
            ),
            itemCount: books.length,
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) {
              // No elevation/shadow; just subtle scale.
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = Curves.easeOutCubic.transform(animation.value);
                  return Transform.scale(
                    scale: 0.985 + 0.015 * t,
                    child: child,
                  );
                },
              );
            },
            onReorderItem: (oldIndex, newIndex) async {
              Haptics.light();
              final current = context.read<AssistantProvider>().getById(
                widget.assistantId,
              );
              if (current == null) return;
              final reordered = [...current.worldBooks];
              final moved = reordered.removeAt(oldIndex);
              final insertionIndex = newIndex > oldIndex
                  ? newIndex - 1
                  : newIndex;
              reordered.insert(insertionIndex, moved);
              await _saveBooks(reordered);
            },
            itemBuilder: (context, index) {
              final book = books[index];

              return KeyedSubtree(
                key: ValueKey('world-book-${book.id}'),
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: index == books.length - 1 ? 0 : 14,
                  ),
                  child: _WorldBookSection(
                    book: book,
                    bookIndex: index,
                    canReorderBooks: books.length > 1,
                    collapsed: _collapsedBooks.contains(book.id),
                    onToggleCollapsed: () {
                      Haptics.light();
                      setState(() {
                        if (!_collapsedBooks.add(book.id)) {
                          _collapsedBooks.remove(book.id);
                        }
                      });
                    },
                    onAddEntry: () async {
                      Haptics.light();
                      final edited = await _showEntryEditSheet();
                      if (edited == null) return;
                      final next = book.copyWith(
                        entries: [...book.entries, edited],
                      );
                      await _replaceBook(next);
                    },
                    onExport: () async {
                      Haptics.light();
                      await _exportBook(book);
                    },
                    onConfig: () async {
                      Haptics.light();
                      final updated = await _showBookConfigSheet(book: book);
                      if (updated == null) return;
                      await _replaceBook(updated);
                    },
                    onDelete: () async {
                      Haptics.light();
                      final assistantProvider = context
                          .read<AssistantProvider>();
                      final confirm = await _confirmDeleteBook(book);
                      if (!mounted || !confirm) return;
                      final current = assistantProvider.getById(
                        widget.assistantId,
                      );
                      if (current == null) return;
                      await _saveBooks(
                        current.worldBooks
                            .where((candidate) => candidate.id != book.id)
                            .toList(),
                      );
                    },
                    onEditEntry: (entry) async {
                      Haptics.light();
                      final edited = await _showEntryEditSheet(entry: entry);
                      if (edited == null) return;
                      final nextEntries = book.entries
                          .map((e) => e.id == entry.id ? edited : e)
                          .toList(growable: false);
                      await _replaceBook(book.copyWith(entries: nextEntries));
                    },
                    onDeleteEntry: (entry) async {
                      Haptics.light();
                      final nextEntries = book.entries
                          .where((e) => e.id != entry.id)
                          .toList(growable: false);
                      await _replaceBook(book.copyWith(entries: nextEntries));
                    },
                    onReorderEntries: (oldEntryIndex, newEntryIndex) async {
                      if (newEntryIndex > oldEntryIndex) newEntryIndex -= 1;
                      Haptics.light();
                      final current = context.read<AssistantProvider>().getById(
                        widget.assistantId,
                      );
                      final matches =
                          current?.worldBooks
                              .where((candidate) => candidate.id == book.id)
                              .toList() ??
                          const <WorldBook>[];
                      final currentBook = matches.isEmpty
                          ? null
                          : matches.first;
                      if (currentBook == null) return;
                      final entries = [...currentBook.entries];
                      final moved = entries.removeAt(oldEntryIndex);
                      entries.insert(newEntryIndex, moved);
                      await _replaceBook(
                        currentBook.copyWith(entries: entries),
                      );
                    },
                    isDesktop: isDesktop,
                  ),
                ),
              );
            },
          );

    if (!widget.embedded) {
      return AppScaffold(
        backgroundColor: cs.surface,
        leadingIslands: [
          [
            AppButtonIslandButton(
              icon: Lucide.ArrowLeft,
              semanticLabel: l10n.settingsPageBackButton,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        ],
        title: AppScaffoldTitle(l10n.worldBookTitle),
        actions: [
          AppButtonIslandButton(
            icon: Lucide.cloudDownload,
            semanticLabel: l10n.providersPageImportTooltip,
            onTap: () async {
              Haptics.light();
              await _importBookFromFile();
            },
          ),
          AppButtonIslandButton(
            icon: Lucide.Plus,
            semanticLabel: l10n.worldBookAdd,
            onTap: () async {
              Haptics.light();
              final assistantProvider = context.read<AssistantProvider>();
              final result = await _showBookConfigSheet();
              if (!mounted || result == null) return;
              final current = assistantProvider.getById(widget.assistantId);
              if (current != null) {
                await _saveBooks([...current.worldBooks, result]);
              }
            },
          ),
        ],
        body: body,
      );
    }
    if (inPage) {
      if (books.isNotEmpty) return body;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: AppScaffold.scrollPadding(
              context,
              const EdgeInsets.all(16),
            ),
            sliver: SliverToBoxAdapter(child: embeddedActions),
          ),
          SliverFillRemaining(hasScrollBody: false, child: body),
        ],
      );
    }
    return Column(
      children: [
        embeddedActions,
        Expanded(child: body),
      ],
    );
  }
}

class _WorldBookSection extends StatelessWidget {
  const _WorldBookSection({
    required this.book,
    required this.bookIndex,
    required this.canReorderBooks,
    required this.isDesktop,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onAddEntry,
    required this.onExport,
    required this.onConfig,
    required this.onDelete,
    required this.onEditEntry,
    required this.onDeleteEntry,
    required this.onReorderEntries,
  });

  final WorldBook book;
  final int bookIndex;
  final bool canReorderBooks;
  final bool isDesktop;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onAddEntry;
  final VoidCallback onExport;
  final VoidCallback onConfig;
  final VoidCallback onDelete;
  final Future<void> Function(WorldBookEntry entry) onEditEntry;
  final Future<void> Function(WorldBookEntry entry) onDeleteEntry;
  final Future<void> Function(int oldIndex, int newIndex) onReorderEntries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    final title = book.name.trim().isEmpty
        ? l10n.worldBookUnnamed
        : book.name.trim();
    final subtitle = book.description.trim();
    final entries = book.entries;

    Future<void> showEntryActions(WorldBookEntry entry) async {
      var result = _EntryAction.cancel;
      await showFrostedPopupMenuAt(
        context,
        globalPosition: popupMenuAnchorForContext(context),
        title: entry.name.trim().isEmpty
            ? l10n.worldBookUnnamedEntry
            : entry.name.trim(),
        items: [
          FrostedPopupMenuItem(
            icon: Lucide.Settings2,
            label: l10n.worldBookEditEntry,
            onPressed: () => result = _EntryAction.edit,
          ),
          FrostedPopupMenuItem(
            icon: Lucide.Trash2,
            label: l10n.worldBookDeleteEntry,
            destructive: true,
            onPressed: () => result = _EntryAction.delete,
          ),
        ],
      );

      if (result == _EntryAction.cancel) return;
      if (result == _EntryAction.edit) {
        await onEditEntry(entry);
      } else if (result == _EntryAction.delete) {
        await onDeleteEntry(entry);
      }
    }

    Widget wrapBookReorder(Widget child) {
      if (!canReorderBooks) return child;
      final wrapped = isDesktop
          ? ReorderableDragStartListener(index: bookIndex, child: child)
          : ReorderableDelayedDragStartListener(index: bookIndex, child: child);
      return isDesktop
          ? MouseRegion(cursor: SystemMouseCursors.grab, child: wrapped)
          : wrapped;
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: wrapBookReorder(
              IosCardPress(
                baseColor: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                pressedBlendStrength: 0.04,
                pressedScale: 1.0,
                haptics: false,
                onTap: onToggleCollapsed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: collapsed ? 0.0 : 0.25,
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Lucide.ChevronRight,
                          size: 16,
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: AppFontWeights.emphasis,
                                    ),
                                  ),
                                ),
                                if (!book.enabled) ...[
                                  const SizedBox(width: 8),
                                  _TagPill(
                                    text: l10n.worldBookDisabledTag,
                                    color: cs.error,
                                  ),
                                ],
                              ],
                            ),
                            if (subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _HeaderIconButton(
            icon: Lucide.Plus,
            tooltip: l10n.worldBookAddEntry,
            onTap: onAddEntry,
          ),
          _HeaderIconButton(
            icon: Lucide.Share2,
            tooltip: l10n.worldBookExport,
            onTap: onExport,
          ),
          _HeaderIconButton(
            icon: Lucide.Settings2,
            tooltip: l10n.worldBookConfig,
            onTap: onConfig,
          ),
          _HeaderIconButton(
            icon: Lucide.Trash2,
            tooltip: l10n.worldBookDelete,
            onTap: onDelete,
            color: cs.error,
          ),
        ],
      ),
    );

    final children = <Widget>[];
    if (entries.isEmpty) {
      children.add(
        _IosEntryRow(icon: Lucide.ListTree, label: l10n.worldBookNoEntriesHint),
      );
    } else {
      children.add(
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: entries.length,
          buildDefaultDragHandles: false,
          proxyDecorator: (child, index, animation) {
            // No shadow; slight scale and higher opacity.
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(animation.value);
                return Opacity(
                  opacity: 0.98,
                  child: Transform.scale(
                    scale: 0.992 + 0.008 * t,
                    child: child,
                  ),
                );
              },
            );
          },
          onReorderItem: (oldIndex, newIndex) async {
            await onReorderEntries(oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final entry = entries[index];
            final entryTitle = entry.name.trim().isEmpty
                ? l10n.worldBookUnnamedEntry
                : entry.name.trim();
            final detail = !entry.enabled
                ? l10n.worldBookDisabledTag
                : (entry.constantActive ? l10n.worldBookAlwaysOnTag : null);
            final canReorder = entries.length > 1;

            final row = _IosEntryRow(
              label: entryTitle,
              detailText: detail,
              enabled: entry.enabled,
              icon: Lucide.Bookmark,
              onTap: () => onEditEntry(entry),
              onLongPress: () => showEntryActions(entry),
              leadingBuilder: (color) {
                final icon = Icon(Lucide.Bookmark, size: 20, color: color);
                if (!canReorder) return icon;
                final handle = isDesktop
                    ? ReorderableDragStartListener(index: index, child: icon)
                    : ReorderableDelayedDragStartListener(
                        index: index,
                        child: icon,
                      );
                return isDesktop
                    ? MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: handle,
                      )
                    : handle;
              },
            );

            return KeyedSubtree(
              key: ValueKey('world-book-entry-${book.id}-${entry.id}'),
              child: Column(
                children: [
                  row,
                  if (index != entries.length - 1) _iosDivider(context),
                ],
              ),
            );
          },
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity, height: 0)
              : SizedBox(
                  width: double.infinity,
                  child: _IosSectionCard(children: children),
                ),
        ),
      ],
    );
  }
}

enum _EntryAction { edit, delete, cancel }

class _IosEntryRow extends StatelessWidget {
  const _IosEntryRow({
    required this.icon,
    required this.label,
    this.detailText,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.leadingBuilder,
  });

  final IconData icon;
  final String label;
  final String? detailText;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget Function(Color color)? leadingBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final opacity = enabled ? 1.0 : 0.55;
    final baseColor = cs.onSurface.withValues(alpha: 0.9 * opacity);
    final interactive = onTap != null || onLongPress != null;
    final leading = leadingBuilder == null
        ? Icon(icon, size: 20, color: baseColor)
        : leadingBuilder!(baseColor);

    return AppListTile(
      onTapFeedback: interactive ? Haptics.light : null,
      onLongPressFeedback: interactive ? Haptics.light : null,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: SizedBox(width: 36, child: leading),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color: baseColor,
          fontWeight: FontWeight.w400,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (detailText != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                detailText!,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.6 * opacity),
                ),
              ),
            ),
          if (onTap != null)
            Icon(Lucide.ChevronRight, size: 16, color: baseColor),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minLeadingWidth: 36,
      horizontalTitleGap: 12,
      minVerticalPadding: 11,
    );
  }
}

class _IosSectionCard extends StatelessWidget {
  const _IosSectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppListGroup.list(children: children);
  }
}

Widget _iosDivider(BuildContext context) {
  return const AppListDivider(indent: 60, endIndent: 12);
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IosIconButton(
        icon: icon,
        size: 18,
        padding: const EdgeInsets.all(8),
        color: color ?? cs.onSurface.withValues(alpha: 0.9),
        onTap: onTap,
      ),
    );
  }
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color.withValues(alpha: 0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: AppFontWeights.emphasis,
          color: cs.onSurface,
        ),
      ),
    );
  }
}

class _WorldBookEditSheet extends StatefulWidget {
  const _WorldBookEditSheet({super.key, required this.book});
  final WorldBook? book;

  @override
  State<_WorldBookEditSheet> createState() => _WorldBookEditSheetState();
}

class _WorldBookEditSheetState extends State<_WorldBookEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  bool _enabled = true;

  void _submit() {
    final base = widget.book;
    Navigator.of(context).pop(
      WorldBook(
        id: base?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        enabled: _enabled,
        entries: base?.entries ?? const <WorldBookEntry>[],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.book?.name ?? '');
    _descController = TextEditingController(
      text: widget.book?.description ?? '',
    );
    _enabled = widget.book?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final base = widget.book;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: ValueKey(PopupContentSurfaceScope.isDialogOf(context)),
        primary: !PopupContentSurfaceScope.isDialogOf(context),
        padding: PopupContentFrame.scrollPadding(
          context,
          EdgeInsets.fromLTRB(
            16,
            12,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
        ),
        child: Column(
          children: [
            AppListGroup.list(
              children: [
                AppListTile(
                  leading: const Icon(Icons.title_rounded, size: 20),
                  title: AppTextField(
                    controller: _nameController,
                    autofocus: base == null,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.worldBookNameLabel,
                      border: InputBorder.none,
                    ),
                  ),
                  minVerticalPadding: 8,
                  minLeadingWidth: 24,
                  horizontalTitleGap: 12,
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppListGroup.list(
              children: [
                AppListTile(
                  title: AppTextField(
                    controller: _descController,
                    minLines: 5,
                    // The form owns vertical scrolling, including drags that
                    // begin over this field. Grow the editor with its text.
                    maxLines: null,
                    scrollPhysics: const NeverScrollableScrollPhysics(),
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: l10n.worldBookDescriptionLabel,
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                  minVerticalPadding: 12,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppListGroup.list(
              children: [
                AppListTile(
                  onTap: () => setState(() => _enabled = !_enabled),
                  title: Text(l10n.worldBookEnabledLabel),
                  trailing: AppSwitch(
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                  minVerticalPadding: 8,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorldBookEntryEditSheet extends StatefulWidget {
  const _WorldBookEntryEditSheet({super.key, required this.entry});
  final WorldBookEntry? entry;

  @override
  State<_WorldBookEntryEditSheet> createState() =>
      _WorldBookEntryEditSheetState();
}

class _WorldBookEntryEditSheetState extends State<_WorldBookEntryEditSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _keywordInputController;
  late final TextEditingController _contentController;
  late final TextEditingController _priorityController;
  late final TextEditingController _scanDepthController;
  late final TextEditingController _injectDepthController;
  List<String> _keywords = <String>[];

  bool _enabled = true;
  bool _useRegex = false;
  bool _caseSensitive = false;
  bool _constantActive = false;
  late WorldBookInjectionPosition _position;
  late WorldBookInjectionRole _role;

  bool get _canSave => _constantActive || _keywords.isNotEmpty;

  void _submit() {
    if (!_canSave) return;
    final base = widget.entry;
    final priority =
        int.tryParse(_priorityController.text.trim()) ?? (base?.priority ?? 0);
    final scanDepth =
        int.tryParse(_scanDepthController.text.trim()) ??
        (base?.scanDepth ?? 4);
    final injectDepth =
        int.tryParse(_injectDepthController.text.trim()) ??
        (base?.injectDepth ?? 4);
    Navigator.of(context).pop(
      WorldBookEntry(
        id: base?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        enabled: _enabled,
        priority: priority,
        position: _position,
        content: _contentController.text,
        injectDepth: injectDepth.clamp(1, 200).toInt(),
        role: _role,
        keywords: List<String>.from(_keywords),
        useRegex: _useRegex,
        caseSensitive: _caseSensitive,
        scanDepth: scanDepth.clamp(1, 200).toInt(),
        constantActive: _constantActive,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _nameController = TextEditingController(text: entry?.name ?? '');
    _keywordInputController = TextEditingController();
    _contentController = TextEditingController(text: entry?.content ?? '');
    _priorityController = TextEditingController(
      text: (entry?.priority ?? 0).toString(),
    );
    _scanDepthController = TextEditingController(
      text: (entry?.scanDepth ?? 4).toString(),
    );
    _injectDepthController = TextEditingController(
      text: (entry?.injectDepth ?? 4).toString(),
    );
    _enabled = entry?.enabled ?? true;
    _useRegex = entry?.useRegex ?? false;
    _caseSensitive = entry?.caseSensitive ?? false;
    _constantActive = entry?.constantActive ?? false;
    _keywords = _cleanKeywords(entry?.keywords ?? const <String>[]);
    _position = entry?.position ?? WorldBookInjectionPosition.afterSystemPrompt;
    _role = entry?.role ?? WorldBookInjectionRole.user;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keywordInputController.dispose();
    _contentController.dispose();
    _priorityController.dispose();
    _scanDepthController.dispose();
    _injectDepthController.dispose();
    super.dispose();
  }

  List<String> _cleanKeywords(Iterable<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      final k = item.trim();
      if (k.isEmpty) continue;
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  List<String> _parseKeywordInput(String raw) {
    final k = raw.trim();
    if (k.isEmpty) return const <String>[];
    return <String>[k];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final base = widget.entry;

    String positionLabel(WorldBookInjectionPosition p) {
      return switch (p) {
        WorldBookInjectionPosition.beforeSystemPrompt =>
          l10n.worldBookInjectionPositionBeforeSystemPrompt,
        WorldBookInjectionPosition.afterSystemPrompt =>
          l10n.worldBookInjectionPositionAfterSystemPrompt,
        WorldBookInjectionPosition.topOfChat =>
          l10n.worldBookInjectionPositionTopOfChat,
        WorldBookInjectionPosition.bottomOfChat =>
          l10n.worldBookInjectionPositionBottomOfChat,
        WorldBookInjectionPosition.atDepth =>
          l10n.worldBookInjectionPositionAtDepth,
      };
    }

    String roleLabel(WorldBookInjectionRole r) {
      return switch (r) {
        WorldBookInjectionRole.user => l10n.worldBookInjectionRoleUser,
        WorldBookInjectionRole.assistant =>
          l10n.worldBookInjectionRoleAssistant,
      };
    }

    void addKeywordsFromInput() {
      final parts = _parseKeywordInput(_keywordInputController.text);
      if (parts.isEmpty) return;
      setState(() {
        for (final k in parts) {
          if (_keywords.contains(k)) continue;
          _keywords.add(k);
        }
      });
      _keywordInputController.clear();
    }

    Widget switchRow({
      required String label,
      String? hint,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return IosCardPress(
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.zero,
        pressedBlendStrength: 0,
        pressedScale: 1.0,
        haptics: false,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: AppFontWeights.semibold,
                        color: cs.onSurface.withValues(alpha: 0.9),
                      ),
                    ),
                    if (hint != null && hint.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurface.withValues(alpha: 0.6),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AppSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      );
    }

    Widget valueRow({
      required String label,
      required String valueText,
      required VoidCallback onTap,
    }) {
      return IosCardPress(
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.zero,
        pressedBlendStrength: 0,
        pressedScale: 1.0,
        haptics: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: AppFontWeights.medium,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Lucide.ChevronRight,
                size: 16,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      );
    }

    Widget keywordChip(String keyword) {
      final color = cs.primary;
      final bg = color.withValues(alpha: isDark ? 0.22 : 0.12);
      final border = color.withValues(alpha: isDark ? 0.36 : 0.26);
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border, width: 0.6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 10,
                  right: 6,
                  top: 6,
                  bottom: 6,
                ),
                child: Text(
                  keyword,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: AppFontWeights.semibold,
                    color: cs.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            IosIconButton(
              icon: Lucide.X,
              size: 14,
              padding: const EdgeInsets.all(6),
              color: cs.onSurface.withValues(alpha: 0.65),
              onTap: () => setState(() => _keywords.remove(keyword)),
            ),
            const SizedBox(width: 2),
          ],
        ),
      );
    }

    Future<void> pickPosition() async {
      final options = <WorldBookInjectionPosition>[
        WorldBookInjectionPosition.beforeSystemPrompt,
        WorldBookInjectionPosition.afterSystemPrompt,
        WorldBookInjectionPosition.topOfChat,
        WorldBookInjectionPosition.bottomOfChat,
        WorldBookInjectionPosition.atDepth,
      ];
      WorldBookInjectionPosition? selected;
      await showFrostedPopupMenuAt(
        context,
        globalPosition: popupMenuAnchorForContext(context),
        title: l10n.worldBookEntryInjectionPositionLabel,
        items: [
          for (final position in options)
            FrostedPopupMenuItem(
              icon: _position == position
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              label: positionLabel(position),
              onPressed: () => selected = position,
            ),
        ],
      );
      if (selected != null) setState(() => _position = selected!);
    }

    Future<void> pickRole() async {
      const options = <WorldBookInjectionRole>[
        WorldBookInjectionRole.user,
        WorldBookInjectionRole.assistant,
      ];
      WorldBookInjectionRole? selected;
      await showFrostedPopupMenuAt(
        context,
        globalPosition: popupMenuAnchorForContext(context),
        title: l10n.worldBookEntryInjectionRoleLabel,
        items: [
          for (final role in options)
            FrostedPopupMenuItem(
              icon: _role == role
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              label: roleLabel(role),
              onPressed: () => selected = role,
            ),
        ],
      );
      if (selected != null) setState(() => _role = selected!);
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 0,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                key: ValueKey(PopupContentSurfaceScope.isDialogOf(context)),
                primary: !PopupContentSurfaceScope.isDialogOf(context),
                padding: PopupContentFrame.scrollPadding(
                  context,
                  const EdgeInsets.only(top: 20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IosSectionCard(
                      children: [
                        IosFormTextField(
                          label: l10n.worldBookEntryNameLabel,
                          controller: _nameController,
                          autofocus: base == null,
                          textAlign: TextAlign.start,
                        ),
                        switchRow(
                          label: l10n.worldBookEntryEnabledLabel,
                          value: _enabled,
                          onChanged: (v) => setState(() => _enabled = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _IosSectionCard(
                      children: [
                        IosFormTextField(
                          label: l10n.worldBookEntryContentLabel,
                          controller: _contentController,
                          maxLines: null,
                          minLines: 8,
                          inlineLabel: false,
                          textAlign: TextAlign.start,
                          textInputAction: TextInputAction.newline,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _IosSectionCard(
                      children: [
                        switchRow(
                          label: l10n.worldBookEntryAlwaysOnLabel,
                          hint: l10n.worldBookEntryAlwaysOnHint,
                          value: _constantActive,
                          onChanged: (v) => setState(() => _constantActive = v),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.worldBookEntryKeywordsLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: AppFontWeights.emphasis,
                                  color: cs.onSurface.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_keywords.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final k in _keywords) keywordChip(k),
                                  ],
                                ),
                              if (_keywords.isNotEmpty)
                                const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white12
                                              : const Color(0xFFF2F3F5),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        alignment: Alignment.centerLeft,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 9,
                                        ),
                                        child: AppTextField(
                                          controller: _keywordInputController,
                                          onChanged: (_) => setState(() {}),
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) =>
                                              addKeywordsFromInput(),
                                          textAlignVertical:
                                              TextAlignVertical.center,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: AppFontWeights.medium,
                                            color: cs.onSurface.withValues(
                                              alpha: 0.92,
                                            ),
                                            height: 1.15,
                                          ),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            isCollapsed: true,
                                            hintText: l10n
                                                .worldBookEntryKeywordInputHint,
                                            hintStyle: TextStyle(
                                              fontSize: 15,
                                              fontWeight: AppFontWeights.medium,
                                              color: cs.onSurface.withValues(
                                                alpha: isDark ? 0.42 : 0.46,
                                              ),
                                              height: 1.15,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Tooltip(
                                      message:
                                          l10n.worldBookEntryKeywordAddTooltip,
                                      child: IosCardPress(
                                        baseColor: isDark
                                            ? Colors.white12
                                            : const Color(0xFFF2F3F5),
                                        borderRadius: BorderRadius.circular(12),
                                        pressedScale: 0.98,
                                        haptics: false,
                                        onTap:
                                            _keywordInputController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : () {
                                                Haptics.light();
                                                addKeywordsFromInput();
                                              },
                                        child: Center(
                                          child: Icon(
                                            Lucide.Plus,
                                            size: 18,
                                            color: cs.onSurface.withValues(
                                              alpha:
                                                  _keywordInputController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? 0.35
                                                  : 0.9,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.worldBookEntryKeywordsHint,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        switchRow(
                          label: l10n.worldBookEntryUseRegexLabel,
                          value: _useRegex,
                          onChanged: (v) => setState(() => _useRegex = v),
                        ),
                        switchRow(
                          label: l10n.worldBookEntryCaseSensitiveLabel,
                          value: _caseSensitive,
                          onChanged: (v) => setState(() => _caseSensitive = v),
                        ),
                        IosFormTextField(
                          label: l10n.worldBookEntryScanDepthLabel,
                          controller: _scanDepthController,
                          keyboardType: TextInputType.number,
                          fieldWidth: 64,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _IosSectionCard(
                      children: [
                        valueRow(
                          label: l10n.worldBookEntryInjectionPositionLabel,
                          valueText: positionLabel(_position),
                          onTap: pickPosition,
                        ),
                        if (_position ==
                            WorldBookInjectionPosition.atDepth) ...[
                          IosFormTextField(
                            label: l10n.worldBookEntryInjectDepthLabel,
                            controller: _injectDepthController,
                            keyboardType: TextInputType.number,
                            fieldWidth: 64,
                          ),
                        ],
                        valueRow(
                          label: l10n.worldBookEntryInjectionRoleLabel,
                          valueText: roleLabel(_role),
                          onTap: pickRole,
                        ),
                        IosFormTextField(
                          label: l10n.worldBookEntryPriorityLabel,
                          controller: _priorityController,
                          keyboardType: TextInputType.number,
                          fieldWidth: 64,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
