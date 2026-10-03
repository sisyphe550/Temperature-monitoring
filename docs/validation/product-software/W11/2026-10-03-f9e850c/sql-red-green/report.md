# Retention父1秒查找：真实SQLite规模RED/GREEN

## 结果

固定20条expired样本，既有父窗口32→2048，不以wall-time为断言：

| 层 | 原SQL VM_STEP 小→大 | 候选VM_STEP 小→大 | 删除数量 |
|---|---:|---:|---:|
| Raw | 5057→246977 | 1358→1358 | 两种规模各20 |
| EMA | 4677→246597 | 978→978 | 两种规模各20 |

原算法两个`large<=small*2`断言失败（RED exit1）；只改复制包Retention两行，未改测试，所有5 tests/6cases通过（GREEN exit0）。规模测试从真实生产方法提取SQL，在真实SQLite及完整bundled schema执行；它是SQL算法工作量检查，不是已编译Store方法的VM计时，也不验证actor/scheduler/硬件。正确性四项另外调用真正SQLiteStore.commitBatch/deleteRawSamples/deleteEMASamples。

## 对齐前提与语义回归

公开现行设计docs/05-processing-pipeline.md:29规定elapsed=0为原点、[k×width,(k+1)×width)；不是仅依据本机snapshot。AggregationWindow整数index/start/end(13–22)、AggregationEngine按sample elapsed建窗(173–186)不因segment重设原点；RawBucketBuilder保留固定start/end(62–75)，partial仅表示coverage不足。

`midSecondRecovery...`使用真实AggregationEngine处理250ms旧段和750ms恢复新段，验证恢复partial父仍为[0,1s)、latest750ms；将其通过真实Store.commitBatch落库，清理只删除同segment新样本，旧段Raw/EMA仍保留。另三项覆盖错segment父、无已提交父/错series/错width不授权删除，正确父提交后才删除，半开end边界、cutoff等号/+1ns、partial父、成员级联、重复清理。

## 交付

- `/tmp/temperature-retention-lookup-scaling-tests.patch`：独立新增测试文件，无生产仪表变更；git apply --check exit0。
- `/tmp/temperature-retention-exact-parent-candidate.patch`：生产仅两行SQL；未应用到仓库。
- `/tmp/temperature-retention-scale-red-green/red-final.log`：最终预期RED原件。
- `/tmp/temperature-retention-scale-red-green/green.log`：同测试候选GREEN原件。
- `/tmp/temperature-retention-scale-red-green/red-green-source-hashes.json`：源/测试/patch/log hashes和返回码。
- `/tmp/temperature-retention-copy-probe-execution-report.md`：另三个真实session复制件回放、全量幸存内容相同、软件模型时间标注。

复制包测试只编译，没有启动SensorWorker/正式App或触发真实硬件；过滤范围只RetentionLookupScalingTests。SwiftPM环境失败与最初test helper编译错误原件单独保留，均不计作预期RED。

## 剩余边界

SQL算法性能问题已独立重现；实际App长测暂停的源码耦合与时间关系支持维护候选，但没有逐次prune trace，不能确定4.2s全由此SQL造成。高密度模型候选250ms事务仍可能拖住50ms采样，未证明skipped≤1%、读批/显示延迟或五档正式通过。root集成后仍需完整Core及门禁；本次不再进行正式GUI/硬件跑测。

