# Runtime Fatal 正常退出死锁独立验证

## 结论

本机 macOS 15.7.3 / Apple Swift 6.2.4 实测复现。NSApp.terminate 从 MainActor Task 或 GCD 主队列回调调用，在 delegate 返回 terminateLater 后进入 AppKit 嵌套事件循环，主队列/执行器仍被当前回调占用，新的 MainActor shutdown/reply Task 无法执行。RunLoop common 模式回调调用 terminate 可让异步回复执行并正常退出。

旧 TemperatureMonitor 的真实 sample 在 883/883 主线程采样中位于 showFatal 的 Task closure (AppDelegate.swift:101) → NSApplication terminate → _shouldTerminate → 嵌套 CFRunLoop，与 harness RED 路径一致。这证实独立退出机制缺陷，区别于最先触发的 history/not_running Fatal。

## 实测原始结果

- `task`：PID 7932；monotonic 2.003994459s；exit -9；watchdog=True；事件 `did_finish_launching, task_timer_completed, task_enter_terminate, should_terminate_return_later`。
- `main-async`：PID 9273；monotonic 2.003433208s；exit -9；watchdog=True；事件 `did_finish_launching, task_timer_completed, initial_task_returned, main_async_enter_terminate, should_terminate_return_later`。
- `runloop`：PID 10679；monotonic 0.127411000s；exit 0；watchdog=False；事件 `did_finish_launching, task_timer_completed, initial_task_returned, runloop_enter_terminate, should_terminate_return_later, reply_task_started, reply_true, will_terminate`。

RED 的 -9 来自 Python watchdog 精确结束该 subprocess handle；仅针对自己启动的 harness，未向正式 App 或其它 App 发信号。每进程最多2秒。三个 stderr 均为空。

## 最小建议与当前源码核对

将唯一 AppDelegate.quit() 的 terminate 调用调度到 RunLoop.main.perform(inModes:[.common])，在回调中 MainActor.assumeIsolated 调用 terminate。这样覆盖 Fatal Task 及其它现有 quit 调用点，保留 terminateLater 的 stop/5s deadline/reply 链。不能改成 DispatchQueue.main.async：实测同样 RED。

Root 已在本验证期间独立应用此修复；只读复核当前 AppDelegate.swift:248-254 与 harness GREEN 调度方式一致。AppDelegate-runloop-quit.patch 是当前 git diff 的只读副本，无需再次应用。本 agent 没有修改工作树。

这是机制 harness 已通过；新正式 App 的 runtime Fatal 窗口/30秒自动退出/正常会话清理仍需 Root 回归，不能把 harness GREEN 当作产品整链通过。没有启动或操作 TemperatureMonitor。

## 可复现命令

```bash
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc -swift-version 6 -g -target arm64-apple-macos15.7.3 -sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk -module-cache-path /tmp/temperature-appkit-termination-harness/module-cache -framework AppKit /tmp/temperature-appkit-termination-harness/TerminationHarness.swift -o /tmp/temperature-appkit-termination-harness/TerminationHarness
python3 /tmp/temperature-appkit-termination-harness/run-harness.py
```

第二条需本机 GUI 权限；仅运行自有 harness。原始 results.json、三份 stdout.jsonl/stderr.log 均在同目录。
