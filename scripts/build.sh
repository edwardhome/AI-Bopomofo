#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
mkdir -p artifacts
xcodebuild -project McBopomofo.xcodeproj -scheme McBopomofo \
  -configuration "$configuration" -derivedDataPath build/DerivedData \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
