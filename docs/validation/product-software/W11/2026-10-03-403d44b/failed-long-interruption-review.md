# 五档各10分钟 UI 长测 · 合盖中断核对

有效运行 `/tmp/temperature-long-ui-20261002T164812Z`，1 项 Failure，7532.346 秒；不能计作任一档 600 秒通过。

- 唯一真实 Session：`51c0b098-ce0c-480a-85ec-e6577b647b83`，正式 App PID 86292，`build/TemperatureMonitor.app`，无 fixture 参数。
- 50 ms 起点：UTC `2026-10-02T16:49:05.198Z`；最后成功进度 UTC `16:53:55.896Z`，清醒单调时长 **290.694 秒**，选项50 ms、主温84.3 °C。没有 `LONG_UI_PHASE_END`，100/200/500/1000 ms 没有开始。
- `pmset -g log` 直接证据：当地 `2026-10-03 00:54:02` 显示关闭，`00:54:07` 因 **Clamshell Sleep** 进入真实系统睡眠，此后多次维护 DarkWake。首次FullWake记录为`05:38:59` Notification，随后又回睡眠；尚无人工FullWake后的产品恢复验收。
- XCTest 在下一次读取周期选择器时无法取得窗口控件；失败 AX 树只有 `Application, pid: 86292, title: TemperatureMonitor`，长度100字节。时间跨度、系统睡眠记录和AX不可达一致；当前证据不能判定为产品周期选择或温度功能缺陷。
- 测试失败清理打印`LONG_UI_FINAL_SNAPSHOT failure_cleanup hold_seconds=30`，但随后窗口退出按钮也不可达。只读pgrep显示PID86292仍在，无worker进程；**没有正常退出/Session清理通过证据**，未发送强制退出或重启。
- 第一次并发准备运行164810Z在0.522秒前置`app.notRunning`断言安全失败，未调用app.launch，未生成新Session；不计为产品执行失败。第二次164812Z成为唯一有效运行。

## 已保留的自有App证据

`/tmp/temperature-long-ui-164812-owned-evidence`：唯一startup应用窗口PNG、xcresult测试状态manifest、从日志提取并明确标注为部分进度的JSON、选定电源时间线。没有导出整屏录像；没有最终成功JSON附件。

导出复现：`python3 /tmp/temperature-export-long-ui-evidence.py /tmp/temperature-long-ui-20261002T164812Z/long-ui.xcresult /tmp/temperature-long-ui-164812-owned-evidence-copy`。

## 完成条件

五档仍全部未完成。重新执行需要盖子打开、显示/GUI会话可访问至少约51分钟；本次物理合盖不能通过软件保活补成600秒清醒运行。应先完成当前真实睡眠后人工唤醒与同Session恢复证据，再正常退出旧Session，按根代理GO单次重跑。worker读批p95/p99、skipped≤1%、显示延迟p95≤500ms仍依赖独立真实观测，不由本轮UI数据推断。
