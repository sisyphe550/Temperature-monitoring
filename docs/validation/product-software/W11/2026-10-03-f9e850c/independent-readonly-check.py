import datetime as dt
import gzip
import hashlib
import json
import pathlib
import random
import sqlite3
import re

root = pathlib.Path('/Users/sisyphus/.codex/worktrees/product-audit-fixes/Temperature monitoring')
arc = root / 'docs/validation/product-software/W11/2026-10-03-c354b03'
manifest = json.loads((arc / 'manifest.json').read_text())
failures = []
for item in manifest['files']:
    if not (arc / item['path']).is_file():
        failures.append(item['path'] + ': listed file missing')
        continue
    data = (arc / item['path']).read_bytes()
    if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
        failures.append(item['path'] + ': archive hash/size mismatch')
    if 'uncompressed_sha256' in item:
        content = gzip.decompress(data)
        if len(content) != item['uncompressed_bytes'] or hashlib.sha256(content).hexdigest() != item['uncompressed_sha256']:
            failures.append(item['path'] + ': decompressed hash/size mismatch')
listed = {i['path'] for i in manifest['files']}
actual = {str(p.relative_to(arc)) for p in arc.rglob('*') if p.is_file()} - {'manifest.json'}
if listed != actual:
    failures.append('archive listed files differ from actual: ' + str(listed ^ actual))
def rows(p):
    return [json.loads(line) for line in gzip.open(arc / p, 'rt')]
original = {r['sample_id']: r for r in rows('long-run/actual-cpu-max-events.jsonl.gz')}
supplemental = rows('long-run/terminal-cpu-main-supplemental.jsonl.gz')
overlap = [r for r in supplemental if r['sample_id'] in original]
if not all(r == original[r['sample_id']] for r in overlap):
    failures.append('collector/SQL overlap differs')
merged = dict(original)
merged.update({r['sample_id']: r for r in supplemental})
ledger = json.loads((arc / 'long-run/independent-five-period-duration-ledger.json').read_text())
window = ledger['independent_1000ms_continuity']
def ns(value):
    t = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    return int(t.timestamp() * 1_000_000_000)
start, end = ns(window['start_utc']), ns(window['end_utc'])
samples = sorted([r for r in merged.values() if r['period_ms'] == 1000 and start <= r['wall_ns'] <= end], key=lambda r: r['elapsed_ns'])
span = (samples[-1]['elapsed_ns'] - samples[0]['elapsed_ns']) / 1e9
if len(samples) != window['successful_cpu_main_count'] or span != window['observed_sample_span_seconds']:
    failures.append('1000 ms ledger count/span does not reproduce')
if any(a['elapsed_ns'] >= b['elapsed_ns'] for a,b in zip(samples,samples[1:])):
    failures.append('sample elapsed order not strictly increasing')

source = (root / 'Packages/TemperatureCore/Sources/TemperatureCore/Storage/Retention.swift').read_text()
queries = {}
for method, table in [('deleteRawSamples','raw_samples'),('deleteEMASamples','ema_samples')]:
    body = source.split('func ' + method + '(beforeOrAt elapsedNS: Int64) throws {',1)[1]
    query = body.split('sql: """',1)[1].split('"""',1)[0]
    queries[table] = query
rng = random.Random(50)
comparison = []
for table, current in queries.items():
    baseline = current.replace('start_elapsed_ns = ('+table+'.elapsed_ns / 1000000000) * 1000000000','start_elapsed_ns <= '+table+'.elapsed_ns')
    if baseline == current:
        failures.append('candidate SQL not integrated: ' + table)
        continue
    db = sqlite3.connect(':memory:')
    db.executescript('CREATE TABLE aggregates(series_id TEXT,segment INTEGER,width_s INTEGER,start_elapsed_ns INTEGER,end_elapsed_ns INTEGER,PRIMARY KEY(series_id,segment,width_s,start_elapsed_ns));CREATE TABLE '+table+'(sample_id TEXT,series_id TEXT,segment INTEGER,elapsed_ns INTEGER);')
    values = [0, 1, 999_999_999, 1_000_000_000, 1_000_000_001, 750_000_000, 3_000_000_000, 3_000_000_001]
    values += [rng.randrange(0, 10_000_000_000) for _ in range(400)]
    sampleset = [(str(i), 'a' if i%3 else 'b', 1 if i%4 else 2, v) for i,v in enumerate(values)]
    parents = []
    for series in ['a','b','c']:
        for segment in [1,2,3]:
            for second in range(11):
                if rng.randrange(3):
                    parents.append((series,segment,1,second*1_000_000_000,(second+1)*1_000_000_000))
                parents.append((series,segment,10,second*10_000_000_000,(second+1)*10_000_000_000))
    db.executemany('INSERT INTO aggregates VALUES (?,?,?,?,?)',parents)
    equality_checks = []
    for cutoff in [-1,0,1,999_999_999,1_000_000_000,3_000_000_000,10_000_000_000]:
        result = []
        for query in [baseline,current]:
            db.execute('DELETE FROM '+table)
            db.executemany('INSERT INTO '+table+' VALUES (?,?,?,?)',sampleset)
            db.execute(query,(cutoff,))
            result.append(db.execute('SELECT * FROM '+table+' ORDER BY sample_id').fetchall())
        equality_checks.append(result[0] == result[1])
    if not all(equality_checks):
        failures.append('aligned-parent SQL survivor equivalence failed: '+table)
    plan = [r[3] for r in db.execute('EXPLAIN QUERY PLAN '+current,(10_000_000_000,))]
    comparison.append({'table':table,'samples':len(sampleset),'parent_rows':len(parents),'cutoff_cases':len(equality_checks),'equivalent':all(equality_checks),'candidate_query_plan':plan})
    db.close()
result = {'archive_manifest_files':len(manifest['files']),'archive_failures':failures,'overlap_rows':len(overlap),'supplemental_rows':len(supplemental),'new_rows':len(supplemental)-len(overlap),'reproduced_1000ms_count':len(samples),'reproduced_span_seconds':span,'sql_aligned_parent_equivalence':comparison,'scope':'Read-only archive hashes and independent in-memory SQLite predicate equivalence. No formal App rerun, no hardware performance threshold measurement. No whole-REQ sleep waiver.'}
out = pathlib.Path('/tmp/temperature-final-independent-readonly-check.json')
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(bool(failures))
