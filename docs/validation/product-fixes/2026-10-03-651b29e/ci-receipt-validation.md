# CI Receipt observation stabilization

Scope: only EndToEndTests.swift; production and global ControllerFixture semantics unchanged.

RED: /tmp/temperature-monitor-review-20261002.1G0KnN/ci-core-failed-6af3f42.log, push run 37028702883 at HEAD 6af3f428f7e24e7093499ef765b94cf80a0f36e8. Raw/EMA=13, batch=1 and history95 failed; readCount=1 and sourceCount=12 passed. The same-head PR run passed, supporting a test timing race.

Cause: ControllerFixture.respondMembers enqueues sensor data then waits a fixed50ms. It does not await engine.accept, persistence.commit or valid Receipt. The test can inspect empty persisted rows/realtime memory while the read has already started.

Change: the affected test observes its CPU max EMA point at210000000ns in controller.history(.fiveMinutes) before its existing exact assertions. MonitorEngine validates the persistence Receipt before appending that EMA to the realtime buffer (MonitorEngine.swift:265-283); realtime reads that buffer (561-579). This establishes both commit and engine state publication, while a DB batch count alone can precede state publication. Expected temperature95 and exact13/13/1 counts remain separate unchanged assertions.

Wait uses ContinuousClock2s deadline and5ms polling of actual state. Query errors and lastAcceptFailure propagate; timeout records an explicit Issue and throws. The caller stops the controller on wait failure. No fixed extra delay, swallowed error, relaxed assertion, fixture-global change or production change.

GREEN: three filtered runs in/tmp, one test each, exit0. Logs: /tmp/temperature-ci-receipt-observation-green-{1,2,3}.log. Existing CI is RED evidence; no extra gate infrastructure added.

Next verification: root applies /tmp/temperature-ci-receipt-observation.patch, runs all core tests with coverage, and independently reviews Receipt→EMA publication plus timeout/error handling. No Release rebuild needed. New-head CI result is still required to claim CI fixed.
