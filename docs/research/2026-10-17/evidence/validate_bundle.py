#!/usr/bin/env python3
"""Read-only integrity checks for this authored report bundle; no probe execution."""
import ast
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def check():
    missing = []
    parsed_python = []
    parsed_json = []
    link_count = 0
    for path in sorted(ROOT.rglob('*')):
        if not path.is_file():
            continue
        if path.suffix == '.py':
            ast.parse(path.read_text(), filename=str(path.relative_to(ROOT)))
            parsed_python.append(str(path.relative_to(ROOT)))
        if path.suffix == '.json':
            json.loads(path.read_text())
            parsed_json.append(str(path.relative_to(ROOT)))
        if path.suffix != '.md':
            continue
        content = path.read_text()
        targets = re.findall(r'\]\(([^)]+)\)', content)
        targets += re.findall(r'^\[[^\]]+\]:\s+(\S+)', content, re.M)
        for target in targets:
            target = target.strip('<>').split('#', 1)[0]
            if not target or re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target):
                continue
            link_count += 1
            if target.startswith('/') or not (path.parent / unquote(target)).is_file():
                missing.append({'source': str(path.relative_to(ROOT)), 'target': target})
    protocol = ROOT / 'reports/benchmark/deliverables/PROTOCOL.md'
    task_ids = sorted(set(re.findall(r'^## (T\d\d)\b', protocol.read_text(), re.M)))
    assert len(task_ids) == 26, task_ids
    assert hashlib.sha256(protocol.read_bytes()).hexdigest() == 'f2fe644270d99435301eb1eeb1f4367b8124af5a0b90bb06101cce11d68cd333'
    result = json.loads((ROOT / 'reports/benchmark/synthetic/run-001/results.json').read_text())
    code = ROOT / 'reports/benchmark/synthetic/probe.py'
    assert hashlib.sha256(code.read_bytes()).hexdigest() == result['script_sha256']
    assert result['checks_passed'] == result['checks_total'] == 10
    assert result['model_trials'] == result['retrieval_strategies_compared'] == 0
    provenance = json.loads((ROOT / 'reports/provenance/probes/results.json').read_text())
    assert provenance['passed'] == 20 and provenance['failed'] == 0
    manifest = ROOT / 'manifest.sha256'
    verified = 0
    if manifest.exists():
        for line in manifest.read_text().splitlines():
            expected, name = line.split('  ', 1)
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
            verified += 1
    assert not missing, missing
    return {'local_file_links_checked': link_count, 'missing_local_file_links': missing,
            'python_syntax_checked': parsed_python, 'json_parsed': parsed_json,
            'benchmark_task_ids': task_ids, 'manifest_entries_verified': verified,
            'probe_execution': 'none during assembly',
            'external_urls_recrawled': False}


if __name__ == '__main__':
    print(json.dumps(check(), indent=2))
