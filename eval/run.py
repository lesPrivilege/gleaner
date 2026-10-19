#!/usr/bin/env python3
"""Runs evaluation E0's episodes (docs/design/evaluation-e0.md, "Policies" and "Scoring").

    eval/run.py <seeds> <out> [--tasks T01 ...] [--policies R G] [--no-build] [--results DIR]

<seeds> is a list such as 1,2,3 or a range such as 1-3 or 101-110. Seeds from 101 are scored:
they run only on the recipe locked in eval/lock.json, from a clean, committed tree. For each
seed, the worlds are written to <out>/seed-<n> and their gold to <out>/gold/seed-<n> (worlds.py),
and prepared (prepare.py): the bundled app indexes each one, and the time and library size are
recorded as the preparation cost charged to G. A world already prepared there is used as it is;
one whose writing or preparation fails is set aside and written once more, and every failed
attempt is recorded. Then each policy answers each world, as a subprocess of this runner
(policies.py):

- every command the policy asks for runs here, in the world's home folder, and every byte of its
  standard output and error is counted, with the command and the tool processes it starts;
- the policy, and every command, run under sandbox-exec: they cannot read or write anything of
  the run's but this world and the policy's scratch folder (the raw policy not even the world's
  catalog), nor the person's own agent logs or library;
- T25's drift hook (drift.json) runs between two commands: after the first whose standard output
  holds the trigger, before the next;
- the world is put back after each episode: the drifted file, and Gleaner's hand-off copies.

After both episodes, the world is checked against its gold (check_worlds.check). Each episode is
appended to episodes.jsonl as it finishes, so a run that stops keeps what it ran; at the end
results.json holds every episode, the gold it is scored against and each world's preparation,
episodes.jsonl is removed, and score.py writes report.md beside it. A results folder is written
once. Python's standard library only; no model or network calls.
"""
import argparse
import datetime
import glob
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

import check_worlds
import history
import prepare
import score
import worlds

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLI = os.path.join(REPO, '.build', 'release', 'gleaner')
# `gleaner` for a pipeline: a folder holding only a link to the command, first on the PATH.
BIN = os.path.join(REPO, '.build', 'e0-bin')
POLICIES = os.path.join(REPO, 'eval', 'policies.py')
LOCK = os.path.join(REPO, 'eval', 'lock.json')
SCORED = 101
# What a policy may run, alone or in a pipeline, and the shell's own words a pipeline may use.
TOOLS = {'rg', 'jq', 'shasum', 'git', 'stat', 'sed', 'awk', 'cat', 'head', 'xargs', 'tr', 'dirname', 'gleaner'}
BUILTINS = {'[', 'test', 'set', 'true', 'false'}
KEYWORDS = {'if', 'then', 'else', 'elif', 'fi', 'while', 'until', 'do', 'done', '!', '{', '}'}
PUNCTUATION = ';&|()<>\n'
# xargs options that take a value (BSD xargs), so the utility it runs is found after them.
XARGS_VALUES = {'-E', '-I', '-J', '-L', '-n', '-P', '-R', '-S', '-s'}
# The person's own agent logs and library, which nothing here may read.
PRIVATE = [os.path.expanduser(p) for p in ('~/.claude', '~/.codex', '~/Library/Application Support/Gleaner')]
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


def first_line(*argv):
    try:
        return subprocess.run(argv, capture_output=True, text=True).stdout.splitlines()[0]
    except (OSError, IndexError):
        return None


def versions():
    return dict(rg=first_line('rg', '--version'), jq=first_line('jq', '--version'), git=first_line('git', '--version'),
                python=platform.python_version(), macos=platform.mac_ver()[0], machine=platform.machine(),
                commit=first_line('git', '-C', REPO, 'rev-parse', 'HEAD'))


def recipe():
    """The harness as it is now: each eval/*.py's sha256, and the tree's uncommitted changes."""
    files = {os.path.relpath(path, REPO): file_sha256(path) for path in sorted(glob.glob(os.path.join(REPO, 'eval', '*.py')))}
    status = subprocess.run(['git', '-C', REPO, 'status', '--porcelain'], capture_output=True, text=True).stdout
    return dict(files=files, clean=not status.strip(), changes=status.splitlines())


