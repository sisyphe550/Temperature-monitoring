# 2026-10-03 c354b03 长测：维护暂停与Worker RSS只读审查

## 审查边界

现场 `/tmp/temperature-long-ui-20261003T043223Z`，会话 `ad735257-fea5-41a0-8e1b-644c8d2bc191`，AppPID88391、WorkerPID88506。源码c354b03、binary9f786由root指明；本文只读现有源码、长测log、观察JSONL、事件JSONL和已有rolling SQLite备份。不编译、不运行tests/App/GUI/压力，不写运行中的App数据库，不修改生产代码，不创建Issue。rolling日志仍增长，以下输出是审查时提取的固定观察，不能代替最终验收原件。

## 已证实事实

### SQL timeout Gap是成功样本的观察间隔，不是此次硬件超时错误

读取rolling snapshot得CPU Max的五个Gap：

| start→end elapsed秒 | 缺口秒数 | 结束后新segment.reason | 下个start距本次end秒数 |
|---|---:|---|---:|
|542.049534458→543.199658083|1.150123625|gap|59.948791875|
|603.148449958→604.721088166|1.572638208|gap|59.948892917|
|664.669981083→666.469932958|1.799951875|gap|60.003862708|
|726.473795666→728.676738208|2.202942542|gap|59.997191792|
|788.673930000→791.269567166|2.595637166|gap|—|

该提取时全库新增segments中69个reason=gap，零recovery；gap为CPU Max5、CPU12×5=60、SSD4，battery零。worker PID/source generation保持相同。

`MonitorEngine.swift:743-768`有两条完全不同路径：已有openGap恢复时segment.reason=recovery；若没有openGap而相邻成功finished时间超 `max(3×period,1s)`，直接产生闭合Gap(reason=timeout)，segment.reason=gap。本次SQL证据对应后者。`MonitorEngine.swift:163-169,244-252`与`SamplingService.swift:425-438`才是明确SensorTimeout失败→openGap→恢复路径；`WorkerClient.swift:182-184`真正管道超时会终止worker并产生timeoutFailure。不能根据数据库reason字符串timeout就写“SMC/worker读取超时”。此次准确表述为“相邻成功观测出现1.15至2.60秒暂停，按契约断线并新建连续段”。

首次50ms phase实际持有601.237771awake秒是runner完成事实，完整Raw数量/理想频率短缺也仍不等于SamplingStatistics.skippedByKind真实计数。是否满足全部性能门槛需root最终审查。

### 维护IO在专用DispatchQueue，等待commit使后续采样停顿

- `SessionMonitorController.swift:275-285`每次等待到期→await performMaintenance→以完成时刻+60秒安排下一次；不是严格每60秒原点调度。
- `SessionPersistence.swift:291-308`先acquireOperation，整个RetentionEngine.prune期间保持同一operation gate，返回后release。
- `SessionPersistence.swift:512-523`把同步SQLite操作移交专用`com.temperaturemonitor.session-persistence.io`队列，continuation挂起actor。DELETE不是直接跑在SamplingService actor，也没有证据说明它封住所有Swift executor。
- `SessionPersistence.swift:202-211`正常commit竞争同一operation gate。
- `SamplingService.swift:459-462`每读批await onRead handler→`ProcessingCoordinator.swift:171-178`await engine.accept→`MonitorEngine.swift:265`await commit后才交换状态；该循环等receipt后才发下一读取。

因此即使prune不阻塞actor执行线程，它仍可通过“prune持operation gate→本次commit等门→采样循环等commit receipt”阻止下一批采样。不能通过改成Task.detached或换一个actor就认定修复，因为共享数据库写序仍在。

### DELETE的查询计划有随聚合历史增长的候选成本

`Retention.swift:92-131`将所有层DELETE及committed batch清理放在单个BEGIN IMMEDIATE事务，再做PASSIVE checkpoint与容量检查。Raw/EMA每60秒待删约一分钟的多来源样本；不得取消已提交父聚合检查。

`Retention.swift:224-254`使用每个Raw/EMA行correlated EXISTS寻找1秒聚合父：series/segment/width等值＋start<=sample.elapsed<end。对已有snapshot只执行EXPLAIN QUERY PLAN，没有执行DELETE：

- 外层 raw_by_time/ema_by_time `(elapsed_ns<?)`。
- 子查询 `sqlite_autoindex_aggregates_1 (series_id=? AND segment=? AND width_s=? AND start_elapsed_ns<?)`。

父窗口查找是历史start前缀范围，而非完整1秒bucket键等值查找。随着该segment的1秒aggregates积累，每个expired sample可能检查更多历史窗口。这是源代码及query plan支持的成本假设，尚未记录语句step次数、DELETE时耗或prune起止，不能把它定为已重现根因。

Gap在上次end后约60秒再发生、暂停时长递增，与维护循环“完成+60秒”高度吻合；但尚缺直接时间trace，相关性不能代替原因验证。

## 排序的可证伪假设

