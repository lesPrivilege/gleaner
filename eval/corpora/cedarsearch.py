#!/usr/bin/env python3
"""Writes CedarSearch, the four-week project of docs/design/project-knowledge-explorations.md, as
a frozen home with gold for questions Q3 (thread), Q4 (stream) and Q5 (section) of
docs/design/questions.md (work order docs/work-orders/2026-10-22-cedarsearch-home.md).

    eval/corpora/cedarsearch.py <seed> <out>                      write the home
    eval/corpora/cedarsearch.py <seed> <out> --check [--no-build] write it twice, prepare it, check it

Each task's folder <out>/seed-<seed>/<task>/ holds world/ and task.json as E0's do, and its gold
goes to <out>/gold/seed-<seed>/<task>/ (history.gold_folder). The three worlds hold the same
project, byte for byte: the repository work/cedarsearch, a ranking worktree beside it and a release
worktree inside it, removed on day 22; three conversations and eight handovers over 25 days, all
in epoch 0. Only the decoys differ, drawn for each task's words as E0's are.

The module imports eval/worlds.py and eval/history.py and changes nothing at eval/*.py, which the
scored seeds' lock hashes. It lives a folder down because run.py's glob of eval/*.py is not
recursive.

Epoch 0 means Gleaner first reads every file when the home is prepared, weeks after its reply.
So every capture is first_seen_after_delivery, comparison.html's day-9 bytes are gone, and the
release worktree's files were never observed. The gold says so (`limits`).

Write the home in a folder with no symbolic link in its path, outside /tmp and /private, and not
under a folder named .claude/worktrees, which Gleaner reads as an agent's worktree.
"""
import argparse
import contextlib
import json
import os
import random
import shutil
import sqlite3
import sys

EVAL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, EVAL)

import check_worlds  # noqa: E402
import history  # noqa: E402
import prepare  # noqa: E402
import worlds  # noqa: E402
from worlds import DAY, SAVE_LIMIT, Cursor, doc, expect, gold, ref, sha256, svg  # noqa: E402

TASKS = ('Q03', 'Q04', 'Q05')
MAIN = 'work/cedarsearch'
# The ranking worktree lies beside the repository and is never removed. The release worktree lies
# inside it: removed before Gleaner first reads the home, it folds into the repository only through
# the folder that held it (rulings §2). Beside the repository it would resolve to whatever
# repository holds the world, the gleaner checkout itself under build/.
RANKING, RELEASE = 'work/cedarsearch-ranking', 'work/cedarsearch/.worktrees/release'
# The project's start, in days before the base date: its newest handover, on day 25, is ten days old.
START = 35


class Claude(worlds.Claude):
    """A Claude Code log whose records name the branch its worktree has checked out."""

    def __init__(self, world, project, cwd, branch):
        super().__init__(world, project, cwd)
        self.branch = branch

    def _append(self, epoch, record):
        if 'gitBranch' in record:
            record = dict(record, gitBranch=self.branch)
        return super()._append(epoch, record)


class Codex(worlds.Codex):
    """A Codex rollout whose session_meta names the branch its worktree has checked out."""

    def __init__(self, world, project, start, title, branch):
        self.branch = branch
        super().__init__(world, project, start, title)

    def _record(self, t, kind, payload):
        if kind == 'session_meta':
            payload = dict(payload, git=dict(branch=self.branch))
        return super()._record(t, kind, payload)


SOURCES = {
    'README.md': '# CedarSearch\n\nLocal full-text search over your documents.\n',
    '.gitignore': '.build/\n.worktrees/\ntmp/\n',
    'src/index.swift': 'struct Posting { var document: Int; var positions: [Int] }\n\n'
                       'final class Index {\n    var postings: [String: [Posting]] = [:]\n}\n',
    'src/query.swift': 'func tokens(_ query: String) -> [String] {\n'
                       '    query.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)\n}\n',
}


def worktree(w, tree, branch, at):
    """Adds a worktree on a new branch. Git checks its files out at the moment it runs, so they are
    written again, the same bytes, with `at` for their time."""
    w.git(0, MAIN, at, 'worktree', 'add', '-q', '-b', branch, os.path.relpath(tree, MAIN))
    for rel, text in SOURCES.items():
        w.write(0, f'{tree}/{rel}', at, text=text)


