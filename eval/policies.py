#!/usr/bin/env python3
"""The two scripted policies of evaluation E0 (docs/design/evaluation-e0.md, "Policies").

    eval/policies.py R|G

Each policy is a generic function of task.json: its `words`, `asks` and the fields `asks` uses
(`project`, `projects`, `field`, `at`, `pointer`). Nothing here names a task, a path or an answer.

A policy runs as a subprocess of run.py and reads only through it. The runner's first line on
stdin is {"task", "home", "scratch"}. Each command then goes to the runner as one JSON line on
stdout, {"argv": [...]} or {"sh": "..."}, run in the home folder; the runner answers with
{"status", "stdout", "stderr"}. So the runner counts every byte read and every command, and can
change a file between two commands, as the drift hook does. The policy's last line is {"answer": {...}}.

- R, the locked raw recipe:
  1. `rg` over the log folders for the typed words: one pipeline that keeps the logs holding
     every word (one listing per word only to weigh partial matches: for a decision, or to
     explain a negative), and Codex titles from its session index;
  2. `jq` to project the candidate logs' records and take the matching turn's request and final
     reply;
  3. each path the reply names, resolved against its record's cwd;
  4. the file read and hashed with `shasum -a 256`, the turn's logged write of it hashed the
     same way, and `git -C … log` for a file that is gone.
- G: `gleaner find`; then `show`, `read`, `verify` or `handoff` as the question needs, and a raw
  read of the delivering session's log for what the catalog does not record (tool output, later
  turns). Each gleaner answer is projected with `jq` to the fields G reads, the home folder
  written ~, as R projects its logs. It falls back to R when the index reports incomplete
  sources or find returns nothing, and never states an absence beyond the scope it reports.
"""
import collections
import datetime
import hashlib
import json
import os
import re
import shlex
import sys
import urllib.parse

LOG_ROOTS = ('.claude/projects', '.codex/sessions')
LOG_GLOBS = ('-g', '*.jsonl', '-g', '!**/subagents/**')
# Codex keeps its session titles in one index beside its sessions; this finds it when it is there.
SESSION_INDEX = ('-g', 'session_index.jsonl', '.codex')

# One line per record that matters, for both agents' logs: requests, assistant text, tool calls
# and results, titles. The home folder is written ~, and long commands and outputs are cut.
PROJECTION = r'''
def short: if type != "string" then . elif . == $home then "~" else split($home + "/") | join("~/") end;
def clip: if type == "string" and length > 240 then .[:240] + "…" else . end;
def body: if type == "string" then . elif type == "array" then [.[] | if type == "object" then (.text // "") else tostring end] | join("") else tostring end;
def at: {l: input_line_number, t: .timestamp};
if has("payload") then
  .payload as $p
  | if .type == "session_meta" then {l: input_line_number, k: "meta", id: $p.id, cwd: ($p.cwd | short), src: $p.thread_source}
    elif .type == "turn_context" then {l: input_line_number, k: "turn", cwd: ($p.cwd | short)}
    elif .type != "response_item" or .metadata.inherited_user_message == true then empty
    elif $p.type == "message" and $p.role == "user" then
      ($p.internal_chat_message_metadata_passthrough.content_item_kinds // []) as $kinds
      | [range($p.content | length) | select($kinds[.] == "user.text") | $p.content[.].text] as $typed
      | if ($typed | length) > 0 then at + {k: "req", text: ($typed | join("\n") | short)} else empty end
    elif $p.type == "message" and $p.role == "assistant" then
      at + {k: "say", final: ($p.phase == "final_answer"), text: ([$p.content[]? | .text // ""] | join("\n\n") | short)}
    elif $p.type == "function_call" then
      at + {k: "tool", id: $p.call_id, name: $p.name,
            cmd: (($p.arguments | fromjson? | .command | if type == "array" then .[-1] else . end) // $p.arguments | short | clip)}
    elif $p.type == "function_call_output" then
      at + {k: "res", ids: [$p.call_id], out: (($p.output | fromjson? | .output) // $p.output | tostring | short | clip)}
    else empty end
elif .isSidechain == true then empty
elif .type == "user" then
  if (.message.content | type) == "array" and any(.message.content[]; .type? == "tool_result") then
    at + {k: "res", ids: [.message.content[] | select(.type? == "tool_result") | .tool_use_id],
          err: any(.message.content[]; .is_error? == true),
          out: ([.message.content[] | select(.type? == "tool_result") | .content | body] | join("\n") | short | clip)}
  elif .isMeta == true or .isCompactSummary == true then empty
  else at + {k: "req", cwd: (.cwd | short), human: (if .origin.kind? then .origin.kind == "human" else null end),
             text: (.message.content | body | short)}
  end
elif .type == "assistant" then
  . as $r | (.message.content // [])[]
  | if .type == "text" then ($r | at) + {k: "say", cwd: ($r.cwd | short), text: (.text | short)}
    elif .type == "tool_use" then ($r | at) + {k: "tool", cwd: ($r.cwd | short), id, name,
          path: ((.input.file_path // .input.notebook_path) | short), cmd: ((.input.command // .input.description) | short | clip)}
    else empty end
elif .type == "ai-title" then {l: input_line_number, k: "title", text: .aiTitle}
elif .type == "custom-title" then {l: input_line_number, k: "title", text: .customTitle, custom: true}
else empty end
'''

# Each gleaner answer, cut to the fields the gleaner policy reads, with the home folder written ~:
# the index's scope (each source's state and partial logs), and for each delivery its reference,
# project name, request and time. The bytes read for each command are what this prints.
G_PROJECTION = r'''
def short: if type != "string" then . elif . == $home then "~" else split($home + "/") | join("~/") end;
def ref: del(.name);
walk(if type == "string" then short else . end)
| if has("index") then .index.sources |= map_values({state, partial_logs}) else . end
| if has("results") then .results |= map(del(.kind, .project.folder) | .reference |= ref) else . end
| if has("deliveries") then del(.reference, .request, .reply, .delivered_at, .number, .kind, .project, .on_disk.checked_at)
    | .deliveries |= map(del(.delivered_at) | .reference |= ref) else . end
| if has("reference") then .reference |= ref else . end
| del(.range, .size)
'''

# The command a tool call ran, from either agent's record.
COMMAND = ('if has("payload") then (.payload.arguments | fromjson | .command | if type == "array" then .[-1] else . end) '
           'else (.message.content[] | select(.type == "tool_use") | .input.command) end')
# A Write call's full content.
WRITTEN = '.message.content[] | select(.type == "tool_use") | .input.content'
# The body of a here-document: the lines after the one that opens it, up to its delimiter.
HEREDOC_BODY = 'f { if ($0 == d) exit; print; next } index($0, "<<") { f = 1 }'

# Policy logic only from here on: the commands above, the file system through them.

Result = collections.namedtuple('Result', 'status out err')


class Shell:
    """Commands through the runner: each request one JSON line out, each answer one JSON line in."""

    def __init__(self, inbox, outbox):
        self.inbox = inbox
        self.outbox = outbox

    def _ask(self, request):
        self.outbox.write(json.dumps(request, ensure_ascii=False) + '\n')
        self.outbox.flush()
        reply = json.loads(self.inbox.readline())
        return Result(reply['status'], reply['stdout'], reply['stderr'])

    def run(self, argv, phase='raw'):
        return self._ask(dict(argv=list(argv), phase=phase))

    def sh(self, script, phase='raw'):
        return self._ask(dict(sh=script, phase=phase))


