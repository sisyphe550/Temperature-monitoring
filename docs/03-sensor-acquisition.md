# 传感器接口、首版配置与可行性结论

更新：2026-09-18；C10基线v1。逐物理核心温度已删除；物理Package和全芯片绝对最高温不再作为产品承诺。完整函数、ABI、来源与证据见[硬件审计](research/2026-09-17-handoff-interface-audit.md)。

## 可行性与证据

| 能力 | 本项目路线 | 现有依据 | 实施后仍要验证 |
|---|---|---|---|
| CPU摄氏温度 | AppleSMC，固定Stats M4 12个CPU热区键 | 本机每键2279条周期读数＋固定上游温度分类 | 正式App/worker、精简集合五档、负载及sleep/wake |
| CPU主指标 | 12个同批有效Raw的max，再EMA | 可读成员＋本项目确定性算法 | 算法/缺失成员/时间跨度；不要求物理Package映射 |
| SSD | 内置唯一NVMe SMART composite | 本机原型600次成功＋SDK及Stats实现 | 内置服务属性/唯一性与最终构建权限 |
| Battery | IOPS Temperature；缺失时TB1T→TB2T→TB0T | IOPS本机缺字段；三SMC键有初始读数＋Stats/MacMonitor分类 | 选中SMC来源的周期读取、身份和生命周期 |
| HID | 原型及macmon动态符号读取，仅诊断/未来profile | 本机47服务；温度事件接口已有调用证据 | 本机没有已分类CPU服务，首版不自动回退 |
| 权限/隔离 | 普通用户只读；自有SensorWorker | 原型沙箱外普通用户读通；Process系统能力 | 正式签名配置与进程故障测试 |

E1=目标机读取证据，E2=固定开源/SDK路线，D=本项目设计。E1/E2支持开发方案，不能据此宣称已完成正式产品验收或计量校准。原记录`decoded_mapping_unverified`保持原样。

## 首版唯一生产候选profile

机器配置见[first-profile-v1.json](contracts/first-profile-v1.json)。机型`Mac16,13`，M4 Air，已观察OS15.7.3/build24G419。其他Air不自动套此表；显示“该机型尚未适配”并退出。相同机型其他≥15.7.3系统组合可用于标注“未验收”的开发验证，不进入正式兼容声明。

- CPU固定键：`Te05 Te0S Te09 Te0H Tp01 Tp05 Tp09 Tp0D Tp0V Tp0Y Tp0b Tp0e`，大小写不变。首次发现全部要求`flt `且4字节；任何变化视为配置不匹配。
- 显示名“CPU热区最高温度”，metricID=`cpu.zone.max`；详情说明12个来源的固定max及开源分类依据。源列表写“CPU温度来源·Tp01”等；可使用“E/P域（开源分类）”，绝不写Core编号。
- TCMz/TCMb/TPMP/Ts1P/T5SP保留诊断，不自动扩成员或替代主指标。它们的更细物理含义存在分歧或只有初始读数。
- 12成员全部成功且批跨度≤200ms才派生；任一失败不缩小集合，执行整集合读取重试。耗尽后CPU关键能力Fatal。

## Battery选择

启动只选唯一内置电池，IOPS温度字段须为数值CFNumber、非CFBoolean、有限；没有字段继续检查SMC `TB1T`、`TB2T`、`TB0T`，取优先级最高的合格项，不平均。本机按现有证据应选TB1T，仍须生产周期测试。

三键的首版配置要求flt/4字节；直接解释为°C，依据固定温度分类。通用解码器可支持sp78，但本profile遇到类型改变应报不匹配，不悄悄接受新编码。`AppleSmartBattery.Temperature=2968`不是IOPS字段，单位未确认，不采用除以100等猜测。

正常运行只采选定来源。暂时失败先重试；耗尽Unavailable，有限恢复探测只探原来源。唤醒/新会话重发现可选择另一来源，必须更新seriesID/definitionVersion、语义说明并断开历史。IOPS和SMC不预设测量位置等价。

## SSD选择

沿用`sp_nvme_open/read`的SDK接口和已修复插件生命周期。发现IOBlockStorageDevice时读取Protocol Characteristics中Physical Interconnect Location；仅唯一明确Internal的NVMe候选可选。属性可沿父服务树最多16层查找；失败/循环/多个候选一律Unavailable并记录原因，不能选`device:0`。

SMART TEMPERATURE小端Kelvin；0表示未报告，其余`Double(kelvin)-273.15`。保持接口与plugin活到所有读取结束，再Release interface→destroy plugin。SMART composite与NAND/邻近/外壳温度分开，后者不回填SSD历史。

## 读取实现

原型已有`sp_smc_open/key/read/close`、`sp_nvme_open/read/close`、`sp_hid_open/count/name/read/close`；具体实现见`prototypes/sensor-probe/Sources/SensorBridge/`。移植保留MIT来源与C结构静态断言。生产新增KeyInfo缓存、Registry ID身份与profile过滤，不直接复制原型全部T*轮询。

SMC selector2，command9 KeyInfo、command5读值；同时检查IOReturn、SMC result、输出长度和类型。flt小端IEEE754、sp78大端有符号/256；未知类型不解码。公开IOKit调用不等于SMC/HID协议公开稳定。

HID仅在诊断模式按需开启并在停止后释放；不将PMU标签猜成CPU，不按同名合并，不复用枚举下标作为永久身份。生产界面不用第三方程序后台运行。IOReport、powermetrics、写风扇/SMC均不在范围内。

## 周期、身份与权限

CPU五档50/100/200/500/1000ms默认200；SSD500ms、Battery1000ms。它们是请求日程，不保证硬件刷新频率；具体串行调度、批次时间和漏采计数见[08](08-component-design.md)。所有读数记录开始/结束elapsed及真实wall时间；无源时间戳则freshness=unknown。

sourceID是连接代次内实例UUID，另存原始键/Registry ID/机型/系统/映射版本/出处。重连不能以同名或同数组位置复用旧ID；定义改变新seriesID和definitionVersion，曲线断开。

App Sandbox关闭、无管理员权限、无私有entitlement。权限拒绝按能力状态与必需性处理，不能要求用户关闭SIP或提权。正式Developer ID/Hardened Runtime构建按[13](13-operations-distribution.md)再测。
