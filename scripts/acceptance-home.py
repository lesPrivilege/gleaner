#!/usr/bin/env python3
"""Build a synthetic home for native acceptance checks (docs/release.md §1).

    scripts/acceptance-home.py <home> initial|second|changed
    open -n build/Gleaner.app --args -GleanerHome <home>

The app then reads only <home>'s agent logs and keeps its library under <home>/Library;
nothing outside <home> is read or written. Run `initial`, look, then `second` (a new
delivery of guide.md and diagram.png), then `changed` (files edited without a delivery,
replace.txt turned into a folder, the atlas-feature worktree removed).

Phases board, board-revise and board-final (after initial, each read by the app before the
next) add a non-code project, `work/board`, outside git: a report revised at one path and then
renamed, a chart revised and then saved under a versioned name, a slide deck, a PDF brief deleted
after delivery, and an appendix delivered from a client-a session, so Gleaner files it under
client-a/app until the person moves it.

Phase capture (on its own or after the others) adds `work/series`, outside git, for what is
observed rather than handed over (docs/design/capture.md): a session asked three hours ago that
answers once its files are written, whose reply names only the folder `out/`, while its files,
media, images, data, code and a nested note, are dated inside its span; forty voice lines in one
folder, enough to fold; a plan created and changed the day before, which no session observes;
and a second session in the same workspace, asked two hours ago, so the covers dated after that
are observed by both. A file's dates can be set back but its inode change time can't, so each
session answers after its files are written, as a session that wrote them would.

Phase bundle (on its own or after the others) adds `work/launch`, outside git, for folders handed
over (SPEC §5.4): a session whose first reply, an hour ago, names the folder `site/` and the Git
checkout `app/`, and whose second, now, names `site/` again with `renders/`. The site's files are
dated before the first reply but written now, after it, so only the second delivery hands them
over, as it does `assets/hero.png`, which came after the first reply; its hidden `.env` and
`.DS_Store` are never handed over; thirty renders crowd their folder and fold; and `app/`, a
project's own folder, stands alone and says why.

Phase review (on its own or after the others) adds `work/reading-list`, outside git, for reviewing
(docs/design/review.md): a series of three episodes and a compilation. Each episode folder holds a
video, its narration (a real WAV), a script, two covers at 4:3 and 16:9 with the 4:3 one's SVG
beside it, and the inputs a renderer read; the compilation folder holds the compilation and its
chapters, and a logo sits at the top. A session asked three hours ago answers once everything is
written, naming episode 1's video and script, the folder `ep02/`, episode 3's video and the
compilation; everything else is only observed, by it and, for the covers, by a second session. A
video already at its path is kept (the tour writes real ones first); otherwise a placeholder
stands in. Beside it, `work/masters`, a Git repository that ignores `*.mov`, holds a 65 MiB master
a third session names: over the save limit, so a verdict on it keeps its bytes only when asked.
Phase review-revise then recuts episode 1's video, and a new reply names it.

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


def claude_delivery(log, session, cwd, request, paths, model='claude-fable-5'):
    base = dict(sessionId=session, cwd=str(cwd), timestamp=now())
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as f:
        f.write(json.dumps(dict(base, type='user', origin={'kind': 'human'}, message={'content': request}), ensure_ascii=False) + '\n')
        f.write(json.dumps(dict(base, type='assistant', message={'model': model, 'content': [{'type': 'text', 'text': links(paths)}]}), ensure_ascii=False) + '\n')


def codex_delivery(thread, cwd, request, paths, provider='magpie', model='moonshot/kimi-k2.5'):
    day = datetime.date.today()
    log = codex / 'sessions' / f'{day:%Y}' / f'{day:%m}' / f'{day:%d}' / f'rollout-{day}-{thread}.jsonl'
    log.parent.mkdir(parents=True, exist_ok=True)
    at = now()
    with log.open('a') as f:
        # Codex through a local gateway, as Magpie routes it: the provider names the gateway, the
        # model its catalog reference.
        for payload, kind in ((dict(id=thread, cwd=str(cwd), thread_source='user', model_provider=provider), 'session_meta'),
                              (dict(turn_id='t1', cwd=str(cwd), model=model), 'turn_context'),
                              (dict(type='message', role='user', content=[dict(type='input_text', text=request)],
                                    internal_chat_message_metadata_passthrough=dict(content_item_kinds=['user.text'])), 'response_item'),
                              (dict(type='message', role='assistant', phase='final_answer',
                                    content=[dict(type='output_text', text=links(paths))]), 'response_item')):
            f.write(json.dumps(dict(timestamp=at, type=kind, payload=payload)) + '\n')
    with (codex / 'session_index.jsonl').open('a') as f:
        f.write(json.dumps(dict(id=thread, thread_name='Atlas feature demo', updated_at=at)) + '\n')


def claude_session(log, session, cwd, title, request, reply, start, end):
    """A Claude Code session asked at `start` and answering at `end`."""
    stamp = lambda t: t.isoformat().replace('+00:00', 'Z')
    base = dict(sessionId=session, cwd=str(cwd))
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('a') as f:
        f.write(json.dumps(dict(base, type='user', timestamp=stamp(start), origin={'kind': 'human'}, message={'content': request})) + '\n')
        f.write(json.dumps(dict(base, type='assistant', timestamp=stamp(end),
                                message={'model': 'claude-fable-5', 'content': [{'type': 'text', 'text': reply}]})) + '\n')
        f.write(json.dumps(dict(type='custom-title', sessionId=session, customTitle=title)) + '\n')


def dated(path, created, modified):
    """Sets a file's creation and modification dates: APFS moves the creation date back with an
    earlier modification date, then keeps it when the modification date moves forward again."""
    os.utime(path, (created.timestamp(), created.timestamp()))
    os.utime(path, (modified.timestamp(), modified.timestamp()))


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


def pdf(path, text):
    stream = f'BT /F1 24 Tf 72 720 Td ({text}) Tj ET'.encode()
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
               b'<< /Length %d >>\nstream\n' % len(stream) + stream + b'\nendstream',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    body, offsets = b'%PDF-1.4\n', []
    for n, o in enumerate(objects, 1):
        offsets.append(len(body))
        body += b'%d 0 obj\n' % n + o + b'\nendobj\n'
    xref = len(body)
    body += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offsets)
    path.write_bytes(body + b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref))


def picture(path, width, height, top, bottom):
    """A PNG of its own size, shaded from `top` to `bottom`, so it is seen at its own aspect."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    rows = b''.join(b'\0' + bytes(int(a + (b - a) * y / max(height - 1, 1)) for a, b in zip(top, bottom)) * width
                    for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def tone(path, seconds, pitch):
    """A real WAV, mono, 16-bit: a tone that rises and falls, to play in place."""
    import math
    rate = 8000
    samples = b''.join(struct.pack('<h', int(6000 * math.sin(2 * math.pi * pitch * (1 + 0.2 * math.sin(i / rate)) * i / rate)))
                       for i in range(int(rate * seconds)))
    path.write_bytes(b'RIFF' + struct.pack('<I', 36 + len(samples)) + b'WAVEfmt '
                     + struct.pack('<IHHIIHH', 16, 1, 1, rate, rate * 2, 2, 16) + b'data' + struct.pack('<I', len(samples)) + samples)


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

