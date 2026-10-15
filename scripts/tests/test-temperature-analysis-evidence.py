#!/usr/bin/env python3
"""Analysis evidence schema tests; synthetic records never claim a real run."""
from __future__ import annotations
import copy
import hashlib
import importlib
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

class AnalysisEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.module = importlib.import_module('acceptance_evidence')
        self.assertTrue(callable(getattr(self.module, 'validate_temperature_analysis_report', None)),
                        'temperature analysis report validator is missing')
        self.temp = tempfile.TemporaryDirectory(prefix='temperature-analysis-evidence-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.raw = self.root / 'original.log'
        self.raw.write_text('Synthetic schema test; no App or hardware executed.\n')

    def payload(self, kind='software'):
        environment = {'execution': 'synthetic-unit-schema'}
        if kind == 'formal-app-hardware':
            environment = {'execution': 'formal-release-app', 'build_configuration': 'Release',
                'fixture': False, 'app_bundle_id': 'io.github.sisyphe550.TemperatureMonitor',
                'app_sha256': 'a'*64, 'worker_sha256': 'b'*64,
                'model': 'SyntheticSchema', 'os_build': 'SyntheticSchema',
                'context': 'synthetic schema only; no hardware executed'}
        cases = {
            'software': ['system-thermal-state', 'cpu-assessment', 'warning-independent',
                'trend-window-and-gap', 'receipt-replay-and-expiry', 'rule-change', 'advice-policy'],
            'formal-app-hardware': ['real-cpu-analysis', 'system-thermal-state', 'trend-display',
                'warning-disabled', 'close-reopen', 'quit'],
        }
        artifact = {'path': 'analysis.json', 'kind': kind, 'source_commit': 'c'*40,
            'result': 'passed', 'environment': environment}
        report = {'contract_version': 5, 'feature': 'temperature-analysis',
            **{key: copy.deepcopy(artifact[key]) for key in ('kind','source_commit','result','environment')},
            'analysis_cases': {name: {'result': 'passed', 'observed': 'Synthetic schema only',
                'evidence': [{'path': 'original.log', 'sha256': hashlib.sha256(self.raw.read_bytes()).hexdigest()}]}
                for name in cases[kind]}}
        return artifact, report

    def validate(self, artifact, report):
        (self.root / artifact['path']).write_text(json.dumps(report))
        return self.module.validate_temperature_analysis_report(self.root, artifact, check_source=False)

    def test_both_analysis_evidence_kinds_bind_original_files(self):
        for kind in ('software', 'formal-app-hardware'):
            artifact, report = self.payload(kind)
            self.assertEqual(report, self.validate(artifact, report))

    def test_warning_report_cannot_be_relabelled_as_analysis(self):
        artifact, report = self.payload()
        report.update(contract_version=4, feature='cpu-warning')
        report['warning_cases'] = report.pop('analysis_cases')
        with self.assertRaisesRegex(ValueError, 'Temperature analysis report'):
            self.validate(artifact, report)

    def test_case_missing_failed_or_without_original_log_is_rejected(self):
        artifact, original = self.payload()
        for mutation in ('missing', 'failed', 'not_observed', 'empty', 'no-log'):
            with self.subTest(mutation=mutation):
                report = copy.deepcopy(original)
                case = report['analysis_cases']['warning-independent']
                if mutation == 'missing': del report['analysis_cases']['warning-independent']
                elif mutation == 'empty': case['observed'] = ''
                elif mutation == 'no-log': case['evidence'] = []
                else: case['result'] = mutation
                with self.assertRaisesRegex(ValueError, 'Temperature analysis report'):
                    self.validate(artifact, report)

    def test_report_identity_must_match_artifact_metadata(self):
        artifact, original = self.payload()
        for field, wrong in (('contract_version',4), ('feature','cpu-warning'),
                             ('kind','formal-app-hardware'), ('source_commit','d'*40),
                             ('result','partial'), ('environment',{})):
            with self.subTest(field=field):
                report = copy.deepcopy(original); report[field] = wrong
                with self.assertRaisesRegex(ValueError, 'Temperature analysis report'):
                    self.validate(artifact, report)

    def test_original_hash_and_repository_boundary_are_enforced(self):
        artifact, original = self.payload()
        for field, wrong in (('sha256','0'*64), ('path','../outside.log')):
            report = copy.deepcopy(original)
            report['analysis_cases']['cpu-assessment']['evidence'][0][field] = wrong
            with self.assertRaisesRegex(ValueError, 'Temperature analysis report'):
                self.validate(artifact, report)

    def test_formal_analysis_rejects_fixture_or_debug_build(self):
        artifact, original = self.payload('formal-app-hardware')
        for field, wrong in (('fixture',True), ('build_configuration','Debug')):
            report = copy.deepcopy(original)
            report['environment'][field] = wrong
            artifact['environment'] = copy.deepcopy(report['environment'])
            with self.assertRaisesRegex(ValueError, 'Temperature analysis report'):
                self.validate(artifact, report)

    def source(self, version=5, declarations=None):
        defaults = self.root / 'docs/contracts/defaults-v1.json'
        defaults.parent.mkdir(parents=True)
        defaults.write_text(json.dumps({'contract_version': version}))
        code = self.root / 'Packages/TemperatureCore/Sources/TemperatureCore/Analysis/Types.swift'
        code.parent.mkdir(parents=True)
        code.write_text(declarations if declarations is not None else
                        'struct CPUAnalysisEvaluator {}\npublic enum TemperatureAdvicePolicy {}\n')
        def git(*args):
            return subprocess.run(['git','-C',str(self.root),*args], check=True,
                                  text=True,capture_output=True).stdout.strip()
        git('init','--quiet')
        git('config','user.name','Synthetic schema fixture')
        git('config','user.email','schema@example.invalid')
        git('add','.')
        git('commit','--quiet','-m','Synthetic analysis schema source; no production run')
        return git('rev-parse','HEAD')

    def test_revision5_source_accepts_enum_advice_policy(self):
        artifact, report = self.payload()
        artifact['source_commit'] = report['source_commit'] = self.source()
        self.validate(artifact, report)
        try:
            self.module.validate_temperature_analysis_report(self.root, artifact)
        except ValueError as error:
            self.fail('Valid revision5 source with enum policy was rejected: ' + str(error))

    def test_old_revision4_source_cannot_prove_analysis(self):
        artifact, report = self.payload()
        artifact['source_commit'] = report['source_commit'] = self.source(version=4)
        self.validate(artifact, report)
        with self.assertRaisesRegex(ValueError, 'source must contain revision5'):
            self.module.validate_temperature_analysis_report(self.root, artifact)

    def test_revision5_defaults_without_analysis_implementation_are_rejected(self):
        artifact, report = self.payload()
        artifact['source_commit'] = report['source_commit'] = self.source(declarations='struct CPUAnalysisEvaluator {}\n')
        self.validate(artifact, report)
        with self.assertRaisesRegex(ValueError, 'source lacks implemented enum TemperatureAdvicePolicy'):
            self.module.validate_temperature_analysis_report(self.root, artifact)

if __name__ == '__main__':
    unittest.main(verbosity=2)
