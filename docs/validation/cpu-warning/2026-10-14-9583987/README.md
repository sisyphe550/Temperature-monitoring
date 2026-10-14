# W12 CPU预警软件测试与独立审查

日期：2026-10-14。源码：`958398772918c3cf61cf5eb552bb24759197b755`（contract revision4）。**软件行为、Core覆盖和同一次最终独立审查通过；正式App、系统通知实际结果及同head CI由root独立记录。** 本目录没有把软件模拟写成硬件通过。

## 结果

| 项目 | 实际结果 | 证据与边界 |
|---|---|---|
| 最终完整Core | 413项/62组，23.854秒，0issues | final-full-core.log；含警报/异常、数据、生命周期及#56回归 |
| Core行覆盖 | 7426/8327 = 89.18%，>=80% | final-core-coverage.log；原定TemperatureCore+SensorRuntime分母，无测试/UI/C薄桥/worker入口 |
| 预警7软件cases | passed | software.json映射实际断言与最终日志；Raw/恢复/提交/偏好/通知fake backend，非硬件温度或横幅事实 |
| #56针对性最终复核 | 44项/6组，4.143秒 | heldcommit快照、Receipt后TTL及原Sleep/Wake回归；独立无消费者探针超期事件0、unableToAssess(stale) |
| 独立审查 | 同次最终PASS；#54/#55/#56已复核，无新增P1/P2 | independent-review-original.md逐字复制；审查未重复完整Core |
| 文档/验收脚本 | 文档结构及负例通过；binder44、course36 | 原始日志；这些结果不能替代真实课程五criterion |
| API/原型保护 | Swift6 API typecheck通过；probe8项/1组通过 | 原型unit不是产品覆盖或正式硬件资格 |

## 失败记录保留

初次完整Core **411项/62组、4issues失败**及空coverage原样保留。OptionalSleepAdmissionRace/WakeRecovery超时属于真实#56生产提交/快照边界缺陷，未改称不稳定fixture。#56的snapshot-block、旧事件expiry-revival、无消费者held-trigger TTL三类红例与修复绿例均保留。

#54初始独立探针在已提交sleep中断后仍add1；修复复核为0，且同session恢复无新Snapshot仍0。#55初始真实旧hashed报告仅追加TC-WARNING标签可使catalog/binding/course全绿；修复后正文、日志哈希和源码版本/预警实现均检查，真实负例已红绿复核。

configuration中间日志原文件名有green但正文为编译失败，保留为失败，不按名称认定通过。原targeted23/93/28日志只用于开发过程；最终各case都引用413项完整回归。pre-issue56构建绿只属于当时产物，不计正式App通过。

## 七个软件case

- trigger-recovery：短尖峰、触发包容边界、Raw与EMA、恢复回差和10秒。
- interruption-and-time：五档/换档、elapsed/墙钟、成员/Gap/来源/过期/生命周期，snapshot无等待和Sleep/Wake软件回归。
- receipt-and-replay：失败/拒绝/重放、规则与在途提交顺序、Receipt后TTL重新校验；TTL等值3000ms可触发，3001/15000ms不触发。
- rule-change：ruleChanged/disabled、相同规则保留状态、运行时及Presentation精确转发。
- events-bounded：最近50唯一事件与被淘汰事件不回放。
- config-persistence：四字段保存、坏偏好、写入/读回错误；不声称物理落盘或正式App重启。
- notification-policy：去重/60秒/晚授权/拒绝/失败、暂停恢复/挂起add/同session点击软件路由；不推定真实横幅与点击。

## 文件与剩余外部验收

[software.json](software.json)为可绑定software artifact，environment/source/result须与catalog逐字一致；[independent-review.json](independent-review.json)绑定源码与复核范围，[原文](independent-review-original.md)保持逐字，[artifact-manifest.json](artifact-manifest.json)记录原始日志/探针的复制路径、字节和SHA256。

正式Release真实CPU/预警短测、App/worker身份、系统授权/请求/实际横幅与点击事实、最终catalog和同PR head五CI由root填写。根目录改名没有修改既有原始日志内容；历史validation/research未回写。达到课程门槛不宣称可选长测/物理sleep/公证/跨机资格。
