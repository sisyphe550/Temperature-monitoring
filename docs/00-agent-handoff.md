# Agent实施交接入口

更新：2026-10-15；实施契约v1族，contract revision 5。当前目标为本机课程演示App；W13温度分析已实现并通过软件与正式Release短测，REQ-135及五课程criterion已绑定新证据；课程材料与最终Git/CI状态以PR #58和本机交付记录为准。W12修订4历史Core413/62、89.18%和正式短测仅证明当时源码/产物。

## 先读的资料

1. [课程交付范围](course-delivery-scope.md)与[课程政策](contracts/course-delivery-v1.json)：最新直接授权、五criterion及可选扩展。
2. [现行需求01](01-requirements.md)与[追踪17](17-traceability.md)：135项映射、133active、2retired；旧逐REQ结果保留。
3. [可行性20](20-feasibility-and-reuse.md)与[实施契约21](21-implementation-contracts.md)：E1/E2/D、revision5、固定JSON/Swift/SQL/第三方边界。
4. [架构02](02-architecture.md)与[组件08](08-component-design.md)：实时路径、worker及文件边界。
5. [工作包22](22-agent-implementation-plan.md)与[60项任务23](23-execution-task-breakdown.md)：接口衔接、课程退出条件；保留原50任务与依赖，新增W12预警和W13分析各五任务。
6. [测试10](10-test-strategy.md)、[本机交付13](13-operations-distribution.md)和[Git流程11](11-git-github-workflow.md)：软件/实机证据、构建、CI、Issue、merge commit。

其他专项03～09细化实现；16登记已定设计与实际依赖。research/validation是原始证据，不能用历史段落恢复当前取消的执行门槛。

## 已经决定，不重新开题

| 项目 | 本版执行选择 |
|---|---|
| 硬件 | 本机Apple Silicon Air，首profile Mac16,13 M4；其他机型不自动套键表 |
| CPU | 固定12热区同批完整Raw max→EMA，名称CPU热区最高温度，单位°C |
| 删除承诺 | 逐物理核/core_id、物理Package、绝对热点、硬件同频刷新、虚构准确度 |
| 附件 | 内置NVMe composite；Battery IOPS→TB1T→TB2T→TB0T；单项Unavailable不停止CPU |
| 数据 | 实时内存Raw/EMA；SQLite批量持久化及分层历史；最长72h、仅本会话 |
| 进程/UI | 普通用户自有SensorWorker；SwiftUI/AppKit/Charts；MacMonitor/Stats方法与原生主窗口 |
| 当前验收 | 五课程criterion；正式App同会话短测及资源观察，关键异常由必要软件回归证明 |
| 可选扩展 | 全133资格、五档10min、物理sleep、72/73h、公证/发行/跨机与精确性能 |

C11已确认课程不要求数据库强制往返；当前内存实时路径保持。最新直接授权覆盖此前暂停和长测要求，详见课程范围中的授权要点；未执行的扩展不能写PASS。

## 修订5接口边界

- SensorTransport输出DiscoveredCatalog；Registry按profile、单位、编码、证据和generation生成QualifiedSourceCatalog，只有Qualified来源进入采样/加工/存储/UI。
- ReadingOutcome成功/失败互斥；失败不得造0°C、旧值或新样本。
- SamplingService先取得PersistenceLease，MonitorEngine提交取得匹配ProcessingReceipt后交换状态。
- PresentationModel是Snapshot/HistoryResult到PresentationState的唯一转换；running/fatal、温度及历史状态互斥。
- 实际第三方复制/修改以[third-party-v1](contracts/third-party-v1.json)和TC-UPSTREAM-BOUNDARY为准，不改许可、notice或Release无fixture边界。

## 当前仓库与历史证据

生产Core、SensorWorker、App、Xcode工程和五CI已存在。本轮分析基线为已合入PR57的main f1a5559，功能分支feature/temperature-analysis。W12预警历史源码9583987保留。最终PR状态/HEAD/检查/Issue须回读GitHub，不由本文推断。

[7124归档](validation/product-software/W11/2026-10-03-7124dc1/README.md)保存生产修复、正式App短测及二进制身份；[f0归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)保存可选来源同步回归，生产/构建输入相对7124不变。旧逐REQ裁决100accepted/31pending/1waived/2retired保持事实；[c354归档](validation/product-software/W11/2026-10-03-c354b03/README.md)中的FAILED长测、duration观察及未测性能保留。历史结果只适用于其源码/产物，不预先证明本轮短测。

## 启动与最小收尾

