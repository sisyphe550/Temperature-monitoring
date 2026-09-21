# 开源项目复核与方案优化

更新：2026-09-21。C07/C08提供研究来源，C09删除逐核并确定UI借鉴方向，C10/C11形成当前交接基线，实施契约v1族修订2固定复用门禁。**本页保留开源比较依据；具体实现以01～13/21/22为准，未宣称生产功能或新增实机验收完成。**

## 1. 结论

现有 Swift＋小型 C 桥接＋SwiftUI/AppKit＋SQLite 路线可以继续。优先复用开源项目的接口封装、能力发现、元数据缓存和原生展示结构。无需引入完整 Rust/Go 运行时或外部监控进程。

CPU 摄氏温度读取已有可行路径；**逐个物理核心和物理 Package 的准确映射仍没有充分证据**。方案应围绕有来源、有范围说明的 CPU 温度指标设计，并保留映射不足状态。读取成功、负载相关、软件间数值接近，都不能独立证明物理位置或测量精度。

## 2. 覆盖清单与固定来源

覆盖指定对话的五个主要项目，以及附带提到的 mactop 和独立 Swift 实验。对话中的星数、支持代际和助手评价不作为验收依据。以下版本于本次从项目仓库取得；文件哈希见 [来源清单](research/2026-09-17-source-manifest.json)。未运行这些项目的安装程序、提权助手或风扇写入代码。

