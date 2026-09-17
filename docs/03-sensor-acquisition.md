# 传感器采集与接口可行性

更新日期：2026-09-17。状态：需求已确认；首台 M4 Air 已取得部分接口证据；语义与兼容范围未冻结。

## 范围与证据边界

产品范围为 Apple Silicon MacBook Air。首台实测为 15 英寸 M4 MacBook Air（Mac16,13），macOS 15.7.3 (24G419)。不能把 MacBook Pro、Mac mini 或 M4 Pro 上的结果外推为 M4 Air 已通过。

本次讨论完成了官方资料、开源代码和本机 SDK 检查。SDK 检查使用 **macOS 15.5 SDK**，它证明对应声明在该 SDK 中存在，不证明目标 macOS 15.7.3 或以后版本上一定返回数据。

## 2026-09-15 首轮证据

- 普通用户 uid/euid=501、Release 命令行原型可打开 AppleSMC，枚举 2,147 个键，取得候选温度；HID 返回 47 个温度服务。
- NVMe SMART 可读取温度字段；原型曾因提前销毁插件导致端口失效，已按 Issue #2 修复并回归。
- IOPowerSources 没有返回 Temperature 字段；HID 返回多个同名 gas gauge battery 候选来源，不进行平均或去重。IORegistry 同名字段单位保持未知。
- CPU Package 与物理 Core 映射、真实刷新频率、跨机型／版本兼容性仍未证实。

完整读数、来源状态与五档计时见 [验证报告](validation/2026-09-15-m4-air/validation-report.md)。

## 接口路线

| 指标／接口 | 已知事实 | 首选验证动作 |
|---|---|---|
| CPU 温度 | 没有在本次核查中找到满足 Package 和逐核摄氏温度需求的稳定公开接口 | 枚举 AppleSMC 与 HID 温度来源 |
| `ProcessInfo.thermalState` | 返回 nominal/fair/serious/critical 等系统热状态，不能换算成摄氏温度 | 可作诊断辅助，不替代温度 |
| `IOPMGetThermalWarningLevel` | 返回系统热警告等级，不是 CPU 温度计 | 不作为主温度来源 |
| AppleSMC | 开源实现通过 IOKit 调用读取传感器键 | 检查连接、键类型、数值单位和可用性 |
| HID 温度事件 | 部分开源项目使用温度服务和未公开声明 | 检查目标系统是否暴露服务及相关读取权限 |
| SSD | Apple 定义 `IONVMeSMARTInterface` 与 `NVMeSMARTData.TEMPERATURE` | 发现服务、创建接口、调用 `SMARTReadData` 或相应日志读取入口，验证温度字段 |
| Battery | `IOPSKeys.h` 定义 `kIOPSTemperatureKey` | 从 `IOPowerSources` 电源描述字典检查字段存在性、类型、单位和返回值 |
| IORegistry Battery 属性 | 通用 IORegistry 访问 API 公开，但具体驱动属性需要单独判断稳定性 | 公开电源描述不能取得数据时，评估其作为候选回退路径 |
| IOReport／powermetrics | 可辅助研究系统遥测；不应预设存在稳定逐核温度输出 | 仅在需要比较或补充证据时研究 |

公开的 IOKit 通用调用机制不等于其承载的 SMC 命令、传感器键和语义都属于公开契约。不得将“在代码中能声明”当作公开 API 的证明。

