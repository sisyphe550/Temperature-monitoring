# Temperature Monitoring

Apple Silicon MacBook Air 本地原生温度监控项目。本文档集整理截至 **2026-09-17** 的有效讨论、首轮实测与开源方案复核，用于后续需求评审、开发和验收。

当前阶段：**已开展 M4 Air 最小传感器验证；生产应用尚未编码，完整 V0 尚未验收。** 本目录名称及其上级 `Go` 目录不表示项目已选择 Go 语言。

## 当前范围

- 仅面向 Apple Silicon MacBook Air，不包括 Intel MacBook Air、MacBook Pro、台式 Mac。
- 本地原生应用；不采用 Web 前端、Docker 或远端业务服务器。
- 不上架 Mac App Store；独立分发。
- 目标指标：CPU主指标、可验证的CPU温度来源／热区、SSD、Battery；已删除逐物理核心温度要求。主指标的Package／派生含义仍待决定。
- CPU 五档采样设置：50 / 100 / 200 / 500 / 1000 ms，默认 200 ms。
- SQLite＋Ring Buffer＋EMA＋分级时间聚合；监控历史最长 72 小时，限本次应用运行会话。
- 删除高温告警和登录后自动启动功能。
- 推荐技术方案：Swift 为主，必要时增加少量 C／Objective-C；SwiftUI＋AppKit；模块化单体。推荐不等于已实施。

## 文档状态

| 标记 | 含义 | 如何使用 |
|---|---|---|
| 已确认 | 用户明确提出或接受的业务要求 | 不因实现方便而自行更改 |
| 设计基线 | 在用户授权细化范围内形成的工作方案 | 用于后续设计；仍需验证其可实现性 |
| 推荐方案 | 助手提出、尚未明确冻结的技术选择 | 不能写成用户已批准或已经实现 |
| 待验证／待决策 | 存在能力、语义或验收缺口 | 关联问题编号；不伪造默认结论 |
| 已替代／已纠正 | 曾讨论但不再作为当前依据 | 仅保留变更原因与来源 |

“已确认需求”与“已验证能力”是两个维度。当前已删除逐物理核心温度要求；CPU主指标和电池来源仍需语义验证。

## 阅读导航

| 文档 | 内容 |
|---|---|
| [项目上下文](CONTEXT.md) | 背景、边界、术语、讨论解释规则 |
| [01 需求规格](docs/01-requirements.md) | 带 ID、状态和来源的中文 EARS 规格 |
| [02 总体架构](docs/02-architecture.md) | 模块划分、数据流、并发、隔离边界 |
| [03 传感器采集](docs/03-sensor-acquisition.md) | API 路线、权限、标识、采样语义、兼容性 |
| [04 数据模型与存储](docs/04-data-storage.md) | SQLite、Ring Buffer、保留期、空间控制 |
| [05 数据加工](docs/05-processing-pipeline.md) | 校验、EMA、Raw 峰值、聚合、趋势 |
| [06 故障与错误码](docs/06-error-handling.md) | 重试、错误分类、退出流程、错误码表 |
| [07 原生界面](docs/07-native-ui.md) | 菜单栏、弹出面板、主窗口、数据来源 |
| [08 构件详细设计草案](docs/08-component-design.md) | 构件职责、输入输出、状态与依赖 |
| [09 技术选型](docs/09-technology-selection.md) | Swift、桥接、UI、存储与工具选择 |
| [10 测试策略](docs/10-test-strategy.md) | 单元、白盒、黑盒、实机、长期测试 |
| [11 Git 与 GitHub 流程](docs/11-git-github-workflow.md) | 分支、Issue、测试门禁、合并节点 |
| [12 开发阶段计划](docs/12-development-plan.md) | 验证、设计、实现、集成、发布阶段 |
| [13 运维与分发](docs/13-operations-distribution.md) | 日志、诊断、清理、签名、公证 |
| [14 初步验证方案](docs/14-feasibility-validation.md) | 首个 M4 Air 采集原型如何验证与交付证据 |
| [15 决策与纠正记录](docs/15-decisions-and-corrections.md) | 有效决策、历史替代、事实纠错 |
| [16 待决策与风险](docs/16-open-questions.md) | 阻塞事项、解决方法、影响范围 |
| [17 需求追踪矩阵](docs/17-traceability.md) | 需求→设计→测试；覆盖不等于通过 |
| [18 来源与证据](docs/18-sources.md) | 对话、附件、官方资料、开源实现 |
| [19 开源复核与方案优化](docs/19-reference-informed-design.md) | 7 项参考、复用边界、需求修订提案、采集细化与 V0.2 计划 |

建议阅读顺序：项目上下文 → 需求规格 → 待决策与风险 → 初步验证方案 → 架构与专项设计。

## 最小验证入口

- [验证报告](docs/validation/2026-09-15-m4-air/validation-report.md)
- [兼容矩阵](docs/validation/2026-09-15-m4-air/compatibility-matrix.md)
- [只读原型与复现命令](prototypes/sensor-probe/README.md)

## 当前推荐方案

新增 [开源复核方案](docs/19-reference-informed-design.md) 与 [M4 全部 249 个已记录来源](docs/research/2026-09-17-m4-source-candidates.md)。采集方案细化为启动发现、版本化注册表、元数据缓存及有界轮询；真实来源与派生指标分开，生产构件尚未实现。C09已删除逐物理核心温度及关联核心标识要求，RC-02已落实，不再预设后续扩展承诺。RC-01主指标定义、RC-03附件可选化、RC-04首发范围仍待决定。前端按[07](docs/07-native-ui.md)复用MacMonitor分组面板、Stats来源列表和SwiftTempBar数字展示经验。

## 使用边界

文档归档已推进到独立采集原型和单机证据阶段；原型不属于生产应用。CPU主指标语义、完整生命周期、数据链、发布配置和长期稳定性仍未验证；逐核映射已不属于当前验收门槛。具体支持的芯片代际、机型尺寸和 macOS 版本由实机证据逐步建立。

后续变更同时更新相关专项文档、决策记录、追踪矩阵与测试。原始附件中的相互冲突内容，不因被引用而重新生效。
