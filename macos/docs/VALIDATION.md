# Validation — 15 October 2026

Local machine: Apple M1 Max, 32 GB RAM, macOS 27.0 (26A428).
Runtime: independently installed Wine Stable 10.0 with Rosetta available.
Wine's logs report MoltenVK 1.3.0. The pinned Valve Wine source was separately built and installed with eight Darwin
patches. Windows cmd, OpenGL and D3D9 passed; Valve Wine 11 + DXMT also passed the
HLSL triangle/readback/present probe.

| Check | Observed result | Boundary |
| --- | --- | --- |
| Launcher unit tests | 16 tests passed | Prefix safety, locking, PE filtering, arguments, retries, timeout and exit codes |
| Native app 0.2 | Built and locally signed; library/source UI inspected on Retina | Folder-grant, persisted grant, engine choice and log sheet exercised on Retina |
| Library persistence | 15 checks passed | PE filtering, duplicates, stable prefixes, settings, sources and corruption handling |
| `.exe` handler | Launch Services and NSWorkspace resolve installed Proton4Mac; document event auto-imported probe | Initial OS consent prompt appeared on Samsung; not an application window |
| Library launch | Windows x64 OpenGL exited 0 from Application Support; guard logged Retina display 1 | Folder grant and second launch from Downloads verified with D3D11/DXMT, exit 0 |
| Display guard | Init, resize, origin and animated resize passed for ARM64 and x86_64 hidden native probes | Runtime window observed on Retina; not all fullscreen APIs certified |
| Internal sources | Steam homepage loaded in embedded WebKit on Retina; presets and custom URL persistence tested | Local HTTP attachment saved through Retina sheet; exact contents verified |
| DXMT 0.80 / Wine 10.0 | D3D11 hardware FL11.0; clear/readback/present and a separate HLSL vertex/pixel shader draw passed, pixel 407fbfff, exit 0; managed CLI and library launch passed | Basic shader compilation/draw only; no gameplay/performance certification or D3D12 |
| Pinned Valve Wine 11 | Full build/install succeeded; Windows cmd exit 0 with empty stderr, OpenGL and D3D9 exit 0 | Development dependency bundle; not a complete Steam/Proton distribution |
| Valve Wine 11 + DXMT | HLSL draw/readback/present exit 0, pixel 407fbfff in a new prefix | Latest GUI option compiled; CLI path verified, final visual check paused by screen lock |
| Windows cmd | `PROTON4MAC_OK`, exit 0 | Process execution only |
| Windows x64 OpenGL probe | Exit 0, expected RGB pixel read back | One WGL context and clear, no shaders/gameplay |
| Windows x64 D3D9 probe | Exit 0, expected backbuffer color, successful present | Built-in Wine D3D9, no DXVK or shader workload |
| Original `proton run` entry | D3D9 probe exit 0 through Darwin dispatch | CLI integration, not native Steam Play |
| Baking Bad default/Vulkan | Engine and bundled .NET load; initial title screen rendered | Shader, scene and signal errors remain; no stable gameplay/FPS claim |
| Baking Bad OpenGL attempt | OpenGL 4.1 context starts, then page fault during resource/effect loading | Failed compatibility attempt; not recommended as a fix |
| Baking Bad Vulkan one-frame capture | Exit 0; PNG shows title and “Press Space To Enter” | A rendered title screen only; no inputs or gameplay certified |
| Stray | Not executed | RAR and extracted game are iCloud placeholders; bounded header read timed out |
| vkd3d-proton requirement query | MoltenVK 1.3.0 and 1.4.2 both lack mandatory robustBufferAccess2 and nullDescriptor on M1 Max | Blocks this D3D12 route; no D3D12 game test passed |
| Base M1 / A18 Pro | Not tested | No suitable test hardware available |

The Baking Bad title frame and raw logs are local under `macos/build/`; no game
binary, pack, or user game files are redistributed in Git. The original game
installation was not patched. Its own configuration may override command-line
resolution: the captured frame is 1920×1080 despite the requested 1280×720.

The default Vulkan log includes `OpArrayLength is not supported yet`, pipeline
cache failures and missing resource/script errors. These are observations;
not all are established as Wine bugs. A title screen and exit 0 do not prove
the remainder of the game works.

REA 6.5.0 runtime capture was attempted around the probe suite. The suite's
report shows all three probes passed, but REA returned an error because process
ownership/environment checks could not verify cleanup. It is not listed as a
successful independent REA capture. The local raw result is preserved for diagnosis.

Reproduce the synthetic tests:

```sh
python3 -m unittest discover -s macos/tests -v
python3 macos/tests/build_probe.py
python3 macos/tests/run_probes.py
```

The LLVM probe builder defaults to `/opt/homebrew/opt/llvm/bin`; use `--llvm`
for another installation. Results are saved in `macos/build/validation.json`.
CI tests launcher logic and builds the app; it does not certify Wine or games.

## Reproduction additions

Build the app before running the default Retina-constrained runtime tests, since
it also builds the universal display guard. Run `macos/build/library-tests` after
the build. [DXMT setup and D3D11 reproduction](GRAPHICS.md) describe the optional
Metal engine and the open Wine headers needed to compile the D3D11 probe. The
installed Wine application was not edited; a private copy is used for DXMT.

The desktop checks paused while the Mac was locked, then resumed after the user
unlocked it. Folder grant, its reuse, engine selection, log sheet, custom source
creation/removal and a local attachment download were exercised. The installed
app's default-handler association was rechecked and Baking Bad remains in the
library; the temporary test-game entry was removed without deleting its files.

Il [riepilogo strutturato](runtime-results.json) riporta pin, hash delle patch e
risultati sintetici dei motori provati. La selezione automatica di DXMT per i
nuovi giochi, quando installato, è coperta dai controlli della libreria.
