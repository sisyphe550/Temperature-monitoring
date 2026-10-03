# W11 验收刷新与本机交付计划

> **For agentic workers:** 使用 superpowers:executing-plans 在当前隔离工作树执行，独立审查后更新已有 PR #26。

**Goal:** 在已合入修复的 main 上刷新逐需求证据，归档c354五档各10分钟的实际duration观察及原自动化失败，完成#50修复后的软件门禁与新Release短测，继续未完成的适用验收并准确交付本机App。本轮物理睡眠/人工唤醒测试已由用户明确跳过。

**Architecture:** 403d44b是PR44合入main的起始基线，c354b039已合并旧W11并修复#46/#47与图表刷新。保留历史报告，#50及新增TTL/SQL回归按实际新生产提交另行绑定；最终新App/worker不能继承c354长测的完整资格。证据逐项保存实际源码SHA、文件hash、执行种类、环境、覆盖和未测边界，不能由TC分组自动推导全部需求通过。

**Tech Stack:** Swift/XCTest/XCUI、Python、SQLite、Git/GitHub。

**Spec:** docs/22-agent-implementation-plan.md 的 W11、docs/23-execution-task-breakdown.md 的 T11.1–T11.3、docs/10-test-strategy.md、docs/11-git-github-workflow.md。

## 约束

- 仅本机 Mac16,13；72/73h耐久、公证/发行和跨机型认证已豁免；72h历史软件规则保留。
- 用户先前保留五档各10分钟及真实睡眠/唤醒；2026-10-03 08:00UTC明确“跳过休眠测试”。仅本轮三轮物理验收标skipped-by-user，生命周期功能和软件回归保留；五档duration及其他未豁免门槛不以8秒或Controller.suspend/resume替代。
- 保留接口、默认值、schema与CPU12成员；当前修复范围包含#46历史查询生命周期、#47 AppKit退出、#49图表刷新及#50维护SQL查找；保留原工作区未提交内容，不把观察到的SQL性能改进推断为全部Gap根因已解决。
- 历史报告原bytes保留；全部证据在新日期/SHA目录，不回写旧通过状态。
- 无root/helper/writeSMC；本轮不再执行物理睡眠，也不再请求人工唤醒。此前实际attempt仅保留partial证据，不扩大为整项需求豁免。

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

### T3 正式App持续性归档与性能边界
**Files:** UITests/TemperatureMonitorUITests.swift；docs/validation/product-software/W11/2026-10-03-c354b03/；后续实际新source目录。
- [x] c354正式Release无fixture的50/100/200/500ms原phase各约601s；1000ms由同一App/worker/Session连续区间的clock、Cua与SQL补证641.637s。仅duration条件observed，原XCTest最后一档AX失败仍FAILED；UI/Raw/EMA/CPU12及性能按各自用例分别判定。
- 本轮三轮物理睡眠/人工唤醒验收：skipped-by-user；已有两次attempt及后续观察保留partial，生命周期功能和软件回归保留，不声明三轮通过。
- [ ] 精确scheduler skipped、读批p95/p99、首帧/显示p95按10的既定门槛补齐；成功样本间隔、理想点数短缺和资源分布不能替代。当前not_measured。
- [x] #50修复后的f9源码完成349/55完整Core、89.01%覆盖、Release构建/签名及独立SQL/TTL审查；正式新App短测重试149.485s PASS，原bootstrap失败保留。[最终归档](../../validation/product-software/W11/2026-10-03-f9e850c/README.md)另存源码/App/worker身份，不把旧长测继承为新产物完整资格。
- [x] 保留原失败、partial及未测结果；不外推全部132项或全部硬件。

### T4 交付刷新和独立审查
**Files:** README.md、docs/00-agent-handoff.md、CONTEXT.md、docs/23-execution-task-breakdown.md、新W11 report/delivery/manifest。
- [ ] 逐REQ审查：337/88.71%及a97实机是历史基线，c354为341/88.88%的历史软件门禁。最终新增TTL/SQL修复须以实际新提交完整Core/覆盖、Release短测和独立审查另归档，再绑定当前有效证据、未完成项和用户局部跳过；记录exact-head CI/合并证据，不固定沿用旧测试数量。
- [ ] 保留旧W11报告，更新当前入口；解释“测量更新时间未知”为来源接口缺少测量时间戳。
- [ ] 适用工具负例、handoff、代码差异、独立审查；普通push更新PR26，不force。
- [ ] PR26最新head五检查及零blocking；使用merge commit/保留分支，是否具备完整验收以实际结果决定。

