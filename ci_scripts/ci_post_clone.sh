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
