# Git、GitHub与执行门禁

更新：2026-09-21；contract revision 2执行方案。远端`git@github.com:sisyphe550/Temperature-monitoring.git`，主分支main。文档基线已由[PR #4](https://github.com/sisyphe550/Temperature-monitoring/pull/4) 合入；[PR #5](https://github.com/sisyphe550/Temperature-monitoring/pull/5) 将 `blocking-issues` 放到默认分支；T00.5 在该检查对真实 open PR head 成功后启用 required 规则。回读证据见 `docs/validation/product-software/W00/`。

## 分支与集成

1. 本轮文档收敛继续原V0分支，保留已有证据，不混入生产App实现。
2. W00先让PR #4通过当时已存在的`handoff-docs`、`probe-tests`和独立审查，由维护者merge commit合入完整规范；此之前后续agent可审阅/验证文档，不能从旧main创建正式功能并遗漏设计。
3. 从合入PR #4后的main创建`feature/w00-repository-gates`，实现并测试`blocking-issues`和配置脚本；用已有检查合入，使特权workflow先成为可信默认分支代码。随后在规则证据PR上触发该检查，确认成功后才把它设为required并回读规则。不得要求尚未部署或从未成功运行的检查。
4. 每个独立功能从最新origin/main创建`feature/<功能>`；这是项目对默认分支命名的覆盖。先检查用户未提交改动；需要隔离用独立worktree，不reset用户工作区。
5. 实现→对应测试→可复现缺陷Issue→修复回归→独立审查→PR；不在main直接提交功能代码。
6. 所有门禁通过且维护者确认后使用merge commit，禁止squash/rebase代替；保留本地和远端功能分支，不用`--delete-branch`。

GitHub审批最低人数设0，适配当前单维护者仓库；**这不免除独立审查**。PR必须链接非实现者的审查结论和已处理事项，维护者最终决定合并。若未来增加协作者，可另行把GitHub非作者审批提升为1，不把不存在的审批人写成已配置。

## 契约变更的原子同步规则

当前实现基线是`contract revision 2`。修改公开类型、默认值、profile、数据库schema、来源资格、持久化所有权、展示状态或第三方复用边界时，必须在同一提交中同步所有受影响的权威层，不能用多个暂时互相矛盾的提交传播契约：

1. 更新`docs/contracts/`中的API、defaults、profile、schema或`third-party-v1.json`；文件名中的`v1`是产品契约族，兼容性修订以`contract_version`判断。
2. 同步`01-requirements.md`、`acceptance-v1.json`正文hash和`17-traceability.md`；不得只改叙述而留下旧机器映射。
3. 同步实际定义行为的02～13、19～21专项设计；错误码、状态互斥、单位、缺口和幂等语义必须保持一致。
4. 接口、依赖或验收发生变化时同步22、23和`tasks-v1.json`；若任务DAG确实不变，记录不改的理由，不制造无意义版本漂移。
5. 同步10中的测试组和`scripts/validate-handoff.py`，先建立会失败的门禁，再更新文档使其通过。涉及上游经验边界时必须覆盖`TC-UPSTREAM-BOUNDARY`。

复制或修改第三方代码前，先在`third-party-v1.json`登记固定commit、上游与本地路径、复用方式、许可证hash、notice路径和修改摘要；同时提交许可证/notice。`method-only`来源不能转成代码导入。契约同步不完整、校验失败或来源登记缺失时，该提交和PR不得合并。

## 强制规则（T00.5 API 回读）

2026-09-21 `gh api` 读取：

- 仓库：`allow_merge_commit=true`、`allow_squash_merge=false`、`allow_rebase_merge=false`、`delete_branch_on_merge=false`。
- ruleset `main-protection` id `23754438`，`enforcement=active`，目标 `refs/heads/main`，`bypass_actors=[]`，`current_user_can_bypass=never`。
- 规则：`deletion`、`non_fast_forward`、`pull_request`（审批人数 0、必须解决 review thread、`allowed_merge_methods=["merge"]`）、`required_status_checks`（strict，contexts：`handoff-docs`、`probe-tests`、`blocking-issues`）。
- 未要求 `core-tests` / `app-build`：这两个检查尚未创建并成功运行。
- open blocking Issue：无。

产品检查创建并至少成功运行一次后，再增加 `core-tests` 和 `app-build`。不能要求一个从未运行的不存在检查而永久锁死 PR。核心覆盖≥80%；准确分母见 10。UI 产品 PR 还须附真实 UI 测试证据。不启用 `required_linear_history`（与 merge commit 矛盾）。

配置脚本：`scripts/configure-repository.sh`。变更规则后必须重新 `gh api` 回读，HTTP 错误不能假装完成。

## Issue与机器门禁

固定标签：`bug`可复现缺陷、`blocking`阻塞当前里程碑/合并、`hardware`实机相关。每条缺陷记录环境、SHA、复现步骤、预期/实际、证据；修复PR用`Fixes #N`关联，回归通过才关闭。

采用保守且可执行的规则：**仓库任何open且带blocking标签的Issue阻止当前所有功能PR合并**。PR另有`Related issues: #1, #2`说明影响；没有Issue写`Related issues: none`，不靠自由文本推断是否阻塞。

W00实现`blocking-issues` check：

- 在PR opened/reopened/synchronize/edited、Issue opened/reopened/closed/labeled/unlabeled以及workflow_dispatch触发。
- 仅用Issues/Pulls API读取仓库状态，枚举open PR最新head SHA，并给每个head提交成功/失败check；API出错按失败，不把“查不到”当0。
- Issue状态变化后必须更新同一head的检查；合并前再次触发检查并确认SHA一致。不要只在代码push时运行，留下陈旧绿灯。
- 使用受信任base/default branch上的workflow，无需checkout或执行PR代码；最小权限issues:read、pull-requests:read、checks:write。任何带写权限的pull_request_target工作流不得执行PR分支脚本。
- PR自带脚本不能决定自己有没有blocking；检查逻辑由受保护默认分支维护。初次启用的引导workflow由管理员审查部署，再要求check，不作自我证明。

## 可复核命令

```sh
git fetch origin
git status --short
gh pr view 4 --json headRefOid,baseRefName,isDraft,state,statusCheckRollup
gh api repos/sisyphe550/Temperature-monitoring/rulesets
gh api repos/sisyphe550/Temperature-monitoring/rules/branches/main
gh api repos/sisyphe550/Temperature-monitoring --jq '{allow_merge_commit,allow_squash_merge,allow_rebase_merge,delete_branch_on_merge}'
gh issue list --state open --label blocking --json number,title,url
gh pr checks 4 --watch
```

实际要合并的PR号由当前任务取得，不硬编码4到后续功能脚本。合并前核对exact head、全部required checks、零blocking、审查结果、适用实机/UI证据；管理员若缺权限则保留PR并记录外部依赖。不得以文档已完整为由跳过仓库保护。

## PR说明

写清触发问题、最终行为、关联REQ、文件/接口变更、执行过的测试及未测边界。不把候选可读写成全Air支持；不把方案/模拟/原型证据写成正式产品通过。合并后核对merge commit具有两个parent，并确认远程开发分支仍存在。
