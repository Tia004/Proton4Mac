#!/usr/bin/env python3
"""Build a small Windows x64 probe with clang/LLVM (no Windows SDK)."""
import argparse
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--llvm", type=Path, default=Path("/opt/homebrew/opt/llvm/bin"))
    parser.add_argument("--output", type=Path, default=Path("macos/build/probe"))
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    exports = {
        "kernel32": ["GetModuleHandleA", "ExitProcess", "Sleep"],
        "user32": ["DefWindowProcA", "RegisterClassA", "CreateWindowExA", "ShowWindow",
                   "GetDC", "ReleaseDC", "DestroyWindow"],
        "gdi32": ["ChoosePixelFormat", "SetPixelFormat", "SwapBuffers"],
        "opengl32": ["wglCreateContext", "wglMakeCurrent", "wglDeleteContext", "glClearColor",
                     "glClear", "glFinish", "glReadPixels"],
        "d3d9": ["Direct3DCreate9"],
    }
    for dll, symbols in exports.items():
        definition = output / (dll + ".def")
        definition.write_text("LIBRARY " + dll + ".dll\nEXPORTS\n" + "\n".join(symbols) + "\n")
        subprocess.run([str(args.llvm / "llvm-dlltool"), "-m", "i386:x86-64", "-d",
                        str(definition), "-l", str(output / (dll + ".lib"))], check=True)
    for name in ("opengl", "d3d9"):
        subprocess.run([shutil.which("clang") or "clang", "--target=x86_64-pc-windows-msvc",
                    "-ffreestanding", "-fno-stack-protector", "-c",
                    str(Path(__file__).with_name("win32_" + name + ".c")), "-o", str(output / (name + ".obj"))], check=True)
        subprocess.run([str(args.llvm / "lld-link"), "/entry:mainCRTStartup", "/subsystem:console",
                    "/nodefaultlib", "/out:" + str(output / ("win32-" + name + ".exe")),
                    str(output / (name + ".obj")), *[str(output / (dll + ".lib")) for dll in exports]], check=True)
        print(output / ("win32-" + name + ".exe"))


if __name__ == "__main__":
    main()
