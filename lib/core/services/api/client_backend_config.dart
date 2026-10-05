/// SharedPreferences key for a user-selected hosted backend API origin.
const String clientBackendBaseUrlOverridePreferenceKey =
    'client_backend_base_url_override_v1';
const String clientMediaBaseUrlOverridePreferenceKey =
    'client_media_base_url_override_v1';

/// Base URL of the AI Inspector backend's `/__client/*` API (kelivo-arch.md).
/// Build configuration supplies the default; the local settings override is
/// loaded before `runApp` and takes precedence when present.
const String defaultClientBackendBaseUrl = String.fromEnvironment(
  'CLIENT_BACKEND_BASE_URL',
  defaultValue: 'https://ai-client.ethan0ne.com',
);

String? _clientBackendBaseUrlOverride;
String? _clientMediaBaseUrlOverride;
String? _serverDeclaredClientMediaBaseUrl;

/// Currently active hosted backend API origin.
String get clientBackendBaseUrl =>
    _clientBackendBaseUrlOverride ?? defaultClientBackendBaseUrl;

/// Updates the in-memory override. Persistence is owned by SettingsProvider.
void setClientBackendBaseUrlOverride(String? value) {
  final trimmed = value?.trim();
  _clientBackendBaseUrlOverride = trimmed == null || trimmed.isEmpty
      ? null
      : trimmed;
}

/// Currently active hosted media origin used to recognize media URLs that
/// may require the hosted session token.
String get clientMediaBaseUrl =>
    _clientMediaBaseUrlOverride ??
    _serverDeclaredClientMediaBaseUrl ??
    defaultClientMediaBaseUrl;

/// Updates the in-memory media origin override. Persistence is owned by
/// SettingsProvider.
void setClientMediaBaseUrlOverride(String? value) {
  final trimmed = value?.trim();
  _clientMediaBaseUrlOverride = trimmed == null || trimmed.isEmpty
      ? null
      : trimmed;
}

/// Updates the media origin anonymously declared by the active backend.
void setServerDeclaredClientMediaBaseUrl(String? value) {
  final trimmed = value?.trim();
  _serverDeclaredClientMediaBaseUrl = trimmed == null || trimmed.isEmpty
      ? null
      : trimmed;
}

/// Base URL that hosted chat images/videos/attachments are actually served
/// from (backend's system setting, with `INSPECTOR_CLIENT_PUBLIC_BASE_URL` as
/// its fallback) — a separately configurable origin from
/// [clientBackendBaseUrl] so media traffic can use its own domain while every other API call still goes to the main backend
/// host. Every place that decides "is this URL ours, attach the session JWT"
/// (see `resolveImageProvider`/`image_viewer_page.dart`) has to check both
/// base URLs, or a media URL under this domain silently gets no
/// Authorization header and 401s.
/// This value identifies media URLs that may require the hosted session
/// token. Media served from the current API origin is recognized separately.
/// The local override takes precedence over the backend declaration, which
/// takes precedence over the build default.
const String defaultClientMediaBaseUrl = String.fromEnvironment(
  'CLIENT_MEDIA_BASE_URL',
  defaultValue: 'https://ai-client-assets.ethan0ne.com',
);
