# Source audit and macOS port boundaries

Audit date: 15 October 2026. Upstream base:
`bc896217ffcd67f892f952b010f898fe7bd0f0a1` on `proton_11.0`.

## What was actually inspected

The user-supplied archive contains 3,564 files, including hidden metadata;
`rg --files` reports 3,555 under its default filters. All 3,564 files were
inventoried with sizes and SHA-256 hashes. A portability-pattern scan found
626 matching lines. This coverage is an inventory and pattern scan, **not a
claim that every generated interface or all dependencies were semantically reviewed**.

The original archive's 25 declared submodules have no source files. In particular,
`wine/`, `dxvk/`, `vkd3d-proton/`, `FEX/` and GStreamer dependencies are empty.
It is impossible to review or compile those sources from the archive alone.
The fork preserves Git history and the upstream gitlinks. The exact Wine, DXVK,
vkd3d-proton and Vulkan-Headers sources have now been fetched into this working
copy. Other submodules still require checkout and dependency-level analysis.
The original archive was not modified.

`source-inventory.json` is reproducible:

```sh
python3 macos/audit_sources.py /path/to/Proton-proton_11.0 \
  --output macos/docs/source-inventory.json
```

## Concrete findings

| Area | Evidence in upstream | Implication |
| --- | --- | --- |
| Launch environment | `proton` uses `LD_LIBRARY_PATH`, `lib64/wine`, Linux ABI directories | Darwin needs its own runtime layout and environment |
| Prefix maintenance | `proton` migrates Proton versions and copies Linux Steam legacy components | Do not run those migrations on ordinary Mac Wine prefixes |
| Linux diagnostics | `proton` accesses `/proc/modules` and `/proc/sys/vm/max_map_count` | These checks do not apply to Darwin |
| Build system | `configure.sh` selects a Proton SDK container; `Makefile.in` has `--target-os=linux` and Linux triples | Building this SDK on Docker for Mac still builds Linux binaries |
| Native Steam bridge | `lsteamclient/unixlib.cpp` already has `#ifdef __APPLE__` loading `steamclient.dylib` | There is useful Apple code to reuse; it is not proof of current ABI/client integration |
| EAC artifacts | `Makefile.in` installs Linux `.so` files under Linux library paths | Those artifacts cannot simply be loaded as Mac libraries |
| CPU translation | `FEX` is a gitlink; tested Darwin Wine is x86_64, executed via Rosetta | A Linux ARM64 configuration does not provide a native Apple Silicon runtime |

Pinned gitlinks in this base:

- Wine: `e60892cc2398b0a83c332a2078c7b85e47bdb42b`
- DXVK: `a6764047e587178283fcde4073ae6e1410af594f`
- vkd3d-proton: `212991fc2c266bc0d59f4c4ce8f80f7126508d71`
- FEX: `1cc4b93e7a71c883ec021b71359f136394dc1f3c`

## Implemented boundary

The original `proton` entry dispatches to `macos/proton_entry.py` only on Darwin.
The Mac code provides fresh managed prefixes, Wine detection and invocation,
Win32 executable validation, process serialization, diagnostics, a persistent native
game library, document-open events, custom web sources/download handling, per-game
engine selection, Retina window constraints and reproducible rendering tests. The tested runtime is externally
installed Wine 10.0, **not the pinned Valve Wine 11 runtime**.

Wine's built-in D3D DLLs are selected explicitly. Their renderer may use OpenGL
or Vulkan according to the runtime. The D3D9 test on this machine produced
MoltenVK/Vulkan output; the separate OpenGL probe explicitly tested WGL/GL.
An optional private Wine 10.0 engine now overlays official DXMT 0.80 modules.
A real D3D11 hardware FL11.0 clear/readback/present test passed with that engine,
including through the managed CLI launch path. No DXVK DLL installation or
DirectX 12 implementation has been added.

## Remaining engineering work

