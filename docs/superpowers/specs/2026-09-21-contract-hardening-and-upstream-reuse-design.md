# 契约收紧与开源复用边界设计

状态：书面规格待用户审阅  
日期：2026-09-21  
适用基线：`feature/v0-sensor-validation` / `77bd69ffeb8629783cfa1770a37db3f262446bad`

## 1. 目标

在不改变项目现行产品范围的前提下，收紧跨模块契约，使后续Agent能够直接实现并验证以下行为：

1. CPU主指标继续采用首个profile固定的12个CPU热区成员，每批先取Raw最大值，再做EMA。
2. 逐物理CPU核心温度、物理Package保证、`core_id`、未验证的E/P域标签继续保持退役状态。
3. SMC、HID、NVMe和IOPS的读取结果只有经过profile、编码、单位、来源身份和generation校验后，才能进入加工、存储和展示。
4. 队列预留、加工状态提交和SQLite写入保持“先确保可接纳，再交换状态”的现行不变量，同时缩小可误用的公开接口。
5. 菜单栏、弹出面板、主窗口和图表共享一个不可变展示状态，不分别推断缓存、过期和能力状态。
6. 复制或改写开源代码时，来源、许可、修改范围和本地文件关系可由机器校验。
7. SDK、部署目标、运行时资格和正式兼容声明分别记录，避免把构建成功解释为实机兼容。

本次是现有架构的收紧，不替换Swift＋小型C桥接＋SensorWorker＋SwiftUI/AppKit＋SQLite路线，不增加告警、自启动、联网更新、风扇控制、root helper、外部监控CLI或跨会话历史。

## 2. 证据与开源复用规则

### 2.1 允许复用

满足许可和逐文件登记后，可以复制、改写或重新实现以下内容：

- macmon的只读SMC连接生命周期、KeyInfo缓存和底层返回码检查。
- Stats、MacMonitor的原生菜单栏、弹出面板、分组和来源列表结构。
- SwiftTempBar中与等宽数字、空值占位和减少无效重绘有关的展示方法。
- MacFanControl的App/Core/C桥接分层思想，但在取得固定版本的完整许可材料前不得复制其代码。
- Philip Turner实验的观测问题和实验方法，不复制无明确许可的源码。

### 2.2 禁止继承

以下行为不得因上游项目存在而进入本项目：

- 用键名、服务名、数组序号或CPU物理核心数推断逐核、E/P域或Package含义。
- 读取失败时把上次成功值重新写成新Raw、EMA或聚合样本。
- 缺少事件或解析失败时生成`0 °C`。
- 使用未经本机profile验证的统一温度上下限、健康颜色或CPU平均公式。
- 引入SMC写入、风扇控制、提权帮助程序、私有entitlement或UI主线程硬件读取。
- 把原型、CI、上游源码或其他机型结果写成正式App在目标机型上的验收证据。

### 2.3 证据层级

证据仍按以下顺序解释：

1. 目标机型、目标OS/build、目标App配置的实机验收。
2. 当前仓库保存的目标机只读原型证据。
3. 固定commit的上游源码和许可文件。
4. 项目设计选择与由证据得出的有限推断。

低层证据不能自动升级为高层证据。来源可读不证明物理位置、刷新率、精度或所有同系列机器兼容。

## 3. 模块边界

生产模块保持以下单向数据流：

```text
SensorBridge / SensorWorker
        │ 原始发现与读取帧
        ▼
SensorRuntime Registry
        │ QualifiedSourceCatalog + ReadBatch
        ▼
SamplingService ──取得PersistenceLease──► SessionPersistence
        │                                      ▲
        ▼                                      │ 原子接纳
MonitorEngine ──PersistenceBatch───────────────┘
        │ Snapshot / HistoryResult
        ▼
PresentationModel
        │ PresentationState
        ▼
StatusItem / Popover / Dashboard / Chart
```

模块职责：

| 模块 | 公开职责 | 不得承担 |
|---|---|---|
| SensorBridge | 只读ABI、类型解码、句柄释放 | profile选择、UI名称、重试、写SMC |
| SensorWorker | 有界帧协议、deadline后的进程隔离 | 算法、SQLite、展示状态 |
| Registry | 将原始发现结果校验为合格来源目录 | 以名称猜测物理含义 |
| SamplingService | 周期、优先级、单在途、有限重试、预留容量 | EMA、聚合、直接写库 |
| MonitorEngine | 校验、Raw主指标、EMA、聚合、趋势和缺口 | 驱动访问、视图格式化 |
| SessionPersistence | 容量预留、幂等提交、查询、TTL和会话删除 | 传感器语义、界面状态 |
| PresentationModel | 将核心快照转换为不可变展示状态 | 驱动调用、SQLite连接、业务重试 |

