#!/usr/bin/env python3
"""Local red/green checks for unique handoff-docs / probe-tests names."""

from __future__ import annotations

import copy
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

    real_load = handoff.load_json
    defaults = real_load(handoff.CONTRACTS / "defaults-v1.json")
    profile = real_load(handoff.CONTRACTS / "first-profile-v1.json")
    for key, wrong_value in (("threshold_c", 89.0), ("duration_seconds", 6),
                             ("recovery_hysteresis_c", 4.0), ("recovery_duration_seconds", 9),
                             ("notification_cooldown_seconds", 59), ("event_limit", 51)):
        broken = copy.deepcopy(defaults)
        broken["cpu_warning"][key] = wrong_value
        handoff.load_json = lambda path: broken if path.name == "defaults-v1.json" else profile
        handoff.ERRORS.clear()
        handoff.validate_contract_values()
        expect(any("cpu_warning" in error for error in handoff.ERRORS),
               f"warning gate accepted changed {key}")
    handoff.load_json = real_load
    handoff.ERRORS.clear()

    result = subprocess.run([sys.executable, str(ROOT / "scripts/validate-handoff.py")], cwd=ROOT)
    expect(result.returncode == 0, "current tree must pass validate-handoff.py")
    print("handoff-docs gate checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
