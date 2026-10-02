# CPU 温度监控修复分支独立审查

状态：最终独立审查完成。代码提交 `a97fd5a8d6ec53c957be7b05de2a3803e24effc2` 的源码、独立测试副本及本轮正式Release实机证据一致，未发现剩余可复现重要缺陷。结论限于下述修复及短时本机验证范围。

## 范围

- 工作树：`/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring`。
- 基线：`0b720deb1d7fe170e55999f2709a3665634746da`；初始修复 HEAD：`bde2423cf5c6cd232c590d1ccd8412adb029ca72`，后续集成已提交至 `a97fd5a8d6ec53c957be7b05de2a3803e24effc2`。
- 独立审查者未参与实现，仅只读仓库；回归和构建副本在 `/tmp`，模块缓存也在 `/tmp`。未修改仓库、Git 或外部线程。
- 已回读 AGENTS、docs/00、01、21、11、22、23、修复计划及原始 `2026-10-02-48cd967d/report.md`；审查基线至当前工作树完整差异，重点为 CPU12→Raw max→EMA→Receipt→SQLite→实时/历史、actor 重入、Lease、Gap/来源代际、有限恢复、睡眠/退出/Fatal、资格事实和前端状态。
- 用户仅本机使用；72/73h 长测、公证、公开发行及跨机型认证豁免，不计缺陷。72h 历史功能仍在范围内。
- 独立回归使用可控Clock/transport，运行实际Registry、Controller、Engine与SQLite等软件路径；它们不是硬件实测。硬件结论只来自明确列出的正式App/资格产物回读。

## 独立发现及修复复核

### I01 [P1] timeout 重新发现后旧来源 Gap 永不关闭 — 已修复

一次 timeout 生成旧 generation 的 CPU12 与主指标 Gap；重新发现产生新 SourceID/SeriesID 后只替换定义，后续新来源成功读数不能关闭旧来源 Gap。独立回归复现：新 generation 全部 available、24 个来源记录正确，但 snapshot 留有旧 13 个 Gap，旧主指标/热区 SQLite 历史仍 ended=nil。

回归：`/tmp/RecoveredSourceGapRegressionTests.swift`；RED：`/tmp/temperature-independent-review-source-gap.log`。实现方随后在 `ProcessingCoordinator.installRecoveredCatalog` 替换定义前通过 Lease/Receipt 提交旧 Gap 的结束事实，保留 timeout reason，不声明 wake，新定义以 sourceChange 开始。独立定向重跑 GREEN 见下文。

### I02 [P1] 超过 Raw 保留宽限的休眠导致唤醒 Fatal — 已修复

200ms 已采样，250ms 入睡时最后一个真实 Raw 仍处在未闭合秒桶；500s 唤醒先 prune，Raw 缺父桶，触发 DB-CLEAN / grace_exceeded。独立控制器回归准确复现。

回归：`/tmp/LongSleepRecoveryRegressionTests.swift`；RED：`/tmp/temperature-independent-review-long-sleep.log`。实现方新增 `prepareForWakeMaintenance`，在读 IO 已停止/在途释放后先将含真实 pre-sleep Raw 的窗口推进至 wake，再 prune。独立定向 GREEN。该修复需要真实尾部父桶，不能把它误判为睡眠空桶。

### I03 [P2] 历史来源超限错误被旧查询覆盖 — 已修复，源码复核

App 在来源版本数超过 8 时发布失败，但原查询未取消、ordinal 未失效，旧结果可能覆盖当前选择并清除错误。当前 `AppSessionRuntime.requestHistoryReload` 已取消查询、增加 ordinal；historyTask 的 defer 在完成/取消/被替代后恢复自动刷新。此项为确定源码路径，未作为独立 UI 实测通过。

### I04 [P2] 可选恢复成功计数跨 SourceID 继承 — 已修复，独立 GREEN

