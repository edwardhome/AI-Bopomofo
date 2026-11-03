#!/usr/bin/env python3
"""Validate independent identity and required resources without launching an IME."""
import pathlib
import json
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
with (app / "Contents/Info.plist").open("rb") as source:
    info = plistlib.load(source)
identifier = "org.aibopomofo.inputmethod.AIBopomofo"
assert app.name == "AI-Bopomofo.app", app
assert info["CFBundleIdentifier"] == identifier
assert info["TISInputSourceID"] == identifier
assert info["InputMethodConnectionName"] == "AIBopomofo_1_Connection"
assert info["CFBundleName"] == "AI注音輸入法"
assert info["CFBundleDisplayName"] == "AI注音輸入法"
for locale in ("Base", "en", "zh-Hant"):
    path = app / "Contents/Resources" / (locale + ".lproj") / "InfoPlist.strings"
    localized = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(path)]))
    assert localized["CFBundleDisplayName"] == "AI注音輸入法"
    assert localized[identifier + ".Bopomofo"] == "AI注音輸入法"
assert set(info["ComponentInputModeDict"]["tsInputModeListKey"]) == {
    identifier + ".Bopomofo", identifier + ".PlainBopomofo"
}
assert "UpdateInfoEndpoint" not in info
assert (app / "Contents/MacOS" / info["CFBundleExecutable"]).is_file()
for name in ("data.txt", "data-plain-bpmf.txt", "associated-phrases-v2.txt"):
    assert (app / "Contents/Resources" / name).stat().st_size > 0, name
if tuple(map(int, info["CFBundleShortVersionString"].split("."))) >= (0, 6, 12):
    catalogs = list((app / "Contents/Resources").rglob("engineering-terms.json"))
    assert len(catalogs) == 1, 'Missing or duplicate bundled engineering lexicon'
    catalog = json.loads(catalogs[0].read_text())
    assert catalog["version"] == 1 and catalog["terms"], 'Invalid engineering lexicon'
    assert any(t["outputs"] == ["SiO₂", "SiO2"] for t in catalog["terms"])
    print(f'PASS: bundled engineering lexicon: {len(catalog["terms"])} terms')
if tuple(map(int, info["CFBundleShortVersionString"].split("."))) >= (0, 6, 13):
    service = app / "Contents/XPCServices/ModelService.xpc"
    service_info = plistlib.loads((service / "Contents/Info.plist").read_bytes())
    assert service_info["CFBundleIdentifier"] == identifier + ".ModelService"
    assert service_info["CFBundlePackageType"] == "XPC!"
    assert (service / "Contents/MacOS/ModelService").is_file()
    subprocess.run(["codesign", "--verify", "--strict", str(service)], check=True)
    assert not list(app.rglob("learning.sqlite")), 'Private learning database must not ship'
    print('PASS: isolated model service and no private learning database')
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(f"PASS: identity, modes, connection, dictionary resources, signature: {app}")
