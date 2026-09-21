# 会话、诊断、构建与分发

更新：2026-09-21；实施契约v1族修订2。正式签名凭证是外部发布输入，不阻塞本地App开发。

## 标识与目录

工作产品名`TemperatureMonitor`，Bundle ID=`io.github.sisyphe550.TemperatureMonitor`，版本从0.1.0开始，build number由提交计数或CI单调编号生成并记录SHA。可以在发布前由维护者改名，但必须统一App、worker、目录、测试及签名配置。

- 会话：`~/Library/Application Support/io.github.sisyphe550.TemperatureMonitor/Sessions/<sessionUUID>/monitor.sqlite`。
- 实例锁：上级应用目录`instance.lock`，用`flock(LOCK_EX|LOCK_NB)`持有FD直到退出。第二实例只提示已有运行实例并退出，不能清理活跃数据。
- 日志：`~/Library/Logs/io.github.sisyphe550.TemperatureMonitor/monitor.jsonl`。
- 报告：日志目录下`Reports/<UTC时间>-<错误码>-<UUID>.json`。
- 每会话有包含bundleID/sessionID/schemaVersion的marker；启动残留清理必须取得锁、检查marker、拒绝符号链接与越界路径，只处理本应用Sessions子目录。

## 生命周期

启动：平台/profile检查 → 获取锁 → 清理带marker的残留会话 → 建新库quick_check/schema → 启worker与来源定义 → 开始采样/UI。数据库文件默认用户私有权限，日志同样仅当前用户可写。

休眠：暂停新日程、停止worker并终结在途、记录Gap、闭合可完成窗口、刷新队列。唤醒：连续时间已前进，重发现产生新源实例/定义/段，推进父层窗口并清理TTL，再恢复；没有数据的长睡眠不补样本、不生成空桶。

正常退出/⌘Q：停止调度 → 处理或终结在途 → 闭合部分窗口/停止加工 → 交付已接纳队列 → 关闭查询与写入连接 → 删除本会话DB/WAL/SHM及marker目录 → 释放锁。预算5秒，不能完成记录原因；下次启动补清理。关闭主窗口/⌘W只隐藏窗口，保持会话与菜单栏运行。

强杀/断电不能保证退出钩子。日志与错误报告独立保留；不跨启动恢复监控历史。当前活动库损坏/schema冲突走Fatal，不能自动清空后伪装连续运行。

## 诊断保留与入口

结构化JSONL，每文件5MiB，最多5个文件；超过14天清理。报告最多20份、单份1MiB、14天TTL。采样正常路径不逐条写诊断日志，按60秒汇总计数；原始证据导出仅用于显式验证运行并有独立目录。

设置中提供“打开日志文件夹”“开源许可”；Fatal窗口提供“打开报告”“复制错误详情”“退出”。没有自动上传、联网更新、高温通知或登录自启动。报告写失败使用OSLog/stderr与可复制文本，保留原始错误码，不递归报错。

## 两级交付

| 产物 | 可执行条件 | 不能声称的事 |
|---|---|---|
| 本地可运行App | 完整Xcode、Core/Runtime/UI测试、ad-hoc签名、已测试本机能力 | 不能声称Developer ID公证或全部Air支持 |
| 正式独立分发ZIP | 前项＋Developer ID Application证书/Team ID＋公证凭证＋最终配置实机复测 | 不能以CLI或Debug结果代替正式构建权限验证 |

正式格式选ZIP，手动下载与替换App，不实现自动更新。关闭App Sandbox，正式签名启用Hardened Runtime；worker与主App同一Team，先签worker再签App，不依赖`--deep`掩盖嵌套签名错误。参考[Apple公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

维护者在本机Keychain或CI secrets提供`DEVELOPER_ID_APPLICATION`、`APPLE_TEAM_ID`及名为`temperature-monitor-notary`的notarytool Keychain profile；禁止将私钥/密码写进仓库。未提供时交付本地App和测试报告，正式发布任务标为等待凭证，不能伪造证书。

## 平台与来源发布清单

每次本地候选和正式ZIP都生成同名机器可读清单，四类字段分别记录，禁止用一个“兼容版本”字符串混合：

| 字段 | 必需内容 | 证据来源 |
|---|---|---|
| `build_toolchain` | Xcode、Swift编译器、SDK完整版本及构建主机系统 | `xcodebuild -version`、`swiftc --version`、`xcrun --show-sdk-version` |
| `deployment_target` | `MACOSX_DEPLOYMENT_TARGET`、架构及最终App/worker的LC_BUILD_VERSION | 构建设置与`otool -l`结果 |
| `runtime_profile` | profile版本、机型标识、最低OS、固定CPU成员定义 | 打包资源及启动检查 |
| `qualified_combinations` | App/worker SHA、签名身份、机型、OS版本/build、测试集合与结果 | W09/W10正式App实机报告；CLI原型不得写入 |

清单同时列源码SHA、schema/contract/profile版本、配置hash和[third-party-v1.json](contracts/third-party-v1.json)的hash。App资源中的ThirdPartyNotices必须覆盖contract中每个copied/modified条目的版权与许可；未登记实际本地路径、缺许可或notice不一致时构建失败。研究manifest只说明检查过的上游，不得代替实际导入清单。

## 发布命令契约

W08先实现`scripts/build-app.sh`，产物`build/TemperatureMonitor.app`；W10实现`scripts/package-release.sh`，包装以下顺序：

```sh
xcodebuild -project TemperatureMonitor.xcodeproj -scheme TemperatureMonitor -configuration Release -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" build/TemperatureMonitor.app/Contents/MacOS/SensorWorker
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" build/TemperatureMonitor.app
codesign --verify --deep --strict --verbose=2 build/TemperatureMonitor.app
ditto -c -k --keepParent build/TemperatureMonitor.app build/TemperatureMonitor.zip
xcrun notarytool submit build/TemperatureMonitor.zip --keychain-profile temperature-monitor-notary --wait
xcrun stapler staple build/TemperatureMonitor.app
spctl --assess --type execute --verbose=2 build/TemperatureMonitor.app
ditto -c -k --keepParent build/TemperatureMonitor.app build/TemperatureMonitor-notarized.zip
```

构建脚本必须从DerivedData的Products/Release复制App到上述路径，并嵌入同一构建的worker与资源；路径不存在就失败，不能继续给旧包签名。最终ZIP与App生成SHA-256及上一节完整发布清单。上传分发属于后续用户发布操作，本轮只定义方案。

正式构建重跑来源、五档、sleep/wake、无网络本地运行、双实例、退出清理、日志不可写、72小时及平台矩阵验收。协议与UI只标实际观察证据等级；同型号不同OS build仍需登记该组合。