## 4. 强类型身份与有效状态

### 4.1 身份类型

跨模块身份不再全部使用可互换的`String`。定义以下轻量值类型，并由其所属模块控制创建：

```swift
public struct SessionID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}

public struct SourceID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}

public struct SeriesID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}

public struct RequestID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}

public struct BatchID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}

public struct GapID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}

public struct WatermarkEventID: Codable, Sendable, Hashable {
    public let rawValue: String
    public init(validating rawValue: String) throws
}
```

上述ID的规范格式统一为小写标准UUID字符串；解码和公开构造均执行同一校验。测试fixture使用固定UUID，不再使用`source-0`、`r1`等自由文本。不得在业务路径随意拼接ID。现有SQLite列继续使用`TEXT`，由存储适配器转换。稳定可见角色另用`MetricID`封闭类型表达，不与实例UUID混用。

### 4.2 读取结果

`Reading`不再同时暴露可空`valueC`和可空`failure`。改为互斥结果：

```swift
public enum ReadingOutcome: Codable, Sendable {
    case success(valueC: Double, sourceWallUnixNS: Int64?, freshness: Freshness)
    case failure(MonitorFailure)
}

public struct Reading: Codable, Sendable {
    public let sourceID: SourceID
    public let started: Timestamp
    public let finished: Timestamp
    public let outcome: ReadingOutcome
}
```

成功值仍须通过有限值、绝对零度、profile编码和单位校验。失败分支不能携带温度值，成功分支不能携带错误。

### 4.3 定义和原因

- `SeriesDefinition.formula`改为`SeriesFormula.identity`或`.maximum`。
- `Segment.reason`改为封闭枚举，至少覆盖sessionStart、sourceChange、wake、clockChange和recovery。
- 固定错误码改为`MonitorErrorCode`枚举；底层未知码仍保存在`underlyingCode`。
- 序列化遇到未知v1枚举值时按协议错误处理，不静默降级为任意字符串。

## 5. 来源发现与资格化

Worker线协议返回`DiscoveredSource`，只包含底层可观察事实：provider、rawKey、registryID、原始类型、原始长度和connection generation。它不能自行声明CPU、SSD或Battery语义。

Registry结合`first-profile-v1.json`生成`QualifiedSourceCatalog`：

```swift
public struct QualifiedSourceCatalog: Sendable {
    public let generation: UInt64
    public let available: [QualifiedSource]
    public let unavailable: [SourceCapabilityRecord]
}
```

`QualifiedSource`只能通过Registry校验工厂创建，包含：

- 新的SourceID。
- provider和原始身份。
- 允许的encoding与单位证据。
- SensorKind、EvidenceLevel和mappingVersion。
- 当前generation。

`unsupported`、`permissionDenied`、`mappingUnknown`和`failed`保存在`SourceCapabilityRecord`，不伪装成可读取来源。重连必须创建新generation和SourceID；旧代响应直接拒绝。

WorkerClient不再直接实现供SamplingService使用的`SensorClient`。接口分为两层：

```swift
protocol SensorTransport: Sendable {
    func discoverRaw() async throws -> DiscoveredCatalog
    func readRaw(_ request: TransportReadRequest) async throws -> TransportReadBatch
    func close() async
}

public protocol SensorClient: Sendable {
    func discover() async throws -> QualifiedSourceCatalog
    func read(_ request: ReadRequest) async throws -> ReadBatch
    func close() async
}
```

`WorkerClient: SensorTransport`只负责线协议。`QualifiedSensorClient: SensorClient`持有SensorTransport和Registry，把SourceID映射到本代worker句柄，并把原始响应转换为经过身份检查的ReadBatch。测试替身实现公开SensorClient，不需要模拟worker帧。

## 6. 持久化接纳协议

### 6.1 不变量

继续保持：

1. SamplingService在启动硬件IO前预留该事件的最大记录数和字节数。
2. 无预留时不启动新读取；已有在途读取按既定规则完成或形成Gap。
3. MonitorEngine只在持久化队列确认接纳不可变批次后交换算法状态。
4. SQLite提交成功但ack丢失时只重试相同BatchID和相同payload hash。
5. 同ID不同payload立即触发`DB-INTEGRITY-010`。

### 6.2 不透明Lease

`QueueReservation`改名为`PersistenceLease`：

