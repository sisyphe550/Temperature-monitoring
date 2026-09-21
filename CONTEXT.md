# 项目上下文与有效决策

更新：2026-09-21；实施契约v1族，contract revision 2。接手入口：[00](docs/00-agent-handoff.md)。

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

当前用户指令 > 01现行需求＋21契约及contracts > 02～13专项设计 > 22/23执行步骤。15/18记录决策与来源；19/20解释复用；旧research/validation是历史证据，不能作为重新启用旧要求的理由。冲突须修正文档、验收映射和测试，不靠隐藏代码决定。

本轮C10授权形成完整交接，工程参数已经选择；不能把选择写成实测通过，也不能把没有完全匹配开源代码的自有算法伪称直接移植。C11已解决实时数据路径。

## 当前实现状态

已有只读Swift/C探针、原型测试、CI和M4短时实测。生产App、完整数据链、UI和正式发布尚未实现/验收。当前功能分支与PR4包含完整设计，GitHub强制规则仍需W00落实。其他agent按22完成任务及证据；不应重新研究已删除的逐核接口。
