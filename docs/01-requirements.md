# 现行需求规格与退役编号

更新：2026-09-18；C10/C11交接基线v1。134个登记编号保持连续，132项现行，REQ-012/114退役。设计决策已明确，生产应用实现和验收尚未完成；原型局部证据见14。

## 使用规则

- 本文为当前需求正文；02～13为实现契约，21的JSON/Swift/SQL为精确参数与结构，22为执行顺序，17为逐项覆盖。
- C09删除逐物理核心温度与core_id。C10授权完成可行方案、清除不合适内容并形成agent交接；在该授权下采用CPU热区max、可选能力隔离、按实测矩阵声明支持，属于工程基线，不伪称用户逐参数确认。
- C11明确课程不强制数据库往返：实时走内存EMA，Raw与EMA仍持久化；历史走SQLite。
- 原始C01数值要求保留：CPU五档及默认200ms、SSD500ms、Battery1000ms、重试次数、Raw/EMA5min与1s/10s/1min分级TTL、最长72h且不跨会话。
- 取消物理Package、逐核、绝对热点、保证硬件同频刷新或一位小数等于测量精度的推断；旧版本由Git历史与15的变更记录追溯。
- `timestamp`规范分为elapsed_ns与wall_ns；`sensor_id`对应sourceID；`last`统一为latest；聚合表名为04的只读视图。
- “有方案”不同于“已实现/已验收”。132项均有任务和测试入口，正式完成须逐项附证据，不能用文档检查替代产品测试。

## 采样与时间

### REQ-001｜限定 CPU 用户可选档位

- 模式：Ubiquitous
- 正文：CPU 采样设置构件应提供 50 ms、100 ms、200 ms、500 ms 和 1 s 五个采样周期。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

### REQ-002｜确定默认行为

- 模式：State-Driven
- 正文：在用户未修改 CPU 采样设置时，CPU 采集构件应使用 200 ms 采样周期。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

### REQ-003｜动态调整不修改已有数据

- 模式：Event-Driven
- 正文：当用户选择新的 CPU 采样周期时，CPU 采集构件应从后续采样任务开始使用新周期。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

### REQ-004｜SSD 与 CPU 采样周期解耦

- 模式：Ubiquitous
- 正文：SSD 温度采集构件应使用 500 ms 采样周期。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

### REQ-005｜Battery 与 CPU 采样周期解耦

- 模式：Ubiquitous
- 正文：Battery 温度采集构件应使用 1000 ms 采样周期。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

### REQ-006｜算法不能使用理论调度时间代替实际时间

- 模式：Event-Driven
- 正文：当有效温度样本产生时，采集构件应记录该样本的实际采集时间戳。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

### REQ-007｜保证改变采样周期以后算法语义不变化

- 模式：Ubiquitous
- 正文：EMA、聚合和趋势构件应依据实际时间戳计算时间关系。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[08](08-component-design.md)的v1契约实现；执行W05与TC-SCHEDULE，结果见17；有方案不等于已通过。

## 标签与校验

### REQ-008｜建立时间维度

- 模式：Event-Driven
- 正文：当 Raw Sample 产生时，标签化构件应记录 `timestamp`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

### REQ-009｜区分温度来源

- 模式：Event-Driven
- 正文：当 Raw Sample 产生时，标签化构件应记录 `sensor_id`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C09删除逐核后同步范围；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

### REQ-010｜区分 CPU 主指标、CPU 温度来源、SSD 和 Battery

- 模式：Event-Driven
- 正文：当 Raw Sample 产生时，标签化构件应记录 `sensor_type`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C09删除逐核后同步范围；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

### REQ-011｜统一数据单位

- 模式：Event-Driven
- 正文：当 Raw Sample 产生时，标签化构件应记录摄氏温度值。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

### REQ-012｜已删除：物理 CPU Core 稳定标识

- 模式：Event-Driven
- 历史正文（不再生效）：当 CPU Core 样本产生时，标签化构件应记录对应 Core 的稳定标识。
- 状态：已删除，不纳入实现与验收
- 来源：C01原要求；C09随逐物理核心温度要求删除
- 验收边界：不适用。温度来源身份仍按REQ-009保存，不要求物理core_id。

