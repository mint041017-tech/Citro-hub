# -*- coding: utf-8 -*-
"""检查打包字体对项目文案的字符覆盖，找出会 fallback 到系统字体的字。"""
import os
import re
import sys
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "flutter", "lib")
FONTS = {
    "NotoSC-400": os.path.join(ROOT, "flutter", "assets", "fonts", "noto-sc-400-app.ttf"),
    "NotoSC-700": os.path.join(ROOT, "flutter", "assets", "fonts", "noto-sc-700-app.ttf"),
    "ZCOOL": os.path.join(ROOT, "flutter", "assets", "fonts", "zcool-app.ttf"),
    "Kalam-400": os.path.join(ROOT, "flutter", "assets", "fonts", "kalam-400-app.ttf"),
    "Kalam-700": os.path.join(ROOT, "flutter", "assets", "fonts", "kalam-700-app.ttf"),
    "Caveat": os.path.join(ROOT, "flutter", "assets", "fonts", "caveat-app.ttf"),
}


def cmap_of(path):
    f = TTFont(path, fontNumber=0, lazy=True)
    chars = set()
    for table in f["cmap"].tables:
        if table.isUnicode():
            chars.update(table.cmap.keys())
    f.close()
    return chars


def dart_strings():
    for dirpath, _, files in os.walk(LIB):
        for name in files:
            if not name.endswith(".dart"):
                continue
            path = os.path.join(dirpath, name)
            with open(path, encoding="utf-8", errors="replace") as fh:
                for lineno, line in enumerate(fh, 1):
                    stripped = line.strip()
                    if stripped.startswith("//"):
                        continue
                    for ch in line:
                        if "\u4e00" <= ch <= "\u9fff":
                            yield ch, os.path.relpath(path, ROOT), lineno, stripped


def main():
    coverage = {k: cmap_of(v) for k, v in FONTS.items() if os.path.exists(v)}
    print("== 字体覆盖字符数 ==")
    for k, v in coverage.items():
        print(f"{k}: {len(v)}")

    used = {}
    for ch, path, lineno, line in dart_strings():
        used.setdefault(ch, []).append((path, lineno, line))

    noto = coverage.get("NotoSC-400", set())
    missing = {ch: v for ch, v in used.items() if ch not in noto}
    zcool = coverage.get("ZCOOL", set())
    missing_zcool = {ch: v for ch, v in used.items() if ch not in zcool}

    print(f"\n== 文案中不同汉字数: {len(used)} ==")
    print(f"NotoSC 缺失: {len(missing)} 个")
    print(f"ZCOOL 缺失: {len(missing_zcool)} 个")

    print("\n== NotoSC 缺失的字（前 80）==")
    for ch in sorted(missing)[:80]:
        path, lineno, line = missing[ch][0]
        print(f"{ch}  {used[ch].__len__():>3}次  {path}:{lineno}  {line[:90]}")

    with open(os.path.join(ROOT, "devtools", "font_coverage.txt"), "w", encoding="utf-8") as out:
        out.write("字体覆盖:\n")
        for k, v in coverage.items():
            out.write(f"{k}: {len(v)}\n")
        out.write(f"\n文案汉字数: {len(used)}\n")
        out.write(f"NotoSC 缺失 {len(missing)}:\n")
        out.write("".join(sorted(missing)))
        out.write(f"\n\nZCOOL 缺失 {len(missing_zcool)}:\n")
        out.write("".join(sorted(missing_zcool)))
        out.write("\n\n明细:\n")
        for ch in sorted(missing):
            for path, lineno, line in missing[ch][:3]:
                out.write(f"{ch} {path}:{lineno} {line}\n")


if __name__ == "__main__":
    main()