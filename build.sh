#!/usr/bin/env bash
# [kelivo-hosted] Flavor switcher + build wrapper (see flavors/*.sh).
#
# This project doesn't use real Flutter/Gradle/Xcode flavors — branding
# (bundle id / app name / icon) is hardcoded directly into ~15 native
# project files across 5 platforms (kelivo-arch.md §11), and Windows/Linux
# have no flavor concept in Flutter tooling at all. So instead: this script
# owns those specific files and rewrites them in place to match whichever
# flavor you last switched to. Switching is PERSISTENT — once you're on
# "miranda" you stay on "miranda" (across builds, across closing the
# terminal) until you explicitly switch back to "normal". There is no
# auto-revert after a build; this is a checked-out-branding switcher, not a
# per-build sandbox.
#
# "normal" and "miranda" are two parallel, equally-real flavors (see
# flavors/normal.sh and flavors/miranda.sh) — neither is "the git-committed
# default". `apply_flavor` diffs the CURRENT flavor's declared values
# against the TARGET flavor's declared values and substitutes old->new
# directly in the owned files below. No git checkout/restore is involved;
# this tool fully owns (and fully overwrites) the files it lists below.
#
# Usage:
#   ./build.sh switch <flavor>                 # just switch, don't build
#   ./build.sh <flavor> <target> [--dev] [-- <extra flutter args>]
#   ./build.sh <target> [--dev] [-- <extra flutter args>]   # use whatever
#                                                     # flavor is currently
#                                                     # switched in
#
#   flavor: normal | miranda   (see flavors/*.sh)
#   target: apk | appbundle | ios | macos | windows | linux | run
#           (all but "run" go through `flutter build`; "run" goes through
#           `flutter run` — e.g. `-d <device>` — so `flutter run` also picks
#           up the flavor's --dart-define=APP_NAME during plain dev iteration,
#           not just release builds.)
#   --dev:  points the built app at http://localhost:8000 instead of the
#           real backend for both API calls and media (images/videos/
#           attachments) — client_backend_config.dart's
#           CLIENT_BACKEND_BASE_URL/CLIENT_MEDIA_BASE_URL defaults — can
#           appear anywhere in the args, before or after the target. Omit
#           it for a real deployed build.
#
# Examples:
#   ./build.sh switch miranda        # switch and stop here
#   ./build.sh apk                   # build APK with whatever's switched in
#   ./build.sh miranda apk           # switch to miranda, then build APK
#   ./build.sh normal ios -- --release
#   ./build.sh run                   # flutter run with whatever's switched in
#   ./build.sh miranda run -- -d macos
#   ./build.sh run --dev             # flutter run against localhost:8000
#   ./build.sh run --dev -- -d macos
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# --dev can appear anywhere (before/after the target, before/after `--`) —
# pull it out up front so it doesn't confuse the flavor/target positional
# parsing below, same way `--` itself is handled further down.
DEV=0
_ARGS_WITHOUT_DEV=()
for _arg in "$@"; do
  if [ "$_arg" = "--dev" ]; then
    DEV=1
  else
    _ARGS_WITHOUT_DEV+=("$_arg")
  fi
done
set -- "${_ARGS_WITHOUT_DEV[@]+"${_ARGS_WITHOUT_DEV[@]}"}"

