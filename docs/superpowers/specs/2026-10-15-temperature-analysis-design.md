# 温度分析设计与验收

更新：2026-10-15；实施契约v1族 contract revision 5。用户已批准“系统热状态、CPU温度判断、变化趋势和操作建议”方案，并授权先同步需求、设计、验收和任务文档后直接开发。当前已在源码`e46f70c`完成实现与软件/正式Release短测；完整Core445项/65组、覆盖89.32%，REQ-135及五课程criterion通过。证据见[软件](../../validation/temperature-analysis/2026-10-15-e46f70c/software.json)、[正式短测](../../validation/temperature-analysis/2026-10-15-e46f70c/formal-app-short.json)与[一次最终独立审查](../../validation/temperature-analysis/2026-10-15-e46f70c/independent-review.md)。课程材料与最终Git/CI状态以PR #58和本机交付记录为准。

## 1 目标与范围

在现有本机课程App中增加统一温度分析卡片，帮助用户理解当前读数及下一步操作。复用真实CPU12同批Raw最大值、已有EMA/趋势、原阈值规则和原生界面；不改采集硬件、SQLite schema、worker协议或本机交付范围。

- 系统热状态：读取Apple公开ProcessInfo.thermalState，映射nominal/fair/serious/critical/unknown。它是整机热状态，不是某个CPU热区安全阈值。
- CPU判断：独立于提醒开关，解释低于阈值、达到阈值待确认、已持续达到阈值、恢复观察及无法判断。
- 趋势：复用CPU主指标10秒EMA线性回归，至少3点、时间覆盖≥80%、平稳带±0.02°C/s（保留已有数值容差）。
- 建议：确定性的Core策略给出观察、关注上升/阈值、恢复观察、减少持续负载、查看活动监视器和保持通风等说明。

主实时温度与曲线继续显示EMA。分析卡单独标注“CPU热区Raw最高温度”，不可拿EMA或预警历史峰值当当前Raw。90°C/5秒及阈值减5°C/10秒仍为软件参考规则，不宣称Apple硬件安全上限、外壳温度、逐物理核心温度或硬件损坏诊断。

## 2 CPU判断与连续性

CPU分析使用独立always-on状态，和用户可关闭的预警并行。仅接收Qualified固定CPU12完整同批且已经通过匹配ProcessingReceipt的Raw主样本。每个新样本只推进一次持续判断。

- belowThreshold：尚无活动分析超阈值阶段，当前Raw低于设定阈值。
- pending(since)：Raw≥阈值，尚未满足durationSeconds。
- sustained：已连续达到阈值；若当前温度回落但不满足完整恢复条件，说明“曾持续超阈值，尚未满足恢复条件”，不可声称当前Raw仍高于阈值。
- recovering(since)：Raw≤阈值减5°C，等待连续10秒恢复；回到恢复阈值以上取消本次恢复计时。
- unavailable(reason)：无新读数、成员不齐/失败、Gap、sourceChange、stale或lifecycle。缺测不是恢复。

使用Timestamp.elapsedNS，不用样本数乘周期，不用墙钟计时。复用现有CPUWarningEvaluator算法的独立值实例，内部enabled=true、notifications=false、eventLimit=1；不发布内部事件、不产生通知、不增加数据库实体。关闭/开启真正预警或仅改变通知开关不影响分析连续性；阈值或持续秒数变化使分析中断并等待新的完整有效样本，不能直接显示低于阈值。

## 3 提交与快照

CPU分析与Raw/EMA在已有actor mutation边界暂算，仅匹配Receipt后交换。提交失败、旧代次、乱序和重复请求不发布新分析。等待Receipt期间已过期或快照已中断时，回到当前已发布分析重算，禁止用迟到数据复活阶段或制造持续达标/恢复。

Snapshot继续不等待正在进行的持久化提交，只使用已提交缓冲和状态；读取可按TTL降级为unavailable，不能推进持续达标或恢复。TTL使用样本自身periodMS的max(3×period,2000ms)，等值有效，超过才失效。来源/segment变化及生命周期中断须同步失效。旧Raw与EMA可继续明确标为缓存展示，但不能形成当前CPU判断。

有效分析的TrendValue由Core调用现有TrendCalculator，从当前series/segment已提交EMA有界buffer计算，窗口锚点为最新已提交Raw observation.timestamp；不是UI刷新时钟。趋势不足显示“数据不足”，不退化成平稳。CPU本身失效时不显示旧趋势为当前趋势。没有SQLite查询、额外硬件读取或第二套趋势算法。

## 4 唯一公开状态

权威精确定义在contracts/api-v1.swift。新增名称冻结如下：

- CPUThresholdAssessment：belowThreshold / pending(since:) / sustained / recovering(since:)。
- CPUAnalysisState：unavailable(reason:CPUWarningInterruptionReason) 或 available(observation:Sample,assessment:CPUThresholdAssessment,trend:TrendValue)。
- CPUAnalysisSnapshot：thresholdC、durationSeconds、state。
- SystemThermalState：nominal / fair / serious / critical / unknown。
- TemperatureAdvice：awaitingCPUData / continueObserving / temperatureRising / thresholdReached / sustainedHighTemperature / coolingDown / systemWarm / systemHot / systemCritical。
- TemperatureAnalysisSnapshot(cpu:systemThermalState:)：包含cpu、systemThermalState和由Core TemperatureAdvicePolicy计算的advice。
- Snapshot.analysis为CPUAnalysisSnapshot；RunningPresentationState.analysis为TemperatureAnalysisSnapshot。构造时显式提供，不以独立UI布尔值替代。