SSD 隔离后，generation1 已有两次有效 probe；CPU timeout 重新发现 generation2 后，新 SourceID 的首次成功 Receipt 错误继承旧计数并立即 available。使用实际ProfileRegistry CPU12+NVMe规则、Controller+SessionPersistence的模拟transport回归确认：新 SSD SQLite Raw COUNT=1，snapshot 新定义已经 available，无 Fatal。根因原 `SamplingService` 更新 schedules.sourceIDs 时保留 optionalProbes.validConsecutiveReads（约295）；executeOptionalProbe 累加并在3时恢复（约342–345）。违背 docs/06:23 的连续有效恢复边界。

`/tmp/OptionalGenerationRecoveryRegressionTests.swift` 与 RED `/tmp/temperature-independent-review-optional-generation-red.log`。实现方按 SourceID 集合变化清零 validConsecutiveReads、保留 failedRounds 防止重连延长预算。独立 GREEN `/tmp/temperature-independent-review-optional-generation-green.log` 验证新来源第1/2次仍 unavailable，第3次 available。

### I05 [P2] 唤醒后可选来源旧 Unavailable 永久保留 — 常规及在途路径已修复，独立 GREEN

SamplingService.start/stop 清空 optionalProbes，但 MonitorEngine.optionalAvailabilityFailures 按 SensorKind 保留；重新发现并替换定义后普通成功采样不会调用 onOptionalAvailability(nil)。SSD 隔离→sleep/wake→generation2 三次新 Raw 已提交，snapshot 有新定义且无 Fatal，仍 unavailable。根因 `SamplingService.start` 约163、`MonitorEngine.snapshot` 约532的旧 kind 状态优先。

`/tmp/OptionalWakeRecoveryRegressionTests.swift`、RED `/tmp/temperature-independent-review-optional-wake-red.log`。docs/06:23 允许唤醒重新资格化，不能永久沿用旧来源故障。实现方新增 suspend 捕获隔离 kind、start 建新有限探测周期，常规回归已纳入独立全量 GREEN。

进一步独立在途回归曾 RED：`/tmp/OptionalSleepAdmissionRaceRegressionTests.swift`，`/tmp/temperature-independent-review-optional-sleep-race-red.log`。第四次 SSD 实际失败暂停；并发调用 sleep，观察采样任务已取消后释放失败。suspend 在 await stop 前捕获隔离集合，此时尚为空；等待内第4失败完成并发布 isolation，但捕获集合不更新。wake 后新SSD三条 Raw 已提交、fresh snapshot、新定义及无Fatal均成立，available预期独自失败。实现方改为 stop(preservingWakeRecovery:) 在 loop task.value 结束后捕获最终隔离集合（当前SamplingService:184–202）。独立 GREEN `/tmp/temperature-independent-review-optional-sleep-race-green.log`，已纳入独立全量337项。

### I06 [P2] CPU 重连重新启动已耗尽的可选探测预算 — 已修复，独立全量 GREEN

SSD 初始4次读取失败及3次60s恢复探测失败后，SamplingService 移除 probe/schedule；无 sleep，仅 CPU timeout 重建 worker，recovery 的 makeSchedules/重建循环又将 SSD 加回 schedule，重新开始采样与重试。使用实际Registry/Controller的模拟transport回归只有newOptionalReads==0预期失败，CPU 仍可用。docs/06:23 明确三轮全失败后“本会话停探测”，唤醒可重新发现；CPU 重连不应重置该预算。

`/tmp/OptionalProbeBudgetAcrossReconnectTests.swift`、RED `/tmp/temperature-independent-review-optional-budget-red.log`。当前 optionalStoppedKinds 保留有界本会话耗尽状态，重建schedule跳过耗尽kind，直到 wake/start 新资格周期；独立全量337项通过。

### I07 测试时序不稳定 — 已收敛，独立全量 GREEN

审查副本全量 333 tests / 48 suites 在 OptionalAvailabilityIntegrationTests 的 false 参数失败：固定 `[500,550,650,850,1000]ms` 每步等待 20ms，读数未达到 4 后等待 unavailable 超时。同构建单独运行该 suite 两个参数均通过；实现方的 coverage 全量日志也出现同一失败。实现方改为观察 Sampling 注册的 retry/下一调度 sleep deadline 后推进 TestClock；独立全量337项通过。本项为测试时序，不据此认定生产可选来源恢复缺陷。

