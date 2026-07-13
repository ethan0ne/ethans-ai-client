/// Base URL of the AI Inspector backend's `/__client/*` API (kelivo-arch.md).
/// Defaults to the real deployed backend — override via
/// `--dart-define=CLIENT_BACKEND_BASE_URL=...` for local development
/// (`./build.sh <target> --dev` sets this to `http://localhost:8000`
/// automatically, see build.sh), the same way `lib/secrets/fallback.dart`
/// values are injected by CI rather than hand-edited here.
const String clientBackendBaseUrl = String.fromEnvironment(
  'CLIENT_BACKEND_BASE_URL',
  defaultValue: 'https://ai-client.ethan0ne.com',
);