PresentationModel.apply(snapshot:systemThermalState:)接收本次系统热状态；省略注入时只能unknown，生产App必须显式注入。history loading/ready/failed重建保留同一分析，旧generation与fatal后更新不得覆盖。

App通过TemperaturePresentation中的ProcessInfoThermalStateProvider及可注入SystemThermalStateProviding薄接口同步读取系统状态，无额外权限、通知或后台轮询任务。未知未来枚举映射unknown，不默认正常。系统状态与CPU读取不宣称同一硬件测量时刻；前者只表达本次系统读取结果。

## 5 建议和界面文案

建议优先级：system critical→systemCritical；serious→systemHot；fair→systemWarm；其余情况CPU unavailable→awaitingCPUData；recovering→coolingDown；sustained→sustainedHighTemperature；pending→thresholdReached；belowThreshold且趋势rising→temperatureRising；其余→continueObserving。unknown可继续解释有效CPU数据，但系统一栏必须写未知，不能显示系统正常。

正常只用于“系统热状态正常（macOS报告）”。CPU低于阈值写“未达到设定阈值”，不写“CPU安全”。无效CPU即使系统nominal也必须保留CPU无法判断；系统serious/critical即使CPU缺测仍可基于整机状态建议降低负载。建议不诊断散热器损坏，不自动关闭进程或控制风扇。

主窗口与Popover复用分析视图，分别展示完整/精简内容；保留现有预警状态和事件。说明Raw、EMA和窗口用途，不把各来源总峰值当CPU峰值。pending/recovering的已观察秒数基于最后有效observation.timestamp减since，而非重复刷新快照的当前时间。

## 6 验证

TC-ANALYSIS软件覆盖：四系统状态及unknown映射、Core建议优先级、Raw/EMA明显不同、未超阈值/持续/恢复、warning关闭后仍分析、通知开关不重置、阈值/时长变更需新样本、读取失败/成员不齐/Gap/source/lifecycle、样本period TTL边界、held/拒绝/乱序Receipt和重放、趋势3点/80%/±0.02及segment隔离、过期CPU不显示当前趋势、快照刷新不推进阶段、history状态重建及fatal。

正式Release App只做一次核心短测：真实CPU12/°C与Raw/EMA标注、本机实际系统热状态、运行足够观察10秒趋势、临时降低阈值观察持续判断、关闭预警后分析仍更新、恢复默认规则、五档短切换、历史、关窗重开及退出。serious/critical/unknown与故障/精确时间边界采用确定性软件注入，不人为加热。没有真实观察到的系统档位不写实机通过。

一次完整Core回归及原≥80%覆盖分母、必要CI、一次最终独立审查；复现真实缺陷建blocking Issue并修复必要回归。保留已免除的真实休眠、72h耐久、五档10分钟、公证、发行和跨机资格，不重新加入长测。

新证据放docs/validation/temperature-analysis/日期-源码前缀，feature=temperature-analysis、contract_version=5，source_commit和原始日志明确。旧revision4预警材料保留原样，不能改标签当分析证据。软件与正式App结果分别记录；最终报告/PPT只同步实际结果。

## 7 任务与交付

REQ-135为核心必验，REQ-125继续负责预警，REQ-045明确分析Raw例外；新增W13/T13.1～T13.5和TC-ANALYSIS。公开契约及绑定升revision5；schema user_version=1/profile_version=1不变。原子提交同步文档/类型/资源/测试；文档先完成不意味着先提交一份与生产不兼容的修订。

从最新origin/main建立feature/temperature-analysis，适用门禁、独立审查和同head五CI通过后按授权merge commit，保留分支。构建后交付正式App及启动说明，最后同步原目录课程报告、PPT和相关图表，达到本机课程目标后结束。

## 参考依据

- Apple ProcessInfo.ThermalState：https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
- Apple Mac运行温度说明：https://support.apple.com/en-us/102336
- 本项目Processing/Trend.swift、Warnings/CPUWarningEvaluator.swift及既有CPU预警提交边界。

仅参考公开API语义与现有自有算法，本次不复制第三方实现，third-party-v1登记范围不变。

## 2026-10-15 实施结果与边界

T13.1～T13.4已完成。定向Core120项/12组、Presentation19项/2组、新增本机Debug UI3项零失败；完整Core445项/65组零issue、24.645秒，覆盖7586/8493=89.32%，统计范围未缩减。正式Release fixture=false在Mac16,13、macOS15.7.3/24G419观察真实CPU12、Raw/EMA差异、趋势上升/下降/平稳、35°C/5秒持续判断、关闭预警后分析继续、五档短切换/历史/关窗重开/正常退出及清理。系统仅实测nominal；其他热状态、自然恢复和故障/精确时间边界的验证范围见软件与正式报告，不人为升温。

一次最终独立审查未发现功能或阻断缺陷，两处文件尾空行已作纯空白修正。T13.5审查部分已完成；课程Word/PPT/图表及最终同head五CI、merge commit和分支保留的执行回读，以PR #58和本机交付记录为准。
