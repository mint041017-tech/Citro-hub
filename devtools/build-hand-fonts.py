"""Build local handwriting-font subsets for the Citro paper-desk redesign.

Downloads Kalam (400/700) and Caveat (400..700) latin subsets from Google Fonts,
then subsets them down to Latin + punctuation + the CJK punctuation we actually use,
and writes woff2 into fonts/.

Usage:
  python devtools/build-hand-fonts.py
"""
import io
import os
import re
import sys
import urllib.request

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(BASE, 'fonts')
UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36')

TARGETS = [
    # (css family query, output name, weight label)
    ('Kalam:wght@400', 'kalam-400-sub.woff2', '400'),
    ('Kalam:wght@700', 'kalam-700-sub.woff2', '700'),
    ('Caveat:wght@400..700', 'caveat-var-sub.woff2', '400 700'),
]

# Characters the handwriting faces will actually render:
# ASCII, latin-1 accents used in copy, and the punctuation/symbols in UI strings.
KEEP = set(chr(c) for c in range(0x20, 0x7F))
KEEP |= set('ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝßàáâãäåæçèéêëìíîïñòóôõöøùúûüýÿ')
KEEP |= set('‘’“”–—…·•°±×÷→←↑↓★☆♥●○■□▲▼◆◇§¶©®™€£¥')
KEEP |= set('①②③④⑤⑥⑦⑧⑨⑩')


def fetch(url, binary=False):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return data if binary else data.decode('utf-8')


def pick_latin_url(css):
    """Find the src url of the block whose unicode-range starts at U+0000-00FF."""
    blocks = re.findall(r'@font-face\s*\{([^}]*)\}', css)
    for b in blocks:
        if 'U+0000-00FF' not in b:
            continue
        m = re.search(r'src:\s*url\((https://[^)]+)\)', b)
        if m:
            return m.group(1)
    # fallback: last src url (Google orders latin last)
    urls = re.findall(r'src:\s*url\((https://[^)]+)\)', css)
    return urls[-1] if urls else None


def subset(src_bytes, out_path):
    from fontTools import subset as _subset
    from fontTools.ttLib import TTFont
    tmp = out_path + '.tmp.ttf'
    with open(tmp, 'wb') as f:
        f.write(src_bytes)
    text = ''.join(sorted(KEEP))
    _subset.main([
        tmp,
        '--text=' + text,
        '--flavor=woff2',
        '--layout-features=*',
        '--no-hinting',
        '--desubroutinize',
        '--output-file=' + out_path,
    ])
    os.remove(tmp)
    f = TTFont(out_path)
    cmap = len(f.getBestCmap())
    glyphs = f['maxp'].numGlyphs
    f.close()
    return os.path.getsize(out_path), cmap, glyphs


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    ok = 0
    for query, out_name, weight in TARGETS:
        css_url = ('https://fonts.googleapis.com/css2?family=' + query + '&display=swap')
        try:
            css = fetch(css_url)
            latin = pick_latin_url(css)
            if not latin:
                print('FAIL no latin src for ' + query)
                continue
            raw = fetch(latin, binary=True)
            out_path = os.path.join(OUT_DIR, out_name)
            size, cmap, glyphs = subset(raw, out_path)
            print('WROTE %-24s %6.1f KB  weight=%s cmap=%d glyphs=%d'
                  % (out_name, size / 1024.0, weight, cmap, glyphs))
            ok += 1
        except Exception as e:  # noqa: BLE001
            print('FAIL %s: %r' % (query, e))
    return 0 if ok == len(TARGETS) else 1


if __name__ == '__main__':
    sys.exit(main())
