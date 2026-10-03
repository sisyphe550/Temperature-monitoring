# 2026-10-03 正式 Release 长测失败：只读审查

## 范围与结论

审查对象为现有正式 Release binary、已有 XCTest log/SQL snapshot/sample/ps 观察；未启动 App、未运行 GUI、未修改仓库。产品代码含尚未提交的 W11 修复，不能把当前 HEAD `403d44b`直接当作该 binary 的最终源提交。

1. 五档各 600 秒未完成。本次只到第一档 50 ms；最后成功进度为 265.7523 秒，接着 AX picker snapshot 瞬时失败，运行器进入正常退出清理。
2. 失败是 XCTest 获取 `cpu.period` 的 AX snapshot 无匹配；该条错误本身不能证明产品 picker 消失或产品 Fatal。清理时确有 Codex Dialog interruption，说明外部前台 UI 干扰是需要排除的候选原因。
3. 实测主 App CPU 随填充增长至 120.3/157.2/163.3%（macOS 100%=一个核心）；worker 0.7/0.8/1.0%。11:39:00的一秒 sample 中，主线程650个采样栈的最外层 Charts 覆盖516个（79.38%）。这些支持先优化可见历史图的布局频率，尚不能证明 Charts 导致上述 AX 失败。
4. SQL 完整50ms段统计的理想20Hz机会短缺为0.90635%，不是正式 scheduler `skippedByKind`计数。不能宣称本次全段 skipped>1%，也不能用约307秒段宣称10分钟验收通过。

## 不可变原始证据

- `/tmp/temperature-long-ui-20261003T033320Z/long-ui.log`，首个 error 在约1801行；teardown约1819行明确 Codex Dialog interruption。
- `/tmp/temperature-long-ui-20261003T033320Z/live-observations.jsonl`：20秒资源/数据库抽样。
- `/tmp/temperature-long-ui-20261003T033320Z/final-before-normal-quit.sqlite`：最后一次清理前在线备份，snapshot不是退出瞬间所有末尾数据。
- `/tmp/temperature-long-50ms-43405.sample.txt`：1ms sampling、2026-10-03 11:39:00.339 +0800、App PID43405。
- `/tmp/temperature-long-failure-readonly-review.json`：以上原件SHA256、主线程stack归类、资源记录、窗口点数。
- `/tmp/temperature-long-ui-20261003T033320Z/cpu50-cadence-review.json`：实际50ms间隔统计。

会话 `790c134a-a3a5-44c3-97bd-e32647b8b704`；main CPU series `00000000-0000-4000-8000-000000000200`。来源为 generation1 CPU12/SSD/Battery、CPU Max segment1，无 source_wall_ns，freshness unknown。

## 实际50ms段统计及边界

| 指标 | SQL snapshot 实际值 |
|---|---:|
| CPU max 50ms Raw样本 | 6,092 |
| 第一/最后elapsed | 18.497954833 / 325.833504125秒 |
| 覆盖时长 | 307.335549292秒 |
| 实际间隔数 | 6,091 |
| 平均间隔 | 50.457322ms |
| p50 / p95 / p99间隔 | 49.982042 / 52.472250 / 58.071833ms |
| 最大间隔 | 255.508541ms |
| dt>75ms / >100ms数 | 37 / 17 |
| 理想20Hz机会量 | 6,146.710986 |
| 实际间隔/理想机会短缺 | 0.906354% |
| 显式Gap数 | 0 |
| 最后300秒内CPU Max Raw点数 | 5,945 |

SQL elapsed为完成观测时间，缺少每次 plannedDue/readStarted/skippedByKind/总请求数，不能精确替代 scheduler skip counter；也不能将相邻样本间隔当作worker读批耗时或屏幕显示延迟。第5个整分钟有1184个点，即相对1200理想点数短缺1.333%，但它是分段观察，不是整个正式10分钟的skip门槛。所有dt都不足现行floor1秒，因此零Gap是预期，与20Hz性能通过不同。

## 按证据排序的可证伪假设

### H1：可见历史图每200ms重建近2000线点和约2000范围点，是主要UI负载

证据：`App/AppSessionRuntime.swift:237-239`对每个快照请求历史；`:277-278`五分钟范围随ui_publish_ms=200ms刷新。`App/Presentation/HistoryChartView.swift:69-79`每点一个LineMark，有min/max时再一个AreaMark。`Packages/TemperatureCore/Sources/TemperaturePresentation/HistoryChartModel.swift:151-186`超过点数cap后每个bin产生min/max；20Hz数据约100秒就到2000点，随后接近4000个mark。ps在50ms点数1718→2112阶段主App CPU68.2→116.9%；单次sample主线程79.38%包含Charts。

可证伪预测：保持CPU50ms、CPU12、300秒保存、2000点上限和窗口尺寸不变，只把历史内容更新降至1Hz并隔离无变化的历史几何，则相同300秒填充之后App CPU应明显下降；不下降就不能认为H1已解决。

### H2：即使历史查询降至1Hz，最新快照asOf仍每200ms使整个历史Chart重建

证据：`Packages/TemperatureCore/Sources/TemperaturePresentation/PresentationModel.swift:20-30,106-114`每快照替换整个running state；`App/Presentation/TemperatureDashboard.swift:113`把running.asOf传给历史Chart；`HistoryChartView.swift:147-151`使用该anchor计算每个Date。没有Equatable隔离。普通wall/elapsed锚点细微抖动改变所有点的Date。

