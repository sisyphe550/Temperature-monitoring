# W01 报告

记录时间：2026-09-21。
分支 HEAD：`3f1c9c16e43467ce5ee9118bdd98a8bbc5874841`（基于 main `d8d100f` 的 `feature/w01-core-contracts`）。

## T01.1–T01.4

| 任务 | commit | 结果 |
|---|---|---|
| T01.1 SwiftPM 骨架 | `d0f3b63` | Package + 红灯 ContractTests |
| T01.2 类型与配置 | `f45d453` | 修订 2 契约四文件、Configuration、资源与 ConfigurationTests |
| T01.3 时钟 | `1343681` | Clock / TestClock / ClockTests（5 项） |
| T01.4 核心 CI 与覆盖 | `3f1c9c1` | core-tests workflow、覆盖门禁、ContractCoverageTests |

## 本地验证

```text
swift test --package-path Packages/TemperatureCore --enable-code-coverage
→ 35 tests passed

python3 scripts/check-core-coverage.py
→ 413/458 = 90.17% (≥ 80%)

python3 scripts/test-core-coverage-gate.py → passed
python3 scripts/validate-handoff.py → passed
```

覆盖分母：`Sources/TemperatureCore` 与 `Sources/SensorRuntime` 生产 Swift；排除测试、App UI、C 薄桥、worker 入口。

## CI

- 新增 workflow：`.github/workflows/core.yml`，检查名 `core-tests`。
- `scripts/validate-handoff.py` 已登记 `core-tests` 为预期检查名。
- **尚未**将 `core-tests` 加入 ruleset required contexts；待本 PR 首次 CI 成功后再执行 `configure-repository.sh` 扩展（同 W00 对 blocking-issues 的做法）。

## 未完成（不阻塞 W01 退出）

- 独立审查仍应由非实现者补记录。
- SensorRuntime / SQLite / App / 实机不在 W01 范围。
- 工具链：本机仅 Command Line Tools（Swift 6.1.2）；完整 Xcode 自 W07 起需要。

## W01 退出

修订 2 公共类型、配置加载、会话时钟与 ≥80% 核心覆盖基线已就绪；W02/W03/W04 可从合入后的 main 并行开始。
