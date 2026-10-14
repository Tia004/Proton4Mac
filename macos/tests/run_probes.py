#!/usr/bin/env python3
"""Run real Windows probes through the launcher and save bounded evidence."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--prefix", default="validation")
parser.add_argument("--report", type=Path, default=Path("macos/build/validation.json"))
args = parser.parse_args()
source = Path(__file__).resolve().parents[1]
launcher = source / "proton4mac.py"
doctor = subprocess.run([sys.executable, str(launcher), "doctor"], capture_output=True, text=True, check=True)
results = []
commands = [("windows_cmd", ["smoke", "--prefix", args.prefix])]
for name in ("opengl", "d3d9"):
    exe = source / "build/probe" / ("win32-" + name + ".exe")
    if not exe.exists():
        parser.error("Compila i programmi di prova con macos/tests/build_probe.py")
    commands.append(("win32_" + name, ["run", "--prefix", args.prefix, str(exe)]))
for name, command in commands:
    with tempfile.TemporaryFile(mode="w+") as log:
        try:
            process = subprocess.run([sys.executable, str(launcher), *command],
                                     stdout=log, stderr=log, timeout=180, check=False)
            log.seek(0)
            text = log.read()
            results.append({"test": name, "passed": process.returncode == 0,
                            "exit_code": process.returncode,
                            "failure_log_tail": text[-4000:] if process.returncode else None})
        except subprocess.TimeoutExpired:
            results.append({"test": name, "passed": False, "error": "timeout"})
report = {"captured_at_utc": datetime.now(timezone.utc).isoformat(), "doctor": json.loads(doctor.stdout),
          "tests": results, "scope": "Synthetic API probes only. No gameplay, FPS, D3D11/D3D12 or base M1 validation."}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
sys.exit(0 if all(r["passed"] for r in results) else 1)
