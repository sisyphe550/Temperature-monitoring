#!/usr/bin/env python3
"""Red fixture: unregistered copied/modified paths must fail the registration gate."""

from __future__ import annotations

import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "docs" / "contracts" / "third-party-v1.json"
FIXTURE = ROOT / "Packages/TemperatureCore/Sources/SensorBridge/UnregisteredFixture.c"


def registered_paths(contract_path: Path) -> set[str]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    paths: set[str] = set()
    for row in contract.get("imports", []):
        for local_path in row.get("local_paths", []):
            paths.add(local_path)
    return paths


def gate_should_fail() -> bool:
    relative = str(FIXTURE.relative_to(ROOT))
    return FIXTURE.is_file() and relative not in registered_paths(CONTRACT)


def main() -> int:
    FIXTURE.write_text("// red fixture: must fail registration gate\n", encoding="utf-8")
    try:
        if not gate_should_fail():
            raise SystemExit("expected unregistered copied fixture to fail gate")
        print("upstream boundary fixtures passed")
        return 0
    finally:
        FIXTURE.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
