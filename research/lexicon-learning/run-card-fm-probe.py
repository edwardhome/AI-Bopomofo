#!/usr/bin/env python3
"""Opt-in synthetic FM/XPC probe. Never installs, launches an IME, or accesses private cards."""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
if len(sys.argv) < 3:
    raise SystemExit("Usage: run-card-fm-probe.py built-app output-directory [wavelength silica bank]")
app, output = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
fixtures = sys.argv[3:] or ["wavelength", "silica", "bank"]
if any(f not in ("wavelength", "silica", "bank") for f in fixtures):
    raise SystemExit("Only public synthetic fixtures are supported")
service = app / "Contents/XPCServices/ModelService.xpc"
if not service.is_dir():
    raise SystemExit("Built model service missing")
package = ROOT / "research/lexicon-learning/CardProbe"
subprocess.run(["swift", "build", "-c", "release", "--package-path", str(package)], check=True)
binary_dir = subprocess.check_output(["swift", "build", "-c", "release", "--package-path", str(package), "--show-bin-path"], text=True).strip()
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="aib-card-probe-") as temp:
    app = pathlib.Path(temp) / "CardProbe.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "XPCServices").mkdir()
    shutil.copy2(pathlib.Path(binary_dir) / "CardProbe", contents / "MacOS/CardProbe")
    shutil.copytree(service, contents / "XPCServices/ModelService.xpc", symlinks=True)
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": "org.aibopomofo.development.CardProbe", "CFBundleExecutable": "CardProbe",
                      "CFBundlePackageType": "APPL", "CFBundleVersion": "1"}, file)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    for fixture in fixtures:
        subprocess.run([str(contents / "MacOS/CardProbe"), fixture, "xpc", str(output / f"{fixture}.json")], check=True, timeout=85)
