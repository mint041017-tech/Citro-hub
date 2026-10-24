# -*- coding: utf-8 -*-
"""Citro 品牌字体子集构建（可重复执行）

背景
----
index.html 里的 `fonts/zcool-kuaile-400-sub.woff2` 是按旧品牌文案（迟暮·Crew）
子集化的，Citro 新文案里的「柑 橘 窝 卷 缘 段 位 …」等字不在其中，标题会掉回
Noto Sans 而出现「混排」。本脚本从 `_tmp/fonts-src/ZCOOLKuaiLe.ttf`（Google Fonts
单文件 TTF）重新子集化，输出**同名**文件，因此 index.html 无需改动。

字符集来源
----------
  1) index.html 可见文案：剥离 <script>/<style> 与标签后的正文；
  2) 可访问性/展示型属性：content / alt / placeholder / aria-label / title / value；
  3) ASCII + 常用中英文标点（省略号、破折号、书名号、箭头、序号等）；
  4) --extend：额外并入 JS 里的界面文案字符（脚本去注释后的 CJK 字符），
     避免运行期动态生成的标题/标签（如「完整烹饪时间」「猕猴桃」）掉字体；
  5) --full：再并上 GB2312 一级汉字（3755 字），生成 `zcool-kuaile-400-full-sub.woff2`
     备选全量版（index.html 目前不引用它）。

Noto Sans SC 检查
-----------------
  顺带核对 fonts/noto-sans-sc-{400,700}-sub.woff2 是否覆盖上述字符集；400/700
  原本按「旧页面文案 ∪ GB2312 一级字」构建，Citro 新文案属于常用字范围，应当全部
  覆盖。若出现缺字只报告，不替换字体（任务约定：不擅自换字体）。

用法
----
  python devtools/build-citro-fonts.py                # 只重建 -sub
  python devtools/build-citro-fonts.py --extend       # -sub 并上 JS 界面文案
  python devtools/build-citro-fonts.py --full         # 额外生成 -full（GB2312 一级字）
  python devtools/build-citro-fonts.py --check        # 只检查覆盖率，不写文件
  python devtools/build-citro-fonts.py --src <ttf>    # 指定源字体
"""
import argparse
import glob
import io
import json
import os
import re
import sys
from html import unescape

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(BASE, 'fonts')
SRC_DEFAULT = os.path.join(BASE, '_tmp', 'fonts-src', 'ZCOOLKuaiLe.ttf')
SUB_NAME = 'zcool-kuaile-400-sub.woff2'
FULL_NAME = 'zcool-kuaile-400-full-sub.woff2'
NOTO_FILES = {
    'noto-sans-sc-400-sub.woff2': 'Noto Sans SC 400',
    'noto-sans-sc-700-sub.woff2': 'Noto Sans SC 700',
}
REPORT = os.path.join(BASE, '_tmp', 'team', 'asset-forge', 'font-build-report.json')

# 一定会用到的标点/符号（全角与半角）
PUNCT = set(
    '　、。〃々〈〉《》「」『』【】〔〕〖〗〝〞–—…“”‘’·×÷°±≈≠≤≥→←↑↓★☆♥●○■□▲▼◆◇'
    '§¶©®™¥€£℃℉①②③④⑤⑥⑦⑧⑨⑩'
    '，。！？；：（）［］｛｝～＠＃％＆＊＋－／＜＞＝￥'
)
PUNCT |= set(chr(c) for c in range(0x20, 0x7F))

# 品牌新文案兜底：即使以后 index.html 的 title/meta 被改，也确保这些字在子集里
BRAND_GUARANTEE = 'Citro柑橘小窝不卷段位随缘开黑游戏Mod工具食谱日记同频社区'


def log(msg):
    """控制台可能是 GBK，只输出 ASCII 安全内容。"""
    print(msg.encode('ascii', 'replace').decode('ascii'))


def read_index():
    path = os.path.join(BASE, 'index.html')
    with io.open(path, encoding='utf-8', errors='ignore') as f:
        return f.read()


def strip_tags_and_scripts(html):
    t = re.sub(r'<script\b[\s\S]*?</script>', '\n', html, flags=re.I)
    t = re.sub(r'<style\b[\s\S]*?</style>', '\n', t, flags=re.I)
    t = re.sub(r'<[^>]+>', '\n', t)
    return unescape(t)


ATTR_RE = re.compile(
    r'(?:content|alt|placeholder|aria-label|title|value)="([^"]*)"')

