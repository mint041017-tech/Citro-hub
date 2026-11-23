# -*- coding: utf-8 -*-
# downloads 静态站 zip 打包 + web/downloads.json 回填(3.3.1)
# 源目录是 build.mjs 生成的 dist/；同样必须用 Python zipfile。
import os, sys, zipfile, hashlib, json, datetime, shutil, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

VERSION = '3.3.1'
BUILD_NUMBER = '3301'
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'dist')
DST = os.path.join(HERE, f'Citro-downloads-{VERSION}.zip')
WEB_COPY = os.path.abspath(os.path.join(HERE, '..', 'web', f'Citro-downloads-{VERSION}.zip'))
NOTES = ('Citro downloads 静态站 3.3.1:Windows / Android 入口更新到 3.3.1，'
         '同步完全随机抽签、签文分段流式、今日一小步修复与社区长文折叠更新日志；Web 入口同步。')

if not os.path.isfile(os.path.join(SRC, 'index.html')):
    sys.exit('missing dist/index.html — run node build.mjs first')
entries = []
for root, dirs, files in os.walk(SRC):
    dirs.sort()
    relroot = os.path.relpath(root, SRC).replace(os.sep, '/')
    for name in sorted(files):
        arc = name if relroot == '.' else relroot + '/' + name
        entries.append((os.path.join(root, name), arc))
for full, arc in entries:
    if '\\' in arc or arc.startswith('/') or '..' in arc.split('/'):
        sys.exit('unsafe zip entry: ' + repr(arc))
if len({a.lower() for _, a in entries}) != len(entries):
    sys.exit('duplicate zip entry names')
tmp = DST + '.tmp'
with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for full, arc in sorted(entries, key=lambda e: e[1]):
        z.write(full, arc)
os.replace(tmp, DST)
shutil.copyfile(DST, WEB_COPY)
b = open(DST, 'rb').read()
sha = hashlib.sha256(b).hexdigest()
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
manifest = {
    'schema': 1,
    'app_name': 'citro-downloads',
    'site': 'dl.chimu-claw.xyz',
    'version': VERSION,
    'build_number': BUILD_NUMBER,
    'file': f'Citro-downloads-{VERSION}.zip',
    'url': f'https://obs.chimu-claw.xyz/web/Citro-downloads-{VERSION}.zip',
    'size': len(b),
    'sha256': sha,
    'published_at': now,
    'notes': NOTES,
}
with open(os.path.join(HERE, '..', 'web', 'downloads.json'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(json.dumps(manifest, ensure_ascii=False, indent=4) + '\n')
print('zip', len(b), 'bytes', len(entries), 'entries')
print('sha256', sha)
print('copied to web/')