### I08 既有并发历史测试假定任务入场顺序/必然重叠 — 已修正，独立 GREEN

最新独立全量首次出现该路径：`HistoryQueryTests:197/205` 并发 async let 不保证 first 先进入 SessionPersistence actor；本次 second 先进入并被随后 first 取消。first 成功触发216的expected-superseded断言，second抛superseded，2 issues。产品按最新实际入场查询取消旧查询符合现有边界；此不是产品故障证据。实现方最终同时修正HistoryQueryTests及MonitorIntegrationTests：不同request必须返回两个合法结果，至少一成功，失败只允许databaseRead/superseded，成功必须匹配各自历史层级。先完成再入场时两个成功合法；真正重叠时才取消旧请求。名称及注释也不再声称每次必然覆盖取消。生产代码未改。该调整消除未被控制的调度假设，独立同步最新副本全量337 tests /52 suites再次通过，未作为新增产品缺陷。

### I09 [P2] 原始证据复制时无换行EOF拼入diff header — 交付归档缺陷已修正，独立逐字节PASS

实现方最终归档复核发现：复制原始`48cd967d`目录时，两个原文件没有末尾换行，拼接的diff文本将下一文件header附进JSON。`after-quit-db.json:66`由合法`]`变为`]diff --git ...report.md`；`fresh-binary-hashes.json:4`由合法`}`变为`}diff --git ...hardware-sources.json`，副本JSON不可解析。产品代码及原始checkout文件未被修改。本报告此前只回读原始报告及部分产物，未逐字节核对整个副本，不能据此前描述声称已证明原样保留。

实现方已将这两个副本恢复到原始byte串，保留原有EOF无换行。独立补审直接读取原始checkout与修复worktree的16个文件，核对两边路径集合、每文件byte相等、SHA256及实现方preservation清单；16/16相等，两个目录均无额外/缺失文件，5个JSON在两边均可解析。162份已审代码/资源/UI/契约hash无变化，当前修改仅为这两个历史副本。此前未验证的preservation表述由本次实测取代。独立证据：`/tmp/temperature-independent-original-audit-preservation.json`；实现方证据：`/tmp/temperature-monitor-review-20261002.1G0KnN/original-audit-preservation.json`。

交付归档时应保留这些原始byte，包括无末尾换行；最终复制/提交后需再核对16个路径及SHA256与此清单一致，不能将恢复副本解释为回写历史结论。

## 最终修复位置

| 项目 | 最终代码SHA中的位置 |
|---|---|
| 旧来源Gap结束提交 | `ProcessingCoordinator.swift:266`、`MonitorEngine.swift:377` |
| wake先完成真实尾桶再prune | `ProcessingCoordinator.swift:259`、`SessionMonitorController.swift:254` |
| 历史选择失效及Task回收 | `App/AppSessionRuntime.swift:227`、`:255` |
| generation恢复计数隔离 | `SamplingService.swift:314`、`:323` |
| sleep等待在途结束再捕获恢复kind | `SamplingService.swift:184`、`:192`、`:210` |
| 耗尽预算防CPU重连复活 | `SamplingService.swift:314`、`:399` |
| production/reopen/窗口退出 | `App/AppDelegate.swift:87`、`:90`，`TemperatureDashboard.swift:28` |

以上Core文件位于`Packages/TemperatureCore/Sources/SensorRuntime/`，MonitorEngine位于`Sources/TemperatureCore/`；Dashboard位于`App/Presentation/`。

## 验证

