# 构件接口、文件边界与状态

更新：2026-09-17；C10可实现设计契约v1。规范类型和异步接口见[api-v1.swift](contracts/api-v1.swift)，协议不是已实现的代码。

## 目标目录与依赖

```text
Packages/TemperatureCore/Package.swift
  Sources/TemperatureCore/Models.swift
  Sources/TemperatureCore/Clock.swift
  Sources/TemperatureCore/Registry.swift
  Sources/TemperatureCore/MetricResolver.swift
  Sources/TemperatureCore/MonitorEngine.swift
  Sources/TemperatureCore/Processing/{EMA,Aggregation,Trend,RingBuffer}.swift
  Sources/TemperatureCore/Storage/{SQLiteStore,HistoryQuery,Retention}.swift
  Sources/TemperatureCore/Diagnostics/{MonitorFailure,ReportWriter}.swift
  Sources/CSQLite/{module.modulemap,shim.h}
  Sources/SensorRuntime/{WorkerClient,WorkerProtocol,SamplingService}.swift
  Sources/SensorBridge/{SensorBridge.c,include/SensorBridge.h}
  Sources/SensorWorker/main.swift
  Tests/TemperatureCoreTests/*Tests.swift
  Tests/SensorRuntimeTests/*Tests.swift
TemperatureMonitor.xcodeproj
App/{TemperatureMonitorApp,AppDelegate,SessionCoordinator}.swift
App/Presentation/{PresentationModel,StatusItemController,TemperaturePopover}.swift
App/Presentation/{TemperatureDashboard,TemperatureSourceRow,HistoryChartView,SettingsView,FatalView}.swift
App/Resources/{defaults-v1.json,first-profile-v1.json,Info.plist,ThirdPartyNotices.md}
UITests/TemperatureMonitorUITests.swift
```

TemperatureCore依赖Foundation及系统SQLite3；SensorRuntime依赖TemperatureCore，不直接导入IOKit；只有SensorBridge/SensorWorker接触驱动ABI。App依赖Core/Runtime，UI只读PresentationModel。测试替身直接实现SensorClient和MonitorClock，不运行真实硬件。

## API职责

| 接口/值类型 | 生产实现 | 前置与后置条件 |
|---|---|---|
| SensorClient.discover/read/close | WorkerClient | 同时最多一个worker请求；超时不能继续用原generation |
| MonitorClock.now/sleep | SystemClock、TestClock | elapsed包含睡眠；测试可前进时间，无真实等待 |
| PersistenceQueue.reserve/enqueue/cancel | BoundedPersistenceQueue actor | 预留绑定ownerID/generation/行数/字节；只能成功消费或取消一次 |
| ProcessingEngine.accept | MonitorEngine（注入PersistenceQueue） | ReadBatch和QueueReservation显式同传；方法内部入队成功才提交状态，返回值仅供测试/审计，调用者不得重复写入 |
| ProcessingEngine.advance | MonitorEngine | 安全watermark与QueueReservation同传；关闭窗口、入队并输出最终结果 |
| ProcessingEngine.markGap/snapshot/realtime | MonitorEngine | markGap以预留持久化；gap/缓存与真实样本分离；实时查询最多5分钟 |
| SampleStore.open/register/append | SQLiteStore | open接收完整SessionMetadata；append先处理batch内sources/definitions；写事务串行；同ID内容一致才幂等 |
| SampleStore.query/prune/closeAndDeleteSession | SQLiteStore/HistoryQuery/Retention | 查询有TTL、点数、时间预算；拿到锁才清理 |
| MonitorController.start/setCPUPeriod/history/stop | SessionCoordinator与MonitorEngine组合 | 唯一调度入口；历史路由5min内存，其余SQLite |
| MonitorController.snapshots | AsyncStream bufferingNewest(1) | UI掉帧可覆盖快照；不能丢持久化队列数据 |

`SourceDescriptor.evidence=referenceClassified`可以用于本版profile，界面详情明确开源分类；只有生产验证报告完成才升targetQualified。unknown不能加入正常CPU成员。原型状态decoded_mapping_unverified作为原始证据保留，不能改写它。

## 调度算法

三个逻辑日程CPU/SSD/Battery共用一个worker。目标时刻由上次**计划时刻**＋周期产生，结束后跳到第一个未来机会；不以完成时刻不断漂移，也不突发追赶。相同到期点依CPU、SSD、Battery；CPU一轮请求含整个固定集合。可选项缺失不安排日程。每次周期修改使对应nextDue=修改时刻＋新周期，已经在途的请求沿用旧周期。

读取开始前调用队列预留，预留失败则暂停，不启动新IO。预留对象绑定requestID、generation、最多512行和估算字节，只能由该请求消费或释放；成功响应把同一个QueueReservation显式传给MonitorEngine，由其通过注入的PersistenceQueue消费预留并原子完成“入队确认→状态交换”。水位和Gap事件同样先用唯一ownerID预留，不能绕开队列推进状态。每source响应包含开始/结束elapsed、请求周期、错误与freshness。超期机会计skipped；失败与漏采分开统计。请求ID/已处理ID集合仅需保存最近10秒及当前在途，不能无界增长。

worker同一连接的普通调用和重试串行。SMC KeyInfo按connectionGeneration＋FourCC缓存；重发现全部失效。关闭与读取不得并发，旧generation的异步结果不能修改新连接的状态。

## Worker协议v1

主程序以绝对路径启动`Contents/MacOS/SensorWorker`，不经shell。stdin/stdout各自是UTF-8一行JSON，最大1MiB；stderr只作有界诊断，持续异步排空避免管道阻塞。每帧必含`version=1, requestID, generation, command`。command仅允许discover/read/close；read带sourceIDs及periodMS；响应只对应一个请求，含sources或readings或failure。

样例请求：`{"version":1,"requestID":"r1","generation":1,"command":"read","sourceIDs":["source-uuid"],"periodMS":200}`。真实sourceID只能来自本generation discover；示例字符串不代表可运行传感器ID。

父进程传入session连续时钟基准的系统tick及timebase；worker用同一系统连续时钟生成elapsed，并保存真实wall time；公开Clock值仍为Timestamp。不能把不同进程各自启动后的相对时间直接相减。传感器单位转换在worker适配层，父进程再次验证finite及已知descriptor。协议中的大Int64按JSON整数编解码，不能经JavaScript Double桥接。

解码失败/超长帧/重复冲突ID → SENSOR-PROTOCOL-006；EOF/退出/超时使本请求失败。1秒读取、10秒发现、250ms终止宽限；每次恢复产生新generation及sourceID、definitionVersion、segment。来源切换不维持旧曲线连续性。

## 生命周期与可测试性

App单实例锁成功后才创建数据库和worker。stop幂等，任何状态调用都不启动新工作。sleep先暂停日程、停止worker、终结水位；wake重新发现、分段、立即TTL清理，再运行。软件模拟时钟用于72小时TTL和gap验收，不能替代实际睡眠/签名后的硬件验证。

实现顺序、每个目标文件和验收向量见[22](22-agent-implementation-plan.md)。状态边界不能以“在UI里临时判断”绕过这些服务接口。
