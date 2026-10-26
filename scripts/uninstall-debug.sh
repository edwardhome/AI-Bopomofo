#!/bin/bash
set -euo pipefail
target="$HOME/Library/Input Methods/AI-Bopomofo.app"
[[ -d "$target" && ! -L "$target" ]] || { echo 'No local AI-Bopomofo installation.'; exit 1; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist")
[[ "$identifier" == org.aibopomofo.inputmethod.AIBopomofo ]] || exit 1
backup="$(mktemp -d "$HOME/Library/Input Methods/../AI-Bopomofo-backup.XXXXXX")"
mv "$target" "$backup/AI-Bopomofo.app"
echo "Bundle preserved at $backup. Remove AI-Bopomofo from Keyboard settings, then log out and back in. User dictionaries are preserved."