def comparison(multilingual):
    rows = '<tr><td>A</td><td>0.61</td><td>205 ms</td></tr>\n<tr><td>B</td><td>0.63</td><td>310 ms</td></tr>\n'
    limits = ('<h2>Limitations</h2>\n<ul>\n<li>English documents only.</li>\n'
              + ('<li>Multilingual: on German and Japanese queries A drops to nDCG@10 0.41 and B to 0.52; '
                 'neither was tuned for them.</li>\n' if multilingual else '') + '</ul>\n')
    return ('<!doctype html>\n<html><head><meta charset="utf-8"><title>Ranking comparison</title></head><body>\n'
            '<h1>Ranking options on one benchmark</h1>\n'
            '<p>Both options on the 10,000-document sample corpus: '
            '<a href="option-a.md">option A</a>, <a href="option-b.md">option B</a>.</p>\n'
            f'<table>\n<tr><th>Option</th><th>nDCG@10</th><th>p95</th></tr>\n{rows}</table>\n'
            '<img src="error-breakdown.svg" alt="Errors by query class">\n'
            f'{limits}</body></html>\n')


def cedarsearch(w):
    """The project, every operation in epoch 0 and recorded in the order it happened. Returns the
    three conversations, the handovers oldest first, the files' hashes and the baseline's text."""
    rng = w.rng
    s = -START * DAY

    def day(n):
        return s + n * DAY + rng.uniform(9, 16) * 3600

    made = s - rng.uniform(40, 60) * DAY
    for rel, text in SOURCES.items():
        w.write(0, f'{MAIN}/{rel}', made, text=text)
    w.git(0, MAIN, made, 'init', '-q', '-b', 'main')
    w.git(0, MAIN, made, 'add', '-A')
    w.git(0, MAIN, made, 'commit', '-q', '-m', 'Initial commit')
    w.repos['cedarsearch'] = w.path(MAIN)
    shas, handovers = {}, []

    def handover(session, n, t, line, request, files):
        handovers.append(dict(day=n, session=session, at=history.iso(w.base + t), line=line, request=request,
                              files=files))

    # Day 0: conversation A, Claude Code on main.
    a = Claude(w, 'cedarsearch', w.path(MAIN), 'main')
    c = Cursor(rng, day(0))
    p50, queries = rng.randint(60, 90), rng.randint(400, 600)
    baseline = ('# Baseline\n\nSearch latency of CedarSearch before any ranking change.\n\n'
                '## Method\n\n'
                f'- {queries} recorded queries replayed against a 10,000-document corpus.\n'
                '- Each query run five times; the first run discarded.\n\n'
                '## Results\n\n'
                f'The p95 latency is 180 ms on the 10,000-document corpus; the p50 is {p50} ms.\n\n'
                '## Limitations\n\n'
                '- English documents only.\n'
                '- One machine with a warm cache; cold starts were not measured.\n'
                '- The corpus is the sample set, not a user library.\n')
    request = 'Measure the baseline search latency of CedarSearch and write up the method, the results and their limitations.'
    a.user(0, c(), request)
    a.text(0, c(), "I'll replay the recorded queries against the sample corpus first.")
    t = c()
    a.bash(0, t, f'swift run cedarbench --corpus samples/10k --queries {queries} --out bench/benchmark.csv',
           f'{queries} queries x 5 runs\np50 {p50} ms  p95 180 ms\nwrote bench/benchmark.csv', after=30.0)
    shas[f'{MAIN}/bench/benchmark.csv'] = w.write(0, f'{MAIN}/bench/benchmark.csv', round(t + 25, 3), text=(
        'query,p50_ms,p95_ms\n' + ''.join(f'q{n:03d},{rng.randint(40, 120)},{rng.randint(120, 240)}\n' for n in range(1, 13))))
    c.t = t + 30
    shas[f'{MAIN}/bench/latency.svg'] = a.write(0, c(), 'bench/latency.svg', svg(
        'query latency (ms), p50 and p95', [rng.randint(30, 90) for _ in range(6)]))
    shas[f'{MAIN}/bench/baseline.md'] = a.write(0, c(), 'bench/baseline.md', baseline)
    t = c()
    line = a.reply(0, t, 'The baseline is measured:\n\n'
                         '- [baseline.md](bench/baseline.md): method, results and limitations\n'
                         '- [latency.svg](bench/latency.svg): p50 and p95 by query\n'
                         '- [benchmark.csv](bench/benchmark.csv): the raw timings\n')
    a.title(0, 'CedarSearch latency baseline')
    handover(a, 0, t, line, request, [f'{MAIN}/bench/baseline.md', f'{MAIN}/bench/latency.svg', f'{MAIN}/bench/benchmark.csv'])

    # Conversation B: one Claude Code log in the ranking worktree, resumed over 22 days.
    worktree(w, RANKING, 'ranking', day(2))
    b = Claude(w, 'cedarsearch', w.path(RANKING), 'ranking')

    def turn(n, request, writes, reply, before=None):
        c = Cursor(rng, day(n))
        b.user(0, c(), request)
        if before:
            before(c)
        for rel, content in writes:
            shas[f'{RANKING}/{rel}'] = b.write(0, c(), rel, content)
        t = c()
        handover(b, n, t, b.reply(0, t, reply), request, [f'{RANKING}/{rel}' for rel in reply_order(reply)])

    turn(3, 'Write up ranking option A, BM25 with a title boost, and implement it.', [
        ('docs/option-a.md', doc('Ranking option A: BM25 with a title boost', rng,
                                 ['Benchmark: the 10,000-document sample corpus.', 'nDCG@10 0.61, p95 205 ms.'])),
        ('src/ranker-a.swift', 'func scoreA(_ tf: Double, _ df: Double, title: Bool) -> Double {\n'
                               '    let bm25 = tf * 2.2 / (tf + 1.2) * log(10_000 / df)\n'
                               '    return title ? bm25 * 1.5 : bm25\n}\n')],
        'Option A is written up and implemented:\n\n'
        '- [option-a.md](docs/option-a.md): the approach and its numbers\n'
        '- [ranker-a.swift](src/ranker-a.swift): the ranker\n')
    b.title(0, 'CedarSearch ranking options')

    corpus = rng.choice(['news-5k', 'forum-8k'])
    turn(5, 'Now write up option B, the learned reranker, as an alternative to A, and implement it too.', [
        ('docs/option-b.md', doc('Ranking option B: a learned reranker', rng,
                                 [f'Benchmark: the {corpus} corpus, not the sample set.', 'nDCG@10 0.66, p95 310 ms.'])),
        ('src/ranker-b.swift', 'func scoreB(_ features: [Double], weights: [Double]) -> Double {\n'
                               '    zip(features, weights).reduce(0) { $0 + $1.0 * $1.1 }\n}\n')],
        'Option B is an alternative to A, measured on a different corpus:\n\n'
        '- [option-b.md](docs/option-b.md)\n'
        '- [ranker-b.swift](src/ranker-b.swift)\n')

    def plots(c):
        # Both charts come from one script; only one is named in the reply, the other is embedded.
        t = c()
        b.bash(0, t, 'python3 scripts/plot_comparison.py --out docs/',
               'wrote docs/quality-v-latency.svg\nwrote docs/error-breakdown.svg', after=4.0)
        for rel, label in (('docs/quality-v-latency.svg', 'nDCG@10 against p95 latency'),
                           ('docs/error-breakdown.svg', 'errors by query class')):
            shas[f'{RANKING}/{rel}'] = w.write(0, f'{RANKING}/{rel}', round(t + 2, 3),
                                               text=svg(label, [rng.randint(10, 90) for _ in range(6)]))
        c.t = t + 4

    turn(9, 'Compare A and B on one benchmark, with a chart of quality against latency.',
         [('docs/comparison.html', comparison(False))],
         'The comparison runs both options on the sample corpus:\n\n'
         '- [comparison.html](docs/comparison.html): the table and the error breakdown\n'
         '- [quality-v-latency.svg](docs/quality-v-latency.svg): quality against latency\n', before=plots)
    shas['comparison.html on day 9'] = shas.pop(f'{RANKING}/docs/comparison.html')

    turn(12, 'Record the ranking decision as an ADR.', [
        ('docs/adr-004-ranking.md', '# ADR 004: Ranking for the first release\n\nStatus: Accepted\n\n'
                                    '## Decision\n\nOption A, BM25 with a title boost, ships in the first release.\n\n'
                                    '## Consequences\n\nMultilingual evaluation is deferred to after the first release.\n')],
        'Recorded: [adr-004-ranking.md](docs/adr-004-ranking.md). A is accepted for the first release; the multilingual '
        'evaluation is deferred.')

    turn(16, 'Add what we found about multilingual queries to the comparison.',
         [('docs/comparison.html', comparison(True))],
         'Updated [comparison.html](docs/comparison.html) with the multilingual limitation.')

    # Day 18-19: the release worktree, and conversation C, Codex, in it.
    worktree(w, RELEASE, 'release', day(18))
    w.repos['cedarsearch-release'] = w.path(RELEASE)
    codex = Codex(w, 'cedarsearch-release', day(19), 'CedarSearch 0.4.0 release candidate', 'release')
    codex.project = 'cedarsearch'
    c = Cursor(rng, codex.start)
    request = 'Prepare the CedarSearch 0.4.0 release candidate: the release notes and a signed installer.'
    codex.turn(c(), request)
    codex.say(c(), 'Writing the notes, then building and signing the installer.')
    notes = ('# CedarSearch 0.4.0-rc1\n\n- Results are ordered by BM25 with a title boost.\n'
             '- Search stays under 200 ms p95 on 10,000 documents.\n- English documents only in this release.\n')
    (shas[f'{RELEASE}/docs/release-notes.md'],) = codex.shell(
        c(), f"mkdir -p docs && cat > docs/release-notes.md <<'EOF'\n{notes}EOF", '', files=[('docs/release-notes.md', notes)])
    t = c()
    codex.shell(t, 'make dmg VERSION=0.4.0-rc1 SIGN=1', 'signed and notarized dist/CedarSearch-0.4.0-rc1.dmg (65.0 MiB)')
    dmg = f'{RELEASE}/dist/CedarSearch-0.4.0-rc1.dmg'
    # Over the save limit, so Gleaner would keep its hash only, had it ever read it.
    shas[dmg] = w.write(0, dmg, round(t + 0.5, 3),
                        sparse=(f'koly synthetic CedarSearch 0.4.0-rc1 installer {w.hex(12)}\n', SAVE_LIMIT + (1 << 20)))
    t = c()
    codex.shell(t, 'git add dist/CedarSearch-0.4.0-rc1.dmg && git commit -m "Add the 0.4.0-rc1 installer"',
                '[release] Add the 0.4.0-rc1 installer\n 1 file changed, 0 insertions(+), 0 deletions(-)')
    w.git(0, RELEASE, t + 0.5, 'add', 'dist/CedarSearch-0.4.0-rc1.dmg')
    w.git(0, RELEASE, t + 0.5, 'commit', '-q', '-m', 'Add the 0.4.0-rc1 installer')
    t = c()
    line = codex.final(t, 'The 0.4.0 release candidate is ready: notes in [release-notes.md](docs/release-notes.md), and the '
                          'installer [CedarSearch-0.4.0-rc1.dmg](dist/CedarSearch-0.4.0-rc1.dmg) is signed and ready to ship.')
    handover(codex, 19, t, line, request, [f'{RELEASE}/docs/release-notes.md', dmg])

    # Day 22: the release worktree is removed, its notes never committed.
    w.git(0, MAIN, day(22), 'worktree', 'remove', '--force', os.path.relpath(RELEASE, MAIN))

    # Day 25: B resumed.
    turn(25, 'Does option A still suit us, given the multilingual results? Write up a follow-up.', [
        ('docs/follow-up.md', doc('Follow-up: multilingual ranking', rng,
                                  ['A falls behind B on German and Japanese queries.',
                                   'Open question: is A still right beyond the first release?',
                                   'ADR 004 stands until this is decided.'])),
        ('docs/multilingual.svg', svg('nDCG@10 by language, A and B', [rng.randint(30, 80) for _ in range(6)]))],
        'The follow-up questions whether A suits multilingual search; it does not replace ADR 004:\n\n'
        '- [follow-up.md](docs/follow-up.md)\n'
        '- [multilingual.svg](docs/multilingual.svg): quality by language\n')
    shas['comparison.html on day 16'] = shas.pop(f'{RANKING}/docs/comparison.html')
    return dict(a=a, b=b, c=codex, handovers=handovers, shas=shas, baseline=baseline)


