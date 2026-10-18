#!/usr/bin/env python3
"""Writes one frozen world per task for evaluation E0 (docs/design/evaluation-e0.md, "Worlds").

    eval/worlds.py <seed> <out>

For each task, <out>/seed-<seed>/<task>/ holds what the policies may be given:
- world/: the home folder both policies see: .claude/projects, .codex/sessions and work/,
  where the projects north, south and harbor are git repositories;
- task.json: the question, the words a person would type for it, and what kind of answer it
  asks for. It carries nothing from the answer (T23's pointer is the question itself).

What the evaluator keeps from them goes to <out>/gold/seed-<seed>/<task>/ (history.gold_folder):
- gold.json: the mechanically checkable answer, the sessions in scope, and what the prepared
  library must hold (`library`, checked by check_worlds.py);
- history.json: the epochs prepare.py applies when it prepares the catalog (see history.py);
- for T25, drift.json and drift/: the change the runner makes while a policy works.

Everything is a function of the seed and <out>: ids, timestamps, the order of sessions and of
the files a reply names, distractors and their number. Logs record absolute paths, so a world
stays where it was written. Epoch 0 is written here at the seed's base date; the epochs in
history.json carry offsets that prepare.py anchors to the moment it prepares the world.
"""
import datetime
import hashlib
import json
import os
import random
import re
import string
import sys
import uuid

import history

TASKS = ('T01', 'T02', 'T03', 'T04', 'T07', 'T09', 'T10', 'T12', 'T16', 'T19', 'T20', 'T21', 'T22', 'T23', 'T25')
FAMILY = {'T16': 'S', 'T19': 'B', 'T20': 'B', 'T21': 'B', 'T22': 'B', 'T23': 'B', 'T25': 'B'}

DAY = 86400
# Epoch 1's deliveries fall within nine minutes before the index, inside Gleaner's ten-minute
# window for a capture at delivery; a later indexed epoch spans twenty seconds after the last
# index, and changes after the last index span five.
LIVE_SPAN, LATER_SPAN, AFTER_SPAN = 540, 20, 5
SAVE_LIMIT = 64 << 20
PROJECTS = ('north', 'south', 'harbor')
CLAUDE_VERSION = '2.0.34'
CLAUDE_MODEL = 'claude-fable-5'
CODEX_VERSION = '0.46.0'
ALNUM = string.ascii_letters + string.digits


def sha256(data):
    return hashlib.sha256(data.encode('utf-8') if isinstance(data, str) else data).hexdigest()


def sparse_sha256(head, size):
    """The hash of `head` followed by zeros up to `size` bytes."""
    digest = hashlib.sha256(head.encode('utf-8'))
    left = size - len(head.encode('utf-8'))
    block = bytes(1 << 20)
    while left > 0:
        digest.update(block[:min(left, len(block))])
        left -= len(block)
    return digest.hexdigest()


def delivery_id(log_path, line, path):
    """The id Gleaner gives the delivery of `path` first named in the reply record at `line`
    (DeliveryCandidate.id): the first ten bytes of a SHA-256, in hex."""
    return hashlib.sha256(f'{log_path}\n{line}\n{path}'.encode('utf-8')).hexdigest()[:20]


class Cursor:
    """A session's clock within one epoch: each call moves it on by a few seconds."""

    def __init__(self, rng, start):
        self.rng = rng
        self.t = start

    def __call__(self, low=4.0, high=14.0):
        self.t += self.rng.uniform(low, high)
        return round(self.t, 3)


class World:
    """A world being written: its epochs of operations and the sessions in it."""

    def __init__(self, task, root, rng):
        self.task = task
        self.root = root
        self.rng = rng
        day = datetime.datetime(2026, 4, 6, tzinfo=datetime.timezone.utc) + datetime.timedelta(days=rng.randrange(140))
        # Epoch 0's anchor: midnight UTC of the seed's base date, well before any preparation.
        self.base = day.timestamp()
        self.epochs = [dict(index=False, span=0, ops=[]), dict(index=True, span=LIVE_SPAN, ops=[])]
        self.sessions = []
        self.repos = {}
        self.files = set()

    # Paths and ids

    def path(self, rel):
        return self.root + '/' + rel

    def rel(self, path):
        assert path.startswith(self.root + '/'), path
        return path[len(self.root) + 1:]

    def uuid(self):
        return str(uuid.UUID(int=self.rng.getrandbits(128), version=4))

    def token(self, n):
        return ''.join(self.rng.choice(ALNUM) for _ in range(n))

    def hex(self, n):
        return ''.join(self.rng.choice('0123456789abcdef') for _ in range(n))

    # Operations

    def later(self, index):
        """Adds an epoch after the last: another index run, or changes after the last one."""
        self.epochs.append(dict(index=index, span=LATER_SPAN if index else AFTER_SPAN, ops=[]))
        return len(self.epochs) - 1

    def op(self, epoch, **op):
        self.epochs[epoch]['ops'].append(op)

    def write(self, epoch, rel, mtime, text=None, sparse=None):
        """Writes a file with modification time `mtime` (an offset in its epoch); returns its hash.
        `sparse` is (head, size): the head, then zeros up to the size."""
        if text is not None:
            self.op(epoch, op='write', path=rel, text=text, mtime=mtime)
            digest = sha256(text)
        else:
            head, size = sparse
            self.op(epoch, op='write', path=rel, sparse=dict(head=head, size=size), mtime=mtime)
            digest = sparse_sha256(head, size)
        self.files.add(rel)
        return digest

    def git(self, epoch, cwd, at, *args):
        self.op(epoch, op='git', cwd=cwd, args=list(args), at=at)

    def repo(self, name):
        """A project: a git repository at work/<name> with a little history of its own."""
        rel = f'work/{name}'
        made = -self.rng.uniform(70, 90) * DAY
        self.write(0, f'{rel}/README.md', made, text=f'# {name.title()}\n\n{PROJECT_BLURB[name]}\n')
        self.write(0, f'{rel}/.gitignore', made, text='tmp/\n.claude/\nnode_modules/\n')
        for path, text in PROJECT_SOURCES[name].items():
            self.write(0, f'{rel}/{path}', made, text=text)
        self.git(0, rel, made, 'init', '-q', '-b', 'main')
        self.git(0, rel, made, 'add', '-A')
        self.git(0, rel, made, 'commit', '-q', '-m', 'Initial commit')
        self.repos[name] = self.path(rel)
        return self.repos[name]

    def projects(self):
        return {name: self.repo(name) for name in PROJECTS}

    # Sessions

    def claude(self, project, cwd=None):
        return Claude(self, project, cwd)

    def codex(self, project, start, title):
        return Codex(self, project, start, title)

    def old(self):
        """A start offset in epoch 0: some weeks before the base date, in working hours."""
        return round(-self.rng.randint(3, 55) * DAY + self.rng.uniform(8, 19) * 3600, 3)

    def decoys(self, words, old, new):
        """Sessions about other things, spread over the projects and both agents: `old` in epoch 0
        and `new` just before the index. They are drawn without regard to the question, except
        that no topic may hold every one of its `words` (a project word, which any session's cwd
        can supply, counts as held). Then one or two near misses: sessions that each hold exactly
        one of the words and nothing else of the question, so every word reaches more logs than
        the answer's."""
        def answers(topic):
            text = ' '.join(topic).lower()
            return all(word in text or word in PROJECTS for word in words)

        topics = [topic for topic in DECOY_TOPICS if not answers(topic)]
        self.rng.shuffle(topics)
        for n in range(old + new):
            request, rel, title, reply = topics[n]
            name = os.path.basename(rel)
            self.background(self.rng.choice(PROJECTS), n < old, request, rel, title,
                            reply.format(link=f'[{name}]({rel})'), decoy_content(rel, title, self.rng), 'decoy')
        if len(words) > 1:
            for word in self.rng.sample(words, self.rng.randint(1, 2)):
                self.near_miss(word, [w for w in words if w != word])

    def near_miss(self, word, others):
        """A session whose request, title, reply, file and project hold `word` and none of `others`."""
        rel = f'docs/notes-{self.hex(4)}.md'
        name = os.path.basename(rel)
        request = self.rng.choice(NEAR_MISSES).format(word=word)
        title = f'Notes on {word}'
        content = f'# Notes on {word}\n\n- What came up about {word} this week.\n- Follow-ups are tracked separately.\n'
        reply = f'Notes: [{name}]({rel}).'
        project = self.rng.choice([p for p in PROJECTS if p not in others])
        held = ' '.join([request, rel, title, content, reply, project]).lower()
        assert not any(other in held for other in others), (self.task, word, others)
        self.background(project, self.rng.random() < 0.5, request, rel, title, reply, content, 'near_miss')

    def background(self, project, old, request, rel, title, reply, content, role):
        """One session that writes `rel` and links it in its reply: in epoch 0 when `old`, by Codex
        some of the time, else in epoch 1 just before the index."""
        if old and self.rng.random() < 0.3:
            session = self.codex(project, self.old(), title)
            c = Cursor(self.rng, session.start)
            session.turn(c(), request)
            session.say(c(), 'Looking at the project layout first.')
            session.shell(c(), 'ls', 'README.md\nsrc\n')
            session.shell(c(), f"mkdir -p {os.path.dirname(rel) or '.'} && cat > {rel} <<'EOF'\n{content}EOF", '',
                          files=[(rel, content)])
            session.final(c(), reply)
            session.role = role
            return
        session = self.claude(project)
        session.role = role
        if old:
            epoch, c = 0, Cursor(self.rng, self.old())
        else:
            epoch, c = 1, Cursor(self.rng, -self.rng.uniform(150, 260))
        session.user(epoch, c(), request)
        session.text(epoch, c(), self.rng.choice(['On it.', 'Let me look at the project first.', 'Writing it now.']))
        session.write(epoch, c(), rel, content)
        session.reply(epoch, c(2, 5), reply)
        session.title(epoch, title)

    # Output

    def manifest(self):
        return [dict(id=s.id, provider=s.provider, project=s.project, log=s.log, **({'subagent': True} if s.subagent else {}),
                     **({'role': s.role} if s.role else {}))
                for s in self.sessions]

    def finish(self, gold_dir):
        """Applies epoch 0 and writes the later epochs for prepare.py."""
        os.makedirs(self.path('.claude/projects'), exist_ok=True)
        os.makedirs(self.path('.codex/sessions'), exist_ok=True)
        history.apply(self.root, self.epochs[0]['ops'], self.base)
        later = [dict(index=e['index'], span=e['span'], ops=merge(e['ops'])) for e in self.epochs[1:]]
        dump(os.path.join(gold_dir, 'history.json'), dict(base=history.iso(self.base), epochs=later))


