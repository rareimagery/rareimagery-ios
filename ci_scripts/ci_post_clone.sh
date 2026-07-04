#!/bin/sh
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate