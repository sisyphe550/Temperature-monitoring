# W11 37项pending执行清单（当前证据衔接）

生成时间：2026-10-03T03:45:35.544885+00:00；实际HEAD：`403d44bab8f972461973c5a91699865b15515be2`；catalog delivery：`403d44bab8f972461973c5a91699865b15515be2`。

执行建议与缺口快照；本次没有运行App/产品测试、修改需求/生产代码/结果或新建Issue。实际判定仍以新原始证据及独立审查为准。

当前catalog中的37项pending全部包含在清单中。组别不是新需求或新的验收结果；尚未执行的建议继续pending。REQ-012/114仍retired，整项豁免仅REQ-127。72/73h耐久、公证、公开发行和跨机型已豁免；72h软件历史、五档各600s及真实sleep/wake仍需证据。

## 执行顺序与不互相替代的证据

- **G0 固定当前候选与证据目录**（依赖：无）：读取最新实际生产提交及未提交变更，冻结source/App/worker/profile/签名/机型OS；正式App验收由根agent串行调度，不启动第二App、不抢会话、不回写历史。
- **G1 先判定条件和模型差异**（依赖：G0）：先处理058/061读重试归属、064–067暂时数学条件、079/082事件报告字段。欠测不是新bug；真实差异只有在具体条件复现后才按项目流程登记。
- **G2 独立补软件执行证据**（依赖：G0）：合法虚拟时间+真实SQLite验证TTL、maintenance、日志保存、无效值/损坏/实际App查询重试路径；相关路径需G1结论。执行结果不在本清单产生。
- **G3 既有#46/#47回归与新证据集成**（依赖：G0）：集成启动/睡眠history取消的软件GREEN及#47新Release运行中Fatal自动退出实机PASS；退出途中wake取消待GREEN/独立复核。真实系统sleep/wake、REQ078剩余组合条件和新生产身份仍分别复核。
- **G4 真实屏幕与同hash资格**（依赖：G0/G3）：配合根agent完成五档各600s清醒运行、真实系统sleep/wake、菜单/Popover、Fatal操作、受控残留恢复；软件补测可并行，不干预现有长测。
- **G5 最后逐REQ/阶段/交付门禁**（依赖：G1/G2/G3/G4）：逐项复审结果，保存132+2矩阵、独立审查、exact-head CI/ruleset/blocking与最终product-acceptance输出；维护者决定merge。099–106当前保守待整体复核，不由一个TC引用自动通过。

## 已确认#46/#47门禁（不新增bug）

### #46 — 合法sleep暂停期间历史查询取消，不访问关闭的persistence，不标Fatal；醒后重新采样/查询

#46启动/睡眠history取消软件GREEN与#47运行中Fatal自动退出实机PASS已产生，待新身份/仓内证据集成；退出途中wake取消目前RED待GREEN。真实sleep/wake与完整REQ条件不据此自动通过。

- 最小实机证据：真实系统睡眠/人工唤醒的同session时间线、OS电源日志、App通知/无Fatal、Gap新segment及醒后采样；记录至少计划要求的生命周期轮次。
- 不能替代：直接Controller.suspend/resume、pmset日志单独存在、软件GREEN、黑屏截图或长测被合盖打断。
- 关联pending：REQ-094 / REQ-101 / REQ-102 / REQ-103 / REQ-110

### #47 — runtime Fatal退出的AppKit RunLoop入口及terminateLater收尾

#46启动/睡眠history取消软件GREEN与#47运行中Fatal自动退出实机PASS已产生，待新身份/仓内证据集成；退出途中wake取消目前RED待GREEN。真实sleep/wake与完整REQ条件不据此自动通过。

- 最小实机证据：新Release运行中Fatal可见30s后的自动退出、≤5s清理、按钮退出与未完成步骤/下一次启动处理；主App/worker进程和目录证据。
- 不能替代：旧启动missingWorker fallback约31s、正常退出、RunLoop最小探针或单元测试。
- 关联pending：REQ-078 / REQ-094 / REQ-102 / REQ-103 / REQ-110

## 已有功能但缺证据（14项）

### REQ-031 限制高精度历史规模

- 范围：在 `samples_1s` 记录超过 1 小时时，数据清理构件应删除其中时间最早的超期记录。
- 最小验证/判定：在RetentionTests/TemporaryStoreFixture的真实SQLite写入width_s=1桶，end_elapsed_ns分别为now−3600s−1ns、cutoff、cutoff+1ns；调用生产prune，按桶身份断言前两条删除、后一条存留。
- 顺序：G2；先核对cutoff半开语义及同series/segment合法父层；可与033/034并行，036复用结果。
- 不可替代：不能用现有width_s=10的86400s测试、配置常量、总行数或长睡眠空表替代1s层身份边界。
- 任务/TC：T03.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetentionTests.swift#deletesAggregateExactlyAtCutoff()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetentionTests.swift#pruneAfterLongSleepRemovesExpiredRows()

