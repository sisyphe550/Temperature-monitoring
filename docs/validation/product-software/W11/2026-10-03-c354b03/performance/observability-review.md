# c354 正式 App 性能可观测性与资格门禁审查

审查时间：2026-10-03 04:56 UTC。只读源码、现行文档和已有 `/tmp` 证据；未启动 App、未编译、未跑测试、未修改仓内文件。运行中的五档长测尚未结束，本报告不提前判定其结果。

## 结论

1. 当前正式 App 有精确的 scheduler skipped 内存计数，并在 worker 协议中携带逐成员读取开始/结束时间，但没有把这些信息导出到正式 App 的现有证据中。现有 SQL/JSONL 无法补算精确 skipped、读批 p95/p99 或屏幕显示延迟 p95。
2. 当前五档各600秒 UI 用例可以证明各档清醒持续运行、每次观察时实际选中档位、有效温度、无 Fatal、同一 Session、正常退出和会话清理。Raw collector 可以证明实际成功样本完成间隔和 Gap/segment 边界。这些成果应单独保留；不能将全部性能门槛一起写 passed。
3. REQ-110 的四块平台字段和同一 App/worker 身份可以据实登记，但现行 W09 schedules 资格包含性能门禁。严格口径下，五档持续性通过而性能指标未测，schedules 应为 partial/pending，不能用 CLI 或旧构建替当前正式 App 完成整套资格。
4. ProductQualification 的现有 schedules 报告存在确定的统计口径缺陷：成功时丢弃精确 skipped，使用所有 committed_batches 与 CPU 理想机会相减作为 missedOpportunities，且 cpuRawSamples 包含所有 period 相同的序列。这是源码确定的工具差异，本次未执行该工具复现；不是当前温度采集故障的证明。

## 绑定受测身份

- source_commit：`c354b0392a91367d42708d7424fd0e133af825b9`。
- App SHA256：`9f786ee330531d2d194ef2c88f04c83c314de3253a1e218ea45df12f5aeabc3c`。
- worker SHA256：`74b44d0617c4524e6cf24024ad48e64304b56b8f0b18c459ad8c364c7f8cb59f`。
- 来源证明：`/tmp/temperature-w11-source-commit-proof.json`，88 个生产文件匹配、mismatches=[]。这里只读取该证明，未重新计算二进制哈希。
- 正式运行：`/tmp/temperature-long-ui-20261003T043223Z`；Session `ad735257-fea5-41a0-8e1b-644c8d2bc191`。
- 环境：Mac16,13 / macOS15.7.3 / 24G419；Release、无 fixture、launch_arguments=[]。应由最终报告附正式来源/签名/构建原始记录再次绑定，不能仅引用本段转述。

## 现行门槛和范围

`docs/10-test-strategy.md:61` 要求普通用户正式 App 五档各10分钟，并规定正常空闲：

| 指标 | 门槛 | 本轮当前证据能力 |
|---|---|---|
| scheduler skipped | ≤1% | 未导出正式 App counter，不可判定 |
| CPU 读批耗时 | p95≤period；p99≤2×period | 仅内存/协议有 starts/finishes，现有证据不可判定 |
| 首帧/显示延迟 | p95≤500ms | 没有可关联的呈现端时间，不可判定 |
| 实际相邻成功样本间隔 | 要保存分布 | collector 可算，但不是上述读批/skip/display 指标 |
| CPU/内存/能耗 | 没有百分比硬指标 | 可报告观察口径和分布，不能自行创造阈值 |
| 队列/Buffer/DB/WAL/日志容量 | 按21/defaults | 现有观察覆盖DB/WAL、进程RSS；不能替代内部队列/Buffer高水位 |

`docs/22-agent-implementation-plan.md:498–500` 还要求计划时刻、实际开始结束、批跨度、失败/重试/skipped、新鲜度与三轮真实睡眠。本轮授权已保留五档600秒和睡眠；72/73h、公证、公开分发、跨机型已豁免。10分钟可控负载是否在本轮适用必须遵循根agent已有授权/范围，不能因本审查自行启动负载。

