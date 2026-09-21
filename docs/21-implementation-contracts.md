# 实施契约v1族：修订2唯一参数、类型与存储定义

更新：2026-09-21；contract revision 2。本文连同01～13是当前实现依据，[已批准设计规格](superpowers/specs/2026-09-21-contract-hardening-and-upstream-reuse-design.md)解释本次收紧原因。历史研究和旧实测报告只作证据，不能恢复被替代的接口或退役需求。

## 机器可读交付物

| 文件 | 权威内容 | 使用方式 |
|---|---|---|
| [defaults-v1.json](contracts/defaults-v1.json) | `contract_version=2`及全部周期、算法、容量和截止时间 | W01加载并拒绝其他修订；数值不得在别处重定义 |
| [first-profile-v1.json](contracts/first-profile-v1.json) | 首机型、固定成员、可选来源优先级和证据状态 | W02资格化来源；不是正式App兼容报告 |
| [api-v1.swift](contracts/api-v1.swift) | 修订2值类型、互斥状态和服务接口 | W01拆入08所列文件；通过typecheck不等于产品实现 |
| [schema-v1.sql](contracts/schema-v1.sql) | SQLite DDL、键、索引、视图与PRAGMA | 本次修订不改变存储schema；W03按04实现事务 |
| [third-party-v1.json](contracts/third-party-v1.json) | 实际复制/修改代码、许可和method-only边界 | 文档校验及W08通知文件门禁 |
| [acceptance-v1.json](contracts/acceptance-v1.json) | 134项REQ到设计、任务和测试的映射 | W11逐项附证据；012/114保持retired |
| [tasks-v1.json](contracts/tasks-v1.json) | T00.1～T11.3依赖图及W归属 | 23逐任务执行；依赖未因修订2改变 |

文件名中的v1表示本产品第一代契约族；JSON中的`contract_version=2`表示本次不向旧公开接口兼容的修订。生产实现只能接受修订2，不得同时保留旧路径。

## 强类型身份

`SessionID`、`SourceID`、`SeriesID`、`RequestID`、`BatchID`、`GapID`和`WatermarkEventID`是不同Swift类型，序列化为小写标准UUID。解码和公开构造必须验证规范格式；测试使用固定UUID，禁止用`source-0`等自由文本代替。

`MetricID`是稳定可见角色标识，使用小写点分格式，例如`cpu.zone.max`。它不是实例UUID。数据库仍保存TEXT，由存储适配器在边界转换。

- 规格中的sensor_id对应SourceID；派生序列使用独立SeriesID和MetricID。
- 重连创建新generation及SourceID；定义成员或语义变化创建新SeriesID并递增definitionVersion。
- segment只表示同一定义内的连续数据段。
- Sample ID仍由会话UUID和单调序列组成，不能与其他ID互换。

## 来源发现与资格化

SensorWorker只通过内部`SensorTransport`交付`DiscoveredCatalog`。DiscoveredSource只包含provider、rawKey、registryID、底层encoding、长度和transport handle等可观察事实，不声明CPU/SSD/Battery语义。

Registry结合profile生成`QualifiedSourceCatalog`：

- `available`只含通过机型、成员、encoding、长度、单位、证据和generation校验的QualifiedSource。
- `unavailable`保存unsupported、permissionDenied、mappingUnknown或failed及原因。
- 只有`QualifiedSensorClient: SensorClient`对SamplingService公开；WorkerClient不再直接实现公开SensorClient。
- QualifiedSensorClient负责SourceID与本代transport handle映射；旧generation、未知handle和身份冲突在进入算法前拒绝。
- 相同显示名但不同registryID保持不同来源；名称、前缀和数组序号不能建立物理核心、E/P域或Package含义。

## 互斥读取与错误类型

Reading由SourceID、开始/结束Timestamp和`ReadingOutcome`组成：

- success同时携带valueC、可选source timestamp和Freshness。
- failure只携带MonitorFailure。
- 类型系统禁止成功值与失败同时存在，也禁止两者皆无。

`SeriesFormula`、`SegmentReason`和`MonitorErrorCode`均为封闭枚举。协议解码遇到未知枚举、无效UUID或错误generation按06映射为结构性失败，不能转成自由字符串继续运行。底层未识别错误只进入`underlyingCode`。

成功温度还必须满足有限数、不得低于绝对零度、profile encoding和单位证据。重复的有限数值是有效观测；失败、缺事件或解析错误不能生成0°C或复写旧值。

## 持久化接纳与状态提交

SessionPersistence是同一个actor实现，并向不同调用者提供三个窄能力视图：

| 调用者 | 能力 | 禁止访问 |
|---|---|---|
| SamplingService | reserve/cancel | commit、query、会话关闭 |
| MonitorEngine | commit | reserve、会话生命周期 |
| SessionCoordinator/HistoryQuery | open/query/prune/close | 构造或消费Lease |

`PersistenceLease`由SessionPersistence内部创建，取消Codable和公开构造；它绑定PersistenceOwner、generation、最大记录数和最大字节。PersistenceOwner只能是request、gap或watermark三种强类型事件。实现以内部reservation UUID校验创建者、容量和消费状态；值复制不能绕过单次消费。