### REQ-033 冻结最大历史范围

- 范围：在 `samples_1m` 记录超过 72 小时时，数据清理构件应删除其中时间最早的超期记录。
- 最小验证/判定：同一真实SQLite中写入width_s=60的1m桶，end_elapsed_ns位于now−259200s的−1/0/+1ns；prune后按身份验证过期删除与未过期存留。
- 顺序：G2；先准备有效定义/segment/桶；036依赖本项。
- 不可替代：不需真实72h等待；用户豁免耐久不能免除72h软件TTL，现有不含1m过期行的长睡眠测试不能替代。
- 任务/TC：T03.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetentionTests.swift#pruneAfterLongSleepRemovesExpiredRows()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SessionLifecycleTests.swift#sleepAcrossRetentionClosesRealParentsWithoutCreatingEmptyBuckets()

### REQ-034 趋势结果不形成另一套长期数据库

- 范围：在 `trend_samples` 记录超过 1 小时时，数据清理构件应删除其中时间最早的超期记录。
- 最小验证/判定：写入trend_samples elapsed_ns=now−3600s的−1/0/+1ns，执行生产prune后核对具体trend身份、条数及值；保留未过期数据。
- 顺序：G2；可与031/033并行，先完成合法趋势记录装配；036依赖本项。
- 不可替代：趋势入库测试、聚合层删除或真实短会话不能证明Trend清理边界。
- 任务/TC：T03.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/StorageFaultTests.swift#batchStoresAggregatesTrendsAndSampleMembers()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetentionTests.swift#pruneAfterLongSleepRemovesExpiredRows()

### REQ-035 数据不存在与查询范围必须一致

- 范围：历史查询构件应拒绝查询当前时刻之前超过 72 小时的监控数据。
- 最小验证/判定：在prune之前保留超过72h及cutoff内的1m记录，执行SessionStoreCapability.query(.threeDays, asOf=now)，断言过期点立即排除、有效点仍返回；再检查数据库仍含过期点以证明是查询过滤。
- 顺序：G2；先核对查询对桶end/latest的权威过滤口径；独立于033物理删除。
- 不可替代：不能用prune后空查询、三天range枚举往返、超范围API不存在或72h耐久豁免替代。
- 任务/TC：T03.3 / T03.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetentionTests.swift#pruneAfterLongSleepRemovesExpiredRows()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ContractCoverageTests.swift#historyAndGapRoundTrip()

### REQ-036 统一清理入口

- 范围：当数据清理任务执行时，数据清理构件应按照 Raw、EMA、1 秒、Trend、10 秒、1 分钟各自 TTL 删除超期记录。
- 最小验证/判定：复用031/033/034向量，加已有Raw/EMA300s及10s86400s；在同一生产prune入口逐表验证cutoff两侧身份，确认Raw/EMA只有父层已提交才可删除。
- 顺序：G2；依赖031/033/034及现有父层/幂等用例；不能跳过Raw/EMA父层前置条件。
- 不可替代：不能由Raw/EMA删除或一个aggregates总数推断六类TTL均通过。
- 任务/TC：T03.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RuntimeMaintenanceRegressionTests.swift#runningControllerPrunesExpiredRawWithCommittedParentWithoutSleep()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetentionTests.swift#deletesAggregateExactlyAtCutoff()

### REQ-037 避免每条采样触发 DELETE

- 范围：数据清理任务应每 60 秒执行一次。
- 最小验证/判定：使用ControllerFixture/TestClock执行现有maintenance loop，观察59.999s前不prune、60s执行、120s再次执行；通过合法可清理记录或测试观察器核对每轮实际执行，不只核对睡眠deadline注册。
- 顺序：G2；先完成调度注册同步和每轮合法过期父桶，避免大跳时间导致遗漏观察；与036不同。
- 不可替代：当前一次跳到481s、读取60s常量或物理睡眠后清理不能替代周期边界。
- 任务/TC：T03.4 / T05.4 / T06.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RuntimeMaintenanceRegressionTests.swift#runningControllerPrunesExpiredRawWithCommittedParentWithoutSleep()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ConfigurationTests.swift#bundledRevisionThreeDefaultsLoad()

### REQ-042 运维日志不能跟随监控数据消失

- 范围：在监控数据库被删除时，日志构件应保留独立错误日志。
- 最小验证/判定：在同一隔离会话写入真实DiagnosticLogger错误日志和ReportWriter报告并记录SHA256，再执行生产session关闭/清理；断言DB/WAL/SHM删除且诊断文件存在、内容hash不变。
- 顺序：G2；先准备合法marker和独立日志目录；039/078实机可额外复核但不是本软件断言的前提。
- 不可替代：不能拼接日志轮转测试、目录分离源码和无错误的正常短会话。
- 任务/TC：T06.2 / T06.3 / T06.4；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/DiagnosticsTests.swift#loggerRotatesAtConfiguredSize()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SessionLifecycleTests.swift#cleanupRemovesOrphanedMarkedSession()