def q(text):
    return shlex.quote(text)


def seconds(stamp):
    """An ISO 8601 time as seconds since the epoch; None when there is none."""
    if not stamp:
        return None
    return datetime.datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()


def now():
    """This moment in UTC, as the agents write times."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def lower(words):
    return [word.lower() for word in words]


def count(words, text):
    text = text.lower()
    return sum(1 for word in words if word in text)


def field_value(text, field):
    """The value of a `field: value` line, ignoring case and list or heading marks."""
    pattern = re.compile(r'^[\s>*#-]*' + re.escape(field) + r'\s*:\s*(.+?)\s*$', re.IGNORECASE | re.MULTILINE)
    match = pattern.search(text or '')
    return match.group(1) if match else None


# Mentions in a reply

LINK = re.compile(r'(!?)\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
CODE = re.compile(r'`([^`\n]+)`')
FENCE = re.compile(r'^(`{3,}|~{3,}).*?(?:^\1[`~]*\s*$|\Z)', re.MULTILINE | re.DOTALL)
BARE = re.compile(r'(?<![\w/.~-])((?:~|/)[\w.~/-]*\.[A-Za-z][A-Za-z0-9]{0,7})(?![\w/])')
LINE_ANCHOR = re.compile(r'^(?:L\d+(?:-L?\d+)?|\d+(?::\d+)?)$')
FILE_NAME = re.compile(r'^[^\s]*[^\s/]\.[A-Za-z][A-Za-z0-9]{0,7}$')
PATH_TOKEN = re.compile(r'(?<![\w/.~-])((?:~/|/|\.{1,2}/)?(?:[\w.-]+/)*[\w-][\w.-]*\.[A-Za-z][A-Za-z0-9]{0,7})(?![\w/])')
OUTPUT_FLAG = re.compile(r'(?:--out(?:put)?|-o)[ =](\S+)')
REDIRECT = re.compile(r'(?<![<>&\d])>{1,2}\s*([^\s<>|&;]+)')
HEREDOC = re.compile(r'(?:cat|tee)\s+(?:-a\s+)?>{0,2}\s*([^\s<>|&;]+)\s*<<-?\s*[\'"]?(\w+)[\'"]?')


def mentions(text):
    """The paths a reply names, in order: {target, syntax, anchor, claim}. A link or image hands a
    file over; so does inline code or a bare path that names a folder. A line anchor makes any of
    them a reference into code, and a bare file name in code is only a mention (SPEC §9).
    Fenced blocks are examples, not hand-offs."""
    text = FENCE.sub('', text)
    found = []

    def add(target, syntax):
        anchor = None
        if syntax in ('link', 'image'):
            if re.match(r'^[a-z][a-z0-9+.-]*:', target) and not target.startswith('file://'):
                return
            target, _, fragment = target.partition('#')
            target = urllib.parse.unquote(target.removeprefix('file://localhost').removeprefix('file://'))
            anchor = '#' + urllib.parse.unquote(fragment) if fragment else None
        match = re.search(r':(\d+(?::\d+)?)$', target)
        if match:
            target, anchor = target[:match.start()], ':' + match.group(1)
        if not target or (syntax != 'link' and syntax != 'image' and not FILE_NAME.match(target)):
            return
        line = anchor is not None and LINE_ANCHOR.match(anchor.lstrip('#:'))
        if line:
            claim = 'line_reference'
        elif syntax in ('link', 'image') or '/' in target.rstrip('/'):
            claim = 'delivery'
        else:
            claim = 'mention'
        found.append(dict(target=target, syntax=syntax, anchor=anchor, claim=claim))

    rest = []
    last = 0
    for match in LINK.finditer(text):
        rest.append(text[last:match.start()])
        last = match.end()
        add(match.group(3), 'image' if match.group(1) else 'link')
    rest.append(text[last:])
    rest = ''.join(rest)
    spans = []
    for match in CODE.finditer(rest):
        spans.append(match.span())
        add(match.group(1).strip(), 'code')
    prose = ''.join(ch if not any(a <= i < b for a, b in spans) else ' ' for i, ch in enumerate(rest))
    for match in BARE.finditer(prose):
        add(match.group(1), 'bare')
    return found


# The raw policy

class Log:
    """A log as the projection read it: its records, and the first line it could not read."""

    def __init__(self, path, records, broken):
        self.path = path
        self.records = records
        self.broken = broken


class Turn:
    """A request and what followed it, up to the next request."""

    def __init__(self, log, request, cwd, session):
        self.log = log
        self.request = request
        self.cwd = cwd
        self.session = session
        self.title = None
        self.records = []

    @property
    def tools(self):
        return [r for r in self.records if r['k'] == 'tool']

    @property
    def results(self):
        return {i: r for r in self.records if r['k'] == 'res' for i in r.get('ids', [])}

    @property
    def replies(self):
        """The final reply: Codex marks it; for Claude Code it is the text after the last tool call."""
        says = [r for r in self.records if r['k'] == 'say']
        if any('final' in r for r in says):
            return [r for r in says if r.get('final')]
        last_tool = max((r['l'] for r in self.tools), default=0)
        return [r for r in says if r['l'] > last_tool]

    @property
    def end(self):
        """The time of the final reply, or of the turn's last record."""
        replies = self.replies
        stamps = [seconds(r.get('t')) for r in (replies or self.records) if r.get('t')]
        return max(stamps) if stamps else seconds(self.request.get('t'))


