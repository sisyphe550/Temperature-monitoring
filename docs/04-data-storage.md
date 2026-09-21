# 数据模型、SQLite与有界保留

更新：2026-09-21；contract revision 2。[schema-v1.sql](contracts/schema-v1.sql)仍是user_version 1的可执行DDL；[api-v1.swift](contracts/api-v1.swift)定义强类型边界。

## 身份与表

数据库一会话一个，`user_version=1`。`sources`只保存经过Registry资格化的真实接口实例，`series`保存可绘图序列和定义，`series_members`保存固定成员。真实来源使用SeriesFormula.identity，CPU主指标用maximum。SeriesID在成员/定义变更后新建；MetricID保留可见角色，definitionVersion递增。`segments`记录每次缺口后连续段；所有算法和聚合都按SeriesID＋segment隔离。

禁止物理core_id及按核心数预分配槽位。sampleID=`sessionUUID:递增Int64序号`，实际成功重复值仍取得新sampleID；同一已交付结果重试保持旧ID。源时间戳没有就NULL，freshness为unknown。

| 实体 | 主键／用途 |
|---|---|
| session/sources/series/series_members/segments | 元数据与来源、定义、连续段证据 |
| raw_samples | sampleID；真实来源读数与明确标记的派生Raw分别成series |
| sample_members | 派生sampleID→成员sampleID；元数据成员独立长期保留 |
| ema_samples | sampleID；每条EMA关联其输入Raw身份 |
| aggregates | seriesID＋segment＋width_s＋start_elapsed_ns；一份存储，多层视图 |
| samples_1s/10s/1m | aggregates的只读视图；保持REQ命名，写入由width_s区分 |
| trend_samples | seriesID＋segment＋elapsed_ns；不足数据时slope=NULL |
| gaps | 每条缺口独立ID；允许尚未结束的缺口 |
| committed_batches | batchID及载荷SHA-256；幂等提交凭据 |

SMC键COLLATE BINARY区分大小写。原始/EMA/聚合都不能存NaN/Infinity；应用层校验，DDL的NOT NULL不能替代有限数检测。

## Buffer与TTL

| 层 | 保留期 | 查询边界 |
|---|---:|---|
| Raw/EMA内存Buffer | 300s；各8192槽/series | elapsed > now−300s，且elapsed ≤ now |
| Raw/EMA数据库 | 300s | 同上；内存满覆盖最早已交付记录，绝不覆盖待写队列 |
| 1s | 3600s | bucket.end > now−3600s |
| 10s | 86400s | bucket.end > now−86400s |
| 1min | 259200s | bucket.end > now−259200s |
| Trend | 3600s | elapsed > now−3600s |
| gap/series/segments | 72h内仍有引用的数据；活动定义始终保留 | 删除数据后清除无引用且非活动元数据 |

32个active series上限**包含派生主指标**。32×2×8192是Buffer槽位硬上限；窗口过期优先于容量覆盖。初始profile只含12 CPU来源＋1派生＋最多1 SSD＋1电池＝15 series。

每60秒清理；睡眠唤醒立即推进窗口并清理。Raw删除前，其1s父结果必须已提交；1s/10s同理。保留边界使用elapsed单调时间，不能因墙钟回拨无限保存。数据查询立即排除过期行，物理清理可滞后至120秒；超过宽限且无法追赶进入`DB-CLEAN-005`，不无限保留。SQL删除条件为`elapsed_ns <= cutoff`或`end_elapsed_ns <= cutoff`。

空窗口不存0值；闭合水位与缺口保存于加工状态/Gap，不要求为72小时休眠生成数十万空行。父层生成在TTL之前，且同一提交批次或较早批次持久化。

## SessionPersistence与提交契约

SessionPersistence是唯一公开持久化门面，同一个actor向不同调用者提供reserve/cancel、commit、open/query/prune/close三种窄能力视图。内部队列、StorageWriter和SQLiteStore不得由App或SamplingService自行组合。

每个事件在硬件IO或状态推进前取得PersistenceLease。Lease绑定强类型PersistenceOwner、generation、最多512条逻辑记录和估算字节；它不能编码、不能公开构造，只能成功commit一次或cancel一次。复制同一值不产生新容量，错误owner/generation、超容量和第二次消费均为完整性失败。

