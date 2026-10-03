# 2026-10-03 Charts CPU：相同50ms阶段的时间对齐对比

## 测量范围

对比既有033320失败运行与043223当前运行的正式50ms阶段，仅使用App自身ps观察。同一名义时间点相差约5至6秒；本表没有使用当前200/500ms阶段。100% CPU表示约一个逻辑核心当量，ps采样百分比不是完整阶段平均。RSS单位KiB，不能据其单独判断live对象泄漏。

| 名义阶段年龄 | 旧实际秒 / ps CPU | 新实际秒 / ps CPU | 旧RSS / 新RSS KiB |
|---:|---:|---:|---:|
| 60s | 61.50s / 54.2% | 56.20s / 27.8% | 201632 / 202912 |
| 120s | 121.90s / 113.3% | 116.32s / 30.9% | 242064 / 259312 |
| 180s | 182.04s / 88.8% | 176.49s / 47.5% | 266320 / 289056 |
| 240s | 242.32s / 121.8% | 236.59s / 38.3% | 301584 / 322400 |
| 300s | 302.50s / 157.2% | 296.85s / 73.6% | 310048 / 379264 |
| 320s | 322.68s / 163.3% | 316.91s / 71.8% | 325264 / 378336 |

TIME累计差÷observer monotonic子区间：旧61.50→322.68秒为108.48%，新56.20→316.91秒为44.66%，约下降58.83%。该结果支持在相近存活时间、相同50ms档下App CPU开销明显下降；不能当作整档平均，也不能分拆history1Hz与Equatable两个改动的贡献。新50ms后半段ps常约70至95%，残余CPU尚未取得新stack归因。RSS并未改善。

## 已测与未测

- 旧版本Charts占主线程一秒采样stack约79.38%，独立于本表的ps总CPU口径。
- 新版本完整50ms持有601.237771awake秒，runner继续到后续档；旧版本326秒左右因AX picker snapshot失败终止。AX失败与Charts的因果关系没有证明。
- 该对比不是受控A/B：两次session的后台活动、硬件热状态与runner激活方式可不同；不能外推其他Mac。
- 当前运行期间未采样新stack、未增加压力或运行性能探针。CPU改善有本机观察支持；不能宣称彻底解决。

## 文件

- `/tmp/temperature-charts-50ms-age-matched-comparison.json` 保存逐条时间点、PID、CPU TIME、observer monotonic、RSS及计算。
- `/tmp/temperature-long-failure-readonly-review.md` 保存旧stack、Charts更新源与候选边界。
- `/tmp/temperature-043223-maintenance-worker-readonly-review.md` 保存新Gap与维护/Worker候选。
