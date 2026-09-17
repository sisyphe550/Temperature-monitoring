# 构件详细设计草案

更新日期：2026-09-17。状态：**职责与接口层面的推荐草案**。不是已经完成的类图、函数签名或实现代码。

## 构件契约

| 构件 | 输入 | 输出 | 关键约束 |
|---|---|---|---|
| SensorDiscovery | 机型、系统、候选 provider | 原始传感器描述与能力状态 | 不把未知映射改名为 CPU Core |
| SourceRegistry | 发现结果、版本化映射与证据 | 有源实例身份的活动集合 | 同名不合并；重连失效元数据缓存 |
| MetricResolver | 固定成员样本、指标定义 | 派生读数或缺失原因 | 保存成员与批次跨度；单源失败不偷偷缩小集合 |
| TemperatureProvider | 原始传感器 ID、读取请求 | 读数或结构化错误 | 保留来源单位、底层错误；同步阻塞能力需验证 |
| SamplingService | CPU 档位、SSD/Battery 周期、生命周期事件 | 已带时间信息的读取结果 | 普通读取与重试不能无界重叠 |
| TaggingValidator | 原始读取及描述 | 有效 Raw 或明确拒绝原因 | 无效数据不进入统计 |
| RawBuffer | 有效 Raw | 有界窗口快照 | 同时满足时间范围和容量约束 |
| EMAProcessor | 连续有效 Raw、tau、时钟 | EMA 值 | 按真实 dt；初始化／重置待定义 |
| BucketAggregator | Raw／低层窗口 | 高层聚合 | 原始 min/max；确定 avg 口径；幂等 |
| TrendProcessor | EMA 时间窗口 | 斜率或数据不足状态 | 不跨缺口回归；最小数据量待定 |
| StorageWriter | Raw、EMA、聚合、趋势批次 | 提交结果 | 单写入通道、事务、有界待写队列 |
| HistoryQuery | 传感器集合、时间范围 | 合适粒度的序列 | 本会话、72 小时、实际保留层级 |
| RetentionService | 当前时间、各 TTL | 清理结果 | 查询过滤与物理清理分开 |
| PresentationModel | 实时快照、历史序列、故障状态 | 可显示数据与交互状态 | 不持有底层传感器连接 |
| ErrorCoordinator | 构件错误、重试结果 | 重试／报告／退出决策 | 能力不支持与暂时失败区分 |
| Diagnostics | 错误上下文 | 独立日志与报告 | 数据库失败时仍可尝试记录 |
| SessionLifecycle | 启动、退出、睡眠与唤醒 | 会话、采样启动／停止事件 | 清理上一会话；唤醒产生缺口 |

## 数据依赖

传感器 API 类型只存在于适配边界。Processing 接收内部模型，不依赖 SwiftUI、SMC 或 SQLite 类型。Presentation 依赖服务接口；Storage 不依赖具体视图。

测试依赖注入：模拟 provider、受控时钟、固定算法参数、独立临时数据库、可注入错误的存储接口。模拟数据必须标记为测试来源，不能在实机界面冒充硬件数据。

## 建议状态模型

应用：Initializing → Discovering → Running → Stopping → Stopped；FatalReporting 为故障退出路径。能力状态与运行状态分开记录，例如 Supported／Unsupported／PermissionDenied／MappingUnknown。

样本：Valid、Invalid、FreshnessUnknown；缓存是否 Stale 取决于已定义的时间阈值，不用“值相同”推导 Stale。

以上状态名称为概念建议。状态迁移时机和最终枚举需在 OQ-05/OQ-08/OQ-11 解决后确定，不作为现成实现契约。

## 收尾与幂等

建议在停机时停止新调度，取消尚未启动的任务，按明确策略处理进行中的读取与待写批次，结束聚合并关闭数据库。底层调用可能不能取消，不能用“设置取消标志”冒充调用已经结束。

同一批次或样本重试不得双重入库、重复累计 count 或使 EMA 计算两次。实现需定义样本序号、批次 ID、窗口键及事务边界。当前这些属于待完成的详细设计。

## 实现前还需输出

正式接口签名与线程约束、启动及退出时序图、schema 与迁移／重置策略、超时和背压预算、错误传播关系、测试替身接口。相关问题统一见 [待决策](16-open-questions.md)，本草案不伪装成全部详细设计已经完成。

来源：C04 架构建议及本轮分类整理中的必要接口细化。

2026-09-17 细化见 [19](19-reference-informed-design.md)：发现与高频读取分开；样本有效性、映射状态、新鲜度分别记录；存储重试保持 sampleID，来源／定义更改开始新连续段。新增构件是推荐设计，尚未实现。
