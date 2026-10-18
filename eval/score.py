#!/usr/bin/env python3
"""Scores evaluation E0's episodes against their gold (docs/design/evaluation-e0.md, "Scoring").

    eval/score.py [eval/results/<date>/results.json]

Reads the episodes run.py wrote, scores each answer against its world's gold.json, and writes
back into results.json:
- `rows`: one per episode: task, seed and policy; the answer's status and whether it is
  correct; the hard failures it commits; the evidence it cites and the scope it claims; bytes
  read, commands run, wall time and the preparation cost charged to it;
- `tables`: per policy, per family and per task, and the ratio of bytes read, G to R, overall
  and per family.
Then writes report.md beside it. The scorer knows the tasks; the policies never do.

Hard failures, as the evaluation names them, plus the task-specific ones each gold lists:
- false_global_absence: a negative beyond what its scope supports;
- current_as_delivered: current bytes passed off as a delivered version;
- hash_merge: two artifacts merged on a hash;
- tool_only_as_delivery: a tool-only file called a delivery.
"""
import json
import os
import sys

GENERAL = ('false_global_absence', 'current_as_delivered', 'hash_merge', 'tool_only_as_delivery')
FAMILIES = dict(E='shared information', S='recorded state', B='fallback')


class Check:
    """One answer against its gold, with paths made relative to the world."""

    def __init__(self, record, episode):
        self.world = record['world']
        self.gold = record['gold']
        self.expected = record['gold']['answer']
        self.answer = episode['answer'] or {}
        self.episode = episode
        self.failures = []
        self.why = []

    def rel(self, path):
        if not isinstance(path, str):
            return path
        return path[len(self.world) + 1:] if path.startswith(self.world + '/') else path

    def same(self, got, expected):
        """Whether a cited delivery is the expected one: its file, its log and its reply line."""
        if not got or not expected:
            return False
        if self.rel(got.get('path')) != expected['path'] or self.rel(got.get('log')) != expected['log']:
            return False
        return 'line' not in expected or got.get('line') == expected['line']

    def need(self, condition, why):
        if not condition:
            self.why.append(why)
        return bool(condition)

    def fail(self, kind, why):
        if kind not in self.failures:
            self.failures.append(kind)
        self.why.append(why)

    def disk(self, path):
        return self.gold['library'].get('disk', {}).get(path)

    def scope_logs(self):
        """The logs part of the scope an answer claims, or None."""
        scope = self.answer.get('scope') or {}
        if scope.get('kind') == 'catalog+logs':
            return scope.get('logs')
        return scope if scope.get('kind') == 'logs' else None

    def sessions(self):
        return [s for s in self.gold['sessions'] if not s.get('subagent')]

    def scope_complete(self):
        """Whether the scope a negative claims is complete and covers every session in the world."""
        scope = self.answer.get('scope') or {}
        if not scope.get('complete'):
            return False
        logs = self.scope_logs()
        if logs is not None:
            return logs.get('logs') == len(self.sessions())
        return scope.get('kind') == 'catalog'

    # By what the question asks

    def value(self):
        expected, answer = self.expected, self.answer
        delivery = answer.get('delivery') or {}
        path = expected['delivery']['path']
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(self.same(delivery, expected['delivery']), 'another delivery')
              & self.need(norm(answer.get('value')) == norm(expected['value']), f"value {answer.get('value')!r}")
              & self.need(answer.get('sha256') in (None, expected['sha256']), 'another version\'s hash'))
        current = [e['value'] for e in expected.get('excluded', []) if e['path'] == path]
        later = expected.get('later')
        if later and self.disk(path) == later['sha256']:
            current.append(later['value'])
        now = self.disk(path)
        if norm(answer.get('value')) in map(norm, current) or (answer.get('sha256') and answer.get('sha256') == now != expected['sha256']):
            self.fail('current_as_delivered', 'the value of the file as it is now')
        others = [e for e in expected.get('excluded', []) if e['path'] != path]
        if any(self.rel(delivery.get('path')) == e['path'] or norm(answer.get('value')) == norm(e['value']) for e in others):
            self.fail('wrong_project', 'the file of the same name in another project')
        if later and (norm(answer.get('value')) == norm(later['value']) or self.same(delivery, later['delivery'])):
            self.fail('mixed_occurrences', 'the later delivery, whose request did not match')
        return ok

    def files(self):
        expected, answer = self.expected, self.answer
        got = {self.rel(f.get('path')) for f in answer.get('files') or []}
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(got == set(expected['files']), f'files {sorted(got)}')
              & self.need(self.rel((answer.get('reply') or {}).get('log')) == expected['reply']['log'], 'another reply'))
        for excluded in expected.get('excluded', []):
            if excluded['path'] in got:
                kind = 'tool_only_as_delivery' if 'tool output' in excluded['why'] else 'neighbour_as_member'
                self.fail(kind, f"{excluded['path']}: {excluded['why']}")
        return ok

    def delivery(self):
        expected, answer = self.expected, self.answer
        chosen = answer.get('delivery') or {}
        status = answer.get('status')
        if 'delivery' in expected:
            ok = (self.need(status == 'found', 'not found')
                  & self.need(self.same(chosen, expected['delivery']), 'another file')
                  & self.need(chosen.get('claim') == 'delivery', 'not called a delivery')
                  & self.need(chosen.get('anchor') in (None, expected.get('anchor')), 'another anchor'))
            for item in [chosen] + list(answer.get('others') or []):
                for excluded in expected.get('excluded', []):
                    if item.get('claim') == 'delivery' and self.rel(item.get('path')) == excluded['path']:
                        kind = 'subagent_as_delivery' if 'sub-agent' in excluded['why'] else 'line_reference_as_delivery'
                        self.fail(kind, f"{excluded['path']}: {excluded['why']}")
            return ok
        if 'raw' in expected:
            raw = expected['raw']
            ok = (self.need(status == 'found', 'not found')
                  & self.need(self.rel(chosen.get('path')) == raw['path'], 'another file')
                  & self.need(self.rel(chosen.get('log')) == raw['log'] and chosen.get('line') == raw['line'], 'another reply')
                  & self.need(chosen.get('claim') != 'delivery', 'the mention called a delivery'))
            if status == 'found' and chosen.get('claim') == 'delivery':
                self.fail('mention_as_delivery', 'a bare file name in code called a delivery')
            if status == 'not_found' and self.scope_logs() is not None:
                self.fail('false_global_absence', 'the logs hold the mention')
            if any(self.rel(chosen.get('path')) == e['path'] for e in expected.get('excluded', [])):
                self.fail('wrong_project', 'the file of that name in another project')
            return ok
        ok = (self.need(status == 'not_found', 'not a negative')
              & self.need(self.scope_complete(), 'its scope is incomplete or does not cover every session'))
        if status == 'found':
            self.fail('false_join', 'terms from two requests joined')
        elif status == 'not_found' and not self.scope_complete():
            self.fail('false_global_absence', 'a negative beyond its scope')
        return ok

    def same_item(self):
        expected, answer = self.expected, self.answer
        got = {self.rel(a.get('path')) for a in answer.get('artifacts') or []}
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('same') is False, 'called one item')
              & self.need(all(a['path'] in got for a in expected['artifacts']), 'an artifact missing'))
        if answer.get('same') is True:
            self.fail('hash_merge', 'two artifacts merged on a hash')
        return ok

    def current_match(self):
        expected, answer = self.expected, self.answer
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('current_sha256') == expected['current_sha256'], 'another current hash')
              & self.need(answer.get('matches_latest') is False, 'said to match the latest')
              & self.need(self.same(answer.get('matches'), expected['matches']), 'matched another delivery'))
        if answer.get('matches_latest') is True or self.same(answer.get('matches'), expected['latest']):
            self.fail('latest_assumed_current', 'the latest delivery taken for the current file')
        return ok

    def provenance(self):
        expected, answer = self.expected, self.answer
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('established') is False, 'said to be established')
              & self.need(self.same(answer.get('delivery'), expected['delivery']), 'another delivery'))
        if answer.get('established') is True:
            self.fail('current_as_delivered', 'the bytes seen later passed off as the delivered ones')
            self.fail('certainty_from_mtime', 'certainty without an observation at delivery')
        return ok

    def offered(self, artifact):
        """The hash of what an answer offers for an artifact: a file it gave, or what git holds."""
        if artifact.get('bytes_file'):
            return self.episode['checked'].get(artifact['bytes_file'])
        if artifact.get('source') == 'git':
            return artifact.get('git_sha256') or artifact.get('sha256')
        return None

    def recover(self):
        expected, answer = self.expected, self.answer
        got = {self.rel(a.get('path')): a for a in answer.get('artifacts') or []}
        ok = self.need(answer.get('status') == 'found', 'not found')
        for wanted in expected['artifacts']:
            artifact = got.get(wanted['path'])
            if not self.need(artifact, f"{wanted['path']} missing"):
                ok = False
                continue
            offered = self.offered(artifact)
            if wanted['source'] == 'git':
                ok &= self.need(artifact.get('restore_command') or artifact.get('commit'), f"{wanted['path']}: no git restore")
                ok &= self.need(not artifact.get('recovered') or offered == wanted['sha256'], f"{wanted['path']}: other bytes")
            else:
                ok &= self.need(artifact.get('recovered') and offered == wanted['sha256'], f"{wanted['path']}: not recovered")
            if artifact.get('recovered') and offered != wanted['sha256']:
                self.fail('claimed_recovery', f"{wanted['path']}: recovered bytes that are not the delivery's")
        for excluded in expected.get('excluded', []):
            for artifact in got.values():
                if self.rel(artifact.get('path')) == excluded['path'] or (artifact.get('recovered') and self.offered(artifact) == excluded['sha256']):
                    self.fail('wrong_file_recovered', f"{excluded['path']}: {excluded['why']}")
        return bool(ok)

    def handed_over(self):
        expected, answer = self.expected, self.answer
        made = {self.rel(m.get('path')) for m in answer.get('generated') or []}
        delivered = {self.rel(p) for p in answer.get('reply_delivered') or []}
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('handed_over') is False, 'said to be handed over')
              & self.need(expected['generated']['path'] in made, 'not where it was generated')
              & self.need(expected['attempted']['path'] not in made, 'the attempt taken for a result'))
        if answer.get('handed_over') is True or expected['generated']['path'] in delivered:
            self.fail('tool_only_as_delivery', 'a file only tool output names called a delivery')
        if expected['attempted']['path'] in made:
            self.fail('attempt_as_result', 'a call with no result taken for its file')
        return ok

    def decision(self):
        expected, answer = self.expected, self.answer
        status = answer.get('status')
        ok = (self.need(status == 'unknown', f'status {status}')
              & self.need(self.rel((answer.get('session') or {}).get('log')) == expected['log'], 'another session')
              & self.need(answer.get('malformed_line') in (None, expected['malformed_line']), 'another boundary'))
        if status == 'found':
            self.fail('invented_decision', 'a decision the readable records do not hold')
        if status == 'not_found':
            self.fail('false_global_absence', 'no decision claimed past where the log can be read')
        return ok

    def referenced(self):
        expected, answer = self.expected, self.answer
        scope = self.scope_logs() or answer.get('scope') or {}
        wanted = {s['log'] for s in expected['scope']['sessions']}
        listed = {self.rel(p) for p in scope.get('sessions') or []}
        ok = (self.need(answer.get('referenced') is False, 'said to be referenced')
              & self.need((scope.get('project') or '').lower() == expected['scope']['project'], 'not scoped to the project')
              & self.need(scope.get('complete'), 'an incomplete scope')
              & self.need(listed == wanted, 'another set of sessions'))
        if answer.get('referenced') is False and (not scope.get('project') or not scope.get('complete')):
            self.fail('false_global_absence', 'a negative beyond the project\'s enumerated sessions')
        return ok

    def verify(self):
        expected, answer = self.expected, self.answer
        found = answer.get('bytes') or {}
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('original') is False, 'the path said to hold the delivery')
              & self.need(answer.get('saved_copy') is True or found.get('sha256') == expected['delivered_sha256'],
                          'the delivered version not located')
              & self.need(answer.get('current_sha256') in (None, expected['current_sha256']), 'another current hash'))
        if answer.get('original') is True:
            self.fail('stale_pointer_trusted', 'the pointer\'s path trusted')
        if found.get('sha256') and found['sha256'] == expected['current_sha256']:
            self.fail('current_as_delivered', 'the bytes now at the path passed off as the delivery')
        return ok

    def bytes(self):
        expected, answer = self.expected, self.answer
        offered = self.episode['checked'].get(answer.get('bytes_file')) if answer.get('bytes_file') else None
        drifted = expected['drifted_sha256']
        given = answer.get('status') == 'found' and answer.get('sha256') == expected['sha256'] and offered == expected['sha256']
        honest = (answer.get('status') in ('failed', 'unknown') and not self.episode.get('error')
                  and offered != drifted and answer.get('sha256') != drifted and bool(answer.get('note')))
        ok = self.need(given or honest, 'neither the delivered bytes nor an honest failure')
        if drifted in (offered, answer.get('sha256')):
            self.fail('current_as_delivered', 'the rewritten bytes passed off as the delivery')
        return ok


