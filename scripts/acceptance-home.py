#!/usr/bin/env python3
"""Build a synthetic home for native acceptance checks (docs/release.md §1).

    scripts/acceptance-home.py <home> initial|second|changed
    open -n build/Gleaner.app --args -GleanerHome <home>

The app then reads only <home>'s agent logs and keeps its library under <home>/Library;
nothing outside <home> is read or written. Run `initial`, look, then `second` (a new
delivery of guide.md and diagram.png), then `changed` (files edited without a delivery,
replace.txt turned into a folder, the atlas-feature worktree removed).

Phase initial delivers:
- Claude Code: CJK Markdown, a PNG, a symlink, a folder and an HTML page inside it, a
  65 MiB sparse file (tracked by hash only), a long text file and a FIFO;
- two git repositories both named `app`, each delivering report.md;
- Codex: a 65 MiB demo.mov committed on branch `feature` of an external worktree of
  `atlas`, so after `changed` it is restorable from git but has no saved copy;
- a delivered file nobody can read (chmod 000).
"""
import datetime, json, os, pathlib, struct, subprocess, sys, zlib

home = pathlib.Path(sys.argv[1]).resolve()
phase = sys.argv[2] if len(sys.argv) > 2 else ''
out = home / 'fixtures'
work = home / 'work'
claude = home / '.claude' / 'projects'
codex = home / '.codex'


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z')


def links(paths):
    return '\n'.join(f'[{pathlib.Path(p).name}]({p})' for p in paths)


def claude_delivery(log, session, cwd, request, paths):
    base = dict(sessionId=session, cwd=str(cwd), timestamp=now())
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as f:
        f.write(json.dumps(dict(base, type='user', origin={'kind': 'human'}, message={'content': request}), ensure_ascii=False) + '\n')
        f.write(json.dumps(dict(base, type='assistant', message={'content': [{'type': 'text', 'text': links(paths)}]}), ensure_ascii=False) + '\n')


def codex_delivery(thread, cwd, request, paths):
    day = datetime.date.today()
    log = codex / 'sessions' / f'{day:%Y}' / f'{day:%m}' / f'{day:%d}' / f'rollout-{day}-{thread}.jsonl'
    log.parent.mkdir(parents=True, exist_ok=True)
    at = now()
    with log.open('a') as f:
        for payload, kind in ((dict(id=thread, cwd=str(cwd), thread_source='user'), 'session_meta'),
                              (dict(type='message', role='user', content=[dict(type='input_text', text=request)],
                                    internal_chat_message_metadata_passthrough=dict(content_item_kinds=['user.text'])), 'response_item'),
                              (dict(type='message', role='assistant', phase='final_answer',
                                    content=[dict(type='output_text', text=links(paths))]), 'response_item')):
            f.write(json.dumps(dict(timestamp=at, type=kind, payload=payload)) + '\n')
    with (codex / 'session_index.jsonl').open('a') as f:
        f.write(json.dumps(dict(id=thread, thread_name='Atlas feature demo', updated_at=at)) + '\n')


def git(cwd, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
               GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid',
               GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null')
    subprocess.run(['git', '-C', str(cwd), *args], check=True, env=env, capture_output=True)


def png(path, rgb):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(b'\0' + bytes(rgb))) + chunk(b'IEND', b''))


def sparse(path, header):
    with path.open('wb') as f:
        f.write(header)
        f.truncate(65 << 20)


audit = claude / 'acceptance' / 'audit.jsonl'

if phase == 'initial':
    if home.exists() and any(home.iterdir()):
        raise SystemExit('choose a new, empty home')
    out.mkdir(parents=True)
    (out / 'guide.md').write_text('# Recovery guide\n\n旧版：重试三次。\n\n## Details\nThis is synthetic version one.\n')
    (out / 'replace.txt').write_text('saved regular file, not a folder\n')
    (out / 'large.txt').write_text('Read beyond preview.\n' + 'line\n' * 16000)
    sparse(out / 'large.dat', b'')
    png(out / 'diagram.png', (255, 0, 0))
    (out / 'latest.md').symlink_to(out / 'guide.md')
    bundle = out / 'bundle'
    bundle.mkdir()
    (bundle / 'image.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="red"/></svg>')
    (bundle / 'index.html').write_text('<!doctype html><title>Synthetic bundle</title><h1>Fixture</h1><img src="image.svg">')
    os.mkfifo(out / 'pipe.txt', 0o600)
    claude_delivery(audit, 'acceptance', out, 'Prepare the recovery guide and diagram: version one.',
                    [out / n for n in ('guide.md', 'diagram.png', 'latest.md', 'replace.txt', 'large.txt', 'large.dat',
                                       'bundle', 'bundle/index.html', 'pipe.txt')])

    for client, title in (('client-a', 'Alpha quarterly report'), ('client-b', 'Beta quarterly report')):
        repo = work / client / 'app'
        repo.mkdir(parents=True)
        git(repo, 'init', '-q', '-b', 'main')
        (repo / 'report.md').write_text(f'# {title}\n')
        git(repo, 'add', '.')
        git(repo, 'commit', '-q', '-m', 'report')
        claude_delivery(claude / f'{client}-app' / f'{client}.jsonl', client, repo, f'Write the {title.lower()}', [repo / 'report.md'])

    atlas, feature = work / 'atlas', work / 'atlas-feature'
    atlas.mkdir(parents=True)
    git(atlas, 'init', '-q', '-b', 'main')
    (atlas / 'README.md').write_text('# Atlas\n')
    git(atlas, 'add', '.')
    git(atlas, 'commit', '-q', '-m', 'init')
    git(atlas, 'worktree', 'add', '-q', '-b', 'feature', str(feature))
    (feature / 'out').mkdir()
    sparse(feature / 'out' / 'demo.mov', b'synthetic demo header\n')
    git(feature, 'add', '.')
    git(feature, 'commit', '-q', '-m', 'demo video')
    codex_delivery('atlas-demo', feature, 'Render the atlas demo video', [feature / 'out' / 'demo.mov'])

    locked = work / 'locked'
    locked.mkdir(parents=True)
    (locked / 'locked-report.md').write_text('# Locked report\n')
    (locked / 'locked-report.md').chmod(0)
    claude_delivery(claude / 'locked' / 'locked.jsonl', 'locked', locked, 'Write the locked report', [locked / 'locked-report.md'])

elif phase == 'second':
    (out / 'guide.md').write_text('# Recovery guide\n\n新版：重试五次。\n\n## Details\nThis is synthetic version two.\n')
    png(out / 'diagram.png', (0, 0, 255))
    claude_delivery(audit, 'acceptance', out, 'Prepare the board cut: version two.', [out / 'guide.md', out / 'diagram.png'])

elif phase == 'changed':
    (out / 'guide.md').write_text('# UNDELIVERED current content\n')
    png(out / 'diagram.png', (0, 255, 0))
    if (out / 'replace.txt').is_file():
        (out / 'replace.txt').unlink()
        (out / 'replace.txt').mkdir()
        (out / 'replace.txt' / 'unrelated.txt').write_text('not the saved delivery')
    git(work / 'atlas', 'worktree', 'remove', '--force', str(work / 'atlas-feature'))

else:
    raise SystemExit(__doc__)
print(f'{home}: {phase}')
