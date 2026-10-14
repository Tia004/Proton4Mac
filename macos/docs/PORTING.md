# Source audit and macOS port boundaries

Audit date: 15 October 2026. Upstream base:
`bc896217ffcd67f892f952b010f898fe7bd0f0a1` on `proton_11.0`.

## What was actually inspected

The user-supplied archive contains 3,564 files, including hidden metadata;
`rg --files` reports 3,555 under its default filters. All 3,564 files were
inventoried with sizes and SHA-256 hashes. A portability-pattern scan found
626 matching lines. This coverage is an inventory and pattern scan, **not a
claim that every generated interface or all dependencies were semantically reviewed**.

The archive's 25 declared submodules have no source files. In particular,
`wine/`, `dxvk/`, `vkd3d-proton/`, `FEX/` and GStreamer dependencies are empty.
It is impossible to review or compile those sources from the archive alone.
The fork preserves Git history and the upstream gitlinks; full dependency
checkout and dependency-level analysis remain required for a real runtime port.
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
Win32 executable validation, process serialization, diagnostics, a native app
and reproducible synthetic rendering tests. The tested runtime is externally
installed Wine 10.0, **not the pinned Valve Wine 11 runtime**.

Wine's built-in D3D DLLs are selected explicitly. Their renderer may use OpenGL
or Vulkan according to the runtime. The D3D9 test on this machine produced
MoltenVK/Vulkan output; the separate OpenGL probe explicitly tested WGL/GL.
No DXVK DLL installation or DirectX 12 implementation has been added.

## Remaining engineering work

1. Check out the exact dependency sources and establish a reproducible Darwin
   Wine build; audit Linux-specific patches and synchronization mechanisms.
2. Compile and test lsteamclient against the actual macOS Steam client, including
   callbacks, overlay and process lifecycle. Then investigate tool discovery;
   a changed VDF alone does not prove Steam Play support on Mac.
3. Select a graphics path per API only after device feature checks and workloads.
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
