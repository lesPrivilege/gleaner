#!/usr/bin/env python3
"""Runs evaluation E0's episodes (docs/design/evaluation-e0.md, "Policies" and "Scoring").

    eval/run.py <seeds> <out> [--tasks T01 ...] [--policies R G] [--no-build] [--results DIR]

<seeds> is a list such as 1,2,3 or a range such as 1-3 or 101-110. For each seed, the worlds are
written to <out>/seed-<n> (worlds.py) and prepared (prepare.py): the bundled app indexes each
one, and the time and library size are recorded as the preparation cost charged to G. A world
already prepared there is used as it is. Then each policy answers each world, as a subprocess
of this runner (policies.py):

- every command the policy asks for runs here, in the world's home folder, and every byte of its
  standard output and error is counted, with the command;
- T25's drift hook (drift.json) runs between two commands: after the first whose standard output
  holds the trigger, before the next;
- the world is put back after each episode: the drifted file, and Gleaner's hand-off copies.

Writes results.json (every episode, with the gold it is scored against and each world's
preparation cost) to eval/results/<date>/, then scores it (score.py), which writes report.md.
Python's standard library only; no model or network calls.
"""
import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time

import history
import prepare
import score
import worlds

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI = os.path.join(REPO, '.build', 'release', 'gleaner')
POLICIES = os.path.join(REPO, 'eval', 'policies.py')
# What a policy may run. A pipeline may also use these, and the shell's own builtins.
TOOLS = {'rg', 'jq', 'shasum', 'git', 'stat', 'sed', 'awk', 'cat', 'head', 'gleaner'}
COMMAND_TIMEOUT = 120
EPISODE_TIMEOUT = 600


def seed_list(text):
    seeds = []
    for part in text.split(','):
        low, _, high = part.partition('-')
        seeds += list(range(int(low), int(high) + 1)) if high else [int(low)]
    return seeds


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def build():
    subprocess.run([os.path.join(REPO, 'scripts', 'bundle-app.sh')], cwd=REPO, check=True)
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'gleaner'], cwd=REPO, check=True)


def versions():
    def first_line(*argv):
        try:
            return subprocess.run(argv, capture_output=True, text=True).stdout.splitlines()[0]
        except (OSError, IndexError):
            return None
    return dict(rg=first_line('rg', '--version'), jq=first_line('jq', '--version'), git=first_line('git', '--version'),
                python=platform.python_version(), macos=platform.mac_ver()[0],
                commit=first_line('git', '-C', REPO, 'rev-parse', 'HEAD'))


