#!/usr/bin/env python3
"""Checks that the worlds hold what their gold presumes, once Gleaner has indexed them.

    eval/check_worlds.py [--seeds 1 2 3 101 102] [--tasks T01 ...] [--out DIR] [--no-build] [--keep]

Builds the app (scripts/bundle-app.sh) and the gleaner command, writes each seed's worlds twice
to show they are a function of the seed, prepares every world with the bundled app (prepare.py),
then asserts gold.json's `library` against the library: each delivery's capture (hash,
provenance, saved copy, number among its file's deliveries, reply line, anchor), what is not a
delivery, what `gleaner find` returns for the task's words, the files on disk, how the index read
each agent's logs, the raw log facts a negative answer rests on, and, through `gleaner show`,
`verify` and `handoff`, the availability, hand-off plan and restore command a task relies on.
T25's drift is applied and undone to check that a hand-off still gives the delivered bytes.

Writes a summary to eval/results/<date>/check_worlds.json and exits 1 if any check failed.
"""
import argparse
import contextlib
import datetime
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

import history
import prepare
import worlds

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI = os.path.join(REPO, '.build', 'release', 'gleaner')


def build():
    subprocess.run([os.path.join(REPO, 'scripts', 'bundle-app.sh')], cwd=REPO, check=True)
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'gleaner'], cwd=REPO, check=True)


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


class Library:
    """A prepared world's library, read only: its rows, and the gleaner command over it."""

    def __init__(self, world):
        self.world = world
        path = os.path.join(prepare.library_folder(world), 'registry.sqlite')
        with contextlib.closing(sqlite3.connect(f'file:{path}?mode=ro', uri=True)) as db:
            db.row_factory = sqlite3.Row
            self.meta = dict(db.execute('SELECT key, value FROM meta').fetchall())
            self.sessions = [dict(row) for row in db.execute('SELECT * FROM sessions')]
            self.rows = [dict(row) for row in db.execute(
                'SELECT d.id, d.session_id, d.path, d.delivered_at, d.evidence, d.log_path, d.reply_line, '
                'c.sha256, c.observed_at, c.saved_at, c.provenance, c.kind '
                'FROM deliveries d LEFT JOIN captures c ON c.delivery_id = d.id')]
        for row in self.rows:
            row['evidence'] = json.loads(row['evidence'])
        self.sources = json.loads(self.meta.get('sources') or '{}')

    def abs(self, rel):
        return self.world + '/' + rel

    def rel(self, path):
        return path[len(self.world) + 1:] if path.startswith(self.world + '/') else path

    def deliveries(self, rel):
        """The deliveries of a file, oldest first."""
        return sorted((row for row in self.rows if row['path'] == self.abs(rel)), key=lambda row: row['delivered_at'])

    def saved(self, sha):
        return sha is not None and os.path.isfile(os.path.join(prepare.library_folder(self.world), 'objects', sha[:2], sha))

    def gleaner(self, *args):
        result = subprocess.run([CLI, *args, '--home', self.world], capture_output=True, text=True)
        try:
            answer = json.loads(result.stdout)
        except json.JSONDecodeError:
            answer = None
        return result.returncode, answer


def check_delivery(library, expected, fail):
    name = f"{expected['path']} ({expected['session'][:8]})"
    rows = [row for row in library.deliveries(expected['path']) if row['session_id'] == expected['session']]
    if 'line' in expected:
        rows = [row for row in rows if row['evidence'][0]['line'] == expected['line']]
    if len(rows) != 1:
        return fail(f'{name}: {len(rows)} deliveries in the library, expected 1')
    row = rows[0]
    every = library.deliveries(expected['path'])
    found = dict(id=row['id'], sha256=row['sha256'], provenance=row['provenance'], saved=library.saved(row['sha256'])
                 and row['saved_at'] is not None, number=every.index(row) + 1, of=len(every),
                 reply_line=row['reply_line'], anchor=row['evidence'][0].get('anchor'),
                 observed_after_delivery=row['observed_at'] > row['delivered_at'] + 600)
    for key, value in found.items():
        if key in expected and expected[key] != value:
            fail(f'{name}: {key} is {value!r}, expected {expected[key]!r}')
    if row['log_path'] != library.abs(expected['log']):
        fail(f"{name}: log {row['log_path']}, expected {library.abs(expected['log'])}")
    if {'availability', 'plan', 'restore_sha256'} & set(expected):
        status, shown = library.gleaner('show', row['id'])
        if status != 0 or shown is None:
            return fail(f'{name}: gleaner show exited {status}')
        availability = shown['reference']['availability']['state']
        if 'availability' in expected and availability != expected['availability']:
            fail(f"{name}: availability {availability}, expected {expected['availability']}")
        plan = shown['handoff']['action']
        if 'plan' in expected and plan != expected['plan']:
            fail(f"{name}: hand-off plan {plan}, expected {expected['plan']}")
        if 'restore_sha256' in expected:
            check_restore(library, shown['handoff'].get('restore_command'), expected, name, fail)
    if 'verify' in expected:
        status, verified = library.gleaner('verify', row['id'])
        got = verified and dict(original=verified['original'], saved_copy=verified['saved_copy'])
        if got != expected['verify']:
            fail(f"{name}: verify gave {got}, expected {expected['verify']}")


