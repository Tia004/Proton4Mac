#!/usr/bin/env python3
"""Inventory every supplied source file and record absent submodule sources."""
import argparse
import configparser
import hashlib
import json
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source = args.source.resolve()
files = []
patterns = re.compile(r"/proc/|LD_LIBRARY_PATH|linux-gnu|target-os=linux|steamclient\.so|__APPLE__|pressure-vessel")
findings = []
for path in sorted(source.rglob("*")):
    relative = path.relative_to(source)
    if not path.is_file() or any(part in (".git", "build", "__pycache__") for part in relative.parts):
        continue
    data = path.read_bytes()
    files.append({"path": str(relative), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    if b"\0" not in data:
        for line_no, line in enumerate(data.decode("utf-8", errors="replace").splitlines(), 1):
            if patterns.search(line):
                findings.append({"path": str(relative), "line": line_no, "text": line[:240]})
modules = configparser.ConfigParser()
modules.read(source / ".gitmodules")
submodules = [{"path": modules[s]["path"], "url": modules[s]["url"],
               "sources_present": any(f["path"].startswith(modules[s]["path"] + "/") for f in files)}
              for s in modules.sections()]
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps({"scope": "File inventory and portability pattern scan, not full semantic review",
                                  "files_total": len(files), "files": files,
                                  "submodules": submodules, "portability_findings": findings}, indent=2) + "\n")
print(json.dumps({"files": len(files), "submodules": len(submodules),
                  "missing_submodules": sum(not m["sources_present"] for m in submodules),
                  "portability_findings": len(findings)}))
