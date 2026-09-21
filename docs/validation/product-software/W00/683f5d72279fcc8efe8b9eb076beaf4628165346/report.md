# W00 T00.5 规则证据（进行中）

默认分支 merge：`683f5d72279fcc8efe8b9eb076beaf4628165346`（PR #5，两个 parent）。  
远端 `feature/w00-repository-gates` 仍存在。本文件在 ruleset 回读完成后替换为最终 `report.md`。

## 已确认

- PR #4 / PR #5 均为 merge commit。
- `blocking-issues.yml` 已在 main；本证据 PR 用于从默认分支触发该检查。
- 在检查写入本 PR 最新 head 之前，不执行 `--require-blocking-issues`。
