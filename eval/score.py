#!/usr/bin/env python3
"""Scores evaluation E0's episodes against their gold (docs/design/evaluation-e0.md, "Scoring").

    eval/score.py [eval/results/<date>/results.json]

Reads the episodes run.py wrote, scores each answer against its world's gold.json, and writes
back into results.json:
- `rows`: one per episode: task, seed and policy; the answer's status and whether it is
  correct; the hard failures it commits; the evidence it cites and the scope it claims; bytes
  read, commands and tool processes run, commands refused or timed out, what it saw cut short,
  wall time, and for G the same with its world's preparation charged to it;
- `tables`: per policy, per family and per task, the ratio of bytes read, G to R, overall and
  per family, the preparation cost, and the queries at which preparation would repay itself.
Then writes report.md beside it. With no path, it scores the newest results.json under
eval/results/. The scorer knows the tasks; the policies never do.

Hard failures, as the evaluation names them, plus the task-specific ones each gold lists:
- false_global_absence: a negative beyond what its scope supports;
- current_as_delivered: current bytes passed off as a delivered version;
- hash_merge: two artifacts merged on a hash;
- tool_only_as_delivery: a tool-only file called a delivery.
"""
import datetime
import glob
import json
import math
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

    def absence(self):
        """A negative where the gold holds the item is a false absence, unless the scope it states
        is bounded and says it is incomplete: with no scope, or a complete one, it claims more than
        it saw."""
        if self.answer.get('status') != 'not_found':
            return
        scope = self.answer.get('scope')
        if not scope or scope.get('complete'):
            self.fail('false_global_absence', 'not found, where the gold holds it, over a complete scope or none')

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
        self.absence()
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
        self.absence()
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
            self.absence()
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
            # Only the catalog's own scope bounds a negative here: it admits no bare file name.
            if status == 'not_found' and (answer.get('scope') or {}).get('kind') != 'catalog':
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
        self.absence()
        expected, answer = self.expected, self.answer
        artifacts = [a for a in answer.get('artifacts') or [] if isinstance(a, dict)]
        got = {self.rel(a.get('path')): a for a in artifacts}
        wanted = [got.get(a['path']) or {} for a in expected['artifacts']]
        hashes = [a.get('sha256') for a in wanted]
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('same') is False, 'called one item')
              & self.need(all(a['path'] in got for a in expected['artifacts']), 'an artifact missing')
              & self.need(all(h in (None, expected['sha256']) for h in hashes), 'another hash')
              & self.need(answer.get('equal_bytes') is True or hashes.count(expected['sha256']) == len(hashes),
                          'the equal hashes not reported'))
        if answer.get('same') is True or (answer.get('status') == 'found' and len(got) < 2):
            self.fail('hash_merge', 'two artifacts merged on a hash')
        return ok

    def current_match(self):
        self.absence()
        expected, answer = self.expected, self.answer
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('current_sha256') == expected['current_sha256'], 'another current hash')
              & self.need(answer.get('matches_latest') is False, 'said to match the latest')
              & self.need(self.same(answer.get('matches'), expected['matches']), 'matched another delivery'))
        if answer.get('matches_latest') is True or self.same(answer.get('matches'), expected['latest']):
            self.fail('latest_assumed_current', 'the latest delivery taken for the current file')
        return ok

    def provenance(self):
        self.absence()
        expected, answer = self.expected, self.answer
        observed = seconds(answer.get('observed_at'))
        ok = (self.need(answer.get('status') == 'found', 'not found')
              & self.need(answer.get('established') is False, 'said to be established')
              & self.need(self.same(answer.get('delivery'), expected['delivery']), 'another delivery')
              & self.need(observed is not None and observed > seconds(expected['delivered_at']) + 600,
                          'no first observation stated, later than the delivery'))
        if answer.get('established') is True:
            self.fail('current_as_delivered', 'the bytes seen later passed off as the delivered ones')
            self.fail('certainty_from_mtime', 'certainty without an observation at delivery')
        return ok

    def offered(self, artifact):
        """The hash of what an answer offers for an artifact, as the runner hashed it: a file it
        gave, or what its git restore command's commit holds at that path."""
        if artifact.get('bytes_file'):
            return self.episode['checked'].get(artifact['bytes_file'])
        if artifact.get('source') == 'git':
            return (self.episode.get('checked_git') or {}).get(artifact.get('path'))
        return None

    def recover(self):
        self.absence()
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
        self.absence()
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
        self.absence()
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
        self.absence()
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