def merge(ops):
    """Consecutive appends to one log, as one operation."""
    merged = []
    for op in ops:
        if merged and op['op'] == 'append' and merged[-1]['op'] == 'append' and merged[-1]['path'] == op['path']:
            merged[-1] = dict(merged[-1], lines=merged[-1]['lines'] + op['lines'])
        else:
            merged.append(op)
    return merged


class Claude:
    """A Claude Code session log, with the record shapes of Tests/GleanerCoreTests/Fixtures."""
    provider = 'claude-code'

    def __init__(self, world, project, cwd=None, subagent_of=None):
        self.w = world
        self.project = project
        self.cwd = cwd or world.repos[project]
        self.id = world.uuid()
        self.subagent = subagent_of is not None
        if subagent_of:
            self.agent = world.hex(8)
            self.log = f'{subagent_of.log[:-len(".jsonl")]}/subagents/agent-{self.agent}.jsonl'
            self.id = subagent_of.id
        else:
            self.log = f".claude/projects/{re.sub(r'[^A-Za-z0-9]', '-', self.cwd)}/{self.id}.jsonl"
        self.parent = None
        self.lines = 0
        self.clock = None
        self.message = None
        self.replied = False
        self.role = None
        world.sessions.append(self)

    def _append(self, epoch, record):
        self.w.op(epoch, op='append', path=self.log, lines=[record])
        self.lines += 1
        return self.lines

    def _entry(self, epoch, t, kind, cwd=None, **fields):
        assert self.clock is None or (epoch, t) > self.clock, (self.w.task, self.log, epoch, t, self.clock)
        self.clock = (epoch, t)
        uid = self.w.uuid()
        record = dict(parentUuid=self.parent, isSidechain=self.subagent, userType='external', cwd=cwd or self.cwd,
                      sessionId=self.id, version=CLAUDE_VERSION, gitBranch='main')
        if self.subagent:
            record['agentId'] = self.agent
        record.update(type=kind, **fields, uuid=uid, timestamp={'$t': t})
        self.parent = uid
        return self._append(epoch, record)

    def user(self, epoch, t, text):
        self.replied = False
        return self._entry(epoch, t, 'user', message=dict(role='user', content=text), origin=dict(kind='human'))

    def _assistant(self, epoch, t, block, cwd=None, same=False):
        if not same or self.message is None:
            self.message = ('msg_01' + self.w.token(22), 'req_011C' + self.w.token(20))
        message = dict(model=CLAUDE_MODEL, id=self.message[0], type='message', role='assistant', content=[block],
                       stop_reason=None, stop_sequence=None,
                       usage=dict(input_tokens=self.w.rng.randint(3, 40), output_tokens=self.w.rng.randint(12, 480)))
        return self._entry(epoch, t, 'assistant', cwd=cwd, message=message, requestId=self.message[1])

    def text(self, epoch, t, text, cwd=None, same=False):
        return self._assistant(epoch, t, dict(type='text', text=text), cwd=cwd, same=same)

    def reply(self, epoch, t, text, cwd=None, same=False):
        """Text of the turn's final reply: nothing but text may follow it before the next request."""
        self.replied = True
        return self.text(epoch, t, text, cwd=cwd, same=same)

    def tool(self, epoch, t, name, arguments, result, details, cwd=None, after=1.5):
        """A tool call and its result `after` seconds later; returns the result's line."""
        assert not self.replied, f'{self.w.task}: a tool call after the reply would make it no final reply'
        call = 'toolu_01' + self.w.token(22)
        self._assistant(epoch, t, dict(type='tool_use', id=call, name=name, input=arguments), cwd=cwd)
        caller = self.parent
        return self._entry(epoch, round(t + after, 3), 'user', cwd=cwd,
                           message=dict(role='user', content=[dict(tool_use_id=call, type='tool_result', content=result)]),
                           toolUseResult=details, sourceToolAssistantUUID=caller)

    def where(self, cwd):
        return cwd or self.cwd

    def write(self, epoch, t, rel, content, cwd=None):
        """The Write tool: the file is written between the call and its result. Returns its hash."""
        path = self.where(cwd) + '/' + rel
        existed = self.w.rel(path) in self.w.files
        digest = self.w.write(epoch, self.w.rel(path), round(t + 0.7, 3), text=content)
        self.tool(epoch, t, 'Write', dict(file_path=path, content=content),
                  f'The file {path} has been updated.' if existed else f'File created successfully at: {path}',
                  dict(type='update' if existed else 'create', filePath=path, content=content, structuredPatch=[]), cwd=cwd)
        return digest

    def read(self, epoch, t, rel, content, cwd=None):
        path = self.where(cwd) + '/' + rel
        lines = content.splitlines()
        numbered = '\n'.join(f'{n:>6}\u2192{text}' for n, text in enumerate(lines, 1))
        self.tool(epoch, t, 'Read', dict(file_path=path), numbered,
                  dict(type='text', file=dict(filePath=path, content=content, numLines=len(lines), startLine=1,
                                              totalLines=len(lines))), cwd=cwd, after=0.4)

    def bash(self, epoch, t, command, output, cwd=None, after=3.0, description=None):
        return self.tool(epoch, t, 'Bash', dict(command=command, description=description or f'Run {command.split()[0]}'), output,
                         dict(stdout=output, stderr='', interrupted=False, isImage=False), cwd=cwd, after=after)

    def raw(self, epoch, text):
        """Text written into the log as it is: a line cut off mid-record has no newline."""
        self.w.op(epoch, op='append', path=self.log, lines=[text])
        self.lines += 1
        return self.lines

    def title(self, epoch, title):
        self._append(epoch, dict(type='ai-title', sessionId=self.id, aiTitle=title))


class Codex:
    """A Codex rollout in epoch 0, with the record shapes of Tests/GleanerCoreTests/Fixtures."""
    provider = 'codex'
    subagent = False

    def __init__(self, world, project, start, title):
        self.w = world
        self.project = project
        self.cwd = world.repos[project]
        self.id = world.uuid()
        self.start = start
        when = datetime.datetime.fromtimestamp(world.base + start, datetime.timezone.utc)
        self.log = f'.codex/sessions/{when:%Y/%m/%d}/rollout-{when:%Y-%m-%dT%H-%M-%S}-{self.id}.jsonl'
        self.lines = 0
        self.clock = None
        self.turn_id = None
        self.role = None
        world.sessions.append(self)
        self._record(start, 'session_meta', dict(
            id=self.id, timestamp={'$t': start}, cwd=self.cwd, originator='codex_cli_rs', cli_version=CODEX_VERSION,
            source='cli', thread_source='user', model_provider='openai', git=dict(branch='main')))
        self._record(start + 0.01, 'response_item', dict(
            type='message', role='user',
            content=[dict(type='input_text', text=f'<environment_context>\n  <cwd>{self.cwd}</cwd>\n'
                                                  '  <approval_policy>on-request</approval_policy>\n'
                                                  '  <sandbox_mode>workspace-write</sandbox_mode>\n</environment_context>')],
            internal_chat_message_metadata_passthrough=dict(content_item_kinds=['environments.environment_context'])))
        world.op(0, op='append', path='.codex/session_index.jsonl',
                 lines=[dict(id=self.id, thread_name=title, updated_at={'$t': start})])

    def _record(self, t, kind, payload):
        t = round(t, 3)
        assert self.clock is None or t > self.clock, (self.w.task, self.log, t, self.clock)
        self.clock = t
        self.w.op(0, op='append', path=self.log, lines=[dict(timestamp={'$t': t}, type=kind, payload=payload)])
        self.lines += 1
        return self.lines

    def turn(self, t, request):
        self.turn_id = self.w.uuid()
        self._record(t, 'turn_context', dict(
            turn_id=self.turn_id, cwd=self.cwd, approval_policy='on-request', sandbox_policy=dict(mode='workspace-write'),
            model='gpt-5-codex', effort='medium', summary='auto'))
        self._record(t + 0.01, 'event_msg', dict(type='task_started', turn_id=self.turn_id, model_context_window=272000))
        return self._record(t + 0.02, 'response_item', dict(
            type='message', role='user', content=[dict(type='input_text', text=request)],
            internal_chat_message_metadata_passthrough=dict(content_item_kinds=['user.text'])))

    def say(self, t, text):
        return self._record(t, 'response_item', dict(type='message', role='assistant', phase='commentary',
                                                     content=[dict(type='output_text', text=text)]))

    def shell(self, t, command, output, files=()):
        """A shell call. `output` None is a call with no result: an attempt whose outcome is unknown.
        `files` are written between the call and its output."""
        call = 'call_' + self.w.token(24)
        self._record(t, 'response_item', dict(type='function_call', name='shell', call_id=call, arguments=json.dumps(
            dict(command=['bash', '-lc', command], workdir=self.cwd, timeout_ms=120000))))
        digests = [self.w.write(0, self.w.rel(self.cwd + '/' + rel), round(t + 0.5, 3), text=text) for rel, text in files]
        if output is not None:
            self._record(t + 1.0, 'response_item', dict(type='function_call_output', call_id=call, output=json.dumps(
                dict(output=output, metadata=dict(exit_code=0, duration_seconds=0.9)))))
        return digests

    def final(self, t, text):
        line = self._record(t, 'response_item', dict(type='message', role='assistant', phase='final_answer',
                                                     content=[dict(type='output_text', text=text)]))
        self._record(t + 0.01, 'event_msg', dict(type='task_complete', turn_id=self.turn_id, last_agent_message=text))
        return line


