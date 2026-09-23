# W09 product software validation

**Scope:** T09.1–T09.3 tooling and Mac16,13 hardware evidence. T09.4 ≥73h endurance **cancelled by maintainer** (2026-09-23).

## Completed

| Task | Status | Evidence |
|------|--------|----------|
| T09.1 schema + dry-run collector | merged PR #20 | `scripts/product_qualification.py`, contract schema |
| T09.2 sources + schedules | merged PR #21 | `docs/validation/product-hardware/Mac16,13-24G419/a06fddbf37a9019fcf25b3b0509b8a8f2ce9f92f/` |
| T09.3 lifecycle collector + sleep/wake fix | merged PR #22 | `docs/validation/product-hardware/Mac16,13-24G419/15cada6…/` |
| T09.4 ≥73h endurance | **cancelled** | optional `endurance` suite in PR #23; not a qualification gate |

## Maintainer decision (2026-09-23)

73 小时连续实机 endurance 不再作为 W09 退出条件。`qualified_combinations` 门禁调整为 sources + schedules + lifecycle（同一 App/worker SHA）。`endurance` 采集器可保留作可选短时诊断，不得替代已取消的长跑验收。

## Software gates

- `swift test --package-path Packages/TemperatureCore` — 244 tests passed
- `python3 scripts/test-product-qualification-schema.py` — passed
- `python3 scripts/validate-handoff.py` — passed

## Hardware notes (Mac16,13 / 24G419)

- 12/12 CPU SMC keys available (`flt `, 4 bytes)
- SSD unavailable (`nvme_interconnect_lookup_failed`) — recorded, not blocking optional source
- Battery selected via `smc:TB1T`
- Five schedule phases × 600s passed
- Lifecycle: 3× sleep/wake, period switch, exit/restart, double-instance lock, no orphan worker, App quit/relaunch

## Remaining for atomic `qualified_combinations`

T09.2 与 T09.3 证据来自不同 App 二进制 SHA。登记前须在同一 `build/TemperatureMonitor.app` 上执行：

```sh
bash scripts/run-hardware-qualification.sh \
  --app build/TemperatureMonitor.app \
  --profile docs/contracts/first-profile-v1.json \
  --suite full \
  --output docs/validation/product-hardware/Mac16,13-24G419/$(git rev-parse HEAD)
```

（`full` 不含 endurance。）

## Fix included in T09.3

`suspendForSleep` previously called terminal `WorkerClient.close()`, blocking `resumeAfterWake` on real hardware. Added `releaseConnection()` plus in-flight I/O drain before worker termination.
