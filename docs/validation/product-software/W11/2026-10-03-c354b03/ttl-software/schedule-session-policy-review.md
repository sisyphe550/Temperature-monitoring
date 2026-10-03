# 五档每档 10 分钟：会话连续性只读审查

## 结论

**未定义，需澄清。** 当前规范明确五档各至少 10 分钟，以及同一 App/worker SHA、签名和目标机型/OS 组合；未明确五档必须在同一连续 Session 完成，也未定义同 SHA、同组合的跨 Session 补验及结果合并规则。因此不能直接把“未要求同 Session”改写为“允许跨 Session 拼接验收”。

跨会话逐档补跑与同档碎片时长相加也不是同一规则；规范没有给出任一合并算法。1000 ms 的 361 s 不能自行解释为完整 600 s。即使后续单独完整运行 600 s，四档旧阶段加新 Session 的合并资格仍需明确口径，不能改写原失败 runner 为 passed。

## 具体来源

| 来源及行号 | 规范或字段 | 结论 |
|---|---|---|
| `docs/10-test-strategy.md:61` | 正式 App 五档各 10 分钟；记录实际间隔、批耗时、skipped、失败、资源与 freshness；空闲 skipped≤1%、read batch p95≤period、p99≤2×period、显示延迟 p95≤500 ms | 明确时长和性能门槛；没有同 Session 或补验合并条款 |
| `docs/10-test-strategy.md:65` | 每次报告保存源码 SHA、App/worker hash、profile、机型/OS、签名、用例、状态及原始证据；新增报告不得改写历史 | 明确每次结果身份与证据；没有跨 Session 合并规则 |
| `docs/10-test-strategy.md:27` | 72h 默认200 ms 与“五档各10min另测”区分 | “另测”只区分耐久项目，不能解释为允许跨 Session 补档 |
| `docs/22-agent-implementation-plan.md:498` | 对五档“分别执行至少10分钟空闲及10分钟可控负载”，记录计划/实际开始结束等 | 明确逐档执行；没有规定五档必须同一 Session，也未明确允许多 Session 归并 |
| `docs/22-agent-implementation-plan.md:494,509` | 组合绑定正式 App/worker SHA、签名、机型及OS；同一正式App SHA完成指定用例后才登记 | 同产物/同组合是明确必要条件；不是跨 Session 合并授权 |
| `docs/23-execution-task-breakdown.md:177` | T09.2 绑定 App/worker SHA、签名、机型及OS build；五档各≥10 min；失败组合不能进 qualified list | 同上；没有同 Session 字段 |
| `docs/13-operations-distribution.md:51,77` | `qualified_combinations` 绑定 App/worker SHA、签名、机型/OS、测试集合与结果；“同一 App/worker SHA”完成 sources/schedules/lifecycle 三套实机套件 | 明确相同二进制及环境组合；没有五档同 Session 连续性条款 |
| `docs/21-implementation-contracts.md:123-128` | 四类平台/资格字段；qualified_combinations 为正式 App SHA、签名、机型、OS及通过用例 | 无 SessionID 或跨 Session aggregation 字段 |
| `docs/contracts/product-qualification-v1.json:36-45` | combination 字段为 app_sha256、worker_sha256、codesign_identity、model_identifier、host_product_version、host_build_version、suite、result | Schema 没有 SessionID/连续性/多报告合并字段；字段缺失不等于允许 |
| `docs/01-requirements.md:930` | REQ-110 按正式 App SHA、签名、机型、系统及通过用例声明支持 | 明确组合资格；没有会话连续性要求 |
| `docs/contracts/acceptance-evidence-catalog-v1.json:283-286`（`acceptance-v1.json:95-98`） | REQ-001 五档控件已验证；各10min性能资格仍为整体未完成门禁 | 控件存在或各档时长不能单独代替全部性能资格 |
| `docs/contracts/acceptance-evidence-catalog-v1.json:2304-2308`（`acceptance-v1.json:11294-11298`） | REQ-110 尚缺同一产物 sources+schedules+lifecycle 整套资格；五档10min及真实sleep未完成前不沿用旧资格 | 强制同产物与整套资格；未指定五档同一 Session |
| `docs/contracts/acceptance-evidence-catalog-v1.json:169-170` | 本机豁免保留“五档各10min及真实sleep/wake” | 未豁免时长；没有补档合并授权 |

## 已明确的同 Session 要求不能外推

- `docs/01-requirements.md:1082`：REQ-129 要求切换采样档位后保留“本会话”内未过期历史。
- `docs/10-test-strategy.md:38`：每次新会话默认200 ms；换档不清历史、不重置无Gap EMA。
- `docs/contracts/acceptance-evidence-catalog-v1.json:2629-2632`（`acceptance-v1.json:13116-13119`）：REQ-129 的现有实机证据明确同一正式 App 会话连续五档、保留不同 period_ms 历史。

这些要求必须在同 Session 验证切换后的历史连续性。它们没有要求每次换档保持 600 s；也不能把跨 Session 的独立 600 s 运行当作同会话历史保留证据。

## 本次审查状态

只读当前指定文档、现行 acceptance catalog 与 qualification schema，并在 /tmp 保存本报告。未核验 043223 原始运行日志，未编译、测试、启动/控制 App 或修改工作树。父任务提供的“四档≥601 s、1000 ms约361 s、runner failed”不在本次独立实测范围内。
