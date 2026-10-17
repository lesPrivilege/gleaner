#!/usr/bin/env python3
"""Create synthetic local acceptance data. Does not install logs or touch user state.
Usage: python3 make_fixtures.py /tmp/gleaner-acceptance initial|second|changed
Run initial, index its log in a DISPOSABLE macOS user, then second, then changed.
"""
import datetime, json, os, pathlib, struct, sys, zlib
root=pathlib.Path(sys.argv[1]).resolve(); phase=sys.argv[2]
if phase not in ('initial','second','changed'): raise SystemExit('invalid phase')
root.mkdir(parents=True,exist_ok=True); out=root/'artifacts';out.mkdir(exist_ok=True)
log=root/'audit.jsonl'
def png(path, rgb):
    def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b'\0'+bytes(rgb)))+chunk(b'IEND',b''))
def append_delivery(request, names):
    at=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
    base=dict(sessionId='gleaner-synthetic-acceptance',cwd=str(out),timestamp=at)
    records=[dict(base,type='user',origin={'kind':'human'},message={'content':request}),
             dict(base,type='assistant',message={'model':'synthetic-fixture','content':[{'type':'text','text':'\n'.join(f'[{name}]({out/name})' for name in names)}]})]
    with log.open('a') as f:
        for record in records:f.write(json.dumps(record,ensure_ascii=False)+'\n')
if phase=='initial':
    if log.exists():raise SystemExit('Choose a new empty fixture root; refusing to replace earlier run')
    (out/'guide.md').write_text('# Recovery guide\n\n旧版：重试三次。\n\n## Details\nThis is synthetic version one.\n')
    (out/'replace.txt').write_text('saved regular file, not a folder\n')
    (out/'large.txt').write_text('Read beyond preview.\n'+'line\n'*16000)
    with (out/'large.dat').open('wb') as f:f.truncate(65<<20)
    png(out/'diagram.png',(255,0,0))
    (out/'latest.md').symlink_to(out/'guide.md')
    bundle=out/'bundle';bundle.mkdir();(bundle/'image.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="red"/></svg>')
    (bundle/'index.html').write_text('<!doctype html><title>Synthetic bundle</title><h1>Fixture</h1><img src="image.svg">')
    os.mkfifo(out/'pipe.txt',0o600)
    append_delivery('Prepare the recovery guide and diagram: version one.', ['guide.md','diagram.png','latest.md','replace.txt','large.txt','large.dat','bundle','bundle/index.html','pipe.txt'])
elif phase=='second':
    if not log.exists():raise SystemExit('Run initial first')
    (out/'guide.md').write_text('# Recovery guide\n\n新版：重试五次。\n\n## Details\nThis is synthetic version two.\n')
    png(out/'diagram.png',(0,0,255))
    append_delivery('Prepare the board cut: version two.', ['guide.md','diagram.png'])
else:
    (out/'guide.md').write_text('# UNDELIVERED current content\n')
    png(out/'diagram.png',(0,255,0))
    target=out/'replace.txt'
    if target.is_file():target.unlink();target.mkdir();(target/'unrelated.txt').write_text('not the saved delivery')
print('Fixture root:',root)
print('Synthetic log:',log)
print('Phase:',phase)
print('Install/update this log only in a disposable test account after reading native-acceptance.md.')