```sh
git status --short
git branch --show-current
python3 scripts/validate-handoff.py
bash scripts/build-app.sh
bash scripts/launch-app.sh
```

先保留用户改动，不reset或覆盖；独立功能从最新main建立feature分支。构建输出`build/TemperatureMonitor.app`，本轮正式App SHA与观察记录见[温度分析正式短测](validation/temperature-analysis/2026-10-15-e46f70c/formal-app-short.json)。正式App无fixture验证CPU12/单位、启动、五档短切换、历史、关窗重开与退出；短测访问树不稳定时原有效断言保留，以原生界面补验并记录失败。本轮新二进制实测历史加载、五档短切换及App/worker CPU/RSS和交互；历史点选及五分钟资源的旧证据保留其原源码边界。最新约4分钟短测不冒充五分钟或耐久，不加压力负载。关键失败/数据/生命周期沿用必要软件回归，再运行本轮完整Core及≥80%覆盖。

```sh
python3 scripts/bind-acceptance-evidence.py
python3 scripts/validate-handoff.py --product-acceptance
```

按五criterion绑定本轮source/App/worker SHA、profile、机型/系统、真实时长、结果、原始日志及限制。未执行为pending；不由TC整体通过或取消长测把旧REQ批量接受。`--strict-product-acceptance`仅检查可选全133扩展资格。

## 当前完成条件与停止边界

五课程criterion通过、文档/契约一致、一次最终独立审查无阻断、同PR head五required CI通过且无真实blocking后，按用户授权push、修改PR状态并merge commit，回读两个parent及远端分支保留，交付本机App路径与结果后停止。Git外部检查按11执行，不使文档CI要求自身未来通过而形成循环。

发现真实可复现缺陷：复现→Issue→必要修复/回归；不能降低CPU集合、单位、数据完整性、TTL或故障语义。只有单纯可选扩展未测不构成本机课程blocking。当前不安排新长测、物理睡眠、额外负控或公开发布。完整Xcode/本机已具备；没有公证凭证不阻塞本机目标，也不声明公证或跨机通过。

## 历史课程测试与交付记录

历史正式App核心观察、完整Core与可运行路径见[课程测试报告](validation/course-delivery/2026-10-03-5984b9e/README.md)。App/worker二进制与已验7124完全一致；自动AX失败及原生补验分开记录。独立审查、CI与合并结果仍须实际回读，不由本段预先宣称。

Core CI的独立用例编排调整及本次355项/88.84%回归见[CI收尾记录](validation/course-delivery/2026-10-03-8222e0a-ci/README.md)；原取消任务保留，App与有效测试断言不变。最终同head五CI和零blocking仍按Git流程回读。

## 历史CPU预警修订4（2026-10-14）

先读[24专项](24-cpu-warning.md)、[已批准设计](superpowers/specs/2026-10-14-cpu-warning-design.md)及[五任务计划](superpowers/plans/2026-10-14-cpu-warning.md)。REQ-125已改为Raw CPU12/elapsed预警；W12新增T12.1～T12.5，工作包13/任务55/TC21。API/defaults统一revision4，SQLite user_version=1/profile_version=1及worker协议版本不变。当时新增行为经历pending后以新证据验收；课程门禁在原五criterion内加入warning证据，不能由旧无告警结果或CI软件推断正式App通过。

本次CPU预警交付与测试边界见[报告](validation/cpu-warning/2026-10-14-9583987/report.md)；旧状态不冒充新功能资格。

## 2026-10-15 温度分析扩展（当前执行入口）

当前135REQ/133现行/2退役、14W/60T/22TC，contract revision 5。REQ-135/W13/TC-ANALYSIS已在源码`e46f70c`完成实现、本轮[软件验证](validation/temperature-analysis/2026-10-15-e46f70c/software.json)与[正式Release短测](validation/temperature-analysis/2026-10-15-e46f70c/formal-app-short.json)，课程五criterion通过。完整Core445项/65组、零issue，覆盖7586/8493=89.32%；[本轮唯一最终独立审查](validation/temperature-analysis/2026-10-15-e46f70c/independent-review.md)未发现功能或阻断缺陷。

T13.1～T13.4完成，T13.5独立审查完成；课程报告/PPT/图表由本机交付流程同步，最终同head五CI、merge commit及分支保留以PR #58和本机交付记录为准。实际只观察到系统nominal；fair/serious/critical/unknown与故障、持续及恢复边界由软件注入验证，未把规则调整当自然降温恢复。保留已豁免的长测、真实休眠、公证和跨机认证，不增加验收项目。
