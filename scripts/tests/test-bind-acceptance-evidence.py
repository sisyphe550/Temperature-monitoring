#!/usr/bin/env python3
"""Exercise acceptance binding against real files and a temporary Git history."""

from __future__ import annotations

import copy
import hashlib
import importlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(SCRIPTS))
PENDING = "pending-product-acceptance"
ACCEPTED = "product-accepted-local"
WAIVED = "product-waived"
CATALOG_PATH = Path("docs/contracts/acceptance-evidence-catalog-v1.json")
ACCEPTANCE_PATH = Path("docs/contracts/acceptance-v1.json")
TRACE_PATH = Path("docs/17-traceability.md")


class EvidenceBindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="temperature-evidence-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "docs/contracts").mkdir(parents=True)
        (self.root / "docs/validation").mkdir()
        (self.root / "scripts").mkdir()
        for name in ("bind-acceptance-evidence.py", "acceptance_evidence.py"):
            if (SCRIPTS / name).exists():
                shutil.copy2(SCRIPTS / name, self.root / "scripts" / name)
        self.git("init", "--quiet")
        self.git("config", "user.name", "Evidence Test")
        self.git("config", "user.email", "evidence-test@example.invalid")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", "/dev/null")
        (self.root / "history.txt").write_text("original software\n", encoding="utf-8")
        self.git("add", "history.txt")
        self.git("commit", "--quiet", "-m", "original evidence source")
        self.source_commit = self.git("rev-parse", "HEAD")
        (self.root / "history.txt").write_text("delivered software\n", encoding="utf-8")
        self.git("commit", "--quiet", "-am", "delivery")
        self.delivery_commit = self.git("rev-parse", "HEAD")

        rows = []
        for number in range(1, 135):
            requirement_id = f"REQ-{number:03d}"
            retired = number in {12, 114}
            tests = ["TC-DOCS"]
            if number == 1:
                tests = ["TC-SCHEDULE"]
            elif number == 8:
                tests = ["TC-SENSOR", "TC-VALIDATE"]
            elif number == 127:
                tests = ["TC-RELEASE"]
            rows.append({"id": requirement_id, "status": "retired" if retired else "active",
                         "tests": [] if retired else tests,
                         "design": ["fixture.md"], "tasks": [] if retired else ["W11"],
                         "verification": "not-applicable" if retired else PENDING})
        self.acceptance = {"version": 1, "contract_revision": 3,
                           "date": "2026-10-03", "requirements": rows,
                           "preserved_metadata": {"note": "keep this"}}
        self.catalog = {
            "version": 2, "contract_revision": 3, "delivery_commit": self.delivery_commit,
            "artifacts": {
                "software": self.artifact("software", "passed", ["TC-DOCS", "TC-SCHEDULE", "TC-SENSOR"]),
                "hardware": self.artifact("formal-app-hardware", "passed", ["TC-SENSOR"]),
                "validation": self.artifact("ci", "passed", ["TC-VALIDATE"]),
                "waiver": self.artifact("waiver", "waived", ["TC-RELEASE"]),
            },
            "requirement_results": {
                row["id"]: {"verification": PENDING, "evidence": [], "covered_cases": [],
                            "outstanding": ["产品验收尚未执行"], "reason": "尚缺本需求证据",
                            "required_evidence_kinds": ["waiver"] if row["id"] == "REQ-127" else ["software"]}
                for row in rows if row["status"] == "active"
            },
        }
        lines = ["# Preserved heading", "", "unrelated text stays byte for byte", "",
                 "| 需求 | 当前状态 | 设计 | 执行任务 | 验收组 | 产品结果 |",
                 "|---|---|---|---|---|---|"]
        for row in rows:
            result = "不适用（已删除）" if row["status"] == "retired" else "未完成产品验收"
            lines.append(f"| {row['id']} | {'已删除' if row['status'] == 'retired' else '现行基线'} "
                         f"| [fixture](fixture.md) | W11 | {'/'.join(row['tests']) or '不适用'} | {result} |")
        self.trace_text = "\n".join(lines) + "\n"
        (self.root / TRACE_PATH).write_text(self.trace_text, encoding="utf-8")
        self.save()

    def git(self, *arguments: str) -> str:
        return subprocess.run(["git", "-C", str(self.root), *arguments], check=True,
                              text=True, capture_output=True).stdout.strip()

    def artifact(self, kind: str, result: str, tc_groups: list[str]) -> dict:
        path = f"docs/validation/{kind}.txt"
        content = ("用户授权本机豁免正式分发。\n" if kind == "waiver"
                   else f"Temporary fixture: {kind} checks only.\n")
        environment = "temporary Git repository; no real hardware claim"
        if kind == "formal-app-hardware":
            # Synthetic schema input only: no App or hardware was executed.
            content = "Synthetic formal environment schema record; no App or hardware was executed.\n"
            environment = {
                "execution": "formal-release-app", "build_configuration": "Release", "fixture": False,
                "app_bundle_id": "io.github.sisyphe550.TemperatureMonitor",
                "app_sha256": "a" * 64, "worker_sha256": "b" * 64,
                "model": "SchemaTestMachine", "os_build": "SchemaTestBuild",
                "context": "synthetic schema fixture; not real hardware acceptance",
            }
        (self.root / path).write_text(content, encoding="utf-8")
        scope = ["用户授权本机豁免正式分发"] if kind == "waiver" else [f"fixture {kind} check"]
        return {"path": path, "sha256": hashlib.sha256(content.encode()).hexdigest(),
                "source_commit": self.source_commit, "kind": kind, "result": result,
                "environment": environment,
                "scope": scope, "tc_groups": tc_groups}

    def save(self) -> None:
        for path, value in ((CATALOG_PATH, self.catalog), (ACCEPTANCE_PATH, self.acceptance)):
            (self.root / path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                                          encoding="utf-8")

    def module(self):
        return importlib.import_module("acceptance_evidence")

    def load(self) -> dict:
        self.save()
        return self.module().load_and_validate(self.root, self.acceptance)

    def run_cli(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(self.root / "scripts/bind-acceptance-evidence.py"),
                               *arguments], text=True, capture_output=True)

    def accept(self, requirement_id: str = "REQ-001", evidence: list[str] | None = None) -> None:
        self.catalog["requirement_results"][requirement_id] = {
            "verification": ACCEPTED, "evidence": evidence or ["software"],
            "covered_cases": ["CPUSchedulingTests.fiveIntervals"], "outstanding": [],
            "reason": "对应软件用例通过", "required_evidence_kinds": ["software"],
        }

    def test_rejects_missing_required_evidence_kinds(self) -> None:
        self.accept("REQ-008", ["software", "validation"])
        result = self.catalog["requirement_results"]["REQ-008"]
        result["required_evidence_kinds"] = ["formal-app-hardware"]
        del result["required_evidence_kinds"]
        with self.assertRaisesRegex(ValueError, "required_evidence_kinds"):
            self.load()

    def test_formal_hardware_requires_structured_environment(self) -> None:
        self.catalog["artifacts"]["hardware"]["environment"] = "fixture CI; no formal hardware run"
        with self.assertRaisesRegex(ValueError, r"hardware\.environment"):
            self.load()

    def test_formal_hardware_rejects_fixture_execution(self) -> None:
        environment = self.catalog["artifacts"]["hardware"]["environment"]
        for value in (True, 0, None):
            with self.subTest(fixture=value):
                environment["fixture"] = value
                with self.assertRaisesRegex(ValueError, "fixture"):
                    self.load()

    def test_formal_hardware_requires_release_execution(self) -> None:
        environment = self.catalog["artifacts"]["hardware"]["environment"]
        for field, value in (("execution", "ci"), ("build_configuration", "Debug")):
            with self.subTest(field=field):
                original = environment[field]
                environment[field] = value
                try:
                    with self.assertRaisesRegex(ValueError, field):
                        self.load()
                finally:
                    environment[field] = original

    def test_formal_hardware_requires_app_worker_and_machine_identity(self) -> None:
        environment = self.catalog["artifacts"]["hardware"]["environment"]
        for field in ("app_bundle_id", "app_sha256", "worker_sha256", "model", "os_build"):
            with self.subTest(missing=field):
                original = environment.pop(field)
                try:
                    with self.assertRaisesRegex(ValueError, field):
                        self.load()
                finally:
                    environment[field] = original
        for field, value in (("app_bundle_id", "example.fixture"), ("app_sha256", "short"),
                             ("worker_sha256", "F" * 64), ("model", ""), ("os_build", "")):
            with self.subTest(invalid=field):
                original = environment[field]
                environment[field] = value
                try:
                    with self.assertRaisesRegex(ValueError, field):
                        self.load()
                finally:
                    environment[field] = original

    def test_ci_cannot_be_relabelled_formal_without_release_identity(self) -> None:
        self.catalog["artifacts"]["validation"]["kind"] = "formal-app-hardware"
        with self.assertRaisesRegex(ValueError, r"validation\.environment"):
            self.load()

    def test_rejects_empty_required_evidence_kinds(self) -> None:
        self.accept("REQ-008", ["software", "validation"])
        self.catalog["requirement_results"]["REQ-008"]["required_evidence_kinds"] = []
        with self.assertRaisesRegex(ValueError, "required_evidence_kinds"):
            self.load()

    def test_delivery_must_belong_to_checked_out_history(self) -> None:
        self.git("checkout", "--quiet", "--orphan", "unrelated-delivery")
        self.git("commit", "--quiet", "-m", "unrelated delivery root")
        unrelated = self.git("rev-parse", "HEAD")
        self.git("checkout", "--quiet", "--detach", self.delivery_commit)
        self.catalog["delivery_commit"] = unrelated
        for artifact in self.catalog["artifacts"].values():
            artifact["source_commit"] = unrelated
        with self.assertRaisesRegex(ValueError, "delivery_commit.*checked-out HEAD"):
            self.load()

    def test_rejects_legacy_tc_catalog_that_infers_acceptance(self) -> None:
        """A passed TC report alone cannot accept every requirement in that group."""
        groups = {tc for row in self.acceptance["requirements"] for tc in row["tests"]}
        self.catalog = {"version": 1, "source_sha256": self.delivery_commit,
                        "tc_evidence": {tc: {"kind": "ci", "reports": ["docs/validation/software.txt"]}
                                        for tc in groups}}
        self.save()
        before = (self.root / ACCEPTANCE_PATH).read_bytes(), (self.root / TRACE_PATH).read_bytes()
        result = self.run_cli("--write")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("version", result.stderr)
        self.assertEqual(before, ((self.root / ACCEPTANCE_PATH).read_bytes(),
                                 (self.root / TRACE_PATH).read_bytes()))

    def test_explicit_pending_survives_passed_tc_evidence(self) -> None:
        result = self.catalog["requirement_results"]["REQ-001"]
        result.update(evidence=["software"], covered_cases=["CPUSchedulingTests.fiveIntervals"],
                      outstanding=["正式 App 五档各10分钟尚未执行"])
        catalog = self.load()
        bound = self.module().bound_acceptance(self.root, catalog, self.acceptance)
        row = bound["requirements"][0]
        self.assertEqual(row["verification"], PENDING)
        self.assertEqual(row["acceptance_notes"]["outstanding"], ["正式 App 五档各10分钟尚未执行"])
        self.assertEqual(row["evidence"][0]["source_commit"], self.source_commit)
        self.assertNotEqual(row["evidence"][0]["source_commit"], catalog["delivery_commit"])

    def test_binding_preserves_source_commit_and_is_a_deep_copy(self) -> None:
        self.accept()
        catalog = self.load()
        original = copy.deepcopy(self.acceptance)
        bound = self.module().bound_acceptance(self.root, catalog, self.acceptance)
        row = bound["requirements"][0]
        self.assertEqual(row["verification"], ACCEPTED)
        self.assertEqual(row["evidence"][0]["artifact_id"], "software")
        for field in ("path", "sha256", "source_commit", "kind", "result", "environment", "scope", "tc_groups"):
            self.assertEqual(row["evidence"][0][field], catalog["artifacts"]["software"][field])
        row["evidence"][0]["scope"].append("mutated result")
        row["acceptance_notes"]["covered_cases"].append("mutated result")
        self.assertEqual(self.acceptance, original)
        self.assertNotIn("mutated result", catalog["artifacts"]["software"]["scope"])
        self.assertEqual(catalog["requirement_results"]["REQ-001"]["covered_cases"],
                         ["CPUSchedulingTests.fiveIntervals"])

    def test_retired_bindings_are_removed(self) -> None:
        retired = self.acceptance["requirements"][11]
        retired.update(verification=ACCEPTED, evidence=[{"old": "claim"}], acceptance_notes={"old": "claim"})
        bound = self.module().bound_acceptance(self.root, self.load(), self.acceptance)
        self.assertEqual(bound["requirements"][11]["verification"], "not-applicable")
        self.assertNotIn("evidence", bound["requirements"][11])
        self.assertNotIn("acceptance_notes", bound["requirements"][11])

    def test_rejects_wrong_catalog_version_and_contract_revision(self) -> None:
        for field, value in (("version", 1), ("contract_revision", 2)):
            with self.subTest(field=field):
                original = self.catalog[field]
                self.catalog[field] = value
                with self.assertRaisesRegex(ValueError, field):
                    self.load()
                self.catalog[field] = original

    def test_rejects_missing_active_and_retired_requirement_results(self) -> None:
        del self.catalog["requirement_results"]["REQ-001"]
        with self.assertRaisesRegex(ValueError, "REQ-001"):
            self.load()
        self.catalog["requirement_results"]["REQ-001"] = copy.deepcopy(
            self.catalog["requirement_results"]["REQ-002"])
        self.catalog["requirement_results"]["REQ-012"] = copy.deepcopy(
            self.catalog["requirement_results"]["REQ-002"])
        with self.assertRaisesRegex(ValueError, "REQ-012"):
            self.load()

    def test_rejects_wrong_hash_and_missing_file(self) -> None:
        self.catalog["artifacts"]["software"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "sha256"):
            self.load()
        del self.catalog["artifacts"]["software"]
        (self.root / "docs/validation/formal-app-hardware.txt").unlink()
        with self.assertRaisesRegex(ValueError, "file"):
            self.load()

    def test_rejects_non_commit_and_non_ancestor_source(self) -> None:
        artifact = self.catalog["artifacts"]["software"]
        for commit in ("0" * 40, self.git("rev-parse", "HEAD:history.txt")):
            with self.subTest(commit=commit):
                artifact["source_commit"] = commit
                with self.assertRaisesRegex(ValueError, "commit"):
                    self.load()
        (self.root / "history.txt").write_text("later source\n", encoding="utf-8")
        self.git("commit", "--quiet", "-am", "later unrelated to delivery")
        artifact["source_commit"] = self.git("rev-parse", "HEAD")
        with self.assertRaisesRegex(ValueError, "ancestor"):
            self.load()

    def test_rejects_tag_object_as_source_commit(self) -> None:
        self.git("tag", "--no-sign", "-a", "evidence-tag", "-m", "annotated tag", self.source_commit)
        self.catalog["artifacts"]["software"]["source_commit"] = self.git("rev-parse", "evidence-tag")
        with self.assertRaisesRegex(ValueError, "commit"):
            self.load()

    def test_rejects_missing_delivery_commit(self) -> None:
        self.catalog["delivery_commit"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "delivery_commit"):
            self.load()

    def test_rejects_directory_traversal_absolute_directory_and_external_symlink(self) -> None:
        artifact = self.catalog["artifacts"]["software"]
        for path in ("../outside.txt", str(self.root / artifact["path"]), "docs/validation"):
            with self.subTest(path=path):
                artifact["path"] = path
                with self.assertRaisesRegex(ValueError, "path|file"):
                    self.load()
        outside = self.root.parent / f"{self.root.name}-outside.txt"
        outside.write_text("private outside content\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        link = self.root / "docs/validation/external.txt"
        link.symlink_to(outside)
        artifact["path"] = "docs/validation/external.txt"
        with self.assertRaisesRegex(ValueError, "path"):
            self.load()

    def test_rejects_failed_or_mislabeled_waiver_artifacts(self) -> None:
        artifact = self.catalog["artifacts"]["software"]
        for value in ("failed", "waived"):
            with self.subTest(result=value):
                artifact["result"] = value
                with self.assertRaisesRegex(ValueError, "result|waiv"):
                    self.load()
        artifact["result"] = "passed"
        self.catalog["artifacts"]["waiver"]["result"] = "passed"
        with self.assertRaisesRegex(ValueError, "waiv"):
            self.load()

    def test_accepted_requires_passed_evidence_covered_cases_and_no_outstanding(self) -> None:
        self.accept()
        result = self.catalog["requirement_results"]["REQ-001"]
        for field, value in (("evidence", []), ("covered_cases", []), ("outstanding", ["五档长测未执行"])):
            with self.subTest(field=field):
                original = result[field]
                result[field] = value
                with self.assertRaisesRegex(ValueError, "REQ-001"):
                    self.load()
                result[field] = original
        self.catalog["artifacts"]["software"]["result"] = "partial"
        with self.assertRaisesRegex(ValueError, "passed"):
            self.load()

    def test_pending_keeps_partial_evidence_and_missing_tc(self) -> None:
        result = self.catalog["requirement_results"]["REQ-008"]
        result.update(evidence=["software"], covered_cases=["RegistryTests.qualifiedSources"],
                      outstanding=["TC-VALIDATE 未覆盖"])
        self.catalog["artifacts"]["software"]["result"] = "partial"
        bound = self.module().bound_acceptance(self.root, self.load(), self.acceptance)
        self.assertEqual(bound["requirements"][7]["evidence"][0]["result"], "partial")
        self.assertEqual(bound["requirements"][7]["verification"], PENDING)

    def test_accepted_tc_union_must_cover_all_mapped_groups(self) -> None:
        self.accept("REQ-008", ["software"])
        with self.assertRaisesRegex(ValueError, "TC-VALIDATE"):
            self.load()
        self.catalog["requirement_results"]["REQ-008"]["evidence"].append("validation")
        self.load()

    def test_rejects_unknown_evidence_and_invalid_metadata(self) -> None:
        self.accept(evidence=["missing-artifact"])
        with self.assertRaisesRegex(ValueError, "missing-artifact"):
            self.load()
        self.accept()
        for field, value in (("scope", []), ("tc_groups", ["not-a-tc"]), ("environment", ""),
                             ("sha256", "short"), ("source_commit", "short"), ("kind", "mixed")):
            with self.subTest(field=field):
                artifact = self.catalog["artifacts"]["software"]
                original = artifact[field]
                artifact[field] = value
                with self.assertRaisesRegex(ValueError, field):
                    self.load()
                artifact[field] = original

    def test_software_cannot_satisfy_required_formal_hardware(self) -> None:
        self.accept("REQ-008", ["software", "validation"])
        result = self.catalog["requirement_results"]["REQ-008"]
        result["required_evidence_kinds"] = ["formal-app-hardware"]
        with self.assertRaisesRegex(ValueError, "formal-app-hardware"):
            self.load()
        result["verification"] = PENDING
        result["outstanding"] = ["正式 App 硬件证据缺失"]
        self.load()
        result.update(verification=ACCEPTED, outstanding=[])
        result["evidence"].append("hardware")
        self.load()

    def test_only_req127_can_use_authorized_local_whole_requirement_waiver(self) -> None:
        result = self.catalog["requirement_results"]["REQ-127"]
        result.update(verification=WAIVED, evidence=["waiver"], covered_cases=["本机交付授权核对"],
                      outstanding=[], reason="用户授权本机豁免正式分发")
        self.load()
        result["reason"] = "not required"
        with self.assertRaisesRegex(ValueError, "authoriz|授权"):
            self.load()
        result["reason"] = "用户授权本机豁免正式分发"
        self.catalog["artifacts"]["waiver"]["scope"] = ["distribution not needed"]
        with self.assertRaisesRegex(ValueError, "authoriz|授权"):
            self.load()
        self.catalog["artifacts"]["waiver"]["scope"] = ["用户授权本机豁免正式分发"]
        self.catalog["requirement_results"]["REQ-001"] = copy.deepcopy(result)
        with self.assertRaisesRegex(ValueError, "REQ-001"):
            self.load()

    def test_waived_requires_only_waiver_and_accepted_cannot_include_waiver(self) -> None:
        self.catalog["artifacts"]["software"]["tc_groups"].append("TC-RELEASE")
        result = self.catalog["requirement_results"]["REQ-127"]
        result.update(verification=WAIVED, evidence=["software"], covered_cases=["授权核对"],
                      outstanding=[], reason="用户授权本机豁免正式分发")
        with self.assertRaisesRegex(ValueError, "waiver"):
            self.load()
        result.update(verification=ACCEPTED, evidence=["waiver"])
        with self.assertRaisesRegex(ValueError, "waiv|passed"):
            self.load()

    def test_subcase_waiver_does_not_waive_other_whole_requirement(self) -> None:
        self.accept()
        self.catalog["requirement_results"]["REQ-001"]["reason"] = "软件规则已验证；用户授权本机豁免72h耐久子用例"
        self.load()
        self.catalog["requirement_results"]["REQ-001"]["verification"] = WAIVED
        with self.assertRaisesRegex(ValueError, "REQ-001"):
            self.load()

    def test_validate_bound_detects_evidence_notes_and_result_drift(self) -> None:
        self.accept()
        catalog = self.load()
        bound = self.module().bound_acceptance(self.root, catalog, self.acceptance)
        self.assertEqual(self.module().validate_bound(self.root, catalog, bound), [])
        row = bound["requirements"][0]
        for field, value in (("verification", PENDING), ("evidence", []),
                             ("acceptance_notes", {"covered_cases": ["invented"]})):
            with self.subTest(field=field):
                original = row[field]
                row[field] = value
                errors = self.module().validate_bound(self.root, catalog, bound)
                self.assertTrue(any("REQ-001" in error and field in error for error in errors), errors)
                row[field] = original
        bound["requirements"][11]["evidence"] = []
        self.assertTrue(any("REQ-012" in error for error in self.module().validate_bound(self.root, catalog, bound)))

    def test_dry_run_preserves_files_and_write_changes_only_binding_columns(self) -> None:
        self.accept()
        self.save()
        before = (self.root / ACCEPTANCE_PATH).read_bytes(), (self.root / TRACE_PATH).read_bytes()
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, ((self.root / ACCEPTANCE_PATH).read_bytes(),
                                 (self.root / TRACE_PATH).read_bytes()))
        self.assertEqual(json.loads(result.stdout)["verification_counts"].get(ACCEPTED), 1)
        self.assertEqual(self.run_cli("--write").returncode, 0)
        updated = json.loads((self.root / ACCEPTANCE_PATH).read_text(encoding="utf-8"))
        self.assertEqual(updated["preserved_metadata"], {"note": "keep this"})
        self.assertEqual(updated["requirements"][0]["verification"], ACCEPTED)
        self.assertEqual(updated["requirements"][1]["verification"], PENDING)
        expected_trace = self.trace_text.replace(
            "| REQ-001 | 现行基线 | [fixture](fixture.md) | W11 | TC-SCHEDULE | 未完成产品验收 |",
            "| REQ-001 | 现行基线 | [fixture](fixture.md) | W11 | TC-SCHEDULE | 本地验收通过 |")
        self.assertEqual((self.root / TRACE_PATH).read_text(encoding="utf-8"), expected_trace)
        again = self.run_cli("--write")
        self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
        self.assertEqual((self.root / TRACE_PATH).read_text(encoding="utf-8"), expected_trace)

    def test_validation_error_writes_neither_acceptance_nor_traceability(self) -> None:
        self.accept()
        self.catalog["artifacts"]["software"]["sha256"] = "0" * 64
        self.save()
        before = (self.root / ACCEPTANCE_PATH).read_bytes(), (self.root / TRACE_PATH).read_bytes()
        result = self.run_cli("--write")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("sha256", result.stderr)
        self.assertEqual(before, ((self.root / ACCEPTANCE_PATH).read_bytes(),
                                 (self.root / TRACE_PATH).read_bytes()))

    def test_bad_traceability_is_rejected_before_either_write(self) -> None:
        self.accept()
        self.save()
        (self.root / TRACE_PATH).write_text(self.trace_text.replace("| REQ-001 |", "| REQ-900 |"), encoding="utf-8")
        before = (self.root / ACCEPTANCE_PATH).read_bytes(), (self.root / TRACE_PATH).read_bytes()
        result = self.run_cli("--write")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("traceability", result.stderr)
        self.assertEqual(before, ((self.root / ACCEPTANCE_PATH).read_bytes(),
                                 (self.root / TRACE_PATH).read_bytes()))


    def test_rejects_wrong_acceptance_format_version(self) -> None:
        self.acceptance["version"] = 2
        with self.assertRaisesRegex(ValueError, "acceptance.*version"):
            self.load()

    def test_waiver_requires_waiver_evidence_kind_policy(self) -> None:
        result = self.catalog["requirement_results"]["REQ-127"]
        result.update(verification=WAIVED, evidence=["waiver"], covered_cases=["本机交付授权核对"],
                      outstanding=[], reason="用户授权本机豁免正式分发",
                      required_evidence_kinds=["formal-app-hardware"])
        with self.assertRaisesRegex(ValueError, "REQ-127.*required_evidence_kinds"):
            self.load()

    def test_second_replace_failure_rolls_back_both_documents(self) -> None:
        import importlib.util
        from unittest.mock import patch

        path = self.root / "scripts/bind-acceptance-evidence.py"
        spec = importlib.util.spec_from_file_location("rollback_binder", path)
        binder = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(binder)
        acceptance = self.root / ACCEPTANCE_PATH
        traceability = self.root / TRACE_PATH
        original = {acceptance: acceptance.read_bytes(), traceability: traceability.read_bytes()}
        original_replace = Path.replace
        calls = 0

        def fail_second_replace(temporary: Path, target: Path):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("injected second document replacement failure")
            return original_replace(temporary, target)

        with patch.object(Path, "replace", fail_second_replace):
            with self.assertRaisesRegex(OSError, "second document replacement"):
                binder.write_documents({acceptance: b"staged acceptance\n", traceability: b"staged trace\n"})
        for document, content in original.items():
            self.assertEqual(document.read_bytes(), content)
            self.assertEqual(list(document.parent.glob(document.name + ".*")), [])



if __name__ == "__main__":
    unittest.main(verbosity=2)
