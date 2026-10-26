#!/bin/bash
# Does not launch an IMK input method, play audio, invoke FM, or install anything.
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -DENABLE_TEST=ON -S Source -B build/engine
cmake --build build/engine -j 4
ctest --test-dir build/engine --output-on-failure
swift test --package-path Packages/MixedInputCore
swift test --package-path Packages/CandidateRanking
python3 -m unittest discover -s research/apple-fm -p 'test_corpus.py'
python3 -m unittest discover -s research/text-assistance -p 'test_*.py'
python3 integrations/vim/test-integration.py
make -C Source/Data check
xcodebuild -project McBopomofo.xcodeproj -scheme McBopomofo -configuration Debug \
  -derivedDataPath build/DerivedData -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build-for-testing
