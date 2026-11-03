#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
mkdir -p artifacts
xcodebuild -project McBopomofo.xcodeproj -scheme McBopomofo \
  -configuration "$configuration" -derivedDataPath "${AI_BOPOMOFO_DERIVED_DATA:-build/DerivedData}" \
  -clonedSourcePackagesDirPath "${AI_BOPOMOFO_PACKAGE_CACHE:-${AI_BOPOMOFO_DERIVED_DATA:-build/DerivedData}/SourcePackages}" -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
