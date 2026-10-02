# 2026-10-03 交付与CI同步修复：651b29e

## 结果与版本

17项产品缺陷#27–#43已修复、回归并关闭，另追加的CI测试同步缺陷[#45](https://github.com/sisyphe550/Temperature-monitoring/issues/45)已修复并关闭。[修复PR #44](https://github.com/sisyphe550/Temperature-monitoring/pull/44)承载本轮代码、文档和证据；全部required checks必须按PR最新head确认，交维护者决定合并。没有执行本轮合并，保留开发分支与原始工作区。

- 正式App生产代码：`a97fd5a8d6ec53c957be7b05de2a3803e24effc2`，[正式App验证报告](../2026-10-02-a97fd5a/report.md)保持当次软件和实机结果。随后651b29e只修改测试：162份已审清单中的161份仍相同，唯一差异为EndToEndTests.swift；生产源码、资源、契约、UI和workflow完全未变，不能将测试同步改动说成重新实机验证。[哈希复核](code-drift.json)。
- 测试修复：`651b29ee9e158ccf8c06f63945460c09e3bbbb65`，仅29行测试同步，原13 Raw/13 EMA/1 batch与95°C历史断言全部保留。
- 最新本地全量：337 tests/52 suites通过；核心覆盖7067/7966=88.71%。[全量日志](logs/full-core.log)、[覆盖](logs/core-coverage.log)。原a97归档88.61%是先前运行结果，未回写为本次测量。
- 定向连续3次通过；非实现者独立10 tests/2 suites通过。[补审报告](independent-ci-review.md)、[日志](logs/independent-ci-tests.log)。

## CI失败的原因与修复

6af3f42的push核心检查失败而同head的PR核心检查通过；两套app-build均通过。失败用例在响应后固定等50ms，然后读取SQLite与内存EMA；这个等待不能保证ProcessingReceipt与其后状态发布完成。[原失败日志](logs/ci-6af3f42-core-failed.log)保留四个精确断言失败，不改名为通过。

改为有界轮询本次CPU max在210ms的EMA。五分钟历史读Engine buffer，此数据只能在合法Receipt验证后发布；2s ContinuousClock deadline、5ms状态轮询，不推进TestClock、不延长固定延时来代替状态边界。history错误与lastAcceptFailure直接抛，超时明确Issue+throw并正常stop。原数据正确性断言继续独立执行，等待条件本身不代替它们。

旧head的[PR核心成功日志](logs/ci-6af3f42-core-passed.log)及[App构建/UI成功日志](logs/ci-6af3f42-app-passed.log)只记录当时状态。推送新head后须重新通过handoff-docs/probe-tests/blocking-issues/core-tests/app-build；不得用旧成功检查盖章新提交。

## 交付边界

正式App在Mac16,13的CPU12/max/EMA、SSD/Battery、五档各8s、5min/1h、标准reopen同会话和正常退出清理由a97精确版本的证据支持。受控缺worker启动Fatal约30s自动退出，范围只为startup fallback。物理菜单右键、最终App真实系统睡眠/运行中故障、五档各10min和真长历史未在本轮实测。72/73h耐久、公证/公开发行与跨机型认证按用户范围豁免；不声明所有132项正式验收完成。

[Issue关闭记录](github-issues-closed.json)、[#45状态](github-ci-issue-closed.json)、[推送前blocking为空](github-blocking-before-push.json)和[归档交付独立补审](a97-delivery-review.md)一并保存。旧W11 PR #26仍基于旧SHA，应在修复合入后重新核对验收证据，不能先沿用旧完成结论。
