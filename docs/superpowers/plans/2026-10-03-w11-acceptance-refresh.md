# W11 验收刷新与本机交付计划

> **For agentic workers:** 使用 superpowers:executing-plans 在当前隔离工作树执行，独立审查后更新已有 PR #26。

**Goal:** 在已合入修复的 main 上重新绑定逐需求证据，补足用户保留的五档各10分钟与真实系统睡眠/唤醒测试，准确交付本机 App。

**Architecture:** 保留旧 W11 分支与报告，merge main 后只携入修正后的验收工具；生产代码以 403d44b 为准。证据逐项保存实际源码 SHA、文件 hash、执行种类、环境、覆盖和未测边界，不能由 TC 分组自动推导全部需求通过。

**Tech Stack:** Swift/XCTest/XCUI、Python、SQLite、Git/GitHub。

**Spec:** docs/22-agent-implementation-plan.md 的 W11、docs/23-execution-task-breakdown.md 的 T11.1–T11.3、docs/10-test-strategy.md、docs/11-git-github-workflow.md。

## 约束

- 仅本机 Mac16,13；72/73h耐久、公证/发行和跨机型认证已豁免；72h历史软件规则保留。
- 用户2026-10-03明确保留五档各10分钟及真实睡眠/唤醒；不以8秒或直接Controller.suspend/resume替代。
- 保留接口、默认值、schema与CPU12成员；仅修复新实机复现的睡眠竞争与runtime Fatal退出问题；保留原工作区未提交内容。
- 历史报告原bytes保留；全部证据在新日期/SHA目录，不回写旧通过状态。
- 无root/helper/writeSMC；真实睡眠需用户手动唤醒，先完成准备再确认执行时段。

## 审查重点

1. 旧TC非pending被批量转成123项通过：须显式逐REQ裁决，并保留partial/未测。
2. 全局SHA盖在旧报告上：须每证据独立SHA和hash，软件与实机分开。
3. 旧UI/构建合并覆盖修复：所有生产路径与main逐字节比较。
4. 测试runner短测误算600秒：用单调时钟，逐档记录开始/结束和数据库实际period。
5. 模拟sleep被当真实通知：记录系统sleep/wake、同PID/session、前后数据及Gap/新segment。

## 任务

### T1 合并修复并保留分支
- [x] exact-head357dbbd五检查、独立审查、零blocking、规则回读。
- [x] 重新触发blocking，merge commit合入main403d44b，两个parent及远端分支核对。

### T2 集成旧W11并修正绑定工具
**Files:** scripts/acceptance_evidence.py、scripts/bind-acceptance-evidence.py、scripts/tests/test-bind-acceptance-evidence.py、scripts/validate-handoff.py、docs/contracts/acceptance-evidence-catalog-v1.json、acceptance-v1.json、docs/17-traceability.md。
- [x] 从main建feature/w11-acceptance-refresh，merge旧远端W11，生产冲突保留main。
- [x] 建立拒绝错hash/SHA/版本、失败结果、模拟冒充实机、未授权整REQ豁免、退役项通过、未覆盖仍通过的负例。
- [x] schema version2逐artifact与逐REQ显式绑定；pending保留已有partial证据；只在覆盖充分时接受。
- [x] dry-run无写入、原子校验后写acceptance/追踪；普通handoff通过，全验收门禁对剩余pending明确失败。

工具完成证据：[35项工具独立复核](../../validation/product-software/W11/2026-10-03-403d44b/binding-tools-independent-review.md)。已验证delivery/source祖先、逐REQ结果与required kinds、formal环境结构、IO错误回滚、dry-run无写及37项pending拒绝；结构门禁不自动证明实机报告真实性，IO回滚不等于断电两文件事务保证。

### T3 正式App长采样与真实睡眠
**Files:** UITests/TemperatureMonitorUITests.swift；docs/validation/product-software/W11/2026-10-03-403d44b/ 新日志/JSON/截图。
- [ ] opt-in正式Release无fixture，50/100/200/500/1000ms每档至少600s；UI选择与DB period、Raw/EMA/max关联、节拍/资源分别记录。
- [ ] 准备睡眠前后同会话采样及通知证据；用户手动唤醒后验证重新采样、Gap、新segment/时钟、正常退出清理。
- [ ] 故障或未执行保留真实结果，不外推全部132项或全部硬件。

### T4 交付刷新和独立审查
**Files:** README.md、docs/00-agent-handoff.md、CONTEXT.md、docs/23-execution-task-breakdown.md、新W11 report/delivery/manifest。
- [ ] 逐REQ审查，绑定337软件回归/88.71%、a97实机和新长测/睡眠，记录当前CI/合并证据。
- [ ] 保留旧W11报告，更新当前入口；解释“测量更新时间未知”为来源接口缺少测量时间戳。
- [ ] 适用工具负例、handoff、代码差异、独立审查；普通push更新PR26，不force。
- [ ] PR26最新head五检查及零blocking；使用merge commit/保留分支，是否具备完整验收以实际结果决定。

## 2026-10-03 实机中断后的计划修订

Ruling：在继续长测前修复 Issue #46、#47。原“不改变生产App”约束已不足以达成真实睡眠和正常退出；只改合法暂停查询的取消语义及 AppKit 退出入口，不改公开状态契约。

- [ ] #46 暂停中的历史查询不执行SQL、不进入Fatal；invalidate旧历史任务并禁止暂停中重启；未启动/停止错误保留。回归先RED再GREEN。
- [ ] #47 Swift MainActor直接退出与main dispatch入口最小RED；RunLoop common入口GREEN；正式Release runtime Fatal的30秒自动退出和5秒停机期限单独验收。
- [ ] 原51c0会话Fatal/样本/电源时间线/partial进度保全；仅在必要授权后结束该已卡住测试进程；新App清理遗留Session并保留诊断。
- [ ] 新生产代码独立审查、测试、Release重新构建后，单次执行新五档600秒及真实系统sleep/wake。所有新证据绑定新生产SHA/二进制hash。

## 2026-10-03 当前证据衔接（不改变逐REQ结果）

- 工具35项、binder dry-run、普通handoff及product gate拒绝37项pending已复核；T2工具环节完成，T11整体仍未完成。
- #46启动/睡眠期间history取消的生产路径软件回归：immediate/discover-held与三项edge已GREEN，原始记录仍在临时验收目录，待绑定新生产提交及集成；这不是实际系统sleep/wake资格通过。退出途中wake取消已有RED，GREEN/独立复核待确认。
- #47新Release运行中Fatal自动退出实机PASS：故障注入后约32.369s、报告后约32.097s进程退出，Session已删除且报告保留；原始记录与新App/worker身份待仓内集成。未据此宣告REQ-078完整组合路径通过。
- 最新五档长测失败，50ms最后UI进度265.752s，无600s阶段结束；DB最后elapsed325.833s、runner总371.103s含清理均不能补成600s。其他四档未由本轮通过，T3长测保持pending。
- 后续执行以[37项pending清单](../../validation/product-software/W11/2026-10-03-403d44b/pending-execution-checklist.md)为入口；新证据仅局部更新，不回写历史或自动提高94/37/1。