### REQ-013｜禁止无效值进入算法链路

- 模式：Event-Driven
- 正文：当标签化完成时，数据校验构件应验证温度值有效性。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

### REQ-014｜建立确定的非法值规则

- 模式：Unwanted
- 正文：如果温度值为 null、NaN 或 Infinity，则数据校验构件应将本次采样判定为读取失败。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

### REQ-015｜隔离异常数据

- 模式：State-Driven
- 正文：在样本被判定为无效时，数据加工构件应将该样本排除于 EMA、聚合和趋势计算之外。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W01/W02/W04与TC-SENSOR/TC-VALIDATE，结果见17；有方案不等于已通过。

## Raw 与 Ring Buffer

### REQ-016｜建立实时计算数据源

- 模式：Event-Driven
- 正文：当有效 Raw Sample 完成校验时，实时数据构件应将该样本写入对应传感器的 Ring Buffer。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-017｜落实 Raw 持久化需求

- 模式：Event-Driven
- 正文：当有效 Raw Sample 完成校验并被流水线接纳时，数据存储构件应将该样本加入有界持久化队列并按批次写入 `raw_samples`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-018｜防止内存数据无限增长

- 模式：State-Driven
- 正文：在 Ring Buffer 达到容量上限时，实时数据构件应覆盖其中时间最早的 Raw Sample。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-019｜冻结实时 Raw 生命周期

- 模式：Ubiquitous
- 正文：Ring Buffer 应保存最近 5 分钟的 Raw Sample。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-020｜冻结 Raw SQLite TTL

- 模式：State-Driven
- 正文：在 `raw_samples` 中的数据超过 5 分钟时，数据清理构件应删除其中时间最早的超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

## EMA

### REQ-021｜兼容不同 CPU 采样周期

- 模式：Event-Driven
- 正文：当新的有效 Raw Sample 进入 EMA 构件时，EMA 构件应根据该样本的实际 `dt` 计算新的 EMA 值。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-022｜为实时 UI 建立稳定数据源

- 模式：Event-Driven
- 正文：当新的 EMA 值生成时，实时数据构件应将该值写入对应传感器的 EMA Ring Buffer。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-023｜落实加工结果持久化

- 模式：Event-Driven
- 正文：当新的 EMA 值被流水线接纳时，数据存储构件应将其与对应 Raw 一起加入有界持久化队列并写入 `ema_samples`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-024｜限制高频加工数据规模

- 模式：State-Driven
- 正文：在 `ema_samples` 中的数据超过 5 分钟时，数据清理构件应删除其中时间最早的超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04/W05与TC-BUFFER/TC-EMA/TC-STORAGE，结果见17；有方案不等于已通过。

## 窗口聚合

### REQ-025｜第一级历史压缩

- 模式：Event-Driven
- 正文：当一个 1 秒窗口结束时，聚合构件应生成对应传感器的 1 秒聚合记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04与TC-AGG，结果见17；有方案不等于已通过。

### REQ-026｜保留平均值之外的峰值信息

- 模式：Ubiquitous
- 正文：每条非空聚合记录应包含 `min`、`max`、`sum`、`avg`、`latest`、`count`、覆盖时长及部分窗口标志。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04与TC-AGG，结果见17；有方案不等于已通过。

### REQ-027｜第二级历史压缩

- 模式：Event-Driven
- 正文：当安全水位达到一个 10 秒窗口的终点时，聚合构件应合并该区间内已闭合的 1 秒结果；缺失子窗口不阻塞闭合且不得补零。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04与TC-AGG，结果见17；有方案不等于已通过。

### REQ-028｜第三级历史压缩

- 模式：Event-Driven
- 正文：当安全水位达到一个 1 分钟窗口的终点时，聚合构件应合并该区间内已闭合的 10 秒结果；缺失子窗口不阻塞闭合且不得补零。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04与TC-AGG，结果见17；有方案不等于已通过。

