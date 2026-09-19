# TemperatureMonitor Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按现行132项需求实现可在首个目标MacBook Air运行的完整原生温度监测App，并形成测试、实机资格与独立分发证据。

**Architecture:** Swift模块化单体；普通用户SensorWorker串行读取硬件，主进程按真实时间加工。实时显示读有界EMA内存，Raw/EMA/聚合/趋势批量写SQLite，历史读SQLite；会话结束删除监控数据库。

**Tech Stack:** Swift 6、SwiftPM tools-version 6.0、少量C/IOKit、系统SQLite3、SwiftUI/AppKit/Swift Charts、Swift Testing、XCTest/XCUITest、Xcode16.4开发基线。

**Spec:** 从[交接入口](00-agent-handoff.md)开始，顺序阅读[01](01-requirements.md)、[02](02-architecture.md)至[13](13-operations-distribution.md)、[20](20-feasibility-and-reuse.md)、[21](21-implementation-contracts.md)。本页定义W级设计与里程碑边界，[23](23-execution-task-breakdown.md)定义50个可审查执行任务。参数、类型、DDL、profile分别以[defaults](contracts/defaults-v1.json)、[API](contracts/api-v1.swift)、[schema](contracts/schema-v1.sql)、[profile](contracts/first-profile-v1.json)为准。

## Global Constraints

- 本计划是后续实施步骤；**生产代码、App项目和本页标为“新建”的脚本尚未存在**。命令块是对应文件完成后的执行命令，不是已执行记录。
- 当前文档基线在`feature/v0-sensor-validation`及PR #4；先按W00评审并合入文档，后续功能分支才能从包含该基线的最新`main`创建。不得只拉当前旧main然后重新发明设计。
- 新功能使用`feature/**`分支；测试、独立审查、阻塞Issue检查通过后由维护者手动merge commit；保留远程分支。GitHub最低审批人数为0，独立审查证据仍是合并条件。
- 部署目标arm64、macOS15.7.3；首版profile是`Mac16,13`。已有硬件证据来自15.7.3/build24G419；正式App通过W09之前不能标为产品兼容已验证。
- CPU固定12键Raw max→EMA，显示“CPU热区最高温度”。不是物理Package、逐物理核心温度或全芯片绝对最高温；REQ-012/114退役，不实现、不验收、不复用编号。
- CPU五档50/100/200/500/1000ms、默认200ms；SSD500ms、Battery1000ms。周期是请求日程，不等于硬件测量更新时间。
- CPU必需；SSD/Battery必须实现能力检测、适配与不可用状态，单项缺失不终止CPU。不能因“可选”而省略适配代码和测试。
- 每条有效Raw和EMA均进入持久化链；最近五分钟图表读内存EMA。C11已取消数据库强制往返要求，不能恢复旧REQ-047的读表限制。
- Raw/EMA保留300s，1s层3600s、10s层86400s、1min层259200s、趋势3600s；每60s清理、物理宽限120s。年龄使用包含睡眠的elapsed时间。
- 参数JSON中的tau、趋势、队列、期限、容量是冻结的v1设计值，尚未宣称性能实测达标。实现者不得静默减成员、降档、删历史或丢样本来获得“通过”。
- 不引入服务器、Web前端、Docker、第三方采集CLI、root服务、高温告警、登录自启动、自动更新、SMC写入或风扇控制。
- 完整Xcode、真实目标机、仓库管理员权限、正式签名凭证是执行环境依赖。缺少其中一项时完成其余可独立任务，将对应交付标为未执行或等待外部条件，不能写假通过。

## 任务顺序、文件与证据约定

依赖顺序：`W00 → W01 → {W02,W03,W04} → W05 → W06 → W07 → W08 → W09 → W10 → W11`。W02/W03/W04接口独立，可在明确文件所有权后分别实施；不要求并发。

现有资产：`prototypes/sensor-probe/`、`.github/workflows/probe.yml`、`scripts/check-probe-coverage.py`、设计文档和历史验证记录。原型继续保留，不能将其测试覆盖率当产品覆盖率。

生产目录遵循[08](08-component-design.md)：

| 任务 | 新建或逐步完成的生产文件 |
|---|---|
| W01 | `Packages/TemperatureCore/Package.swift`；`Sources/TemperatureCore/{Models,Configuration,Clock}.swift`；`Sources/TemperatureCore/Diagnostics/MonitorFailure.swift` |
| W02 | `THIRD_PARTY_NOTICES.md`；`Sources/TemperatureCore/Registry.swift`；`Sources/SensorRuntime/{WorkerClient,WorkerProtocol}.swift`；`Sources/SensorBridge/{SensorBridge.c,include/SensorBridge.h}`；`Sources/SensorWorker/main.swift` |
| W03 | `Sources/CSQLite/{module.modulemap,shim.h}`；`Sources/TemperatureCore/Storage/{SQLiteStore,HistoryQuery,Retention}.swift`；`Sources/TemperatureCore/Resources/schema-v1.sql` |
| W04 | `Sources/TemperatureCore/MetricResolver.swift`；`Sources/TemperatureCore/Processing/{EMA,Aggregation,Trend,RingBuffer}.swift`；加工部分`Sources/TemperatureCore/MonitorEngine.swift` |
| W05 | `Sources/TemperatureCore/{MonitorEngine,PersistenceQueue}.swift`；`Sources/TemperatureCore/Storage/StorageWriter.swift`；`Sources/SensorRuntime/SamplingService.swift` |
| W06 | `Sources/TemperatureCore/SessionLock.swift`；`Sources/TemperatureCore/Storage/SessionCleanup.swift`；`Sources/TemperatureCore/Diagnostics/{RetryPolicy,DiagnosticLogger,ReportWriter}.swift`；`App/SessionCoordinator.swift` |
| W07 | `App/Presentation/{PresentationModel,StatusItemController,TemperaturePopover,TemperatureDashboard,TemperatureSourceRow,HistoryChartView,SettingsView,FatalView}.swift`；为UI可独立测试先建立`TemperatureMonitor.xcodeproj`、App入口与scheme |
| W08 | 完成W07创建的`TemperatureMonitor.xcodeproj`与`App/{TemperatureMonitorApp,AppDelegate}.swift`生产装配；`App/Resources/{defaults-v1.json,first-profile-v1.json,Info.plist,ThirdPartyNotices.md}` |

上表`Sources/`相对`Packages/TemperatureCore/`。测试放该包的`Tests/TemperatureCoreTests/`和`Tests/SensorRuntimeTests/`；App测试放`UITests/TemperatureMonitorUITests.swift`。资源复制必须逐字匹配规范文件，不能形成第二套默认值。

Swift Testing文件使用同名`@Suite struct`，例如`@Suite struct EMAProcessorTests { ... }`；本页`@Test`片段放入对应suite。每条`swift test --filter <Suite>`必须确认实际执行测试数大于0，不能把无匹配测试的退出码当通过。下文新任务按“写失败用例→运行观察失败→实现→运行观察通过→提交及审查”逐步执行。