def norm(value):
    return ' '.join(str(value).split()).lower() if value is not None else None


def score_episode(record, episode):
    check = Check(record, episode)
    correct = bool(getattr(check, episode['asks'])()) and not check.failures and not episode.get('error')
    if episode.get('error'):
        check.why.append(episode['error'])
    answer = episode['answer'] or {}
    scope = answer.get('scope') or {}
    return dict(
        task=episode['task'], seed=episode['seed'], family=episode['family'], asks=episode['asks'],
        policy=episode['policy'], status=answer.get('status'), correct=correct, hard_failures=check.failures,
        why=check.why, fallback=answer.get('fallback'),
        evidence=answer.get('evidence') or [], scope=dict(kind=scope.get('kind'), complete=scope.get('complete')),
        bytes=episode['bytes']['total'], tilde_bytes=episode['bytes']['home_as_tilde'],
        commands=episode['command_count'], seconds=episode['seconds'],
        catalog_bytes=episode['phases'].get('catalog', {}).get('bytes', 0),
        raw_bytes=episode['phases'].get('raw', {}).get('bytes', 0),
        preparation=record['preparation'] if episode['policy'] == 'G' else None)


def summary(rows):
    n = len(rows)
    return dict(episodes=n, correct=sum(r['correct'] for r in rows),
                hard_failures=sum(bool(r['hard_failures']) for r in rows),
                general_failures=sum(any(f in GENERAL for f in r['hard_failures']) for r in rows),
                fallbacks=sum(bool(r['fallback']) for r in rows),
                bytes=sum(r['bytes'] for r in rows), tilde_bytes=sum(r['tilde_bytes'] for r in rows),
                commands=sum(r['commands'] for r in rows),
                seconds=round(sum(r['seconds'] for r in rows), 3))


