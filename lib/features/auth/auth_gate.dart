import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/assistant_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/chat/chat_service.dart';
import '../../l10n/app_localizations.dart';
import 'pages/login_page.dart';

/// Gates access to [child] behind a signed-in Kelivo-hosted-client account
/// (kelivo-arch.md 3). Wraps `_selectHome()`'s result in `main.dart` rather
/// than replacing it, so the existing mobile/desktop platform split is
/// untouched.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});

  final Widget child;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Assistant bootstrap belongs to the signed-in transition, not generic
  // app startup. That covers both an explicit login and a restored session,
  // while preventing the login screen itself from creating a local assistant
  // before the account's cloud list has been queried.
  bool _assistantBootstrapStarted = false;

  void _bootstrapSignedInAssistantState(BuildContext context) {
    if (_assistantBootstrapStarted) return;
    _assistantBootstrapStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      await context.read<AssistantProvider>().ensureDefaults(context);
      if (!context.mounted) return;
      try {
        context.read<ChatService>().setDefaultConversationTitle(
          AppLocalizations.of(context)!.chatServiceDefaultConversationTitle,
        );
      } catch (_) {}
      try {
        context.read<UserProvider>().setDefaultNameIfUnset(
          AppLocalizations.of(context)!.userProviderDefaultUserName,
        );
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final status = auth.status;
    switch (status) {
      case AuthStatus.unknown:
        // A persisted access token is enough to render the app while the
        // backend validates it in the background. If it is rejected,
        // AuthProvider transitions to signedOut and this gate switches to
        // LoginPage automatically.
        if (auth.token != null) {
          _bootstrapSignedInAssistantState(context);
          return widget.child;
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        _assistantBootstrapStarted = false;
        return const LoginPage();
      case AuthStatus.signedIn:
        _bootstrapSignedInAssistantState(context);
        return widget.child;
    }
  }
}
