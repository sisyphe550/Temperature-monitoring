# 产品审查缺陷修复实施计划

> 执行方式：当前会话逐项实施（executing-plans），完成后进行一次独立整分支审查。

**Goal:** 修复审查 R01～R17（GitHub #27～#43），使本机正式 Release App 的 CPU12→Raw max→EMA→SQLite→实时/历史界面链路、异常恢复、睡眠唤醒和退出清理可实际运行。
**Architecture:** 保持核心边界，并将NVMe发现事实补齐为 contract revision 3、非特权只读 worker、QualifiedSourceCatalog、互斥 ReadingOutcome、Lease/Receipt 和 PresentationState。恢复已规定的行为；优先内部接线和事务暂存，不新增平行架构。
**Tech Stack:** Swift 6、Swift actors、Swift Testing、AppKit/SwiftUI/Charts、SQLite、SMC/IOKit。
**Spec:** docs/01-requirements.md、docs/21-implementation-contracts.md、docs/22-agent-implementation-plan.md、docs/23-execution-task-breakdown.md、docs/11-git-github-workflow.md；缺陷证据为 2026-10-02、48cd967d 产品审查及 issues #27～#43。
**Baseline:** origin/main 0b720deb1d7fe170e55999f2709a3665634746da；feature/product-audit-fixes，独立 worktree。244 项 core tests 全部通过。已审查 W11 分支 48cd967d 的证据保持原样。

## Global Constraints

- 原工作区及 feature/w11-acceptance 保留；不 reset、不覆盖 Cursor 或用户改动。
- 固定12个 CPU 成员，禁止恢复逐物理核心或 Package 保证。成员不足为关键失败，不能悄悄使用子集。
- 全部可见温度均来自 Qualified 来源；失败不能复写旧值、补零或插入新样本。
- 仅 Receipt 成功后交换算法状态；父会话与 worker 共用连续时钟基准。
- Raw/EMA、聚合、缺口、幂等、TTL 和容量遵守现行契约。必要公开契约变化在同一提交同步权威文档与门禁。
- Battery/SSD 保留现行需求；以本机实际资格结果展示，不能把未实现的查询写成物理不可行。
- 用户明确豁免72/73小时长测、公证、公开发行及跨机型认证。本轮仍做真实短时 Release App 验证，不将模拟替代实机。
- 每任务先看 RED，再修复到 GREEN；全量 core tests 通过后提交。blocking Issue 未解决不得合并。
- 文档历史证据不可回写。新验证按当前提交新增，源码、软件测试与实机结论分开。

## Review Focus

审查逐项检查：actor 在 await commit 时重入是否会丢新读数/注册；失败或取消是否释放同一 in-flight 注册；worker 重启/唤醒是否保留时钟且请求 ID 不复用；同相位可选来源能否获得真实非零耗时 IO；Receipt 失败后是否可重试且聚合不丢；CPU12 缺成员/编码失败是否阻止正式运行；TTL 是否要求父层已提交；幂等和 Lease 元数据是否有界且仍拒绝非法复用；历史请求是否覆盖完整时间范围且保留峰值/segment/缺口；App 退出是否等待清理而非创建即弃 Task；可选来源不可用是否有明确行；Fatal 是否真正按截止时间退出并留下报告。检查所有公开契约漂移和 Release fixture 边界。

## Task 1: Receipt 前状态隔离（R05 / #31）

**Files:** Packages/TemperatureCore/Sources/TemperatureCore/MonitorEngine.swift；Tests/TemperatureCoreTests/MonitorEngineTests.swift 或新的 CommitRegressionTests.swift。
**Interfaces:** Produces 同一 accept/advance/commitLifecycleTransition 签名，成功 Receipt 才提交的状态；后续调度和睡眠任务消费。不改变 schema 或公开契约。

- [x] 先加入提交失败后原 ReadBatch 重试、聚合推进失败后重试、唤醒提交失败后重试测试。
- [x] 运行 `swift test --package-path Packages/TemperatureCore --filter CommitRegression`。Expected: 原状态提前变化导致断言失败，非编译错误。
- [x] 暂存 sample sequence、generation、series/failure/success 状态；聚合关闭及唤醒 segment 也在 Receipt 后交换。验证 actor 重入时只交换该事件影响的状态。
- [x] 重跑定向与全量 core tests。Expected: 新旧测试均通过；无重复 Raw/EMA 或缺失 bucket。
- [x] 提交 `fix: commit processing state only after persistence receipt`，记录范围、测试及 #31。