def seconds(stamp):
    """An ISO 8601 time as seconds since the epoch; None when there is none or it does not parse."""
    if not isinstance(stamp, str):
        return None
    try:
        return datetime.datetime.fromisoformat(stamp.replace('Z', '+00:00')).timestamp()
    except ValueError:
        return None


def score_episode(record, episode):
    answer = episode['answer'] or {}
    if record.get('gold') is None:
        correct, failures, why = False, [], [episode.get('error') or 'not run']
    else:
        check = Check(record, episode)
        correct = bool(getattr(check, episode['asks'])()) and not check.failures and not episode.get('error')
        failures, why = check.failures, check.why
        if episode.get('error'):
            why.append(episode['error'])
    scope = answer.get('scope') or {}
    diagnostics = answer.get('diagnostics') or {}
    preparation = record.get('preparation') if episode['policy'] == 'G' else None
    return dict(
        task=episode['task'], seed=episode['seed'], family=episode['family'], asks=episode['asks'],
        policy=episode['policy'], status=answer.get('status'), correct=correct, hard_failures=failures,
        why=why, fallback=answer.get('fallback'), not_run=bool(episode.get('not_run')),
        evidence=answer.get('evidence') or [], scope=dict(kind=scope.get('kind'), complete=scope.get('complete')),
        bytes=episode['bytes']['total'], tilde_bytes=episode['bytes']['home_as_tilde'],
        commands=episode['command_count'], processes=episode.get('processes', episode['command_count']),
        refused=episode.get('refused', 0), timed_out=episode.get('timed_out', 0),
        clipped=diagnostics.get('clipped_fields', 0),
        truncated=len(diagnostics.get('truncated') or []) + bool(answer.get('truncated')),
        seconds=episode['seconds'],
        seconds_with_preparation=round(episode['seconds'] + (preparation or {}).get('index_seconds', 0), 3),
        catalog_bytes=episode['phases'].get('catalog', {}).get('bytes', 0),
        raw_bytes=episode['phases'].get('raw', {}).get('bytes', 0),
        drift_after_command=episode.get('drift_after_command'),
        preparation=preparation)


def summary(rows):
    n = len(rows)
    return dict(episodes=n, correct=sum(r['correct'] for r in rows),
                hard_failures=sum(bool(r['hard_failures']) for r in rows),
                general_failures=sum(any(f in GENERAL for f in r['hard_failures']) for r in rows),
                fallbacks=sum(bool(r['fallback']) for r in rows), not_run=sum(r['not_run'] for r in rows),
                bytes=sum(r['bytes'] for r in rows), tilde_bytes=sum(r['tilde_bytes'] for r in rows),
                commands=sum(r['commands'] for r in rows), processes=sum(r['processes'] for r in rows),
                refused=sum(r['refused'] for r in rows), timed_out=sum(r['timed_out'] for r in rows),
                clipped=sum(r['clipped'] for r in rows), truncated=sum(r['truncated'] for r in rows),
                seconds=round(sum(r['seconds'] for r in rows), 3),
                seconds_with_preparation=round(sum(r['seconds_with_preparation'] for r in rows), 3))


def ratio(g, r):
    return round(g / r, 3) if r else None


