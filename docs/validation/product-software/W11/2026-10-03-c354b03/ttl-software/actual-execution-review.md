# TTL 新案例实际执行结果

2026-10-03，源码基线 `c354b0392a91367d42708d7424fd0e133af825b9`。仅使用 `/tmp/temperature-ttl-software.sD1Hqe` package 复制件和独立 scratch；jobs1，未启动正式 App/GUI，未修改仓内文件或生产代码。

## 结果

三项新增 Swift Testing 案例全部通过：首次 build40.37s，测试3项/2suite、0失败，执行0.041s。日志：`ttl-tests-escalated.log`。XCTest 的“0 tests”是另一套 runner 的空筛选结果；随后 Swift Testing 明确运行并通过这三项，不能误判为零测试验收。

| REQ | 实际通过的新增断言 | 范围 |
|---|---|---|
| 031 | 1s cutoff−1/0/+1ns：前两项删除，仅后一项留存；核对 aggregate width＋latestSampleID 身份 | 软件/真实SQLite |
| 033 | 1min259200s cutoff−1/0/+1ns，同上 | 软件虚拟elapsed，非72h实机 |
| 034 | Trend3600s elapsed cutoff−1/0/+1ns，仅后一项留存 | 软件/真实SQLite |
| 035 | prune前旧72h桶仍存在；三日查询只返回完全处于窗口内的有效桶；查询后物理行集不变 | 不决定跨左边界整桶统计政策 |
| 036 | 一次production prune同时验证Raw/EMA/1s/Trend/10s/1min六层；Raw/EMA无已提交1s父层时保持且未越120sgrace | 不重复已有grace Fatal测试 |
| 037 | Controller启动后59.999/60/119.999/120s，真实Raw/EMA行数2→2→1→1→0；下一waiter仅作同步 | 不统计空DELETE或正式App墙钟相位 |

输入通过既有 `appendForTesting` 实际 SQLite commit 写入；它不经过采样 Lease/StorageWriter 队列，不把这三项声明为完整实时采样管线验收。Lower-layer待删桶已有已提交父层；parentless控制组使用独立SeriesID，避免被其它父桶覆盖。

## 生产源码一致性与补丁

`Package.swift`＋`Sources` 共66文件逐项SHA256与复制件一致，原始对照：`/tmp/temperature-ttl-software.sD1Hqe/production-source-comparison.json`。执行期间没有替换 Core 实现。

- 补丁：`/tmp/temperature-ttl-boundary-review/ttl-minimal-tests.patch`
- SHA256：`912b1f690b9e7926cfa2e07f6bd665536045cc62ce71bc4354d69724e4cd60a8`
- 机器可读结果：`/tmp/temperature-ttl-boundary-review/actual-execution-results.json`

## 已开始的覆盖轮次

按本轮GO请求对同一三项案例做了一次 coverage-instrumented run，build35.00s，3项/2suite、0失败，执行0.040s；日志 `ttl-tests-coverage.log`，原始覆盖JSON在该scratch的 `arm64-apple-macosx/debug/codecov/TemperatureCore.json`。

| 相关文件 | 本轮命中行/可执行行 | 行覆盖 |
|---|---:|---:|
| Retention.swift | 210/250 | 84.00% |
| HistoryQuery.swift | 216/288 | 75.00% |
| SessionMonitorController.swift | 114/326 | 34.97% |

该数字只描述三个定向案例执行过的相关路径，**不作为全产品80%门槛**。最终生产修复提交后的全套覆盖由父任务统一运行。本轮覆盖既已开始则完成归档，随后没有追加其它测试/覆盖。摘要：`targeted-coverage-summary.json`。

## 沙盒尝试与未执行范围

首次sandbox命令在manifest编译阶段因不能写用户clang ModuleCache而退出，保留 `ttl-tests.log`；这不是测试/产品失败。对同一复制件一次升级权限后实际编译和三项测试通过，无重复启动另一复制件。

可选 `crossing-edge-diagnostic.patch` 未应用、未编译或运行；不把源码两种窗口口径登记为已复现缺陷。72h/73h实机耐久不由虚拟300000s代替。最新用户明确跳过本轮三轮真实休眠条件，休眠未执行，不修改其它验收要求。

