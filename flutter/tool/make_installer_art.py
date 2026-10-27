from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CREAM = (251, 247, 236)
SURFACE = (255, 253, 248)
INK = (35, 33, 28)
INK_SOFT = (110, 104, 88)
LINE = (228, 220, 201)
GRID = (232, 224, 208)
ACCENT = (242, 164, 60)
ACCENT_INK = (143, 78, 5)
TAPE = (240, 176, 184)
TAPE2 = (150, 196, 226)
TAPE3 = (244, 214, 120)
STAMP = (179, 64, 42)
MINT = (143, 199, 160)

FONT_DIR = os.path.join(ROOT, 'assets', 'fonts')


def font(name, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def centered(draw, xy, text, fnt, fill):
    box = draw.textbbox((0, 0), text, font=fnt)
    w = box[2] - box[0]
    draw.text((xy[0] - w / 2, xy[1]), text, font=fnt, fill=fill)


def paper(size):
    im = Image.new('RGB', size, CREAM)
    d = ImageDraw.Draw(im)
    for x in range(0, size[0], 48):
        d.line((x, 0, x, size[1]), fill=GRID, width=1)
    for y in range(0, size[1], 48):
        d.line((0, y, size[0], y), fill=GRID, width=1)
    return im


def tape(im, box, color, angle):
    layer = Image.new('RGBA', im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    d.rectangle((x0, y0, x1, y1), fill=color + (215,))
    # 撕边
    for i in range(x0, x1, 7):
        d.polygon([(i, y1), (i + 4, y1 + 4), (i + 7, y1)], fill=(0, 0, 0, 0))
    layer = layer.rotate(angle, resample=Image.Resampling.BICUBIC, expand=False)
    im.paste(layer, (0, 0), layer)


def round_rect(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def make_wizard():
    W, H = 328, 628
    im = paper((W, H))
    d = ImageDraw.Draw(im)

    # 左上与右下纸胶带
    tape(im, (18, 0, 140, 30), TAPE, -5)
    tape(im, (238, 555, 326, 586), TAPE3, 4)

    logo = Image.open(os.path.join(ROOT, 'assets', 'images', 'logo.webp')).convert('RGBA')
    logo = logo.resize((112, 112), Image.Resampling.LANCZOS)
    im.paste(logo, (108, 38), logo)

    centered(d, (W / 2, 154), 'Citro', font('kalam-700-app.ttf', 66), INK)
    centered(d, (W / 2, 232), '今天也要开心', font('noto-sc-400-app.otf', 24), INK_SOFT)

    # Windows 桌面版徽章
    badge = 'Windows 版'
    f_badge = font('noto-sc-700-app.otf', 15)
    bbox = d.textbbox((0, 0), badge, font=f_badge)
    tw = bbox[2] - bbox[0]
    bx0, bx1 = W / 2 - tw / 2 - 18, W / 2 + tw / 2 + 18
    round_rect(d, (bx0, 292, bx1, 324), 16, (255, 244, 220), ACCENT, 2)
    centered(d, (W / 2, 295), badge, f_badge, ACCENT_INK)

    # 虚线
    for x in range(52, 276, 14):
        d.line((x, 347, x + 7, 347), fill=(190, 180, 158), width=2)

    # 手账小窗口
    x0, y0, x1, y1 = 44, 374, 284, 524
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((x0 + 4, y0 + 10, x1 + 4, y1 + 10), radius=18, fill=(90, 74, 44, 38))
    shadow = shadow.filter(ImageFilter.GaussianBlur(9))
    im.paste(shadow, (0, 0), shadow)

    round_rect(d, (x0, y0, x1, y1), 18, SURFACE, LINE, 2)
    d.line((x0 + 1, y0 + 30, x1 - 1, y0 + 30), fill=LINE, width=2)
    for i, color in enumerate([STAMP, TAPE3, MINT]):
        cx = x0 + 18 + i * 15
        d.ellipse((cx - 4, y0 + 13, cx + 4, y0 + 21), fill=color)
    centered(d, ((x0 + x1) / 2, y0 + 8), 'Citro', font('kalam-700-app.ttf', 20), INK)
    # 左侧天气卡
    round_rect(d, (x0 + 12, y0 + 42, x0 + 120, y0 + 136), 12, (255, 250, 240), LINE, 1)
    centered(d, (x0 + 66, y0 + 51), '今天', font('noto-sc-400-app.otf', 12), INK_SOFT)
    d.ellipse((x0 + 54, y0 + 70, x0 + 78, y0 + 94), fill=ACCENT)
    centered(d, (x0 + 66, y0 + 99), '21°', font('kalam-700-app.ttf', 26), INK)
    # 右侧便签卡
    round_rect(d, (x0 + 132, y0 + 42, x1 - 12, y0 + 136), 12, (251, 241, 196), LINE, 1)
    centered(d, ((x0 + 132 + x1 - 12) / 2, y0 + 53), '今日心情', font('noto-sc-700-app.otf', 11), ACCENT_INK)
    for i in range(3):
        yy = y0 + 78 + i * 13
        d.line((x0 + 145, yy, x1 - 26, yy), fill=(166, 144, 92), width=2)

    # 底部信息
    line = 'Mod · 小工具 · 驱动  /  小游戏  /  应用内更新'
    f_line = font('noto-sc-400-app.otf', 12)
    centered(d, (W / 2, 552), line, f_line, INK_SOFT)
    centered(d, (W / 2, 590), 'chimu-claw.xyz', font('caveat-app.ttf', 24), ACCENT_INK)

    out = os.path.join(ROOT, 'tool', 'installer_wizard.bmp')
    im.save(out, 'BMP')
    print('wizard', out, im.size)


def make_small():
    W = H = 110
    im = paper((W, H))
    d = ImageDraw.Draw(im)
    logo = Image.open(os.path.join(ROOT, 'assets', 'images', 'logo.webp')).convert('RGBA')
    logo = logo.resize((78, 78), Image.Resampling.LANCZOS)
    im.paste(logo, (16, 12), logo)
    d.ellipse((18, 88, 26, 96), fill=ACCENT)
    for x in range(34, 92, 10):
        d.line((x, 92, x + 4, 92), fill=ACCENT, width=2)
    out = os.path.join(ROOT, 'tool', 'installer_small.bmp')
    im.save(out, 'BMP')
    print('small', out, im.size)


if __name__ == '__main__':
    make_wizard()
    make_small()
