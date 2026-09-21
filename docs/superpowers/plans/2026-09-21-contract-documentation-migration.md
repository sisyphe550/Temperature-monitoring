# Contract Documentation Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已批准的契约收紧设计迁移到全部现行权威文档、机器契约、追踪矩阵、任务计划和Agent入口，使后续开发只依赖仓库文件即可实施。

**Architecture:** 保留现有产品范围和50项任务DAG，升级文档契约修订号并用更严格的Swift接口契约表达互斥状态、来源资格化、持久化能力视图和统一展示状态。Python交接校验器先增加失败门禁，再逐层迁移机器契约、专项设计、需求追踪、执行任务与入口文件；历史research/validation证据保持只读。

**Tech Stack:** Markdown、JSON、Swift 6类型契约、SQLite DDL、Python 3交接校验器、Git。

**Spec:** `docs/superpowers/specs/2026-09-21-contract-hardening-and-upstream-reuse-design.md`

**Execution method:** Native execution in the current task, as explicitly requested by the user; no subagent delegation.

## Global Constraints

- CPU主指标仍为Mac16,13首profile固定12个CPU热区成员，每批Raw max后EMA；逐物理核心、物理Package和`core_id`保持退役。
- Swift＋小型C桥接＋普通用户SensorWorker＋SwiftUI/AppKit＋SQLite路线不变。
- Raw/EMA实时内存路径、Raw/EMA入库、分层历史、当前会话TTL、缺口、幂等和有界队列语义不变。
- SSD和Battery仍为必须实现的可选能力；不可用时显式展示，不能用未知来源静默替代。
- 禁止SMC写入、风扇控制、root helper、外部监控CLI、告警、自启动、联网更新和跨会话历史。
- research/validation历史证据不改写；新增验证记录使用新文件并注明源码SHA和证据边界。
- 实质复制或修改第三方代码必须登记固定commit、路径、许可hash、本地路径和修改说明；MacFanControl及Philip Turner当前仅允许`method-only`。
- SDK、deployment target、runtime profile和qualified combinations分开记录；最低运行要求15.7.3暂不改变。
- 当前工作继续位于`feature/v0-sensor-validation`和Draft PR #4，不reset、不覆盖用户改动、不创建产品功能分支。

## Review Focus

- 同一Reading同时携带成功值和失败，或两者皆无：Swift类型必须无法构造，并由契约token检查固定。
- 同一PersistenceLease重复消费、错误owner或错误generation：文档接口和测试任务必须要求固定完整性失败，不能重试掩盖。
- 原始worker发现结果绕过Registry进入加工或UI：接口只能让SamplingService取得QualifiedSourceCatalog。
- UI同时出现live与fatal，或loading与failed：PresentationState和HistoryChartState必须使用互斥枚举。
- copied/modified第三方文件缺登记、许可证或ThirdPartyNotices：交接校验和后续CI任务必须失败。

---

### Task 1: 机器契约与交接校验器

**Files:**
- Modify: `scripts/validate-handoff.py`
- Modify: `docs/contracts/defaults-v1.json`
- Modify: `docs/contracts/api-v1.swift`
- Create: `docs/contracts/third-party-v1.json`
- Modify: `docs/21-implementation-contracts.md`

**Interfaces:**
- Consumes: 已批准规格第4至9节；现行`schema-v1.sql`、`first-profile-v1.json`和全部默认参数。
- Produces: `contract_version=2`；可由Swift 6类型检查的强类型API；机器可校验的第三方来源契约；后续文档使用的唯一名称。

- [ ] **Step 1: 先增加必然失败的新契约门禁**

在`validate_contract_values()`中把契约修订号改为2，并新增`validate_third_party_contract()`及API token检查：

```python
if defaults.get("contract_version") != 2:
    fail("defaults-v1.json: contract_version must be 2")

third_party = load_json(CONTRACTS / "third-party-v1.json")
if third_party.get("version") != 1:
    fail("third-party-v1.json: version must be 1")

api = (CONTRACTS / "api-v1.swift").read_text(encoding="utf-8")
for token in ("ReadingOutcome", "QualifiedSourceCatalog", "PersistenceLease",
              "PersistenceOwner", "ProcessingReceipt", "PresentationState"):
    if token not in api:
        fail(f"api-v1.swift: missing {token}")
for forbidden in ("public struct QueueReservation", "valueC: Double?",
                  "failure: MonitorFailure?"):
    if forbidden in api:
        fail(f"api-v1.swift: obsolete API remains: {forbidden}")
```

