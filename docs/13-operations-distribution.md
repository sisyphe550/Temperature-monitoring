# 会话、诊断、构建与分发

更新：2026-09-23；实施契约v1族修订3。正式签名凭证是外部发布输入，不阻塞本地App开发。

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
| 正式独立分发ZIP | 前项＋Developer ID Application证书/Team ID＋公证凭证＋最终配置实机复测 | 不能以CLI或Debug结果代替正式构建权限验证；**2026-09-23 维护者豁免**：本项目以本机 ad-hoc App 为交付目标，不要求公证 ZIP |

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

正式构建重跑来源、五档、sleep/wake、无网络本地运行、双实例、退出清理、日志不可写及平台矩阵验收。协议与UI只标实际观察证据等级；同型号不同OS build仍需登记该组合。

## 历史目标机型资格矩阵

`qualified_combinations` 在**同一 App/worker SHA** 完成 sources、schedules、lifecycle 三套实机套件后登记。2026-09-23 维护者决定**取消 ≥73h endurance 长跑**作为 W09 门禁；`endurance` 套件保留为可选诊断工具，不写入 `qualified_combinations`。

| 机型 | OS build | 证据 SHA | sources | schedules | lifecycle | endurance | 签名 |
|---|---|---|---|---|---|---|---|
| Mac16,13 | 24G419 | `14cac6f…` | passed | passed | passed | cancelled（维护者豁免） | ad-hoc |

历史`qualified_combinations` 已登记：`72339d42…` / `83e14d5e…`，suites=`[sources, schedules, lifecycle]`。该记录只适用于对应历史产物，不表示当前候选已取得资格。历史证据目录见 `docs/validation/product-hardware/Mac16,13-24G419/14cac6fe3b365ff36bf6c5c7e795dffc7319cf73/`。

## 2026-10-03 本机验收刷新记录

- 最高正式稳定 macOS：**27.0.1**，Apple于2026-09-28发布；2026-10-03核对[Apple安全性更新列表](https://support.apple.com/en-us/100100)与[Developer发布记录26A434](https://developer.apple.com/news/releases/?id=09282026c)。[机器记录](validation/product-software/W11/2026-10-03-403d44b/latest-stable-macos.json)保留查询日期和出处。本机仍15.7.3/24G419；该版本核对不构成27.0.1运行认证。
- 上述14cac6f资格矩阵是历史结果。PR44合入main403d44b后，a97正式App只有五档8秒等短测证据；当时五档各10分钟与真实系统睡眠/唤醒尚未完成；最新c354 duration与物理sleep跳过见后续条目，不能延用历史passed为当前资格。
- 2026-10-03合盖长测在第一档未满600秒时中断，随后发现睡眠历史刷新误Fatal（#46）与runtime Fatal退出卡住（#47）。新修复必须重新构建正式App并绑定新源码/二进制hash。
- 历史长测冻结的受测生产源码为`c354b0392a91367d42708d7424fd0e133af825b9`，正式Release App SHA256=`9f786ee330531d2d194ef2c88f04c83c314de3253a1e218ea45df12f5aeabc3c`，worker SHA256=`74b44d0617c4524e6cf24024ad48e64304b56b8f0b18c459ad8c364c7f8cb59f`；本机仍Mac16,13/15.7.3/24G419。[短测](validation/product-software/W11/2026-10-03-403d44b/anchor-release-short-ui/14-Release-real-hardware-short-acceptance.txt)已执行五档各8秒、主窗历史/图表点选、关闭重开和正常退出清理；[runtime Fatal记录](validation/product-software/W11/2026-10-03-403d44b/anchor-release-runtime-fatal/result.json)证明该产物的实际自动退出与会话清理，均不替代五档600秒或真实系统睡眠。
- c354五档清醒时长条件已分别observed：50/100/200/500ms原phase各约601秒；1000ms在同一App/worker/Session连续区间经独立clock、Cua与末端SQL补证641.637秒。原XCTest因最后一档AX控件缺失仍为FAILED，不能改suite通过。精确scheduler skipped、读批p95/p99及首帧/屏幕显示p95仍not_measured，性能门槛不变。用户2026-10-03 08:00UTC明确“跳过休眠测试”，本轮三轮物理睡眠/人工唤醒验收仅标skipped-by-user；已经触发的两次attempt观察保留partial，生命周期功能和软件回归继续保留。原始记录见[c354不可变归档](validation/product-software/W11/2026-10-03-c354b03/README.md)与[user-scope](validation/product-software/W11/2026-10-03-c354b03/user-scope.json)。不得登记sources+schedules+lifecycle整套passed或把W11标完成；后续Issue #50修复的新产物f9已完成独立软件门禁与正式短测，见[新产物记录](validation/product-software/W11/2026-10-03-f9e850c/README.md)，不能继承该c354长测为新产物性能资格。

### 当前交付候选f9e850c

新App SHA256=`7bf8d21dcd825497484573ec57b79d773b3cb933e0e708791b3641a5d799722c`；worker SHA256=`d0b6d7dbc08299b292dccc6e7076f494ce18366d5c5b0d7c3ba602c79b040b65`；本机环境未变。349/55软件回归、89.01%覆盖与149.485秒正式短测分别归档。未登记整套qualified combination，五档精确性能仍未测；本轮物理sleep用户已跳过。PR26保留Draft，未满足零blocking和全部验收条件，不能合并。