# Contents

PROJECT_BLURB = {
    'north': 'The north gateway, billing and partner API.',
    'south': 'Batch jobs, checkout and the signup flow for the south region.',
    'harbor': 'The export pipeline and the Chinese and English guides.',
}

PROJECT_SOURCES = {
    'north': {
        'src/gateway/client.ts': 'export async function call(url: string, init: RequestInit) {\n'
                                 '  const response = await fetch(url, init)\n'
                                 '  if (!response.ok) throw new Error(`gateway ${response.status}`)\n'
                                 '  return response\n}\n',
        'src/billing/ledger.ts': 'export interface Entry { account: string; cents: number; at: Date }\n\n'
                                 'export function balance(entries: Entry[]) {\n'
                                 '  return entries.reduce((sum, e) => sum + e.cents, 0)\n}\n',
        'openapi.yaml': 'openapi: 3.1.0\ninfo:\n  title: North partner API\n  version: 2.3.0\npaths: {}\n',
    },
    'south': {
        'src/batch/runner.py': 'def run(jobs):\n    for job in jobs:\n        job.start()\n',
        'src/signup.tsx': 'export function Signup() {\n  return <form aria-label="Sign up" />\n}\n',
        'scripts/profile.py': 'import sys\nprint("profiling", sys.argv[1:])\n',
    },
    'harbor': {
        'src/main.swift': ''.join(
            ['import Foundation\n\n'] + [f'// export step {n}\n' for n in range(1, 40)]
            + ['func slug(_ heading: String) -> String {\n',
               '    heading.lowercased().replacingOccurrences(of: " ", with: "-")\n}\n']),
        'src/export/serializer.swift': 'struct Row { var cells: [String] }\n\n'
                                       'func serialize(_ rows: [Row]) -> String {\n'
                                       '    rows.map { $0.cells.joined(separator: ",") }.joined(separator: "\\n")\n}\n',
        'scripts/plot_latency.py': 'import sys\nprint("plotting", sys.argv[1:])\n',
    },
}

# Each: request, file, session title, reply with {link}.
DECOY_TOPICS = [
    ('Write the onboarding guide for new contributors.', 'docs/onboarding.md', 'Contributor onboarding guide',
     'The guide is in {link}.'),
    ('Draft the changelog for the next minor release.', 'docs/changelog-draft.md', 'Minor release changelog',
     'Changelog draft: {link}.'),
    ('Generate seed data for the staging database.', 'data/seed.json', 'Staging seed data',
     'Seed data is in {link}; load it with the usual fixture command.'),
    ('Sketch the database schema diagram.', 'docs/schema.svg', 'Schema diagram', 'Here is the diagram: {link}.'),
    ('Write the style guide for error messages.', 'docs/error-style.md', 'Error message style guide',
     'Style guide: {link}.'),
    ('Summarize the customer interviews from last week.', 'out/interviews.md', 'Customer interview summary',
     'I summarized the interviews in {link}.'),
    ('Draft the hiring rubric for backend engineers.', 'docs/hiring-rubric.md', 'Backend hiring rubric',
     'Rubric: {link}.'),
    ('Benchmark the image resizer on the sample set.', 'out/resizer-bench.csv', 'Image resizer benchmark',
     'Results are in {link}.'),
    ('Write the deprecation notice for the v1 endpoints.', 'docs/deprecation.md', 'v1 deprecation notice',
     'Notice: {link}.'),
    ('Create the icon set for the settings page.', 'assets/settings-icons.svg', 'Settings icons',
     'Icons: {link}.'),
    ('Document the feature flag cleanup.', 'docs/flags.md', 'Feature flag cleanup', 'Documented in {link}.'),
    ('Write the localization glossary for the translators.', 'docs/glossary.md', 'Localization glossary',
     'Glossary: {link}.'),
    ('Export the open bug counts by component.', 'out/bugs.csv', 'Bug counts by component', 'Counts: {link}.'),
    ('Draft the privacy notice update.', 'docs/privacy.md', 'Privacy notice update', 'Draft: {link}.'),
    ('Prepare the release notes for the iOS build.', 'out/release-notes.md', 'iOS release notes',
     'Release notes: {link}.'),
    ('Describe the cron jobs and who owns each.', 'docs/cron.md', 'Cron job owners', 'Written up in {link}.'),
    ('Write the runbook for rotating the signing keys.', 'docs/key-rotation.md', 'Signing key rotation runbook',
     'Runbook: {link}.'),
    ('Collect the dependency licenses into one list.', 'out/licenses.md', 'Dependency licenses', 'List: {link}.'),
]

# A near miss's request, about one word of the question.
NEAR_MISSES = ['Collect what the team said about {word} into the wiki.',
               'Write up the open questions about {word} for Friday.',
               'List the tickets that mention {word}.']

BULLETS = ['Owners are listed per section.', 'Open questions are marked TODO.', 'Numbers are from the last full week.',
           'Links point at the main branch.', 'Each item has one owner.', 'Dates are in UTC.',
           'Anything unclear is flagged for review.', 'The previous version is in git history.']


def doc(title, rng, lines=()):
    body = list(lines) + rng.sample(BULLETS, rng.randint(2, 4))
    return f'# {title}\n\n' + ''.join(f'- {line}\n' for line in body)


def decoy_content(rel, title, rng):
    if rel.endswith('.json'):
        return json.dumps([dict(id=n, name=f'record-{n}') for n in range(rng.randint(3, 6))], indent=2) + '\n'
    if rel.endswith('.csv'):
        return 'name,value\n' + ''.join(f'item-{n},{rng.randint(1, 900)}\n' for n in range(rng.randint(3, 8)))
    if rel.endswith('.svg'):
        return svg(title, [rng.randint(10, 90) for _ in range(6)])
    return doc(title, rng)


def svg(label, values):
    points = ' '.join(f'{40 + 100 * n},{220 - 2 * v}' for n, v in enumerate(values))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="240">\n'
            f'  <text x="20" y="24">{label}</text>\n'
            f'  <polyline fill="none" stroke="black" points="{points}"/>\n</svg>\n')


def pdf(title):
    return (f'%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
            f'2 0 obj << /Type /Pages /Kids [] /Count 0 >> endobj\n'
            f'% {title}\ntrailer << /Root 1 0 R >>\n%%EOF\n')


# Answers and gold

def ref(session, rel, line=None):
    """A delivery as gold names it: the file, the session and log that delivered it, and the
    reply record's line."""
    found = dict(path=rel, session=session.id, log=session.log)
    if line is not None:
        found['line'] = line
    return found


def task(world, question, words, asks, **extra):
    return dict(task=world.task, family=FAMILY.get(world.task, 'E'), question=question, words=words, asks=asks, **extra)


def gold(world, answer, library, hard_failures=()):
    library = dict(dict(index_runs=sum(1 for e in world.epochs if e['index']),
                        sources={'claude-code': dict(state='read', partial_logs=0),
                                 'codex': dict(state='read', partial_logs=0)}), **library)
    return dict(task=world.task, answer=answer, hard_failures=list(hard_failures), sessions=world.manifest(), library=library)


def expect(session, rel, line=None, **fields):
    """What the library must hold for one delivery (check_worlds.py)."""
    return dict(ref(session, rel, line), **fields)


# Tasks

def t01(w):
    rng = w.rng
    w.projects()
    backoff, cap, per_try = rng.choice([100, 150, 200, 250]), rng.choice([4, 5, 8]), rng.choice([2, 3])

    def policy(project, retries):
        return (f'# {project.title()} gateway retry policy\n\nretries: {retries}\n'
                f'backoff: exponential, base {backoff} ms, cap {cap} s\ntimeout: {per_try} s per attempt\n'
                f'applies-to: {project}-gateway\n')

    rel = 'out/retry.md'
    old = w.claude('north')
    c = Cursor(rng, w.old())
    old.user(0, c(), 'Retry the flaky deploy job and write up what failed.')
    old.bash(0, c(), 'gh run rerun 4412 --failed', '✓ Re-ran 2 failed jobs')
    notes = old.write(0, c(), 'out/deploy-notes.md', doc('Deploy job failures', rng, ['The cache step timed out once.']))
    old.reply(0, c(), 'What failed and why: [deploy-notes.md](out/deploy-notes.md).')
    old.title(0, 'Flaky deploy job')

    target = w.claude('north')
    south = w.claude('south')
    south_first = rng.random() < 0.5
    starts = (-rng.uniform(500, 520), -rng.uniform(330, 360)) if south_first else (-rng.uniform(330, 360), -rng.uniform(500, 520))
    c = Cursor(rng, starts[1])
    target.user(1, c(), "North's gateway is hitting timeouts under load. Add a retry policy with backoff.")
    target.text(1, c(), "I'll check how the gateway client handles failures first.")
    target.read(1, c(), 'src/gateway/client.ts', PROJECT_SOURCES['north']['src/gateway/client.ts'])
    delivered = target.write(1, c(), rel, policy('north', 3))
    line = target.reply(1, c(), f'Added the retry policy in [retry.md]({rel}); the gateway client loads it at startup.')
    target.title(1, 'North gateway retry policy')

    c = Cursor(rng, starts[0])
    south.user(1, c(), "South's batch gateway sees timeouts too. Add a retry policy for it.")
    south_sha = south.write(1, c(), rel, policy('south', 7))
    south_line = south.reply(1, c(), f'Retry policy for South: [retry.md]({rel}).')
    south.title(1, 'South gateway retry policy')

    after = w.later(index=False)
    live = w.write(after, f'work/north/{rel}', -2.0, text=policy('north', 5))
    words = ['north', 'timeout', 'retry', 'policy']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    question = task(w, "Find the retry-policy file delivered for North's timeout request and state its `retries` value in "
                       "that delivered version.", words, 'value', project='north', field='retries')
    answer = dict(delivery=ref(target, f'work/north/{rel}', line), sha256=delivered, value='3',
                  excluded=[dict(path=f'work/south/{rel}', value='7', why="South's file of the same name"),
                            dict(path=f'work/north/{rel}', value='5', why="North's file as it is now, not the delivered bytes")])
    library = dict(
        deliveries=[expect(target, f'work/north/{rel}', line, sha256=delivered, provenance='at_delivery', saved=True,
                           number=1, of=1, availability='saved_copy', plan='ready'),
                    expect(south, f'work/south/{rel}', south_line, sha256=south_sha, provenance='at_delivery', saved=True),
                    expect(old, 'work/north/out/deploy-notes.md', sha256=notes, provenance='first_seen_after_delivery')],
        disk={f'work/north/{rel}': live, f'work/south/{rel}': south_sha},
        find=[dict(words=words, paths=[f'work/north/{rel}'])])
    return question, gold(w, answer, library, ['current_as_delivered', 'wrong_project'])


