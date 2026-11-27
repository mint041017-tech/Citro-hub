# -*- coding: utf-8 -*-
# web zip 打包 + latest.json 回填(3.3.5)
# 用 Python zipfile —— 绝不能用 .NET ZipFile(反斜杠条目在 Linux 端 404)。
import hashlib
import io
import json
import os
import sys
import zipfile
from datetime import datetime, timezone

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

VERSION = '3.3.5'
BUILD_NUMBER = '3305'
SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'flutter', 'build', 'web'))
DST = os.path.abspath(os.path.join(os.path.dirname(__file__), f'Citro-web-{VERSION}.zip'))
NOTES = ('3.3.5:新增测试中心与十二系亲密关系测评，MBTI 结果改为测试档案内联回顾；'
         '登录注册支持自动识别手机号/邮箱、免昵称注册与确认密码；'
         '全局玻璃与深色模式通透度重新调校；游戏卡片与游戏页视觉改版；'
         '沿用 3.3.2 的 Web 桌面横屏布局与首屏延迟加载优化。')

if not os.path.isfile(os.path.join(SRC, 'index.html')):
    sys.exit('missing index.html in ' + SRC)

main_js = os.path.join(SRC, 'main.dart.js')
if not os.path.isfile(main_js):
    sys.exit('missing main.dart.js in ' + SRC)
build_id = hashlib.md5(open(main_js, 'rb').read()).hexdigest()
with open(os.path.join(SRC, '.last_build_id'), 'w', encoding='ascii', newline='\n') as f:
    f.write(build_id)

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
now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
manifest = {
    'schema': 1,
    'app_name': 'citro',
    'version': VERSION,
    'build_number': BUILD_NUMBER,
    'build_id': build_id,
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
print('build_id', build_id)