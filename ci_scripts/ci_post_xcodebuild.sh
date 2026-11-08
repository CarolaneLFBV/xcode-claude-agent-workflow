#!/bin/sh
# Xcode Cloud post-build hook: upload dSYMs (blocking) and associate the commit with the Sentry release
# (non-blocking). Workflow environment: SENTRY_AUTH_TOKEN (secret), SENTRY_URL, SENTRY_ORG, SENTRY_PROJECT.
# Keep this file executable in git (100755). Never add `set -x`.
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    echo "Sentry: no archive action; skipping."
    exit 0
fi
case "${CI_XCODEBUILD_EXIT_CODE:-}" in
    0) ;;
    ''|*[!0-9]*) echo "error: Missing or invalid CI_XCODEBUILD_EXIT_CODE." >&2; exit 1 ;;
    *) echo "Sentry: archive failed; skipping."; exit 0 ;;
esac
: "${CI_ARCHIVE_PATH:?CI_ARCHIVE_PATH is required after a successful archive}"
: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set as a secret in the workflow}"

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export SENTRY_DISABLE_UPDATE_CHECK=1
command -v sentry-cli >/dev/null 2>&1 || brew install getsentry/tools/sentry-cli

# 1. dSYMs: blocking, a failed upload fails the step
sentry-cli debug-files upload --type dsym --wait "$CI_ARCHIVE_PATH/dSYMs"

# 2. Release commits: non-blocking
associate_commits() {
    for var in SENTRY_URL SENTRY_ORG SENTRY_PROJECT; do
        eval "value=\${$var:-}"
        [ -n "$value" ] || { echo "warning: Sentry: $var is not set in the workflow."; return 1; }
    done
    if [ -z "${GITHUB_REPO:-}" ]; then   # owner/repo, derived from the remote (never printed)
        REMOTE=$(git -C "${CI_PRIMARY_REPOSITORY_PATH:-.}" remote get-url origin 2>/dev/null || true)
        GITHUB_REPO=$(printf '%s' "$REMOTE" | sed -E 's#\.git$##; s#^.*[:/]([^/:]+/[^/]+)$#\1#')
    fi
    case "$GITHUB_REPO" in */*) ;; *) echo "warning: Sentry: cannot determine the GitHub repo."; return 1 ;; esac

    PLIST="$CI_ARCHIVE_PATH/Info.plist"
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleIdentifier" "$PLIST")
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$PLIST")
    # Xcode Cloud replaces the build number at export: use its number, like the SDK at runtime
    BUILD="${CI_BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$PLIST")}"
    RELEASE="${BUNDLE_ID}@${VERSION}+${BUILD}"

    [ -n "${CI_COMMIT:-}" ] || { echo "warning: Sentry: CI_COMMIT is missing."; return 1; }
    sentry-cli releases new "$RELEASE" \
      && sentry-cli releases set-commits "$RELEASE" --commit "${GITHUB_REPO}@${CI_COMMIT}" \
      && sentry-cli releases finalize "$RELEASE" \
      && echo "Sentry: release $RELEASE associated with commit $CI_COMMIT."
}
associate_commits || echo "warning: Sentry: commit association skipped (build not affected)."