# CSS 伪元素里直接出字的 content:"…"（会真正渲染成文字，必须进子集）
CSS_CONTENT_RE = re.compile(r'content\s*:\s*"((?:[^"\\]|\\.)*)"')


def attr_text(html):
    return ' '.join(unescape(x) for x in ATTR_RE.findall(html))


def _css_unescape(raw):
    """只还原 CSS 反斜杠转义（\\201C / \\"），不能碰原文里的中文（不能走 unicode_escape）。"""
    s = re.sub(r'\\([0-9a-fA-F]{1,6})\s?', lambda m: chr(int(m.group(1), 16)), raw)
    return re.sub(r'\\(.)', r'\1', s)


def css_content_text(html):
    """收集会出现文字的 CSS content:"…"，含 index.html 内联 <style> 与 styles/*.css。"""
    chunks = []
    for block in re.findall(r'<style\b[^>]*>([\s\S]*?)</style>', html, flags=re.I):
        chunks.append(block)
    for path in sorted(glob.glob(os.path.join(BASE, 'styles', '*.css'))):
        try:
            with io.open(path, encoding='utf-8', errors='ignore') as f:
                chunks.append(f.read())
        except OSError:
            pass
    out = set()
    for block in chunks:
        for raw in CSS_CONTENT_RE.findall(block):
            out |= set(_css_unescape(raw))
    return out


JS_COMMENT_RE = re.compile(r'/\*[\s\S]*?\*/|//[^\n]*')


def script_ui_chars(html):
    """JS 字符串/模板里可能进入界面的 CJK 字符（去注释后取全集）。"""
    out = set()
    for block in re.findall(r'<script\b[^>]*>([\s\S]*?)</script>', html, flags=re.I):
        code = JS_COMMENT_RE.sub('', block)
        out |= set(c for c in code if '\u4e00' <= c <= '\u9fff')
    return out


def gb2312_level1():
    s = set()
    for b1 in range(0xB0, 0xD8):
        for b2 in range(0xA1, 0xFF):
            try:
                s.add(bytes([b1, b2]).decode('gb2312'))
            except Exception:
                pass
    return s


def build_charsets(html, extend=False):
    """返回 (subset_chars, full_chars, required_chars, meta)。

    required = 一定会被渲染的文字（可见正文/属性/CSS content/品牌兜底）；
    subset   = required ∪ 常用标点（给字体子集额外垫一些常用标点）。
    """
    visible = strip_tags_and_scripts(html)
    css_text = css_content_text(html)
    required = set(visible) | set(attr_text(html)) | css_text | set(BRAND_GUARANTEE)
    chars = set(required) | PUNCT
    meta = {
        'visible_chars': len(set(visible)),
        'attr_chars': len(set(attr_text(html))),
        'css_content_chars': len(css_text),
        'punct_chars': len(PUNCT),
        'required_chars': len(required),
        'extend_chars': 0,
    }
    if extend:
        js = script_ui_chars(html)
        before = len(required)
        required |= js
        chars |= js
        meta['extend_chars'] = len(required) - before
    meta['total_chars'] = len(chars)
    meta['cjk'] = sum(1 for c in chars if '\u4e00' <= c <= '\u9fff')
    full = set(chars) | gb2312_level1()
    meta['full_chars'] = len(full)
    return chars, full, required, meta


def load_cmap(path):
    from fontTools.ttLib import TTFont
    f = TTFont(path)
    return set(f.getBestCmap().keys())


def subset_font(src, chars, out_path):
    """用 fontTools 内置 subset 生成 woff2；返回 (字节数, 覆盖字符数)。"""
    from fontTools import subset as _subset
    text = ''.join(sorted(chars))
    args = [
        src,
        '--text=' + text,
        '--flavor=woff2',
        '--layout-features=*',
        '--no-hinting',
        '--desubroutinize',
        '--output-file=' + out_path,
    ]
    _subset.main(args)
    from fontTools.ttLib import TTFont
    f = TTFont(out_path)
    cmap = set(f.getBestCmap().keys())
    glyphs = f['maxp'].numGlyphs
    f.close()
    return os.path.getsize(out_path), len(cmap), glyphs