def reply_order(reply):
    """The files a reply links, in its order."""
    return [part.split(')')[0] for part in reply.split('](')[1:]]


LIMITS = [
    'Every file was first read when the home was prepared, long after its reply: every capture is '
    'first_seen_after_delivery.',
    "The day-9 bytes of comparison.html are not preserved. The file was rewritten on day 16, before Gleaner first read "
    "it, so both of its deliveries hold the day-16 bytes. The sample's older saved copy of the earlier version is not "
    'reproduced here; scripts/acceptance-home.py (second phase) covers it.',
    'The release worktree was removed on day 22, before Gleaner first read the home, so its two files were never '
    'observed: no hash, availability none, hand-off plan lost. The installer is committed on the release branch, but '
    'Gleaner recorded no checkout for a delivery it never observed, so it offers no restore from git. The notes were '
    'never committed. The sample\'s "only notes have saved bytes" is not reproduced here.',
    'The release worktree lies inside the repository (work/cedarsearch/.worktrees/release), not beside it as the work '
    'order names it: removed before Gleaner first read it, only a worktree inside its repository still folds into '
    'the project (rulings §2).',
]


def entry(h):
    """A handover as the gold names it: its log, agent, reply line, day and time, request and files."""
    session = h['session']
    return dict(log=session.log, session=session.id, agent=session.provider, line=h['line'], day=h['day'], at=h['at'],
                request=h['request'], files=h['files'])