### REQ-029｜避免平均值再次平均产生统计误差

- 模式：Event-Driven
- 正文：当多个子窗口生成高层级平均值时，聚合构件应按照各子窗口 `count` 计算加权平均值。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04与TC-AGG，结果见17；有方案不等于已通过。

### REQ-030｜先聚合后删除，避免历史数据丢失

- 模式：Event-Driven
- 正文：当低层级记录所需的父层聚合已成功提交到数据库时，数据生命周期构件应允许已超期的低层记录进入 TTL 清理范围。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[05](05-processing-pipeline.md)的v1契约实现；执行W03/W04与TC-AGG，结果见17；有方案不等于已通过。

## 分级保留与清理

### REQ-031｜限制高精度历史规模

- 模式：State-Driven
- 正文：在 `samples_1s` 记录超过 1 小时时，数据清理构件应删除其中时间最早的超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-032｜限制中期历史规模

- 模式：State-Driven
- 正文：在 `samples_10s` 记录超过 24 小时时，数据清理构件应删除其中时间最早的超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-033｜冻结最大历史范围

- 模式：State-Driven
- 正文：在 `samples_1m` 记录超过 72 小时时，数据清理构件应删除其中时间最早的超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-034｜趋势结果不形成另一套长期数据库

- 模式：State-Driven
- 正文：在 `trend_samples` 记录超过 1 小时时，数据清理构件应删除其中时间最早的超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-035｜数据不存在与查询范围必须一致

- 模式：Ubiquitous
- 正文：历史查询构件应拒绝查询当前时刻之前超过 72 小时的监控数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-036｜统一清理入口

- 模式：Event-Driven
- 正文：当数据清理任务执行时，数据清理构件应按照 Raw、EMA、1 秒、Trend、10 秒、1 分钟各自 TTL 删除超期记录。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-037｜避免每条采样触发 DELETE

- 模式：Ubiquitous
- 正文：数据清理任务应每 60 秒执行一次。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

## 会话生命周期

### REQ-038｜数据库生命周期开始

- 模式：Event-Driven
- 正文：当应用启动时，数据库构件应初始化本次运行使用的 SQLite 数据库。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-039｜禁止跨应用运行周期恢复历史

- 模式：Event-Driven
- 正文：当应用发现上一运行周期遗留的监控数据库时，数据库构件应清除其中的监控历史数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-040｜保证数据库正确关闭

- 模式：Event-Driven
- 正文：当应用正常退出时，数据库构件应关闭 SQLite 连接。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-041｜数据库与应用运行生命周期一致

- 模式：Event-Driven
- 正文：当应用正常退出时，数据生命周期构件应删除本次运行产生的监控数据库。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-042｜运维日志不能跟随监控数据消失

- 模式：State-Driven
- 正文：在监控数据库被删除时，日志构件应保留独立错误日志。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[13](13-operations-distribution.md)的v1契约实现；执行W03/W06与TC-RETENTION/TC-LIFECYCLE，结果见17；有方案不等于已通过。

## 实时与历史展示

### REQ-043｜CPU热区主指标的EMA展示

- 模式：State-Driven
- 正文：在菜单栏存在有效 CPU 热区最高温度 EMA 数据时，菜单栏构件应显示该固定成员派生主指标的最新 EMA 温度。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-044｜摄氏一位小数

- 模式：State-Driven
- 正文：在菜单栏显示 CPU 主温度时，菜单栏构件应使用摄氏度和一位小数格式。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-045｜数字面板不直接展示 Raw

- 模式：State-Driven
- 正文：在实时数字面板存在有效温度数据时，数字面板构件应显示对应传感器的最新 EMA 温度。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-046｜降低柱体高频抖动

- 模式：State-Driven
- 正文：在柱状图显示实时温度时，柱状图构件应使用各传感器最新 EMA 温度。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-047｜实时折线读取内存EMA

- 模式：State-Driven
- 正文：在实时折线图显示最近 5 分钟以内数据时，折线图构件应通过实时查询服务读取 EMA Ring Buffer。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线；C11允许实时内存路径
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-048｜长期图表禁止读取全部高频数据