elif phase == 'board':
    board, log = work / 'board', claude / 'board' / 'board.jsonl'
    (board / 'charts').mkdir(parents=True)
    (board / 'slides').mkdir()
    (board / 'report.md').write_text('# Board report\n\nRevenue grew 12%.\n\n## Risks\nDraft one.\n')
    png(board / 'charts' / 'revenue.png', (200, 40, 40))
    (board / 'slides' / 'board-deck.pptx').write_bytes(b'PK synthetic deck, not a real presentation\n')
    pdf(board / 'brief.pdf', 'Board brief')
    claude_delivery(log, 'board', board, 'Draft the board report, the revenue chart, the deck and a one-page brief',
                    [board / n for n in ('report.md', 'charts/revenue.png', 'slides/board-deck.pptx', 'brief.pdf')])

elif phase == 'board-revise':
    board, log = work / 'board', claude / 'board' / 'board.jsonl'
    (board / 'report.md').write_text('# Board report\n\nRevenue grew 12%, ahead of plan.\n\n## Risks\nTightened.\n')
    png(board / 'charts' / 'revenue.png', (40, 80, 200))
    claude_delivery(log, 'board', board, 'Tighten the report and recolor the chart', [board / 'report.md', board / 'charts' / 'revenue.png'])

elif phase == 'board-final':
    board, log = work / 'board', claude / 'board' / 'board.jsonl'
    (board / 'report.md').rename(board / 'board-report-final.md')
    claude_delivery(log, 'board', board, 'Name the report as the final board version', [board / 'board-report-final.md'])
    png(board / 'charts' / 'revenue-v2.png', (40, 160, 80))
    claude_delivery(log, 'board', board, 'Keep the old chart and save a v2 with the new palette', [board / 'charts' / 'revenue-v2.png'])
    (board / 'brief.pdf').unlink()
    (board / 'appendix.md').write_text('# Board appendix\n\nNumbers behind the chart.\n')
    claude_delivery(claude / 'client-a-app' / 'client-a.jsonl', 'client-a', work / 'client-a' / 'app',
                    'Export the board appendix', [board / 'appendix.md'], model='deepseek-v4-flash')

