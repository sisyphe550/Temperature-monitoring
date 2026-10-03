#!/usr/bin/env python3
"""Bind explicit, validated per-REQ evidence; dry-run never writes documentation."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import sys
import tempfile

sys.dont_write_bytecode = True
from acceptance_evidence import TRACE_RESULT, bound_acceptance, load_and_validate


ROOT = Path(__file__).resolve().parents[1]
ACCEPTANCE_PATH = ROOT / "docs/contracts/acceptance-v1.json"
TRACEABILITY_PATH = ROOT / "docs/17-traceability.md"


def updated_traceability(text: str, acceptance: dict) -> str:
    by_id = {row["id"]: row["verification"] for row in acceptance["requirements"]}
    seen = []
    updated = []
    for line in text.splitlines(keepends=True):
        match = re.match(r"^\|[ \t]*(REQ-\d{3})[ \t]*\|", line)
        if not match:
            updated.append(line)
            continue
        requirement_id = match[1]
        cells = line.split("|")
        if requirement_id not in by_id or requirement_id in seen or len(cells) != 8:
            raise ValueError(f"traceability: unknown, duplicate or malformed row {requirement_id}")
        seen.append(requirement_id)
        whitespace = re.fullmatch(r"([ \t]*).*?([ \t]*)", cells[6])
        cells[6] = whitespace[1] + TRACE_RESULT[by_id[requirement_id]] + whitespace[2]
        updated.append("|".join(cells))
    if seen != list(by_id):
        raise ValueError("traceability: requirement rows must match acceptance order and IDs exactly")
    return "".join(updated)


def write_documents(contents: dict[Path, bytes]) -> None:
    """Stage both documents before replacement; restore any replaced file on IO failure."""
    temporary_paths = {}
    originals = {path: path.read_bytes() for path in contents}
    replaced = []
    try:
        for path, content in contents.items():
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name + ".", delete=False) as handle:
                temporary_paths[path] = Path(handle.name)
                os.fchmod(handle.fileno(), path.stat().st_mode & 0o777)
                handle.write(content)
        for path, temporary in temporary_paths.items():
            temporary.replace(path)
            replaced.append(path)
    except OSError:
        for path in replaced:
            path.write_bytes(originals[path])
        raise
    finally:
        for temporary in temporary_paths.values():
            temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write acceptance-v1.json and 17-traceability.md")
    args = parser.parse_args()
    try:
        for path in (ACCEPTANCE_PATH, TRACEABILITY_PATH):
            if not path.resolve().is_relative_to(ROOT) or not path.is_file():
                raise ValueError(f"{path.name}: must be a file inside the repository")
        acceptance = json.loads(ACCEPTANCE_PATH.read_text(encoding="utf-8"))
        catalog = load_and_validate(ROOT, acceptance)
        bound = bound_acceptance(ROOT, catalog, acceptance)
        traceability = updated_traceability(TRACEABILITY_PATH.read_bytes().decode("utf-8"), bound)
        if args.write:
            write_documents({
                ACCEPTANCE_PATH: (json.dumps(bound, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
                TRACEABILITY_PATH: traceability.encode("utf-8"),
            })
    except (OSError, ValueError) as error:
        print(f"acceptance evidence: {error}", file=sys.stderr)
        return 1
    print(json.dumps({"status": "ok", "delivery_commit": catalog["delivery_commit"],
                      "verification_counts": dict(Counter(row["verification"] for row in bound["requirements"]))},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
