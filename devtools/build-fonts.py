# -*- coding: utf-8 -*-
"""字体子集化：从字体 CDN 的 unicode-range 切片重建「按字重的本地单文件子集」

背景
----
页面原本用第三方 CDN 的字体样式表，它有两个问题：
  1) 样式表本身 886KB、799 条 @font-face、跨域且 **渲染阻塞**；
  2) 它把 3 个字体族按 unicode-range 切成 ~100 片，粗体靠可变字体的 wght 轴在
     渲染时实例化 —— 所以 400/700/900 三个字重指向的是**同一批切片 URL**。

自托管时不能直接把某一批切片当成某个字重：切片是 wght 100→900 的可变字体，
**默认实例是 100（ExtraLight）**。必须先按目标字重实例化，否则 700/900 会全部
塌陷成 ExtraLight，标题会明显变细。

流程
----
  CDN CSS → 取各字重切片 URL → 下载(带缓存) → 按 wght 实例化 → 按字形名合并
  → pyftsubset 裁到目标字符集 → fonts/*.woff2

字重与字符集分配
----------------
  full = 页面用字 ∪ GB2312 一级字 ∪ 标点/ASCII   —— 承接接口返回的动态文案
  page = 页面用字 ∪ 标点/ASCII                    —— 仅固定 UI 文案
  art  = 剥离 script/style 后的可见文案 ∪ 标点     —— 装饰性书法体

用法：python devtools/build-fonts.py [输出名或 family/weight ...]   不带参数=全部
"""
import os
import re
import sys
import time
import hashlib
import urllib.request
from collections import defaultdict

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(BASE, 'devtools', '.fontcache')
OUT = os.path.join(BASE, 'fonts')
CSS_CACHE = os.path.join(CACHE, 'fonts.css')

CSS_URL = ('https://miaoda.feishu.cn/fonts/css2'
           '?family=Noto+Serif+SC:wght@400;700;900'
           '&family=Noto+Sans+SC:wght@300;400;500;700'
           '&family=Ma+Shan+Zheng&display=swap')
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36'

# (字族, 字重, 输出文件名, 字符集)
TARGETS = [
    ('Noto Serif SC', 400, 'noto-serif-sc-400-sub.woff2', 'page'),
    ('Noto Serif SC', 700, 'noto-serif-sc-700-sub.woff2', 'page'),
    ('Noto Serif SC', 900, 'noto-serif-sc-900-sub.woff2', 'full'),
    ('Noto Sans SC',  300, 'noto-sans-sc-300-sub.woff2',  'page'),
    ('Noto Sans SC',  400, 'noto-sans-sc-400-sub.woff2',  'full'),
    ('Noto Sans SC',  500, 'noto-sans-sc-500-sub.woff2',  'page'),
    ('Noto Sans SC',  700, 'noto-sans-sc-700-sub.woff2',  'full'),
    ('Ma Shan Zheng', 400, 'ma-shan-zheng-400-sub.woff2', 'art'),
]

os.makedirs(CACHE, exist_ok=True)
os.makedirs(OUT, exist_ok=True)


def fetch_bytes(url, retries=3):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    last = None
    for _ in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=40) as r:
                return r.read()
        except Exception as e:
            last = e
            time.sleep(1.5)
    raise last


def load_css():
    if os.path.exists(CSS_CACHE) and os.path.getsize(CSS_CACHE) > 1024:
        return open(CSS_CACHE, encoding='utf-8', errors='ignore').read()
    css = fetch_bytes(CSS_URL).decode('utf-8', 'ignore')
    with open(CSS_CACHE, 'w', encoding='utf-8') as f:
        f.write(css)
    return css


def parse_rules(css):
    pat_fam = re.compile(r"font-family:\s*'([^']+)'")
    pat_w = re.compile(r'font-weight:\s*(\d+)')
    pat_url = re.compile(r'url\(([^)]+)\)')
    pat_ur = re.compile(r'unicode-range:\s*([^;]+);')
    rules = defaultdict(list)
    for b in re.findall(r'@font-face\s*\{(.*?)\}', css, re.S):
        fm, wm, um, rm = pat_fam.search(b), pat_w.search(b), pat_url.search(b), pat_ur.search(b)
        if not (fm and um):
            continue
        ranges = []
        for part in (rm.group(1) if rm else 'U+0-10FFFF').split(','):
            part = part.strip().lower().replace('u+', '')
            if '-' in part:
                a, b2 = part.split('-')
                ranges.append((int(a, 16), int(b2, 16)))
            else:
                v = int(part, 16)
                ranges.append((v, v))
        rules[(fm.group(1), int(wm.group(1)) if wm else 400)].append((ranges, um.group(1)))
    return rules