- 模式：State-Driven
- 正文：在历史折线图显示超过 5 分钟的数据时，折线图构件应依据时间范围读取对应聚合层级。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-049｜防止历史压缩掩盖温度峰值

- 模式：State-Driven
- 正文：在历史图使用聚合数据时，图表构件应保留对应窗口的 `max` 信息。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

## 查询层级

### REQ-050｜最近五分钟实时范围

- 模式：State-Driven
- 正文：在用户查询最近 5 分钟时，历史查询入口应路由到 EMA Ring Buffer 并返回本会话有效范围内的数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线；C11允许实时内存路径
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-051｜短期历史

- 模式：State-Driven
- 正文：在用户查询超过 5 分钟且不超过 1 小时时，历史查询构件应读取 1 秒聚合数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-052｜中期历史

- 模式：State-Driven
- 正文：在用户查询超过 1 小时且不超过 24 小时时，历史查询构件应读取 10 秒聚合数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

### REQ-053｜长期历史

- 模式：State-Driven
- 正文：在用户查询超过 24 小时且不超过 72 小时时，历史查询构件应读取 1 分钟聚合数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[07](07-native-ui.md)的v1契约实现；执行W03/W07与TC-UI/TC-HISTORY，结果见17；有方案不等于已通过。

## 采集重试

### REQ-054｜短暂读取错误允许快速恢复

- 模式：Unwanted
- 正文：如果一次传感器读取发生暂时性失败，则温度采集构件应按照 50 ms、100 ms、200 ms 的间隔执行最多 3 次重试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-055｜禁止成功后继续重试

- 模式：Event-Driven
- 正文：当任意一次传感器重试成功时，温度采集构件应结束本轮重试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-056｜建立确定的失败出口

- 模式：Unwanted
- 正文：如果传感器读取经过 3 次重试仍失败，则故障管理构件应生成 `SENSOR-READ-002`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-057｜无效值进入同一重试机制

- 模式：Unwanted
- 正文：如果传感器返回无效温度值，则温度采集构件应将该结果视为一次读取失败。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

## 数据库重试

### REQ-058｜允许短时锁竞争和 I/O 波动恢复

- 模式：Unwanted
- 正文：如果 SQLite 操作发生暂时性失败，则数据存储构件应按照 100 ms、250 ms、500 ms、1000 ms、2000 ms 的间隔执行最多 5 次重试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-059｜建立成功出口

- 模式：Event-Driven
- 正文：当任意一次 SQLite 重试成功时，数据存储构件应结束本轮重试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-060｜确定写失败错误码

- 模式：Unwanted
- 正文：如果 SQLite 写入经过 5 次重试仍失败，则故障管理构件应生成 `DB-WRITE-003`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-061｜读取和写入故障分离

- 模式：Unwanted
- 正文：如果 SQLite 读取经过 5 次重试仍失败，则故障管理构件应生成 `DB-READ-004`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-062｜损坏不进行无意义重试

- 模式：Unwanted
- 正文：如果数据库完整性检查确认数据库损坏，则故障管理构件应直接生成 `DB-CORRUPT-006`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-063｜结构性错误不进入暂时故障重试

- 模式：Unwanted
- 正文：如果数据库 schema 与当前应用版本不兼容，则故障管理构件应直接生成 `DB-SCHEMA-007`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

## 加工重试

### REQ-064｜避免单个任务无限循环

- 模式：Unwanted
- 正文：如果一次数据加工任务发生暂时性执行失败，则对应加工构件应按照 50 ms、100 ms、200 ms 的间隔执行最多 3 次重试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-065｜EMA 独立定位

- 模式：Unwanted
- 正文：如果 EMA 任务经过 3 次重试仍失败，则故障管理构件应生成 `PROC-EMA-002`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-066｜聚合独立定位

- 模式：Unwanted
- 正文：如果聚合任务经过 3 次重试仍失败，则故障管理构件应生成 `PROC-AGG-003`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-067｜趋势独立定位