class Episode:
    """One policy answering one world, with every command it ran."""

    def __init__(self, folder, policy):
        self.folder = folder
        self.world = os.path.join(folder, 'world')
        self.policy = policy
        with open(os.path.join(folder, 'task.json'), encoding='utf-8') as f:
            self.task = json.load(f)
        self.hook = None
        drift = os.path.join(folder, 'drift.json')
        if os.path.exists(drift):
            with open(drift, encoding='utf-8') as f:
                self.hook = json.load(f)
        self.commands = []
        self.fired = None
        # The home folder's path, as itself and as Claude Code spells it in a log folder's name.
        self.spellings = [self.world.encode(), re.sub(r'[^A-Za-z0-9]', '-', self.world).encode()]
        self.env = dict(PATH=os.environ.get('PATH', '/usr/bin:/bin'), HOME=self.world, LANG='en_US.UTF-8',
                        LC_ALL='en_US.UTF-8', GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1', TZ='UTC')

    def check(self, request):
        """The command to run, or why not: only the tools above, gleaner only with this world's
        home, and the raw policy never near the catalog."""
        library = os.path.join(self.world, 'Library')
        if 'sh' in request:
            script = request['sh']
            if re.search(r'(^|[\s|;&(])gleaner(\s|$)', script):
                return None, 'gleaner runs on its own, not in a pipeline'
            if self.policy == 'R' and library in script:
                return None, 'the raw policy does not read the catalog'
            return ['/bin/sh', '-c', script], None
        argv = list(request['argv'])
        if not argv or argv[0] not in TOOLS:
            return None, f'{argv[:1]} is not a tool the policies use'
        if argv[0] == 'gleaner':
            if self.policy == 'R':
                return None, 'the raw policy does not use gleaner'
            if argv[-2:] != ['--home', self.world]:
                return None, 'gleaner runs only with --home <world>'
            argv[0] = CLI
        elif self.policy == 'R' and any(library in arg for arg in argv):
            return None, 'the raw policy does not read the catalog'
        return argv, None

    def execute(self, request):
        argv, why = self.check(request)
        started = time.monotonic()
        if argv is None:
            status, out, err = 126, b'', f'refused: {why}\n'.encode()
        else:
            try:
                done = subprocess.run(argv, cwd=self.world, env=self.env, capture_output=True, timeout=COMMAND_TIMEOUT)
                status, out, err = done.returncode, done.stdout, done.stderr
            except subprocess.TimeoutExpired as expired:
                status, out, err = 124, expired.stdout or b'', (expired.stderr or b'') + b'timed out\n'
        elapsed = time.monotonic() - started
        text = request.get('sh') or ' '.join(shlex.quote(a) for a in request['argv'])
        self.commands.append(dict(n=len(self.commands) + 1, phase=request.get('phase', 'raw'),
                                  tool=(request['argv'][0] if 'argv' in request else 'sh'),
                                  command=text if len(text) <= 400 else text[:400] + '…',
                                  status=status, stdout_bytes=len(out), stderr_bytes=len(err),
                                  tilde_bytes=len(self.tilde(out)) + len(self.tilde(err)), seconds=round(elapsed, 4)))
        self.drift(out)
        return dict(status=status, stdout=out.decode('utf-8', 'replace'), stderr=err.decode('utf-8', 'replace'))

    def tilde(self, data):
        """The output with the home folder's path written ~, so where a world was written weighs
        nothing in a byte count."""
        for spelling in self.spellings:
            data = data.replace(spelling, b'~')
        return data

    def drift(self, out):
        """The drift hook (T25): once, after the first command whose standard output holds the
        trigger, the file is rewritten, before the policy's next command."""
        if not self.hook or self.fired is not None:
            return
        if self.hook['trigger']['after_output_containing'].encode('utf-8') in out:
            write = self.hook['write']
            shutil.copyfile(os.path.join(self.folder, write['source']), os.path.join(self.world, write['path']))
            self.fired = len(self.commands)

    def run(self):
        scratch = os.path.join(self.folder, 'episodes', self.policy)
        if os.path.exists(scratch):
            shutil.rmtree(scratch)
        os.makedirs(scratch)
        kept = self.keep()
        started = time.monotonic()
        error = None
        answer = None
        with open(os.path.join(scratch, 'policy.err'), 'w', encoding='utf-8') as log:
            process = subprocess.Popen([sys.executable, '-I', POLICIES, self.policy], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=log, cwd=scratch, text=True, encoding='utf-8',
                                       env=dict(PATH=self.env['PATH'], LANG='en_US.UTF-8'))
            # A policy that stops answering is stopped, and its episode fails.
            watchdog = threading.Timer(EPISODE_TIMEOUT, process.kill)
            watchdog.start()
            try:
                process.stdin.write(json.dumps(dict(task=self.task, home=self.world, scratch=scratch)) + '\n')
                process.stdin.flush()
                for line in process.stdout:
                    message = json.loads(line)
                    if 'answer' in message:
                        answer = message['answer']
                        break
                    process.stdin.write(json.dumps(self.execute(message)) + '\n')
                    process.stdin.flush()
                else:
                    error = 'the policy stopped without an answer'
            finally:
                watchdog.cancel()
                if time.monotonic() - started >= EPISODE_TIMEOUT:
                    error = f'the episode ran past {EPISODE_TIMEOUT} s'
                process.stdin.close()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
        seconds = time.monotonic() - started
        checked = {path: (file_sha256(path) if os.path.isfile(path) else None) for path in bytes_files(answer)}
        self.restore(kept)
        with open(os.path.join(scratch, 'policy.err'), encoding='utf-8') as f:
            trace = f.read().strip()
        stdout = sum(c['stdout_bytes'] for c in self.commands)
        stderr = sum(c['stderr_bytes'] for c in self.commands)
        tilde = sum(c['tilde_bytes'] for c in self.commands)
        phases = {}
        for c in self.commands:
            entry = phases.setdefault(c['phase'], dict(commands=0, bytes=0, tilde_bytes=0))
            entry['commands'] += 1
            entry['bytes'] += c['stdout_bytes'] + c['stderr_bytes']
            entry['tilde_bytes'] += c['tilde_bytes']
        return dict(task=self.task['task'], family=self.task['family'], asks=self.task['asks'], policy=self.policy,
                    answer=answer if answer is not None else dict(status='failed', note=error),
                    error=error or (trace.splitlines()[-1] if 'Traceback' in trace else None),
                    bytes=dict(stdout=stdout, stderr=stderr, total=stdout + stderr, home_as_tilde=tilde), command_count=len(self.commands),
                    phases=phases, seconds=round(seconds, 3), drift_after_command=self.fired, checked=checked,
                    commands=self.commands)

    def keep(self):
        """What an episode may change in the world, to put back afterwards."""
        kept = {}
        if self.hook:
            path = os.path.join(self.world, self.hook['write']['path'])
            with open(path, 'rb') as f:
                kept[path] = (f.read(), os.stat(path))
        return kept

    def restore(self, kept):
        for path, (data, info) in kept.items():
            with open(path, 'wb') as f:
                f.write(data)
            os.utime(path, ns=(info.st_atime_ns, info.st_mtime_ns))
        staging = os.path.join(self.world, 'Library', 'Caches', 'Gleaner', 'handoff')
        if os.path.isdir(staging):
            for root, dirs, files in os.walk(staging):
                for name in dirs + files:
                    os.chmod(os.path.join(root, name), 0o755 if name in dirs else 0o644)
            shutil.rmtree(staging)


def bytes_files(value):
    """The files an answer offers as bytes."""
    if isinstance(value, dict):
        found = [value['bytes_file']] if isinstance(value.get('bytes_file'), str) else []
        return found + [f for key, item in value.items() if key != 'bytes_file' for f in bytes_files(item)]
    if isinstance(value, list):
        return [f for item in value for f in bytes_files(item)]
    return []


def prepared_worlds(seed, out, tasks, say):
    """The seed's worlds under `out`, written and prepared unless they already are."""
    folder = os.path.join(out, f'seed-{seed}')
    missing = [t for t in tasks if not os.path.exists(os.path.join(folder, t))]
    if missing:
        worlds.generate(seed, folder, missing)
    folders = []
    for task in tasks:
        world = os.path.join(folder, task)
        record = os.path.join(world, 'prepared.json')
        if not os.path.exists(record):
            prepare.prepare(world, prepare.APP, say=lambda _: None)
        with open(record, encoding='utf-8') as f:
            cost = json.load(f)
        if 'index_runs' not in cost:
            raise SystemExit(f'{world}: its preparation stopped partway; write it again')
        say(f'seed {seed} {task}: prepared ({cost["index_seconds"]} s to index, {cost["library_bytes"]} library bytes)')
        folders.append(world)
    return folders


def world_record(seed, folder):
    with open(os.path.join(folder, 'task.json'), encoding='utf-8') as f:
        task = json.load(f)
    with open(os.path.join(folder, 'gold.json'), encoding='utf-8') as f:
        gold = json.load(f)
    with open(os.path.join(folder, 'prepared.json'), encoding='utf-8') as f:
        cost = json.load(f)
    # What the scorer reads of the gold; check_worlds.py asserts the rest of it.
    kept = dict(answer=gold['answer'], hard_failures=gold['hard_failures'], sessions=gold['sessions'],
                library=dict(disk=gold['library'].get('disk', {})))
    return dict(seed=seed, task=task['task'], family=task['family'], asks=task['asks'], world=folder + '/world',
                question=task['question'], words=task['words'], gold=kept,
                preparation=dict(index_runs=len(cost['index_runs']), index_seconds=cost['index_seconds'],
                                 library_bytes=cost['library_bytes'], saved_copies=cost['saved_copies'],
                                 generation=cost['generation']))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('seeds', type=seed_list, help='seeds: 1,2,3 or 1-3')
    parser.add_argument('out', help='a folder for the worlds, with no symbolic link in its path, outside /tmp and /private')
    parser.add_argument('--tasks', nargs='+', default=list(worlds.TASKS))
    parser.add_argument('--policies', nargs='+', default=['R', 'G'], choices=['R', 'G'])
    parser.add_argument('--no-build', action='store_true', help='use the app and command already built')
    parser.add_argument('--results', default=os.path.join(REPO, 'eval', 'results', datetime.date.today().isoformat()))
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    if not args.no_build:
        build()
    out = history.place(args.out)
    os.makedirs(out, exist_ok=True)
    started = time.time()
    records, episodes = [], []
    for seed in args.seeds:
        for n, folder in enumerate(prepared_worlds(seed, out, args.tasks, print)):
            record = world_record(seed, folder)
            records.append(record)
            # Alternate which policy goes first, so neither always meets a warm file cache.
            order = args.policies if (seed + n) % 2 == 0 else list(reversed(args.policies))
            for position, policy in enumerate(order, 1):
                episode = Episode(folder, policy).run()
                episode.update(seed=seed, order=position)
                episodes.append(episode)
                answer = episode['answer']
                print(f"seed {seed} {record['task']} {policy}: {answer.get('status')}, {episode['command_count']} commands, "
                      f"{episode['bytes']['total']} bytes, {episode['seconds']} s" + (f" ({episode['error']})" if episode['error'] else ''))
    results = dict(evaluation='E0', created=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
                   seeds=args.seeds, tasks=args.tasks, policies=args.policies, seconds=round(time.time() - started),
                   environment=versions(), worlds=records, episodes=episodes)
    os.makedirs(args.results, exist_ok=True)
    path = os.path.join(args.results, 'results.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
        f.write('\n')
    score.write(path)
    print(f'wrote {path} and report.md')


if __name__ == '__main__':
    main()
