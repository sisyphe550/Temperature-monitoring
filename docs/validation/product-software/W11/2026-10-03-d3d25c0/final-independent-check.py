import collections
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

root=Path('/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring')
arc=root/'docs/validation/product-software/W11/2026-10-03-f9e850c'
issues=[]
digest=lambda data:hashlib.sha256(data).hexdigest()
manifest=json.loads((arc/'manifest.json').read_text())
listed=set()
for record in manifest['files']:
    name=record['path']; listed.add(name)
    data=(arc/name).read_bytes()
    if digest(data)!=record['sha256'] or len(data)!=record['bytes']:
        issues.append('archive hash/size: '+name)
    if 'uncompressed_sha256' in record:
        raw=gzip.decompress(data)
        if digest(raw)!=record['uncompressed_sha256'] or len(raw)!=record['uncompressed_bytes']:
            issues.append('uncompressed hash/size: '+name)
actual={str(p.relative_to(arc)) for p in arc.rglob('*') if p.is_file()}-{'manifest.json'}
if listed!=actual:issues.append('manifest files differ: '+str(listed^actual))
identity=json.loads((arc/'source-and-build-identity.json').read_text())
source=identity['source_commit']
for name,expected in identity['source_files_sha256'].items():
    committed=subprocess.check_output(['git','-C',str(root),'show',source+':'+name])
    if digest(committed)!=expected:issues.append('commit source mismatch: '+name)
    if digest((root/name).read_bytes())!=expected:issues.append('working source mismatch: '+name)
ui=json.loads((arc/'short-ui/build-and-run-identity.json').read_text())
ui_manifest=json.loads((arc/'short-ui/manifest.json').read_text())
for item in ui_manifest['attachments']:
    raw=(arc/'short-ui'/item['file']).read_bytes()
    if digest(raw)!=item['sha256'] or len(raw)!=item['bytes']:issues.append('UI attachment mismatch '+item['file'])
if ui['formal_app']!=identity:issues.append('UI build identity differs from source identity')
raw_log=Path(ui['raw_log_path']).read_bytes()
if digest(raw_log)!=ui['raw_log_sha256'] or len(raw_log)!=ui['raw_log_bytes']:issues.append('UI original retry log hash mismatch')
if b'** TEST SUCCEEDED **' not in raw_log:issues.append('UI retry not TEST SUCCEEDED')
failure=gzip.decompress((arc/'logs/ui-runner-bootstrap-failed.log.gz').read_bytes())
if b'** TEST FAILED **' not in failure or b'bootstrapping' not in failure:issues.append('bootstrap failure not retained')
app=root/'build/TemperatureMonitor.app/Contents/MacOS/TemperatureMonitor'
worker=root/'build/TemperatureMonitor.app/Contents/MacOS/SensorWorker'
if app.is_file() and digest(app.read_bytes())!=identity['app_sha256']:issues.append('actual App hash differs')
if worker.is_file() and digest(worker.read_bytes())!=identity['worker_sha256']:issues.append('actual worker hash differs')
catalog=json.loads((root/'docs/contracts/acceptance-evidence-catalog-v1.json').read_text())
acceptance=json.loads((root/'docs/contracts/acceptance-v1.json').read_text())
requirements={r['id']:r for r in acceptance['requirements']}
six=['REQ-031','REQ-033','REQ-034','REQ-035','REQ-036','REQ-037']
summaries={}
for req in six:
    r=catalog['requirement_results'][req]
    artifacts=[catalog['artifacts'][a] for a in r['evidence']]
    required_tc=set(requirements[req]['tests'])
    tc={g for a in artifacts for g in a['tc_groups']}
    kinds={a['kind'] for a in artifacts}
    passed=all(a['result']=='passed' and a['kind']!='waiver' for a in artifacts)
    if r['verification']!='product-accepted-local' or r['outstanding'] or not required_tc<=tc or not set(r['required_evidence_kinds'])<=kinds or not passed:
        issues.append('six-REQ acceptance boundary: '+req)
    if requirements[req]['verification']!=r['verification']:issues.append('acceptance/catalog mismatch: '+req)
    for a in artifacts:
        if digest((root/a['path']).read_bytes())!=a['sha256']:issues.append('artifact hash mismatch: '+a['path'])
        ok=subprocess.run(['git','-C',str(root),'merge-base','--is-ancestor',a['source_commit'],catalog['delivery_commit']]).returncode==0
        if not ok:issues.append('artifact source not delivery ancestor: '+req)
    summaries[req]={'required_tc':sorted(required_tc),'required_kinds':r['required_evidence_kinds'],'verification':r['verification'],'new_case':r['covered_cases'][-1]}
base=json.loads(subprocess.check_output(['git','-C',str(root),'show',source+':docs/contracts/acceptance-evidence-catalog-v1.json']))
changes=[k for k,v in catalog['requirement_results'].items() if v['verification']!=base['requirement_results'][k]['verification']]
if set(changes)!=set(six):issues.append('more/fewer than six verdict changes: '+str(changes))
pending_scope={}
for req in ['REQ-094','REQ-110']:
    r=catalog['requirement_results'][req]
    scope=' '.join(r['outstanding'])
    if r['verification']!='pending-product-acceptance' or not r['outstanding']:issues.append('pending scope lost: '+req)
    pending_scope[req]={'verification':r['verification'],'outstanding':r['outstanding']}
counter=dict(collections.Counter(r['verification'] for r in catalog['requirement_results'].values()))
retired=sum(r['status']=='retired' for r in acceptance['requirements'])
counts={'catalog':counter,'retired':retired}
result={'source_commit':source,'archive_manifest_files':len(listed),'source_files_checked_against_git_and_working_bytes':len(identity['source_files_sha256']),'ui_owned_attachments':len(ui_manifest['attachments']),'ui_retry_tests':ui_manifest['tests'],'only_changed_verdicts':changes,'requirements':summaries,'counts':counts,'pending_scope':pending_scope,'failures':issues,'scope':'Read-only hash/source/REQ binding checks and actual recorded retry log inspection. No test rerun, GUI or physical sleep.'}
out=Path('/tmp/temperature-final-f9-supplemental-check.json')
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(bool(issues))
