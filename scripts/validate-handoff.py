#!/usr/bin/env python3
"""Validate the executable documentation handoff without claiming product acceptance."""

from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CONTRACTS = DOCS / "contracts"
ERRORS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"{path.relative_to(ROOT)}: invalid JSON: {error}")
        return {}
    if not isinstance(value, dict):
        fail(f"{path.relative_to(ROOT)}: top level must be an object")
        return {}
    return value


def requirement_sections() -> dict[str, str]:
    path = DOCS / "01-requirements.md"
    text = path.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^### (REQ-\d{3})｜.*$", text, re.MULTILINE))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        requirement_id = match.group(1)
        if requirement_id in sections:
            fail(f"01-requirements.md: duplicate {requirement_id}")
        sections[requirement_id] = text[match.end() : end]
    expected = [f"REQ-{number:03d}" for number in range(1, 135)]
    if list(sections) != expected:
        missing = sorted(set(expected) - set(sections))
        extra = sorted(set(sections) - set(expected))
        fail(f"01-requirements.md: IDs not exactly REQ-001..134; missing={missing}, extra={extra}")
    return sections


def validate_requirements() -> None:
    sections = requirement_sections()
    contract = load_json(CONTRACTS / "acceptance-v1.json")
    rows = contract.get("requirements", [])
    if not isinstance(rows, list):
        fail("acceptance-v1.json: requirements must be an array")
        return
    by_id = {row.get("id"): row for row in rows if isinstance(row, dict)}
    if len(rows) != 134 or len(by_id) != 134 or set(by_id) != set(sections):
        fail("acceptance-v1.json: must contain each of 134 requirement IDs exactly once")
        return

    retired_ids = {requirement_id for requirement_id, row in by_id.items() if row.get("status") == "retired"}
    if retired_ids != {"REQ-012", "REQ-114"}:
        fail(f"acceptance-v1.json: retired IDs are {sorted(retired_ids)}, expected REQ-012/114")

    task_text = (DOCS / "22-agent-implementation-plan.md").read_text(encoding="utf-8")
    defined_tasks = set(re.findall(r"^## (W(?:0\d|1[01]))：", task_text, re.MULTILINE))
    if defined_tasks != {f"W{number:02d}" for number in range(12)}:
        fail(f"22-agent-implementation-plan.md: W00..W11 mismatch: {sorted(defined_tasks)}")

    test_text = (DOCS / "10-test-strategy.md").read_text(encoding="utf-8")
    defined_tests = set(re.findall(r"^\| (TC-[A-Z0-9-]+) \|", test_text, re.MULTILINE))
    if len(defined_tests) != 19:
        fail(f"10-test-strategy.md: expected 19 TC groups, found {len(defined_tests)}")

    for requirement_id, section in sections.items():
        row = by_id[requirement_id]
        if requirement_id in retired_ids:
            if row.get("tasks") or row.get("tests") or row.get("body_sha256"):
                fail(f"{requirement_id}: retired item must not have tasks, tests, or body hash")
            if "已删除，不纳入实现与验收" not in section:
                fail(f"{requirement_id}: retired status missing from requirements")
            continue

        body_match = re.search(r"^- 正文：(.*)$", section, re.MULTILINE)
        if not body_match:
            fail(f"{requirement_id}: active requirement has no body")
            continue
        digest = hashlib.sha256(body_match.group(1).encode("utf-8")).hexdigest()
        if row.get("body_sha256") != digest:
            fail(f"{requirement_id}: body_sha256 is stale")
        if row.get("verification") != "pending-product-acceptance":
            fail(f"{requirement_id}: must remain pending-product-acceptance")
        tasks = row.get("tasks")
        tests = row.get("tests")
        design = row.get("design")
        if not tasks or not set(tasks) <= defined_tasks:
            fail(f"{requirement_id}: unknown or empty task mapping {tasks}")
        if not tests or not set(tests) <= defined_tests:
            fail(f"{requirement_id}: unknown or empty test mapping {tests}")
        if not design:
            fail(f"{requirement_id}: empty design mapping")
        else:
            for filename in design:
                if not (DOCS / filename).is_file():
                    fail(f"{requirement_id}: design file does not exist: {filename}")

    traceability = (DOCS / "17-traceability.md").read_text(encoding="utf-8")
    trace_rows = re.findall(r"^\| (REQ-\d{3}) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$", traceability, re.MULTILINE)
    trace_ids = [row[0] for row in trace_rows]
    if trace_ids != [f"REQ-{number:03d}" for number in range(1, 135)]:
        fail("17-traceability.md: rows must be REQ-001..REQ-134 exactly once and in order")
    for requirement_id, status, design_cell, task_cell, test_cell, result in trace_rows:
        row = by_id[requirement_id]
        design_files = re.findall(r"\[[^\]]+\]\(([^)]+\.md)\)", design_cell)
        tasks = [] if task_cell.strip() == "不适用" else task_cell.strip().split("/")
        tests = [] if test_cell.strip() == "不适用" else test_cell.strip().split("/")
        if design_files != row.get("design") or tasks != row.get("tasks") or tests != row.get("tests"):
            fail(f"17-traceability.md: {requirement_id} differs from acceptance-v1.json")
        if row.get("status") == "retired":
            if status.strip() != "已删除" or result.strip() != "不适用（已删除）":
                fail(f"17-traceability.md: {requirement_id} retired labels are inconsistent")
        elif status.strip() != "现行基线" or result.strip() != "未完成产品验收":
            fail(f"17-traceability.md: {requirement_id} active labels are inconsistent")


