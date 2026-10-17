"""Read public repository metadata and pinned text; no credentials or installs."""
import concurrent.futures, datetime, json, pathlib, urllib.request

OUT = pathlib.Path(__file__).parent
REPOS = {
    'modelcontextprotocol/swift-sdk': ['README.md', 'Package.swift', 'LICENSE'],
    'swiftlang/swift-argument-parser': ['README.md', 'LICENSE.txt'],
    'github/github-mcp-server': ['README.md', 'LICENSE', 'pkg/github/repos.go'],
    'cli/cli': ['LICENSE', 'pkg/cmd/pr/list/list.go'],
    'BurntSushi/ripgrep': ['COPYING', 'crates/printer/src/json.rs'],
    'sourcegraph/zoekt': ['README.md', 'LICENSE'],
    'datahub-project/datahub': ['LICENSE', 'metadata-models/src/main/pegasus/com/linkedin/metadata/key/DatasetKey.pdl', 'metadata-models/src/main/pegasus/com/linkedin/schema/EditableSchemaMetadata.pdl'],
    'opencontainers/image-spec': ['LICENSE', 'descriptor.md'],
    'a2aproject/A2A': ['LICENSE', 'specification/a2a.proto'],
    'modelcontextprotocol/modelcontextprotocol': ['LICENSE', 'schema/2026-07-28/schema.ts'],
}

def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'gleaner-public-research'})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()

def collect(repo):
    item = {'repository': repo, 'checked_at': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    directory = OUT / 'public' / repo.replace('/', '__')
    directory.mkdir(parents=True, exist_ok=True)
    try:
        meta = json.loads(get('https://api.github.com/repos/' + repo))
        item.update({k: meta.get(k) for k in ('default_branch', 'archived', 'pushed_at', 'license', 'html_url')})
        head = json.loads(get('https://api.github.com/repos/' + repo + '/commits/' + meta['default_branch']))
        item['sha'] = head['sha']
        item['commit_date'] = head['commit']['committer']['date']
        try:
            release = json.loads(get('https://api.github.com/repos/' + repo + '/releases/latest'))
            item['latest_release'] = {k: release.get(k) for k in ('tag_name', 'published_at', 'html_url')}
        except Exception as e:
            item['release_lookup'] = str(e)
        item['files'] = []
        for path in REPOS[repo]:
            url = f"https://raw.githubusercontent.com/{repo}/{item['sha']}/{path}"
            entry = {'path': path, 'url': url}
            try:
                data = get(url)
                dest = directory / path.replace('/', '__')
                dest.write_bytes(data)
                entry.update({'bytes': len(data), 'local': str(dest.relative_to(OUT))})
            except Exception as e:
                entry['error'] = str(e)
            item['files'].append(entry)
    except Exception as e:
        item['error'] = str(e)
    return item

with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    results = list(pool.map(collect, REPOS))
(OUT / 'public-sources.json').write_text(json.dumps(results, indent=2) + '\n')
for row in results:
    print(json.dumps({k: v for k, v in row.items() if k != 'files'}))
    for f in row.get('files', []):
        if 'error' in f:
            print('FILE ERROR', f)