同时要求`third-party-v1.json`登记现有原型中从macmon修改而来的`prototypes/sensor-probe/Sources/SensorBridge/SensorBridge.c`，并把R04、R07标为method-only。

- [ ] **Step 2: 运行校验并确认失败原因只来自缺失的新契约**

Run:

```sh
python3 scripts/validate-handoff.py
```

Expected: FAIL，至少报告`contract_version must be 2`、缺少`third-party-v1.json`及缺少新API token；不得出现现有134项需求、SQL或任务图损坏。

- [ ] **Step 3: 更新defaults和第三方来源契约**

保持所有数值参数不变，只把`contract_version`设为2。创建：

```json
{
  "version": 1,
  "imports": [{
    "upstream_project": "macmon",
    "upstream_commit": "6919d7781b6c55a6e3bedff83a210435837e1dfe",
    "upstream_path": "src_lib/sources.rs",
    "local_paths": ["prototypes/sensor-probe/Sources/SensorBridge/SensorBridge.c"],
    "reuse_mode": "modified",
    "license": "MIT",
    "license_sha256": "65f575b0127a4383e4710c5ffefe2c5a9ab906231013f42ba899f3fa9b9fdaaf",
    "notice_path": "prototypes/sensor-probe/THIRD_PARTY_NOTICES.md",
    "modification_summary": "Read-only exploratory SMC/HID ABI bridge; fan control and writes omitted."
  }],
  "method_only": [
    {"source_id":"R04","reason":"Pinned tree lacks a complete license file."},
    {"source_id":"R07","reason":"Inspected single-file revision has no explicit license."}
  ]
}
```

校验器验证local/notice路径存在、reuse_mode为固定枚举、commit为40位小写十六进制、SHA为64位小写十六进制，并拒绝R04/R07进入imports。

- [ ] **Step 4: 用强类型契约替换旧公开API**

在`api-v1.swift`中实现并类型检查：

```swift
public enum ReadingOutcome: Codable, Sendable, Equatable {
    case success(valueC: Double, sourceWallUnixNS: Int64?, freshness: Freshness)
    case failure(MonitorFailure)
}
public enum PersistenceOwner: Codable, Sendable, Equatable {
    case request(RequestID)
    case gap(GapID)
    case watermark(WatermarkEventID)
}
public enum PresentationState: Sendable, Equatable {
    case running(RunningPresentationState)
    case fatal(FatalPresentationState)
}
```

同时完成UUID格式的SessionID/SourceID/SeriesID/RequestID/BatchID/GapID/WatermarkEventID；SeriesFormula和SegmentReason枚举；DiscoveredCatalog→Registry→QualifiedSourceCatalog两层接口；不透明PersistenceLease；ProcessingReceipt；SessionPersistence的reserve/commit/cancel及会话方法；互斥HistoryChartState。删除旧QueueReservation、可空`Reading.valueC/failure`、字符串formula/reason以及返回完整PersistenceBatch的ProcessingEngine签名。

- [ ] **Step 5: 更新21中的唯一契约说明**

机器清单增加`third-party-v1.json`；说明文件名中的v1表示产品契约族，`contract_version=2`表示兼容性破坏修订，实现只能使用修订2。加入能力视图所有权表和旧→新名称迁移表，明确schema-v1.sql没有存储结构变化。

