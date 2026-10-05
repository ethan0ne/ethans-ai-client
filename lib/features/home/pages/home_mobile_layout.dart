import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'dart:ui' as ui;

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/interactive_drawer.dart';
import '../widgets/side_drawer.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../shared/animations/widgets.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../utils/brand_assets.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../widgets/assistant_avatar.dart';
import '../widgets/assistant_entry_actions.dart';
import 'package:Kelivo/theme/app_font_weights.dart';

/// Mobile layout scaffold for the home page
/// This widget handles only the structural layout - AppBar, drawer, body structure
/// All message list rendering and input bar logic remain in home_page.dart
class HomeMobileScaffold extends StatelessWidget {
  const HomeMobileScaffold({
    super.key,
    required this.scaffoldKey,
    required this.drawerController,
    required this.assistantPickerCloseTick,
    required this.loadingConversationIds,
    required this.title,
    required this.isDraftConversation,
    required this.modelDisplay,
    required this.modelProviderKey,
    required this.modelId,
    required this.onToggleDrawer,
    required this.onDismissKeyboard,
    required this.onSelectConversation,
    required this.onNewConversation,
    required this.onOpenMiniMap,
    required this.showHostedRefresh,
    required this.onRefreshHostedConversation,
    required this.onRenameConversation,
    required this.onDeleteConversation,
    required this.onCreateNewConversation,
    required this.onToggleTemporaryConversation,
    required this.onSelectModel,
    required this.canToggleTemporaryConversation,
    required this.temporaryConversationEnabled,
    required this.globalSearchMode,
    required this.globalSearchQuery,
    required this.onGlobalSearchQueryChanged,
    required this.onEnterGlobalSearch,
    required this.onExitGlobalSearch,
    required this.onOpenGlobalSearchResult,
    this.appBarOverride,
    required this.body,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final InteractiveDrawerController drawerController;
  final ValueNotifier<int> assistantPickerCloseTick;
  final Set<String> loadingConversationIds;
  final String title;
  final bool isDraftConversation;
  final String? modelDisplay;
  final String? modelProviderKey;
  final String? modelId;
  final VoidCallback onToggleDrawer;
  final VoidCallback onDismissKeyboard;
  final void Function(String id) onSelectConversation;
  final VoidCallback onNewConversation;
  final VoidCallback onOpenMiniMap;
  final bool showHostedRefresh;
  final VoidCallback onRefreshHostedConversation;
  final Future<void> Function() onRenameConversation;
  final Future<void> Function() onDeleteConversation;
  final Future<void> Function() onCreateNewConversation;
  final Future<void> Function() onToggleTemporaryConversation;
  final VoidCallback onSelectModel;
  final bool canToggleTemporaryConversation;
  final bool temporaryConversationEnabled;
  final bool globalSearchMode;
  final String globalSearchQuery;
  final ValueChanged<String> onGlobalSearchQueryChanged;
  final VoidCallback onEnterGlobalSearch;
  final VoidCallback onExitGlobalSearch;
  final Future<void> Function(String conversationId, String messageId)
  onOpenGlobalSearchResult;
  final PreferredSizeWidget? appBarOverride;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InteractiveDrawer(
      controller: drawerController,
      side: DrawerSide.left,
      drawerWidth: MediaQuery.sizeOf(context).width * 0.75,
      scrimColor: cs.onSurface,
      maxScrimOpacity: 0.12,
      barrierDismissible: true,
      drawer: SideDrawer(
        drawerController: drawerController,
        userName: context.watch<UserProvider>().name,
        assistantName: _getAssistantName(context),
        closePickerTicker: assistantPickerCloseTick,
        loadingConversationIds: loadingConversationIds,
        globalSearchMode: globalSearchMode,
        globalSearchQuery: globalSearchQuery,
        onGlobalSearchQueryChanged: onGlobalSearchQueryChanged,
        onEnterGlobalSearch: onEnterGlobalSearch,
        onExitGlobalSearch: onExitGlobalSearch,
        onOpenGlobalSearchResult: (conversationId, messageId) async {
          await onOpenGlobalSearchResult(conversationId, messageId);
          drawerController.close();
        },
        onSelectConversation: (id, {closeDrawer = true}) {
          onSelectConversation(id);
          if (closeDrawer) drawerController.close();
        },
        onNewConversation: ({closeDrawer = true}) async {
          if (closeDrawer) drawerController.close();
          await onCreateNewConversation();
        },
      ),
      child: AppScaffold(
        scaffoldKey: scaffoldKey,
        leadingIslands: appBarOverride == null
            ? [
                [
                  AppButtonIslandButton(
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).openAppDrawerTooltip,
                    builder: (color) => SvgPicture.asset(
                      'assets/icons/list.svg',
                      width: 16,
                      height: 16,
                      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                    ),
                    onTap: () {
                      onDismissKeyboard();
                      onToggleDrawer();
                    },
                  ),
                ],
              ]
            : const [],
        title: appBarOverride == null
            ? _buildToolbarTitle(context, cs)
            : const SizedBox.shrink(),
        actions: appBarOverride == null
            ? _buildToolbarActions(context)
            : const [],
        appBarOverride: appBarOverride,
        body: body,
      ),
    );
  }

