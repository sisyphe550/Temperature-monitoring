# 构件接口、文件边界与状态

更新：2026-09-21；实施契约v1族修订2。规范类型和异步接口见[api-v1.swift](contracts/api-v1.swift)，协议是生产实现必须满足的设计契约，不是已完成代码。

## 目标目录与依赖

```text
Packages/TemperatureCore/Package.swift
  THIRD_PARTY_NOTICES.md
  Sources/TemperatureCore/Contracts/{Identifiers,SensorTypes,PersistenceTypes,PresentationTypes}.swift
  Sources/TemperatureCore/Configuration.swift
  Sources/TemperatureCore/Clock.swift
  Sources/TemperatureCore/SessionLock.swift
  Sources/TemperatureCore/Registry.swift
  Sources/TemperatureCore/QualifiedSensorClient.swift
  Sources/TemperatureCore/MetricResolver.swift
  Sources/TemperatureCore/MonitorEngine.swift
  Sources/TemperatureCore/Persistence/SessionPersistence.swift
  Sources/TemperatureCore/Persistence/{BoundedQueue,StorageWriter}.swift
  Sources/TemperatureCore/Processing/{EMA,Aggregation,Trend,RingBuffer}.swift
  Sources/TemperatureCore/Storage/{SQLiteStore,HistoryQuery,Retention,SessionCleanup}.swift
  Sources/TemperatureCore/Diagnostics/{MonitorFailure,RetryPolicy,DiagnosticLogger,ReportWriter}.swift
  Sources/CSQLite/{module.modulemap,shim.h}
  Sources/SensorRuntime/{SensorTransport,WorkerClient,WorkerProtocol,SamplingService}.swift
  Sources/SensorBridge/{SensorBridge.c,include/SensorBridge.h}
  Sources/SensorWorker/main.swift
  Tests/TemperatureCoreTests/*Tests.swift
  Tests/SensorRuntimeTests/*Tests.swift
TemperatureMonitor.xcodeproj
App/{TemperatureMonitorApp,AppDelegate,SessionCoordinator}.swift
App/Presentation/{PresentationModel,PresentationState,StatusItemController,TemperaturePopover}.swift
App/Presentation/{TemperatureDashboard,TemperatureSourceRow,HistoryChartModel,HistoryChartView,SettingsView,FatalView}.swift
App/Resources/{defaults-v1.json,first-profile-v1.json,Info.plist,ThirdPartyNotices.md}
UITests/TemperatureMonitorUITests.swift
```

TemperatureCore依赖Foundation及系统SQLite3。SensorRuntime依赖TemperatureCore但不直接导入IOKit；只有SensorBridge和SensorWorker接触驱动ABI。App依赖Core/Runtime，UI只读`PresentationState`。测试替身分别实现`SensorTransport`、`SensorClient`、持久化窄能力和`MonitorClock`，不运行真实硬件。

依赖方向固定为：

```text
SensorBridge -> SensorWorker/WorkerClient(SensorTransport)
SensorTransport -> Registry -> QualifiedSensorClient(SensorClient)
SensorClient -> SamplingService -> PersistenceReservationCapability
SamplingService -> MonitorEngine -> PersistenceCommitCapability
SessionCoordinator -> SessionStoreCapability -> SessionPersistence actor
MonitorEngine/Snapshot + HistoryResult -> PresentationModel -> PresentationState -> Views
```

原始worker结果不能绕过Registry进入SamplingService、加工、存储或UI；视图不能反向访问SensorClient、SessionPersistence或SQLite。

## 接口职责

| 接口/值类型 | 生产实现 | 前置与后置条件 |
|---|---|---|
| SensorTransport.discoverRaw/readRaw/close | WorkerClient | 包内接口；交付底层事实和transport handle；同时最多一个worker请求；超时后不得继续使用原generation |
| SourceRegistry.qualify | Registry | 结合profile验证机型、成员、编码、单位、证据与generation；输出QualifiedSourceCatalog，未知项进入unavailable而非猜测 |
| SensorClient.discover/read/close | QualifiedSensorClient | 唯一公开传感器客户端；只接受SourceID；把handle映射、旧generation和身份冲突拦在算法之前 |
| MonitorClock.now/sleep | SystemClock、TestClock | elapsed包含睡眠；测试可前进时间，无真实等待 |
| PersistenceReservationCapability.reserve/cancel | SessionPersistence actor | Lease绑定PersistenceOwner、generation、行数和字节；无Lease不启动IO或状态事件；只能消费或取消一次 |
| PersistenceCommitCapability.commit | SessionPersistence actor | 校验Lease owner/generation/容量/消费状态；接纳不可变PersistenceBatch后返回ProcessingReceipt |
| ProcessingEngine.accept/advance/markGap | MonitorEngine | ReadBatch与同一PersistenceLease显式同传；只在收到receipt后交换算法状态和发布新generation |
| ProcessingEngine.snapshot/realtime | MonitorEngine | Snapshot分离EMA事实、能力、最后成功/失败与Gap；实时查询最多5分钟 |
| SessionStoreCapability.open/query/prune/closeAndDeleteSession | SessionPersistence actor | SessionCoordinator/HistoryQuery持有；不能构造或消费Lease；清理必须持有实例锁和合法marker |
| MonitorController.start/setCPUPeriod/history/stop | SessionCoordinator与MonitorEngine组合 | 唯一调度入口；历史路由5分钟内存，其余SQLite；stop幂等 |
| MonitorController.snapshots | AsyncStream bufferingNewest(1) | UI掉帧可覆盖展示快照；不能丢持久化队列数据 |
| PresentationModel | MainActor对象 | Snapshot/HistoryResult到PresentationState的唯一转换器；Fatal进入后不再发布running |

