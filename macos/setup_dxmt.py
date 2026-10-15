#!/usr/bin/env python3
"""Install a private, optional DXMT engine from a verified official archive.

Does not edit the source Wine installation or change existing game prefixes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile

VERSION = "0.80"
SHA256 = "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
URL = "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True, help="Official dxmt-v0.80-builtin.tar.gz")
    parser.add_argument("--wine-root", type=Path, required=True, help="Existing Darwin Wine root containing bin/wine and lib/wine")
    parser.add_argument("--destination", type=Path, default=Path.home() / "Library/Application Support/Proton4Mac/runtimes/dxmt-v0.80")
    args = parser.parse_args()
    if platform.system() != "Darwin" or int(platform.mac_ver()[0].split('.')[0]) < 14:
        parser.error("DXMT requires macOS 14 or newer")
    source = args.wine_root.resolve(); destination = args.destination.expanduser().resolve()
    if destination.exists():
        parser.error("Destination already exists; no runtime was overwritten")
    if not (source / "bin/wine").is_file() or not (source / "lib/wine/x86_64-unix/winemac.so").is_file():
        parser.error("A compatible x86_64 Darwin Wine installation is required")
    if hashlib.sha256(args.archive.read_bytes()).hexdigest() != SHA256:
        parser.error("Archive checksum differs from the pinned official release")
    version = subprocess.check_output([str(source / "bin/wine"), "--version"], text=True).strip()
    # Do not accept arbitrary Wine 11 binaries: our exact build adapts the
    # changed window layout to the pinned DXMT Unix ABI.
    if version != "wine-10.0":
        manifest_file = source / "proton4mac-runtime.json"
        try:
            manifest = json.loads(manifest_file.read_text())
        except (OSError, ValueError):
            manifest = {}
        if not (version == "wine-11.0" and manifest.get("wine_revision") == "e60892cc2398b0a83c332a2078c7b85e47bdb42b"
                and "0008-dxmt-window-abi.patch" in manifest.get("patches", {})):
            parser.error("Use wine-10.0 or Proton4Mac's pinned Valve Wine 11 build with its DXMT ABI adapter")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".dxmt-", dir=destination.parent) as work:
        work = Path(work)
        with tarfile.open(args.archive) as archive:
            members = archive.getmembers()
            for member in members:
                path = Path(member.name)
                if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
                    parser.error("Unexpected member in the runtime archive")
            # Member names/types have been checked; compatible with Python 3.9+.
            archive.extractall(work / "archive", members=members)
        runtime = work / "runtime"
        # APFS clones give separate inodes: replacing files never edits the
        # existing Wine installation, and ordinary dependencies aren't duplicated.
        subprocess.run(["/bin/cp", "-cR", str(source), str(runtime)], check=True)
        overlay = work / "archive" / ("v" + VERSION)
        for architecture in ("x86_64-windows", "i386-windows", "x86_64-unix"):
            expected = ("winemetal.so",) if architecture.endswith("unix") else ("d3d11.dll", "dxgi.dll", "d3d10core.dll", "winemetal.dll")
            for filename in expected:
                original = overlay / architecture / filename
                if not original.is_file():
                    parser.error("Missing DXMT module: " + str(original))
                target = runtime / "lib/wine" / architecture / filename
                if target.exists() or target.is_symlink():
                    target.unlink()
                shutil.copy2(original, target)
        (runtime / "proton4mac-engine.json").write_text(json.dumps({
            "name": "DXMT", "version": VERSION, "base_wine": version,
            "base_source": str(source), "archive_url": URL, "archive_sha256": SHA256,
            "license": "https://github.com/3Shain/dxmt/blob/v0.80/LICENSE",
            "scope": "D3D11 synthetic clear/readback/present tested; game compatibility varies"
        }, indent=2) + "\n")
        shutil.copy2(Path(__file__).with_name("licenses") / "DXMT-LICENSE", runtime / "LICENSE.DXMT")
        runtime.rename(destination)
    print(destination)


if __name__ == "__main__":
    main()
