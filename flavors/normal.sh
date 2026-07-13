# [kelivo-hosted] "normal" flavor — see build.sh's `apply_flavor`. Parallel
# to miranda.sh: every value here is substituted the same way, just with
# different content. Neither flavor is "the base" — apply_flavor always
# diffs the CURRENT flavor's values against the TARGET flavor's values and
# rewrites in place, so switching normal<->miranda works symmetrically in
# either direction with no git involved.
APP_NAME="Ethan's AI"
ANDROID_APPLICATION_ID="com.ethan0ne.aiclient"
BUNDLE_ID="com.ethan0ne.ai-client"
MACOS_PRODUCT_NAME="Ethans AI"
WINDOWS_MUTEX_NAME="EthansAIMutex"
LINUX_APP_ID="com.ethan0ne.ai-client"
LINUX_ICON_NAME="ethans-ai"
ICON_SOURCE_DIR="assets/normal_version"
