# W00 报告

记录时间：2026-09-21。
默认分支 merge SHA（PR #5）：`683f5d72279fcc8efe8b9eb076beaf4628165346`（parents：`1d303a44e46d00d9e32163a305ab8baba5ba779d`、`d53ff7789cb36d9d02652b4c5e1e2187f3bdcfca`）。
证据 PR：[#6](https://github.com/sisyphe550/Temperature-monitoring/pull/6)。

## T00.1–T00.4

| 任务 | 结果 |
|---|---|
| T00.1 | 基线 `docs/validation/product-software/W00/1d303a44e46d00d9e32163a305ab8baba5ba779d/baseline.md` |
| T00.2 | `handoff-docs`/`probe-tests` 唯一检查名；损坏 fixture 失败 |
| T00.3 | PR #4 已 merge commit 合入；远端 `feature/v0-sensor-validation` 保留 |
| T00.4 | PR #5 merge commit；远端 `feature/w00-repository-gates` 保留；12 项 Node 测试通过 |

## T00.5 触发与回读

1. 从 main `683f5d7` 创建本证据分支；`pull_request_target` 使用默认分支 workflow。
2. 本 PR 首个 head `365de63575f9061bea93e0493be3a37ea83b4765` 上 `blocking-issues` conclusion=success（run `35573152369`），同时 `handoff-docs`/`probe-tests` 通过。open blocking Issue 为空。
3. 随后执行 `bash scripts/configure-repository.sh --require-blocking-issues`。
4. 仓库回读：`allow_merge_commit=true`，`allow_squash_merge=false`，`allow_rebase_merge=false`，`delete_branch_on_merge=false`。
5. ruleset `main-protection` id `23754438`：`enforcement=active`，`bypass_actors=[]`，`current_user_can_bypass=never`，include `refs/heads/main`。
6. required contexts：`handoff-docs`、`probe-tests`、`blocking-issues`；`strict_required_status_checks_policy=true`。
7. `allowed_merge_methods=["merge"]`。未要求尚未存在的 `core-tests`/`app-build`。
8. 标签 `bug`/`blocking`/`hardware` 存在。

## 未完成（不阻塞 W00 退出）

- 独立审查仍应由非实现者补记录；GitHub 审批人数为 0。
- 生产 App / Xcode / 实机 / 公证不在 W00 范围。
- `core-tests` 与 `app-build` 在对应工作包首次成功运行后再加入 required。

## W00 退出

main 可从 PR #4/#5 取得完整规范与门禁实现；规则与 API 回读一致；无未解决 blocking Issue。W01 从本证据 PR 合入后的最新 main 创建 `feature/w01-core-contracts`。