docs/22:499 的“用户已暂缓的性能SLO”与 docs/10:61 的明确验收门槛存在正文用词差异。至少不能把未测写成达标；若维护者决定正式豁免性能指标，需记录明确授权并同步契约/追踪，不可借这句话自动豁免。

## 源码链路和可证明信息

### 精确 skipped

- `Packages/TemperatureCore/Sources/SensorRuntime/SamplingService.swift:14–22` 的 SamplingStatistics 仅有 skippedByKind 和 completedReads。
- `SamplingService.swift:49–76` 按 plannedDue/period 跳过过期机会；`:513–541` 记录 skippedByKind。
- `SamplingService.swift:155` 在 start 重置统计，睡眠后重新 start 也会重置；`:170–177` 换档不重置统计。正式测量必须在每档/每代边界取得快照或导出阶段事件，不能把会话累计值直接当单档值。
- `ProcessingCoordinator.swift:167–168` 和 `SessionMonitorController.swift:132–133` 提供内存查询。但 App/SessionCoordinator、AppSessionRuntime 未调用该接口，正式 App 不写它到诊断日志或 SQLite。
- completedReads 在 `SamplingService.swift:459–462` 的 handler 返回后递增，包含CPU/SSD/Battery，未按 kind 分开。`ProcessingCoordinator.swift:177–185` 在 accept 失败时内部记录后返回，因此 completedReads 不能单独当成功持久化数，也不是 CPU 计划机会总数。
- skipped 比率需保存明确分母：该档首次调度机会数 + 被跳过机会数，重试次数另列。现行结构只有 skipped 和混合 completedReads，不能直接用后者构造严格 CPU 分母。

### 读批耗时与批跨度

- `SensorWorker/HardwareSession.swift:55–67` 串行遍历读取成员；`:269–287` 保存每个成员 started/finished。
- `TemperatureCore/Contracts/SensorTypes.swift:294–323,342–377` 和 WorkerProtocol.swift:414–415 将时间传到主进程。
- worker 内部读批耗时可定义为 `max(finished.elapsedNS)−min(started.elapsedNS)`；CPU成员完成跨度为 `max(finished)−min(finished)`，两者不同。CPU主值有效批的跨度门禁在 SamplingService.swift:454–457，现值200ms。
- IPC调用耗时也不是 worker 内部耗时，需要在 `client.read` 前后独立记录，排除持久化 handler 的时间。SamplingService.swift:414 的 reservation 等待和 handler/commit 等待会影响下一次调度，必须分开命名。
- `docs/contracts/schema-v1.sql:59–70` raw_samples 只保存样本完成 elapsed/wall、period/value/freshness，没有请求计划时刻、开始时刻、请求ID、批耗时。CPU主值的完成时间为同批最后完成的成员时间（MonitorEngine/CPUMaxDerivation），不是整批开始。
- 即使查询未过期的12成员 raw 完成时间，也只能得到完成跨度，不能还原第一项开始或 IPC 往返延迟；全程 raw 仅保留300秒，滚动 SQLite backup 会覆盖之前片段。

### 首帧与实时显示

- SessionMonitorController.swift:323–334 每200ms构造/发布快照，这是代码设计上限，不是呈现延迟实测。
- AppSessionRuntime.swift:283–286 的历史自动刷新最少间隔1秒，与200ms实时温度快照分离。500ms门槛必须明确定义为实时温度首帧/新值呈现；若要求历史图中新点也500ms，1Hz刷新存在需要确认的规格/设计差异。这里只指出范围歧义，未复现500ms超标。
- 当前 UI 每约20秒通过 AX 读取一次数字，未保存对应 sample_id 或可关联 snapshot/version，不能区分重复温度值，也不能给显示延迟分位数。
- UI waitForExistence 超时仅是存在性/启动成功验证，不是500ms首帧样本。真实首帧需记录启动基准、第一份有效CPU样本、实际首帧呈现时间；多次独立启动才能计算首帧p95。MainActor apply/onAppear 单独只能证明提交到UI状态或视图出现，不能冒充屏幕渲染完成。

### Gap 与资源

