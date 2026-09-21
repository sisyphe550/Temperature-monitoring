# W00 T00.1 实施基线

记录时间：2026-09-21T06:55:00+08:00（本机）。  
被记录源码 SHA：`1d303a44e46d00d9e32163a305ab8baba5ba779d`。  
本文件描述该 SHA 的仓库与 GitHub 状态，不修改 2026-09-15 原型证据。

## 分支与提交

| 项 | 实际值 |
|---|---|
| 工作树 | 干净；`main` 已 fast-forward 到 `origin/main` |
| 当前基线 HEAD | `1d303a44e46d00d9e32163a305ab8baba5ba779d` |
| 提交说明 | `Merge pull request #4 from sisyphe550/feature/v0-sensor-validation` |
| parents | `3fa99aa491c4ea270e60fbda75c3872f9336e07a`（旧 main）与 `c529d8deacd0c5140465c12a069f96c0f516f534`（PR #4 head） |
| 远端功能分支 | `origin/feature/v0-sensor-validation` 仍存在 |
| 后续实施分支 | 自该 main 创建 `feature/w00-repository-gates` |

## PR #4

`gh pr view 4`：

- state：`MERGED`（2026-09-21T06:30:03Z）
- headRefOid：`c529d8deacd0c5140465c12a069f96c0f516f534`
- mergeCommit：`1d303a44e46d00d9e32163a305ab8baba5ba779d`
- 合入前检查：`handoff-docs` SUCCESS、`probe-tests` SUCCESS（push 与 PR 各一次）
- merge commit 上检查：`handoff-docs` success、`probe-tests` success

T00.3 要求的独立 merge commit、两个 parent、远端开发分支保留均已满足。本任务不重复合入。

## 文档契约

本机命令：

```text
python3 scripts/validate-handoff.py
→ status=passed; requirements 134/132 active/2 retired; 12 work packages; 50 execution tasks; contract_revision=2

swiftc -swift-version 6 -module-cache-path /tmp/temperature-monitor-contract -typecheck docs/contracts/api-v1.swift
→ exit 0
```

`acceptance-v1.json` 与 `01-requirements.md` 编号为 REQ-001..134；退役仅 REQ-012/114。

## GitHub 规则与 Issue

| 项 | 实际值 |
|---|---|
| rulesets | `[]` |
| `rules/branches/main` | `[]` |
| allow_merge_commit | true |
| allow_squash_merge | true（W00 目标 false） |
| allow_rebase_merge | true（W00 目标 false） |
| delete_branch_on_merge | false |
| open blocking Issue | 无 |
| 其他 open Issue | 无 |
| `blocking-issues` 检查 | 不存在，尚未部署 |

文档 11 中“当前 rulesets 为空、允许 squash/rebase”与本次 API 回读一致。T00.4/T00.5 负责实现与启用，本记录不宣称门禁已生效。

## 工具链与外部依赖

| 项 | 实际值 |
|---|---|
| `xcode-select -p` | `/Library/Developer/CommandLineTools` |
| `/Applications/Xcode*.app` | 不存在 |
| Swift | Apple Swift 6.1.2（swiftlang-6.1.2.1.2） |
| 目标 | arm64-apple-macosx15.0 |
| GitHub CLI | `sisyphe550`，`repo` 等 scope；无 org admin 声明 |
| 签名/公证凭证 | 本任务未检查 Keychain profile；W10 外部依赖 |

CLT 足以完成文档校验、SwiftPM 核心测试与契约 typecheck。W07/W08 UI/`xcodebuild`、W09 正式 App 实机、W10 公证在对应任务记录为未执行或等待外部输入，不得在本基线写成已通过。

## 生产代码状态

- 存在：`prototypes/sensor-probe/`、原型 CI、2026-09-15 Mac16,13/15.7.3/24G419 证据。
- 不存在：`Packages/TemperatureCore/`、`TemperatureMonitor.xcodeproj`、`App/`、`blocking-issues` workflow、产品软件/实机/发布验证目录（本目录除外）。
- 不得将原型覆盖率或 CLI 读数当作正式 App 通过。

## T00.1 结论

后继任务可从 SHA `1d303a44e46d00d9e32163a305ab8baba5ba779d` 的 main 继续。T00.3 已由维护者完成；T00.2 固定检查名；T00.4 实现 `blocking-issues`；T00.5 在检查真实运行后再启用 required 规则。