## Task 2: 请求生命周期与聚合水位（R02 / #28、R04 部分 / #30）

**Files:** SensorRuntime/SamplingService.swift、ProcessingCoordinator.swift（均在 Packages/TemperatureCore/Sources/）；对应 runtime 测试。
**Interfaces:** Consumes Task 1 Receipt 语义；内部按 RequestID 记录 planned start，同一键终结。RequestID 在整个会话不重用，生命周期回调只在 IO 结束/取消后释放注册。

- [x] 补真实 coordinator 路径的非零 IO、读异常、取消/stop/stale generation、wake 后首读测试；Expected RED: 水位卡住或请求碰撞。
- [x] 成功、失败、取消都配对释放原 planned 注册；保留 Reading 的 actual 时间，不用 actual start 删除 planned。唤醒不重置请求身份。
- [x] 新旧测试及全量 core tests 通过后提交；Expected: 水位可超过首秒、聚合出现，wake 首读新增 Raw。

## Task 3: 统一时钟与历史装载（R01 / #27）

**Files:** TemperatureCore/Clock.swift、SensorRuntime/WorkerClient.swift、SensorWorker/WorkerClock.swift、App/AppSessionRuntime.swift；Clock、worker、history 集成测试。
**Interfaces:** Consumes Task 2 可重启 worker；现有 WorkerClientConfiguration.environment 传递父会话基准，所有 query 使用同一 session clock。内部环境校验禁止默认接受畸形基准。

- [x] 先测 worker 启动/重启前后的同一 elapsed 原点以及 session 时间范围查询；Expected RED: 重启归零或查询丢数据。
- [x] 父进程创建唯一基准并传给 worker；App 元数据、采样、历史查询复用该 clock。首次有效 Snapshot 选好 series 后加载，后续受限刷新并取消过期结果。
- [x] core tests、worker 集成测试及 Release 构建；Expected: 查询覆盖当前样本，重启时间单调。提交 #27 对应修复。

## Task 4: CPU完整性、有限重试与运行错误（R08 / #34、R03 / #29）

**Files:** TemperatureCore/Registry.swift、QualifiedSensorClient.swift、Diagnostics/；SensorRuntime/SessionMonitorController.swift、SamplingService.swift、ProcessingCoordinator.swift；App/AppSessionRuntime.swift、AppDelegate.swift、Presentation/FatalView.swift。
**Interfaces:** Consumes Tasks 1～3；资格失败和运行错误按现有 MonitorFailure/RetryPolicy/ErrorCoordinator 到唯一 PresentationState，正常恢复重新 discover 新 generation。可选单项故障隔离。

- [x] 先测试生产 profile CPU11/12、坏编码、暂时 timeout 后恢复、重试耗尽、持久化/加工关键错误；Expected RED: 静默接受或永久停采/无 Fatal。
- [x] 启动/唤醒强制验证固定 CPU 集；接入有上限退避、重新资格化、日志/报告和关键失败通知；首个主值读失败不得继续 loading 且无原因。
- [x] core tests、App 构建通过；Expected: 关键错误停止采样且可见，可恢复错误恢复新样本，可选失败不杀 CPU。提交并关联 #29/#34。

## Task 5: 周期保留与有界元数据（R06 / #32）

**Files:** SensorRuntime/SessionMonitorController.swift、TemperatureCore/Persistence/SessionPersistence.swift、BoundedQueue.swift、MonitorEngine.swift、Storage/Retention.swift；retention/queue 集成测试。
**Interfaces:** Consumes Task 2 正常聚合父层、Task 4 关键失败路径；每60秒按现有配置 prune；保留幂等/单次消费语义，过期内部缓存不能让旧 ID 成为新数据。

- [x] 先测试481秒 runtime tick 删除有父层的过期 Raw/EMA、缺父层保留、长序列 Lease/请求元数据容量及非法复用；Expected RED: 记录或元数据持续增长。
- [x] 接入周期 prune，终结 reservation 回收；样本 ID 依赖单调序列，请求指纹压缩并设有界生命周期，对过期重复必须显式拒绝。
- [x] core tests/覆盖检查通过；Expected: 不丢未聚合有效记录、运行开销不扫描全会话。提交 #32。

## Task 6: 睡眠、退出与 Fatal 生命周期（R04 / #30、R07 / #33、R03 / #29）