- MonitorEngine.swift:752–768 的相邻成功 dt 超过 max(3×period,1s) 会写 reason=timeout 的闭合 Gap、新 segment.reason=gap。它不等价于 SENSOR-TIMEOUT-003；真实读取失败恢复则有 open Gap 与 recovery segment，应结合诊断日志判断。
- `/tmp/temperature-observe-new-long-ui.py` 每20秒读取 owned App/children 的 ps CPU/RSS、DB/WAL文件大小、来源/Gap/row计数；它没有内部缓冲、writer queue、最老年龄或日志目录全量体积指标。
- CPU百分比以macOS单核100%口径报告；RSS需区分App和worker。短时“没有超过硬限”不证明72h资源无界问题不存在，但本轮72/73h已明确豁免。
- defaults当前限制：各Raw/EMA ring 8192、max_active_series32、writer_max_records16384 / pause12288 / resume8192、writer最老10s、WAL soft32MiB / hard64MiB、SQLite页数262144×4096=1GiB、日志5MiB×5文件。需分别验证，不能用App RSS代替writer记录数。

## 现有证据允许/禁止的计算

| 证据 | 可以准确获取 | 不可以推导 |
|---|---|---|
| LONG_UI_PHASE_START/END | 同一Session、选中period、UTC/awake/continuous时间、各档≥600清醒秒 | 精确读取开始/结束、scheduler总机会和skipped |
| actual-cpu-max-events.jsonl | sample_id、period、segment、完成elapsed/wall、value、unknown freshness；相邻成功间隔分位数/最长空窗 | 读批耗时、数据产生时间、屏幕显示时刻 |
| final/rolling SQLite backup | 当前未过期raw/ema、保留聚合、source/series/member/segment/gap、持久化状态 | 完整已过TTL的样本、遗漏counter、开始时刻 |
| live-observations.jsonl | 时间点CPU/RSS、DB/WAL体积、source generation、Gap计数等 | 内部资源峰值、完整每次失败率或屏幕延迟 |
| owned UI PNG/JSON attachment | 所拍时刻真实页面与采样档位/温度显示 | 500ms首帧/显示p95、菜单物理交互、其他屏幕条件 |

Cadence统计应同时提供：严格UIphase窗口内结果（墙钟不跳变时按wall_ns落窗）和按实际period变化分组结果；说明首次/最后边界、跨档在途旧请求。每组按elapsed计算并使用 nearest-rank 分位数，保留同温值，不跨segment混成连续曲线。`expected−observed`只能命名 sample_count_shortfall，标注不是scheduler skipped。如果collector发生读取错误/超过TTL/晚到同elapsed等情况，完整性另判，不能补0或重复旧样本。

## 已确定的工具口径差异（未执行复现）

1. SchedulesCollector.swift:121 取得 stats，成功结果`:148–157`不包含stats；只在零批次错误文本`:135–142`打印 skipped。
2. SchedulesCollector.swift:125–127 用计划 duration/CPUperiod 算 expected，再减全部 committed_batches。SQLiteEvidence.swift:90–97 的 committed_batches 没有CPU过滤，包含其他源和watermark/Gap加工批；不能当 CPU started/successful/opportunities，也不能当 skipped。
3. SQLiteEvidence.swift:94 以period_ms统计全部raw序列，CPU同批12成员+派生主值，且500/1000ms可能还包括同period可选源。cpuRawSamples字段名不能当主CPU样本数。
4. SchedulesCollector.swift:146 删除阶段数据库；成功summary没有请求级原始时间，后续无法审计延迟。它构建独立controller而不是读取正在运行的正式App，因此即使修正CLI统计也只能是Core/worker诊断，不能独自完成正式GUI资格。

根agent如计划修复，先建立可复现计数向量（如同周期CPU成员、可选读、watermark并存）确认报告字段与各层语义；当前长测期间不修改/运行它，不把此工具缺陷归入温度读取已复现缺陷。

## 最小后续补证方案

### 立即完成且不改变 c354 产物

