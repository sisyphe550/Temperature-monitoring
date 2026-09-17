# 需求到设计、测试的追踪矩阵

更新日期：2026-09-17。此表覆盖全部 134 条 REQ；已记录首轮原型局部证据，**不等于产品需求验收通过**。关联代表已有测试计划，不代表已经通过或能力已经实现。

需求原文见 [需求规格](01-requirements.md)，用例组定义见 [测试策略](10-test-strategy.md)，阻塞项见 [待决策](16-open-questions.md)。

| 需求 | 状态 | 设计 | 计划用例组 | 相关未决项 | 执行状态 |
|---|---|---|---|---|---|
| REQ-001 | 已确认 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | OQ-02 | 原型局部验证；产品未验收 |
| REQ-002 | 已确认 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-003 | 已确认 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | OQ-02 | 未执行 |
| REQ-004 | 设计基线 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-005 | 设计基线 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-006 | 设计基线 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | OQ-08 | 原型局部验证；产品未验收 |
| REQ-007 | 设计基线 | [采样与时间](03-sensor-acquisition.md) | TC-SCHEDULE | OQ-08 | 未执行 |
| REQ-008 | 已确认 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-009 | 已确认 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-010 | 已确认 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | OQ-01 | 未执行 |
| REQ-011 | 已确认 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-012 | 已确认目标／待验证 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | OQ-01 | 未执行 |
| REQ-013 | 设计基线 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-014 | 设计基线 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-015 | 设计基线 | [标签与校验](05-processing-pipeline.md) | TC-VALIDATE | 按专项设计 | 未执行 |
| REQ-016 | 设计基线 | [Raw 与 Ring Buffer](04-data-storage.md) | TC-BUFFER / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-017 | 已确认 | [Raw 与 Ring Buffer](04-data-storage.md) | TC-BUFFER / TC-STORAGE | OQ-10 | 未执行 |
| REQ-018 | 设计基线 | [Raw 与 Ring Buffer](04-data-storage.md) | TC-BUFFER / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-019 | 已确认 | [Raw 与 Ring Buffer](04-data-storage.md) | TC-BUFFER / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-020 | 已确认 | [Raw 与 Ring Buffer](04-data-storage.md) | TC-BUFFER / TC-STORAGE | OQ-07 | 未执行 |
| REQ-021 | 设计基线 | [EMA](05-processing-pipeline.md) | TC-EMA | OQ-06、OQ-08 | 未执行 |
| REQ-022 | 设计基线 | [EMA](05-processing-pipeline.md) | TC-EMA | 按专项设计 | 未执行 |
| REQ-023 | 已确认 | [EMA](05-processing-pipeline.md) | TC-EMA | 按专项设计 | 未执行 |
| REQ-024 | 设计基线 | [EMA](05-processing-pipeline.md) | TC-EMA | OQ-07 | 未执行 |
| REQ-025 | 设计基线 | [窗口聚合](05-processing-pipeline.md) | TC-AGG | OQ-06 | 未执行 |
| REQ-026 | 设计基线 | [窗口聚合](05-processing-pipeline.md) | TC-AGG | OQ-06 | 未执行 |
| REQ-027 | 设计基线 | [窗口聚合](05-processing-pipeline.md) | TC-AGG | OQ-06 | 未执行 |
| REQ-028 | 设计基线 | [窗口聚合](05-processing-pipeline.md) | TC-AGG | OQ-06 | 未执行 |
| REQ-029 | 设计基线 | [窗口聚合](05-processing-pipeline.md) | TC-AGG | OQ-06 | 未执行 |
| REQ-030 | 设计基线／需澄清 | [窗口聚合](05-processing-pipeline.md) | TC-AGG | OQ-06、OQ-07 | 未执行 |
| REQ-031 | 设计基线 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | OQ-07 | 未执行 |
| REQ-032 | 设计基线 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | OQ-07 | 未执行 |
| REQ-033 | 已确认 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | 按专项设计 | 未执行 |
| REQ-034 | 设计基线 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | OQ-06 | 未执行 |
| REQ-035 | 已确认 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | OQ-12 | 未执行 |
| REQ-036 | 设计基线 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | 按专项设计 | 未执行 |
| REQ-037 | 设计基线 | [分级保留与清理](04-data-storage.md) | TC-RETENTION | OQ-07 | 未执行 |
| REQ-038 | 已确认 | [会话生命周期](13-operations-distribution.md) | TC-LIFECYCLE | 按专项设计 | 未执行 |
| REQ-039 | 已确认 | [会话生命周期](13-operations-distribution.md) | TC-LIFECYCLE | 按专项设计 | 未执行 |
| REQ-040 | 已确认 | [会话生命周期](13-operations-distribution.md) | TC-LIFECYCLE | 按专项设计 | 未执行 |
| REQ-041 | 已确认 | [会话生命周期](13-operations-distribution.md) | TC-LIFECYCLE | 按专项设计 | 未执行 |
| REQ-042 | 已确认 | [会话生命周期](13-operations-distribution.md) | TC-LIFECYCLE | 按专项设计 | 未执行 |
| REQ-043 | 已确认目标／待验证 | [实时与历史展示](07-native-ui.md) | TC-UI | OQ-01 | 未执行 |
| REQ-044 | 已确认 | [实时与历史展示](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-045 | 已确认 | [实时与历史展示](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-046 | 已确认 | [实时与历史展示](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-047 | 设计基线／需澄清 | [实时与历史展示](07-native-ui.md) | TC-UI | OQ-04 | 未执行 |
| REQ-048 | 设计基线 | [实时与历史展示](07-native-ui.md) | TC-UI | OQ-12 | 未执行 |
| REQ-049 | 设计基线 | [实时与历史展示](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-050 | 设计基线 | [查询层级](07-native-ui.md) | TC-UI / TC-RETENTION | OQ-04 | 未执行 |
| REQ-051 | 设计基线 | [查询层级](07-native-ui.md) | TC-UI / TC-RETENTION | OQ-12 | 未执行 |
| REQ-052 | 设计基线 | [查询层级](07-native-ui.md) | TC-UI / TC-RETENTION | OQ-12 | 未执行 |
| REQ-053 | 设计基线 | [查询层级](07-native-ui.md) | TC-UI / TC-RETENTION | OQ-12 | 未执行 |
| REQ-054 | 已确认 | [采集重试](06-error-handling.md) | TC-ERROR / TC-SENSOR | OQ-09 | 未执行 |
| REQ-055 | 已确认 | [采集重试](06-error-handling.md) | TC-ERROR / TC-SENSOR | 按专项设计 | 未执行 |
| REQ-056 | 设计基线 | [采集重试](06-error-handling.md) | TC-ERROR / TC-SENSOR | 按专项设计 | 未执行 |
| REQ-057 | 设计基线 | [采集重试](06-error-handling.md) | TC-ERROR / TC-SENSOR | 按专项设计 | 未执行 |
| REQ-058 | 已确认 | [数据库重试](06-error-handling.md) | TC-ERROR / TC-STORAGE | OQ-10 | 未执行 |
| REQ-059 | 已确认 | [数据库重试](06-error-handling.md) | TC-ERROR / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-060 | 设计基线 | [数据库重试](06-error-handling.md) | TC-ERROR / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-061 | 设计基线 | [数据库重试](06-error-handling.md) | TC-ERROR / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-062 | 设计基线 | [数据库重试](06-error-handling.md) | TC-ERROR / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-063 | 设计基线 | [数据库重试](06-error-handling.md) | TC-ERROR / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-064 | 已确认 | [加工重试](06-error-handling.md) | TC-ERROR | OQ-06 | 未执行 |
| REQ-065 | 设计基线 | [加工重试](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-066 | 设计基线 | [加工重试](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-067 | 设计基线 | [加工重试](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-068 | 已确认 | [UI 读取重试](06-error-handling.md) | TC-ERROR / TC-UI | 按专项设计 | 未执行 |
| REQ-069 | 已确认 | [UI 读取重试](06-error-handling.md) | TC-ERROR / TC-UI | 按专项设计 | 未执行 |
| REQ-070 | 设计基线 | [UI 读取重试](06-error-handling.md) | TC-ERROR / TC-UI | OQ-12 | 未执行 |
| REQ-071 | 设计基线 | [UI 读取重试](06-error-handling.md) | TC-ERROR / TC-UI | 按专项设计 | 未执行 |
| REQ-072 | 设计基线／需澄清 | [致命故障](06-error-handling.md) | TC-ERROR | OQ-05 | 未执行 |
| REQ-073 | 设计基线／需澄清 | [致命故障](06-error-handling.md) | TC-ERROR | OQ-05 | 未执行 |
| REQ-074 | 已确认 | [致命故障](06-error-handling.md) | TC-ERROR | OQ-11 | 未执行 |
| REQ-075 | 已确认 | [致命故障](06-error-handling.md) | TC-ERROR | OQ-11 | 未执行 |
| REQ-076 | 已确认 | [致命故障](06-error-handling.md) | TC-ERROR | OQ-11 | 未执行 |
| REQ-077 | 已确认 | [致命故障](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-078 | 已确认 | [致命故障](06-error-handling.md) | TC-ERROR | OQ-11 | 未执行 |
| REQ-079 | 设计基线 | [错误报告与编码](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-080 | 设计基线 | [错误报告与编码](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-081 | 设计基线 | [错误报告与编码](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-082 | 设计基线 | [错误报告与编码](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-083 | 设计基线 | [错误报告与编码](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-084 | 设计基线 | [错误报告与编码](06-error-handling.md) | TC-ERROR | 按专项设计 | 未执行 |
| REQ-085 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-086 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 未执行 |
| REQ-087 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 未执行 |
| REQ-088 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-089 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-090 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-091 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 未执行 |
| REQ-092 | 设计基线 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-093 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-094 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-095 | 设计基线 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | OQ-15 | 未执行 |
| REQ-096 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 未执行 |
| REQ-097 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 未执行 |
| REQ-098 | 已确认 | [Git 与 GitHub](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 未执行 |
| REQ-099 | 设计基线 | [阶段测试](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-100 | 设计基线 | [阶段测试](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-101 | 设计基线 | [阶段测试](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-102 | 设计基线 | [阶段测试](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-103 | 设计基线 | [阶段测试](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-104 | 设计基线 | [阶段测试](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-105 | 已确认 | [编码前文档](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-106 | 已确认 | [编码前文档](12-development-plan.md) | TC-DOCS | 按专项设计 | 未执行 |
| REQ-107 | 已确认 | [补充范围与后续讨论](02-architecture.md) | TC-PLATFORM | 按专项设计 | 未执行 |
| REQ-108 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-109 | 已确认 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-PLATFORM | OQ-03 | 原型局部验证；产品未验收 |
| REQ-110 | 已确认目标／待验证 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-PLATFORM | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-111 | 设计基线 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-RELEASE | 按专项设计 | 未执行 |
| REQ-112 | 已确认 | [补充范围与后续讨论](02-architecture.md) | TC-PLATFORM | 按专项设计 | 未执行 |
| REQ-113 | 已确认目标／待验证 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-SENSOR | OQ-01 | 未执行 |
| REQ-114 | 已确认目标／待验证 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-SENSOR | OQ-01、OQ-05 | 未执行 |
| REQ-115 | 已确认目标／待验证 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-SENSOR | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-116 | 已确认目标／待验证 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-SENSOR | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-117 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | OQ-12 | 未执行 |
| REQ-118 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | OQ-05、OQ-12 | 未执行 |
| REQ-119 | 已确认方向／待设计 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-120 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | OQ-12 | 未执行 |
| REQ-121 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-122 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-123 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-124 | 已确认 | [补充范围与后续讨论](04-data-storage.md) | TC-STORAGE | 按专项设计 | 未执行 |
| REQ-125 | 已确认 | [补充范围与后续讨论](07-native-ui.md) | TC-UI | 按专项设计 | 未执行 |
| REQ-126 | 已确认 | [补充范围与后续讨论](13-operations-distribution.md) | TC-RELEASE | 按专项设计 | 未执行 |
| REQ-127 | 已确认 | [补充范围与后续讨论](13-operations-distribution.md) | TC-RELEASE | OQ-16 | 未执行 |
| REQ-128 | 已确认 | [补充范围与后续讨论](11-git-github-workflow.md) | TC-WORKFLOW | 按专项设计 | 原型局部验证；产品未验收 |
| REQ-129 | 设计基线 | [补充范围与后续讨论](04-data-storage.md) | TC-SCHEDULE / TC-STORAGE | 按专项设计 | 未执行 |
| REQ-130 | 推荐方案 | [补充范围与后续讨论](07-native-ui.md) | TC-UI / TC-LIFECYCLE | OQ-08 | 未执行 |
| REQ-131 | 推荐方案 | [补充范围与后续讨论](05-processing-pipeline.md) | TC-TREND | OQ-06、OQ-08 | 未执行 |
| REQ-132 | 推荐方案 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-SENSOR | OQ-05 | 原型局部验证；产品未验收 |
| REQ-133 | 推荐修正 | [补充范围与后续讨论](05-processing-pipeline.md) | TC-AGG | OQ-06 | 未执行 |
| REQ-134 | 推荐方案 | [补充范围与后续讨论](03-sensor-acquisition.md) | TC-SENSOR / TC-SCHEDULE | 按专项设计 | 原型局部验证；产品未验收 |

## 维护规则

需求正文改变时同步更新设计、用例与决策记录。验证报告必须包含机型、系统 build、应用版本、配置和证据路径，方能将相应测试标为通过。文档已完成链接检查不等于产品测试通过。


## 首轮证据索引

统一证据入口：[V0 最小验证报告](validation/2026-09-15-m4-air/validation-report.md)。TC-SENSOR／TC-SCHEDULE 为单机和短时局部证据；TC-WORKFLOW 包含功能分支、Issue、原型CI与PR，但强制门禁未完整配置，未执行merge。REQ-092只取得原型纯逻辑覆盖率，产品采集边界未验收。Package／逐核、UI、数据链和长期测试仍未执行。

## 2026-09-17 方案增量追踪

以下是[19](19-reference-informed-design.md)的提案和推荐细化，未覆盖上表状态。V2为未来测试计划，未执行。

| 变更 | 关联REQ | 设计／提案 | 计划验证 |
|---|---|---|---|
| CPU主指标定义 | 010/043/044/113 | RC-01；03/05/07/19 | V2-01/05；TC-SENSOR/EMA/UI |
| 逐核改热区列表 | 009/010/012/114/122/132 | RC-02；03/07/19 | V2-01/04；TC-SENSOR/VALIDATE/UI |
| 附件能力隔离 | 054～057/072～078/115/116 | RC-03；06/19 | V2-02/04；TC-ERROR |
| 按矩阵声明支持 | 109～111 | RC-04；03/19 | V2-06；TC-PLATFORM/RELEASE |
| 轮询／缓存／串行调度 | 001～007/054/055/129/134 | RC-05；02/03/08/19 | V2-03/04；TC-SCHEDULE/LIFECYCLE |
| 身份、派生与分段 | 008～015/021/025～029/130～133 | 04/05/08/19 | V2-04/05；TC-EMA/AGG/TREND |
| 有界且幂等交付 | 017/023/058～060/100 | 04/19 | V2-05；TC-STORAGE/ERROR |
| 来源与状态核对 | 105/106/128 | 15/18/19；研究清单 | TC-DOCS：链接、134条REQ、249条来源与哈希核对 |
