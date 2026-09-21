#!/usr/bin/env python3
"""Enforce ≥80% line coverage on TemperatureCore and SensorRuntime production Swift."""

from __future__ import annotations

import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages/TemperatureCore"
THRESHOLD = 0.8
INCLUDED = ("/Sources/TemperatureCore/", "/Sources/SensorRuntime/")
EXCLUDED = (
    "/Tests/",
    "/Sources/SensorBridge/",
    "/Sources/SensorWorker/",
    "/Sources/CSQLite/",
    "resource_bundle_accessor.swift",
)


def coverage_files(report: dict) -> list[dict]:
    files = [file for unit in report.get("data", []) for file in unit.get("files", [])]
    selected = []
    for file in files:
        name = file.get("filename", "")
        if any(token in name for token in EXCLUDED):
            continue
        if any(token in name for token in INCLUDED) and name.endswith(".swift"):
            selected.append(file)
    return selected


def summarize(files: list[dict]) -> tuple[int, int, list[str]]:
    covered = 0
    total = 0
    lines = []
    for file in files:
        summary = file["summary"]["lines"]
        file_covered = summary["covered"]
        file_total = summary["count"]
        covered += file_covered
        total += file_total
        lines.append(f"{file['filename']}: {file_covered}/{file_total}")
    return covered, total, lines


def load_report() -> dict:
    paths = list(PACKAGE.glob(".build/*/debug/codecov/*.json"))
    paths = [path for path in paths if path.name.lower().startswith("temperaturecore")]
    if not paths:
        paths = list(PACKAGE.glob(".build/*/debug/codecov/*.json"))
    if not paths:
        raise SystemExit("No TemperatureCore coverage report; run swift test --enable-code-coverage")
    return json.loads(paths[0].read_text())


def evaluate(report: dict) -> int:
    files = coverage_files(report)
    if not files:
        print("No TemperatureCore/SensorRuntime production Swift coverage data", file=sys.stderr)
        return 1
    covered, total, details = summarize(files)
    ratio = covered / total if total else 0
    print("Core line coverage: {}/{} = {:.2%}".format(covered, total, ratio))
    print("Scope: Sources/TemperatureCore and Sources/SensorRuntime production Swift.")
    print("Excluded: tests, App UI, C bridge, worker entry, CSQLite.")
    for line in details:
        print(line)
    return 0 if ratio >= THRESHOLD else 1


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "--report":
        report = json.loads(pathlib.Path(sys.argv[2]).read_text())
        return evaluate(report)
    return evaluate(load_report())


if __name__ == "__main__":
    raise SystemExit(main())