def t02(w):
    rng = w.rng
    w.projects()
    rel = 'out/review.md'
    ratio = rng.choice(['2.9', '3.1', '3.4'])
    first = (f'# Checkout accessibility review\n\n## Findings\n\n- Body text on the payment step fails contrast ({ratio}:1).\n'
             '- Focus outlines disappear on the promo banner.\n- The card field has no visible label.\n\n'
             'Recommendation: increase contrast\n')
    second = ('# Checkout review: board summary\n\nThe checkout flow review, condensed to one page for the board.\n\n'
              f'- {rng.randint(3, 6)} issues found, one blocking.\n- Fixes fit in the next sprint.\n\n'
              'Recommendation: shorten summary\n')

    audit = w.claude('south')
    c = Cursor(rng, w.old())
    audit.user(0, c(), 'Run an accessibility audit of the South signup form.')
    audit.read(0, c(), 'src/signup.tsx', PROJECT_SOURCES['south']['src/signup.tsx'])
    audit.write(0, c(), 'out/a11y-audit.md', doc('Signup form audit', rng, ['Labels are present on every field.']))
    audit.reply(0, c(), 'Audit: [a11y-audit.md](out/a11y-audit.md).')
    audit.title(0, 'Signup form audit')

    notes = w.claude('south')
    c = Cursor(rng, w.old())
    notes.user(0, c(), 'Write code review notes for the cache PR.')
    notes.write(0, c(), rel, doc('Cache PR notes', rng, ['Eviction runs on every write.']))
    notes.reply(0, c(), f'Notes: [review.md]({rel}).')
    notes.title(0, 'Cache PR notes')

    one = w.claude('harbor')
    c = Cursor(rng, -rng.uniform(480, 510))
    one.user(1, c(), 'Review the checkout flow for accessibility and recommend the one fix to make first.')
    one.text(1, c(), "I'll go through the checkout screens one by one.")
    first_sha = one.write(1, c(10, 30), rel, first)
    first_line = one.reply(1, c(), f'The accessibility review is in [review.md]({rel}).')
    one.title(1, 'Checkout accessibility review')

    agenda = w.claude('north')
    c = Cursor(rng, -rng.uniform(200, 260))
    agenda.user(1, c(), 'Write the agenda for the board meeting.')
    agenda.write(1, c(), 'out/board-agenda.md', doc('Board meeting agenda', rng, ['Checkout status', 'Hiring plan']))
    agenda.reply(1, c(), 'Agenda: [board-agenda.md](out/board-agenda.md).')

    two = w.claude('harbor')
    later = w.later(index=True)
    c = Cursor(rng, -18.0)
    two.user(later, c(2, 3), 'Turn the checkout review into a one-page summary for the board.')
    two.read(later, c(2, 3), rel, first)
    second_sha = two.write(later, c(2, 3), rel, second)
    second_line = two.reply(later, c(2, 3), f'Updated [review.md]({rel}) as a one-page board summary.')
    two.title(later, 'Board summary of the checkout review')
    words = ['accessibility', 'review']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    path = f'work/harbor/{rel}'
    question = task(w, 'Retrieve the version of the review that answered the original accessibility request, and identify '
                       'its recommendation.', words, 'value', field='recommendation')
    answer = dict(delivery=ref(one, path, first_line), sha256=first_sha, value='increase contrast',
                  later=dict(delivery=ref(two, path, second_line), sha256=second_sha, value='shorten summary'))
    library = dict(
        deliveries=[expect(one, path, first_line, sha256=first_sha, provenance='at_delivery', saved=True, number=1, of=2,
                           availability='saved_copy'),
                    expect(two, path, second_line, sha256=second_sha, provenance='at_delivery', saved=True, number=2,
                           of=2, availability='original')],
        disk={path: second_sha},
        find=[dict(words=words, paths=[path])])
    return question, gold(w, answer, library, ['mixed_occurrences', 'current_as_delivered'])


def t03(w):
    rng = w.rng
    w.projects()
    chart = w.claude('north')
    c = Cursor(rng, w.old())
    chart.user(0, c(), 'Chart the p95 latency for the ops dashboard.')
    chart.write(0, c(), 'out/latency.svg', svg('p95 latency, last 7 days', [rng.randint(20, 80) for _ in range(6)]))
    chart.reply(0, c(), 'Chart: [latency.svg](out/latency.svg).')
    chart.title(0, 'p95 latency chart')

    pr = w.claude('south')
    c = Cursor(rng, w.old())
    pr.user(0, c(), 'Write code review notes for the cache PR.')
    pr.write(0, c(), 'docs/cache-review.md', doc('Cache PR notes', rng, ['Eviction runs on every write.']))
    pr.reply(0, c(), 'Notes: [cache-review.md](docs/cache-review.md).')

    s = w.claude('south')
    c = Cursor(rng, -rng.uniform(470, 500))
    s.user(1, c(), 'Run the latency review on the checkout service and hand me the write-up, a chart and the fix.')
    s.text(1, c(), 'Profiling first.')
    t = c()
    s.bash(1, t, 'python3 scripts/profile.py --service checkout --out tmp/profile-scratch.txt',
           f'collected {rng.randint(3000, 6000)} samples -> tmp/profile-scratch.txt\np95 {rng.randint(380, 460)} ms')
    w.write(1, 'work/south/tmp/profile-scratch.txt', round(t + 1, 3),
            text=''.join(f'{rng.randint(80, 1900)}\n' for _ in range(40)))
    p95 = [rng.randint(30, 90) for _ in range(6)]
    files = {
        'out/review.md': doc('Checkout latency review', rng, [f'p95 is {max(p95) * 5} ms on /pay.',
                                                              'The connection pool is too small under load.']),
        'out/latency.svg': svg('checkout p95 by endpoint (ms)', p95),
        'out/fix.patch': ('--- a/src/checkout/pool.ts\n+++ b/src/checkout/pool.ts\n@@ -1,3 +1,3 @@\n'
                          f'-export const POOL_SIZE = 8\n+export const POOL_SIZE = {rng.choice([24, 32, 48])}\n'),
    }
    shas = {rel: s.write(1, c(), rel, text) for rel, text in files.items()}
    described = {'out/review.md': 'the write-up', 'out/latency.svg': 'p95 by endpoint', 'out/fix.patch': 'the pool fix'}
    order = list(files)
    rng.shuffle(order)
    line = s.reply(1, c(), 'The latency review is done:\n\n' + ''.join(
        f'- [{os.path.basename(rel)}]({rel}): {described[rel]}\n' for rel in order))
    s.user(1, c(20, 40), 'Also export the budget numbers to a CSV.')
    budget = s.write(1, c(), 'out/budget.csv', 'line,amount\n' + ''.join(
        f'{name},{rng.randint(100, 9000)}\n' for name in ('compute', 'storage', 'egress')))
    budget_line = s.reply(1, c(), 'Budget numbers: [budget.csv](out/budget.csv).')
    s.title(1, 'Checkout latency review')
    words = ['latency', 'review']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    paths = [f'work/south/{rel}' for rel in order]
    question = task(w, 'Which files were handed over in the reply to the latency review request?', words, 'files')
    answer = dict(reply=dict(session=s.id, log=s.log, line=line), files=paths,
                  excluded=[dict(path='work/south/out/budget.csv', why='named by the next reply'),
                            dict(path='work/south/tmp/profile-scratch.txt', why='named only in tool output')])
    library = dict(
        deliveries=[expect(s, f'work/south/{rel}', line, sha256=shas[rel], provenance='at_delivery', reply_line=line)
                    for rel in order]
        + [expect(s, 'work/south/out/budget.csv', budget_line, sha256=budget, reply_line=budget_line)],
        not_delivered=['work/south/tmp/profile-scratch.txt'],
        # The next reply's file matches too, through the session's title: a neighbour to tell apart.
        find=[dict(words=words, paths=paths + ['work/south/out/budget.csv'])])
    return question, gold(w, answer, library, ['tool_only_as_delivery', 'neighbour_as_member'])