- 模式：Unwanted
- 正文：如果趋势任务经过 3 次重试仍失败，则故障管理构件应生成 `PROC-TREND-004`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

## UI 读取重试

### REQ-068｜短暂故障不立即终止界面

- 模式：Unwanted
- 正文：如果 UI 数据读取发生暂时性失败，则前端数据构件应按照 100 ms、250 ms、500 ms 的间隔执行最多 3 次重试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-069｜用户仍能看到已有状态

- 模式：State-Driven
- 正文：在 UI 数据读取重试期间，前端构件应显示最后一次成功取得的缓存数据。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-070｜禁止将旧数据伪装成实时数据

- 模式：State-Driven
- 正文：在 UI 显示缓存数据时，前端构件应显示数据暂时未更新状态。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-071｜建立失败出口

- 模式：Unwanted
- 正文：如果 UI 数据读取经过 3 次重试仍失败，则故障管理构件应生成 `UI-DATA-001`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

## 致命故障

### REQ-072｜关键故障与可选能力分级

- 模式：Event-Driven
- 正文：当关键 CPU 主指标、存储、加工或关键 UI 数据故障达到对应重试上限时，故障管理构件应提升为 Fatal；可选 SSD/Battery 的单项读取耗尽应标为不可用并保留 CPU 监控。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-073｜结构性失败与能力缺失分级

- 模式：Event-Driven
- 正文：当不可重试的关键链路结构性故障产生时，故障管理构件应立即标为 Fatal；可选指标能力缺失、权限不足或映射未知应标为不可用并说明原因。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-074｜保证诊断证据

- 模式：Event-Driven
- 正文：当 Fatal 故障产生时，日志构件应写入对应错误日志。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-075｜生成用户可提交的故障材料

- 模式：Event-Driven
- 正文：当 Fatal 故障产生时，错误报告构件应生成本次错误报告。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-076｜用户获得稳定故障标识

- 模式：Event-Driven
- 正文：当 Fatal 报告写入结束或写入失败已兜底记录时，错误界面应显示原始错误代码。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-077｜确定后续操作

- 模式：Event-Driven
- 正文：当 Fatal 错误界面显示时，界面应提示用户重新启动应用，并提供打开报告、复制详情和退出操作。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-078｜确定最终状态

- 模式：Event-Driven
- 正文：当用户在 Fatal 界面选择退出或界面可见满 30 秒时，系统应在 5 秒收尾预算内停止当前运行，并记录未完成清理以供下次启动处理。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

## 错误报告与编码

### REQ-079｜错误追踪主键

- 模式：Event-Driven
- 正文：当错误报告生成时，错误报告构件应记录稳定错误代码。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-080｜定位故障模块

- 模式：Event-Driven
- 正文：当错误报告生成时，错误报告构件应记录发生故障的构件名称。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-081｜判断重试行为是否符合规格

- 模式：Event-Driven
- 正文：当错误报告生成时，错误报告构件应记录实际重试次数。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-082｜定位具体传感器

- 模式：Event-Driven
- 正文：当传感器相关错误报告生成时，错误报告构件应记录对应 `sensor_id`。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-083｜错误码属于外部诊断契约

- 模式：Ubiquitous
- 正文：同一种故障语义应在不同版本中保持相同错误代码。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

### REQ-084｜避免一个代码覆盖多个根因

- 模式：Ubiquitous
- 正文：不同故障语义应使用不同错误代码。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[06](06-error-handling.md)、[13](13-operations-distribution.md)的v1契约实现；执行W05/W06与TC-ERROR，结果见17；有方案不等于已通过。

## Git 与 GitHub

### REQ-085｜保证功能隔离

- 模式：Event-Driven
- 正文：当开始独立功能开发时，开发人员应从最新主分支创建 feature branch。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-086｜主分支必须经过门禁

- 模式：Ubiquitous
- 正文：GitHub 应禁止直接向主分支推送功能代码。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-087｜测试是合并前置条件

- 模式：State-Driven
- 正文：在 feature branch 尚未通过规定测试时，GitHub 应阻止对应 Pull Request 合并。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-088｜建立缺陷追踪

