# PR #44 / Issue #45：EndToEnd提交完成观测独立复核

## 裁决

补丁`/tmp/temperature-ci-receipt-observation.patch`只修改EndToEndTests.swift，等待边界成立，未发现重要问题；生产代码不变。原始Raw13、EMA13、committed_batches1、readCount1、成员12及历史95°C断言全部保留。

## 依据

- CI失败记录：push run37028702883 / HEAD6af3f428中的该用例在三个SQLite数量及history95四项失败；同head另一核心run通过。Fixture.respondMembers原本释放传感器IO后固定等待50ms，不能证明加工和持久化完成。
- 新helper固定查询本cpuMax SeriesID的fiveMinutes历史，asOf/目标样本为210000000ns；不推进TestClock，避免产生下一CPU读数。Controller.history该层读取MonitorEngine.realtime内存buffer；MonitorEngine.accept在真实commit返回并validateReceipt后才appendEMA。因此目标EMA可见证明本次合法Receipt后的发布事实，SQLite断言随后可执行。
- 等待存在ContinuousClock两秒deadline，每次未完成后sleep5ms；history错误直接传播，lastAcceptFailure直接抛，timeout记录明确Issue再throw，外层stop后重新抛出。无try?、空结果成功或超时吞错。
- gate只观测时间戳，95°C正确性仍由后面的原始断言校验；本Fixture新建空会话且限定SeriesID/210ms，旧样本不能满足条件。
- 使用补丁完整文件在独立/tmp副本运行：10 tests /2 suites PASS，exit0，包含EndToEndTests及TC-UPSTREAM-BOUNDARY。日志：`/tmp/temperature-independent-ci-receipt-test.log`。构建/module cache均在/tmp，未修改worktree。

此裁决覆盖测试同步修改；PR当前head完整CI结果和Issue45状态由实际新运行确认，不能用本地定向通过替代。无需重新运行正式App，因为生产Sources/契约未改。

## 提交后复核

实际测试提交：`651b29ee9e158ccf8c06f63945460c09e3bbbb65`，仅EndToEndTests.swift增加29行。与原162文件清单比较，161份一致，唯一变化为该测试文件；正式App的production/resources/contracts/UI/workflows不变。实现方报告该提交本地全量337 tests /52 suites通过、覆盖7067/7966=88.71%；独立执行范围仍为上述10 tests /2 suites，未将实现方全量标作独立全量。
