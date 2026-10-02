# 2026-10-02 产品审查：48cd967d

## 结论

**当前可在目标 Mac 上构建、启动和显示真实 CPU 温度；完整历史、故障恢复、休眠恢复和资源清理存在缺陷，不能判定为已经完整交付且可稳定常驻使用。**

CPU 温度采集的可行性已由本次正式 Release App 实机读数验证。1731 个批次的主指标均来自同批全部 12 个来源的 Raw 最大值，再独立计算 EMA，成员关联与数值检查均无反例。当前主要阻碍来自软件集成与状态处理，修复可以沿用已有传感器路线。

本次建立 **10 个缺陷 Issue，其中 7 个 blocking**；新增 7 项针对性回归测试全部复现缺陷。该数量是审查问题数，不是项目完成率。

## 范围与执行边界

- 审查源码：`48cd967d835e5c9f2ad2f191d97eb32a92623bcd`；分支 `feature/w11-acceptance`。
- 环境：Mac16,13（M4 Air）；macOS 15.7.3 / 24G419；Xcode **26.3 / 17C529**；Swift 6.2.4；arm64。SDK 26.2 与 Xcode 应用版本区分记录。
- 用户使用范围：仅本机自用。**≥72/73h 实机耐久、Developer ID 公证、对外分发不作为未完成缺陷。**不要求多型号认证。
- 72h 历史范围仍按现行需求审查；它与“连续运行 72h 测试”是不同要求。分层历史缺陷已在约 10.5min 实机和短时确定性测试中复现。
- CPU 物理逐核心温度/core_id 和物理 Package 温度保证已退役，不恢复、不列缺陷。
- 原始未追踪 `build/` 和 `6800e170...dry/` 保留；未修改生产源码、原有测试、既有需求/验收/历史证据，也未提交、push、合并或修改 PR 状态。
- 从 `git archive HEAD` 建临时副本进行编译、测试；7 项审查测试仅在临时副本执行，本目录保存副本供修复使用。
- 只对本次启动的正式 App 执行正常退出；没有强制系统休眠、杀死用户其他进程或更改安全设置。GitHub Issue 按 AGENTS.md 和 Git 流程登记。

## 验证结果

| 检查 | 当前结果 | 能说明的范围 |
| --- | --- | --- |
| 原有 Swift 核心测试 | **244 项 / 31 suites 通过** | 已覆盖测试的行为成立，不能替代生产 App 链路 |
| 核心行覆盖率 | **5945/6947 = 85.58%** | TemperatureCore + SensorRuntime Swift；不含 App UI、C bridge、worker 入口 |
| 新增针对性回归 | **7/7 失败，复现预期缺陷** | 时钟、水位、唤醒 ID、TTL、超时恢复、CPU 完整成员、写入失败状态 |
| 新鲜 Release 构建 | **BUILD SUCCEEDED** | 使用项目 build-app.sh，未使用用户已有 build 产物 |
| Release ad-hoc 签名检查 | **通过** | codesign --verify --deep --strict |
| 真实 App CPU 读取 | **通过** | 12 个热区和主指标有真实读数，屏幕观察约 38–45°C，未使用 UI fixture |
| 真实 App 周期切换 | **200→1000ms 成功** | UI 选项包含五档；本次实际操作两档，SQLite period_ms 验证切换 |
| SQLite 数据链 | **22503 Raw + 22503 EMA，1731 committed batches** | 每个主样本 12 个成员；主 Raw=同批 Raw max，0 个不符 |
| 真实历史图 | **失败** | 默认持续 loading；手动选择 1h、5min 均空 |
| 分层聚合 | **失败，aggregates=0** | 样本 elapsed 0.480736375s 到 629.877935125s |
| 正常退出 | **进程退出通过，会话删除失败** | 没有 App/SensorWorker 残留；monitor.sqlite 仍在 |
| 现有 XCUITest | **首轮 7 通过、1 失败、1 skip；失败单项重跑通过** | testCPUPeriodPicker 等待窗口超时后单独重跑成功，测试存在不稳定；用例全部 fixture |
| 上游边界扫描及反例门禁 | **通过** | 已登记代码/资源和禁止行为的机械校验 |
| 资格报告格式测试 | **8 checks 通过** | 报告格式和脚本，不证明运行时功能完整 |
| 文档交接检查 | **通过** | 134 编号、132 active、2 retired、12 W、50 tasks、20 TC、revision 2 |
| 完整产品验收门禁 | **失败，8 项元验收 pending** | REQ-099..106；不能把 123/132 绑定数当完成率 |

