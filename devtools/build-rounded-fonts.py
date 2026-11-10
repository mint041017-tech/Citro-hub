# -*- coding: utf-8 -*-
"""Build the rounded UI font subsets for the nosh-style redesign.

Source fonts come from the nosh Android APK (com.chaochaoshishi.nosh):
  Resource Han Rounded CN  (SIL Open Font License 1.1)  -- UI / display
  Xiaolai Mono            (SIL Open Font License 1.1)  -- numeric readouts

Both are OFL: embedding and subsetting are permitted. The subset keeps the same
character coverage as the previous Noto Sans SC subset so no UI string falls
back to a system font.

Usage:
  python devtools/build-rounded-fonts.py --src-dir <dir with ib/Px/QS/L8.ttf>
"""
import argparse
import os

from fontTools import subset
from fontTools.ttLib import TTFont

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(BASE, "flutter", "assets", "fonts")
COVERAGE_REF = os.path.join(BASE, "devtools", "fonts-src", "noto-sc-400-app.ttf")

# Punctuation / symbols the UI uses that the previous subset may not carry.
EXTRA = set(
    "　、。〃々〈〉《》「」『』【】〔〕〖〗〝〞–—…“”‘’·×÷°±≈≠≤≥→←↑↓★☆♥●○■□▲▼◆◇"
    "§¶©®™¥€£℃℉①②③④⑤⑥⑦⑧⑨⑩"
    "，。！？；：（）［］｛｝～＠＃％＆＊＋－／＜＞＝￥"
)
ASCII = set(chr(c) for c in range(0x20, 0x7F))
DIGITS = set("0123456789.,:;%+-/()[]<>=%‰kcalKJgmgMJkml×·")

DEFAULTS = {
    "ib.ttf": "rounded-400-app.ttf",
    "Px.ttf": "rounded-500-app.ttf",
    "QS.ttf": "rounded-700-app.ttf",
    "L8.ttf": "mono-app.ttf",
}


def coverage_chars():
    font = TTFont(COVERAGE_REF, lazy=True)
    chars = {chr(cp) for cp in font.getBestCmap() if cp > 0x20}
    font.close()
    chars |= EXTRA | ASCII
    chars.discard("\n")
    chars.discard("\r")
    return "".join(sorted(chars))


def build(src_dir, out_dir, only=None):
    os.makedirs(out_dir, exist_ok=True)
    text = coverage_chars()
    print("subset char count:", len(text))
    for src_name, out_name in DEFAULTS.items():
        if only and src_name not in only:
            continue
        src = os.path.join(src_dir, src_name)
        if not os.path.exists(src):
            print("MISSING", src)
            continue
        opts = subset.Options()
        opts.flavor = None
        opts.hinting = False
        opts.desubroutinize = True
        opts.notdef_outline = True
        opts.recalc_bounds = True
        opts.name_IDs = ["*"]
        opts.name_legacy = True
        opts.name_languages = ["*"]
        font = subset.load_font(src, opts)
        subsetter = subset.Subsetter(options=opts)
        if out_name == "mono-app.ttf":
            subsetter.populate(text="".join(sorted((EXTRA | ASCII | DIGITS) - {" ", "\n"})))
        else:
            subsetter.populate(text=text)
        subsetter.subset(font)
        out = os.path.join(out_dir, out_name)
        subset.save_font(font, out, opts)
        print("wrote %-24s %8.1f KB" % (out_name, os.path.getsize(out) / 1024))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src-dir", required=True)
    ap.add_argument("--out-dir", default=OUT_DIR)
    ap.add_argument("--only", nargs="*", default=None)
    args = ap.parse_args()
    build(args.src_dir, args.out_dir, args.only)


if __name__ == "__main__":
    main()