def t04(w):
    rng = w.rng
    w.projects()
    rel = 'out/brief.md'
    a = w.claude('north')
    c = Cursor(rng, w.old())
    a.user(0, c(), 'Summarize our retry policy for the gateway team in a short brief.')
    brief = doc('Gateway retries', rng, ['Three attempts with exponential backoff.'])
    a.write(0, c(), rel, brief)
    a_line = a.reply(0, c(), f'The brief is in [brief.md]({rel}).')
    a.title(0, 'Gateway retry policy brief')

    retry = w.claude('south')
    c = Cursor(rng, w.old())
    retry.user(0, c(), 'Draft the retry policy for the South batch jobs.')
    retry.write(0, c(), 'docs/retry-policy.md', doc('Batch retries', rng, ['Jobs retry twice, then page.']))
    retry.reply(0, c(), 'Draft: [retry-policy.md](docs/retry-policy.md).')

    b = w.claude('north')
    c = Cursor(rng, -rng.uniform(470, 510))
    b.user(1, c(), 'Rework the brief into talking points for the board presentation.')
    b.read(1, c(), rel, brief)
    b.write(1, c(), rel, doc('Talking points', rng, ['Our retry policy cut gateway errors by half.',
                                                    'Next: the same policy for batch jobs.']))
    b_line = b.reply(1, c(), f'Talking points are in [brief.md]({rel}).')
    b.title(1, 'Board presentation talking points')

    signup = w.claude('south')
    c = Cursor(rng, w.old())
    signup.user(0, c(), 'Write a short brief on the new signup flow.')
    signup.write(0, c(), rel, doc('Signup flow brief', rng, ['Two steps instead of four.']))
    signup.reply(0, c(), f'Brief: [brief.md]({rel}).')

    deck = w.claude('south')
    c = Cursor(rng, -rng.uniform(200, 300))
    deck.user(1, c(), 'Build the slide outline for the board presentation.')
    deck.write(1, c(), 'out/board-deck.md', doc('Board deck outline', rng, ['Revenue', 'Hiring', 'Risks']))
    deck.reply(1, c(), 'Outline: [board-deck.md](out/board-deck.md).')
    words = ['retry', 'policy', 'board', 'presentation']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    path = f'work/north/{rel}'
    question = task(w, 'Find the delivery whose request mentions both retry policy and board presentation; if none is '
                       'evidenced in the supplied scope, explain.', words, 'delivery')
    answer = dict(found=False, scope='every session in the world, as the index reports it',
                  split=[dict(ref(a, path, a_line), phrase='retry policy'),
                         dict(ref(b, path, b_line), phrase='board presentation')],
                  note='The file exists and was delivered twice; no single request names both.')
    library = dict(
        deliveries=[expect(a, path, a_line, number=1, of=2), expect(b, path, b_line, number=2, of=2)],
        find=[dict(words=words, paths=[])])
    return question, gold(w, answer, library, ['false_join', 'false_global_absence'])


def t07(w):
    rng = w.rng
    w.projects()
    rel = 'templates/report-template.md'
    template = ('# Monthly report\n\n## Highlights\n\n## Metrics\n\n| Metric | Value | Change |\n|---|---|---|\n\n'
                f'## Risks\n\n## Next month\n\n<!-- template v{rng.randint(2, 9)} -->\n')
    other = template.replace('Monthly report', 'Quarterly review').replace('Next month', 'Next quarter')

    harbor = w.claude('harbor')
    c = Cursor(rng, w.old())
    harbor.user(0, c(), "Draft a report template for Harbor's quarterly reviews.")
    harbor_sha = harbor.write(0, c(), rel, other)
    harbor.reply(0, c(), f'Template: [report-template.md]({rel}).')

    north, south = w.claude('north'), w.claude('south')
    first, second = (north, south) if rng.random() < 0.5 else (south, north)
    shas, lines = {}, {}
    for session, start in ((first, -rng.uniform(480, 510)), (second, -rng.uniform(300, 340))):
        c = Cursor(rng, start)
        if session is north:
            session.user(1, c(), 'Create the monthly report template for North.')
        else:
            session.user(1, c(), "Set up a report template for South's monthly reporting.")
        shas[session.project] = session.write(1, c(), rel, template)
        lines[session.project] = session.reply(1, c(), f'Template: [report-template.md]({rel}).')
    words = ['report', 'template']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    question = task(w, "Do North and South share one work item because their report templates have the same hash?",
                    words, 'same_item', projects=['north', 'south'])
    answer = dict(same=False, sha256=shas['north'],
                  artifacts=[ref(north, f'work/north/{rel}', lines['north']),
                             ref(south, f'work/south/{rel}', lines['south'])],
                  note='Equal bytes at two paths in two projects: two artifacts, kept apart.')
    library = dict(
        deliveries=[expect(north, f'work/north/{rel}', lines['north'], sha256=shas['north'], of=1),
                    expect(south, f'work/south/{rel}', lines['south'], sha256=shas['south'], of=1),
                    expect(harbor, f'work/harbor/{rel}', sha256=harbor_sha, of=1)],
        find=[dict(words=words, paths=[f'work/{p}/{rel}' for p in ('north', 'south', 'harbor')])])
    assert shas['north'] == shas['south'] != harbor_sha
    return question, gold(w, answer, library, ['hash_merge'])


def t09(w):
    rng = w.rng
    w.projects()
    rel = 'out/forecast.md'

    def forecast(revenue, note):
        return (f'# Revenue forecast, next quarter\n\nrevenue: {revenue} k\nconfidence: {rng.choice(["low", "medium"])}\n\n'
                f'{note}\n')

    one, two = forecast(rng.randint(800, 900), 'Based on the current pipeline.'), None
    south = w.claude('south')
    c = Cursor(rng, w.old())
    south.user(0, c(), 'Draft the South revenue forecast.')
    south.write(0, c(), rel, forecast(rng.randint(300, 400), 'South region only.'))
    south.reply(0, c(), f'Forecast: [forecast.md]({rel}).')

    hiring = w.claude('north')
    c = Cursor(rng, w.old())
    hiring.user(0, c(), 'Write the hiring forecast for the platform team.')
    hiring.write(0, c(), 'out/hiring-forecast.md', doc('Platform hiring forecast', rng, ['Two backend roles in Q3.']))
    hiring.reply(0, c(), 'Hiring forecast: [hiring-forecast.md](out/hiring-forecast.md).')

    s = w.claude('north')
    c = Cursor(rng, -rng.uniform(470, 500))
    s.user(1, c(), 'Draft the revenue forecast for next quarter.')
    first = s.write(1, c(), rel, one)
    first_line = s.reply(1, c(), f'Forecast: [forecast.md]({rel}).')
    s.title(1, 'North revenue forecast')
    later = w.later(index=True)
    two = forecast(rng.randint(910, 990), 'Updated with the new pipeline numbers.')
    c = Cursor(rng, -18.0)
    s.user(later, c(2, 3), 'Update the forecast with the new pipeline numbers.')
    s.read(later, c(2, 3), rel, one)
    second = s.write(later, c(2, 3), rel, two)
    second_line = s.reply(later, c(2, 3), f'Updated [forecast.md]({rel}) with the new pipeline.')
    after = w.later(index=False)
    current = w.write(after, f'work/north/{rel}', -2.0, text=one)
    words = ['north', 'revenue', 'forecast']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    path = f'work/north/{rel}'
    question = task(w, "Does North's revenue forecast on disk match its most recent delivery, and which delivered version "
                       'does it match?', words, 'current_match', project='north')
    answer = dict(current_sha256=current, matches_latest=False,
                  latest=dict(ref(s, path, second_line), number=2, sha256=second),
                  matches=dict(ref(s, path, first_line), number=1, sha256=first),
                  note='A byte match with delivery 1; no rollback event is recorded.')
    library = dict(
        deliveries=[expect(s, path, first_line, sha256=first, provenance='at_delivery', number=1, of=2,
                           availability='original'),
                    expect(s, path, second_line, sha256=second, provenance='at_delivery', number=2, of=2,
                           availability='saved_copy')],
        disk={path: current},
        find=[dict(words=words, paths=[path])])
    assert current == first != second
    return question, gold(w, answer, library, ['latest_assumed_current'])


def t10(w):
    rng = w.rng
    w.projects()
    rel = 'out/memo.md'
    days = rng.randint(20, 40)
    reply_at = -days * DAY + 10 * 3600
    day = datetime.datetime.fromtimestamp(w.base + reply_at, datetime.timezone.utc)
    minutes = rng.randint(30, 45)
    logged = f'# Incident memo\n\nImpact: checkout errors for {minutes} minutes.\nCause: under investigation.\n'
    seen = (f'# Incident memo\n\nImpact: checkout errors for {minutes + rng.randint(3, 9)} minutes.\n'
            'Cause: an expired TLS certificate on the payments proxy.\nFollow-up: alert on certificate expiry.\n')

    timeline = w.claude('north')
    c = Cursor(rng, reply_at - rng.randint(2, 6) * DAY)
    timeline.user(0, c(), 'Collect the incident timeline from the pager logs.')
    timeline.write(0, c(), 'out/incident-timeline.md', doc('Incident timeline', rng, ['09:12 first page']))
    timeline.reply(0, c(), 'Timeline: [incident-timeline.md](out/incident-timeline.md).')

    s = w.claude('north')
    s.user(0, reply_at - 19 * 60, "Write the incident memo for this morning's outage.")
    s.text(0, reply_at - 18 * 60, "I'll draft it from the pager timeline.")
    s.bash(0, reply_at - 8 * 60, f"cat > {rel} <<'EOF'\n{logged}EOF", '', description='Write the memo')
    seen_sha = w.write(0, f'work/north/{rel}', reply_at - 5 * 60, text=seen)
    line = s.reply(0, reply_at, f'The incident memo is in [memo.md]({rel}).')
    s.title(0, 'Incident memo')

    launch = w.claude('south')
    c = Cursor(rng, -rng.uniform(400, 480))
    launch.user(1, c(), 'Write the launch memo for South.')
    launch.write(1, c(), rel, doc('Launch memo', rng, ['Launch is on Tuesday.']))
    launch.reply(1, c(), f'Memo: [memo.md]({rel}).')
    words = ['incident', 'memo']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    path = f'work/north/{rel}'
    at = history.iso(w.base + reply_at)
    question = task(w, f'Can the saved file establish the exact bytes of the incident memo delivered at 10:00 UTC on '
                       f'{day:%Y-%m-%d}?', words, 'provenance', at=at[:19] + 'Z')
    answer = dict(established=False, delivery=ref(s, path, line), delivered_at=at[:19] + 'Z',
                  provenance='first_seen_after_delivery', sha256=seen_sha, logged_input_sha256=sha256(logged),
                  mtime=history.iso(w.base + reply_at - 5 * 60)[:19] + 'Z',
                  note='Gleaner first read the file when the catalog was prepared, long after the reply. The modification '
                       'time before the reply and the logged write input do not establish the delivered bytes.')
    library = dict(
        deliveries=[expect(s, path, line, sha256=seen_sha, provenance='first_seen_after_delivery', saved=True,
                           observed_after_delivery=True)],
        disk={path: seen_sha},
        find=[dict(words=words, paths=[path])])
    assert seen_sha != sha256(logged)
    return question, gold(w, answer, library, ['current_as_delivered', 'certainty_from_mtime'])