- 取消`Codable`和公开memberwise初始化器。
- 仅SessionPersistence实现能够创建。
- 对外只暴露调试需要的只读owner、generation和容量摘要；内部保存不可伪造的reservationID。
- enqueue/cancel均校验创建者、owner、generation、容量和消费状态。
- 复制同一值不能绕过单次消费；第二次消费得到固定完整性错误。

### 6.3 加工接口

```swift
public protocol ProcessingEngine: Sendable {
    func accept(_ batch: ReadBatch, lease: PersistenceLease) async throws -> ProcessingReceipt
    func advance(to timestamp: Timestamp, lease: PersistenceLease) async throws -> ProcessingReceipt
    func markGap(_ gap: Gap, lease: PersistenceLease) async throws -> ProcessingReceipt
    func snapshot(at timestamp: Timestamp) async -> Snapshot
    func realtime(_ request: HistoryRequest) async -> HistoryResult
}
```

`ProcessingReceipt`只包含BatchID、接纳记录数和提交后的snapshot generation。生产调用者不能取得已入队的完整`PersistenceBatch`并再次append。测试通过注入的SessionPersistence替身检查批次内容和顺序。

SessionPersistence是该模块唯一公开入口：

```swift
public protocol SessionPersistence: Sendable {
    func open(_ session: SessionMetadata) async throws
    func reserve(owner: PersistenceOwner, generation: UInt64,
                 maxRecords: Int, maxBytes: Int) async throws -> PersistenceLease
    func commit(_ batch: PersistenceBatch, using lease: PersistenceLease) async throws -> ProcessingReceipt
    func cancel(_ lease: PersistenceLease) async
    func query(_ request: HistoryRequest) async throws -> HistoryResult
    func prune(nowElapsedNS: Int64) async throws
    func closeAndDeleteSession() async throws
}
```

`PersistenceOwner`是`.request(RequestID)`、`.gap(GapID)`和`.watermark(WatermarkEventID)`的封闭枚举，不接受任意字符串。原`PersistenceQueue`、`StorageWriter`和`SampleStore`作为SessionPersistence模块内部协议保留；App和SamplingService不直接组合这些内部对象。MonitorEngine持有注入的SessionPersistence提交能力并调用commit，SamplingService只取得reserve/cancel能力，SessionCoordinator取得open/query/prune/close能力；三个调用方不能访问不属于自己的方法，能力视图由同一个SessionPersistence actor提供。

## 7. 统一展示状态

核心`Snapshot`保留可复核的来源、EMA、能力和观测时间事实。PresentationModel在MainActor上将其转换为：

```swift
public enum TemperatureValueState: Sendable, Equatable {
    case loading
    case live(valueC: Double, observedAt: Timestamp)
    case cached(valueC: Double, observedAt: Timestamp, reason: String)
    case stale(lastObservedAt: Timestamp?, reason: String)
    case unavailable(capability: Capability, reason: String)
}

public enum PresentationState: Sendable, Equatable {
    case running(RunningPresentationState)
    case fatal(FatalPresentationState)
}

public struct RunningPresentationState: Sendable, Equatable {
    public let asOf: Timestamp
    public let cpuPeriodMS: Int
    public let primaryCPU: TemperatureValueState
    public let sections: [TemperatureSectionState]
    public let chart: HistoryChartState
}

public struct FatalPresentationState: Sendable, Equatable {
    public let failure: MonitorFailure
    public let reportPath: String?
    public let exitDeadline: Timestamp
}

public struct TemperatureSectionState: Sendable, Equatable {
    public let id: String
    public let title: String
    public let rows: [TemperatureRowState]
}

public struct TemperatureRowState: Sendable, Equatable {
    public let sourceID: SourceID?
    public let metricID: String
    public let title: String
    public let evidence: EvidenceLevel
    public let value: TemperatureValueState
}

public enum HistoryChartState: Sendable, Equatable {
    case loading(previous: [HistorySeriesState])
    case ready(series: [HistorySeriesState], gaps: [Gap])
    case failed(MonitorFailure, previous: [HistorySeriesState])
}
```

`HistorySeriesState`包含SeriesID、display name、颜色token、选定HistoryLayer和有序HistoryPoint；不得携带驱动句柄或SQLite对象。为支持状态快照测试，MonitorFailure、Gap、HistoryPoint及上述展示类型实现Equatable。

规则：

