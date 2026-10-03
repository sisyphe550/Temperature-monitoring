# Temperature Monitoring

Apple Silicon MacBook Air本地原生温度监控项目。**2026-10-02实施契约v1族，contract revision 3**。生产Core、SensorWorker、App与Xcode工程已存在；本轮17项产品审查缺陷已修复并完成本机短时验证，修复[PR #44](https://github.com/sisyphe550/Temperature-monitoring/pull/44)已于2026-10-03以merge commit `403d44b`合入main并保留功能分支。

## 接手开发

从[Agent交接入口](docs/00-agent-handoff.md)开始，以[W00～W11工作包](docs/22-agent-implementation-plan.md)作为里程碑边界，按[50个执行任务](docs/23-execution-task-breakdown.md)核对设计和交接边界；当前工作按[产品审查修复计划](docs/superpowers/plans/2026-10-02-product-audit-fixes.md)执行。无需依赖聊天记录或临时克隆目录。

- CPU：固定12个M4温度来源的最高值，EMA展示；不承诺逐物理核心、物理Package或全芯片绝对热点。
- SSD/Battery：有具体接口与来源选择，不支持或单项失败时显示不可用，CPU继续。
- 原生SwiftUI/AppKit，前端参考MacMonitor和Stats；五档CPU请求，默认200ms。
- 实时内存加工与展示，Raw/EMA仍批量入SQLite，分层历史最长72小时、仅当前会话。
- 自有普通用户采集worker隔离同步接口；不引入root、外部监控CLI、告警、自启动或Web后端。

修订3的实现边界固定为：SensorTransport只交付`DiscoveredCatalog`底层事实，Registry生成`QualifiedSourceCatalog`后才允许采样；`ReadingOutcome`互斥表达成功或失败；`PersistenceLease`经SessionPersistence提交并取得receipt后才交换算法状态；所有界面只绑定`PresentationState`。实际复制/修改的上游代码由[third-party-v1.json](docs/contracts/third-party-v1.json)登记，`TC-UPSTREAM-BOUNDARY`验证旧值回退、名称物理语义、补0°C、root/helper/写SMC、Release fixture及许可缺失均被拒绝。

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

## 验证入口

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-contract -typecheck docs/contracts/api-v1.swift
```

[契约修订2迁移记录](docs/research/2026-09-21-contract-documentation-migration.md)、[旧实测报告](docs/validation/2026-09-15-m4-air/validation-report.md)、[原型复现](prototypes/sensor-probe/README.md)、[硬件接口审计](docs/research/2026-09-17-handoff-interface-audit.md)供复核。E1本机读数、E2上游路线、D设计契约分开标注；有方案不等于正式App已测通过。

本机已具备Xcode 26.3和Mac16,13目标机；[2026-10-02产品审查](docs/validation/product-review/2026-10-02-48cd967d/report.md)确认CPU12正式读取链路可运行，同时发现历史、故障恢复、持久化和退出缺陷。本轮仅本机使用，用户豁免72/73小时长测、公证、公开发行与跨机型认证；分层历史最长72小时的功能保留。[a97fd5a修复验证](docs/validation/product-fixes/2026-10-02-a97fd5a/report.md)已完成：核心337项通过、当次行覆盖88.61%、fixture UI16项执行通过、正式Release实机1项通过；五档各8秒、CPU12/max/EMA、历史与正常退出清理有新证据。菜单栏隐藏时已提供主窗口/reopen/退出入口；物理右键菜单、真实系统睡眠和五档各10分钟未在最终构建验收，不声明全部132项完成。文档基线已由[PR #4](https://github.com/sisyphe550/Temperature-monitoring/pull/4) 合入 main；后续功能从最新 main 创建 `feature/<功能>`。

追加CI测试同步已修复并记录[651b29e报告](docs/validation/product-fixes/2026-10-03-651b29e/report.md)：最新337项回归通过、覆盖88.71%，生产代码不变。

## 2026-10-03 当前验收入口

按[W11刷新计划](docs/superpowers/plans/2026-10-03-w11-acceptance-refresh.md)继续[PR #26](https://github.com/sisyphe550/Temperature-monitoring/pull/26)。当前该PR为Draft：新实机睡眠发现#46/#47，需要修复、重新构建及复测。旧W11报告保留为历史，不能作为当前完整验收结论。

[逐REQ证据目录](docs/contracts/acceptance-evidence-catalog-v1.json)内容格式version2：每份证据有独立source_commit、SHA256、环境和适用范围。403/a97/651登记保留为历史基线；当前逐REQ裁决以catalog中的有效覆盖、未完成项及用户授权范围为准。新修复须用新证据更新，不由TC组整体结果推导，不能沿用旧快照的通过数量作为当前状态。

```sh
python3 scripts/bind-acceptance-evidence.py            # 只读核对
python3 scripts/validate-handoff.py                   # 文档/绑定一致性
python3 scripts/validate-handoff.py --product-acceptance # 全验收；存在pending时必须失败
```

“应用读取时间”是软件收到有效数据的观测时间；“测量更新时间未知”表示SMC/NVMe/IOPS接口未提供可验证的硬件测量时间戳，不等于未读到温度。失败、缓存或超时由其它互斥展示状态表达。

## 2026-10-03 c354独立duration与最新验收范围

c354五档清醒时长条件已分别observed：50/100/200/500ms原phase各约601秒；1000ms在同一App/worker/Session连续区间经独立clock、Cua与末端SQL补证641.637秒。原XCTest因最后一档AX控件缺失仍为FAILED，不能改suite通过。精确scheduler skipped、读批p95/p99及首帧/屏幕显示p95仍not_measured，性能门槛不变。用户2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理睡眠/人工唤醒验收仅标skipped-by-user；已经触发的两次attempt观察保留partial，生命周期功能和软件回归继续保留。 [不可变归档](docs/validation/product-software/W11/2026-10-03-c354b03/README.md)保存原失败suite、四档phase、末档同Session独立补证、Raw/SQL overlap、资源与正常退出；[最新user-scope](docs/validation/product-software/W11/2026-10-03-c354b03/user-scope.json)保存用户原话。

最新生产源码`f9e850cb6986ca9b22980849c503080c8b5d96ee`已集成Issue [#50](https://github.com/sisyphe550/Temperature-monitoring/issues/50)两行父窗口索引查找修复及TTL回归；完整349测试/55组通过、核心覆盖89.01%，正式Release构建/签名/上游边界通过。新App短测重试1项149.485秒PASS，首次runner启动失败独立保留；[最终归档](docs/validation/product-software/W11/2026-10-03-f9e850c/README.md)保存153份源码匹配、App/worker身份、原日志hash和14份自有UI附件。六项明确软件TTL缺口已局部补齐：当前100项本机接受、31项待验收、1项豁免、2项退役。此裁决不继承c354长测为新产物完整资格；W11、精确性能、物理菜单/其他未测要求及blocking/CI仍按实际证据处理。