def t12(w):
    rng = w.rng
    w.projects()
    rel, decoy = 'out/说明.md', 'out/说明-草稿.md'

    codex = w.codex('harbor', w.old(), 'Normalize export file names')
    c = Cursor(rng, codex.start)
    codex.turn(c(), 'Normalize the Unicode file names in the export folder.')
    codex.say(c(), 'Checking how the export names are spelled now.')
    codex.shell(c(), 'python3 -c "import os; print(os.listdir(\'export\'))"', "['café.csv', 'naïve.csv']")
    names = doc('Export file names', rng, ['All names are NFC.'])
    codex.shell(c(), f"cat > out/export-names.md <<'EOF'\n{names}EOF", '', files=[('out/export-names.md', names)])
    codex.final(c(), 'Normalized names are listed in [export-names.md](out/export-names.md).')

    readme = w.claude('north')
    c = Cursor(rng, w.old())
    readme.user(0, c(), 'Translate the README into Chinese for the partner team.')
    readme.write(0, c(), 'docs/说明.md', '# 说明\n\n北方网关、计费和合作伙伴 API。\n')
    readme.reply(0, c(), 'Translated: [说明.md](docs/说明.md).')

    changelog = w.claude('harbor')
    c = Cursor(rng, w.old())
    changelog.user(0, c(), 'Fix the heading levels in the changelog.')
    changelog.write(0, c(), 'docs/changelog.md', '# Changelog\n\n## 1.4\n\n- Faster export.\n')
    changelog.reply(0, c(), 'Fixed: [changelog.md](docs/changelog.md).')

    s = w.claude('harbor')
    c = Cursor(rng, -rng.uniform(470, 500))
    s.user(1, c(), 'Add a Unicode heading for the usage section (用法) to the Chinese guide.')
    s.text(1, c(), "I'll have a sub-agent draft the heading text while I check the slug code.")
    t = c()
    agent = Claude(w, 'harbor', subagent_of=s)
    draft = '# 说明\n\n## 用法（草稿）\n\n运行 `harbor export`。\n'
    agent.user(1, t + 1, 'Draft a 用法 heading and a one-line usage example for the Chinese guide.')
    agent.write(1, t + 3, decoy, draft)
    agent.text(1, t + 8, f'Draft written to [说明-草稿.md]({decoy}).')
    s.tool(1, t, 'Task', dict(description='Draft the 用法 heading', subagent_type='general-purpose',
                              prompt='Draft a 用法 heading and a one-line usage example for the Chinese guide.'),
           [dict(type='text', text=f'Draft written to [说明-草稿.md]({decoy}).')],
           dict(status='completed', content=[dict(type='text', text=f'Draft written to [说明-草稿.md]({decoy}).')],
                totalDurationMs=9100), after=10.0)
    c.t = t + 10
    s.read(1, c(), 'src/main.swift', PROJECT_SOURCES['harbor']['src/main.swift'])
    guide = '# 说明\n\n## 用法\n\n运行 `harbor export --out out/`，导出文件会写入 `out/`。\n'
    guide_sha = s.write(1, c(), rel, guide)
    first = s.reply(1, c(), 'The 用法 heading is in place, and its anchor resolves.')
    second = s.reply(1, c(0.2, 0.8), f'Guide: [说明.md]({rel}#用法). The slug comes from `src/main.swift:42`.', same=True)
    s.title(1, 'Unicode usage heading')
    words = ['unicode', 'heading']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    path = f'work/harbor/{rel}'
    question = task(w, 'Which artifact did the user-facing final reply deliver for the Unicode heading request?', words,
                    'delivery')
    answer = dict(delivery=ref(s, path, second), anchor='#用法', reply_lines=[first, second], sha256=guide_sha,
                  excluded=[dict(path=f'work/harbor/{decoy}', why="named by a sub-agent, not the reply to the person"),
                            dict(path='work/harbor/src/main.swift', why='a line reference (:42), not a hand-off')])
    library = dict(
        deliveries=[expect(s, path, second, sha256=guide_sha, provenance='at_delivery', anchor='#用法', reply_line=first)],
        not_delivered=[f'work/harbor/{decoy}', 'work/harbor/src/main.swift'],
        find=[dict(words=words, paths=[path])])
    return question, gold(w, answer, library, ['subagent_as_delivery', 'line_reference_as_delivery'])


def t16(w):
    rng = w.rng
    w.projects()
    name = f"{rng.choice(['brave', 'quiet', 'amber', 'swift', 'mellow'])}-{rng.choice(['otter', 'falcon', 'birch', 'comet'])}"
    tree = f'work/north/.claude/worktrees/{name}'
    branch = f'worktree-{name}'
    main_notes = doc('Demo walkthrough notes', rng, ['Start on the dashboard.', 'Show the export last.'])

    old = w.claude('north')
    c = Cursor(rng, w.old())
    old.user(0, c(), 'Write notes for the demo walkthrough.')
    main_sha = old.write(0, c(), 'out/demo-notes.md', main_notes)
    t = c()
    old.bash(0, t, 'git add out/demo-notes.md && git commit -m "Add the demo walkthrough notes"',
             '[main] Add the demo walkthrough notes\n 1 file changed')
    w.git(0, 'work/north', t + 1, 'add', 'out/demo-notes.md')
    w.git(0, 'work/north', t + 1, 'commit', '-q', '-m', 'Add the demo walkthrough notes')
    old_line = old.reply(0, c(), 'Notes: [demo-notes.md](out/demo-notes.md), committed on main.')

    start = -rng.uniform(470, 500)
    w.git(1, 'work/north', start - 5, 'worktree', 'add', '-q', '-b', branch, f'.claude/worktrees/{name}')
    s = w.claude('north', cwd=w.path(tree))
    c = Cursor(rng, start)
    s.user(1, c(), 'Render the demo video for the launch and write its notes.')
    t = c()
    s.bash(1, t, 'make demo-video OUT=out/demo.mov', 'rendered out/demo.mov (65.0 MiB)', after=20.0)
    head = f'\0\0\0\x14ftypqt  synthetic launch demo {w.hex(12)}\n'
    # Over the save limit, so Gleaner keeps its hash and no saved copy.
    video = w.write(1, f'{tree}/out/demo.mov', round(t + 10, 3), sparse=(head, SAVE_LIMIT + (1 << 20)))
    c.t = t + 20
    s.read(1, c(), 'out/demo-notes.md', main_notes)
    notes = doc('Launch demo notes', rng, ['Open on the new export screen.', 'The video runs 2:40.'])
    notes_sha = s.write(1, c(), 'out/demo-notes.md', notes)
    t = c()
    s.bash(1, t, 'git add out/demo.mov && git commit -m "Add the launch demo video"',
           f'[{branch}] Add the launch demo video\n 1 file changed, 0 insertions(+), 0 deletions(-)\n create mode 100644 out/demo.mov')
    w.git(1, tree, t + 1, 'add', 'out/demo.mov')
    w.git(1, tree, t + 1, 'commit', '-q', '-m', 'Add the launch demo video')
    line = s.reply(1, c(), 'Rendered [demo.mov](out/demo.mov) and updated [demo-notes.md](out/demo-notes.md) for the launch.')
    s.title(1, 'Launch demo video')
    after = w.later(index=False)
    w.git(after, 'work/north', -3.0, 'worktree', 'remove', '--force', f'.claude/worktrees/{name}')
    words = ['demo', 'video']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    mov, wt_notes = f'{tree}/out/demo.mov', f'{tree}/out/demo-notes.md'
    question = task(w, 'Recover the demo video and notes delivered from the now-deleted worktree, or state exactly what '
                       'survives.', words, 'recover')
    answer = dict(
        worktree=dict(path=tree, branch=branch, state='removed'),
        artifacts=[dict(ref(s, wt_notes, line), source='saved_copy', sha256=notes_sha),
                   dict(ref(s, mov, line), source='git', sha256=video,
                        restore='git worktree add at a commit on the branch that holds out/demo.mov',
                        note='Too large for a saved copy; Gleaner kept its hash only and cannot confirm the git version '
                             'is the delivered one without hashing it.')],
        excluded=[dict(path='work/north/out/demo-notes.md', sha256=main_sha,
                       why='the main folder\'s notes, a different file with different bytes')])
    library = dict(
        deliveries=[expect(s, wt_notes, line, sha256=notes_sha, provenance='at_delivery', saved=True,
                           availability='saved_copy', plan='ready'),
                    expect(s, mov, line, sha256=video, provenance='at_delivery', saved=False, availability='none',
                           plan='restore_from_git', restore_sha256=video),
                    expect(old, 'work/north/out/demo-notes.md', old_line, sha256=main_sha)],
        disk={mov: None, wt_notes: None, 'work/north/out/demo-notes.md': main_sha},
        find=[dict(words=words, paths=[mov, wt_notes])])
    assert notes_sha != main_sha
    return question, gold(w, answer, library, ['wrong_file_recovered', 'claimed_recovery'])


