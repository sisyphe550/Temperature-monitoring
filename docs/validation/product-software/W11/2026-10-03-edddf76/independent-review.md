# Optional Generation 回归测试最终独立审查（2026-10-03）

## 结论

未发现本次测试修正的阻断问题。提交 `edddf76ddcffd3396315c52ede11eccda3ca2392` 只修改 `Packages/TemperatureCore/Tests/TemperatureCoreTests/OptionalGenerationRecoveryRegressionTests.swift`，187行新增、47行删除。该修改使测试等待真实提交及采样流程完成后再推进虚拟时间；保留并加强原有“来源换代必须重新累计三次成功”回归目标，未修改生产算法、物理接口或产品需求。

已实读正常/慢轮询 GREEN、单行生产变异负控 RED 和根 agent 的全量 Core 原始日志；已独立核对补丁、Git 源码、复制包恢复和 coverage。本结论可用于测试修复归档与新提交 CI，不能代替新 head 的实际 CI 或整个 W11 产品验收。

## 原失败与诊断边界

基线 `7c13d94ba728616d14a74866c03545e966a73ffe` 的 run37114147439/job111177560322，原日志在 OptionalGeneration 单用例报告 Cocoa256，355 tests中1issue。原测试有两个 helper 在等待到期时显式抛同一 `CocoaError(.fileReadUnknown)`，原日志没有阶段信息，不能从该错误文本认定真实 SQLite 文件打不开，也不能唯一确定原 CI 在哪个 helper/阶段到期。

原 `generationAdvanceUntil` 每轮虚拟时间只推进25ms，再真实 sleep5ms；4秒墙钟预算与虚拟推进速率耦合。`slow-poll-red.log` 使用明确125ms受控轮询延迟，实际在 initial-unavailable、虚拟775ms、optionalReads3 时墙钟先到期，850ms第四次重试仍在等待。当前默认 SSD 周期500ms；不得写成SSD采样周期2秒导致。该模型证明测试驱动存在调度依赖，不能把模型阶段当作原 CI 唯一失败阶段，也不能当作硬件性能压力测试。

本用例使用软件 GenerationProbeTransport、QualifiedSensorClient、TestClock 与真实 SQLite，不进入 WorkerClient。新失败不是 SIGPIPE signal13 的重复复现；原 SIGPIPE 修复和此测试驱动修正须分别记录。

## 实现与测试语义检查

仓库根目录：`/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring`。以下行号对应 eddd 新文件。

1. `:16–30` 从 ProfileRegistry 的 gen1/gen2 Qualified catalog 派生不同 SSD SeriesID。commit observer 在真实 `store.commitBatch` 成功返回后才计数，按SSD身份筛选 raw批次，不把 CPU、gap 或metadata提交算成SSD成功，也没有伪造 Receipt。
2. `:40–51` 在冻结500ms的场景，以550ms重试唯一识别 sampling task，以发布500ms后的700ms等待识别 snapshot task。后续按 task 身份取未来sleep，避免CPU、snapshot、水位在相同deadline上的混淆。
3. `:65–66` / `:91–92` 同时等待确切SSD提交计数与同sampling task的新sleep。后者发生在 performRead/onRead/Receipt/optional转换返回后；单独 transport读计数或 afterCommit计数都不足以证明该状态边界。`nextDeadline` 只返回deadline>now，排除已到期但尚未移除的旧sleep注册。
4. `:60–103` 真实 SQL 核对旧SSD0/1/2、新SSD1/2/3行；旧代恰好两次成功后、第三次之前触发CPU timeout与重发现。新代第一次、第二次提交后均明确不可用，第三次才可用，并断言新来源代际及 lastAcceptFailure=nil。
5. `:205–211` 只推进已注册publisher的未来截止，并要求截止严格早于下一SSD probe；等待 snapshot.asOf 到达该次目标后，再等待sampling新sleep。不会为发布UI而悄悄触发下一次探测、破坏“恰好1/2/3次”的前提。
6. 私有clock和计数器使用锁，封装基础TestClock；注册sleep后提前advance也由基础clock的已到期路径安全处理。没有改共享TestClock、生产clock/API或其它suite。成功与可抛失败路径均停止controller并回收observer；SQLite reader在stop前关闭。
7. wall-clock轮询参数固定2ms/125ms，只影响观测延迟，等待循环不再每轮推进虚拟时间。每次超时带phase/elapsed/sleeps，外层打印reads、commits、catalog与snapshot上下文；有界墙钟预算仍作为测试失败检测，未宣称对任意系统挂起均保证通过。

