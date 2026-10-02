# 2026-10-02 产品缺陷修复与验证：a97fd5a

## 结论

R01–R17（Issue #27–#43）已完成对应代码修复。最终代码核心 **337 tests / 52 suites通过，行覆盖7059/7966=88.61%**；独立复核同源337项通过，未发现剩余可复现重要代码缺陷。目标Mac的正式Release短时验证已通过CPU12→Raw max→EMA→SQLite、5min/1h历史、五档切换、Battery/SSD状态、标准窗口重开及正常退出清理。结论支持本机短时正常使用，不将测试计数或覆盖率解释为全部需求完成率。

受控Release副本移除worker后，启动Fatal显示APP-INIT-001/missingSensorWorker及30秒退出提示，无按钮或强制结束，首观察进程到退出约31.464s（含初始化与关停）。此证据只覆盖启动fallback；运行中故障与真系统休眠仍采用软件回归和源码证据。

## 版本、环境与证据范围

- 最终代码：`a97fd5a8d6ec53c957be7b05de2a3803e24effc2`；分支`feature/product-audit-fixes`；修复基线`0b720deb1d7fe170e55999f2709a3665634746da`。
- 原始审查：`48cd967d835e5c9f2ad2f191d97eb32a92623bcd`的[历史报告](../../product-review/2026-10-02-48cd967d/report.md)，保持原样，不用本报告回写旧结果。
- Mac16,13；macOS15.7.3 /24G419；Xcode26.3 /17C529；Swift6.2.4；SDK26.2；本机执行arm64，Release构建arm64+x86_64。
- 唯一接口为contract revision3；本轮增加NVMe位置/查询状态的发现事实并同步契约、需求、追踪、资源、测试和门禁；SQLite schema仍为1。
- 全部温度须来自Qualified来源；CPU固定12热区。逐物理核心/core_id及物理Package保证继续退役。
- 用户明确豁免72/73h实机耐久、公证、公开发行及跨机型认证。这些项目不计作本轮未修缺陷；72h历史功能范围与72h耐久测试区分处理。
- 软件输入、fixture UI、正式硬件和故障副本分别记录。原始审查只登记R01–R10；R11–R17为后续追加问题。独立I01旧来源Gap、I02长睡眠另列，不改变R11/#37及R12/#38的含义。

## 最终验证汇总

| 项目 | 结果 | 支持范围与证据 |
| --- | --- | --- |
| 核心测试 | 337 /52通过 | [最终日志](logs/core-tests-final.log)，包含提交失败、重入、生命周期、可选来源、身份、Gap和存储异常回归 |
| 核心行覆盖率 | 7059/7966=88.61%，超过80% | [覆盖日志](logs/core-coverage-final.log)；仅TemperatureCore/SensorRuntime生产Swift，不含App UI、C bridge、worker入口及CSQLite |
| 独立同源测试 | 337 /52通过 | [独立日志](logs/independent-core-tests-final.log)及[独立报告](independent-review.md)；162份代码/资源/契约hash与最终提交一致 |
| Fixture UI | 18项报告，16实际执行通过、2条件跳过、0失败 | [日志](logs/ui-fixtures.log)；跳过不是执行通过，fixture不能替代正式App |
| 正式Release真实UI | 1项通过、0失败，84.800s | [日志](logs/ui-real-release.log)；CPU12、可选状态、5min/1h、五档各等待8s、关闭后标准重开保留会话、app.quit删除目录 |
| 正式SQLite链 | 5650 Raw、5650 EMA、674批次 | [脱离用户目录路径的快照汇总](hardware/live-summary.json)；420个主样本均有12成员，Raw=max不符0，foreign-key violation0 |
| 分层聚合 | 1/10/60s均有记录 | 最后快照分别959/90/15行；不是完整24h/72h实机历史 |
| 正式正常退出 | 通过 | UI断言本次目录删除；[清理观测](hardware/cleanup.json)剩余会话数据库0 |
| 受控启动Fatal | 自动退出通过 | [计时观测](hardware/fatal-negative-timed-observation.json)、[报告](hardware/fatal-negative-report.json)；移除worker的已重签名副本，首观察至消失31.4639s |
| 最终Release构建 | BUILD SUCCEEDED | [构建日志](logs/release-build.log)；主App及worker本机ad-hoc签名 |
| 签名及Release上游边界 | 独立复核通过 | [独立报告](independent-review.md)；签名有效性不等于公证 |
| 上游禁止行为反例门禁 | 通过 | [实际成功重跑](logs/upstream-boundary-negative.log)；先前沙箱权限错误属基础设施，未视为产品缺陷 |
| 资格schema工具 | 8 checks通过 | [日志](logs/qualification-schema.log)；另有[本机资格产物](hardware/sources.json)，不能将schema工具当成硬件功能验收 |
| 文档交接及API typecheck | 通过 | [handoff](handoff.json)：revision3、132 active、50tasks、20TC；typecheck见独立报告，handoff只验证文档契约 |

