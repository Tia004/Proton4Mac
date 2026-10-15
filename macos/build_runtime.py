#!/usr/bin/env python3
"""Reproduce the experimental Darwin build of Proton 11's pinned Valve Wine.

No runtime is activated automatically. Dependencies must already be installed.
The resulting build is for development, not a redistributable release bundle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parent
REPOSITORY = SOURCE.parent
WINE_REVISION = "e60892cc2398b0a83c332a2078c7b85e47bdb42b"


def run(argv, **kwargs):
    subprocess.run([str(item) for item in argv], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deps", type=Path, required=True, help="Directory of existing x86_64 Darwin dependency dylibs")
    parser.add_argument("--freetype-include", type=Path, required=True, help="Directory containing ft2build.h")
    parser.add_argument("--llvm-bin", type=Path, default=Path("/opt/homebrew/opt/llvm/bin"))
    parser.add_argument("--bison-bin", type=Path, default=Path("/opt/homebrew/opt/bison/bin"))
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--phase", choices=("configure", "build", "install", "all"), default="all")
    parser.add_argument("--build-dir", type=Path, default=SOURCE / "build/valve-wine64")
    parser.add_argument("--prefix", type=Path, default=SOURCE / "build/valve-runtime")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("A macOS host with Apple Command Line Tools is required")
    if not 1 <= args.jobs <= 16:
        parser.error("--jobs must be between 1 and 16")
    wine = REPOSITORY / "wine"
    if not (wine / "configure.ac").exists():
        parser.error("Initialize the pinned wine submodule first: git submodule update --init wine")
    revision = subprocess.check_output(["git", "-C", str(wine), "rev-parse", "HEAD"], text=True).strip()
    if revision != WINE_REVISION:
        parser.error("Wine revision differs from the tested Proton 11 source pin")
    for path in [args.deps / "libfreetype.dylib", args.freetype_include / "ft2build.h", args.llvm_bin / "clang", args.bison_bin / "bison"]:
        if not path.exists():
            parser.error("Missing dependency: " + str(path))
    build = args.build_dir.resolve(); build.mkdir(parents=True, exist_ok=True)
    if any(c.isspace() for c in str(build)):
        parser.error("Wine's development build directory must not contain whitespace")
    dependencies = build / "dependencies"
    if dependencies.is_symlink():
        if dependencies.resolve() != args.deps.resolve():
            parser.error("The build directory is already associated with other dependencies")
    elif dependencies.exists():
        parser.error("Unexpected existing dependencies directory")
    else:
        dependencies.symlink_to(args.deps.resolve(), target_is_directory=True)
    # Darwin tools may link dependency install names such as libfreetype.dylib.
    # /usr/bin/make strips inherited DYLD_*; expose only these explicit build
    # dependencies in its working directory rather than changing global paths.
    for dependency in args.deps.resolve().glob("*.dylib"):
        link = build / dependency.name
        if not link.exists() and not link.is_symlink():
            link.symlink_to(dependency)
    if shutil.disk_usage(build).free < 4 * 1024**3:
        parser.error("At least 4 GiB of free space are required to continue this development build")
    patches = sorted((SOURCE / "patches/wine").glob("*.patch"))
    for patch in patches:
        check = subprocess.run(["git", "apply", "--check", str(patch)], cwd=wine, capture_output=True)
        if check.returncode == 0:
            run(["git", "apply", patch], cwd=wine)
        else:
            reverse = subprocess.run(["git", "apply", "--reverse", "--check", str(patch)], cwd=wine, capture_output=True)
            if reverse.returncode:
                parser.error("Patch conflicts with the source tree: " + patch.name)
    env = os.environ.copy()
    env["PATH"] = os.pathsep.join([str(args.bison_bin.resolve()), str(args.llvm_bin.resolve()), "/opt/homebrew/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    env.update(CC="/usr/bin/clang -arch x86_64", CXX="/usr/bin/clang++ -arch x86_64",
               LDFLAGS="-L" + str(dependencies) + " -Wl,-rpath," + str(dependencies),
               FREETYPE_CFLAGS="-I" + str(args.freetype_include.absolute()),
               FREETYPE_LIBS="-L" + str(dependencies) + " -lfreetype")
    configure = [wine / "configure", "--build=x86_64-apple-darwin", "--host=x86_64-apple-darwin",
                 "--enable-win64", "--enable-archs=i386,x86_64", "--disable-tests", "--without-x", "--without-wayland",
                 "--with-mingw=" + str((args.llvm_bin / "clang").resolve()), "--prefix=" + str(args.prefix.resolve())]
    if args.phase in ("configure", "all"):
        run([wine / "autogen.sh"], cwd=wine, env=env)
        run(configure, cwd=build, env=env)
    elif not (build / "Makefile").exists():
        parser.error("Configure this build directory first with --phase configure")
    if args.phase in ("build", "install", "all"):
        run(["make", "depend"], cwd=build, env=env)
    if args.phase in ("build", "all"):
        run(["make", "-j" + str(args.jobs)], cwd=build, env=env)
    if args.phase in ("install", "all"):
        run(["make", "install"], cwd=build, env=env)
    manifest = {"wine_revision": revision, "phase_completed": args.phase,
                "configure": [str(x) for x in configure], "dependencies": str(args.deps.resolve()),
                "patches": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in patches},
                "activated": False, "gameplay_validated": False,
                "notice": "Development build; external dylibs and their licenses are not bundled."}
    (build / "proton4mac-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.phase in ("install", "all"):
        runtime_manifest = {**manifest, "kind": "valve-development", "dependency_dir": str(args.deps.resolve())}
        (args.prefix / "proton4mac-runtime.json").write_text(json.dumps(runtime_manifest, indent=2) + "\n")
    print("Completed", args.phase, "— runtime has not been activated")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