**Files:** App/AppDelegate.swift、SessionCoordinator.swift、AppSessionRuntime.swift、Presentation/FatalView.swift；SensorRuntime/SessionMonitorController.swift、TemperatureCore/Diagnostics/MonitorShutdown.swift。
**Interfaces:** Consumes Tasks 1～5；OS 睡眠通知串行调用 suspend/resume；应用终止有有界等待且 closeAndDeleteSession 完成后退出。Fatal 复用同一终止路径。

- [x] 先测 runtime stop 等待 worker/持久化关闭并删除 SQLite/WAL/SHM、重复 stop、sleep/wake 顺序；Expected RED: session 文件残留或异步清理未等待。
- [x] App 接 NSWorkspace 通知；applicationShouldTerminate 返回稍后答复，等待现行 deadline 内清理；Fatal deadline 真正触发退出。
- [x] core tests、Release 构建、短时正常退出验证；Expected: 无遗留本次会话目录与 worker。提交 #30/#33。

## Task 7: 可选来源资格化与公平调度（R09 / #35）

**Files:** TemperatureCore/Registry.swift、QualifiedSensorClient.swift、SensorRuntime/SeriesCatalogBuilder.swift、SamplingService.swift、SensorWorker/HardwareSession.swift、ProductQualification/SourcesCollector.swift；对应 tests。
**Interfaces:** Consumes Task 4 资格/故障通道；Battery/SSD 从 Discovered facts 进入 Qualified catalog，保留 unavailable 原因；串行 IO 对同相位来源公平，绝不补样。

- [x] 先测有非零 IO 的 CPU+Battery/SSD 调度、Battery 候选、SSD NVMe ancestry 查找与单位、缺属性 unavailable；Expected RED: 可选被跳过/未资格化。
- [x] 复用已登记 bridge 方法；查询真实 parent interconnect/property；优先级按 profile；资格报告使用正式 Registry 结果；新增NVMe位置/查询状态事实，原子同步契约修订3，schema/数值/DAG保持。复制新上游代码前登记许可，否则只参考方法。
- [x] core tests、边界检查及本机 sources 实测；Expected: Battery 正式展示，SSD 按真实证据可用或明确不可用。提交 #35。

## Task 8: 完整历史范围与前端需求（R10 / #36、R01 / #27、R03 / #29）

**Files:** TemperaturePresentation/HistoryChartModel.swift、PresentationModel.swift、PresentationState.swift；App/Presentation/HistoryChartView.swift、TemperatureDashboard.swift、TemperaturePopover.swift、TemperatureFormatting.swift、TemperatureSourceRow.swift、SettingsView.swift；UI tests。
**Interfaces:** Consumes Tasks 3/4/7 时间、错误、来源状态；沿用唯一 PresentationState。跨完整请求范围减点，按 series/segment/gap 分隔，保留 min/max 峰值。App/Presentation 核心模型副本同步。

- [x] 先测50ms/100ms五分钟完整范围、峰值、segment/gap、可选 unavailable 行及 cached/stale 原因；Expected RED: suffix 截断/缺行。
- [x] 修正点数上限为全范围减点，增加时间轴、来源选择、温度条形比较及明确状态/来源说明；绑定统一 actions。
- [x] core/presentation tests、适用 UI tests、正式 App 人机界面短时验证；Expected: 完整范围、当前 CPU 及所有能力状态可见。提交 #36。

## 补充缺陷 R13 / #39：运行缺口与EMA分段

- [x] 失败读数或实际dt超过GapDetector阈值时，生成Gap；恢复时持久化新segment并重置EMA，所有状态在Receipt后交换。
- [x] CPU主指标随成员失败打开缺口；可选来源隔离期间保持Unavailable，三次有效探测后恢复。
- [x] 五分钟内存历史与SQLite历史均携带已提交Gap，闭合缺口按300s内存TTL清理；不能跨缺口连接曲线。
- [x] 运行失败、dt超阈值、改周期不误报、Receipt失败重试、同时间恢复及可选状态回归通过。

## 独立审查补充 R14～R16 / #40～#42：可选恢复边界

