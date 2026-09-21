# V0 只读传感器探测原型

这是 [初步验证方案](../../docs/14-feasibility-validation.md) 的探索性产物，不是生产应用或全部 V0 验收。原型保留以便复现实测；进入产品前需重新设计接口、取消／超时、权限、映射、发布配置与测试。

## 构建与测试

本机验证工具链：Apple Swift 6.1.2、macOS 15.5 SDK、Command Line Tools。使用内置 Swift Testing，无第三方包依赖。仅使用该工具链实测，不宣称所有 Swift 6.0 工具链通过。

在仓库根目录执行：

```sh
swift test --package-path prototypes/sensor-probe --enable-code-coverage
python3 scripts/check-probe-coverage.py
swift build --package-path prototypes/sensor-probe -c release
python3 scripts/test-probe-cli.py
prototypes/sensor-probe/.build/release/sensor-probe --intervals 50,100,200,500,1000 --seconds 60 --output validation-runs/example
python3 scripts/summarize-probe.py validation-runs/example
```

`--seconds` 是每档时长，默认 10 秒；默认 CPU 档位 200 ms。输出目录必须不存在，防止覆盖旧证据。工具按当前用户权限运行。Codex 工具沙箱可能禁止硬件访问；沙箱外运行不等于 root。不能从沙箱中的失败判断普通用户在 macOS 上无法读取。

## 输出与口径

- `capabilities.json`：环境、二进制 SHA-256、Git 提交／工作树状态、接口状态、原始 ID／类型／数值、单位证据、映射限制。Git 字段取调用目录，复现时必须从仓库根目录运行。
- `sampling-results.csv`：每次读取的目标时刻、开始／结束单调时间、读取前墙钟、原始值、候选摄氏值、返回状态。硬件更新时间为空；重试次数为 0，本轮不实现产品重试策略。
- `timing.csv`：每组批次的实际开始／结束、调度延迟。`read_end-read_start` 含墙钟格式化、接口读取与解码；批次耗时含行序列化、不含批次文件写入。不是纯内核调用耗时。
- `summary.json`：每档请求机会数、实际批次、漏采、读数计数与资源开销。某来源不存在时不建立该组；能力缺失与漏采分开。
- `analysis.json`：脚本从 CSV 重算统计，校验汇总计数。中位数按通常定义计算，p95 使用 nearest-rank；跨档不计算相邻间隔。

每档单调时钟从零开始，目标窗口为 `[0, seconds)`，初次机会为 0。串行读取；结束一次读取后跳过已经错过的目标机会，不积压补采。漏采数为目标机会数减已启动批次数。CPU／SSD／电池周期独立，底层调用和文件写入共用串行线程，故仍可能互相延迟。最后一次批次完成后等待到观察窗口结束；完全没有来源时立即记录空结果，实际耗时另报。

CPU 候选筛选为 SMC `Te*`／`Tp*` 和 HID `eACC*`／`pACC*`；筛选受开源命名启发，不是物理核心清单。所有 `T*` SMC 键和 HID 温度服务都进入枚举证据；未归组来源只做初始快照。SSD SMART 与 HID NAND 候选每 500 ms 读取，IOPowerSources 与 HID 电池候选每 1000 ms 读取。

## 必须保留的限制

- `finiteReadings` 仅表示解码得到有限数字，不是物理有效率或计量准确度。0、负值和同值重复保留，未知哨兵值不自行设阈值过滤。
- CPU Package、物理 Core ID、HID 重名来源归并、硬件刷新频率仍未验证。HID 索引／NVMe 索引／电源索引只用于本次进程。
- SMC/HID 使用未公开的协议或声明。NVMe SMART 使用本机公开 SDK 声明。Apple 通用 IOKit API 的公开性不代表 SMC 键语义有官方保证。
- 电池 IORegistry 的同名 `Temperature` 仅保存原始值，单位未知，不沿用 IOPowerSources 的摄氏度注释。
- 原型无 App Sandbox、无签名公证验收；同步驱动调用没有强制取消／超时，故 `--seconds` 不是驱动阻塞时的退出上限。必要时由操作者终止进程，残留 CSV 只是部分证据。
- CPU 为本进程 user＋system 时间 / 实际墙钟时间，一个逻辑核 100%；RSS 是本进程启动以来高水位。两者不含外部驱动／系统代理成本，也不证明持续资源有界。
- CI 的 80% 覆盖门槛仅统计 `Sources/ProbeCore`（解码、输入校验、CSV 转义、调度数学）。硬件桥接与 CLI 通过实机和黑盒验证，不在该数字分母中。不能用它宣称产品采集边界或全部核心模块已达到 REQ-092。

## 来源与许可

SMC/HID ABI 参考 [macmon 6919d778](https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/sources.rs)，MIT 许可保存在 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.md)。实现仅保留只读操作。

[Stats 27c0c343 映射](https://github.com/exelban/stats/blob/27c0c343a0df77ffaca8317c31b4e3aa14754eb7/Modules/Sensors/values.swift) 仅用于候选命名对照，没有据此认定拓扑或移植产品代码。NVMe 插件生命周期与 SDK 的 COM/IOKit 接口所有权核对；先释放 SMART interface，再销毁 plugin。
