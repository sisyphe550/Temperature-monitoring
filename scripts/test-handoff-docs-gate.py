#!/usr/bin/env python3
"""Local red/green checks for unique handoff-docs / probe-tests names."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_handoff():
    path = ROOT / "scripts/validate-handoff.py"
    spec = importlib.util.spec_from_file_location("handoff", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def main() -> int:
    handoff = load_handoff()
    good = """
on:
  push:
    branches: [main]
  pull_request:

jobs:
  handoff-docs:
    name: handoff-docs
    runs-on: macos-15
"""
    expect(handoff.parse_job_check_names(good) == ["handoff-docs"], "parser missed unique job name")
    renamed = good.replace("name: handoff-docs", "name: docs-check")
    expect(handoff.parse_job_check_names(renamed) == ["docs-check"], "parser missed renamed job")

    result = subprocess.run([sys.executable, str(ROOT / "scripts/validate-handoff.py")], cwd=ROOT)
    expect(result.returncode == 0, "current tree must pass validate-handoff.py")
    print("handoff-docs gate checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
