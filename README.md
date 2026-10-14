# Proton4Mac

Experimental macOS launcher in a fork of Valve's Proton 11.0. Free source code,
no CrossOver dependency. **This is an initial working launcher, not a complete
port of Valve's Wine, DXVK, vkd3d-proton or Steam Play to macOS.**

The macOS path uses an independently installed Darwin Wine runtime. On Linux,
the original Proton launcher still follows its upstream path. The original
build instructions are in [README.proton.md](README.proton.md).

## What works so far

- Native macOS app: select a Windows executable and choose an environment name.
- Separate Wine prefixes; an installer and its game can share the same name.
- Explicit runtime selection, diagnostics, prefix locking and exit status forwarding.
- `./proton run game.exe` and `waitforexitandrun` dispatch to the macOS launcher.
- Real Windows x64 probes: `cmd`, OpenGL pixel readback and Direct3D 9 frame
  clear/readback/presentation passed on an M1 Max, using free Wine 10.0.

Game compatibility and performance must be tested per game. There is no native
Mac Steam Play registration, bundled macOS build of Valve's Wine, verified
DXVK/vkd3d stack, DirectX 12 validation, or base M1/A18 Pro performance result.
Windows x86 files are accepted but only x64 execution has been tested.

## Try it on macOS

Requires Python 3 and Wine built for macOS. On Apple Silicon the tested Wine
runtime also requires Rosetta. Installing prerequisites is a separate step;
the launcher does not install software automatically.

The [Homebrew wine-stable cask](https://github.com/Homebrew/homebrew-cask/blob/master/Casks/w/wine-stable.rb)
is currently disabled (since 1 September 2026, Gatekeeper check failure).
This prototype was tested with an existing Wine 10.0 installation. It does not
provide a verified fresh-runtime installation procedure or bypass macOS checks.
If you have a compatible Darwin Wine runtime already, point `--wine` to it and
run the diagnostic before launching anything:

```sh
python3 macos/proton4mac.py doctor
python3 macos/proton4mac.py run --prefix my-game '/path/to/game.exe'
# Equivalent macOS entry through the fork's original launcher:
PROTON4MAC_PREFIX=my-game ./proton run '/path/to/game.exe'
```

Game arguments follow the executable. The launcher starts in the executable's
directory, preserving arguments as separate values rather than shell commands.
The game receives a minimal host environment rather than terminal/agent API credentials.

For a native app, build with Xcode/Command Line Tools:

```sh
python3 macos/build_app.py
open macos/build/Proton4Mac.app
```

The app is compiled for the build machine and signed locally; this is not a
notarized universal release. It uses Python and Wine installed on the machine.
Use **Scegli file…**, give the game's environment a name, then **Avvia**.
Use the same name for the game's installer and installed executable.

Prefixes live in `~/Library/Application Support/Proton4Mac/prefixes/`; app logs
live in the adjacent `logs/` directory. These are separate Wine environments,
not security sandboxes. No existing Wine/CrossOver prefix is imported or migrated.
An explicit `STEAM_COMPAT_DATA_PATH` uses a separate `proton4mac/` subdirectory;
this CLI convention does not establish native Steam integration.

Select a different runtime with `--wine /path/to/wine` before the subcommand,
or `PROTON4MAC_WINE`. A prefix cannot silently switch to another runtime path.
The first initialization can take up to two minutes.

## Development and evidence

```sh
python3 -m unittest discover -s macos/tests -v
python3 macos/tests/build_probe.py  # requires clang and LLVM's Windows linker
python3 macos/tests/run_probes.py
```

See [the source audit](macos/docs/PORTING.md) and [validation report](macos/docs/VALIDATION.md).
The macOS app and local logs are excluded from Git; CI builds the app and tests
the launcher without pretending that synthetic tests certify game compatibility.

## Licensing

New macOS code uses [BSD-3-Clause](macos/LICENSE). Upstream Proton and each
submodule retain their own licenses and notices. Wine and any graphics runtime
must be obtained and redistributed under their respective licenses. This fork
is independent and is not endorsed by Valve, Apple or CodeWeavers.
