# W09 exit report

**HEAD:** `14cac6fe3b365ff36bf6c5c7e795dffc7319cf73`  
**Model / OS:** Mac16,13 / 15.7.3 (24G419)  
**App SHA:** `72339d42a7b0e272b5e568cb37e3e733663bef6749fd0d9d5443decc42c6ec3e`  
**Worker SHA:** `83e14d5ea60362488b225bc60a84ce1b59cb8d112c3bbff61e249bc79da4e01d`  
**Signature:** ad-hoc

## Suites (atomic, single binary)

| Suite | Result | Evidence |
|-------|--------|----------|
| sources | passed | `sources.json` |
| schedules | passed | `schedules.json` (五档 × 600s) |
| lifecycle | passed | `lifecycle.json`, `processes.json` |
| endurance ≥73h | **cancelled** | maintainer waiver 2026-09-23; optional tool in main |

Hardware evidence: `docs/validation/product-hardware/Mac16,13-24G419/14cac6fe3b365ff36bf6c5c7e795dffc7319cf73/`

`qualified_combinations` populated in `platform.json` with suites `[sources, schedules, lifecycle]`.

## Software gates

- PR #20–#23 merged
- `swift test` — 244 passed
- `python3 scripts/test-product-qualification-schema.py` — 8 checks passed
- `python3 scripts/validate-handoff.py` — passed
- `full` hardware qualification — passed (~54 min wall time)

## W09 status

**Complete** for local ad-hoc App on Mac16,13 / 24G419. W10 may proceed (formal signing / notarization).