固定时序：

1. SamplingService在启动硬件IO或推进水位/Gap前取得Lease。
2. 无Lease不启动新IO；预留覆盖该事件的最大逻辑行和字节。
3. MonitorEngine在临时状态上产生不可变PersistenceBatch。
4. MonitorEngine用同一Lease调用commit。
5. SessionPersistence确认队列接纳后返回ProcessingReceipt。
6. MonitorEngine收到receipt后才交换算法状态和发布快照。
7. 失败时丢弃临时状态并cancel尚未消费的Lease。

ProcessingEngine的变更方法只返回ProcessingReceipt，包含BatchID、接纳记录数和snapshot generation。生产调用者不能获得已入队完整批次再写一次；测试通过注入的持久化替身观察批次内容。

StorageWriter和SQLite store是SessionPersistence内部实现。SQLite提交成功但ack丢失时仅以相同BatchID和相同payload hash重试；同ID不同内容继续触发`DB-INTEGRITY-010`。

## 时间、样本与存储映射

- Timestamp.elapsedNS使用父会话统一mach continuous基准；wallUnixNS只用于显示和诊断。
- 系统Clock和worker共享父进程基准；不能用各自启动时刻冒充同一elapsed原点。
- `Sample.timestamp.elapsedNS`写elapsed_ns，wallUnixNS写wall_ns。
- QualifiedSource写sources；SeriesDefinition写series和series_members。
- `Sample.memberSampleIDs`写sample_members；EMA和其输入Sample共用sampleID但存不同表。
- Bucket.latestSampleID只作证据，不跨TTL建立外键。
- elapsed为Int64非负；clock换算使用整数商余数/宽乘防溢出。
- 无来源更新时间保持nil/NULL，不填应用读取完成时间冒充硬件测量时间。

schema-v1.sql的user_version仍为1，因为本次只收紧Swift/API和文档契约，没有改变表、列、键或SQLite语义。

## 核心快照与展示状态

Snapshot包含定义、EMA事实、最后成功时间、最后失败、能力、Gap ID、CPU周期和snapshot generation；不再使用可互相矛盾的cached/stale布尔组合。

PresentationModel在MainActor上唯一负责把Snapshot/HistoryResult转换为`PresentationState`：

- `.running`包含CPU周期、CPU主值、分组行和HistoryChartState。
- `.fatal`只包含固定MonitorFailure、报告路径和退出截止时间，不能与运行状态并存。
- TemperatureValueState为loading、live、cached、stale或unavailable。
- HistoryChartState为loading、ready或failed，不能同时声明loading和failed。
- StatusItem、Popover、Dashboard和Chart只绑定PresentationState，不自行计算TTL、能力优先级或Fatal。

第一次读取失败可以显示cached，但不生成新Raw/EMA/count；距最后成功点超过`max(3×period, 2s)`进入stale并隐藏数值。

## 参数、profile与变更

五档、默认200ms、SSD/Battery周期、Raw/EMA保留、分层TTL和所有容量参数保持defaults中的既定值。tau、趋势、容量、截止时间和布局仍是未声称性能调优的工程参数。

`ring_capacity_per_series=8192`分别适用于Raw和EMA；`max_active_series=32`包含派生序列。每个事件最多预留512逻辑行；发现上限256。遇到实测不达标先记录失败和Issue，再版本化修订，不能静默减少CPU成员、丢有效数据或降低采样档位。

首profile只接受12个固定CPU键、`flt `及4字节；通用sp78解码存在不等于profile允许编码变化。未知机型不自动套表。

## 第三方来源契约

research source manifest记录“研究时检查过什么”；third-party-v1.json记录“实际有哪些代码进入仓库或产品”，二者不能替代。

每个copied/modified条目必须包含固定上游commit、路径、本地文件、reuse mode、许可、许可hash、notice和修改说明。当前原型SensorBridge登记为macmon modified；R04和R07只能method-only。W08导入新的MIT代码时先更新该合同和ThirdPartyNotices，再提交源文件。

## 平台字段

发布和资格报告分别保存：

- build_toolchain：Xcode、Swift和SDK。
- deployment_target：构建设置及最终二进制load command。
- runtime_profile：机型、最低OS和profile版本。
- qualified_combinations：正式App SHA、签名、机型、OS版本/build及通过用例。

最低运行要求15.7.3保持不变；Xcode/SDK可构建不等于目标组合已通过正式App实机验收。

## 确定的失败与开发边界

不支持机型或关键CPU定义不足按06停止；可选SSD/Battery保留明确状态。DB、算法、关键UI和持久化完整性失败按固定错误码处理。开始实现无需重新选择语言、数据库、进程模型、主指标或实时路径。

遇到证据与profile冲突时记录差异和Issue并完成其他独立任务，不得把上游/源码推断升级为正式目标App实测。

## 文档自检入口

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-contract -typecheck docs/contracts/api-v1.swift
sqlite3 ':memory:' < docs/contracts/schema-v1.sql
```

这些命令只验证文档契约、Swift类型和DDL；不证明生产App、UI、硬件或发布配置已实现。
