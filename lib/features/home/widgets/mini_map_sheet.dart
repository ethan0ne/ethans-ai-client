import 'dart:ui' as ui;

import 'package:Kelivo/shared/widgets/app_popup_sheet.dart';
import 'package:Kelivo/shared/widgets/app_text_field.dart';

import 'package:flutter/material.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/chat_input_data.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/resolve_image_provider.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../shared/widgets/popup_content_frame.dart';

Future<String?> showMiniMapSheet(
  BuildContext context,
  List<ChatMessage> messages, {
  bool selecting = false,
  Set<String>? selectedMessageIds,
  Listenable? selectionListenable,
  ValueChanged<String>? onToggleSelection,
}) async {
  assert(
    !selecting || (selectedMessageIds != null && onToggleSelection != null),
    'Mini map selection mode requires selectedMessageIds and onToggleSelection.',
  );
  return showPopupContentFrame<String>(
    context,
    maxWidth: 620,
    maxHeight: 700,
    largeSheet: true,
    builder: (_, isDialog) => _MiniMapSheet(
      messages: messages,
      selecting: selecting,
      selectedMessageIds: selectedMessageIds,
      selectionListenable: selectionListenable,
      onToggleSelection: onToggleSelection,
      isDialog: isDialog,
    ),
  );
}

/// Uses the same draggable bottom-sheet presentation as MiniMap for choosing
/// an attachment reference in the composer.
Future<ChatImageReferenceCandidate?> showImageReferenceSheet(
  BuildContext context,
  List<ChatImageReferenceCandidate> candidates, {
  Future<List<ChatImageReferenceCandidate>> Function()? refreshCandidates,
}) {
  final l10n = AppLocalizations.of(context)!;
  return showAppPopupSheet<ChatImageReferenceCandidate>(
    context: context,
    title: l10n.chatInputBarReferenceAttachmentTitle,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ImageReferenceSheet(
      candidates: candidates,
      refreshCandidates: refreshCandidates,
    ),
  );
}

class _ImageReferenceSheet extends StatefulWidget {
  const _ImageReferenceSheet({
    required this.candidates,
    this.refreshCandidates,
  });

  final List<ChatImageReferenceCandidate> candidates;
  final Future<List<ChatImageReferenceCandidate>> Function()? refreshCandidates;

  @override
  State<_ImageReferenceSheet> createState() => _ImageReferenceSheetState();
}

class _ImageReferenceSheetState extends State<_ImageReferenceSheet> {
  late List<ChatImageReferenceCandidate> _candidates;
  late bool _loading;

  @override
  void initState() {
    super.initState();
    _candidates = List.of(widget.candidates);
    _loading = widget.refreshCandidates != null;
    if (_loading) {
      _refreshCandidates();
    }
  }

