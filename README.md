# Temperature Monitoring

Apple Silicon MacBook Air本机课程演示项目。实施契约v1族，**contract revision 3**；当前目标为用户本机可运行的ad-hoc Release App。正式App核心观察与课程五项门禁通过；完整Core355/57、覆盖88.93%。独立审查、同head CI和合并按PR实际结果另核对。

## 当前范围与接手入口

先读[课程交付范围](docs/course-delivery-scope.md)与[Agent交接入口](docs/00-agent-handoff.md)，再按[工作包](docs/22-agent-implementation-plan.md)、[50项任务](docs/23-execution-task-breakdown.md)和[Git流程](docs/11-git-github-workflow.md)完成收尾。无需从历史聊天重新推导范围。

- CPU固定12个M4温度来源，同批完整Raw max→EMA，单位°C；不承诺逐物理核心、物理Package或全芯片绝对热点。
- SSD/Battery保留适配、来源选择与明确Unavailable状态；单项不支持或故障不停止CPU。
- SwiftUI/AppKit原生界面，前端参考MacMonitor和Stats；CPU五档请求50/100/200/500/1000ms，默认200ms。
- 实时走内存；Raw/EMA批量入SQLite，分层历史最长72小时、仅本会话。关窗继续采集，重开复用会话，正常退出清理监控库。
- 普通用户自有SensorWorker隔离硬件调用；不引入root、外部采集CLI、SMC写入、告警、自启动或Web后端。

最新用户授权将严格132项资格、五档各10分钟、物理睡眠、72/73小时耐久、公证/公开发行/跨机认证和精确skipped/p95/p99/首帧/显示测量收缩为可选扩展。**72小时历史功能、核心覆盖≥80%、必要异常回归、真实缺陷blocking与Git门禁保留。**五个课程criterion及core/auxiliary/optional/retired分类见[课程政策](docs/contracts/course-delivery-v1.json)；旧逐REQ裁决仍为100accepted/31pending/1waived/2retired，不批量改为PASS。

SensorTransport的DiscoveredCatalog底层事实必须经Registry成为QualifiedSourceCatalog来源；ReadingOutcome成功/失败互斥，失败不补0或旧值；PersistenceLease取得匹配ProcessingReceipt后交换状态；界面只绑定PresentationState。实际复制/修改的上游代码以[third-party-v1.json](docs/contracts/third-party-v1.json)和TC-UPSTREAM-BOUNDARY为准。

## 本机启动

```sh
bash scripts/build-app.sh
bash scripts/launch-app.sh
```

构建脚本当前输出`build/TemperatureMonitor.app`，嵌入同次构建的SensorWorker并ad-hoc签名；可运行交付App与二进制SHA见[课程报告](docs/validation/course-delivery/2026-10-03-5984b9e/README.md)。无需公证凭证即可本机运行，不声称全部Air或其他OS支持。

“应用读取时间”是收到有效值的观测时间；“测量更新时间未知”表示接口未给出可验证硬件测量时间戳，不等于没读到温度。缓存、过期或失败由互斥状态另行表达。

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
| [21 契约](docs/21-implementation-contracts.md)／[22 工作包](docs/22-agent-implementation-plan.md)／[23 执行任务](docs/23-execution-task-breakdown.md) | contract revision 3精确配置、Swift/SQL、第三方边界、W级里程碑与50个可审查任务 |
| [课程交付范围](docs/course-delivery-scope.md) | 最新授权、五criterion、最小收尾、扩展验收边界 |

## 验证入口与历史证据

```sh
python3 scripts/validate-handoff.py
python3 scripts/bind-acceptance-evidence.py
python3 scripts/validate-handoff.py --product-acceptance
```

普通文档检查只验证契约/链接/绑定。课程门槛按五criterion判定；`--strict-product-acceptance`保留旧全132项扩展资格，pending存在时拒绝。最终审查、同head五CI、零真实blocking及merge commit另按11回读，不把CI自身未来状态写成文档门禁的先决条件。

[7124正式App与软件证据](docs/validation/product-software/W11/2026-10-03-7124dc1/README.md)、[f0测试同步证据](docs/validation/product-software/W11/2026-10-03-f0a7dde/README.md)分别绑定原源码/产物；[c354归档](docs/validation/product-software/W11/2026-10-03-c354b03/README.md)保留失败长测、duration观察与未测性能。它们不能预先证明本轮最终短测或合并成功。旧[原型报告](docs/validation/2026-09-15-m4-air/validation-report.md)、[接口审计](docs/research/2026-09-17-handoff-interface-audit.md)与研究记录不回写；新结果另按日期/源码提交归档。

## 本轮测试与交付记录

当前正式App核心观察、完整Core与可运行路径见[课程测试报告](docs/validation/course-delivery/2026-10-03-5984b9e/README.md)。App/worker二进制与已验7124完全一致；自动AX失败及原生补验分开记录。独立审查、CI与合并结果仍须实际回读，不由本段预先宣称。
