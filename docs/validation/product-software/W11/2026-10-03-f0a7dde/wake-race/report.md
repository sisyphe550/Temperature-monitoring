# Optional Wake / Sleep Race 测试同步修复

## 当前结论

仅修改两份测试候选；复制包的65份生产 Sources 文件逐字未变。root 已运行候选有限过滤：2个测试函数、4个参数用例（每个2ms/125ms）全部通过，build35.01s、测试2.018s、进程exit0。两项测试seam负控也已执行并按预期失败，具体失败断言和cleanup完成均已核对。

此处验证软件生命周期和测试同步；没有启动正式 App、GUI、传感器或系统休眠。用户已跳过物理休眠，本报告不能用软件测试补成物理验收。

## 来源与修改边界

- 复制来源commit：`44070d6ea5d8dbe3e64a1c0ddc206f5bd2597f97`。
- 原始测试保存为 `baseline-OptionalWakeRecoveryRegressionTests.swift` / `baseline-OptionalSleepAdmissionRaceRegressionTests.swift`。
- 最终交付 `final-two-tests.patch` 只包含上述两个测试文件；已集成初始候选后可追加 `wake-eof-normalization.patch`。共享 `TestSupport/OptionalPhaseClock.swift` 由父agent负责，未包含于此patch。复制helper SHA256为 `51c8249850b9a41dabcf14c703c5244372cb3b7e3843eccdbb9e511103dbce22`。
- `source-manifest.json` 固定原始生产/测试字节。`production-unchanged-check.json` 确认复制包65份Sources与初始manifest相同。
- 旧内存探针任务已停止，无内存对照结果；不混入本轮结论。

## 测试问题与具体证据

原Wake两段轮询及Race推进器每轮把虚拟时间推进25ms，同时墙钟sleep5ms，并以4s墙钟为截止。真实执行速度可改变重试时间、错过callback和快照发布时序。

两测试先等待 `newOptionalReads >= 3` 后额外推进200ms；运输读次数发生在返回数据及SQLite提交之前，不能证明三份ProcessingReceipt。Race的catch原先直接stop，没有先释放第四失败gate，也没有保存/等待自己创建的unstructured suspend Task。

这些是源代码可识别的同步风险。当前已知CI失败阶段属于父agent处理的Budget测试；本报告没有把Wake/Race也描述为已捕获原CI失败。拟运行旧轮询的慢延迟受控RED曾被审批等待和turn_aborted中断，实际未编译、未运行、无RED日志，不计失败证据。

## 候选同步机制

1. 初始500ms触发SSD失败；550/650/850ms只在采样task对应sleep注册后推进。初始snapshot在500ms发布、700ms独立注册后识别publisher task。
2. Wake正常路径等第四失败callback/隔离完成，再验证Unavailable并suspend。
3. Race保留原关键场景：第四次read在gate等待；创建自有suspend Task，观察它触发该read的cancellation handler，仍hold gate，随后release；运输最终抛出sensorRead，而不是改成CancellationError，最后等待suspend结束。
4. 唤醒创建新的采样/publisher任务。它们首个wake+200 deadline重叠，不能按这一时刻裸识别task。候选推进至首SSD的wake+500，等待真实新SSD和CPU的SQLite提交，再以wake+600采样sleep、wake+700publisher sleep分别重新识别。
5. `batchCommitOperation` 先真实调用 `store.commitBatch`，之后才记录已提交数量；在新sampler下一次sleep注册前不把callback看成完成。
6. 新代第一、第二个真实SSD提交分别核对SQLite行数并发布snapshot，要求仍Unavailable；第三个read在store commit之前被gate挡住，核对实际read3但commit/SQLite仍2且snapshot仍Unavailable。
7. 释放第三commit gate后，等待第三SQLite提交及采样callback完成，才发布并要求新代Available。整个过程只发生3次新optional read；正式数据库读取验证3行，CPU也须有新代真实commit。
8. Race异常清理顺序为failureGate.release → await已创建suspend Task → receipts.release → controller.stop → observer.cancel/join。这样既不遗留held read，也不让并行stop与未完成suspend交错。

轮询延迟只影响墙钟等待，不负责推进虚拟时间。未延长既有4s/2s期限、未把全套测试串行、未删除三次新提交和第四次in-flight取消断言。

## 已运行结果

`run-tests.sh candidate-green` 是root统一审批执行的固定白名单模式；两suite有限过滤、jobs1、独立cache和scratch目录，没有另跑全套。

| 用例 | 轮询ms | 新optional read | 新SSD已提交 | 新CPU已提交 | 结果 |
|---|---:|---:|---:|---:|---|
| Wake | 2 | 3 | 3 | 7 | pass |
| Wake | 125 | 3 | 3 | 7 | pass |
| Race | 2 | 3 | 3 | 7 | pass |
| Race | 125 | 3 | 3 | 7 | pass |

真实输出见 `candidate-green.log` / `candidate-green.exit-code`；解析见 `candidate-green-results.json`。Swift Testing汇总为2 tests，各2参数case，不能重复计为4个独立@Test函数。先行XCTest桥接的“0 tests”不是最终结果，实际Swift Testing正执行上述有限用例。

## 已运行的负控与判读

固定模式 `run-tests.sh negative-control-red` 只使用现有测试seam，不修改生产代码：

- `OPTIONAL_PHASE_NEGATIVE=reject-third-receipt`：释放第三commit gate后故意让测试hook抛integrityConflict；实际测试exit1、1.911s、2个测试函数共4参数case产生4issues。每case在要求lastAcceptFailure=nil的必要断言处失败，全部显示newread3/commit2，全部记录cleanup完成，未进入成功marker。
- `OPTIONAL_PHASE_NEGATIVE=cancelled-fourth-cleanup`：在Race已观察第四held read取消后故意抛出受控阶段错误；实际测试exit1、0.699s、1测试函数共2参数case产生2issues。两个2/125mscase在850ms虚拟阶段注入错误后都记录 `SleepRace_PHASE_CLEANUP_COMPLETE`；release/join/stop终结了此受控路径。错误文本含“phase timed out”，但这是人为抛出同种阶段错误，没有发生实际deadline过期。

负控wrapper最终exit0表示其两个内部测试命令按预期非零；本报告还核对了每个失败原因和cleanup marker，未仅以退出码判定有效。它们不是生产mutation测试，也不证明全部异常路径或硬件睡眠。

所有实际失败和中断保留；若后续发现问题，新文件/记录说明，不删日志，不把未运行记为RED。

## 最终源与已测源的唯一差异

已测源码原样保存为 `tested-*.swift`。最终Wake只规范EOF，删除一个空白末行，SHA256由 `1db8b4054ad6422e292de0bfde68ab8b1236ec9239c89f590aea499b3c838772` 变为 `58692895a8c8407fd03403553a73884b55bd1242dd8289fb79e1db6c982f676c`；Race仍为 `b18cd27d3d163713db133ff9d03ff71ec803dc5fcb8b45165f2b3b0c3dec47c3`。无行为差异，不重复有限过滤；root负责对集成后的最终源码运行一次完整Core。该尚未运行的根验证不在本报告中冒充通过。
