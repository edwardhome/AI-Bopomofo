#!/usr/bin/env python3
"""Explicit synthetic XPC probe; never launches or installs the IME, types, or plays audio."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
if len(sys.argv) != 3:
    raise SystemExit("Usage: run-xpc-probe.py built-app-path output.json")
app = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
service = app / "Contents/XPCServices/ModelService.xpc"
if not service.is_dir():
    raise SystemExit("Built model service missing")
package = ROOT / "research/text-assistance/Probe"
subprocess.run(["swift", "build", "-c", "release", "--package-path", str(package)], check=True)
binary_dir = subprocess.check_output(["swift", "build", "-c", "release", "--package-path", str(package), "--show-bin-path"], text=True).strip()
with tempfile.TemporaryDirectory(prefix="aib-xpc-probe-") as temporary:
    bundle = pathlib.Path(temporary) / "AssistanceProbe.app"
    contents = bundle / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "XPCServices").mkdir()
    shutil.copy2(pathlib.Path(binary_dir) / "Probe", contents / "MacOS/Probe")
    shutil.copytree(service, contents / "XPCServices/ModelService.xpc", symlinks=True)
    with (contents / "Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": "org.aibopomofo.development.AssistanceProbe",
                      "CFBundleExecutable": "Probe", "CFBundlePackageType": "APPL",
                      "CFBundleVersion": "1"}, file)
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(bundle)], check=True)
    subprocess.run([str(contents / "MacOS/Probe"), str(ROOT / "research/text-assistance/automatic-4.json"), str(output)],
                   env={**os.environ, "AI_BOPOMOFO_PROBE_XPC": "1"}, timeout=80, check=True)
