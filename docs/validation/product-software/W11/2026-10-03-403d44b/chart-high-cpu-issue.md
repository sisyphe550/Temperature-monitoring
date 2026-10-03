## 问题

正式 Release 在 Mac16,13 / macOS15.7.3 (24G419) 可见五分钟历史图、CPU50ms采样时，主App随样本填充产生高CPU负载。约5分钟主App达到120.3%→157.2%→163.3%，worker仅0.7%→0.8%→1.0%；macOS100%代表一个核心。一秒profile主线程650个采样栈中516个（79.38%）进入Charts。

本Issue记录真实资源负载和候选优化。现行文档没有CPU百分比硬指标，不能把高CPU等同为已证实违反skipped≤1%；硬件对照仍待执行。

## 复现条件与证据

- 正式Release、无fixture/no launch arguments、CPU12＋CPU Max＋可选SSD/Battery。
- 会话790c134a-a3a5-44c3-97bd-e32647b8b704，AppPID43405，WorkerPID43512。
- 可见默认五分钟历史；CPU50ms连续填充300秒左右。
- 最后SQL snapshot中CPU Max50ms共6092点，18.497954833→325.833504125秒；最后300秒含5945点，Presentation降采样到≤2000点/来源，Charts每点LineMark且分桶后再有AreaMark。
- 本地证据：`/tmp/temperature-long-ui-20261003T033320Z/live-observations.jsonl`、`final-before-normal-quit.sqlite`；`/tmp/temperature-long-50ms-43405.sample.txt`；独立审查`/tmp/temperature-long-failure-readonly-review.{md,json}`。

自动长测同时发生cpu.period AX snapshot瞬时无匹配，清理时有Codex Dialog interruption；尚未证明该AX失败由Charts造成。第一档未完成600秒，后四档未执行，不能记录五档通过。

## 机制与优化边界

AppSessionRuntime随200ms snapshot自动刷新五分钟history；Dashboard又以每200ms改变的running.asOf传入历史Chart，使几何可能在结果未变化时仍反复更新。超过2000点后多数bin带min/max，接近2000个LineMark＋2000个AreaMark。

候选：将自动历史结果更新独立降至1Hz，当前值快照仍200ms；HistoryChartView以chartState作Equatable隔离，历史asOf锚点跟随该次接受的history几何更新。强制来源/范围/唤醒reload即时。Swift6 operator用nonisolated，仅比较Sendable不可变chartState；不触及@State，不用unsafe或uncheckedSendable。

不改CPU50/100/200/500/1000档、不丢Raw/EMA、不缩CPU12成员、不改2000点cap/minmax/count/gap/来源边界、不更改schema/API/default/契约revision。

## 验收

- [ ] 实际AppRuntime TestClock/查询spy验证自动1Hz，强制reload仍即时。
- [ ] 不同asOf而相同history等值；新点、gap、segment、来源、状态会重绘。
- [ ] 完整Release Swift6构建、核心/相关UI回归通过。
- [ ] 同CPU50ms、同窗口尺寸、至少300秒同填充真实App对照CPU/RSS/profile，确认改善，不能凭候选代码判定修复。
- [ ] 点选摘要、切范围/来源、浅深色、sleep/wake gap与新来源正确。
- [ ] 新同哈希五档各600秒和真实睡眠/唤醒验收独立归档。

已测边界：原样本实际相邻间隔p95=52.47225ms/p99=58.071833ms；理想20Hz机会短缺0.90635%，不是scheduler skippedByKind计数，不能替代读批耗时和显示延迟指标。`skipped≤1%`、读批/显示门槛需正式独立证据；不得为降低负载删去五档。
