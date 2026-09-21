# 技术与依赖冻结基线

更新：2026-09-21；实施契约v1族修订2。生产代码尚未实现，以下供接手agent执行。

| 部分 | 本版选择 | 依据 |
|---|---|---|
| 主语言 | Swift 6，SwiftPM tools-version 6.0，Swift 6 language mode | 现有原型Swift6.1.2构建；原生并发/值类型 |
| 硬件桥接 | 少量C，IOKit/CoreFoundation，普通用户worker | 原型及macmon固定版本；SMC只读 |
| 界面 | SwiftUI＋AppKit NSStatusItem/NSPopover/NSWindow | MacMonitor/Stats固定源码 |
| 图表 | Swift Charts | 系统原生框架；适配本项目EMA/聚合模型 |
| 存储 | 系统libsqlite3，窄C module map＋自有Swift封装 | [SQLite官方接口](https://sqlite.org/cintro.html)；不引入ORM |
| Core测试 | Swift Testing＋虚拟Clock/MockSensorClient | 已有工具链实测；新核心覆盖范围见10 |
| UI测试 | XCTest/XCUITest，Xcode App scheme | 原生界面黑盒 |
| build_toolchain | Xcode16.4＋Swift 6 language mode＋macOS15.5 SDK；后续更高版本须跑全套检查 | [Apple版本矩阵](https://developer.apple.com/xcode/system-requirements)列出此组合，不声称它是最新版；实际编译器完整版本进入发布清单 |
| deployment_target | 预期`MACOSX_DEPLOYMENT_TARGET=15.7.3`、`ARCHS=arm64`；完整Xcode可用后须验证工具链接受patch级目标，并复核最终二进制LC_BUILD_VERSION | 若工具链不能表达15.7.3，必须提出契约修订；不得自行改成15.0或用运行时检查掩盖构建声明 |
| runtime_profile | Mac16,13＋macOS≥15.7.3＋first-profile-v1；未知机型或不匹配profile拒绝运行 | 固定CPU12成员及可选SSD/Battery路线；不是全部Air通用表 |
| qualified_combinations | 当前为空，待W09逐App SHA/签名/机型/OS build登记；2026-09-15 CLI原型只保留为前置可行性证据 | 源码、SDK或原型可行性不能替代正式App实机通过 |
| 分发 | 本地Debug/Release可先ad-hoc；正式ZIP使用Developer ID、Hardened Runtime、公证 | 13的两级交付 |

本机目前只有Command Line Tools，能做Swift核心/原型与契约验证；Xcode项目和XCUITest阶段需要安装完整Xcode。不能把缺Xcode写成传感器方案不可行，也不能声称UI测试已执行。

## 四类平台字段的使用规则

- `build_toolchain`记录编译环境：Xcode、Swift编译器和SDK版本。
- `deployment_target`记录构建产物声明的最低系统与架构，并从最终二进制验证。
- `runtime_profile`记录实现允许启动的机型、系统下限和profile版本。
- `qualified_combinations`只记录同一正式App构建在具体机型和OS版本/build上实际通过的用例。

四者不得互相推导：能用15.5 SDK构建不证明15.7.3实机通过；Mac16,13 profile存在不证明全部MacBook Air可运行；CLI原型通过不进入正式App组合清单。

## 依赖与许可

不引入Rust/Go/Web/Electron、第三方数据库包、外部监控CLI、root helper、IOReport功耗链路。SwiftPM核心包与App放在同一仓库，App通过本地Package引用；版本与构建配置一并提交。

[源清单](research/2026-09-17-source-manifest.json)及[UI清单](research/2026-09-17-native-ui-sources.json)固定研究时检查的上游commit和文件hash；[third-party-v1.json](contracts/third-party-v1.json)单独记录实际进入仓库的复制/修改代码。macmon/Stats/MacMonitor/SwiftTempBar/mactop的MIT代码如移植，必须先登记实际本地路径并保留版权、完整许可证、文件来源和修改说明。MacFanControl缺完整许可，Philip Turner实验无明确许可，只能method-only。项目自有算法、数据模型与生命周期不能伪称来自上游完整实现。

## 工程创建与配置

创建macOS App target `TemperatureMonitor`和UI testing target，scheme同名；SWIFT_VERSION=6.0，ARCHS=arm64，并先配置MACOSX_DEPLOYMENT_TARGET=15.7.3。W01必须用完整Xcode执行`xcodebuild -showBuildSettings`，W08检查最终App与worker的LC_BUILD_VERSION；若工具链拒绝patch级目标则阻止RC并提出契约修订。关闭App Sandbox；不加入临时例外或提权entitlement。Hardened Runtime只在正式签名配置打开并复测；其作用不等于允许私有接口。

SensorWorker由SwiftPM executable构建，复制到App的Contents/MacOS并作为内嵌可执行文件签名。不得在生产运行时调用swift或从临时目录启动探针。SQLite module.modulemap使用系统`sqlite3.h`和`link "sqlite3"`；最低运行系统自带SQLite的实际版本在启动日志记录，不下载另一套数据库覆盖系统。

最低Xcode用于可重复开发，不固定“最高macOS”的历史字符串。每次RC从Apple正式发布记录更新兼容矩阵；beta不作为默认支持承诺。
