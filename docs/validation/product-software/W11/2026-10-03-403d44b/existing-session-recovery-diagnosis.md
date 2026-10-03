# 旧正式会话恢复诊断（2026-10-03）

## 已确认事实

- 会话 `51c0b098-ce0c-480a-85ec-e6577b647b83` 的真实 Fatal 报告为 `PROC-VALIDATE-001`，`SessionMonitorController` / `history` / `not_running`，写于 `2026-10-02T16:54:02Z`；同一诊断 JSONL 记录一致。报告 `incomplete_shutdown_steps=[]` 只表示当时写报告，不能证明随后停机成功。
- pmset 同秒 DisplayOff，5 秒后 ClamshellSleep。willSleep 通知可先于最终 Sleep 记录，因此不能称 Fatal 必然发生于 sleep 通知前。
- 原 XCTest 最后有效 UI 观测为 `16:53:55.896Z`、50ms 290.694146750s。其首次断言失败发生于 t577.42s，晚于实际 Fatal，不能将 Fatal 归因于断言失败或其失败清理。
- Root 于当前真实 FullWake 后观察同 PID 86292、同会话、无 worker、Raw 截止约 elapsed304s、sleep gaps 未闭。这里只引用 Root 的独立进程/DB证据；本 sandbox ps/pgrep 读取被系统服务权限拒绝，没有绕过。

## 源码与具体竞争候选

`AppSessionRuntime.suspendForSleep` cancel/nil 历史任务，但 snapshot 消费循环仍可能消费已缓冲/正进行的快照并再调用 `requestHistoryReload`。Controller suspend 先 `running=false` 再 await 多项 suspend 工作，而 `history` 对 `running=false` 抛 fatal `not_running`。这给出了 sleep 过渡窗口触发 history Fatal 的具体路径；尚待确定性回归证明。

`enterFatal -> freezeForFatal -> recordFatal -> presentationModel.enterFatal -> showFatal` 是现行路径。`resumeAfterWake` 遇 presentation Fatal 直接返回，因此该会话不能按正常 wake 恢复预期解释。它还可能处于正常终止尚未完成的状态（AX Disabled / 无窗口）；需要 Root 的只读 process sample 才能确定，不能从窗口消失推断进程已正常退出。

## 交付且未运行的诊断测试

`/tmp/temperature-existing-session-reopen.patch`：仅新增 `testLocalReleaseAppReopenExistingSession`。
`/tmp/temperature-run-existing-session-reopen-ui.sh`：Root 唯一执行者运行一次 Xcode UI test。

严格 guard 已存 PID/path/session，标准 NSWorkspace.open，不 launch/terminate、不 fixture。窗口后观察至少30秒；CPU member标签必须为“应用读取”且匹配当下本地秒（-5..+2s），至少两个不同当前读取时间，排除旧 cached/live。own-window PNG + JSON。失败无退出/teardown；默认成功仍保留会话，显式 TM_REAL_REOPEN_QUIT=1 且恢复成功才正常 app.quit。

Swift6 typecheck、bash语法、git apply --check 均 exit0。这是准备验证，未执行，不能计为 UI/OS睡眠恢复通过。
