#!/usr/bin/env python3
"""Build the local native launcher; Wine remains an external dependency."""
from pathlib import Path
import plistlib
import platform
import shutil
import subprocess

source = Path(__file__).resolve().parent
bundle = source / "build/Proton4Mac.app"
binary = bundle / "Contents/MacOS"
resources = bundle / "Contents/Resources"
binary.mkdir(parents=True, exist_ok=True)
resources.mkdir(parents=True, exist_ok=True)
subprocess.run(["xcrun", "swiftc", "-O", str(source / "Launcher.swift"),
                "-target", platform.machine() + "-apple-macos12.0",
                "-o", str(binary / "Proton4Mac"), "-framework", "AppKit"], check=True)
shutil.copy2(source / "proton4mac.py", resources / "proton4mac.py")
shutil.copy2(source / "LICENSE", resources / "LICENSE.Proton4Mac")
shutil.copy2(source.parent / "LICENSE.proton", resources / "LICENSE.proton")
with (bundle / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleExecutable": "Proton4Mac", "CFBundleIdentifier": "org.proton4mac.launcher",
                  "CFBundleName": "Proton4Mac", "CFBundlePackageType": "APPL",
                  "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
                  "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "12.0"}, stream)
subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
print(bundle)