- [x] 来源SourceID换代清零连续成功数，保留运行中的有限失败轮次；新来源第1/2次仍Unavailable，第3次成功Receipt才恢复。
- [x] 睡眠停止等待在途任务完成后捕获最终隔离状态；唤醒重新资格化建立新的有限恢复周期，避免旧kind隔离锁和await重入遗漏。
- [x] 非重试错误及恢复探测预算耗尽后保留有界kind状态；运行中CPU重连不得复活已停探测的来源，唤醒才可重新建立资格周期。
- [x] 独立RED→实现修复→独立GREEN；新增4项真实Registry/Controller/SQLite软件集成回归，包含在途失败与睡眠的并发路径。

## 实机补充 R17 / #43：菜单栏隐藏时的可达入口

- [x] 正式App AX与测试录像复现隐藏状态项无法右键打开菜单，记录NSScreen刘海安全区域；不把AX exists当物理可点击。
- [x] 正式启动打开主窗口；标准reopen显示原窗口与原会话；主窗口正常退出按钮。
- [x] Fixture UI与最终Release本机验证这些入口、五档及退出清理；菜单栏隐藏条件单独记录，不能宣称右键通过。

## Task 9: 交付文档、集成验收与独立审查

**Files:** README.md、docs/00-agent-handoff.md、docs/01-requirements.md（状态）、docs/validation/product-review/、新修复证据；涉及契约变动时同步 docs/contracts、17、21～23、10。
**Interfaces:** Consumes 全部任务结果；当前入口陈述验证范围，原始审查/研究记录保持历史；Issue 状态以实际修复和证据为准。

- [x] 全量 `swift test --package-path Packages/TemperatureCore --enable-code-coverage`、coverage≥80%、handoff、upstream boundary、qualification schema、Release 构建/签名检查。Expected: 全部适用检查通过。
- [x] 正式无 fixture App 验证CPU12/max/EMA、历史/聚合、五档/改周期、可选状态、正常退出；记录当前 SHA、二进制 hash、环境及时间范围。豁免长测仍明确保留。
- [x] 更新入口/需求状态和证据，避免“测试全绿=全部REQ完成”的表述；保存具体未验证边界。
- [x] 生成整分支 review package，委派独立 reviewer；重要发现用 RED→GREEN 修复并跑全量；minor 和裁决如实记录。
- [ ] 符合实际修复证据后关闭相应 Issue；推送修复分支、创建/更新 PR，链接 review 和证据，检查 exact head CI。仅在用户已授权本轮合并且全部阻塞项解决时按 merge commit 合并；否则保留可审阅 PR。

## 执行记录

任务开始/完成、测试输出和裁决记录在本计划独立执行目录的 progress.md；交付时将有效修复状态汇总到新日期/提交的证据目录。未完成任务不能勾选，实机未测不能写“通过”。

### 2026-10-02 提交前软件集成阶段结果（保留中间测量）

该阶段337项核心测试／52 suites通过，覆盖7069/7966=88.74%。独立审查同源337项亦通过。UI Runner复用unsigned构建目录曾启动失败，独立签名目录已正常启动；15项UI的5个失败经AX现场定位并修复；最终18项中16项执行通过、2项条件跳过，包含窗口重复打开／退出回归。正式Release的初步真实采样证据已观察CPU12/Raw max/EMA/SSD/Battery及三层聚合与周期TTL，但需按最终代码SHA重新构建并执行明确可选的本机UI用例。不得据此宣称全部REQ或长测完成。

查询测试裁决：Swift任务创建顺序不保证actor入场顺序，也不保证两次查询重叠。两个并发创建请求均须返回各自正确层级，或明确superseded；合法串行完成允许两者成功。测试不以固定sleep制造重叠，也不宣称每次都覆盖到取消路径。

### 最终代码a97fd5a本机验证

337项／52 suites通过，最终覆盖7059/7966=88.61%；独立同源全量与源码审查通过。正式Release重新构建并验证签名/上游边界，最终本机UI 1项84.800s通过，CPU12/Raw max/EMA、Battery/SSD、五档各8s、5min/1h历史、标准reopen同会话及app.quit清理有新证据。受控缺worker副本启动Fatal显示原始错误并自动退出，首观察至消失31.4639s，含启动/收尾；范围只为startup fallback。

[最终修复报告](../../validation/product-fixes/2026-10-02-a97fd5a/report.md)及机器结果按代码SHA归档。菜单栏右键、真实睡眠/运行中故障、五档各10min、真24h/72h历史和最终SHA的真实TTL长时观察未验收；用户豁免项保持不执行。Task9的Issue/PR/CI条目在实际交付后记录，原W11 PR #26不可沿用旧SHA作修复验收。
