import datetime,json,pathlib,sqlite3,subprocess,sys,time
OUT=pathlib.Path(sys.argv[1]); LOG=OUT/'long-ui.log'; ROOT=pathlib.Path('/Users/sisyphus/Library/Application Support/io.github.sisyphe550.TemperatureMonitor/Sessions')
start=time.monotonic(); last_backup=0; final_seen=False; session=None; app_pid=None
OUT.mkdir(parents=True,exist_ok=True)
def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def emit(x):
 with (OUT/'live-observations.jsonl').open('a') as f:f.write(json.dumps(x,ensure_ascii=False)+'\n')
def backup(c,label):
 p=OUT/(label+'.sqlite'); dest=sqlite3.connect(p)
 try:c.backup(dest)
 finally:dest.close()
 return str(p)
while time.monotonic()-start<4300:
 text=LOG.read_text(errors='replace') if LOG.exists() else ''
 if session is None:
  for line in text.splitlines():
   if line.startswith('LONG_UI_BEGIN '):
    x=json.loads(line[len('LONG_UI_BEGIN '):]);session=x['session_id'];emit({'utc':utc(),'event':'attached_from_owned_test_begin','session_id':session,'formal_app_path':x['app_path']});break
  if session is None:time.sleep(2);continue
 db=ROOT/session/'monitor.sqlite'; record={'utc':utc(),'session_id':session,'database_exists':db.exists(),'observer_monotonic_seconds':time.monotonic()}
 if not db.exists():emit(record);emit({'utc':utc(),'event':'observed_session_removed','session_id':session,'final_snapshot_recorded':final_seen});break
 try:
  c=sqlite3.connect(db.as_uri()+'?mode=ro',uri=True,timeout=2);c.execute('PRAGMA query_only=ON');c.execute('BEGIN')
  record['counts']={t:c.execute(f'SELECT count(*) FROM {t}').fetchone()[0] for t in ['raw_samples','ema_samples','aggregates','gaps','committed_batches']}
  record['cpu_periods']=c.execute("SELECT r.period_ms,count(*),min(r.elapsed_ns),max(r.elapsed_ns),min(r.wall_ns),max(r.wall_ns) FROM raw_samples r JOIN series s USING(series_id) WHERE s.kind='cpuMain' GROUP BY r.period_ms").fetchall()
  record['sources']=c.execute('SELECT kind,count(*),max(connection_generation) FROM sources GROUP BY kind').fetchall();record['gaps']=c.execute('SELECT reason,count(*),sum(end_elapsed_ns IS NULL) FROM gaps GROUP BY reason').fetchall();c.commit()
  record['sizes']={p.name:p.stat().st_size for p in db.parent.iterdir() if p.is_file()}
  if 'LONG_UI_FINAL_SNAPSHOT' in text and not final_seen:record['final_snapshot']=backup(c,'final-before-normal-quit');final_seen=True
  elif time.monotonic()-last_backup>=120:record['rolling_snapshot']=backup(c,'latest-live-snapshot');last_backup=time.monotonic()
  c.close()
 except Exception as e: record['observer_error']=repr(e)
 try:
  if app_pid is None:
   pids=subprocess.run(['/usr/bin/pgrep','-x','TemperatureMonitor'],capture_output=True,text=True).stdout.split()
   if len(pids)==1:app_pid=pids[0]
  if app_pid:
   children=subprocess.run(['/usr/bin/pgrep','-P',app_pid],capture_output=True,text=True).stdout.split(); selected=[app_pid]+children
   p=subprocess.run(['/bin/ps','-p',','.join(selected),'-o','pid=,ppid=,pcpu=,rss=,time=,comm='],capture_output=True,text=True);record['app_worker_resources']=p.stdout.strip().splitlines();record['ps_exit']=p.returncode
 except Exception as e:record['resource_error']=repr(e)
 emit(record);time.sleep(20)
print(json.dumps({'observer_completed':True,'session_id':session,'final_snapshot_recorded':final_seen,'out':str(OUT)},ensure_ascii=False),flush=True)