| 编号／项目 | 固定版本与检查入口 | 可复用经验 | 本项目采用边界 |
|---|---|---|---|
| R01 Stats | [e31d279b：映射](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/Modules/Sensors/values.swift)、[读取与派生指标](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/Modules/Sensors/readers.swift)、[FAQ](https://github.com/exelban/stats/blob/e31d279b3f27aacb19b512b26eb5ab92e166c289/README.md) | 按平台管理传感器；区分硬件读数与计算值；菜单栏模块化 | 采用版本化候选表；不继承“Core n”标签。FAQ 明确传感器表示热区而非逐物理核。其失效时沿用旧值的路径不能直接复制为新 Raw |
| R02 MacMonitor | [2fff1062：传感器研究](https://github.com/ryyansafar/MacMonitor/blob/2fff106238e17e318f1b48775034c461f6464257/SENSORS.md)、[读取实现](https://github.com/ryyansafar/MacMonitor/blob/2fff106238e17e318f1b48775034c461f6464257/Macmonitor/IOReportWrapper.m) | 独立研究目录；SMC/HID 来源选择；SwiftUI 展示与底层桥接分层 | 采用研究→适配→展示的边界；其文档实测主要是 M2，不能替代 M4 验证；其 CPU 平均还纳入 Ts0*，不能与其他工具的平均直接比较 |
| R03 macmon | [6919d778：接口与缓存](https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/sources.rs)、[指标计算](https://github.com/vladkens/macmon/blob/6919d7781b6c55a6e3bedff83a210435837e1dfe/src_lib/metrics.rs) | 普通用户读取；SMC KeyInfo 缓存；连接生命周期；结构化指标 | 原型已复用并注明 MIT；继续借鉴缓存，保持 Swift/C；SMC 可用性探测优于仅按芯片代际选接口。平均温度不是 Package/逐核温度 |
| R04 MacFanControl | [e5afaeb5：分层](https://github.com/sak0a/MacFanControl/blob/e5afaeb51da6d80ac6e26e0bdef7503cceebb7e6/Package.swift)、[SMC 封装](https://github.com/sak0a/MacFanControl/blob/e5afaeb51da6d80ac6e26e0bdef7503cceebb7e6/Sources/MacFanControlCore/SMC.swift)、[分类](https://github.com/sak0a/MacFanControl/blob/e5afaeb51da6d80ac6e26e0bdef7503cceebb7e6/Sources/MacFanControlCore/Sensors.swift) | App/Core/C shim 分层；串行保护共享连接；类型解码集中 | 借鉴结构；不引入风扇控制、写 SMC 或 root helper。键前缀分类仅是猜测。README 的“400+”不能当成本机温度数量 |
| R05 SwiftTempBar | [da4b0b54：TemperatureReader](https://github.com/WHYBBE/SwiftTempBar/blob/da4b0b54e4e3d56941c3cd902b0bc877349ff190/Sources/TemperatureReader.swift) | 小规模 HID 动态符号加载、枚举和菜单栏读数路径 | 适合理解 API；不照搬每次全量重建、不把 PMU/PMU2 名称直接判为 CPU/GPU、不套用统一 110°C 截断；事件缺失必须返回错误而非默认数值 |
| R06 mactop | [eaa2fab3：温度路径](https://github.com/context-labs/mactop/blob/eaa2fab31481d10bc7544466434eb74a2e2318c3/internal/app/ioreport.m) | 启动发现 SMC 键；SMC 优先、HID 回退；观测辅助工具 | 用作交叉观察，比较前记录实际参与的源集合。该版本 HID 循环以 cpuCount==0 控制累加，首个匹配后不再累加，不能把这条路径当作全体 HID 平均的参考答案 |
| R07 Philip Turner 实验 | [TemperatureSensor.swift 固定修订](https://gist.github.com/philipturner/81bed277f2942c87ea8825910e91a766/7092b98722f9eed2e169ad515a296b57da3705a2) | 观察重复服务、量化步长、调用延迟与分箱行为 | 找到了与对话描述匹配的实验；原对话未暴露引文 URL，无法证明就是其原引文。仅借鉴实验方法；千赫兹注释不证明 M4 硬件刷新率；不采用补齐旧值或硬编码时钟频率 |

### 许可与复用方式

- R01/R02/R03/R05/R06 固定版本均有完整 MIT 文件，记录于来源清单。若后续复制或改写实质代码，随文件保留版权、完整许可、上游 commit 和修改范围；也需检查具体文件的第三方来源声明。
- R04 README 标示 MIT，但该 commit 的仓库树没有完整 LICENSE 文件；本轮只参考架构，代码移植等待许可材料完整。
- R07 所查单文件没有明确许可文本；只借鉴观测问题与方法，不复制代码。
- 本轮未导入新的第三方源代码。已有 macmon 桥接的许可仍在 [THIRD_PARTY_NOTICES](../prototypes/sensor-probe/THIRD_PARTY_NOTICES.md)。

研究清单和实际导入清单职责不同：[source manifest](research/2026-09-17-source-manifest.json)及[UI manifest](research/2026-09-17-native-ui-sources.json)固定研究输入；[third-party-v1.json](contracts/third-party-v1.json)固定实际copied/modified本地路径、许可hash和notice。研究过某项目不等于获准复制其代码；MIT项目也必须逐文件登记。R04和R07保持method-only。

下列上游行为明确禁止进入产品：失败时把旧值当成新Raw、缺事件返回0°C、按名称或数组序号赋予物理核心/E-P域/Package含义、把12个来源映射成10个物理核、合并同名但registryID不同的来源、写SMC、风扇控制、root/helper、外部监控CLI及把测试fixture装入Release。`TC-UPSTREAM-BOUNDARY`必须同时覆盖行为反例、Release扫描与缺登记失败。

## 3. 从冲突中建立本机候选表

来源表需要保存“谁这样命名、在哪台机器观察到、我们验证到哪一步”，不能只保存一个好看的传感器名称。

| 发现 | 对本项目的影响 |
|---|---|
| R02 将 TPMP 称为 SoC Package；R04 将其称为 Platform memory | 暂列含义冲突，不能选作 CPU Package |
| R02 将 Ts1P 称为 SSD proximity；R04 将其称为 Top case | 暂列含义冲突，不替代 NVMe SMART 温度 |
| R01 的 M4 CPU 表有 12 个热区候选；本机 12 个均可解码，而物理 CPU 数为 10 | 再次说明传感器数不能映射成物理核心数；保留原始键 |
| 本机初次枚举 TCMz=76.046875、TCMb=44.818958；当时未同步施加受控负载 | 值存在不证明 hotspot 含义、精度或响应速度；优先做并行来源观察 |
| 本机 T5SP 与 TPMP 初值相同，TB0T/TB1T 与若干 HID 电池读数相同 | 单次相同不足以证明别名；不据此去重或平均 |

[本机候选清单](research/2026-09-17-m4-source-candidates.md) 从已有 capabilities.json 生成，包含全部 249 个已记录来源及重点候选。它不是 249 个有效温度计，也不是新的硬件测试。

## 4. 原提案的当前落点

| 原编号 | 当前处理 | 实施文档 |
|---|---|---|
| RC-01 | C10基线：CPU固定12热区Raw max后EMA；移除物理Package称谓 | 01/03/05 |
| RC-02 | C09已删除逐物理核温度及core_id，不预设恢复承诺 | 01/15 |
| RC-03 | C10基线：SSD/Battery可选；CPU主指标无法生成且重试耗尽Fatal | 06 |
| RC-04 | C10基线：按实测profile/OS/构建声明支持，未知机型不自动套表 | 03/13 |
| RC-05 | 五档请求周期保留，新鲜度未知明确记录 | 03/08/10 |

C11明确实时路径可以走内存；不再保留强制数据库往返的并行方案。Raw/EMA入库、SQLite分级历史及会话约束继续实现。

## 5. 已转化为明确契约的经验

- macmon元数据缓存→启动/重连发现、按generation缓存KeyInfo，周期只读活动来源。
- Stats平台表→固定profile与来源证据；不继承Core编号。
- MacMonitor/Stats原生组件→07的面板、来源列表和菜单栏；本项目自行接历史图表与EMA。
- 多项目不同定义→真实来源与派生series分离，sourceID/definitionVersion/segment三层记录。
- 同步调用与失败路径→自有普通用户worker、单在途请求、有限重试、不可取消时进程隔离。
- 上游没有完整实现的部分→04/05定义Raw峰值、分层聚合、TTL、幂等和有界队列，不谎称来自现成完整方案。
- 复制/修改的实质代码→先更新third-party-v1和ThirdPartyNotices；method-only来源只可重新实现方法，不能逐行改写规避许可。

实现路线完整对照见[20](20-feasibility-and-reuse.md)，精确参数/接口/DDL见[21](21-implementation-contracts.md)，逐任务执行见[22](22-agent-implementation-plan.md)。此前V2研究动作已收敛为[14](14-feasibility-validation.md)的资格测试，不保留未选择的生产路径。
