import datetime, hashlib, json, math, pathlib, sqlite3
root=pathlib.Path('/tmp/temperature-long-ui-20261003T043223Z')
prior=json.loads((root/'full-long-run-analysis.json').read_text())
ending=json.loads((root/'independent-1000ms-duration.json').read_text())
snap=root/'independent-final-state/actual-1000ms-end.sqlite'
raw=[json.loads(x) for x in (root/'actual-cpu-max-events.jsonl').read_text().splitlines() if x.strip()]
byid={r['sample_id']:r for r in raw};original_ids=set(byid)
c=sqlite3.connect(snap.as_uri()+'?mode=ro',uri=True);c.execute('PRAGMA query_only=ON')
names=['sample_id','series_id','segment','elapsed_ns','wall_ns','period_ms','value_c','freshness','source_wall_ns']
rows=c.execute("SELECT r.sample_id,r.series_id,r.segment,r.elapsed_ns,r.wall_ns,r.period_ms,r.value_c,r.freshness,r.source_wall_ns FROM raw_samples r JOIN series s USING(series_id) WHERE s.kind='cpuMain' ORDER BY elapsed_ns").fetchall();c.close()
overlap=0
for row in rows:
    event=dict(zip(names,row)); sid=event['sample_id']
    if sid in byid:
        assert event==byid[sid],sid
        overlap+=1
    byid[sid]=event
assert overlap>0
merged=sorted(byid.values(),key=lambda r:r['elapsed_ns'])
assert len(merged)==len(set(r['elapsed_ns'] for r in merged))
def ns(s):
    d=datetime.datetime.fromisoformat(s.replace('Z','+00:00'));return int(d.timestamp())*1_000_000_000+d.microsecond*1000
start=ending['phase_start'];a=ns(start['utc']);b=ns(ending['utc'])
phase=[r for r in merged if r['period_ms']==1000 and a<=r['wall_ns']<=b]
diffs=[(v['elapsed_ns']-u['elapsed_ns'])/1e6 for u,v in zip(phase,phase[1:])]
def percentile(q):return sorted(diffs)[math.ceil(len(diffs)*q)-1] if diffs else None
interval={'p50':percentile(.5),'p95':percentile(.95),'p99':percentile(.99),'max':max(diffs,default=None)}
span=(phase[-1]['elapsed_ns']-phase[0]['elapsed_ns'])/1e6
phase_result={'period_ms':1000,'held_awake_seconds':ending['held_awake_seconds'],
    'start_utc':start['utc'],'end_utc':ending['utc'],'duration_at_least_600_seconds':ending['duration_at_least_600_seconds'],
    'successful_cpu_main_count':len(phase),'observed_sample_span_seconds':span/1000,
    'successful_finish_interval_ms':interval,'cadence_count_shortfall_estimate_percent':100*(1-(len(phase)-1)/(span/1000)),
    'evidence_kind':'independent CUA+clock+owned SQLite observation of the same continuous interval',
    'same_app_pid':88391,'same_worker_pid':88506,'same_session':prior['session_id'],
    'elapsed_strictly_increasing':all(v['elapsed_ns']>u['elapsed_ns'] for u,v in zip(phase,phase[1:])),
    'segments':sorted(set(r['segment'] for r in phase)),
    'snapshot_row_count':len(rows),'overlapping_sample_ids':overlap,'new_sample_ids_from_snapshot':len(byid)-len(original_ids)}
report={'source_commit':prior['source_commit'],'app_sha256':prior['app_sha256'],'worker_sha256':prior['worker_sha256'],
    'execution':'formal-release-app','fixture':False,'configuration':'Release','model':'Mac16,13','os_build':'24G419',
    'session_id':prior['session_id'],'original_xctest_result':'failed_ax_cpu_picker_missing',
    'original_four_complete_phases':prior['phases'],'independent_1000ms_continuity':phase_result,
    'all_five_duration_conditions_observed':len(prior['phases'])==4 and all(p['complete_600_awake_seconds'] for p in prior['phases']) and phase_result['duration_at_least_600_seconds'],
    'ui_observations_transcribed_from_native_cua':[
      {'utc':'2026-10-03T05:20:34Z','period_ms':1000,'cpu_ema_c':79.7,'scope':'Cua getApp main dashboard, no process restart; initial observation time rounded to UI second'},
      {'utc':'2026-10-03T05:22:26.859Z','cpu_ema_c':76.1,'scope':'updated main dashboard AX diff'},
      {'utc':'2026-10-03T05:24:02.859Z','period_ms':1000,'cpu_ema_c':82.3,'fatal_present':False,'scope':'full main dashboard AX'}],
    'normal_exit':{'method':'native CUA clicked actual app.quit button after final observation','app_and_worker_absent':True,
      'owned_session_directory_absent':True,'verification':'pgrep exit1 and Sessions listing empty after click; subsequent sleep session was separately created'},
    'not_measured':{'exact_scheduler_skipped':None,'worker_read_batch_latency':None,'screen_display_delay':None,'first_frame_latency':None},
    'merge_method':'union by sample_id of original collector and final same-session SQLite snapshot; every overlapping record equal; original files remain unchanged',
    'limits':['The original failed XCTest is not rewritten as passed.',
      'Supplemental final interval never stopped or changed App/session; no separate partial runs are stitched.',
      'Original observers stopped with the runner; their tail alone does not cover the final extension.',
      'Owned SQLite snapshot overlaps original raw collector and adds the uninterrupted final readings.',
      'Interval percentiles and count shortfall do not measure exact skipped, read latency or display latency.',
      'CPU12 protocol and qualification evidence are separate from this CPU-main continuity ledger.'],
    'input_hashes':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'actual-cpu-max-events.jsonl',root/'independent-1000ms-duration.json',snap]}}
dest=root/'independent-five-period-duration-ledger.json';dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'report':str(dest),'all_five_duration_conditions_observed':report['all_five_duration_conditions_observed'],'independent_1000ms':phase_result},ensure_ascii=False,indent=2))
