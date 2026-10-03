# Agent实施交接入口

更新：2026-10-03；实施契约v1族，contract revision 3。当前目标是用户本机课程演示App，采用ad-hoc Release交付。最小收尾进行中，最终短测、独立审查、同head CI与合并须按本轮证据确认。

## 先读的资料

1. [课程交付范围](course-delivery-scope.md)与[课程政策](contracts/course-delivery-v1.json)：最新直接授权、五criterion及可选扩展。
2. [现行需求01](01-requirements.md)与[追踪17](17-traceability.md)：134项映射、132历史active、2retired；旧逐REQ结果保留。
3. [可行性20](20-feasibility-and-reuse.md)与[实施契约21](21-implementation-contracts.md)：E1/E2/D、revision3、固定JSON/Swift/SQL/第三方边界。
4. [架构02](02-architecture.md)与[组件08](08-component-design.md)：实时路径、worker及文件边界。
5. [工作包22](22-agent-implementation-plan.md)与[50项任务23](23-execution-task-breakdown.md)：接口衔接、现行W09～W11退出条件；任务和DAG不变。
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
| 可选扩展 | 旧全132资格、五档10min、物理sleep、72/73h、公证/发行/跨机与精确性能 |

C11已确认课程不要求数据库强制往返；当前内存实时路径保持。最新直接授权覆盖此前暂停和长测要求，详见课程范围中的授权要点；未执行的扩展不能写PASS。

## 修订3接口边界

- SensorTransport输出DiscoveredCatalog；Registry按profile、单位、编码、证据和generation生成QualifiedSourceCatalog，只有Qualified来源进入采样/加工/存储/UI。
- ReadingOutcome成功/失败互斥；失败不得造0°C、旧值或新样本。
- SamplingService先取得PersistenceLease，MonitorEngine提交取得匹配ProcessingReceipt后交换状态。
- PresentationModel是Snapshot/HistoryResult到PresentationState的唯一转换；running/fatal、温度及历史状态互斥。
- 实际第三方复制/修改以[third-party-v1](contracts/third-party-v1.json)和TC-UPSTREAM-BOUNDARY为准，不改许可、notice或Release无fixture边界。

## 当前仓库与历史证据

生产Core、SensorWorker、App、Xcode工程和五CI已存在。PR44修复已以merge commit合入main403d44b；W11 PR26当前收尾继续，不因历史Draft文字禁止本轮授权合并。最终PR状态/HEAD/检查/Issue须回读GitHub，不由本文推断。

[7124归档](validation/product-software/W11/2026-10-03-7124dc1/README.md)保存生产修复、正式App短测及二进制身份；[f0归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)保存可选来源同步回归，生产/构建输入相对7124不变。旧逐REQ裁决100accepted/31pending/1waived/2retired保持事实；[c354归档](validation/product-software/W11/2026-10-03-c354b03/README.md)中的FAILED长测、duration观察及未测性能保留。历史结果只适用于其源码/产物，不预先证明本轮短测。

## 启动与最小收尾

```sh
git status --short
git branch --show-current
python3 scripts/validate-handoff.py
bash scripts/build-app.sh
bash scripts/launch-app.sh
```

先保留用户改动，不reset或覆盖；独立功能从最新main建立feature分支。构建输出`build/TemperatureMonitor.app`，正式交付路径/SHA待最终交付记录。正式App短测复用testLocalReleaseAppRealHardwareUI，无fixture：CPU12/单位、启动、五档短切换、历史/点选、关窗重开、正常退出。首50ms约330s覆盖最近5分钟图，其他档各8s；同次观察App/Worker CPU/RSS和交互，不加压力负载。关键失败/数据/生命周期沿用必要软件回归，再运行本轮完整Core及≥80%覆盖。

```sh
python3 scripts/bind-acceptance-evidence.py
python3 scripts/validate-handoff.py --product-acceptance
```

按五criterion绑定本轮source/App/worker SHA、profile、机型/系统、真实时长、结果、原始日志及限制。未执行为pending；不由TC整体通过或取消长测把旧REQ批量接受。`--strict-product-acceptance`仅检查可选旧全132扩展资格。

## 当前完成条件与停止边界

五课程criterion通过、文档/契约一致、一次最终独立审查无阻断、同PR head五required CI通过且无真实blocking后，按用户授权push、修改PR状态并merge commit，回读两个parent及远端分支保留，交付本机App路径与结果后停止。Git外部检查按11执行，不使文档CI要求自身未来通过而形成循环。

发现真实可复现缺陷：复现→Issue→必要修复/回归；不能降低CPU集合、单位、数据完整性、TTL或故障语义。只有单纯可选扩展未测不构成本机课程blocking。当前不安排新长测、物理睡眠、额外负控或公开发布。完整Xcode/本机已具备；没有公证凭证不阻塞本机目标，也不声明公证或跨机通过。