def library(p, words):
    """What the prepared library must hold: every delivery of the eight handovers, the same for all
    three tasks, and what `gleaner find` returns for the task's words, with and without the project."""
    shas, release = p['shas'], p['handovers'][6]
    deliveries = []
    for h in p['handovers']:
        for path in h['files']:
            if h is release:
                fields = dict(sha256=None, provenance='never_observed', saved=False, availability='none', plan='lost')
            elif path.endswith('comparison.html'):
                fields = dict(sha256=shas['comparison.html on day 16'], provenance='first_seen_after_delivery', saved=True,
                              number=1 if h['day'] == 9 else 2, of=2, availability='original')
            else:
                fields = dict(sha256=shas[path], provenance='first_seen_after_delivery', saved=True)
            deliveries.append(expect(h['session'], path, h['line'], reply_line=h['line'], **fields))
    return dict(
        deliveries=deliveries,
        not_delivered=[f'{RANKING}/docs/error-breakdown.svg'],
        # Bytes no capture or saved copy holds: rewritten before Gleaner first read the file.
        absent=[dict(path=f'{RANKING}/docs/comparison.html', sha256=shas['comparison.html on day 9'],
                     why='the day-9 bytes, rewritten on day 16 before Gleaner first read the file')],
        disk={f'{RANKING}/docs/comparison.html': shas['comparison.html on day 16'],
              f'{RANKING}/docs/error-breakdown.svg': shas[f'{RANKING}/docs/error-breakdown.svg'],
              **{path: None for path in release['files']}},
        # Each reply's files, in the order of the replies' times.
        handovers=[dict(log=h['session'].log, line=h['line'], files=h['files']) for h in p['handovers']],
        find=[dict(words=words, paths=sorted(words_find(p, words))),
              dict(words=words, project='cedarsearch', paths=sorted(words_find(p, words)))])


