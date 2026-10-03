# 两项生产修复独立最终审查（2026-10-03）

## 结论

当前所审查的暂停历史请求、启动中睡眠、正常退出取消、Fatal异步退出调度路径没有剩余阻断项。初版 gate 丢弃 startup sleep 与 wake取消被误标Fatal 两项真实缺陷已由 Root 应用修正，独立实际Runtime CLI已完成对应RED/GREEN。没有操作工作树，没有启动GUI或正式 TemperatureMonitor。

最终 AppSessionRuntime SHA256：`913571a8143a7f9d11a159139c0b06da8ef182df51a7dc9e334acceedea8357b`。

取消GREEN实际编译Runtime SHA256：`507beff5fc748def778415af7ac66f9912f2dc4d63b48b791ae1ee78446b4aad`。它与最终Runtime唯一差异为Root新增的1Hz自动历史刷新；本审查不声称完成频率/Equatable/实际GUI响应验收。

## 独立实际验证

| 路径 | 初版/RED | 修正/GREEN |
|---|---|---|
| discovery被受控阻塞时收到sleep | startup sleep被忽略，历史仍可查询 | history Cancellation，wake恢复查询，无Fatal |
| 同一个MainActor job中start后立即sleep | 未据此扩大RED结论 | Cancellation→wake恢复→正常stop，exit0 |
| start Task尚未入队时stop | 未运行RED | 无孤儿Session，停止后拒绝query，exit0 |
| discovery阻塞时stop | 未运行RED | 无孤儿Session，无Fatal，exit0 |
| 取消正在discover的wake并stop | APP-INIT-001，exit1，0.499833s | Fatal为空，exit0，0.493053s，未触发5s watchdog |
| Task/GCD主队列调用AppKit terminateLater | 两者reply Task均不能开始，2s watchdog | RunLoop common回调正常reply/exit0，0.127411s |

真实Runtime CLI使用实际 AppSessionRuntime、SessionCoordinator、Core源码与受控Qualified目录/时钟；没有用简化状态机替代。startup两种调用与stop两种边界已通过，取消最终仅重复原RED场景，没有另跑硬件/GUI/全套Core。

## 源码审查

- `AppSessionRuntime.start()` 同步进入 starting，建立共享 startupTask；sleep覆盖starting/active并先关history gate，等待启动结束后才进入coordinator的sleep操作。run只把仍starting转active，不覆写suspended。
- stop先设inactive、使历史请求ordinal失效、取消并join启动，再stop协调器，防止未入队启动在停机后新建会话。sleep/wake catch均要求仍suspended且Task未取消，正常退出的取消不被重新包装为Fatal。
- history reload只在active提交；暂停与Fatal都会使旧ordinal失效。已有query成功/失败回调仍检查取消与ordinal，不会把睡眠中的旧请求套到醒来后的状态。
- `SessionMonitorController.history` 在暂停时先Cancellation，避免 realtime/SQLite dispatch；unstarted/stopped仍保留not_running失败。`SuspendedHistoryRegressionTests`覆盖两历史范围、禁止触及已关闭持久化、无新receipt/Failure、正常wake后Raw/EMA及sleep gap/新segment；这里为独立源码审查，未将Root全Core运行冒充本agent执行。
- 新私有生命周期枚举、startupTask只用于后端任务协调，未加入新的公开UI状态、并行UI布尔或View切换条件。展示仍由PresentationModel.state/PresentationState决定。
- `AppDelegate.quit()` 使用RunLoop common回调后调用terminate，使调用它的Task/GCD回调先返回；普通菜单、窗口退出、Fatal计时都走同一quit入口。既有terminateLater的stop、5s预算、一次reply保持。菜单/窗口按钮这里只确认源码共享入口，物理可达性和实际点击不在此轮非GUI验收。独立harness证实退出机制；Root报告的正式 runtime Fatal自动退出/清理是另一条实机证据，本报告未替代其最终构建回归。

## 边界与可提交材料

- 本报告只关闭所述生产修复及已复现的相关竞争，不宣称五档各600秒、OS sleep/wake、性能p95/p99、72h或最终GUI整体通过。
- Root新增的1Hz历史刷新/Equatable隔离和long runner调整不属于此项独立动态验收；频率只确认代码差异不触及startup/cancellation guards。
- 精简可重复源码包：`temperature-runtime-review-reproduction.tar.gz`，内含四个最终文件快照/哈希、最少Core依赖、实际CLI harness与原始JSON；包不含.build、整屏录像或其它App内容。
- 原始取消证据：`wake-stop-red.json` / `wake-stop-green.json`。AppKit原始证据另在 `/tmp/temperature-appkit-termination-harness/`。
