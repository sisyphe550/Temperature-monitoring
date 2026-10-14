# CPU温度预警实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在正式本机App加入真实CPU持续阈值预警、恢复、配置、事件与可选系统通知，并验证课程交付。

**Architecture:** MonitorEngine暂算纯预警状态，匹配Receipt后发布CPUWarningSnapshot。TemperaturePresentation承接状态、UserDefaults规则保存和可测试通知dispatcher；App提供原生显示与UserNotifications薄适配器。

**Tech Stack:** Swift 6/Swift Testing、SwiftUI/AppKit、UserNotifications、现有SQLite与XCTest；不加第三方依赖。

**Spec:** [批准设计](../specs/2026-10-14-cpu-warning-design.md)与[完整预警规格](../../24-cpu-warning.md)。用户已明确授权文档完成后直接实施；本计划采用并行的独立文件所有权和一次最终独立审查，不要求多轮模型复现。

## Global Constraints

- 最新origin/main d02f7f2，feature/cpu-warning隔离分支；保留用户工作区。公开契约revision4，schema user_version=1、worker协议版本不变。
- 只判断固定12 Qualified CPU成员同批完整Raw max；默认启用、90°C/5秒，恢复阈值减5°C/10秒，通知默认关闭、冷却60秒、最近50会话事件。
- threshold有限5..120°C；duration整数1..300秒。持续和冷却用elapsedNS，新有效样本推进，UI快照/缓存不推进。
- 事件.started为实际触发样本；pending.since为首候选。Gap结束interrupted而非recovered；新段重新累计。规则变更/禁用独立结束原因。
- 状态暂算后随Receipt发布，失败/重放不造事件；通知失败不Fatal，关窗不停止判断。
- defaults/API/需求/追踪/任务/验收/实际代码保持同一原子契约提交；旧无告警证据不用于新REQ-125，历史validation不回写。
- 最终完整Core>=80%、五CI、一次独立审查、正式App短测；不恢复长测、真实睡眠、公证或跨机认证。

## Review Focus

1. Receipt await期间规则修改必须串行，旧提交不能覆盖新规则；T12.2并发回归。
2. 应用刷新/图表重建不能累积高温或丢警报；T12.2 Presentation测试。
3. 异步授权后事件已结束/规则改变/退出时不能发送旧通知；T12.3 dispatcher测试。
4. CPU成员失败不能部分max，SSD/Battery-only批次不应重置CPU持续；T12.2集成测试。
5. 坏偏好须可见fallback有效默认；晚事件、冷却与去重内存须有界；T12.3测试。

## T12.1 规则与纯状态机

**Files:** 新建 `Sources/TemperatureCore/Warnings/CPUWarningTypes.swift`、`CPUWarningEvaluator.swift`（均相对Packages/TemperatureCore）；修改Configuration.swift及defaults资源；测试ConfigurationTests.swift、CPUWarningEvaluatorTests.swift。

**Interfaces:** `CPUWarningRule(enabled:thresholdC:durationSeconds:systemNotificationsEnabled:) throws`、CPUWarningSnapshot(rule:state:events:)；`RuntimeConfiguration.cpuWarning`及throws getter `cpuWarningRule`。精确枚举/API按contracts/api-v1.swift，不采用默认空warning隐藏漏接。

- [ ] 写阈值/5秒边界、短尖峰、10秒恢复、回差、同值新读数、elapsed墙钟差、规则解码非法、禁用/规则变更、中断和50条上限断言。
- [ ] 运行 `swift test --package-path Packages/TemperatureCore --filter 'ConfigurationTests|CPUWarningEvaluatorTests'`，确认新行为缺失导致失败并保存日志。
- [ ] 实现纯状态机与嵌套配置；冻结参数来自唯一defaults，输入validation拒绝非法值。
- [ ] 同命令运行至实际测试数>0且通过；审阅新增状态边界和内存上限。

## T12.2 提交、运行时与展示契约

**Files:** MonitorEngine.swift、Contracts/PresentationTypes.swift、PersistenceTypes.swift、SensorRuntime/SessionMonitorController.swift、TemperaturePresentation/PresentationModel.swift及CPUWarningCommitTests.swift/PresentationModelTests.swift，必要既有Snapshot测试构造。

