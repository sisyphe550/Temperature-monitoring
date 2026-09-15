# 技术选型建议

更新日期：2026-09-14。状态：SQLite、原生 macOS 和本地部署已确认；编程语言及具体框架组合为推荐方案。

## 推荐组合

| 部分 | 推荐 | 选择原因／状态 |
|---|---|---|
| 主语言 | Swift | 与原生系统、界面、并发和测试整合；尚未指定 Swift 小版本 |
| 传感器边界 | Swift，必要时少量 C／Objective-C | 声明 IOKit 函数、结构体及未公开接口；桥接范围受控 |
| 主窗口／设置 | SwiftUI | 原生声明式界面 |
| 菜单栏／弹出面板 | AppKit `NSStatusItem`／`NSPopover` | 控制菜单栏与窗口行为 |
| 图表 | Swift Charts | 折线、柱状与范围展示 |
| 存储 | SQLite | 已确认；是否采用 Swift 封装库仍待 OQ-14 |
| 架构 | 模块化单体；UI 层 MVVM | 当前最适合已讨论的本地单机范围 |
| 并发组织 | Swift Concurrency＋专用后台执行环境 | 同步硬件／存储调用不阻塞界面 |
| 开发环境 | Xcode | 编译、调试、签名及原生 UI 测试 |
| 测试 | Swift Testing／XCTest | 具体职责与版本在工具链冻结时决定 |
| 协作 | Git＋GitHub Actions | 分支、Issue、门禁由工作流文档定义 |
| 分发 | Developer ID＋Hardened Runtime＋公证 | 独立分发建议；不代表已经有证书或完成公证 |

Swift 可直接与 C／Objective-C API 互操作；SwiftUI 可与 AppKit 双向集成。[Swift 官方互操作资料](https://www.swift.org/documentation/cxx-interop/)、[Apple AppKit 集成](https://developer.apple.com/documentation/swiftui/appkit-integration)

## 已比较的方案

| 方案 | 优点 | 代价／结论 |
|---|---|---|
| 全 Swift | 语言一致、调试和构建集中 | 部分低层结构与声明需要维护；可以作为起点 |
| Swift＋少量 C／Objective-C | 将低层细节封装在窄边界 | 增加桥接，但范围较小；当前推荐 |
| Swift＋Rust | 可复用某些遥测实现 | 增加 FFI、错误传播和构建维护；当前没有足够证据需要引入 |

路径 `/Code/Go/` 不构成 Go 技术选型。项目没有选择 Web/Electron、Docker 数据库或远端后端，也不因监控工具中存在 HTTP 输出就加入本项目。

## 选型纪律

- 底层路线由 M4 Air 实测决定，不能先按语言偏好宣称所有指标可读。
- 库版本和最低工具链版本需冻结后记录；不在本轮编造最新 Xcode／Swift 版本。
- 开源实现仅作路线与映射参考；实际复用代码前检查对应版本许可证及依赖。
- 普通用户权限首先验证；是否需要辅助进程、XPC 或额外授权由证据决定。
- App Sandbox 对站外分发为可选项；Hardened Runtime 与 App Sandbox 是不同机制。公证不提供传感器兼容保证。[Apple 分发说明](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)

来源：C01、C03、C04。[来源](18-sources.md)
