# 7c13 Core CI 等待超时：测试驱动诊断与修正证据

## 结论与边界

失败 run37114147439/job111177560322，head `7c13d94ba728616d14a74866c03545e966a73ffe`。原日志 `/tmp/temperature-7c13-core-ci-failed.log:1282–1287` 是 `OptionalGenerationRecoveryRegressionTests.sourceGenerationChangeRequiresThreeNewOptionalReceipts` 捕获 Cocoa256，355tests中1issue。它完全使用 GenerationProbeTransport/TestClock/SQLite，未进入 WorkerClient。该日志中的 SIGPIPE 公开回归和无效 origin 回归均通过；不能把新失败归为 SIGPIPE 修复失效。

原测试把 helper 等待到期主动表示为 `CocoaError(.fileReadUnknown)`，造成文件读取错误的表象。原 CI 未输出失败阶段，因此没有从旧日志唯一确定具体 wait。受控软件模型可确定性复现其测试驱动缺陷：每轮固定推进25ms虚拟时间，再依赖墙钟轮询；推进速率随调度延迟下降，而4s等待预算不变。这不是新产品算法或物理接口缺陷证据。

最小修正仅改变单个测试文件：采样任务/发布任务按身份识别；先确认实际 SQLite commit 和同采样任务新的 sleep（代表读回调、Receipt及optional状态转换完成），再推进注册的虚拟事件。删除40ms猜测完成和隐式25ms步进；保留真实SQL数量、来源代际、前2次不可用/第3次恢复的断言。参数化2ms/125ms轮询延迟，确保测试与推进速率解耦。

本 agent 仅修改 `/tmp`，无仓库修改、GUI、传感器、睡眠或 Worker RSS A/B。根 agent 集成后全Core/覆盖与CI另行验证；不重复正式 App/Release 实机证据。

## 原错误与受控 RED

原测试路径（仓库根 `/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring`）；下述原测试行号对应7c13基线及保存的 `/tmp/temperature-optional-generation-ci-probe/OptionalGeneration-baseline.swift`，不是集成后的新行号：

- `Packages/TemperatureCore/Tests/TemperatureCoreTests/OptionalGenerationRecoveryRegressionTests.swift:123–130`：generationAdvanceUntil墙钟4s到期抛Cocoa256，每轮虚拟+25ms、真实sleep5ms。
- 同文件 `:132–138`：generationAwaitSnapshot墙钟2s到期也抛相同Cocoa256，无法区分阶段。
- 同文件 `:26–32`：通过 transport.optionalReads数量及40ms固定sleep假设两个成功已commit并安装下一deadline。
- `Sources/SensorRuntime/SamplingService.swift:373–386`：实际必须在performRead返回后才增加validConsecutiveReads、可用状态变更及下一可选deadline。
- `Sources/SensorRuntime/SessionMonitorController.swift:311–342`：发布循环捕获asOf、生成snapshot，再安装下一200ms发布deadline，异步进度不能由读计数替代。

复制包先只加8个阶段日志和失败上下文；常规5ms轮询PASS0.746s。独立125ms慢poll模型（非硬件/性能压力）RED `slow-poll-red.log`：exit1，4.105s，phase=initial-unavailable；虚拟775ms，optionalReads3，discoveries1，snapshot625ms；pending=[825,850,1000,60000]ms。第4次重试仍在850ms正确等待，测试墙钟预算先耗尽。默认SSD500ms、CPU200ms、重试50/100/200ms，不能声称SSD间隔2s。这个模型证明driver失败机制，**不证明原CI唯一失败阶段**。

## 候选测试设计

最终候选 `/tmp/temperature-optional-generation-ci-probe/OptionalGeneration-candidate.swift`，共278行。