主要来源：[Apple 热状态](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)、[SSD 接口](https://developer.apple.com/documentation/iokit/ionvmesmartinterface)、[SSD 温度字段](https://developer.apple.com/documentation/iokit/nvmesmartdata/3521284-temperature)、[Apple 电源键定义](https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h)、[macmon 源码](https://github.com/vladkens/macmon/blob/main/src_lib/sources.rs)。

## Battery 纠错

C02 中“IOPSKeys.h 没有温度 key”的说法已被纠正。正确字段为 `kIOPSTemperatureKey`，宏值为 `Temperature`；本次查阅头文件注释写明摄氏度。

这不证明 M4 内置电池实际返回该字段，也不表示 IORegistry 中同名字段采用相同单位。单位转换必须随具体来源记录，不能看到 `Temperature` 就统一除以 100 或套用某个经验公式。

## 指标身份

- CPU Package：必须确定是一个有据可查的硬件读数，还是经确认的派生指标。平均值／最大值不能无说明地继续标为物理 Package 温度。
- CPU Core：只有存在足够映射证据才建立 core ID；传感器枚举序号不等于核心编号。
- 同一传感器可能经多条路径暴露；去重和来源切换规则见 OQ-03。
- 源码中的传感器名称仅是项目映射。温度对负载的相关性和其他软件一致性不能独立证明逐核拓扑。[Stats 映射](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)
- 标识设计建议包含来源、原始 key、机型、映射版本；具体持久化字段见 [数据设计](04-data-storage.md)。

## 采样与时间语义

| 对象 | 当前工作基线 | 状态 |
|---|---|---|
| CPU 类指标 | 50 / 100 / 200 / 500 / 1000 ms，默认 200 ms | 用户已确认 |
| SSD | 500 ms | 接受“不低于 500 ms”方案后的 v0.3 默认细化 |
| Battery | 1000 ms | 接受“不低于 1000 ms”方案后的 v0.3 默认细化 |

以上必须区分目标请求间隔、实际调用间隔、驱动刷新间隔、UI 刷新间隔。Apple 普通定时器不提供严格实时保证。[Timer](https://developer.apple.com/documentation/foundation/timer)

推荐记录调用开始／结束时间、实际观测时间、请求周期、数据源更新时间（若存在）。算法用单调时间差；展示与历史查询保留日历时间。两类时钟关系、休眠与校时规则见 OQ-08。

相同读数不证明缓存；不同读数不证明准确度。没有源时间戳或更新序号时，将数据新鲜度标为未知。Raw 是应用取得的读数，不能承诺为传感器内部刚产生的原始测量。

## 权限与兼容性

普通用户、候选最终构建配置下首先验证。站外分发使 App Sandbox 成为可选项，但不会自动获得驱动权限、解除系统限制或保证私有接口稳定。实际需要的权限由测试决定。

兼容性按“Air 机型／芯片／尺寸＋macOS 版本与 build＋构建配置＋指标”记录。最新正式版在发布冻结时重新核实，不沿用旧对话中的固定版本号。新增 Air 机型不自动继承兼容声明；最低系统要求也不表示所有新机都能安装该最低版本。

## 失败与能力不足

分别记录：硬件不存在、接口不支持、权限不足、映射未知、读取暂时失败、无效值、超时。重试参数沿用 [故障设计](06-error-handling.md)。哪些失败必须退出、哪些仅使某项不可用，尚待 OQ-05 决定。

首轮验证步骤见 [初步验证方案](14-feasibility-validation.md)。

## 2026-09-17 参考实现整合

固定来源、冲突和路线见 [19](19-reference-informed-design.md)，全部已记录来源见 [M4 候选表](research/2026-09-17-m4-source-candidates.md)。Stats 的12个 M4 CPU 热区候选在本机均可解码，但本机只有10个物理核心；不采用其 Core 编号作为物理映射。TCMz/TCMb 进入下一轮重点验证；TPMP/Ts1P 因项目间命名冲突保持未知。

推荐启动时发现来源并建立注册表，周期任务只读活动集合；缓存类型与大小信息，重连或唤醒后重建。SMC CPU、NVMe SMART、IOPS／电池候选分别选择来源，禁止将 NAND channel、SSD proximity 和 composite 合并成同一语义。HID 同名实例保持分离。

常规采集优先一个已验证主来源；诊断模式才并行对照。来源集合改变必须创建新指标定义版本并断开历史；只有已证明语义等价时才可保留用户可见指标名称，否则连名称／语义也应更改。主 CPU 指标及附件可选化属于 RC-01/03 提案，尚未变更已确认要求。