正常触发：最老待写记录到200ms或累计512条即刷新。一次事务最多512条逻辑记录；一个不可拆分的加工批次若触及上限独占事务，其上限仍为512。记录计数包含成员引用与元数据；入队同时检查32MiB字节上限。在途事务仍计入队列。重试期间200ms不是提交延迟保证。

1. `BEGIN IMMEDIATE`；先查committed_batches。
2. 同batchID、同hash：返回已提交；同ID不同hash：`DB-INTEGRITY-010`。
3. 先插入来源/定义/segment，再插Raw、成员、EMA、最终聚合/趋势/Gap；已存在相同主键必须逐字段一致，不能无条件IGNORE覆盖冲突。
4. 已闭合聚合值是最终值，重试不以`count=count+...`累计。Gap结束是唯一允许的单调更新（NULL→确定结束时间）。
5. 写committed_batches＋hash后COMMIT，收到ack才从内部队列移除并返回ProcessingReceipt。提交成功但响应丢失时用相同BatchID重试，不重复运算。

committed_batches保留10分钟，且有未确认批次时不删其凭据；运行时不允许重试超过10秒的批次。Raw与EMA在一个加工批次提交，避免一半成功。SQLite事务/冲突处理依据[SQLite事务](https://sqlite.org/lang_transaction.html)、[UPSERT](https://sqlite.org/lang_upsert.html)；本项目具体幂等协议自行设计。

## SQLite配置与空间

一个写连接、一个历史读连接，各专用队列。WAL＋synchronous=NORMAL，busy_timeout=0，由统一重试层处理SQLITE_BUSY/LOCKED；避免隐式等待再叠加重试。每连接cache_size=-8192；mmap_size=0，prepared statement使用后reset/finalize；连接关闭前释放所有statement。

WAL checkpoint每60秒PASSIVE，自动阈值1000页；读事务最多250ms，旧图表查询被新请求取消。查询的SQLite progress handler检查取消与截止时间，响应过期时丢弃结果。单次操作的取消属于SQL执行预算，不能保证中断操作系统文件IO。

数据库软限768MiB按`(page_count-freelist_count)×page_size`计算仍被有效数据占用的主库页；主文件物理硬限1GiB，WAL软/硬限32MiB/64MiB。接近任一软限先清理TTL、取消过期读事务、暂停新采集并尝试TRUNCATE checkpoint；有效页和WAL都恢复到各自软限以下后开启Gap新段。这样TTL删除产生的freelist可以解除软限，不依赖文件立即缩小。主文件达到物理硬限、空间不足或最老待写超过10秒则`DB-CAPACITY-009`或`DB-BACKPRESSURE-008`，报告后退出。`max_page_count=262144`在4KiB页面下约束主文件，不代替WAL单独监测。不得删除尚应保留的数据来假装支持72小时。

SQLite删行复用空间、不保证缩小主文件，因此主库软限看有效页、物理硬限看文件字节；不在采样路径跑全库VACUUM。[WAL机制](https://sqlite.org/wal.html)、[PRAGMA](https://sqlite.org/pragma.html)。容量是初始保护参数，长期实测达到硬限即验收失败，须优化或显式修订，不能声称已测足够。

## 历史查询

仅支持以查询时刻为终点的四档最近范围：5min→EMA内存，1h→1s，24h→10s，72h→1min。首版不提供任意过去区间或跨层拼接。查询结果携带层级、实际覆盖和persistedThrough；尚未闭合的最后窗口作为暂未形成历史处理，不补值。

最多同时8条series、每条2000个显示点。SQL按时间范围读本层（最多约8640行/series），再按屏幕分箱，保留min/max包络、加权avg与最新点；不能先LIMIT丢掉较早历史。结果总点数≤16000，旧快照释放。

## 文件与损坏

目录/单实例/清理顺序见[13](13-operations-distribution.md)。异常会话数据库不恢复、不迁移；拿到实例锁后只删除有本应用会话标识的残留目录，再创建新库。当前活动库的user_version不匹配或quick_check损坏直接Fatal，不能悄悄删除当前会话继续运行。