| 检查 | 独立结果 | 证据/限定 |
|---|---|---|
| 25 项定向回归 / 6 suites | PASS | `/tmp/temperature-independent-review-targeted-green.log`；源代际 Gap、500s sleep、EngineGap、StorageLifecycle、RuntimeShutdown、HistoryBudget |
| OptionalAvailabilityIntegrationTests 两参数单独运行 | PASS | `/tmp/temperature-independent-review-optional-isolated.log` |
| 全量 337 tests / 52 suites | PASS，exit 0 | `/tmp/temperature-independent-review-core-tests-final.log`；最新副本包含全部独立回归及并发历史测试的调度断言修正 |
| 原始审查证据保留补审 | PASS，16/16 byte相等 | 独立比较原始checkout与修复worktree，5个JSON均可解析；见I09及独立preservation清单 |
| git diff --check 基线至代码SHA | 修复范围PASS | 全diff只有不可回写的原始48cd967d归档两条日志有`224 | `尾空格（audit-regressions.log:111/core-tests.log:125）；排除该原始证据目录后exit0，非产品缺陷 |
| handoff + handoff 反例门禁 | PASS | revision3、132 active、50 tasks、20 TC |
| api-v1.swift typecheck | PASS | 显式 `/tmp` module cache |
| Release 上游边界扫描 | PASS | 扫描a97fd5a对应build/TemperatureMonitor.app和SensorWorker，无fixture/root/write-SMC禁止token，资源与登记文件匹配 |
| 资格 schema 工具 | 实现方产物8项PASS | `/private/tmp/temperature-monitor-review-20261002.1G0KnN/qualification-schema-green.log`已回读；独立执行受xcodebuild隐式写用户cache限制，未产生schema断言失败 |
| 本机来源资格产物回读 | 有事实支持 | `/private/tmp/temperature-monitor-review-20261002.1G0KnN/task7-real-sources.json`：CPU12、Battery TB1T、唯一 Internal SSD selected；这是 qualification 证据，不能替代正式 App 连续链路实测 |
| fixture UI | PASS，16项实际执行，2项条件跳过 | `/private/tmp/temperature-monitor-review-20261002.1G0KnN/ui-final-fixtures.log`：18 tests、2 skipped、0 failures；含R17标准重开及窗口退出。Release fixture拒绝由单测覆盖，opt-in正式App用例未在此运行 |
| 最终核心覆盖率产物回读 | 88.61% | `/private/tmp/temperature-monitor-review-20261002.1G0KnN/core-commit-coverage-gate.log`：7059/7966，范围为TemperatureCore/SensorRuntime生产Swift；不包含UI/C bridge |
| 最终Release签名校验 | PASS | `codesign --verify --deep --strict build/TemperatureMonitor.app` exit0；为本机ad-hoc签名 |
| 最终Release构建 | PASS | `/private/tmp/temperature-monitor-review-20261002.1G0KnN/release-code-commit-build.log`；代码SHA a97fd5a，BUILD SUCCEEDED并完成ad-hoc签名 |
| 最终正式App本机UI | PASS，1项实际执行 | `/private/tmp/temperature-monitor-review-20261002.1G0KnN/ui-final-real.log`及`/tmp/temperature-ui-final-real.xcresult`：84.8s、0失败，五档各8s、真实来源、历史、同会话重开及正常退出清理；下节列出独立证据回读 |
| 受控Release启动Fatal负例 | PASS，范围受限 | missingWorker受控复制App产生APP-INIT-001/report，首次观察到进程消失31.4639s，含启动；无用户输入或强制信号，只验证启动fallback |

## 新增入口修复复核

本机拥挤刘海菜单栏的状态项AX存在但物理未绘制，原App可能没有可达的窗口/退出入口。R17新增生产启动显示主窗口（AppDelegate:87）、标准reopen复用主窗口（AppDelegate:90）、主窗口退出按钮（TemperatureDashboard:28）；三者进入既有状态及正常stop/cleanup路径。已回读对应fixture和opt-in Release UI用例。该修复不声称物理菜单栏点击通过，当前docs/07也明确此宿主限制。

## 正式Release本机证据复核

实测由实现方在普通用户环境执行；独立审查只读回读日志、SQL取证脚本、结构化产物及全部10张自有App窗口PNG和2份文本附件，没有操作App或其他屏幕内容。

