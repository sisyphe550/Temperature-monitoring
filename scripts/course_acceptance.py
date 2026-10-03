"""Course-local evidence criteria; immutable provenance is checked by acceptance_evidence."""
from __future__ import annotations

import json
from pathlib import Path
import re

POLICY_PATH = Path("docs/contracts/course-delivery-v1.json")
REQUIREMENT_IDS = {f"REQ-{number:03d}" for number in range(1, 135)}
RETIRED_IDS = {"REQ-012", "REQ-114"}
CHECK_KINDS = {
    "COURSE-CPU": "formal-app-hardware",
    "COURSE-FUNCTIONS": "formal-app-hardware",
    "COURSE-RESOURCES": "formal-app-hardware",
    "COURSE-REGRESSIONS": "software",
    "COURSE-CORE": "software",
}


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate key {key!r}")
        result[key] = value
    return result


def _coverage(root: Path, artifact: dict) -> bool:
    """Use hashed artifact counts, never a scope declaration or rounded percentage."""
    name = artifact.get("path")
    if not isinstance(name, str):
        return False
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        return False
    try:
        text = path.read_text(encoding="utf-8")
        if path.suffix == ".json":
            report = json.loads(text)
            text = report.get("coverage_summary", "") if isinstance(report, dict) else ""
    except (OSError, UnicodeError, json.JSONDecodeError):
        return False
    if not isinstance(text, str):
        return False
    match = re.search(r"Core line coverage:\s*(\d+)\s*/\s*(\d+)\b", text)
    if not match:
        return False
    covered, total = map(int, match.groups())
    return total > 0 and 0 <= covered <= total and covered * 100 >= total * 80


def validate_course_policy(root: Path, acceptance: dict, catalog: dict,
                           require_complete: bool = False) -> list[str]:
    """Validate policy using a catalog already passed through load_and_validate.

    Ordinary handoff permits criteria awaiting evidence. Completion requires every
    selected artifact passed, required kinds present, and production Core >=80%.
    This does not declare all 132 strict requirements accepted or replace head CI.
    """
    errors: list[str] = []
    try:
        policy = json.loads((root / POLICY_PATH).read_text(encoding="utf-8"),
                            object_pairs_hook=_unique_object)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        return [f"course-delivery-v1.json: invalid policy: {error}"]
    if not isinstance(policy, dict):
        return ["course-delivery-v1.json: top level must be an object"]
    for key, expected in (("version", 1), ("contract_revision", 3), ("target", "course-local")):
        if type(policy.get(key)) is not type(expected) or policy.get(key) != expected:
            errors.append(f"course policy {key}: must be {expected!r}")
    if not isinstance(policy.get("authorization"), str) or not policy["authorization"].strip():
        errors.append("course policy authorization: must be non-empty")
    rows = acceptance.get("requirements", [])
    ids = [row.get("id") for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []
    if len(ids) != 134 or set(ids) != REQUIREMENT_IDS:
        errors.append("course policy acceptance: must contain all 134 requirement IDs exactly once")
    tiers = policy.get("requirement_tiers")
    if not isinstance(tiers, dict):
        errors.append("course policy requirement_tiers: must be an object")
        tiers = {}
    if set(tiers) != REQUIREMENT_IDS:
        errors.append("course policy requirement_tiers: must map all 134 requirement IDs exactly once")
    for rid, tier in tiers.items():
        if not isinstance(tier, str) or tier not in {"core", "auxiliary", "optional", "retired"}:
            errors.append(f"course policy {rid}: unknown tier {tier!r}")
        elif (tier == "retired") != (rid in RETIRED_IDS):
            errors.append(f"course policy {rid}: retired tier is only for REQ-012/114")
    artifacts = catalog.get("artifacts", {})
    if not isinstance(artifacts, dict):
        errors.append("course policy catalog artifacts: must be an object")
        artifacts = {}

    def strings(value: object, label: str, nonempty: bool = False) -> list[str]:
        if not isinstance(value, list) or (nonempty and not value):
            errors.append(f"{label}: must be {'a non-empty' if nonempty else 'an'} array")
            return []
        if any(not isinstance(item, str) or not item.strip() for item in value):
            errors.append(f"{label}: entries must be non-empty strings")
            return []
        if len(set(value)) != len(value):
            errors.append(f"{label}: duplicate entries")
        return value

    checks = policy.get("checks")
    if not isinstance(checks, list):
        return errors + ["course policy checks: must be an array"]
    seen = []
    for row in checks:
        if not isinstance(row, dict):
            errors.append("course policy checks: each criterion must be an object")
            continue
        check_id = row.get("id")
        if not isinstance(check_id, str) or check_id not in CHECK_KINDS:
            errors.append(f"course policy: unknown criterion {check_id!r}")
            continue
        seen.append(check_id)
        if not isinstance(row.get("description"), str) or not row["description"].strip():
            errors.append(f"{check_id}.description: must be non-empty")
        requirements = strings(row.get("requirements"), f"{check_id}.requirements", nonempty=True)
        if not set(requirements) <= REQUIREMENT_IDS - RETIRED_IDS:
            errors.append(f"{check_id}.requirements: unknown or retired requirement")
        required = strings(row.get("required_evidence_kinds"),
                           f"{check_id}.required_evidence_kinds", nonempty=True)
        if not set(required) <= {"software", "formal-app-hardware"}:
            errors.append(f"{check_id}.required_evidence_kinds: unsupported kind")
        if CHECK_KINDS[check_id] not in required:
            errors.append(f"{check_id}: cannot remove required {CHECK_KINDS[check_id]} evidence")
        evidence = strings(row.get("evidence"), f"{check_id}.evidence")
        missing = set(evidence) - set(artifacts)
        if missing:
            errors.append(f"{check_id}.evidence: unknown artifacts {sorted(missing)}")
        selected = [artifacts[key] for key in evidence if key in artifacts]
        if any(not isinstance(artifact, dict) for artifact in selected):
            errors.append(f"{check_id}.evidence: artifact must be an object")
            continue
        if require_complete:
            if not selected:
                errors.append(f"{check_id}: requires at least one passed evidence artifact")
            if any(artifact.get("result") != "passed" for artifact in selected):
                errors.append(f"{check_id}: all selected evidence must have result passed")
            kinds = {artifact.get("kind") for artifact in selected if artifact.get("result") == "passed"
                     and isinstance(artifact.get("kind"), str)}
            if not set(required) <= kinds:
                errors.append(f"{check_id}: missing passed evidence kinds {sorted(set(required) - kinds)}")
            if check_id == "COURSE-CORE" and not any(
                    artifact.get("kind") == "software" and artifact.get("result") == "passed"
                    and _coverage(root, artifact) for artifact in selected):
                errors.append("COURSE-CORE: requires production Core line coverage >=80% in evidence")
    if len(seen) != len(CHECK_KINDS) or set(seen) != set(CHECK_KINDS):
        errors.append("course policy checks: must contain each of the five required criteria exactly once")
    return errors


def strict_product_errors(acceptance: dict) -> list[str]:
    """Keep the original all-active-requirements gate independent of course tiers."""
    pending = [row["id"] for row in acceptance.get("requirements", [])
               if row.get("status") == "active" and row.get("verification") not in
               {"product-accepted-local", "product-waived"}]
    return ([f"strict product acceptance incomplete: {len(pending)} active requirements still pending: {pending}"]
            if pending else [])
