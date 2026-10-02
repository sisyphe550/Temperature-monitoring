# 2026-10-02 · a97fd5a8 独立 UI 证据核对

## 结论

本机真实硬件 UI 用例通过：`testLocalReleaseAppRealHardwareUI()`，1 项、0 失败、84.7996 秒。已核对当前提交 `a97fd5a8` 的测试代码、xcresult 状态、文本附件及应用窗口截图；未发现本轮已执行 UI 路径的生产缺陷或 AX 选择器错误。状态项的实际点击与右键菜单仍未验收。

## 已覆盖的生产路径

- `XCUIApplication(url:)` 指向工作树 `build/TemperatureMonitor.app`；启动参数为空，没有 fixture 或 `--ui-open`。生产启动主窗口及 `app.quit` 按钮存在断言通过。
- CPU 主温度必须符合数字摄氏度格式；12 个 CPU 来源 checkbox 数量与来源键集合精确匹配。文本附件记录 12 项实际数值；SSD/TEMPERATURE 40.7 °C、Battery/TB1T 33.8 °C，均明确显示应用读取时间与测量更新时间未知。
- 50/100/200/500/1000 ms 逐项选择，分别保持约 8.0009/8.0050/8.0038/8.0046/8.0050 秒；每档结束仍有数字主温度、无 Fatal、选项值保持。
- CPU Max 与 Te05 比较；5 分钟/1 小时历史标题、来源、非空数据和无失败断言通过。1 小时窗口截图可见两条实际曲线及 Raw 峰值。
- 关闭主窗口后进程状态项仍在且主温度有数值；`NSWorkspace.shared.open(appURL)` 标准重开成功，1000 ms 和 Te05 选择保持，新增 Session UUID 集合仍为同一项。
- 点击窗口 `app.quit` 后到达 `notRunning`，本轮创建的 UUID 目录消失，无剩余新增会话目录。

## 范围与证据限制

- 五档验证的是生产 UI 控制、短时保持和持续出现温度；没有逐样本统计实际采样间隔。CPU12 自动断言要求键、数量和 °C，单项是否数字由本次文本附件补充实测；不是更强的通用断言。
- 状态项 AX 为 `exists=true, isHittable=false, frame=(771,4.5,69,24)`。测试不依赖不可点击状态项，也没有据此跳过主窗口、数据或退出断言；不声明右键菜单可用。
- 本轮为本机短时验收，未扩展到跨硬件、五档各 10 分钟或 72 小时耐久。

## 可归档附件

已导出至 `/tmp/temperature-final-real-owned-evidence`：10 张 1600×1120 的应用窗口 PNG、2 份显式文本附件及 `manifest.json`。导出采用名称/类型白名单；没有导出整屏录像，也没有导出关窗后的菜单栏截图。已视觉核对启动及 1 小时历史窗口只包含自有应用。

复现导出：

```sh
python3 /tmp/temperature-export-owned-attachments.py /tmp/temperature-ui-final-real.xcresult /tmp/temperature-final-real-owned-evidence-copy
```

xcresult 来源：`/tmp/temperature-ui-final-real.xcresult`；运行日志：`/tmp/temperature-monitor-review-20261002.1G0KnN/ui-final-real.log`。

## Fatal 负例的独立范围核对

根代理执行受控 Release 副本移除 worker 并重新 adhoc 签名的实测。我只读核对 `/tmp/temperature-monitor-review-20261002.1G0KnN/fatal-negative-timed-observation.json` 和对应日志，未启动第二套应用。

- 报告保留 `error_code=APP-INIT-001, component=AppDelegate, operation=makeProduction, severity=fatal, underlying_error=missingSensorWorker`，与 `AppSessionRuntime.makeProduction` 缺少 worker 的源码错误路径一致。
- 定时观察有 PID，然后无输入自动消失：首观察 `15:24:07.185203Z`，最后有 PID `15:24:38.513307Z`，首次无 PID `15:24:38.649256Z`，从首观察计 31.4639 秒，包含启动。根代理另见 Fatal 窗口中的原始错误、报告路径和 30 秒倒计时。
- 这是启动 Fatal fallback 及名义 30 秒自动退出的短时证据；不证明窗口可见时长精确为 30.000 秒，也不覆盖运行中 Fatal 的会话收尾。缺少 worker 的 guard 发生在创建 SessionCoordinator 之前。
- 最终定时报告为 timed JSON 内 `written_at=15:24:07Z` 的记录。单独 `fatal-negative-report.json` 是较早第一轮 `15:22:28Z` 的报告，不应与定时观察混批。
