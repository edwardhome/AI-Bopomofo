#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="${1:-build/DerivedData/Build/Products/Debug/AI-Bopomofo.app}"
python3 scripts/verify-bundle.py "$app"
target="$HOME/Library/Input Methods/AI-Bopomofo.app"
if [[ -e '/Library/Input Methods/AI-Bopomofo.app' ]]; then
  echo 'A system installation exists. Remove that copy first; do not install duplicate input sources.' >&2
  exit 1
fi
mkdir -p "$HOME/Library/Input Methods"
if [[ -e "$target" || -L "$target" ]]; then
  echo 'Existing AI-Bopomofo found. Run uninstall-debug.sh to preserve it before installing.' >&2
  exit 1
fi
ditto "$app" "$target"
echo 'Installed AI-Bopomofo for this account. Log out and back in, then add AI-Bopomofo in Keyboard settings.'
