import datetime,json,pathlib,sqlite3,sys,time
OUT=pathlib.Path(sys.argv[1]); ROOT=pathlib.Path('/Users/sisyphus/Library/Application Support/io.github.sisyphe550.TemperatureMonitor/Sessions');last=-1;count=0;start=time.monotonic();path=OUT/'actual-cpu-max-events.jsonl'; SESSION=None
while time.monotonic()-start<300 and SESSION is None:
 log=OUT/'long-ui.log'
 if log.exists():
  for line in log.read_text(errors='replace').splitlines():
   if line.startswith('LONG_UI_BEGIN {'):
    SESSION=json.loads(line[line.index('{'):])['session_id'];break
 if SESSION is None:time.sleep(2)
if SESSION is None:raise SystemExit('No owned LONG_UI_BEGIN within startup deadline')
DB=ROOT/SESSION/'monitor.sqlite'
with path.open('w') as f:
 while time.monotonic()-start<3800 and DB.exists():
  try:
   c=sqlite3.connect(DB.as_uri()+'?mode=ro',uri=True,timeout=2);c.execute('PRAGMA query_only=ON')
   rows=c.execute("SELECT r.sample_id,r.series_id,r.segment,r.elapsed_ns,r.wall_ns,r.period_ms,r.value_c,r.freshness,r.source_wall_ns FROM raw_samples r JOIN series s USING(series_id) WHERE s.kind='cpuMain' AND r.elapsed_ns>? ORDER BY r.elapsed_ns",(last,)).fetchall();c.close()
   for row in rows:
    f.write(json.dumps(dict(zip(['sample_id','series_id','segment','elapsed_ns','wall_ns','period_ms','value_c','freshness','source_wall_ns'],row)))+'\n');last=row[3];count+=1
   f.flush()
  except Exception as e:
   with (OUT/'event-collector-errors.jsonl').open('a') as err:err.write(json.dumps({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'error':repr(e)})+'\n')
  time.sleep(10)
print(json.dumps({'sample_events_collected':count,'session_id':SESSION,'last_elapsed_ns':last,'path':str(path),'note':'Actual persisted CPU max sample events; not worker read-batch latency or exact SamplingStatistics counters.'}),flush=True)
