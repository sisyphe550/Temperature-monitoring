# W05 软件验证报告

记录时间：2026-09-22。
分支 HEAD：`c8669876f0787a151f29e60a920410e73ba4b59f`（`feature/w05-orchestration`）。

## 任务范围

| 任务 | 提交 | 说明 |
|---|---|---|
| T05.1 | `6e8d647` | SessionPersistence 能力与 Lease |
| T05.2 | `0798cfc` | 三日程采样器 |
| T05.3 | `e18cbae` | 重试与安全 watermark 编排 |
| T05.4 | `162675a` | MonitorController 快照与历史路由 |
| T05.5 | `c866987` | 12 成员软件端到端闭环 |

## W05 四套测试

```sh
swift test --package-path Packages/TemperatureCore --filter SamplingServiceTests
swift test --package-path Packages/TemperatureCore --filter MonitorIntegrationTests
swift test --package-path Packages/TemperatureCore --filter BackpressureTests
swift test --package-path Packages/TemperatureCore --filter WatermarkTests
```

| Suite | 结果 |
|---|---|
| SamplingServiceTests | 7/7 通过 |
| MonitorIntegrationTests | 8/8 通过 |
| BackpressureTests | 10/10 通过 |
| WatermarkTests | 4/4 通过 |

全量 `swift test`：185/185 通过。

## 覆盖与门禁

```sh
swift test --package-path Packages/TemperatureCore --enable-code-coverage
python3 scripts/check-core-coverage.py
python3 scripts/validate-handoff.py
```

| 检查 | 结果 |
|---|---|
| Core 行覆盖 | 5147/5941 = **86.64%**（≥80%） |
| validate-handoff | passed |

## T05.5 闭环证据

`MonitorIntegrationTests.fullCPUSoftwareDataLoopPersistsRawMaxEMAAndHistory` 使用 bundled profile 12 个 CPU 键：

- Qualified 目录 → 单次 CPU 读（12 source）→ 12 Raw + cpu.zone.max 派生 → EMA → SessionPersistence/SQLite
- 验证：`sources=12`、`series=13`、`raw_samples=13`、`ema_samples=13`、`sample_members=12`
- 快照 generation ≥ 1，cpu max EMA = 95°C（热点成员）
- 5min 历史走内存 realtime 路径，`persistedThrough == nil`

`fullCPUSoftwareDataLoopReceiptMatchesPersistedRecords` 验证两次读后 `raw/ema` 行数与 `committed_batches` 一致（26/26/2），receipt 与 DB 无重复批次。

## 限制

- 本报告为 MockSensor/脚本驱动软件集成，不替代 W09 实机验收。
- 控制器路径下自动 watermark 聚合桶写入仍由 `WatermarkTests`/`AggregationTests` 单独覆盖；端到端测试当前断言 Raw/EMA/SQLite 与 realtime 历史。
- W05 PR 合入前仍需独立审查与 CI `core-tests` 通过。

## W05 退出条件（软件范围）

- [x] MockSensor → 真实加工 → 真实 SQLite → 历史查询闭环
- [x] 背压/Lease/Watermark 单元与集成测试通过
- [x] Core 覆盖 ≥ 80%
- [ ] 独立审查（待 W05 PR）
- [ ] 合入 main（待维护者）
