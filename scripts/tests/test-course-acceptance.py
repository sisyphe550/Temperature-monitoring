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
sys.path.insert(0, str(MODULE_PATH.parent))
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
            "contract_revision": 5,
            "artifacts": {
                "hardware": self.artifact("formal-app-hardware", "hardware.json"),
                "software": self.artifact("software", "coverage.json"),
            },
            "requirement_results": {},
        }
        # The caller already validated catalog hashes/provenance. Only coverage
        # contents are consumed here; no synthetic fixture claims real hardware.
        self.write_coverage("Core line coverage: 88/100 = 88.00%")
        self.write_warning_payloads()
        self.policy = {
            "version": 1,
            "contract_revision": 5,
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
        self.policy["requirement_tiers"]["REQ-125"] = "core"
        for check_id in ("COURSE-FUNCTIONS", "COURSE-REGRESSIONS"):
            self.check(check_id)["requirements"].append("REQ-125")
        self.warning = next(row for row in self.acceptance["requirements"] if row["id"] == "REQ-125")
        self.warning["verification"] = "product-accepted-local"
        self.analysis = next(row for row in self.acceptance["requirements"] if row["id"] == "REQ-135")
        self.analysis["verification"] = "product-accepted-local"
        self.policy["requirement_tiers"]["REQ-135"] = "core"
        self.write_analysis_payloads()
        for check_id in ("COURSE-FUNCTIONS", "COURSE-REGRESSIONS"):
            self.check(check_id)["requirements"].append("REQ-135")
            kind = "hardware" if check_id == "COURSE-FUNCTIONS" else "software"
            self.check(check_id)["evidence"].append("analysis-" + kind)
        # Swap another active fixture row to keep the original 31-pending boundary test.
        next(row for row in self.acceptance["requirements"] if row["id"] == "REQ-101")["verification"] = "pending-product-acceptance"


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
            "tc_groups": ["TC-ACCEPTANCE", "TC-WARNING"],
        }

    @staticmethod
    def make_acceptance() -> dict:
        rows = []
        active_ids = [f"REQ-{i:03d}" for i in range(1, 135) if i not in {12, 114}]
        pending_ids = set(active_ids[-31:])
        for i in range(1, 136):
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
        # Keep exactly 31 pending + 1 waived among 133 active requirements.
        next(row for row in rows if row["id"] == "REQ-102")["verification"] = "pending-product-acceptance"
        return {"version": 1, "contract_revision": 5, "requirements": rows}

    def write_warning_payloads(self) -> None:
        import hashlib
        raw = self.root / "warning-original.log"
        raw.write_text("Synthetic warning evidence only; no App or hardware executed.\n")
        reference = {"path": "warning-original.log", "sha256": hashlib.sha256(raw.read_bytes()).hexdigest()}
        names = {
            "software": ["trigger-recovery", "interruption-and-time", "receipt-and-replay", "rule-change",
                         "events-bounded", "config-persistence", "notification-policy"],
            "hardware": ["real-cpu", "cpu-warning-trigger", "rule-change-not-recovered", "close-reopen",
                         "quit", "config-persistence", "notification-handler"],
        }
        self.catalog["artifacts"]["hardware"]["environment"] = {
            "execution": "formal-release-app", "build_configuration": "Release", "fixture": False,
            "app_bundle_id": "io.github.sisyphe550.TemperatureMonitor", "app_sha256": "a" * 64,
            "worker_sha256": "b" * 64, "model": "SyntheticSchema", "os_build": "SyntheticSchema",
            "context": "synthetic schema only; not hardware evidence",
        }
        for artifact_id, cases in names.items():
            artifact = self.catalog["artifacts"][artifact_id]
            path = self.root / artifact["path"]
            report = json.loads(path.read_text()) if path.is_file() else {}
            report.update(contract_version=4, feature="cpu-warning", kind=artifact["kind"],
                          source_commit=artifact["source_commit"], result=artifact["result"],
                          environment=copy.deepcopy(artifact["environment"]),
                          warning_cases={name: {"result": "passed", "observed": "Synthetic schema only",
                                                "evidence": [copy.deepcopy(reference)]} for name in cases})
            if artifact_id == "hardware":
                report["warning_cases"]["notification-handler"].update(
                    authorization="authorized", adapter_request="request-accepted",
                    observed_banner=False, notification_click=False)
            path.write_text(json.dumps(report))

    def write_analysis_payloads(self) -> None:
        import hashlib
        raw = self.root / "analysis-original.log"
        raw.write_text("Synthetic analysis schema evidence; no App or hardware executed.\n")
        reference = {"path": "analysis-original.log", "sha256": hashlib.sha256(raw.read_bytes()).hexdigest()}
        names = {
            "software": ["system-thermal-state", "cpu-assessment", "warning-independent", "trend-window-and-gap",
                         "receipt-replay-and-expiry", "rule-change", "advice-policy"],
            "hardware": ["real-cpu-analysis", "system-thermal-state", "trend-display", "warning-disabled", "close-reopen", "quit"],
        }
        for kind, cases in names.items():
            artifact = copy.deepcopy(self.catalog["artifacts"][kind])
            artifact["path"] = "analysis-" + kind + ".json"
            artifact["tc_groups"] = ["TC-ANALYSIS"]
            self.catalog["artifacts"]["analysis-" + kind] = artifact
            report = {"contract_version": 5, "feature": "temperature-analysis",
                      **{key: copy.deepcopy(artifact[key]) for key in ("kind", "source_commit", "result", "environment")},
                      "analysis_cases": {name: {"result": "passed", "observed": "Synthetic schema only",
                                               "evidence": [copy.deepcopy(reference)]} for name in cases}}
            (self.root / artifact["path"]).write_text(json.dumps(report))

    def test_analysis_pending_allows_structure_but_blocks_completion(self) -> None:
        self.analysis["verification"] = "pending-product-acceptance"
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)

    def test_old_warning_evidence_cannot_prove_new_analysis(self) -> None:
        for check_id in ("COURSE-FUNCTIONS", "COURSE-REGRESSIONS"):
            self.check(check_id)["evidence"] = [key for key in self.check(check_id)["evidence"] if not key.startswith("analysis-")]
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)

    def test_warning_report_relabelled_analysis_tag_is_rejected(self) -> None:
        self.catalog["artifacts"]["analysis-hardware"]["path"] = "hardware.json"
        self.assert_rejected(complete=True)

    def test_analysis_mapping_cannot_be_removed(self) -> None:
        for check_id in ("COURSE-FUNCTIONS", "COURSE-REGRESSIONS"):
            with self.subTest(check_id=check_id):
                row = self.check(check_id)
                row["requirements"].remove("REQ-135")
                self.assert_rejected()
                row["requirements"].append("REQ-135")

    def write_coverage(self, summary: str | None) -> None:
        path = self.root / "coverage.json"
        data = json.loads(path.read_text()) if path.is_file() else {}
        data.pop("coverage_summary", None)
        if summary is not None: data["coverage_summary"] = summary
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

    def test_relabelled_real_old_report_payloads_are_rejected(self) -> None:
        old = MODULE_PATH.parents[1] / "docs/validation/course-delivery/2026-10-03-5984b9e"
        (self.root / "coverage.json").write_text((old / "full-core-summary.json").read_text())
        (self.root / "hardware.json").write_text((old / "formal-app-summary.json").read_text())
        self.assert_rejected(complete=True)

    def test_warning_mapping_cannot_be_removed(self) -> None:
        for check_id in ("COURSE-FUNCTIONS", "COURSE-REGRESSIONS"):
            with self.subTest(check_id=check_id):
                row = self.check(check_id)
                row["requirements"].remove("REQ-125")
                self.assert_rejected()
                row["requirements"].append("REQ-125")

    def test_warning_pending_allows_structure_but_blocks_completion(self) -> None:
        self.warning["verification"] = "pending-product-acceptance"
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)

    def test_old_no_warning_evidence_cannot_prove_new_warning(self) -> None:
        for artifact in self.catalog["artifacts"].values():
            artifact["tc_groups"] = ["TC-UI", "TC-LIFECYCLE"]
        self.assertEqual([], self.errors())
        self.assert_rejected(complete=True)

    def test_warning_software_cannot_replace_formal_warning_observation(self) -> None:
        self.catalog["artifacts"]["hardware"]["tc_groups"] = ["TC-UI"]
        self.assert_rejected(complete=True)

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
        self.policy["requirement_tiers"]["REQ-136"] = "optional"
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