def validate_contract_values() -> None:
    defaults = load_json(CONTRACTS / "defaults-v1.json")
    exact = {
        "contract_version": 1,
        "cpu_intervals_ms": [50, 100, 200, 500, 1000],
        "cpu_default_ms": 200,
        "ssd_interval_ms": 500,
        "battery_interval_ms": 1000,
        "ring_capacity_per_series": 8192,
        "max_active_series": 32,
        "writer_max_records": 16384,
        "writer_pause_at_records": 12288,
        "writer_resume_below_records": 8192,
        "writer_flush_records": 512,
        "writer_reserve_records_per_event": 512,
        "db_soft_bytes": 805306368,
        "db_hard_bytes": 1073741824,
        "wal_soft_bytes": 33554432,
        "wal_hard_bytes": 67108864,
    }
    for key, expected in exact.items():
        if defaults.get(key) != expected:
            fail(f"defaults-v1.json: {key}={defaults.get(key)!r}, expected {expected!r}")
    if not (
        defaults.get("writer_resume_below_records", 0)
        < defaults.get("writer_pause_at_records", 0)
        < defaults.get("writer_max_records", 0)
    ):
        fail("defaults-v1.json: writer resume/pause/max ordering is invalid")
    if defaults.get("writer_reserve_records_per_event", 0) > defaults.get("writer_flush_records", 0):
        fail("defaults-v1.json: one event reservation exceeds a transaction")

    profile = load_json(CONTRACTS / "first-profile-v1.json")
    expected_keys = ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
    if profile.get("model") != "Mac16,13" or profile.get("cpu_keys") != expected_keys:
        fail("first-profile-v1.json: first model or ordered 12-key CPU set changed")
    if len(set(profile.get("cpu_keys", []))) != 12:
        fail("first-profile-v1.json: CPU keys must be 12 unique case-sensitive values")
    if profile.get("expected_smc_encoding") != "flt " or profile.get("expected_smc_size_bytes") != 4:
        fail("first-profile-v1.json: first profile must require flt-space/4-byte SMC values")
    if profile.get("cpu_formula") != "max" or profile.get("automatic_unknown_model_profile") is not False:
        fail("first-profile-v1.json: CPU max or unknown-model refusal changed")


