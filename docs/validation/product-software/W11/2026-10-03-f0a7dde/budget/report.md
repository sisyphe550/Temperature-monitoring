# Optional recovery probe budget CI diagnosis and test driver correction

## Conclusion and boundaries

The real CI failure on head `44070d6ea5d8dbe3e64a1c0ddc206f5bd2597f97` is `OptionalProbeBudgetAcrossReconnectTests.unrelatedCPUReconnectMustNotRestartExhaustedOptionalProbeBudget`: Cocoa256,5.244s, original CI log1465–1466. Cocoa256 is deliberately thrown by the test helper when its wall-time polling deadline expires. The log contains no phase context, so this report does **not** claim the exact original CI timeout phase is proven.

The controlled software model reproduces the same opaque timeout through the old test driver's virtual-time/wall-time coupling. Replacing that driver with registered task-clock boundaries passes normal and slow polling without raising the4s/2s waits. A copy-only production negative control proves the new test still detects an exhausted optional budget being restarted by CPU reconnect. No production changes, GUI, hardware, physical sleep or whole-Core test run were performed in this subtask. Root owns whole-Core and CI verification.

## Ranked hypotheses and falsifiable results

1. Wall polling controls virtual-time progression: increasing poll latency while preserving25ms increments should stop before the required virtual retry. **Confirmed in controlled model.**
2. A transport read count is observed before its failure Receipt/quarantine/budget update returns: observing the same sampling task's next future sleep should eliminate that ambiguity. **Removed by candidate barrier; source path supports this mechanism.**
3. Production CPU reconnect really restarts the exhausted optional budget: unchanged production should violate the final7/0 assertion after crossing its SSD deadline. **Not reproduced on unchanged production; the explicit guard-removal negative control is detected.**

These results do not establish which unrecorded phase failed in the original CI runner.

## Evidence

| Evidence | Actual result | Interpretation |
| --- | --- | --- |
| `ci-44070-failed.log`1465–1470 | Budget case5.244sFAIL; full355testsFAIL1issue; generation2/125 casePASS4.524s | Real CI failure isolated to budget case, no precise phase recorded |
| `model-red.log` | exit1,1test/2cases,4.796s;125ms polling times out in initial-unavailable;5ms case has no issue | Old25ms advance + wall sleep cannot reach required virtual retry under slower polling |
| `candidate-green.log` | exit0,2tests/4cases,2.429s; Budget2.132s, Generation2.429s | Same shared task-clock helper works for Budget and existing Generation; parameters2/125 both pass |
| `negative-control-red.log` | exit1,1test/2cases,12issues,2.318s; both parameters optional10/newOptional3 | Removing stopped-kind reconnect guard is caught by retained budget assertions |
| `production-restoration.json` | Copied production file hashes match current worktree; SamplingService and runner restored | Negative control confined to temporary copy |
| `model-compile-first.log` | Compile failed because an instrumentation property name was wrong | Excluded from behavioural RED evidence |

The slow model stopped at elapsed775ms with optionalReads3,discoveries1,snapshot625ms. Pending sleeps were825/850/1000/60000ms. The fourth initial failure retry was due850ms. This is a measured incomplete driver phase, not a sensor or file-opening failure.

## Candidate design

Patch paths:

- `Packages/TemperatureCore/Tests/TemperatureCoreTests/TestSupport/OptionalPhaseClock.swift`: extract existing private Generation clock to an internal test-support class. NSLock protects sleeper/task-role metadata; underlying TestClock remains unchanged. Sampling and publisher task identities distinguish overlapping deadlines; only deadlines strictly greater than current elapsed time qualify as future completion barriers.
- `Packages/TemperatureCore/Tests/TemperatureCoreTests/OptionalGenerationRecoveryRegressionTests.swift`: rename references to OptionalPhaseClock and remove the now-shared class. Generation regression semantics remain unchanged.
- `Packages/TemperatureCore/Tests/TemperatureCoreTests/OptionalProbeBudgetAcrossReconnectTests.swift`: parameters2/125ms; initial500ms advance identifies sampling retry550 and publisher700, then advances registered550/650/850 retries. Same sampling task's1000ms sleep proves all failure processing and quarantine returned before assertions.

The three failed recovery rounds are driven at60.85/120.85/180.85s, with exact optional read counts5/6/7. Each phase also observes growth of a counter incremented only after real SQLite commitBatch succeeds, and waits for the same sampling task's next future sleep. The counter includes **all committed batches**, not SSD-exclusive Receipt counts. The source path `SamplingService.performRead` awaits failed batch processing/commit; its loop sleeps after executeOptionalProbe and state transitions return, so the combined read count and task-sleep barrier proves completion rather than merely IO entry.

Initial SSD failure has one real SQL gap and zero temperature samples. Every failed probe retains old SSD raw count0. After CPU timeout/requalification, generation2 CPU has committed raw samples; generation2 SSD remains raw0. Advancing beyond a normal catalog SSD deadline and an additional61s recovery window still leaves optionalReads7/newOptionalReads0. A published generation2 SSD remains unavailable. Required CPU work therefore continues while exhausted optional sampling remains stopped.

The4s wait/2s publication timeout remains; wall polling never advances virtual time. Timeout errors now include phase, elapsed time and role-labelled sleepers; outer catch adds read/discovery/commit/snapshot counts and performs cleanup.

## Negative control and identity

`SamplingService-negative-control.swift` removes only the reconnect loop's `optionalStoppedKinds.contains(sourceKind)` removal/continue guard from the copied production source. It does not alter the candidate test. The same final Budget test fails both polling parameters after observing optional10/newOptional3. Swift Testing'sFAIL status and12issues are the pass/fail signal: nonthrowing #expect still allows BUDGET_PHASE_COMPLETE to print, so that marker does not mean a test passed.

`source-hashes.json` binds baseline, diagnostic, final candidate, shared helper, negative control and patch identities. `run-summary.json` stores exact outcome metrics. The first candidate-green and first negative-control logs are preserved separately because final source adds real SSD-gap and published-unavailable assertions. Final negative and final restored GREEN use the same final source.

## Follow-up limits

Issue52 can cover this test-driver family. This report provides three files only; the delegated Wake/Race fixes are independent test-only patches using the same helper. Root should integrate all nonconflicting test patches, run whole-Core/coverage, verify production/build inputs are unchanged, archive these new source-bound artifacts and wait for final CI. The controlled model does not prove a particular original CI stage or universal immunity to runner starvation.
