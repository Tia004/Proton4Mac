# Validation — 15 October 2026

Local machine: Apple M1 Max, 32 GB RAM, macOS 27.0 (26A428).
Runtime: independently installed Wine Stable 10.0 with Rosetta available.
Wine's logs report MoltenVK 1.3.0. Valve's pinned Wine submodule was not built.

| Check | Observed result | Boundary |
| --- | --- | --- |
| Launcher unit tests | 11 tests passed | Prefix safety, locking, PE filtering, arguments, retries, timeout and exit codes |
| Native app | Built, locally signed, inspected and exercised via its chooser and Avvia button | Local build, not notarized distribution |
| Windows cmd | `PROTON4MAC_OK`, exit 0 | Process execution only |
| Windows x64 OpenGL probe | Exit 0, expected RGB pixel read back | One WGL context and clear, no shaders/gameplay |
| Windows x64 D3D9 probe | Exit 0, expected backbuffer color, successful present | Built-in Wine D3D9, no DXVK or shader workload |
| Original `proton run` entry | D3D9 probe exit 0 through Darwin dispatch | CLI integration, not native Steam Play |
| Baking Bad default/Vulkan | Engine and bundled .NET load; initial title screen rendered | Shader, scene and signal errors remain; no stable gameplay/FPS claim |
| Baking Bad OpenGL attempt | OpenGL 4.1 context starts, then page fault during resource/effect loading | Failed compatibility attempt; not recommended as a fix |
| Baking Bad Vulkan one-frame capture | Exit 0; PNG shows title and “Press Space To Enter” | A rendered title screen only; no inputs or gameplay certified |
| Stray | Not executed | RAR and extracted game are iCloud placeholders; bounded header read timed out |
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
