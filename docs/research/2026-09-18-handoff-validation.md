# 实施交接包验证记录

日期：2026-09-18

基线：`21fc9625720b32c5d07c471322a6ac3b7b144b7d`之后的文档交接改动；最终提交SHA在PR #4形成后以GitHub检查记录为准。

## 范围

本记录验证需求、设计、接口、SQLite DDL、实施计划和历史原型回归是否形成一致的可执行交接。它不证明生产App已经实现，也不替代W08的App构建、W09的正式App实机资格、W10的签名/公证和72小时测试。

## 本地检查

| 检查 | 命令 | 结果 |
|---|---|---|
| 需求／任务／测试／链接／JSON／SQLite约束 | `python3 scripts/validate-handoff.py` | 通过：134 total、132 active、2 retired、12 tasks、19 test groups |
| Swift 6公共类型契约 | `swiftc -swift-version 6 -typecheck docs/contracts/api-v1.swift` | 通过 |
| 独立模块使用公共初始化器 | `swiftc -emit-module … api-v1.swift`后从另一源文件`import HandoffAPI`并typecheck | 通过 |
| 目标机旧证据复核 | Python读取`sampling-results.csv.gz`并按固定12键计数/状态 | 通过：每键2279、合计27348，全部仍为`decoded_mapping_unverified` |
| 固定上游快照复核 | 对临时只读克隆的6个固定commit及manifest内文件SHA-256复算 | 通过：6个commit一致、24/24文件hash一致；临时目录不作为交接依赖 |
| 原型Swift测试 | `swift test --package-path prototypes/sensor-probe --enable-code-coverage` | 通过：8/8 |
| 原型纯逻辑覆盖 | `python3 scripts/check-probe-coverage.py` | 通过：ProbeCore 55/55，100% |
| 原型Release构建 | `swift build --package-path prototypes/sensor-probe -c release` | 通过 |
| 原型CLI黑盒 | `python3 scripts/test-probe-cli.py` | 通过：help、非法参数、缺值和已有目录保护 |
| 工作树文本完整性 | `git diff --check` | 通过 |

`validate-handoff.py`实际创建临时SQLite文件，执行schema，验证外键、重复主键、segment隔离、count加权avg、无效趋势、空聚合与事务rollback；同时验证134个连续REQ、132个active、2个retired、正文SHA、W00～W11、19组测试、设计链接和固定profile/defaults。它只验证规格内部一致性。

本机Codex受限沙箱第一次阻止SwiftPM写用户级Clang cache，第二次阻止SwiftPM自身的`sandbox-exec`；这是执行环境拒绝，不是测试断言失败。获准在沙箱外运行后，仓库标准`.build`路径的同一测试命令8/8通过，随后覆盖门禁、Release和CLI检查均通过。

## 仍须实施阶段取得的证据

- 完整Xcode App和嵌入worker尚未创建，不能声明`app-build`或UI验收通过。
- Mac16,13上的现有E1来自传感器原型；正式App沙箱/签名条件、全部五档、休眠恢复、可控负载和连续72小时仍由W09执行。
- Developer ID、notarytool、公证票据及正式ZIP仍由W10执行；缺凭证时保留为明确外部依赖。
- GitHub规则集与`blocking-issues`可信工作流由W00配置并回读；本次只交付`handoff-docs`检查定义，不把尚未启用的保护写成事实。

## 结论口径

检查全部通过时，只能得出“其他agent可以依据交接包开始并逐阶段验收”的结论。硬件接口有E1原型证据或固定E2实现路线；系统其余部分有D级工程契约和测试入口。D级设计不是开源代码现成实现，也不是产品完成证明。
