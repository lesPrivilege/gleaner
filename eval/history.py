"""A world's timed history: the operations `worlds.py` records, applied at an anchor time.

A world is written in epochs. Epoch 0 is applied by `worlds.py` at the seed's base date, so
its logs, files and commits are fixed bytes. Later epochs are applied by `prepare.py` at the
moment it prepares the catalog, because Gleaner calls a capture "at delivery" only when it reads
the file within ten minutes of the reply that named it (SPEC §5.1). Every time in an operation is
an offset in seconds from its epoch's anchor; inside a log record it is written {"$t": offset}.

Operations:
- {"op": "write", "path", "text" | "sparse": {"head", "size"}, "mtime"}: a sparse file is its
  head, then zeros up to its size
- {"op": "append", "path", "lines": [record | raw text]}: a record is one JSON line; raw text
  is written as it is, so a log can end mid-record
- {"op": "git", "cwd", "args", "at"}: git with a fixed identity and both dates at `at`
- {"op": "mkdir", "path"} and {"op": "remove", "path"}
Paths are relative to the world folder.
"""
import datetime
import json
import os
import shutil
import subprocess


def place(path):
    """`path` made absolute, where Gleaner spells it one way. Gleaner lists logs through
    FileManager, which resolves symbolic links (/tmp becomes /private/tmp), and standardizes the
    paths a reply names, which drops a leading /private; so under a link or /private a world's
    logs and files would be recorded under two spellings. Such a folder is refused."""
    path = os.path.abspath(path)
    if os.path.realpath(path) != path or path.startswith('/private/'):
        raise SystemExit(f'{path}: choose a folder with no symbolic link in its path, outside /private and '
                         '/tmp, such as one under your home folder')
    return path


def iso(seconds):
    """UTC with milliseconds, as both agents write timestamps."""
    moment = datetime.datetime.fromtimestamp(round(seconds, 3), datetime.timezone.utc)
    return moment.isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def resolve(value, anchor):
    """`value` with every {"$t": offset} replaced by its ISO time."""
    if isinstance(value, dict):
        if set(value) == {'$t'}:
            return iso(anchor + value['$t'])
        return {key: resolve(item, anchor) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, anchor) for item in value]
    return value


def offsets(value):
    """Every {"$t": offset} in `value`."""
    if isinstance(value, dict):
        if set(value) == {'$t'}:
            return [value['$t']]
        return [t for item in value.values() for t in offsets(item)]
    if isinstance(value, list):
        return [t for item in value for t in offsets(item)]
    return []


def line(record):
    """One JSONL line as the agents write it: compact, non-ASCII kept."""
    return json.dumps(record, ensure_ascii=False, separators=(',', ':')) + '\n'


def git_env(at):
    """Git with no user or system configuration, a fixed identity, and both dates at `at`."""
    date = f'@{int(at)} +0000'
    return dict(os.environ,
                GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1',
                GIT_AUTHOR_NAME='Agent', GIT_AUTHOR_EMAIL='agent@example.invalid',
                GIT_COMMITTER_NAME='Agent', GIT_COMMITTER_EMAIL='agent@example.invalid',
                GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)


def apply(root, ops, anchor):
    """Applies `ops` to the world at `root`, with every time an offset from `anchor`."""
    for op in ops:
        path = os.path.join(root, op['path']) if 'path' in op else None
        kind = op['op']
        if kind == 'write':
            os.makedirs(os.path.dirname(path), exist_ok=True)
            if os.path.lexists(path):
                os.unlink(path)
            with open(path, 'wb') as f:
                if 'text' in op:
                    f.write(op['text'].encode('utf-8'))
                else:
                    f.write(op['sparse']['head'].encode('utf-8'))
                    f.truncate(op['sparse']['size'])
            when = anchor + op['mtime']
            os.utime(path, (when, when))
        elif kind == 'append':
            # The log's modification time is its latest record's, as when the agent wrote it.
            os.makedirs(os.path.dirname(path), exist_ok=True)
            before = os.stat(path).st_mtime if os.path.exists(path) else None
            with open(path, 'a', encoding='utf-8') as f:
                for item in op['lines']:
                    f.write(item if isinstance(item, str) else line(resolve(item, anchor)))
            times = [anchor + offset for offset in offsets(op['lines'])]
            when = max(times) if times else before
            if when is not None:
                os.utime(path, (when, when))
        elif kind == 'git':
            subprocess.run(['git', '-c', 'init.defaultBranch=main', '-c', 'core.autocrlf=false', *op['args']],
                           cwd=os.path.join(root, op['cwd']), env=git_env(anchor + op['at']),
                           check=True, capture_output=True)
        elif kind == 'mkdir':
            os.makedirs(path, exist_ok=True)
        elif kind == 'remove':
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            elif os.path.lexists(path):
                os.unlink(path)
        else:
            raise ValueError(f'unknown operation {kind}')
