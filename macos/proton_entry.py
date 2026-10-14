#!/usr/bin/env python3
"""Adapt Proton's command-line verbs to the separate macOS launcher."""
import os
from pathlib import Path
import sys

from proton4mac import main


def translate(argv, env):
    if len(argv) < 2 or argv[0] not in ("run", "waitforexitandrun"):
        raise ValueError("Su macOS: ./proton run /percorso/gioco.exe [argomenti]. "
                         "L'integrazione con Steam per Mac non è ancora disponibile.")
    result = []
    if env.get("STEAM_COMPAT_DATA_PATH"):
        # Separate storage: never migrate or overwrite an existing Linux pfx.
        result += ["--root", str(Path(env["STEAM_COMPAT_DATA_PATH"]).expanduser() / "proton4mac")]
    result += ["run", "--prefix", env.get("PROTON4MAC_PREFIX") or env.get("SteamAppId") or "default"]
    if argv[0] == "waitforexitandrun":
        result += ["--wait-for-exit"]
    return result + argv[1:]


if __name__ == "__main__":
    try:
        sys.exit(main(translate(sys.argv[1:], os.environ)))
    except ValueError as exc:
        print("Proton4Mac: " + str(exc), file=sys.stderr)
        sys.exit(1)