### REQ-057 无效值进入同一重试机制

- 范围：如果传感器返回无效温度值，则温度采集构件应将该结果视为一次读取失败。
- 最小验证/判定：通过生产QualifiedSensorClient/SamplingService路径给同批CPU12中一成员无效温度对应ReadingOutcome.failure，其余有效；用TestClock观察首次后50/100/200ms三次重试、成功停止或第4次失败耗尽，并断言失败无Raw/EMA/count。
- 顺序：G2；先复用SensorRecoveryRegressionTests的可控transport并核对sensorValue可重试分类；不修改生产分类以促成测试。
- 不可替代：不能用timeout、普通IO失败、解码拒绝或failure不产样本的孤立测试替代这个输入。
- 任务/TC：T04.1 / T05.3 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/SensorRuntimeTests/SensorDecodingTests.swift#rejectsWrongLengthUnknownEncodingAndNonFiniteValues()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ProcessingIdentityTests.swift#failureReadingProducesNoSample()

### REQ-062 损坏不进行无意义重试

- 范围：如果数据库完整性检查确认数据库损坏，则故障管理构件应直接生成 `DB-CORRUPT-006`。
- 最小验证/判定：向生产SessionPersistence.open提供真实NOTADB/CORRUPT库，观察MonitorFailure.databaseCorrupt(DB-CORRUPT-006)、retryCount=0及无重试；确认原损坏文件保留供诊断。随机非SQLite字节只覆盖NOTADB映射；要声称quick_check损坏分支通过，必须取得有效SQLite且quick_check明确非ok输入。
- 顺序：G2；先选择生产实际支持的open/quick_check入口；复用SessionLifecycleTests的损坏fixture，不能只catch清理器错误。
- 不可替代：SessionCleanupError.databaseCorrupt、枚举或RetryPolicy表测试不证明SessionPersistence出口。
- 任务/TC：T03.1 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SessionLifecycleTests.swift#corruptedActiveDatabaseIsNotAutoDeleted()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#structuralDatabaseFailuresAreNotRetryable()

### REQ-068 短暂故障不立即终止界面

- 范围：如果 UI 数据读取发生暂时性失败，则前端数据构件应按照 100 ms、250 ms、500 ms 的间隔执行最多 3 次重试。
- 最小验证/判定：执行AppSessionRuntime.queryHistoryWithBudget实际调用路径，用可达暂时查询失败观察首次+100/250/500ms三次预算以及成功即停；检查总attempt、延迟、取消和非暂时错误不重试。
- 顺序：G2；058/061先明确DB/UI唯一预算所有者；当前Runtime持具体SessionCoordinator且query方法private，无现成注入，先确认可复用App headless测试构建入口；没有入口时记录具体边界，不实现新产品行为。
- 不可替代：ErrorCoordinatorTests表测试、直接调用RetryPolicy或预置fixture不等于App查询重试；不能用coordinator已停止产生notRunning假装暂时SQLite失败。
- 任务/TC：T06.1 / T07.4；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#uiHistoryBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ErrorCoordinatorTests.swift#uiHistoryBudgetIsIndependentFromDatabaseBudget()

### REQ-069 用户仍能看到已有状态

- 范围：在 UI 数据读取重试期间，前端构件应显示最后一次成功取得的缓存数据。
- 最小验证/判定：在068同一App运行路径先得到一份成功历史/展示状态，再触发暂时读取失败，逐次重试期间断言仍保留同份最后成功数据，失败未生成新Raw/EMA且未把previous转成新的ready。
- 顺序：G2；依赖068可控真实调用路径；先核对“缓存数据”指历史刷新还是传感器观测年龄的边界。
- 不可替代：直接预置cached、共享ViewModel或单独previous状态测试不证明重试过程。
- 任务/TC：T06.1 / T07.4；TC-ERROR
- 现有入口：software-fixture:UITests/TemperatureMonitorUITests.swift#testCachedFixtureLabelsStatusAndReadFailure()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/PresentationModelTests.swift#valueStatesAreMutuallyExclusive()

### REQ-071 建立失败出口

- 范围：如果 UI 数据读取经过 3 次重试仍失败，则故障管理构件应生成 `UI-DATA-001`。
- 最小验证/判定：在068路径首次及追加3次查询均失败，断言UI-DATA-001、retryCount=3、真实Fatal报告/状态且停止继续query；取消/superseded不得计Fatal。
- 顺序：G2；依赖058/061预算归属与068；给072提供关键UI耗尽分支。
- 不可替代：SENSOR-READ-002预置Fatal fixture、CPU耗尽或UI预算常量不能替代。
- 任务/TC：T06.1 / T07.4 / T07.5；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#uiHistoryBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ErrorCoordinatorTests.swift#uiHistoryBudgetIsIndependentFromDatabaseBudget()