覆盖率以最终`core-commit-coverage-gate.log`的88.61%为准；修复过程中88.73%/88.74%属不同运行产物，不作为当前版本数值。

## R01–R17 / Issue #27–#43 修复与验收映射

下面每项软件回归均包含在最终337项通过记录内。右列明确真实测试与尚未实际执行的边界；不根据测试函数名或日志文件名推断通过。

| 缺陷 | 最终改动 | 主要软件回归 | 实机/验收边界 |
| --- | --- | --- | --- |
| R01 / [#27](https://github.com/sisyphe550/Temperature-monitoring/issues/27) 历史时钟和首次装载 | 父会话、worker、Snapshot及历史查询共享连续时钟基准；初次有效Snapshot选择来源后装载并受限刷新，替代查询取消旧结果。 | `sharedBasisProducesSameOriginForTwoClocks`<br>`realWorkerKeepsParentClockOriginAcrossConnectionRestart` | 正式Release的5min/1h选择有当前会话数据；worker重启原点由真实worker软件回归验证。 未在运行中的正式App注入worker故障；真实历史观察只有本次短会话。 |
| R02 / [#28](https://github.com/sisyphe550/Temperature-monitoring/issues/28) 在途登记残留导致水位冻结 | 按RequestID保存planned start，success/failure/stale/cancel/stop配对终结；actual时间继续用于样本，不拿actual start清除planned登记。 | `completedNonzeroReadReleasesPlannedWatermarkStart`<br>`failedOrStaleReadReleasesWatermarkRegistration`<br>`stopCancelsInFlightReadAndReleasesWatermarkBeforeReturning` | 最终实机SQLite产生1/10/60s三层聚合。 故障/取消释放路径属于可控软件回归。 |
| R03 / [#29](https://github.com/sisyphe550/Temperature-monitoring/issues/29) 超时永久停采和运行错误失联 | CPU失败接有限重试、重发现及Fatal；加工/持久化失败接诊断和报告；Fatal冻结采样，退出时走统一等待清理。 | `oneRecoverableTimeoutDoesNotPermanentlyStopProductionSampling`<br>`repeatedCPUTimeoutStopsAtRetryBudgetAndReportsFatal`<br>`fatalFreezeStopsIOButPreservesDatabaseUntilQuit` | 受控Release副本启动缺worker显示APP-INIT-001并约30s自动退出；正常Release无Fatal。 受控负例只覆盖startup fallback，不是运行中传感器/数据库故障实测。 |
| R04 / [#30](https://github.com/sisyphe550/Temperature-monitoring/issues/30) 睡眠通知与唤醒RequestID | App接NSWorkspace睡眠/唤醒，串行调用生命周期；请求ordinal在全会话不复用，醒后首读被接受。 | `wakeFirstReadUsesNewRequestIdentity`<br>`sleepWakeOpensAndClosesSleepGap` | 软件睡眠/唤醒回归通过；系统通知接线经独立源码审查。 没有执行目标Mac真实合盖/系统休眠。 |
| R05 / [#31](https://github.com/sisyphe550/Temperature-monitoring/issues/31) Receipt前推进加工状态 | 暂存样本序列、EMA、聚合及生命周期变化，合法Receipt后交换；await期间按事件合并注册，失败保留可重试状态。 | `failedReadCommitCanRetryWithoutAdvancingSamplesOrSequence`<br>`failedAggregationCommitRetainsWindowForRetry`<br>`concurrentAcceptsCommitDistinctSampleIDsAndOrderedEMA`<br>`inFlightRegistrationSurvivesAggregationCommit` | 提交失败、重试及actor重入软件回归通过。 没有在正式App真实磁盘上制造IO故障。 |
| R06 / [#32](https://github.com/sisyphe550/Temperature-monitoring/issues/32) TTL与Lease/请求元数据无界 | 运行每60s执行prune；终结reservation回收且取消幂等；请求SHA256指纹缓存按300s/16384上限清理，过期重放显式拒绝，同请求异Lease拒绝；写/prune/close串行，写重试保持同BatchID/同payload。 | `runningControllerPrunesExpiredRawWithCommittedParentWithoutSleep`<br>`expiredRequestCannotBeReintroducedAsNewTemperature`<br>`finalizedReservationMetadataDoesNotGrowWithSessionReads`<br>`temporaryWriteFailureRetriesSameBatchAndPayload`<br>`lostCommitAcknowledgementRetriesWithoutDuplicateSamples`<br>`repeatedRequestCannotClaimNewUnconsumedLease` | SQLite TTL、缺父层保留、固定payload重试、伪造Lease、WAL/容量及重入回归通过。 最终短会话不足以覆盖Raw300s+宽限及长期容量压力；不将短测写成耐久通过。 |
| R07 / [#33](https://github.com/sisyphe550/Temperature-monitoring/issues/33) 退出未等待数据库清理 | applicationShouldTerminate等待正常关停；worker/已接纳写入完成后关闭并删除SQLite/WAL/SHM及本次会话目录，重复stop幂等。 | `stopWaitsForSessionDeletionAndIsIdempotent`<br>`closeWaitsForAcceptedWriteAndDeletesAllDatabaseFiles` | 正式Release点击app.quit后进程结束、本次会话目录删除，SQLite轮询剩余数据库=0。 强制SIGKILL/掉电恢复不属于本次真实UI用例。 |
| R08 / [#34](https://github.com/sisyphe550/Temperature-monitoring/issues/34) 缺CPU成员仍生成主值 | 正式profile启动/恢复要求固定12成员及正确编码；不足或损坏不能用子集派生CPU最高温度，也不能以loading隐藏关键失败。 | `missingOneRequiredCPUMemberStopsStartup`<br>`firstCPUFailureHasExplicitMainValueFailureState`<br>`cpuMaxSkippedWhenMemberMissing` | 实机12键与12个UI成员一致；420个主值均关联12成员且等于同批Raw max。 缺成员/坏编码为软件故障输入，不能外推其他机型。 |
| R09 / [#35](https://github.com/sisyphe550/Temperature-monitoring/issues/35) Battery/SSD资格化与采样饥饿 | Battery/SSD经Registry进入Qualified catalog；NVMe discovery保留Internal位置及查询状态，按证据解码Kelvin；同相位串行IO公平，可选单项有限失败隔离不杀CPU。 | `nonzeroCPUReadDoesNotStarveSimultaneouslyDueOptionalSources`<br>`profileQualifiesOnlyHighestPrioritySMCBatterySource`<br>`absentOptionalProvidersProduceExplicitCapabilityRecords`<br>`optionalRecoveryRequiresThreeCommittedReadsAndKeepsCPUAlive` | 本机Battery TB1T及唯一Internal NVMe SSD被选中，正式App两者有Raw/EMA和明确状态行。 不承诺任意SSD/Battery设备可用；可选故障及三次恢复边界由软件回归验证。 |
| R10 / [#36](https://github.com/sisyphe550/Temperature-monitoring/issues/36) 高频历史截尾与显示边界 | 全请求范围减点，按series/segment/Gap分隔并保留边界、min/max与count；每条series跨segment总预算有界，不可表示时明确失败；加来源选择、时间轴、温度比较和cached/stale原因。 | `fiveMinutesPreservesFullRangeAndExtrema`<br>`sqliteBudgetAppliesAcrossSegmentsWithoutLosingPeaksOrCounts`<br>`explicitGapBreaksLineEvenWithinOneSegment`<br>`fiveMinuteHistoryRetainsPriorSourceDefinitionWithoutJoiningSeries` | 50/100ms完整300s软件输入及SQLite跨段预算通过；正式App短时5min/1h、两来源选择与比较区域通过。 真实UI只装载当前短会话，不是完整24h/72h实机历史。 |
| R11 / [#37](https://github.com/sisyphe550/Temperature-monitoring/issues/37) CPU max的period_ms固定200 | 派生max的Raw使用该ReadBatch.requestedPeriodMS；在途批次保持原周期，不能取当前picker值或定义默认200ms。 | `pendingCPUReadUsesItsRequestedPeriodAfterPickerChanges` | 实机cpu.zone.max五档period_ms=50/100/200/500/1000均落库，计数194/98/95/19/14。 本轮各档等待8s，不是5×10min性能/节拍验收。 |
| R12 / [#38](https://github.com/sisyphe550/Temperature-monitoring/issues/38) 重连generation未进入来源身份 | Registry把新catalog/connection generation纳入SourceID；SeriesID/定义随来源实例换代，旧代历史独立保留，禁止重连后复用旧身份。 | `reconnectCreatesNewSourceAndSeriesIdentities`<br>`fiveMinuteHistoryRetainsPriorSourceDefinitionWithoutJoiningSeries` | 代际身份不相交和旧代5min历史隔离软件回归通过。 没有在本轮正常正式App运行中强制重连物理传感器。 |
| R13 / [#39](https://github.com/sisyphe550/Temperature-monitoring/issues/39) 读失败缺Gap且恢复EMA跨段 | 失败或dt超Gap阈值生成Gap；CPU主值随任一必需成员失败打开Gap；恢复在同批持久化闭合Gap、新segment和Raw/EMA，Receipt后交换并重置EMA；实时返回已提交Gap。 | `explicitReadFailureOpensOneGapAndRecoveryResetsEMA`<br>`failedCPU12MemberAlsoGapsMaximumAndRecoveryUsesRawMaximum`<br>`rejectedRecoveryReceiptDoesNotLeakSegmentOrCloseGap`<br>`actualSQLiteStoresFailureAndRecoveryGapWithItsSegment` | Engine/SQLite故障→恢复、改周期不误Gap、Receipt失败及Gap内存TTL回归通过。 最终实机正常会话gaps=0，没有真实故障Gap验收。 |
| R14 / [#40](https://github.com/sisyphe550/Temperature-monitoring/issues/40) 可选成功计数跨来源代际继承 | SourceID集合变化清零连续成功数，保留失败轮次；新来源第1/2次有效Receipt仍Unavailable，第3次才恢复。 | `sourceGenerationChangeRequiresThreeNewOptionalReceipts` | 独立Registry/Controller/SQLite回归RED→GREEN，纳入最终337项。 没有本机物理可选来源故障/代际切换实测。 |
| R15 / [#41](https://github.com/sisyphe550/Temperature-monitoring/issues/41) 唤醒残留可选隔离锁 | 停止采样等待loop task及在途失败完成后捕获最终隔离状态；唤醒重新资格化建立有限恢复周期，三次新来源成功Receipt恢复，包含suspend与第四失败并发。 | `wakeRediscoveryCanRecoverPreviouslyUnavailableOptionalSource`<br>`sleepWaitsForFinalFailureBeforeCapturingWakeRecoveryState` | 常规与在途sleep race独立回归RED→GREEN，纳入最终337项。 没有真实系统睡眠与故障同时发生的硬件验收。 |
| R16 / [#42](https://github.com/sisyphe550/Temperature-monitoring/issues/42) CPU重连复活耗尽可选预算 | 按有界SensorKind保留本会话已耗尽/停探测状态；CPU重连不能重新加入已停可选schedule，唤醒新资格周期才可重建。 | `unrelatedCPUReconnectMustNotRestartExhaustedOptionalProbeBudget` | 独立真实软件路径验证CPU继续、重连后optional新读取=0，最终337项通过。 故障输入和60s探测时间由可控Clock/transport生成。 |
| R17 / [#43](https://github.com/sisyphe550/Temperature-monitoring/issues/43) 隐藏状态项导致无可达窗口/退出 | 正式启动显示主窗口；标准LaunchServices reopen复用窗口与会话；窗口提供app.quit，进入既有正常关停路径。 | fixture和正式Release窗口入口测试 | fixture与正式Release验证启动、关闭仍采样、标准重开保留period/selection/session、窗口按钮退出删除会话。 菜单栏拥挤/刘海条件下AX exists不证明物理可点击；本轮未验收右键菜单。 |

## 独立发现与裁决

- **I01旧代Gap未闭合：已修复。** timeout重发现安装新定义前，使用Lease/Receipt提交旧Gap结束，保留原reason，新来源以sourceChange开始；`recoveredTimeoutClosesOldGenerationGapsBeforeInstallingNewSources`通过。
- **I02长睡眠先prune导致Fatal：已修复。** 停止IO并释放在途后，唤醒维护先把含真实pre-sleep Raw的窗口推进、提交父桶，再prune；`longSleepClosesPreSleepPartialBucketsBeforeWakePrunesRaw`通过，不补睡眠样本、不造空桶。
- **I03超过8来源后旧结果覆盖错误：已修复并经源码复核。** 失效查询ordinal并取消旧任务，完成/取消后恢复有界自动刷新；不把源码复核写成独立实机UI通过。
- I04–I06分别对应R14–R16。R15另覆盖第四次可选失败仍在途时同时suspend的竞争：等待任务终结后捕获最终隔离状态。
- **I07可选集成测试假时钟时序：测试已稳定化。** 固定20ms wall wait不保证Receipt和调度已完成；改为观察Sampling任务的下一次sleep注册后推进TestClock。无生产行为变更。
- **I08历史并发测试：测试语义已修正。** 创建顺序不保证actor入场顺序，也不保证查询重叠。至少一个合法成功；成功匹配自己的layer，失败只能databaseRead/superseded。合法先后完成允许两者成功，不用固定sleep伪造重叠。
- 请求receipt缓存仅允许同一原Lease幂等；新Lease重放同RequestID明确拒绝，防止新预留泄漏。committed_batches的600s作用域按现行契约处理，不增加无界tombstone。
- 初始UI Runner签名/复用DerivedData失败和中间测试时序失败保留为修复过程证据；最终通过以最终日志为准。原48cd967d历史日志的尾空格不回写；新日志也保留命令原始输出，包含Xcode输出中的空白行。产品代码/文档diff排除原始输出日志后检查通过。最终归档逐字节核对发现两份旧JSON副本被EOF补丁头拼接，已恢复为原始字节；原始checkout从未改动，[16文件保存清单](original-audit-preservation.json)记录全部一致且JSON可解析。

## 本机真实链路数据

正式无fixture启动的最后快照为`2026-10-02T15:18:40.300107Z`。CPU12每个成员及主值各420个Raw；SSD127个，Battery63个，Raw与EMA总数均5650。主Raw检查SQL通过sample_members连接同批成员，成员数必须12且`abs(mainRaw-memberRawMax)≤0.00001`，420个检查无反例。此检查证明Raw max和成员关联；EMA算法与状态交换由软件测试验证，本次未重新独立计算真实会话全部EMA。

| CPU max请求周期 | Raw数量 |
| --- | ---: |
| 50ms | 194 |
| 100ms | 98 |
| 200ms | 95 |
| 500ms | 19 |
| 1000ms | 14 |

这些period_ms是实际请求元数据，不证明所有读取间隔完全等于档位，也不证明性能抖动指标。实机UI每档等待8s后检查仍有温度且无Fatal；本轮没有5×10min节拍/功耗/CPU占用验收。Battery/SSD由真实资格证据选择，本机值可读不外推其他硬件。无故障正常会话的Gap行数0，不能作为真实故障分段通过证据。

## 尚未验证及用户豁免

1. ≥72/73h耐久、公证/公开发行、跨机型认证按用户范围豁免，未执行、未宣称通过。
2. 真系统合盖/休眠和唤醒、睡眠与传感器失败并发，以及正式运行中worker/磁盘故障注入未执行；已修软件路径和回归不替代这些硬件证据。
3. 五档各10min的性能/节拍验收未执行；本轮为五档各8s短时操作。
4. 真24h/72h完整会话历史、最终SHA的真实Raw TTL到期及长时间容量压力未执行。短会话UI只验当前已存在数据。
5. 拥挤刘海菜单栏上的物理右键/上下文菜单未验收；AX存在不能等同物理可点击。正式启动窗口、标准reopen及窗口退出已提供并实测可达入口。
6. 受控启动Fatal验证约30s自动退出，不声称已验证运行中Fatal的全部真实清理路径。

## 归档与交付记录

[verification.json](verification.json)保存机器可读结果和17项映射；[artifact-manifest.json](artifact-manifest.json)保存原文件位置及SHA256，归档时按清单核对。正式二进制：App `f1ae783663557fdf7da346f78f8d632748937c1bf239051a003c982ee683d95b`；worker `5e546ae7f7ba0d5f9d890fa662cd5f3f727ac71133d6c4e71eab6209bf7590ac`。

仅使用本App拥有的窗口/控件附件；不加入私密整屏截图。原始xcresult保留在临时验证目录，不自动整个复制进Git。自有附件来源为`/tmp/temperature-final-real-owned-evidence/`，可按其manifest另行归档。

本报告记录最终代码的本地验证；推送、Issue关闭、PR和exact-head CI另以GitHub当前状态确认，不在此预写通过。后续提交仅整理文档/证据，正式App绑定上述测试代码SHA。原W11验收[PR #26](https://github.com/sisyphe550/Temperature-monitoring/pull/26)仍使用旧代码与旧证据，应在修复合入后重新核对，不能沿用其旧完成声明。

## 当前仓库规则与附件入口

[规则回读](github-ruleset.json)确认main-protection active、无bypass、strict required checks为handoff-docs/probe-tests/blocking-issues/core-tests/app-build；[仓库设置](github-repository-policy.json)只允许merge commit并保留开发分支。旧9月21日规则快照不回写。

- [正式App身份与环境](release-final-identity.json)、[签名输出](logs/release-signature.log)、[Release边界](release-upstream-boundary.json)。
- [自有App附件清单](ui/manifest.json)、[正式启动窗口](ui/02-Release-production-startup-dashboard.png)、[1小时历史窗口](ui/10-Release-history-1hour.png)、[实机断言与读数](ui/12-Release-real-hardware-short-acceptance.txt)。
- [完整最终SQLite快照](hardware/live-final-snapshot.json)、[只读取证SQL](hardware/capture-live-db.py)、[独立UI核对](ui-independent-review.md)。
- [启动Fatal同批简表](hardware/fatal-timed-summary.json)：首次PID15:24:07.185203Z、最后PID15:24:38.513307Z、首次无PID15:24:38.649256Z；31.4639s包含启动与收尾，不证明窗口精确显示30.000s。