1. Finish and validate the Darwin build of the exact Valve Wine source. Eight
   concrete portability patches and a pinned, reproducible build script now exist
   in [macos/patches/wine](../patches/wine/README.md). Linux-only AMD DRM, futex,
   ntsync and CPU-topology paths are guarded; native Mach thread setup and non-EGL
   OpenGL paths are retained. The complete build now succeeds and the binary reports `wine-11.0`;
   runtime probes and installation validation remain a separate gate.
2. Compile and test lsteamclient against the actual macOS Steam client, including
   callbacks, overlay and process lifecycle. Then investigate tool discovery;
   a changed VDF alone does not prove Steam Play support on Mac.
3. Broaden the optional DXMT path from its passed D3D11 synthetic probe to shader
   workloads and real games. Select other paths only after feature checks.
   [MoltenVK](https://github.com/KhronosGroup/MoltenVK) implements a Vulkan subset
   over Metal; [DXVK's requirements](https://github.com/doitsujin/dxvk) must be
   checked against the actual implementation and hardware. Simply copying the
   Linux Proton DLLs does not establish compatibility.
4. Test audio, video, controllers and representative D3D11/D3D12 workloads.
5. Benchmark actual games on a base M1, including an 8 GB machine, with repeatable
   resolution/settings, frame times, memory pressure and thermal behavior.
6. Validate on A18 Pro hardware when available. No device-level results exist here.

REA 6.5.0 was registered for Codex with a configuration backup. Its CLI was
also used for a runtime capture attempt. Ordinary source inspection did not
require binary reverse engineering. The capture's cleanup ownership checks
were unverified, so that attempt is recorded as a limitation, not a successful
REA capture. Direct probe exit codes and readbacks are the primary evidence.

## Desktop integration and boundaries in 0.2

The macOS default handler resolves to the installed Proton4Mac bundle. A cold
document-open event imported a real first-party Windows test executable, created
a dedicated prefix and requested launch. A graphics probe launched from the
library in Application Support completed with exit 0 and its window on display 1,
the built-in Retina. Downloads-directory launches exposed an access wait; the
current app adds a one-time folder picker and persistent security-scoped bookmark.
The final folder-grant UI and engine picker were then exercised after unlock:
D3D11 through DXMT exited 0 from Downloads, and a second launch reused the saved
folder grant without another picker. No Full Disk Access setting was changed.

The launcher, source browser, panels and runtime guard target the built-in display.
The guard blocks external mode changes and captures inside the launched process.
An OS association confirmation nevertheless appeared on the Samsung during testing;
macOS owns that dialog, and the application cannot guarantee its display. This
exception is explicitly documented; a native-window constraint is not global
control over system prompts or untested game display code.

Source bookmarks include Steam, SteamRIP, Xbox/Game Pass, Xbox Cloud Gaming, GOG
and Epic, plus arbitrary HTTP(S) URLs. They do not synchronize entitlements or
make the Xbox Windows client/UWP/Gaming Services work. External URL schemes are
kept inside the app policy instead of launching another application on the Samsung.
No purchase, account login or third-party game download was performed.

## Measured DirectX 12 blocker

A read-only Vulkan capability probe ran on the M1 Max against both the existing
MoltenVK 1.3.0 and official MoltenVK 1.4.2 (private test copy, no global update).
Both report `robustBufferAccess2=false` and `nullDescriptor=false`. The pinned
vkd3d-proton's `libs/vkd3d/device.c` explicitly rejects those missing features.
Advertising the extension name alone does not meet the checks. Full results are
in [vulkan-capabilities.json](vulkan-capabilities.json), and the reproducible
probe source is `macos/tests/vulkan_caps.c`. The latest macOS release archive was
verified against SHA-256
`f95765a6229cb7b915990a2890ce12ebe36a730b021545d3d52ae69ce4c4024e`.

This is a blocker for that DirectX 12 route on the queried implementations, not
a proof that DirectX 12 is impossible on all Macs. A compatible open graphics
implementation or additional feature implementation is required. No unsupported
features are falsely enabled to make initialization appear successful.