### REQ-072 关键故障与可选能力分级

- 范围：当关键 CPU 主指标、存储、加工或关键 UI 数据故障达到对应重试上限时，故障管理构件应提升为 Fatal；可选 SSD/Battery 的单项读取耗尽应标为不可用并保留 CPU 监控。
- 最小验证/判定：汇总已测CPU耗尽Fatal、DB写耗尽、可选SSD/Battery隔离继续CPU；补071的关键UI耗尽，按064–067判定列明加工条件适用性；核对单项可选失败不能停CPU。
- 顺序：G2；依赖071和064–067结论；真实生命周期回归不能免除各链路条件。
- 不可替代：不能从CPU一条Fatal路径推断所有关键链路，或把可选失败也统一Fatal。
- 任务/TC：T06.1 / T06.4 / T07.5；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SensorRecoveryRegressionTests.swift#repeatedCPUTimeoutStopsAtRetryBudgetAndReportsFatal()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/StorageLifecycleRegressionTests.swift#writeRetryExhaustionUsesFiveAdditionalAttemptsAndWriteError()

### REQ-100 验证数据链

- 范围：在 M2 完成时，测试流程应对传感器、数据加工和 SQLite 数据路径执行集成测试。
- 最小验证/判定：绑定最终生产提交对应EndToEndTests.fullCPURawToHistorySoftwareLoop及MonitorIntegrationTests真实SQLite链路执行日志，核对Qualified12→Raw max→EMA→聚合→SQLite→history的同一输入/Receipt/sampleID。记录M2当时集成报告顺序。
- 顺序：G5；源代码变化后需当前适用回归；catalog整体门禁结束后单独复核结论。
- 不可替代：孤立算法PASS、原型或跨提交拼接测试计数不能替代产品集成链路和阶段事实。
- 任务/TC：T05.5 / T08.3 / T11.1；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

## 文档条件适用性或实现差异待判定（12项）

### REQ-058 允许短时锁竞争和 I/O 波动恢复

- 范围：如果 SQLite 操作发生暂时性失败，则数据存储构件应按照 100 ms、250 ms、500 ms、1000 ms、2000 ms 的间隔执行最多 5 次重试。
- 最小验证/判定：先列出生产private-cache/WAL的SQLite暂时失败来源和唯一重试所有者；区分已测写预算首次+5与查询/UI预算。现有StorageLifecycleRegressionTests把等待改为五个1ms，默认100/250/500/1000/2000只由策略表核对；必要写路径补默认配置实际等待/恢复/耗尽证据，再按读操作适用判定选择读取向量。
- 顺序：G1；与061共同先于068/071/072总链路结论；既有写重试证据保留。
- 不可替代：不能将五个1ms的执行结果称为默认等待实测，不能把“SQLite操作”静默缩成写操作，也不能用shared-cache/DELETE锁构造生产并不存在的读失败或嵌套DB5×UI3。
- 任务/TC：T03.3 / T05.3 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#databaseBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/StorageLifecycleRegressionTests.swift#temporaryWriteFailureRetriesSameBatchAndPayload()

### REQ-061 读取和写入故障分离

- 范围：如果 SQLite 读取经过 5 次重试仍失败，则故障管理构件应生成 `DB-READ-004`。
- 最小验证/判定：找到符合生产连接模式的真实可达暂时读取错误，记录SQL/结果码/发生条件及DB5预算归属；适用时执行生产读取路径首次+5耗尽，断言DB-READ-004及retryCount=5。若不可达，保留pending并提交具体条件判定。
- 顺序：G1；依赖058预算与可达性判定；不能先实现新重试包装来制造符合测试的路径。
- 不可替代：private-cache WAL下外部BEGIN EXCLUSIVE+DDL不阻断已有reader普通SELECT；不能改journal/cache模式、复用写错误或表测试冒充。
- 任务/TC：T03.3 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#databaseBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ErrorCoordinatorTests.swift#uiHistoryBudgetIsIndependentFromDatabaseBudget()

### REQ-064 避免单个任务无限循环

- 范围：如果一次数据加工任务发生暂时性执行失败，则对应加工构件应按照 50 ms、100 ms、200 ms 的间隔执行最多 3 次重试。
- 最小验证/判定：逐列生产EMA/聚合/趋势可抛出错误及来源；确认是否存在暂时性纯加工失败。当前EMA唯一throw为确定性nonPositiveDeltaTime，聚合/趋势非throwing。先形成条件可达性/不可达性判定，必要时由维护者审查契约解释。
- 顺序：G1；065–067及072依赖该判定；本任务不新增故障接口或重试机制。
- 不可替代：不能把DB写失败、Lease/Receipt/schema/非法dt重命名为暂时加工失败；不能制造假生产故障或仅测processing预算表。
- 任务/TC：T04.2 / T04.4 / T04.5 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingValidateIsNotRetryable()

### REQ-065 EMA 独立定位

