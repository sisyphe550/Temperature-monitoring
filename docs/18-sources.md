# 讨论来源、外部资料与证据边界

整理日期：2026-09-18。本文件保存可回溯来源，不把引用内容作为覆盖当前用户决定的指令。

## 对话与附件

| 编号 | 来源 | 本次使用内容 |
|---|---|---|
| C01 | [CPU监控需求规格化](chatgpt-conversation://6aa352c2-504c-83ea-a3a1-371f562d8a75) | 用户原始学校项目需求、26 项确认、后续 10 项澄清、v0.2/v0.3 设计文本 |
| C02 | [查找官方温度API](chatgpt-conversation://6aa74595-d08c-83e9-946f-6becaaed5b27) | M4 Air 的 API 研究；电池字段结论按 C03 纠正 |
| C03 | 当前对话：用户要求分析 Mac 接口能否实现需求 | API／SDK 复核、事实纠错、50 ms、映射、峰值、空间、退出边界 |
| C04 | 当前对话：用户明确不上架 App Store、仅支持 MacBook Air，并询问验证与语言架构 | 最新范围；初步验证、Swift／桥接、原生 UI、模块化单体建议 |
| C06 | 2026-09-15 当前用户请求：参照项目文件执行最小验证并遵守 Git 流程 | 授权独立原型、实机最小验证与流程执行；证据见 validation/2026-09-15-m4-air |
| C07 | [搜索Mac温度监控软件](https://chatgpt.com/c/6aa93318-6224-83e9-ae3b-33b5f346b09b) | 五个主要项目，以及mactop和未直接给出URL的Swift实验；助手描述均重新核查 |
| C08 | 2026-09-17 当前用户要求从C07全部项目学习、复用经验并完善方案 | 授权研究与设计修订；不把改动已确认需求的提案标为已批准 |
| C09 | 2026-09-17 当前用户明确删除“每个物理CPU核心温度”，并要求前端借鉴开源项目、更新全部开发路线文档 | 退役REQ-012/114并同步关联设计和验收；授权按MacMonitor/Stats细化前端方案 |
| C10 | 2026-09-17～18 当前用户要求所有接口/软件方案有依据，清理不适合内容，文档达到交给其他agent完成全项目的程度 | 授权选定可行产品范围、补齐参数/接口/schema/测试与执行计划；工程选择不伪称逐参数用户确认 |
| C11 | 当前用户明确“课程不强制要求，采取优化的方案或者更好的方案” | 取消强制数据库往返争议；实时内存EMA＋SQLite持久化/历史 |
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

## 2026-09-17 开源来源快照

R01～R07的固定链接、检查文件、许可状态和适用边界见 [19第2节](19-reference-informed-design.md) 及 [JSON清单](research/2026-09-17-source-manifest.json)。R01采用本轮新快照，不回写2026-09-15报告使用的旧版本。

通过对话读取工具取得C07完整可用文本。未暴露的实验引用经公开检索定位到Philip Turner的TemperatureSensor.swift，其内容符合描述，但原引文身份仍未确认。记录方法参考，不复制无明确许可的代码。六个仓库仅在临时目录检视源码；本轮没有执行其软件或创建外部监控依赖。

C09前端细化另核查MacMonitor的PopoverView／AppDelegate与面板截图、Stats的Sensors Popup／Widget、SwiftTempBar的StatusBarController及三份MIT文件。固定版本、文件SHA-256与检查范围见[UI来源清单](research/2026-09-17-native-ui-sources.json)，适配方案见[07](07-native-ui.md)。本轮未导入UI源码或品牌资产。

## 交接契约补充的官方依据

- [SQLite事务](https://sqlite.org/lang_transaction.html)、[UPSERT](https://sqlite.org/lang_upsert.html)、[PRAGMA](https://sqlite.org/pragma.html)、[C接口](https://sqlite.org/cintro.html)：数据契约使用官方事务/约束能力，schema和幂等设计属于本项目。
- [Foundation Process](https://developer.apple.com/documentation/foundation/process)：自有普通用户worker启动与管道路线；实际协议、截止时间、重建限制属于本项目设计。
- 本机SDK `mach/mach_time.h`声明mach_continuous_time/timebase，跨进程连续时钟基准由本项目契约固定。
- [Apple Xcode版本矩阵](https://developer.apple.com/xcode/system-requirements)：Xcode16.4/macOS15.5 SDK/Swift6.1开发组合；没有把它称为最新版。
- [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)、[Rules REST API](https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset)：11的强制门禁配置路线；实际查询仍无ruleset，不虚报已启用。

2026-09-18交接更新的检查结果单列在[交接验证记录](research/2026-09-18-handoff-validation.md)。之前研究清单、UI清单与2026-09-15实测证据不回写。