`DiscoveredSource`只含可观察事实；`QualifiedSource`才具有SourceID、SensorKind、单位和EvidenceLevel。`referenceClassified`可以用于首版profile，但界面详情必须注明来自开源分类；只有正式产品验证完成才升为`targetQualified`。`unknown`不能进入正常CPU成员、采样请求或展示序列。原型的`decoded_mapping_unverified`状态作为历史证据保留，不能回写改名。

## 强类型事件与持久化所有权

SessionID、SourceID、SeriesID、RequestID、BatchID、GapID和WatermarkEventID是不同类型，均使用规范小写UUID；MetricID使用小写点分格式。不同ID不可用String临时互换。`SeriesFormula`、`SegmentReason`、`MonitorErrorCode`和展示状态均为封闭枚举。

`PersistenceLease`没有公开构造器且不编码。SessionPersistence内部保存reservation UUID、owner、generation、容量和消费状态；复制Swift值不能增加使用次数。固定交互如下：

1. SamplingService用`PersistenceOwner.request(RequestID)`在启动硬件IO前预留；Gap和watermark使用各自强类型owner。
2. 预留失败暂停新工作，不启动“读完再想办法写”的旁路。
3. MonitorEngine在临时状态中校验ReadingOutcome、计算Raw/EMA/聚合/趋势并生成不可变PersistenceBatch。
4. MonitorEngine用同一Lease提交；SessionPersistence接纳后返回ProcessingReceipt。
5. MonitorEngine核对receipt的BatchID、记录数和snapshotGeneration后才交换临时状态并发布Snapshot。
6. 计算或提交失败时丢弃临时状态并取消仍未消费的Lease；错误owner、generation、容量、伪造或重复消费均为`DB-INTEGRITY-010`。

BoundedQueue、StorageWriter和SQLiteStore是SessionPersistence内部构件，App和MonitorEngine不能单独拼装它们。SQLite提交成功但ack丢失只允许相同BatchID和相同payload hash幂等重试；生产接口不把已接纳完整批次返回给调用者。

## 调度算法

三个逻辑日程CPU/SSD/Battery共用一个worker。目标时刻由上次**计划时刻**加周期产生，结束后跳到第一个未来机会；不以完成时刻不断漂移，也不突发追赶。相同到期点依CPU、SSD、Battery；CPU一轮请求含整个固定集合。可选项缺失不安排日程。每次周期修改使对应`nextDue=修改时刻+新周期`，已经在途的请求沿用旧周期。

读取前按该事件最大512行和估算字节取得Lease。每个Reading通过`ReadingOutcome.success`或`.failure`表达，类型上不能同时有值和错误。超期机会计skipped；失败与漏采分开统计。RequestID和已处理集合只保留最近10秒及当前在途，不能无界增长。

worker同一连接的普通调用和重试串行。SMC KeyInfo按connectionGeneration和FourCC缓存；重发现全部失效。关闭与读取不得并发，旧generation的异步结果不能修改新连接状态。

## Worker协议v1

主程序以绝对路径启动`Contents/MacOS/SensorWorker`，不经shell。stdin/stdout各自是UTF-8一行JSON，最大1MiB；stderr只作有界诊断，持续异步排空避免管道阻塞。每帧必含`version=1`、规范UUID requestID、generation和command。command只允许discover/read/close；read带transport handles及periodMS；响应只对应一个请求，含sources、readings或结构化failure。

真实SourceID由Registry生成，worker既不接收也不创建SourceID。父进程传入session连续时钟基准的系统tick及timebase；worker用同一系统连续时钟生成elapsed，并保存真实wall time。不能把不同进程各自启动后的相对时间直接相减。传感器单位转换在worker适配层，QualifiedSensorClient和算法边界再次验证有限数及已资格化descriptor。协议中的大Int64按JSON整数编解码，不能经JavaScript Double桥接。

未知枚举、无效UUID、解码失败、超长帧、重复冲突ID或错误generation触发06中的结构性失败；EOF、退出或超时使本请求失败。1秒读取、10秒发现、250ms终止宽限；每次恢复产生新generation及SourceID、definitionVersion、segment。来源切换不维持旧曲线连续性。

## 展示状态边界

PresentationModel只接收核心Snapshot和HistoryResult：

- PresentationState只能是running或fatal；运行态包含CPU周期、主值、分组和HistoryChartState。
- TemperatureValueState只能是loading/live/cached/stale/unavailable；cached不得生成新样本，stale隐藏数值。
- HistoryChartState只能是loading/ready/failed；previous只是保留显示，不代表查询成功。
- StatusItem、Popover、Dashboard和Chart共用同一状态，不得各自实现TTL、能力映射、Fatal或来源优先级。

## 生命周期与可测试性

App单实例锁成功后才创建数据库和worker。stop幂等，停止后任何状态调用都不启动新工作。sleep先暂停日程、停止worker并终结水位；wake重新发现、资格化、分段、立即TTL清理，再运行。软件模拟时钟用于72小时TTL和gap验收，不能替代实际睡眠、签名后的正式App硬件验证。

实现顺序、每个目标文件和验收向量见[22](22-agent-implementation-plan.md)。状态边界不能以“在UI里临时判断”、裸String ID、直接worker结果或直接SQLite调用绕过这些服务接口。
