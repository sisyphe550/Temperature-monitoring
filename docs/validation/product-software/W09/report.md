# W09 product software validation (partial)

**Branch:** `feature/w09-hardware-qualification`  
**Scope:** T09.1–T09.3 tooling and Mac16,13 hardware evidence collected through lifecycle suite.

## Completed

| Task | Status | Evidence |
|------|--------|----------|
| T09.1 schema + dry-run collector | merged PR #20 | `scripts/product_qualification.py`, contract schema |
| T09.2 sources + schedules | merged PR #21 | `docs/validation/product-hardware/Mac16,13-24G419/a06fddbf37a9019fcf25b3b0509b8a8f2ce9f92f/` |
| T09.3 lifecycle collector + sleep/wake fix | this branch | lifecycle/processes JSON under current HEAD after commit |

## Software gates (local)

- `swift test --package-path Packages/TemperatureCore` — 244 tests passed
- `python3 scripts/test-product-qualification-schema.py` — 7 checks passed
- `python3 scripts/validate-handoff.py` — passed

## Hardware notes (Mac16,13 / 24G419)

- 12/12 CPU SMC keys available (`flt `, 4 bytes)
- SSD unavailable (`nvme_interconnect_lookup_failed`) — recorded, not blocking optional source
- Battery selected via `smc:TB1T`
- Five schedule phases × 600s passed with `qualified_combinations` (sources + schedules)
- Lifecycle: 3× sleep/wake (gap + segment), period switch, exit/restart, double-instance lock, no orphan worker after stop, App quit/relaunch

## Pending (W09)

- T09.4 endurance ≥73h and qualified-combination finalization in ops matrix
- W09 exit: full software report at `docs/validation/product-software/W09/<head-sha>/report.md` after all tasks merge

## Fix included in T09.3

`suspendForSleep` previously called terminal `WorkerClient.close()`, blocking `resumeAfterWake` on real hardware. Added `releaseConnection()` on transport/client so sleep terminates the worker without permanently closing the client.
