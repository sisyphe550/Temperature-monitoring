#!/usr/bin/env python3
"""Enforce the exploration's pure Swift logic gate, not hardware coverage."""
import json
import pathlib
import sys

paths = list(pathlib.Path("prototypes/sensor-probe/.build").glob("*/debug/codecov/SensorProbe.json"))
if len(paths) != 1:
    raise SystemExit(f"Expected one Swift coverage report, found {len(paths)}")
report = json.loads(paths[0].read_text())
files = [file for unit in report["data"] for file in unit["files"]
         if "/Sources/ProbeCore/" in file["filename"]]
if not files:
    raise SystemExit("No ProbeCore coverage data")
covered = sum(file["summary"]["lines"]["covered"] for file in files)
total = sum(file["summary"]["lines"]["count"] for file in files)
ratio = covered / total if total else 0
print(f"ProbeCore line coverage: {covered}/{total} = {ratio:.2%}")
print("Scope: Sources/ProbeCore/*.swift. Hardware bridge and CLI require real-machine evidence; not included.")
sys.exit(0 if ratio >= 0.8 else 1)
