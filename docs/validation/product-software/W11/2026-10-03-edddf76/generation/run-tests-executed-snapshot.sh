#!/bin/zsh
set -eu
case "${1-}" in
  public-red) probe_filter=WorkerBrokenPipeIntegrationTests/publicClientMapsClosedWorkerInputToProtocolFailureAndReapsChild; probe_log=/tmp/temperature-sigpipe-red-green/public-red.log ;;
  public-green) probe_filter=WorkerBrokenPipeIntegrationTests; probe_log=/tmp/temperature-sigpipe-red-green/public-green.log ;;
  unit-green) probe_filter=WorkerPipeWriteTests; probe_log=/tmp/temperature-sigpipe-red-green/unit-green.log ;;
  invalid-origin-green) probe_filter=SessionClockRegressionTests/malformedOrFutureParentOriginRejectsWorkerStartup; probe_log=/tmp/temperature-sigpipe-red-green/invalid-origin-green.log ;;
  runtime-green) probe_filter="WorkerLifecycleTests|WorkerProtocolTests|WorkerBrokenPipeIntegrationTests|WorkerPipeWriteTests"; probe_log=/tmp/temperature-sigpipe-red-green/runtime-green.log ;;
  optional-diagnostic) probe_filter=OptionalGenerationRecoveryRegressionTests; probe_log=/tmp/temperature-optional-generation-ci-probe/baseline-diagnostic.log ;;
  optional-model-red) export TM_GENERATION_POLL_DELAY_MS=125; probe_filter=OptionalGenerationRecoveryRegressionTests; probe_log=/tmp/temperature-optional-generation-ci-probe/slow-poll-red.log ;;
  optional-candidate) probe_filter=OptionalGenerationRecoveryRegressionTests; probe_log=/tmp/temperature-optional-generation-ci-probe/candidate-green.log ;;
  optional-model-green) export TM_GENERATION_POLL_DELAY_MS=125; probe_filter=OptionalGenerationRecoveryRegressionTests; probe_log=/tmp/temperature-optional-generation-ci-probe/slow-poll-green.log ;;
  optional-negative-control) probe_filter=OptionalGenerationRecoveryRegressionTests; probe_log=/tmp/temperature-optional-generation-ci-probe/negative-control-red.log ;;
  *) exit 64 ;;
esac
swift test --package-path /tmp/temperature-sigpipe-red-green/TemperatureCore --cache-path /tmp/temperature-sigpipe-red-green/cache --jobs 1 --filter "$probe_filter" > "$probe_log" 2>&1
