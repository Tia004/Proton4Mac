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
subprocess.run(["xcrun", "swiftc", "-O", str(source / "Library.swift"), str(source / "DisplayPolicy.swift"), str(source / "Sources.swift"), str(source / "Launcher.swift"),
                "-target", platform.machine() + "-apple-macos12.0",
                "-o", str(binary / "Proton4Mac"), "-framework", "AppKit", "-framework", "WebKit"], check=True)
guard_parts = []
for architecture in ("arm64", "x86_64"):
    part = source / "build" / ("display-guard-" + architecture + ".dylib")
    subprocess.run(["xcrun", "clang", "-dynamiclib", "-fobjc-arc", "-O2", "-target",
                    architecture + "-apple-macos12.0", str(source / "DisplayGuard.m"),
                    "-framework", "AppKit", "-framework", "CoreGraphics", "-o", str(part)], check=True)
    guard_parts.append(str(part))
guard = resources / "libProton4MacDisplayGuard.dylib"
subprocess.run(["xcrun", "lipo", "-create", *guard_parts, "-output", str(guard)], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(guard)], check=True)
shutil.copy2(guard, source / "build/libProton4MacDisplayGuard.dylib")
shutil.copy2(source / "proton4mac.py", resources / "proton4mac.py")
shutil.copy2(source / "LICENSE", resources / "LICENSE.Proton4Mac")
shutil.copy2(source.parent / "LICENSE.proton", resources / "LICENSE.proton")
with (bundle / "Contents/Info.plist").open("wb") as stream:
    plistlib.dump({"CFBundleExecutable": "Proton4Mac", "CFBundleIdentifier": "org.proton4mac.launcher",
                  "CFBundleName": "Proton4Mac", "CFBundlePackageType": "APPL",
                  "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "2",
                  "CFBundleDocumentTypes": [{"CFBundleTypeName": "Windows executable", "CFBundleTypeRole": "Viewer",
                                              "LSHandlerRank": "Owner", "LSItemContentTypes": ["com.microsoft.windows-executable"],
                                              "CFBundleTypeExtensions": ["exe"]}],
                  "NSDownloadsFolderUsageDescription": "Proton4Mac legge i giochi e i loro file nella cartella Download.",
                  "NSDocumentsFolderUsageDescription": "Proton4Mac legge i giochi scelti nella cartella Documenti.",
                  "NSDesktopFolderUsageDescription": "Proton4Mac legge i giochi scelti sulla Scrivania.",
                  "NSHighResolutionCapable": True, "LSMinimumSystemVersion": "12.0"}, stream)
subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
print(bundle)
subprocess.run(["xcrun", "swiftc", str(source / "Library.swift"), str(source / "tests/LibraryTests.swift"),
                "-o", str(source / "build/library-tests")], check=True)
