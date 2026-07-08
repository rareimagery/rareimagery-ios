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

# Xcode Cloud: inject X OAuth client ID for Release Archive builds.
# Set X_CLIENT_ID as an environment variable in the workflow settings.
# Writes gitignored Configuration/Release.local.xcconfig so Release.xcconfig
# picks up the real value via #include? "Release.local.xcconfig".
if [ -n "${X_CLIENT_ID:-}" ]; then
  printf 'X_CLIENT_ID = %s\n' "$X_CLIENT_ID" > Configuration/Release.local.xcconfig
  echo "ci_post_clone: wrote Configuration/Release.local.xcconfig from X_CLIENT_ID env"
else
  echo "ci_post_clone: X_CLIENT_ID not set — Release builds will use placeholder until workflow env is configured"
fi