**Interfaces:** `MonitorController.setCPUWarningRule(_ rule:CPUWarningRule) async throws`，Engine同名串行方法；Snapshot.warning、RunningPresentationState.warning必填。只在原事务提交确认后交换warning。

- [ ] 写实际CPU12、Raw/EMA分离、五档切换、成员失败/Gap/来源变化/过期、拒绝Receipt/重放、跨commit规则变更及图表warning转发的失败测试。
- [ ] 运行 `swift test --package-path Packages/TemperatureCore --filter 'CPUWarningCommitTests|PresentationModelTests|CommitRegressionTests|EngineGapRegressionTests'`，确认原行为缺少warning接入的失败。
- [ ] 接入已有actor mutation/commit，不修改温度schema和来源资格边界；仅有效新的CPU数据累计。
- [ ] 同命令回归通过；检查optional-only批次与生命周期软件路径。

## T12.3 规则偏好和系统通知

**Files:** TemperaturePresentation/CPUWarningPreferences.swift、CPUWarningNotificationPolicy.swift，App/CPUWarningNotificationController.swift，测试CPUWarningPreferencesTests.swift和CPUWarningNotificationTests.swift。

**Interfaces:** Preferences.init(configuration:userDefaults:key:) throws、load()/save(_:)；controller.init(configuration:onOpenDashboard:)，start(sessionID:)，update(rule:)，consume(snapshot:at:)，pause()/resume()，stop()。系统backend注入dispatcher测试，真实App使用UNUserNotificationCenter。

- [ ] 写仅四字段持久、非法数据可见fallback、写后读取校验、权限拒绝/重复开启、冷却/去重/晚到、延迟授权期间恢复/改规则/退出、投递失败不Fatal断言。
- [ ] 运行 `swift test --package-path Packages/TemperatureCore --filter 'CPUWarningPreferencesTests|CPUWarningNotificationTests'`，确认未实现时失败。
- [ ] 实现规则保存与单一dispatcher；请求前后检查同会话/规则/活动事件，取消失效pending请求；seen集合有界。
- [ ] 同命令通过；系统add成功仅记为请求接受，不伪报横幅必达。

## T12.4 设置与界面装配

**Files:** AppSessionRuntime.swift、SessionCoordinator.swift、AppDelegate.swift、PresentationActions.swift、CPUWarningViews.swift、SettingsView.swift、TemperatureDashboard.swift、TemperaturePopover.swift、StatusItemController.swift、UIFixtures.swift、TemperatureMonitor.xcodeproj及UITests。

**Interfaces:** App动作 `applyCPUWarningRule(_:) async throws`，运行时启动加载偏好并设置Core；`CPUWarningStatusView(warning:asOf:compact:)`显示同Snapshot；`CPUWarningEventsView(warning:)`最近会话事件。

- [ ] 新增UI控制/状态断言，再运行针对性UI测试观察旧页面缺少预警控件的失败；可先使用Debug fixture，正式证据另测。
- [ ] 添加表单四字段、应用/错误反馈、恢复说明、通知授权状态，菜单符号配文字，主窗/Popover状态和事件列表；图表/关窗不自建判断器。
- [ ] 运行 `bash scripts/build-app.sh` 和针对性UI测试；键盘输入、配置存取、关闭与重开通过。
- [ ] 确认Release fixture隔离、worker正常嵌入、CPU温度来源与单位不变。

## T12.5 验证与交付

**Files:** 新日期/提交validation证据、REQ125验收绑定、课程policy当前报告、PR说明；不改历史记录。

- [ ] 运行 `python3 scripts/validate-handoff.py`、文档门禁负例、上游边界及受影响脚本测试，所有实际断言保留。
- [ ] 运行一次 `swift test --package-path Packages/TemperatureCore --no-parallel --enable-code-coverage` 与 `python3 scripts/check-core-coverage.py`；Core>=80%。
- [ ] 在最终正式App短测真实CPU12/单位、五档短切换、历史、阈值触发/记录、关窗重开、通知权限/结果、退出清理；规则变更不冒充自然降温恢复。
- [ ] 记录源码/App/worker身份、命令、实测/软件证据和未观察边界；新REQ125保持pending直到新证据。
- [ ] 一次最终独立审查，修复真实阻断并针对性回归；git diff --check，原子commit，push/PR，回读同head五CI及零blocking。
- [ ] 按项目Git流程交维护者merge commit并保留分支，交付可运行App与简要测试报告，完成即止。
