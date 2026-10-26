#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/vim
sdk="$(xcrun --show-sdk-path)"
for arch in arm64 x86_64; do
  xcrun swiftc -O -sdk "$sdk" -target "$arch-apple-macos13.0" integrations/vim/input-source.swift -o "build/vim/ai-bopomofo-input-$arch"
done
lipo -create build/vim/ai-bopomofo-input-arm64 build/vim/ai-bopomofo-input-x86_64 -output build/vim/ai-bopomofo-input
codesign --force --sign - build/vim/ai-bopomofo-input
