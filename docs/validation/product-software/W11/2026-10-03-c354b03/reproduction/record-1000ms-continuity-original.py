import ctypes, datetime, hashlib, json, pathlib, subprocess, time

root=pathlib.Path('/tmp/temperature-long-ui-20261003T043223Z')
events=[]
for line in (root/'long-ui.log').read_text(errors='replace').splitlines():
    if line.startswith('LONG_UI_'):
        try: events.append(json.loads(line.split(' ',1)[1]))
        except (ValueError,IndexError):pass
phase=next(e for e in events if e.get('event')=='LONG_UI_PHASE_START' and e['period_ms']==1000)
lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib')
class Timebase(ctypes.Structure):_fields_=[('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
tb=Timebase();lib.mach_timebase_info(ctypes.byref(tb));lib.mach_continuous_time.restype=ctypes.c_uint64
awake=time.monotonic(); continuous=lib.mach_continuous_time()*tb.numer/tb.denom/1e9
held=awake-phase['start_awake_uptime_seconds']
p=subprocess.run(['/bin/ps','-p','88391,88506','-o','pid=,ppid=,comm='],capture_output=True,text=True)
result={'event':'INDEPENDENT_1000MS_CONTINUOUS_DURATION_OBSERVATION','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'source_commit':'c354b0392a91367d42708d7424fd0e133af825b9','session_id':phase['session_id'],
    'period_ms':1000,'original_xctest_result':'failed_ax_cpu_picker_missing','original_last_ui_progress_awake_seconds':360.96940612467006,
    'phase_start':phase,'awake_uptime_seconds':awake,'continuous_monotonic_seconds':continuous,'held_awake_seconds':held,
    'duration_at_least_600_seconds':held>=600,'app_and_worker_processes':p.stdout,'ps_exit':p.returncode,
    'source_identity_unchanged':'Source and App/worker binaries are frozen; process and session observed unchanged.',
    'limits':['This independent duration observation does not rewrite the failed XCTest result.',
              'AX picker was temporarily unavailable to XCTest; independent CUA found the live main window.',
              'UI observations and successful CPU raw continuity must be reviewed with this timing record.',
              'No exact scheduler skipped, read-batch or display-delay percentile is measured.']}
target=root/'independent-1000ms-duration.json';target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
