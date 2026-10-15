#!/usr/bin/env python3
"""Experimental macOS launcher; not the Linux Proton runtime."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile

VERSION = "0.2.0"
ROOT = Path.home() / "Library/Application Support/Proton4Mac"


class LauncherError(Exception):
    pass


def runtime(explicit=None):
    override = explicit or os.environ.get("PROTON4MAC_WINE")
    candidates = [override] if override else [
        str(ROOT / "runtimes/current/bin/wine"),
        shutil.which("wine"), shutil.which("wine64"),
        "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine",
        "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine",
        "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate, os.X_OK):
            return Path(candidate).resolve()
    raise LauncherError("Wine non trovato. Installa Wine per macOS oppure usa --wine /percorso/wine.")


def runtime_for_prefix(explicit, prefix):
    if explicit or os.environ.get("PROTON4MAC_WINE"):
        return runtime(explicit)
    marker = prefix / ".proton4mac.json"
    if marker.is_file():
        info = json.loads(marker.read_text())
        if isinstance(info.get("wine"), str) and info["wine"]:
            return runtime(info["wine"])
    return runtime()


def prefix_path(root, name):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,63}", name):
        raise LauncherError("Il nome deve contenere solo lettere, numeri, trattini o underscore (max 64).")
    return Path(root).expanduser().resolve() / "prefixes" / name


@contextlib.contextmanager
def prefix_lock(prefix, wait=False):
    prefix.parent.mkdir(parents=True, exist_ok=True)
    with (prefix.parent / (prefix.name + ".lock")).open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
        except BlockingIOError as exc:
            raise LauncherError("Questo ambiente è già in uso da Proton4Mac.") from exc
        yield


def display_guard():
    for path in (Path(__file__).with_name("libProton4MacDisplayGuard.dylib"),
                 Path(__file__).parent / "build/libProton4MacDisplayGuard.dylib"):
        if path.is_file():
            return path.resolve()
    raise LauncherError("Controllo display non disponibile. Ricompila l’app Proton4Mac prima di avviare giochi sul Retina.")


def environment(prefix, guard=None, wine=None):
    # Games do not need credentials belonging to the terminal/agent session.
    # Keep only the host environment required by this supported launch path.
    allowed = {"PATH", "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "TMP", "TEMP",
               "LANG", "LANGUAGE", "TZ", "DISPLAY", "XAUTHORITY", "SteamAppId", "SteamGameId"}
    env = {key: value for key, value in os.environ.items()
           if key in allowed or key.startswith("LC_") or key == "MVK_CONFIG_LOG_LEVEL"}
    env.update(WINEPREFIX=str(prefix), WINEARCH="win64", WINEDEBUG="-all")
    # Only Wine's built-in renderer has been smoke-tested by this project.
    env["WINEDLLOVERRIDES"] = "d3d8,d3d9,d3d10,d3d10_1,d3d10core,d3d11,dxgi=b"
    if guard:
        env["DYLD_INSERT_LIBRARIES"] = str(guard)
    if wine:
        root = wine.parent.parent
        manifest = root / "proton4mac-runtime.json"
        if manifest.is_file():
            info = json.loads(manifest.read_text())
            if info.get("kind") == "valve-development":
                dependencies = Path(info["dependency_dir"])
                if not dependencies.is_dir():
                    raise LauncherError("Le dipendenze di questo runtime di sviluppo non sono disponibili.")
                env["DYLD_FALLBACK_LIBRARY_PATH"] = os.pathsep.join([str(root / "lib"), str(dependencies), "/usr/local/lib", "/usr/lib"])
    return env


def execute(command, env=None, cwd=None, timeout=None, capture=False):
    try:
        if capture:
            # Wine services can inherit pipes after the launcher exits. Files
            # avoid waiting indefinitely for those background pipes to close.
            with tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as out, tempfile.TemporaryFile(mode="w+", encoding="utf-8", errors="replace") as err:
                result = subprocess.run(command, env=env, cwd=cwd, timeout=timeout,
                                        stdout=out, stderr=err, check=False)
                out.seek(0)
                err.seek(0)
                return subprocess.CompletedProcess(command, result.returncode, out.read(), err.read())
        return subprocess.run(command, env=env, cwd=cwd, timeout=timeout,
                              text=True, check=False)
    except subprocess.TimeoutExpired as exc:
        raise LauncherError("Tempo massimo superato; controlla i processi Wine e il log.") from exc
    except OSError as exc:
        raise LauncherError(str(exc)) from exc


def runtime_stamp(wine):
    try:
        binary = wine.stat()
        stamp = {"binary_size": binary.st_size, "binary_mtime_ns": binary.st_mtime_ns}
        inf = wine.parent.parent / "share/wine/wine.inf"
        if inf.is_file():
            info = inf.stat()
            stamp.update(inf_size=info.st_size, inf_mtime_ns=info.st_mtime_ns)
        return stamp
    except OSError:
        return None


def initialize(wine, prefix, guard=None):
    marker = prefix / ".proton4mac.json"
    stamp = runtime_stamp(wine)
    if prefix.exists() and not marker.exists():
        raise LauncherError("Ambiente esistente non gestito da Proton4Mac: scegli un altro nome.")
    if marker.exists():
        info = json.loads(marker.read_text())
        if info.get("wine") != str(wine):
            raise LauncherError("Questo ambiente usa un altro runtime Wine. Scegli un nuovo nome.")
        if info.get("ready") and info.get("runtime_stamp") == stamp:
            return
    prefix.mkdir(exist_ok=True)
    # Marker survives failed initialization so the operation can be retried.
    marker.write_text(json.dumps({"version": VERSION, "wine": str(wine), "ready": False, "runtime_stamp": stamp}, indent=2))
    boot_env = environment(prefix, guard, wine)
    # Initializing an environment must not wait on optional Mono/Gecko download
    # dialogs. This override is limited to wineboot, never the launched game.
    boot_env["WINEDLLOVERRIDES"] += ";mscoree,mshtml="
    try:
        result = execute([str(wine), "wineboot", "-u"], env=boot_env, timeout=120, capture=True)
    except LauncherError:
        server = wine.parent / "wineserver"
        if server.is_file():
            try:
                execute([str(server), "-k"], env=boot_env, timeout=20, capture=True)
            except LauncherError:
                pass
        raise
    if result.returncode:
        raise LauncherError("Wine non ha inizializzato l'ambiente:\n" + result.stderr[-4000:])
    marker.write_text(json.dumps({"version": VERSION, "wine": str(wine), "ready": True, "runtime_stamp": stamp}, indent=2))


def windows_executable(path):
    target = Path(path).expanduser().resolve()
    try:
        with target.open("rb") as stream:
            header = stream.read(64)
            if len(header) != 64 or header[:2] != b"MZ":
                raise LauncherError("Il file non è un eseguibile Windows PE.")
            offset = struct.unpack_from("<I", header, 60)[0]
            stream.seek(offset)
            pe = stream.read(6)
            if len(pe) != 6 or pe[:4] != b"PE\0\0":
                raise LauncherError("Intestazione Windows PE non valida.")
            if struct.unpack_from("<H", pe, 4)[0] not in (0x14C, 0x8664):
                raise LauncherError("Questa versione supporta eseguibili Windows x86 e x64.")
    except OSError as exc:
        raise LauncherError(str(exc)) from exc
    return target


def doctor(wine_override):
    result = {"version": VERSION, "system": platform.system(), "architecture": platform.machine(),
              "macos": platform.mac_ver()[0], "renderer": "Wine built-in (wined3d; runtime default)",
              "steam_native_integration": False, "dxvk_validated": False,
              "d3d12_validated": False, "wine": None, "wine_version": None, "ready": False}
    try:
        wine = runtime(wine_override)
        check = execute([str(wine), "--version"], timeout=20, capture=True)
        result.update(wine=str(wine), wine_version=check.stdout.strip(),
                      ready=check.returncode == 0 and platform.system() == "Darwin")
        if check.returncode:
            result["error"] = check.stderr.strip()
    except LauncherError as exc:
        result["error"] = str(exc)
    if platform.system() == "Darwin" and platform.machine() == "arm64":
        check = execute(["/usr/bin/arch", "-x86_64", "/usr/bin/true"], timeout=10, capture=True)
        result["rosetta_available"] = check.returncode == 0
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description="Proton4Mac: launcher Wine sperimentale per macOS")
    parser.add_argument("--wine", help="Eseguibile Wine per macOS")
    parser.add_argument("--root", type=Path, default=ROOT, help="Cartella degli ambienti")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("doctor", help="Diagnostica in JSON")
    for action in ("init", "run", "smoke", "stop"):
        p = commands.add_parser(action)
        p.add_argument("--prefix", default="default" if action != "smoke" else "smoke-test")
        p.add_argument("--display", choices=("builtin", "system"), default="builtin",
                       help="Vincola le finestre al Retina del MacBook (predefinito)")
        if action == "run":
            p.add_argument("--dry-run", action="store_true")
            p.add_argument("--wait-for-exit", action="store_true", help="Attende la chiusura delle sessioni nello stesso ambiente")
            p.add_argument("exe")
            p.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        if args.command == "doctor":
            report = doctor(args.wine)
            print(json.dumps(report, indent=2, ensure_ascii=False))
            return 0 if report["ready"] else 1
        if platform.system() != "Darwin":
            raise LauncherError("Questo launcher richiede macOS.")
        prefix = prefix_path(args.root, args.prefix)
        wine = runtime_for_prefix(args.wine, prefix)
        target = windows_executable(args.exe) if args.command == "run" else None
        command = [str(wine), str(target), *args.args] if target else None
        if args.command == "run" and args.dry_run:
            print(json.dumps({"argv": command, "cwd": str(target.parent),
                              "prefix": str(prefix), "renderer": "wined3d"}, indent=2))
            return 0
        if args.command == "stop":
            if not (prefix / ".proton4mac.json").is_file():
                raise LauncherError("Questo ambiente non è gestito da Proton4Mac.")
            server = wine.parent / "wineserver"
            stopped = execute([str(server), "-k"], env=environment(prefix, wine=wine), timeout=20, capture=True)
            # wineserver -k returns 1 without diagnostics when no server exists.
            # Stopping an already closed managed session is an idempotent action.
            if stopped.returncode == 1 and not stopped.stderr.strip():
                return 0
            if stopped.stderr:
                print(stopped.stderr, file=sys.stderr, end="")
            return stopped.returncode
        guard = display_guard() if args.display == "builtin" else None
        with prefix_lock(prefix, wait=args.command == "run" and args.wait_for_exit):
            initialize(wine, prefix, guard)
            if args.command == "init":
                print(prefix)
                return 0
            if args.command == "smoke":
                test = execute([str(wine), "cmd", "/c", "echo PROTON4MAC_OK"],
                               env=environment(prefix, guard, wine), timeout=60, capture=True)
                ok = test.returncode == 0 and "PROTON4MAC_OK" in test.stdout
                print(json.dumps({"passed": ok, "exit_code": test.returncode,
                                  "stdout": test.stdout, "stderr": test.stderr,
                                  "scope": "Windows cmd only; no game or graphics validation"}, indent=2))
                return 0 if ok else 1
            if args.wait_for_exit:
                server = wine.parent / "wineserver"
                if not server.is_file() or not os.access(server, os.X_OK):
                    raise LauncherError("wineserver non trovato accanto al runtime selezionato.")
                waiting = execute([str(server), "-w"], env=environment(prefix, guard, wine), timeout=120)
                if waiting.returncode:
                    return waiting.returncode
            return execute(command, env=environment(prefix, guard, wine), cwd=target.parent).returncode
    except (LauncherError, ValueError) as exc:
        print("Proton4Mac: " + str(exc), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
