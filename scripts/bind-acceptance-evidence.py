#!/usr/bin/env python3
"""Bind TC evidence from acceptance-evidence-catalog-v1.json into acceptance-v1.json."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CONTRACTS = DOCS / "contracts"
ACCEPTANCE_PATH = CONTRACTS / "acceptance-v1.json"
CATALOG_PATH = CONTRACTS / "acceptance-evidence-catalog-v1.json"
TRACEABILITY_PATH = DOCS / "17-traceability.md"

VERIFICATION_PENDING = "pending-product-acceptance"
VERIFICATION_LOCAL = "product-accepted-local"
VERIFICATION_WAIVED = "product-waived"

TRACE_RESULT = {
    VERIFICATION_PENDING: "未完成产品验收",
    VERIFICATION_LOCAL: "本地验收通过",
    VERIFICATION_WAIVED: "已豁免（本地交付）",
}


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_catalog(catalog: dict) -> None:
    if catalog.get("version") != 1:
        raise SystemExit("acceptance-evidence-catalog-v1.json: version must be 1")
    source_sha = catalog.get("source_sha256", "")
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise SystemExit("acceptance-evidence-catalog-v1.json: source_sha256 must be 40-char lowercase hex")
    tc_evidence = catalog.get("tc_evidence")
    if not isinstance(tc_evidence, dict) or not tc_evidence:
        raise SystemExit("acceptance-evidence-catalog-v1.json: tc_evidence must be a non-empty object")


def build_evidence_entry(tc: str, tc_info: dict, source_sha256: str) -> dict:
    kind = tc_info.get("kind")
    if kind not in {"ci", "hardware", "mixed", "waived", "pending"}:
        raise SystemExit(f"{tc}: invalid kind {kind!r}")
    entry: dict = {"tc": tc, "kind": kind, "source_sha256": source_sha256}
    reports = tc_info.get("reports", [])
    if reports:
        entry["reports"] = reports
    if tc_info.get("commands"):
        entry["commands"] = tc_info["commands"]
    if tc_info.get("note"):
        entry["note"] = tc_info["note"]
    return entry


def decide_verification(evidence: list[dict]) -> str:
    if not evidence:
        return VERIFICATION_PENDING
    kinds = {item["kind"] for item in evidence}
    if kinds == {"waived"}:
        return VERIFICATION_WAIVED
    if "pending" in kinds:
        return VERIFICATION_PENDING
    if "waived" in kinds and len(kinds) > 1:
        return VERIFICATION_PENDING
    return VERIFICATION_LOCAL


def bind_requirements(catalog: dict) -> tuple[dict, dict[str, str]]:
    acceptance = load_json(ACCEPTANCE_PATH)
    tc_evidence = catalog["tc_evidence"]
    source_sha256 = catalog["source_sha256"]
    verification_by_id: dict[str, str] = {}

    for row in acceptance["requirements"]:
        requirement_id = row["id"]
        if row.get("status") == "retired":
            row["verification"] = "not-applicable"
            row.pop("evidence", None)
            verification_by_id[requirement_id] = "not-applicable"
            continue

        tests = row.get("tests", [])
        evidence: list[dict] = []
        missing = False
        for tc in tests:
            tc_info = tc_evidence.get(tc)
            if not tc_info:
                missing = True
                break
            if tc_info.get("kind") == "pending":
                missing = True
                break
            evidence.append(build_evidence_entry(tc, tc_info, source_sha256))

        if missing or not evidence:
            row["verification"] = VERIFICATION_PENDING
            row.pop("evidence", None)
            verification_by_id[requirement_id] = VERIFICATION_PENDING
            continue

        row["evidence"] = evidence
        verification = decide_verification(evidence)
        row["verification"] = verification
        verification_by_id[requirement_id] = verification

    return acceptance, verification_by_id


def sync_traceability(verification_by_id: dict[str, str]) -> None:
    text = TRACEABILITY_PATH.read_text(encoding="utf-8")
    lines = text.splitlines()
    updated: list[str] = []
    row_re = re.compile(
        r"^\| (REQ-\d{3}) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$"
    )
    for line in lines:
        match = row_re.match(line)
        if not match:
            updated.append(line)
            continue
        requirement_id, status, design, tasks, tests, _result = match.groups()
        verification = verification_by_id.get(requirement_id, VERIFICATION_PENDING)
        if verification == "not-applicable":
            result = "不适用（已删除）"
        else:
            result = TRACE_RESULT.get(verification, TRACE_RESULT[VERIFICATION_PENDING])
        updated.append(
            f"| {requirement_id} | {status} | {design} | {tasks} | {tests} | {result} |"
        )
    TRACEABILITY_PATH.write_text("\n".join(updated) + "\n", encoding="utf-8")


def summarize(verification_by_id: dict[str, str]) -> dict:
    counts: dict[str, int] = {}
    for value in verification_by_id.values():
        counts[value] = counts.get(value, 0) + 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write acceptance-v1.json and 17-traceability.md")
    args = parser.parse_args()

    catalog = load_json(CATALOG_PATH)
    validate_catalog(catalog)
    acceptance, verification_by_id = bind_requirements(catalog)

    for report in {
        path
        for tc_info in catalog["tc_evidence"].values()
        for path in tc_info.get("reports", [])
        if tc_info.get("kind") != "pending"
    }:
        if not (ROOT / report).is_file():
            raise SystemExit(f"missing evidence report: {report}")

    stats = summarize(verification_by_id)
    if args.write:
        ACCEPTANCE_PATH.write_text(
            json.dumps(acceptance, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        sync_traceability(verification_by_id)

    print(json.dumps({"status": "ok", "verification_counts": stats}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