- 范围：如果 EMA 任务经过 3 次重试仍失败，则故障管理构件应生成 `PROC-EMA-002`。
- 最小验证/判定：在064结论中单列EMA：nonPositiveDeltaTime为结构性确定错误，不能重试恢复；仅存在真实暂时条件时才需要生产50/100/200ms耗尽→PROC-EMA-002向量，否则保存适用性待判定。
- 顺序：G1；依赖064；不能为了耗尽码而给纯EMA加入人为throwing transport。
- 不可替代：拒绝非法dt、预算表或持久化commit失败不证明EMA暂时失败重试耗尽。
- 任务/TC：T04.2 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingValidateIsNotRetryable()

### REQ-066 聚合独立定位

- 范围：如果聚合任务经过 3 次重试仍失败，则故障管理构件应生成 `PROC-AGG-003`。
- 最小验证/判定：在064结论中单列聚合：确认非throwing确定性计算和DB提交边界；仅有真实暂时纯聚合条件时验证生产耗尽PROC-AGG-003，否则保持条件判定待闭合。
- 顺序：G1；依赖064及commit/receipt归属核对。
- 不可替代：failedAggregationCommitRetainsWindowForRetry是持久化提交证据，不能直接证明纯聚合暂时失败。
- 任务/TC：T04.4 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingValidateIsNotRetryable()

### REQ-067 趋势独立定位

- 范围：如果趋势任务经过 3 次重试仍失败，则故障管理构件应生成 `PROC-TREND-004`。
- 最小验证/判定：在064结论中单列趋势：区分点数不足/coverage不足/Gap的正常insufficient状态与错误；仅有真实暂时条件时验证生产耗尽PROC-TREND-004。
- 顺序：G1；依赖064；不把正常无结果升级Fatal。
- 不可替代：coverage不足、两点输入、Gap、DB失败或预算常量不等于暂时趋势错误。
- 任务/TC：T04.5 / T06.1；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingBudgetMatchesContract()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RetryPolicyTests.swift#processingValidateIsNotRetryable()

### REQ-079 错误追踪主键

- 范围：当错误报告生成时，错误报告构件应记录封闭枚举中的稳定错误代码，并按适用范围记录强类型 requestID、sourceID、batchID、gapID 或 watermarkEventID，禁止以可互换自由字符串代替事件身份。
- 最小验证/判定：按request/source/batch/gap/watermark实际可发生的故障逐项建立“事件→原始强类型ID→FatalReport字段”表。现有MonitorFailure只有SourceID?，ReportPayload无事件身份字段；先核对正文按适用范围的模型/契约差异，再用实际生产报告JSON断言对应ID。
- 顺序：G1；先判定事件适用条件，不制造不存在的故障；与082共用报告身份审核，未经批准不改契约或字段。
- 不可替代：UUID类型存在/往返、session_id、把ID塞入underlyingCode或不同事件互换自由字符串不能代替报告字段。
- 任务/TC：T01.2 / T05.3 / T06.2；TC-ERROR / TC-VALIDATE / TC-UPSTREAM-BOUNDARY
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ContractCoverageTests.swift#taggedUUIDTypesEncodeAndDecode()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ContractCoverageTests.swift#presentationAndMonitorFailureRoundTrip()

### REQ-082 定位具体传感器

- 范围：当传感器相关错误报告生成时，错误报告构件应记录对应 `sensor_id`。
- 最小验证/判定：对确有单一QualifiedSource的传感器故障，执行生产报告writer并核对JSON source_id与当次故障SourceID相等；当前ReportPayload实际无source_id，catalog reason称已序列化需纠正判断依据。先从SamplingService无效success规范化入口取得非nil sourceID作报告复核，再单列QualifiedSensorClient.transport failure当前固定sourceID=nil的身份传递边界；确认实际差异后再决定后续工作。
- 顺序：G1；依赖079身份表；CPU整批timeout可无单一source，应另列不适用而非伪造source。
- 不可替代：MonitorFailure SourceID往返、无机器序列号测试或无单一source的整批超时不覆盖正文条件。
- 任务/TC：T06.2；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ContractCoverageTests.swift#presentationAndMonitorFailureRoundTrip()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/DiagnosticsTests.swift#reportWriterDoesNotIncludeMachineSerialField()

### REQ-099 编码前设计门禁

- 范围：在进入 M2 前，项目应完成需求基线和架构设计评审。
- 最小验证/判定：回读首次M2之前的需求/架构设计评审提交、PR/报告及提交顺序，确认当时基线；另复核当前W11完整矩阵。历史先后不可由今天补文档反推，缺证据继续pending。
- 顺序：G5；历史回读可与G2并行；catalog当前把099–106保留到整体门禁复核，最后逐项判定。
- 不可替代：当前handoff通过、今日审查或某E2E不能证明“进入M2前已评审”。
- 任务/TC：T11.1 / T11.2；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

