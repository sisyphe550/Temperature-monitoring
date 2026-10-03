# 会话、诊断、构建与分发

更新：2026-10-03；实施契约v1族修订3。本轮按[课程范围](course-delivery-scope.md)交付本机ad-hoc Release App，最小收尾进行中；公证/公开发行/跨机为可选扩展，不阻塞当前目标。

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

## 当前本机交付与可选发行

| 产物 | 可执行条件 | 不能声称的事 |
|---|---|---|
| 当前本机课程App | 完整Core≥80%、必要回归、正式App短测/资源观察、ad-hoc签名及五criterion证据 | 不能声称Developer ID公证、旧全132资格或全部Air支持 |
| 可选正式独立分发ZIP | Developer ID Application证书/Team ID、公证凭证及最终发行配置实机复测 | 只有实际Accepted/staple/spctl通过才声明公证；未执行不阻塞本机交付 |

本机脚本先签worker再签App，采用ad-hoc身份；不宣称Developer ID或Hardened Runtime发行资格。可选公开发行格式选ZIP、手动更新，关闭App Sandbox，Developer ID签名启用Hardened Runtime；worker与App同Team，不依赖`--deep`掩盖嵌套签名错误。参考[Apple公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。

维护者在本机Keychain或CI secrets提供`DEVELOPER_ID_APPLICATION`、`APPLE_TEAM_ID`及名为`temperature-monitor-notary`的notarytool Keychain profile；禁止将私钥/密码写进仓库。本轮不要求这些凭证；本机App与实际验证报告完成后可交付。若未来启动可选正式发行，缺凭证时标为未执行，不能伪造证书。

## 平台与来源发布清单

每次本地候选和正式ZIP都生成同名机器可读清单，四类字段分别记录，禁止用一个“兼容版本”字符串混合：

| 字段 | 必需内容 | 证据来源 |
|---|---|---|
| `build_toolchain` | Xcode、Swift编译器、SDK完整版本及构建主机系统 | `xcodebuild -version`、`swiftc --version`、`xcrun --show-sdk-version` |
| `deployment_target` | `MACOSX_DEPLOYMENT_TARGET`、架构及最终App/worker的LC_BUILD_VERSION | 构建设置与`otool -l`结果 |
| `runtime_profile` | profile版本、机型标识、最低OS、固定CPU成员定义 | 打包资源及启动检查 |
| `qualified_combinations` | App/worker SHA、签名身份、机型、OS版本/build、测试集合与结果 | W09/W10正式App实机报告；CLI原型不得写入 |

清单同时列源码SHA、schema/contract/profile版本、配置hash和[third-party-v1.json](contracts/third-party-v1.json)的hash。App资源中的ThirdPartyNotices必须覆盖contract中每个copied/modified条目的版权与许可；未登记实际本地路径、缺许可或notice不一致时构建失败。研究manifest只说明检查过的上游，不得代替实际导入清单。

## 本机构建与启动

```sh
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 build/TemperatureMonitor.app
bash scripts/launch-app.sh
```

build-app.sh构建Release App与worker，复制当次Products/Release到`build/TemperatureMonitor.app`、嵌入worker/契约/许可资源并ad-hoc签名。记录源码及App/worker SHA、工具链/系统/profile和实际短测；本轮App/worker签名与复用边界通过，实际路径与SHA见[课程报告](validation/course-delivery/2026-10-03-5984b9e/README.md)。launch-app.sh采用标准LaunchServices打开/重开，无fixture或测试专用UI参数。

## 可选发行命令契约

既有`scripts/package-release.sh`保留以下Developer ID/公证路线；只有未来明确启动公开发行时执行：

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

可选Developer ID发行配置需另按适用严格范围验证来源、五档、sleep/wake、退出/权限及平台矩阵；本轮本机ad-hoc短测不被要求补全这些公开发行用例。协议与UI只标实际观察证据等级；同型号不同OS build仍需登记该组合。

## 历史目标机型资格矩阵

以下是旧严格资格矩阵：`qualified_combinations` 在**同一 App/worker SHA** 完成 sources、schedules、lifecycle 三套实机套件后登记。本轮课程criterion证据独立记录本机范围，不把局部短测改写成上述三套完整passed。2026-09-23 维护者决定**取消 ≥73h endurance 长跑**作为 W09 门禁；`endurance` 套件保留为可选诊断工具，不写入 `qualified_combinations`。

| 机型 | OS build | 证据 SHA | sources | schedules | lifecycle | endurance | 签名 |
|---|---|---|---|---|---|---|---|
| Mac16,13 | 24G419 | `14cac6f…` | passed | passed | passed | cancelled（维护者豁免） | ad-hoc |

历史`qualified_combinations` 已登记：`72339d42…` / `83e14d5e…`，suites=`[sources, schedules, lifecycle]`。该记录只适用于对应历史产物，不表示当前候选已取得资格。历史证据目录见 `docs/validation/product-hardware/Mac16,13-24G419/14cac6fe3b365ff36bf6c5c7e795dffc7319cf73/`。

## 当前收尾与历史身份

当前W09同一次正式App短测执行五档短切换（同次观察已填充的五分钟历史，五档短切换）、最近5分钟图与资源/响应观察、标准启动/历史/关窗重开/正常退出；无压力负载、物理sleep或长跑。必要软件生命周期/退出/残留清理回归保留，72小时历史功能不变。W10交付本机ad-hoc App，W11依五criterion及11的外部门禁完成授权merge commit后停止。

[7124归档](validation/product-software/W11/2026-10-03-7124dc1/README.md)保留App SHA eae5c0b46776eebfa7a297cae46ac0a0d08ad833fa574230897d2ee54da35651、Worker SHA 12356c172d67e4d6161543aa86a6a0616d5133e3121ac91bd0f9cb6e03c78c96与当次Mac16,13/macOS15.7.3/24G419环境；[f0软件归档](validation/product-software/W11/2026-10-03-f0a7dde/README.md)记录测试同步，生产/构建输入相对7124不变。当前新短测/资源和最终二进制身份仍须本轮另录，不继承旧结果。

[c354原长测](validation/product-software/W11/2026-10-03-c354b03/README.md)的FAILED suite/duration观察/not_measured性能及[f9修复](validation/product-software/W11/2026-10-03-f9e850c/README.md)保持历史。旧逐REQ100accepted/31pending/1waived/2retired不批量改为PASS；取消严格长测、公证或跨机门槛不等于它们通过，也不声明未测试系统兼容。