def validate_task_graph() -> None:
    contract = load_json(CONTRACTS / "tasks-v1.json")
    rows = contract.get("tasks", [])
    if not isinstance(rows, list):
        fail("tasks-v1.json: tasks must be an array")
        return
    if len(rows) != 50:
        fail(f"tasks-v1.json: expected 50 execution tasks, found {len(rows)}")
    by_id: dict[str, dict] = {}
    for row in rows:
        if not isinstance(row, dict):
            fail("tasks-v1.json: every task must be an object")
            continue
        task_id = row.get("id")
        if not isinstance(task_id, str) or not re.fullmatch(r"T(?:0\d|1[01])\.\d", task_id):
            fail(f"tasks-v1.json: invalid task ID {task_id!r}")
            continue
        if task_id in by_id:
            fail(f"tasks-v1.json: duplicate {task_id}")
        by_id[task_id] = row
        expected_package = f"W{task_id[1:3]}"
        if row.get("work_package") != expected_package:
            fail(f"tasks-v1.json: {task_id} must belong to {expected_package}")
        if not isinstance(row.get("depends_on"), list):
            fail(f"tasks-v1.json: {task_id}.depends_on must be an array")

    if contract.get("entry_task") != "T00.1" or contract.get("terminal_task") != "T11.3":
        fail("tasks-v1.json: entry/terminal task must be T00.1/T11.3")
    roots = {task_id for task_id, row in by_id.items() if row.get("depends_on") == []}
    if roots != {"T00.1"}:
        fail(f"tasks-v1.json: only T00.1 may be a root, found {sorted(roots)}")

    order = {row.get("id"): index for index, row in enumerate(rows) if isinstance(row, dict)}
    for task_id, row in by_id.items():
        dependencies = row.get("depends_on", [])
        if len(dependencies) != len(set(dependencies)):
            fail(f"tasks-v1.json: {task_id} has duplicate dependencies")
        for dependency in dependencies:
            if dependency not in by_id:
                fail(f"tasks-v1.json: {task_id} depends on unknown {dependency}")
            if dependency == task_id:
                fail(f"tasks-v1.json: {task_id} depends on itself")
            if dependency in order and order[dependency] >= order[task_id]:
                fail(f"tasks-v1.json: {task_id} appears before dependency {dependency}")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(task_id: str) -> None:
        if task_id in visiting:
            fail(f"tasks-v1.json: dependency cycle reaches {task_id}")
            return
        if task_id in visited or task_id not in by_id:
            return
        visiting.add(task_id)
        for dependency in by_id[task_id].get("depends_on", []):
            visit(dependency)
        visiting.remove(task_id)
        visited.add(task_id)

    for task_id in by_id:
        visit(task_id)

    ancestors: set[str] = set()

    def collect(task_id: str) -> None:
        if task_id in ancestors or task_id not in by_id:
            return
        ancestors.add(task_id)
        for dependency in by_id[task_id].get("depends_on", []):
            collect(dependency)

    collect("T11.3")
    if ancestors != set(by_id):
        fail(f"tasks-v1.json: tasks not connected to terminal: {sorted(set(by_id) - ancestors)}")

    plan = (DOCS / "23-execution-task-breakdown.md").read_text(encoding="utf-8")
    plan_ids = re.findall(r"^\| - \[ \] (T(?:0\d|1[01])\.\d) ", plan, re.MULTILINE)
    if plan_ids != [row.get("id") for row in rows if isinstance(row, dict)]:
        fail("23-execution-task-breakdown.md: checkbox task order differs from tasks-v1.json")
    task_lines = [line for line in plan.splitlines() if re.match(r"^\| - \[ \] T(?:0\d|1[01])\.\d ", line)]
    for line in task_lines:
        columns = [column.strip() for column in line.strip().strip("|").split("|")]
        if len(columns) != 6 or any(not column for column in columns):
            fail(f"23-execution-task-breakdown.md: task row must have six non-empty columns: {line[:40]}")
    for marker in ("TBD", "TODO", "FIXME", "implement later"):
        if marker in plan:
            fail(f"23-execution-task-breakdown.md: placeholder marker present: {marker}")

    packages = {row.get("work_package") for row in rows if isinstance(row, dict)}
    if packages != {f"W{number:02d}" for number in range(12)}:
        fail(f"tasks-v1.json: work-package coverage mismatch: {sorted(packages)}")
    expected_counts = {"W00": 5, "W01": 4, "W02": 6, "W03": 4, "W04": 5, "W05": 5,
                       "W06": 4, "W07": 5, "W08": 3, "W09": 4, "W10": 2, "W11": 3}
    actual_counts = {package: sum(row.get("work_package") == package for row in rows if isinstance(row, dict))
                     for package in expected_counts}
    if actual_counts != expected_counts:
        fail(f"tasks-v1.json: task counts changed: {actual_counts}")


def expect_integrity(connection: sqlite3.Connection, sql: str, parameters: tuple = ()) -> None:
    try:
        connection.execute(sql, parameters)
    except sqlite3.IntegrityError:
        return
    fail(f"schema-v1.sql: expected IntegrityError for {sql.split()[0:3]}")