### REQ-104 形成开发阶段门禁

- 范围：在任一里程碑存在未解决阻塞缺陷时，开发流程应禁止进入下一里程碑。
- 最小验证/判定：按各里程碑保存blocking Issue/required check/独立审查及进入下一阶段的Git时间线；当前#46/#47未有新同hash实机回归时，相关资格/最终交付不得越过。最终再读取exact-head blocking状态。
- 顺序：G5；依赖已确认问题闭合及真实GitHub现状；历史和当前快照分开。
- 不可替代：历史PR44零blocking、当前本地无失败或只改Issue标签不能证明本轮可跨阶段。
- 任务/TC：T11.2 / T11.3；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

### REQ-105 封闭“所有文档”的范围

- 范围：在首次进入 M2 前，项目应完成本规格列明的设计文档，并使 00、01、21、22、23 及 contracts 中的机器契约共同覆盖身份、接口、存储、测试、第三方来源和执行顺序，不依赖聊天记录补全实现规则。
- 最小验证/判定：独立核对00/01/21/22/23及contracts对身份、状态、存储、测试、许可和顺序的覆盖；保存handoff/API typecheck/DDL验证及首次M2前文档提交祖先证据。
- 顺序：G5；G1判定若需文档调整须走授权/契约同步；当前矩阵整体复核后逐项结论。
- 不可替代：当前JSON存在、聊天解释、旧revision2检查或只验证链接不能证明修订3完整边界及历史顺序。
- 任务/TC：T11.1 / T11.2；TC-DOCS / TC-ACCEPTANCE / TC-UPSTREAM-BOUNDARY
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

### REQ-106 防止未确定业务规则被编码 Agent 自行填充

- 范围：在任一必需设计文档仍含阻塞级待澄清事项时，项目应禁止进入正式功能编码阶段。
- 最小验证/判定：列出必需文档阻塞级待澄清项和首次编码时处理记录；当前058/061/064–067/079/082需明确适用/差异判断，独立审查确认有无阻塞再定阶段状态。
- 顺序：G5；依赖G1条件判定与105文档完整性；没有明确结论时保留pending。
- 不可替代：不允许把所有TBD一律认作阻塞，也不能删TBD、口头假设或继续编码来证明不存在阻塞。
- 任务/TC：T11.1 / T11.2；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

## 已确认 bug，新证据待集成及剩余组合回归（1项）

### REQ-078 确定最终状态

- 范围：当用户在 Fatal 界面选择退出或界面可见满 30 秒时，系统应在 5 秒收尾预算内停止当前运行，并记录未完成清理以供下次启动处理。
- 最小验证/判定：先将#47新Release运行中Fatal自动退出PASS的原始记录、新source/App/worker身份集成并独立审查；该记录有故障注入后32.369s退出、Session删除及报告保留。仍补核Fatal退出按钮、可见计时起点、≤5s收尾及未完成步骤/下次启动的组合条件，不能直接整项accepted。
- 顺序：G3；依赖新生产提交/二进制冻结、独立审查和#46睡眠取消语义；先不干预根agent串行验收。
- 不可替代：旧a97移除worker启动fallback约31s、正常quit、最小RunLoop探针或新软件GREEN不能拼成runtime Fatal实机完整通过。
- 任务/TC：T06.4 / T07.5 / T09.3；TC-ERROR
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SessionLifecycleTests.swift#fatalDisplayReceiptExpiresAfterConfiguredDuration()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/RuntimeShutdownRegressionTests.swift#fatalFreezeStopsIOButPreservesDatabaseUntilQuit()

## 需要实机交互或最终资格审查（10项）

### REQ-039 禁止跨应用运行周期恢复历史

- 范围：当应用发现上一运行周期遗留的监控数据库时，数据库构件应清除其中的监控历史数据。
- 最小验证/判定：在隔离验收目录用当前正式Release生成有效session/marker和监控库，受控强制结束后重新启动同构建，记录只清旧合法会话且新会话无旧历史；同时保存旧日志和进程/目录快照。
- 顺序：G4；先完成#46/#47新构建身份冻结；不得干预根agent串行验收；联合042/078的恢复边界。
- 不可替代：SessionCleanup单元测试、手工删库、正常quit或不含有效marker的目录不证明App启动接线。
- 任务/TC：T06.3 / T08.1 / T09.3；TC-RETENTION / TC-LIFECYCLE
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SessionLifecycleTests.swift#cleanupRemovesOrphanedMarkedSession()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/SessionLifecycleTests.swift#cleanupRequiresHeldLock()

### REQ-077 确定后续操作

