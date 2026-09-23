#!/usr/bin/env python3
"""Collect and validate W09 product hardware qualification platform schema."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "docs" / "contracts" / "product-qualification-v1.json"
PACKAGE = ROOT / "Packages" / "TemperatureCore"
FORBIDDEN_PROBE = ROOT / "prototypes" / "sensor-probe" / ".build" / "release" / "sensor-probe"
WORKER_FLAGS = ["-Xswiftc", "-target", "-Xswiftc", "arm64-apple-macos15.7.3"]
MIN_SCHEDULE_DURATION = int(
    __import__("os").environ.get("QUALIFICATION_MIN_SCHEDULE_SECONDS", "600")
)
DEFAULT_INTERVALS = [50, 100, 200, 500, 1000]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_command(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr.strip()}"
        )
    return result.stdout


def parse_build_version(raw: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
    return values


def parse_load_command(binary: Path) -> dict[str, str]:
    raw = run_command(["otool", "-l", str(binary)])
    blocks = re.findall(
        r"cmd LC_BUILD_VERSION\n(?:.*?\n)*?\s*platform (\d+)\n\s*minos ([0-9.]+)\n\s*sdk ([0-9.]+)",
        raw,
        re.MULTILINE,
    )
    if not blocks:
        raise RuntimeError(f"missing LC_BUILD_VERSION in {binary}")
    platform, minos, sdk = blocks[0]
    for candidate in blocks[1:]:
        if candidate != blocks[0]:
            raise RuntimeError(f"inconsistent LC_BUILD_VERSION slices in {binary}")
    return {"platform": platform, "minos": minos, "sdk": sdk}


def parse_architectures(binary: Path) -> list[str]:
    raw = run_command(["lipo", "-info", str(binary)])
    if "Non-fat file" in raw:
        match = re.search(r"architecture: (\S+)", raw)
        return [match.group(1)] if match else []
    match = re.search(r"architectures: (.+)$", raw)
    if not match:
        return []
    return [part.strip() for part in match.group(1).split()]


def configured_deployment_target() -> str:
    raw = run_command(
        [
            "xcodebuild",
            "-project",
            str(ROOT / "TemperatureMonitor.xcodeproj"),
            "-scheme",
            "TemperatureMonitor",
            "-configuration",
            "Release",
            "-showBuildSettings",
        ]
    )
    for line in raw.splitlines():
        if "MACOSX_DEPLOYMENT_TARGET =" in line:
            return line.split("=", 1)[1].strip()
    raise RuntimeError("MACOSX_DEPLOYMENT_TARGET not found in build settings")


def git_head_sha() -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
        cwd=ROOT,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def codesign_identity(app_path: Path) -> str:
    result = subprocess.run(
        ["codesign", "-dv", str(app_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    output = result.stderr + result.stdout
    match = re.search(r"Authority=(.+)", output)
    if match:
        return match.group(1).strip()
    if "Signature=adhoc" in output:
        return "adhoc"
    return "unknown"


def load_profile(profile_path: Path) -> dict[str, Any]:
    payload = json.loads(profile_path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"{profile_path}: profile must be a JSON object")
    return payload


def bundled_profile_path(app_path: Path) -> Path:
    path = app_path / "Contents" / "Resources" / "first-profile-v1.json"
    if not path.is_file():
        raise RuntimeError(f"missing bundled profile at {path}")
    return path


def host_runtime() -> dict[str, str]:
    sw_vers = parse_build_version(run_command(["sw_vers"]))
    model = run_command(["sysctl", "-n", "hw.model"]).strip()
    return {
        "model_identifier": model,
        "host_product_version": sw_vers.get("ProductVersion", ""),
        "host_build_version": sw_vers.get("BuildVersion", ""),
    }


def build_toolchain() -> dict[str, str]:
    xcode = run_command(["xcodebuild", "-version"]).strip().splitlines()
    swift = run_command(["swift", "--version"]).splitlines()[0].strip()
    sdk = run_command(["xcrun", "--show-sdk-version"]).strip()
    host = host_runtime()
    return {
        "xcode_version": xcode[0] if xcode else "",
        "xcode_build": xcode[1] if len(xcode) > 1 else "",
        "swift_version": swift,
        "sdk_version": sdk,
        "host_product_version": host["host_product_version"],
        "host_build_version": host["host_build_version"],
    }


def minos_matches_configured(minos: str, configured: str) -> bool:
    return minos == configured or minos == configured.rsplit(".", 1)[0]


def collect_platform(app_path: Path, profile_path: Path, suite: str) -> dict[str, Any]:
    app_path = app_path.resolve()
    profile_path = profile_path.resolve()
    app_binary = app_path / "Contents" / "MacOS" / "TemperatureMonitor"
    worker_binary = app_path / "Contents" / "MacOS" / "SensorWorker"
    for path in (app_path, app_binary, worker_binary, profile_path):
        if not path.exists():
            raise RuntimeError(f"missing required path: {path}")

    configured = configured_deployment_target()
    app_load = parse_load_command(app_binary)
    worker_load = parse_load_command(worker_binary)
    load_commands_match = (
        minos_matches_configured(app_load["minos"], configured)
        and minos_matches_configured(worker_load["minos"], configured)
        and app_load["minos"] == worker_load["minos"]
    )

    profile = load_profile(profile_path)
    bundled_profile = bundled_profile_path(app_path)
    profile_sha = sha256_file(profile_path)
    bundled_sha = sha256_file(bundled_profile)
    host = host_runtime()
    cpu_keys = profile.get("cpu_keys", [])
    if not isinstance(cpu_keys, list):
        raise RuntimeError("profile cpu_keys must be an array")

    return {
        "schema_version": 1,
        "artifact_kind": "product-hardware-qualification",
        "recorded_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "source_tree_sha": git_head_sha(),
        "suite": suite,
        "execution_status": "schema_validated" if suite == "dry-run" else "pending",
        "app_path": str(app_path),
        "app_sha256": sha256_file(app_binary),
        "worker_sha256": sha256_file(worker_binary),
        "codesign_identity": codesign_identity(app_path),
        "build_toolchain": build_toolchain(),
        "deployment_target": {
            "configured_macosx_deployment_target": configured,
            "architectures": {
                "app": parse_architectures(app_binary),
                "worker": parse_architectures(worker_binary),
            },
            "app_load_command": app_load,
            "worker_load_command": worker_load,
            "load_commands_match_configuration": load_commands_match,
        },
        "runtime_profile": {
            "profile_id": profile.get("profile_id", ""),
            "profile_version": profile.get("profile_version"),
            "profile_sha256": profile_sha,
            "bundled_profile_sha256": bundled_sha,
            "profile_matches_bundle": profile_sha == bundled_sha,
            "model_identifier": host["model_identifier"],
            "profile_model": profile.get("model", ""),
            "host_product_version": host["host_product_version"],
            "host_build_version": host["host_build_version"],
            "minimum_os": profile.get("observed_os", ""),
            "cpu_key_count": len(cpu_keys),
        },
        "qualified_combinations": [],
    }


def validate_report(report: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    required_sections = contract["required_sections"]
    for section in required_sections:
        if section not in report:
            errors.append(f"missing required section: {section}")

    toolchain = report.get("build_toolchain", {})
    if not isinstance(toolchain, dict):
        errors.append("build_toolchain must be an object")
    else:
        for field in contract["build_toolchain_fields"]:
            if not toolchain.get(field):
                errors.append(f"build_toolchain missing {field}")

    deployment = report.get("deployment_target", {})
    if not isinstance(deployment, dict):
        errors.append("deployment_target must be an object")
    else:
        for field in contract["deployment_target_fields"]:
            if field not in deployment:
                errors.append(f"deployment_target missing {field}")
        if deployment.get("load_commands_match_configuration") is not True:
            errors.append("deployment_target load commands do not match configuration")

    runtime = report.get("runtime_profile", {})
    if not isinstance(runtime, dict):
        errors.append("runtime_profile must be an object")
    else:
        for field in contract["runtime_profile_fields"]:
            if field not in runtime:
                errors.append(f"runtime_profile missing {field}")
        if runtime.get("profile_matches_bundle") is not True:
            errors.append("runtime_profile bundled profile hash mismatch")

    combinations = report.get("qualified_combinations")
    if not isinstance(combinations, list):
        errors.append("qualified_combinations must be an array")

    backend = str(report.get("execution_backend", ""))
    for forbidden in contract["forbidden_backends"]:
        if forbidden in backend:
            errors.append(f"forbidden qualification backend: {forbidden}")

    suite = report.get("suite")
    if suite not in contract["suites"]:
        errors.append(f"unknown suite: {suite}")

    return errors


def host_model() -> str:
    return run_command(["sysctl", "-n", "hw.model"]).strip()


def assert_target_host(profile_path: Path) -> None:
    profile = load_profile(profile_path)
    expected = profile.get("model", "")
    actual = host_model()
    if actual != expected:
        raise RuntimeError(
            f"host model {actual} does not match profile model {expected}; "
            "hardware qualification must run on the target machine"
        )


def qualification_binaries() -> tuple[Path, Path]:
    run_command(
        [
            "swift",
            "build",
            "--package-path",
            str(PACKAGE),
            "--product",
            "SensorWorker",
            "-c",
            "release",
            *WORKER_FLAGS,
        ]
    )
    run_command(
        [
            "swift",
            "build",
            "--package-path",
            str(PACKAGE),
            "--product",
            "ProductQualification",
            "-c",
            "release",
        ]
    )
    bin_path = Path(
        run_command(
            [
                "swift",
                "build",
                "--package-path",
                str(PACKAGE),
                "--product",
                "ProductQualification",
                "-c",
                "release",
                "--show-bin-path",
            ]
        ).strip()
    )
    worker_path = Path(
        run_command(
            [
                "swift",
                "build",
                "--package-path",
                str(PACKAGE),
                "--product",
                "SensorWorker",
                "-c",
                "release",
                *WORKER_FLAGS,
                "--show-bin-path",
            ]
        ).strip()
    )
    return bin_path / "ProductQualification", worker_path / "SensorWorker"


def run_product_qualification(command: list[str]) -> dict[str, Any]:
    result = subprocess.run(command, capture_output=True, text=True, check=False, cwd=ROOT)
    if result.returncode != 0:
        raise RuntimeError(
            f"ProductQualification failed ({result.returncode}): "
            f"{' '.join(command)}\n{result.stderr.strip()}"
        )
    return json.loads(result.stdout)


def validate_sources_report(report: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if report.get("artifactKind") != "product-hardware-sources":
        errors.append("sources artifactKind mismatch")
    expected = report.get("cpuExpectedCount")
    available = report.get("cpuAvailableCount")
    if expected != 12:
        errors.append(f"cpuExpectedCount must be 12, got {expected}")
    if available != expected:
        errors.append(f"cpuAvailableCount {available} != expected {expected}")
    cpu_keys = report.get("cpuKeys", [])
    if len(cpu_keys) != 12:
        errors.append("cpuKeys must contain 12 entries")
    for entry in cpu_keys:
        if entry.get("status") != "available":
            errors.append(f"cpu key {entry.get('rawKey')} not available")
        if entry.get("encoding") != "flt ":
            errors.append(f"cpu key {entry.get('rawKey')} encoding must be flt ")
        if entry.get("byteCount") != 4:
            errors.append(f"cpu key {entry.get('rawKey')} must be 4 bytes")
    for kind in ("ssd", "battery"):
        section = report.get(kind)
        if not isinstance(section, dict) or "status" not in section:
            errors.append(f"{kind} section missing status")
    if "not inferred" not in str(report.get("mappingAndFreshness", "")):
        errors.append("sources must declare mapping/freshness non-inference")
    return errors


def validate_lifecycle_report(report: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if report.get("artifactKind") != "product-hardware-lifecycle":
        errors.append("lifecycle artifactKind mismatch")
    rounds = report.get("sleepWakeRounds", [])
    if len(rounds) < 3:
        errors.append("lifecycle must include at least three sleep/wake rounds")
    for entry in rounds:
        if entry.get("gapsAfterSleep", 0) <= entry.get("gapsBefore", 0):
            errors.append(f"sleep/wake round {entry.get('round')} did not open a gap")
        if entry.get("segmentsAfterWake", 0) < 2:
            errors.append(f"sleep/wake round {entry.get('round')} did not advance segments")
    scenarios = {item.get("name"): item for item in report.get("scenarios", [])}
    for required in (
        "period_switch",
        "exit_restart",
        "double_instance",
        "orphan_worker_after_stop",
    ):
        scenario = scenarios.get(required)
        if not isinstance(scenario, dict):
            errors.append(f"missing lifecycle scenario {required}")
        elif scenario.get("status") != "passed":
            errors.append(f"lifecycle scenario {required} not passed")
    if "not inferred" not in str(report.get("mappingAndFreshness", "")):
        errors.append("lifecycle must declare mapping/freshness non-inference")
    return errors


def validate_processes_report(report: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if report.get("artifactKind") != "product-hardware-processes":
        errors.append("processes artifactKind mismatch")
    snapshots = report.get("snapshots", [])
    if not snapshots:
        errors.append("processes report must include snapshots")
    return errors


def validate_schedules_report(report: dict[str, Any], *, min_duration: int) -> list[str]:
    errors: list[str] = []
    if report.get("artifactKind") != "product-hardware-schedules":
        errors.append("schedules artifactKind mismatch")
    phases = report.get("phases", [])
    if len(phases) != len(DEFAULT_INTERVALS):
        errors.append("schedules must include all five CPU intervals")
    for phase in phases:
        if phase.get("cpuPeriodMS") not in DEFAULT_INTERVALS:
            errors.append(f"unexpected interval {phase.get('cpuPeriodMS')}")
        if phase.get("plannedDurationSeconds", 0) < min_duration:
            errors.append(f"planned duration below {min_duration}s for {phase.get('cpuPeriodMS')}")
        if phase.get("actualDurationSeconds", 0) < min_duration:
            errors.append(f"actual duration below {min_duration}s for {phase.get('cpuPeriodMS')}")
        if phase.get("committedBatches", 0) <= 0:
            errors.append(f"no committed batches for {phase.get('cpuPeriodMS')}")
        if phase.get("cpuRawSamples", 0) <= 0:
            errors.append(f"no cpu raw samples for {phase.get('cpuPeriodMS')}")
    return errors


def maybe_qualified_combination(
    report: dict[str, Any],
    *,
    suites_passed: list[str],
) -> list[dict[str, Any]]:
    runtime = report.get("runtime_profile", {})
    if "sources" not in suites_passed or "schedules" not in suites_passed:
        return []
    return [
        {
            "app_sha256": report.get("app_sha256"),
            "worker_sha256": report.get("worker_sha256"),
            "codesign_identity": report.get("codesign_identity"),
            "model_identifier": runtime.get("model_identifier"),
            "host_product_version": runtime.get("host_product_version"),
            "host_build_version": runtime.get("host_build_version"),
            "suites": suites_passed,
            "result": "passed",
        }
    ]


def write_report(output_dir: Path, report: dict[str, Any], *, create: bool = True) -> Path:
    if create:
        output_dir.mkdir(parents=True, exist_ok=False)
    platform_path = output_dir / "platform.json"
    platform_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest = {
        "schema_version": 1,
        "artifact_kind": "product-hardware-summary",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "reports": [str(platform_path.relative_to(output_dir))],
        "qualified_combinations": report.get("qualified_combinations", []),
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return platform_path


def collect_command(args: argparse.Namespace) -> int:
    if args.use_probe:
        raise SystemExit("sensor-probe backend is forbidden for product qualification")
    app_path = Path(args.app)
    profile_path = Path(args.profile)
    suite = args.suite
    output_dir = Path(args.output)
    if output_dir.exists():
        raise SystemExit(f"output already exists: {output_dir}")

    report = collect_platform(app_path, profile_path, suite)
    report["execution_backend"] = "TemperatureMonitor.app"
    errors = validate_report(report)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    suites_passed: list[str] = []
    if suite == "dry-run":
        report["execution_status"] = "schema_validated"
        path = write_report(output_dir, report)
        print(json.dumps({"output": str(output_dir), "platform": str(path)}, indent=2))
        return 0

    try:
        assert_target_host(profile_path)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    output_dir.mkdir(parents=True, exist_ok=False)

    worker_path = app_path / "Contents" / "MacOS" / "SensorWorker"
    defaults_path = app_path / "Contents/Resources/defaults-v1.json"
    if not worker_path.is_file():
        tool_binary, built_worker = qualification_binaries()
        worker_path = built_worker
    else:
        tool_binary, _ = qualification_binaries()

    duration = args.duration_seconds
    allow_short = __import__("os").environ.get("QUALIFICATION_ALLOW_SHORT") == "1"
    if suite in ("schedules", "full") and duration < MIN_SCHEDULE_DURATION and not allow_short:
        print(
            f"error: schedule duration {duration}s below required {MIN_SCHEDULE_DURATION}s",
            file=sys.stderr,
        )
        return 1

    if suite in ("sources", "full"):
        sources = run_product_qualification(
            [
                str(tool_binary),
                "sources",
                "--worker",
                str(worker_path),
                "--profile",
                str(profile_path),
            ]
        )
        source_errors = validate_sources_report(sources)
        if source_errors:
            for error in source_errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
        (output_dir / "sources.json").write_text(
            json.dumps(sources, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        suites_passed.append("sources")

    if suite in ("schedules", "full"):
        schedules = run_product_qualification(
            [
                str(tool_binary),
                "schedules",
                "--worker",
                str(worker_path),
                "--profile",
                str(profile_path),
                "--defaults",
                str(defaults_path),
                "--output",
                str(output_dir),
                "--duration-seconds",
                str(duration),
                "--intervals",
                ",".join(str(value) for value in DEFAULT_INTERVALS),
            ]
        )
        schedule_errors = validate_schedules_report(
            schedules,
            min_duration=1 if allow_short else MIN_SCHEDULE_DURATION,
        )
        if schedule_errors:
            for error in schedule_errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
        (output_dir / "schedules.json").write_text(
            json.dumps(schedules, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        suites_passed.append("schedules")

    if suite in ("lifecycle", "full"):
        lifecycle_command = [
            str(tool_binary),
            "lifecycle",
            "--worker",
            str(worker_path),
            "--profile",
            str(profile_path),
            "--defaults",
            str(defaults_path),
            "--output",
            str(output_dir),
            "--app",
            str(app_path),
        ]
        lifecycle = run_product_qualification(lifecycle_command)
        lifecycle_errors = validate_lifecycle_report(lifecycle)
        processes_path = output_dir / "processes.json"
        if not processes_path.is_file():
            lifecycle_errors.append("missing processes.json")
        else:
            processes = json.loads(processes_path.read_text(encoding="utf-8"))
            lifecycle_errors.extend(validate_processes_report(processes))
        if lifecycle_errors:
            for error in lifecycle_errors:
                print(f"error: {error}", file=sys.stderr)
            return 1
        (output_dir / "lifecycle.json").write_text(
            json.dumps(lifecycle, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        suites_passed.append("lifecycle")

    report["execution_status"] = "passed" if suites_passed else "pending"
    report["qualified_combinations"] = maybe_qualified_combination(
        report,
        suites_passed=suites_passed,
    )
    path = write_report(output_dir, report, create=False)
    print(
        json.dumps(
            {
                "output": str(output_dir),
                "platform": str(path),
                "suites_passed": suites_passed,
            },
            indent=2,
        )
    )
    return 0


def summarize_command(args: argparse.Namespace) -> int:
    input_root = Path(args.input)
    if not input_root.is_dir():
        raise SystemExit(f"missing input directory: {input_root}")
    reports: list[dict[str, Any]] = []
    qualified: list[dict[str, Any]] = []
    errors: list[str] = []
    for platform_path in sorted(input_root.rglob("platform.json")):
        report = json.loads(platform_path.read_text(encoding="utf-8"))
        report_errors = validate_report(report)
        if report_errors:
            errors.extend(f"{platform_path}: {error}" for error in report_errors)
            continue
        reports.append(
            {
                "path": str(platform_path.relative_to(input_root)),
                "suite": report.get("suite"),
                "execution_status": report.get("execution_status"),
                "app_sha256": report.get("app_sha256"),
            }
        )
        qualified.extend(report.get("qualified_combinations", []))
    summary = {
        "schema_version": 1,
        "artifact_kind": "product-hardware-summary",
        "generated_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "report_count": len(reports),
        "reports": reports,
        "qualified_combinations": qualified,
        "errors": errors,
    }
    if args.output:
        Path(args.output).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 1 if errors else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    collect = subparsers.add_parser("collect")
    collect.add_argument("--app", required=True)
    collect.add_argument("--profile", required=True)
    collect.add_argument("--suite", required=True)
    collect.add_argument("--output", required=True)
    collect.add_argument("--duration-seconds", type=int, default=MIN_SCHEDULE_DURATION)
    collect.add_argument("--use-probe", action="store_true")
    collect.set_defaults(func=collect_command)

    summarize = subparsers.add_parser("summarize")
    summarize.add_argument("--input", required=True)
    summarize.add_argument("--output")
    summarize.set_defaults(func=summarize_command)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
