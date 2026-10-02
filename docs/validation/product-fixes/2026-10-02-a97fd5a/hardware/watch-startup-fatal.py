import pathlib,subprocess,time,json,datetime
out=pathlib.Path("/tmp/temperature-monitor-review-20261002.1G0KnN")
expected="/private/tmp/temperature-monitor-review-20261002.1G0KnN/negative-fatal/TemperatureMonitor.app/Contents/MacOS/TemperatureMonitor"
reports=pathlib.Path("/Users/sisyphus/Library/Application Support/io.github.sisyphe550.TemperatureMonitor/Diagnostics/reports")
previous=set(reports.glob("fatal-*.json"))
seen=False;events=[];begin=None
for i in range(1200):
    result=subprocess.run(["ps","-axo","pid,comm"],capture_output=True,text=True,check=True)
    pids=[int(line.strip().split(" ",1)[0]) for line in result.stdout.splitlines() if expected in line]
    if pids or seen:
        if begin is None: begin=time.monotonic()
        events.append({"observed_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"since_first_observed_seconds":time.monotonic()-begin,"matching_pids":pids})
        seen=True
        if not pids: break
    time.sleep(0.1)
new=list(set(reports.glob("fatal-*.json"))-previous)
p=max(new,key=lambda p:p.stat().st_mtime) if new else None
r={"seen_running":seen,"automatic_exit_without_input":bool(events) and not events[-1]["matching_pids"],"process_observed_running_seconds":events[-1]["since_first_observed_seconds"] if events else None,"observations":events,"fatal_report":json.loads(p.read_text()) if p else None,"scope":"controlled copied Release startup missing-worker failure; no user input or forced termination; not running-session fatal cleanup"}
(out/"fatal-negative-timed-observation.json").write_text(json.dumps(r,ensure_ascii=False,indent=2)+"\n")
print(json.dumps({k:v for k,v in r.items() if k!="observations"},ensure_ascii=False),flush=True)