### 界面测试失败的限定

按 CI 命令禁用签名时，runner 在连接前 SIGKILL，签名检查报 `CSSMERR_TP_NOT_TRUSTED`。复用目录改为 ad-hoc 签名时出现 runner 插件链接 `errno=1`。使用新的临时 DerivedData 和项目默认 ad-hoc 签名后，9 个 UI 用例可运行；仅周期用例等待窗口失败，单独重跑成功。此过程没有更改项目源文件或系统安全设置。保留全部日志，不把第一次基础设施故障误判为 App 崩溃，也不把重跑成功改写为完整首轮通过。

### 核心测试为何没发现真实问题

现有测试主要使用同一 TestClock、零耗时 mock、直接调用 controller 生命周期、手动调用水位/清理、预设 Qualified catalog；它们绕过真实 App 时钟、实际 IO 开始时间、系统通知、Registry 可选能力接线和生产周期调度。UI 用例通过 `--ui-fixture` 启动，历史用例仅检查控件存在（`UITests/TemperatureMonitorUITests.swift:40-45,84-91`）。因此历史空图、可选来源缺失及错误恢复失联可以与现有测试通过同时发生。

## 功能完成度

| 方面 | 判断 | 后续处理 |
| --- | --- | --- |
| CPU 只读 SMC 采集、12 热区、Raw max→EMA | 本机正常路径已实测可用 | 保留现有采集路线；补完整成员及故障路径 |
| 原生菜单栏、Dashboard、设置、周期选择 | 基础实现已存在且可启动 | 修复真实历史和状态提示；无需重新设计整个前端 |
| 5min 内存历史 | App 集成失败 | 共享时钟、首轮加载、自动刷新、全范围降采样 |
| 1h/24h/72h SQLite 历史 | 水位和时钟阻断 | 修复分层聚合与查询，短时测试即可验证主要逻辑 |
| SSD/Battery | 生产链尚未接通 | 电池 TB1T 本机已可读；SSD 当前报告不足以认定物理不可用 |
| 休眠与采样故障恢复 | 未完成正确接线，控制器路径有实证错误 | 请求 ID、跨进程时钟、通知和重试一并修复 |
| 数据寿命、队列和退出 | 实机/测试/源码均有缺口 | 定期 TTL、有界去重、等待关停和删除会话 |
| 错误码、日志、Fatal | 组件存在，生产路径接线不完整 | 运行错误进入统一通道，并执行到期退出 |
| 柱图、多来源曲线、时间轴、缓存状态提示 | 现行 UI 需求有缺口 | 保留则补实现；不要静默按“已完成”验收 |
| Git/文档/验收 | 流程和门禁存在，状态描述过期 | 修复后刷新当前状态和新证据，不回写旧报告 |

## 缺陷清单

P1：阻碍正确、持续监测或核心历史交付。P2：正常退出/可选功能/图表完整性问题。实测、模拟回归、源码推导在每项内分别注明。

### R01 [P1] 正式 App 历史查询使用新时钟，且首轮选择来源后未加载历史 — [Issue #27](https://github.com/sisyphe550/Temperature-monitoring/issues/27)