可证伪预测：仅1Hz throttle若仍有高CPU，而仅在chartState真正变化时更新历史View后下降，则H2成立。当前不允许独立再跑GUI，所以这是代码机制假设而非已验证改善。

### H3：核心RingBuffer/加工随300秒样本增加而有额外CPU成本

sample存在后台MonitorEngine/EMA复制/过滤栈；不过worker很低且主线程大量Charts已明确，故排在H1/H2之后。若隔离历史图后App后台CPU仍继续随数据量明显增长，应分别profile核心actor。不能仅凭整个进程CPU把全部成本归为图表。

### H4：外部Codex Dialog或前台焦点变化引发短暂AX snapshot缺失

失败后正常清理能再次找到并点击App quit；XCTest明确检测外部Dialog。预测：先完成所有审批，并在progress周期只读取一次picker.value、必要时激活目标App并有限重试，AX失败率下降。Dialog在teardown被观测到，不足以追溯为首个AX错误的已证实唯一根因。

## 现行契约是否违规

- `docs/10-test-strategy.md:61`：五档各10分钟、正常空闲 skipped≤1%、读批p95≤周期/p99≤2周期、显示p95≤500ms。当前未测完整；本次没有完整读批/显示/skip指标，不能标通过或造出failed counter。
- `docs/10-test-strategy.md:63`明确CPU/内存/能耗暂无百分比硬指标。因此163% CPU是实测优化问题，不能捏造CPU百分比硬验收门槛。
- `docs/07-native-ui.md:129`仅规定快照发布上限每200ms一次，采样/存储/渲染分别调度。并未规定历史曲线必须5Hz；历史1Hz＋当前温度200ms不改CPU五档或Raw/EMA持久化，属于现行范围的优化。
- 每来源2000点上限已有真实代码，不能说图表点数无界增长。核心实时结果返回约6000个EMA，再在Presentation降采样到≤2000，View最高约4000 mark。隐藏窗口的绘图停调度不能单凭未见visibility guard断言失败，因为AppKit可能停止不可见布局；需要实测。

## 最小候选及未验证状态

候选均只输出到/tmp，未修改仓库：

1. `/tmp/temperature-chart-history-refresh-candidate.patch`：只把AppSessionRuntime自动history refresh改1秒；强制选择/范围/唤醒reload立即执行。CPU采样档、snapshot200ms、Raw/EMA/TTL/schema/API/default不变。
2. `/tmp/temperature-chart-equatable-isolation-candidate.patch`：HistoryChartView conform Equatable，static==只比较chartState；Dashboard加.equatable()。历史锚点绑定其接受的历史几何；相同结果不因live snapshot而重绘。新点、source/segment/gap、loading/failure仍不相等。selectedDate为本地@State，预期仍会自主更新，需实际交互验证。

source/time风险：同图形固定首次asOf使普通墙钟微抖不动全部点；真实clockChange必须进入Gap/segment的新chartState并触发重绘，测试必须覆盖该路径。缓存失败/加载的历史锚点冻结符合展示旧查询的范围。此前tooltip显示方法本身是anchor映射，不是所有point.wall直接格式化；此次优化不应扩大为未验证的时间语义改写。

## 验证建议

- 应用前用真实AppRuntime查询spy/TestClock证明200ms自动历史刷新；应用后同时间序列应只有≥1秒的自动刷新，强制选择/范围/唤醒仍立即查询。不写仅验证常数字面值的镜像测试。
- 视图Equality测试：同chartState而asOf不同等值；新point/source/layer/segment/gap/loading/failed不等；保持原2000点和min/max/count/gap边界测试。
- 用同Release、同CPU50ms、相同可见窗口宽度、同source比较≥300秒前后CPU/RSS与sample；真正性能效果以实际反馈为准。
- 真实UI验证点选/时间温度minmax/count摘要、切范围/来源、浅深色、sleep/wake gap、新来源分段；@State交互不能因eq隔离失效。
- 处理审批弹窗后，runner每个progress只读取一次picker.value；AX异常仅做有限App activate＋retry，记录异常次数，不吞Fatal/退出/档位不符。
- 完整五档每600秒、真实系统睡眠另测；新增正式指标观察需记录plannedDue、worker读批started/finished、skip counter和屏幕时刻，不能拿SQL finished间隔代替全部门槛。

## 候选编译修正（软件验证，不是性能通过）

root应用两份候选后的正式Release build发现 Swift6 `HistoryChartView: Equatable`默认MainActor operator不能满足nonisolated协议要求。新增`/tmp/temperature-chart-equatable-nonisolated.patch`只把static==标为nonisolated，仍只读取不可变Sendable chartState，不访问selectedDate/@State，不引入unsafe/uncheckedSendable。

已以SDK26.2、Swift6、arm64-apple-macos15.7.3和正式Release TemperatureCore/TemperaturePresentation模块对/tmp中的单View候选typecheck，exit0、无诊断。`/tmp/temperature-chart-typecheck/HistoryChartView.swift`和`result.log`保存验证对象/结果。完整App构建、UI交互和CPU同填充对照仍由root执行，尚未判定硬件改善。