每个任务保存：对应提交SHA、配置、测试命令/预期/实际、失败Issue及回归证据。软件证据放`docs/validation/product-software/`，实机放`docs/validation/product-hardware/<model>-<osbuild>/<commit>/`，发布放`docs/validation/releases/<version>/`。这些目录由实施阶段创建；不覆盖2026-09-15原始证据。

### 共用测试支撑：先定义，再调用

W01创建`Tests/TemperatureCoreTests/TestSupport/Fixtures.swift`，W02/W03/W04分别补充自己的fixture；这些是测试入口，不是另一套产品协议。所有测试使用真实生产实现及协议注入，不在fixture内重写被测算法。

```swift
import Foundation
import Testing
@testable import TemperatureCore

enum Fixtures {
    static func timestamp(ms: Int64) -> Timestamp {
        Timestamp(elapsedNS: ms * 1_000_000,
                  wallUnixNS: 1_700_000_000_000_000_000 + ms * 1_000_000)
    }
    static func source(id: String = "source-0", key: String = "Tp01") -> SourceDescriptor {
        SourceDescriptor(sourceID: id, provider: .smc, rawKey: key,
            registryID: nil, connectionGeneration: 1, kind: .cpuZone,
            encoding: "flt ", unitEvidence: "test-fixture-celsius",
            evidence: .referenceClassified, mappingVersion: "fixture-v1",
            capability: .available)
    }
    static func definition() -> SeriesDefinition {
        SeriesDefinition(seriesID: "series-0", metricID: "fixture.cpu",
            definitionVersion: 1, kind: .cpuZone, displayName: "测试来源",
            memberSourceIDs: ["source-0"], formula: "identity")
    }
    static func read(id: String, ms: Int64, values: [Double]) -> ReadBatch {
        ReadBatch(requestID: id, generation: 1,
            readings: values.enumerated().map { index, value in
                Reading(sourceID: "source-\(index)", valueC: value,
                    started: timestamp(ms: ms), finished: timestamp(ms: ms),
                    sourceWallUnixNS: nil, freshness: .unknown, failure: nil)
            })
    }
    static func persistence(id: String, value: Double, ms: Int64) -> PersistenceBatch {
        let t = timestamp(ms: ms)
        return PersistenceBatch(batchID: id, sources: [source()], definitions: [definition()],
            segments: [Segment(seriesID: "series-0", number: 1,
                started: timestamp(ms: 0), reason: "start")],
            raw: [Sample(sampleID: "fixture-session:1", seriesID: "series-0",
                segment: 1, timestamp: t, periodMS: 200, valueC: value,
                freshness: .unknown, sourceWallUnixNS: nil, memberSampleIDs: [])],
            ema: [EMAValue(sampleID: "fixture-session:1", seriesID: "series-0",
                segment: 1, timestamp: t, valueC: value)],
            buckets: [], trends: [], gaps: [])
    }
}
```

测试支撑接口由所属任务创建并给出完整实现：

| 文件／接口 | 实现要求 |
|---|---|
| W01 `TestSupport/TestClock.swift`：`final class TestClock: MonitorClock, @unchecked Sendable`；`init(now: Timestamp)`、`now()`、`sleep(untilElapsedNS:)`、`advance(to:)` | 锁保护时间和等待continuation；advance只前进elapsed，唤醒到期等待；取消睡眠移除continuation。`@unchecked`必须伴随线程安全测试，不允许真实sleep。 |
| W02 `TestSupport/WorkerFixture.swift`：`WorkerFixture.make(scenario: String) async throws -> WorkerFixture`；属性`client: any SensorClient`、`childProcessIDs: [Int32]`；`close() async` | 构建测试专用子进程模拟协议；scenario为`success/timeout/oversize/badJSON/wrongID/oldGeneration/crash`。只在测试target可用，绝不能作为生产硬件fallback。 |
| W03 `TestSupport/TemporaryStoreFixture.swift`：`TemporaryStoreFixture.make() async throws -> TemporaryStoreFixture`；属性`store: any SampleStore`、`databaseURL: URL`；`rows(in: String) throws -> Int` | 每测试独立临时目录，建真实SQLiteStore，以完整SessionMetadata open固定测试session并register测试来源/定义。rows只允许测试内部固定表名白名单；结束调用closeAndDeleteSession。 |
| W04 `TestSupport/ProcessorFixture.swift`：`ProcessorFixture.make(cpuMembers: Int = 1) async throws -> ProcessorFixture`；属性`engine: any ProcessingEngine`；方法`reservation(ownerID:generation:) async throws` | 注入TestClock、测试registry和始终成功的有界PersistenceQueue；单源用identity，12源模式按规范CPU集合构造主指标。reservation返回生产Queue实现创建的一次性预留；只驱动真实Processing代码，不运行定时采集。 |
| W05 `TestSupport/ControllerFixture.swift`：`ControllerFixture.make() async throws -> ControllerFixture`；属性`controller: any MonitorController`、`clock: TestClock`、`requests: [ReadRequest]` | MockSensorClient使用受控响应，真实MonitorEngine/队列＋临时SQLite；记录调用日程。提供脚本事件`advance/respond/fail/blockWriter/unblockWriter/stop`的确定性驱动，事件数据见W05。 |

以上fixture提供构造与观察边界，不改变[api-v1.swift](contracts/api-v1.swift)的协议签名。各任务可增加内部测试观察方法，但须在fixture文件中明确定义，不暴露给生产UI。

## W00：先落地文档基线与Git门禁

**需求：** REQ-085～106、128；TC-WORKFLOW、TC-DOCS。**依赖：** 仓库管理员权限仅用于强制配置；无权限时准备PR和配置脚本，禁止宣称门禁启用。

**文件：** 使用并检查交接阶段提供的`scripts/validate-handoff.py`和`.github/workflows/handoff-docs.yml`；新建`.github/workflows/blocking-issues.yml`、`.github/scripts/{blocking-issues.mjs,blocking-issues.test.mjs}`、`scripts/configure-repository.sh`；保留`.github/workflows/probe.yml`；更新`docs/11-git-github-workflow.md`的真实配置证据。

**接口：** 消费需求/契约/验收映射；产出固定检查名`handoff-docs`、`probe-tests`、`blocking-issues`。W01产生可运行产品测试后再启用`core-tests`；W08产生真实App构建后再启用`app-build`，不创建永久成功的空检查。

