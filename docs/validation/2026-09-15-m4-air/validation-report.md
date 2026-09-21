# M4 Air 最小可行性验证报告

日期：2026-09-15。**结论：部分可行；完成本轮最小验证，完整 V0 未通过，生产设计未冻结。**

## 1. 已得到的结论

- 普通用户可以取得 AppleSMC CPU 候选数值、NVMe SMART SSD 温度，以及 HID 电池／NAND 候选数值。
- 没有建立 CPU Package 或物理 Core 对应关系。55 个 CPU 候选来源不是55个物理核心；本机物理CPU核心数为10。
- IOPowerSources 没有返回 Temperature 字段；6个同名 HID 电池来源数值不同，不能擅自去重或平均为唯一电池温度。
- 五档各60秒实测共128,645条读取记录、3,179个批次。50ms档漏采1/1,200次目标机会，其余CPU档位和SSD／电池组均无漏采。没有证据证明硬件按50ms生成新测量。
- 8项单元／白盒测试、CLI黑盒、Release构建和源码提交的CI通过。100%行覆盖率仅指原型纯逻辑55/55行，**不是产品核心模块整体覆盖率**。

## 2. 环境与可复现版本

| 项目 | 实测记录 |
|---|---|
| 机型 | Mac16,13 / Apple M4 / 10个物理CPU核心 / 32GiB内存 |
| 尺寸 | 15英寸，按 [Apple型号对照](https://support.apple.com/en-ge/102869) 核对 |
| 系统 | macOS 15.7.3，build 24G419 |
| 权限 | uid/euid=501；普通用户，沙箱外，无sudo |
| 正式采样开始时间 | 2026-09-15T11:35:07Z（UTC） |
| 供电与负载 | 开始时AC Power；日常交互环境，无受控CPU负载，无外部温度计／环境温度记录 |
| 工具链 | Apple Swift6.1.2；macOS15.5 SDK；Command Line Tools |
| 构建 | Release，arm64；adhoc/linker-signed；无Developer ID、无Hardened Runtime验收 |
| 源码提交 | `cc5db3cfbb7ce921153b4fd5be9c6d1ccaa89f3c`；采样初始化时工作树干净 |
| 二进制SHA-256 | `680e2d22ce1e4563326be7fb1a26b283f895af98d606f7fe4d079a1885de2fc9` |

完整环境见 [capabilities.json](capabilities.json)，源码文件校验见 [source-manifest.json](source-manifest.json)，签名检查见 [codesign.txt](codesign.txt)。环境只采集必要信息，未读取设备序列号、硬件UUID或磁盘标识。

调用命令（仓库根目录）：

```sh
swift build --package-path prototypes/sensor-probe -c release
prototypes/sensor-probe/.build/release/sensor-probe --intervals 50,100,200,500,1000 --seconds 60 --output validation-runs/NEW_RUN
python3 scripts/summarize-probe.py validation-runs/NEW_RUN
```

本次另用父进程设置360秒超时保护，总采样约300秒，正常结束退出码0。工具退出码只表示证据记录成功且取得CPU候选数值，不能代替产品验收结论。后续文档提交不修改该源码版本。

## 3. 四类接口证据

| 路径 | 枚举／调用结果 | 可证实范围与限制 |
|---|---|---|
| AppleSMC | 2,147个键，枚举索引失败0；200个T前缀候选，其中186个可解码为有限数字、14个类型不支持或非有限 | 55个Te/Tp候选进入五档采样；其余仅初始快照。T前缀筛选不证明物理温度或核心映射 |
| HID温度事件 | 47个服务，46个初始有限数字，1个无事件 | 存在负值及同名来源；保留原始证据，不以全局阈值过滤。没有eACC/pACC命名的CPU来源 |
| NVMe SMART | 1个SMART-capable服务，600/600次采样返回数值 | uint16小端Kelvin，减273.15；本轮SSD范围 23.85～26.85°C，不构成计量校准 |
| IOPowerSources | 1个电源描述，Temperature缺失；300次均field_absent | SDK中有字段声明不等于设备实际提供 |
| HID电池候选 | 6个同名gas gauge battery来源，分别记录，共1,800次数字读数 | 数值范围 22.00～24.50°C；身份仅本次进程有效，来源差异待解释 |
| HID NAND候选 | 1个NAND CH0 temp来源，600次数字读数 | 不与SMART复合温度自动归并 |
| 电池IORegistry回退 | 初始Temperature原始值 `2968` | 单位未知，不换算、不进行周期采样 |

总计128,345条有限数字、300条缺失字段记录。数字有限不等于物理读数有效、准确或新鲜；初始枚举快照与周期记录分别保存。CPU候选采样数125,345，均有有限数字，仍不能证明Package／Core要求。

## 4. 五档调度观测

以下“间隔”是相邻CPU批次开始时间差；每批读取55个候选，不能解读为同一时刻的55路硬件测量。漏采分母为`[0,60s)`内目标调度机会，含0时刻。实际每档观察约60.004秒。

| 目标ms | 已启动/目标批次 | 漏采 | 间隔中位ms | 间隔p95 ms | 最大间隔ms | 批次读取p95 ms | 本进程平均CPU |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 50 | 1199/1200 | 1 | 49.999 | 52.665 | 101.741 | 27.327 | 9.05% |
| 100 | 600/600 | 0 | 100.003 | 103.897 | 104.933 | 27.438 | 6.25% |
| 200 | 300/300 | 0 | 200.001 | 203.994 | 205.036 | 27.702 | 3.07% |
| 500 | 120/120 | 0 | 499.852 | 504.135 | 504.721 | 27.828 | 1.51% |
| 1000 | 60/60 | 0 | 1000.134 | 1003.906 | 1004.995 | 27.719 | 0.82% |

50ms档1次漏采率约0.0833%，最长批次读取51.837ms，超过该目标周期；最大相邻间隔101.741ms。调度器跳过过期机会、不积压补采。该观测为串行扫描55个未去重候选的原型结果，不能直接套用到未来产品选定来源后的开销。

CPU百分比以单个逻辑核100%计算，仅本进程user＋system时间。RSS高水位和各组时延在 [summary.json](summary.json)、[analysis.json](analysis.json)。批次读取时间包含墙钟格式化、解码、行序列化，排除批次文件写入；不是纯IOKit调用延时。

中位数按通常定义计算；p95使用nearest-rank。同值重复保留。当前没有资源／时延验收阈值，不作“性能达标”判断。

## 5. 测试、缺陷与复核

| 项目 | 结果与证据 |
|---|---|
| 单元／白盒 | 8项Swift Testing通过；解码端序、负数、长度／类型、NaN/Infinity、重复值、NVMe转换、调度边界、CSV转义、参数异常；[日志](unit-tests.log) |
| 测试先行 | 空实现首次运行产生28个预期断言失败，随后通过；[首次失败日志](regressions/red-tests.log) |
| 覆盖率 | ProbeCore 55/55行，100%；门槛80%。硬件桥接与CLI不在分母内；REQ-092产品范围未验收 |
| CLI黑盒 | --help、非法档位／时长／参数／缺参退出2；拒绝覆盖已有证据目录 |
| Release与CI | 构建通过；[源码提交CI](https://github.com/sisyphe550/Temperature-monitoring/actions/runs/34916543698) 的测试、覆盖率、Release、黑盒步骤全部成功 |
| 独立代码审查 | 发现并修复窗口提前返回、证据版本不可区分；复核通过，未发现新的最小验证阻塞项 |
| Issue #1 | [CLT缺少XCTest](https://github.com/sisyphe550/Temperature-monitoring/issues/1)：改用自带Swift Testing，回归通过 |
| Issue #2 | [NVMe插件生命周期](https://github.com/sisyphe550/Temperature-monitoring/issues/2)：初次0x10000003=MACH_SEND_INVALID_DEST；延迟销毁plugin后SMART读取成功，正式600次回归成功 |
| Issue #3 | [窗口提前结束](https://github.com/sisyphe550/Temperature-monitoring/issues/3)：请求2秒曾仅观察约1.825秒；补足等待后五档1秒回归为1.0006～1.0051秒，正式各档均至少60秒 |

早期 [回归目录](regressions/) 包含沙箱对比和修复前后读数。前3轮是未提交代码的诊断快照，未记录二进制哈希，**不可单独作为最终可复现能力验收**；失败记录中的0／NaN曾是初始化占位值，应按错误状态解读。最终版本已将失败原始值留空，正式证据有提交＋二进制哈希。

## 6. 执行范围与阶段门禁

| 计划步骤 | 本轮状态 |
|---|---|
| V-01 环境 | 已记录单台目标机型、系统、构建与普通用户权限 |
| V-02 枚举 | 四类路线已探测，成功、缺失、错误与单位未知分开保存 |
| V-03 语义 | 仅日常环境数值观察与SDK／固定开源映射参考；受控空闲／CPU负载、Stats/macmon实时对照未执行；Package／Core未证实 |
| V-04 五档 | 五档各60秒的缩短实测完成；完整每档数分钟及验收阈值仍待完成 |
| V-05 生命周期 | 多次进程停止再运行及同进程依次切档可工作；睡眠唤醒、主动插拔电源、并发切档未测试 |
| V-06 数据链 | 未执行；无Ring Buffer/EMA/SQLite/UI |
| V-07 发布配置 | 仅检查现有adhoc签名；Developer ID/Hardened Runtime/公证下读取未验证 |
| 72小时与跨机兼容 | 未执行 |

工作流：从最新origin/main `3fa99aa`建立 `feature/v0-sensor-validation`；提交代码、执行测试与CI、关联缺陷，再提交证据和待审查PR。当前GitHub无main分支保护／ruleset，阻塞Issue自动门禁和审批规则未定义；本轮提交 [Draft PR #4](https://github.com/sisyphe550/Temperature-monitoring/pull/4)，不合并，保留本地／远程功能分支。仓库允许merge commit且关闭自动删除分支，后续满足门禁才能合并。**CI成功不等于强制合并门禁已生效。**

## 7. 证据与下一步

- [capabilities.json](capabilities.json)：完整枚举和环境。
- [sampling-results.csv.gz](sampling-results.csv.gz)、[timing.csv.gz](timing.csv.gz)：无损压缩原始证据。
- [raw-sha256.txt](raw-sha256.txt)：解压后的原始文件SHA-256；本轮脚本已核对行数／批次／汇总一致性。
- [兼容矩阵](compatibility-matrix.md)、[原型复现说明](../../../prototypes/sensor-probe/README.md)。

优先完成OQ-01：确定可接受的CPU主指标定义、逐核映射证据和电池候选语义；随后补受控负载、跨工具同步对照、完整五档与睡眠唤醒。OQ-02/OQ-09/OQ-15保持打开。OQ-04教学数据链与OQ-05指标必需性仍由业务验收决定。未修改已确认需求来适配当前结果。
