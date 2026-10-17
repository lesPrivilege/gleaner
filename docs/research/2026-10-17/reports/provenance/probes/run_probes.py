#!/usr/bin/env python3
"""Synthetic identifiability witnesses; no provider logs or product code.

The finite model hides unobserved transitions, then compares visible evidence
and delivery-time ground truth. Equal evidence with different truth proves
non-identifiability within that scenario; it estimates no real-world frequency.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
RESULTS = []


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run_world(initial, events):
    files = {k: dict(v) for k, v in initial.items()}
    evidence = []
    delivery = None
    for event in events:
        op = event[0]
        if op == 'record':
            evidence.append(event[1])
        elif op == 'write':
            _, path, data, identity = event
            files[path] = {'bytes': data, 'identity': identity}
        elif op == 'edit':
            _, path, old, new = event
            assert files[path]['bytes'].count(old) == 1
            files[path]['bytes'] = files[path]['bytes'].replace(old, new)
        elif op == 'move':
            _, src, dst = event
            files[dst] = files.pop(src)
        elif op == 'copy':
            _, src, dst, identity = event
            files[dst] = dict(files[src], identity=identity)
        elif op == 'delete':
            files.pop(event[1], None)
        elif op == 'observe':
            evidence.append({'read': event[1], 'bytes': files[event[1]]['bytes']})
        elif op == 'prefix':
            evidence.append({'read': event[1], 'prefix': files[event[1]]['bytes'][:event[2]], 'complete': False})
        elif op == 'deliver':
            path = event[1]
            evidence.append({'delivery_path': path})
            delivery = files.get(path)
            delivery = dict(delivery) if delivery else None
        else:
            raise ValueError(op)
    assert delivery is not None
    return {'evidence': evidence, 'delivery_truth': delivery, 'events': events}


def state(data='old', identity='object-A'):
    return {'p': {'bytes': data, 'identity': identity}}


def witness(name, left, right, dimension='bytes'):
    a = run_world(*left)
    b = run_world(*right)
    assert a['evidence'] == b['evidence'], name
    assert a['delivery_truth'][dimension] != b['delivery_truth'][dimension], name
    RESULTS.append({'name': name, 'kind': 'indistinguishable-histories',
                    'passed': True, 'dimension': dimension, 'worlds': [a, b]})


call = ('record', {'call_id': 'w1', 'tool': 'Write', 'input': 'new'})
ok = ('record', {'call_id': 'w1', 'result': 'success'})
failed = ('record', {'call_id': 'w1', 'result': 'error'})
deliver = ('deliver', 'p')
witness('write-intent-without-result',
        (state(), [call, ('write', 'p', 'new', 'object-A'), deliver]),
        (state(), [call, deliver]))
witness('failed-write-can-be-partial',
        (state(), [call, ('write', 'p', 'n', 'object-A'), failed, deliver]),
        (state(), [call, failed, deliver]))
witness('success-report-requires-trust',
        (state(), [call, ('write', 'p', 'new', 'object-A'), ok, deliver]),
        (state(), [call, ok, deliver]))
witness('outside-writer-after-success',
        (state(), [call, ('write', 'p', 'new', 'object-A'), ok, deliver]),
        (state(), [call, ('write', 'p', 'new', 'object-A'), ok,
                   ('write', 'p', 'external', 'object-A'), deliver]))
edit_call = ('record', {'call_id': 'e1', 'old': 'red', 'new': 'blue'})
edit_ok = ('record', {'call_id': 'e1', 'result': 'success'})
witness('patch-without-base',
        (state('red cat'), [edit_call, ('edit', 'p', 'red', 'blue'), edit_ok, deliver]),
        (state('red dog'), [edit_call, ('edit', 'p', 'red', 'blue'), edit_ok, deliver]))
witness('truncated-output',
        (state('prefix:one'), [('prefix', 'p', 7), deliver]),
        (state('prefix:two'), [('prefix', 'p', 7), deliver]))
witness('same-bytes-different-object',
        (state('equal', 'object-A'), [('observe', 'p'), deliver]),
        (state('equal', 'object-B'), [('observe', 'p'), deliver]), 'identity')
witness('rename-versus-copy-delete',
        (state('equal'), [('move', 'p', 'q'), ('observe', 'q'), ('deliver', 'q')]),
        (state('equal'), [('copy', 'p', 'q', 'object-B'), ('delete', 'p'),
                           ('observe', 'q'), ('deliver', 'q')]), 'identity')
witness('pre-edit-checkpoint-not-post-state',
        (state(), [('observe', 'p'), call, ('write', 'p', 'new', 'object-A'), deliver]),
        (state(), [('observe', 'p'), call, deliver]))
witness('observation-not-delivery-binding',
        (state('captured'), [('observe', 'p'), deliver]),
        (state('captured'), [('observe', 'p'), ('write', 'p', 'later', 'object-A'), deliver]))
timestamps = ('record', {'A_time': 5, 'B_time': 5, 'record_order': ['A', 'B']})
witness('equal-timestamps-no-execution-order',
        (state(), [timestamps, ('write', 'p', 'A', 'object-A'), ('write', 'p', 'B', 'object-A'), deliver]),
        (state(), [timestamps, ('write', 'p', 'B', 'object-A'), ('write', 'p', 'A', 'object-A'), deliver]))
async_report = ('record', {'call_id': 'async-1', 'status': 'running'})
witness('background-process-completion-gap',
        (state(), [async_report, ('write', 'p', 'new', 'object-A'), deliver]),
        (state(), [async_report, deliver, ('write', 'p', 'new', 'object-A')]))

# Positive bounded cases: a known base and explicit deterministic transitions.
base = b'red cat\n'
output = base.replace(b'red', b'blue', 1)
assert output == b'blue cat\n'
RESULTS.append({'name': 'known-base-exact-edit', 'kind': 'conditional-positive',
                'passed': True, 'input_sha256': sha(base), 'output_sha256': sha(output),
                'assumptions': ['complete base', 'exact edit semantics', 'no other writers', 'successful operation']})
blob = bytes(range(256)) + b'\x00\xff\x80'
encoded = base64.b64encode(blob)
decoded = base64.b64decode(encoded, validate=True)
assert decoded == blob
RESULTS.append({'name': 'binary-logged-payload', 'kind': 'positive-byte-recovery',
                'passed': True, 'bytes': len(blob), 'sha256': sha(decoded),
                'delivery_binding': 'not established by decoding'})
possible_bases = [s for s in ('a', 'b') if s.replace('a', 'b') == 'b']
assert possible_bases == ['a', 'b']
RESULTS.append({'name': 'lossy-inverse', 'kind': 'ambiguous-inverse',
                'passed': True, 'possible_bases': possible_bases})

with tempfile.TemporaryDirectory(prefix='synthetic-', dir=ROOT) as tmp:
    d = Path(tmp)
    p = d / 'file'
    p.write_bytes(b'AAAA')
    original = p.stat()
    p.write_bytes(b'BBBB')
    os.utime(p, ns=(original.st_atime_ns, original.st_mtime_ns))
    assert p.stat().st_size == original.st_size
    assert p.stat().st_mtime_ns == original.st_mtime_ns
    assert p.read_bytes() == b'BBBB'
    RESULTS.append({'name': 'mtime-and-size-can-match-after-change', 'kind': 'filesystem-witness',
                    'passed': True, 'mtime_equal': True, 'size_equal': True, 'bytes_different': True})
    log = d / 'log.jsonl'
    original_log = b'{"id":"m1"}\n{"id":"m2"}\n'
    log.write_bytes(original_log)
    second_record = original_log.splitlines()[1]
    log.write_bytes(b'{"id":"inserted"}\n' + original_log)
    assert log.read_bytes().splitlines()[1] != second_record
    assert log.read_bytes().splitlines()[2] == second_record
    RESULTS.append({'name': 'line-anchor-after-log-rewrite', 'kind': 'filesystem-witness',
                    'passed': True, 'old_line': 2, 'new_line': 3, 'record_sha256': sha(second_record)})
    repo = d / 'repo'
    repo.mkdir()
    env = dict(os.environ, GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null', GIT_TERMINAL_PROMPT='0')
    def git(*args, data=None):
        return subprocess.run(['git', '--no-optional-locks', '-c', 'core.hooksPath=/dev/null',
                               '-c', 'credential.helper=', *args], cwd=repo, env=env,
                              input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    git('init', '--quiet')
    oid = git('hash-object', '-w', '--stdin', data=blob).decode().strip()
    recovered = git('cat-file', 'blob', oid)
    assert recovered == blob
    RESULTS.append({'name': 'binary-git-blob-recovery', 'kind': 'positive-byte-recovery',
                    'passed': True, 'git_oid': oid, 'sha256': sha(recovered),
                    'delivery_binding': 'none; no commits or delivery events created'})

# Governance/projection witnesses: authorization and approval are separate facts.
approved_digest = sha(b'version-one')
new_digest = sha(b'version-two')
assert approved_digest != new_digest
RESULTS.append({'name': 'approval-target-does-not-follow-path', 'kind': 'governance-witness',
                'passed': True, 'approved_digest': approved_digest, 'replacement_digest': new_digest,
                'approval_applies_to_replacement': False})
retained_record = {'evidence_id': 'ev1', 'source_status': 'permission-denied', 'previously_observed': True}
assert retained_record['source_status'] != 'deleted'
RESULTS.append({'name': 'denied-is-not-deleted', 'kind': 'governance-witness', 'passed': True,
                'record': retained_record})

result = {'scope': 'synthetic finite histories and isolated filesystem/Git objects; no product tests',
          'passed': len(RESULTS), 'failed': 0, 'probes': RESULTS}
(ROOT / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'passed': len(RESULTS), 'failed': 0, 'results': str(ROOT / 'results.json')}))