def t19(w):
    rng = w.rng
    w.projects()
    release = w.claude('north')
    c = Cursor(rng, w.old())
    release.user(0, c(), 'Write the release checklist for the mobile app.')
    release_sha = release.write(0, c(), 'docs/checklist.md', doc('Release checklist', rng, ['Bump the build number.']))
    release_line = release.reply(0, c(), 'Checklist: [checklist.md](docs/checklist.md).')

    labels = w.claude('south')
    c = Cursor(rng, w.old())
    labels.user(0, c(), 'Fix the accessibility labels on the signup form.')
    labels.write(0, c(), 'src/signup.tsx', 'export function Signup() {\n  return <form aria-label="Create your account" />\n}\n')
    labels.reply(0, c(), 'Fixed in [signup.tsx](src/signup.tsx).')

    s = w.claude('south')
    c = Cursor(rng, -rng.uniform(470, 500))
    s.user(1, c(), 'Draft an accessibility checklist for the release.')
    s.text(1, c(), "I'll put it with the other docs.")
    checklist = doc('Accessibility checklist', rng, ['Every control has a label.', 'Contrast is at least 4.5:1.',
                                                     'Focus order follows the screen.'])
    sha = s.write(1, c(), 'docs/checklist.md', checklist)
    line = s.reply(1, c(), 'The accessibility checklist is ready in `checklist.md`, grouped by screen.')
    s.title(1, 'Accessibility checklist')
    words = ['accessibility', 'checklist']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    question = task(w, 'Which file did the final reply call the accessibility checklist?', words, 'delivery')
    answer = dict(found=False, scope='the catalog admits no bare file name (SPEC §9)',
                  raw=dict(session=s.id, log=s.log, line=line, mention='checklist.md', syntax='code',
                           path='work/south/docs/checklist.md', sha256=sha,
                           basis='the session cwd, the Write call in the same turn and the folder listing'),
                  excluded=[dict(path='work/north/docs/checklist.md', why='another project, another request')])
    library = dict(
        deliveries=[expect(release, 'work/north/docs/checklist.md', release_line, sha256=release_sha)],
        not_delivered=['work/south/docs/checklist.md', 'work/south/checklist.md'],
        disk={'work/south/docs/checklist.md': sha},
        find=[dict(words=words, paths=[])])
    return question, gold(w, answer, library, ['false_global_absence', 'mention_as_delivery'])


def t20(w):
    rng = w.rng
    w.projects()
    cost = w.claude('south')
    c = Cursor(rng, -rng.uniform(400, 480))
    cost.user(1, c(), 'Plot the cloud cost by month.')
    cost.write(1, c(), 'out/plot.svg', svg('cloud cost by month', [rng.randint(20, 90) for _ in range(6)]))
    cost.reply(1, c(), 'Plot: [plot.svg](out/plot.svg).')

    slo = w.claude('north')
    c = Cursor(rng, w.old())
    slo.user(0, c(), 'Write the latency SLO doc.')
    slo.write(0, c(), 'docs/slo.md', doc('Latency SLO', rng, ['p99 under 800 ms.']))
    slo.reply(0, c(), 'SLO doc: [slo.md](docs/slo.md).')

    s = w.codex('harbor', w.old(), 'Export job latency')
    c = Cursor(rng, s.start)
    s.turn(c(), 'Profile the export job and plot the latency distribution.')
    s.say(c(), 'Profiling the export job first.')
    share = rng.randint(60, 80)
    s.shell(c(), 'python3 scripts/profile_export.py --runs 20', f'20 runs, median 3.4 s; {share}% in serialize_rows')
    plot = svg('export latency (s)', [rng.randint(20, 90) for _ in range(6)])
    (plot_sha,) = s.shell(c(), 'python3 scripts/plot_latency.py --out tmp/plot.svg', 'wrote tmp/plot.svg (12 KB)',
                          files=[('tmp/plot.svg', plot)])
    s.shell(c(), 'python3 scripts/plot_latency.py --by-region --out tmp/plot2.svg', None)
    summary = doc('Export job profile', rng, [f'{share}% of the time is spent serializing rows.'])
    s.shell(c(), f"cat > out/summary.md <<'EOF'\n{summary}EOF", '', files=[('out/summary.md', summary)])
    s.final(c(), 'The export job spends most of its time serializing rows; the findings are in [summary.md](out/summary.md).')
    words = ['latency', 'plot']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    question = task(w, 'Where was the latency plot actually generated, and was it handed over in the final reply?', words,
                    'handed_over')
    answer = dict(handed_over=False, generated=dict(path='work/harbor/tmp/plot.svg', sha256=plot_sha, session=s.id, log=s.log),
                  attempted=dict(path='work/harbor/tmp/plot2.svg', why='a call with no result; the file does not exist'),
                  reply_delivered=['work/harbor/out/summary.md'])
    library = dict(
        deliveries=[expect(s, 'work/harbor/out/summary.md', sha256=sha256(summary))],
        not_delivered=['work/harbor/tmp/plot.svg', 'work/harbor/tmp/plot2.svg'],
        disk={'work/harbor/tmp/plot.svg': plot_sha, 'work/harbor/tmp/plot2.svg': None},
        find=[dict(words=words, paths=['work/harbor/out/summary.md'])])
    return question, gold(w, answer, library, ['tool_only_as_delivery', 'attempt_as_result'])


def t21(w):
    rng = w.rng
    w.projects()
    search = w.claude('south')
    c = Cursor(rng, w.old())
    search.user(0, c(), 'Plan the rollback of the search index rebuild.')
    search.write(0, c(), 'out/rollback-plan.md', doc('Search index rollback', rng, ['Point reads at the old index.']))
    search.reply(0, c(), 'Plan: [rollback-plan.md](out/rollback-plan.md).')

    queue = w.claude('north')
    c = Cursor(rng, w.old())
    queue.user(0, c(), 'Record the decision on queue retries.')
    queue.write(0, c(), 'docs/decisions/queue.md', doc('Decision: queue retries', rng, ['Retry twice, then dead-letter.']))
    queue.reply(0, c(), 'Recorded in [queue.md](docs/decisions/queue.md).')

    cache = w.claude('south')
    c = Cursor(rng, -rng.uniform(400, 480))
    cache.user(1, c(), 'Decide on the cache eviction policy and record the decision.')
    cache.write(1, c(), 'docs/decision-cache.md', doc('Decision: cache eviction', rng, ['LRU with a 10 minute TTL.']))
    cache.reply(1, c(), 'Decision recorded: [decision-cache.md](docs/decision-cache.md).')

    s = w.claude('north')
    c = Cursor(rng, w.old())
    s.user(0, c(), 'Plan the rollback of the billing migration.')
    plan = doc('Billing migration rollback', rng, ['Stop the writers.', 'Restore the snapshot.', 'Replay the queue.'])
    s.write(0, c(), 'out/rollback-plan.md', plan)
    line = s.reply(0, c(), 'The rollback plan is in [rollback-plan.md](out/rollback-plan.md).')
    s.title(0, 'Billing migration rollback')
    s.user(0, c(1800, 7200), 'Should we roll back or roll forward? Make the call and record it.')
    s.text(0, c(), 'Checking the migration status first.')
    s.bash(0, c(), "psql -c 'select step, state from migrations order by step'",
           f'applied: {rng.randint(11, 14)} of 15 steps\nfailed: step 15 (backfill)')
    readable = s.lines
    # The next record was being written when the log was copied: it ends mid-record, before its text.
    record = history.line(dict(parentUuid=s.parent, isSidechain=False, userType='external', cwd=s.cwd, sessionId=s.id,
                               version=CLAUDE_VERSION, gitBranch='main', message=dict(
                                   model=CLAUDE_MODEL, id='msg_01' + w.token(22), type='message', role='assistant',
                                   content=[dict(type='text', text='Decision: ' + 'x' * 80)])))
    s.raw(0, record[:record.index('"content"') + 12])
    words = ['billing', 'rollback', 'decision']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    question = task(w, "Is there a later decision about the billing migration rollback in that request's session?", words,
                    'decision')
    answer = dict(status='unknown', session=s.id, log=s.log, readable_lines=readable, malformed_line=readable + 1,
                  delivered_before=[dict(ref(s, 'work/north/out/rollback-plan.md', line))],
                  note='No decision in lines 1-%d; the log ends mid-record at line %d, so what followed is unknown. Other '
                       'sessions record unrelated decisions.' % (readable, readable + 1))
    library = dict(
        sources={'claude-code': dict(state='read_with_problems', partial_logs=1), 'codex': dict(state='read', partial_logs=0)},
        deliveries=[expect(s, 'work/north/out/rollback-plan.md', line)],
        find=[dict(words=words, paths=[])],
        raw=[dict(log=s.log, lines=readable + 1, last_line_complete=False)])
    return question, gold(w, answer, library, ['false_global_absence', 'invented_decision'])