def check_restore(library, command, expected, name, fail):
    """The command adds the removed worktree back at a commit whose file has the delivered bytes."""
    if not command or ' worktree add ' not in command:
        return fail(f'{name}: restore command {command!r} does not add the worktree back')
    # git -C '<repository>' worktree add -f --detach '<folder>' '<commit>'
    _, repository, _, checkout, _, commit, _ = command.split("'")
    inside = os.path.relpath(library.abs(expected['path']), checkout)
    blob = subprocess.run(['git', '-C', repository, 'show', f'{commit}:{inside}'], capture_output=True)
    if blob.returncode != 0 or hashlib.sha256(blob.stdout).hexdigest() != expected['restore_sha256']:
        fail(f'{name}: commit {commit} does not hold the delivered bytes at {inside}')


def check_drift(library, drift, folder, fail):
    """T25: with the file rewritten, a hand-off still gives the delivered bytes; then the file is put back."""
    path = library.abs(drift['path'])
    rows = library.deliveries(drift['path'])
    with open(os.path.join(folder, 'drift.json'), encoding='utf-8') as f:
        hook = json.load(f)
    before = os.stat(path)
    with open(path, 'rb') as f:
        original = f.read()
    shutil.copyfile(os.path.join(folder, hook['write']['source']), path)
    try:
        status, handed = library.gleaner('handoff', rows[-1]['id'])
        if status != 0 or file_sha256(handed['copy']) != drift['handoff_sha256']:
            fail(f'drift: handoff exited {status} or gave other bytes than the delivery')
        status, verified = library.gleaner('verify', rows[-1]['id'])
        got = verified and dict(original=verified['original'], saved_copy=verified['saved_copy'])
        if got != drift['verify']:
            fail(f"drift: verify gave {got}, expected {drift['verify']}")
    finally:
        with open(path, 'wb') as f:
            f.write(original)
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))


def check(folder):
    """Every way the prepared world in `folder` differs from its gold, as messages."""
    failures = []
    fail = failures.append
    with open(os.path.join(folder, 'gold.json'), encoding='utf-8') as f:
        gold = json.load(f)
    with open(os.path.join(folder, 'prepared.json'), encoding='utf-8') as f:
        prepared = json.load(f)
    expected = gold['library']
    library = Library(os.path.join(folder, 'world'))

    if len(prepared['index_runs']) != expected['index_runs'] or int(library.meta.get('generation', 0)) < expected['index_runs']:
        fail(f"index runs {len(prepared['index_runs'])}, generation {library.meta.get('generation')}; "
             f"expected {expected['index_runs']}")
    for provider, source in expected['sources'].items():
        got = library.sources.get(provider, {})
        for key, value in source.items():
            if got.get(key) != value:
                fail(f'source {provider}: {key} is {got.get(key)!r}, expected {value!r}')
    logs = {row['log_path'] for row in library.sessions}
    for session in gold['sessions']:
        if not session.get('subagent') and library.abs(session['log']) not in logs:
            fail(f"session {session['id']} ({session['log']}) was not read")
    for delivery in expected.get('deliveries', []):
        check_delivery(library, delivery, fail)
    for rel in expected.get('not_delivered', []):
        if library.deliveries(rel):
            fail(f'{rel} is a delivery in the library')
    for rel, sha in expected.get('disk', {}).items():
        path = library.abs(rel)
        got = file_sha256(path) if os.path.isfile(path) else None
        if got != sha:
            fail(f'{rel} on disk: {got}, expected {sha}')
    for search in expected.get('find', []):
        args = ['find', *search['words'], '--limit', '200'] + (['--project', search['project']] if 'project' in search else [])
        status, found = library.gleaner(*args)
        paths = sorted(library.rel(hit['reference']['path']) for hit in (found or {}).get('results', []))
        if status != 0 or paths != sorted(search['paths']):
            fail(f"find {' '.join(args[1:])}: {paths}, expected {sorted(search['paths'])}")
    for fact in expected.get('raw', []):
        with open(library.abs(fact['log']), encoding='utf-8') as f:
            text = f.read()
        if 'absent' in fact and fact['absent'] in text:
            fail(f"{fact['log']} contains {fact['absent']}")
        if 'present' in fact and fact['present'] not in text:
            fail(f"{fact['log']} lacks {fact['present']}")
        if 'lines' in fact and (text.count('\n') + (not text.endswith('\n')), text.endswith('\n')) != (
                fact['lines'], fact['last_line_complete']):
            fail(f"{fact['log']}: not {fact['lines']} lines ending as expected")
    if 'drift' in expected:
        check_drift(library, expected['drift'], folder, fail)
    return failures


