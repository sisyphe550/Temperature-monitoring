# c354 本机验收独立归档

日期：2026-10-03。生产源码 `c354b0392a91367d42708d7424fd0e133af825b9`；正式Release App `9f786ee330531d2d194ef2c88f04c83c314de3253a1e218ea45df12f5aeabc3c`，worker `74b44d0617c4524e6cf24024ad48e64304b56b8f0b18c459ad8c364c7f8cb59f`。仅Mac16,13/macOS15.7.3/build24G419，无fixture、普通用户。归档不改变旧403/a97/历史validation文件或验收catalog。

## 结论与边界

- 五档连续清醒运行时长条件已分别观察到。原XCTest整套仍为 **FAILED**：1000ms阶段AX找不到picker，记录保持原样。独立补证仅验证该同一连续区间的时长、真实样本和实际UI；不能改原suite为通过。
- 同一App88391、worker88506、Session `ad735257-fea5-41a0-8e1b-644c8d2bc191` 未退出/重启继续1000ms，观察641.637836秒，641个主CPU成功点覆盖640.010117583秒；不是拼接多次短测。实际期末Cua主窗温度82.3°C、无Fatal，随后实际app.quit与进程/会话清理见ledger。Cua事实是根agent记录的转录，未伪装成额外原始截图文件。
- 精确scheduler skipped、读批p95/p99、首帧及屏幕显示p95仍 **not_measured**。Raw完成间隔、理想点数短缺、资源观察不能替代它们。资格和W11整体仍未完成。
- 用户08:00UTC明确“跳过休眠测试”：仅跳过本轮三轮物理睡眠/手动唤醒验收。已触发的两次attempt及后续深Idle/合盖观察只作partial保留，不声称3轮passed；软件生命周期测试和功能保留。REQ-127整项豁免仍原范围，未新增整REQ豁免。
- 维护SQL性能问题的软件复制件回放与候选记录单列；尚未将SQL候选的新App进行同样长测，后续新App/worker不能继承此c354完整资格。

## 五档实际时长

| CPU period ms | 清醒秒数 | 证据 |
|---:|---:|---|
| 50 | 601.237771 | 原XCTest实际phase end |
| 100 | 601.295063 | 原XCTest实际phase end |
| 200 | 601.235623 | 原XCTest实际phase end |
| 500 | 601.300894 | 原XCTest实际phase end |
| 1000 | 641.637836 | 同一进程/会话独立clock + CUA + SQL |

四档原始UI记录和1000ms独立结束来自同一次连续运行。[完整duration ledger](long-run/independent-five-period-duration-ledger.json)分开保存原XCTest失败、四档phase、第五档补证、正常退出和未测项。[原失败摘录](long-run/original-xctest-failure-excerpt.json)只保留测试错误和summary；[LONG_UI事件](long-run/owned-long-ui-events.log)只含本测试结构化事件，完整原始日志保留在原/tmp路径及SHA，其他App AX不提交。

## 可复核的Raw与末端SQL

[原collector](long-run/actual-cpu-max-events.jsonl.gz)原字节以gzip保存，停止时点受失败runner影响。末端[完整344条主CPU SQL记录](long-run/terminal-cpu-main-supplemental.jsonl.gz)来自同Session只读snapshot，144个ID与原collector字段逐项相同，新增200个ID；按sample_id并集后，原1000ms窗口有641点。查询、列、snapshot SHA、重合断言和时间窗见[复核说明](long-run/terminal-cpu-main-query-and-overlap.json)。72MB原SQLite不提交，保存路径/字节数/SHA。不得补0、复制旧温或以数值重复推断硬件刷新。

所有gzip文件解压后hash/大小列在[manifest](manifest.json)。JSONL每行是一个原始事实；相邻间隔以elapsed差值计算，分位数为nearest-rank，period/segment/来源分别判定，不当读批时间。

## 图表与维护性能

[相同50ms年龄对比](performance/charts-age-matched-comparison.md)显示旧/新存活约60–323秒内App CPU TIME口径108.48%→44.66%，观察下降58.83%；非受控A/B，不拆分1Hz和Equatable贡献，RSS未改善。CPU百分比单核100%口径，观测最大值不是绝对峰值。

[维护/worker只读审查](performance/maintenance-worker-readonly-review.md)与相关JSON保留当时部分观察；SQL timeout Gap在本段对应相邻成功样本暂停和segment.reason=gap，不凭字符串认定SENSOR-TIMEOUT错误。[复制件回放](performance/retention-copy-probe-execution-report.md)是后来已实际执行的软件结果，原SQL与候选幸存数据一致、VM工作下降；不能把回放时间当正式App修复后实际延迟。较早源码假设和当时“待测”措辞原样保留，由各报告时间/范围阅读。

[性能可观测性审查](performance/observability-review.md)是04:56UTC长测尚在执行时的只读报告，当前状态以本README/verification-summary为准；报告内源码/不可推导指标边界保持。

## TTL软件补证

[实际执行结果](ttl-software/actual-execution-results.json)、[审查](ttl-software/actual-execution-review.md)与压缩PASS日志证明3项新增Swift Testing /2 suites通过。真实SQLite配合虚拟elapsed验证六层边界、三日查询过滤与60秒maintenance；66个生产文件与c354复制件一致。新增/tmp测试源码、patch及hash已归档，不声称它们原已存在c354提交；定向coverage不冒充完整产品80%门禁。根agent将另归档最终全套Core/coverage。

TTL原审查中的“休眠未执行”只描述其软件任务未运行正式三轮物理验收；不取消本目录已保存的真实partial attempt。跨左边界整桶统计政策诊断未执行，不登记为已复现bug。

## 睡眠观察与用户指令

[user-scope.json](user-scope.json)保存用户原话、接收时间、范围与保留项。前/后/停止时的独立Session `62ff3456-1c0b-4c43-b563-5f250f6e7fe3` 观察在 `sleep-observed-partial/`；AppPID36763持续，worker与来源代变化及Gap/segments有原始JSON，不据其自动判整套验收。未补齐规定三轮、未把深Idle唤醒等同人工FullWake；不会再执行物理睡眠。停止后正常quit事实的来源见[cleanup](cleanup-facts.json)。

## 使用方式

读[verification-summary](verification-summary.json)、原始ledger和manifest后，按具体用例判定。source commit proof与冻结inventory绑定生产身份；新证据delivery提交由根agent设置。此归档不修改catalog、132项计数或整体passed结论。适用未完成项、当前blocking、精确head CI和下一SQL修复的实机状态仍由当前交接文档与后续报告管理。