  String _getAssistantName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final a = context.watch<AssistantProvider>().currentAssistant;
    final n = a?.name.trim();
    return (n == null || n.isEmpty) ? l10n.homePageDefaultAssistant : n;
  }

  Widget _buildToolbarTitle(BuildContext context, ColorScheme cs) {
    final isDesktopPlatform =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    final useNewAssistantAvatarUx = context
        .watch<SettingsProvider>()
        .useNewAssistantAvatarUx;

    return useNewAssistantAvatarUx
        ? Row(
            children: [
              _buildAssistantTitleAvatar(context),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedTextSwap(
                      text: title,
                      alignment: Alignment.center,
                      style: TextStyle(
                        fontSize: isDesktopPlatform ? 14 : 16,
                        fontWeight: AppFontWeights.medium,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    _buildModelSubtitle(context, cs),
                  ],
                ),
              ),
            ],
          )
        : SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedTextSwap(
                  text: title,
                  alignment: Alignment.center,
                  style: TextStyle(
                    fontSize: isDesktopPlatform ? 14 : 16,
                    fontWeight: AppFontWeights.medium,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                _buildModelSubtitle(context, cs),
              ],
            ),
          );
  }

  Widget _buildModelSubtitle(BuildContext context, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: InkWell(
            onTap: onSelectModel,
            borderRadius: BorderRadius.circular(999),
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: cs.onSurface.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
              child: AnimatedSwitcher(
                duration: kAnim,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.center,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Row(
                  key: ValueKey(
                    '$modelProviderKey:$modelId:${modelDisplay ?? 'none'}',
                  ),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildModelIcon(context),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        modelDisplay ?? l10n.homePageNoModelSelected,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.brightness == Brightness.dark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                          fontWeight: AppFontWeights.medium,
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
  }

  Widget _buildModelIcon(BuildContext context) {
    final modelName = modelId?.trim();
    final asset = (modelName == null || modelName.isEmpty)
        ? null
        : BrandAssets.assetForName(modelName) ??
              (modelProviderKey == null
                  ? null
                  : BrandAssets.assetForName(modelProviderKey!));
    if (asset == null) return Icon(Lucide.Boxes, size: 12);

    final isSvg = asset.endsWith('.svg');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark && isSvg && !asset.contains('color')
        ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        : null;
    return SizedBox(
      width: 10,
      height: 14,
      child: Center(
        child: isSvg
            ? SvgPicture.asset(asset, width: 10, height: 10, colorFilter: tint)
            : Image.asset(asset, width: 10, height: 10, fit: BoxFit.contain),
      ),
    );
  }

  List<Widget> _buildToolbarActions(BuildContext context) {
    return [
      AppButtonIslandButton(
        size: 20,
        key: const ValueKey('new-conversation'),
        onTap: () async {
          if (canToggleTemporaryConversation) {
            await onToggleTemporaryConversation();
          } else {
            await onCreateNewConversation();
          }
        },
        semanticLabel: canToggleTemporaryConversation
            ? AppLocalizations.of(context)!.temporaryChatToggleTooltip
            : AppLocalizations.of(context)!.titleForLocale,
        icon: canToggleTemporaryConversation && !temporaryConversationEnabled
            ? Lucide.MessageCircleDashed
            : Lucide.MessageCirclePlus,
        builder: canToggleTemporaryConversation && temporaryConversationEnabled
            ? (color) => SvgPicture.asset(
                'assets/icons/temporary_chat_checked.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              )
            : null,
      ),
      if (!isDraftConversation)
        AppButtonIslandButton(
          size: 20,
          key: const ValueKey('toolbar-overflow'),
          menuTitle: title,
          menuItems: _buildToolbarMenuItems(context),
          semanticLabel: MaterialLocalizations.of(context).showMenuTooltip,
          icon: Lucide.Ellipsis,
        ),
    ];
  }

  List<FrostedPopupMenuItem> _buildToolbarMenuItems(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return [
      FrostedPopupMenuItem(
        icon: Lucide.Pencil,
        label: l10n.sideDrawerMenuRename,
        dividerAfter: true,
        onPressed: () {
          onRenameConversation();
        },
      ),
      if (showHostedRefresh)
        FrostedPopupMenuItem(
          icon: Lucide.RefreshCw,
          label: l10n.hostedRefreshConversationTooltip,
          onPressed: onRefreshHostedConversation,
        ),
      FrostedPopupMenuItem(
        icon: Lucide.Map,
        label: l10n.miniMapTooltip,
        onPressed: onOpenMiniMap,
      ),
      FrostedPopupMenuItem(
        icon: Lucide.Trash2,
        label: l10n.sideDrawerMenuDelete,
        destructive: true,
        onPressed: () {
          onDeleteConversation();
        },
      ),
    ];
  }

  Widget _buildAssistantTitleAvatar(BuildContext context) {
    final assistantProvider = context.watch<AssistantProvider>();
    final currentAssistant = assistantProvider.currentAssistant;
    final currentAssistantId = assistantProvider.currentAssistantId;

    return IosCardPress(
      borderRadius: BorderRadius.circular(999),
      baseColor: Colors.transparent,
      padding: const EdgeInsets.all(2),
      longPressTimeout: const Duration(milliseconds: 280),
      onTap: () {
        onDismissKeyboard();
        onToggleDrawer();
      },
      onLongPress: currentAssistantId == null
          ? null
          : () {
              Haptics.light();
              AssistantEntryActions.openAssistantSettings(
                context,
                currentAssistantId,
              );
            },
      child: AssistantAvatar(
        assistant: currentAssistant,
        fallbackName: _getAssistantName(context),
        size: 28,
      ),
    );
  }
}

/// Mobile background widget with assistant-specific image and gradient overlay
class MobileBackgroundLayer extends StatelessWidget {
  const MobileBackgroundLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = context.watch<AssistantProvider>().currentAssistant?.background;
    final maskStrength = context
        .watch<SettingsProvider>()
        .chatBackgroundMaskStrength;

    if (bg == null || bg.trim().isEmpty) return const SizedBox.shrink();

    ImageProvider provider;
    if (bg.startsWith('http')) {
      provider = NetworkImage(bg);
    } else {
      final localPath = SandboxPathResolver.fix(bg);
      final file = File(localPath);
      if (!file.existsSync()) return const SizedBox.shrink();
      provider = FileImage(file);
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: provider,
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.04),
                    BlendMode.srcATop,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.surface.withValues(
                        alpha: (0.20 * maskStrength).clamp(0.0, 1.0),
                      ),
                      cs.surface.withValues(
                        alpha: (0.50 * maskStrength).clamp(0.0, 1.0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scroll navigation buttons (scroll to bottom + scroll to previous question)
class ScrollNavigationButtons extends StatelessWidget {
  const ScrollNavigationButtons({
    super.key,
    required this.showJumpToBottom,
    required this.inputBarHeight,
    required this.hasMessages,
    required this.onScrollToBottom,
    required this.onScrollToPreviousQuestion,
  });

  final bool showJumpToBottom;
  final double inputBarHeight;
  final bool hasMessages;
  final VoidCallback onScrollToBottom;
  final VoidCallback onScrollToPreviousQuestion;

  @override
  Widget build(BuildContext context) {
    final showSetting = context.watch<SettingsProvider>().showMessageNavButtons;
    if (!showSetting || !hasMessages) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomOffset = inputBarHeight + 12;

    return Stack(
      children: [
        // Scroll to bottom button
        Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            top: false,
            bottom: false,
            child: IgnorePointer(
              ignoring: !showJumpToBottom,
              child: AnimatedScale(
                scale: showJumpToBottom ? 1.0 : 0.9,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  opacity: showJumpToBottom ? 1 : 0,
                  child: Padding(
                    padding: EdgeInsets.only(right: 16, bottom: bottomOffset),
                    child: _ScrollButton(
                      isDark: isDark,
                      icon: Lucide.ChevronDown,
                      onTap: onScrollToBottom,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Scroll to previous question button
        Align(
          alignment: Alignment.bottomRight,
          child: SafeArea(
            top: false,
            bottom: false,
            child: IgnorePointer(
              ignoring: !showJumpToBottom,
              child: AnimatedScale(
                scale: showJumpToBottom ? 1.0 : 0.9,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  opacity: showJumpToBottom ? 1 : 0,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: 16,
                      bottom: bottomOffset + 52,
                    ),
                    child: _ScrollButton(
                      isDark: isDark,
                      icon: Lucide.ChevronUp,
                      onTap: onScrollToPreviousQuestion,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollButton extends StatelessWidget {
  const _ScrollButton({
    required this.isDark,
    required this.icon,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.07),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.20),
              width: 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  icon,
                  size: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selection mode toolbar overlay
class SelectionToolbarOverlay extends StatelessWidget {
  const SelectionToolbarOverlay({
    super.key,
    required this.visible,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool visible;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 122),
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: IgnorePointer(
                ignoring: !visible,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _GlassCircleButton(
                      icon: Lucide.X,
                      color: cs.onSurface,
                      onTap: onCancel,
                      semanticLabel: l10n.homePageCancel,
                    ),
                    const SizedBox(width: 14),
                    _GlassCircleButton(
                      icon: Lucide.Check,
                      color: cs.primary,
                      onTap: onConfirm,
                      semanticLabel: l10n.homePageDone,
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

    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: ClipOval(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tileColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Center(
                  child: Icon(widget.icon, size: 18, color: widget.color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