elif phase == 'capture':
    series = work / 'series'
    start = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) - datetime.timedelta(hours=3)
    at = lambda minutes: start + datetime.timedelta(minutes=minutes)

    def made(relative, minutes, data=b'synthetic\n', changed=None):
        path = series / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        dated(path, at(minutes), at(changed if changed is not None else minutes))

    made('scripts/render.py', 5, b'print("render the episode")\n')
    made('data/segments.csv', 15, b'segment,start,end\n0,0.0,4.2\n')
    for n in range(40):
        made(f'out/voice/line-{n:03}.wav', 10 + n / 4, b'RIFF synthetic voice line\n')
    made('out/ep00.inputs.json', 25, b'{"voice": "out/voice", "segments": "data/segments.csv"}\n')
    made('out/ep00.narration.wav', 30, b'RIFF synthetic narration\n')
    made('out/ep00.mix.wav', 35, b'RIFF synthetic mix\n')
    sparse(series / 'out' / 'ep00.mp4', b'synthetic episode header\n')
    dated(series / 'out' / 'ep00.mp4', at(40), at(40))
    made('episodes/00-overview/notes/outline.md', 50, b'# Overview\n\nWhat the episode covers.\n')
    made('covers/ov-4x3.svg', 70, b'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="3"/>\n')
    png(series / 'covers' / 'ov-4x3.png', (90, 60, 30))
    dated(series / 'covers' / 'ov-4x3.png', at(75), at(75))
    # Created and changed the day before: outside every span.
    made('notes/plan.md', -48 * 60, b'# Plan\n', changed=-24 * 60)

    # Both answer now, once every file above is written.
    answered = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) + datetime.timedelta(seconds=1)
    claude_session(claude / 'series' / 'series.jsonl', 'series', series, 'Reading list series, episode 0',
                   'Render episode 0 with its narration and covers', 'Everything is in [out](out/).', at(0), answered)
    claude_session(claude / 'series' / 'series-covers.jsonl', 'series-covers', series, 'Series covers',
                   'Draw the 4:3 cover', 'The covers are ready.', at(60), answered)

elif phase == 'bundle':
    launch = work / 'launch'
    site, renders, app = launch / 'site', launch / 'renders', launch / 'app'
    start = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) - datetime.timedelta(hours=2)
    at = lambda minutes: start + datetime.timedelta(minutes=minutes)

    def made(path, minutes, data=b'synthetic\n'):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        dated(path, at(minutes), at(minutes))

    made(site / 'index.html', 10, b'<!doctype html><title>Launch</title><link rel="stylesheet" href="css/style.css">'
                                  b'<img src="assets/hero.png"><script src="js/app.js"></script>\n')
    made(site / 'css' / 'style.css', 11, b'body { font: 16px system-ui; }\n')
    made(site / 'js' / 'app.js', 12, b'console.log("launch")\n')
    made(site / '.env', 9, b'DEPLOY_TOKEN=synthetic-not-a-secret\n')
    made(site / '.DS_Store', 9)
    app.mkdir(parents=True)
    git(app, 'init', '-q', '-b', 'main')
    (app / 'README.md').write_text('# Launch app\n')
    git(app, 'add', '.')
    git(app, 'commit', '-q', '-m', 'init')
    log = claude / 'launch' / 'launch.jsonl'
    claude_session(log, 'launch', launch, 'Launch site', 'Build the launch site and set up the app',
                   f'The [site]({site}/) is built, and the [app]({app}) is set up.', at(0), at(60))

    # After the first reply: only the second hands these over.
    (site / 'assets').mkdir()
    png(site / 'assets' / 'hero.png', (30, 90, 200))
    renders.mkdir()
    for n in range(30):
        png(renders / f'frame-{n:03}.png', (n * 8, 120, 160))
    (renders / '.DS_Store').write_bytes(b'synthetic\n')
    answered = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) + datetime.timedelta(seconds=1)
    claude_session(log, 'launch', launch, 'Launch site', 'Add the hero image and export the renders',
                   f'The [site]({site}/) has its hero image; the [renders]({renders}/) are exported.', at(90), answered)

