# -*- coding: utf-8 -*-
"""Citro Flutter 端中文字体子集重建（可重复执行）。

背景
----
`flutter/assets/fonts/*-app.*` 里的 NotoSC 原来是按**旧文案**子集化的：
- 只覆盖 1964 个字符，而 `flutter/lib` 当前文案有 2127 个不同汉字；
- 缺的 296 个字（很 / 因 / 告 / 议 / 导 / 帮 / 环 / 替 …）在各端会掉到系统字体
  （Windows 的微软雅黑、iOS 的苹方、Web 的浏览器默认字体），字重和笔画跟正文字体
  不一致；请求粗体时系统字体还会被引擎合成加粗，小字因此发虚、发灰。
- 旧子集用 `--no-hinting` 裁掉了 TTF 的 prep/gasp，小字号缺少指令对齐，也更显糊。

本脚本
------
1. 字符集 = `flutter/lib` 全部 Dart 源文件字符 ∪ GB2312 一级 + 二级汉字（6763）
   ∪ ASCII ∪ 中英文标点；动态文案（AI 回复、昵称、菜名）也在常用字范围内。
   - 正文 400：一级 + 二级（约 7000 字）
   - 粗体 700 / 标题 ZCOOL：一级 + 项目文案（约 4100 字）
2. 源字体：@fontsource 的 Noto Sans SC 静态 woff2（单文件，无可变轴，无需合并）。
   **注意：woff2 读入后必须把 flavor 置空再保存**，否则输出仍是 wOFF2 容器，
   Flutter 无法加载，所有字都会渲染成 .notdef 方块。
3. 保留 hinting，改善 Windows / Android 小字清晰度。

用法
----
  python devtools/build-app-fonts.py                 # 全部重建
  python devtools/build-app-fonts.py --check         # 只检查覆盖率
  python devtools/build-app-fonts.py --weights 400,700
"""
import argparse
import io
import os
import sys
import time
import urllib.request

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(BASE, 'flutter', 'lib')
OUT = os.path.join(BASE, 'flutter', 'assets', 'fonts')
CACHE = os.path.join(BASE, 'devtools', '.fontcache')
PROBE = os.path.join(CACHE, '_probe')

NOTO_URL = ('https://unpkg.com/@fontsource/noto-sans-sc@5.2.5/files/'
            'noto-sans-sc-chinese-simplified-%d-normal.woff2')
UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36')

NOTO_OUT = {400: 'noto-sc-400-app.ttf', 700: 'noto-sc-700-app.ttf'}
ZCOOL_OUT = 'zcool-app.ttf'
ZCOOL_SRC = os.path.join(BASE, 'devtools', 'fonts-src', 'ZCOOLKuaiLe.ttf')

PUNCT = set(
    '　、。〃々〈〉《》「」『』【】〔〕〖〗〝〞–—…“”‘’·×÷°±≈≠≤≥→←↑↓★☆♥●○■□▲▼◆◇'
    '§¶©®™¥€£℃℉①②③④⑤⑥⑦⑧⑨⑩'
    '，。！？；：（）［］｛｝～＠＃％＆＊＋－／＜＞＝￥'
)
PUNCT |= set(chr(c) for c in range(0x20, 0x7F))


def log(msg):
    try:
        print(msg)
    except UnicodeEncodeError:
        print(msg.encode('utf-8', 'replace').decode('utf-8'))


def gb2312_levels():
    l1, l2 = set(), set()
    for b1 in range(0xB0, 0xD8):
        for b2 in range(0xA1, 0xFF):
            try:
                l1.add(bytes([b1, b2]).decode('gb2312'))
            except Exception:
                pass
    for b1 in range(0xD8, 0xF8):
        for b2 in range(0xA1, 0xFF):
            try:
                l2.add(bytes([b1, b2]).decode('gb2312'))
            except Exception:
                pass
    return l1, l2


def dart_chars():
    out = set()
    for dirpath, _, files in os.walk(LIB):
        for name in files:
            if not name.endswith('.dart'):
                continue
            with io.open(os.path.join(dirpath, name), encoding='utf-8',
                         errors='replace') as f:
                out |= set(f.read())
    return out


