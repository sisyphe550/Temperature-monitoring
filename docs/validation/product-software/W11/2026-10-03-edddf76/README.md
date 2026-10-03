# edddf76 可选来源代际回归的同步修正

测试提交：`edddf76ddcffd3396315c52ede11eccda3ca2392`；生产及构建输入与`7124dc1644516f471d69930024589342c0ca34c9`逐项Git diff为空。156份源码、构建和测试源与当前提交对象逐字节匹配。

7c13的Core一次通过、一次用例等待超时，原CI日志保留。Cocoa256来自测试helper主动抛出，不证明真实文件IO失败；公开断管回归在该运行中通过，没有SIGPIPE。125ms慢轮询模型中，旧驱动在virtual775ms/optional3提前耗尽墙钟，第四retry仍在850ms，证明驱动与墙钟速率耦合；没有锁定原CI唯一阶段。

本次仅修正OptionalGenerationRecoveryRegressionTests的时钟/receipt同步，保留旧代际两个成功不能继承、新代际1/2不可用、3个已提交成功后恢复、真实SQLite记录和CPU继续运行等断言。详见[诊断与红绿记录](generation/report.md)、[独立审查](independent-review.md)及[新完整Core](full-core-summary.json)。局部用例与完整套件计数不相加。

正式App未重建/重测。此前7124真实Release短测保留原source/App/worker身份和87.162秒范围，可适用于未改变的生产/构建输入；不冒称新提交重新实跑，不继承为五档600秒/精确性能/物理sleep通过。

本轮物理休眠按用户要求跳过，软件生命周期回归保留。当前100accepted/31pending/1waived/2retired不变；PR26保持Draft，W11未完整完成。最新文档head CI与open blocking另按GitHub回读，不以旧结果覆盖。
