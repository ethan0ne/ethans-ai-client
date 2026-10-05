import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/api/client_backend_api.dart';
import '../../../core/services/api/client_backend_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../settings/widgets/app_language_select_sheet.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import '../../settings/pages/debug_development_page.dart';
import 'oidc_login_page.dart';

/// Geometry and gradient follow Financial-Memory's AccountPage.
/// Providers, ordering and logos come from the hosted server.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.api});
  final ClientBackendApi? api;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final ClientBackendApi _api;
  late Future<List<ClientLoginProvider>> _providers;
  String? _activeProviderId;
  int _loginTitleTapCount = 0;
  DateTime? _lastLoginTitleTapAt;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ClientBackendApi(baseUrl: clientBackendBaseUrl);
    _providers = _api.fetchLoginProviders();
  }

  double _largeTitleTop(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = math.max(media.padding.top, media.viewPadding.top);
    final portraitPhone =
        Theme.of(context).platform == TargetPlatform.iOS &&
        media.size.shortestSide < 600 &&
        media.size.height >= media.size.width &&
        safeTop > 24;
    return AppScaffold.scrollContentTop(context) - 2 - (portraitPhone ? 14 : 0);
  }

  void _retry() {
    final providers = _api.fetchLoginProviders();
    setState(() {
      _providers = providers;
    });
  }

  void _handleLoginTitleTap() {
    final now = DateTime.now();
    final lastTap = _lastLoginTitleTapAt;
    if (lastTap == null ||
        now.difference(lastTap) > const Duration(seconds: 2)) {
      _loginTitleTapCount = 0;
    }
    _lastLoginTitleTapAt = now;
    _loginTitleTapCount++;
    if (_loginTitleTapCount < 5) return;

    _loginTitleTapCount = 0;
    _lastLoginTitleTapAt = null;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const DebugDevelopmentPage()),
      ),
    );
  }

  Future<void> _startLogin(ClientLoginProvider provider) async {
    if (_activeProviderId != null) return;
    setState(() => _activeProviderId = provider.id);
    try {
      final errorCode = await Navigator.of(context).push<String?>(
        MaterialPageRoute(
          builder: (_) => OidcLoginPage(providerId: provider.id),
        ),
      );
      if (!mounted || errorCode == null) return;
      final l10n = AppLocalizations.of(context)!;
      final message = switch (errorCode) {
        'account_pending' => l10n.authOidcAccountPending,
        'account_banned' => l10n.authOidcAccountBanned,
        'server_error' => l10n.authOidcServerError,
        _ => l10n.authErrorGeneric,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _activeProviderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final busy = _activeProviderId != null;
    return PopScope(
      canPop: !busy,
      child: AppScaffold(
        title: const SizedBox.shrink(),
        backgroundColor: AppColors.groupedBackgroundFor(context),
        actions: [
          AppButtonIslandButton(
            icon: Lucide.Globe,
            semanticLabel: l10n.displaySettingsPageLanguageTitle,
            onTap: busy ? null : () => showAppLanguageSelector(context),
          ),
        ],
        leadingIslands: Navigator.of(context).canPop()
            ? [
                [
                  AppButtonIslandButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    semanticLabel: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onTap: busy ? null : () => Navigator.of(context).maybePop(),
                  ),
                ],
              ]
            : const [],
        body: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 340,
                child: IgnorePointer(child: _LoginGradientDecoration()),
              ),
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          16,
                          _largeTitleTop(context),
                          16,
                          AppScaffold.scrollContentBottom(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: busy ? null : _handleLoginTitleTap,
                              child: Text(
                                l10n.authLoginPageTitle,
                                textHeightBehavior: const TextHeightBehavior(
                                  applyHeightToFirstAscent: false,
                                  applyHeightToLastDescent: false,
                                ),
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                  height: 1.1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            FutureBuilder<List<ClientLoginProvider>>(
                              future: _providers,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  );
                                }
                                final providers =
                                    snapshot.data ??
                                    const <ClientLoginProvider>[];
                                if (snapshot.hasError || providers.isEmpty) {
                                  return SizedBox(
                                    width: double.infinity,
                                    child: Column(
                                      children: [
                                        Icon(
                                          snapshot.hasError
                                              ? Icons.cloud_off_outlined
                                              : Icons.info_outline,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                          size: 28,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          snapshot.hasError
                                              ? l10n.authLoginMethodsLoadFailed
                                              : l10n.authLoginMethodsEmpty,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 12),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            splashFactory:
                                                NoSplash.splashFactory,
                                          ),
                                          onPressed: busy ? null : _retry,
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                          label: Text(
                                            l10n.authLoginMethodsRetry,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                return Column(
                                  children: [
                                    for (
                                      var index = 0;
                                      index < providers.length;
                                      index++
                                    ) ...[
                                      if (index > 0) const SizedBox(height: 12),
                                      _LoginOptionCapsule(
                                        icon: SizedBox(
                                          width: 30,
                                          height: 30,
                                          child:
                                              providers[index].iconUrl == null
                                              ? const Icon(
                                                  Icons.login_rounded,
                                                  size: 30,
                                                )
                                              : Image.network(
                                                  providers[index].iconUrl!,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, _, _) =>
                                                      const Icon(
                                                        Icons.login_rounded,
                                                        size: 30,
                                                      ),
                                                ),
                                        ),
                                        label: l10n.authLoginWithProvider(
                                          providers[index].name,
                                        ),
                                        enabled: !busy,
                                        isLoading:
                                            _activeProviderId ==
                                            providers[index].id,
                                        onTap: () =>
                                            _startLogin(providers[index]),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginGradientDecoration extends StatelessWidget {
  const _LoginGradientDecoration();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gold = isDark ? const Color(0xFFFFC857) : const Color(0xFFB78316);
    final blue = isDark ? const Color(0xFF65D6F5) : const Color(0xFF78C8E8);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.52, 0.82, 1.0],
        colors: [
          Colors.white.withValues(alpha: 1.0),
          Colors.white.withValues(alpha: 0.92),
          Colors.white.withValues(alpha: 0.48),
          Colors.transparent,
        ],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gold.withValues(alpha: isDark ? 0.30 : 0.24),
              blue.withValues(alpha: isDark ? 0.24 : 0.20),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LoginOptionCapsule extends StatelessWidget {
  const _LoginOptionCapsule({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.isLoading,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool enabled;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(999);
    final contentOpacity = enabled ? 1.0 : 0.45;
    final textStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    final scaler = MediaQuery.textScalerOf(context);
    final largeText = scaler.scale(textStyle?.fontSize ?? 16) > 22;
    final height = math.max(
      64.0,
      scaler.scale(textStyle?.fontSize ?? 16) * 2.4 + 24,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.groupedSurface(theme.brightness),
        borderRadius: radius,
      ),
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: ExcludeSemantics(
          child: IosCardPress(
            haptics: false,
            baseColor: Colors.transparent,
            borderRadius: radius,
            onTap: enabled ? onTap : null,
            child: SizedBox(
              height: largeText ? height : 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AppSpacing.lg,
                      ),
                      child: Opacity(opacity: contentOpacity, child: icon),
                    ),
                  ),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const leftInset = 64.0;
                        final rightInset = isLoading ? 64.0 : 24.0;
                        final centeredWidth = math.max(
                          0.0,
                          constraints.maxWidth - leftInset * 2,
                        );
                        final availableWidth = math.max(
                          0.0,
                          constraints.maxWidth - leftInset - rightInset,
                        );
                        final resolvedTextStyle =
                            textStyle ?? DefaultTextStyle.of(context).style;
                        final painter = TextPainter(
                          text: TextSpan(text: label, style: resolvedTextStyle),
                          maxLines: 1,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout();
                        final painterWidth = painter.width;
                        final fitsWhileCentered = painterWidth <= centeredWidth;
                        painter.dispose();
                        final textWidth = fitsWhileCentered
                            ? centeredWidth
                            : availableWidth;

                        return Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: fitsWhileCentered ? 0 : leftInset,
                            end: fitsWhileCentered ? 0 : rightInset,
                          ),
                          child: Align(
                            alignment: fitsWhileCentered
                                ? Alignment.center
                                : AlignmentDirectional.centerStart,
                            child: SizedBox(
                              width: textWidth,
                              child: Opacity(
                                opacity: contentOpacity,
                                child: Text(
                                  label,
                                  maxLines:
                                      largeText || painterWidth > availableWidth
                                      ? 2
                                      : 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: fitsWhileCentered
                                      ? TextAlign.center
                                      : TextAlign.start,
                                  style: textStyle,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (isLoading)
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(end: AppSpacing.lg),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