elif phase == 'review':
    series = work / 'reading-list'
    start = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) - datetime.timedelta(hours=3)
    at = lambda minutes: start + datetime.timedelta(minutes=minutes)

    def made(relative, minutes, write):
        path = series / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        write(path)
        dated(path, at(minutes), at(minutes))

    def video(path):
        # The tour writes real videos first; a person's own run gets a placeholder.
        if not path.exists():
            path.write_bytes(b'synthetic video, not a real movie\n')

    colors = [((40, 70, 140), (120, 170, 230)), ((140, 60, 40), (240, 170, 120)), ((40, 110, 70), (150, 220, 160))]
    for n, (top, bottom) in enumerate(colors, 1):
        ep, base = f'ep{n:02}', 20 * n
        made(f'{ep}/{ep}.inputs.json', base, lambda p: p.write_text(json.dumps({'episode': n, 'voice': 'narrator-a'}) + '\n'))
        made(f'{ep}/script.md', base + 1, lambda p: p.write_text(
            f'# Episode {n}\n\nThe reading list, part {n}.\n\n## Open\nA line to open on.\n\n## Close\nWhat to read next.\n'))
        made(f'{ep}/{ep}.narration.wav', base + 2, lambda p: tone(p, 3, 220 + 60 * n))
        made(f'{ep}/{ep}.mp4', base + 3, video)
        made(f'{ep}/cover-4x3.svg', 70 + n, lambda p: p.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="#%02x%02x%02x"/></svg>\n' % top))
        made(f'{ep}/cover-4x3.png', 72 + n, lambda p: picture(p, 400, 300, top, bottom))
        made(f'{ep}/cover-16x9.png', 74 + n, lambda p: picture(p, 640, 360, bottom, top))
    made('compilation/chapters.md', 90, lambda p: p.write_text('# Chapters\n\n1. Episode 1\n2. Episode 2\n3. Episode 3\n'))
    made('compilation/reading-list.mp4', 95, video)
    made('logo.png', 96, lambda p: picture(p, 256, 256, (30, 30, 30), (90, 90, 90)))

    # Both answer now, once every file above is written.
    answered = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) + datetime.timedelta(seconds=1)
    names = [series / 'ep01' / 'ep01.mp4', series / 'ep01' / 'script.md', series / 'ep03' / 'ep03.mp4',
             series / 'compilation' / 'reading-list.mp4']
    claude_session(claude / 'reading-list' / 'reading-list.jsonl', 'reading-list', series, 'Reading list series',
                   'Render the three episodes and the compilation',
                   f'Episode 1 is [rendered]({names[0]}) with its [script]({names[1]}); [episode 2]({series / "ep02"}/) '
                   f'is done; [episode 3]({names[2]}) and the [compilation]({names[3]}) too.', at(0), answered)
    claude_session(claude / 'reading-list' / 'reading-list-covers.jsonl', 'reading-list-covers', series, 'Series covers',
                   'Draw the covers at 4:3 and 16:9', 'The covers are ready.', at(60), answered)
    masters = work / 'masters'
    masters.mkdir(parents=True, exist_ok=True)
    git(masters, 'init', '-q')
    (masters / '.gitignore').write_text('*.mov\n')
    sparse(masters / 'reading-list-master.mov', b'synthetic master, not a real movie\n')
    claude_session(claude / 'masters' / 'masters.jsonl', 'masters', masters, 'Masters', 'Render the master',
                   f'The [master]({masters / "reading-list-master.mov"}) is rendered.', at(100), answered)

elif phase == 'review-revise':
    series = work / 'reading-list'
    recut = series / 'ep01' / 'ep01.mp4'
    # Trailing bytes a player ignores: other bytes at the same path.
    with recut.open('ab') as f:
        f.write(b'\0' * 64)
    asked = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0) - datetime.timedelta(minutes=1)
    answered = asked + datetime.timedelta(minutes=1, seconds=1)
    claude_session(claude / 'reading-list' / 'reading-list.jsonl', 'reading-list', series, 'Reading list series',
                   'Recut episode 1 with a shorter open', f'Episode 1 is [recut]({recut}).', asked, answered)

else:
    raise SystemExit(__doc__)
print(f'{home}: {phase}')