- 模式：Event-Driven
- 正文：当测试发现可复现缺陷时，项目流程应创建对应 GitHub Issue。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-089｜建立修改追踪关系

- 模式：Event-Driven
- 正文：当提交缺陷修复 Pull Request 时，该 Pull Request 应关联对应 GitHub Issue。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-090｜单元测试进入自动门禁

- 模式：State-Driven
- 正文：在 feature branch 申请合并前，CI 应完成所有自动化单元测试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-091｜零失败原则

- 模式：State-Driven
- 正文：在任一自动化单元测试失败时，GitHub 应禁止对应 Pull Request 合并。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-092｜给核心模块建立最低可量化门槛

- 模式：State-Driven
- 正文：在核心逻辑 feature branch 申请合并前，测试报告应证明10中规定的产品核心逻辑代码行覆盖率至少为 80%。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-093｜避免只测试正常输入

- 模式：State-Driven
- 正文：在核心算法 feature branch 申请合并前，测试流程应覆盖正常路径、边界路径和错误路径。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-094｜需求规格直接成为黑盒测试依据

- 模式：State-Driven
- 正文：在用户可见功能 feature branch 申请合并前，测试流程应执行对应 EARS 验收测试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-095｜已知严重缺陷不得进入主干

- 模式：State-Driven
- 正文：在 Pull Request 存在未解决阻塞 Issue 时，GitHub 应阻止该 Pull Request 合并。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-096｜自动检查属于强制门禁

- 模式：State-Driven
- 正文：在 Pull Request 的 CI 未全部通过时，GitHub 应阻止该 Pull Request 合并。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-097｜保留分支合并节点

- 模式：Event-Driven
- 正文：当 Pull Request 满足全部门禁时，GitHub 合并流程应创建独立 merge commit。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-098｜满足项目审计要求

- 模式：Event-Driven
- 正文：当 feature branch 合并完成时，GitHub 仓库应保留该远程 feature branch。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)、[10](10-test-strategy.md)的v1契约实现；执行W00/W11与TC-WORKFLOW，结果见17；有方案不等于已通过。

## 阶段测试

### REQ-099｜编码前设计门禁

- 模式：State-Driven
- 正文：在进入 M2 前，项目应完成需求基线和架构设计评审。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

### REQ-100｜验证数据链

- 模式：State-Driven
- 正文：在 M2 完成时，测试流程应对传感器、数据加工和 SQLite 数据路径执行集成测试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

### REQ-101｜验证原生 UI

- 模式：State-Driven
- 正文：在 M3 完成时，测试流程应对菜单栏、透明面板和主窗口执行 UI 黑盒测试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

### REQ-102｜验证全部构件协作

- 模式：State-Driven
- 正文：在 M4 完成时，测试流程应执行完整系统测试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

### REQ-103｜Release Candidate 直接对应需求基线

- 模式：State-Driven
- 正文：在 M5 完成时，测试流程应执行最终 EARS 验收测试。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

### REQ-104｜形成开发阶段门禁

- 模式：State-Driven
- 正文：在任一里程碑存在未解决阻塞缺陷时，开发流程应禁止进入下一里程碑。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

## 编码前文档

### REQ-105｜封闭“所有文档”的范围

- 模式：State-Driven
- 正文：在首次进入 M2 前，项目应完成本规格列明的 13 类设计文档。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

### REQ-106｜防止未确定业务规则被编码 Agent 自行填充

- 模式：State-Driven
- 正文：在任一必需设计文档仍含阻塞级待澄清事项时，项目应禁止进入正式功能编码阶段。
- 状态：现行基线／产品未验收
- 来源：C01（v0.3 对应原条号）；C10交接基线
- 验收边界：按[12](12-development-plan.md)、[10](10-test-strategy.md)的v1契约实现；执行W11与TC-DOCS/TC-ACCEPTANCE，结果见17；有方案不等于已通过。

## 补充范围与后续讨论

### REQ-107｜本地部署

- 模式：Ubiquitous
- 正文：CPU 温度监控系统应在本地计算机上运行。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-108｜原生界面