1. 完成当前5×600清醒秒，导出仅属于本App的窗口和结构化记录；保存long日志哈希、owned excerpt、collector errors、Raw collector哈希、最终SQLite backup哈希与派生统计。
2. 完成同一App/worker SHA三轮真实OS睡眠/手动唤醒，保存power事件、同App/Session/worker代、sources/gap/segments、新读取和正常退出清理。
3. 为持续性/生命周期具体用例标通过；为性能量化保持not_measured/pending，不改变门槛，不删除50ms，不复用旧14cac/a97组合。

### 最小精确性能补证（需要新正式二进制，不能回填 c354）

1. 增加有界、低开销的本机结构化度量出口，保留真实硬件路径。无需新增产品传感器状态或SQLite温度schema；可用独立性能sidecar/signpost，必须不写传感器、不补数据、不切换fixture。
2. 每调度机会输出phase/epoch、kind、period、plannedDue、requestID、generation、是否首次/重试、skipped delta；各kind首次机会与skipped分母分开，stage切换/睡眠reset明确。
3. 同一request保存worker批min(start)/max(finish)、host client.read start/end、accept/commit完成，失败/取消也输出事实。若只采部分读批，报告采样策略和缺失，不能称完整分布。
4. 对实时CPU显示保存可关联的sample/snapshot标识和实际呈现测量；只测MainActor状态应用要命名state_apply_delay，不能改名screen_display_delay。若使用系统frame instrumentation，其时钟必须与elapsed校准并记录帧事件归属。首帧与持续更新分别统计。
5. 新正式构建冻结 source/App/worker/Profile/签名；先检查度量开销与功能等价，再按同口径五档600秒记录精确counter、read/display分位数。可以保留c354已完成生命周期作为历史修复证据，但新版本资格需重新评估受影响项。无新度量出口时，维持当前指标pending是准确结果。

## 新 dated c354 证据报告必须字段

- 身份：source_commit、delivery_commit、App/worker SHA256、测试源码与脚本hash、签名身份/验证、Release/无fixture、bundle id、schema/contract/profile/defaults hash。
- 四个平台块：product-qualification-v1.json 的 build_toolchain、deployment_target（最终load commands）、runtime_profile、qualified_combinations；不把历史组合当当前支持。仅当前通过用例可列到该组合。
- 长测：Session/AppPID/workerPID，phase配置/实际period，UTC+awake+continuous开始/结束，各档清醒秒数，collector完整性/错误，正常退出/会话清理，owned attachments/hash。
- 每档Raw间隔：样本数、观察跨度、相邻差数、p50/p95/p99/max、Gap/segment、重复温度保留规则、边界说明；统计名显式为successful_sample_finish_interval。
- 指标状态：exact_scheduler_skipped、worker_read_batch_latency、host_roundtrip_latency、first_frame_latency、screen_display_delay均保存measured/not_measured与原因；未测数值应为空，不填0。
- 资源：App/worker分别CPU单核口径、RSS KiB、测量周期、DB/WAL/max观测值，未覆盖内部资源项明确列出；不将采样点最大值称绝对峰值。
- 睡眠：3轮OS sleep/human fullwake时间、同一Session/AppPID、新worker generation、sources/requalified、每类Gap闭合/segment、恢复成功点与UI、正常quit无孤立worker。
- 判定：持续性、具体生命周期用例、来源/单位/CPU12与修复回归分别判定；性能pending、物理菜单/Notch等未测、豁免项目单列；REQ-110最终qualified不得越过本报告范围。
- 原始文件哈希manifest、独立审查、exact-head CI与blocking Issue状态，禁止历史文件回写。

## 文档刷新提醒（与本审查范围相关）

- docs/10-test-strategy.md:3 仍称“当前仅原型及文档契约检查有执行证据”，与已存在产品Core/正式App验证不一致；应改为分层现状，门槛保持。
- docs/09-technology-selection.md:17 称qualified当前为空；docs/13:83称旧14cac组合已登记且:88又正确限定为历史。应统一为“历史组合保留，当前c354资格按新证据判定”，不能删除历史结果或让正文看似当前已支持。
- docs/22:498–511/23旧73h任务与本轮豁免应保持明确适用标记；本报告不要求重启已豁免耐久，也不代替授权改变性能门槛。