def t22(w):
    rng = w.rng
    w.projects()
    api = w.claude('north')
    c = Cursor(rng, w.old())
    api.user(0, c(), 'Write the API overview for the partner docs.')
    api.read(0, c(), 'openapi.yaml', PROJECT_SOURCES['north']['openapi.yaml'])
    api.write(0, c(), 'docs/api-overview.md', doc('Partner API overview', rng, ['Version 2.3, OAuth only.']))
    api.reply(0, c(), 'Overview: [api-overview.md](docs/api-overview.md).')

    review = w.codex('north', w.old(), 'Design spec review')
    c = Cursor(rng, review.start)
    review.turn(c(), 'Summarize the review comments on the design spec.')
    notes = doc('Design spec review', rng, ['Reviewers want the error model settled first.'])
    review.shell(c(), f"cat > out/spec-review.md <<'EOF'\n{notes}EOF", '', files=[('out/spec-review.md', notes)])
    review.final(c(), 'Summary: [spec-review.md](out/spec-review.md).')

    billing = w.claude('north')
    c = Cursor(rng, -rng.uniform(400, 480))
    billing.user(1, c(), 'Update the billing notes in the specs folder.')
    billing.write(1, c(), 'docs/specs/billing.md', doc('Billing notes', rng, ['Invoices close on the first.']))
    billing.reply(1, c(), 'Updated [billing.md](docs/specs/billing.md).')

    south = w.claude('south')
    c = Cursor(rng, w.old())
    south.user(0, c(), 'Export the product spec as a PDF for the partners.')
    t = c()
    south.bash(0, t, 'pandoc docs/product-spec.md -o out/spec.pdf', '')
    spec_sha = w.write(0, 'work/south/out/spec.pdf', round(t + 1, 3), text=pdf('South product spec'))
    spec_line = south.reply(0, c(), 'The PDF is at [spec.pdf](out/spec.pdf).')
    words = ['spec.pdf']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    north = [s for s in w.sessions if s.project == 'north']
    question = task(w, "Was spec.pdf referenced in North's sessions?", words, 'referenced', project='north', name='spec.pdf')
    answer = dict(referenced=False, scope=dict(project='north', sessions=[dict(id=s.id, provider=s.provider, log=s.log)
                                                                          for s in north]),
                  elsewhere=[ref(south, 'work/south/out/spec.pdf', spec_line)],
                  note='No record of any North session names spec.pdf; South delivered one, so it is not absent everywhere.')
    library = dict(
        deliveries=[expect(south, 'work/south/out/spec.pdf', spec_line, sha256=spec_sha)],
        find=[dict(words=words, project='north', paths=[]), dict(words=words, paths=['work/south/out/spec.pdf'])],
        raw=[dict(log=s.log, absent='spec.pdf') for s in north] + [dict(log=south.log, present='spec.pdf')])
    return question, gold(w, answer, library, ['false_global_absence'])


def t23(w):
    rng = w.rng
    w.projects()
    rel = 'out/plan.md'
    archived = 'archive/ledger-migration-plan.md'
    sprint = w.claude('south')
    c = Cursor(rng, w.old())
    sprint.user(0, c(), 'Plan the next sprint for the South team.')
    sprint.write(0, c(), rel, doc('Sprint plan', rng, ['Finish the signup flow.']))
    sprint.reply(0, c(), f'Sprint plan: [plan.md]({rel}).')

    s = w.claude('north')
    c = Cursor(rng, -rng.uniform(470, 500))
    s.user(1, c(), 'Draft the ledger migration plan.')
    s.read(1, c(), 'src/billing/ledger.ts', PROJECT_SOURCES['north']['src/billing/ledger.ts'])
    plan = doc('Ledger migration plan', rng, [f'Move {rng.randint(3, 9)} tables to the new ledger schema.',
                                              'Dual-write for one week.', 'Cut over on a Monday.'])
    delivered = s.write(1, c(), rel, plan)
    t = c()
    s.bash(1, t, f'git add {rel} && git commit -m "Add the ledger migration plan"',
           '[main] Add the ledger migration plan\n 1 file changed')
    w.git(1, 'work/north', t + 1, 'add', rel)
    w.git(1, 'work/north', t + 1, 'commit', '-q', '-m', 'Add the ledger migration plan')
    line = s.reply(1, c(), f'The ledger migration plan is in [plan.md]({rel}).')
    s.title(1, 'Ledger migration plan')

    after = w.later(index=False)
    w.op(after, op='mkdir', path='work/north/archive')
    w.git(after, 'work/north', -4.0, 'mv', rel, archived)
    w.git(after, 'work/north', -4.0, 'commit', '-q', '-m', 'Archive the ledger migration plan')
    offsite = doc('Offsite plan', rng, ['Day one: roadmap.', 'Day two: hack day.'])
    current = w.write(after, f'work/north/{rel}', -3.0, text=offsite)
    w.git(after, 'work/north', -2.0, 'add', rel)
    w.git(after, 'work/north', -2.0, 'commit', '-q', '-m', 'Start the offsite plan')
    words = ['ledger', 'migration', 'plan']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    path = f'work/north/{rel}'
    pointer = dict(delivery=delivery_id(w.path(s.log), line, w.path(path)), name='plan.md', sha256=delivered,
                   path=w.path(path), evidence=dict(log=w.path(s.log), line=line))
    question = task(w, 'Resolve the delivered plan using this catalog pointer and verify the version.', words, 'verify',
                    pointer=pointer)
    answer = dict(original=False, saved_copy=True, delivery=ref(s, path, line), delivered_sha256=delivered,
                  current_sha256=current, moved_to=dict(path=f'work/north/{archived}', sha256=delivered,
                                                        basis='git history renames out/plan.md to the archive'),
                  note='The path now holds the offsite plan; the delivered version is the saved copy.')
    library = dict(
        deliveries=[dict(expect(s, path, line, sha256=delivered, provenance='at_delivery', saved=True,
                                availability='saved_copy', plan='ready'),
                         id=pointer['delivery'], verify=dict(original=False, saved_copy=True))],
        disk={path: current, f'work/north/{archived}': delivered},
        find=[dict(words=words, paths=[path])])
    assert current != delivered
    return question, gold(w, answer, library, ['current_as_delivered', 'stale_pointer_trusted'])


def t25(w):
    rng = w.rng
    w.projects()
    rel = 'out/kpis.csv'

    def table(rows):
        return 'kpi,value\n' + ''.join(f'{k},{v}\n' for k, v in rows)

    weekly = w.claude('north')
    c = Cursor(rng, w.old())
    weekly.user(0, c(), 'Export the weekly KPI table.')
    weekly.write(0, c(), rel, table([('signups', rng.randint(100, 300)), ('churn', rng.randint(1, 9))]))
    weekly.reply(0, c(), f'KPIs: [kpis.csv]({rel}).')

    rows = [('revenue_k', rng.randint(800, 990)), ('active_accounts', rng.randint(4000, 6000)),
            ('nps', rng.randint(20, 60))]
    s = w.claude('south')
    c = Cursor(rng, -rng.uniform(470, 500))
    s.user(1, c(), 'Export the quarterly KPI table for South.')
    s.bash(1, c(), 'python3 scripts/kpis.py --quarter', 'exported 3 KPIs')
    delivered = s.write(1, c(), rel, table(rows))
    line = s.reply(1, c(), f'KPI table: [kpis.csv]({rel}).')
    s.title(1, 'Quarterly KPI export')
    words = ['quarterly', 'kpi']
    w.decoys(words, rng.randint(1, 3), rng.randint(1, 2))

    drifted = table([(k, v + (7 if k == 'revenue_k' else 0)) for k, v in rows] + [('refunds_k', rng.randint(5, 30))])
    path = f'work/south/{rel}'
    question = task(w, 'Provide the bytes matching the delivered quarterly KPI table and explain any failed verification.',
                    words, 'bytes')
    answer = dict(sha256=delivered, delivery=ref(s, path, line), drifted_sha256=sha256(drifted),
                  accept=['bytes hashing to sha256, with where they came from',
                          'an honest failure naming the change at the path'],
                  note='The file is rewritten while the policy works (drift.json); the new bytes are not the delivery.')
    library = dict(
        deliveries=[expect(s, path, line, sha256=delivered, provenance='at_delivery', saved=True)],
        disk={path: delivered},
        find=[dict(words=words, paths=[path])],
        drift=dict(path=path, handoff_sha256=delivered, verify=dict(original=False, saved_copy=True)))
    extra = dict(drift={'kpis.csv': drifted},
                 hook=dict(trigger=dict(after_output_containing=delivered),
                           write=dict(path=path, source='drift/kpis.csv'),
                           note='Once per episode: after the first command whose standard output holds the delivered '
                                "bytes' sha256, so the policy has seen the file verified, and before its next command, "
                                'the runner copies the source over the path. The same hook runs for every policy.'))
    return question, gold(w, answer, library, ['current_as_delivered']), extra


BUILDERS = dict(T01=t01, T02=t02, T03=t03, T04=t04, T07=t07, T09=t09, T10=t10, T12=t12, T16=t16, T19=t19, T20=t20,
                T21=t21, T22=t22, T23=t23, T25=t25)


def dump(path, value):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write('\n')


def generate(seed, out, tasks=TASKS):
    """Writes the worlds for `seed` under `out` (<root>/seed-<n>), one folder per task, and their
    gold under history.gold_folder; returns the world folders."""
    out = history.place(out)
    folders = []
    for name in tasks:
        folder = os.path.join(out, name)
        gold_dir = history.gold_folder(folder)
        for made in (folder, gold_dir):
            if os.path.exists(made):
                raise SystemExit(f'{made} exists: a world is written once, into a new folder')
        os.makedirs(folder)
        os.makedirs(gold_dir)
        world = World(name, os.path.join(folder, 'world'), random.Random(f'gleaner-e0:{seed}:{name}'))
        built = BUILDERS[name](world)
        question, expected = built[:2]
        world.finish(gold_dir)
        dump(os.path.join(folder, 'task.json'), question)
        dump(os.path.join(gold_dir, 'gold.json'), dict(expected, seed=seed))
        if len(built) > 2:
            extra = built[2]
            os.makedirs(os.path.join(gold_dir, 'drift'))
            for file, text in extra['drift'].items():
                with open(os.path.join(gold_dir, 'drift', file), 'w', encoding='utf-8') as f:
                    f.write(text)
            dump(os.path.join(gold_dir, 'drift.json'), extra['hook'])
        folders.append(folder)
    return folders


def main():
    if len(sys.argv) != 3 or not sys.argv[1].lstrip('-').isdigit():
        raise SystemExit(__doc__)
    seed = int(sys.argv[1])
    for folder in generate(seed, os.path.join(sys.argv[2], f'seed-{seed}')):
        print(folder)


if __name__ == '__main__':
    main()
