import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/layouts/app_scaffold.dart';
import 'oidc_login_page.dart';

/// [kelivo-hosted] OIDC (account.ethan0ne.com) is the only sign-in path —
/// see `oidc_login_page.dart`'s doc comment for the flow itself.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  Future<void> _startOidcLogin() async {
    setState(() => _busy = true);
    final errorCode = await Navigator.of(
      context,
    ).push<String?>(MaterialPageRoute(builder: (_) => const OidcLoginPage()));
    if (!mounted) return;
    setState(() => _busy = false);
    // `null` is success (`OidcLoginPage` only pops that after
    // `AuthProvider.completeOidcLogin` actually succeeded, which already
    // updates `AuthProvider.status` — `AuthGate` picks that up on its own).
    if (errorCode == null) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppScaffold(
      title: AppScaffoldTitle(l10n.authLoginPageTitle),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(
              top: AppScaffold.scrollContentTop(context),
            ),
            sliver: const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FilledButton(
                  onPressed: _busy ? null : _startOidcLogin,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.authLoginPageOidcButton),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