- 身份：`release-final-identity.json`中的代码SHA、正式App路径、App/Worker hash与独立取值完全一致；Mac16,13 / Apple M4 / macOS15.7.3(24G419)。文本附件`12-Release-real-hardware-short-acceptance.txt`明确相同路径及会话`f33062e7-91c8-4e0b-8735-3a33ff1a7bf5`。
- UI：`/tmp/temperature-final-real-owned-evidence/manifest.json`、01/12文本及02–11 PNG均已查看。生产启动窗口可见，CPU12逻辑热区与主指标、SSD TEMPERATURE、Battery TB1T有真实读数；五档依次为50/100/200/500/1000ms；5分钟为EMA，1小时为历史平均及已记录Raw峰值，两个来源图例独立。重开后1000ms、选择和历史保持。窗口退出正常结束，测试断言该会话目录删除。
- DB：`final-live/snapshot-022.json`至053共32次，观测UTC15:17:37–15:18:40。最后Raw=EMA5650；CPU12及主指标各420，SSD127、Battery63；1/10/60s聚合959/90/15。主指标五档记录分别194/98/95/19/14；`sample_members`链接420个主指标均有12成员且max一致，所有snapshot的mismatches=0、FK违规为空。`capture-live-db.py`为只读SQLite查询，SQL口径已核对。独立摘要：`/tmp/temperature-independent-final-live-summary.json`。
- 清理：`final-live/cleanup.json`在UTC15:18:42观察会话DB剩余0，与UI正常退出及会话目录不存在的断言一致。
- Fatal：`fatal-negative-timed-observation.json`与只读ps观测日志证明，复制Release App移走Worker后APP-INIT-001/missingSensorWorker报告生成，进程首次被观察至消失31.4639s（含启动）。无按钮/信号输入。该负例不作为运行中Fatal五秒收尾的实机认证，相关软件回归已包含在核心测试。

限定：五档每档8s及约64s数据链验证，不声称docs/10五档各10min的统计性能门槛、72/73h耐久或跨机型认证通过。此轮未在最终SHA App制造物理睡眠/timeout；睡眠及来源代际边界由独立可控回归验证，较早真实自然睡眠/timeout数据只作补充历史证据。状态项AX `isHittable=false`，被拥挤刘海菜单栏隐藏；右键菜单未验收，R17通过生产窗口、标准reopen和窗口退出提供可达入口。用户明确豁免的长测/发行认证不作为本轮缺陷。

## 其他审查裁决

- replay cache 的历史重用必须同 Lease；当前同 request、异 Lease 返回 Receipt 的问题已修为 lease_replay_mismatch，避免泄漏新预留。
- committed_batches 的 600s 保留符合现行 docs/04 的 10min 作用域。过期后换新 Lease 人工复用旧 BatchID 不属于正常 processor UUID / 10s 有限重试链，因此不作为可复现重要生产缺陷；不建议无界 tombstone。
- 实时历史现在携带已提交 Gap；来源切换保留旧 EMA 的有界历史、按独立 SeriesID 展示；超边界预算显式失败，不静默截尾或拼接。
- 已回读修复后的 README/当前入口/架构/UI/开发计划/任务文档，生产 App 未创建/未实现的过期表述已移除；原始按SHA归档证据的状态不得回写；副本保真已于I09独立逐字节复核，不能沿用此前未经byte核对的推断。

最终代码SHA `a97fd5a8d6ec53c957be7b05de2a3803e24effc2` 与162份已审代码/资源/UI/契约哈希全部一致；独立337测试副本的Sources/Tests与提交没有漂移，产品代码没有变动；交付归档补审时工作树仅两个历史JSON副本恢复原始bytes。基线到代码SHA最终差异已核对，代码层面未发现剩余可复现重要缺陷；全部独立发现已修复或明确裁决。同SHA正式Release的UI/SQLite/清理与启动Fatal受控负例新证据已回读。后续发现的EOF归档复制缺陷已修正并独立复核16/16，未发现剩余重要问题；本轮修复独立审查通过，实测范围以上述限定为准。源码哈希清单：`/tmp/temperature-independent-reviewed-code-sha256.json`；独立Release二进制/资源hash：`/tmp/temperature-independent-final-release-hashes.json`（App `f1ae783663557fdf7da346f78f8d632748937c1bf239051a003c982ee683d95b`，Worker `5e546ae7f7ba0d5f9d890fa662cd5f3f727ac71133d6c4e71eab6209bf7590ac`）。
