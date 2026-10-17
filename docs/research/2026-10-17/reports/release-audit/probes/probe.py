#!/usr/bin/env python3
"""Synthetic Linux probes. SQL executes verbatim schema/statements from the pinned source.
Projects and regex probes are explicit transcriptions, NOT executed Swift or macOS tests.
Only temporary fixture data is read/written. No private logs.
"""
import hashlib, json, os, pathlib, re, sqlite3, subprocess, tempfile

SOURCE = pathlib.Path('/workspace/gleaner-review')
OUT = pathlib.Path(__file__).resolve().parent.parent / 'evidence' / 'probe-results.json'
results = []
def record(name, result, kind):
    results.append(dict(name=name, evidence_kind=kind, result=result))
    print(name + ': ' + json.dumps(result, ensure_ascii=False))

registry = (SOURCE/'Sources/GleanerCore/Registry.swift').read_text()
schema = re.search(r'try db.execute\("""(.*?)"""\)', registry, re.S).group(1)
sql = sqlite3.connect(':memory:')
sql.executescript(schema)
upsert = re.search(r'public func upsert\(_ session:.*?try db.run\("""(.*?)"""', registry, re.S).group(1)
sql.execute(upsert, ('same-id', 'claude-code', 'Alpha', '/alpha', '/a.jsonl'))
sql.execute(upsert, ('same-id', 'codex', 'Beta', '/beta', '/b.jsonl'))
row = sql.execute('SELECT provider,title,cwd,log_path FROM sessions').fetchone()
assert row == ('claude-code','Beta','/beta','/b.jsonl')
record('provider-id-collision', row, 'actual SQLite; verbatim Registry.upsert SQL')

sql.execute("INSERT INTO deliveries VALUES ('d', 'same-id', '/synthetic/report.md', 1, '/synthetic', 'report', '[]', '/a.jsonl')")
sql.execute("INSERT INTO captures VALUES ('d', 'saved-hash', 10, 1, 1, 1, 'at_delivery', 0)")
stale = re.search(r'let stale = """(.*?)"""', registry, re.S).group(1)
for table,key in [('captures','delivery_id'),('deliveries','id')]:
    sql.execute(f'DELETE FROM {table} WHERE {key} IN ({stale})',('/a.jsonl','[]'))
counts = [sql.execute(f'SELECT count(*) FROM {t}').fetchone()[0] for t in ['deliveries','captures']]
assert counts == [0,0]
record('partial-reread-prunes-history', dict(deliveries=counts[0],captures=counts[1]), 'actual SQLite pruning; malformed-parse-to-empty path established by source')

def repository(directory):
    # Projects.resolve/mainFolder, without its process-lifetime cache.
    current=pathlib.Path(directory)
    while str(current) not in ('/','.'):
        dot=current/'.git'
        if dot.exists():
            if dot.is_dir(): return current
            text=dot.read_text()
            line=next((x for x in text.splitlines() if x.startswith('gitdir:')),None)
            if not line: return current
            gitdir=pathlib.Path(line[len('gitdir:'):].strip())
            if not gitdir.is_absolute():gitdir=current/gitdir
            common=gitdir/'commondir'
            if not common.exists():return current
            cd=pathlib.Path(common.read_text().strip())
            if not cd.is_absolute():cd=gitdir/cd
            cd=pathlib.Path(os.path.normpath(cd))
            return cd.parent if cd.name=='.git' else current
        current=current.parent
    return None

with tempfile.TemporaryDirectory(prefix='gleaner-audit-') as td:
    root=pathlib.Path(td)
    a=root/'client-a'/'app'; b=root/'client-b'/'app'
    for repo in [a,b]: (repo/'.git').mkdir(parents=True)
    labels=[repository(p/'out').name for p in [a,b]]
    assert labels == ['app','app']
    record('distinct-repositories-share-filter-label', labels,'Projects.swift transcription over synthetic .git directories')
    main=root/'Atlas'; (main/'.git'/'worktrees'/'ephemeral').mkdir(parents=True)
    wt=root/'elsewhere'/'ephemeral'; wt.mkdir(parents=True)
    (wt/'.git').write_text('gitdir: '+str(main/'.git'/'worktrees'/'ephemeral')+'\n')
    (main/'.git'/'worktrees'/'ephemeral'/'commondir').write_text('../..\n')
    before=repository(wt/'out').name
    (wt/'.git').unlink(); wt.rmdir()
    after=repository(wt/'out')
    assert before=='Atlas' and after != main
    record('external-worktree-after-cold-relaunch',dict(before=before,repository_after=str(after) if after else None,project_after=after.name if after else wt.name),'Projects.swift transcription; cache intentionally cold as on relaunch')

    env=os.environ.copy()
    env.update(GIT_AUTHOR_NAME='GPT Task',GIT_AUTHOR_EMAIL='gpt-task@example.invalid',GIT_COMMITTER_NAME='GPT Task',GIT_COMMITTER_EMAIL='gpt-task@example.invalid')
    repo=root/'recovery'; repo.mkdir()
    def git(*args, check=True):
        return subprocess.run(['git','-C',str(repo),*args],env=env,text=True,capture_output=True,check=check)
    git('init','-q','-b','main'); (repo/'base').write_text('base'); git('add','.');git('commit','-qm','synthetic base')
    git('checkout','-qb','feature');(repo/'report.md').write_text('only on feature');git('add','.');git('commit','-qm','synthetic report')
    git('checkout','-q','main')
    candidate=git('rev-list','-n','1','--all','--','report.md').stdout.strip()
    assert git('cat-file','-e','HEAD:report.md',check=False).returncode != 0
    restore=git('checkout',candidate+'^','--','report.md',check=False)
    assert restore.returncode != 0
    assert git('cat-file','-e',candidate+':report.md').returncode == 0
    record('history-restore-parent-is-wrong',dict(recoverable_candidate=True,suggested_restore_exit=restore.returncode,error=restore.stderr.strip()),'actual Git; synthetic repository; exact generated argument pattern')
    unsafe="git -C '/tmp/Bob's Project' restore --source=HEAD -- 'report.md'"
    syntax=subprocess.run(['sh','-n'],input=unsafe,text=True,capture_output=True)
    assert syntax.returncode != 0
    record('restore-apostrophe-quoting',dict(exit=syntax.returncode,error=syntax.stderr.strip()),'actual POSIX shell syntax check; no command execution')

extractor=(SOURCE/'Sources/GleanerCore/MentionExtractor.swift').read_text()
fence=re.search(r'static let fence = .*?pattern: #"(.*?)"#',extractor).group(1)
sample='Example only:\n```sh\ncat /tmp/out/report.md\n'
assert not list(re.finditer(fence,sample))
record('unclosed-fence-not-covered',dict(fence_matches=0,exposed_absolute_path='/tmp/out/report.md'),'verbatim regex run with Python on ASCII fixture; Swift/ICU acceptance test supplied separately')

library=(SOURCE/'Sources/GleanerCore/Library.swift').read_text()
assert 'if now.state.kind == .directory || delivery.capture?.isDirectory == true { return .folder }' in library
record('historical-file-current-directory',dict(selected_sha='saved-file-sha',current_kind='directory',handoff='folder'), 'direct source branch trace; Swift regression test supplied separately')

OUT.write_text(json.dumps(results,indent=2,ensure_ascii=False)+'\n')