def contents(root):
    """Every file under `root` outside git's own folders, with its modification time inside a world."""
    found = {}
    for folder, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d != '.git']
        for name in files:
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, root)
            with open(path, 'rb') as f:
                found[rel] = (f.read(), os.stat(path).st_mtime_ns if '/world/' in rel else None)
    return found


def deterministic(seed, out, tasks):
    """Writes the seed's worlds, then writes them again in the same place and compares the two;
    returns the folders and the files that differ. The worlds stay where they were written,
    because their logs record absolute paths."""
    folder = os.path.join(out, f'seed-{seed}')
    worlds.generate(seed, folder, tasks)
    first = contents(history.place(folder))
    shutil.rmtree(folder)
    folders = worlds.generate(seed, folder, tasks)
    again = contents(history.place(folder))
    return folders, sorted(path for path in set(first) | set(again) if first.get(path) != again.get(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--seeds', nargs='+', type=int, default=[1, 2, 3, 101, 102])
    parser.add_argument('--tasks', nargs='+', default=list(worlds.TASKS))
    parser.add_argument('--out', help='a folder for the worlds, with no symbolic link in its path (default: a new '
                                      'one under build/, removed afterwards)')
    parser.add_argument('--no-build', action='store_true', help='use the app and command already built')
    parser.add_argument('--keep', action='store_true', help='keep the worlds')
    parser.add_argument('--results', default=os.path.join(REPO, 'eval', 'results', datetime.date.today().isoformat()))
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    if not args.no_build:
        build()
    if not args.out:
        os.makedirs(os.path.join(REPO, 'build'), exist_ok=True)
    out = history.place(args.out or tempfile.mkdtemp(prefix='worlds-', dir=os.path.join(REPO, 'build')))
    os.makedirs(out, exist_ok=True)
    report, failed = [], 0
    started = time.time()
    try:
        for seed in args.seeds:
            folders, differ = deterministic(seed, out, args.tasks)
            if differ:
                failed += 1
                print(f'seed {seed}: two writes differ in {differ[:5]}')
            for folder in folders:
                cost = prepare.prepare(folder, prepare.APP, say=lambda _: None)
                failures = check(folder)
                failed += bool(failures)
                task = os.path.basename(folder)
                print(f"seed {seed} {task}: {'ok' if not failures else 'FAILED'} "
                      f"({cost['index_seconds']} s to index, {cost['library_bytes']} library bytes)")
                for failure in failures:
                    print(f'    {failure}')
                report.append(dict(seed=seed, task=task, ok=not failures, failures=failures,
                                   index_runs=len(cost['index_runs']), index_seconds=cost['index_seconds'],
                                   library_bytes=cost['library_bytes'], saved_copies=cost['saved_copies']))
    finally:
        if not args.keep and not args.out:
            shutil.rmtree(out, ignore_errors=True)
    os.makedirs(args.results, exist_ok=True)
    with open(os.path.join(args.results, 'check_worlds.json'), 'w', encoding='utf-8') as f:
        json.dump(dict(seeds=args.seeds, tasks=args.tasks, seconds=round(time.time() - started), failed=failed,
                       worlds=report), f, indent=2)
        f.write('\n')
    print(f"{len(report) - sum(not r['ok'] for r in report)} of {len(report)} worlds hold what their gold presumes")
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
