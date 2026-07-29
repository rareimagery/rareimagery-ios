#!/bin/sh
# Xcode Cloud post-clone: regenerate RareImagery.xcodeproj from project.yml so
# the committed project can never drift from the source of truth. The project
# is also committed (Xcode Cloud resolves it from the git tree at plan time),
# so this is a freshness step, not the sole source.
set -ex

echo "ci_post_clone: pwd=$(pwd) CI_PRIMARY_REPOSITORY_PATH=${CI_PRIMARY_REPOSITORY_PATH:-UNSET}"
cd "${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH not set}"

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

xcodegen generate
# Fail loudly here (not later in the opaque resolve step) if generation
# didn't produce the project where the workflow expects it.
test -d RareImagery.xcodeproj
echo "ci_post_clone: RareImagery.xcodeproj generated OK"

# Xcode Cloud: inject auth config for Release Archive builds.
# Set these as environment variables in the workflow (App Store Connect → Xcode Cloud → Workflow → Environment):
#   X_CLIENT_ID              — X OAuth 2.0 Client ID (must match BFF X_CLIENT_ID)
#   OAUTH_CLIENT_ID          — Drupal simple_oauth consumer UUID (broker primary path)
#   GOOGLE_IOS_CLIENT_ID     — Google Cloud iOS OAuth client ID
#   GOOGLE_REVERSED_CLIENT_ID — reversed client ID for URL scheme (com.googleusercontent.apps.…)
# Writes gitignored Configuration/Release.local.xcconfig via Release.xcconfig #include.
# Only X_CLIENT_ID + OAUTH_CLIENT_ID are REQUIRED for an archive. Google is
# OPTIONAL: leave its env vars unset and the build uses the RFC-safe
# Release.xcconfig defaults, the Google button stays hidden in-app, and Apple +
# X still ship. If GOOGLE_REVERSED_CLIENT_ID is set it is still format-validated
# below (it becomes a CFBundleURLScheme App Store rejects if malformed).
missing=""
[ -z "${X_CLIENT_ID:-}" ] && missing="X_CLIENT_ID"
[ -z "${OAUTH_CLIENT_ID:-}" ] && missing="${missing:+$missing }OAUTH_CLIENT_ID"

if [ -n "${X_CLIENT_ID:-}" ] || [ -n "${OAUTH_CLIENT_ID:-}" ] || [ -n "${GOOGLE_IOS_CLIENT_ID:-}" ]; then
  : > Configuration/Release.local.xcconfig
  if [ -n "${X_CLIENT_ID:-}" ]; then
    printf 'X_CLIENT_ID = %s\n' "$X_CLIENT_ID" >> Configuration/Release.local.xcconfig
  fi
  if [ -n "${OAUTH_CLIENT_ID:-}" ]; then
    printf 'OAUTH_CLIENT_ID = %s\n' "$OAUTH_CLIENT_ID" >> Configuration/Release.local.xcconfig
  fi
  if [ -n "${GOOGLE_IOS_CLIENT_ID:-}" ]; then
    printf 'GOOGLE_IOS_CLIENT_ID = %s\n' "$GOOGLE_IOS_CLIENT_ID" >> Configuration/Release.local.xcconfig
  fi
  if [ -n "${GOOGLE_REVERSED_CLIENT_ID:-}" ]; then
    printf 'GOOGLE_REVERSED_CLIENT_ID = %s\n' "$GOOGLE_REVERSED_CLIENT_ID" >> Configuration/Release.local.xcconfig
  fi
  echo "ci_post_clone: wrote Configuration/Release.local.xcconfig from Xcode Cloud env"
else
  echo "ci_post_clone: auth env vars not set — Release builds will use placeholders"
fi

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] || [ "${CI_XCODEBUILD_ACTION:-}" = "build-for-distribution" ]; then
  if [ -n "$missing" ]; then
    echo "error: Archive builds require Xcode Cloud env: $missing"
    echo "error: (Google is optional — set GOOGLE_IOS_CLIENT_ID + GOOGLE_REVERSED_CLIENT_ID only when enabling Google sign-in.)"
    exit 1
  fi
  case "${GOOGLE_REVERSED_CLIENT_ID:-}" in
    *REPLACE*|*replace*|*_*)
      echo "error: GOOGLE_REVERSED_CLIENT_ID '${GOOGLE_REVERSED_CLIENT_ID}' is invalid for URL schemes (RFC1738: no underscores)."
      exit 1
      ;;
  esac
fi
