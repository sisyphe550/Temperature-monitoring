# 温度分析 Implementation Plan

> **For agentic workers:** Use the existing authorized multi-agent execution in this session. Keep one final independent review as explicitly requested by the user. Each owner runs targeted RED/GREEN; root integrates, verifies and commits the atomic revision.

**Goal:** 给本机课程App增加系统热状态、独立CPU阈值分析、10秒趋势和可解释操作建议。

**Architecture:** Core拥有已提交Raw判断、独立持续状态、既有EMA趋势和纯建议策略；App仅适配ProcessInfo；PresentationModel合成唯一RunningPresentationState。沿用采集、Receipt、SQLite和原生界面。

**Tech Stack:** Swift6、Foundation ProcessInfo、SwiftUI/AppKit/Charts、既有Swift Testing/XCTest与Python文档门禁。

**Spec:** [温度分析设计](../specs/2026-10-15-temperature-analysis-design.md)，与[专项25](../../25-temperature-analysis.md)一致。

## Global Constraints

- 实施契约v1族 contract revision 5；schema user_version=1、profile_version=1、CPU12和worker协议不变。
- CPU分析只用已提交、同批完整Qualified CPU12 Raw max；主数值仍为EMA，分析单独标Raw。
- 默认90°C持续5秒，恢复阈值减5°C持续10秒。沿用原规则偏好，不新增另一套阈值。
- 预警/通知开关不停止或重置分析；阈值/持续时间变化中断分析并等待新的有效Raw。
- Snapshot不得等待mutation或持久化；可中断失效，不能靠刷新推进持续阶段。
- 趋势复用Core现有10秒OLS、3点、80%覆盖、±0.02°C/s，锚定有效Raw observation.timestamp；不跨segment。
- 系统nominal只称“系统热状态正常（macOS报告）”；unknown不默认正常，CPU失效不能据系统nominal宣称正常。
- 保留既有≥80%核心覆盖分母、必要五CI、一次最终独立审查。无休眠、72h、五档长测或人为升温。
- 文档/生产类型/资源/测试同一原子契约提交；文档先落地，再开发生产代码。

## Review Focus

1. held Receipt期间旧CPU到期：快照仍能返回，迟到提交不能复活持续阶段。
2. 只切换预警或通知：分析连续性不丢；改阈值/时间必须等新数据。
3. 系统nominal配失效CPU、unknown配有效CPU：不能产生“CPU安全”结论。
4. Raw与EMA不同、当前Raw回落但尚在恢复：数值、阶段和文案不矛盾。
5. UI刷新/历史重建、五档换档及source/segment变化：不推进虚假样本或保留过期趋势。

### Task 1 文档与契约