def words_find(p, words):
    """The files `gleaner find` returns for the task's words: those of every handover whose request,
    reply, session title, file name, folders or project hold each word (SPEC §10)."""
    return {path for h in p['handovers'] for path in h['files'] if FINDS[tuple(words)](h)}


# Which handovers each task's words reach. B's title holds "ranking"; every handover is in the
# project cedarsearch; A's reply holds both "baseline" and "limitations", and names three files.
FINDS = {('ranking',): lambda h: h['day'] in (3, 5, 9, 12, 16, 25),
         ('cedarsearch',): lambda h: True,
         ('baseline', 'limitations'): lambda h: h['day'] == 0}


def built(w, words):
    """E0's usual projects, then CedarSearch, then decoys for the task's words."""
    w.projects()
    p = cedarsearch(w)
    w.decoys(words, w.rng.randint(1, 3), w.rng.randint(1, 2))
    return p


def q03(w):
    words = ['ranking']
    p = built(w, words)
    b = p['b']
    thread = [entry(h) for h in p['handovers'] if h['session'] is b]
    question = worlds.task(w, 'Where did the ranking conversation leave off?', words, 'thread')
    answer = dict(log=b.log, session=b.id, agent=b.provider, handovers=thread, last=thread[-1],
                  excluded=[dict(log=h['session'].log, line=h['line'], why='another conversation in the same project')
                            for h in p['handovers'] if h['session'] is not b])
    return question, gold(w, answer, library(p, words), ['other_thread_as_member'])


