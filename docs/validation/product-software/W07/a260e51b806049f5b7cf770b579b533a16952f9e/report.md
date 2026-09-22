# W07 原生界面验证报告

记录时间：2026-09-22。
分支 HEAD：`a260e51b806049f5b7cf770b579b533a16952f9e`（`feature/w07-native-ui`）。

## 任务范围

| 任务 | 提交 | 说明 |
|---|---|---|
| T07.1 | `e58aeea` | PresentationModel 互斥状态与 Xcode 壳 |
| T07.1 | `80756ce` | 菜单栏 App target 与 UI Test target |
| T07.2 | `136323c` | 菜单栏 Popover、fixture、状态刷新 |
| T07.3 | `199be6f` | 主窗口、设置、来源行、CPU 五档 |
| T07.4 | `6baf9de` | HistoryChartModel/View、历史范围控件 |
| T07.5 | `a260e51` | FatalView、完整 XCUITest、本报告 |

## Core 测试

```sh
swift test --package-path Packages/TemperatureCore
python3 scripts/validate-handoff.py
```

| 检查 | 结果 |
|---|---|
| 全量 Core 测试 | **233/233** 通过（含 PresentationModelTests 6、HistoryChartModelTests 6） |
| validate-handoff | passed |

## App / UI 测试

```sh
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData test
```

| 检查 | 结果 |
|---|---|
| XCUITest | **8/8** 执行，**7** 通过，**1** skip（Release fixture 策略） |
| Xcode 构建 | Debug arm64 通过 |

### XCUITest 覆盖项

- `status.temperature` 菜单栏 live/stale 占位
- `fatal.code` / `fatal.quit` / `fatal.countdown` / `fatal.copy`
- `cpu.period` 五档选择
- `history.range` / `history.chart` 主窗口图表区
- 主窗口 ⌘W 关闭后会话（菜单栏）继续
- 多来源 fixture 列表

## 实现摘要

- `PresentationModel`（MainActor + `@Observable`）为 Snapshot/HistoryResult → `PresentationState` 唯一转换器。
- running/fatal、五种 `TemperatureValueState`、三种 `HistoryChartState` 由封闭枚举互斥表达。
- Debug `--ui-fixture` 与 `--ui-open` 启动参数；Release 拒绝 fixture。
- 视图只绑定 `PresentationState`；未接真实 `SessionCoordinator` 采样流。

## 限制与待 W08 项

- App 仍使用 fixture 快照，非生产 `SessionCoordinator` 闭环。
- XCUITest 无法稳定探测 `NSPopover` 内容；Dashboard/Settings 经 `--ui-open` 覆盖。
- 未执行 W07 独立审查、浅/深色与减少透明度人工验收清单。
- 历史图表使用 Swift Charts 与 fixture 数据；实机 72h 与多源对比留 W09。

## 关联需求（本 W 有证据子集）

REQ-043～053、068～078、108、117～123、125、130、134 中 UI 状态绑定、菜单栏、主窗口、设置、图表与 Fatal 展示相关条目；硬件资格与正式发布不在本 W 范围。