- `live`来自本周期新成功读数形成的EMA。
- 第一次失败后可显示`cached`，但不得生成新数据样本。
- 超过`max(3×period, 2s)`变为`stale`并隐藏数值。
- 能力缺失进入`unavailable`，不与短时缓存混合。
- Fatal把整个PresentationState切换到`.fatal`，不能与live/cached等运行状态同时存在；所有表面进入同一退出流程。
- StatusItem、Popover、Dashboard和HistoryChart只绑定PresentationState，不重复计算过期时间或能力优先级。

UI布局继续使用现行MacMonitor紧凑分组、Stats来源列表和SwiftTempBar等宽数字方案。第三方视图的数据模型不得直接进入Core或Runtime。

## 8. 第三方代码来源契约

新增`docs/contracts/third-party-v1.json`，每项至少包含：

```json
{
  "upstream_project": "macmon",
  "upstream_commit": "6919d7781b6c55a6e3bedff83a210435837e1dfe",
  "upstream_path": "src_lib/sources.rs",
  "local_paths": ["Packages/TemperatureCore/Sources/SensorBridge/..."],
  "reuse_mode": "modified",
  "license": "MIT",
  "license_sha256": "...",
  "copyright_notice": "...",
  "modification_summary": "..."
}
```

`reuse_mode`固定为`copied`、`modified`或`method-only`。method-only不能产生从上游复制的源码文件。CI校验：

1. 每个声明为copied/modified的本地文件存在并有来源头注释。
2. 固定上游commit、路径和许可hash都不为空。
3. App中的`ThirdPartyNotices.md`包含所有copied/modified项目的完整许可和版权。
4. MacFanControl和Philip Turner当前只能为method-only。
5. 未登记的实质第三方代码使检查失败。

该文件记录实际进入产品的代码；现有research manifest继续记录研究时检查过的来源，两者不可互相替代。

## 9. 平台、构建与兼容资格

平台信息分成四个字段组：

| 字段组 | 含义 | 证据 |
|---|---|---|
| build_toolchain | Xcode、Swift、SDK版本 | 构建日志和`xcodebuild -version` |
| deployment_target | 二进制声明的最低macOS版本 | build settings及产物load command |
| runtime_profile | App允许运行的机型、最低OS和profile版本 | defaults/profile及启动检查 |
| qualified_combinations | 正式验收通过的机型、OS版本/build、签名和App SHA | W09/W10实机报告 |

现行用户要求的最低macOS 15.7.3暂不改变。完整Xcode可用后必须用`xcodebuild -showBuildSettings`和最终产物验证deployment target是否被工具链按预期接受。若工具链不能表达该patch级目标，须另行提出契约修订；不得自行放宽运行时要求，也不得把SDK 15.5解释为已支持所有15.7.3机器。

## 10. 测试与验收补充

新增`TC-UPSTREAM-BOUNDARY`测试组，至少包含：

1. 上游式旧值回退输入不得产生新Raw、EMA、count或source timestamp。
2. `PMU`、`PMU2`、`Tp*`、`Te*`等名称本身不能建立CPU、GPU、E/P域或物理核心语义。
3. 事件缺失、无法解析、NaN、Inf和低于绝对零度不得变成`0 °C`。
4. 12个profile成员与10个物理CPU核心并存时仍只显示热区来源，不生成Core 0…9。
5. 相同显示名、不同registryID的HID服务保持独立SourceID。
6. Release产物和符号检查确认没有SMC写入、风扇控制、root helper、测试fixture入口或外部CLI调用。
7. copied/modified代码缺登记、许可或ThirdPartyNotices内容时CI失败。

现有TC-SENSOR、TC-VALIDATE、TC-STORAGE、TC-UI和TC-RELEASE继续保留；新测试组用于明确开源复用边界，不重复替代这些产品测试。

## 11. 失败处理

- Registry拒绝来源时，必需CPU不足仍按`SENSOR-DISCOVER-001`；可选来源进入能力状态。
- 非法worker帧、未知协议枚举和身份冲突仍按`SENSOR-PROTOCOL-006`或`SENSOR-TAG-004`。
- Lease伪造、重复消费、owner/generation不符视为内部完整性错误，不通过重试掩盖。
- 展示状态转换出现互斥状态冲突时按`UI-RENDER-002`，同时保留原始核心快照用于诊断。
- 第三方来源门禁失败属于构建/合并失败，不在运行时容错。
- 平台配置不一致阻止RC资格测试和发布，不降级成“未验收但继续正式发布”。

## 12. 现行文档迁移范围

本规格经用户书面审阅通过后，实施计划阶段必须同步修改以下文件，不能只改`api-v1.swift`：

