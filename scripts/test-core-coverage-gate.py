#!/usr/bin/env python3
"""Red fixture: coverage below 80% must fail the core gate."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def report(covered: int, total: int) -> dict:
    return {
        "data": [
            {
                "files": [
                    {
                        "filename": "/workspace/Packages/TemperatureCore/Sources/TemperatureCore/Clock.swift",
                        "summary": {"lines": {"covered": covered, "count": total}},
                    }
                ]
            }
        ]
    }


def run(path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ROOT / "scripts/check-core-coverage.py"), "--report", str(path)],
        capture_output=True,
        text=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory() as directory:
        low = Path(directory) / "low.json"
        high = Path(directory) / "high.json"
        empty = Path(directory) / "empty.json"
        low.write_text(json.dumps(report(7, 10)))
        high.write_text(json.dumps(report(8, 10)))
        empty.write_text(json.dumps({"data": [{"files": []}]}))
        failed = run(low)
        passed = run(high)
        missing = run(empty)
        if failed.returncode == 0:
            raise SystemExit("expected 70% coverage to fail")
        if passed.returncode != 0:
            raise SystemExit(f"expected 80% coverage to pass: {passed.stdout}{passed.stderr}")
        if missing.returncode == 0:
            raise SystemExit("expected empty production file set to fail")
        print("core coverage fixtures passed")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
