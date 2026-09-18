# 总体架构与运行时边界

更新：2026-09-17；C10交接设计基线v1，尚未实现生产App。参数与类型以[契约](21-implementation-contracts.md)为准。

## 确定的结构

Swift模块化单体，SwiftUI＋AppKit界面，SQLite嵌入式数据库。主App拥有调度、加工、存储与UI；**一个普通用户权限的自有SensorWorker子进程**拥有同步硬件句柄。它随App启动/结束，不是root服务、登录项或第三方CLI。分进程是为了避免同步驱动调用卡住界面，不改变本地部署边界。

选择依据：原型与macmon证明只读SMC/HID桥接路线；MacFanControl仅参考分层思想；进程隔离属于本项目工程设计，使用系统[Foundation Process](https://developer.apple.com/documentation/foundation/process)，不能说开源项目已经实现了本产品完整架构。

## 唯一数据路径

C11用户明确课程不强制数据库往返，采用优化方案：

```mermaid
flowchart TD
    H[SensorWorker: SMC / SMART / IOPS] --> S[调度与校验]
    S --> R[Raw Ring Buffer]
    R --> E[每来源 EMA]
    R --> A[Raw 聚合 / 峰值]
    R --> M[固定成员 max]
    M --> E
    M --> A
    E --> T[趋势]
    E --> V[实时快照与 EMA Buffer]
    S --> Q[有界持久化队列]
    M --> Q
    E --> Q
    A --> Q
    T --> Q
    Q --> W[SQLite 单写入事务]
    W --> D[(会话数据库)]
    D --> HQ[历史查询]
    V --> UI[菜单栏 / 面板 / 主窗口]
    HQ --> UI
```

Raw与EMA都持久化，保留各5分钟。菜单栏、数字、柱图和最近5分钟曲线使用内存EMA；1h/24h/72h历史读SQLite。视图不访问驱动或SQLite连接。实时值可能比已提交历史新至一个批量写入周期；数据库故障时明确显示暂未写入状态并停止新采集，不能把实时显示冒充已经持久化。

## 模块与所属执行环境

| 构件 | 所属环境 | 核心职责 |
|---|---|---|
| SensorWorker | 子进程串行命令循环 | 打开/枚举/读取/关闭；只发送读数和能力；不做EMA/数据库 |
| WorkerClient | 主进程专用IO队列＋actor状态 | 有界协议、请求截止时间、generation、回收；异步回调返回 |
| SourceRegistry／MetricResolver | MonitorEngine actor | 来源身份、固定定义、CPU派生；不猜物理核 |
| SamplingService | MonitorEngine actor＋SystemClock | CPU/SSD/Battery日程、重试、背压预留 |
| ProcessingEngine | 同一个MonitorEngine actor，构造时注入PersistenceQueue | 顺序推进Raw/EMA/聚合/趋势/缺口；不可重复处理sampleID；接纳方法内部完成队列交付 |
| StorageWriter | 专用串行DispatchQueue | 一个写连接；不可变批次事务；不在Swift协作线程池阻塞SQLite |
| HistoryQuery | 一个只读连接＋专用串行队列 | 最多一个当前查询；取消旧请求，结果按requestID匹配 |
| PresentationModel | MainActor | 最多5Hz快照；隐藏图表停止绘制；保留一个最新查询结果 |
| SessionCoordinator | 主进程actor；UI操作转MainActor | 单实例锁、启动、休眠、正常退出、Fatal |

对外异步协议见[api-v1.swift](contracts/api-v1.swift)。actor内部不能同步等子进程/SQLite；异步调用前后用generation和会话状态校验，防止actor重入使停止后结果重新进入链路。

## 原子接纳与有界交付

启动每条读取前为最坏输出预留512条记录容量；所有Raw/EMA/聚合/趋势/缺口及在途事务都计数，总上限16384条、序列化载荷32MiB。到12288条暂停新的读取，低于8192条恢复并开启新连续段。必须给在途结果留好预留空间，不能先读完再决定丢弃。

SamplingService先取得只能消费一次的QueueReservation，再随ReadBatch／水位事件／Gap传给MonitorEngine。加工器在临时状态上生成不可变PersistenceBatch，通过注入的PersistenceQueue以该预留入队；收到队列接纳确认后才交换加工状态并发布快照，随后才返回批次的审计副本。调用者不得再次append这个返回值。入队失败则临时状态作废并释放预留。同一requestID重复交付不再次加工。StorageWriter只排空已接纳队列；数据库重试仅重试同一个batchID与原内容。背压暂停、超过截止时间、失败读数产生Gap，不伪造0或重放旧值。

队列最老批次超过10秒即`DB-BACKPRESSURE-008` Fatal。容量和期限是v1保护参数，测试中必须验证；它们不是已经测得的性能水平。

## 进程与状态机

`Initializing → Discovering → Running ↔ Paused/Suspended → Stopping → Stopped`；任一关键失败转`FatalReporting → Stopping`。SSD/Battery单项不可用只影响能力状态。

读取请求1秒、发现10秒截止；超时丢弃请求响应，SIGTERM后250ms未退出则SIGKILL，确认退出后才启动替代worker。禁止靠Task.cancel声称取消驱动调用；若操作系统未回收子进程，停止重建并Fatal，不无界积累。子进程管道EOF自动结束；App单实例生命周期控制见[13](13-operations-distribution.md)。

这一设计允许完成App实现，但发布前必须验证进程签名、实机权限和故障回收。CLI已读通并不等于最终App已验收。
