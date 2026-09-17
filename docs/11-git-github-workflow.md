# Git、GitHub 与开发门禁

更新日期：2026-09-17。状态：用户确认流程＋授权设计基线；Git／GitHub 与原型 CI 已存在，强制门禁尚不完整。

## 分支与提交

1. 独立功能从最新主分支建立 feature branch，在分支内完成任务。
2. 分支开发期间执行相应单元、白盒和黑盒测试。
3. 测试发现可复现缺陷，建立 Issue，记录复现环境、步骤、预期、实际和证据。
4. 修复提交或 PR 关联 Issue，修复后执行对应回归测试。
5. 测试通过、阻塞缺陷解决后提交合并申请。
6. 满足门禁后采用独立 merge commit 合并。
7. 合并后保留远程开发分支和合并节点，不自动删除 feature branch。

现有主分支为 `main`，远端为 `git@github.com:sisyphe550/Temperature-monitoring.git`。本轮使用 `feature/v0-sensor-validation`。维护者审批规则和审批人数仍未冻结。

## 推荐仓库配置

| 目标 | 配置／实现方式 |
|---|---|
| 禁止直接推送功能代码至主分支 | 主分支保护或 ruleset，限制旁路权限 |
| 必需测试通过 | 设置必需 status checks |
| 核心逻辑行覆盖率至少 80% | CI 中执行覆盖率检查；工具与统计范围明示 |
| 阻塞 Issue 未解决时不得合并 | 明确阻塞标签及 Issue→PR 关联规则，再用检查实现 |
| 保留独立合并节点 | 采用 merge commit；避免 squash/rebase 取代所需历史 |
| 保留开发分支 | 关闭自动删除分支选项 |
| 缺陷可追踪 | PR 描述关联 Issue、测试与需求 ID |

GitHub 不会仅凭“有未解决 Issue”自动阻止所有合并。需要明确阻塞判定与可执行检查；未配置前不能宣称门禁已经生效。功能可用性随仓库可见性和账户方案而异，实际建仓时验证。

## PR 内容

记录修改的具体问题、变化后的行为、关联需求 ID、设计变更、测试证据、Issue 和已知限制。避免把未验证的传感器适配写成“支持全部 Air”。

## 主分支阶段测试

数据链阶段执行采集／加工／存储集成；UI 阶段执行菜单栏与窗口黑盒；系统集成执行完整测试；RC 执行 EARS 验收、实机兼容与分发检查。里程碑存在阻塞缺陷时不进入下一阶段。

## 待落实

仓库地址、main、原型CI、Issue与PR已落实；ruleset、维护者审批权限、阻塞标签检查及产品实机验证机制仍见OQ-15。不能将流程文档等同于强制门禁已经生效。

来源：C01。关联：[测试](10-test-strategy.md)、[阶段计划](12-development-plan.md)。

## 2026-09-15 执行记录与未满足门禁

- 从最新 `origin/main`（`3fa99aa`）创建功能分支；不直接向 main 提交功能代码。
- 功能代码提交 `cc5db3c`；实测前工作树干净，报告另行提交以保留代码版本追踪。
- GitHub Actions `probe-tests` 执行 Swift Testing、原型纯逻辑覆盖率、Release 构建、CLI 黑盒；托管 runner 不提供 Air 传感器证明。
- 测试／审查发现的缺陷建立 Issue #1、#2、#3，PR 关联修复和回归证据。
- 读取 GitHub 实际配置：支持 merge commit，`delete_branch_on_merge=false`；当前 main 没有传统分支保护，rulesets 为空。
- 因强制主分支保护、阻塞 Issue 检查、审批规则及产品覆盖率门禁未完整落地，本轮只提交待审查 PR，不执行合并。保留本地与远程功能分支。

原型 CI 成功不能声称 REQ-086/087/091/095/096 已由 GitHub 强制执行。相关配置属于 OQ-15，后续落实后方可执行规定的 merge commit 合并。

本轮待审查产物：[Draft PR #4](https://github.com/sisyphe550/Temperature-monitoring/pull/4)。Issue #1～#3 已附修复回归证据并关闭；OQ清单中的未决项继续保留。

## 2026-09-17 方案修订范围

刷新远端后main仍为`3fa99aa`，PR #4保持打开且为Draft。本轮是既有V0证据的参考项目复核与设计细化，继续在`feature/v0-sensor-validation`提交文档增量并更新同一PR；未增加独立产品功能，未合并main。后续正式功能仍从最新主分支建立独立feature branch。