def require_lock(now):
    """The lock a scored run is held to: the recipe was locked on the development seeds and
    committed before, and nothing has changed since."""
    if not os.path.exists(LOCK):
        raise SystemExit('scored seeds need eval/lock.json: lock the recipe on the development seeds first')
    with open(LOCK, encoding='utf-8') as f:
        lock = json.load(f)
    if not now['clean']:
        raise SystemExit('the working tree has uncommitted changes; a scored run needs the locked recipe committed:\n'
                         + '\n'.join(now['changes']))
    differ = sorted(path for path in set(lock['files']) | set(now['files']) if lock['files'].get(path) != now['files'].get(path))
    if differ:
        raise SystemExit(f'{", ".join(differ)} differ from the lock in eval/lock.json')
    return lock


def sbpl(paths):
    return ' '.join(f'(subpath "{path}")' for path in paths)


def tokens(script):
    """A shell script's words and operators, as sh splits them, quotes removed."""
    lexer = shlex.shlex(script, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace = ' \t\r'
    lexer.whitespace_split = True
    lexer.commenters = ''
    return list(lexer)


def simple_commands(words):
    """The simple commands in a script's tokens, each its words, the utility xargs runs counted as
    one of its own; and every redirect target and assignment value, which name files too."""
    commands, others, current, expect, redirect = [], [], None, True, False
    for word in words:
        if word and set(word) <= set(PUNCTUATION):
            redirect = set(word) <= set('<>&') and word not in ('&', '&&')
            if not redirect:
                expect, current = True, None
            continue
        if redirect:
            redirect = False
            others.append(word)
            continue
        if expect:
            if word in KEYWORDS:
                continue
            if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', word):
                others.append(word.split('=', 1)[1])
                continue
            current = [word]
            commands.append(current)
            expect = False
        elif current[0] == 'xargs' and len(current) > 1 and current[-1] in XARGS_VALUES:
            current.append(word)
        elif current[0] == 'xargs' and not word.startswith('-'):
            current = [word]
            commands.append(current)
        else:
            current.append(word)
    return commands, others


class Episode:
    """One policy answering one world, with every command it ran."""

    def __init__(self, folder, policy, out):
        self.folder = folder
        self.world = os.path.join(folder, 'world')
        self.gold = history.gold_folder(folder)
        self.policy = policy
        self.scratch = os.path.join(folder, 'episodes', policy)
        with open(os.path.join(folder, 'task.json'), encoding='utf-8') as f:
            self.task = json.load(f)
        self.hook = None
        drift = os.path.join(self.gold, 'drift.json')
        if os.path.exists(drift):
            with open(drift, encoding='utf-8') as f:
                self.hook = json.load(f)
        self.commands = []
        self.fired = None
        # The home folder's path, as itself and as Claude Code spells it in a log folder's name.
        self.spellings = [self.world.encode(), re.sub(r'[^A-Za-z0-9]', '-', self.world).encode()]
        self.env = dict(PATH=BIN + os.pathsep + os.environ.get('PATH', '/usr/bin:/bin'), HOME=self.world,
                        LANG='en_US.UTF-8', LC_ALL='en_US.UTF-8', GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                        GIT_CEILING_DIRECTORIES=folder, TZ='UTC')
        library = os.path.join(self.world, 'Library')
        # Nothing of the run's but this world and the scratch folder; the raw policy not even the
        # world's catalog; and only the scratch folder, or for G the catalog's own folder, to write.
        rules = ['(version 1)', '(allow default)',
                 f'(deny file-read-data file-write* {sbpl([out] + PRIVATE)})',
                 f'(allow file-read-data {sbpl([self.world, self.scratch])})',
                 f'(allow file-write* {sbpl([self.scratch] + ([library] if policy == "G" else []))})']
        if policy == 'R':
            rules.append(f'(deny file-read-data file-write* {sbpl([library])})')
        self.profile = ''.join(rules)
        # The policy itself reads nothing of the run's: the runner is its only way to the world.
        self.policy_profile = f'(version 1)(allow default)(deny file-read-data file-write* {sbpl([out] + PRIVATE)})'

    def outside(self, word):
        """Whether a word names a path outside the world and the scratch folder. A word with a
        space in it is a program or a pattern, not a path."""
        value = word.split('=', 1)[1] if re.match(r'^-*[A-Za-z_][\w-]*=', word) else word
        if not value or any(ch.isspace() for ch in value):
            return False
        if not (value.startswith(('/', '~')) or '..' in value.split('/')):
            return False
        if value == '~' or value.startswith('~/'):
            value = self.world + value[1:]
        path = os.path.normpath(os.path.join(self.world, value))
        return not any(path == root or path.startswith(root + '/') for root in (self.world, self.scratch, '/dev/null'))

    def check(self, request):
        """The command to run and the tool processes it starts, or why not: only the tools above,
        gleaner only for G and with this world's home, no path outside the world and scratch."""
        if not isinstance(request, dict):
            return None, 0, 'a request is a JSON object'
        if isinstance(request.get('sh'), str):
            try:
                words = tokens(request['sh'])
            except ValueError as error:
                return None, 0, f'the script does not parse: {error}'
            if any('$(' in word or '`' in word for word in words):
                return None, 0, 'a command substitution inside quotes is not checked'
            commands, others = simple_commands(words)
            argv = ['/bin/sh', '-c', request['sh']]
        elif isinstance(request.get('argv'), list) and request['argv'] and all(isinstance(a, str) for a in request['argv']):
            words = list(request['argv'])
            commands, others = [words], []
            argv = [CLI if words[0] == 'gleaner' else words[0]] + words[1:]
        else:
            return None, 0, 'a request holds a non-empty "argv" list of strings or an "sh" string'
        for command in commands:
            name = command[0]
            if name not in TOOLS | BUILTINS:
                return None, 0, f'{name} is not a tool the policies use'
            if name == 'gleaner':
                if self.policy == 'R':
                    return None, 0, 'the raw policy does not use gleaner'
                if command[-2:] != ['--home', self.world]:
                    return None, 0, 'gleaner runs only with --home <world>'
        for word in [w for command in commands for w in command[1:]] + others:
            if self.outside(word):
                return None, 0, f'{word} is outside the world'
        return argv, sum(1 for command in commands if command[0] in TOOLS), None

    def execute(self, request):
        argv, processes, why = self.check(request)
        started = time.monotonic()
        entry = {}
        if argv is None:
            status, out, err = 126, b'', f'refused: {why}\n'.encode()
            entry['refused'] = why
        else:
            try:
                done = subprocess.run(['sandbox-exec', '-p', self.profile, *argv], cwd=self.world, env=self.env,
                                      capture_output=True, timeout=COMMAND_TIMEOUT)
                status, out, err = done.returncode, done.stdout, done.stderr
            except subprocess.TimeoutExpired as expired:
                status, out, err = 124, expired.stdout or b'', (expired.stderr or b'') + b'timed out\n'
                entry['timed_out'] = True
            except OSError as failure:
                status, out, err = 127, b'', f'{failure}\n'.encode()
        elapsed = time.monotonic() - started
        if isinstance(request, dict) and isinstance(request.get('sh'), str):
            text, tool = request['sh'], 'sh'
        elif isinstance(request, dict) and isinstance(request.get('argv'), list):
            text, tool = ' '.join(shlex.quote(str(a)) for a in request['argv']), str((request['argv'] or ['?'])[0])
        else:
            text, tool = json.dumps(request)[:400], '?'
        phase = request.get('phase', 'raw') if isinstance(request, dict) else 'raw'
        self.commands.append(dict(n=len(self.commands) + 1, phase=phase, tool=tool,
                                  command=text if len(text) <= 400 else text[:400] + '…', processes=processes,
                                  status=status, stdout_bytes=len(out), stderr_bytes=len(err),
                                  tilde_bytes=len(self.tilde(out)) + len(self.tilde(err)), seconds=round(elapsed, 4),
                                  **entry))
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
            shutil.copyfile(os.path.join(self.gold, write['source']), os.path.join(self.world, write['path']))
            self.fired = len(self.commands)

    def run(self):
        if os.path.exists(self.scratch):
            shutil.rmtree(self.scratch)
        os.makedirs(self.scratch)
        kept = self.keep()
        started = time.monotonic()
        error = None
        answer = None
        trace_path = os.path.join(self.folder, 'episodes', f'{self.policy}.err')
        with open(trace_path, 'w', encoding='utf-8') as log:
            process = subprocess.Popen(['sandbox-exec', '-p', self.policy_profile, sys.executable, '-I', POLICIES, self.policy],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, cwd='/', text=True,
                                       encoding='utf-8', env=dict(PATH=os.environ.get('PATH', '/usr/bin:/bin'), LANG='en_US.UTF-8'))
            # A policy that stops answering is stopped, and its episode fails.
            watchdog = threading.Timer(EPISODE_TIMEOUT, process.kill)
            watchdog.start()
            try:
                process.stdin.write(json.dumps(dict(task=self.task, home=self.world, scratch=self.scratch)) + '\n')
                process.stdin.flush()
                for line in process.stdout:
                    try:
                        message = json.loads(line)
                    except ValueError:
                        error = f'the policy wrote a line that is not JSON: {line[:200]!r}'
                        break
                    if isinstance(message, dict) and 'answer' in message:
                        answer = message['answer']
                        break
                    process.stdin.write(json.dumps(self.execute(message)) + '\n')
                    process.stdin.flush()
                else:
                    error = 'the policy stopped without an answer'
            except (OSError, ValueError) as failure:
                error = f'{type(failure).__name__}: {failure}'
            finally:
                watchdog.cancel()
                if time.monotonic() - started >= EPISODE_TIMEOUT:
                    error = f'the episode ran past {EPISODE_TIMEOUT} s'
                try:
                    process.stdin.close()
                except OSError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
        seconds = time.monotonic() - started
        if not isinstance(answer, dict):
            answer = None
        checked = {path: (file_sha256(path) if os.path.isfile(path) else None) for path in bytes_files(answer)}
        restored = git_restores(answer, self.world)
        self.restore(kept)
        # The scratch folder's copies are hashed; they are not kept.
        shutil.rmtree(self.scratch, ignore_errors=True)
        with open(trace_path, encoding='utf-8') as f:
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
                    bytes=dict(stdout=stdout, stderr=stderr, total=stdout + stderr, home_as_tilde=tilde),
                    command_count=len(self.commands), processes=sum(c['processes'] for c in self.commands),
                    refused=sum(1 for c in self.commands if 'refused' in c),
                    timed_out=sum(1 for c in self.commands if c.get('timed_out')),
                    phases=phases, seconds=round(seconds, 3), drift_after_command=self.fired, checked=checked,
                    checked_git=restored, commands=self.commands)

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
        clear_staging(self.world)