- 范围：当 Fatal 错误界面显示时，界面应提示用户重新启动应用，并提供打开报告、复制详情和退出操作。
- 最小验证/判定：先核对当前FatalView实际只有倒计时、复制报告路径和退出，正文要求的重启提示/打开报告/复制详情不能由这些替代。核实最终候选实际交互是否满足；正式Fatal后逐项截图并验证打开的精确报告目标、剪贴板详情与退出。
- 顺序：G4；先处理源码/正文差异的实际确认，依赖#47及078可靠退出；本清单不新增功能或自动认定通过。
- 不可替代：不能用按钮exists、复制路径、Settings报告目录入口、启动fallback或截图文字替代实际动作和正文内容。
- 任务/TC：T07.5；TC-ERROR
- 现有入口：software-fixture:UITests/TemperatureMonitorUITests.swift#testFatalFixtureShowsFatalCodeInDashboard()；software-fixture:UITests/TemperatureMonitorUITests.swift#testSettingsHasDiagnosticsAndLicenseEntries()

### REQ-094 需求规格直接成为黑盒测试依据

- 范围：在用户可见功能 feature branch 申请合并前，测试流程应执行对应 EARS 验收测试。
- 最小验证/判定：在最终候选上汇集每条用户可见EARS的黑盒日志：菜单/Popover、档位及历史、读取重试/Fatal、关窗重开退出、五档600s和真实sleep；结合当前exact-head CI，逐条核对而非整组推断。
- 顺序：G5；依赖068/069/071/077/078/117–119、G4正式资格及当前CI；现有子集仍保留。
- 不可替代：8s五档、fixture全面PASS、主窗口可用或旧head CI不证明全部用户可见EARS。
- 任务/TC：T07.5 / T09.2 / T09.3 / T11.1；TC-WORKFLOW
- 现有入口：software-fixture:UITests/TemperatureMonitorUITests.swift#testCPUPeriodPickerSupportsAllFiveOptions()；software-fixture:UITests/TemperatureMonitorUITests.swift#testCachedFixtureLabelsStatusAndReadFailure()

### REQ-101 验证原生 UI

- 范围：在 M3 完成时，测试流程应对菜单栏、透明面板和主窗口执行 UI 黑盒测试。
- 最小验证/判定：汇集最终候选菜单栏物理点击、Popover半透明和状态、主窗口的UI黑盒操作/截图；核对M3所需完整面，不把主窗口测试代表菜单面板。
- 顺序：G5；依赖117/118/119和当前UI执行证据，最后复核阶段报告。
- 不可替代：主窗口10张截图、共享组件、AX exists或ViewModel不证明三个原生UI入口均验收。
- 任务/TC：T07.2 / T07.5 / T11.1；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

### REQ-102 验证全部构件协作

- 范围：在 M4 完成时，测试流程应执行完整系统测试。
- 最小验证/判定：对最终同hash候选形成完整系统测试报告，合并自动化链路/异常向量与正式sources+schedules+lifecycle，明确未适用条件和用户豁免；完整系统是逐用例证据审查结论。
- 顺序：G5；依赖G1条件判定、G2软件缺口、#46/#47新硬件回归及G4；独立审查后再判定。
- 不可替代：TC组都引用一份报告、覆盖率≥80%或单个短会话不能证明完整系统。
- 任务/TC：T08.3 / T09.2 / T09.3 / T11.2；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

### REQ-103 Release Candidate 直接对应需求基线

- 范围：在 M5 完成时，测试流程应执行最终 EARS 验收测试。
- 最小验证/判定：冻结最终RC source/App/worker/profile/签名后，审查132项逐REQ有效证据、012/114retired、授权豁免和全部剩余pending；运行product-acceptance门禁并保存最终EARS验收结论。
- 顺序：G5；最后执行，依赖其余适用缺口及独立审查；不得批量改结果跳过真实缺项。
- 不可替代：只跑binder dry-run、当前94accepted、按TC组自动填PASS或未来计划不是最终EARS。
- 任务/TC：T11.1 / T11.2 / T11.3；TC-DOCS / TC-ACCEPTANCE
- 现有入口：ci:W00文档/工作流历史设计入口；PR44 head357五项门禁通过、merge403与零blocking；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/EndToEndTests.swift#fullCPURawToHistorySoftwareLoop()

### REQ-110 最低系统与按证据声明支持

- 范围：项目应将最低运行系统要求保持为 macOS 15.7.3，并分别记录 build_toolchain、deployment_target、runtime_profile 和 qualified_combinations；只有绑定正式 App SHA、签名、机型、系统版本/build及通过用例的组合才能声明支持。
- 最小验证/判定：对含#46/#47修复的最终同一App/worker hash保存build_toolchain、deployment_target(最终load command)、runtime_profile、qualified_combinations；完成CPU12/可选sources、五档各≥600s、真实sleep/wake及进程/退出证据后才登记本机组合。
- 顺序：G4；先G0冻结身份和G3新构建回归；五档及真实系统睡眠可分轮但必须同一二进制，其他修改后重评受影响证据。
- 不可替代：旧14cac/a97组合、五档各8s、被合盖打断约305s、Controller.suspend/resume、源码推断或CI不等于新正式组合资格。
- 任务/TC：T09.1 / T09.2 / T09.3 / T09.4；TC-PLATFORM / TC-SENSOR / TC-UPSTREAM-BOUNDARY
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/AppBundleConfigurationTests.swift#appResourcesMatchBundledContracts()；software:Packages/TemperatureCore/Tests/TemperatureCoreTests/ConfigurationTests.swift#bundledProfileHasTwelveCaseSensitiveKeys()

