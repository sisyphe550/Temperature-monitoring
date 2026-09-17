# 开源项目复核与方案优化

日期：2026-09-17。来源：C07（指定对话）及 C08（学习并完善本项目的授权）。**本次交付是方案修订，不是生产功能实现或新增实机验收。** 技术细化列入推荐设计；改变已确认产品要求的部分列为 RC 提案，未自动生效。

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

## 4. 推荐产品范围与需求改动提案

以下是可评审的替代方案。**RC-01～RC-04 会改变已确认要求，仍待产品决定；旧 REQ 正文保留，不宣称已删除逐核需求。** 实现时先关闭相应 OQ，再同步替代条款、UI 与测试。纯事实纠错和来源约束立即用于设计。

| 提案 | 受影响需求 | 推荐新行为 | 验收重点 |
|---|---|---|---|
| RC-01 CPU 主指标 | REQ-010/043/044/113 | 首选“已验证 CPU 热区最高温度”，按已通过本机语义验证的固定成员集合计算 max，再做 EMA 显示；说明这是已覆盖区域的派生指标。若后续确认某个硬件主指标，则用独立名称和定义版本替换 | 名称、成员、公式可追溯；没有合格成员则不可用；不能叫物理 Package 或全芯片绝对最高温 |
| RC-02 逐核范围 | REQ-009/010/012/114/122/132 | 首版显示“CPU 热区／传感器列表”，取消首版逐物理核心完整覆盖的硬性承诺；物理 Core 模式保留为有映射证据后的扩展 | 不生成 Core 0…N 的伪映射；按源 ID 区分和绘图；测试传感器数量不同于核心数 |
| RC-03 能力缺失 | REQ-054～057/072～078/115/116 | CPU 为核心能力，SSD、Battery 为可选能力。某项不支持、单位未知或可选源耗尽重试时显示不可用及原因，CPU 继续工作。全部 CPU 主来源失效则报告并进入既有 Fatal 流程 | 区分启动不支持、临时故障与关键能力丢失；未确认前不改写原全局退出规则 |
| RC-04 首发声明 | REQ-109～111 | 首发验收限定已测试的 Air 机型＋系统＋构建配置；其他 Air 为待适配。保持 Air 产品方向和最低系统目标 | 兼容矩阵不能把单机 CLI 通过扩展成全部代际的正式 App 支持 |
| RC-05 轮询语义细化 | REQ-001～007/134 | 保留五档和默认 200 ms；50/100 ms 用于高频观测，注明请求频率及代价；验收实际调用节奏，不承诺硬件同频产生新测量 | 间隔、批耗时、漏采和新鲜度分开统计；实际误差阈值仍归 OQ-02 |

不扩大为综合系统监控工具：GPU、功耗、风扇控制、网络、远程指标服务、告警、自启动均不因参考项目具备而加入。现有原生 UI、SQLite、Raw 入库、EMA、分级历史、会话内 72 小时设计继续保留。OQ-04 的教师数据库往返要求仍需外部确认。

## 5. 采集与身份：可实现的细化

### 5.1 发现阶段与读取阶段分开

启动／重连时枚举候选；按机型、系统 build、provider、原始键、数据类型和验证记录形成运行时注册表。周期任务只读活动源。缓存 SMC KeyInfo 与读取句柄，不缓存为“新的测量值”。连接重建、睡眠恢复或能力变化时失效并重建缓存。

R03 的 KeyInfo 缓存是直接可借鉴的机制；R05 每次全量枚举适合小实验，不能未经测量作为 50 ms 路径。探测全部 200 个 T* 键属于研究模式，生产常规轮询应限制到经过验证的源集合。只看 12 个 R01 候选可将相对 55 个候选的请求数减少约 78%，这是数量估算，**不是已测性能提升**，也不代表这 12 个已经适合生产。

### 5.2 来源和指标分层

```text
Provider（只读桥接）
  → SourceRegistry（能力、原始身份、单位证据、映射版本）
  → SamplingService（周期、连接串行化、时间和错误）
  → 校验 → 每来源 Raw／EMA／历史
          → MetricResolver（固定成员、公式、定义版本）
             → 派生读数／EMA／历史 → 展示快照
```

注册表至少记录：sourceID、provider、rawKey、model、osBuild、connectionGeneration、encoding、unitEvidence、semanticClass、mappingVersion、evidenceRefs。派生指标另存 metricID、成员 sourceID、公式、definitionVersion；不要伪装成独立物理传感器。

SMC 的 FourCC 区分大小写。HID 同名不等于同源；若有可验证的 Registry ID／LocationID 则保存，但不预设它跨启动稳定。不能证明重发现前后身份一致时创建新的源实例，并切断 EMA／趋势连续性。旧原型的枚举序号只在其进程内有意义。

### 5.3 主来源与回退

| 指标 | 推荐顺序／条件 | 不允许的替代 |
|---|---|---|
| CPU | 本机验证的 SMC 热区集合；只有 HID 的单位与 CPU 域也经验证时，才提供独立的备用定义 | 直接把 PMU tdie/tdev 都纳入 CPU；把平均值静默改名 hotspot |
| SSD | NVMe SMART composite temperature；SMC/HID NAND 作为另列研究候选 | 把 SSD proximity、NAND channel、控制器和 SMART composite 拼成同一历史 |
| Battery | 启动检查 IOPowerSources；字段缺失则考虑经验证的 SMC TB* 或 HID gas gauge 来源 | 按同名合并六条服务；将未知 IORegistry 单位直接除以 100 |

