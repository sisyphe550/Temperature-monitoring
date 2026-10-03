# W11 SQL、TTL 与证据边界独立审查

日期：2026-10-03；审查者为非实现子agent。工作树：`/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring`。执行前已读取AGENTS、00/01/21/22/23/11，按现行contract revision 3处理；没有修改仓库、启动GUI、执行睡眠或重复长测。

## 审查结论

**生产修复及新增测试无阻断发现。** 审查的当前生产HEAD为`f9e850cb6986ca9b22980849c503080c8b5d96ee`。仅批准“两行父桶精确查找＋新增软件回归”这一范围的技术结论，不批准完整W11资格、所有REQ、合并或新App性能通过。

独立读取实际全套Core日志：`/tmp/temperature-w11-retention-final-core.log`，349 tests / 55 suites passed；本审查未重复该全套运行。独立执行官方`python3 scripts/check-core-coverage.py --report Packages/TemperatureCore/.build/arm64-apple-macosx/debug/codecov/TemperatureCore.json`，exit 0，7095/7971=89.01%。实际日志还包含新增RetentionLookupScalingTests/TTLRequirementBoundaryTests编译和执行；Raw VM steps 1358→1358，EMA 978→978。

## Retention 两行算法

- 原两处`start_elapsed_ns <= sample.elapsed_ns`变为`start_elapsed_ns = (sample.elapsed_ns / 1000000000) * 1000000000`，只改变父桶查找，不改变cutoff、系列、segment、width=1、半开end条件、事务、TTL、默认值、schema或API。
- 非负Int64 elapsed是现行契约。整除后的整秒乘积不大于原elapsed，SQLite整数算术不因这两处乘法溢出。
- 05规定以session elapsed=0对齐半开窗口；实际AggregationWindow.index/start与AggregationEngine.ingest均保持该不变量。新segment在750ms开始也生成[0,1s)的partial父桶，按series/segment隔离，不能误用旧段的同秒父桶。
- 新条件命中既有(series_id, segment, width_s, start_elapsed_ns)复合主键。独立in-memory SQLite检查408个样本、不同series/segment/width与缺父桶，Raw/EMA各7个cutoff；旧/新SQL幸存行完全相同。EXPLAIN显示精确四键查找。
- 新回归直接读取实际Retention.swift SQL计算VM工作量，32/2048父桶下过期样本数量固定；它测算法工作而不是机器相关耗时。单独读源码测试不能证明已编译路径，另外四项语义测试实际调用SQLiteStore.deleteRawSamples/deleteEMASamples和commitBatch，补足这一边界。
- 语义测试覆盖真实AggregationEngine的partial父桶、同秒跨段、错系列/宽度/缺父桶、父桶提交后才删除、父桶end点半开、cutoff/+1ns、Raw sample_members级联和重复删除。

## 三个TTL补证的适用性

当前catalog的REQ-031/033/034/035/036/037都只要求software证据；三项新增软件测试逐条覆盖现有outstanding：

| REQ | 新证据 |
|---|---|
| 031 | 1s层3600s的cutoff−1/0/+1ns身份删除/保留 |
| 033 | 1min层259200s的同类边界 |
| 034 | Trend 3600s边界 |
| 035 | 未prune时SQL仍有过期1min记录，threeDays查询独立过滤 |
| 036 | 同一生产prune对Raw/EMA、1s/10s/1min/Trend逐表判定，并保留无父桶Raw/EMA |
| 037 | Controller启动后59.999/60/119.999/120s的虚拟elapsed；两次真实SQLite删除及维护等待重新登记 |

TestClock增加的pendingSleepDeadlinesForTesting仅为测试工具，NSLock保护，并未增加生产注入接口。维护等待是同步屏障，真正执行证据来自库中两次删除；不以时钟常量单独证明执行。

这些向量足以关闭上述明确的软件证据缺口。正式catalog修改仍必须加入最终实际源码、日志hash、测试定位与必需TC，运行binder/validator并只对六项作局部更新。三日查询测试不诊断跨左边界整桶统计政策，不新增产品bug；这些软件测试不是72h实机或三轮物理睡眠通过。

## c354不可变归档复核

独立运行`/tmp/temperature-final-independent-readonly-check.py`，最终exit 0；结果`/tmp/temperature-final-independent-readonly-check.json`。

- 64个manifest条目、文件大小/sha256与gzip解压sha256全部匹配，无遗漏或额外未列文件。
- 末端同Session SQL 344条；144 overlap的所有字段等于原collector，新增200条；并集在原1000ms时间窗内复算641点、elapsed严格递增、span640.010117583s，与ledger一致。
- 归档明确保留原XCTest FAILED；五档duration observed不等同整套自动化、scheduler skipped、read batch latency、first frame或display性能通过。
- scope保留用户原话“跳过休眠测试”，只取消本轮三轮物理验收，不把生命周期功能或整REQ扩为waived；partial观察保持partial。
- 最初发现两个0字节文件event-collector.log/live-monitor.log被文本patch遗漏，root补齐后独立重核通过。该发现已修复，不是现存阻断。

## 文档纠正与待测边界

现行W11计划顶部Goal/Architecture/约束、T3/T4及历史中断段此前仍将403视为当前生产、计划再次睡眠、写337/88.71%或临时证据待集成，和末节最新状态冲突。已仅在/tmp准备纠正patch：`/tmp/temperature-current-w11-plan-corrective.patch`，10490字节，SHA256`9c02286cf7b4f66d7cbca5e0f1bd7356f2d90fe5d55c3d879ae060284953fdc3`。它把当前执行入口更新为c354历史duration＋新SQL最终软件/短测、物理sleep skipped-by-user、性能pending，并将过去时间线明确标历史。是否集成及后续source绑定由root核对。

审查时新Release短UI日志`/tmp/temperature-w11-retention-release-smoke.log`记录TEST FAILED：runner49716在建立连接前signal kill、bootstrapping未完成。不能把它写通过，也不能仅据该runner启动错误断定产品核心功能失败。任何后续重试须单独保留原失败与实际新结果；本报告没有批准该短UI。

新App尚不具备本报告范围之外的五档性能资格；c354历史长测不能自动覆盖f9e850cb的新App。精确性能、未测物理菜单/其他REQ、exact-head CI与open blocking仍按实际状态处理。

## 审查源文件hash

| 文件 | SHA256 |
|---|---|
| Storage/Retention.swift | 693127c2d4c3a173204d13e92740ccb4dade7377cf6f694c8d654e299f0d8f90 |
| RetentionLookupScalingTests.swift | 721d59c4f192cea3c085cfc5f1c3e3ac6c227a481767391dbaa716c640e03153 |
| TTLRequirementBoundaryTests.swift | 67363c71ea3504384c953db607d33bcc90f236c36e4a16caced1f15eab1eed46 |
| RuntimeMaintenanceRegressionTests.swift | 5ffb3ffa4589b74df244900bfc51041e5959a883023653a907408d7d3c3805db |
| TestSupport/TestClock.swift | ff8e1be4376fdad678c42a6f89e695e7594193ec2d0481c5f5e628c62dfdb4cb |

git diff --check独立执行无输出。上述结论不替代剩余工作，也不关闭Issue或修改PR状态。
