import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../icons/lucide_adapter.dart' as lucide;
import '../../l10n/app_localizations.dart';
import '../../theme/app_font_weights.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/assistant_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../shared/pages/webview_page.dart';

/// [kelivo-hosted] Desktop counterpart of the mobile "Account" section in
/// `SettingsPage` (kelivo-arch.md 8) — this pane is only reachable once
/// `AuthGate` has already let the user through, so it never needs to render
/// a signed-out/login state, matching the mobile section it mirrors.
class DesktopAccountPane extends StatelessWidget {
  const DesktopAccountPane({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final auth = context.watch<AuthProvider>();

    return Container(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 36,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.authSettingsAccountSection,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: AppFontWeights.regular,
                      color: cs.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _DeskCard(
                title: l10n.authSettingsAccountSection,
                children: [
                  _DeskInfoRow(
                    icon: lucide.Lucide.User,
                    label: auth.user?.email ?? '',
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _DeskDestructiveButton(
                      icon: lucide.Lucide.ChartColumnBig,
                      label: l10n.authSettingsViewUsage,
                      color: cs.primary,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WebViewPage(
                              url: 'https://ai-cpa-dash.ethan0ne.com',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _DeskDestructiveButton(
                      icon: lucide.Lucide.LogOut,
                      label: l10n.authSettingsLogout,
                      onTap: () async {
                        final assistantProvider = context
                            .read<AssistantProvider>();
                        await context.read<AuthProvider>().logout(
                          context.read<ChatService>(),
                          assistantProvider,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeskCard extends StatelessWidget {
  const _DeskCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          width: 0.5,
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : cs.outlineVariant.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: AppFontWeights.emphasis,
                  color: cs.onSurface,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DeskInfoRow extends StatelessWidget {
  const _DeskInfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Icon(
              icon,
              size: 18,
              color: cs.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                color: cs.onSurface.withValues(alpha: 0.92),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeskDestructiveButton extends StatefulWidget {
  const _DeskDestructiveButton({
    required this.icon,
    required this.label,
    required this.onTap,
    // [kelivo-hosted] Defaults to the error/destructive styling this widget
    // was originally built for (the logout button); a caller like "查看用量"
    // passes a neutral color instead of this becoming a second near-duplicate
    // button widget (see CLAUDE.md 3.9's "no near-duplicate widgets" rule).
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  @override
  State<_DeskDestructiveButton> createState() => _DeskDestructiveButtonState();
}

class _DeskDestructiveButtonState extends State<_DeskDestructiveButton> {
  bool _hover = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.color ?? cs.error;
    final bg = _hover
        ? accent.withValues(alpha: 0.10)
        : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.03));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: accent),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: accent,
                    fontWeight: AppFontWeights.semibold,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
