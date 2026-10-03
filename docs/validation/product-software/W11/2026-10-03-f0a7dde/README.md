# f0a7dde 可选来源回归组的同步修正

测试提交：`f0a7dde76e3e02e66f23aed47915bb75e2fa438b`；生产及构建输入与`7124dc1644516f471d69930024589342c0ca34c9`Git diff为空。157份源码、构建和测试源与实际提交对象逐字节匹配。

44070 Core一次通过、一次OptionalProbeBudgetAcrossReconnectTests等待超时，原CI失败及同head快照完整保留；Cocoa256来自测试helper主动到期，不证明真实文件IO失败。125ms受控旧驱动模型在virtual775ms提前到期，第四retry仍在850ms。模型证明墙钟/虚拟时钟速率耦合，原CI唯一阶段未知。

仅更改四项可选来源回归及共用测试时钟：Budget按实际提交及任务未来sleep边界推进；Generation抽取已验证helper；Wake/Race保留软件睡眠恢复及第四读取消竞态。真实SQLite记录、来源代际、三次新成功恢复、探测预算和异常清理断言保留。详见[预算红绿与负控](budget/report.md)、[Wake/Race记录](wake-race/report.md)、[独立审查](review/wake-race-independent-review.md)和[完整Core](full-core-summary.json)。局部测试和全量计数不相加。

最新完整Core 355 tests / 57 suites PASS；Core line coverage: 7116/8002 = 88.93%。生产代码及构建输入未变，正式App未重建/重测；原7124真实Release短测87.162秒保留原source/App/worker身份。不继承为五档600秒/精确性能或物理sleep通过。

用户要求跳过本轮真实休眠验收，软件生命周期回归保留。100accepted/31pending/1waived/2retired不变，PR26仍Draft，W11未完整完成。GitHub最新head CI和blocking另回读，不能用此软件归档宣称整体交付通过。
