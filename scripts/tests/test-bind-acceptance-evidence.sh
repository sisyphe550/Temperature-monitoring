#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

python3 scripts/bind-acceptance-evidence.py >/tmp/bind-acceptance-dry.json
python3 - <<'PY'
import json
from pathlib import Path

summary = json.loads(Path("/tmp/bind-acceptance-dry.json").read_text())
counts = summary["verification_counts"]
assert counts.get("product-accepted-local", 0) == 123, counts
assert counts.get("product-waived", 0) == 1, counts
assert counts.get("pending-product-acceptance", 0) == 8, counts
assert counts.get("not-applicable", 0) == 2, counts
print("bind-acceptance dry-run counts ok")
PY

python3 scripts/bind-acceptance-evidence.py --write
python3 scripts/validate-handoff.py

if python3 scripts/validate-handoff.py --product-acceptance; then
  echo "expected --product-acceptance to fail while TC-ACCEPTANCE meta reqs are pending" >&2
  exit 1
fi

echo "test-bind-acceptance-evidence: passed"
