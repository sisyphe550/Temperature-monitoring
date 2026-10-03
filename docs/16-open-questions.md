# 设计决策闭合与待执行验证

更新：2026-10-03；实施契约v1族修订3。当前验证按[课程范围](course-delivery-scope.md)执行，不恢复旧长测或暂停要求。原OQ编号保留用于追溯。**设计已决定、实现待验收、外部输入待具备是三种状态；不能混用。**

## 原设计问题的明确处理

| ID | 当前设计决定 | 权威位置 | 后续执行 |
|---|---|---|---|
| OQ-01 | CPU固定12热区max，SSD SMART，Battery单源优先级；删除物理核/Package承诺 | 01/03/20 | W02/W09验证正式App来源 |
| OQ-02 | 五档请求日程，实际时刻/漏采独立统计；精确p95/skipped为可选扩展，当前资源观察见10 | 03/08/10 | W05模拟、W09实测；不保证硬件刷新 |
| OQ-03 | 首profile Mac16,13；source实例UUID＋generation，换源新定义 | 03/04 | W02/W09；其他机型未来配置 |
| OQ-04 | C11用户明确无需数据库强制往返，实时内存、历史SQLite；Raw/EMA仍入库 | 02/04/07 | W05/W07按唯一路径实现 |
| OQ-05 | CPU主指标关键；SSD/Battery可选；关键重试耗尽Fatal | 06 | W06故障矩阵 |
| OQ-06 | tau/趋势参数、Raw sum/count、窗口水位、首点/缺口规则已固定 | 05/defaults-v1 | W04数学与边界测试 |
| OQ-07 | 容量、TTL120秒清理宽限、WAL与保护阈值固定 | 04/defaults-v1 | W03软件TTL/容量，W09短时资源观察；实机长跑可选，不宣称长期容量实测 |
| OQ-08 | 系统连续elapsed用于dt/TTL，wall仅显示；sleep/时钟跳变分段 | 05/08/13 | W06软件生命周期，W09关窗/重开/正常退出；物理sleep可选 |
| OQ-09 | 普通用户SensorWorker；1s读/10s发现，有限回收，不虚构驱动取消 | 02/06/08 | W02假worker＋W09实机 |
| OQ-10 | 单写入、200ms/512行刷新、预留512、16K行/32MiB队列、10s故障界限 | 02/04/defaults-v1 | W03/W05故障与幂等 |
| OQ-11 | JSONL轮转/报告目录，30s可见Fatal/5s收尾、独立兜底 | 06/13 | W06不可写/卡住/双实例测试 |
| OQ-12 | 07布局；四档最近范围、最多8源/2000点、缓存过期公式、窗口关闭继续采集 | 04/07 | W07 UI黑盒 |
| OQ-13 | 不增加CPU/能耗百分比承诺；确定结构容量上限与实际记录 | 04/10 | W09量测，超硬限即失败 |
| OQ-14 | build_toolchain、deployment_target、runtime_profile、qualified_combinations分开；Swift6与实际Xcode工具链分开记录、系统SQLite、schema-v1/WAL/NORMAL、固定文件布局 | 08/09/13/contracts | W01/W03验证构建/存储；W09登记正式App组合 |
| OQ-15 | feature/PR/merge commit；检查名、blocking标签、0最低平台审批＋独立审查、人工合并 | 11 | W00门禁已落地；2026-10-02 API回读main-protection为active |
| OQ-16 | 工作名/Bundle ID确定；本机ad-hoc App交付；Developer ID公证ZIP为可选，手动更新 | 13 | W08/W10当前本机交付无需正式凭证；可选发行由维护者提供 |
| OQ-17 | 契约修订3固定ReadingOutcome、资格化来源、SessionPersistence能力视图、PersistenceLease/ProcessingReceipt和PresentationState；无并行旧API | 02～10/21 | W01～W08按唯一类型实现；不再作为设计问题 |

上述事项的**设计分支已收敛**，不能继续按旧文档同时实现两套路径。实测不符合基线时记录失败、修订受影响契约及测试，不将“已决定”改写为“已验证”。

## 当前实际依赖与收尾

| 输入/结果 | 当前边界 | 对接手agent的动作 |
|---|---|---|
| 完整Xcode/普通用户目标Air | 本机工具链与Mac16,13已具备；旧正式短测有原身份 | 用本轮正式App同会话短测和资源观察绑定新source/App/worker SHA，不重复旧全资格实验 |
| 必要软件回归 | 当前生产功能与已有异常用例保留 | 本轮完整Core≥80%，CPU失败/数据/生命周期/断管与清理必要回归保持 |
| 仓库门禁 | 按11回读当前head五CI、保护和零真实blocking | 一次最终独立审查后执行授权merge commit并保留分支，完成即停 |
| Developer ID/Team/公证凭证 | 本轮不是必需输入 | 仅未来启动可选公开发行时索取，不阻塞本机ad-hoc目标 |
| 更多机型/系统或严格性能 | 无本轮证据，不扩大支持 | 跨机/精确skipped/p95/p99/首帧/显示、长跑与物理sleep为可选，不假写PASS |

没有未决架构/数据流/UI状态或第三方复用选择。最新用户授权覆盖先前暂停及五档10min要求；当前只有[五课程criterion](contracts/course-delivery-v1.json)与上述最小收尾，不把旧31pending等同当前31个阻塞任务。真实可复现错误仍按11建Issue/修复，不能隐去blocking或降低CPU、单位、数据、TTL语义。最终App核心观察与课程门禁已有本轮记录；审查/CI/合并仍以实际结果确认。

## 不作为待实现功能

逐物理核温度、物理Package精确映射、全芯片绝对热点、外部/任意SSD、硬件20Hz刷新保证、±0.1°C准确度、root修复权限、HID同名自动合并、未知IORegistry单位猜测、任意历史区间、自动更新、告警及自启动均不进入首版任务清单。
