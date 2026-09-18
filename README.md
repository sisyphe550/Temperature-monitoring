# Temperature Monitoring

Apple Silicon MacBook Air本地原生温度监控项目。**2026-09-18交接设计基线v1**；已有M4 Air只读原型证据，生产App尚未实现。

## 接手开发

从[Agent交接入口](docs/00-agent-handoff.md)开始，按[实施计划](docs/22-agent-implementation-plan.md)执行。无需依赖聊天记录或临时克隆目录。

- CPU：固定12个M4温度来源的最高值，EMA展示；不承诺逐物理核心、物理Package或全芯片绝对热点。
- SSD/Battery：有具体接口与来源选择，不支持或单项失败时显示不可用，CPU继续。
- 原生SwiftUI/AppKit，前端参考MacMonitor和Stats；五档CPU请求，默认200ms。
- 实时内存加工与展示，Raw/EMA仍批量入SQLite，分层历史最长72小时、仅当前会话。
- 自有普通用户采集worker隔离同步接口；不引入root、外部监控CLI、告警、自启动或Web后端。

## 权威文档

| 入口 | 内容 |
|---|---|
| [CONTEXT](CONTEXT.md)／[AGENTS](AGENTS.md) | 当前边界与执行纪律 |
| [00 Agent交接](docs/00-agent-handoff.md) | 阅读顺序、当前状态、启动和完成条件 |
| [01 需求](docs/01-requirements.md)／[17 追踪](docs/17-traceability.md) | 134编号、132现行、2退役；逐项任务与验收 |
| [02 架构](docs/02-architecture.md)／[03 接口](docs/03-sensor-acquisition.md) | 数据路径、具体硬件实现与证据 |
| [04 存储](docs/04-data-storage.md)／[05 算法](docs/05-processing-pipeline.md) | DDL、TTL、EMA、聚合、趋势与幂等 |
| [06 故障](docs/06-error-handling.md)／[07 界面](docs/07-native-ui.md) | 重试、退出、缓存、布局和交互 |
| [08 构件](docs/08-component-design.md)／[09 工具链](docs/09-technology-selection.md) | 文件结构、Swift接口、进程协议与依赖 |
| [10 测试](docs/10-test-strategy.md)／[11 Git](docs/11-git-github-workflow.md) | 验收向量、覆盖率、CI、Issue和merge commit |
| [12 阶段](docs/12-development-plan.md)／[13 分发](docs/13-operations-distribution.md) | 生命周期、日志、打包、公证和外部凭证 |
| [14 实测](docs/14-feasibility-validation.md)／[15 决策](docs/15-decisions-and-corrections.md) | 已存证据、变更原因与后续验证 |
| [16 决策与执行依赖](docs/16-open-questions.md)／[18 来源](docs/18-sources.md) | 原OQ处理、官方及讨论出处 |
| [19 开源比较](docs/19-reference-informed-design.md)／[20 可行性](docs/20-feasibility-and-reuse.md) | 全部参考项目、复用与自有设计边界 |
| [21 契约](docs/21-implementation-contracts.md)／[22 执行计划](docs/22-agent-implementation-plan.md) | 精确配置、Swift/SQL、逐任务实现与测试 |

## 验证入口

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -typecheck docs/contracts/api-v1.swift
```

[旧实测报告](docs/validation/2026-09-15-m4-air/validation-report.md)、[原型复现](prototypes/sensor-probe/README.md)、[硬件接口审计](docs/research/2026-09-17-handoff-interface-audit.md)供复核。E1本机读数、E2上游路线、D设计契约分开标注；有方案不等于正式App已测通过。

设计已给出可执行选择；剩余工作是实现与验证。完整Xcode、正式签名凭证、仓库管理员权限及目标实机属于明确执行依赖。当前基线在[Draft PR #4](https://github.com/sisyphe550/Temperature-monitoring/pull/4)，未合并前不要从旧main丢失文档开始开发。