**证据与影响：** 本机正式 Release App 持续显示真实 CPU 温度；默认历史一直“正在加载历史…”，切换 1 小时和 5 分钟均“本会话暂无数据”。reloadHistory 每次 new SystemClock，asOfElapsedNS 接近 0，过滤了已有会话样本；首次 reload 发生在 selectedSeriesIDs 设置之前，此后没有自动刷新。临时测试 historyRequestWithFreshSystemClockRetainsCurrentSessionSample：正确时钟可查询 1 点，新时钟查询 0 点。App 与 worker 也分别创建 elapsed origin，重启 worker 后存在样本时间倒退风险（源码判断，本次没有杀死真实 worker）。

**源码：** [App/AppSessionRuntime.swift:57](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppSessionRuntime.swift#L57)；[App/AppSessionRuntime.swift:118-125](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppSessionRuntime.swift#L118)；[App/AppSessionRuntime.swift:143-156](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppSessionRuntime.swift#L143)；[Packages/TemperatureCore/Sources/TemperatureCore/Clock.swift:15-21](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Clock.swift#L15)；[Packages/TemperatureCore/Sources/SensorWorker/WorkerClock.swift:8-14](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorWorker/WorkerClock.swift#L8)。

**修复方向：** 让调度、worker 样本、Snapshot 和 HistoryRequest 使用同一会话时间基准；worker 重建不重置会话 elapsed。首次有效 Snapshot 设置主 series 后加载历史，之后按有界频率刷新，并取消过时查询。

**验收：** 非 fixture Release 启动后 5 分钟图出现真实 EMA 并继续移动；切换 1h/24h 查询能出现已关闭聚合；重建 worker 后时间仍递增。时钟回归测试转绿。

**关联：** REQ-006/008/047/050-053/129。

### R02 [P1] 在途采样注册和注销时间不一致，真实采样后聚合水位冻结 — [Issue #28](https://github.com/sisyphe550/Temperature-monitoring/issues/28)

**证据与影响：** willRead 注册计划开始时间，handleRead 注销各传感器实际开始时间，AggregationEngine 只按整数精确相等移除。实际时间不同，最早注册永久残留。真实 App 运行 629.88s，22503 条 Raw、22503 条 EMA、1731 个已提交批次，aggregates=0。临时测试 completedReadReleasesPlannedWatermarkRegistration：完成请求后 now=2s，水位仍为 999999999ns。读取抛错路径也未注销注册。

**源码：** [Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift:39-40](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift#L39)；[Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift:124-149](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift#L124)；[Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:246-270](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift#L246)；[Packages/TemperatureCore/Sources/TemperatureCore/Processing/Aggregation.swift:154-163](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Processing/Aggregation.swift#L154)；[Packages/TemperatureCore/Sources/TemperatureCore/Processing/SafeWatermark.swift:11-13](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Processing/SafeWatermark.swift#L11)。

**修复方向：** 按 RequestID 保存与清理同一次在途登记；success、failure、stale generation、cancel、sleep/stop 所有终止路径均清理。实际读取时间继续用于样本和算法。

**验收：** 读取开始比计划晚 1ms 且批次包含 12 个不同开始时间时，完成后水位可推进；错误/取消不留下阻塞。正式 App 每秒产生聚合，10s/60s 父层也按时关闭。

**关联：** REQ-025-030/048/051-053。

### R03 [P1] 一次传感器超时后采样永久停止，运行错误未进入重试和 Fatal 流程 — [Issue #29](https://github.com/sisyphe550/Temperature-monitoring/issues/29)

**证据与影响：** 超时或协议错误清空 Qualified catalog；采样循环只取消 lease 并等待下一周期，不 discover/retry，后续请求全部 notDiscovered。临时一次性超时 transport 已准备从第二次读恢复，但 2s/10 个周期后实际 transport readCount=1、Raw=0。ProcessingCoordinator 吞掉加工/水位错误，正式 App 不消费 lastAcceptFailure；ErrorCoordinator、RetryPolicy、DiagnosticLogger、ReportWriter 未接入生产运行路径。FatalView 只显示倒计时，没有到期退出动作；cached/live 文本也无区别。

**源码：** [Packages/TemperatureCore/Sources/TemperatureCore/QualifiedSensorClient.swift:104-118](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/QualifiedSensorClient.swift#L104)；[Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:259-270](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift#L259)；[Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift:137-143](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift#L137)；[Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift:191-200](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift#L191)；[App/AppSessionRuntime.swift:119-139](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppSessionRuntime.swift#L119)；[App/Presentation/FatalView.swift:25-52](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/Presentation/FatalView.swift#L25)。

**修复方向：** 把 I/O、单项 CPU 失败、加工和存储故障接入统一有界重试/降级/Fatal 通道。失效连接重新 discover 并资格验证；关键 CPU 失败不能静默忽略；日志/报告保留真实错误码。Fatal 倒计时到期执行统一关停。缓存值明确显示缓存状态。

**验收：** 一次超时后恢复真实新样本；连续失败按配置次数结束并显示真实错误码、日志/报告；Fatal 到期实际退出；可选源故障不终止健康 CPU。

**关联：** REQ-054-084/134。

### R04 [P1] 正式 App 未绑定系统休眠通知，恢复路径复用 RequestID 并拒绝新样本 — [Issue #30](https://github.com/sisyphe550/Temperature-monitoring/issues/30)

**证据与影响：** App 没有 NSWorkspace willSleep/didWake 通知接线。独立调用 controller suspend/resume 后，SamplingService.start 重置 ordinal=1，而 MonitorEngine 保留本会话 processedRequests。临时 firstReadAfterWakeIsAcceptedWithUniqueRequestIdentity：醒后第一批报 databaseIntegrity/request_content_mismatch，Raw 从 1 条仍为 1 条。这里是控制器模拟验证，不声称本次对用户电脑执行了系统休眠。

**源码：** [App/SessionCoordinator.swift:65-76](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/SessionCoordinator.swift#L65)；[Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:138](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift#L138)；[Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:336-340](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift#L336)；[Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift:104-112](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/ProcessingCoordinator.swift#L104)；[Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift:93-100](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift#L93)。

**修复方向：** 在 App 绑定系统睡眠/唤醒通知，并串行、幂等处理生命周期。全会话 RequestID 唯一；worker 重启时保持共同时间基准；恢复成功后首个新批次必须进入存储。

**验收：** 模拟三轮生命周期每轮首批即被接受；短时真实合盖/唤醒后有新 CPU Raw 和 EMA，sleep Gap/segment 正确，采样继续；不要求 72h 长跑。

**关联：** REQ-039/130-132。

### R05 [P1] MonitorEngine 在写入回执前推进状态，未提交批次无法正确重试 — [Issue #31](https://github.com/sisyphe550/Temperature-monitoring/issues/31)

**证据与影响：** accept 在 commit/validateReceipt 之前修改 seriesState.lastElapsedNS、lastSuccessfulAt、sample sequence 等。临时 commit 第一次写入前抛暂态异常，第二次可成功，但同一 ReadBatch 重试在进入 commit 前被 non_monotonic_elapsed 拒绝，成功落库次数=0。测试 failedPersistenceDoesNotAdvanceStateBeforeRetry 已复现。

**源码：** [Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift:142-181](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift#L142)；[Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift:196-214](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift#L196)。

**修复方向：** 将接受过程改为暂存计算结果；只有合法 ProcessingReceipt 返回后原子交换正式状态。提交失败应保留原状态和可重试的批次身份；必须保持当前幂等和同 ID 不同内容拒绝规则。

**验收：** 首次 commit 抛错、第二次同批重试成功，最终只一份 Raw/EMA，后续 EMA 与无故障执行一致；错误回执不推进任何正式状态。

**关联：** REQ-017/023/058-064；contract revision 2 PersistenceLease/ProcessingReceipt 状态边界。

### R06 [P1] 正常运行未调度 TTL 清理，去重和 lease 记录持续增长 — [Issue #32](https://github.com/sisyphe550/Temperature-monitoring/issues/32)

**证据与影响：** 生产路径只在 resumeAfterWake 调用 session.prune，lastPruneElapsedNS 记录后未用于周期调度。真实 10.5min 会话最早 0.48s Raw/EMA 仍在（同时存在 R02 父层未提交，不能只凭实机现象独立归因）。临时 normalRuntimeTickPrunesExpiredPersistedSamples 已先插入合法已提交父桶，推进超过 Raw300s+宽限120s+tick60s，Raw/EMA 仍各 1 条。deliveredSampleIDs、完整 ReadBatch JSON 指纹、已取消/已消费 reservation 永不删除；每次容量计算还遍历所有历史 reservation。

**源码：** [Packages/TemperatureCore/Sources/SensorRuntime/SessionMonitorController.swift:188](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SessionMonitorController.swift#L188)；[Packages/TemperatureCore/Sources/TemperatureCore/Persistence/SessionPersistence.swift:60](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Persistence/SessionPersistence.swift#L60)；[Packages/TemperatureCore/Sources/TemperatureCore/Persistence/SessionPersistence.swift:277-291](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Persistence/SessionPersistence.swift#L277)；[Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift:39-40](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift#L39)；[Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift:221-232](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift#L221)；[Packages/TemperatureCore/Sources/TemperatureCore/Persistence/BoundedQueue.swift:27](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Persistence/BoundedQueue.swift#L27)；[Packages/TemperatureCore/Sources/TemperatureCore/Persistence/BoundedQueue.swift:53-68](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Persistence/BoundedQueue.swift#L53)；[Packages/TemperatureCore/Sources/TemperatureCore/Persistence/BoundedQueue.swift:121-167](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Persistence/BoundedQueue.swift#L121)。

**修复方向：** 正常运行每 60s 调度统一 prune，保留先聚合后删除、120s 宽限和恢复错误处理。为去重记录/已结束 lease 设置有界生命周期或有界索引，避免预留成本随整个会话长度增长。

**验收：** 父桶已提交的超期 Raw/EMA 在下一 tick 删除；缺父桶不能提前删除。常规模拟大量批次后去重/lease 容量受明确上限约束，资源测量只作补充，不要求 72h 实机。

**关联：** REQ-018-020/024/030-037/133。

### R07 [P2] 正常退出没有关闭删除会话数据库，异步 stop 未等待完成 — [Issue #33](https://github.com/sisyphe550/Temperature-monitoring/issues/33)

**证据与影响：** 正常 Cmd+Q 后 App/SensorWorker 进程均退出，但会话 monitor.sqlite 和数据仍存在。applicationWillTerminate 启动异步 Task 不等待；coordinator/controller stop 均未调用 session.closeAndDeleteSession。下次启动有孤儿目录清理，可清旧会话；它不替代当前正常退出契约。本次不声称有孤儿进程。

**源码：** [App/AppDelegate.swift:127-131](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppDelegate.swift#L127)；[App/AppDelegate.swift:195-196](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppDelegate.swift#L195)；[App/SessionCoordinator.swift:79-84](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/SessionCoordinator.swift#L79)；[Packages/TemperatureCore/Sources/SensorRuntime/SessionMonitorController.swift:138-159](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SessionMonitorController.swift#L138)；[Packages/TemperatureCore/Sources/TemperatureCore/Persistence/SessionPersistence.swift:299-309](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Persistence/SessionPersistence.swift#L299)。

**修复方向：** 使用可等待的统一退出流程，按 5s budget 停止采样、处理待提交、关闭 worker、checkpoint/close SQLite、删除本会话数据库及 marker 后才结束；AppKit 可使用 terminateLater/reply。

**验收：** 正常退出无 App/worker，当前 session 数据库/WAL/SHM 和目录被清；异常终止后下一次启动清孤儿；重复 stop 幂等且不误删其他目录。

**关联：** REQ-040-041/130。

### R08 [P1] 缺失固定 CPU 成员时 App 静默用剩余来源定义最高温度 — [Issue #34](https://github.com/sisyphe550/Temperature-monitoring/issues/34)

**证据与影响：** profile 指定 all listed keys/no silent subset。Registry 缺键时返回 11 available+1 unavailable，但 SeriesCatalogBuilder 只要求 count>1，控制器仍正常 start，重新定义 11 成员 cpu.zone.max。临时 missingOneRequiredCPUMemberStopsStartup 期望拒绝，实际接受。当前本机全部 12 可读，本问题是失败/缺失路径，不是本次正常读数已经少成员。

**源码：** [Packages/TemperatureCore/Sources/TemperatureCore/Registry.swift:216-260](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Registry.swift#L216)；[Packages/TemperatureCore/Sources/SensorRuntime/SeriesCatalogBuilder.swift:25-31](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SeriesCatalogBuilder.swift#L25)；[Packages/TemperatureCore/Sources/SensorRuntime/SessionMonitorController.swift:40-64](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SessionMonitorController.swift#L40)。

**修复方向：** 生产启动/重新发现验证固定 12 个成员的准确集合、编码和来源资格；关键成员缺失执行规定重试或 Fatal，不改变主指标定义为可用子集。

**验收：** 逐个遗漏/重复/编码错/全部无 CPU 都不能进入正常 12 成员主指标；正常 12 成员仍通过；采样单项失败亦不生成子集最大值。

**关联：** REQ-009/013/072-073/113。

### R09 [P2] 电池/SSD 未接入 Qualified catalog，且同相位可选采样会被 CPU 持续跳过 — [Issue #35](https://github.com/sisyphe550/Temperature-monitoring/issues/35)

**证据与影响：** 实际 sources 检查 CPU12/12，电池 SMC TB1T selected；正式 App 数据只有 cpuMain/cpuZone，没有 Battery/SSD 分组。ProfileRegistry.qualify 只做 CPU 与 HID 诊断，电池/SSD 从未 Qualified。资格工具电池独立直接读 transport；SSD evidence 将 interconnectLocation 固定 nil、lookupStatus 固定 missingProperty，因此 nvme_interconnect_lookup_failed 不能证明物理接口不可用。可选排期接入后还有调度缺陷：同到期先 CPU，任何正读取时长后 skipOverdueSchedules 会丢掉到期的 Battery/SSD；默认 CPU200ms/Battery1000ms 或 CPU50/100/500ms 与 SSD500ms 持续同相位。后者为确定源码推导，未对真实 App 可选采样实测（尚未接入）。

**源码：** [Packages/TemperatureCore/Sources/TemperatureCore/Registry.swift:195-205](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/Registry.swift#L195)；[Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:300-325](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift#L300)；[Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:365-380](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift#L365)；[Packages/TemperatureCore/Sources/TemperaturePresentation/PresentationModel.swift:140-145](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperaturePresentation/PresentationModel.swift#L140)；[Packages/TemperatureCore/Sources/ProductQualification/SourcesCollector.swift:48-53](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/ProductQualification/SourcesCollector.swift#L48)；[Packages/TemperatureCore/Sources/ProductQualification/SourcesCollector.swift:103-110](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/ProductQualification/SourcesCollector.swift#L103)。

**修复方向：** 如保留可选需求，资格选择必须进入同一 Registry/catalog→schedule→store→UI，不可用能力也应形成带原因的 UI 记录。SSD 应真实检查父节点/内置属性，禁止硬编码失败证据。调度应串行服务同到期来源，有界丢弃落后批次而不使可选来源永久饥饿。如用户删除这些功能，同步所有权威需求与验收。

**验收：** 本机 TB1T 被正式 App 每 1000ms 采集并展示；SSD 成功或可靠不可用原因清晰。带非零读耗时的同相位 CPU/SSD/Battery 调度测试证明各组取得样本；不要求扩展其他 Mac。

**关联：** REQ-004-005/010/115-116。

### R10 [P2] 五分钟图对高频样本取最后 2000 点，丢弃前段历史 — [Issue #36](https://github.com/sisyphe550/Temperature-monitoring/issues/36)

**证据与影响：** realtime 返回全部内存 EMA 不处理 pointLimit，HistoryChartModel 使用 suffix(2000)。50ms 的 5min 约 6000 点，结果只覆盖最后约 100s；100ms 约 3000 点只保留约 200s，前部峰值消失。此项为源码及采样数量推导；现有真实历史还被 R01/R02 阻断。App 还只选 cpu.zone.max、没有多来源选择，时间轴隐藏；柱图没有实现，按现行 UI 需求尚有缺口。

**源码：** [Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift:434-455](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift#L434)；[Packages/TemperatureCore/Sources/TemperaturePresentation/HistoryChartModel.swift:111-120](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/Packages/TemperatureCore/Sources/TemperaturePresentation/HistoryChartModel.swift#L111)；[App/AppSessionRuntime.swift:172-175](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/AppSessionRuntime.swift#L172)；[App/Presentation/HistoryChartView.swift:88-89](https://github.com/sisyphe550/Temperature-monitoring/blob/48cd967d835e5c9f2ad2f191d97eb32a92623bcd/App/Presentation/HistoryChartView.swift#L88)。

**修复方向：** 在完整请求时间范围按时间分箱降采样，保留 min/max、segment/Gap 和首尾，不能简单截尾。若保留当前 UI 需求，补来源选择、柱图和可读时间轴；这些非核心功能可经用户确认删减，并同步文档。

**验收：** 50ms、100ms 的完整 300s 历史首段峰值保留、首尾范围不缩短，每个 series≤2000 点；Gap 不连线，多来源按保留需求验收。

**关联：** REQ-047/049-050/046/122-123/129。

## 其他需要收敛的状态与界面

1. `README.md:3`、`docs/00-agent-handoff.md:43` 仍写生产 App/Package/工程未创建，`docs/01-requirements.md:3` 状态和 W00–W09 任务勾选也有过期内容。应更新当前状态，保留既有按 SHA 归档证据；不要通过勾选任务替代缺陷修复。
2. `App/AppDelegate.swift:38-43` 对 worker 缺失直接跳过运行时初始化，对配置加载使用 `try?`，错误表现为持续“正在读取…”；直接 Xcode Run 的 App target 没有 build-app.sh 的 worker 嵌入步骤。按本次脚本构建的 Release 能运行，开发启动路径及资源缺失路径仍应明确报错。归入 R03 的启动/故障通道收敛。
3. `TemperatureFormatting.swift:15-18,26-29` 的 live/cached 显示完全相同，stale/loading 都是占位符，原因未展示；`FatalView.swift:50-52` 倒计时到 0 没有退出。归入 R03，不另建重复 Issue。
4. `AppSessionRuntime.swift:172-175` 仅选 CPU 主曲线；Dashboard 无多来源选择和柱图；Chart 隐藏时间轴。归入 R10。基本前端已实现，但这些现行需求尚未全部完成。
5. 本机单一型号已足以满足当前使用范围。未知 Mac 型号、SMC 编码漂移、重新连接后的来源身份是扩展支持的额外边界，不作为此次自用交付的新增硬件认证要求。现有 metadata 把 profile.model 当实际 model，不能用于声明其他设备通过。

## 可保留或删减的需求

- **继续保留 CPU 监控核心需求。**正式 App 已证明采集可行，当前问题需要修复集成和异常行为。
- 本机 ad-hoc 构建保留为交付路线；公证和分发只保留可选工具，不阻塞当前任务。
- 72/73h 耐久继续保持用户豁免；TTL、水位、唤醒和故障恢复仍通过短时自动化及必要的短时实机验证。
- SSD/Battery、柱图、多来源历史、复杂诊断界面若不再需要，可以删减；这是产品范围选择。用户本次只明确豁免长跑/本机以外的分发，没有明确删除这些功能，因此本报告按现行文档列出缺口，未擅改需求。
- SSD 的 `nvme_interconnect_lookup_failed` 来自当前资格工具硬编码 `nil/missingProperty`，不能据此宣布硬件或接口不可实现。先验证实际内置 NVMe 路径，或明确放弃功能，不能伪装成已验证不可用。

## 交给修复 Agent 的执行顺序

| 步骤 | 范围 | 依赖及完成条件 |
| --- | --- | --- |
| A1 | R01 会话时钟 + R04 请求身份 | 先确定全会话时间/ID，采样、worker、查询共用语义；保留 revision 2 公开边界，变更协议须同步权威契约 |
| A2 | R08 固定成员 + R03 故障重发现 | 不允许子集 CPU；一次暂态超时恢复，持续失败正确退出 |
| A3 | R05 commit 前暂存状态 | 提交失败同批可重试且不重复写；非法回执不交换状态 |
| A4 | R02 请求生命周期与聚合水位 | 所有终止路径清登记；真实耗时后 1s/10s/60s 桶可关闭 |
| A5 | R01 App 历史加载 + R10 全范围图 | A1/A4 后验证正式非 fixture 数据出现在图中并连续刷新 |
| A6 | R06 TTL/有界缓存 + R07 退出 | A3/A4 后清理超期数据；退出等待完成并删会话 |
| A7 | R04 系统通知接线 | A1/A2/A3 后做短时真实睡眠/唤醒，醒后第一批成功落库 |
| A8 | R09 可选能力 + R10 可选界面 | 用户保留则接入真实 Registry 和公平调度；删减则原子同步需求/设计/验收 |
| A9 | 新证据、文档状态、独立复审 | 7 项新增回归转绿；原244测试/覆盖/适用界面测试；正式App短时端到端；不得把 fixture 或绑定路径视为功能通过 |

修复时遵守 `docs/11-git-github-workflow.md`：先检查用户改动，从最新 main 开 `feature/<修复主题>`，核对本报告 SHA 与修复基线差异；保留本次被审查分支，禁止 reset。公开类型/defaults/profile/schema/来源资格变动须原子同步 docs/contracts、需求、设计、追踪与测试。修复 PR 链接相应 Issue；blocking 未解决不合并/跨阶段；独立审查通过后由维护者使用 merge commit，保留开发分支。本次没有执行这些修复/合并动作。

### 使用审查回归测试

本目录 `regressions/` 有 3 个 Swift 文件、7 个用例。在独立修复分支确认 TestSupport 未改变后复制到 `Packages/TemperatureCore/Tests/TemperatureCoreTests/`，运行：

```sh
swift test --package-path Packages/TemperatureCore --filter 'ProductAudit.*RegressionTests'
```

它们断言正确行为，审查版本全失败；修复应使其转绿。休眠测试使用可控制时钟，不能替代实际系统通知接线验收；时钟和水位测试复现生产路径构造方式，不要求所有任意 SystemClock 对象天然共用 origin。

## 证据文件与复核

- [verification.json](verification.json)：源码、环境、命令结果、Issue 和范围。
- [hardware-sources.json](hardware-sources.json)：fresh Release worker 实际读取资格，CPU12/12、Battery TB1T selected。
- [after-quit-db.json](after-quit-db.json)：正常退出后数据库事实、成员数分布和主指标批次最大值核对。
- [fresh-binary-hashes.json](fresh-binary-hashes.json)：本次新构建 App 与 worker 的 SHA-256。
- [核心测试日志](logs/core-tests.log)、[覆盖率](logs/core-coverage.log)、[审查回归](logs/audit-regressions.log)、[传感器异常回归](logs/audit-sensor-regressions.log)、[提交边界回归](logs/audit-commit-regression.log)。
- [界面测试结果摘要](logs/ui-summary.txt)、[资格格式测试](logs/qualification-schema-tests.log)。
- 完整 build、codesign 相关调用输出、XCUITest/xcresult 在 `/tmp/temperature-monitor-review-20261002.1G0KnN/`；本报告保存关键日志和结构化证据，未复制大型构建缓存。

审查不会证明未执行的系统休眠、真实 worker 故障注入或长时资源上限。对应问题依据可重复的控制器回归及源码列明；正常 CPU 读数、历史空图、数据库事实和退出进程已在正式 App 上实测。