def check_noto(chars):
    rows = {}
    for fn, label in NOTO_FILES.items():
        path = os.path.join(OUT_DIR, fn)
        if not os.path.exists(path):
            rows[label] = {'missing': ['<file missing>'], 'missing_count': -1}
            continue
        cmap = load_cmap(path)
        miss = sorted(c for c in chars if ord(c) not in cmap)
        rows[label] = {
            'missing': miss,
            'missing_count': len(miss),
            'size_kb': round(os.path.getsize(path) / 1024.0, 1),
        }
    return rows


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument('--src', default=SRC_DEFAULT)
    ap.add_argument('--full', action='store_true', help='also build GB2312-L1 full variant')
    ap.add_argument('--extend', action='store_true', help='include JS-generated UI copy chars')
    ap.add_argument('--check', action='store_true', help='coverage check only, no write')
    ap.add_argument('--report', default=REPORT)
    args = ap.parse_args()

    if not os.path.exists(args.src):
        log('ERROR: source font not found: ' + args.src)
        return 2
    if not os.path.exists(os.path.join(BASE, 'index.html')):
        log('ERROR: index.html not found')
        return 2

    html = read_index()
    chars, full_chars, required, meta = build_charsets(html, extend=args.extend)

    src_cmap = load_cmap(args.src)
    src_missing = sorted(c for c in required if ord(c) not in src_cmap and ord(c) > 0x1F)
    # 源字体没有的字（emoji / 扩展符号 / 极生僻字）只能回退，脚本里单独报告
    coverable = set(c for c in chars if ord(c) in src_cmap)
    brand_probe = sorted(set(c for c in BRAND_GUARANTEE if ord(c) in src_cmap))

    log('Citro font build')
    log('  required chars   : %d (subset %d, cjk %d)' % (len(required), meta['total_chars'], meta['cjk']))
    log('  source font      : %s (%d cmap)' % (os.path.basename(args.src), len(src_cmap)))
    log('  required not in src: %d' % len(src_missing))
    log('  coverable        : %d' % len(coverable))

    report = {
        'charset': meta,
        'source': {
            'path': os.path.relpath(args.src, BASE).replace('\\', '/'),
            'cmap': len(src_cmap),
            'required_missing_from_source': [{'cp': 'U+%04X' % ord(c), 'ch': c} for c in src_missing],
            'required_missing_from_source_count': len(src_missing),
        },
        'brand_probe': ''.join(brand_probe),
        'noto': check_noto(required),
        'outputs': {},
    }

    if not args.check:
        os.makedirs(OUT_DIR, exist_ok=True)
        # 1) 主字体（index.html 引用的文件名，必须保持）
        out = os.path.join(OUT_DIR, SUB_NAME)
        size, cmap_n, glyphs = subset_font(args.src, coverable, out)
        out_cmap = load_cmap(out)
        still_missing = [c for c in coverable if ord(c) not in out_cmap]
        brand_missing = [c for c in brand_probe if ord(c) not in out_cmap]
        report['outputs'][SUB_NAME] = {
            'bytes': size, 'kb': round(size / 1024.0, 1), 'glyphs': glyphs,
            'cmap': cmap_n, 'text_chars': len(coverable),
            'missing_after_build': still_missing,
            'brand_probe_missing': brand_missing,
        }
        log('  WROTE %-32s %6.1f KB  cmap=%d glyphs=%d' % (SUB_NAME, size / 1024.0, cmap_n, glyphs))
        log('  brand probe covered: %d/%d' % (len(brand_probe) - len(brand_missing), len(brand_probe)))
        if still_missing or brand_missing:
            log('  WARN missing after build (as expected only if not in source font)')

        # 2) 可选全量版（GB2312 一级字兜底，index.html 未引用）
        if args.full:
            out_full = os.path.join(OUT_DIR, FULL_NAME)
            full_coverable = set(c for c in full_chars if ord(c) in src_cmap)
            size, cmap_n, glyphs = subset_font(args.src, full_coverable, out_full)
            report['outputs'][FULL_NAME] = {
                'bytes': size, 'kb': round(size / 1024.0, 1), 'glyphs': glyphs,
                'cmap': cmap_n, 'text_chars': len(full_coverable),
            }
            log('  WROTE %-32s %6.1f KB  cmap=%d glyphs=%d' % (FULL_NAME, size / 1024.0, cmap_n, glyphs))

    # 3) Noto 覆盖检查报告（只报“一定会渲染”的字符；emoji 回退系统字体属正常）
    for label, row in report['noto'].items():
        if row['missing_count'] < 0:
            log('  NOTO %-18s MISSING FILE' % label)
        else:
            log('  NOTO %-18s missing required char(s): %d' % (label, row['missing_count']))
            if row['missing_count']:
                log('       -> %s' % ' '.join(row['missing'][:40]))

    os.makedirs(os.path.dirname(args.report), exist_ok=True)
    with io.open(args.report, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    log('  report: ' + os.path.relpath(args.report, BASE).replace('\\', '/'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