def q04(w):
    words = ['cedarsearch']
    p = built(w, words)
    stream = [entry(h) for h in reversed(p['handovers'])]
    assert [h['day'] for h in stream[:4]] == [25, 19, 16, 12]
    question = worlds.task(w, 'What are the latest handovers in CedarSearch?', words, 'stream', project='cedarsearch')
    answer = dict(project='cedarsearch', handovers=stream, latest_four=stream[:4],
                  excluded=[dict(path=f'{RANKING}/docs/error-breakdown.svg',
                                 why='embedded by comparison.html and named only in tool output, never in a reply'),
                            dict(sessions='every session with a role', why='decoys and near misses, in other projects')])
    return question, gold(w, answer, library(p, words), ['embedded_as_delivery', 'decoy_as_member', 'order_lost'])


def q05(w):
    words = ['baseline', 'limitations']
    p = built(w, words)
    h = p['handovers'][0]
    data = p['baseline'].encode('utf-8')
    start = data.index(b'## Limitations')
    question = worlds.task(w, 'The Limitations section of the baseline report', words, 'section', heading='Limitations')
    answer = dict(delivery=ref(p['a'], h['files'][0], h['line']), sha256=sha256(data),
                  heading=dict(text='Limitations', level=2), range=[start, len(data)],
                  lines=[data[:start].count(b'\n') + 1, data.count(b'\n')], text=data[start:].decode('utf-8'),
                  outline_matches=1, note='A section runs from its heading to the next of its level or above; '
                                          'Limitations is the last, so it runs to the end of the file.')
    lib = dict(library(p, words), section=dict(answer['delivery'], term='Limitations', level=2, sha256=answer['sha256'],
                                               range=answer['range'], lines=answer['lines'], text=answer['text']))
    return question, gold(w, answer, lib, ['range_from_other_bytes'])


BUILDERS = dict(Q03=q03, Q04=q04, Q05=q05)


def generate(seed, out, tasks=TASKS):
    """Writes the home for `seed` under `out` (<root>/seed-<n>) once per task, as worlds.generate
    does, and its gold under history.gold_folder; returns the world folders. Every task's world
    starts from the same random stream, so the project is the same in each."""
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
        world = worlds.World(name, os.path.join(folder, 'world'), random.Random(f'gleaner-cedarsearch:{seed}'))
        question, expected = BUILDERS[name](world)
        world.finish(gold_dir)
        worlds.dump(os.path.join(folder, 'task.json'), dict(question, family='Q'))
        worlds.dump(os.path.join(gold_dir, 'gold.json'), dict(expected, limits=LIMITS, seed=seed))
        folders.append(folder)
    return folders


# Checks

def deterministic(seed, out, tasks=TASKS):
    """check_worlds.deterministic for this module: writes the home twice in the same place and
    compares bytes and, inside the worlds, modification times. A worktree's `.git` file is git's
    own, as `.git` folders are, and is left out with them. Returns the folders, the files that
    differ and how many were compared."""
    folders = [os.path.join(out, f'seed-{seed}'), os.path.join(out, 'gold', f'seed-{seed}')]

    def contents():
        return {(n, path): data for n, folder in enumerate(folders)
                for path, data in check_worlds.contents(history.place(folder)).items()
                if os.path.basename(path) != '.git'}

    generate(seed, folders[0], tasks)
    first = contents()
    for folder in folders:
        shutil.rmtree(folder)
    made = generate(seed, folders[0], tasks)
    again = contents()
    differ = [(n, path) for n, path in set(first) | set(again) if first.get((n, path)) != again.get((n, path))]
    return made, sorted(os.path.join(folders[n], path) for n, path in differ), len(first)


