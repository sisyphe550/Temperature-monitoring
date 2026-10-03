#!/usr/bin/env python3
"""Course-local policy boundary tests; fixtures are synthetic, not hardware evidence."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

MODULE_PATH = Path(__file__).resolve().parents[1] / "course_acceptance.py"
CHECKS = {
    "COURSE-CPU": ("REQ-001", "formal-app-hardware", "hardware"),
    "COURSE-FUNCTIONS": ("REQ-002", "formal-app-hardware", "hardware"),
    "COURSE-RESOURCES": ("REQ-003", "formal-app-hardware", "hardware"),
    "COURSE-REGRESSIONS": ("REQ-004", "software", "software"),
    "COURSE-CORE": ("REQ-005", "software", "software"),
}


class CourseAcceptanceTests(unittest.TestCase):
    def setUp(self) -> None:
        # Missing implementation must produce an assertion failure, not ImportError.
        self.assertTrue(MODULE_PATH.is_file(), f"course policy gate module is missing: {MODULE_PATH}")
        spec = importlib.util.spec_from_file_location("course_acceptance_under_test", MODULE_PATH)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        self.module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = self.module
        spec.loader.exec_module(self.module)
        self.temporary = tempfile.TemporaryDirectory(prefix="course-policy-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "docs/contracts").mkdir(parents=True)
        self.acceptance = self.make_acceptance()
        self.catalog = {
            "version": 2,
            "contract_revision": 3,
            "artifacts": {
                "hardware": self.artifact("formal-app-hardware", "hardware.json"),
                "software": self.artifact("software", "coverage.json"),
            },
            "requirement_results": {},
        }
        # The caller already validated catalog hashes/provenance. Only coverage
        # contents are consumed here; no synthetic fixture claims real hardware.
        self.write_coverage("Core line coverage: 88/100 = 88.00%")
        self.policy = {
            "version": 1,
            "contract_revision": 3,
            "target": "course-local",
            "authorization": "Synthetic unit-test authorization for course-local scope.",
            "requirement_tiers": {
                row["id"]: ("retired" if row["status"] == "retired" else "auxiliary")
                for row in self.acceptance["requirements"]
            },
            "checks": [
                {
                    "id": check_id,
                    "description": f"Synthetic criterion {check_id}",
                    "requirements": [requirement_id],
                    "required_evidence_kinds": [kind],
                    "evidence": [artifact_id],
                }
                for check_id, (requirement_id, kind, artifact_id) in CHECKS.items()
            ],
        }
        for requirement_id, _, _ in CHECKS.values():
            self.policy["requirement_tiers"][requirement_id] = "core"
        self.policy["requirement_tiers"]["REQ-127"] = "optional"

    @staticmethod
    def artifact(kind: str, path: str) -> dict:
        return {
            "path": path,
            "sha256": "a" * 64,
            "source_commit": "b" * 40,
            "kind": kind,
            "result": "passed",
            "environment": {"execution": "synthetic-unit-fixture", "fixture": True},
            "scope": ["Synthetic policy-schema fixture only"],
            "tc_groups": ["TC-ACCEPTANCE"],
        }

    @staticmethod
    def make_acceptance() -> dict:
        rows = []
        active_ids = [f"REQ-{i:03d}" for i in range(1, 135) if i not in {12, 114}]
        pending_ids = set(active_ids[-31:])
        for i in range(1, 135):
            rid = f"REQ-{i:03d}"
            retired = i in {12, 114}
            rows.append({
                "id": rid,
                "status": "retired" if retired else "active",
                "verification": (
                    "retired" if retired else
                    "product-waived" if rid == "REQ-127" else
                    "pending-product-acceptance" if rid in pending_ids else
                    "product-accepted-local"
                ),
                "acceptance_notes": {"required_evidence_kinds": ["software"]},
                "evidence": [],
            })
        # Keep exactly 31 pending + 1 waived among 132 active requirements.
        next(row for row in rows if row["id"] == "REQ-102")["verification"] = "pending-product-acceptance"
        return {"version": 1, "contract_revision": 3, "requirements": rows}

    def write_coverage(self, summary: str | None) -> None:
        data = {} if summary is None else {"coverage_summary": summary}
        (self.root / "coverage.json").write_text(json.dumps(data), encoding="utf-8")

    def errors(self, complete: bool = False) -> list[str]:
        (self.root / "docs/contracts/course-delivery-v1.json").write_text(
            json.dumps(self.policy), encoding="utf-8"
        )
        result = self.module.validate_course_policy(
            self.root, self.acceptance, self.catalog, require_complete=complete
        )
        self.assertIsInstance(result, list)
        self.assertTrue(all(isinstance(item, str) for item in result))
        return result

    def assert_rejected(self, complete: bool = False) -> None:
        self.assertTrue(self.errors(complete), "invalid course-local policy must return errors")

    def check(self, check_id: str) -> dict:
        return next(row for row in self.policy["checks"] if row["id"] == check_id)

    def test_valid_policy_accepts_complete_passed_criteria(self) -> None:
        self.assertEqual([], self.errors(complete=True))

    def test_normal_policy_allows_empty_evidence_but_complete_rejects_it(self) -> None:
        for row in self.policy["checks"]:
            row["evidence"] = []
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)

    def test_each_required_criterion_cannot_be_deleted(self) -> None:
        original = copy.deepcopy(self.policy)
        for check_id in CHECKS:
            with self.subTest(check_id=check_id):
                self.policy = copy.deepcopy(original)
                self.policy["checks"] = [row for row in self.policy["checks"] if row["id"] != check_id]
                self.assert_rejected()

    def test_hardware_criterion_cannot_replace_kind_with_software(self) -> None:
        original = copy.deepcopy(self.policy)
        for check_id in ("COURSE-CPU", "COURSE-FUNCTIONS", "COURSE-RESOURCES"):
            with self.subTest(check_id=check_id):
                self.policy = copy.deepcopy(original)
                self.check(check_id)["required_evidence_kinds"] = ["software"]
                self.check(check_id)["evidence"] = ["software"]
                self.assert_rejected()

    def test_each_required_kind_cannot_be_omitted(self) -> None:
        original = copy.deepcopy(self.policy)
        for check_id in CHECKS:
            with self.subTest(check_id=check_id):
                self.policy = copy.deepcopy(original)
                self.check(check_id)["required_evidence_kinds"] = []
                self.assert_rejected()

    def test_software_criterion_cannot_replace_kind_with_hardware(self) -> None:
        original = copy.deepcopy(self.policy)
        for check_id in ("COURSE-REGRESSIONS", "COURSE-CORE"):
            with self.subTest(check_id=check_id):
                self.policy = copy.deepcopy(original)
                self.check(check_id)["required_evidence_kinds"] = ["formal-app-hardware"]
                self.check(check_id)["evidence"] = ["hardware"]
                self.assert_rejected()

    def test_complete_requires_passed_evidence_for_each_declared_kind(self) -> None:
        self.check("COURSE-CPU")["required_evidence_kinds"].append("software")
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)
        self.check("COURSE-CPU")["evidence"].append("software")
        self.assertEqual([], self.errors(complete=True))

    def test_complete_rejects_partial_not_run_and_failed_artifacts(self) -> None:
        for result in ("partial", "not_run", "failed"):
            with self.subTest(result=result):
                self.catalog["artifacts"]["hardware"]["result"] = result
                self.assertEqual([], self.errors())
                self.assert_rejected(complete=True)

    def test_complete_rejects_nonpassing_extra_evidence_even_with_passed_kind(self) -> None:
        self.catalog["artifacts"]["partial-extra"] = self.artifact("formal-app-hardware", "partial.json")
        self.catalog["artifacts"]["partial-extra"]["result"] = "partial"
        self.check("COURSE-CPU")["evidence"].append("partial-extra")
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)

    def test_requirement_tier_mapping_must_cover_every_requirement(self) -> None:
        for missing_id in ("REQ-001", "REQ-012", "REQ-134"):
            with self.subTest(missing_id=missing_id):
                original = self.policy["requirement_tiers"].pop(missing_id)
                self.assert_rejected()
                self.policy["requirement_tiers"][missing_id] = original

    def test_requirement_tier_mapping_rejects_unknown_requirement(self) -> None:
        self.policy["requirement_tiers"]["REQ-135"] = "optional"
        self.assert_rejected()

    def test_requirement_tier_rejects_unknown_tier(self) -> None:
        self.policy["requirement_tiers"]["REQ-001"] = "ignored"
        self.assert_rejected()

    def test_retired_requirement_cannot_become_core(self) -> None:
        self.policy["requirement_tiers"]["REQ-012"] = "core"
        self.assert_rejected()

    def test_active_requirement_cannot_be_marked_retired(self) -> None:
        self.policy["requirement_tiers"]["REQ-001"] = "retired"
        self.assert_rejected()

    def test_duplicate_criterion_is_rejected(self) -> None:
        self.policy["checks"].append(copy.deepcopy(self.check("COURSE-CPU")))
        self.assert_rejected()

    def test_unknown_criterion_is_rejected(self) -> None:
        extra = copy.deepcopy(self.check("COURSE-CPU"))
        extra["id"] = "COURSE-UNKNOWN"
        self.policy["checks"].append(extra)
        self.assert_rejected()

    def test_unknown_requirement_reference_is_rejected(self) -> None:
        self.check("COURSE-CPU")["requirements"] = ["REQ-999"]
        self.assert_rejected()

    def test_unknown_artifact_reference_is_rejected_in_normal_and_complete(self) -> None:
        self.check("COURSE-CPU")["evidence"] = ["missing-artifact"]
        self.assert_rejected()
        self.assert_rejected(complete=True)

    def test_empty_criterion_description_is_rejected(self) -> None:
        self.check("COURSE-CPU")["description"] = "  "
        self.assert_rejected()

    def test_empty_authorization_is_rejected(self) -> None:
        self.policy["authorization"] = " "
        self.assert_rejected()

    def test_empty_requirements_are_rejected(self) -> None:
        self.check("COURSE-CPU")["requirements"] = []
        self.assert_rejected()

    def test_duplicate_requirement_reference_is_rejected(self) -> None:
        self.check("COURSE-CPU")["requirements"] = ["REQ-001", "REQ-001"]
        self.assert_rejected()

    def test_duplicate_artifact_reference_is_rejected(self) -> None:
        self.check("COURSE-CPU")["evidence"] = ["hardware", "hardware"]
        self.assert_rejected()

    def test_unknown_required_evidence_kind_is_rejected(self) -> None:
        self.check("COURSE-CPU")["required_evidence_kinds"].append("source-audit")
        self.assert_rejected()

    def test_wrong_field_types_are_rejected_without_crashing(self) -> None:
        original = copy.deepcopy(self.policy)
        mutations = (
            ("requirement_tiers", []), ("checks", {}),
            ("authorization", []), ("version", True),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                self.policy = copy.deepcopy(original)
                self.policy[field] = value
                self.assert_rejected()
        for field, value in (("requirements", "REQ-001"), ("required_evidence_kinds", "formal-app-hardware"), ("evidence", "hardware")):
            with self.subTest(check_field=field):
                self.policy = copy.deepcopy(original)
                self.check("COURSE-CPU")[field] = value
                self.assert_rejected()

    def test_version_revision_and_target_cannot_drift(self) -> None:
        for field, invalid in (("version", 2), ("contract_revision", 2), ("target", "strict-product")):
            with self.subTest(field=field):
                original = self.policy[field]
                self.policy[field] = invalid
                self.assert_rejected()
                self.policy[field] = original

    def test_complete_core_coverage_uses_counts_not_claimed_percentage(self) -> None:
        self.write_coverage("Core line coverage: 79/100 = 88.00%")
        self.assert_rejected(complete=True)

    def test_complete_core_coverage_at_80_percent_is_accepted(self) -> None:
        self.write_coverage("Core line coverage: 80/100 = 80.00%")
        self.assertEqual([], self.errors(complete=True))

    def test_complete_core_coverage_rejects_missing_summary(self) -> None:
        self.write_coverage(None)
        self.assert_rejected(complete=True)

    def test_strict_product_still_rejects_31_pending_requirements(self) -> None:
        pending = [row for row in self.acceptance["requirements"] if row["verification"] == "pending-product-acceptance"]
        self.assertEqual(31, len(pending), "fixture preserves the stricter pending requirement count")
        self.assertEqual([], self.errors(complete=True))
        self.assertTrue(self.module.strict_product_errors(self.acceptance))

    def test_strict_product_accepts_all_active_accepted_or_explicitly_waived(self) -> None:
        for row in self.acceptance["requirements"]:
            if row["status"] == "active" and row["verification"] == "pending-product-acceptance":
                row["verification"] = "product-accepted-local"
        self.assertEqual([], self.module.strict_product_errors(self.acceptance))


if __name__ == "__main__":
    unittest.main(verbosity=2)
