# Agent实施交接入口

更新：2026-10-03；实施契约v1族，contract revision 3。目标：接手agent无需读取本对话即可按确定的范围、接口、参数、测试和Git流程完成本地App，本轮仅本机ad-hoc交付；公证、公开发行和跨机型认证已由用户豁免。

## 先读的七份资料

1. [现行需求01](01-requirements.md)：132项现行、2项退役。
2. [可行性与复用20](20-feasibility-and-reuse.md)：E1实测、E2上游路线、D项目设计及局限。
3. [实施契约21](21-implementation-contracts.md)：contract revision 3、JSON默认值/profile、Swift类型、SQL schema、第三方来源和逐REQ映射。
4. [架构02](02-architecture.md)与[组件08](08-component-design.md)：实时数据路径、worker与模块文件边界。
5. [工作包计划22](22-agent-implementation-plan.md)：W00～W11的设计、文件、测试和完成条件。
6. [执行任务23](23-execution-task-breakdown.md)：50个可审查任务、依赖图、接口产出和交接边界。
7. [Git流程11](11-git-github-workflow.md)：PR所在分支、强制门禁、Issue和merge commit。

其他专项03～10/13给出细则；16只登记已决定设计与实际执行依赖。[修订2迁移记录](research/2026-09-21-contract-documentation-migration.md)给出提交与校验结果。15/18/19和research/validation保存来源与历史，不得用旧记录恢复当前已删除要求。

## 已经决定，不重新开题

| 项目 | 本版执行选择 |
|---|---|
| 硬件 | Apple Silicon Air；首个profile Mac16,13 M4，其他机型不自动套键表 |
| CPU主指标 | Stats映射的12个CPU热区Raw max→EMA，名称“CPU热区最高温度” |
| 删除承诺 | 逐物理核温度/core_id、物理Package、绝对热点、硬件同频刷新、虚构准确度 |
| 附件 | SSD内置NVMe composite；Battery IOPS→TB1T→TB2T→TB0T；不支持显式Unavailable |
| 数据 | 内存Raw/EMA实时；SQLite批量保存Raw/EMA/聚合/趋势；最长72h、仅当前会话 |
| 进程 | Swift主App＋普通用户自有SensorWorker；无root/外部CLI/远端业务服务 |
| 前端 | MacMonitor分组面板＋Stats来源列表＋本项目历史主窗口，按07适配 |
| 验证 | 模拟/契约/CI证明软件行为；正式App在目标Air上的报告证明硬件与发布配置 |

C10用户授权清理不合适内容、补齐完整交接；上述产品收敛和工程参数在授权下形成设计基线，不虚构逐参数用户确认。C11用户明确课程不强制数据库往返，优化内存路径已确定。

## 修订3接口边界

- SensorTransport只输出`DiscoveredCatalog`底层事实；Registry验证profile、单位、编码、证据和generation后输出`QualifiedSourceCatalog`，只有Qualified来源可进入ReadRequest、算法、存储和UI。
- `ReadingOutcome`只能是success或failure；失败不得生成0°C、复用旧值或携带温度。
- SamplingService取得强类型owner的`PersistenceLease`后才启动IO或推进事件；MonitorEngine经SessionPersistence commit取得ProcessingReceipt后才交换状态。
- PresentationModel是Snapshot/HistoryResult到`PresentationState`的唯一转换器；running/fatal、温度值和历史图状态互斥。
- [third-party-v1.json](contracts/third-party-v1.json)记录实际copied/modified代码，research manifest只记录研究输入。`TC-UPSTREAM-BOUNDARY`验证上游行为反例、Release禁用符号及许可/notice完整性。

## 当前仓库实际状态

