# 可选恢复同族测试等待机制只读检索（2026-10-03）

## 本轮范围

当前源码的完全相同机制剩3个测试文件：每轮只推进25ms虚拟时间，再sleep5ms真实时间，用4秒墙钟期限结束。这使需要到达的虚拟截止与外部调度负载耦合。Generation用例已修正，OptionalAvailability已有task/receipt barrier，没有这条推进耦合；不能仅因其它helper也抛Cocoa256而认定全部是同一缺陷。

| 建议同步修正 | 基线位置 | 具体机制与必须保留的目标 |
| --- | --- | --- |
| OptionalProbeBudgetAcrossReconnectTests | 26–37、105–110 | 四次初始失败与三次恢复失败仅按transport读次数+40ms猜callback完成。先等待同sampling task新sleep，确认failure Receipt、预算耗尽/stoppedKinds完成，再触发CPU重连；证明旧代7次后新代SSD零读、CPU仍真实提交、SSD仍不可用。全部SSD都失败，不能套raw成功数observer来计失败Receipt。 |
| OptionalWakeRecoveryRegressionTests | 26–44、108–121 | 初始隔离及wake后3读仍用同helper推进；newOptionalReads并不证明SQLite commit和可用转换完成。使用新代真实commit+SQL1/2/3及sampling task新sleep，发布后前2次不可用、第3次恢复。保留真实软件suspend/resume，不冒充物理睡眠。 |
| OptionalSleepAdmissionRaceRegressionTests | 27–48、118–131 | 相同推进耦合；第四失败故意卡在PendingFailureGate，其目标是suspend取消发生时该失败回调尚未返回。必须保留进入gate→suspend→取消标记→release→awaitsuspend的顺序，不能先等第四Receipt完整返回再睡。wake后以真实新代1/2/3提交/状态证明恢复。 |

## 同范围清理缺陷

SleepAdmissionRace的catch先await controller.stop，却没有release PendingFailureGate。当等待取消标记超时等可抛错误发生时，采样可能仍卡在该gate；stop也等待采样loop，因此清理本身可无限等待。源码可推导，未做运行复现。应在catch/defer中先同步、幂等release gate，再stop；保留pending sleepTask句柄并保证结束。正常路径已释放时重复release不应改变测试。

## Clock角色边界

resume会创建新的sampling/snapshot Task，旧身份需要重新识别。两者初始截止都可能是wakeMS+200，不能按这个裸deadline给SAM角色。可在wakeMS+500第一个SSD成功后用SAM下一wakeMS+600和publisher下一wakeMS+700的独立注册识别，并使wake偏移避开整数秒watermark；或从明确的采样fixture调用上下文捕获任务身份。总原则是按task角色过滤未来sleep、等待对应callback完成，不能误把publisher或水位等待当Receipt完成。

## 不扩大本次实现

其它CPU恢复/缺口用例含固定stride+短sleep，但不属于上述相同25ms/5ms/4秒helper族；未从本次检索证明它们触发44070失败，不建议据此扩大生产修改。本报告只要求3个同族test同步修正、保留现有Generation/Availability证据边界。

本次只读源码和已有日志；未修改仓库、运行测试/GUI、访问传感器或执行物理睡眠。

## 检索时身份

Git HEAD：`44070d6ea5d8dbe3e64a1c0ddc206f5bd2597f97`。

- OptionalProbeBudgetAcrossReconnectTests.swift SHA256 `e5724074142d43bbe6a6ba0730e452ac117aa8b5aaa4ec9434ca173cbd84a451`。
- OptionalWakeRecoveryRegressionTests.swift SHA256 `a6026f067b543bd8efe9471cc6a7a3338c37c0a2c76b56f82bd94ac1973fc61d`。
- OptionalSleepAdmissionRaceRegressionTests.swift SHA256 `5cbca901c4b1cc375533e7210cd49140c1a12dfc89e262a865a9bcc6e7f5af50`。
