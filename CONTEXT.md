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

当前用户指令 > 01现行需求＋21契约及contracts > 02～13专项设计 > 22/23执行步骤。15/18记录决策与来源；19/20解释复用；旧research/validation是历史证据，不能作为重新启用旧要求的理由。冲突须修正文档、验收映射和测试，不靠隐藏代码决定。

本轮C10授权形成完整交接，工程参数已经选择；不能把选择写成实测通过，也不能把没有完全匹配开源代码的自有算法伪称直接移植。C11已解决实时数据路径。

## 当前实现状态

已有生产Core、SensorWorker、App、Xcode工程及CI；2026-10-02正式App审查确认本机CPU12→Raw max→EMA可运行，历史与故障/清理等17项缺陷已按修复计划解决；a97fd5a核心337测试、独立审查及正式Release本机短测通过，详细范围见docs/validation/product-fixes/2026-10-02-a97fd5a/report.md。修复PR和原W11验收PR分开处理，不能将短测标为全部正式验收。用户仅本机使用，豁免72/73h、公证、公开发行与跨机型认证；72h会话历史功能保留。文档基线与 `blocking-issues` 已合入 main；T00.5 启用 `main-protection` ruleset。其他 agent 按 22 完成任务及证据；不应重新研究已删除的逐核接口。

### 2026-10-03 验收刷新

PR44已merge commit合入main403d44b；旧W11 PR26恢复Draft。新真实睡眠暴露历史刷新误Fatal(#46)和自动退出卡住(#47)，在当前隔离feature工作树修复并重验。五档各10分钟保留；2026-10-03 08:00UTC用户明确“跳过休眠测试”，本轮三轮物理验收仅标skipped-by-user，生命周期功能和软件回归仍保留；旧短测不替代其他未豁免门槛。

证据catalog格式version2，产品契约族仍v1/revision3；source commit须在delivery且delivery须在当前HEAD历史中。逐REQ声明必需证据种类、已覆盖和未测项，formal实机必须记录Release/fixture=false/App+worker hash/机型系统。声明结构门禁不自动证明报告真实性，仍需独立审查。

### 2026-10-03 c354证据与用户范围更新

c354五档清醒时长条件已分别observed：50/100/200/500ms原phase各约601秒；1000ms在同一App/worker/Session连续区间经独立clock、Cua与末端SQL补证641.637秒。原XCTest因最后一档AX控件缺失仍为FAILED，不能改suite通过。精确scheduler skipped、读批p95/p99及首帧/屏幕显示p95仍not_measured，性能门槛不变。用户2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理睡眠/人工唤醒验收仅标skipped-by-user；已经触发的两次attempt观察保留partial，生命周期功能和软件回归继续保留。 [不可变归档](docs/validation/product-software/W11/2026-10-03-c354b03/README.md)保存原失败suite、四档phase、末档同Session独立补证、Raw/SQL overlap、资源与正常退出；[最新user-scope](docs/validation/product-software/W11/2026-10-03-c354b03/user-scope.json)保存用户原话。

前次生产源码`f9e850cb6986ca9b22980849c503080c8b5d96ee`已集成Issue [#50](https://github.com/sisyphe550/Temperature-monitoring/issues/50)两行父窗口索引查找修复及TTL回归；完整349测试/55组通过、核心覆盖89.01%，正式Release构建/签名/上游边界通过。新App短测重试1项149.485秒PASS，首次runner启动失败独立保留；[最终归档](docs/validation/product-software/W11/2026-10-03-f9e850c/README.md)保存153份源码匹配、App/worker身份、原日志hash和14份自有UI附件。六项明确软件TTL缺口已局部补齐：当前100项本机接受、31项待验收、1项豁免、2项退役。此裁决不继承c354长测为新产物完整资格；W11、精确性能、物理菜单/其他未测要求及blocking/CI仍按实际证据处理。

## 2026-10-03 当前Worker管道修复

当前生产源码`7124dc1644516f471d69930024589342c0ca34c9`追加Issue [#51](https://github.com/sisyphe550/Temperature-monitoring/issues/51)修复：新请求管道在spawn前配置SIGPIPE保护，断管EPIPE进入既有协议错误及worker回收；全局信号策略、公开接口、schema和默认值不变。同一公开接口用例在原f42源码signal13 RED、候选GREEN，实际子PID已回收。完整Core355项/57组PASS，覆盖7120/8002=88.98%；Release构建、签名、上游边界通过，正式App新短测1项87.162秒PASS。 [最终源码与证据](docs/validation/product-software/W11/2026-10-03-7124dc1/README.md)保存155份源文件身份、二进制完整SHA、14份自有附件和独立审查。 当前仍为100项接受、31项待验收、1项豁免、2项退役；本轮物理休眠按用户要求跳过，软件生命周期回归保留。原f42 CI失败、c354 FAILED长测和f9历史验证均保持原件；短测不等同完整硬件性能资格，PR26保持Draft。