- [ ] **Step 6: 验证并提交机器契约**

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-doc-migration -typecheck docs/contracts/api-v1.swift
sqlite3 ':memory:' < docs/contracts/schema-v1.sql
git diff --check
```

Expected: 四条命令exit 0；validator报告contract_version 2和third-party-v1.json；Swift不存在旧API token。

```sh
git add scripts/validate-handoff.py docs/contracts/defaults-v1.json docs/contracts/api-v1.swift docs/contracts/third-party-v1.json docs/21-implementation-contracts.md
git commit -m "docs: harden implementation contracts"
```

### Task 2: 专项设计文档迁移

**Files:**
- Modify: `docs/02-architecture.md`
- Modify: `docs/03-sensor-acquisition.md`
- Modify: `docs/04-data-storage.md`
- Modify: `docs/05-processing-pipeline.md`
- Modify: `docs/06-error-handling.md`
- Modify: `docs/07-native-ui.md`
- Modify: `docs/08-component-design.md`
- Modify: `docs/09-technology-selection.md`
- Modify: `docs/10-test-strategy.md`
- Modify: `docs/13-operations-distribution.md`
- Modify: `docs/15-decisions-and-corrections.md`
- Modify: `docs/16-open-questions.md`
- Modify: `docs/18-sources.md`
- Modify: `docs/19-reference-informed-design.md`
- Modify: `docs/20-feasibility-and-reuse.md`
- Modify: `scripts/validate-handoff.py`

**Interfaces:**
- Consumes: Task 1的精确类型名和已批准规格。
- Produces: 所有专项文档使用同一数据流、错误语义、平台字段和复用边界。

- [ ] **Step 1: 更新架构、传感器和存储数据流**

02明确唯一链路：SensorTransport原始帧→Registry资格化→QualifiedSensorClient→SamplingService→PersistenceLease→MonitorEngine→SessionPersistence→Snapshot/History→PresentationState。03写清DiscoveredSource仅含底层事实，QualifiedSource才允许进入算法；04用SessionPersistence能力视图替代App直接组合queue/writer/store。

- [ ] **Step 2: 更新加工和故障契约**

05用ReadingOutcome及ProcessingReceipt重写成功/失败和状态交换时序；06把未知协议枚举、无效UUID、Lease伪造/重复消费映射到现有固定错误码，不增加新的恢复行为。

- [ ] **Step 3: 更新UI和组件文件图**

07定义PresentationState、Running/Fatal、TemperatureValueState及HistoryChartState互斥规则；08把WorkerClient改为SensorTransport，把QualifiedSensorClient、QualifiedSourceCatalog、SessionPersistence能力视图和Presentation状态文件加入模块图。保留现有布局、尺寸、交互和上游UI来源。

- [ ] **Step 4: 拆分平台字段与发布证据**

09和13分别列出`build_toolchain`、`deployment_target`、`runtime_profile`、`qualified_combinations`；15记录DEC-16“收紧契约而不照搬完整上游App”；16明确剩余项只是Xcode、实机、管理员权限和签名凭证等执行依赖。

- [ ] **Step 5: 更新复用来源与边界**

18加入`third-party-v1.json`入口；19/20明确研究manifest和实际导入contract职责不同，列出允许复制/修改与method-only边界，保留Stats旧值回退、SwiftTempBar名称分类、root/helper、风扇写入等禁止项。

- [ ] **Step 6: 增加TC-UPSTREAM-BOUNDARY**

10的主表加入第20组：旧值不生成新样本、名称不产生物理语义、缺事件不生成0°C、12来源不映射10核心、同名registryID不合并、Release无写SMC/root/helper/fixture、第三方登记缺失失败。validator检查测试组总数20。

- [ ] **Step 7: 验证并提交专项设计**

```sh
python3 scripts/validate-handoff.py
rg -n "QueueReservation|valueC: Double\?|failure: MonitorFailure\?" docs/02-architecture.md docs/03-sensor-acquisition.md docs/04-data-storage.md docs/05-processing-pipeline.md docs/06-error-handling.md docs/07-native-ui.md docs/08-component-design.md docs/09-technology-selection.md docs/10-test-strategy.md docs/13-operations-distribution.md docs/15-decisions-and-corrections.md docs/16-open-questions.md docs/18-sources.md docs/19-reference-informed-design.md docs/20-feasibility-and-reuse.md
git diff --check
```

Expected: validator exit 0；rg无输出；diff check exit 0。

```sh
git add docs/02-architecture.md docs/03-sensor-acquisition.md docs/04-data-storage.md docs/05-processing-pipeline.md docs/06-error-handling.md docs/07-native-ui.md docs/08-component-design.md docs/09-technology-selection.md docs/10-test-strategy.md docs/13-operations-distribution.md docs/15-decisions-and-corrections.md docs/16-open-questions.md docs/18-sources.md docs/19-reference-informed-design.md docs/20-feasibility-and-reuse.md
git commit -m "docs: align subsystem designs with hardened contracts"
```

### Task 3: 需求、验收和追踪同步

**Files:**
- Modify: `docs/01-requirements.md`
- Modify: `docs/contracts/acceptance-v1.json`
- Modify: `docs/17-traceability.md`
- Modify: `scripts/validate-handoff.py`

**Interfaces:**
- Consumes: Task 1机器契约、Task 2专项设计、现有134个REQ编号。
- Produces: 132项现行需求的正文hash、设计、工作包和20组测试映射完全一致；REQ-012/114继续退役。

- [ ] **Step 1: 在现有需求中承载新契约，不新增产品功能编号**

修改并保持原业务目标：REQ-009（发现与合格来源分离）、REQ-013/014（ReadingOutcome和封闭校验）、REQ-070（cached不生成样本）、REQ-079（强类型事件身份）、REQ-083（固定错误码枚举）、REQ-098（第三方来源审计）、REQ-105（权威文档范围）、REQ-110（四类平台字段）、REQ-132（资格化证据）、REQ-134（新鲜度互斥展示）。REQ-012/114不改。

- [ ] **Step 2: 更新acceptance映射和hash**

对上述正文重新计算SHA-256；为这11项加入`TC-UPSTREAM-BOUNDARY`并保留原测试组。设计映射指向实际定义规则的03/05/06/07/09/19/21。

- [ ] **Step 3: 从acceptance同步追踪矩阵**

保持REQ-001..134顺序和六列格式，只修改与JSON映射变化有关的行。产品结果继续为“未完成产品验收”。

- [ ] **Step 4: 收紧validator一致性检查**

测试组期望从19改成20；上述11项必须包含`TC-UPSTREAM-BOUNDARY`；012/114不得获得该测试；acceptance、17和01的hash/顺序必须一致。

- [ ] **Step 5: 验证并提交需求追踪**

```sh
python3 scripts/validate-handoff.py
python3 -m json.tool docs/contracts/acceptance-v1.json >/dev/null
git diff --check
```

Expected: validator报告134 total、132 active、2 retired、20 test groups。

```sh
git add docs/01-requirements.md docs/contracts/acceptance-v1.json docs/17-traceability.md scripts/validate-handoff.py
git commit -m "docs: trace hardened contracts to requirements"
```

### Task 4: 工作包与50项执行任务更新

**Files:**
- Modify: `docs/22-agent-implementation-plan.md`
- Modify: `docs/23-execution-task-breakdown.md`
- Review, modify only if dependency changes: `docs/contracts/tasks-v1.json`

**Interfaces:**
- Consumes: Task 1至3的类型、设计和验收映射。
- Produces: 后续Agent可直接执行的W01/W02/W03/W04/W05/W07/W08/W09/W11边界；任务数及DAG保持50项。

- [ ] **Step 1: 更新W01公共契约任务**

T01.1/1.2使用UUID强类型、ReadingOutcome、SeriesFormula、SegmentReason、MonitorErrorCode、Presentation状态和contract_version 2；测试非法UUID、未知枚举、成功/失败互斥及旧token不存在。

- [ ] **Step 2: 更新W02来源边界任务**

T02.1/2.2产出SensorTransport原始帧；T02.5产出QualifiedSensorClient和QualifiedSourceCatalog。测试raw发现不能直接进入ReadRequest，旧generation和同名不同registryID不合并。

- [ ] **Step 3: 更新W03/W04/W05持久化与加工任务**

T03定义SessionPersistence内部store/writer；T04消费ReadingOutcome；T05.1实现PersistenceLease和三个能力视图，T05.3验证commit ack后状态交换并返回ProcessingReceipt。移除公开QueueReservation和返回PersistenceBatch供审计的描述。

- [ ] **Step 4: 更新W07/W08展示与许可任务**

T07.1先实现互斥PresentationState，T07.2～7.5只消费它；T08.1复制contract revision 2资源并生成ThirdPartyNotices，T08.3执行TC-UPSTREAM-BOUNDARY及Release禁用符号检查。

- [ ] **Step 5: 更新W09/W11资格与最终验收任务**

W09分别记录toolchain/deployment/runtime/qualified组合；T11.1检查20组测试和third-party contract。50个任务ID、计数、根T00.1、终点T11.3及依赖不变，因此`tasks-v1.json`只在依赖确实变化时修改。

- [ ] **Step 6: 验证并提交任务契约**

```sh
python3 scripts/validate-handoff.py
rg -n "QueueReservation|return.*PersistenceBatch|返回.*PersistenceBatch" docs/22-agent-implementation-plan.md docs/23-execution-task-breakdown.md
python3 -m json.tool docs/contracts/tasks-v1.json >/dev/null
git diff --check
```

Expected: validator报告50 execution tasks；rg无输出。

```sh
git add docs/22-agent-implementation-plan.md docs/23-execution-task-breakdown.md docs/contracts/tasks-v1.json
git commit -m "docs: update executable tasks for contract revision"
```

### Task 5: 入口、上下文与最终交接证据

**Files:**
- Modify: `README.md`
- Modify: `CONTEXT.md`
- Modify: `AGENTS.md`
- Modify: `docs/00-agent-handoff.md`
- Modify: `docs/11-git-github-workflow.md`
- Modify: `docs/12-development-plan.md`
- Create: `docs/research/2026-09-21-contract-documentation-migration.md`
- Modify: `scripts/validate-handoff.py`

**Interfaces:**
- Consumes: 全部迁移后的权威文档和当前Git状态。
- Produces: 后续Agent的唯一阅读顺序、术语、执行边界和可复核验证记录。

- [ ] **Step 1: 更新入口与术语**

README、CONTEXT、AGENTS和00统一写入contract revision 2、Discovered/Qualified区别、ReadingOutcome、PersistenceLease、PresentationState、third-party contract和TC-UPSTREAM-BOUNDARY。启动命令的Swift typecheck使用可写`/tmp` module cache。

- [ ] **Step 2: 更新阶段和Git说明**

11保持当前PR #4与W00流程，只补充文档契约变更必须同提交同步API、acceptance、任务和validator；12把修订2契约冻结列为W01前置输入，不新增里程碑。

- [ ] **Step 3: 增加迁移验证记录**

新记录写明设计规格commit `3b2c6a6`、迁移提交列表、变更文件范围、未改历史证据、执行命令及输出摘要。明确文档契约通过不等于生产App或目标硬件通过。

- [ ] **Step 4: 扩展入口一致性校验**

validator检查README/CONTEXT/AGENTS/00/21均包含contract revision 2和新关键类型；全部现行设计及计划中禁止旧QueueReservation和可空Reading字段；research/validation历史目录从禁止token扫描中排除。

- [ ] **Step 5: 运行最终全量验证**

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-doc-migration-final -typecheck docs/contracts/api-v1.swift
sqlite3 ':memory:' < docs/contracts/schema-v1.sql
swift test --package-path prototypes/sensor-probe
python3 scripts/check-probe-coverage.py
python3 scripts/test-probe-cli.py
git diff --check
git status --short
```

Expected: 全部exit 0；validator报告134/132/2、50 tasks、20 test groups、contract revision 2和third-party-v1.json；原型测试维持8项通过；工作树只含计划内文件。

- [ ] **Step 6: 提交交接入口与验证记录**

```sh
git add README.md CONTEXT.md AGENTS.md docs/00-agent-handoff.md docs/11-git-github-workflow.md docs/12-development-plan.md docs/research/2026-09-21-contract-documentation-migration.md scripts/validate-handoff.py
git commit -m "docs: publish contract revision two handoff"
```

- [ ] **Step 7: 提交后复核**

```sh
git status --short
git log -8 --oneline --decorate
python3 scripts/validate-handoff.py
```

Expected: 工作树为空；提交顺序与Task 1至5一致；validator仍通过。不得push、修改PR状态或合并，除非用户另行授权。