1. **父1秒聚合correlated range lookup增大DELETE时耗，prune的operation gate拖住commit。** 预测：复制snapshot基线Retention事务耗时应随聚合历史长度增长；语句step主要集中Raw/EMA父窗口查找；使用不改变父存在判定的精确bucket键查找后明显下降，真实采样暂停也下降。
2. **checkpoint或其他层/committed batch DELETE是主因。** 预测：分段计时显示Raw/EMA非主要成本，WAL checkpoint/其他操作覆盖pause长度。当前观察WAL几MiB未到32MiB软限，因此TRUNCATE容量分支不是首选，但PASSIVE仍需测。
3. **本机其他CPU/IO活动或实际worker读取慢。** 预测：没有prune也出现等长暂停，或worker读started→finished本身跨pause。现有成功Raw仅保存finished，无法精确拆分driver/read/commit等待；外部负载口径尚需控制。全部worker/source保持generation1、segment=gap使“真正管道SensorTimeout”解释较弱。
4. **维护后的DiagnosticLogger同步磁盘扫描占controller actor。** `SessionMonitorController.swift:297`和`DiagnosticLogger.swift:108-127`在prune后同步枚举日志文件；当前仅少量日志，因此优先级低，但实际trace应保留这段边界。

## Worker RSS：增长已测，live leak尚未证明

已有ps记录同PID88506：04:32:42 RSS9600KiB→04:42:44 RSS83072KiB→04:50:45 RSS115424KiB。前段相对CPU Max成功读取约+6.20KiB/次，后段CPU100ms约+6.82KiB/次。它与请求数增长相关，值得优先查，但ps RSS是驻留页，含allocator缓存/高水位，不等于仍被引用的live对象或确定泄漏；CPU百分比也不是整个阶段累计预算。

`SensorWorkerEntry.swift:13-22`在main线程长时间同步readLine循环，每帧Data→decodeRequest→HardwareSession.read→JSONSerialization.encodeResponse→String→FileHandle.write，没有每帧autoreleasepool，也没有RunLoop。`WorkerProtocol.swift:151,277-280`使用Foundation JSONSerialization及NSNumber/Any桥接；临时ObjC/CF对象推迟释放是第一候选。持有HardwareSession的SMC键表/设备/探针为固定发现集合，不按read添加条目。

未发现下列确定CF漏释放：SMC读取`SensorBridge.c:88-108`为栈值；HID event在`:199`CFRelease；IOPS Copy对象在`HardwareSession.swift:250-251`takeRetainedValue、description是与info生命周期关联的borrowed对象；NVMe接口在`SensorBridge.c:407-419`Release及销毁plugin。闭合返回和ARC作用域不证明Foundation没有autorelease积累，也不能凭无pool就断言它是唯一原因。

## 长测结束后的最小验证建议

当前保持同二进制完成另外四档与真实sleep。以下都在结束后执行，不在此轮运行期间施压或换binary：

1. 保留最终不可变snapshot及事件/日志，复制到专用/tmp工作库后跑原RetentionEngine，记录每个DELETE与checkpoint的ContinuousClock耗时和SQLITE_STMTSTATUS_VM_STEP；先重现，再改SQL。
2. 在真实AppRuntime/SessionPersistence seam，用可控prune操作或trace证明prune持门时commit等待、下一读取推迟；actor本身仍可响应不依赖该门的查询，以区别“线程被堵”与“正确写序等待”。
3. 若已证实父窗口查询热点，优先将1秒父存在判定改为已契约对齐的bucket.start=floor(sample.elapsed/1秒)×1秒精确键查找，保留series/segment/width/end检查；回归恰好边界、父未提交、跨segment、partial父、级联sample_members和Raw/EMA一致清理。不能先取消EXISTS或扩大TTL。若仍过长，再考虑按小批事务在维护门间允许commit，不破坏先聚合后删除/Grace/幂等。
4. Worker先独立执行同协议decode→模拟12路reading→encode/write循环，分别有无每帧autoreleasepool，并观察每固定请求数的RSS及live allocations/phys_footprint；再以正式Worker低压力确认HardwareSession路径。只证明序列化循环改善时，不提前标整个驱动内存已解决。
5. per-frame pool候选只包请求处理与响应临时对象；HardwareSession/连接在pool外持有，异常可抛出，不能改变generation、EOF/close、请求成员、时间戳或协议。增加真实解码/完整响应/畸形帧/正常关闭回归；随后正式App同50ms同填充复测。
6. 所有优化保持CPU12、五档、Raw/EMA/全部TTL、父聚合完整性和真实Gap，最终将源提交与新App/worker hash一并更新再做验收。

## 输出

- `/tmp/temperature-043223-gap-segment-readonly.json`：SQL Gap/segment与计算时间间隔。
- `/tmp/temperature-043223-retention-query-plan.json`：只读EXPLAIN查询计划。
- `/tmp/temperature-043223-worker-resource-readonly.json`：观察时刻资源与成功CPU事件数（不包括SSD/Battery/retry/skipped）。