### REQ-117 菜单栏交互

- 范围：当用户点击菜单栏图标时，界面构件应显示温度信息弹出面板。
- 最小验证/判定：在实际屏幕上用正式Release物理点击可见status.temperature，记录前后截图/操作时间及真正出现的Popover；同时核对左右键、Esc/外点关闭的TC-UI要求，窗口替代入口单列。
- 顺序：G4；先确认屏幕/菜单栏拥挤或刘海条件；不得为本清单启动App、改用户菜单布局或干预根agent长测。
- 不可替代：AX exists/isHittable=false、showPopoverForTesting、直接开Dashboard/标准reopen或菜单item源码不能替代物理点击。
- 任务/TC：T07.2 / T09.3；TC-UI
- 现有入口：software-fixture:UITests/TemperatureMonitorUITests.swift#testBasicFixtureShowsLiveTemperature()；formal-app-hardware:a97fd5a#status.temperature AX exists=true、isHittable=false；窗口/reopen替代入口已实测

### REQ-118 弹出面板

- 范围：在温度信息弹出面板打开时，面板应显示当前可用硬件的EMA温度，并为不可用、缓存或过期指标显示明确状态。
- 最小验证/判定：117打开真实Popover后保存实际EMA值/来源/状态与对应Snapshot的一致证据；软件层另对实际Popover运行live/cached/stale/unavailable状态渲染并分类保存，未出现的硬件故障状态明确未实测，按逐条件范围复核。
- 顺序：G4；依赖117；受控Debug输入只能补软件状态渲染，正式实际来源场景须单独证据。
- 不可替代：Dashboard状态截图、共享Model、预置cached或Unavailable不能被标成正式App真实故障/Popover实测。
- 任务/TC：T07.2 / T07.5；TC-UI
- 现有入口：software:Packages/TemperatureCore/Tests/TemperatureCoreTests/PresentationModelTests.swift#valueStatesAreMutuallyExclusive()；software-fixture:UITests/TemperatureMonitorUITests.swift#testCachedFixtureLabelsStatusAndReadFailure()

### REQ-119 透明视觉

- 范围：温度信息弹出面板应使用 macOS 原生半透明视觉效果。
- 最小验证/判定：实际打开正式Popover，在可见桌面背景上保留原生半透明视觉截图，记录浅/深色与减少透明度设置状态；核对TemperaturePopover原生material实现与截图对应。
- 顺序：G4；依赖117真实打开；如当前系统减少透明度导致不透明须如实记录条件，不擅改用户设置。
- 不可替代：原生material源码、主窗口/状态项截图、渲染mock或透明图层示意不能替代实际Popover屏幕效果。
- 任务/TC：T07.2；TC-UI
- 现有入口：software-source-audit:403d44b#TemperaturePopoverView使用原生material背景，非自绘透明模拟

## 证据写入规则

每个新增报告保存实际source commit、App/worker SHA256、signature、profile、model/OS build、执行种类、输入/预期/实际及原始日志。软件、Debug fixture、正式Release硬件和CI分别标注。不得回写a97/651历史报告；先校验文件hash/Git ancestry、再局部更新catalog结果并运行binder/handoff。

064–067的可达性判定不能擅自删需求或将其整项waiver；079/082不能用字段缺测的措辞掩盖当前序列化模型的实际差异；077不能把复制报告路径解释为复制详情。后续如果出现可复现失败，再按项目Issue流程处理；本清单没有建立新bug。

机器可读JSON包含每项当前covered_cases、outstanding快照和权威文档SHA256，供根agent将本轮长测结果局部整合。错误类现有测试的1ms等待、App查询测试接入及报告身份差异已在各条最小动作中明确；本清单不依赖临时补充报告。

## 新证据待集成状态

本轮保持94项accepted、37项pending、1项waived。#46启动/睡眠history取消的App生产路径软件harness已有GREEN，#47正式Release真实运行中Fatal自动退出已有PASS；尚需纳入新生产提交、App/worker hash及仓内artifact。退出途中wake取消目前已有RED，GREEN/独立复核待确认。软件harness不是目标Mac真实系统sleep/wake资格。

最新50ms长测失败，最后UI进度265.752s，数据库末elapsed325.833s，runner371.103s含清理；没有600s阶段结束，其他四档未由本轮通过。三个时间口径不得混用，五档验收仍pending。临时原始路径及实际文件hash保存在本清单JSON的`new_evidence_integration_status`，只供集成取证线索，未作为仓内不可变artifact或新的accepted依据。
