# 硬件接口交接审计与首个采集配置

审计日期：2026-09-17；交接同步：2026-09-18。审计基线：仓库 `21fc962`、下列固定上游版本、2026-09-15 已存证据。**本轮只读源码和旧记录，未运行上游程序、施加负载或新增硬件测量。** 本文的选择规则是可直接实现的项目设计；产品范围、重试预算和发布门禁以 [代理实施交接](../00-agent-handoff.md) 为准。

## 1. 结论与证据分层

CPU、SSD、Battery 都有具体读取路线，可以开始实现。无需等待物理核心映射或外部温度计校准，前提是名称明确表达“来源分类／固定集合计算值”，而不是宣称物理 Package、逐物理核心、全芯片绝对最高温或计量精度。SMC/HID 的私有协议风险通过平台配置、能力检查和不可用状态管理，不转换成提权需求。

| 标记 | 含义 | 不能据此宣称 |
|---|---|---|
| E1 | 目标机器实际取得的已存读数／错误：Mac16,13、M4、macOS 15.7.3 (24G419)、普通用户、沙箱外 Release CLI | 正式 App 已验收、全部 Air 可用、物理位置或准确度已校准 |
| E2 | 固定上游代码的实现、分类与解码方法；或指定 SDK 的接口声明 | 上游的其他机器测量就是本机结果；SDK 有字段就一定有返回值 |
| D | 本项目固定源集合、优先级、派生公式、错误处理和验证门槛 | 已实现或已测通过 |

保留原证据中的 `decoded_mapping_unverified`，不回写为 `verified`。开发配置可保存 `unitEvidence=upstream_celsius`、`semanticEvidence=upstream_cpu_region`；这足以说明采用依据，但不同于物理语义或计量校准。`flt ` 本身只说明数字编码；必须与固定键表的温度分类共同使用，不能把任意浮点值当成 °C。

## 2. 接口到实现的完整路线

原型目录为 `prototypes/sensor-probe/Sources/`。表中函数已存在；`SourceRegistry` 等生产构件尚待实现，不应误写成已经可调用的库。

