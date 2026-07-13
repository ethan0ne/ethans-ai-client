# [kelivo-hosted] "miranda" flavor — see build.sh's `apply_flavor`. Parallel
# to normal.sh: every value here is substituted in over whichever flavor's
# value currently occupies that spot (normal or miranda, symmetrically).
APP_NAME="AI for Miranda"
# Android disallows hyphens in applicationId (Gradle compile-time check —
# see kelivo-arch.md §11.3, the same reason the "normal" flavor's Android id
# already dropped the hyphen from the ai-client base). Mirroring that
# precedent here rather than literally using "ai-client.miranda", which
# would fail to build.
ANDROID_APPLICATION_ID="com.ethan0ne.aiclient.miranda"
# iOS/macOS/Linux bundle ids allow hyphens — this is the literal id
# requested. Every iOS identifier that's currently prefixed with the
# "normal" BUNDLE_ID (GenerationActivityExtension, RunnerTests, background
# task/notification identifiers) gets this same prefix substituted in, so
# they all cascade to the miranda-flavored equivalent together.
BUNDLE_ID="com.ethan0ne.ai-client.miranda"
MACOS_PRODUCT_NAME="AI for Miranda"
# Windows single-instance mutex name — must differ from the normal flavor's
# so a running "normal" build doesn't prevent a "miranda" build from
# opening its own window (and vice versa); see main.cpp's CreateMutexW/
# SendAppLinkToInstance call sites, which build.sh patches together.
WINDOWS_MUTEX_NAME="AIforMirandaMutex"
LINUX_APP_ID="com.ethan0ne.ai-client.miranda"
LINUX_ICON_NAME="ai-for-miranda"
ICON_SOURCE_DIR="assets/miranda_version"