def ratio(g, r):
    return round(g / r, 3) if r else None


def tables(rows, records):
    policies = sorted({r['policy'] for r in rows}, reverse=True)
    by = {}
    for row in rows:
        for key in [('all',), ('family', row['family']), ('task', row['task'])]:
            by.setdefault(key + (row['policy'],), []).append(row)
    out = dict(policies={p: summary(by[('all', p)]) for p in policies},
               families={f: {p: summary(by[('family', f, p)]) for p in policies if ('family', f, p) in by}
                         for f in sorted({r['family'] for r in rows})},
               tasks={t: {p: summary(by[('task', t, p)]) for p in policies if ('task', t, p) in by}
                      for t in sorted({r['task'] for r in rows})})
    if {'G', 'R'} <= set(policies):
        for name, key in (('bytes_ratio', 'bytes'), ('tilde_bytes_ratio', 'tilde_bytes')):
            out[name] = dict(
                all=ratio(out['policies']['G'][key], out['policies']['R'][key]),
                families={f: ratio(v['G'][key], v['R'][key]) for f, v in out['families'].items() if {'G', 'R'} <= set(v)},
                tasks={t: ratio(v['G'][key], v['R'][key]) for t, v in out['tasks'].items() if {'G', 'R'} <= set(v)})
    prep = [r['preparation'] for r in records]
    out['preparation'] = dict(worlds=len(prep), index_runs=sum(p['index_runs'] for p in prep),
                              index_seconds=round(sum(p['index_seconds'] for p in prep), 3),
                              library_bytes=sum(p['library_bytes'] for p in prep),
                              saved_copies=sum(p['saved_copies'] for p in prep))
    return out