STATE_FILE=".flavor_current"
PLATFORMS="apk appbundle ios macos windows linux"
TARGETS="$PLATFORMS run"
is_target() { case " $TARGETS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

current_flavor() {
  if [ -f "$STATE_FILE" ]; then cat "$STATE_FILE"; else echo "normal"; fi
}

# --- Parse args. Three call shapes:
#   switch <flavor>
#   <flavor> <target> [-- extra...]
#   <target> [-- extra...]                (uses current_flavor)
if [ $# -lt 1 ]; then
  echo "Usage:" >&2
  echo "  ./build.sh switch <flavor>" >&2
  echo "  ./build.sh <flavor> <target> [-- <extra flutter args>]" >&2
  echo "  ./build.sh <target> [-- <extra flutter args>]" >&2
  echo "  flavor: normal | miranda" >&2
  echo "  target: $TARGETS" >&2
  exit 1
fi

MODE="build"
FLAVOR=""
TARGET=""

if [ "$1" = "switch" ]; then
  MODE="switch"
  FLAVOR="${2:-}"
  shift $(( $# >= 2 ? 2 : $# ))
  if [ -z "$FLAVOR" ]; then
    echo "Usage: ./build.sh switch <flavor>" >&2
    exit 1
  fi
elif is_target "$1"; then
  TARGET="$1"
  FLAVOR="$(current_flavor)"
  shift
else
  FLAVOR="$1"
  TARGET="${2:-}"
  shift $(( $# >= 2 ? 2 : $# ))
  if [ -z "$TARGET" ] || ! is_target "$TARGET"; then
    echo "Expected a target ($TARGETS) after flavor '$FLAVOR', got '${TARGET:-<nothing>}'" >&2
    exit 1
  fi
fi

EXTRA_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) EXTRA_ARGS+=("$1"); shift ;;
  esac
done

FLAVOR_FILE="flavors/${FLAVOR}.sh"
if [ ! -f "$FLAVOR_FILE" ]; then
  echo "Unknown flavor '$FLAVOR' (no $FLAVOR_FILE)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$FLAVOR_FILE"

# field <flavor> <var> — read a single variable out of flavors/<flavor>.sh
# without polluting the current shell, so we can hold both the OLD and NEW
# flavor's values in hand at once (needed for old->new substitution below).
field() {
  local flavor="$1" var="$2"
  (
    # shellcheck source=/dev/null
    source "flavors/${flavor}.sh"
    echo "${!var}"
  )
}

replace_all() {
  # replace_all <file> <old> <new> — plain-string substitution.
  local file="$1" old="$2" new="$3"
  sed -i '' "s|${old}|${new}|g" "$file"
}

apply_flavor() {
  local from="$1"
  # Pull every field from both the flavor we're leaving and the flavor
  # we're entering, then substitute old->new in each owned file. Works
  # symmetrically in either direction (normal->miranda or miranda->normal)
  # and is a no-op if from == FLAVOR.
  local old_app_name old_android_id old_bundle_id old_macos_name
  local old_win_mutex old_linux_id old_linux_icon
  old_app_name="$(field "$from" APP_NAME)"
  old_android_id="$(field "$from" ANDROID_APPLICATION_ID)"
  old_bundle_id="$(field "$from" BUNDLE_ID)"
  old_macos_name="$(field "$from" MACOS_PRODUCT_NAME)"
  old_win_mutex="$(field "$from" WINDOWS_MUTEX_NAME)"
  old_linux_id="$(field "$from" LINUX_APP_ID)"
  old_linux_icon="$(field "$from" LINUX_ICON_NAME)"

  if [ "$from" = "$FLAVOR" ]; then
    return
  fi

  replace_all android/app/build.gradle.kts \
    "applicationId = \"${old_android_id}\"" "applicationId = \"${ANDROID_APPLICATION_ID}\""
  replace_all android/app/src/main/AndroidManifest.xml \
    "android:label=\"${old_app_name}\"" "android:label=\"${APP_NAME}\""

  replace_all ios/Runner/Info.plist "$old_app_name" "$APP_NAME"
  replace_all ios/Runner/Info.plist "$old_bundle_id" "$BUNDLE_ID"
  replace_all ios/Runner/AppDelegate.swift "$old_bundle_id" "$BUNDLE_ID"
  replace_all ios/Runner.xcodeproj/project.pbxproj "$old_bundle_id" "$BUNDLE_ID"

  replace_all macos/Runner/Configs/AppInfo.xcconfig "$old_macos_name" "$MACOS_PRODUCT_NAME"
  replace_all macos/Runner/Configs/AppInfo.xcconfig "$old_bundle_id" "$BUNDLE_ID"
  replace_all macos/Runner.xcodeproj/project.pbxproj "$old_bundle_id" "$BUNDLE_ID"

  replace_all windows/runner/Runner.rc "$old_app_name" "$APP_NAME"
  replace_all windows/runner/main.cpp "$old_win_mutex" "$WINDOWS_MUTEX_NAME"
  replace_all windows/runner/main.cpp "$old_app_name" "$APP_NAME"

  replace_all linux/CMakeLists.txt "$old_linux_id" "$LINUX_APP_ID"
  replace_all linux/runner/my_application.cc "$old_linux_icon" "$LINUX_ICON_NAME"
  replace_all linux/runner/my_application.cc "$old_app_name" "$APP_NAME"

  for f in app_icon.png app_icon_dark.png app_icon_macos2.png app_icon.ico; do
    if [ -f "${ICON_SOURCE_DIR}/${f}" ]; then
      cp "${ICON_SOURCE_DIR}/${f}" "assets/${f}"
    fi
  done
}

if [ "$(current_flavor)" != "$FLAVOR" ]; then
  echo "==> Switching flavor: $(current_flavor) -> $FLAVOR ($APP_NAME)"
  apply_flavor "$(current_flavor)"
  echo "$FLAVOR" > "$STATE_FILE"
  echo "==> Generating platform icons"
  dart run flutter_launcher_icons
else
  echo "==> Already on flavor '$FLAVOR' ($APP_NAME) — no changes to branding files."
fi

if [ "$MODE" = "switch" ]; then
  echo "==> Done (switch only, not building)."
  exit 0
fi

DEV_DEFINE=()
if [ "$DEV" = "1" ]; then
  # No local CDN to hit in dev — media (images/videos/attachments) comes
  # straight from the same localhost backend as everything else, same as
  # before `clientMediaBaseUrl` (client_backend_config.dart) existed.
  DEV_DEFINE=(
    --dart-define="CLIENT_BACKEND_BASE_URL=http://localhost:8000"
    --dart-define="CLIENT_MEDIA_BASE_URL=http://localhost:8000"
  )
  echo "==> --dev: pointing at http://localhost:8000 instead of the real backend"
fi

if [ "$TARGET" = "run" ]; then
  RUN_ARGS=(--dart-define="APP_NAME=$APP_NAME" "${DEV_DEFINE[@]+"${DEV_DEFINE[@]}"}")
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    RUN_ARGS+=("${EXTRA_ARGS[@]}")
  fi
  echo "==> flutter run ${RUN_ARGS[*]}"
  flutter run "${RUN_ARGS[@]}"
else
  BUILD_ARGS=("$TARGET" --dart-define="APP_NAME=$APP_NAME" "${DEV_DEFINE[@]+"${DEV_DEFINE[@]}"}")
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    BUILD_ARGS+=("${EXTRA_ARGS[@]}")
  fi
  echo "==> flutter build ${BUILD_ARGS[*]}"
  flutter build "${BUILD_ARGS[@]}"
fi

echo "==> Done. Still on flavor '$FLAVOR' — run './build.sh switch normal' to go back."
