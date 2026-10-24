# -*- coding: utf-8 -*-
"""Citro 品牌光栅素材构建（可重复执行）

从 `素材/` 里的两张源图生成网站引用的全部位图：
  源图 A：素材/Citro壁纸.png            2720x1536 柑橘水彩插画（原为 palette PNG）
  源图 B：素材/Citro logo（抠图版）.png  2048x2048 透明品牌字标
  源图 C：素材/Citro Backend logo.png    1152x1152 圆形 CITRO 徽章（透明）

产出（文件名/路径被 index.html / manifest.webmanifest / styles/*.css 引用，不可改）：
  citro-wallpaper.jpg        2160x1220 桌面壁纸   q84 4:2:0 progressive
  citro-wallpaper-mobile.jpg 800x1536  手机竖版裁切（中央橙子+两只猫）q85
  citro-logo.png             768x768   透明品牌字标（Hero 水印实际显示 210px）
  citro-mark.png             384x384   圆形徽章（游戏页 360px 低透明底纹）
  citro-mark-128.png         128x128   徽章小图（顶栏/头像/游戏页角标）
  favicon-32/64.png          小尺寸 favicon（收紧裁切 + 锐化，保证标签页可辨）
  apple-touch-icon.png       180x180   奶油圆角底 + 徽章
  icon-192/512.png           PWA 图标（奶油圆角底 + 徽章）
  citro-og.jpg               1200x630  OG 社交分享图（浅色品牌版式）

用法（工作目录 = 仓库根）：
  <python> _tmp/team/asset-forge/build-citro-assets.py            # 全部重建
  <python> _tmp/team/asset-forge/build-citro-assets.py --only og  # 只重建 OG
  <python> _tmp/team/asset-forge/build-citro-assets.py --only favicons,wallpapers
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BASE = r'C:\迟暮\迟暮Crew'
ASSET = os.path.join(BASE, '素材')
SRC_WALL = os.path.join(ASSET, 'Citro壁纸.png')
SRC_LOGO = os.path.join(ASSET, 'Citro logo（抠图版）.png')
SRC_MARK = os.path.join(ASSET, 'Citro Backend logo.png')
ZCOOL = os.path.join(BASE, '_tmp', 'fonts-src', 'ZCOOLKuaiLe.ttf')
BODY_FONT = r'C:\Windows\Fonts\msyh.ttc'
BODY_BOLD = r'C:\Windows\Fonts\msyhbd.ttc'

# 设计令牌（与 styles/citro-core.css 对齐）
CREAM = (251, 247, 236)
CREAM_HI = (253, 250, 240)
CREAM_LO = (245, 238, 222)
INK = (46, 44, 34)
INK2 = (87, 84, 70)
INK_SOFT = (118, 113, 94)
ACCENT = (242, 164, 60)
ACCENT_INK = (154, 86, 6)
MINT = (127, 196, 156)
MINT_INK = (47, 115, 87)


def hexrgb(c):
    return c


def save_jpg(im, path, q=84, subsampling=2):
    im.convert('RGB').save(path, 'JPEG', quality=q, optimize=True,
                           progressive=True, subsampling=subsampling)


def log(msg):
    print(msg)


# ---------------------------------------------------------------- wallpapers
def build_wallpapers():
    src = Image.open(SRC_WALL).convert('RGB')
    W, H = src.size
    # 桌面：2160 宽（源 2720 → 0.79x，1440/1920 屏都够清晰）
    tw = 2160
    desk = src.resize((tw, round(H * tw / W)), Image.LANCZOS)
    save_jpg(desk, os.path.join(ASSET, 'citro-wallpaper.jpg'), q=84)
    # 手机：1:1 像素中央裁切，保留中央橙子切片 + 两只小猫
    cw = 800
    left = 1500 - cw // 2
    mob = src.crop((left, 0, left + cw, H))
    save_jpg(mob, os.path.join(ASSET, 'citro-wallpaper-mobile.jpg'), q=85)
    return {
        'citro-wallpaper.jpg': (desk.size, os.path.getsize(os.path.join(ASSET, 'citro-wallpaper.jpg'))),
        'citro-wallpaper-mobile.jpg': (mob.size, os.path.getsize(os.path.join(ASSET, 'citro-wallpaper-mobile.jpg'))),
    }


# ---------------------------------------------------------------- logos
def alpha_bbox(im):
    return im.convert('RGBA').split()[-1].getbbox()


def build_logos():
    logo = Image.open(SRC_LOGO).convert('RGBA')
    # Hero 水印实际显示 210px（CSS .hero-deco img），768 已覆盖 DPR3，1024 版体积翻倍无收益
    logo768 = logo.resize((768, 768), Image.LANCZOS)
    logo768.save(os.path.join(ASSET, 'citro-logo.png'), 'PNG', optimize=True, compress_level=9)

    mark = Image.open(SRC_MARK).convert('RGBA')
    # 徽章裁掉四周空白，保持正方形（与旧版一致的算法）
    arr = np.array(mark)
    mask = (arr[:, :, :3].astype(int).sum(axis=2) < 735) & (arr[:, :, 3] > 40)
    ys, xs = np.where(mask)
    if len(xs):
        pad = 18
        x0, x1 = max(0, xs.min() - pad), min(arr.shape[1], xs.max() + pad)
        y0, y1 = max(0, ys.min() - pad), min(arr.shape[0], ys.max() + pad)
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        half = max(x1 - x0, y1 - y0) // 2
        x0, x1 = max(0, cx - half), min(arr.shape[1], cx + half)
        y0, y1 = max(0, cy - half), min(arr.shape[0], cy + half)
        mark = mark.crop((x0, y0, x1, y1))
    # 仅用于游戏页 360px、opacity .055 的装饰底纹：384px 足够，体积从 333KB 降到 199KB
    mark384 = mark.resize((384, 384), Image.LANCZOS)
    mark384.save(os.path.join(ASSET, 'citro-mark.png'), 'PNG', optimize=True, compress_level=9)
    mark384.resize((128, 128), Image.LANCZOS).save(
        os.path.join(ASSET, 'citro-mark-128.png'), 'PNG', optimize=True, compress_level=9)
    return mark384


# ---------------------------------------------------------------- favicons / PWA icons
def rounded_bg(size, radius_ratio, bg=(253, 249, 239, 255)):
    c = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(c)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=bg)
    return c


def compose_icon(art, size, inner=0.84, radius_ratio=0.22, sharpen=0.0, punch=1.0):
    canvas = rounded_bg(size, radius_ratio)
    inner_px = max(1, int(round(size * inner)))
    a = art.resize((inner_px, inner_px), Image.LANCZOS)
    if punch != 1.0:
        from PIL import ImageEnhance
        r, g, b, al = a.split()
        rgb = ImageEnhance.Color(Image.merge('RGB', (r, g, b))).enhance(punch)
        a = Image.merge('RGBA', (*rgb.split(), al))
    if sharpen:
        a = a.filter(ImageFilter.UnsharpMask(radius=1.0, percent=int(sharpen * 100), threshold=0))
    canvas.alpha_composite(a, ((size - inner_px) // 2, (size - inner_px) // 2))
    return canvas


def build_icons(mark512):
    # favicon：收紧裁切 + 轻锐化，32px 上仍能看出「CITRO 柑橘徽章」
    compose_icon(mark512, 32, inner=.90, radius_ratio=.18, sharpen=.55, punch=1.10).save(
        os.path.join(ASSET, 'favicon-32.png'), 'PNG', optimize=True)
    compose_icon(mark512, 64, inner=.90, radius_ratio=.19, sharpen=.40, punch=1.08).save(
        os.path.join(ASSET, 'favicon-64.png'), 'PNG', optimize=True)
    # 主屏/PWA 图标：整枚徽章 + 奶油圆角底（与旧版观感一致）
    for size, name, inner, rad in [
        (180, 'apple-touch-icon.png', .84, .24),
        (192, 'icon-192.png', .84, .24),
        (512, 'icon-512.png', .84, .24),
    ]:
        compose_icon(mark512, size, inner=inner, radius_ratio=rad).save(
            os.path.join(ASSET, name), 'PNG', optimize=True)


# ---------------------------------------------------------------- OG image
def load_font(path, size):
    return ImageFont.truetype(path, size)


def have_glyphs(font_path, text):
    from fontTools.ttLib import TTFont
    cmap = set(TTFont(font_path).getBestCmap().keys())
    return all(ord(c) in cmap for c in text)


def draw_text_runs(draw, xy, text, font_primary, font_path_primary, font_fallback, fill):
    """按字符覆盖情况拆 run 绘制（主字体缺字时退回系统字体，避免豆腐块）。"""
    from fontTools.ttLib import TTFont
    cmap = set(TTFont(font_path_primary).getBestCmap().keys())
    x, y = xy
    run, cur = '', None
    def flush():
        nonlocal x, run, cur
        if not run:
            return
        f = font_primary if cur else font_fallback
        draw.text((x, y), run, font=f, fill=fill)
        x += draw.textlength(run, font=f)
        run = ''
    for ch in text:
        use = ord(ch) in cmap
        if cur is None:
            cur = use
        if use != cur:
            flush()
            cur = use
        run += ch
    flush()


def text_w(draw, text, font):
    return draw.textlength(text, font=font)


def make_radial_blob(w, h, cx, cy, rx, ry, color, alpha):
    """柔和径向光斑：预乘 alpha 叠加到 RGBA 图层。"""
    yy, xx = np.mgrid[0:h, 0:w]
    d = ((xx - cx) / float(rx)) ** 2 + ((yy - cy) / float(ry)) ** 2
    a = np.clip(1.0 - np.sqrt(d), 0.0, 1.0) ** 2 * alpha
    layer = np.zeros((h, w, 4), dtype=np.uint8)
    layer[:, :, 0], layer[:, :, 1], layer[:, :, 2] = color
    layer[:, :, 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(layer, 'RGBA')


def build_og():
    S = 2  # 2x 超采样
    W, H = 1200 * S, 630 * S
    canvas = Image.new('RGB', (W, H), CREAM)

    # 顶部提亮 → 底部压暗的极轻渐变，模拟奶油纸
    grad = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None]
    top = np.array(CREAM_HI, dtype=np.float32)
    bot = np.array(CREAM_LO, dtype=np.float32)
    row = top[None, :] * (1 - grad) + bot[None, :] * grad
    canvas = Image.fromarray(
        np.repeat(row[:, None, :].astype(np.uint8), W, axis=1), 'RGB')

    # 柔和品牌光斑
    canvas = Image.alpha_composite(canvas.convert('RGBA'),
                                  make_radial_blob(W, H, int(W * .02), int(H * .96),
                                                   int(W * .42), int(H * .60), MINT, .13))
    canvas = Image.alpha_composite(canvas,
                                  make_radial_blob(W, H, int(W * 1.02), int(H * -.06),
                                                   int(W * .36), int(H * .55), ACCENT, .12))

    # ---------------- 右侧：壁纸圆角卡片 ----------------
    src = Image.open(SRC_WALL).convert('RGB')
    sw, sh = src.size
    card = (int(660 * S), int(46 * S), int(1152 * S), int(584 * S))
    cw, ch = card[2] - card[0], card[3] - card[1]
    target_ar = cw / float(ch)
    if sw / sh > target_ar:          # 源更宽 → 裁宽
        crop_w = int(round(sh * target_ar))
        x0 = (sw - crop_w) // 2 + 160    # 右移一点，让中央橙子居中
        x0 = max(0, min(sw - crop_w, x0))
        crop = src.crop((x0, 0, x0 + crop_w, sh))
    else:
        crop_h = int(round(sw / target_ar))
        y0 = (sh - crop_h) // 2
        crop = src.crop((0, y0, sw, y0 + crop_h))
    art = crop.resize((cw, ch), Image.LANCZOS)

    radius = int(28 * S)
    mask = Image.new('L', (cw, ch), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, cw - 1, ch - 1], radius=radius, fill=255)
    art_masked = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
    art_masked.paste(art, (0, 0), mask)

    # 阴影（模糊圆角块）
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sh_mask = Image.new('L', (cw, ch), 0)
    ImageDraw.Draw(sh_mask).rounded_rectangle([0, 0, cw - 1, ch - 1], radius=radius, fill=150)
    sh_block = Image.new('RGBA', (cw, ch), (88, 74, 40, 255))
    sh_block.putalpha(sh_mask)
    shadow.paste(sh_block, (card[0], card[1] + int(16 * S)), sh_block)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=int(18 * S)))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(art_masked, (card[0], card[1]))

    # 卡片内白描边（半透明需单独图层合成）
    ring = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle(
        [card[0] + 2, card[1] + 2, card[2] - 2, card[3] - 2],
        radius=radius - 2, outline=(255, 255, 255, 220), width=int(3 * S))
    canvas = Image.alpha_composite(canvas, ring)

    # 右下角小圆徽章贴纸（重叠在卡片边缘外，形成贴纸感）
    mark = Image.open(os.path.join(ASSET, 'citro-mark.png')).convert('RGBA')
    ms = int(120 * S)
    mark_small = mark.resize((ms, ms), Image.LANCZOS)
    shadow2 = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    circle = Image.new('L', (ms, ms), 0)
    ImageDraw.Draw(circle).ellipse([0, 0, ms - 1, ms - 1], fill=110)
    blk = Image.new('RGBA', (ms, ms), (88, 74, 40, 255))
    blk.putalpha(circle)
    mx, my = int(622 * S), int(468 * S)
    shadow2.paste(blk, (mx, my), blk)
    shadow2 = shadow2.filter(ImageFilter.GaussianBlur(radius=int(10 * S)))
    canvas = Image.alpha_composite(canvas, shadow2)
    canvas.alpha_composite(mark_small, (mx, my))

    # ---------------- 左侧：品牌文字 ----------------
    logo = Image.open(SRC_LOGO).convert('RGBA')
    lbox = alpha_bbox(logo)
    logo = logo.crop(lbox)
    lw = int(322 * S)
    lh = int(round(logo.height * lw / logo.width))
    logo = logo.resize((lw, lh), Image.LANCZOS)
    canvas.alpha_composite(logo, (int(72 * S), int(58 * S)))

    zcool = load_font(ZCOOL, int(64 * S))
    zcool_sm = load_font(ZCOOL, int(33 * S))
    body_sm = load_font(BODY_FONT, int(19 * S))
    d = ImageDraw.Draw(canvas)
    # 标题：柑橘小窝
    d.text((int(74 * S), int(344 * S)), '柑橘小窝', font=zcool, fill=INK)
    # 橙色小圆点收尾
    dot_r = int(5 * S)
    tw = text_w(d, '柑橘小窝', zcool)
    cy = int(344 * S) + int(64 * S * .52)
    d.ellipse([int(74 * S) + tw + int(14 * S) - dot_r, cy - dot_r,
               int(74 * S) + tw + int(14 * S) + dot_r, cy + dot_r], fill=ACCENT)
    # tagline
    d.text((int(76 * S), int(430 * S)), '不卷段位，随缘开黑', font=zcool_sm, fill=ACCENT_INK)
    # 分隔线（薄荷）
    d.rounded_rectangle([int(76 * S), int(492 * S), int(76 * S) + int(46 * S), int(492 * S) + int(3 * S)],
                        radius=int(2 * S), fill=MINT)
    # 功能行（系统雅黑，确保中文渲染无豆腐）
    d.text((int(76 * S), int(514 * S)), '游戏 Mod 与工具 · 13 款小游戏 · 食谱日记 · 同频社区',
           font=body_sm, fill=INK2)

    og = canvas.convert('RGB').resize((1200, 630), Image.LANCZOS)
    out = os.path.join(ASSET, 'citro-og.jpg')
    og.save(out, 'JPEG', quality=90, optimize=True, progressive=True, subsampling=0)
    return {'citro-og.jpg': (og.size, os.path.getsize(out))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='all',
                    help='comma list: all,wallpapers,logos,icons,og')
    args = ap.parse_args()
    only = set(x.strip() for x in args.only.split(',') if x.strip())
    do_all = 'all' in only
    out = {}
    if do_all or 'wallpapers' in only:
        out.update(build_wallpapers())
        log('wallpapers done')
    if do_all or 'logos' in only or 'icons' in only:
        mark = build_logos()
        log('logos done')
        if do_all or 'icons' in only:
            build_icons(mark)
            log('icons done')
    if do_all or 'og' in only:
        out.update(build_og())
        log('og done')
    for name, (size, bytelen) in sorted(out.items()):
        log('  %-30s %sx%s  %.1f KB' % (name, size[0], size[1], bytelen / 1024.0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