def clear_staging(world):
    """Removes Gleaner's hand-off copies, which it makes read-only."""
    staging = os.path.join(world, 'Library', 'Caches', 'Gleaner', 'handoff')
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


def git_restores(answer, world):
    """For each artifact an answer offers from git, the sha256 of what its restore command's commit
    holds at that file's path, hashed here rather than taken from the answer; None when the
    command names no commit and path that git can show."""
    found = {}
    for artifact in (answer or {}).get('artifacts') or []:
        command = artifact.get('restore_command') if isinstance(artifact, dict) else None
        if artifact.get('source') != 'git' or not isinstance(command, str):
            continue
        try:
            words = [world + w[1:] if w == '~' or w.startswith('~/') else w for w in shlex.split(command)]
            repository = words[words.index('-C') + 1]
            if 'worktree' in words:
                folder, commit = words[-2], words[-1]
                spec = f'{commit}:{os.path.relpath(artifact["path"], folder)}'
            elif 'restore' in words:
                commit = next(w.split('=', 1)[1] for w in words if w.startswith('--source='))
                spec = f'{commit}:./{words[-1]}'
            else:
                spec = words[words.index('show') + 1]
        except (ValueError, IndexError, StopIteration, TypeError):
            found[artifact.get('path')] = None
            continue
        blob = subprocess.run(['git', '-C', repository, 'show', spec], capture_output=True,
                              env=dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1'))
        found[artifact.get('path')] = hashlib.sha256(blob.stdout).hexdigest() if blob.returncode == 0 else None
    return found


def prepared_world(seed, out, task):
    """The seed's world for `task` under `out`, written and prepared unless it already is: its
    folder, its preparation record, and every attempt that failed. A world whose writing or
    preparation fails is set aside under a name of its own and written once more."""
    folder = os.path.join(out, f'seed-{seed}')
    world = os.path.join(folder, task)
    failed = []
    for attempt in (1, 2):
        try:
            if not os.path.exists(world):
                worlds.generate(seed, folder, [task])
            record = os.path.join(history.gold_folder(world), 'prepared.json')
            if not os.path.exists(record):
                prepare.prepare(world, prepare.APP, say=lambda _: None)
            with open(record, encoding='utf-8') as f:
                cost = json.load(f)
            if 'index_runs' not in cost:
                raise RuntimeError('its preparation stopped partway')
            return world, cost, failed
        except (Exception, SystemExit) as error:
            failed.append(dict(attempt=attempt, reason=f'{type(error).__name__}: {error}'))
            stamp = datetime.datetime.now().strftime('%H%M%S')
            for path in (world, history.gold_folder(world)):
                if os.path.exists(path):
                    os.rename(path, f'{path}.failed-{attempt}-{stamp}')
    return None, None, failed


def distractors(world, words, sessions):
    """How many session logs, sub-agent transcripts left out, hold each word and every word, as
    `rg -i -F` finds them; and how many of the logs are decoys and near misses."""
    logs = [s for s in sessions if not s.get('subagent')]
    holding = {word: 0 for word in words}
    every = 0
    for session in logs:
        with open(os.path.join(world, session['log']), 'rb') as f:
            text = f.read().decode('utf-8', 'replace').lower()
        held = [word for word in words if word.lower() in text]
        for word in held:
            holding[word] += 1
        every += len(held) == len(words)
    return dict(logs=len(logs), holding=holding, holding_every_word=every,
                decoys=sum(1 for s in logs if s.get('role') == 'decoy'),
                near_misses=sum(1 for s in logs if s.get('role') == 'near_miss'))


def world_record(seed, task, folder, cost, failed):
    """What the scorer and the report need of a world: its question, the gold it is scored
    against, its preparation and how many logs each word reaches."""
    record = dict(seed=seed, task=task, family=worlds.FAMILY.get(task, 'E'), preparation_failures=failed)
    if folder is None:
        return dict(record, asks=None, world=None, gold=None, preparation=None)
    with open(os.path.join(folder, 'task.json'), encoding='utf-8') as f:
        question = json.load(f)
    with open(os.path.join(history.gold_folder(folder), 'gold.json'), encoding='utf-8') as f:
        gold = json.load(f)
    # What the scorer reads of the gold; check_worlds.py asserts the rest of it.
    kept = dict(answer=gold['answer'], hard_failures=gold['hard_failures'], sessions=gold['sessions'],
                library=dict(disk=gold['library'].get('disk', {})))
    world = folder + '/world'
    return dict(record, asks=question['asks'], world=world, question=question['question'], words=question['words'],
                gold=kept, distractors=distractors(world, question['words'], gold['sessions']),
                preparation=dict(index_runs=len(cost['index_runs']), index_seconds=cost['index_seconds'],
                                 library_bytes=cost['library_bytes'], saved_copies=cost['saved_copies'],
                                 generation=cost['generation']))


def not_run(record, policy, seed, order):
    """An episode that could not run, because its world could not be prepared; it counts as failed."""
    reason = 'the world could not be written and prepared: ' + '; '.join(f['reason'] for f in record['preparation_failures'])
    return dict(task=record['task'], family=record['family'], asks=record['asks'], policy=policy, seed=seed, order=order,
                answer=dict(status='failed', note=reason), error=reason, not_run=True,
                bytes=dict(stdout=0, stderr=0, total=0, home_as_tilde=0), command_count=0, processes=0, refused=0,
                timed_out=0, phases={}, seconds=0, drift_after_command=None, checked={}, checked_git={}, commands=[])


def gold_check(folder, scored):
    """The world checked against its gold once both policies have answered. A scored world's
    check is kept as pass or fail and a count, not what failed."""
    try:
        failures = check_worlds.check(folder)
    except Exception as error:  # A check that breaks is a failed check.
        failures = [f'the check broke: {type(error).__name__}: {error}']
    finally:
        clear_staging(os.path.join(folder, 'world'))
    return dict(ok=not failures, failures=len(failures)) if scored else dict(ok=not failures, failures=failures)


def link_gleaner():
    os.makedirs(BIN, exist_ok=True)
    link = os.path.join(BIN, 'gleaner')
    if os.path.lexists(link):
        os.unlink(link)
    os.symlink(CLI, link)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('seeds', type=seed_list, help='seeds: 1,2,3 or 1-3; from 101 they are scored')
    parser.add_argument('out', help='a folder for the worlds, with no symbolic link in its path, outside /tmp and /private')
    parser.add_argument('--tasks', nargs='+', default=list(worlds.TASKS))
    parser.add_argument('--policies', nargs='+', default=['R', 'G'], choices=['R', 'G'])
    parser.add_argument('--no-build', action='store_true', help='use the app and command already built')
    parser.add_argument('--results', help='the folder for results.json and report.md (default: eval/results/<date>/ '
                                          'for scored seeds, eval/results/<date>/dev/ otherwise); written once')
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    scored = max(args.seeds) >= SCORED
    harness = recipe()
    lock = require_lock(harness) if scored else None
    day = os.path.join(REPO, 'eval', 'results', datetime.date.today().isoformat())
    results_dir = args.results or (day if scored else os.path.join(day, 'dev'))
    for name in ('results.json', 'episodes.jsonl'):
        if os.path.exists(os.path.join(results_dir, name)):
            raise SystemExit(f'{results_dir} already holds {name}: every run keeps its own folder (--results)')
    if not args.no_build:
        build()
    link_gleaner()
    out = history.place(args.out)
    os.makedirs(out, exist_ok=True)
    os.makedirs(results_dir, exist_ok=True)
    stream = open(os.path.join(results_dir, 'episodes.jsonl'), 'w', encoding='utf-8')
    started = time.time()
    records, episodes = [], []
    for seed in args.seeds:
        for n, task in enumerate(args.tasks):
            folder, cost, failed = prepared_world(seed, out, task)
            record = world_record(seed, task, folder, cost, failed)
            records.append(record)
            if failed:
                print(f'seed {seed} {task}: {len(failed)} failed preparation attempt(s): {failed[-1]["reason"]}')
            # Alternate which policy goes first, so neither always meets a warm file cache.
            order = args.policies if (seed + n) % 2 == 0 else list(reversed(args.policies))
            for position, policy in enumerate(order, 1):
                if folder is None:
                    episode = not_run(record, policy, seed, position)
                else:
                    episode = Episode(folder, policy, out).run()
                    episode.update(seed=seed, order=position)
                episodes.append(episode)
                stream.write(json.dumps(episode, ensure_ascii=False) + '\n')
                stream.flush()
                answer = episode['answer']
                print(f"seed {seed} {task} {policy}: {answer.get('status')}, {episode['command_count']} commands, "
                      f"{episode['bytes']['total']} bytes, {episode['seconds']} s" + (f" ({episode['error']})" if episode['error'] else ''))
            if folder is not None:
                record['gold_check'] = gold_check(folder, scored)
                if not record['gold_check']['ok']:
                    print(f'seed {seed} {task}: the world does not hold what its gold presumes')
    stream.close()
    results = dict(evaluation='E0', created=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
                   seeds=args.seeds, scored=scored, tasks=args.tasks, policies=args.policies,
                   seconds=round(time.time() - started), environment=versions(), recipe=harness, lock=lock,
                   worlds=records, episodes=episodes)
    path = os.path.join(results_dir, 'results.json')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
        f.write('\n')
    # results.json now holds every episode; episodes.jsonl is left only by a run that stopped.
    os.remove(os.path.join(results_dir, 'episodes.jsonl'))
    score.write(path)
    print(f'wrote {path} and report.md')


if __name__ == '__main__':
    main()
