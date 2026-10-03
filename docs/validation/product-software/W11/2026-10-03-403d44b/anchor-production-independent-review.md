# W11 1Hz 历史查询与 View 相等判断独立审查

## 结论

1Hz 自动历史查询本身未发现新的阻断问题。原 `HistoryChartView.==` 存在一个可由源码与算术证明的正确性缺口：忽略 `asOf`，但 `date(for:)`、坐标与选点文字依赖 `asOf`。同一 chartState 遇到 wall-minus-elapsed 偏移变化时，相等的两个 View 会计算出不同显示时间。该问题应在合并前由所附单文件补丁修正。

补丁将显示锚点按最近毫秒量化，比较器和日期转换共用该偏移；没有修改 Raw/EMA、clock、契约、schema 或采样默认值。普通相同偏移的 clock advance 不触发无意义重绘；大于 1ms 的偏移变化必定使比较不等，跨量化边界的小变化也可能重绘。不可宣称所有“微秒抖动”都必然相等。量化误差最多 0.5ms，仅作用于绘图坐标/选点显示，UI 日期精度为秒。

## 具体审查

- `AppSessionRuntime.swift:267–312`：每次自动请求须 active、无在途 historyTask、距上次发起至少 1s；force 绕过节流。切范围、选来源、wake 仍强制请求。CPU 采样与 200ms live snapshot 不受改动；docs/07-native-ui.md 只规定 snapshot 发布上限和渲染分离，没有历史查询至少 5Hz 的要求。
- query 回调继续检查取消与 request ordinal，旧请求无法覆写当前结果；慢请求期间维持旧图，不创建重叠自动查询。实际查询耗时加上 snapshot 调度可使更新间隔大于 1s，不能将代码节流常量宣称成严格的 1Hz 完成保证。
- `HistoryChartState` 的 synthesized Equatable 包含状态 case、Failure、previous、series、Gap。每个 series 包括 seriesID/displayName/color/layer/所有 points；point 包括 segment、elapsed/wall、value、min/max/count；Gap 包括来源、起止和原因。来源版本在 seriesID/displayName 中表达。新增/关闭 Gap、来源/version/layer/数值变化不会因这个 comparator 被跳过。
- `TemperatureDashboard.swift:113–114` 只给 HistoryChartView 添加 equatable 包装；没有把整个 Dashboard、数值更新或时间范围控制冻结。
- `@State selectedDate` 没有改成外部输入，也没有新增状态模型。相等判断不比较本地 @State 不构成源码层面的新缺陷；本地 chartXSelection 更新是否仍可交互需要真实 SwiftUI 点选确认。本次没有操作 App，不能将上述源码判断当成物理选点通过。
- 原 comment 声称冻结“accepted history result 的 anchor”，但实参实际来自 live `running.asOf`，PresentationModel 未把 history-result anchor 绑定进 chartState；不可依赖旧 View 实例偶然冻结实现这一语义。所附补丁消除了这种隐含依赖。
- startup/sleep/cancel 和 RunLoop.quit 采用另一独立报告 `/tmp/temperature-runtime-final-review/final-independent-production-review.md` 的实 Runtime RED/GREEN、AppKit CLI 证据；本次仅确认最后新增 1Hz 没有删除相关 guard，没有重复编译/运行那些用例。

## 补丁与验证边界

补丁：`/tmp/w11-chart-anchor-equality.patch`（仅 `App/Presentation/HistoryChartView.swift`）；替换预览：`/tmp/w11-chart-anchor-equality-green.swift`。

`asOf` 改为不可变 Sendable `let`，computed offset 显式 nonisolated，避免 Swift 6 的非隔离 == 读取可变 MainActor 属性。唯一生产构造点 Dashboard 已传入 asOf。

整数实现先分解商和余数，再对余数 floor((r+500000)/1000000)。它等价于无限精度整数 `(wall−elapsed+500000)//1000000`，包括负余数和正/负极限；没有直接 wall−elapsed、+500000 的 Int64 溢出，也没有 offsetMS×1000000 的溢出。无 asOf 时仍使用原 point.wallUnixNS fallback。

独立 Python 算术 RED：chartState 不变、wall jump +3600s，旧 comparator 为 true、计算出的 point date 相差 3600s。GREEN：偏移比较为 false；正常 wall/elapsed 同步推进保持 equal。16 组 signed Int64/负余数/half-ms 边界通过。原始数据 `/tmp/w11-chart-anchor-equality-results.json`，这是算法模型与源码检查，不是编译后的 App 或硬件验证。`git apply --check --whitespace=error` 通过，没有改仓库文件。

单 View Swift 6 SDK typecheck 状态另见本报告最后的补充；没有全产品构建或启动 App。

## 测试仍缺的证据

- 现有 `PresentationHistoryRegressionTests` 验证 5min 降采样范围/extrema、显式 Gap、segment、8 来源版本限制和独立版本曲线；它们不涵盖 SwiftUI equatable wrapper、本地选点或实际墙钟调整后的显示。
- 最小后续 UI 检查：图表有数据时点选一个 point，记录 selection 文本；保持图形数据相同而让显示 anchor offset 改变，确认坐标与 selection 时间同步；切换 range/来源再点选，确认新的 series/version/Gap 被展示。这些应使用正式 Release App，不用 Python 模型/AX 元素存在代替真实交互。
- Root 提供的正式 Release build/sign/upstream 和 ShortUI 130s PASS 属于 Root 的实测，本 agent 未独立执行；补丁后需新的 Release 回归。
- 5min 数据填充到完整范围后的性能对比、五档各 600s、OS sleep/wake、72h 均仍 pending。1Hz 可能减少查询/渲染负载只是实现依据，不是实测性能通过。

## 所审源码 SHA256
- `App/AppSessionRuntime.swift`：`913571a8143a7f9d11a159139c0b06da8ef182df51a7dc9e334acceedea8357b`
- `App/AppDelegate.swift`：`03e1aecc50ec491da4d9da8a5080e1cf8122cc013ed7836f599eaec999034f74`
- `App/Presentation/HistoryChartView.swift`：`ac86aec31e6ad455ff39849fe3081f7744e2c89f7b1d0c2ac7df769ed6fb0488`
- `App/Presentation/TemperatureDashboard.swift`：`28399dded4080211019322ab0f28ba4910b4968b6a55144a364387daed294cf3`
- patch 后 HistoryChartView：`472ca0f36c225f6772c414c3edfb382f88d5fc6e0e243d51431d3650ae97df4a`

## 单 View Swift 6 typecheck 补充

最终 target `arm64-apple-macos15.0`、Swift 6、当前 Xcode macOS SDK、缓存的 Core/Presentation module，`swiftc -typecheck` 检查 `/tmp/w11-chart-anchor-equality-green.swift` 退出 0、无诊断。首次误用 target14 因 Core 最低 macOS15 被拒绝，修正目标后通过；没有改变生产代码以规避诊断，没有 link/fullbuild/启动 App。

原始命令与结果：`/tmp/w11-chart-anchor-equality-typecheck.json`。