  Future<void> _refreshCandidates() async {
    try {
      final refreshed = await widget.refreshCandidates!.call();
      if (!mounted) return;
      setState(() {
        _candidates = refreshed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Draft indexes identify attachments selected in the message currently
    // being composed. Keep those in insertion order at the top; conversation
    // history is intentionally newest-first so the nearest context is easiest
    // to reach on a mobile sheet.
    final currentCandidates = _candidates
        .where(
          (candidate) =>
              candidate.draftImageIndex != null ||
              candidate.draftDocumentIndex != null,
        )
        .toList(growable: false);
    final historyCandidates = _candidates
        .where(
          (candidate) =>
              candidate.draftImageIndex == null &&
              candidate.draftDocumentIndex == null,
        )
        .toList()
        .reversed
        .toList(growable: false);
    final orderedCandidates = [...currentCandidates, ...historyCandidates];
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, controller) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : orderedCandidates.isEmpty
                    ? Center(
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            AppLocalizations.of(
                              context,
                            )!.chatInputBarReferenceAttachmentEmpty,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        itemCount: orderedCandidates.length,
                        itemBuilder: (context, index) {
                          final candidate = orderedCandidates[index];
                          final source = candidate.isImage
                              ? (candidate.localPath ?? candidate.previewSource)
                              : null;
                          final provider = source == null
                              ? null
                              : resolveImageProvider(source);
                          return AppListTile(
                            minLeadingWidth: 44,
                            leading: SizedBox(
                              width: 44,
                              height: 44,
                              child: provider == null
                                  ? Icon(
                                      candidate.isImage
                                          ? Lucide.Image
                                          : Lucide.FileText,
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image(
                                        image: provider,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                            ),
                            title: Text(candidate.fileName ?? candidate.label),
                            subtitle: Text(
                              candidate.fileId == null
                                  ? AppLocalizations.of(
                                      context,
                                    )!.chatInputBarReferenceAttachmentCurrent
                                  : AppLocalizations.of(
                                      context,
                                    )!.chatInputBarReferenceAttachmentHistory,
                            ),
                            onTap: () => Navigator.of(context).pop(candidate),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMapSheet extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool selecting;
  final Set<String>? selectedMessageIds;
  final Listenable? selectionListenable;
  final ValueChanged<String>? onToggleSelection;
  final bool isDialog;

  const _MiniMapSheet({
    required this.messages,
    required this.isDialog,
    this.selecting = false,
    this.selectedMessageIds,
    this.selectionListenable,
    this.onToggleSelection,
  });

  @override
  State<_MiniMapSheet> createState() => _MiniMapSheetState();
}

class _MiniMapSheetState extends State<_MiniMapSheet> {
  late final TextEditingController _searchController;
  final ScrollController _dialogListFallbackController = ScrollController(
    keepScrollOffset: false,
  );
  late List<_QaPair> _pairs;
  String _query = '';

  static const double _popupSearchReservedExtent = 84;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _pairs = _buildPairs(widget.messages);
  }

  @override
  void didUpdateWidget(covariant _MiniMapSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.messages, widget.messages)) {
      _pairs = _buildPairs(widget.messages);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dialogListFallbackController.dispose();
    super.dispose();
  }

  void _handleSearchChanged(String value, ScrollController controller) {
    final shouldScrollToTop = _query.trim().isEmpty && value.trim().isNotEmpty;
    setState(() => _query = value);
    if (!shouldScrollToTop) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(controller.position.minScrollExtent);
    });
  }

  void _clearSearch(ScrollController controller) {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _handleSearchChanged('', controller);
  }

  void _scrollToBottom(ScrollController controller) {
    if (!controller.hasClients || controller.position.maxScrollExtent <= 0) {
      return;
    }
    controller.jumpTo(controller.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.isDialog
        ? _dialogListFallbackController
        : PrimaryScrollController.maybeOf(context) ??
              _dialogListFallbackController;
    final l10n = AppLocalizations.of(context)!;

    return PopupContentFrame(
      title: l10n.miniMapTitle,
      isDialog: widget.isDialog,
      showCloseButton: true,
      actions: [
        AppButtonIslandButton(
          icon: Lucide.ChevronsDown,
          semanticLabel: l10n.miniMapScrollToBottomTooltip,
          onTap: () => _scrollToBottom(controller),
        ),
      ],
      child: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(child: _buildList(context, controller)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildPopupBottomOverlay(context, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, ScrollController controller) {
    final pairs = _filteredPairs(_pairs);
    Widget buildList() => ListView.builder(
      controller: controller,
      padding: PopupContentFrame.scrollPadding(
        context,
        EdgeInsets.fromLTRB(
          12,
          PopupContentFrame.contentTopPadding(context, widget.isDialog),
          12,
          _popupSearchReservedExtent,
        ),
      ),
      itemCount: pairs.length,
      itemBuilder: (context, index) => _MiniMapRow(
        pair: pairs[index],
        selecting: widget.selecting,
        selectedMessageIds: widget.selectedMessageIds,
        onToggleSelection: widget.onToggleSelection,
      ),
    );

    if (!widget.selecting || widget.selectionListenable == null) {
      return buildList();
    }
    return AnimatedBuilder(
      animation: widget.selectionListenable!,
      builder: (context, _) => buildList(),
    );
  }

  Widget _buildPopupBottomOverlay(
    BuildContext context,
    ScrollController controller,
  ) {
    final background = Theme.of(context).colorScheme.surface;
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _buildPopupSearchBar(context, controller),
          ),
        ),
      ],
    );
  }

  Widget _buildPopupSearchBar(
    BuildContext context,
    ScrollController controller,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = BorderRadius.circular(999);

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [AppButtonIslandStyle.shadow(theme.brightness)],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: AppButtonIslandStyle.blurSigma,
            sigmaY: AppButtonIslandStyle.blurSigma,
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppButtonIslandStyle.fill(theme.brightness),
              borderRadius: borderRadius,
              border: Border.all(
                color: AppButtonIslandStyle.border(theme.brightness),
                width: AppButtonIslandStyle.borderWidth,
              ),
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
                    child: AppTextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) =>
                          _handleSearchChanged(value, controller),
                      style: theme.textTheme.bodyMedium,
                      cursorColor: colorScheme.primary,
                      decoration: InputDecoration(
                        hintText: MaterialLocalizations.of(
                          context,
                        ).searchFieldLabel,
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _clearSearch(controller),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(
                          Lucide.X,
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
    );
  }

  List<_QaPair> _buildPairs(List<ChatMessage> items) {
    final pairs = <_QaPair>[];
    ChatMessage? pendingUser;
    for (final m in items) {
      if (m.role == 'user') {
        // Push previous if it had no assistant
        if (pendingUser != null) {
          pairs.add(_QaPair(user: pendingUser, assistant: null));
        }
        pendingUser = m;
      } else if (m.role == 'assistant') {
        if (pendingUser != null) {
          pairs.add(_QaPair(user: pendingUser, assistant: m));
          pendingUser = null;
        } else {
          // Assistant without user: show as orphan on the right
          pairs.add(_QaPair(user: null, assistant: m));
        }
      }
    }
    if (pendingUser != null) {
      pairs.add(_QaPair(user: pendingUser, assistant: null));
    }
    return pairs;
  }

  List<_QaPair> _filteredPairs(List<_QaPair> base) {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return base;
    return base.where((pair) {
      final user = pair.user?.content.toLowerCase() ?? '';
      final asst = pair.assistant?.content.toLowerCase() ?? '';
      return user.contains(needle) || asst.contains(needle);
    }).toList();
  }
}

class _QaPair {
  final ChatMessage? user;
  final ChatMessage? assistant;
  _QaPair({required this.user, required this.assistant});
}

class _MiniMapRow extends StatelessWidget {
  final _QaPair pair;
  final bool selecting;
  final Set<String>? selectedMessageIds;
  final ValueChanged<String>? onToggleSelection;

  const _MiniMapRow({
    required this.pair,
    this.selecting = false,
    this.selectedMessageIds,
    this.onToggleSelection,
  });

  String _oneLine(String s) {
    // Strip inline embed markers used in user messages to avoid noise
    var t = s
        // remove vendor inline reasoning blocks if present
        .replaceAll(
          RegExp(
            r'<(?:think|thought)>[\s\S]*?<\/(?:think|thought)>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r"\[image:[^\]]+\]"), "")
        .replaceAll(RegExp(r"\[file:[^\]]+\]"), "")
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pair.user case final user?)
                _buildBubble(
                  context,
                  user,
                  alignment: Alignment.centerRight,
                  maxWidth: availableWidth * 0.75,
                  background: colors.primary.withValues(
                    alpha: isDark ? 0.15 : 0.08,
                  ),
                  selectedBackground: colors.primary.withValues(
                    alpha: isDark ? 0.26 : 0.14,
                  ),
                  selectedBorder: colors.primary.withValues(
                    alpha: isDark ? 0.45 : 0.35,
                  ),
                ),
              if (pair.user != null && pair.assistant != null)
                const SizedBox(height: 6),
              if (pair.assistant case final assistant?)
                _buildBubble(
                  context,
                  assistant,
                  alignment: Alignment.centerLeft,
                  maxWidth: availableWidth,
                  background: colors.onSurface.withValues(
                    alpha: isDark ? 0.06 : 0.04,
                  ),
                  selectedBackground: colors.primary.withValues(
                    alpha: isDark ? 0.18 : 0.10,
                  ),
                  selectedBorder: colors.primary.withValues(
                    alpha: isDark ? 0.38 : 0.28,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    ChatMessage message, {
    required Alignment alignment,
    required double maxWidth,
    required Color background,
    required Color selectedBackground,
    required Color selectedBorder,
  }) {
    final selected =
        selecting && (selectedMessageIds?.contains(message.id) ?? false);
    final borderRadius = BorderRadius.circular(16);
    final preview = _oneLine(message.content);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? selectedBackground : background,
        borderRadius: borderRadius,
        border: selecting && selected
            ? Border.all(color: selectedBorder, width: 1)
            : null,
      ),
      child: Text(
        preview.isNotEmpty ? preview : ' ',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15.5,
          height: 1.45,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: Colors.transparent,
          child: selecting
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onToggleSelection?.call(message.id),
                  child: content,
                )
              : InkWell(
                  borderRadius: borderRadius,
                  onTap: () => Navigator.of(context).pop(message.id),
                  child: content,
                ),
        ),
      ),
    );
  }
}
