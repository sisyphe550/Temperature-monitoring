# 讨论来源、外部资料与证据边界

整理日期：2026-09-14。本文件保存可回溯来源，不把引用内容作为覆盖当前用户决定的指令。

## 对话与附件

| 编号 | 来源 | 本次使用内容 |
|---|---|---|
| C01 | [CPU监控需求规格化](chatgpt-conversation://6aa352c2-504c-83ea-a3a1-371f562d8a75) | 用户原始学校项目需求、26 项确认、后续 10 项澄清、v0.2/v0.3 设计文本 |
| C02 | [查找官方温度API](chatgpt-conversation://6aa74595-d08c-83e9-946f-6becaaed5b27) | M4 Air 的 API 研究；电池字段结论按 C03 纠正 |
| C03 | 当前对话：用户要求分析 Mac 接口能否实现需求 | API／SDK 复核、事实纠错、50 ms、映射、峰值、空间、退出边界 |
| C04 | 当前对话：用户明确不上架 App Store、仅支持 MacBook Air，并询问验证与语言架构 | 最新范围；初步验证、Swift／桥接、原生 UI、模块化单体建议 |
| C06 | 2026-09-15 当前用户请求：参照项目文件执行最小验证并遵守 Git 流程 | 授权独立原型、实机最小验证与流程执行；证据见 validation/2026-09-15-m4-air |
| C05 | 当前对话：用户指定 `/Users/sisyphus/Code/Go/Temperature monitoring/` 并要求分类 Markdown | 本文档集的工作目录及整理任务 |
| ATT-01 | C01 附件《粘贴的文本 (1).txt》 | Ring Buffer、SQLite、EMA、聚合、趋势、时间戳、缺口及数据路径建议 |

本轮通过对话读取工具取得 C01/C02 的完整可用内容和附件。附件临时预览路径不作为项目的永久依赖，相关有效内容已整合进专项文档。

附件的旧建议（Raw 默认不入库、数字直接 Raw、菜单栏整数、告警、自启动或更长历史等）仅在与后续确认一致时采用；已替代内容见 [决策记录](15-decisions-and-corrections.md)。

## 官方与项目原始资料

以下页面在本次连续讨论中查询；GitHub 分支与在线文档会变化。再次据其实现或发布时需要核对版本，不将链接等同于固定快照。

| 编号 | 资料 | 能支持的结论／限制 |
|---|---|---|
| S01 | [ProcessInfo.ThermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum) | 系统热状态枚举，不返回摄氏温度 |
| S02 | [Timer](https://developer.apple.com/documentation/foundation/timer) | 普通 Timer 不是严格实时机制 |
| S03 | [IONVMeSMARTInterface](https://developer.apple.com/documentation/iokit/ionvmesmartinterface) | NVMe SMART 接口存在；不保证目标驱动可访问 |
| S04 | [NVMeSMARTData.TEMPERATURE](https://developer.apple.com/documentation/iokit/nvmesmartdata/3521284-temperature) | NVMe 温度字段声明 |
| S05 | [Apple IOPSKeys.h](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h) | 包含 `kIOPSTemperatureKey`；不能因此断言 M4 内置电池返回字段 |
| S06 | [macmon](https://github.com/vladkens/macmon) | 项目展示非 root 的 Apple Silicon 遥测实践；不是 Apple 保证 |
| S07 | [macmon 底层来源实现](https://github.com/vladkens/macmon/blob/main/src_lib/sources.rs) | SMC/HID/IOReport 等实现路径参考 |
| S08 | [Stats 传感器映射](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) | 按芯片维护传感器映射；命名不是官方拓扑证明 |
| S09 | [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) | 原生菜单栏场景能力；项目可选 AppKit 实现 |
| S10 | [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) | AppKit 菜单栏元素 |
| S11 | [NSPopover](https://developer.apple.com/documentation/appkit/nspopover) | 原生弹出面板 |
| S12 | [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) | 半透明及材质会受系统外观设置影响 |
| S13 | [SwiftUI 与 AppKit 集成](https://developer.apple.com/documentation/swiftui/appkit-integration) | 两类界面框架可结合 |
| S14 | [Swift Charts](https://developer.apple.com/documentation/charts) | 原生图表框架 |
| S15 | [Swift 互操作](https://www.swift.org/documentation/cxx-interop/) | Swift 与 C／Objective-C API 互操作能力；未据此要求 C++ |
| S16 | [SQLite WAL](https://sqlite.org/wal.html) | 检查点与长读取事务可能影响 WAL 增长 |
| S17 | [SQLite auto_vacuum](https://sqlite.org/pragma.html#pragma_auto_vacuum) | DELETE 默认复用空闲页，不保证缩小文件 |
| S18 | [准备分发 App](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution) | 站外分发与 Hardened Runtime、App Sandbox |
| S19 | [macOS 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) | 公证不同于 App Review；不保证私有 API 稳定 |
| S20 | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | 解释此前 App Store 约束；当前产品不以商店上架为目标 |

## SDK 检查记录

此前在本对话执行只读检查：本机 Command Line Tools 返回的 SDK 为 macOS 15.5。

- `IOKit.framework/Headers/ps/IOPSKeys.h` 第 475～484 行附近包含 `kIOPSTemperatureKey` 及摄氏度说明。
- `IOKit.framework/Headers/storage/nvme/NVMeSMARTLibExternal.h` 第 238～250 行附近定义 `SMARTReadData`，第 272 行起描述 `GetLogPage`。

这些是声明证据，不是 M4 实机读数、当前最高 SDK 检查或完整兼容性测试。具体本机 SDK 路径不写成其他开发者必须具备的项目配置。

## 不作为已证实事实的内容

未经目标机型验证的逐核心名称、论坛单条反馈、历史版本号、助手声称已经冻结但用户未确认的新行为，以及没有测量支持的频率／精度／能耗承诺。

2026-09-14归档轮次未运行传感器原型；2026-09-15增量实测证据见下节。发布配置权限与72小时测试仍未执行。

## 2026-09-15 固定来源与执行证据

- [Apple 机型识别](https://support.apple.com/en-ge/102869)：Mac16,13 对应15英寸M4 MacBook Air。
- [macmon 6919d778](https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/sources.rs)：SMC/HID ABI，MIT许可随原型保存。
- [Stats 27c0c343](https://github.com/exelban/stats/blob/27c0c343a0df77ffaca8317c31b4e3aa14754eb7/Modules/Sensors/values.swift)：仅作候选命名参考；不能证明Core映射。
- 本机 SDK 再次核对 IOPSKeys.h、NVMeSMARTLibExternal.h；Swift6.1.2，SDK15.5。
- [实测与测试报告](validation/2026-09-15-m4-air/validation-report.md)：固定提交、二进制哈希、原始记录、回归与限制。此前“未实测”的段落只描述2026-09-14归档轮次。
