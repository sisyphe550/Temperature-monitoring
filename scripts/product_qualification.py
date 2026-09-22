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
FORBIDDEN_PROBE = ROOT / "prototypes" / "sensor-probe" / ".build" / "release" / "sensor-probe"


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


def write_report(output_dir: Path, report: dict[str, Any]) -> Path:
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
    if FORBIDDEN_PROBE.is_file() and args.suite != "dry-run":
        pass
    report = collect_platform(Path(args.app), Path(args.profile), args.suite)
    report["execution_backend"] = "TemperatureMonitor.app"
    errors = validate_report(report)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    if args.suite != "dry-run":
        print(
            f"suite {args.suite} requires target hardware execution (T09.2+); "
            "platform schema validated only",
            file=sys.stderr,
        )
        return 2
    output_dir = Path(args.output)
    if output_dir.exists():
        raise SystemExit(f"output already exists: {output_dir}")
    path = write_report(output_dir, report)
    print(json.dumps({"output": str(output_dir), "platform": str(path)}, indent=2))
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
