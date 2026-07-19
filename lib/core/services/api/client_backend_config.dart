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

/// Base URL that hosted chat images/videos/attachments are actually served
/// from (backend's `INSPECTOR_CLIENT_PUBLIC_BASE_URL` — see
/// `client_message_files.py`'s `file_url()`) — a separate, Cloudflare-fronted
/// domain from [clientBackendBaseUrl] specifically so media traffic gets CDN
/// acceleration while every other API call still goes to the main backend
/// host. Every place that decides "is this URL ours, attach the session JWT"
/// (see `resolveImageProvider`/`image_viewer_page.dart`) has to check both
/// base URLs, or a media URL under this domain silently gets no
/// Authorization header and 401s.
/// `./build.sh <target> --dev` overrides this to match
/// [clientBackendBaseUrl]'s own dev override (`http://localhost:8000`) —
/// there's no separate CDN domain to hit locally. Override via
/// `--dart-define=CLIENT_MEDIA_BASE_URL=...` for any other environment that
/// needs a different value than the production CDN domain below.
const String clientMediaBaseUrl = String.fromEnvironment(
  'CLIENT_MEDIA_BASE_URL',
  defaultValue: 'https://ai-client-assets.ethan0ne.com',
);
