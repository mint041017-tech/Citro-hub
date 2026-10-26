#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Citro Flutter 安卓端：桌面图标 + 启动页字标生成（可重复执行）

输入（只读）：
  flutter/ios/.../Icon-App-1024x1024@1x.png  iOS 图标 —— 旧版方图直接复用，保证两端观感一致
  material/citro-logo.png                    640x640 透明字标 —— 自适应前景 / 圆形图标 / 启动页

输出（flutter/android 工程资源）：
  flutter/android/app/src/main/res/mipmap-{ldpi,mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/
      ic_launcher.png              旧版方形图标（API < 26，与 iOS 图标同构图）
      ic_launcher_round.png        旧版圆形图标（API 25+ 的 android:roundIcon）
      ic_launcher_foreground.png   自适应图标前景层（108dp 画布，透明字标）
      ic_launcher_background.png   自适应图标背景层（iOS 同源奶油纯色）
  flutter/android/app/src/main/res/drawable/splash_logo.png   启动页透明字标

自适应图标几何（Material 规范）：
  两层画布 108dp，启动器只显示中央 72dp 遮罩区域。字标宽度取 72dp 的 80.4%
  （与 iOS 图标一致），即 108dp 画布的 53.6%；内容最大半径约 30.3dp，
  仍在 Ø66dp 安全圆（半径 33dp）内，圆形遮罩不会裁切。

预览（供 Lead 审核，均写 _tmp/team/shell-branding/）：
  icon-preview.png      各密度实际像素 + 48dp 实机观感
  adaptive-masks.png    108dp 自适应图标 × 圆形/方圆/方形遮罩 + Ø66dp 安全圆标注
  splash-preview.png    启动页 390x844dp 布局模拟
  icon-manifest.json    产出文件清单（尺寸/模式/体积/sha256）

用法（工作目录任意；Windows 下中文路径按 UTF-8 处理）：
  <python> devtools/gen-citro-app-icons.py                  # 全部重建 + 校验
  <python> devtools/gen-citro-app-icons.py --verify-only    # 只校验现有产出
  <python> devtools/gen-citro-app-icons.py --only icons
  <python> devtools/gen-citro-app-icons.py --only splash,previews
"""
import argparse
import hashlib
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

# 仓库根目录 = devtools/ 的上一级（脚本放在 devtools/ 里常驻）
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSET_DIR = os.path.join(BASE, 'material')
RES_DIR = os.path.join(BASE, 'flutter', 'android', 'app', 'src', 'main', 'res')
PREVIEW_DIR = os.path.join(BASE, '_tmp', 'team', 'flutter-branding')

SRC_SQUARE = os.path.join(BASE, 'flutter', 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', 'Icon-App-1024x1024@1x.png')
SRC_LOGO = os.path.join(ASSET_DIR, 'citro-logo.png')

# 各密度：Android 密度倍率
DENSITIES = (
    ('ldpi', 0.75),
    ('mdpi', 1.0),
    ('hdpi', 1.5),
    ('xhdpi', 2.0),
    ('xxhdpi', 3.0),
    ('xxxhdpi', 4.0),
)
LEGACY_DP = 48            # 旧版启动图标基准尺寸
ADAPTIVE_DP = 108         # 自适应图标层画布尺寸
SAFE_CIRCLE_DP = 66       # 自适应图标安全圆直径（Material）
ADAPTIVE_LOGO_WIDTH_RATIO = 0.536  # 字标宽度 / 108dp 画布 = iOS 的 80.4% × 72/108
LEGACY_ROUND_LOGO_RATIO = 0.78   # 圆形旧版图标里字标宽度占直径比例
SPLASH_LOGO_PAD = 4       # 启动页字标裁边后四周留白（源图像素）
ALPHA_TRIM = 8            # 计算内容范围时的 alpha 阈值

# 设计令牌（docs/citro-design.md 最终口径）
BG = (237, 230, 214)        # --bg #EDE6D6
CARD = (246, 239, 223)      # --surface #F6EFDF
INK = (46, 44, 34)          # --ink #2E2C22
INK_SOFT = (103, 99, 79)    # --ink-soft #67634F
ACCENT = (242, 164, 60)     # --accent #F2A43C
ACCENT_INK = (154, 86, 6)   # --accent-ink #9A5606
FALLBACK_CREAM = (251, 247, 236)  # #FBF7EC 兜底奶油色

_font_cache = {}


def log(msg):
    print(msg)


def rel(path):
    return os.path.relpath(path, BASE).replace('\\', '/')


# ------------------------------------------------------------------ 基础工具
def load_wordmark():
    """读透明字标并裁掉透明边（返回 RGBA）。"""
    im = Image.open(SRC_LOGO).convert('RGBA')
    bbox = im.getbbox()
    if bbox is None:
        raise RuntimeError('字标源图完全透明：' + SRC_LOGO)
    return im.crop(bbox)


def radial_extent(im, threshold=ALPHA_TRIM):
    """返回不透明像素到图像中心的最大像素距离（用于把内容收进安全圆）。"""
    alpha = im.getchannel('A')
    w, h = im.size
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    data = alpha.tobytes()
    best2 = 0.0
    for y in range(h):
        base = y * w
        dy = y - cy
        row = data[base:base + w]
        for x in range(w):
            if row[x] > threshold:
                dx = x - cx
                d2 = dx * dx + dy * dy
                if d2 > best2:
                    best2 = d2
    return math.sqrt(best2) if best2 > 0 else 1.0


def sample_cream(square):
    """从方图里取主色奶油（同源取色），兜底 #FBF7EC。"""
    colors = square.convert('RGB').getcolors(maxcolors=1 << 22) or []
    colors.sort(key=lambda c: -c[0])
    for _count, color in colors:
        # 奶油底：亮且低彩度；阈值放宽到 232 以命中 JPEG 里最常见的主底色
        if min(color) >= 232 and (max(color) - min(color)) <= 24:
            return tuple(color)
    return FALLBACK_CREAM


def save_png(im, path, optimize=True):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, 'PNG', optimize=optimize, compress_level=9)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fp:
        for chunk in iter(lambda: fp.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def preview_font(size, bold=False):
    key = (size, bold)
    if key in _font_cache:
        return _font_cache[key]
    candidates = []
    if bold:
        candidates += [r'C:\Windows\Fonts\msyhbd.ttc', r'C:\Windows\Fonts\simhei.ttf']
    candidates += [r'C:\Windows\Fonts\msyh.ttc', r'C:\Windows\Fonts\simhei.ttf']
    font = None
    for c in candidates:
        if os.path.exists(c):
            try:
                font = ImageFont.truetype(c, size)
                break
            except OSError:
                continue
    if font is None:
        font = ImageFont.load_default()
    _font_cache[key] = font
    return font


def checkerboard(w, h, cell=16, c1=(224, 218, 205, 255), c2=(243, 238, 228, 255)):
    im = Image.new('RGBA', (w, h), c1)
    d = ImageDraw.Draw(im)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if ((x // cell) + (y // cell)) % 2 == 0:
                d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=c2)
    return im


# ------------------------------------------------------------------ 图标生成
def render_foreground(wordmark, max_radius_src, canvas_px, fit_radius_px):
    """把字标缩放后居中画进 108dp 前景画布，内容半径不超过安全圆。

    粘贴时按缩放后不透明内容的 bbox 中心对齐画布中心，避免整像素取整
    导致的偏心（小画布上尤其明显）。
    """
    scale = fit_radius_px / max_radius_src
    tw = max(1, int(round(wordmark.width * scale)))
    th = max(1, int(round(wordmark.height * scale)))
    art = wordmark.resize((tw, th), Image.LANCZOS)
    bbox = art.getbbox()
    if bbox is None:
        raise RuntimeError('前景字标缩放后为空')
    art_cx = (bbox[0] + bbox[2] - 1) / 2.0
    art_cy = (bbox[1] + bbox[3] - 1) / 2.0
    canvas = Image.new('RGBA', (canvas_px, canvas_px), (0, 0, 0, 0))
    canvas_cx = (canvas_px - 1) / 2.0
    canvas_cy = (canvas_px - 1) / 2.0
    canvas.alpha_composite(art, (int(round(canvas_cx - art_cx)),
                                 int(round(canvas_cy - art_cy))))
    return canvas


def render_legacy_round(wordmark, size, cream):
    """旧版圆形图标：奶油圆盘 + 字标（四周留安全边，不裁切）。"""
    canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(canvas).ellipse(
        (0, 0, size - 1, size - 1), fill=tuple(cream) + (255,))
    logo_w = max(1, int(round(size * LEGACY_ROUND_LOGO_RATIO)))
    logo_h = max(1, int(round(wordmark.height * logo_w / wordmark.width)))
    art = wordmark.resize((logo_w, logo_h), Image.LANCZOS)
    canvas.alpha_composite(art, ((size - logo_w) // 2, (size - logo_h) // 2))
    return canvas


def build_icons():
    square = Image.open(SRC_SQUARE).convert('RGB')
    cream = sample_cream(square)
    wordmark = load_wordmark()
    max_radius = radial_extent(wordmark)
    outputs = []
    for name, scale in DENSITIES:
        out_dir = os.path.join(RES_DIR, 'mipmap-' + name)
        legacy = int(round(LEGACY_DP * scale))
        adaptive = int(round(ADAPTIVE_DP * scale))
        fit_radius_px = max_radius * (adaptive * ADAPTIVE_LOGO_WIDTH_RATIO) / wordmark.width

        # 1) 旧版方形：直接来自奶油底方图（同源）
        square_icon = square.resize((legacy, legacy), Image.LANCZOS)
        p = os.path.join(out_dir, 'ic_launcher.png')
        save_png(square_icon, p)
        outputs.append(p)

        # 2) 旧版圆形：奶油圆盘 + 透明字标
        round_icon = render_legacy_round(wordmark, legacy, cream)
        p = os.path.join(out_dir, 'ic_launcher_round.png')
        save_png(round_icon, p)
        outputs.append(p)

        # 3) 自适应前景：字标宽度对齐 iOS（72dp 可见区的 80.4%）
        fg = render_foreground(wordmark, max_radius, adaptive, fit_radius_px)
        p = os.path.join(out_dir, 'ic_launcher_foreground.png')
        save_png(fg, p)
        outputs.append(p)

        # 4) 自适应背景：同源奶油纯色满铺 108dp 画布
        bg = Image.new('RGB', (adaptive, adaptive), cream)
        p = os.path.join(out_dir, 'ic_launcher_background.png')
        save_png(bg, p)
        outputs.append(p)
    log('icons: %d 个 PNG（6 密度 × 4 张），背景奶油 %s'
        % (len(outputs), '#%02X%02X%02X' % cream))
    return outputs, cream, wordmark, max_radius


# -------------------------------------------------------------- 启动页字标
def build_splash_logo():
    wordmark = load_wordmark()
    pad = SPLASH_LOGO_PAD
    canvas = Image.new(
        'RGBA', (wordmark.width + 2 * pad, wordmark.height + 2 * pad), (0, 0, 0, 0))
    canvas.alpha_composite(wordmark, (pad, pad))
    p = os.path.join(RES_DIR, 'drawable', 'splash_logo.png')
    save_png(canvas, p)
    log('splash: %s  (%dx%d, 已裁透明边)'
        % (rel(p), canvas.width, canvas.height))
    return p


# ------------------------------------------------------------------ 校验
def alpha_stats(im):
    a = im.convert('RGBA').getchannel('A')
    hist = a.histogram()
    total = sum(hist)
    transparent = sum(hist[:ALPHA_TRIM + 1])
    return {
        'min': min(i for i, c in enumerate(hist) if c) if total else 0,
        'max': max(i for i, c in enumerate(hist) if c) if total else 0,
        'transparent_ratio': transparent / float(total) if total else 0.0,
    }


def verify():
    """校验尺寸 / 透明通道 / 安全区，返回错误列表。"""
    errors = []
    checks = []
    for name, scale in DENSITIES:
        d = os.path.join(RES_DIR, 'mipmap-' + name)
        legacy = int(round(LEGACY_DP * scale))
        adaptive = int(round(ADAPTIVE_DP * scale))
        expects = (
            ('ic_launcher.png', (legacy, legacy), 'opaque'),
            ('ic_launcher_round.png', (legacy, legacy), 'round'),
            ('ic_launcher_foreground.png', (adaptive, adaptive), 'foreground'),
            ('ic_launcher_background.png', (adaptive, adaptive), 'opaque'),
        )
        for filename, size, kind in expects:
            path = os.path.join(d, filename)
            tag = 'mipmap-%s/%s' % (name, filename)
            if not os.path.exists(path):
                errors.append('缺少文件 %s' % rel(path))
                continue
            im = Image.open(path)
            if im.size != size:
                errors.append('%s 尺寸 %s，期望 %s' % (tag, im.size, size))
                continue
            st = alpha_stats(im)
            if kind == 'opaque':
                if st['min'] != 255 or st['max'] != 255:
                    errors.append('%s 应为不透明，alpha %d..%d'
                                  % (tag, st['min'], st['max']))
                checks.append('%s %dx%d 不透明 ✓' % (tag, size[0], size[1]))
            elif kind == 'round':
                if st['min'] != 0 or st['max'] != 255:
                    errors.append('%s 圆形图标应有透明角，alpha %d..%d'
                                  % (tag, st['min'], st['max']))
                corner = im.convert('RGBA').getpixel((0, 0))[3]
                if corner != 0:
                    errors.append('%s 四角应透明（(0,0) alpha=%d）' % (tag, corner))
                checks.append('%s %dx%d 圆盘+透明角 ✓' % (tag, size[0], size[1]))
            elif kind == 'foreground':
                if st['min'] != 0 or st['max'] != 255:
                    errors.append('%s 前景层应有透明通道，alpha %d..%d'
                                  % (tag, st['min'], st['max']))
                trimmed = im.convert('RGBA')
                bbox = trimmed.getbbox()
                if bbox is None:
                    errors.append('%s 前景层为空' % tag)
                    continue
                # 按实际不透明像素算最大半径（bbox 四角对异形字标是虚的，不能直接用）
                r = _alpha_max_radius(trimmed)
                r_dp = r / scale
                if r_dp > SAFE_CIRCLE_DP / 2.0 + 0.5:
                    errors.append('%s 字标超出 Ø%d dp 安全圆：半径 %.2f dp'
                                  % (tag, SAFE_CIRCLE_DP, r_dp))
                checks.append('%s %dx%d 内容半径 %.2f dp（≤ Ø%d dp 安全圆半径 %.1f dp）✓'
                              % (tag, size[0], size[1], r_dp, SAFE_CIRCLE_DP,
                                 SAFE_CIRCLE_DP / 2.0))

    splash = os.path.join(RES_DIR, 'drawable', 'splash_logo.png')
    if not os.path.exists(splash):
        errors.append('缺少文件 %s' % rel(splash))
    else:
        im = Image.open(splash)
        if im.mode != 'RGBA':
            errors.append('splash_logo.png 应为 RGBA，实际 %s' % im.mode)
        st = alpha_stats(im)
        if st['min'] != 0 or st['max'] != 255:
            errors.append('splash_logo.png 透明通道异常：alpha %d..%d'
                          % (st['min'], st['max']))
        pad = SPLASH_LOGO_PAD
        bbox = im.convert('RGBA').getbbox()
        if bbox is None or bbox[0] < pad or bbox[1] < pad:
            errors.append('splash_logo.png 裁边异常：%s' % (bbox,))
        checks.append('drawable/splash_logo.png %dx%d 透明字标（裁边+%dpx 留白）✓'
                      % (im.width, im.height, pad))
    return errors, checks


def _alpha_max_radius(im, threshold=ALPHA_TRIM):
    alpha = im.getchannel('A')
    w, h = im.size
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    data = alpha.tobytes()
    best2 = 0.0
    for y in range(h):
        base = y * w
        dy = y - cy
        row = data[base:base + w]
        for x in range(w):
            if row[x] > threshold:
                dx = x - cx
                d2 = dx * dx + dy * dy
                if d2 > best2:
                    best2 = d2
    return math.sqrt(best2)


# ------------------------------------------------------------------ 预览图
def load_adaptive_xxxhdpi():
    d = os.path.join(RES_DIR, 'mipmap-xxxhdpi')
    bg = Image.open(os.path.join(d, 'ic_launcher_background.png')).convert('RGBA')
    fg = Image.open(os.path.join(d, 'ic_launcher_foreground.png')).convert('RGBA')
    return Image.alpha_composite(bg, fg), fg


def mask_circle(im):
    size = im.size
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, size[0] - 1, size[1] - 1), fill=255)
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def mask_squircle(im, radius_ratio=0.22):
    size = im.size
    radius = int(round(size[0] * radius_ratio))
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle(
        (0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def draw_safe_circle(im, size_px, width=2, color=(214, 74, 44, 210)):
    """在 size_px 的正方形预览图上画 Ø66dp 安全圆（按 108dp 画布换算）。"""
    d = ImageDraw.Draw(im)
    r = (SAFE_CIRCLE_DP / 2.0) / ADAPTIVE_DP * size_px
    cx, cy = size_px / 2.0, size_px / 2.0
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=color, width=width)
    tick = width * 3
    d.line((cx - tick, cy, cx + tick, cy), fill=color, width=width)
    d.line((cx, cy - tick, cx, cy + tick), fill=color, width=width)


def build_icon_preview():
    """icon-preview.png：各密度实际像素 + 48dp 实机观感。"""
    W, H = 1320, 1516
    sheet = Image.new('RGBA', (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)
    f_title = preview_font(34, bold=True)
    f_sub = preview_font(18)
    f_sec = preview_font(20, bold=True)
    f_lbl = preview_font(15)
    f_small = preview_font(14)

    d.text((44, 30), 'Citro · 安卓原生壳图标预览', font=f_title, fill=INK)
    d.text((44, 78),
           'devtools/gen-citro-app-icons.py 生成 · 源：素材/citro-logo-square.jpg | 素材/citro-logo.png',
           font=f_sub, fill=INK_SOFT)

    def panel(y, h):
        d.rounded_rectangle((44, y, W - 44, y + h), radius=20, fill=CARD + (255,))

    def density_row(icons, row_top, icon_area_h):
        """按标签宽度分配列宽，图标底部对齐、标签居中，避免小图标标签互相压字。"""
        labels = ['%d px · %s' % (im.width, name) for name, im in icons]
        col_w = []
        for (_name, im), label in zip(icons, labels):
            bbox = d.textbbox((0, 0), label, font=f_small)
            col_w.append(max(im.width, bbox[2] - bbox[0]) + 28)
        x = (W - sum(col_w)) // 2
        for (_name, im), label, width in zip(icons, labels, col_w):
            ix = x + (width - im.width) // 2
            sheet.alpha_composite(im, (ix, row_top + icon_area_h - im.height))
            bbox = d.textbbox((0, 0), label, font=f_small)
            lw = bbox[2] - bbox[0]
            d.text((x + (width - lw) / 2.0, row_top + icon_area_h + 8),
                   label, font=f_small, fill=INK_SOFT)
            x += width

    # ---- ① 旧版方形 ----
    y0 = 122
    panel(y0, 330)
    d.text((68, y0 + 16),
           '① ic_launcher.png —— 旧版方形图标（API < 26 / 部分系统界面，按实际像素显示）',
           font=f_sec, fill=INK)
    square_icons = []
    for name, scale in DENSITIES:
        px = int(round(LEGACY_DP * scale))
        p = os.path.join(RES_DIR, 'mipmap-' + name, 'ic_launcher.png')
        im = Image.open(p).convert('RGBA')
        if im.width != px:
            im = im.resize((px, px), Image.LANCZOS)
        square_icons.append((name, im))
    density_row(square_icons, y0 + 90, 200)

    # ---- ② 旧版圆形 ----
    y0 = 468
    panel(y0, 330)
    d.text((68, y0 + 16),
           '② ic_launcher_round.png —— 旧版圆形图标（API 25+ android:roundIcon）',
           font=f_sec, fill=INK)
    round_icons = []
    for name, scale in DENSITIES:
        p = os.path.join(RES_DIR, 'mipmap-' + name, 'ic_launcher_round.png')
        round_icons.append((name, Image.open(p).convert('RGBA')))
    density_row(round_icons, y0 + 90, 200)

    # ---- ③ 自适应图标 108dp ----
    y0 = 814
    panel(y0, 342)
    d.text((68, y0 + 16),
           '③ 自适应图标（108dp 画布）：圆形遮罩 / 方圆遮罩 / 方形，字标全部位于 Ø66dp 安全圆内',
           font=f_sec, fill=INK)
    comp, fg = load_adaptive_xxxhdpi()
    preview_px = 200
    comp_small = comp.resize((preview_px, preview_px), Image.LANCZOS)
    fg_small = fg.resize((preview_px, preview_px), Image.LANCZOS)
    items = (
        ('圆形遮罩（Pixel 等）', mask_circle(comp_small)),
        ('方圆遮罩（三星/小米等）', mask_squircle(comp_small)),
        ('方形（无遮罩）', comp_small),
    )
    gap = 64
    total_w = len(items) * preview_px + gap * (len(items) - 1) + preview_px + 44
    x = (W - total_w) // 2
    row_top = y0 + 82
    for label, im in items:
        bgc = checkerboard(preview_px, preview_px, cell=20)
        bgc.alpha_composite(im)
        sheet.alpha_composite(bgc, (x, row_top))
        d.rectangle((x, row_top, x + preview_px - 1, row_top + preview_px - 1),
                    outline=(216, 208, 187, 255))
        d.text((x, row_top + preview_px + 12), label, font=f_lbl, fill=INK_SOFT)
        x += preview_px + gap
    # 前景层 + 安全圆叠加
    bgc = checkerboard(preview_px, preview_px, cell=20)
    bgc.alpha_composite(fg_small)
    draw_safe_circle(bgc, preview_px)
    sheet.alpha_composite(bgc, (x, row_top))
    d.rectangle((x, row_top, x + preview_px - 1, row_top + preview_px - 1),
                outline=(216, 208, 187, 255))
    d.text((x, row_top + preview_px + 12), '前景层 + 安全圆 Ø66dp',
           font=f_lbl, fill=ACCENT_INK)

    # ---- ④ 48dp 实机观感 ----
    y0 = 1172
    panel(y0, 300)
    d.text((68, y0 + 16),
           '④ 48dp 实机尺寸观感（左：48dp 实机；右：同图 2x 放大便于检查边缘）',
           font=f_sec, fill=INK)
    mdpi_dir = os.path.join(RES_DIR, 'mipmap-mdpi')
    mdpi_comp = Image.alpha_composite(
        Image.open(os.path.join(mdpi_dir, 'ic_launcher_background.png')).convert('RGBA'),
        Image.open(os.path.join(mdpi_dir, 'ic_launcher_foreground.png')).convert('RGBA'))
    smalls = (
        ('方形（旧版）', Image.open(os.path.join(mdpi_dir, 'ic_launcher.png'))),
        ('圆形（旧版）', Image.open(os.path.join(mdpi_dir, 'ic_launcher_round.png'))),
        ('自适应·圆', mask_circle(mdpi_comp)),
        ('自适应·方圆', mask_squircle(mdpi_comp)),
    )
    real = 48
    step = 136
    total_w = 3 * step + real
    x = (W - total_w) // 2
    for label, im in smalls:
        ic = im.resize((real, real), Image.LANCZOS).convert('RGBA')
        bgc = checkerboard(real + 16, real + 16, cell=8)
        bgc.alpha_composite(ic, (8, 8))
        sheet.alpha_composite(bgc, (x, y0 + 64))
        big = im.resize((real * 2, real * 2), Image.LANCZOS).convert('RGBA')
        big_box = checkerboard(real * 2 + 16, real * 2 + 16, cell=12)
        big_box.alpha_composite(big, (8, 8))
        sheet.alpha_composite(big_box, (x + real // 2 - (real * 2 + 16) // 2,
                                       y0 + 136))
        bbox = d.textbbox((0, 0), label, font=f_lbl)
        lw = bbox[2] - bbox[0]
        d.text((x + real / 2.0 - lw / 2.0, y0 + 258), label,
               font=f_lbl, fill=INK_SOFT)
        x += step

    out = os.path.join(PREVIEW_DIR, 'icon-preview.png')
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    sheet.convert('RGB').save(out, 'PNG', optimize=True)
    log('preview: %s' % rel(out))
    return out


def build_adaptive_masks_preview():
    """adaptive-masks.png：三种遮罩下 108dp 图标 + 安全圆标注。"""
    W, H = 1320, 640
    sheet = Image.new('RGBA', (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)
    f_title = preview_font(30, bold=True)
    f_sub = preview_font(17)
    f_lbl = preview_font(18)

    d.text((44, 30), 'Citro 自适应图标 · 遮罩安全区检查', font=f_title, fill=INK)
    d.text((44, 74),
           '108dp 画布（图中 360px 演示）· 红色细圈为 Ø66dp 安全圆 · 字标内容全部位于圈内，任何遮罩都不会裁切',
           font=f_sub, fill=INK_SOFT)
    comp, fg = load_adaptive_xxxhdpi()
    demo = comp.resize((360, 360), Image.LANCZOS)
    variants = (
        ('圆形遮罩（Pixel / 原生）', mask_circle(demo)),
        ('方圆遮罩（三星 / 小米 / OPPO）', mask_squircle(demo)),
        ('方形（无遮罩极端情况）', demo),
    )
    gap = 60
    total_w = 3 * 360 + 2 * gap
    x = (W - total_w) // 2
    top = 128
    for label, im in variants:
        bgc = checkerboard(360, 360, cell=24)
        bgc.alpha_composite(im)
        draw_safe_circle(bgc, 360)
        sheet.alpha_composite(bgc, (x, top))
        d.rectangle((x, top, x + 359, top + 359), outline=(216, 208, 187, 255))
        d.text((x, top + 380), label, font=f_lbl, fill=INK_SOFT)
        x += 360 + gap
    d.text((44, H - 92),
           '注：字标宽度按 iOS 图标比例（72dp 可见区的 80.4%）生成，内容最大半径约 30.3dp，仍在 Ø66dp 安全圆内。',
           font=f_sub, fill=INK_SOFT)
    out = os.path.join(PREVIEW_DIR, 'adaptive-masks.png')
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    sheet.convert('RGB').save(out, 'PNG', optimize=True)
    log('preview: %s' % rel(out))
    return out


def build_splash_preview():
    """splash-preview.png：390x844dp 启动页布局模拟（2x）。"""
    scale = 2
    W, H = 390 * scale, 844 * scale
    sheet = Image.new('RGBA', (W, H), BG + (255,))
    d = ImageDraw.Draw(sheet)

    splash_path = os.path.join(RES_DIR, 'drawable', 'splash_logo.png')
    logo = Image.open(splash_path).convert('RGBA')
    logo_w = 216 * scale
    logo_h = int(round(logo.height * logo_w / float(logo.width)))
    logo = logo.resize((logo_w, logo_h), Image.LANCZOS)
    top = int(round(H * 0.24))
    x = (W - logo_w) // 2
    sheet.alpha_composite(logo, (x, top))

    f_sub = preview_font(14 * scale)
    sub = '游戏 · 食谱 · 社区'
    bbox = d.textbbox((0, 0), sub, font=f_sub)
    sw = bbox[2] - bbox[0]
    sy = top + logo_h + 14 * scale
    d.text(((W - sw) / 2.0, sy), sub, font=f_sub, fill=INK_SOFT)

    # 测量标注：字标宽度 216dp
    my = top - 30
    d.line((x, my, x + logo_w, my), fill=ACCENT_INK + (255,), width=2)
    for tx in (x, x + logo_w):
        d.line((tx, my - 10, tx, my + 10), fill=ACCENT_INK + (255,), width=2)
    f_tick = preview_font(22)
    d.text((x + logo_w / 2.0 - 34, my - 36), '216dp', font=f_tick, fill=ACCENT_INK)

    # 说明面板
    panel_top = H - 300
    d.rounded_rectangle((40, panel_top, W - 40, H - 40), radius=24,
                        fill=CARD + (255,))
    f_cap = preview_font(22, bold=True)
    f_body = preview_font(20)
    d.text((64, panel_top + 24), '启动页布局模拟（390×844dp @2x，静态）',
           font=f_cap, fill=INK)
    lines = (
        '背景 #EDE6D6（与网站浅色 --bg 一致，无白底）',
        '主视觉：透明字标 splash_logo.png，宽 216dp',
        '副标：游戏 · 食谱 · 社区 · 14sp · #67634F',
        '入场：淡入 + 上浮 12dp，420ms；顶部留白 24%',
    )
    for i, line in enumerate(lines):
        d.text((64, panel_top + 72 + i * 40), line, font=f_body, fill=INK_SOFT)
    out = os.path.join(PREVIEW_DIR, 'splash-preview.png')
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    sheet.convert('RGB').save(out, 'PNG', optimize=True)
    log('preview: %s' % rel(out))
    return out


# ------------------------------------------------------------------ 清单
def write_manifest(cream):
    files = []
    for name, scale in DENSITIES:
        d = os.path.join(RES_DIR, 'mipmap-' + name)
        for filename in ('ic_launcher.png', 'ic_launcher_round.png',
                         'ic_launcher_foreground.png', 'ic_launcher_background.png'):
            p = os.path.join(d, filename)
            if not os.path.exists(p):
                continue
            im = Image.open(p)
            files.append({
                'path': rel(p),
                'size': list(im.size),
                'mode': im.mode,
                'bytes': os.path.getsize(p),
                'sha256': sha256_of(p),
            })
    splash = os.path.join(RES_DIR, 'drawable', 'splash_logo.png')
    if os.path.exists(splash):
        im = Image.open(splash)
        files.append({
            'path': rel(splash),
            'size': list(im.size),
            'mode': im.mode,
            'bytes': os.path.getsize(splash),
            'sha256': sha256_of(splash),
        })
    out = os.path.join(PREVIEW_DIR, 'icon-manifest.json')
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    with open(out, 'w', encoding='utf-8') as fp:
        json.dump({
            'generator': 'devtools/gen-citro-app-icons.py',
            'safe_circle_dp': SAFE_CIRCLE_DP,
            'adaptive_canvas_dp': ADAPTIVE_DP,
            'legacy_dp': LEGACY_DP,
            'background_cream': '#%02X%02X%02X' % cream,
            'files': files,
        }, fp, ensure_ascii=False, indent=2)
    log('manifest: %s（%d 个文件）' % (rel(out), len(files)))


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser(
        description='Citro 安卓外壳图标 / 启动页字标生成器')
    ap.add_argument('--only', default='all',
                    help='逗号分隔：all,icons,splash,previews（默认 all）')
    ap.add_argument('--verify-only', action='store_true',
                    help='只校验现有产出，不生成')
    args = ap.parse_args()
    only = set(x.strip() for x in args.only.split(',') if x.strip())
    do_all = 'all' in only

    if args.verify_only:
        errors, checks = verify()
        for c in checks:
            log('  ✓ ' + c)
        for e in errors:
            log('  ✗ ' + e)
        if errors:
            log('\n校验失败：%d 处问题' % len(errors))
            return 1
        log('\n校验通过：%d 项' % len(checks))
        return 0

    cream = None
    if do_all or 'icons' in only:
        _outputs, cream, _wm, _mr = build_icons()
    if cream is None:
        cream = sample_cream(Image.open(SRC_SQUARE).convert('RGB'))
    if do_all or 'splash' in only:
        build_splash_logo()
    write_manifest(cream)
    if do_all or 'previews' in only:
        build_icon_preview()
        build_adaptive_masks_preview()
        build_splash_preview()

    errors, checks = verify()
    for c in checks:
        log('  ✓ ' + c)
    for e in errors:
        log('  ✗ ' + e)
    if errors:
        log('\n校验失败：%d 处问题' % len(errors))
        return 1
    log('\n校验通过：%d 项' % len(checks))
    return 0


if __name__ == '__main__':
    sys.exit(main())