def break_even(rows, records):
    """When G's preparation would repay itself, per world: with P its mean index time and d the
    mean per-query saving in wall time (R's seconds less G's), ceil(P / d) queries, or none when
    d is not positive (03, "Amortization"). Cost at 1, 10, 100 and 1000 queries a world beside it.
    Bytes have no preparation counterpart: the index's reading of the logs is not read by a policy."""
    by = {(r['seed'], r['task'], r['policy']): r for r in rows}
    pairs = [(by[(w['seed'], w['task'], 'R')], by[(w['seed'], w['task'], 'G')], w['preparation'])
             for w in records if w.get('preparation') and (w['seed'], w['task'], 'R') in by and (w['seed'], w['task'], 'G') in by]
    if not pairs:
        return None
    n = len(pairs)
    r_time = sum(r['seconds'] for r, _, _ in pairs) / n
    g_time = sum(g['seconds'] for _, g, _ in pairs) / n
    prep = sum(p['index_seconds'] for _, _, p in pairs) / n
    saving = r_time - g_time
    return dict(worlds=n, preparation_seconds=round(prep, 3), r_seconds=round(r_time, 4), g_seconds=round(g_time, 4),
                saving_seconds=round(saving, 4), queries=math.ceil(prep / saving) if saving > 0 else None,
                bytes_saving=round(sum(r['bytes'] - g['bytes'] for r, g, _ in pairs) / n, 1),
                sensitivity={q: dict(R=round(q * r_time, 3), G=round(prep + q * g_time, 3)) for q in (1, 10, 100, 1000)})


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
        out['break_even'] = break_even(rows, records)
    prep = [r['preparation'] for r in records if r.get('preparation')]
    failures = [dict(seed=r['seed'], task=r['task'], **f) for r in records for f in r.get('preparation_failures') or []]
    out['preparation'] = dict(worlds=len(records), prepared=len(prep), failed_attempts=len(failures), failures=failures,
                              index_runs=sum(p['index_runs'] for p in prep),
                              index_seconds=round(sum(p['index_seconds'] for p in prep), 3),
                              library_bytes=sum(p['library_bytes'] for p in prep),
                              saved_copies=sum(p['saved_copies'] for p in prep))
    checked = [r['gold_check'] for r in records if r.get('gold_check')]
    out['gold_checks'] = dict(checked=len(checked), ok=sum(c['ok'] for c in checked))
    reach = [r['distractors'] for r in records if r.get('distractors')]
    if reach:
        out['distractors'] = dict(
            worlds=len(reach), logs=round(sum(d['logs'] for d in reach) / len(reach), 1),
            per_word=round(sum(sum(d['holding'].values()) / len(d['holding']) for d in reach) / len(reach), 1),
            every_word=round(sum(d['holding_every_word'] for d in reach) / len(reach), 1),
            decoys=round(sum(d['decoys'] for d in reach) / len(reach), 1),
            near_misses=round(sum(d['near_misses'] for d in reach) / len(reach), 1))
    return out


def runs():
    """Every results.json under eval/results/, newest first."""
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    found = []
    for path in glob.glob(os.path.join(repo, 'eval', 'results', '**', 'results.json'), recursive=True):
        with open(path, encoding='utf-8') as f:
            results = json.load(f)
        found.append(dict(path=os.path.relpath(path, repo), created=results.get('created'),
                          seeds=results.get('seeds'), commit=(results.get('environment') or {}).get('commit'),
                          episodes=len(results.get('episodes') or [])))
    return sorted(found, key=lambda r: r['created'] or '', reverse=True)


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
        f.write(report(results, path))
    return results


def seeds_text(seeds):
    if seeds == list(range(seeds[0], seeds[-1] + 1)) and len(seeds) > 2:
        return f'Seeds {seeds[0]}–{seeds[-1]}'
    return ('Seed ' if len(seeds) == 1 else 'Seeds ') + ', '.join(map(str, seeds))