- 第25–31行 commit observer在真实Store.commitBatch成功后记录SSD receipt；只按Qualified gen1/gen2派生的SSD SeriesID分别计数，排除CPU、gap、metadata批次。
- 初始550ms重试唯一识别采样task；冻结500ms时，snapshot500ms已发布后的700ms sleep唯一识别publisher。CPU/快照/水位截止可能重合，后续必须按task身份取sleep，不按裸deadline猜角色。
- nextSamplingDeadline仅返回同采样task且deadline>当前虚拟时间的sleep，排除刚被唤醒但尚未清除的旧注册。真实SSD commit计数与这个sleep同时满足，才认为读回调/Receipt/optional转换完整返回。
- 每次发布推进已注册publisher的未来截止；guard发布不得跨下一SSD probe。消费snapshot.asOf至少达到这次目标，再等待采样未来sleep，保持下一场景的完成边界。
- SQL核对gen1 SSD0/1/2行，gen2 SSD1/2/3行；gen1恰好2次后触发CPU timeout/requal，在gen1第3次前切换；gen2第1/第2次仍不可用，第3次才可用；lastAcceptFailure保持nil。
- test-local锁保护clock角色及receipt计数；基于本项目已有QuarantineClock/receipt观察方式，无生产公开API、defaults/schema/contract修改。

| 阶段 | 虚拟读取时间ms | 证据 |
| --- | ---: | --- |
| 初始隔离 | 500，重试550/650/850 | 4失败后sampling1000 sleep，再发布unavailable |
| gen1成功1/2 | 60850/61350 | receipt1/2+sampling新sleep、SQL1/2、仍unavailable |
| CPU timeout/requal | 61600，retry61650 | 同sampling retry注册；gen2目录及CPU Receipt后新sleep；旧SSD仍2 |
| gen2成功1/2/3 | 61850/62350/62850 | receipt1/2/3+SQL；发布后前2不可用、第3可用 |
| 完成 | 63050 | oldReceipts2/newReceipts3，两个poll参数相同结果 |

## 实际验证

| 日志 | 实际结果 | 说明 |
| --- | --- | --- |
| baseline-diagnostic.log | exit0，1test/1case，0.746s | 原driver加阶段诊断，普通5mspoll |
| slow-poll-red.log | exit1，1issue，4.105s | 原driver125ms受控轮询模型，停在initial-unavailable虚拟775ms |
| candidate-green-before-negative.log | exit0，1test/2cases，3.182s | 新driver2ms/125ms都old2/new3 |
| negative-control-red.log | exit1，1test/2cases，4issues，2.852s | 仅复制SamplingService临时移除重连计数清零；两参数均抓gen2第1/2次提前可用 |
| candidate-green.log | exit0，1test/1suite/2cases，2.705s | 恢复复制生产原件后最终同源GREEN，old2/new3、63.05s虚拟完成 |

负控证明没有弱化原代际回归目标。Swift Testing的#expect失败会继续执行，所以负控仍出现GEN_PHASE_COMPLETE；该marker只表示流程走完，**不能据它宣称PASS**，以测试框架结果/exit为准。首次candidate-compile-first.log缺configuration构造参数为编译失败，修正后通过；不冒充行为RED。

## 补丁、身份及归档

- `/tmp/temperature-optional-generation-ci-probe/tests.patch`：唯一修改 `Packages/TemperatureCore/Tests/TemperatureCoreTests/OptionalGenerationRecoveryRegressionTests.swift`。apply--check通过，SHA256 `7efcdda66e90281de171afbb7f1a710c88da51e65084ed815d25755d4e0f28b1`。
- 原测试source SHA256 `c4b7634babcd53b0ed084ae052960f4e80ff55d2ffee07966dd4af7b38e8795b`；最终candidate SHA256 `748bbadd26e22648df84cf5917edc27835942bd7ea7124e4f6623ae7f0a06fa9`。
- SamplingService复制原件/当前repo/负控后恢复件字节相等，SHA256 `64d74335e7f426532fc299b35d9c48f3edbdf6b4ff7dcbe809473f94882e31c3`；负控变体独立保存，不会作为生产候选交付。
- source-hashes.json、run-summary.json、production-restoration.json和evidence-manifest.json记录精确身份、exit/测试数、恢复与证据哈希。
- 实际命令复用已批准、参数白名单、固定copy package/cache/jobs1的 `/tmp/temperature-sigpipe-red-green/run-tests.sh`。执行版快照保存 `run-tests-executed-snapshot.sh`；执行完已恢复旧脚本到前次SIGPIPE manifest哈希，避免改变既有证据。复制包生产原件也已恢复。只新测试源码留在复制包，不扩大或重复其他suite。

原7c13 CI FAIL需独立保留，与新test commit的全Core/CI结果分列。正式App源输入没有由这个测试改动变化；不能把此软件验证覆盖为新的实机长测或睡眠通过。
