#!/usr/bin/env python3
"""Read-only worktree probe: re-label historical evidence in memory only."""
import copy
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
root = Path(sys.argv[1] if len(sys.argv) > 1 else
            '/Users/sisyphus/.codex/worktrees/cpu-warning/Temperature monitoring').resolve()
sys.path.insert(0, str(root / 'scripts'))
from acceptance_evidence import _validate_catalog, bound_acceptance, validate_bound
from course_acceptance import validate_course_policy

current_acceptance = json.loads((root / 'docs/contracts/acceptance-v1.json').read_text())
current_catalog = json.loads((root / 'docs/contracts/acceptance-evidence-catalog-v1.json').read_text())
print('baseline complete errors:', validate_course_policy(root, current_acceptance,
                                                        current_catalog, require_complete=True))
acceptance = copy.deepcopy(current_acceptance)
catalog = copy.deepcopy(current_catalog)
artifact_ids = ['course-final-core', 'course-final-formal-app']
for artifact_id in artifact_ids:
    if 'TC-WARNING' not in catalog['artifacts'][artifact_id]['tc_groups']:
        catalog['artifacts'][artifact_id]['tc_groups'].append('TC-WARNING')
catalog['requirement_results']['REQ-125'].update(
    verification='product-accepted-local',
    covered_cases=['revision4 warning tested'],
    outstanding=[],
    reason='CPU warning accepted using existing reports',
    evidence=artifact_ids,
)
bound = bound_acceptance(root, catalog, acceptance)
_validate_catalog(root, catalog, bound)
binding_errors = validate_bound(root, catalog, bound)
complete_errors = validate_course_policy(root, bound, catalog, require_complete=True)
print('relabeled validate_catalog: passed')
print('relabeled binding errors:', binding_errors)
print('relabeled complete course errors:', complete_errors)
for artifact_id in artifact_ids:
    artifact = catalog['artifacts'][artifact_id]
    original = current_catalog['artifacts'][artifact_id]
    report_path = root / artifact['path']
    report_bytes = report_path.read_bytes()
    assert {key: value for key, value in artifact.items() if key != 'tc_groups'} == {
        key: value for key, value in original.items() if key != 'tc_groups'}
    assert hashlib.sha256(report_bytes).hexdigest() == artifact['sha256']
    print(json.dumps({
        'artifact_id': artifact_id,
        'path': artifact['path'],
        'source_commit': artifact['source_commit'],
        'sha256_unchanged_and_matches': True,
        'environment_unchanged': artifact['environment'] == original['environment'],
        'report_contains_TC_WARNING': b'TC-WARNING' in report_bytes,
    }, ensure_ascii=False))
if not binding_errors and not complete_errors:
    print('REPRODUCED: historical reports passed without any new warning evidence.')
else:
    print('NOT REPRODUCED: validator rejected the relabeled historical reports.')