- 有独立只读原型、8项原型测试、CI及2026-09-15 Mac16,13/15.7.3/24G419证据。
- 生产Packages/TemperatureCore、SensorWorker、App和Xcode工程已创建；已按[产品审查修复计划](superpowers/plans/2026-10-02-product-audit-fixes.md)修复#27～#43；[最终代码a97fd5a报告](validation/product-fixes/2026-10-02-a97fd5a/report.md)记录337核心测试、88.61%覆盖、独立审查、16项fixture UI及正式Release本机短测。修复[PR #44](https://github.com/sisyphe550/Temperature-monitoring/pull/44)已合入main `403d44b`；[测试同步补充](validation/product-fixes/2026-10-03-651b29e/report.md)记录最新337项回归和88.71%覆盖，该次生产代码不变，PR44合并前exact-head五检查与零blocking已核对。[48cd967d审查](validation/product-review/2026-10-02-48cd967d/report.md)保留原始结论，新修复证据单独归档，不能直接改旧报告。W11验收PR #26已恢复Draft；按[新计划](superpowers/plans/2026-10-03-w11-acceptance-refresh.md)刷新，不延用旧SHA的全通过结论。
- 文档基线已由[PR #4](https://github.com/sisyphe550/Temperature-monitoring/pull/4) merge commit 合入 main。`blocking-issues` 实现已由[PR #5](https://github.com/sisyphe550/Temperature-monitoring/pull/5) 合入；ruleset `main-protection` 已启用。其他独立功能从最新 main 起分支。
- 既有原型/原始CSV/历史报告不能因产品范围调整而修改；新实测写新目录并记录源码SHA。

## 执行者启动检查

```sh
git status --short
git branch --show-current
git log -3 --oneline
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-contract -typecheck docs/contracts/api-v1.swift
xcode-select -p
swift --version
```

先检查用户改动，不覆盖或reset。CLT可完成文档/核心验证；App/UI阶段需要完整Xcode并验证工具链能表达预期15.7.3 deployment target。需要上游代码时先按研究manifest固定来源，再按third-party-v1登记实际本地路径、许可hash、notice和修改说明；不要依赖临时目录，也不要直接运行第三方监控软件替代产品。

## 接手任务与证据

以22的W工作包作为里程碑边界，按23的T任务逐项执行；W00按三步引导PR，W01～W11各用一个功能PR。代码/文档任务记录commit，外部Git或实机任务记录目标SHA和不可变报告。每个W结束更新17/acceptance-v1映射对应的验证报告（保留设计任务关系，不把pending批量改成pass）。每个报告至少记录：REQ/TC、T任务证据、源码与App/worker哈希、工具链/profile、环境、输入、预期/实际、结果和日志位置。未执行写未执行；替身测试与实机分列。

遇到真实实现问题：复现→Issue，标blocking则禁止跨阶段/合并；在既定边界内修复并回归。只有发现证据与设计实质冲突才修订契约，不能私自缩CPU成员、丢Raw、改TTL、关闭门禁或恢复逐核目标来减少工作。

## 完成的两种状态

**本地完整App完成：** 132项适用功能及流程按10/22完成，菜单栏/窗口/真实来源/SQLite/故障生命周期可运行，目标Air通过本轮适用五档与生命周期验证，输出可复核App与报告；正式签名相关项明确等待外部输入时不能标整项目发布完成。

本轮仅本机使用，用户已豁免72/73h耐久、公证、公开发行及跨机型认证。72h历史保留和容量软件规则仍适用；未执行的物理睡眠或长期试验如实标注。完整Xcode 26.3已具备，main-protection已实查启用。

**正式交付完成：** 上述条件＋Developer ID/公证＋最终包复测＋所有适用发布要求通过，维护者完成PR合并及分发决策。

外部输入清单已限定为完整Xcode、实机、仓库管理员权限和签名/公证凭证。缺凭证不阻塞本地开发；缺对应机型不能扩大兼容声明。文档完整也不能预先保证未来系统私有接口永不变化。

## W11刷新：后续执行顺序

1. [version2证据目录](contracts/acceptance-evidence-catalog-v1.json)与acceptance/17同步。403/a97/651逐项登记是历史基线；当前状态以有效证据、逐REQ裁决与授权豁免为准，012/114仍retired。每项`covered_cases`与`outstanding`是后续验证清单，不以旧快照数量判当前完成度。
2. 修复实机睡眠误Fatal #46和runtime Fatal退出死锁 #47；工具证据边界修复记录在#48。完整核心、Release、独立审查通过后，才用最终代码/同App+worker哈希做新硬件验收。
3. 用户先前保留五档各10分钟与真实系统睡眠/人工唤醒；2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理验收标skipped-by-user，生命周期功能与软件回归保留。早前约305秒失败记录仍是历史；新c354五档duration条件由同一连续会话证据分别observed，原XCTest仍FAILED，正式性能仍pending，不等于完整qualified combination。
4. 仅有验收记录缺口、没有实际可复现错误的条目继续pending，不凭推断建产品bug。历史源码/CI/fixture和正式App实机分别绑定。
5. 普通push更新既有PR26；当前原工作区及其用户文件保留。最新head五CI、独立审查和零blocking满足后，才由维护者决定merge commit；保留功能分支。

执行`python3 scripts/validate-handoff.py`只证明文档与证据绑定一致；完整验收用`--product-acceptance`，pending存在时会拒绝。禁止把前者当成整个产品通过。

## 2026-10-03 c354证据与当前衔接

c354五档清醒时长条件已分别observed：50/100/200/500ms原phase各约601秒；1000ms在同一App/worker/Session连续区间经独立clock、Cua与末端SQL补证641.637秒。原XCTest因最后一档AX控件缺失仍为FAILED，不能改suite通过。精确scheduler skipped、读批p95/p99及首帧/屏幕显示p95仍not_measured，性能门槛不变。用户2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理睡眠/人工唤醒验收仅标skipped-by-user；已经触发的两次attempt观察保留partial，生命周期功能和软件回归继续保留。 [不可变归档](validation/product-software/W11/2026-10-03-c354b03/README.md)保存原失败suite、四档phase、末档同Session独立补证、Raw/SQL overlap、资源与正常退出；[最新user-scope](validation/product-software/W11/2026-10-03-c354b03/user-scope.json)保存用户原话。

前次生产源码`f9e850cb6986ca9b22980849c503080c8b5d96ee`已集成Issue [#50](https://github.com/sisyphe550/Temperature-monitoring/issues/50)两行父窗口索引查找修复及TTL回归；完整349测试/55组通过、核心覆盖89.01%，正式Release构建/签名/上游边界通过。新App短测重试1项149.485秒PASS，首次runner启动失败独立保留；[最终归档](validation/product-software/W11/2026-10-03-f9e850c/README.md)保存153份源码匹配、App/worker身份、原日志hash和14份自有UI附件。六项明确软件TTL缺口已局部补齐：当前100项本机接受、31项待验收、1项豁免、2项退役。此裁决不继承c354长测为新产物完整资格；W11、精确性能、物理菜单/其他未测要求及blocking/CI仍按实际证据处理。

最终源/归档与六项局部裁决由非实现者追加[补充独立审查](validation/product-software/W11/2026-10-03-d3d25c0/final-independent-review.md)，已核对153源文件、34归档文件及14自有UI附件；未批准整体W11、性能或合并。

## 2026-10-03 当前Worker管道修复

当前生产源码`7124dc1644516f471d69930024589342c0ca34c9`追加Issue [#51](https://github.com/sisyphe550/Temperature-monitoring/issues/51)修复：新请求管道在spawn前配置SIGPIPE保护，断管EPIPE进入既有协议错误及worker回收；全局信号策略、公开接口、schema和默认值不变。同一公开接口用例在原f42源码signal13 RED、候选GREEN，实际子PID已回收。完整Core355项/57组PASS，覆盖7120/8002=88.98%；Release构建、签名、上游边界通过，正式App新短测1项87.162秒PASS。 [最终源码与证据](validation/product-software/W11/2026-10-03-7124dc1/README.md)保存155份源文件身份、二进制完整SHA、14份自有附件和独立审查。 当前仍为100项接受、31项待验收、1项豁免、2项退役；本轮物理休眠按用户要求跳过，软件生命周期回归保留。原f42 CI失败、c354 FAILED长测和f9历史验证均保持原件；短测不等同完整硬件性能资格，PR26保持Draft。

## 当前交接的测试同步修正

交接测试提交`f0a7dde76e3e02e66f23aed47915bb75e2fa438b`修正可选来源Generation、Budget、Wake、SleepAdmissionRace四项回归及共同任务时钟；生产/构建输入相对7124仍为空diff。原7c13与44070的CI失败保留，Cocoa256来自测试等待到期，实际CI唯一阶段未知。按真实SQLite提交、任务未来sleep边界驱动后，正常/125ms慢轮询通过；探测预算生产复制件负控、第三Receipt拒绝及第四读取消清理负控均在目标位置失败并终止，断言未弱化。最终完整Core355项/57组PASS3.093秒，覆盖7116/8002=88.93%；157份源码、构建和测试文件与实际Git对象匹配，独立审查无阻断。 [最新软件归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)另列最终源、完整回归、原失败和负控；[上一轮Generation归档](validation/product-software/W11/2026-10-03-edddf76/README.md)保持原件。正式App未重建/重测，7124短测保留原source/App/worker身份。本轮真实休眠验收按用户要求跳过，软件生命周期回归保留。验收仍100accepted/31pending/1waived/2retired，精确性能等缺口未自动接受，PR26保持Draft。完成当前修复、证据绑定与远端检查后按用户要求暂停，不启动新验收；最新head CI与Issue按GitHub回读，不能由本段宣称完整产品通过。