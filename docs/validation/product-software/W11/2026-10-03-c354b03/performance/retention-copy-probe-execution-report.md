# 2026-10-03 Retention父窗口查找：复制件回放结果

## 结论

原Raw/EMA DELETE的父聚合前缀范围查询开销已在三个软件回放中复现。精确匹配已对齐的1秒bucket主键减少SQL VM工作，三个回放的全部幸存逻辑数据一致。该证据确认SQL算法性能问题；本轮真实App的1.00–4.20秒暂停与维护路径高度相关，仍缺直接prune trace，不能把每次pause的全部原因定为此SQL，也不能宣称50ms采样达标。

root于正式App正常退出、用户跳过睡眠后明确GO。仅操作独立/tmp SQLite复制件，未启动正式GUI、未更改仓库。人工推进时钟明确标为软件回放，不是真实睡眠。

## 三个回放

| 输入/时间模型 | 每层删除Raw/EMA数 | 原事务→候选ms | 原Raw/EMA VM总步数→候选 | 幸存数据 |
|---|---:|---:|---:|---|
| 旧50ms高密度 +120秒 | 34496 / 34496 | 1783.999→250.014 | 37350482→4721636 | 全7表一致 |
| 新最终snapshot 原时刻 | 687 / 687 | 380.298→7.467 | 8467839→91427 | 全7表一致 |
| 新最终snapshot +60秒 | 1646 / 1646 | 785.160→18.752 | 20883754→218992 | 全7表一致 |

旧高密度原事务1784ms，其中Raw486ms、EMA1243ms；候选Raw84ms、EMA97ms。新最终snapshot只删除687条各层样本，原仍耗380ms，候选7.47ms。新+60秒原785ms，候选18.75ms。所有quick_check=ok，Grace未超限；PASSIVE checkpoint均远小于Raw/EMA基线耗时。

原EXPLAIN父查询为`(series_id=? AND segment=? AND width_s=? AND start_elapsed_ns<?)`，候选为完整等值键`(... start_elapsed_ns=?)`。VM步数下降证据比本机单次wall-time更稳健，后台并行build及cache可影响wall-time。

## 最小候选

`/tmp/temperature-retention-exact-parent-candidate.patch`仅两行：

```sql
AND start_elapsed_ns = (raw_samples.elapsed_ns / 1000000000) * 1000000000
AND start_elapsed_ns = (ema_samples.elapsed_ns / 1000000000) * 1000000000
```

分别位于Raw与EMA各自的EXISTS子查询。保留TTL cutoff、series、segment、width=1、end>sample、父存在检查、删除顺序/事务/级联/Grace/checkpoint。源码Aggregation.swift:13–22及:177–185保证合法1秒bucket按全局elapsed整数对齐；probe预检查两个snapshot所有1秒bucket均对齐。没有扩默认值、schema或API。git apply --check退出0，但未应用、未编译。

250ms的高密度候选事务仍可能推迟50ms采样。若维护gate等待仍超标，下一步需真实gate/commit trace或软件actor seam，再决定小批事务交错commit；不能先删父检查或扩大TTL。

## 建议回归

1. cutoff恰好等于sample时间、半开bucket端点：start命中；end时样本必须匹配下一bucket。Raw及EMA同时验证。
2. 父不存在时保留；仅有别series、别segment、width10/60父时保留；父未提交时保留，Grace超限仍Fatal。
3. partial父仍按对齐时间窗命中；CPU Max和12成员正确清理，sample_members外键级联与聚合内容保持。
4. 固定数量expired样本，加入很多更早1秒父，验证完整键查找的查询计划/VM步数不会随历史前缀线性增长；避免依赖本机毫秒阈值。
5. 跑适用Retention/Storage/幂等/aggregation/gap回归及完整门禁；新增回放不是正式App硬件验收。

## 原始结果与复现

```sh
TM_RETENTION_EXECUTION_APPROVED=yes bash /tmp/temperature-retention-copy-probe/run-after-explicit-go.sh --snapshot /tmp/temperature-long-ui-20261003T033320Z/final-before-normal-quit.sqlite --age-seconds 120 --repetitions 1
TM_RETENTION_EXECUTION_APPROVED=yes bash /tmp/temperature-retention-copy-probe/run-after-explicit-go.sh --snapshot /tmp/temperature-long-ui-20261003T043223Z/final-before-normal-quit.sqlite --age-seconds 0 --repetitions 1
TM_RETENTION_EXECUTION_APPROVED=yes bash /tmp/temperature-retention-copy-probe/run-after-explicit-go.sh --snapshot /tmp/temperature-long-ui-20261003T043223Z/final-before-normal-quit.sqlite --age-seconds 60 --repetitions 1
```

- `/tmp/temperature-retention-copy-bbtcr0lb/results.json`
- `/tmp/temperature-retention-copy-xk3viaxm/results.json`
- `/tmp/temperature-retention-copy-94tfrtwr/results.json`

- `/tmp/temperature-retention-copy-probe-execution-summary.json`：来源/时间/完整结果hash/指标与边界。
- `/tmp/temperature-retention-exact-parent-query-plan.json`：两种SQL的查询计划。
- `/tmp/temperature-retention-copy-probe/Baseline.Retention.swift`：冻结原SQL来源，SHA9ed9ed53…。

