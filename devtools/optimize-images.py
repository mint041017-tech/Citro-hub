# -*- coding: utf-8 -*-
"""图片体积优化：压缩 index.html 实际引用的图片，原图备份到 素材/_原图备份/"""
import os, shutil, glob
from PIL import Image

BASE = r"C:/迟暮/迟暮Crew"
BAK = os.path.join(BASE, "图", "_原图备份")
os.makedirs(BAK, exist_ok=True)


def backup(path):
    dst = os.path.join(BAK, os.path.basename(path))
    if not os.path.exists(dst):
        shutil.copy2(path, dst)
        return True
    return False


def kb(path):
    return round(os.path.getsize(path) / 1024)


def save_jpg(im, path, quality):
    im.save(path, "JPEG", quality=quality, optimize=True, progressive=True)


def resize_keep(im, max_w):
    if im.width <= max_w:
        return im
    h = round(im.height * max_w / im.width)
    return im.resize((max_w, h), Image.LANCZOS)


report = []

# 1) 壁纸：全屏 cover 背景，1920 宽足够
f = os.path.join(BASE, "图", "迟暮壁纸.jpeg")
backup(f)
before = kb(f)
im = Image.open(f).convert("RGB")
im = resize_keep(im, 1920)
save_jpg(im, f, 76)
report.append(("迟暮壁纸.jpeg", before, kb(f), im.size))

# 2) logo：最大显示 72px，256 宽足够（覆盖 3x 屏）
f = os.path.join(BASE, "图", "logo.png")
backup(f)
before = kb(f)
im = Image.open(f)
im = resize_keep(im, 256)
im.save(f, "PNG", optimize=True)
report.append(("logo.png", before, kb(f), im.size))

# 3) MOD 缩略图：卡片显示约 300px，720 宽足够
for f in sorted(glob.glob(os.path.join(BASE, "图", "MOD图片", "*.jpg"))):
    backup(f)
    before = kb(f)
    im = Image.open(f).convert("RGB")
    im = resize_keep(im, 720)
    save_jpg(im, f, 78)
    report.append((os.path.basename(f), before, kb(f), im.size))

# 4) 赞赏码：503px 展示，保持原尺寸仅重压缩
f = os.path.join(BASE, "图", "赞赏码.png")
backup(f)
before = kb(f)
im = Image.open(f)
im.save(f, "PNG", optimize=True)
report.append(("赞赏码.png", before, kb(f), im.size))

print(f"{'文件':<20}{'优化前':>10}{'优化后':>10}{'尺寸':>16}")
tot_b = tot_a = 0
for name, b, a, size in report:
    tot_b += b; tot_a += a
    print(f"{name:<20}{str(b)+'KB':>10}{str(a)+'KB':>10}{str(size):>16}")
print("-" * 56)
print(f"{'合计':<20}{str(tot_b)+'KB':>10}{str(tot_a)+'KB':>10}  压缩 {round((1-tot_a/tot_b)*100)}%")
