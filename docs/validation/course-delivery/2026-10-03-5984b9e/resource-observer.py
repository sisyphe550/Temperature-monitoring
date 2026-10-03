#!/usr/bin/env python3
"""Bounded read-only observation of this run's formal App and child worker."""
from pathlib import Path
import datetime, json, os, sqlite3, subprocess, sys, time

app=Path(sys.argv[1]).resolve()
output=Path(sys.argv[2]); stop=Path(sys.argv[3])
sessions=Path.home()/'Library/Application Support/io.github.sisyphe550.TemperatureMonitor/Sessions'
before={p.name for p in sessions.iterdir() if p.is_dir()} if sessions.exists() else set()
binary=str(app/'Contents/MacOS/TemperatureMonitor')
started=time.monotonic()

def clock_seconds(text):
    try:
        days=0
        if '-' in text:
            day,text=text.split('-',1);days=int(day)
        parts=[float(v) for v in text.split(':')]
        value=0
        for v in parts:value=value*60+v
        return days*86400+value
    except ValueError:return None

def sample():
    now=datetime.datetime.now(datetime.timezone.utc).isoformat()
    rows=[]
    result=subprocess.run(['/bin/ps','-axww','-o','pid=,ppid=,%cpu=,rss=,etime=,time=,command='],capture_output=True,text=True,check=True)
    for line in result.stdout.splitlines():
        values=line.split(None,6)
        if len(values)!=7:continue
        pid,parent,cpu,rss,elapsed,cputime,command=values
        try:rows.append((int(pid),int(parent),float(cpu),int(rss),elapsed,cputime,command))
        except ValueError:continue
    parents={r[0] for r in rows if r[6]==binary or r[6].startswith(binary+' ')}
    owned=[r for r in rows if r[0] in parents or r[1] in parents and r[6].startswith(str(app/'Contents/MacOS/SensorWorker'))]
    if not owned:return None
    data={'utc':now,'observer_seconds':round(time.monotonic()-started,3),'processes':[{'pid':r[0],'ppid':r[1],'role':'app' if r[0] in parents else 'worker','cpu_percent':r[2],'rss_kib':r[3],'elapsed':r[4],'cpu_seconds':clock_seconds(r[5])} for r in owned]}
    new=[p for p in sessions.iterdir() if p.is_dir() and p.name not in before] if sessions.exists() else []
    if len(new)==1:
        database=new[0]/'monitor.sqlite'
        data['session']=new[0].name
        try:
            with sqlite3.connect(database.as_uri()+'?mode=ro',uri=True,timeout=0.1) as connection:
                row=connection.execute("SELECT count(*),min(r.elapsed_ns),max(r.elapsed_ns),min(r.value_c),max(r.value_c),min(r.period_ms),max(r.period_ms) FROM raw_samples r JOIN series s USING(series_id) WHERE s.kind='cpuMain'").fetchone()
                data['cpu_raw']={'rows':row[0],'min_elapsed_ns':row[1],'max_elapsed_ns':row[2],'min_c':row[3],'max_c':row[4],'min_period_ms':row[5],'max_period_ms':row[6]}
                data['cpu_ema_rows']=connection.execute("SELECT count(*) FROM ema_samples e JOIN series s USING(series_id) WHERE s.kind='cpuMain'").fetchone()[0]
                data['sources']=[dict(zip(['raw_key','kind','unit_evidence','evidence'],r)) for r in connection.execute('SELECT raw_key,kind,unit_evidence,evidence FROM sources ORDER BY raw_key')]
        except (sqlite3.Error,OSError) as error:data['database_observation_error']=str(error)
    else:data['new_session_count']=len(new)
    return data

with output.open('w') as stream:
    stream.write(json.dumps({'observer':'read-only ps and current-session SQLite; only exact App path and direct owned worker','app':str(app),'initial_sessions':len(before),'maximum_observer_seconds':900})+'\n');stream.flush()
    while not stop.exists() and time.monotonic()-started<900:
        try:data=sample()
        except (subprocess.SubprocessError,OSError) as error:data={'observer_error':str(error),'observer_seconds':round(time.monotonic()-started,3)}
        if data:stream.write(json.dumps(data,ensure_ascii=False)+'\n');stream.flush()
        time.sleep(2)
