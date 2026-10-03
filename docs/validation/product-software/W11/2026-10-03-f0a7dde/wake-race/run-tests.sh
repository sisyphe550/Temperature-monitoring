#!/bin/zsh
set -u

probe_dir=/tmp/temperature-optional-wake-race-sync-probe
package_dir="$probe_dir/TemperatureCore"
case "${1:-}" in
  candidate-green)
    env SWIFTPM_MODULECACHE_OVERRIDE="$probe_dir/build/ModuleCache" CLANG_MODULE_CACHE_PATH="$probe_dir/build/ModuleCache" swift test --package-path "$package_dir" --cache-path "$probe_dir/cache" --scratch-path "$probe_dir/build" --jobs 1 --filter 'Optional(WakeRecovery|SleepAdmissionRace)RegressionTests' > "$probe_dir/candidate-green.log" 2>&1
    result=$?
    printf '%s\n' "$result" > "$probe_dir/candidate-green.exit-code"
    exit "$result"
    ;;
  negative-control-red)
    env OPTIONAL_PHASE_NEGATIVE=reject-third-receipt SWIFTPM_MODULECACHE_OVERRIDE="$probe_dir/build/ModuleCache" CLANG_MODULE_CACHE_PATH="$probe_dir/build/ModuleCache" swift test --package-path "$package_dir" --cache-path "$probe_dir/cache" --scratch-path "$probe_dir/build" --jobs 1 --filter 'Optional(WakeRecovery|SleepAdmissionRace)RegressionTests' > "$probe_dir/negative-reject-third-receipt.log" 2>&1
    receipt_result=$?
    printf '%s\n' "$receipt_result" > "$probe_dir/negative-reject-third-receipt.exit-code"
    env OPTIONAL_PHASE_NEGATIVE=cancelled-fourth-cleanup SWIFTPM_MODULECACHE_OVERRIDE="$probe_dir/build/ModuleCache" CLANG_MODULE_CACHE_PATH="$probe_dir/build/ModuleCache" swift test --package-path "$package_dir" --cache-path "$probe_dir/cache" --scratch-path "$probe_dir/build" --jobs 1 --filter OptionalSleepAdmissionRaceRegressionTests > "$probe_dir/negative-cancelled-fourth-cleanup.log" 2>&1
    cleanup_result=$?
    printf '%s\n' "$cleanup_result" > "$probe_dir/negative-cancelled-fourth-cleanup.exit-code"
    if [[ "$receipt_result" != 0 && "$cleanup_result" != 0 ]]; then exit 0; fi
    exit 1
    ;;
  *)
    printf '%s\n' 'Only fixed modes candidate-green or negative-control-red are allowed.' >&2
    exit 64
    ;;
esac