- 模式：Ubiquitous
- 正文：CPU 温度监控系统应采用 macOS 原生应用界面提供交互。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-109｜目标机型

- 模式：Ubiquitous
- 正文：CPU 温度监控项目应将目标机型限定为 Apple Silicon MacBook Air。
- 状态：现行基线／产品未验收
- 来源：C04；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-110｜最低系统与按证据声明支持

- 模式：Ubiquitous
- 正文：项目应将最低运行系统设为 macOS 15.7.3，并仅对完成正式构建验收的机型、系统版本与 build 组合声明支持。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-111｜最高版本核对

- 模式：State-Driven
- 正文：在每次 Release Candidate 冻结时，项目兼容性矩阵应记录当时 Apple 已正式发布的最高稳定版 macOS。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-112｜单机运行

- 模式：State-Driven
- 正文：在无远端业务服务器的条件下，CPU 温度监控系统应完成本地核心监控功能。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-113｜固定CPU热区最高温度

- 模式：Ubiquitous
- 正文：CPU主指标构件应按固定配置内同批有效CPU温度来源Raw的最大值生成“CPU热区最高温度”，保留成员、定义版本和证据说明，不将其称为物理Package或全芯片绝对热点。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-114｜已删除：逐物理核心温度

- 模式：Ubiquitous
- 历史正文（不再生效）：温度采集构件应取得各 CPU Core 的温度。
- 状态：已删除，不纳入实现与验收
- 来源：C01原要求；C09明确删除
- 验收边界：不适用。不再为逐核映射阻塞发布，不把该功能预设为后续版本承诺；保留CPU温度来源／热区监测。

### REQ-115｜SSD能力与不可用状态

- 模式：Ubiquitous
- 正文：当唯一内置NVMe SMART温度来源可用时，采集构件应取得其composite温度；不支持、身份不明确或单项重试耗尽时，SSD应显示不可用及原因。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-116｜电池能力与不可用状态

- 模式：Ubiquitous
- 正文：当按配置选中的内置电池温度来源可用时，采集构件应取得该单一来源温度；无合格来源或单项重试耗尽时，Battery应显示不可用及原因。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)、[09](09-technology-selection.md)、[20](20-feasibility-and-reuse.md)的v1契约实现；执行W02/W08/W09与TC-PLATFORM/TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-117｜菜单栏交互

- 模式：Event-Driven
- 正文：当用户点击菜单栏图标时，界面构件应显示温度信息弹出面板。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-118｜弹出面板

- 模式：State-Driven
- 正文：在温度信息弹出面板打开时，面板应显示当前可用硬件的EMA温度，并为不可用、缓存或过期指标显示明确状态。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-119｜透明视觉

- 模式：Ubiquitous
- 正文：温度信息弹出面板应使用 macOS 原生半透明视觉效果。
- 状态：现行基线／产品未验收
- 来源：C01；C09授权借鉴开源前端；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-120｜主窗口数字

- 模式：State-Driven
- 正文：在主窗口打开时，主窗口应显示当前可用硬件的EMA温度和不可用、缓存或过期状态。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-121｜主窗口设置

- 模式：State-Driven
- 正文：在主窗口打开时，主窗口构件应显示 CPU 采样档位选择控件。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-122｜柱状图

- 模式：State-Driven
- 正文：在主窗口打开时，主窗口构件应显示温度柱状图。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-123｜折线图

- 模式：State-Driven
- 正文：在主窗口打开时，主窗口构件应显示温度折线图。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)的v1契约实现；执行W07与TC-UI，结果见17；有方案不等于已通过。

### REQ-124｜数据库选择

- 模式：Ubiquitous
- 正文：CPU 温度监控系统应将监控数据持久化到本地 SQLite 数据库。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[04](04-data-storage.md)的v1契约实现；执行W03与TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-125｜取消告警

- 模式：Ubiquitous
- 正文：CPU 温度监控项目应将高温告警功能排除在当前版本范围之外。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)、[13](13-operations-distribution.md)的v1契约实现；执行W07/W08与TC-UI/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-126｜取消自启动