def check(folder):
    """check_worlds.check, then what it doesn't know: bytes no capture may hold, each reply's files
    in the reply's order, the replies in time order, every delivery's delivered_with (the reply's
    other files, in its order), and for Q05 the section read back through outline and read. Returns
    every difference, as messages."""
    failures = check_worlds.check(folder)
    fail = failures.append
    with open(os.path.join(history.gold_folder(folder), 'gold.json'), encoding='utf-8') as f:
        expected = json.load(f)['library']
    library = check_worlds.Library(os.path.join(folder, 'world'))

    times = []
    with contextlib.closing(sqlite3.connect(f"file:{os.path.join(prepare.library_folder(library.world), 'registry.sqlite')}"
                                            '?mode=ro', uri=True)) as db:
        for h in expected['handovers']:
            rows = db.execute('SELECT path, delivered_at FROM deliveries WHERE log_path = ? AND reply_line = ? '
                              'ORDER BY reply_rank', (library.abs(h['log']), h['line'])).fetchall()
            if [library.rel(path) for path, _ in rows] != h['files']:
                fail(f"{h['log']}:{h['line']}: delivers {[library.rel(path) for path, _ in rows]}, expected {h['files']}")
            times.append(min(at for _, at in rows) if rows else None)
    if None in times or times != sorted(times):
        fail(f'the replies are not in the gold order: {times}')

    for item in expected['absent']:
        if any(row['sha256'] == item['sha256'] for row in library.rows) or library.saved(item['sha256']):
            fail(f"{item['path']}: the library holds {item['sha256'][:12]}, which no read could have seen")

    for h in expected['handovers']:
        for rel in h['files'] if len(h['files']) > 1 else ():
            others = [other for other in h['files'] if other != rel]
            status, shown = library.gleaner('show', delivery(library, rel, h['line']))
            together = [library.rel(d['path']) for d in (shown or {}).get('delivered_with', [])]
            if status != 0 or together != others:
                fail(f'show {rel}: exit {status}, delivered_with {together}, expected {others}')

    if 'section' in expected:
        section = expected['section']
        found = delivery(library, section['path'], section['line'])
        status, outline = library.gleaner('outline', found, section['term'])
        headings = (outline or {}).get('headings', [])
        if status != 0 or len(headings) != 1 or outline['ambiguous']:
            return failures + [f"outline {section['term']}: exit {status}, {len(headings)} headings, expected 1"]
        heading = headings[0]
        got = (heading['text'], heading['level'], heading['range'], heading['lines'], outline['reference']['sha256'])
        want = (section['term'], section['level'], section['range'], section['lines'], section['sha256'])
        if got != want:
            fail(f"outline {section['term']}: {got}, expected {want}")
        start, end = heading['range']
        status, read = library.gleaner('read', found, '--bytes', f'{start}:{end}')
        if status != 0 or (read['text'], read['reference']['sha256']) != (section['text'], section['sha256']):
            fail(f'read --bytes {start}:{end}: exit {status}, not the gold text of {section["sha256"][:12]}')
    return failures


def delivery(library, rel, line):
    """The id of the delivery of `rel` by the reply at `line`."""
    (row,) = [row for row in library.deliveries(rel) if row['reply_line'] == line]
    return row['id']


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('seed', type=int)
    parser.add_argument('out', help='a folder with no symbolic link in its path, outside /tmp and /private')
    parser.add_argument('--check', action='store_true', help='write the home twice, prepare it and check it')
    parser.add_argument('--no-build', action='store_true', help='with --check, use the app and command already built')
    args = parser.parse_args()
    out = history.place(args.out)
    if not args.check:
        for folder in generate(args.seed, os.path.join(out, f'seed-{args.seed}')):
            print(folder)
        return
    sys.stdout.reconfigure(line_buffering=True)
    if not args.no_build:
        check_worlds.build()
    os.makedirs(out, exist_ok=True)
    folders, differ, files = deterministic(args.seed, out)
    print(f'seed {args.seed}: written twice, {files} files compared, ' + (f'differ in {differ[:5]}' if differ else 'identical'))
    failed = bool(differ)
    for folder in folders:
        cost = prepare.prepare(folder, prepare.APP, say=lambda _: None)
        failures = check(folder)
        failed |= bool(failures)
        print(f"seed {args.seed} {os.path.basename(folder)}: {'ok' if not failures else 'FAILED'} (generation "
              f"{cost['generation']}, {cost['index_seconds']} s to index, {cost['saved_copies']} saved copies)")
        for failure in failures:
            print(f'    {failure}')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
