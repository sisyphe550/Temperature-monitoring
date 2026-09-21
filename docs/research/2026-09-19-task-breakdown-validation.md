# 2026-09-19任务拆分验证

## 范围

- 基线分支：`feature/v0-sensor-validation`。
- 基线提交：`4eff38901dc9d5d1fe8501998868ae726ec79fab`。
- 本次只验证实施文档与机器可读任务图，不代表生产App、UI、目标机或发布验收完成。
- 历史研究和2026-09-18验证记录未被改写。

## 结构结果

| 项目 | 结果 |
|---|---|
| 里程碑 | W00～W11，共12个 |
| 执行任务 | T00.1～T11.3，共50个，ID唯一 |
| 分布 | W00 5；W01 4；W02 6；W03 4；W04 5；W05 5；W06 4；W07 5；W08 3；W09 4；W10 2；W11 3 |
| 依赖 | 唯一根任务T00.1；无未知、自依赖、逆序或环；全部任务均为T11.3前置 |
| 表格契约 | 每行均含任务、依赖、文件、设计产出、失败测试/验证、交接六列 |
| Git引导 | W00明确按PR #4→可信门禁PR→规则证据PR执行，避免未部署的required check锁死仓库 |
| 后续并行 | W02/W03/W04仅在W01合入后分开；W05显式汇合硬件、存储和算法 |

任务状态保持未勾选。拆分和验证通过只证明计划可解析，不证明任务已经实施。

## 执行结果

```text
python3 -m py_compile scripts/validate-handoff.py
结果：通过

python3 scripts/validate-handoff.py
结果：通过；134项需求=132现行+2退役；12个工作包；50个执行任务；19个测试组

临时把T00.1依赖改成T11.3后调用validate_task_graph()
结果：按预期拒绝；报告非唯一根、逆序依赖和依赖环；临时文件未写入仓库

CLANG_MODULE_CACHE_PATH=/tmp/temperature-monitor-swift-module-cache \
SWIFT_MODULECACHE_PATH=/tmp/temperature-monitor-swift-module-cache \
swiftc -swift-version 6 -typecheck docs/contracts/api-v1.swift
结果：通过

swift test --package-path prototypes/sensor-probe --enable-code-coverage
结果：通过；ProbeCoreTests 8/8

python3 scripts/check-probe-coverage.py
结果：通过；ProbeCore 55/55行，100.00%

git diff --check
结果：通过
```

第一次直接运行`swiftc`时，默认`~/.cache/clang/ModuleCache`在当前沙箱中不可写；改用可写的临时模块缓存后同一契约通过。SwiftPM首次在受限沙箱内运行时也因其内部`sandbox-exec`被拒绝；按项目允许的测试命令在沙箱外重跑后8项测试通过。这两次失败属于执行环境权限，不是契约或原型回归。

## 实施入口

- W级设计、完整接口和验收：[22](../22-agent-implementation-plan.md)。
- T级执行顺序、文件和交接：[23](../23-execution-task-breakdown.md)。
- 机器可读依赖图：[tasks-v1.json](../contracts/tasks-v1.json)。
- Git引导和合并流程：[11](../11-git-github-workflow.md)。
