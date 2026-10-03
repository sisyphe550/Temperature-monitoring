# Optional Wake/Race 与最终测试族独立只读审查（2026-10-03）

## 结论与范围

最终normalized Wake/Race两文件候选及集成测试族未发现阻断问题。它们使用已独立审过的共享OptionalPhaseClock替代25ms虚拟步进/5ms墙钟轮询，保留软件休眠/唤醒回归目标并加强真实SQLite commit边界。当前集成五文件（Budget、Generation、Wake、Race、OptionalPhaseClock）均为测试源，生产与构建输入相对7124无差异。

本审查实读最终筛选GREEN、两项负控原始输出、集成全量Core与覆盖率原始JSON，并核对最终manifest/patch/源码身份。未运行测试、GUI、传感器或系统睡眠，未修改仓库。源提交f0a7dde已逐文件核对；新归档与新head CI由根agent处理，本报告不提前宣称它们完成。

## 具体语义

1. 初始500ms阶段以采样550ms和publisher700ms识别task，后续按真实registered sampling sleep推进550/650/850ms。2/125ms仅影响条件检查频率，不累计虚拟时间；future deadline必须大于now，排除同deadline的其它task与已唤醒旧sleep。
2. Wake正常隔离后等待同采样task的1000ms sleep，覆盖整个第四失败处理与可选状态callback返回，再发布不可用快照。Race明确等待第四读位于PendingFailureGate内，启动自己拥有的suspend Task，观察任务取消且gate仍等待，随后release、join suspend；第四读仍抛原sensorRead，没有提前release或改成CancellationError。保留生产stop在await采样循环后捕获wake恢复状态的回归目标。
3. 唤醒创建新的采样/publisher任务；首个wake+200ms sleep重叠，候选没有按此deadline混认角色。首SSD和新代CPU真实SQLite commit后，以首读+100ms采样/+200ms publisher重新识别fresh task。
4. commit hook在真实store.commitBatch返回后记录新代SSD/CPU计数。该计数证明SQLite写入已返回，不单独证明完整ProcessingReceipt/engine/availability callback结束；同采样task新future sleep补足流程完成边界。SQL独立校验SSD1/2/3、新CPU≥1，前两次快照仍不可用。
5. 第三新代SSD在beforeCommit gate被阻塞：读数已3，但commit计数和SQL仍2；publisher独立发布快照，仍须不可用。release后真commit3、采样callback完成、lastAcceptFailure=nil，才要求新代SSD可用。reject-third-receipt只在测试hook拒绝该commit，生产文件不变。
6. Race catch先failureGate.release，join仍拥有的suspend Task，再receipts.release、controller.stop、observer.cancel/join。gate忽略取消直到release；release幂等、提前release安全、continuation在锁外resume，排除原catch直接stop被gate阻塞的路径。cancelled-fourth-cleanup只在已观察取消且仍waiting时主动throw以检查收尾。
7. 等待保留4秒/2秒墙钟期限，错误含phase/elapsed/sleeps；慢poll验证检查频率解耦，不保证任意线程饥饿下通过。PHASE_COMPLETE可出现在非throwing #expect失败之后，不能替代框架结果；CLEANUP_COMPLETE只证明catch清理返回。

## 实读运行证据

| 证据 | 真实结果 | 判读 |
| --- | --- | --- |
| candidate-green.log | build35.01s；2tests/2suites、4参数case PASS2.018s；exit0 | Wake/Race各2/125ms，每case新SSD读3、已提交3、新CPU已提交7 |
| negative-reject-third-receipt.log | 2tests/2suites、4参数case FAIL4issues1.911s；exit1 | 每case目标lastAcceptFailure=nil必要断言失败，读3/commit2，全部catch清理结束，无成功marker |
| negative-cancelled-fourth-cleanup.log | 1test/1suite、2参数case FAIL2issues0.699s；exit1 | 850ms已取消第四held read时主动抛受控phase错误，两case release/join/stop均返回 |
| /tmp/temperature-w11-optional-family-final-core.log | 355tests/57suites PASS3.093s | 使用最终normalized集成五文件；Budget/Generation/Wake/Race全部2/125参数通过 |
| 最终TemperatureCore.json | 7116/8002=88.93% | 独立复算43个TemperatureCore/SensorRuntime生产Swift文件，排除测试/AppUI/C桥/worker入口 |

