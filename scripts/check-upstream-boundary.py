#!/usr/bin/env python3
"""TC-UPSTREAM-BOUNDARY: Release artifact scan and third-party registration gate."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "build" / "TemperatureMonitor.app"
MACOS = APP / "Contents" / "MacOS"
CONTRACT = ROOT / "docs" / "contracts" / "third-party-v1.json"

FORBIDDEN_BINARY_TOKENS = [
    "ProtocolWorker",
    "WORKER_SCENARIO",
    "--ui-fixture",
    "WORKER_SCENARIO=success",
]

FORBIDDEN_SOURCE_TOKENS = [
    "ProtocolWorker",
    "WORKER_SCENARIO",
    "AuthorizationExecute",
    "AppleSMCForce",
    "kSMCSupervisor",
    "SMSet",
    "command = 6",
    "command = 7",
    "command=6",
    "command=7",
    "setuid(",
    "system(",
    "popen(",
]


def fail(message: str) -> None:
    print(f"upstream-boundary: {message}", file=sys.stderr)
    raise SystemExit(1)


def strings_output(path: Path) -> str:
    result = subprocess.run(
        ["strings", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        fail(f"strings failed for {path}")
    return result.stdout


def scan_binary(path: Path) -> None:
    if not path.is_file():
        fail(f"missing binary: {path.relative_to(ROOT)}")
    haystack = strings_output(path)
    for token in FORBIDDEN_BINARY_TOKENS:
        if token in haystack:
            fail(f"{path.name}: forbidden release token {token!r}")


def validate_third_party_registration() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    imports = contract.get("imports")
    if not isinstance(imports, list) or not imports:
        fail("third-party-v1.json: imports must be a non-empty array")

    registered: set[str] = set()
    for index, row in enumerate(imports):
        if not isinstance(row, dict):
            fail(f"third-party-v1.json: imports[{index}] must be an object")
        paths = row.get("local_paths")
        if not isinstance(paths, list) or not paths:
            fail(f"third-party-v1.json: imports[{index}].local_paths must be a non-empty array")
        for local_path in paths:
            if not isinstance(local_path, str) or not local_path:
                fail(f"third-party-v1.json: imports[{index}] has invalid local path")
            if local_path in registered:
                fail(f"third-party-v1.json: duplicate local path {local_path}")
            registered.add(local_path)
            absolute = ROOT / local_path
            if not absolute.is_file():
                fail(f"third-party-v1.json: missing registered file {local_path}")

    bridge = ROOT / "Packages/TemperatureCore/Sources/SensorBridge/SensorBridge.c"
    if str(bridge.relative_to(ROOT)) not in registered:
        fail("SensorBridge.c must remain registered in third-party-v1.json")


def validate_registered_sources() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    for row in contract.get("imports", []):
        for local_path in row.get("local_paths", []):
            source = (ROOT / local_path).read_text(encoding="utf-8")
            for token in FORBIDDEN_SOURCE_TOKENS:
                if token in source:
                    fail(f"{local_path}: forbidden token {token!r} in registered source")


def validate_app_resources() -> None:
    resources = APP / "Contents" / "Resources"
    required = (
        "defaults-v1.json",
        "first-profile-v1.json",
        "third-party-v1.json",
        "ThirdPartyNotices.md",
    )
    for name in required:
        if not (resources / name).is_file():
            fail(f"missing bundled resource {name}")

    for name in ("defaults-v1.json", "first-profile-v1.json", "third-party-v1.json"):
        bundled = (resources / name).read_text(encoding="utf-8")
        canonical = (ROOT / "docs" / "contracts" / name).read_text(encoding="utf-8")
        if bundled != canonical:
            fail(f"bundled resource mismatch: {name}")


def main() -> int:
    if not APP.is_dir():
        fail("missing build/TemperatureMonitor.app; run scripts/build-app.sh first")

    scan_binary(MACOS / "TemperatureMonitor")
    scan_binary(MACOS / "SensorWorker")
    validate_app_resources()
    validate_third_party_registration()
    validate_registered_sources()

    print(
        json.dumps(
            {
                "status": "passed",
                "app": str(APP.relative_to(ROOT)),
                "binaries": ["TemperatureMonitor", "SensorWorker"],
                "forbidden_token_count": len(FORBIDDEN_BINARY_TOKENS),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
