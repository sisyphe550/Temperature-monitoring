import datetime, hashlib, json, math, pathlib, re, sqlite3, sys

root = pathlib.Path(sys.argv[1])
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def dt_ns(s):
    d = datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
    return int(d.timestamp()) * 1_000_000_000 + d.microsecond * 1000
def percentile(xs, q):
    if not xs: return None
    ys = sorted(xs)
    return ys[max(0, min(len(ys)-1, math.ceil(len(ys)*q)-1))]

events = []
for line in (root/'long-ui.log').read_text(errors='replace').splitlines():
    if line.startswith('LONG_UI_'):
        try: events.append(json.loads(line.split(' ', 1)[1]))
        except (ValueError, IndexError): pass
raw = [json.loads(l) for l in (root/'actual-cpu-max-events.jsonl').read_text().splitlines() if l.strip()]
observations = [json.loads(l) for l in (root/'live-observations.jsonl').read_text().splitlines() if l.strip()]
phases = []
for end in (e for e in events if e.get('event')=='LONG_UI_PHASE_END'):
    period = end['period_ms']
    start = next(e for e in events if e.get('event')=='LONG_UI_PHASE_START' and e['period_ms']==period)
    begin_ns, end_ns = dt_ns(start['utc']), dt_ns(end['utc'])
    rows = [r for r in raw if r['period_ms']==period and begin_ns<=r['wall_ns']<=end_ns]
    diffs = [(b['elapsed_ns']-a['elapsed_ns'])/1e6 for a,b in zip(rows, rows[1:])]
    transitions = [{'start_elapsed_ns':a['elapsed_ns'], 'end_elapsed_ns':b['elapsed_ns'],
                    'gap_ms':(b['elapsed_ns']-a['elapsed_ns'])/1e6, 'old_segment':a['segment'],
                    'new_segment':b['segment']} for a,b in zip(rows, rows[1:]) if a['segment']!=b['segment']]
    awake = end['held_awake_seconds']
    continuous = end['continuous_monotonic_seconds']-start['continuous_monotonic_seconds']
    span_ms = (rows[-1]['elapsed_ns']-rows[0]['elapsed_ns'])/1e6 if len(rows)>1 else 0
    phases.append({'period_ms':period,'start':start,'end':end,'held_awake_seconds':awake,
        'observed_continuous_seconds':continuous,'complete_600_awake_seconds':awake>=600,
        'own_cpu_main_success_count_inside_ui_window':len(rows),'first':rows[0] if rows else None,
        'last':rows[-1] if rows else None,'observed_interval_ms':{'p50':percentile(diffs,.5),
        'p95':percentile(diffs,.95),'p99':percentile(diffs,.99),'max':max(diffs,default=None)},
        'cadence_count_shortfall_estimate_percent':100*(1-(len(rows)-1)/(span_ms/period)) if span_ms else None,
        'segment_transitions':transitions})

snapshot = root/'final-before-normal-quit.sqlite'
db = {}
if snapshot.exists():
    c=sqlite3.connect(snapshot.as_uri()+'?mode=ro',uri=True)
    c.execute('PRAGMA query_only=ON')
    db['snapshot_sha256']=sha(snapshot)
    db['counts']={t:c.execute('SELECT count(*) FROM '+t).fetchone()[0] for t in ['raw_samples','ema_samples','aggregates','gaps','committed_batches']}
    db['sources']=c.execute('SELECT kind,connection_generation,count(*) FROM sources GROUP BY kind,connection_generation').fetchall()
    db['gap_summary']=c.execute('SELECT reason,count(*),sum(end_elapsed_ns IS NULL) FROM gaps GROUP BY reason').fetchall()
    db['segments_schema']=c.execute('PRAGMA table_info(segments)').fetchall()
    db['segment_reason_counts']=c.execute('SELECT reason,count(*) FROM segments GROUP BY reason').fetchall()
    c.close()

report={'execution_kind':'formal-release-app','source_commit':'c354b0392a91367d42708d7424fd0e133af825b9',
    'app_sha256':'9f786ee330531d2d194ef2c88f04c83c314de3253a1e218ea45df12f5aeabc3c',
    'worker_sha256':'74b44d0617c4524e6cf24024ad48e64304b56b8f0b18c459ad8c364c7f8cb59f',
    'phases':phases,'all_five_completed':len(phases)==5 and all(p['complete_600_awake_seconds'] for p in phases),
    'session_id':'ad735257-fea5-41a0-8e1b-644c8d2bc191','database_before_quit':db,
    'raw_collector_count':len(raw),'raw_collector_unique_sample_ids':len({r['sample_id'] for r in raw}),
    'raw_collector_errors':(root/'event-collector.log').read_text(errors='replace') if (root/'event-collector.log').exists() else None,
    'interval_percentile_method':'nearest-rank ceil(n*q)',
    'observation_count':len(observations),'first_observation':observations[:2], 'last_observation':observations[-1:] if observations else [],
    'owned_ui_events':events, 'input_hashes':{p.name:sha(p) for p in [root/'long-ui.log',root/'actual-cpu-max-events.jsonl',root/'live-observations.jsonl']},
    'limits':['Cadence shortfall is an estimate from consecutive successful readings, not exact SamplingStatistics.skipped.',
              'Observed interval p95/p99 is not worker read-batch latency.',
              'No display-delay or first-frame percentile is measured by this collector.',
              'SQLite backup is session-owned; no other applications are included.',
              'Per-phase rows are restricted to the actual UI phase wall-clock window.']}
out=root/'full-long-run-analysis.json'
out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'report':str(out),'all_five_completed':report['all_five_completed'],'phases':[{k:p[k] for k in ['period_ms','held_awake_seconds','own_cpu_main_success_count_inside_ui_window','observed_interval_ms','cadence_count_shortfall_estimate_percent']} for p in phases]}, ensure_ascii=False,indent=2))
