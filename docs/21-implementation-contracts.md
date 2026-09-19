# 实施契约v1：唯一参数、类型与存储定义

更新：2026-09-19；C10/C11授权细化。本页连同01～13是当前实现依据，历史研究/旧实测报告仅作为证据，不能恢复被替代的需求。

## 机器可读交付物

| 文件 | 权威内容 | 使用方式 |
|---|---|---|
| [defaults-v1.json](contracts/defaults-v1.json) | 全部默认周期、算法参数、容量与截止时间 | W01加载并验证；不可在别处写不同默认值 |
| [first-profile-v1.json](contracts/first-profile-v1.json) | 首机型、来源成员、优先级、证据状态 | W02资源；不是已通过正式App的兼容报告 |
| [api-v1.swift](contracts/api-v1.swift) | 值类型与服务接口签名 | W01拆入08所列文件；通过typecheck不等于实现 |
| [schema-v1.sql](contracts/schema-v1.sql) | SQLite DDL、键、索引、视图与PRAGMA | W03初始化资源，事务逻辑遵守04 |
| [acceptance-v1.json](contracts/acceptance-v1.json) | 134项REQ到任务和测试的映射 | W11逐项附证据；012/114为retired |
| [tasks-v1.json](contracts/tasks-v1.json) | T00.1～T11.3依赖图及W归属 | 23逐task执行；禁止跳过依赖或循环引用 |

## 命名与转换

- 规格中的sensor_id对应sourceID；只有派生序列使用独立seriesID/metricID，不混入硬件sensor数量。
- `Sample.timestamp.elapsedNS`到SQL elapsed_ns；wallUnixNS到wall_ns。Double只用于温度/数学，不承载纳秒整数。
- `SessionMetadata`逐字段写入session；`PersistenceBatch.sources/definitions`在引用它们的segment/sample之前写入。重发现产生的新source必须随首批数据原子提交，不能只在内存registry存在。
- 系统Clock和worker共用父进程传入的系统连续tick基准，双方均以mach_continuous_time＋mach_timebase_info转换；ContinuousClock用于异步sleep剩余时长。禁止将两个进程各自启动时刻当同一基准。
- `SeriesDefinition.definitionVersion`变化必须新seriesID；新来源UUID也是新定义。`segment`只在同一定义内标记连续性变化。bucket主键包含seriesID、segment、width和起点。
- `Sample.memberSampleIDs`写sample_members；EMA与其输入Sample共用sampleID但处于不同表。`Bucket.latestSampleID`仅作证据字段，不跨TTL建立外键。
- elapsed为Int64非负；clock换算用整数商余数/宽乘防溢出。无源更新时间保持nil/NULL，不填应用观测时间冒充它。

## 参数性质与修改

五档、默认200ms、SSD/Battery周期、Raw/EMA保留及分层TTL来自既有要求。tau、trend、容量、截止时间与布局初值属于本轮选择的v1工程参数，**未声称经过性能调优**。遇到实测不达标，先记录失败、定位原因，修订版本和验收；不能偷偷降低采样档位、减少CPU成员或丢有效数据来制造通过。

`ring_capacity_per_series=8192`各适用于Raw和EMA；`max_active_series=32`包含派生。队列条数包括SQL成员/元数据逻辑行与在途事务；每个事件最多512行、预留512行。发现最多256候选，正常只接纳profile选定集合；新profile超出限制应拒绝配置并显式修订容量，不能截断集合。

`ProcessingEngine.accept/advance/markGap`的生产实现持有注入的PersistenceQueue：调用者把预先取得的一次性QueueReservation与事件显式同传，方法在临时状态计算、以该预留完成入队，收到接纳确认后才交换状态。返回的PersistenceBatch只供测试与审计，不由调用者再次写库。StorageWriter仅排空队列并调用SampleStore；这条所有权规则防止“状态已前进但批次未入队”及重复append。

首次probe已观测CPU键/battery编码为flt4，profile只接受该编码；通用解码器支持sp78并不扩大profile允许范围。数据源温度低于物理绝对零度或非有限拒绝；其他合理性告警只能记诊断，不用经验阈值截断有效峰值。

## 确定的失败与开发边界

不支持机型/关键CPU不可用→报告并停止；可选SSD/Battery不可用→保留占位和原因。固定CPU成员缺失重试耗尽→Fatal。DB/算法/关键UI失败→Fatal。详细码及预算仅以06为准。

开始实现不需要再次选择语言、数据库、进程模型、主指标公式或实时数据路径。接手者遇到实测证据与profile不符时记录差异和Issue，完成其他独立任务；不得将文档中的E2依据升级为E1实测。13中的签名凭证、Xcode和机型资源是明确外部依赖。

## 文档自检入口

```sh
python3 scripts/validate-handoff.py
swiftc -swift-version 6 -typecheck docs/contracts/api-v1.swift
```

第一条检查需求/任务覆盖、JSON、SQL创建与关键约束、链接和未闭合设计用语；第二条检查规范类型可编译。测试产物不证明App已实现。完整验收命令与新增文件顺序见[22](22-agent-implementation-plan.md)。