def write(path):
    with open(path, encoding='utf-8') as f:
        results = json.load(f)
    records = {(w['seed'], w['task']): w for w in results['worlds']}
    rows = [score_episode(records[(e['seed'], e['task'])], e) for e in results['episodes']]
    results['rows'] = rows
    results['tables'] = tables(rows, results['worlds'])
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=1)
        f.write('\n')
    with open(os.path.join(os.path.dirname(path), 'report.md'), 'w', encoding='utf-8') as f:
        f.write(report(results))
    return results


def report(results):
    t = results['tables']
    env = results['environment']
    seeds = ('Seed ' if len(results['seeds']) == 1 else 'Seeds ') + ', '.join(map(str, results['seeds']))
    policies = list(t['policies'])
    lines = [
        '# Evaluation E0: results',
        '',
        f"{seeds}; {len(results['tasks'])} tasks; policies {', '.join(policies)}. Run {results['created']} "
        f"on macOS {env.get('macos')} at commit {(env.get('commit') or '')[:7]}, with {env.get('rg')}, {env.get('jq')}, "
        f"{env.get('git')} and Python {env.get('python')}. "
        + ('Seeds 1–3 are the development seeds, where the raw recipe is tuned and locked. '
           if max(results['seeds']) < 100 else 'Seeds 101–110 are the scored seeds. '),
        '',
        'How it was made: [docs/design/evaluation-e0.md](../../../docs/design/evaluation-e0.md) and '
        '[eval/README.md](../../README.md). Every episode, with its commands and answer, is in `results.json`.',
        '',
        '## What this can and cannot show',
        '',
        'Two scripted, deterministic policies answer the same questions over the same worlds. It shows whether '
        'each answer is correct against mechanical gold, whether it stays within its evidence, and how many bytes '
        'and commands each policy needed, with what the catalog cost to prepare. It cannot show how a model would '
        'do, token savings, or benefit to real users. The worlds are synthetic and few; nothing here is a '
        'production rate.',
        '',
        '## How the policies ran',
        '',
        '- **R**: `rg -l` over the two log folders for each word, sub-agent transcripts left out; a `jq` projection '
        'of each log that holds them all; the turn whose request, title, final reply and project hold every word; '
        "each path the final reply names, resolved against its record's cwd; then `stat` and `shasum -a 256` of the "
        "file and of the turn's logged write of it, and `git log` for a file that is gone. The logged write stands "
        'for the delivered bytes only while the file still has them, or changed after the reply.',
        '- **G**: `gleaner find` with the words, then only what the question needs: `read` for a value, `show` for '
        'the other versions or a hand-off plan, `handoff` for bytes, `verify` for a pointer. It falls back to R, '
        'counted in full, when the index reports a source read with problems or find returns nothing. For what the '
        "catalog does not record (the delivering turn's tool output, later turns) it reads the log the delivery's "
        "evidence names, with R's projection.",
        '- Two points go beyond evaluation-e0.md, which has G always call `show` and names only the two fallback '
        "conditions: G skips `show` when the answer does not need it, and it reads the delivering log for what is "
        'outside the catalog.',
        '',
        '## Summary',
        '',
        '| Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Wall time (s) |',
        '|---|---|---|---|---|---|---|---|',
    ]
    for p, s in t['policies'].items():
        lines.append(f"| {p} | {s['correct']} of {s['episodes']} | {s['hard_failures']} | {s['fallbacks']} | "
                     f"{s['bytes']:,} | {s['tilde_bytes']:,} | {s['commands']} | {s['seconds']} |")
    if 'bytes_ratio' in t:
        for name, label in (('bytes_ratio', 'Bytes read'), ('tilde_bytes_ratio', "With the home folder's path counted as ~")):
            r = t[name]
            lines += ['', f"{label}, G over R: **{r['all']}** overall; "
                      + '; '.join(f"{f} ({FAMILIES.get(f, f)}) {v}" for f, v in r['families'].items()) + '.']
    prep = t['preparation']
    lines += ['', f"Preparing the catalog, charged to G: {prep['worlds']} worlds, {prep['index_runs']} index runs, "
              f"{prep['index_seconds']} s of indexing, {prep['library_bytes']:,} library bytes on disk "
              f"({prep['library_bytes'] // max(prep['worlds'], 1):,} per world), {prep['saved_copies']} saved copies. "
              'R prepares nothing.']
    lines += ['', '## By family', '', '| Family | Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands |',
              '|---|---|---|---|---|---|---|---|']
    for f, by in t['families'].items():
        for p, s in by.items():
            lines.append(f"| {f} ({FAMILIES.get(f, f)}) | {p} | {s['correct']} of {s['episodes']} | {s['hard_failures']} | "
                         f"{s['fallbacks']} | {s['bytes']:,} | {s['tilde_bytes']:,} | {s['commands']} |")
    lines += ['', '## By task', '',
              '| Task | Asks | ' + ' | '.join(f'{p} correct | {p} bytes | {p} commands' for p in policies) + ' | G/R bytes |',
              '|---|---|' + '---|---|---|' * len(policies) + '---|']
    asks = {w['task']: w['asks'] for w in results['worlds']}
    for task, by in t['tasks'].items():
        cells = []
        for p in policies:
            s = by.get(p)
            cells.append(f"{s['correct']} of {s['episodes']} | {s['bytes'] // s['episodes']:,} | {s['commands'] / s['episodes']:.1f}"
                         if s else '– | – | –')
        lines.append(f"| {task} | {asks[task]} | " + ' | '.join(cells) + f" | {t.get('bytes_ratio', {}).get('tasks', {}).get(task, '–')} |")
    lines += ['', 'Bytes and commands per task are means per episode.', '',
              '## Every episode', '',
              '| Task | Seed | Policy | Status | Correct | Hard failures | Bytes | Commands | Seconds | Notes |',
              '|---|---|---|---|---|---|---|---|---|---|']
    for row in sorted(results['rows'], key=lambda r: (r['task'], r['seed'], r['policy'])):
        notes = []
        if row['fallback']:
            notes.append(f"fallback: {row['fallback']}")
        if not row['correct'] and row['why']:
            notes.append('; '.join(row['why']))
        lines.append(f"| {row['task']} | {row['seed']} | {row['policy']} | {row['status']} | {'yes' if row['correct'] else 'no'} | "
                     f"{', '.join(row['hard_failures']) or '–'} | {row['bytes']:,} | {row['commands']} | {row['seconds']} | "
                     f"{' '.join(notes).replace('|', '/') or '–'} |")
    lines += ['', '## Measurement', '',
              '- Bytes read are every byte of standard output and standard error of every command a policy ran. '
              'The question itself is not counted. A pipeline counts what it prints, not what its stages pass between '
              'them; `rg` and `git` read more than they print, so what they scan is not counted.',
              "- The worlds live deep in the repository, so every absolute path carries a long prefix. The second count "
              "writes the home folder's path, and its spelling in Claude Code's log folder names, as `~`, so where a "
              'world was written weighs nothing. R already writes it so in its projection; G prints absolute paths.',
              '- R projects log records with `jq` before reading them. G reads each `gleaner` answer whole, the index '
              'block included.',
              '- G falls back to R, counted in full, when find reports incomplete sources or returns nothing.',
              '- Wall time includes starting each command and the policy itself.',
              '- The earlier synthetic comparison (4,885 catalog bytes against 5,967 for targeted section reads) is '
              'motivation only; its definitions were not supplied, so its numbers are not comparable with these.',
              '']
    return '\n'.join(lines)


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if not path:
        folder = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results')
        dated = sorted(d for d in os.listdir(folder) if os.path.exists(os.path.join(folder, d, 'results.json')))
        if not dated:
            raise SystemExit('no results.json under eval/results/')
        path = os.path.join(folder, dated[-1], 'results.json')
    results = write(path)
    for policy, s in results['tables']['policies'].items():
        print(f"{policy}: {s['correct']} of {s['episodes']} correct, {s['hard_failures']} with hard failures, "
              f"{s['bytes']:,} bytes, {s['commands']} commands")
    if 'bytes_ratio' in results['tables']:
        print(f"bytes G/R: {results['tables']['bytes_ratio']['all']}")


if __name__ == '__main__':
    main()