def build_charsets():
    page = ''
    for fn in ['index.html', 'beian.html']:
        p = os.path.join(BASE, fn)
        if os.path.exists(p):
            page += open(p, encoding='utf-8', errors='ignore').read()
    raw = open(os.path.join(BASE, 'index.html'), encoding='utf-8', errors='ignore').read()
    t = re.sub(r'<script[\s\S]*?</script>', '', raw)
    t = re.sub(r'<style[\s\S]*?</style>', '', t)
    t = re.sub(r'<[^>]+>', '', t)
    visible = t

    common = set()
    for b1 in range(0xB0, 0xD8):
        for b2 in range(0xA1, 0xFF):
            try:
                common.add(bytes([b1, b2]).decode('gb2312'))
            except Exception:
                pass
    punct = set(chr(c) for c in range(0x20, 0x7F))
    punct |= set('　、。〃々〈〉《》「」『』【】〔〕〖〗〝〞–—…“”‘’·×÷°±≈≠≤≥→←↑↓★☆♥●○■□▲▼◆◇§¶©®™¥€£℃℉①②③④⑤⑥⑦⑧⑨⑩')
    return {
        'full': set(page) | common | punct,
        'page': set(page) | punct,
        'art': set(visible) | punct,
    }


def fetch_slice(url):
    fp = os.path.join(CACHE, hashlib.md5(url.encode()).hexdigest() + '.woff2')
    if os.path.exists(fp) and os.path.getsize(fp) > 100:
        return fp
    data = fetch_bytes(url)
    if len(data) < 100:
        raise RuntimeError('切片过小: %s' % url)
    with open(fp, 'wb') as f:
        f.write(data)
    return fp


def main():
    from fontTools.ttLib import TTFont
    from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
    from fontTools.varLib import instancer
    from fontTools import subset as _subset

    def load_at(path, wght):
        """切片是 wght 100-900 的可变字体，默认实例为 100(ExtraLight)，必须先实例化。"""
        f = TTFont(path)
        if 'fvar' in f and any(a.axisTag == 'wght' for a in f['fvar'].axes):
            f = instancer.instantiateVariableFont(
                f, {'wght': wght}, inplace=False, updateFontNames=False)
        return f

    def merge_slices(paths, wght):
        """按字形名手工合并：fontTools 的 Merger 会因切片内可变表冲突而失败。"""
        base = load_at(paths[0], wght)
        order = list(base.getGlyphOrder())
        seen = set(order)
        glyf, hmtx = base['glyf'], base['hmtx']
        cmap = dict(base.getBestCmap())
        for p in paths[1:]:
            f = load_at(p, wght)
            fg, fh = f['glyf'], f['hmtx']
            for name in f.getGlyphOrder():
                if name in seen:
                    continue
                seen.add(name)
                order.append(name)
                glyf[name] = fg[name]
                hmtx[name] = fh[name]
            for u, n in f.getBestCmap().items():
                cmap.setdefault(u, n)
        base.setGlyphOrder(order)
        base['maxp'].numGlyphs = len(order)
        base['OS/2'].usWeightClass = wght
        for tag in ['gvar', 'fvar', 'avar', 'HVAR', 'VVAR', 'MVAR', 'STAT', 'cvar', 'VORG', 'vmtx', 'vhea']:
            if tag in base:
                del base[tag]
        sub = CmapSubtable.newSubtable(4)
        sub.platformID, sub.platEncID, sub.language = 3, 1, 0
        sub.cmap = {u: n for u, n in cmap.items() if u <= 0xFFFF and n in seen}
        base['cmap'].tables = [sub]
        return base

    css = load_css()
    rules = parse_rules(css)
    sets = build_charsets()
    print('字符集: full %d | page %d | art %d   |  CDN 规则 %d 条' %
          (len(sets['full']), len(sets['page']), len(sets['art']), sum(len(v) for v in rules.values())))

    only = sys.argv[1:]
    merged_path = os.path.join(CACHE, 'merged.ttf')
    total = 0

    print('\n%-34s %-5s %-6s %6s %9s %s' % ('输出', '字重', '字符集', '切片', '大小', '缺失(非该字体内字符)'))
    for fam, wt, outname, setname in TARGETS:
        if only and ('%s/%d' % (fam, wt)) not in only and outname not in only:
            continue
        if (fam, wt) not in rules:
            print('  缺字体规则:', fam, wt)
            continue
        chars = sets[setname]

        need, seen_urls = [], set()
        for ranges, url in rules[(fam, wt)]:
            if url in seen_urls:
                continue
            for cp in chars:
                v = ord(cp)
                if any(a <= v <= b for a, b in ranges):
                    need.append(url)
                    seen_urls.add(url)
                    break
        paths = [fetch_slice(u) for u in need]

        t0 = time.time()
        mf = load_at(paths[0], wt) if len(paths) == 1 else merge_slices(paths, wt)
        mf.save(merged_path)

        dp = os.path.join(OUT, outname)
        _subset.main([merged_path, '--text=' + ''.join(sorted(chars)), '--flavor=woff2',
                      '--layout-features=*', '--no-hinting', '--desubroutinize',
                      '--output-file=' + dp])
        cmap = TTFont(dp).getBestCmap()
        miss = sum(1 for c in chars if ord(c) not in cmap)
        size = os.path.getsize(dp) / 1024
        total += size
        print('%-34s %-5s %-6s %6d %8.0fKB  合并%.0fs  缺失 %d' %
              (outname, wt, setname, len(paths), size, time.time() - t0, miss))

    print('-' * 78)
    print('合计 %.2f MB' % (total / 1024))
    print('\n提醒：index.html 里的 @font-face 必须逐字重声明 font-weight，')
    print('      不能写成 font-weight:100 900 —— 那会让 700/900 塌陷成 400。')


if __name__ == '__main__':
    main()
