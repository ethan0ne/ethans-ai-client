/// Base URL of the AI Inspector backend's `/__client/*` API (kelivo-arch.md).
/// Placeholder for local development — override via `--dart-define=CLIENT_BACKEND_BASE_URL=...`
/// when building for staging/production, the same way `lib/secrets/fallback.dart` values are
/// injected by CI rather than hand-edited here.
const String clientBackendBaseUrl = String.fromEnvironment(
  'CLIENT_BACKEND_BASE_URL',
  defaultValue: 'http://localhost:8000',
);
