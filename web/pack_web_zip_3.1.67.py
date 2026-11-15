# -*- coding: utf-8 -*-
# web zip 打包 + latest.json 回填(3.1.67)
# 用 Python zipfile —— 绝不能用 .NET ZipFile(反斜杠条目在 Linux 端 404)。
import os, sys, zipfile, hashlib, json, datetime, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

VERSION = '3.1.67'
BUILD_NUMBER = '3167'
SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'flutter', 'build', 'web'))
DST = os.path.abspath(os.path.join(os.path.dirname(__file__), f'Citro-web-{VERSION}.zip'))
NOTES = ('3.1.67:「一起看」网页观看端接通声网主链路,断线自动回退;'
         '全屏新增聊天按钮;修复手机 App 退出全屏画面压条;画面比例完整显示。')

if not os.path.isfile(os.path.join(SRC, 'index.html')):
    sys.exit('missing index.html in ' + SRC)
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
b = open(DST, 'rb').read()
sha = hashlib.sha256(b).hexdigest()
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
manifest = {
    'schema': 1,
    'app_name': 'citro',
    'version': VERSION,
    'build_number': BUILD_NUMBER,
    'build_id': sha[:32],
    'file': f'Citro-web-{VERSION}.zip',
    'url': f'https://obs.chimu-claw.xyz/web/Citro-web-{VERSION}.zip',
    'size': len(b),
    'sha256': sha,
    'published_at': now,
    'notes': NOTES,
}
latest_path = os.path.join(os.path.dirname(__file__), 'latest.json')
with open(latest_path, 'w', encoding='utf-8', newline='\n') as f:
    f.write(json.dumps(manifest, ensure_ascii=False, indent=4) + '\n')
print('zip', len(b), 'bytes', len(entries), 'entries')
print('sha256', sha)
print('build_id', sha[:32])
