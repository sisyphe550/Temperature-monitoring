#!/usr/bin/env python3
import json, subprocess, time
from pathlib import Path
root = Path('/tmp/temperature-appkit-termination-harness')
executable = root / 'TerminationHarness'
results = []
for mode in ['task', 'main-async', 'runloop']:
    started = time.monotonic()
    child = subprocess.Popen([str(executable), mode], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    timed_out = False
    try:
        stdout, stderr = child.communicate(timeout=2)
    except subprocess.TimeoutExpired:
        timed_out = True
        # This subprocess handle refers only to the harness spawned above, never another App.
        child.kill()
        stdout, stderr = child.communicate()
    duration = time.monotonic() - started
    (root / (mode + '.stdout.jsonl')).write_text(stdout)
    (root / (mode + '.stderr.log')).write_text(stderr)
    events=[]
    for line in stdout.splitlines():
        try: events.append(json.loads(line))
        except json.JSONDecodeError: pass
    result={'mode':mode,'pid':child.pid,'exit_code':child.returncode,'watchdog_timeout_seconds':2,'watchdog_fired':timed_out,
            'observed_monotonic_seconds':duration,'events':events,'stderr_file':str(root / (mode+'.stderr.log'))}
    results.append(result)
    print(json.dumps(result,ensure_ascii=False),flush=True)
(root / 'results.json').write_text(json.dumps(results,indent=2)+'\n')
# A watchdog timeout alone is not RED: require actual delegate .terminateLater reached.
red=all(r['watchdog_fired'] and 'should_terminate_return_later' in [e['event'] for e in r['events']] and 'reply_true' not in [e['event'] for e in r['events']] for r in results[:2])
green=not results[2]['watchdog_fired'] and results[2]['exit_code']==0 and all(e in [v['event'] for v in results[2]['events']] for e in ['reply_task_started','reply_true','will_terminate'])
print(json.dumps({'red_task_and_main_async':red,'green_runloop':green,'classification':'reproduced' if red and green else 'inconclusive'}),flush=True)
raise SystemExit(0 if red and green else 1)
