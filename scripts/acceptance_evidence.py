"""Validate immutable artifact provenance and explicit per-requirement acceptance."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess


CATALOG_PATH = Path("docs/contracts/acceptance-evidence-catalog-v1.json")
VERIFICATION_PENDING = "pending-product-acceptance"
VERIFICATION_LOCAL = "product-accepted-local"
VERIFICATION_WAIVED = "product-waived"
TRACE_RESULT = {
    VERIFICATION_PENDING: "未完成产品验收",
    VERIFICATION_LOCAL: "本地验收通过",
    VERIFICATION_WAIVED: "已豁免（本地交付）",
    "not-applicable": "不适用（已删除）",
}
KINDS = {"software", "formal-app-hardware", "ci", "waiver", "reference"}
RETIRED_IDS = {"REQ-012", "REQ-114"}
REQUIREMENT_IDS = {f"REQ-{number:03d}" for number in range(1, 135)}


def _text(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label}: must be a non-empty string")
    return value


def _strings(value: object, label: str, *, nonempty: bool = False) -> list[str]:
    if not isinstance(value, list) or (nonempty and not value):
        raise ValueError(f"{label}: must be {'a non-empty' if nonempty else 'an'} array")
    for item in value:
        _text(item, label)
    if len(set(value)) != len(value):
        raise ValueError(f"{label}: duplicate entries")
    return value


def _hex(value: object, length: int, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(rf"[0-9a-f]{{{length}}}", value):
        raise ValueError(f"{label}: must be {length}-character lowercase hex")
    return value


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"catalog: duplicate key {key!r}")
        result[key] = value
    return result


def _requirement_rows(acceptance: dict) -> dict[str, dict]:
    if not isinstance(acceptance, dict) or acceptance.get("version") != 1:
        raise ValueError("acceptance: version must be 1")
    if not isinstance(acceptance, dict) or acceptance.get("contract_revision") != 3:
        raise ValueError("acceptance: contract_revision must be 3")
    rows = acceptance.get("requirements")
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise ValueError("acceptance: requirements must be an array of objects")
    by_id = {}
    for row in rows:
        requirement_id = _text(row.get("id"), "acceptance requirement id")
        if requirement_id in by_id:
            raise ValueError(f"acceptance: duplicate {requirement_id}")
        by_id[requirement_id] = row
    if set(by_id) != REQUIREMENT_IDS:
        raise ValueError("acceptance: must contain REQ-001..REQ-134 exactly once")
    for requirement_id, row in by_id.items():
        expected = "retired" if requirement_id in RETIRED_IDS else "active"
        if row.get("status") != expected:
            raise ValueError(f"{requirement_id}: status must be {expected}")
        tests = _strings(row.get("tests"), f"{requirement_id}.tests", nonempty=expected == "active")
        if any(not re.fullmatch(r"TC-[A-Z0-9-]+", tc) for tc in tests):
            raise ValueError(f"{requirement_id}.tests: invalid TC group")
        if expected == "retired" and tests:
            raise ValueError(f"{requirement_id}: retired requirement must have no tests")
    return by_id


def _artifact_path(root: Path, value: object, label: str) -> Path:
    name = _text(value, label)
    path = Path(name)
    if path.is_absolute() or "\\" in name or any(part in {"", ".", ".."} for part in name.split("/")):
        raise ValueError(f"{label}: path must stay inside the repository")
    resolved = (root / path).resolve()
    if not resolved.is_relative_to(root):
        raise ValueError(f"{label}: path resolves outside the repository")
    if not resolved.is_file():
        raise ValueError(f"{label}: evidence file does not exist or is not a file")
    return resolved


def _validate_formal_environment(environment: object, label: str) -> None:
    """Check formal-run identity declarations; reports still require human review."""
    if not isinstance(environment, dict):
        raise ValueError(f"{label}: formal-app-hardware requires a structured environment object")
    for field, expected in (
        ("execution", "formal-release-app"),
        ("build_configuration", "Release"),
        ("app_bundle_id", "io.github.sisyphe550.TemperatureMonitor"),
    ):
        if environment.get(field) != expected:
            raise ValueError(f"{label}.{field}: must be {expected!r}")
    if environment.get("fixture") is not False:
        raise ValueError(f"{label}.fixture: formal-app-hardware requires fixture=false")
    for field in ("app_sha256", "worker_sha256"):
        _hex(environment.get(field), 64, f"{label}.{field}")
    for field in ("model", "os_build"):
        _text(environment.get(field), f"{label}.{field}")


def _authorized_local_waiver(text: str) -> bool:
    return all(re.search(pattern, text, re.IGNORECASE) for pattern in (
        r"用户|\buser\b", r"本机|本地|\blocal\b", r"授权|\bauthoriz(?:ed|ation)\b",
    ))


def _validate_catalog(root: Path, catalog: dict, acceptance: dict) -> None:
    root = root.resolve()
    rows = _requirement_rows(acceptance)
    if not isinstance(catalog, dict) or catalog.get("version") != 2:
        raise ValueError("catalog: version must be 2")
    if catalog.get("contract_revision") != 3:
        raise ValueError("catalog: contract_revision must be 3")
    delivery = _hex(catalog.get("delivery_commit"), 40, "catalog.delivery_commit")
    commits = set()

    def git(*arguments: str) -> subprocess.CompletedProcess:
        try:
            return subprocess.run(["git", "-C", str(root), *arguments],
                                  text=True, capture_output=True, check=False)
        except OSError as error:
            raise ValueError(f"Git provenance check failed: {error}") from error

    def check_commit(commit: str, label: str) -> None:
        if commit not in commits:
            object_type = git("cat-file", "-t", commit)
            if object_type.returncode != 0 or object_type.stdout.strip() != "commit":
                raise ValueError(f"{label}: Git commit does not exist")
            commits.add(commit)

    check_commit(delivery, "catalog.delivery_commit")
    if git("merge-base", "--is-ancestor", delivery, "HEAD").returncode != 0:
        raise ValueError("catalog.delivery_commit: must be an ancestor of checked-out HEAD")
    artifacts = catalog.get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        raise ValueError("catalog.artifacts: must be a non-empty object")
    ancestors = set()
    for artifact_id, artifact in artifacts.items():
        _text(artifact_id, "artifact id")
        label = f"artifact {artifact_id}"
        if not isinstance(artifact, dict):
            raise ValueError(f"{label}: must be an object")
        path = _artifact_path(root, artifact.get("path"), f"{label}.path")
        expected_hash = _hex(artifact.get("sha256"), 64, f"{label}.sha256")
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected_hash:
            raise ValueError(f"{label}.sha256: evidence file hash does not match")
        source = _hex(artifact.get("source_commit"), 40, f"{label}.source_commit")
        check_commit(source, f"{label}.source_commit")
        if source not in ancestors:
            if git("merge-base", "--is-ancestor", source, delivery).returncode != 0:
                raise ValueError(f"{label}.source_commit: must be an ancestor of delivery_commit")
            ancestors.add(source)
        kind = artifact.get("kind")
        if not isinstance(kind, str) or kind not in KINDS:
            raise ValueError(f"{label}.kind: unsupported evidence kind {kind!r}")
        result = artifact.get("result")
        if not isinstance(result, str) or result not in {"passed", "partial", "waived"}:
            raise ValueError(f"{label}.result: only passed, partial or waived evidence is allowed")
        if (kind == "waiver") != (result == "waived"):
            raise ValueError(f"{label}.result: waiver kind and waived result must occur together")
        environment = artifact.get("environment")
        if not ((isinstance(environment, str) and environment.strip())
                or (isinstance(environment, dict) and environment)):
            raise ValueError(f"{label}.environment: must be a non-empty string or object")
        if kind == "formal-app-hardware":
            _validate_formal_environment(environment, f"{label}.environment")
        _strings(artifact.get("scope"), f"{label}.scope", nonempty=True)
        groups = _strings(artifact.get("tc_groups"), f"{label}.tc_groups", nonempty=True)
        if any(not re.fullmatch(r"TC-[A-Z0-9-]+", tc) for tc in groups):
            raise ValueError(f"{label}.tc_groups: invalid TC group")

    results = catalog.get("requirement_results")
    if not isinstance(results, dict):
        raise ValueError("catalog.requirement_results: must be an object")
    active_ids = set(rows) - RETIRED_IDS
    if set(results) != active_ids:
        raise ValueError("catalog.requirement_results: must contain all 132 active requirements only; "
                         f"missing={sorted(active_ids - set(results))}, extra={sorted(set(results) - active_ids)}")
    for requirement_id, result in results.items():
        if not isinstance(result, dict):
            raise ValueError(f"{requirement_id}: result must be an object")
        verification = result.get("verification")
        if not isinstance(verification, str) or verification not in {
            VERIFICATION_PENDING, VERIFICATION_LOCAL, VERIFICATION_WAIVED,
        }:
            raise ValueError(f"{requirement_id}.verification: invalid result {verification!r}")
        evidence = _strings(result.get("evidence"), f"{requirement_id}.evidence")
        covered = _strings(result.get("covered_cases"), f"{requirement_id}.covered_cases")
        outstanding = _strings(result.get("outstanding"), f"{requirement_id}.outstanding")
        reason = _text(result.get("reason"), f"{requirement_id}.reason")
        required = _strings(result.get("required_evidence_kinds"),
                            f"{requirement_id}.required_evidence_kinds", nonempty=True)
        if not set(required) <= KINDS:
            raise ValueError(f"{requirement_id}.required_evidence_kinds: unknown evidence kind")
        missing = set(evidence) - set(artifacts)
        if missing:
            raise ValueError(f"{requirement_id}.evidence: unknown artifacts {sorted(missing)}")
        selected = [artifacts[artifact_id] for artifact_id in evidence]
        groups = {tc for artifact in selected for tc in artifact["tc_groups"]}
        if verification != VERIFICATION_PENDING:
            missing_groups = set(rows[requirement_id]["tests"]) - groups
            if missing_groups:
                raise ValueError(f"{requirement_id}: evidence does not cover TC groups {sorted(missing_groups)}")
        if verification == VERIFICATION_LOCAL:
            if not evidence or not covered or outstanding:
                raise ValueError(f"{requirement_id}: accepted requires evidence, covered_cases and no outstanding items")
            if any(artifact["result"] != "passed" or artifact["kind"] == "waiver" for artifact in selected):
                raise ValueError(f"{requirement_id}: accepted requires only passed, non-waiver artifacts")
            missing_kinds = set(required) - {artifact["kind"] for artifact in selected}
            if missing_kinds:
                raise ValueError(f"{requirement_id}: missing required evidence kinds {sorted(missing_kinds)}")
        elif verification == VERIFICATION_WAIVED:
            if set(required) != {"waiver"}:
                raise ValueError(f"{requirement_id}.required_evidence_kinds: waived requires only waiver")
            if requirement_id != "REQ-127":
                raise ValueError(f"{requirement_id}: whole-requirement waiver is allowed only for REQ-127")
            if not evidence or any(artifact["kind"] != "waiver" for artifact in selected):
                raise ValueError(f"{requirement_id}: waived requires only waiver artifacts")
            if not _authorized_local_waiver(reason) or any(
                not _authorized_local_waiver(" ".join(artifact["scope"])) for artifact in selected
            ):
                raise ValueError(f"{requirement_id}: reason and waiver scope must reference user-authorized local waiver（用户授权本机豁免）")


def load_and_validate(root: Path, acceptance: dict) -> dict:
    """Load version-2 evidence, checking files, Git provenance and each REQ decision."""
    try:
        catalog = json.loads((root / CATALOG_PATH).read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
        _validate_catalog(root, catalog, acceptance)
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"{CATALOG_PATH}: {error}") from error
    return catalog


def bound_acceptance(root: Path, catalog: dict, acceptance: dict) -> dict:
    """Deep-copy acceptance using an already validated catalog; preserve all other fields."""
    bound = copy.deepcopy(acceptance)
    for row in bound["requirements"]:
        if row["status"] == "retired":
            row["verification"] = "not-applicable"
            row.pop("evidence", None)
            row.pop("acceptance_notes", None)
            continue
        result = catalog["requirement_results"][row["id"]]
        row["verification"] = result["verification"]
        row["evidence"] = [dict(copy.deepcopy(catalog["artifacts"][artifact_id]), artifact_id=artifact_id)
                           for artifact_id in result["evidence"]]
        row["acceptance_notes"] = {field: copy.deepcopy(result.get(field, [])) for field in (
            "covered_cases", "outstanding", "reason", "required_evidence_kinds",
        )}
    return bound


def validate_bound(root: Path, catalog: dict, acceptance: dict) -> list[str]:
    """Return provenance or binding errors without treating partial evidence as acceptance."""
    try:
        _validate_catalog(root, catalog, acceptance)
        expected = bound_acceptance(root, catalog, acceptance)
    except (OSError, ValueError) as error:
        return [str(error)]
    errors = []
    for row, expected_row in zip(acceptance["requirements"], expected["requirements"]):
        for field in ("verification", "evidence", "acceptance_notes"):
            if (field in row) != (field in expected_row) or row.get(field) != expected_row.get(field):
                errors.append(f"{row['id']}.{field}: differs from the validated evidence catalog")
    return errors