| 对象 | 现成入口／真实底层调用 | 证据／实施边界 |
|---|---|---|
| SMC 建连 | `SensorBridge/SensorBridge.c`：`sp_smc_open`；`IOServiceGetMatchingServices("AppleSMC")` → 名称 `AppleSMCKeysEndpoint` → `IOServiceOpen(..., type=0)` | E1 普通用户成功。对未知机型不猜测其他 endpoint，不要求 root |
| SMC 元数据与读取 | `sp_smc_read`；`IOConnectCallStructMethod` selector=2，command=9 取 KeyInfo，command=5 取值 | E1 成功。生产版增加 KeyInfo 缓存；连接 generation 改变就失效。原型每读一键都会重取元数据 |
| SMC 研究枚举 | `sp_smc_key` command=8；`#KEY` 为 `ui32` 大端数量 | E1 枚举 2,147 键。生产固定配置无需每 tick 枚举全部键；全量枚举只用于诊断 |
| SMC 数字解码 | `ProbeCore/ProbeCore.swift`：`Decode.smc(type:bytes:)` | E1＋E2；只支持下节明确编码。未知类型报错，不猜测 |
| CPU 域分类 | [Stats M4 表](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/Modules/Sensors/values.swift#L442-L455)；原型 `Hardware.smcReading` | E2 分类＋E1 读取。生产固定12键，移除原型 `Te* || Tp*` 全前缀入选规则 |
| Battery SMC | 同一 SMC 连接，固定 `TB1T`、`TB2T`、`TB0T` | E1 初次枚举成功；E2 Stats 与 MacMonitor 有温度分类。不是电芯数量／编号证明 |
| Battery IOPS | `Hardware.swift`：`batteryDescriptions`、`discoverBattery`；`IOPSCopyPowerSourcesInfo` → `IOPSCopyPowerSourcesList` → `IOPSGetPowerSourceDescription` | E1 本机字段缺失；E2 SDK 提供 `kIOPSTemperatureKey`。生产先以 `kIOPSTypeKey == kIOPSInternalBatteryType` 选内置电池，不能持久化数组下标 |
| SSD SMART | `sp_nvme_open` → `sp_nvme_read`；`IOBlockStorageDevice` → `NVMe SMART Capable` → `IOCreatePlugInInterfaceForService` → `QueryInterface(kIONVMeSMARTInterfaceID)` → `SMARTReadData` | E1 600次成功。只读 NVMe composite temperature；不需要 Identify、序列号、SMARTEnable 或 ATA 路线 |
| HID 备用／诊断 | `sp_hid_open`、`sp_hid_name`、`sp_hid_read`；动态解析 IOKit 符号，温度事件15、字段 `15 << 16` | E1 47服务，目标机没有 eACC/pACC CPU 服务；E2 有读取与分类路线。首个配置不启用自动 CPU/HID 回退 |
| 机型／系统 | 原型 `SensorProbe/main.swift` 已用 `sysctl -n hw.model`、`sw_vers` 等记录环境；App 可用 `sysctlbyname`、`ProcessInfo.operatingSystemVersion` 并单独保存 `kern.osversion` | 不以物理CPU数推导源数量；只有配置允许的平台才激活其固定键表 |
| 采样时刻 | 原型使用 `DispatchTime.now().uptimeNanoseconds`，日历时间另存；生产采用单调时钟驱动周期并独立记录 wall time | 请求间隔、完成时间、源更新时间分开。没有源时间戳时 freshness=unknown |

公开 IOKit 函数承载未公开 SMC/HID 协议，不表示整个链路是 Apple 承诺稳定的温度 API。初版只读，不增加风扇控制、SMC 写入、powermetrics、IOReport、管理员助手或常驻第三方 CLI。

## 3. 可实现的首个配置：`Mac16,13-m4-v1`

### 3.1 平台与 CPU 固定集合

目标机型 `Mac16,13`，芯片 M4；已测系统只包括 `15.7.3 / 24G419`。其他 build 可进入显式“未验收配置”诊断，不自动获得兼容声明。正式支持范围另由发布矩阵扩展。构建基线为 arm64、普通用户、App Sandbox 关闭；尚须正式 App 权限与签名测试。

| E2 分类 | 固定键，大小写不可改变 | E1 已存周期样本 |
|---|---|---:|
| CPU E域温度来源 | `Te05`、`Te0S`、`Te09`、`Te0H` | 每键2,279条 |
| CPU P域温度来源 | `Tp01`、`Tp05`、`Tp09`、`Tp0D`、`Tp0V`、`Tp0Y`、`Tp0b`、`Tp0e` | 每键2,279条 |

本次静态检查 `sampling-results.csv.gz` 得到合计27,348条上述来源记录，均为 `decoded_mapping_unverified`；12键也均存在于 `capabilities.json` 的初始快照，类型均为 `flt `。本机物理CPU数量为10，不能生成12个“物理核”。[Stats FAQ](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/README.md#sensors-show-incorrect-cpugpu-core-count) 对其名称的解释也是热区，而非物理核心。

首版选择算法（D）：

1. 根据机型与配置版本选中上述列表，不按数值最大、名称相似或 `T*` 自动扩大集合。
2. 开连接，依次读取12键的 KeyInfo 和一批值；本配置要求 `flt `、4字节、有限数字。源记录保存原始字节与类型、E2出处和E1记录引用。
3. 12键全部合格才激活 `cpu.zone.max`：公式为本批12个读数的最大值；用户名称为“CPU 热区最高温度”，详情注明“12个固定来源的最大值，分类依据 Stats M4 表”。它不是硬件单一传感器、物理Package或全芯片绝对热点。
4. 来源列表按 E／P域展示原始键；不显示“Core 1…12”。每源 Raw 与派生指标分别标识，派生值不能伪装成第13个硬件来源。
5. 任一必需成员缺失、类型变化、错误或非有限值，本批派生指标缺失；不得用11个剩余成员重算，也不得插入0或旧值。成功的成员可保留自己的 Raw，但不能补成完整主指标。
6. 启动时集合不完整：`profile_source_missing`／`unsupported_encoding`，CPU核心能力不可用。暂时读取错误按统一有限重试规则恢复；恢复失败进入CPU关键故障流程。需兼容子集时另建配置和指标定义版本，并重新验收；不能在运行时静默删成员。
7. 切换成员、公式、provider 或映射版本，创建新 definitionVersion 和连续段；即使界面短名称相同，也不跨定义计算EMA或连接趋势。

算法各档按50/100/200/500/1000ms请求，默认200ms；该频率不是硬件产生新测量的保证。每批保留首个成员开始到最后成员完成的跨度；跨度合格阈值见实施交接的调度契约。跨重试的旧成员不得拼进新批以掩盖时间差。

### 3.2 为什么不首选 `TCMz`／`TCMb`

E1：二者在初始快照解码为76.046875和44.818958；没有进入原有五档周期采样，不能称已有持续响应验证。

E2：[MacMonitor `SENSORS.md`](https://github.com/ryyansafar/MacMonitor/blob/2fff106238e17e318f1b48775034c461f6464257/SENSORS.md#1-temperature-sensors-smc) 将二者描述为CPU die相关，该文明确实测对象是 M2 Air；其“热点／最快响应／精度”评价不能转为M4实测。其 [`IOReportWrapper.m`](https://github.com/ryyansafar/MacMonitor/blob/2fff106238e17e318f1b48775034c461f6464257/Macmonitor/IOReportWrapper.m#L697-L707) 直接读 `TCMz`。另一个项目把 `TCMb` 标为 CPU motherboard，存在更细物理语义分歧：[MacFanControl 映射](https://github.com/sak0a/MacFanControl/blob/e5afaeb51da6d80ac6e26e0bdef7503cceebb7e6/Sources/MacFanControlCore/Sensors.swift#L123-L141)。

D：二者列入诊断，显示“SMC TCMz／TCMb”；不加入首版12键集合，不作为CPU故障自动替代，不据其单次最大值选择“更准确”的来源。`TPMP`、`Ts1P` 的跨项目冲突同样保留，不扩大CPU域。macmon 的 `Tp/Te/Ts` 前缀归类、MacMonitor 的 `Tp/Te/Ts0` 归类是E2实现差异，不是本项目自动扩表规则。

### 3.3 Battery：具体来源优先级与单位

启动发现顺序（D）：**内置电池 IOPS Temperature → `TB1T` → `TB2T` → `TB0T` → 不可用**。IOPS只有在内置电池身份唯一、字段为CFNumber且有限时入选；没有字段并不是驱动错误。本机E1为字段缺失，因此按此规则应选择 `TB1T`。所有候选失败时 Battery 为可选能力不可用，不阻塞CPU。

- `TB1T`／`TB2T`：E2 [Stats Apple Silicon 表](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/Modules/Sensors/values.swift#L503-L509) 明确归为 Battery 温度。
- `TB0T`：E2 [MacMonitor 电池表](https://github.com/ryyansafar/MacMonitor/blob/2fff106238e17e318f1b48775034c461f6464257/SENSORS.md#system--board) 将 `TB0T`～`TB2T`归为电池温度；其测试对象是M2，保留来源等级，不将数字后缀解释为本机电芯编号。
- E1 三键初始值分别为23.599991、23.599991、22.599991，均 `flt `；原有周期数据中三键均无记录。初值相同不证明别名。
- `flt `／4字节：按小端组成 UInt32，解释为IEEE754 Float32，再转Double。数值按固定温度键的E2语义直接解释为°C，不除以100，不减273.15。原型 `Decode.smc` 已实现。
- `sp78`／2字节：通用解码器按**大端、有符号**Int16／256；但首个目标配置只接受E1已观察的 `flt `。遇到编码变化应报配置不匹配，不能仅因为通用解码器能解析就默默升级兼容性。
- IOPS：macOS15.5 SDK `IOPSKeys.h` 的 `kIOPSTemperatureKey` 是CFNumber、单位C，直接读摄氏数字。IORegistry `AppleSmartBattery.Temperature=2968` 是不同接口，不继承IOPS单位，不参与首版温度。

每次发现固定一个主来源，不平均三键或六个HID服务。SMC选择后的显示名称带来源，例如“电池温度 · TB1T”。活动来源临时失败先按统一重试；耗尽后标为不可用，每60秒最多一次恢复探测，总共最多3轮，且只探测同一活动来源；探测成功后须连续3次本周期读数有效才恢复显示，并开始新定义／连续段。3轮都失败后本会话停止探测，不自动改选低优先级来源。睡眠恢复／应用重启触发新发现时可以重选；换来源必须创建新definitionVersion、清空EMA并断开曲线，不隐式回切。IOPS与SMC尚未证明测量位置等价，故换源详情必须同时更新。

### 3.4 SSD：SMART composite，不混入邻近温度

`sp_nvme_open/read` 已有目标机E1成功路线；SDK头文件为 `IOKit/storage/nvme/NVMeSMARTLibExternal.h`，公开入口见 [IONVMeSMARTInterface](https://developer.apple.com/documentation/iokit/ionvmesmartinterface)。`SMARTReadData` 返回 `NVMeSMARTData`；读取 `TEMPERATURE` 后 `CFSwapInt16LittleToHost`，0表示未报告，其他值按 `Double(kelvin)-273.15`。原型 `Decode.nvme` 已实现，不复制其他软件整数截断或负数钳制方式。

生产发现时仅选择唯一明确识别的内置NVMe服务。具体路线：在 `IOBlockStorageDevice` 读取 `kIOPropertyProtocolCharacteristicsKey` 对应字典，以 `kIOPropertyPhysicalInterconnectLocationKey == kIOPropertyInternalKey` 判定内置；必要时沿 `IORegistryEntryGetParentEntry(..., kIOServicePlane, ...)` 有界向上查找。常量定义在macOS15.5 SDK `IOStorageProtocolCharacteristics.h`。该身份补充属于D，原E1未记录内外部属性；实施时必须保存其发现证据。0个合格服务为不可用，多个合格服务或属性未知为 `identity_ambiguous`，不自动选择数组第一个。

用 `IORegistryEntryGetRegistryEntryID` 给当前连接实例记录身份；重新发现不能仅凭 `device:0` 认定同一设备，不能把服务索引、BSD名或Registry ID当作跨重启永久ID。首版不采硬盘序列号。可借鉴 [Stats `getSMARTDetails`／`getNVMeSMART`](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/Modules/Disk/readers.swift#L555-L613) 的服务树查找与插件创建；使用SDK定义和本项目已回归的释放顺序。

轮询500ms；SMART失败只使SSD不可用。`TH0x`、`TH0T`、`T5SP`、`NAND CH0 temp`保留独立研究名称，不作为SMART composite回退，不接续同一历史。

## 4. HID：有读取路线，但不是本机自动CPU回退

真实链路见原型 `SensorBridge.c:85–140` 及固定 [macmon `IOHIDSensors`](https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/sources.rs#L1023-L1108)：

```text
dlopen(IOKit) → 检查所有所需dlsym
IOHIDEventSystemClientCreate → SetMatching({PrimaryUsagePage:0xff00, PrimaryUsage:5})
CopyServices → 每个service读取Product → CopyEvent(service,15,0,0)
IOHIDEventGetFloatValue(event,15<<16) → 检查事件与有限值 → CFRelease(event)
```

- E2 macmon把返回数字直接作为摄氏数值；不可再次除65536或100，也不可套NVMe Kelvin转换。此为所选上游事件解释，不能给任意同名IORegistry属性授予摄氏单位。
- CPU域只考虑有明确E2分类的 `eACC MTR Temp Sensor`、`pACC MTR Temp Sensor`，见 [macmon `get_temp_hid`](https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/metrics.rs#L412-L439)。本机E1不存在这些服务，因此HID不能成为本配置CPU兜底。`PMU tdie/tdev`不等于CPU传感器，`PMU2`也不等于GPU。
- E1有六个同名 `gas gauge battery` 服务，初次枚举位置16、24、26、33、42、44；还有位置30的 `NAND CH0 temp`。位置只是旧进程索引，不可写进未来配置作为永久身份。
- 生产诊断可从macOS15.5 SDK声明的 `IOHIDServiceClientGetRegistryID` 取得CFTypeRef，检查CFNumber类型后记录；它是Get返回值，不擅自CFRelease借用引用。调用已持有的service引用时才有效。不能证明跨发现身份一致时分配新sourceInstanceID。
- `Product`相同不合并；HID客户端／服务数组重建后索引失效，旧闭包不能继续读新数组的同下标。
- 符号缺失、NULL事件和非有限返回值分别记录 `unsupported_symbol`、`event_absent`、`nonfinite`，均不生成0或旧值；不采用上游“0到150°C”的通用过滤作为计量证明。
- 上游手写私有C声明并非稳定SDK ABI。尤其不要把四参数 `CopyEvent` 的最后一个0擅自解释成可取消的毫秒timeout；有的上游称timeout，但这不能建立本项目的取消契约。初版诊断保持已测试的调用形式，正式启用前进行目标构建回归。

首个配置不将HID列为自动回退；HID接口仍可独立实现和测试，未来新增已验收配置后再启用。这样“暂无目标CPU服务”是确定能力结果，而不是无限等待某个不存在接口的开发阻塞项。

## 5. ABI、所有权与线程约束

### SMC

- 沿用C桥接结构布局，不从Swift随意重排结构。原型有 `_Static_assert(sizeof(SMCRequest)==80)`、`offsetof(SMCRequest,bytes)==48`；生产保留并增补必要的field offset检查。
- 输出缓冲区大小必须恰好等于请求结构；返回IOReturn成功后还要检查SMC `result`。数据长度必须≤32且与所选encoding完全一致；失败时输出缓冲区不得当作测量。
- FourCC是区分大小写的4个ASCII字节；键整数按高位到低位组成。值字节编码独立：不能把键的大端规则套到 `flt ` 上。
- 每条连接只允许一个进行中的调用链；CPU和SMC Battery即使周期不同也共享串行保护。KeyInfo缓存属于connectionGeneration，关闭、唤醒重连、接口失效后清空。
- 先阻止新工作，再等正在进行的调用结束，最后 `IOServiceClose`。不能与在途同步调用竞争关闭来“取消”。

### NVMe

- 使用SDK的 `IONVMeSMARTInterface **`、`NVMeSMARTData` 和对齐定义，不自行复制一个“看起来相同”的结构。生产C桥接保留 `sizeof(NVMeSMARTData)==512`、`offsetof(NVMeSMARTData,TEMPERATURE)==1` 的静态断言；本次仅用 `clang -fsyntax-only` 在macOS15.5 SDK核对这两条断言，通过且未调用硬件。
- **plugin必须活到所有SMART调用结束。** 原型实测过早 `IODestroyPlugInInterface` 会产生 `MACH_SEND_INVALID_DEST (0x10000003)`；这是已修复的 Issue #2，不能在重构时重新引入。
- 关闭顺序：停止派发并结束在途读取 → `(*interface)->Release(interface)` → `IODestroyPlugInInterface(plugin)` → 清空指针。中途失败的部分初始化对象也须按拥有关系释放。
- `IOIteratorNext`、`IORegistryEntryGetParentEntry` 返回的IO对象要逐个 `IOObjectRelease`；创建的CF属性要 `CFRelease`；不要混用IO对象与CF对象的释放函数。

### HID／Swift跨层

- `CopyServices`数组拥有service元素；数组活到最后一个使用者结束。若service脱离数组独立存储，要建立明确retain所有权。所有Copy/Create对象按取得的所有权释放，借用Get结果不额外释放。
- release事件／服务数组 → release客户端 → 最后 `dlclose`；函数指针及对象使用期间不能卸载库。只有确认无在途调用才销毁。
- 原型 `Sensor.read` 捕获 `[unowned self]`，只适用于Hardware保证活到闭包最后一次调用的当前同步流程。生产不可把这类闭包排入生命周期更长的任务；用有明确owner的Provider句柄／序列化executor，并在stop完成后才释放。

## 6. 超时与取消：必须实现真实边界

`IOConnectCallStructMethod`、`SMARTReadData` 和当前HID读取链为同步调用；已有原型没有证明可中断正在执行的调用。`Task.cancel()`、丢弃future或定时器先返回只改变应用任务状态，不等于取消驱动调用。有限重试只有在上一调用真正结束后才能开始。

**首版固定采用普通用户权限、随App打包的自有 `SensorWorker` 子进程。** 进程内软超时仅为本轮早期评估的替代方案，不是当前可选实现路线。

1. 主App用Foundation `Process`按绝对路径启动 `Contents/MacOS/SensorWorker`，不经shell，不使用root服务或第三方CLI。`Pipe`承载stdin/stdout一行UTF-8 JSON，单帧最多1MiB；异步持续读取stdout与有界stderr，避免管道写满阻塞。
2. 同时最多一个在途worker请求。每帧携带version、requestID、generation和command；允许discover/read/close，真实sourceID只取自当前generation的发现结果。协议定义见 [08组件设计](../08-component-design.md)。
3. 读取请求截止为1秒，发现请求截止为10秒。父进程期限到立即停止接纳该请求的结果并发送SIGTERM；250ms仍未退出则仅向自己持有的worker PID发送SIGKILL。**确认旧进程退出后才允许新generation启动替代worker。** 若系统未回收子进程，停止重建并进入Fatal，不累积替代进程。
4. 父进程持有样本接纳序号／generation；过期回复不进入Raw／EMA／SQLite，子进程不写数据库。每次恢复产生新generation，并按 [08](../08-component-design.md) 重建身份、定义版本与连续段。
5. 该进程边界隔离崩溃和用户态阻塞，不需要提权；它不能保证不可中断内核状态下绝对按时终止。不得把发送SIGKILL等同于已退出，也不得使用未验证的“异步SMC取消API”。

以上为工程设计D，尚无生产worker的实测通过记录。实现后用模拟worker的永不回复／晚回复／崩溃／超长帧测试证明有界行为，恢复次数与故障升级遵循 [06故障契约](../06-error-handling.md)。

默认sensor重试仍为首次＋最多3次，退避50/100/200ms；350ms只是等待合计，不是调用总期限。期间跳过过时tick，不为每tick新开重试链。睡眠／停止使旧generation失效，已取消generation的晚到结果丢弃；普通采样档位变更**不使在途generation失效**，允许旧周期请求完成，并将对应 `nextDue` 设为“修改时刻＋新周期”。关闭遵守在途资源约束。

## 7. 删除、降级与真正的外部输入

以下要求无足够接口依据，应从首版验收中移除：逐物理核心温度、硬件Package精确映射、全芯片绝对热点、50ms硬件刷新保证、单机CLI结果覆盖所有Apple Silicon Air、每个传感器故障都通过提权修复、HID同名自动合并、未知IORegistry字段单位猜测。

以下事项**不阻止实现**：尚无外部计量校准、TCMz响应特性未测、HID没有本机CPU服务、IOPS字段缺失、其他Air机型未适配。通过上述命名、固定配置与可选能力策略处理。

需要后续实机验收而非另找API：最终App构建的访问权限、12键精简轮询开销、Battery SMC周期读取、内置SSD属性与唯一性、睡眠唤醒、阻塞隔离、72小时、系统升级后的profile一致性。当前E1不能替这些测试盖章；先用模拟Provider实现数据链和故障行为，再执行授权实机检查。

真实外部输入仅包括：

1. 若公开分发要求Developer ID签名／公证，需要用户的Apple开发者身份和签名配置；未提供前可完成本地adhoc构建与模拟验证。
2. 若要扩大首发机型／系统，需要对应实机及测试机会；不能用联网搜索替代机型实测。

C11已确认不存在课堂数据库往返要求，实时视图采用优化后的内存数据路径；这不再是待提供的外部输入。Raw持久化和历史查询继续遵循数据契约。

## 8. 复核入口与后续代理操作

固定上游版本及已审文件哈希见 [来源清单](2026-09-17-source-manifest.json)。临时克隆 `/private/tmp/temp-reference-review-20260917` 只为本次审计便利，交接不得依赖它永久存在；可按来源清单的repository＋commit重新取得。已有改编macmon的MIT全文见 [THIRD_PARTY_NOTICES](../../prototypes/sensor-probe/THIRD_PARTY_NOTICES.md)。Stats、MacMonitor、macmon的实质复制须保留许可；MacFanControl仅参考分类冲突，不移植其缺少完整LICENSE的固定版本代码。

目标机证据：[报告](../validation/2026-09-15-m4-air/validation-report.md)、[capabilities](../validation/2026-09-15-m4-air/capabilities.json)、[周期记录](../validation/2026-09-15-m4-air/sampling-results.csv.gz)、[候选清单](2026-09-17-m4-source-candidates.md)。本次用Python标准库只读取这些文件，核实12键各2,279条、TCMz/TCMb/TB*无周期记录、SDK声明及固定上游文件位置；没有改动历史证据。

开始实现时顺序：类型／解码／选择规则fixture → 只读Provider与资源生命周期 → 有界调度和超时隔离 → Raw／派生指标数据链 → 正式App能力测试。无需先运行第三方软件或先验证已删除的逐核要求。