**Files:** 需求01、设计02/05/07/08/25、测试10、追踪17、契约21、计划22/23、contracts/*、新规格和本计划；scripts文档门禁及对应测试。

**Interfaces:** 产出REQ-135、TC-ANALYSIS、W13/T13.1..5、135REQ/133active/14W/60T/22TC；CPUAnalysisSnapshot和TemperatureAnalysisSnapshot公开签名见api-v1.swift。

- [ ] 先写拒绝旧报告重标签、缺四分析内容、版本错配的门禁测试并确认RED。
- [ ] 更新文档/机器契约、保留旧revision4历史报告按其source验证；新分析必须新source-bound证据。
- [ ] 验证文档ID/hash/DAG、API typecheck、SQLite未变；记录生产资源尚待同步项。

### Task 2 Core分析与提交接入

**Files:** Contracts/TemperatureAnalysisTypes.swift、Analysis/CPUAnalysisEvaluator.swift、Analysis/TemperatureAdvicePolicy.swift、MonitorEngine.swift；Configuration.swift、两份生产defaults/profile资源；新增CPUAnalysisTests/CPUAnalysisCommitTests及现有Snapshot测试构造器。

**Interfaces:** 消费CPUWarningRule和既有纯Evaluator/TrendCalculator；产出Snapshot.analysis:CPUAnalysisSnapshot。TemperatureAnalysisSnapshot(cpu:systemThermalState:)及TemperatureAdvicePolicy.advice(cpu:systemThermalState:)为UI唯一建议入口。

- [ ] 先写Raw与EMA不同、独立开关、规则变化、持续/恢复/失效与建议优先级测试，运行确认RED。
- [ ] 独立always-on evaluator复用原算法，内部事件限1且不发布；仅匹配Receipt后交换。
- [ ] 接入source/lifecycle/Gap/TTL及held Receipt重基线；TTL取样本period，等值有效。
- [ ] Core从已提交buffer复用TrendCalculator；旧Raw失效时不显示旧趋势；刷新不推进状态。
- [ ] 更新revision5生产资源与Configuration/ContractCoverage期望，不改硬件/存储版本；迁移测试Snapshot显式analysis参数。
- [ ] 运行CPUAnalysis/CPUWarning/Trend/相关配置提交边界针对性回归并记录GREEN。

### Task 3 系统适配和统一界面

**Files:** TemperaturePresentation/PresentationModel.swift、SystemThermalStateProviding.swift及格式化辅助；App/AppSessionRuntime.swift、TemperatureAnalysisView.swift、Dashboard/Popover、project.pbxproj；PresentationModel及UI测试。

**Interfaces:** 消费Task2公开类型；PresentationModel.apply(snapshot:systemThermalState:)默认unknown，正式App显式读取provider。RunningPresentationState.analysis保留于所有历史重建。

- [ ] 先写系统四档/unknown映射、nominal+CPU unavailable、历史loading/ready/failed与fatal/旧generation保护测试，确认RED。
- [ ] 增加薄ProcessInfo适配，无额外权限/后台循环；映射未知未来枚举为unknown。
- [ ] 主窗口与Popover共用分析视图，明确Raw/EMA、整机/CPU和趋势不足；保留既有预警/事件功能。
- [ ] pending/recovering进度取最后有效Raw observation.timestamp减since；界面刷新不得伪造已观察时间。
- [ ] 加必要可见UI断言，修Xcode四处文件引用；运行针对性Presentation/UI构建验证并记录GREEN。

### Task 4 核心验证与正式短测

**Files:** docs/validation/temperature-analysis/2026-10-15-<source>/、验收绑定；build本机交付目录。

**Interfaces:** 固定本轮生产source SHA，software与formal-app-hardware报告contract_version5分列；analysis_cases按文档门禁冻结。

- [ ] 对受影响生产代码跑针对性回归，修真实缺陷并保留失败记录。
- [ ] 一次完整Core：swift test --package-path Packages/TemperatureCore --no-parallel --enable-code-coverage；运行check-core-coverage.py，原分母≥80%。
- [ ] bash scripts/build-app.sh构建无fixture Release；必要UI/CI与正式App证据分开。
- [ ] 一次本机核心短测：真实Raw/EMA和系统状态、10秒趋势、低阈值持续阶段、预警关闭后仍分析、恢复默认、切档/历史/关窗重开/退出。
- [ ] software注入覆盖serious/critical/unknown及故障边界，不能声称本机实际经历这些状态；不人为加热。
- [ ] 写实际source/App/worker身份、观察记录和限制，运行binder/五criterion文档门禁。

### Task 5 独立审查 Git与课程材料

**Files:** 原目录课程报告/PPT/图表；当前source对应验证与交付说明。

**Interfaces:** 仅引用Task4实际证据；旧截图继续标历史，四份个人评价表保留在报告内。

- [ ] 在原子提交上做一次最终fresh-context独立审查；修阻断及必要回归，不增加无关验收。
- [ ] push/create或更新PR，附独立结论；同head五required CI、零blocking，合并前刷新检查。
- [ ] 按授权执行merge commit，回读两个parent和保留开发分支。
- [ ] 同步Word、PPT、流程/功能图，写触发/判断/趋势/建议和本轮测试；逐页渲染与内容核对。
- [ ] 交付可运行App、启动说明、简要测试报告及更新后的课程材料，达到范围后结束。

本计划已按用户本轮直接执行授权自检；Task2/3并行仅在Task1文档完成后开始。两者共享PresentationTypes签名必须以api-v1.swift为准，根agent负责集成；Core与UI各自文件所有权不重叠。
