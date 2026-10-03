# 项目上下文与有效决策

更新：2026-10-03；实施契约v1族，contract revision 3。接手入口：[00](docs/00-agent-handoff.md)。

这是学校实验项目：从本机温度接口采样、加工、保存、原生展示。C11用户明确课程不强制数据库往返，采用内存实时路径和SQLite批量持久化/历史查询。无需继续询问教师路径选择。

## 本版边界

Apple Silicon MacBook Air；首配置Mac16,13 M4，已存CLI证据仅macOS15.7.3/24G419。最低运行目标15.7.3，实际兼容按正式App报告逐组合声明。Swift6＋C桥接，SwiftUI/AppKit/Charts；本地SQLite；主App＋普通用户自有SensorWorker。

CPU主指标为固定12热区Raw max后EMA；SSD为唯一内置NVMe SMART composite；电池按IOPS/TB1T/TB2T/TB0T固定单源。CPU关键，附件可选但适配/状态必须实现。CPU五档50/100/200/500/1000ms默认200；SSD500ms、Battery1000ms。

Raw与EMA均保留5分钟，分层历史最多72小时，只在当前会话存在；关窗口不结束会话，退出/重启清理监控库，日志独立保留。取消逐物理核/core_id、物理Package保证、告警、登录自启动、Web、Docker、远端业务服务、风扇控制与自动更新。

## 术语

| 名称 | 固定含义 |
|---|---|
| sourceID | 某provider连接代次内的来源实例UUID，不是物理核心或永久硬件ID |
| seriesID | 一个可绘图来源/派生定义；换成员或语义时新建 |
| metricID/definitionVersion | 可见指标角色与定义版本；如cpu.zone.max |
| segment | 同一定义内的连续数据段；Gap后重启EMA/趋势 |
| Raw | 应用取得的未经EMA平滑的有效读数；不声称ADC原值或新硬件测量 |
| EMA | 使用实际dt的指数平滑，菜单栏与实时图表所用值 |
| E1/E2/D | 目标机读取证据／固定上游或SDK路线／本项目设计 |
| referenceClassified | 有固定上游分类依据，不等于物理位置或精度已校准 |
| targetQualified | 通过本项目正式目标构建验收，仍非计量校准 |
| elapsed/wall | 系统连续时间用于调度/TTL/算法；真实墙钟用于观测标签 |
| Fatal | 必须停止本次运行的关键故障；不同于单项能力Unavailable |
| DiscoveredCatalog | SensorTransport观察到的底层事实；不带CPU/SSD/Battery语义，不能进入算法或UI |
| QualifiedSourceCatalog | Registry按profile、单位、编码、证据和generation资格化后的来源；只有Qualified来源可采样 |
| ReadingOutcome | success或failure二选一；失败不携带值，不补0°C或重放旧值 |
| PersistenceLease | SessionPersistence内部创建的一次性容量与owner凭据；commit取得ProcessingReceipt后才交换算法状态 |
| PresentationState | running或fatal互斥展示状态；值与图表也使用封闭枚举，不由各视图自行判断 |

实际第三方复制/修改代码只以[third-party-v1.json](docs/contracts/third-party-v1.json)为准，研究manifest不能替代。`TC-UPSTREAM-BOUNDARY`覆盖上游行为反例、Release禁用符号和许可证/notice缺失门禁。

## 文档优先级

当前用户指令 > course-delivery-scope及course-delivery-v1课程验收政策 > 01现行功能＋21实现契约及contracts > 02～13专项设计 > 22/23执行步骤。15/18记录决策与来源；19/20解释复用；旧research/validation是历史证据，不能作为重新启用旧要求的理由。冲突须修正文档、验收映射和测试，不靠隐藏代码决定。

本轮C10授权形成完整交接，工程参数已经选择；不能把选择写成实测通过，也不能把没有完全匹配开源代码的自有算法伪称直接移植。C11已解决实时数据路径。

## 当前交付范围与状态

最新用户直接授权恢复最小收尾，目标是本机课程演示App，满足当前课程门槛后完成PR合并交付；这覆盖此前“当前工作完成后暂停”以及五档各10分钟/物理睡眠的旧执行要求。授权要点、五criterion和停止条件以[课程交付范围](docs/course-delivery-scope.md)及[课程政策](docs/contracts/course-delivery-v1.json)为准。

公开API/default/profile/schema仍revision3，50个任务与DAG不变。完整Core及≥80%覆盖、关键失败/数据/生命周期软件回归、CPU12 Raw max→EMA、来源单位与失败不造值必须保留；本机正式App完成启动、五档短切换、历史、关窗重开与正常退出。同一次短测同次观察已填充的五分钟历史，五档短切换，同时观察App/Worker CPU、RSS和交互，不加压力负载。严格132资格、五档10分钟、物理sleep、72/73h耐久、公证/跨机及精确性能为可选扩展，不阻塞当前本机交付。

本轮App核心观察与五criterion通过；独立审查、同head CI和合并仍按PR实际结果确认。生产修复证据见[7124](docs/validation/product-software/W11/2026-10-03-7124dc1/README.md)，测试同步见[f0](docs/validation/product-software/W11/2026-10-03-f0a7dde/README.md)；旧逐REQ100accepted/31pending/1waived/2retired保留。最终本机交付与旧全132项扩展资格分开判定，不把pending改成passed。

[c354不可变归档](docs/validation/product-software/W11/2026-10-03-c354b03/README.md)保留原FAILED suite、duration补证、partial物理sleep及not_measured性能；[原产品审查](docs/validation/product-review/2026-10-02-48cd967d/report.md)和[原修复](docs/validation/product-fixes/2026-10-02-a97fd5a/report.md)保留当时范围。历史记录中的当时“必须继续长测/暂停/保持Draft”不重新启用当前已授权取消的门槛。

收尾依[11](docs/11-git-github-workflow.md)进行一次最终独立审查，回读同head五CI、零真实blocking与保护配置后按用户授权merge commit，保留本地/远端分支；完成即停止扩展工作。