- [ ] 读取PR #4状态、diff、head SHA和`main`实际保护配置；确认当前分支含全部交接文件。检查工作树，保留用户未提交改动。
- [ ] 运行以下现有文档及原型检查，保存日志；任何失败先修复并重测。预期：文档结构／契约通过、原型测试通过，不意味着App已完成。

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -typecheck docs/contracts/api-v1.swift
swift test --package-path prototypes/sensor-probe --enable-code-coverage
python3 scripts/check-probe-coverage.py
```

- [ ] PR #4先通过当时已有的`handoff-docs`、`probe-tests`和独立审查，由维护者merge commit合入。核对exact head、两个parent和远端分支保留；再从更新后的main创建`feature/w00-repository-gates`。该次引导合并不得被写成`blocking-issues`已启用。
- [ ] 在门禁分支实现`blocking-issues`：读取仓库全部分页的open issue，只要存在`blocking`标签就失败；排除API返回中的PR对象。PR opened/reopened/synchronize触发检查；Issue opened/reopened/closed/labeled/unlabeled时，重新检查所有打开PR的**最新head SHA**。API失败、分页不完整或权限不足均失败，不按“零Issue”放行。
- [ ] 使用受信任默认分支workflow及最小只读Issue/PR权限，状态写入仅用于对应SHA。特权workflow不checkout、import或执行PR代码。逻辑示例必须在测试中覆盖：

```javascript
const blockers = allPages.filter(issue =>
  !issue.pull_request && issue.state === "open" &&
  issue.labels.some(label =>
    (typeof label === "string" ? label : label.name) === "blocking"));