负控是测试seam，不是生产mutation；其非零退出须结合上述目标断言与cleanup判读。cancelled-fourth错误文本含“phase timed out”，实为人为抛出该类型，没有deadline过期。拟运行旧Wake/Race慢轮询受控RED曾在审批/中断阶段停止，实际未编译、未运行，不算RED；原CI已知失败属于Budget，不能据此声称Wake/Race原CI失败或唯一原因已定位。

## 已测源、最终源与完整性

基线44070d6ea5d8dbe3e64a1c0ddc206f5bd2597f97；最终源提交f0a7dde76e3e02e66f23aed47915bb75e2fa438b仅修改上述五个tests/helper路径。Git对象五文件SHA均等于集成/最终候选，工作树干净。

- 筛选GREEN与两项负控使用的Wake SHA256：1db8b4054ad6422e292de0bfde68ab8b1236ec9239c89f590aea499b3c838772。
- 最终normalized Wake SHA256：58692895a8c8407fd03403553a73884b55bd1242dd8289fb79e1db6c982f676c。独立逐字节确认仅删除一个EOF空行；当前仓库与最终候选一致。最终全量Core实际使用该源，不将旧筛选输出冒称它的再次执行。
- Race已测/最终/集成SHA256均为b18cd27d3d163713db133ff9d03ff71ec803dc5fcb8b45165f2b3b0c3dec47c3。
- tested-two-tests.patch SHA256：19168b85a49d5c32f6bad62b869a976f1e507aaa2352519375392fcb1988858a；final-two-tests.patch：25de65bdecc10b535919eb8673db04da5a7fbfd20714ea7201fbea2f62414bbd。两份补丁全部hunk按44070 Git对象在内存重建，与对应tested/final源码完全一致。
- final-evidence-manifest.json SHA256：057b4d1e54190fda74a0d210db9c9844d3a773f2a81a4b684633c4e2830c2a28；26项/26个唯一路径逐项SHA通过，原tested源、normalized源及EOF差异均保留。
- 复制包65生产Sources及Package.swift共66文件与44070 Git/当前工作树完全一致；共享clock SHA51c8249850b9a41dabcf14c703c5244372cb3b7e3843eccdbb9e511103dbce22，复制/当前相同。集成五文件全部匹配各最终候选SHA。当前App、Package Sources/Package.swift、Xcode工程/build-app输入相对7124差异为空，git diff --check无输出。
- 最终Core原始log SHA256：9ae3dd9a36ee2c43f6f1cb37e5df3c815a35361a47014d3f2e86a5c691155197。
- 最终覆盖率原始JSON SHA256：52ee37a7bd31625959e9a12d6894e25b51fdc5e34e0960aed1f7bf554e3317e2。保持此前7124的88.98%及generation阶段88.93%为历史独立记录。

机器核对文件：/tmp/temperature-final-wake-race-independent-check.json，failures=[]。Budget/Generation/helper另见已交付 /tmp/temperature-final-budget-independent-review.md。Race第二审查 /tmp/temperature-race-final-independent-review.md SHA83e5c27fafd05396b846b564d48c6dc2941aa659fbb25a4be940adc0f35fa584，结果一致；其范围不包含本报告新增的全量Core/最终manifest核对。

## 保留验收边界

软件生命周期需求与回归继续保留。用户仅跳过本轮物理睡眠/人工唤醒验收；本次不会发生真实系统睡眠，也不豁免REQ094/110其余生命周期/性能需求。原长测XCTest失败、独立五档duration观察、未测性能项目均保留原结论。正式App继续引用7124实机记录及构建源等价，本次只修改测试，没有重新运行正式App，不把CI/软件模型当硬件验收。