def report(results, path):
    t = results['tables']
    env = results['environment']
    policies = list(t['policies'])
    scored = results.get('scored', max(results['seeds']) >= 101)
    lock = results.get('lock')
    recipe = results.get('recipe') or {}
    lines = [
        '# Evaluation E0: results',
        '',
        f"{seeds_text(results['seeds'])}; {len(results['tasks'])} tasks; policies {', '.join(policies)}. Run "
        f"{results['created']} on macOS {env.get('macos')} ({env.get('machine')}) at commit {(env.get('commit') or '')[:7]}, "
        f"with {env.get('rg')}, {env.get('jq')}, {env.get('git')} and Python {env.get('python')}.",
        '',
    ]
    if scored and lock:
        lines += [f"These are the scored seeds. The raw recipe was locked on development seeds {', '.join(map(str, lock['seeds']))} "
                  f"at commit {lock['commit'][:7]} ({lock['locked_at']}), recorded in `eval/lock.json` with the sha256 of "
                  f"every `eval/*.py`. The run checked that those files still had those hashes and that the tree was clean. "
                  f"The development run that locked it is `{lock['results']}`.", '']
    elif not scored:
        lines += ['These are development seeds, where the raw recipe is tuned and locked. '
                  + ('The tree was clean.' if recipe.get('clean') else 'The tree had uncommitted changes.'), '']
    lines += [
        'How it was made: [docs/design/evaluation-e0.md](' + rel_link(path, 'docs/design/evaluation-e0.md') + ') and '
        '[eval/README.md](' + rel_link(path, 'eval/README.md') + '). Every episode, with its commands and answer, is in '
        '`results.json`.',
        '',
        '## What this can and cannot show',
        '',
        'Two scripted, deterministic policies answer the same questions over the same worlds. This shows whether each '
        'answer is correct against mechanical gold, whether it stays within its evidence, how many bytes and commands '
        'each policy needed, and what the catalog cost to prepare. Nothing here calls a model. So it cannot show model '
        'efficacy, token savings, or benefit to real users. Bytes read by a script are not tokens a model would spend. '
        'The worlds are synthetic and few, and none of this is a production rate.',
        '',
        'Limits of this design:',
        '',
        '- **One template per task.** The scored seeds run the same 15 world builders as the development seeds. Only the '
        'values, ids, order, timestamps and distractors are new. Both policies were written against these templates, '
        'and `asks` alone names the task for 10 of the 15 (every `asks` but `value` and `delivery`). So correctness '
        'here shows the policies hold up on new draws of templates they were built for. It does not show they '
        'generalize to new kinds of question. The protocol (08) asks for a split by generator template; this split is '
        'by seed.',
        '- **One raw variant.** R projects each candidate log whole, which is close to the protocol\'s R-session. '
        'R-search and R-section (01) were not run. The synthetic sessions are one or two turns long, so a section '
        'read would differ little from a whole-log read here.',
        '- **Equal tools.** Both policies may use `jq`, and G projects each `gleaner` answer to the fields it reads, '
        'with the home folder written `~`, as R projects its logs. Commands count requests; processes count the '
        'tools a pipeline starts.',
        '- **One query per world.** Each world is prepared once and asked one question, so preparation is charged in '
        'full to that one G episode. The break-even line below says how many queries a world would need.',
        '- **T25.** The drift lands after the first output that holds the delivered hash. Gleaner hands off from its '
        'saved copy, as the protocol\'s retained capture allows, so its check of a copy made from the changed '
        'original is never reached.',
        '',
        '## How the policies ran',
        '',
        '- **R**: one `rg` pipeline over the two log folders keeps the logs that hold every word, sub-agent transcripts '
        'left out, with Codex titles from its session index. A per-word listing is used only for a decision, which '
        'weighs partial matches, and to explain a negative. Then a `jq` projection of each candidate log; the turn whose '
        "request, title, final reply and project hold every word; each path the final reply names, resolved against "
        "its record's cwd; then `stat` and `shasum -a 256` of the file and of the turn's logged write of it, and `git "
        'log` for a file that is gone. The logged write stands for the delivered bytes only while the file still has '
        'them, or changed after the reply.',
        '- **G**: `gleaner find` with the words, then only what the question needs: `read` for a value, `show` for '
        'the other versions or a hand-off plan, `handoff` for bytes, `verify` for a pointer. Each answer is projected '
        'with `jq`. G falls back to R, counted in full, when the index reports a source read with problems or find '
        "returns nothing. For what the catalog does not record (the delivering turn's tool output, later turns), it "
        "reads the log the delivery's evidence names, with R's projection.",
        '- Two points go beyond evaluation-e0.md, which has G always call `show` and names only the two fallback '
        "conditions. G skips `show` when the answer does not need it, and it reads the delivering log for what is "
        'outside the catalog.',
        '- The runner is each policy\'s only way to the world. The policy, and every command, run under '
        '`sandbox-exec`. They can read and write nothing of the run\'s but that world and the policy\'s scratch '
        'folder; R cannot read the world\'s catalog either. Gold lives outside every world.',
        '',
        '## Summary',
        '',
        '| Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Processes | '
        'Refused | Timed out | Wall time (s) | With preparation (s) |',
        '|---|---|---|---|---|---|---|---|---|---|---|---|',
    ]
    for p, s in t['policies'].items():
        lines.append(f"| {p} | {s['correct']} of {s['episodes']} | {s['hard_failures']} | {s['fallbacks']} | "
                     f"{s['bytes']:,} | {s['tilde_bytes']:,} | {s['commands']} | {s['processes']} | {s['refused']} | "
                     f"{s['timed_out']} | {s['seconds']} | {s['seconds_with_preparation']} |")
    if 'bytes_ratio' in t:
        for name, label in (('bytes_ratio', 'Bytes read'), ('tilde_bytes_ratio', "With the home folder's path counted as ~")):
            r = t[name]
            lines += ['', f"{label}, G over R: **{r['all']}** overall; "
                      + '; '.join(f"{f} ({FAMILIES.get(f, f)}) {v}" for f, v in r['families'].items()) + '.']
    lines += ['', 'R reported ' + f"{t['policies'].get('R', {}).get('clipped', 0)} projected fields clipped at 240 characters; "
              f"G {t['policies'].get('G', {}).get('clipped', 0)} in its raw reads, and {t['policies'].get('G', {}).get('truncated', 0)} "
              'gleaner answers marked truncated. Episodes that could not run: '
              + ', '.join(f"{p} {s['not_run']}" for p, s in t['policies'].items()) + '.']
    prep = t['preparation']
    lines += ['', '## Preparation', '',
              f"Charged to G: {prep['prepared']} of {prep['worlds']} worlds prepared, {prep['index_runs']} index runs, "
              f"{prep['index_seconds']} s of indexing, {prep['library_bytes']:,} library bytes on disk "
              f"({prep['library_bytes'] // max(prep['prepared'], 1):,} per world), {prep['saved_copies']} saved copies. "
              f"Failed preparation attempts: {prep['failed_attempts']}"
              + (' (' + '; '.join(f"seed {f['seed']} {f['task']} attempt {f['attempt']}: {f['reason']}" for f in prep['failures']) + ')'
                 if prep['failures'] else '') + '. R prepares nothing.']
    be = t.get('break_even')
    if be:
        timing = (f"saving {be['saving_seconds']} s a query, so preparation would repay itself in wall time after "
                  f"**{be['queries']}** queries on one world." if be['queries'] else
                  f"so G is {-be['saving_seconds']} s a query slower and **preparation never repays itself in wall time**.")
        reading = (f"G read {be['bytes_saving']:,} fewer bytes a query than R" if be['bytes_saving'] >= 0 else
                   f"G read {-be['bytes_saving']:,} more bytes a query than R")
        lines += ['', f"Per world, G's preparation took {be['preparation_seconds']} s on average. Its episodes took "
                  f"{be['g_seconds']} s against R's {be['r_seconds']} s, {timing} {reading}. Bytes have no preparation "
                  "counterpart: the index reads every log, but no policy reads what it read.",
                  '', '| Queries a world | R seconds | G seconds, preparation included |', '|---|---|---|']
        for q, c in be['sensitivity'].items():
            lines.append(f'| {q} | {c["R"]} | {c["G"]} |')
        lines += ['', 'These counts are a sensitivity range, not observed workloads.']
    lines += ['', '## By family', '',
              '| Family | Policy | Correct | Hard failures | Fallbacks | Bytes read | Bytes, home as ~ | Commands | Processes '
              '| Wall time (s) | With preparation (s) |',
              '|---|---|---|---|---|---|---|---|---|---|---|']
    for f, by in t['families'].items():
        for p, s in by.items():
            lines.append(f"| {f} ({FAMILIES.get(f, f)}) | {p} | {s['correct']} of {s['episodes']} | {s['hard_failures']} | "
                         f"{s['fallbacks']} | {s['bytes']:,} | {s['tilde_bytes']:,} | {s['commands']} | {s['processes']} | "
                         f"{s['seconds']} | {s['seconds_with_preparation']} |")
    lines += ['', '## By task', '',
              '| Task | Asks | ' + ' | '.join(f'{p} correct | {p} bytes | {p} commands' for p in policies) + ' | G/R bytes |',
              '|---|---|' + '---|---|---|' * len(policies) + '---|']
    asks = {w['task']: w['asks'] for w in results['worlds'] if w.get('asks')}
    for task, by in t['tasks'].items():
        cells = []
        for p in policies:
            s = by.get(p)
            cells.append(f"{s['correct']} of {s['episodes']} | {s['bytes'] // s['episodes']:,} | {s['commands'] / s['episodes']:.1f}"
                         if s else '– | – | –')
        lines.append(f"| {task} | {asks.get(task, '–')} | " + ' | '.join(cells)
                     + f" | {t.get('bytes_ratio', {}).get('tasks', {}).get(task, '–')} |")
    lines += ['', 'Bytes and commands per task are means per episode.', '', '## Hard failures', '']
    failed = [r for r in results['rows'] if r['hard_failures']]
    if failed:
        lines += ['| Task | Seed | Policy | Failures | Why |', '|---|---|---|---|---|']
        for r in sorted(failed, key=lambda r: (r['task'], r['seed'], r['policy'])):
            lines.append(f"| {r['task']} | {r['seed']} | {r['policy']} | {', '.join(r['hard_failures'])} | "
                         f"{'; '.join(r['why']).replace('|', '/')} |")
    else:
        lines.append(f"None in {len(results['rows'])} episodes. Each was checked for the four general classes "
                     '(' + ', '.join(f'`{g}`' for g in GENERAL) + ') and for the task-specific ones its gold lists. Zero '
                     'observed failures in this many synthetic episodes does not establish a failure rate.')
    reach = t.get('distractors')
    checks = t['gold_checks']
    lines += ['', '## Worlds', '']
    if reach:
        lines.append(f"A world has {reach['logs']} session logs on average, sub-agent transcripts left out: {reach['decoys']} "
                     f"decoys about other things and {reach['near_misses']} near misses that each hold exactly one query "
                     f"word. A query word is in {reach['per_word']} logs on average; every word is in {reach['every_word']}. "
                     'The per-world counts are in `results.json` (`worlds[].distractors`).')
    lines.append('')
    lines.append(f"After its episodes, each world was checked against its gold (check_worlds.check): {checks['ok']} of "
                 f"{checks['checked']} hold what their gold presumes."
                 + (' For scored worlds only pass or fail is kept.' if scored else ''))
    lines += ['', '## Every episode', '',
              '| Task | Seed | Policy | Status | Correct | Hard failures | Bytes | Commands | Seconds | Notes |',
              '|---|---|---|---|---|---|---|---|---|---|']
    for row in sorted(results['rows'], key=lambda r: (r['task'], r['seed'], r['policy'])):
        notes = []
        if row['fallback']:
            notes.append(f"fallback: {row['fallback']}")
        if row['refused'] or row['timed_out']:
            notes.append(f"{row['refused']} refused, {row['timed_out']} timed out")
        if row['drift_after_command']:
            notes.append(f"drift after command {row['drift_after_command']}")
        if not row['correct'] and row['why']:
            notes.append('; '.join(row['why']))
        lines.append(f"| {row['task']} | {row['seed']} | {row['policy']} | {row['status']} | {'yes' if row['correct'] else 'no'} | "
                     f"{', '.join(row['hard_failures']) or '–'} | {row['bytes']:,} | {row['commands']} | {row['seconds']} | "
                     f"{' '.join(notes).replace('|', '/') or '–'} |")
    lines += ['', '## Measurement', '',
              '- Bytes read are every byte of standard output and standard error of every command a policy ran. '
              'The question itself is not counted. A pipeline counts what it prints, not what its stages pass between '
              'them. `rg`, `git` and `gleaner` read more than they print, so what they scan is not counted.',
              "- The worlds live deep in the repository, so every absolute path carries a long prefix. The second count "
              "writes the home folder's path, and its spelling in Claude Code's log folder names, as `~`, so where a "
              'world was written weighs nothing. Both projections already write the home folder as `~`. The log folder '
              'names in `rg` listings and in `gleaner` evidence keep the long spelling.',
              '- Commands are the requests a policy made; processes are the tools those requests started, so a pipeline '
              'counts each tool in it. Refused and timed-out commands count as commands, with what they printed.',
              '- G falls back to R, counted in full, when find reports incomplete sources or returns nothing.',
              '- Wall time includes starting each command under `sandbox-exec`, about 7 ms a command on this machine, and '
              "the policy itself. G's time with preparation adds its world's indexing time.",
              '- The earlier synthetic comparison (4,885 catalog bytes against 5,967 for targeted section reads) is '
              'motivation only; its definitions were not supplied, so its numbers are not comparable with these.',
              '', '## Runs', '', 'The results kept under `eval/results/`, newest first:', '',
              '| Results | Created | Seeds | Commit | Episodes |', '|---|---|---|---|---|']
    for run in runs():
        lines.append(f"| `{run['path']}` | {run['created']} | {seeds_text(run['seeds']) if run['seeds'] else '–'} | "
                     f"{(run['commit'] or '')[:7]} | {run['episodes']} |")
    lines.append('')
    return '\n'.join(lines)


def rel_link(results_path, target):
    """A link from the report beside `results_path` to `target`, a path in the repository."""
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.relpath(os.path.join(repo, target), os.path.dirname(os.path.abspath(results_path)))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if not path:
        found = runs()
        if not found:
            raise SystemExit('no results.json under eval/results/')
        path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), found[0]['path'])
    results = write(path)
    for policy, s in results['tables']['policies'].items():
        print(f"{policy}: {s['correct']} of {s['episodes']} correct, {s['hard_failures']} with hard failures, "
              f"{s['bytes']:,} bytes, {s['commands']} commands")
    if 'bytes_ratio' in results['tables']:
        print(f"bytes G/R: {results['tables']['bytes_ratio']['all']}")


if __name__ == '__main__':
    main()
