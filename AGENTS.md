# 项目Agent执行规则

## 沟通

1. 禁止寒暄、奉承、比喻和无实质内容；用户观点有误时用证据直接说明。
2. 保持客观、理性、简洁；区分实测、上游依据、设计选择和推断。
3. 分析按具体条件和实践证据处理，不把单机结论外推全部硬件。

## 开发入口

先读[docs/00-agent-handoff.md](docs/00-agent-handoff.md)、[需求](docs/01-requirements.md)、[契约](docs/21-implementation-contracts.md)、[工作包计划](docs/22-agent-implementation-plan.md)、[细粒度任务](docs/23-execution-task-breakdown.md)和[Git流程](docs/11-git-github-workflow.md)。这些文件包含当前有效方案，无需依赖聊天记录。

- 仅实现现行需求；012/114退役，禁止恢复逐物理核心温度/core_id或物理Package保证。
- 实时内存EMA、Raw/EMA入SQLite、历史分层、会话清理按唯一契约实施。
- CPU12成员、单项可选故障、来源身份、单位、缺口与幂等不能被静默简化。
- 默认值、profile、类型、schema见docs/contracts；变更它们同时更新需求、设计、追踪、测试及版本。
- 真实硬件证据与模拟数据分开；不得将CI/源码推断当作正式App实机通过。
- 历史validation/research记录不可回写状态；新验证新增按日期/提交命名的证据。
- 复用实质开源代码必须保留对应版本许可和版权；缺完整许可的项目只参考方法。

## Git与验收

当前基线在PR4的feature/v0-sensor-validation。按W00先完成门禁并由维护者合入，再从最新main建feature/<功能>。不可reset或覆盖用户改动。缺陷建GitHub Issue，blocking未解决不得合并/跨阶段；CI和独立审查通过才交维护者合并。使用merge commit，保留开发分支。

每次修改运行适用检查；文档入口`python3 scripts/validate-handoff.py`。产品核心覆盖≥80%且必须含异常路径；UI、硬件与72小时验收不能用原型或短时模拟替代。没有Xcode/凭证/目标机时记录具体外部依赖，继续独立可做工作，不伪造完成。
