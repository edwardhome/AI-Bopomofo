#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-dist/0.3.1-alpha}"
[[ -d "$out" ]] || exit 1
(cd "$out" && shasum -a 256 -c checksums.txt)
temp="$(mktemp -d "$PWD/build/verify-package.XXXXXX")"
trap 'rm -rf "$temp"' EXIT
packages=("$out"/*.pkg)
[[ "${#packages[@]}" -eq 1 ]] || exit 1
pkgutil --expand-full "${packages[0]}" "$temp/expanded"
python3 scripts/verify-bundle.py "$temp/expanded/Payload/AI-Bopomofo.app"
python3 - "$out/AI-Bopomofo.app" "$temp/expanded/Payload/AI-Bopomofo.app" "$temp/expanded/PackageInfo" <<'PY'
import hashlib, pathlib, sys, xml.etree.ElementTree as ET
def contents(root):
    root = pathlib.Path(root)
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}
original, extracted = contents(sys.argv[1]), contents(sys.argv[2])
assert original == extracted, 'Package payload differs from saved app'
info = ET.parse(sys.argv[3]).getroot()
assert info.get('install-location') == '/Library/Input Methods'
assert info.get('relocatable') == 'false'
assert info.find('bundle').get('id') == 'org.aibopomofo.inputmethod.AIBopomofo'
print(f'PASS: {len(original)} payload files match, fixed independent install location')
PY