## 历史：2026-10-03 实机中断后的计划修订

本节记录当时修订与执行状态，不作为再次睡眠的当前指令。当前执行入口以T3/T4和最新用户范围为准。

Ruling：当时决定在继续长测前修复Issue #46、#47；原“不改变生产App”约束不足以达成真实睡眠和正常退出，修复合法暂停查询的取消语义及AppKit退出入口，公开状态契约不变。

- #46暂停中的历史查询不执行SQL、不进入Fatal；invalidate旧历史任务并禁止暂停中重启，未启动/停止错误保留。软件RED/GREEN及最终源码独立复核已归档，issue关闭仍须当前CI/回归条件。
- #47 Swift MainActor直接退出与main dispatch入口最小RED；RunLoop common入口GREEN。c354正式Release runtime Fatal自动退出实机记录已归档，issue关闭及整REQ结论仍须当前CI/回归和各用例条件。
- 原51c0会话Fatal/样本/电源时间线/partial进度作为历史保全；不回写当时失败结果。后续实际结束和清理只以对应执行证据判定。
- 当时计划在重新构建后执行新五档及sleep/wake；c354五档duration已有后续独立归档，睡眠后由用户明确跳过。本行不再授权或安排新的物理睡眠，所有后续新证据仍须绑定实际源码与二进制hash。

## 历史准备证据及c354归档衔接（不改变逐REQ结果）

- 工具35项、binder dry-run、普通handoff及product gate拒绝37项pending已复核；T2工具环节完成，T11整体仍未完成。
- #46启动/暂停期间history取消的生产路径软件回归：immediate/discover-held、三项edge及退出途中wake取消的RED/GREEN已保存在[运行时归档](../../validation/product-software/W11/2026-10-03-403d44b/runtime-regression/final-independent-production-review.md)，c354提交包含该生产路径；目录名403表示准备基线，不把其所有记录当403生产代码结果。这些软件证据不是实际系统三轮sleep/wake资格。
- #47早期候选的32.369s/32.097s观察保留为各自身份的历史；最终c354 [runtime Fatal记录](../../validation/product-software/W11/2026-10-03-403d44b/anchor-release-runtime-fatal/result.json)另存实际App/worker哈希、退出和清理。不得混用候选时间或据单一路径宣告REQ-078完整组合通过。
- 033320历史重跑失败：50ms最后UI进度265.752s，无600s阶段结束；DB最后elapsed325.833s、runner总371.103s含清理均不能补成600s。该次T3结果原样保留，当前c354独立duration补证另记，不回写本失败结果。
- [403基线pending清单](../../validation/product-software/W11/2026-10-03-403d44b/pending-execution-checklist.md)保留为历史任务快照；后续按当前catalog有效证据和未完成项继续，新证据仅局部更新，不回写历史或沿用旧数量判当前完成。

## 2026-10-03 c354长测补证与用户范围更新

c354五档清醒时长条件已分别observed：50/100/200/500ms原phase各约601秒；1000ms在同一App/worker/Session连续区间经独立clock、Cua与末端SQL补证641.637秒。原XCTest因最后一档AX控件缺失仍为FAILED，不能改suite通过。精确scheduler skipped、读批p95/p99及首帧/屏幕显示p95仍not_measured，性能门槛不变。用户2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理睡眠/人工唤醒验收仅标skipped-by-user；已经触发的两次attempt观察保留partial，生命周期功能和软件回归继续保留。 [不可变归档](../../validation/product-software/W11/2026-10-03-c354b03/README.md)保存原失败suite、四档phase、末档同Session独立补证、Raw/SQL overlap、资源与正常退出；[最新user-scope](../../validation/product-software/W11/2026-10-03-c354b03/user-scope.json)保存用户原话。

Issue [#50](https://github.com/sisyphe550/Temperature-monitoring/issues/50)的SQL性能修复、最终Core门禁及新Release短测须按实际新source/App/worker另记录；不将c354长测继承为新产物完整资格。当前W11未完成，物理菜单/其他未覆盖要求、精确性能和blocking/CI均按当前有效证据逐项处理，不由本段自动更新catalog或全部REQ结果。

## 当前源码与局部裁决

f9e850cb包含两行SQL修复和八个新增@Test函数，生产接口/默认值/schema不变。当前目录与binder同步为100accepted/31pending/1waived/2retired；只关闭六项明确软件TTL证据缺口。适用门禁及新Release短测通过，PR26仍Draft，exact-head CI与open blocking须GitHub回读，不声称W11完成。
