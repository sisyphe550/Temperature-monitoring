#!/usr/bin/env python3
"""Gate tests for W09 product qualification schema and runner guardrails."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run-hardware-qualification.sh"
APP = ROOT / "build" / "TemperatureMonitor.app"
PROFILE = ROOT / "docs" / "contracts" / "first-profile-v1.json"
MODULE = ROOT / "scripts" / "product_qualification.py"


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT)
    if check and result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {' '.join(command)}\n"
            f"stdout={result.stdout}\nstderr={result.stderr}"
        )
    return result


def test_dry_run_collects_four_platform_sections() -> None:
    if not APP.is_dir():
        raise AssertionError("build/TemperatureMonitor.app missing; run scripts/build-app.sh first")
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "qualification"
        result = run(
            ["bash", str(RUNNER), "--app", str(APP), "--profile", str(PROFILE), "--suite", "dry-run", "--output", str(output)]
        )
        assert result.returncode == 0, result.stderr
        report = json.loads((output / "platform.json").read_text(encoding="utf-8"))
        for section in ("build_toolchain", "deployment_target", "runtime_profile", "qualified_combinations"):
            assert section in report, section
        assert report["qualified_combinations"] == []
        assert report["execution_backend"] == "TemperatureMonitor.app"
        summary = run(["python3", str(ROOT / "scripts" / "summarize-product-qualification.py"), "--input", str(output.parent)])
        assert summary.returncode == 0


def test_missing_section_fails_validation() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    from product_qualification import validate_report  # type: ignore

    report = {
        "schema_version": 1,
        "artifact_kind": "product-hardware-qualification",
        "suite": "dry-run",
        "execution_backend": "TemperatureMonitor.app",
        "build_toolchain": {},
        "deployment_target": {},
        "runtime_profile": {},
    }
    errors = validate_report(report)
    assert any("qualified_combinations" in error for error in errors)


def test_load_command_mismatch_fails() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    from product_qualification import validate_report  # type: ignore

    report = {
        "schema_version": 1,
        "artifact_kind": "product-hardware-qualification",
        "suite": "dry-run",
        "execution_backend": "TemperatureMonitor.app",
        "build_toolchain": {
            "xcode_version": "Xcode 16",
            "swift_version": "Swift 6",
            "sdk_version": "15.5",
            "host_product_version": "15.7.3",
            "host_build_version": "24G419",
        },
        "deployment_target": {
            "configured_macosx_deployment_target": "15.7.3",
            "architectures": {"app": ["arm64"], "worker": ["arm64"]},
            "app_load_command": {"platform": "1", "minos": "15.7.3", "sdk": "15.5"},
            "worker_load_command": {"platform": "1", "minos": "15.0", "sdk": "15.5"},
            "load_commands_match_configuration": False,
        },
        "runtime_profile": {
            "profile_id": "Mac16,13-m4-v1",
            "profile_version": 1,
            "profile_sha256": "a" * 64,
            "bundled_profile_sha256": "a" * 64,
            "profile_matches_bundle": True,
            "model_identifier": "Mac16,13",
            "host_product_version": "15.7.3",
            "host_build_version": "24G419",
            "minimum_os": "15.7.3",
            "cpu_key_count": 12,
        },
        "qualified_combinations": [],
    }
    errors = validate_report(report)
    assert any("load commands" in error for error in errors)


def test_use_probe_is_rejected() -> None:
    with tempfile.TemporaryDirectory() as directory:
        result = run(
            [
                "bash",
                str(RUNNER),
                "--app",
                str(APP),
                "--profile",
                str(PROFILE),
                "--suite",
                "dry-run",
                "--output",
                str(Path(directory) / "blocked"),
                "--use-probe",
            ],
            check=False,
        )
        assert result.returncode == 1
        assert "sensor-probe" in result.stderr


def test_validate_sources_report_fixture() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    from product_qualification import validate_sources_report  # type: ignore

    fixture = {
        "artifactKind": "product-hardware-sources",
        "cpuExpectedCount": 12,
        "cpuAvailableCount": 12,
        "cpuKeys": [
            {
                "rawKey": key,
                "status": "available",
                "encoding": "flt ",
                "byteCount": 4,
            }
            for key in [
                "Te05",
                "Te0S",
                "Te09",
                "Te0H",
                "Tp01",
                "Tp05",
                "Tp09",
                "Tp0D",
                "Tp0V",
                "Tp0Y",
                "Tp0b",
                "Tp0e",
            ]
        ],
        "ssd": {"status": "unavailable", "kind": "ssd"},
        "battery": {"status": "selected", "kind": "battery"},
        "mappingAndFreshness": "not inferred from names or repeated values",
    }
    assert validate_sources_report(fixture) == []


def test_full_suite_rejects_probe_backend() -> None:
    probe_dir = ROOT / "prototypes" / "sensor-probe" / ".build" / "release"
    probe_dir.mkdir(parents=True, exist_ok=True)
    probe = probe_dir / "sensor-probe"
    probe.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    probe.chmod(0o755)
    try:
        with tempfile.TemporaryDirectory() as directory:
            result = run(
                [
                    "bash",
                    str(RUNNER),
                    "--app",
                    str(APP),
                    "--profile",
                    str(PROFILE),
                    "--suite",
                    "full",
                    "--output",
                    str(Path(directory) / "blocked"),
                ],
                check=False,
            )
            assert result.returncode == 1
            assert "sensor-probe" in result.stderr
    finally:
        probe.unlink(missing_ok=True)
        if probe_dir.exists() and not any(probe_dir.iterdir()):
            shutil.rmtree(probe_dir, ignore_errors=True)


def main() -> int:
    tests = [
        test_dry_run_collects_four_platform_sections,
        test_missing_section_fails_validation,
        test_load_command_mismatch_fails,
        test_use_probe_is_rejected,
        test_validate_sources_report_fixture,
        test_full_suite_rejects_probe_backend,
    ]
    for test in tests:
        test()
    print(f"product qualification schema: {len(tests)} checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