def build_charset():
    """正文覆盖 GB2312 一级 + 二级；粗体 / 标题只需一级 + 项目文案。"""
    l1, l2 = gb2312_levels()
    src = dart_chars()
    full = set(l1) | set(l2) | PUNCT | src
    common = set(l1) | PUNCT | src
    full = set(c for c in full if c.isprintable() and not c.isspace()) | set(' \t')
    common = set(c for c in common if c.isprintable() and not c.isspace()) | set(' \t')
    return full, common, l1, l2, src


def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def static_noto(weight):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, 'static-noto-%d.woff2' % weight)
    if not os.path.exists(path) or os.path.getsize(path) < 1024:
        data = fetch(NOTO_URL % weight)
        with open(path, 'wb') as f:
            f.write(data)
        log('  下载 Noto Sans SC %d: %.1f KB' % (weight, len(data) / 1024.0))
    return path


def write_subset(src_path, chars, out_path):
    """子集化并强制输出 SFNT（TTF），不能保留 woff2 容器。"""
    from fontTools import subset as _subset
    opts = _subset.Options()
    opts.flavor = None
    opts.layout_features = ['*']
    opts.hinting = True
    opts.desubroutinize = False
    font = _subset.load_font(src_path, opts)
    subsetter = _subset.Subsetter(options=opts)
    subsetter.populate(text=''.join(sorted(chars)))
    subsetter.subset(font)
    font.flavor = None
    _subset.save_font(font, out_path, opts)
    with open(out_path, 'rb') as fh:
        magic = fh.read(4)
    if magic == b'wOF2':
        raise RuntimeError('输出仍是 woff2，Flutter 无法加载: ' + out_path)


def check(out_path, chars, label):
    from fontTools.ttLib import TTFont
    f = TTFont(out_path, lazy=True)
    cmap = set(f.getBestCmap().keys())
    miss = sorted(c for c in chars if ord(c) not in cmap)
    glyphs = f['maxp'].numGlyphs
    f.close()
    size = os.path.getsize(out_path) / 1024.0
    log('  %-22s %8.1f KB  glyphs=%d  cmap=%d  missing=%d'
        % (label, size, glyphs, len(cmap), len(miss)))
    if miss:
        log('    missing -> %s' % ''.join(miss[:60]))
    return len(miss)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--weights', default='400,700')
    args = ap.parse_args()

    full, common, l1, l2, src = build_charset()
    log('字符集: 正文 %d / 标题 %d (GB2312 L1 %d / L2 %d / 源码 %d)'
        % (len(full), len(common), len(l1), len(l2), len(src)))
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)

    weights = [int(x) for x in args.weights.split(',') if x]
    if args.check:
        missing = 0
        for w in weights:
            p = os.path.join(OUT, NOTO_OUT[w])
            if os.path.exists(p):
                want = full if w == 400 else common
                missing += check(p, want, NOTO_OUT[w])
        p = os.path.join(OUT, ZCOOL_OUT)
        if os.path.exists(p):
            missing += check(p, common, ZCOOL_OUT)
        return 0 if missing == 0 else 1

    for w in weights:
        log('Noto %d' % w)
        src_path = static_noto(w)
        want = full if w == 400 else common
        out = os.path.join(OUT, NOTO_OUT[w])
        t0 = time.time()
        write_subset(src_path, want, out)
        check(out, want, NOTO_OUT[w])
        log('  用时 %.1fs' % (time.time() - t0))

    if os.path.exists(ZCOOL_SRC):
        log('ZCOOL')
        write_subset(ZCOOL_SRC, common, os.path.join(OUT, ZCOOL_OUT))
        check(os.path.join(OUT, ZCOOL_OUT), common, ZCOOL_OUT)
    else:
        log('WARN 缺少 ZCOOL 源字体，跳过')
    log('完成')
    return 0


if __name__ == '__main__':
    sys.exit(main())