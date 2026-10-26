#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:-0.1.0-alpha}"
configuration="${2:-Debug}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || exit 2
out="dist/$version"
if [[ -e "$out" ]]; then
  echo "Refusing to overwrite preserved artifact: $out" >&2
  exit 1
fi
app="build/DerivedData/Build/Products/$configuration/AI-Bopomofo.app"
python3 scripts/verify-bundle.py "$app"
mkdir -p "$out"
ditto "$app" "$out/AI-Bopomofo.app"
licenses="$out/AI-Bopomofo.app/Contents/Resources/Licenses"
mkdir -p "$licenses"
cp LICENSE.txt "$licenses/McBopomofo-MIT.txt"
cp ACKNOWLEDGEMENTS.md "$licenses/ACKNOWLEDGEMENTS.md"
if [[ -d licenses ]]; then cp licenses/* "$licenses/"; fi
python3 - "$licenses" <<'PY'
import pathlib, shutil, sys
target = pathlib.Path(sys.argv[1])
base = pathlib.Path('build/DerivedData/SourcePackages/checkouts')
for path in base.rglob('*'):
    if path.is_file() and path.name.lower() in ('license', 'license.txt', 'copying', 'notice', 'notice.txt'):
        shutil.copy2(path, target / str(path.relative_to(base)).replace('/', '-'))
PY
codesign --force --deep --sign - "$out/AI-Bopomofo.app"
python3 scripts/verify-bundle.py "$out/AI-Bopomofo.app"
# Component is fixed at /Library/Input Methods; no relocation into the upstream bundle.
python3 - <<'PY'
import plistlib
with open('build/component.plist', 'wb') as f:
    plistlib.dump([{'RootRelativeBundlePath':'AI-Bopomofo.app',
                   'BundleIsRelocatable':False,
                   'BundleOverwriteAction':'upgrade'}], f)
PY
stage="$(mktemp -d "$PWD/build/package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$out/AI-Bopomofo.app" "$stage/AI-Bopomofo.app"
pkgbuild --root "$stage" --component-plist build/component.plist \
  --identifier org.aibopomofo.pkg --version "${version%%-*}" \
  --install-location '/Library/Input Methods' "$out/AI-Bopomofo-$version.pkg"
ditto -c -k --keepParent "$out/AI-Bopomofo.app" "$out/AI-Bopomofo-$version.zip"
cp docs/installation.md "$out/README-INSTALL.md"
cp docs/release-notes.md "$out/RELEASE-NOTES.md"
git rev-parse HEAD > "$out/SOURCE-COMMIT.txt"
(cd "$out" && shasum -a 256 ./*.pkg ./*.zip > checksums.txt)
echo "Saved local development artifacts: $out"