- 模式：Ubiquitous
- 正文：CPU 温度监控项目应将登录后自动启动功能排除在当前版本范围之外。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[07](07-native-ui.md)、[13](13-operations-distribution.md)的v1契约实现；执行W07/W08与TC-UI/TC-LIFECYCLE，结果见17；有方案不等于已通过。

### REQ-127｜独立分发

- 模式：Ubiquitous
- 正文：CPU 温度监控项目应通过 Mac App Store 之外的渠道分发应用。
- 状态：现行基线／产品未验收
- 来源：C04；C10交接基线
- 验收边界：按[13](13-operations-distribution.md)的v1契约实现；执行W10与TC-RELEASE，结果见17；有方案不等于已通过。

### REQ-128｜协作工具

- 模式：Ubiquitous
- 正文：项目开发流程应使用 Git 与 GitHub 管理代码和协作记录。
- 状态：现行基线／产品未验收
- 来源：C01；C10交接基线
- 验收边界：按[11](11-git-github-workflow.md)的v1契约实现；执行W00与TC-WORKFLOW，结果见17；有方案不等于已通过。

### REQ-129｜动态切换历史

- 模式：Event-Driven
- 正文：当用户切换 CPU 采样档位时，存储构件应保留本会话中仍在保留期限内的已有历史数据。
- 状态：现行基线／产品未验收
- 来源：ATT-01、C01；C10交接基线
- 验收边界：按[04](04-data-storage.md)、[08](08-component-design.md)的v1契约实现；执行W03/W05与TC-SCHEDULE/TC-STORAGE，结果见17；有方案不等于已通过。

### REQ-130｜图表缺口

- 模式：State-Driven
- 正文：在相邻有效采样之间存在已识别的数据缺口时，图表构件应断开跨越该缺口的折线连接。
- 状态：现行基线／产品未验收
- 来源：ATT-01、C03；C10交接基线
- 验收边界：按[05](05-processing-pipeline.md)、[07](07-native-ui.md)的v1契约实现；执行W04/W07与TC-TREND/TC-UI，结果见17；有方案不等于已通过。

### REQ-131｜趋势缺口

- 模式：State-Driven
- 正文：在趋势窗口跨越已识别的数据缺口时，趋势构件应停止输出跨缺口计算的趋势结果。
- 状态：现行基线／产品未验收
- 来源：ATT-01、C03；C10交接基线
- 验收边界：按[05](05-processing-pipeline.md)、[07](07-native-ui.md)的v1契约实现；执行W04/W07与TC-TREND/TC-UI，结果见17；有方案不等于已通过。

### REQ-132｜来源分类证据真实性

- 模式：Unwanted
- 正文：如果某温度来源没有本机验证或固定上游分类依据，则来源描述应标为unknown并只供诊断；仅有上游分类时标为referenceClassified，不伪称targetQualified或物理位置已证实。
- 状态：现行基线／产品未验收
- 来源：C03、C04；C09删除逐核范围后保留真实性约束；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)的v1契约实现；执行W02/W09与TC-SENSOR，结果见17；有方案不等于已通过。

### REQ-133｜Raw 峰值

- 模式：Event-Driven
- 正文：当算法生成某个时间窗口的原始峰值结果时，聚合构件应使用该窗口有效 Raw 样本的最大值。
- 状态：现行基线／产品未验收
- 来源：C03、C04；C10交接基线
- 验收边界：按[05](05-processing-pipeline.md)的v1契约实现；执行W04与TC-AGG，结果见17；有方案不等于已通过。

### REQ-134｜新鲜度真实性

- 模式：Unwanted
- 正文：如果读取接口没有提供可验证的测量更新时间信息，则采集记录构件应将测量新鲜度标为未知。
- 状态：现行基线／产品未验收
- 来源：C03、C04；C10交接基线
- 验收边界：按[03](03-sensor-acquisition.md)的v1契约实现；执行W02/W09与TC-SENSOR/TC-SCHEDULE，结果见17；有方案不等于已通过。