| 文件 | 必须同步的内容 |
|---|---|
| `docs/00-agent-handoff.md` | 新契约摘要、执行入口和未完成状态 |
| `docs/01-requirements.md` | 强类型状态、第三方登记和平台字段的规范要求 |
| `docs/02-architecture.md` | QualifiedSourceCatalog、SessionPersistence、PresentationState数据流 |
| `docs/03-sensor-acquisition.md` | 发现事实与资格化来源分离 |
| `docs/04-data-storage.md` | PersistenceLease、receipt和内部队列边界 |
| `docs/05-processing-pipeline.md` | ReadingOutcome及状态提交时序 |
| `docs/06-error-handling.md` | 新的契约校验失败映射 |
| `docs/07-native-ui.md` | 统一TemperatureValueState及共享组件 |
| `docs/08-component-design.md` | 模块/文件归属和公开/内部接口 |
| `docs/09-technology-selection.md` | 四类平台版本字段 |
| `docs/10-test-strategy.md` | TC-UPSTREAM-BOUNDARY及命令 |
| `docs/13-operations-distribution.md` | 第三方声明、发布manifest和平台资格 |
| `docs/15-decisions-and-corrections.md` | 新决策记录及被替代接口 |
| `docs/17-traceability.md` | 新需求到设计、任务、测试追踪 |
| `docs/19-reference-informed-design.md` | 可复制、改写、method-only边界 |
| `docs/20-feasibility-and-reuse.md` | 复用结论与剩余实机限制 |
| `docs/21-implementation-contracts.md` | 新唯一契约和迁移规则 |
| `docs/contracts/api-v1.swift` | 本规格第4至7节的类型和接口 |
| `docs/contracts/defaults-v1.json` | contract_version升级；参数值无授权不变 |
| `docs/contracts/third-party-v1.json` | 新增实际代码来源契约 |
| `docs/contracts/acceptance-v1.json` | 新/变更需求的任务与测试映射、hash |
| `docs/22-agent-implementation-plan.md` | W01/W02/W03/W04/W05/W07/W08/W09任务调整 |
| `docs/23-execution-task-breakdown.md` | 细粒度文件、测试、依赖和提交边界调整 |
| `docs/contracts/tasks-v1.json` | 与23一致的无环任务依赖 |
| `scripts/validate-handoff.py` | 新契约、来源清单、互斥状态和测试组校验 |

现行134个需求的业务范围不因本规格自动增加。若规范性要求需要新REQ编号，必须在实施计划阶段明确新增正文、测试和追踪，不复用退役的REQ-012或REQ-114。

## 13. 实施顺序约束

书面规格获批后，下一阶段先编写详细实施计划，再按项目Git流程执行。计划必须遵守：

1. 当前PR #4仍是完整文档基线；不从旧main建立功能分支。
2. 先完成W00门禁并由维护者合入，再从最新main创建功能分支。
3. 契约版本、规范文档、任务图和校验器在同一个文档变更中保持一致。
4. 产品实现采用测试先行；先写互斥状态、Lease单次消费、来源资格化和反错误复用测试。
5. 不把接口typecheck、模拟数据、CI或原型当作正式App硬件验收。

## 14. 验收标准

文档迁移完成时应满足：

- 后续Agent只读取00、01、21、22、23和11即可得到唯一当前方案，不依赖聊天记录或本规格中的历史讨论。
- 规范中不存在同时有效的旧`QueueReservation`和新`PersistenceLease`路径。
- 读取成功/失败、展示live/cached/stale/unavailable/fatal均为互斥状态。
- 原始发现结果不能绕过Registry进入加工和UI。
- copied/modified第三方代码具有机器可验证的来源和许可闭环。
- SDK、部署目标、运行时profile和正式兼容组合不会被混写。
- `validate-handoff.py`、Swift契约typecheck、SQLite DDL创建和全部文档链接通过。
- 工作树中的变更按项目Git规则提交，不覆盖或重写既有证据。

## 15. 已选择和未选择的方案

选择“收紧现有架构”：保留已经完整的采集、加工、存储、UI和生命周期路线，仅深化模块边界和机器门禁。这样能够复用上游成熟方法，同时保留本项目对来源身份、缺口、幂等、TTL和硬件证据的更严格要求。

未选择“完整照搬某一开源App”，因为没有一个固定上游同时满足本项目的12成员CPU定义、Raw/EMA双存储、72小时分层历史、一次性容量预留、worker隔离和证据边界。也未选择只改文字说明，因为当前公开值类型确实允许构造矛盾状态，单靠注释不能防止后续Agent误用。
