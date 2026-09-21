# W00 T00.4 门禁实现

实现提交：`79cfacd5d11c5a125117350365db85d7821bcf16`  
命令时间：2026-09-21。本文件记录实现与测试，不宣称 GitHub required 检查已启用。

## 交付

| 文件 | 作用 |
|---|---|
| `.github/scripts/blocking-issues.mjs` | 分页读取 Issue/PR，过滤 PR 对象，按最新 head 写 `blocking-issues` check |
| `.github/scripts/blocking-issues.test.mjs` | 12 项 Node 测试 |
| `.github/workflows/blocking-issues.yml` | `pull_request_target` + Issue 事件；只 checkout 默认分支 |
| `scripts/configure-repository.sh` | 幂等配置 merge 策略、标签、ruleset；`--require-blocking-issues` 默认关闭 |

## 测试

```text
node --test .github/scripts/blocking-issues.test.mjs
tests 12, fail 0
```

覆盖：0 Issue 成功、普通 Issue 成功、blocking 失败、第二页 blocking 失败、关闭后成功、重开失败、新 push 只写最新 head、API 错误写 failure 且不按零 Issue 放行、多 PR head 同步失败。

本提交**未**执行 `configure-repository.sh`，**未**把 `blocking-issues` 设为 required。T00.5 在该 workflow 进入默认分支并成功写到真实 PR head 后再启用。

## 与现有检查

本 PR 仍只依赖已存在的 `handoff-docs` 与 `probe-tests`。`blocking-issues.yml` 在合入 main 之前不会作为受信任默认分支逻辑运行。
