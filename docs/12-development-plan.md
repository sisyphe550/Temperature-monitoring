# 阶段、依赖与交付完成条件

更新：2026-10-14；contract revision 4。当前验收以[本机课程范围](course-delivery-scope.md)为准，最小收尾进行中。W00～W12的设计和验收见[22](22-agent-implementation-plan.md)，55个可审查执行任务及依赖见[23](23-execution-task-breakdown.md)。没有承诺工期。

| 阶段 | 任务 | 交付与退出条件 |
|---|---|---|
| M0/V0已存基线 | 历史原型、来源复核、需求收敛 | 既有证据原样保留；逐核/Package等不可靠承诺已移除 |
| M1交接设计 | 00～23及contracts；W00/W01前置 | contract revision 4、第三方复用契约和21组测试冻结；当前设计有唯一方案、接口、参数和测试；外部依赖列明；文档审查通过 |
| M2数据链 | W01类型/Clock、W02接口/worker、W03存储、W04算法、W05编排、W06生命周期 | 模拟端到端、异常与幂等/有界验收通过；核心≥80% |
| M3原生界面 | W07 UI、W08 App集成 | 菜单栏/面板/主窗口可交互，UI黑盒和真实数据接入完成 |
| M4本机正式App | W09当前Release短测、五档短切换与资源/响应观察 | CPU12/单位、启动/历史/重开/正常退出证据；同次观察已填充的五分钟历史，五档短切换，不加压力；真实缺陷处理 |
| M5本机课程交付 | W10 ad-hoc App；W11五criterion及外部门禁 | 课程证据、完整Core≥80%、一次独立审查、同head五CI、零真实blocking后授权merge commit并留分支；完成即停 |

## 顺序与可独立推进

W00按文档基线、可信门禁、规则回读三个PR完成仓库引导。W01以已冻结的contract revision 4为输入，实现公共类型、`DiscoveredCatalog`到`QualifiedSourceCatalog`边界、`ReadingOutcome`、`PersistenceLease`和`PresentationState`；W01不得在实现中自行恢复旧API或另造不兼容语义。W02硬件、W03存储和W04算法从W01合入后的同一main基线独立推进；W05等待三者合入后贯通；W06完成停止/错误边界；W07/W08接界面与打包，W09检验真正硬件条件。W01～W11每个W一个PR；每个T是独立可审查单元，外部Git/实机任务以不可变报告为证据。不能把Mock数据冒充实机温度。

当前语言、指标、实时路径、schema、算法、故障语义、第三方复用边界和`TC-UPSTREAM-BOUNDARY`已成为设计基线。`schema-v1.sql`仍user_version=1；原50项任务依赖保留，修订4新增W12五项。严格全132资格、跨机支持、精确性能、正式公证及72/73h长跑当前为可选扩展，不作为本机课程前置；72h历史功能及必要软件验证保留。若某项实测失败则建Issue并修复；不可通过偷偷删除现行需求来关闭失败。

每项独立功能遵循11的feature分支→测试→Issue/回归→审查→PR→merge commit→保留分支。阶段存在blocking缺陷则不得进入下一里程碑。

## 本轮最小收尾与可选扩展

生产App已实现，既有[7124正式短测](validation/product-software/W11/2026-10-03-7124dc1/README.md)与[f0软件回归](validation/product-software/W11/2026-10-03-f0a7dde/README.md)绑定当时源码/产物。当前按五criterion完成必要软件验证、一次约7分钟正式App同会话观察、文档/证据同步及一次最终审查，再回读同head五CI和零真实blocking后按用户授权合并。完成后交付可启动本机App和实际结果，停止扩展。

最新授权覆盖此前暂停及五档各10分钟要求；物理sleep、72/73h、公证/公开发行/跨机、精确skipped/p95/p99/首帧/显示测量不再是当前阻塞项。旧逐REQ100accepted/31pending/1waived/2retired和所有失败/未测证据保持，不声称旧全资格通过。当前最小收尾仍未完成，不提前写合并或未来实机PASS。

本机Xcode/目标Air已具备；公证凭证和更多机型仅是可选发行/认证的外部输入，不阻塞本机ad-hoc交付。不能承诺未测机型、驱动阻塞的绝对回收或温度计量精度。原50项任务依赖保留，修订4新增W12五项；W09～W11继续适用课程退出条件。

## W12 CPU预警扩展

保留原W00～W11/50任务，新增W12与T12.1～T12.5，共13工作包/55任务/21TC。按[专项设计](24-cpu-warning.md)和[实施计划](superpowers/plans/2026-10-14-cpu-warning.md)完成规则→提交→保存通知→UI→验证，文档成稿前不写生产。

### W12已验证范围

[源码9583987的新证据](validation/cpu-warning/2026-10-14-9583987/README.md)记录Core413项/62组和89.18%通过、正式Release预警短测通过、同次最终独立审查#54/#55/#56复核PASS及course-local五criterion通过。T12.1～T12.4实现与验证已完成；T12.5剩同head五CI/真实blocking/merge及交付回读。旧失败和31条strict pending保持，不提前声明合并或全132资格完成。
