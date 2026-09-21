# Contract revision 2 文档迁移记录

日期：2026-09-21

分支：`feature/v0-sensor-validation`

承载PR：Draft PR #4

性质：文档、机器契约与交接门禁迁移；不是生产App或新增硬件实测。

## 依据与提交链

- 已批准设计规格：`3b2c6a6 docs: specify contract hardening and reuse boundaries`
- 执行计划：`6147ceb docs: plan contract documentation migration`
- 机器契约：`fd6f754 docs: harden implementation contracts`
- 专项设计：`778b88f docs: align subsystem designs with hardened contracts`
- 需求与追踪：`693ab5f docs: trace hardened contracts to requirements`
- 工作包与任务：`e002ad4 docs: update executable tasks for contract revision`
- 入口、Git规则和本验证记录：本文件所在提交，可用`git log -1 --format='%H %s' -- docs/research/2026-09-21-contract-documentation-migration.md`取得不可变SHA。

本迁移在现有Draft PR分支完成，没有push、修改PR状态或合并。

## 迁移范围

1. `docs/contracts/defaults-v1.json`升级为`contract_version: 2`；新增`third-party-v1.json`，固定实际copied/modified代码的上游commit、路径、许可证hash、notice和修改说明。
2. `api-v1.swift`以封闭类型固定`DiscoveredCatalog`→`QualifiedSourceCatalog`、`ReadingOutcome`、强类型ID、一次性`PersistenceLease`/`ProcessingReceipt`以及`PresentationState`边界。
3. 02～10、13、15、16、18～21统一采集、持久化、故障、UI、平台字段和上游复用语义；测试策略增加`TC-UPSTREAM-BOUNDARY`，测试组总数为20。
4. 01、`acceptance-v1.json`与17同步11项受影响需求的正文hash、设计映射和测试映射；REQ-012/114仍退役，没有恢复逐物理核心、`core_id`或物理Package要求。
5. 22、23保持12个工作包和50项任务的DAG，改写任务输入、接口产出和验收，使实现直接消费修订2契约。
6. README、CONTEXT、AGENTS、00、11和12统一接手顺序、术语、原子同步规则与开发阶段；`validate-handoff.py`增加修订2、第三方来源、入口token和旧API禁用检查。

`docs/contracts/schema-v1.sql`未改，SHA-256为`f435d7f0ba5ce01392ec14d3d3581e9b10d9e6fccbf44ef9659f3f5487fe056e`：本次没有存储结构变化。`docs/contracts/tasks-v1.json`未改，SHA-256为`d1d986a22da7b061a481a8ffb50ff8d1f397db833f722d573fd1ffc2cad6e4df`：任务数量、ID和依赖DAG没有变化。既有`docs/research/`和`docs/validation/`文件未改写；本文件是新增迁移证据。

## 2026-09-21 校验结果

在上述分支、Task 5提交前的工作树执行：

| 命令 | 结果 |
|---|---|
| `python3 scripts/validate-handoff.py` | exit 0；134项需求、132现行、2退役；12个工作包、50项任务；20个测试组；contract revision 2；7份机器契约均被识别 |
| `swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-doc-migration-final -typecheck docs/contracts/api-v1.swift` | exit 0 |
| `sqlite3 ':memory:' < docs/contracts/schema-v1.sql` | exit 0；DDL断言输出`memory`、`0`、`1000`、`262144` |
| `swift test --package-path prototypes/sensor-probe --scratch-path /tmp/temperature-monitor-probe-final` | exit 0；构建成功，8项测试通过 |
| `python3 scripts/check-probe-coverage.py` | exit 0；ProbeCore 55/55行，100.00%；硬件桥和CLI不在该覆盖分母内 |
| `python3 scripts/test-probe-cli.py` | exit 0；help、非法interval/duration/options、缺值和已有输出保护通过 |
| `git diff --check` | exit 0 |

SwiftPM测试因受限执行环境的嵌套沙箱限制在已授权的沙箱外执行；测试内容仍是仓库现有本地包，没有联网或更改产品状态。

## 证据边界

上述结果只证明文档、机器契约、原型和交接门禁在该提交链上自洽。生产`Packages/TemperatureCore`、App、Xcode工程尚未创建，因此不能把本记录标作正式App构建、目标Mac实机资格、UI黑盒、五档采样、sleep/wake、72小时运行、签名、公证或发布验收通过。后续Agent必须按22/23生成新的实现与实机证据，不能回写本记录扩大结论。