## 实际证据

| 日志 | 框架实际结果 | 解释 |
| --- | --- | --- |
| baseline-diagnostic.log | 1 test PASS，0.746s | 原驱动加阶段日志、常规5ms轮询 |
| slow-poll-red.log | 1 test FAILED，4.105s | 原驱动125ms模型，在虚拟775ms提前超时 |
| candidate-green-before-negative.log | 1 test /2 cases PASS，3.182s | 新测试2ms/125ms初次正常验证 |
| negative-control-red.log | 1 test /2 cases FAILED，4issues，2.852s | 复制生产源码仅删除来源换代时validConsecutiveReads归零；两参数均在新代第1/第2次后的不可用断言失败 |
| candidate-green.log | 1 test /2 cases PASS，2.705s | 生产复制件恢复原字节后的最终GREEN；old2/new3、虚拟63.05秒，两参数结果相同 |
| /tmp/temperature-w11-generation-final-core.log | 355 tests /57 suites PASS，2.860s | 根 agent 执行的最终全量测试，已含本参数化用例；过滤套件结果不能重复加总 |

负控只删一条真实生产reset赋值，两个参数均抓住原回归缺陷，证明修正没有以弱化断言换取通过。负控中的 `GEN_PHASE_COMPLETE` 只表示流程走完：#expect失败后仍继续执行，必须按Swift Testing FAILED/exit判断。首次 candidate-compile-first.log 的缺configuration编译失败保留，不能作为行为RED或正式GREEN。

独立读取最新原始 coverage JSON，按项目官方筛选/计算函数重算：`7116/8002 = 88.93%`，达到≥80%核心门槛。原7124的 `7120/8002 = 88.98%` 仍是历史结果，不回写。本门槛只含TemperatureCore/SensorRuntime生产Swift，不扩到UI、C bridge、worker entry或硬件。

原始coverage SHA256：`256fb0ccc8d4152f599811509e4b7db8d3db6d1be56f73954ef9721ff407579d`。

## 身份及独立核对

- 原测试 Git/保存件 SHA256 `c4b7634babcd53b0ed084ae052960f4e80ff55d2ffee07966dd4af7b38e8795b`；最终测试 Git/工作树/复制件/候选 SHA256均为 `748bbadd26e22648df84cf5917edc27835942bd7ea7124e4f6623ae7f0a06fa9`。
- tests.patch SHA256 `7efcdda66e90281de171afbb7f1a710c88da51e65084ed815d25755d4e0f28b1`；已在内存按7c13 Git原件重建所有hunk，结果逐字节等于最终提交。
- `/tmp/temperature-optional-generation-ci-probe/evidence-manifest.json` 18个唯一路径，所有bytes/SHA256一致；manifest SHA256 `28a3df731a74ab4fa0bd8c254168e6b2eca523ff65ddaeb7344ebff8faf48c09`。source-hashes全部6项一致。
- 负控复制件相对生产原件只有那一条reset赋值被注释。最终复制包Sources与Package.swift共66份生产/包文件逐项等于eddd Git对象，已确认恢复；负控不会进入交付生产源。
- eddd Git提交只有一个测试文件变化；相对7124的App、Package Sources/Package.swift、Xcode工程、build-app脚本差异为空。可引用7124正式App短测和源输入等价说明，本次没有重跑App短测，不能把旧测试表示成eddd版本重新执行。

机器核对结果：`/tmp/temperature-final-generation-independent-check.json`，failures=[]。完整源码绑定/新CI及最终证据落库由根agent继续执行。

## 产品验收边界

保留原7c13 CI失败、原长测XCTest失败与同会话1000ms duration补证的不同范围；read-batch、first-frame、display/性能等未测项仍未测。用户跳过的是本轮物理睡眠/手动唤醒验收，不移除软件生命周期、异常处理功能或整项需求。

本次独立审查只读源码、Git对象、现有日志/清单和coverage；没有修改仓库、重跑测试、启动GUI、访问传感器或执行真实睡眠。