class Raw:
    """R: the locked raw recipe. G uses it too, for its fallback and its raw reads."""

    def __init__(self, shell, task, home, scratch):
        self.shell = shell
        self.task = task
        self.home = home
        self.scratch = scratch
        self.words = lower(task['words'])
        self.logs = {}
        self.titles = {}
        self.observed = {}
        self.unreadable = []
        self.written = 0
        self.clipped = 0

    # Commands

    def run(self, *argv):
        return self.shell.run(argv)

    def diagnostics(self):
        """What this policy saw cut short: fields its projection clipped at 240 characters."""
        return dict(clipped_fields=self.clipped)

    def sh(self, script):
        return self.shell.sh(script)

    # Paths

    def expand(self, path):
        if path is None:
            return None
        if path == '~' or path.startswith('~/'):
            path = self.home + path[1:]
        return os.path.normpath(path)

    def resolve(self, target, cwd):
        target = self.expand(target) if target.startswith('~') else target
        return os.path.normpath(target if os.path.isabs(target) else os.path.join(cwd, target))

    def project_of(self, cwd):
        """The folders of a cwd below the home folder: a project is named by one of them."""
        rel = os.path.relpath(cwd, self.home) if cwd else ''
        return [] if rel.startswith('..') else rel.split(os.sep)

    def in_project(self, cwd, project):
        return project.lower() in [part.lower() for part in self.project_of(cwd)]

    # Step 1: rg over the log folders

    def search(self, words, need_all=True):
        """Which logs hold the words, sub-agent transcripts left out, each with the words it holds;
        a Codex session's title counts as its own. With `need_all`, one pipeline keeps only the
        logs that hold every word; otherwise each word is listed on its own, to weigh logs that
        hold some of them."""
        titles = self.codex_titles(words)
        found = collections.defaultdict(set)
        if need_all:
            for path in self.lines(self.sh(self.intersect(words, LOG_ROOTS))):
                found[path] = set(words)
            # A Codex session whose title holds some of the words need hold only the rest.
            for session, held in sorted(titles.items()):
                if any(session in path for path in found):
                    continue
                rest = [word for word in words if word not in held]
                glob = ('-g', f'*{session}.jsonl')
                command = (self.intersect(rest, ('.codex/sessions',), glob) if rest else
                           ' '.join(['rg', '--files', *map(q, glob), '.codex/sessions']))
                for path in self.lines(self.sh(command)):
                    found[path] = set(words)
            return found
        for word in words:
            for path in self.lines(self.run('rg', '-l', '-i', '-F', *LOG_GLOBS, '-e', word, *LOG_ROOTS)):
                found[path].add(word)
        for path in found:
            for session, held in titles.items():
                if session in path:
                    found[path] |= held
        return found

    @staticmethod
    def intersect(words, roots, globs=LOG_GLOBS):
        """One pipeline listing the logs under `roots` that hold every word: each stage keeps the
        files of the one before that hold the next word."""
        stages = []
        for n, word in enumerate(words):
            flag = '-l' if n == len(words) - 1 else '-l0'
            if n == 0:
                stages.append(' '.join(['rg', flag, '-i', '-F', *map(q, globs), '-e', q(word), *map(q, roots)]))
            else:
                stages.append(f'xargs -0 rg {flag} -i -F -e {q(word)}')
        return ' | '.join(stages)

    def codex_titles(self, words):
        """The words each Codex session's title holds, from its session index when there is one."""
        patterns = [arg for word in words for arg in ('-e', word)]
        titles = {}
        for line in self.lines(self.run('rg', '--no-filename', '-i', '-F', *patterns, *SESSION_INDEX)):
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            title = entry.get('thread_name') or ''
            held = {word for word in words if word in title.lower()}
            if entry.get('id') and held:
                titles[entry['id']] = held
                self.titles[entry['id']] = title
        return titles

    def lines(self, result):
        self.note_errors(result)
        return result.out.splitlines()

    def note_errors(self, result):
        """Keeps what rg could not read. A folder or index that is not there is not unread: there
        is nothing in it."""
        for line in result.err.splitlines():
            if line.strip() and 'No such file or directory' not in line:
                self.unreadable.append(line.strip())

    def enumerate_logs(self):
        """Every session log under the log folders: the scope a negative answer covers."""
        result = self.run('rg', '--files', *LOG_GLOBS, *LOG_ROOTS)
        self.note_errors(result)
        return sorted(result.out.splitlines()), result.status == 0

    def scope(self, logs=None, complete=None, **extra):
        if logs is None:
            logs, complete = self.enumerate_logs()
        broken = sorted(self.logpath(log.path) for log in self.logs.values() if log.broken)
        return dict(kind='logs', roots=list(LOG_ROOTS), logs=len(logs),
                    complete=bool(complete) and not self.unreadable and not broken,
                    partial_logs=broken, **extra)

    # Step 2: jq over a log

    def log(self, path):
        if path not in self.logs:
            result = self.run('jq', '-c', '--arg', 'home', self.home, PROJECTION, path)
            records = []
            for line in result.out.splitlines():
                try:
                    records.append(json.loads(line))
                except ValueError:
                    break
            self.clipped += sum(1 for r in records for key in ('cmd', 'out')
                                if isinstance(r.get(key), str) and r[key].endswith('…'))
            broken = None
            if result.status != 0:
                match = re.search(r'line (\d+)', result.err)
                broken = int(match.group(1)) if match else (records[-1]['l'] + 1 if records else 1)
            self.logs[path] = Log(path, records, broken)
        return self.logs[path]

    def turns(self, path):
        log = self.log(path)
        turns, current, cwd, session, title, custom = [], None, None, None, None, False
        for record in log.records:
            kind = record['k']
            if kind == 'meta':
                if record.get('src') == 'subagent':
                    return []
                session, cwd = record.get('id'), self.expand(record.get('cwd'))
            elif kind == 'turn':
                cwd = self.expand(record.get('cwd')) or cwd
            elif kind == 'title':
                # Claude Code: the latest custom title, else the latest generated one.
                if record.get('custom') or not custom:
                    title, custom = record['text'], bool(record.get('custom'))
            elif kind == 'req':
                # A notification starts no request of its own: the person's request stays the context.
                if record.get('human') is False and current:
                    current.records.append(record)
                    continue
                current = Turn(path, record, self.expand(record.get('cwd')) or cwd, session)
                turns.append(current)
            elif current:
                current.records.append(record)
        for turn in turns:
            turn.title = title or self.titles.get(turn.session)
        return turns

    def reply_cwd(self, turn, record):
        return self.expand(record.get('cwd')) or turn.cwd

    def named(self, turn):
        """The paths the turn's final reply names, each resolved against its record's cwd."""
        named, seen = [], set()
        for record in turn.replies:
            cwd = self.reply_cwd(turn, record)
            for mention in mentions(record.get('text') or ''):
                path = self.resolve(mention['target'], cwd)
                if mention['claim'] == 'mention':
                    path, basis = self.place(turn, mention['target'], path)
                    mention['basis'] = basis
                if path in seen:
                    continue
                seen.add(path)
                named.append(dict(mention, path=path, log=turn.log, line=record['l'], at=record.get('t')))
        return named

    def tool_paths(self, turn):
        """Paths the turn's tool calls name: files they wrote, read or produced."""
        paths = []
        for tool in turn.tools:
            cwd = self.reply_cwd(turn, tool)
            if tool.get('path'):
                paths.append(self.expand(tool['path']))
            for target in self.outputs(tool.get('cmd') or ''):
                paths.append(self.resolve(target, cwd))
        return paths

    def place(self, turn, name, guess):
        """Where a bare file name points: the one file of that name the turn's tools touched, else
        the name in the cwd."""
        same = sorted({p for p in self.tool_paths(turn) if os.path.basename(p) == name})
        if len(same) == 1:
            return same[0], 'the one file of that name the turn wrote'
        return guess, 'the name in the reply\'s cwd'

    @staticmethod
    def outputs(command):
        """Files a shell command writes: output flags, redirects and here-documents."""
        found = [m.group(1) for m in OUTPUT_FLAG.finditer(command)]
        found += [m.group(1) for m in REDIRECT.finditer(command.split('\n', 1)[0]) if not m.group(1).startswith('/dev/')]
        return list(dict.fromkeys(found))

    # Choosing the turn

    def text_of(self, turn):
        parts = [turn.request.get('text') or '', turn.title or '']
        parts += [r.get('text') or '' for r in turn.replies]
        parts += self.project_of(turn.cwd)
        return ' '.join(parts).lower()

    def matching(self, need_all=True, project=None):
        """The turns whose request, title, reply and project hold the words, best first: all of
        them, or as many as any turn holds. Ranked by the words in the request, then the newest."""
        found = self.search(self.words, need_all)
        if not found:
            return [], found
        most = max(len(words) for words in found.values())
        wanted = len(self.words) if need_all else most
        candidates = sorted(path for path, words in found.items() if len(words) >= wanted)
        turns = []
        for path in candidates:
            for turn in self.turns(path):
                if project and not self.in_project(turn.cwd, project):
                    continue
                held = count(self.words, self.text_of(turn))
                if held:
                    turns.append((held, count(self.words, turn.request.get('text') or ''), turn.end or 0, turn))
        best = max((held for held, *_ in turns), default=0)
        turns = [item for item in turns if item[0] == (len(self.words) if need_all else best)]
        turns.sort(key=lambda item: (-item[0], -item[1], -item[2]))
        return [turn for *_, turn in turns], found

    def pick(self, named, claim='delivery'):
        """The named path the question is about: the one whose name holds the most words."""
        chosen = [n for n in named if n['claim'] == claim] or named
        if not chosen:
            return None
        return max(chosen, key=lambda n: count(self.words, os.path.basename(n['path'])))

    # Step 3 and 4: the file, its logged write and git

    def facts(self, path):
        """What is at a path now: whether it is a file, its modification time, size and hash."""
        if path not in self.observed:
            result = self.sh(f"stat -f '%m %z %HT' {q(path)} && shasum -a 256 {q(path)}")
            lines = result.out.splitlines()
            if not lines:
                self.observed[path] = dict(exists=False)
            else:
                mtime, size, kind = lines[0].split(' ', 2)
                sha = lines[1].split()[0] if len(lines) > 1 and result.status == 0 else None
                self.observed[path] = dict(exists=True, kind=kind, mtime=float(mtime), size=int(size), sha256=sha,
                                           observed_at=now())
        return self.observed[path]

    def writes(self, turn, path, before):
        """The turn's logged writes of `path` before line `before` that succeeded: (record, kind),
        where a Write or a here-document holds the whole content and an edit does not."""
        results = turn.results
        found = []
        for tool in turn.tools:
            if tool['l'] > before:
                continue
            result = results.get(tool.get('id'))
            if result is None or result.get('err'):
                continue
            name = tool.get('name')
            if name == 'Write' and self.expand(tool.get('path')) == path:
                found.append((tool, 'write', None))
            elif name in ('Edit', 'MultiEdit', 'NotebookEdit') and self.expand(tool.get('path')) == path:
                found.append((tool, 'edit', None))
            elif tool.get('cmd'):
                heredoc = HEREDOC.search(tool['cmd'])
                if heredoc and self.resolve(heredoc.group(1), self.reply_cwd(turn, tool)) == path:
                    found.append((tool, 'heredoc', heredoc.group(2)))
                elif any(self.resolve(t, self.reply_cwd(turn, tool)) == path for t in self.outputs(tool['cmd'])):
                    found.append((tool, 'command', None))
        return found

    def payload(self, log, record, kind, delimiter):
        """A command that prints the logged content of a write."""
        select = f"sed -n '{record['l']}p' {q(log)}"
        if kind == 'write':
            return f'{select} | jq -j {q(WRITTEN)}'
        return f'{select} | jq -r {q(COMMAND)} | awk -v d={q(delimiter)} {q(HEREDOC_BODY)}'

    def keep(self, name):
        self.written += 1
        return os.path.join(self.scratch, f'{self.written}-{name}')

    def delivered(self, item, turn, want='hash'):
        """Where the bytes delivered as `item` are, as far as its log, the file and git show.

        The turn's last logged write that holds the whole content stands for the delivered bytes
        while nothing contradicts it: the file still has them, or the file changed after the reply
        or is gone. A file whose bytes differ from the write while its modification time is before
        the reply was changed by something the log does not show, so neither is the delivery.
        With no such write, a commit made during the turn holds them. Anything else is unknown:
        a modification time alone never establishes the bytes.

        `want` is 'hash', 'text' (the content too) or 'file' (a copy in the scratch folder)."""
        path = item['path']
        reply_at = seconds(item.get('at')) or turn.end
        now = self.facts(path)
        found = dict(path=path, current=now, source=None, sha256=None)
        writes = self.writes(turn, path, item['line'])
        last = writes[-1] if writes else None
        if last and last[1] in ('write', 'heredoc'):
            record, kind, delimiter = last
            command = self.payload(turn.log, record, kind, delimiter)
            if want == 'text':
                result = self.sh(command)
                logged = hashlib.sha256(result.out.encode('utf-8')).hexdigest() if result.status == 0 else None
                found['text'] = result.out
            elif want == 'file':
                copy = self.keep(os.path.basename(path))
                result = self.sh(f'{command} > {q(copy)} && shasum -a 256 {q(copy)}')
                logged = result.out.split()[0] if result.status == 0 and result.out else None
                found['bytes_file'] = copy
            else:
                result = self.sh(f'{command} | shasum -a 256')
                logged = result.out.split()[0] if result.status == 0 and result.out else None
            found['logged'] = dict(log=turn.log, line=record['l'], sha256=logged)
            if logged and now['exists'] and now.get('sha256') == logged:
                found.update(source='file', sha256=logged)
            elif logged and (not now['exists'] or now['mtime'] > reply_at + 2):
                found.update(source='logged_write', sha256=logged)
            elif logged:
                found['note'] = 'the file differs from the logged write and was changed before the reply'
        if found['source'] is None and (not now['exists'] or now.get('sha256') != (found.get('logged') or {}).get('sha256')):
            commit = self.committed(turn, path, reply_at, want)
            if commit:
                found.update(source='git', sha256=commit['sha256'], git=commit)
                if want == 'file' and commit.get('bytes_file'):
                    found['bytes_file'] = commit['bytes_file']
                if want == 'text':
                    found['text'] = commit.get('text')
        if found['source'] is None:
            found.pop('text', None)
            found.pop('bytes_file', None)
        return found

    def repository(self, folder):
        """The repository holding a folder, or its nearest folder still there."""
        result = self.sh(f'd={q(folder)}; while [ ! -d "$d" ]; do d=$(dirname "$d"); done; '
                         'git -C "$d" rev-parse --show-toplevel')
        return result.out.strip() if result.status == 0 and result.out.strip() else None

    def committed(self, turn, path, reply_at, want):
        """A commit made during the turn, before its reply, that holds `path`."""
        root = self.repository(os.path.dirname(path))
        if not root:
            return None
        rels = []
        for base in (turn.cwd, root):
            if base and (path + '/').startswith(base.rstrip('/') + '/'):
                rels.append(os.path.relpath(path, base))
        rels = list(dict.fromkeys(rels))
        if not rels:
            return None
        log = self.run('git', '-C', root, 'log', '--all', '--format=C %H %ct', '--name-only', '--', *rels)
        start = seconds(turn.request.get('t')) or 0
        commits, current = [], None
        for line in log.out.splitlines():
            if line.startswith('C '):
                _, sha, when = line.split()
                current = dict(commit=sha, at=int(when), paths=[])
                commits.append(current)
            elif line.strip() and current:
                current['paths'].append(line.strip())
        inside = [c for c in commits if start - 2 <= c['at'] <= reply_at + 2 and set(c['paths']) & set(rels)]
        if not inside:
            return None
        commit = inside[0]
        rel = next(r for r in rels if r in commit['paths'])
        show = f"git -C {q(root)} show {q(commit['commit'] + ':' + rel)}"
        found = dict(repository=root, commit=commit['commit'], path=rel, at=commit['at'], restore=show)
        if want == 'text':
            result = self.run('git', '-C', root, 'show', commit['commit'] + ':' + rel)
            found['text'] = result.out
            found['sha256'] = hashlib.sha256(result.out.encode('utf-8')).hexdigest()
        elif want == 'file':
            copy = self.keep(os.path.basename(path))
            result = self.sh(f'{show} > {q(copy)} && shasum -a 256 {q(copy)}')
            words = result.out.split()
            found['sha256'] = words[0] if words else None
            if len(words) > 1 and words[1] == copy:
                found['bytes_file'] = copy
        else:
            result = self.sh(f'{show} | shasum -a 256')
            found['sha256'] = result.out.split()[0] if result.out else None
        return found

    # Answers, by what the question asks

    def answer(self):
        asks = self.task['asks']
        if asks == 'verify':
            return self.verify()
        if asks == 'referenced':
            return self.referenced()
        if asks == 'same_item':
            return self.same_item()
        turns, found = self.matching(need_all=asks != 'decision', project=self.task.get('project'))
        if asks == 'provenance' and self.task.get('at'):
            wanted = seconds(self.task['at'])
            turns.sort(key=lambda turn: abs((turn.end or 0) - wanted))
        if not turns:
            return self.none(found)
        if asks != 'decision':
            # The best turn whose reply names a file; a reply that names none delivered nothing.
            turns = [t for t in turns if self.named(t)] or turns
        return getattr(self, asks)(turns)

    def none(self, found):
        """No turn holds the words: a negative within the logs searched, never beyond them. When
        no log holds them all, each word is listed on its own, to say where the parts are."""
        if not found:
            found = self.search(self.words, need_all=False)
        held = sorted(((len(words), path, sorted(words)) for path, words in found.items()), reverse=True)
        most = held[0][0] if held else 0
        near = [dict(log=self.logpath(path), words=words) for n, path, words in held if n == most and n > 0]
        return dict(status='not_found', scope=self.scope(), near=near,
                    note='No single turn in the logs searched holds every word.')

    def logpath(self, log):
        """A log named relative to the home folder, as rg lists it, made absolute."""
        return os.path.join(self.home, log)

    def ref(self, item):
        return dict(path=item['path'], log=self.logpath(item['log']), line=item['line'])

    def value(self, turns):
        turn = turns[0]
        item = self.pick(self.named(turn))
        if not item:
            return dict(status='not_found', scope=self.scope(), note='The matching reply names no file.')
        bytes_ = self.delivered(item, turn, want='text')
        if bytes_['source'] is None:
            return dict(status='unknown', delivery=self.ref(item), current_sha256=bytes_['current'].get('sha256'),
                        note=bytes_.get('note') or 'No observation of the delivered bytes.')
        value = field_value(bytes_['text'], self.task['field'])
        return dict(status='found' if value is not None else 'unknown', delivery=self.ref(item), value=value,
                    sha256=bytes_['sha256'], source=bytes_['source'],
                    evidence=[dict(log=self.logpath(turn.log), line=turn.request['l']), self.ref(item)])

    def files(self, turns):
        turn = turns[0]
        named = [n for n in self.named(turn) if n['claim'] == 'delivery']
        lines = sorted({n['line'] for n in named})
        return dict(status='found' if named else 'not_found', reply=dict(log=self.logpath(turn.log), lines=lines),
                    request=dict(log=self.logpath(turn.log), line=turn.request['l']),
                    files=[self.ref(n) for n in named])

    def delivery(self, turns):
        turn = turns[0]
        named = self.named(turn)
        item = self.pick(named)
        if not item:
            return dict(status='not_found', scope=self.scope(), note='The matching reply names no file.')
        now = self.facts(item['path'])
        chosen = dict(self.ref(item), claim=item['claim'], syntax=item['syntax'], anchor=item['anchor'],
                      sha256=now.get('sha256'))
        if item.get('basis'):
            chosen['basis'] = item['basis']
        others = [dict(self.ref(n), claim=n['claim'], syntax=n['syntax']) for n in named if n is not item]
        return dict(status='found', delivery=chosen, others=others,
                    evidence=[dict(log=self.logpath(turn.log), line=turn.request['l']), self.ref(item)])

    def same_item(self):
        projects = self.task.get('projects') or []
        turns, found = self.matching()
        artifacts = []
        for project in projects:
            mine = [t for t in turns if self.in_project(t.cwd, project)]
            item = self.pick(self.named(mine[0])) if mine else None
            if item:
                bytes_ = self.delivered(item, mine[0])
                artifacts.append(dict(self.ref(item), project=project, sha256=bytes_['sha256'], source=bytes_['source']))
        if len(artifacts) < 2:
            return dict(status='not_found', artifacts=artifacts, scope=self.scope())
        hashes = [a['sha256'] for a in artifacts]
        same_path = len({a['path'] for a in artifacts}) == 1
        return dict(status='found', same=same_path, artifacts=artifacts,
                    equal_bytes=None not in hashes and len(set(hashes)) == 1,
                    note='Each path is its own artifact; equal bytes at two paths do not make one item.')

    def deliveries_of(self, path):
        """Every reply that delivered `path`, oldest first: logs naming its file name, projected."""
        result = self.run('rg', '-l', '-F', *LOG_GLOBS, '-e', os.path.basename(path), *LOG_ROOTS)
        found = []
        for log in sorted(result.out.splitlines()):
            for turn in self.turns(log):
                for item in self.named(turn):
                    if item['path'] == path and item['claim'] == 'delivery':
                        found.append((seconds(item['at']) or 0, item, turn))
        found.sort(key=lambda entry: entry[0])
        return [(item, turn) for _, item, turn in found]

    def current_match(self, turns):
        item = self.pick(self.named(turns[0]))
        if not item:
            return dict(status='not_found', scope=self.scope())
        versions = []
        for number, (each, turn) in enumerate(self.deliveries_of(item['path']), 1):
            bytes_ = self.delivered(each, turn)
            versions.append(dict(self.ref(each), number=number, sha256=bytes_['sha256'], source=bytes_['source']))
        now = self.facts(item['path'])
        latest = versions[-1] if versions else None
        same = [v for v in versions if v['sha256'] and v['sha256'] == now.get('sha256')]
        matches = same[-1] if same else None
        return dict(status='found', current_sha256=now.get('sha256'), latest=latest, matches=matches,
                    matches_latest=bool(matches and latest and matches['number'] == latest['number']),
                    deliveries=versions)

    def provenance(self, turns):
        turn = turns[0]
        item = self.pick(self.named(turn))
        if not item:
            return dict(status='not_found', scope=self.scope())
        bytes_ = self.delivered(item, turn)
        now = bytes_['current']
        established = bytes_['source'] == 'file'
        # Without a capture, the first observation of the file's bytes this policy has is its own read.
        return dict(status='found', established=established, delivery=self.ref(item), delivered_at=item.get('at'),
                    sha256=now.get('sha256'), observed_at=now.get('observed_at'), modified_at=now.get('mtime'),
                    logged=bytes_.get('logged'),
                    note=('The file holds the bytes the turn logged writing.' if established else
                          (bytes_.get('note') or 'Nothing observed the bytes when they were delivered') +
                          f"; the first observation of these bytes is this read, at {now.get('observed_at')}. A "
                          'modification time does not establish them.'))

    def recover(self, turns):
        turn = turns[0]
        artifacts = []
        for item in [n for n in self.named(turn) if n['claim'] == 'delivery']:
            bytes_ = self.delivered(item, turn, want='file')
            entry = dict(self.ref(item), source=bytes_['source'], sha256=bytes_['sha256'],
                         recovered=bytes_['source'] is not None, current=bytes_['current'].get('exists'))
            if bytes_.get('bytes_file'):
                entry['bytes_file'] = bytes_['bytes_file']
            if bytes_.get('git'):
                entry['restore_command'] = bytes_['git']['restore']
                entry['commit'] = bytes_['git']['commit']
            artifacts.append(entry)
        return dict(status='found' if artifacts else 'not_found', artifacts=artifacts,
                    request=dict(log=self.logpath(turn.log), line=turn.request['l']))

    def bytes(self, turns):
        turn = turns[0]
        item = self.pick(self.named(turn))
        if not item:
            return dict(status='not_found', scope=self.scope(), note='The matching reply names no file.')
        bytes_ = self.delivered(item, turn, want='file')
        now = bytes_['current']
        verification = dict(original=bool(now.get('sha256')) and now.get('sha256') == bytes_['sha256'],
                            current_sha256=now.get('sha256'), logged=bytes_.get('logged'))
        if bytes_['source'] is None:
            return dict(status='failed', delivery=self.ref(item), verification=verification,
                        note=bytes_.get('note') or 'No observation of the delivered bytes.')
        note = ('The file holds the delivered bytes.' if bytes_['source'] == 'file' else
                'The file at the path no longer holds the bytes the turn logged writing; these are those bytes, '
                f"from {bytes_['source'].replace('_', ' ')}.")
        return dict(status='found', delivery=self.ref(item), sha256=bytes_['sha256'], bytes_file=bytes_.get('bytes_file'),
                    source=bytes_['source'], verification=verification, note=note)

    def generated(self, turn, delivered):
        """Files the turn's tools produced, apart from what the reply delivered, and calls that
        never returned."""
        results = turn.results
        made, tried = [], []
        for tool in turn.tools:
            cwd = self.reply_cwd(turn, tool)
            command = tool.get('cmd') or ''
            outputs = [self.resolve(t, cwd) for t in self.outputs(command)]
            result = results.get(tool.get('id'))
            if result is None:
                tried += [dict(path=p, log=self.logpath(turn.log), line=tool['l']) for p in outputs]
                continue
            if tool.get('name') == 'Write' and tool.get('path'):
                outputs.append(self.expand(tool['path']))
            named = [self.resolve(m.group(1), cwd) for m in PATH_TOKEN.finditer(result.get('out') or '')]
            for path in dict.fromkeys(outputs + [p for p in named if p in outputs or not result.get('err')]):
                if path not in delivered:
                    made.append(dict(path=path, log=self.logpath(turn.log), line=result['l']))
        made = list({m['path']: m for m in made}.values())
        about = [m for m in made if count(self.words, os.path.basename(m['path']))]
        return about or made, [t for t in tried if t['path'] not in {m['path'] for m in made}]

    def handed_over(self, turns):
        turn = turns[0]
        delivered = [n['path'] for n in self.named(turn) if n['claim'] == 'delivery']
        made, tried = self.generated(turn, delivered)
        for entry in made:
            now = self.facts(entry['path'])
            entry.update(exists=now['exists'], sha256=now.get('sha256'))
        made = [m for m in made if m['exists']]
        return dict(status='found', handed_over=any(m['path'] in delivered for m in made), generated=made,
                    attempted=tried, reply_delivered=delivered,
                    request=dict(log=self.logpath(turn.log), line=turn.request['l']))

    def decision(self, turns):
        turn = turns[0]
        log = self.log(turn.log)
        later = [t for t in self.turns(turn.log) if t.request['l'] > turn.request['l']]
        replies = [dict(log=self.logpath(turn.log), line=r['l'], text=r.get('text')) for t in later for r in t.replies]
        readable = log.broken - 1 if log.broken else (log.records[-1]['l'] if log.records else 0)
        session = dict(log=self.logpath(turn.log), request_line=turn.request['l'])
        if replies:
            return dict(status='found', session=session, decision=replies[0], readable_lines=readable,
                        malformed_line=log.broken)
        if log.broken:
            return dict(status='unknown', session=session, readable_lines=readable, malformed_line=log.broken,
                        note=f'No later reply in lines 1-{readable}; the log cannot be read from line {log.broken}, '
                             'so what followed is unknown.')
        return dict(status='not_found', session=session, readable_lines=readable,
                    scope=dict(kind='log', log=self.logpath(turn.log), lines=readable, complete=True),
                    note='The session holds no later reply.')

    def referenced(self):
        """Whether the project's sessions name the file anywhere in their records."""
        project = self.task.get('project')
        name = self.task.get('name') or self.task['words'][0]
        found = self.search([name.lower()])
        listing = self.run('rg', '-m1', '-o', *LOG_GLOBS, '"cwd":"[^"]*"', *LOG_ROOTS)
        cwds = {}
        for line in listing.out.splitlines():
            path, _, match = line.partition(':"cwd":')
            cwds[path] = json.loads(match) if match else None
        mine = sorted(p for p, cwd in cwds.items() if not project or self.in_project(cwd, project))
        hits = [self.logpath(p) for p in mine if p in found]
        elsewhere = [self.logpath(p) for p in sorted(found) if p not in mine]
        scope = self.scope(logs=mine, complete=listing.status == 0, project=project,
                           sessions=[self.logpath(p) for p in mine])
        return dict(status='found' if hits else 'not_found', referenced=bool(hits), mentions=hits, scope=scope,
                    elsewhere=elsewhere)

    def verify(self):
        pointer = self.task['pointer']
        path = pointer['path']
        now = self.facts(path)
        answer = dict(status='found', original=now.get('sha256') == pointer['sha256'], saved_copy=None,
                      delivered_sha256=pointer['sha256'], current_sha256=now.get('sha256'))
        if answer['original']:
            return answer
        log = os.path.relpath(pointer['evidence']['log'], self.home)
        line = pointer['evidence']['line']
        turn = next((t for t in self.turns(log) if any(r['l'] == line for r in t.replies)), None)
        if turn:
            item = next((n for n in self.named(turn) if n['path'] == path), None)
            if item:
                bytes_ = self.delivered(item, turn)
                if bytes_['sha256'] == pointer['sha256']:
                    answer['bytes'] = dict(source=bytes_['source'], sha256=bytes_['sha256'],
                                           logged=bytes_.get('logged'), git=bytes_.get('git'))
        if 'bytes' not in answer:
            moved = self.moved(path, pointer['sha256'])
            if moved:
                answer.update(moved_to=moved, bytes=dict(source='moved', sha256=moved['sha256']))
        answer['note'] = ('The path holds other bytes now; the delivered version is located elsewhere.'
                          if 'bytes' in answer else 'The path holds other bytes now, and the delivered ones were not found.')
        return answer

    def moved(self, path, sha):
        """Where git history renamed the file to, if that file still has the delivered bytes."""
        result = self.sh(f'git -C {q(os.path.dirname(path))} rev-parse --show-toplevel && '
                         f'git -C {q(os.path.dirname(path))} log --all -M --diff-filter=R --name-status --format=C%x20%H')
        lines = result.out.splitlines()
        if result.status != 0 or not lines:
            return None
        root = lines[0]
        rel = os.path.relpath(path, root)
        commit = None
        for line in lines[1:]:
            if line.startswith('C '):
                commit = line[2:]
            elif line.startswith('R'):
                _, old, new = line.split('\t')
                if old == rel:
                    target = os.path.join(root, new)
                    now = self.facts(target)
                    if now.get('sha256') == sha:
                        return dict(path=target, sha256=sha, commit=commit, basis='git history renames the path')
        return None