回退只有在语义等价得到证明时才可沿用用户可见的 metricID 与语义名称；**只要成员 sourceID 集合改变，就必须创建新的 definitionVersion 并标记曲线断点**。语义不等价时还需更换名称／语义定义，不能只改版本。常态只采主来源，诊断时才并行对照，避免双倍读取与重复计数。回切加入稳定期与有限恢复探测，参数通过 V0.2 故障注入确定，避免每个 tick 来回切换。

派生 max/avg 的成员在一个定义版本内固定；单个必需成员失败则本批派生指标缺失，不以“剩下的源”无提示重算。CPU 源集合因此整体缺失是否触发 Fatal，按 RC-03 决定后的关键能力策略处理。

## 6. 调度、加工与存储优化

1. **一条连接最多一个进行中的调用链。** 普通轮询和该轮重试共用通道。不同周期是独立逻辑日程，不等于共享 SMC 可并发访问；只有已验证独立的通道才可并行。超期跳过已过时机会并计数，不突发补采。
2. **每条读数保留实际开始／结束时间。** 批内各源不是同时测得；派生值保存批次时间跨度与成员，验收最大允许时间差。记录单调时钟、日历时间、sourceTime（若有），没有 sourceTime 时新鲜度未知。时钟换算用平台接口，不照搬实验中的固定频率。
3. **失败不生成测量值。** 缺失事件、类型不支持、非有限值和映射未知分别记录；最后有效值只可供带时间和过期标记的 UI 缓存，不重新进入 Raw、EMA 或 count。0°C 也不能通用地充当错误码。
4. **本机原型结果是预算输入。** 55 个候选的批次 p95 约 27.3～27.8 ms；50 ms 档平均单核 CPU 占用约 9.05%，有一次漏采；200 ms 档约 3.07%，短时无漏采。保持默认 200 ms，优化后重新测量，不能按键数线性预测耗能。
5. **UI 与采样解耦。** 快照发布初始试验值为 200 ms，隐藏窗口停止绘图；菜单栏可按变化更新。该值不是已冻结的 UI 性能承诺。历史查询按屏幕点数选择层级或保留 min/max 的降采样，不把每条 Raw 都交给主线程。
6. **Raw 与 EMA 双路保留。** 从有效来源 Raw／明确标记的派生读数聚合 min/max；EMA 用真实 dt，只用于约定的平滑展示与趋势。来源／定义改变、睡眠恢复和已识别缺口开始新连续段；不补齐“上次值”。
7. **SQLite 单写入、批事务、有界队列。** 每次有效读取产生唯一 sampleID；重试同一写入不重复 EMA/count。容量到顶时记录过载、暂停新采集并产生缺口，已接纳样本仍交付存储；不能为避免报错静默丢弃。具体预算和暂停升级规则在 OQ-10 冻结。

这些是针对现有需求的工程设计，不是宣称上游已实现本项目的 EMA、SQLite TTL 或 72 小时会话契约。高频采集路径不增加风扇写入、提权或常驻第三方 CLI。是否需要自己的辅助进程，仍由不可取消阻塞的实测决定。

## 7. V0.2：下一轮验证与退出条件

| 验证 | 做法 | 产生的证据与通过条件 |
|---|---|---|
| V2-01 CPU 主来源 | 同时记录 TCMz、TCMb、R01 的 12 个候选；空闲→受控 CPU 负载→恢复，多次重复；研究模式才加入 PMU/未知源 | 保存机器、构建、负载方法、源集合、实际时间。至少确定一个可说明 CPU 域和单位的来源；相关性不授予物理 Core 映射 |
| V2-02 附件来源 | SMART 与 NAND、T5SP 分列；TB0T/1T/2T 与六个 HID 电池服务分列观察；重复枚举／重启验证身份 | 定义 SSD composite；电池明确单位、来源选择或不可用。观察时差和量化，不以软件相近值推导绝对精度 |
| V2-03 调度优化 | 对同一来源集合比较元数据缓存前后；再比较全候选与生产候选；五档＋受控负载；每种条件记录时长 | p50/p95/max、漏采率、CPU、内存、失败数、发现耗时；满足 OQ-02 冻结的门槛才通过，阈值未定则仅报告数据 |
| V2-04 生命周期与故障 | 睡眠唤醒、重连、缺失符号／事件、单源失效、同名多源、重试与档位切换重叠 | 无伪 0/伪新样本；连接缓存重建；身份变化断线；不堆积重试；已接纳样本无重复写入 |
| V2-05 最小数据链 | 模拟 provider＋虚拟时钟先贯通 Raw→EMA／聚合→SQLite→展示模型，再接单个已验证 CPU 指标 | 原始峰值保留、来源切换隔离、TTL、重放幂等、有界积压通过；教学路径由 OQ-04 决定 |
| V2-06 正式构建 | 最终权限／签名配置下重做能力、睡眠和长时间运行 | CLI 证据与 App 证据分开；72 小时及跨机型通过前不扩大声明 |

先做来源语义与身份验证，再确定指标集合；随后优化读取，最后运行完整数据链。**当前未执行上述 V2 测试。** 不因为增加文档而关闭 OQ-01/02/03/05/09。

## 8. 实施优先级

- P0：评审 RC-01～04；解决 OQ-04；补齐 V2-01/02 和最终权限约束。
- P1：实现 SourceRegistry＋只读 Provider＋有界调度；验证元数据缓存及失败语义。
- P2：实现单指标数据链、模拟回放和数据库边界；再接入其他已验证来源。
- P3：原生菜单栏／面板／窗口、历史查询和缺口呈现；完成生命周期、长期与发布验证。

本次只是延续 V0 PR 的证据解释和方案收敛。后续独立功能按 [Git 流程](11-git-github-workflow.md) 从最新 main 建分支，门禁通过后使用 merge commit，保留开发分支。