const state = blockers.length === 0 ? "success" : "failure";
// allPages必须来自分页完成的Issues API；异常路径单独提交failure。
// 每次写status前重新获取PR.head.sha，不使用旧事件中的head缓存。
```

- [ ] 用API fixture验证“无Issue成功、普通Issue成功、blocking失败、第二页blocking失败、关闭后成功、重新打开后失败、期间新push只写最新head、API错误失败”；不为验证而随意操作用户真实Issue。
- [ ] 门禁分支用已有检查审查和合入，使特权workflow先成为默认分支的可信代码。随后创建规则证据PR，从默认分支触发`blocking-issues`并确认它写到该PR最新head；只有成功运行后才将检查设为required。
- [ ] 配置main禁止直接推功能、必需已存在且成功运行的检查、merge commit、保留分支；最低GitHub审批人数0，PR内仍附独立审查结论与已解决问题。把ruleset、仓库merge配置、blocking列表和规则证据PR检查状态的API回读写入W00报告；证据PR自身通过新规则后合入。
- [ ] fetch并确认main同时包含文档基线、门禁实现和规则证据，再为W01建立`feature/w01-core-contracts`。后续任务同样从含前置任务的main分支开始。

**完成条件：** PR #4的基线可从main取得；门禁配置与实际读取一致；没有未解决blocking Issue。W00不能靠跳过保护配置宣称完成。

## W01：核心类型、配置、时钟与测试基础

**需求：** REQ-001～015、107～112、124、129～134中的类型/时间边界；TC-VALIDATE、TC-SCHEDULE、TC-PLATFORM。

**文件：** 新建Package、Models、Clock、MonitorFailure；`Tests/TemperatureCoreTests/{ContractTests,ClockTests,ConfigurationTests}.swift`及上述TestSupport；`scripts/check-core-coverage.py`、`.github/workflows/core.yml`。

**接口：** 按API逐字拆分公开enum/struct/protocol及public初始化器；`SystemClock: MonitorClock`，`now() -> Timestamp`、`sleep(untilElapsedNS: Int64) async throws`。在Models定义`RuntimeConfiguration: Decodable, Sendable`与`SensorProfile: Decodable, Sendable`，字段/CodingKeys逐项匹配两个JSON；入口分别为`static func load(from: URL) throws -> Self`。

- [ ] 建最小SwiftPM library与TemperatureCoreTests target；先加入合同编译测试及拒绝非法配置的测试，再运行确认缺实现时失败。Package只声明已经有源文件的target，后续W02/W03再加入Runtime/Bridge/Worker/CSQLite。
- [ ] 复制API类型；测试必须由独立模块`import TemperatureCore`构造Timestamp、ReadRequest和Sample，不能只靠`@testable`掩盖缺少public initializer。

```swift
@Test func timestampPreservesNanoseconds() throws {
    let original = Timestamp(elapsedNS: 9_007_199_254_740_993,
                             wallUnixNS: 1_700_000_000_000_000_001)
    let decoded = try JSONDecoder().decode(Timestamp.self,
        from: JSONEncoder().encode(original))
    #expect(decoded == original)
}
```

- [ ] 配置加载验证：CPU五档精确集合、默认200、tau均>0、TTL递增、resume<pause<max、单事件预留≤事务上限、profile12键无重复且区分大小写、active series含派生。坏JSON、未知版本、负容量、删除必填参数必须抛错；不得静默退回硬编码默认值。
- [ ] 以主进程共享的`mach_continuous_time`基准和`mach_timebase_info`生成elapsed；跨进程沿用同一基准。整数商余/宽乘防溢出；ContinuousClock只负责异步等待剩余时长。TestClock模拟睡眠前进、墙钟回拨及取消，不等待真实72小时。
- [ ] Clock测试输入elapsed=10s、wall回退3600s，预期elapsed继续增加；整数时间往返不丢纳秒；同时登记多sleep等待和取消一个等待，其他到期等待各恢复一次。
- [ ] 运行以下计划命令，预期所有测试通过且Swift 6并发检查通过。`check-core-coverage.py`统计Core和SensorRuntime生产Swift可执行行，不包含测试、App UI、C桥接与worker入口；未达到80%时失败，并报告各文件分母，不能沿用ProbeCore的55行分母。

```sh
swift test --package-path Packages/TemperatureCore --filter ContractTests
swift test --package-path Packages/TemperatureCore --filter ClockTests
swift test --package-path Packages/TemperatureCore --enable-code-coverage
python3 scripts/check-core-coverage.py
```

- [ ] 使`core-tests`在`feature/**`及PR运行实际Swift测试和80%门禁，加入main必需检查；提交可独立评审的类型/时钟工作，附红绿测试证据。

**完成条件：** 配置无重复来源、协议跨模块可用、测试时钟可控、Core测试门禁实际执行。此阶段不读硬件。

## W02：来源注册、SensorWorker协议与硬件边界

**需求：** REQ-008～015、054～057、109～116、132、134；TC-SENSOR、TC-VALIDATE、TC-PLATFORM。

**文件：** Registry、SensorRuntime/WorkerClient/WorkerProtocol、SensorBridge、SensorWorker入口；`Tests/SensorRuntimeTests/{WorkerProtocolTests,WorkerLifecycleTests,SourceRegistryTests,SensorDecodingTests}.swift`；测试专用`Tests/Fixtures/ProtocolWorker/main.swift`及构建配置。

**接口：** `WorkerClient: SensorClient`；`discover() async throws -> [SourceDescriptor]`、`read(_ request: ReadRequest) async throws -> ReadBatch`、`close() async`。Wire frame与公共ReadRequest不同，由WorkerProtocol封装version/generation/command；不得向公开协议暗加第二条读取路径。

- [ ] 先实现协议fixture程序，以行JSON接收并按scenario响应；success例：

```json
{"version":1,"requestID":"r1","generation":1,"command":"read","sourceIDs":["source-0"],"periodMS":200}
```

- [ ] 写失败测试：1MiB+1字节帧、错误JSON、错requestID、旧generation、EOF、1s读取超时、10s发现超时、stderr持续输出。预期协议错误为SENSOR-PROTOCOL-006；超时回收旧worker，旧回复不产生Sample，stderr不会堵住stdout。
- [ ] 实现WorkerClient：绝对路径启动、不用shell；独立IO队列读写和排空stderr；同时最多一个请求；超时SIGTERM→250ms→SIGKILL，确认退出再创建替代实例。测试每次close幂等，连续故障不积累子进程；OS不回收时停止重建并上报。
- [ ] 从原型逐函数移植只读SMC/NVMe/HID桥接，保留MIT声明、ABI静态断言和正确plugin/interface释放顺序；新增KeyInfo按generation+FourCC缓存。C头只暴露open/discover/read/close，不暴露写入操作。
- [ ] 编码测试以字节验收：`sp78 [0x19,0x80] → 25.5°C`；`flt [0x00,0x00,0xCC,0x41] → 25.5°C`；长度不符、NaN/Infinity、未知编码拒绝；SMART `[0x2C,0x01] → 26.85°C`、Kelvin0未报告。浮点误差容限1e-8。
- [ ] 按profile发现12个CPU键，逐键校验本profile必须`flt `且4字节。通用sp78解码成功不意味着profile允许类型变化。生成source UUID，connectionGeneration变化后旧sourceID失效；`Tp0b`与`Tp0B`不合并。
- [ ] Battery严格执行IOPS CFNumber且非CFBoolean→TB1T→TB2T→TB0T；不使用AppleSmartBattery未证实单位字段。SSD仅唯一Internal NVMe，父树最多16层，多个/未知/循环都Unavailable。用模拟服务树覆盖这些分支；不选device:0，不平均电池源。
- [ ] HID仅诊断模式启用；同名不同registryID分别保存；没有本机CPU分类则不回退。未知机型APP-PLATFORM-002，缺少固定CPU成员SENSOR-DISCOVER-001，可选缺失只影响capability。
- [ ] 运行以下计划命令，预期协议/解码/身份测试通过、worker可构建；真实硬件温度结果留到W09，不在CI伪造。

```sh
swift test --package-path Packages/TemperatureCore --filter WorkerProtocolTests
swift test --package-path Packages/TemperatureCore --filter WorkerLifecycleTests
swift test --package-path Packages/TemperatureCore --filter SensorDecodingTests
swift test --package-path Packages/TemperatureCore --filter SourceRegistryTests
swift build --package-path Packages/TemperatureCore --product SensorWorker -c release
```

- [ ] 提交桥接、协议、来源测试及第三方声明；独立审查重点检查所有权、超时回收与无提权路径。

**完成条件：** SensorClient在进程边界可测试，来源和单位选择确定；普通用户生产读通仍需W09证明。

## W03：SQLite、幂等事务、查询与TTL

**需求：** REQ-017～020、023/024、030～042、048～053、058～063、124、129；TC-STORAGE、TC-RETENTION。

**文件：** CSQLite模块、Storage三文件和schema资源；`Tests/TemperatureCoreTests/{SQLiteStoreTests,RetentionTests,HistoryQueryTests,StorageFaultTests}.swift`及TemporaryStoreFixture。

**接口：** `SQLiteStore: SampleStore`，实现API所有六类方法；SQL资源与规范DDL一致。Core用单写/单读连接的专用串行队列，不在MainActor或Swift协作线程池同步阻塞。

- [ ] 创建系统SQLite module map，Package增加systemLibrary和资源，不下载数据库或引入ORM：

```c
/* Sources/CSQLite/shim.h */
#include <sqlite3.h>
```

```text
module CSQLite [system] {
    header "shim.h"
    link "sqlite3"
    export *
}
```

- [ ] 先写真实临时数据库的批次幂等测试，再实现事务；fixture已注册来源，以下测试必须调用真实append而非MockStore：

```swift
@Test func repeatedBatchIsIdempotent() async throws {
    let f = try await TemporaryStoreFixture.make()
    let batch = Fixtures.persistence(id: "batch-1", value: 80, ms: 100)
    try await f.store.append(batch)
    try await f.store.append(batch)
    #expect(try f.rows(in: "raw_samples") == 1)
    #expect(try f.rows(in: "ema_samples") == 1)
    #expect(try f.rows(in: "committed_batches") == 1)
    try await f.store.closeAndDeleteSession()
}
```

- [ ] 实现`BEGIN IMMEDIATE`、canonical不可变载荷SHA-256、batchID查询、逐字段冲突检测、依赖顺序插入、凭据与数据同事务COMMIT。相同ID不同内容DB-INTEGRITY-010；Gap仅允许NULL结束时间单调变确定值。覆盖提交成功但ack丢失后重试、事务中途失败回滚，Raw/EMA不能只成功一半。
- [ ] 实现PRAGMA及schemaVersion/quick_check；BUSY/LOCKED唯一重试层busy_timeout=0；disk full/损坏/schema冲突不重建当前会话库。模拟锁竞争按100/250/500/1000/2000ms重试，释放后成功停止重试。
- [ ] TTL测试用虚拟elapsed在300s/3600s/86400s/259200s边界±1ns查询和prune。边界正好等于cutoff删除；父层未提交不能删子层；睡眠超72h不产生空桶且过期行不可见；清理落后超过120s为DB-CLEAN-005。
- [ ] 历史只实现四档最近范围；SQLite query处理1h/24h/72h，5min由控制器路由内存。检查最多8series×2000显示点、全时间范围再分箱、min/max包络和count加权avg、最多250ms、旧query取消/结果丢弃。不能先LIMIT掉较早历史。
- [ ] 压力fixture插入8640个10s桶，一个中间桶max=99，其余max=50；请求2000点后仍覆盖首尾时间且保留99峰值。两段相同窗口起点分别返回，不能跨segment合并。
- [ ] 实现每60s清理/checkpoint；主库768MiB软限按`(page_count-freelist_count)×page_size`有效页计算、1GiB硬限按物理文件字节计算，WAL为32/64MiB；实现statement释放与缓存上限。验证TTL删除形成freelist后能解除软限，即使文件尚未缩小。故障注入通过文件空间/SQLite返回值替身，不为测试真实耗尽用户磁盘。
- [ ] 运行以下计划命令，预期全部通过、关闭后临时会话DB/WAL/SHM不存在；提交存储实现和故障证据。

```sh
swift test --package-path Packages/TemperatureCore --filter SQLiteStoreTests
swift test --package-path Packages/TemperatureCore --filter RetentionTests
swift test --package-path Packages/TemperatureCore --filter HistoryQueryTests
swift test --package-path Packages/TemperatureCore --filter StorageFaultTests
```

**完成条件：** schema、幂等、时间边界、取消、容量和故障可重现；数据库空间上限是保护机制，未宣称72h实测占用已达标。

## W04：Raw、EMA、聚合、趋势与缺口

**需求：** REQ-013～034、043～053、064～067、129～134；TC-BUFFER、TC-EMA、TC-AGG、TC-TREND。

**文件：** MetricResolver、Processing四文件、MonitorEngine加工部分；`Tests/TemperatureCoreTests/{EMAProcessorTests,AggregationTests,TrendTests,RingBufferTests,ProcessingIdentityTests}.swift`及ProcessorFixture。

**接口：** MonitorEngine实现`ProcessingEngine.accept/advance/markGap/snapshot/realtime`，并在构造时注入PersistenceQueue；三个变更状态的方法都显式接收QueueReservation，在临时状态计算，完成入队确认后才交换状态，返回批次仅供测试/审计。advance的时间参数只接收安全watermark。私有算法类型不依赖SMC、SQLite或SwiftUI。

- [ ] 先写以下对生产ProcessingEngine的数值测试；fixture为单identity来源且不启动定时采集：

```swift
@Test func emaUsesActualElapsedTime() async throws {
    let f = try await ProcessorFixture.make()
    let ar = try await f.reservation(ownerID: "a", generation: 1)
    let br = try await f.reservation(ownerID: "b", generation: 1)
    let cr = try await f.reservation(ownerID: "c", generation: 1)
    let a = try await f.engine.accept(Fixtures.read(id: "a", ms: 0, values: [80]), reservation: ar)
    let b = try await f.engine.accept(Fixtures.read(id: "b", ms: 500, values: [100]), reservation: br)
    let c = try await f.engine.accept(Fixtures.read(id: "c", ms: 1000, values: [100]), reservation: cr)
    #expect(a.ema.first?.valueC == 80)
    #expect(abs(try #require(b.ema.first).valueC - 92.6424111766) < 1e-8)
    #expect(abs(try #require(c.ema.first).valueC - 97.2932943353) < 1e-8)
}
```

- [ ] 实现每来源Raw与EMA各8192槽、300s时间过滤，快照不能持有无限历史副本。首点Raw，`alpha=-expm1(-dt/tau)`；dt≤0拒绝；相同值不同请求计新样本，相同requestID/内容重放不推进算法。
- [ ] 用12源fixture验证先max再EMA：第一批`[100,20,20,…]`，第二批`[20,100,20,…]`，主指标两次均100。删一个成员、重复一个sourceID、批跨度200ms+1ns都不得产生主指标；不缩小集合。真实来源的有效读数及失败批次处理依05/06，不制造旧值。
- [ ] 写Raw聚合验收：同一1s内70/71/72/95/74，水位到1s后min70/max95/sum382/count5/latest74；父层A=sum60/count1、B=sum240/count3合并avg75。点恰在1s归下一窗口，空窗无Bucket，一个10s窗口仅首尾有1s子桶也准时闭合且partial=true。
- [ ] 实现窗口`[k×width,(k+1)×width)`、同series+segment分层合并、latest时间/序号裁决、coverage时间并集；不以EMA生成历史max，不用子avg简单平均，不跨缺口补旧值。
- [ ] 趋势测试使用固定EMA点：t=0/4/8s、v=20/20.08/20.16，CPU主指标窗口10s、3点和80%覆盖满足，斜率0.02为stable；改v=20/20.12/20.24为rising，反向为falling。仅两点或覆盖7.999s为insufficient；任何Gap后旧点不可参与。
- [ ] Gap测试覆盖明确失败、sleep、overload、sourceChange、clockChange，以及`dt > max(3×max(previousPeriod,currentPeriod),1s)`；正常200→1000ms改变不误判。新segment首EMA=Raw，Raw历史仍保留；重复同一连续故障不无限创建Gap。
- [ ] 处理临时状态先生成PersistenceBatch，成功进入预留输出队列才交换状态并发布；拒绝接纳时EMA、聚合count、sample序号、已处理ID都不能部分前移。将此失败注入作为独立回归测试，不只测算术。
- [ ] 执行计划命令，预期所有数值在明确容限内、时序/幂等严格相等；提交算法与验收向量。

```sh
swift test --package-path Packages/TemperatureCore --filter EMAProcessorTests
swift test --package-path Packages/TemperatureCore --filter AggregationTests
swift test --package-path Packages/TemperatureCore --filter TrendTests
swift test --package-path Packages/TemperatureCore --filter RingBufferTests
swift test --package-path Packages/TemperatureCore --filter ProcessingIdentityTests
```

**完成条件：** 算法和数据接纳状态均可确定重放；生产tau/趋势阈值只取配置，不因fixture改生产参数。

## W05：串行调度、背压、持久化与快照编排

**需求：** REQ-001～007、016～018、054～071、100、129；TC-SCHEDULE、TC-STORAGE、TC-ERROR。

**文件：** MonitorEngine编排、SensorRuntime/SamplingService；`Tests/TemperatureCoreTests/{MonitorIntegrationTests,BackpressureTests,WatermarkTests}.swift`；`Tests/SensorRuntimeTests/SamplingServiceTests.swift`及ControllerFixture。

**接口：** `MonitorController.start/setCPUPeriod/snapshots/history/stop`；构造时注入SensorClient、MonitorClock、SampleStore和配置/profile。Core只依赖SensorClient协议，不能为使用SamplingService反向import SensorRuntime而形成循环；Runtime调度器调用Core定义的入口。

- [ ] 先写受控事件脚本，fixture逐事件执行真实编排，输出实际request时刻/ID、队列计数、快照和提交批次：

```json
[
  {"at_ms":0,"event":"start","cpu_period_ms":200},
  {"at_ms":200,"event":"expect_read","kind":"cpu"},
  {"at_ms":210,"event":"respond","all_members_celsius":80},
  {"at_ms":250,"event":"set_cpu_period","value_ms":500},
  {"at_ms":400,"event":"expect_no_cpu_read"},
  {"at_ms":750,"event":"expect_read","kind":"cpu"},
  {"at_ms":760,"event":"respond","all_members_celsius":81},
  {"at_ms":800,"event":"stop"}
]
```

- [ ] 实现CPU/SSD/Battery三日程共用一个worker；nextDue按计划时刻推进，结束后跳过过期机会、不追赶；同到期CPU优先。周期变更nextDue=变更时刻+新周期，在途任务沿用旧周期。不存在可选来源时无对应调度。
- [ ] start以SessionMetadata打开数据库，首次发现后在启动任何读取前register全部来源/定义。重发现产生的新source/definition随首个PersistenceBatch写入sources/definitions并与引用它的segment/sample同事务提交；旧定义不改写。注册或首批提交失败不得发布新来源快照。
- [ ] 将普通读取与重试放同一串行通道；成功终止本轮重试，失败次数与skipped分开计数。测试50ms下读取持续120ms，不能累计补发定时任务或同时运行第二条worker调用。
- [ ] 每事件先预留512逻辑记录及最坏序列化容量；总含在途事务≤16384条/32MiB。达到12288暂停，低于8192恢复并分段；队列阻塞仍保留已接纳批次。200ms或512条触发flush，事务≤512条，最老年龄>10s Fatal。
- [ ] 背压测试驱动writer停止响应，验证采集在高水位前停止、在途结果有预留空间、所有接纳sampleID最终恰好一次持久化；释放writer后低水位恢复，Gap显式结束。饱和时禁止覆盖持久化队列或仅保留最新Raw。
- [ ] 实现安全watermark：请求start<窗口end且未完成时不得封窗；返回后先加工再advance，超时后旧generation结果丢弃。测试请求0.95s开始、1.05s完成，源点进1～2s桶，不能先写错误0～1s结果再重开。
- [ ] snapshots使用`AsyncStream(bufferingPolicy: .bufferingNewest(1))`、最多每200ms发布一次；允许UI覆盖旧快照，不允许覆盖写队列。history五分钟走ProcessingEngine.realtime，其余SampleStore.query；结果携带persistedThrough。
- [ ] stop和actor重入测试：start/await read期间stop，迟到响应不得重启采集、写新批或发布“运行中”；连续两次stop都结束。任何await返回后校验session/generation/state。
- [ ] 运行计划命令，预期单一worker、无追赶、预算不越界、Raw/EMA/聚合最终匹配；提交集成证据。

```sh
swift test --package-path Packages/TemperatureCore --filter SamplingServiceTests
swift test --package-path Packages/TemperatureCore --filter MonitorIntegrationTests
swift test --package-path Packages/TemperatureCore --filter BackpressureTests
swift test --package-path Packages/TemperatureCore --filter WatermarkTests
```

**完成条件：** `MockSensorClient → 真实加工 → 真实SQLite → 历史查询`闭环及内存实时路由均通过，不依赖真实驱动完成软件集成。

## W06：重试、Fatal、会话、睡眠与日志

**需求：** REQ-038～042、054～084、125/126；TC-ERROR、TC-LIFECYCLE。

**文件：** MonitorFailure、ReportWriter、App/SessionCoordinator；`Tests/TemperatureCoreTests/{RetryPolicyTests,ErrorCoordinatorTests,SessionLifecycleTests,DiagnosticsTests}.swift`。可测文件锁/文件清理/日志逻辑放Core的Diagnostics及Storage文件，App类只连接系统事件和MainActor。

**接口：** MonitorFailure字段保持API；SessionCoordinator实现/持有MonitorController生命周期入口；不让View直接关闭worker或删数据库。

- [ ] 参数化失败测试覆盖以下等待序列；等待从前次调用结束计，次数不含首次。UI历史读取走UI预算，不嵌套DB五次预算：

```text
sensor:     attempts=4, waits_ms=[50,100,200]
database:   attempts=6, waits_ms=[100,250,500,1000,2000]
processing: attempts=4, waits_ms=[50,100,200]
ui_history: attempts=4, waits_ms=[100,250,500]
```

- [ ] 编写并实现严重性矩阵：CPU固定成员重试耗尽Fatal；SSD/Battery耗尽Unavailable且CPU继续；schema/损坏/ID冲突直接Fatal；普通非有限读数不是PROC-VALIDATE-001。可选恢复每60s最多3轮，成功后连续3次本周期有效才恢复显示和新定义/段。
- [ ] 单实例测试以两个真实文件锁持有者模拟；第二个不能删除第一个会话。残留清理仅处理带正确bundle/session/schema marker的Sessions子目录，拒绝符号链接、目录越界和无marker文件。
- [ ] 完成启动、sleep/wake、正常退出顺序。测试sleep跨300s/72h后无补样本/空桶、重发现新UUID、历史按TTL清理；⌘W不调用stop。退出收尾5s预算不因worker或DB失败无限等待，下次启动清理合法残留。
- [ ] 日志/报告写真实临时目录：5MiB×5个JSONL、20份报告×1MiB、14天TTL；日志路径与会话删除分离；60s汇总而非每条Raw写诊断。测试无法写报告时保留原错误码，OSLog/stderr与可复制文本兜底，不递归Fatal。
- [ ] 设计Fatal展示状态在首个可见时刻开始30s倒计时，支持打开报告/复制详情/退出；MainActor连接留W07，Core用展示回执fixture验证“报告完成不等于已展示”。关闭/计时到期后同一stop链，原生展示失败走NSAlert，再失败终止。
- [ ] 运行以下计划命令，预期次数、时序、文件范围和状态都可严格断言；提交故障与生命周期实现。

```sh
swift test --package-path Packages/TemperatureCore --filter RetryPolicyTests
swift test --package-path Packages/TemperatureCore --filter ErrorCoordinatorTests
swift test --package-path Packages/TemperatureCore --filter SessionLifecycleTests
swift test --package-path Packages/TemperatureCore --filter DiagnosticsTests
```

**完成条件：** 每种故障有有限出口，日志独立、单实例安全、stop幂等；真实系统sleep/wake仍需W09。

## W07：原生菜单栏、面板、主窗口与图表

**需求：** REQ-043～053、068～078、108、117～123、125、130；TC-UI。

**文件：** App/Presentation全部文件；`UITests/TemperatureMonitorUITests.swift`；UI资源许可记录；先创建用于运行这些视图的`TemperatureMonitor.xcodeproj`及`App/{TemperatureMonitorApp,AppDelegate}.swift`最小入口。完整Xcode是本任务运行UI测试的条件，W08完成生产装配及最终打包脚本。

**接口：** PresentationModel为MainActor，只消费`Snapshot`、`HistoryResult`、`MonitorFailure`及MonitorController；不直接import SensorBridge或持有SQLite连接。公开绑定名称由本任务统一定义，所有视图共享同一CPU设置状态。

- [ ] 创建最小macOS App target、UI test target及共享scheme`TemperatureMonitor`，使用09的Swift6/arm64/15.7.3/Bundle ID并连接本地Package，使W07无需等待W08即可运行UI测试。测试专用数据注入仅Debug/Test配置接受`--ui-fixture basic/gap/stale/fatal`，生产Release必须拒绝该入口。fixture在界面显著写“测试数据”，不作为硬件验收来源。
- [ ] 先写菜单栏显示/交互测试和主窗口关闭后会话持续测试；为控件设置稳定accessibilityIdentifier：`status.temperature`、`cpu.period`、`history.range`、`source.list`、`fatal.code`、`fatal.quit`。

```swift
func testCPUPeriodPicker() throws {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-fixture", "basic"]
    app.launch()
    let picker = app.popUpButtons["cpu.period"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    picker.click()
    app.menuItems["500 ms"].click()
    XCTAssertEqual(picker.value as? String, "500 ms")
}
```

- [ ] 按07固定来源移植NSStatusItem/NSPopover与分组行，逐文件登记上游commit/版权/许可/修改范围。完成左键切换、右键命令、Esc/点击外部关闭；340×640pt面板按屏幕限高，960×680pt主窗最小800×560pt，关闭窗口采集继续。
- [ ] 数值始终EMA、一位小数和°C，缺失为`— °C`；暂时失败显示缓存/观测时间，超过`max(3×当前周期,2s)`隐藏数值为过期；不可用显示原因；freshness未知不写“刚测量”。CPU标题固定profile主指标。
- [ ] 图表实现5min内存EMA、其余历史avg和min/max包络，默认CPU主指标、最多8源、每源2000点；绘线按series+segment分组，Gap断开；不以曲线平滑制造Raw峰值。无历史写“本会话暂无数据”，隐藏窗口停止绘图。
- [ ] Settings提供五档、来源显示、日志文件夹、版本/许可；无高温告警、登录项、更新网络入口。来源详情暴露key/provider/evidence，正常页面不显示调试堆栈。
- [ ] FatalView连接W06展示回执与30s倒计时，错误文本和报告操作可访问；渲染失败NSAlert兜底。检查浅/深色、减少透明度、键盘导航、窄屏、滚动和辅助功能文本。
- [ ] 用本任务创建的scheme执行下列计划命令；XCUITest及需人工的菜单栏/视觉项目分别留证，不能因为automation未识别菜单栏就跳过：

```sh
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
```

- [ ] 独立审查UI状态与来源声明，提交UI实现、截图和测试日志。

**完成条件：** 所有要求的原生界面均能操作，数据状态及来源真实；没有复用上游Core占用率网格冒充温度。

## W08：App工程、worker嵌入、本地构建与端到端

**需求：** REQ-100～108、112、124、126/127；TC-PLATFORM、TC-LIFECYCLE、TC-UI、TC-RELEASE。

**文件：** Xcode项目、TemperatureMonitorApp/AppDelegate、App资源、`scripts/build-app.sh`、`.github/workflows/app.yml`；扩展UITests与`Tests/TemperatureCoreTests/EndToEndTests.swift`。

**接口：** App通过本地Swift Package使用Core/Runtime；创建唯一SessionCoordinator与PresentationModel。构建脚本产物固定为`build/TemperatureMonitor.app`，内嵌同一构建的`Contents/MacOS/SensorWorker`。

- [ ] 完成W07创建的macOS App、UI test target和共享scheme`TemperatureMonitor`的生产装配；复核Swift6、arm64、deployment15.7.3、Bundle ID按defaults。接入唯一真实SessionCoordinator与PresentationModel，链接本地Package，关闭App Sandbox，无root/private entitlement。
- [ ] 将规范defaults/profile资源复制到App，schema作为Package资源加载；CI逐字比对资源，修改规范后未更新拷贝必须失败。把所有实际移植的MIT版权与完整许可纳入ThirdPartyNotices。
- [ ] 实现build-app.sh：`set -euo pipefail`，校验完整Xcode、构建Release与SensorWorker、从本次DerivedData复制App、嵌入worker/资源；路径或新产物缺失立即失败，不能签/测旧包。本地先worker后App进行ad-hoc签名。

```sh
swift build --package-path Packages/TemperatureCore --product SensorWorker -c release
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -configuration Release -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/TemperatureMonitor.app
```

- [ ] 端到端测试使用测试配置：12源→Raw→CPU派生→EMA→聚合→SQLite→历史→展示；重放请求、注入缺成员/DB BUSY/背压/Gap、退出后验证DB/WAL/SHM消失且日志保留。Release拒绝测试数据开关，不在最终产品自动fallback到fixture。
- [ ] 执行Core全套、coverage、App构建、UI测试及文档检查。CI新增真实`app-build`并设必需；runner必须有选定完整Xcode，固定选择工具链且保存版本。无硬件runner只证明构建/软件测试。

```sh
swift test --package-path Packages/TemperatureCore --enable-code-coverage
python3 scripts/check-core-coverage.py
bash scripts/build-app.sh
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
python3 scripts/validate-handoff.py
```

- [ ] 检查App包没有运行时调用swift、外部probe路径、未打包依赖、私钥或模拟硬件开关；提交完整可本地安装App构建链。

**完成条件：** 无签名外部凭证也能构建并运行本地App；`handoff-docs/probe-tests/core-tests/app-build/blocking-issues`均为实际检查。硬件与公证状态仍由W09/W10分别判定。

## W09：首台实机资格、五档与长期运行

**需求：** REQ-001～015、054～057、109～116、129～134及资源/生命周期要求；TC-SENSOR、TC-SCHEDULE、TC-PLATFORM、TC-ENDURANCE。

**文件：** 新建`scripts/run-hardware-qualification.sh`、`scripts/summarize-product-qualification.py`及产品实机证据目录；必要缺陷修复回到对应模块，并保留失败证据。

**接口：** 验证脚本运行W08生成的实际App/内嵌worker，以显式诊断配置导出计时和来源信息，不调用旧原型代替App。输出capabilities.json、timing.csv、sampling-results.csv、summary.json和报告，字段含提交/应用版本/机型/OS build/配置/profile/签名/日期。

- [ ] 首先确认真实机器为Mac16,13、普通用户且profile允许的系统；保存构建SHA与App签名。只有目标环境执行真实资格；其他环境不得伪造机型或通过fixture冒充。
- [ ] 逐键核对12CPU来源、flt4字节、单位证据、固定成员、未知freshness；SSD明确Internal唯一NVMe composite；Battery记录实际选中IOPS或TB键和优先级判定。周期读取失败按规范显式失败，不补0/旧值。
- [ ] 对五档分别执行至少10分钟空闲及10分钟可控负载，记录计划/实际开始结束/批跨度/读取失败/重试/skipped/source时间信息；负载必须使用维护者批准的本地工具并记录命令。不得用相同温度比例推断硬件刷新频率。
- [ ] 确认所有派生CPU批次12成员完整且跨度≤200ms；超范围被正确拒绝并重试。调度是否按日程/跳过过期机会由事件证据判定；CPU/内存/能耗只报告实测分布，不编造用户已暂缓的性能SLO。
- [ ] 实机执行至少三轮sleep/wake、档位切换、窗口关闭重开、App退出重启、双实例、断网运行。验证新source/definition/segment、Gap、无跨会话恢复、停止后无孤立worker。
- [ ] 持续运行至少73小时以实际越过最大72h TTL；保存分时资源、数据库/WAL/日志体积、队列最高值与最老年龄、清理进度。通过条件：未触发硬限、队列有界、查询TTL准确、父层先提交、无无限增长迹象；软件虚拟时钟测试不替代此记录。
- [ ] 在验证工具完成后执行计划命令，预期生成可机器检查的证据与明确pass/fail；任何失败建立Issue并回归，不将旧V0报告重命名成产品报告：

```sh
bash scripts/run-hardware-qualification.sh --app build/TemperatureMonitor.app --profile docs/contracts/first-profile-v1.json --suite full
python3 scripts/summarize-product-qualification.py --input docs/validation/product-hardware
```

- [ ] 报告逐项声明available/unavailable及理由；通过的机型+OS build组合才列入正式兼容矩阵，其他组合保持未验收。仅在有生产证据的定义上升为targetQualified，不改写历史原型证据。

**完成条件：** 首个组合产品硬件/生命周期/73h验收通过；失败或未运行项目不隐藏。缺实机时可以完成脚本和软件测试，但W09状态只能为未执行。

## W10：签名、公证ZIP与正式配置复测

**需求：** REQ-111、126/127；TC-RELEASE及最终权限下TC-SENSOR/TC-LIFECYCLE。

**文件：** 新建`scripts/package-release.sh`、发布manifest/校验文件/证据目录；更新App版本与兼容矩阵。不增加自动更新或上传服务。

**接口：** 输入W08当前源码构建及维护者Keychain/CI secrets；输出`build/TemperatureMonitor-notarized.zip`及manifest。外部输入是`DEVELOPER_ID_APPLICATION`、`APPLE_TEAM_ID`、`temperature-monitor-notary` Keychain profile，名称已确定，不需要Agent自行发明证书。

- [ ] package-release.sh验证凭证存在且当前源码/配置全套检查通过；缺凭证时明确失败并保留本地App交付。日志不能输出私钥、密码或完整认证内容。
- [ ] 重新调用build-app.sh生成当前源码产物，记录SHA/toolchain/SDK/profile/资源哈希；先签worker，再签App，启用Hardened Runtime，不以`codesign --deep`作为签名方式。
- [ ] 将13的完整命令顺序写入脚本：签名→验证→原始ZIP→notarytool等待→staple App→spctl→最终ZIP。仅notarytool返回Accepted且stapler/spctl均成功才能命名/声明notarized。

```sh
bash scripts/package-release.sh
codesign --verify --deep --strict --verbose=2 build/TemperatureMonitor.app
xcrun stapler validate build/TemperatureMonitor.app
spctl --assess --type execute --verbose=2 build/TemperatureMonitor.app
shasum -a 256 build/TemperatureMonitor-notarized.zip
```

- [ ] 对正式签名App重跑W09来源、五档、sleep/wake、本地断网、双实例、退出清理、日志不可写及73h验收；最终配置有变化就不能沿用Debug/ad-hoc权限结论。保存App身份、ticket、证据及已发布最高稳定macOS核对日期。
- [ ] 发布manifest包含version/build/source SHA、App/ZIP SHA-256、工具链/SDK、签名Team、profile版本、兼容机型/OS build、许可证。保留手动下载/替换说明；对外上传或发布由维护者按授权执行，不能把本地打包成功写成已发布。
- [ ] 提交发布脚本和非敏感证据；等待维护者审查及发布决定。

**完成条件：** 有凭证时完成正式ZIP和最终构建资格；无凭证时明确列为外部发布条件未满足，W01～W09的本地产品工作仍完整交付。

## W11：逐REQ验收、最终审查与交接

**需求：** 全部REQ-001～134，其中012/114退役；TC-DOCS、TC-WORKFLOW及全套产品用例。

**文件：** 更新`docs/contracts/acceptance-v1.json`对应证据字段、`docs/17-traceability.md`、产品软件/实机/发布报告；保持原始需求来源与历史报告不被覆盖。

**接口：** 逐REQ使用现有映射的任务/测试组及证据路径；不凭任务标题批量标“通过”。新增/变更规则必须同步需求、决策、契约和测试，不只修改实现。

- [ ] 检查134个ID唯一且齐全，132个现行各有实现任务、自动或人工验收、结果与证据；012/114仅为retired/不适用。C10/C11改动已覆盖Package改名、可选指标、Raw峰值和内存实时路径。
- [ ] 以测试产物逐项核对REQ：模拟软件、实机、签名分发三类证据分开；“已实现”“软件通过”“目标组合通过”“正式公证通过”不得互换。不存在测试日志的项目保持未执行。
- [ ] 在最终commit运行以下计划命令，保存输出；变更后只重跑相关及规定总门禁，不重复无变化的昂贵实机测试：

```sh
python3 scripts/validate-handoff.py
swift test --package-path prototypes/sensor-probe --enable-code-coverage
python3 scripts/check-probe-coverage.py
swift test --package-path Packages/TemperatureCore --enable-code-coverage
python3 scripts/check-core-coverage.py
bash scripts/build-app.sh
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
git diff --check
```

- [ ] 独立审查对照设计而非仅看测试成功：检查所有权/退出、固定成员、缺口、水位、幂等/背压、私密目录、代码许可、Release无测试fallback。发现可复现缺陷建Issue，阻塞级加`blocking`，修复并附回归。
- [ ] 读取最新PR head上的五个required checks、仓库全部open blocking Issue和保护配置；确保head未变。审查证据入PR，由维护者手动merge commit，保留远程feature分支。无管理员权限或外部门禁失败时交付完整待审PR，不能自行绕过。
- [ ] 最终报告包含本地App路径、已完成任务、134项映射结果、实际支持组合、失败/未执行项、正式ZIP状态、外部凭证或设备依赖、操作与诊断入口。没有公证凭证时明确“本地App完成，正式发布未完成”；不能将全部项目称为完全验收通过。

**完成条件：** 每条现行需求可追到实现与真实证据，代码/文档/契约一致，保留分支和合并节点；最终交付范围与外部条件状态明确。

## 执行者每任务收尾清单

- [ ] 先记录能失败的有意义测试，再实现并观察通过；无行为变化的文档/配置检查不机械添加镜像测试。
- [ ] 本任务文件遵守08边界，协议与21一致；没有不受限队列、重复算法或隐藏fallback。
- [ ] 对应测试、Core80%门禁、既有原型回归和文档验证通过；UI/实机/发布按任务阶段真实执行。
- [ ] 保存失败与回归证据，更新本任务REQ映射；通过独立审查后提交PR，不直接推main。
- [ ] 接下任务前确认前置合同已合入main；不能从旧main丢失已批准设计，也不能把文档计划命令写成已执行事实。