# The gleaner policy

class Gleaner:
    """G: the gleaner command first, the raw recipe where the catalog's scope ends."""

    def __init__(self, shell, task, home, scratch):
        self.shell = shell
        self.task = task
        self.home = home
        self.scratch = scratch
        self.words = lower(task['words'])
        self.raw = Raw(shell, task, home, scratch)
        self.index = None
        self.truncated = []

    def gleaner(self, *args):
        """A gleaner command, its answer projected with jq to what this policy reads (G_PROJECTION).
        Its exit status is gleaner's."""
        script = (f"set -o pipefail; gleaner {' '.join(q(a) for a in args)} --home {q(self.home)}"
                  f" | jq -c --arg home {q(self.home)} {q(G_PROJECTION)}")
        result = self.shell.sh(script, phase='catalog')
        try:
            answer = self.expand(json.loads(result.out))
        except ValueError:
            answer = None
        if answer and 'index' in answer:
            self.index = answer['index']
        if answer and answer.get('truncated'):
            self.truncated.append(args[0])
        return result.status, answer

    def expand(self, value, key=None):
        """An answer with the paths its projection wrote ~ made absolute again; text is left as it is."""
        if isinstance(value, dict):
            return {k: self.expand(v, k) for k, v in value.items()}
        if isinstance(value, list):
            return [self.expand(v, key) for v in value]
        if isinstance(value, str) and key not in ('text', 'request', 'message', 'restore_command'):
            return self.raw.expand(value) if value == '~' or value.startswith('~/') else value
        return value

    def diagnostics(self):
        return dict(self.raw.diagnostics(), truncated=self.truncated)

    def scope(self):
        index = self.index or {}
        sources = {name: dict(state=s.get('state'), partial_logs=s.get('partial_logs', 0))
                   for name, s in (index.get('sources') or {}).items()}
        return dict(kind='catalog', library=index.get('library'), generation=index.get('generation'),
                    scanned_at=index.get('scanned_at'), sources=sources, complete=complete(index))

    def fallback(self, reason):
        """R, with what the catalog said and why it was not enough."""
        answer = self.raw.answer()
        raw_scope = answer.get('scope')
        answer['scope'] = dict(kind='catalog+logs', catalog=self.scope(), logs=raw_scope,
                               complete=bool(raw_scope and raw_scope.get('complete')))
        answer['fallback'] = reason
        return answer

    def answer(self):
        task = self.task
        pointer = task.get('pointer') or {}
        if task['asks'] == 'verify' and pointer.get('delivery'):
            return self.verify(pointer)
        args = ['find', *task['words']]
        if task.get('project'):
            args += ['--project', task['project']]
        status, found = self.gleaner(*args)
        if status != 0 or found is None:
            return self.fallback(f'find exited {status}')
        if not complete(found['index']):
            return self.fallback('the index reports incomplete sources')
        hits = found['results']
        if task.get('projects'):
            hits = [h for h in hits if h['project']['name'].lower() in lower(task['projects'])]
        if not hits:
            return self.fallback('find returned nothing')
        return getattr(self, task['asks'])(hits)

    # Choosing the hit

    def ranked(self, hits):
        """Hits best first: the most words in the request they answered, then find's order (newest)."""
        order = {id(h): n for n, h in enumerate(hits)}
        return sorted(hits, key=lambda h: (-count(self.words, h.get('request') or ''), order[id(h)]))

    def group(self, hits):
        """The best hit with every other file its reply delivered: same log, same request."""
        best = self.ranked(hits)[0]
        key = (best['reference']['evidence']['log'], best.get('request'))
        return [h for h in hits if (h['reference']['evidence']['log'], h.get('request')) == key]

    @staticmethod
    def ref(reference):
        return dict(path=reference['path'], log=reference['evidence']['log'], line=reference['evidence']['line'],
                    delivery=reference['delivery'])

    def evidence(self, reference):
        return [dict(delivery=reference['delivery'], library=reference['library'], **reference['evidence'])]

    # Answers

    def value(self, hits):
        hit = self.ranked(hits)[0]
        reference = hit['reference']
        status, read = self.gleaner('read', reference['delivery'])
        if status != 0 or read is None:
            reason = (read or {}).get('error', {}).get('message', f'read exited {status}')
            return dict(status='unknown', delivery=self.ref(reference), note=reason, scope=self.scope())
        value = field_value(read['text'], self.task['field'])
        return dict(status='found' if value is not None else 'unknown', delivery=self.ref(read['reference']),
                    value=value, sha256=read['reference']['sha256'],
                    source=read['reference']['availability']['state'], truncated=read.get('truncated'),
                    evidence=self.evidence(reference), scope=self.scope())

    def files(self, hits):
        group = self.group(hits)
        reference = group[0]['reference']
        return dict(status='found', reply=dict(log=reference['evidence']['log'],
                                               lines=sorted({h['reference']['evidence']['line'] for h in group})),
                    files=[self.ref(h['reference']) for h in group], scope=self.scope())

    def delivery(self, hits):
        hit = self.ranked(hits)[0]
        reference = hit['reference']
        return dict(status='found', delivery=dict(self.ref(reference), claim='delivery', sha256=reference['sha256']),
                    others=[], evidence=self.evidence(reference), scope=self.scope())

    def same_item(self, hits):
        artifacts = []
        for project in self.task.get('projects') or []:
            mine = [h for h in hits if h['project']['name'].lower() == project.lower()]
            if mine:
                reference = self.ranked(mine)[0]['reference']
                artifacts.append(dict(self.ref(reference), project=project, sha256=reference['sha256']))
        hashes = [a['sha256'] for a in artifacts]
        return dict(status='found' if len(artifacts) > 1 else 'not_found',
                    same=len({a['delivery'] for a in artifacts}) == 1 and len(artifacts) > 1,
                    artifacts=artifacts, equal_bytes=None not in hashes and len(set(hashes)) == 1,
                    note='Gleaner keeps one artifact per path; equal hashes do not merge them.', scope=self.scope())

    def current_match(self, hits):
        hit = self.ranked(hits)[0]
        status, shown = self.gleaner('show', hit['reference']['delivery'])
        if status != 0 or shown is None:
            return dict(status='unknown', note=f'show exited {status}', scope=self.scope())
        current = shown['on_disk'].get('sha256')
        versions = sorted(shown['deliveries'], key=lambda v: v['number'])
        latest = versions[-1]
        same = [v for v in versions if v['reference']['sha256'] and v['reference']['sha256'] == current]
        matches = same[-1] if same else None

        def version(v):
            return v and dict(self.ref(v['reference']), number=v['number'], sha256=v['reference']['sha256'],
                              provenance=v['reference']['provenance']['state'])
        return dict(status='found', current_sha256=current, latest=version(latest), matches=version(matches),
                    matches_latest=bool(matches and matches['number'] == latest['number']),
                    deliveries=[version(v) for v in versions], scope=self.scope())

    def provenance(self, hits):
        wanted = seconds(self.task.get('at'))
        if wanted:
            hit = min(hits, key=lambda h: abs((seconds(h.get('delivered_at')) or 0) - wanted))
        else:
            hit = self.ranked(hits)[0]
        reference = hit['reference']
        seen = reference['provenance']
        return dict(status='found', established=seen['state'] == 'at_delivery', delivery=self.ref(reference),
                    delivered_at=hit.get('delivered_at'), provenance=seen['state'], observed_at=seen.get('observed_at'),
                    sha256=reference['sha256'], evidence=self.evidence(reference), scope=self.scope(),
                    note=('Gleaner read the file within ten minutes of the reply.' if seen['state'] == 'at_delivery' else
                          'Gleaner first read the file after the delivery, so its bytes may not be the delivered ones.'))

    def recover(self, hits):
        artifacts = []
        for hit in self.group(hits):
            reference = hit['reference']
            # A version whose bytes are at hand is handed off; show gives the plan for one that isn't.
            if reference['availability']['state'] in ('original', 'saved_copy'):
                plan = dict(action='ready')
            else:
                status, shown = self.gleaner('show', reference['delivery'])
                plan = (shown or {}).get('handoff', {})
            entry = dict(self.ref(reference), sha256=reference['sha256'], plan=plan.get('action'),
                         availability=reference['availability'], recovered=False, source=None)
            if plan.get('action') == 'ready':
                status, handed = self.gleaner('handoff', reference['delivery'])
                if status == 0 and handed:
                    copy = handed['copy']
                    sha = self.shell.sh(f'shasum -a 256 {q(copy)}').out.split()
                    entry.update(bytes_file=copy, recovered=bool(sha) and sha[0] == reference['sha256'],
                                 source=handed['reference']['availability']['state'])
            elif plan.get('action') == 'restore_from_git' and plan.get('restore_command'):
                entry['restore_command'] = plan['restore_command']
                checked = self.check_restore(plan['restore_command'], reference)
                if checked:
                    entry.update(checked)
            artifacts.append(entry)
        return dict(status='found', artifacts=artifacts, scope=self.scope())

    def check_restore(self, command, reference):
        """Whether the commit a restore command names holds the delivered bytes, hashed through git."""
        words = [self.raw.expand(w) if w.startswith('~') else w for w in shlex.split(command)]
        try:
            if 'worktree' in words:
                repository = words[words.index('-C') + 1]
                folder, commit = words[-2], words[-1]
                rel = os.path.relpath(reference['path'], folder)
            else:
                repository = words[words.index('-C') + 1]
                commit = next(w.split('=', 1)[1] for w in words if w.startswith('--source='))
                rel = words[-1]
        except (ValueError, IndexError, StopIteration):
            return None
        result = self.shell.sh(f'git -C {q(repository)} show {q(commit + ":" + rel)} | shasum -a 256')
        sha = result.out.split()[0] if result.out else None
        return dict(source='git', commit=commit, git_sha256=sha,
                    recovered=sha is not None and sha == reference['sha256'])

    def session(self, hits):
        """The best hit's delivering turn, read raw from the log its evidence names."""
        hit = self.ranked(hits)[0]
        reference = hit['reference']
        log = os.path.relpath(reference['evidence']['log'], self.home)
        line = reference['evidence']['line']
        turn = next((t for t in self.raw.turns(log) if any(r['l'] == line for r in t.replies)), None)
        return hit, turn

    def handed_over(self, hits):
        group = self.group(hits)
        delivered = [h['reference']['path'] for h in group]
        _, turn = self.session(group)
        if turn is None:
            return dict(status='unknown', reply_delivered=delivered, scope=self.scope(),
                        note='The delivering record is not in its log any more.')
        made, tried = self.raw.generated(turn, delivered)
        for entry in made:
            now = self.raw.facts(entry['path'])
            entry.update(exists=now['exists'], sha256=now.get('sha256'))
        made = [m for m in made if m['exists']]
        return dict(status='found', handed_over=any(m['path'] in delivered for m in made), generated=made,
                    attempted=tried, reply_delivered=delivered, scope=self.scope())

    def decision(self, hits):
        _, turn = self.session(hits)
        if turn is None:
            return self.fallback('the delivering record is not in its log any more')
        answer = self.raw.decision([turn])
        answer['catalog'] = dict(scope=self.scope())
        return answer

    def referenced(self, hits):
        return dict(status='found', referenced=True, mentions=[self.ref(h['reference']) for h in hits],
                    scope=dict(self.scope(), project=self.task.get('project')))

    def bytes(self, hits):
        hit = self.ranked(hits)[0]
        reference = hit['reference']
        status, handed = self.gleaner('handoff', reference['delivery'])
        if status != 0 or not handed or 'copy' not in handed:
            error = (handed or {}).get('error', {})
            return dict(status='failed', delivery=self.ref(reference), sha256=reference['sha256'],
                        note=error.get('message', f'handoff exited {status}'), scope=self.scope())
        copy = handed['copy']
        sha = self.shell.sh(f'shasum -a 256 {q(copy)}').out.split()
        verified = bool(sha) and sha[0] == handed['reference']['sha256']
        availability = handed['reference']['availability']
        return dict(status='found' if verified else 'failed', delivery=self.ref(handed['reference']),
                    sha256=handed['reference']['sha256'], bytes_file=copy, source=availability['state'],
                    verification=dict(original=availability['state'] == 'original', copy_sha256=sha[0] if sha else None),
                    note=('The file at the path no longer holds the delivered bytes; these are Gleaner\'s saved copy.'
                          if availability['state'] == 'saved_copy' else 'The file at the path holds the delivered bytes.'),
                    scope=self.scope())

    def verify(self, pointer):
        status, verified = self.gleaner('verify', pointer['delivery'])
        if verified is None or 'reference' not in verified:
            error = (verified or {}).get('error', {})
            if error.get('code') in ('not_found', 'other_library'):
                return self.fallback(error.get('message', 'the delivery is not in this library'))
            return dict(status='failed', note=error.get('message', f'verify exited {status}'), scope=self.scope())
        reference = verified['reference']
        answer = dict(status='found', original=verified['original'], saved_copy=verified['saved_copy'],
                      delivered_sha256=reference['sha256'], delivery=self.ref(reference), scope=self.scope())
        if not verified['original'] and verified['saved_copy']:
            answer['bytes'] = dict(source='saved_copy', sha256=reference['sha256'])
        answer['note'] = ('The file at the path holds the delivered bytes.' if verified['original'] else
                          'The path holds other bytes now; Gleaner\'s saved copy holds the delivered version.'
                          if verified['saved_copy'] else 'Neither the path nor a saved copy holds the delivered bytes.')
        return answer


def complete(index):
    """Whether an index is evidence within its scope: it has run, and it read every source without
    problems. A source read with problems, or one it could not read, may be missing what is asked."""
    if not index or not index.get('generation'):
        return False
    return all(source.get('state') in ('read', 'absent') for source in (index.get('sources') or {}).values())


POLICIES = dict(R=Raw, G=Gleaner)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in POLICIES:
        raise SystemExit(__doc__)
    shell = Shell(sys.stdin, sys.stdout)
    start = json.loads(sys.stdin.readline())
    policy = POLICIES[sys.argv[1]](shell, start['task'], start['home'], start['scratch'])
    try:
        answer = policy.answer()
    except Exception as error:  # A policy that breaks gives an answer that says so, and is scored as one.
        answer = dict(status='failed', note=f'{type(error).__name__}: {error}')
        import traceback
        traceback.print_exc()
    answer['diagnostics'] = policy.diagnostics()
    sys.stdout.write(json.dumps(dict(answer=answer), ensure_ascii=False) + '\n')
    sys.stdout.flush()


if __name__ == '__main__':
    main()