def validate_schema() -> None:
    schema = (CONTRACTS / "schema-v1.sql").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory(prefix="temperature-handoff-") as directory:
        database = Path(directory) / "contract.sqlite3"
        connection = sqlite3.connect(database)
        try:
            connection.executescript(schema)
            if connection.execute("PRAGMA user_version").fetchone()[0] != 1:
                fail("schema-v1.sql: user_version is not 1")
            if connection.execute("PRAGMA foreign_keys").fetchone()[0] != 1:
                fail("schema-v1.sql: foreign keys are not enabled")
            views = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='view'")}
            if views != {"samples_1s", "samples_10s", "samples_1m"}:
                fail(f"schema-v1.sql: aggregate views mismatch: {sorted(views)}")

            connection.execute("INSERT INTO session VALUES (?,?,?,?,?)", ("session", 1, "Mac16,13", "24G419", "0.1"))
            connection.execute(
                "INSERT INTO sources VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                ("source", "session", "smc", "Tp01", None, 1, "cpuZone", "flt ", "fixture", "v1", "referenceClassified"),
            )
            connection.execute("INSERT INTO series VALUES (?,?,?,?,?,?,?)", ("series", "session", "fixture.cpu", 1, "cpuZone", "Fixture", "identity"))
            connection.execute("INSERT INTO series_members VALUES (?,?,?)", ("series", "source", 0))
            connection.execute("INSERT INTO segments VALUES (?,?,?,?,?)", ("series", 1, 0, 1, "start"))
            connection.execute("INSERT INTO segments VALUES (?,?,?,?,?)", ("series", 2, 0, 1, "gap"))
            raw = ("sample", "series", 1, 1, 1, 200, 70.0, "unknown", None)
            connection.execute("INSERT INTO raw_samples VALUES (?,?,?,?,?,?,?,?,?)", raw)
            expect_integrity(connection, "INSERT INTO raw_samples VALUES (?,?,?,?,?,?,?,?,?)", raw)
            expect_integrity(
                connection,
                "INSERT INTO raw_samples VALUES (?,?,?,?,?,?,?,?,?)",
                ("bad-fk", "series", 99, 2, 2, 200, 70.0, "unknown", None),
            )
            aggregate = ("series", 1, 1, 0, 1_000_000_000, 60.0, 80.0, 300.0, 80.0, 900_000_000, "sample", 4, 1_000_000_000, 0)
            connection.execute("INSERT INTO aggregates VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", aggregate)
            connection.execute("INSERT INTO aggregates VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", ("series", 2, *aggregate[2:]))
            average = connection.execute("SELECT avg FROM samples_1s WHERE segment=1").fetchone()[0]
            if average != 75.0:
                fail(f"schema-v1.sql: count-weighted view average is {average}, expected 75")
            expect_integrity(
                connection,
                "INSERT INTO aggregates VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                ("series", 1, 10, 0, 10_000_000_000, 1.0, 1.0, 0.0, 1.0, 1, "sample", 0, 0, 1),
            )
            expect_integrity(
                connection,
                "INSERT INTO trend_samples VALUES (?,?,?,?,?,?,?)",
                ("series", 1, 1, 1, None, "stable", 3),
            )

            connection.commit()
            connection.execute("BEGIN")
            connection.execute("INSERT INTO gaps VALUES (?,?,?,?,?)", ("rollback", "series", 1, None, "timeout"))
            try:
                connection.execute("INSERT INTO gaps VALUES (?,?,?,?,?)", ("rollback", "series", 2, None, "timeout"))
            except sqlite3.IntegrityError:
                connection.rollback()
            if connection.execute("SELECT count(*) FROM gaps WHERE gap_id='rollback'").fetchone()[0] != 0:
                fail("schema-v1.sql: transaction rollback left a partial row")
        except sqlite3.Error as error:
            fail(f"schema-v1.sql: execution failed: {error}")
        finally:
            connection.close()


def validate_links() -> None:
    files = [ROOT / "README.md", ROOT / "CONTEXT.md", ROOT / "AGENTS.md"]
    files.extend(sorted(DOCS.glob("[0-2][0-9]-*.md")))
    files.extend(
        [
            DOCS / "research/2026-09-17-handoff-interface-audit.md",
            DOCS / "research/2026-09-18-handoff-validation.md",
            DOCS / "research/2026-09-19-task-breakdown-validation.md",
        ]
    )
    pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
    for path in files:
        if not path.is_file():
            fail(f"missing handoff document: {path.relative_to(ROOT)}")
            continue
        for target in pattern.findall(path.read_text(encoding="utf-8")):
            target = target.strip().strip("<>")
            if "://" in target or target.startswith(("mailto:", "#")):
                continue
            local = target.split("#", 1)[0]
            if local and not (path.parent / local).resolve().exists():
                fail(f"{path.relative_to(ROOT)}: broken local link {target}")


def main() -> int:
    validate_requirements()
    validate_contract_values()
    validate_task_graph()
    validate_schema()
    validate_links()
    if ERRORS:
        print(json.dumps({"status": "failed", "errors": ERRORS}, ensure_ascii=False, indent=2))
        return 1
    print(
        json.dumps(
            {
                "status": "passed",
                "requirements": {"total": 134, "active": 132, "retired": 2},
                "tasks": {"work_packages": 12, "execution_tasks": 50},
                "test_groups": 19,
                "contracts": ["defaults-v1.json", "first-profile-v1.json", "api-v1.swift", "schema-v1.sql", "acceptance-v1.json", "tasks-v1.json"],
                "scope": "documentation contracts only; production App and hardware acceptance remain pending",
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
