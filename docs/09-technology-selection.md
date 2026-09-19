# 技术与依赖冻结基线

更新：2026-09-17；C10工作基线v1。生产代码尚未实现，以下供接手agent执行。

| 部分 | 本版选择 | 依据 |
|---|---|---|
| 主语言 | Swift 6，SwiftPM tools-version 6.0，Swift 6 language mode | 现有原型Swift6.1.2构建；原生并发/值类型 |
| 硬件桥接 | 少量C，IOKit/CoreFoundation，普通用户worker | 原型及macmon固定版本；SMC只读 |
| 界面 | SwiftUI＋AppKit NSStatusItem/NSPopover/NSWindow | MacMonitor/Stats固定源码 |
| 图表 | Swift Charts | 系统原生框架；适配本项目EMA/聚合模型 |
| 存储 | 系统libsqlite3，窄C module map＋自有Swift封装 | [SQLite官方接口](https://sqlite.org/cintro.html)；不引入ORM |
| Core测试 | Swift Testing＋虚拟Clock/MockSensorClient | 已有工具链实测；新核心覆盖范围见10 |
| UI测试 | XCTest/XCUITest，Xcode App scheme | 原生界面黑盒 |
| 开发工具基线 | Xcode16.4＋macOS15.5 SDK；后续更高版本须跑全套检查 | [Apple版本矩阵](https://developer.apple.com/xcode/system-requirements)列出此组合，不声称它是最新版 |
| 部署目标 | arm64，MACOSX_DEPLOYMENT_TARGET=15.7.3 | 用户目标；运行时再核对OS与Air profile |
| 分发 | 本地Debug/Release可先ad-hoc；正式ZIP使用Developer ID、Hardened Runtime、公证 | 13的两级交付 |

本机目前只有Command Line Tools，能做Swift核心/原型与契约验证；Xcode项目和XCUITest阶段需要安装完整Xcode。不能把缺Xcode写成传感器方案不可行，也不能声称UI测试已执行。

## 依赖与许可

不引入Rust/Go/Web/Electron、第三方数据库包、外部监控CLI、root helper、IOReport功耗链路。SwiftPM核心包与App放在同一仓库，App通过本地Package引用；版本与构建配置一并提交。

[源清单](research/2026-09-17-source-manifest.json)及[UI清单](research/2026-09-17-native-ui-sources.json)固定上游commit和文件hash。macmon/Stats/MacMonitor/SwiftTempBar/mactop的MIT代码如移植须保留版权、完整许可证、文件来源和修改说明。MacFanControl缺完整许可，PhilipTurner实验无明确许可，仅参考方法不复制代码。项目自有算法、数据模型与生命周期不能伪称来自上游完整实现。

## 工程创建与配置

创建macOS App target `TemperatureMonitor`和UI testing target，scheme同名；SWIFT_VERSION=6.0，ARCHS=arm64。关闭App Sandbox；不加入临时例外或提权entitlement。Hardened Runtime只在正式签名配置打开并复测；其作用不等于允许私有接口。

SensorWorker由SwiftPM executable构建，复制到App的Contents/MacOS并作为内嵌可执行文件签名。不得在生产运行时调用swift或从临时目录启动探针。SQLite module.modulemap使用系统`sqlite3.h`和`link "sqlite3"`；最低运行系统自带SQLite的实际版本在启动日志记录，不下载另一套数据库覆盖系统。

最低Xcode用于可重复开发，不固定“最高macOS”的历史字符串。每次RC从Apple正式发布记录更新兼容矩阵；beta不作为默认支持承诺。
