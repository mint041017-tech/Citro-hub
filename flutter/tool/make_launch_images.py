#!/usr/bin/env python3
"""Generate the iOS launch-screen brand block and background color.

The native launch storyboard places a fixed-size transparent brand image
(LaunchBrand, 240×352 pt) over a named background color. Because the image
view has explicit point constraints and uses scaleAspectFit, the block keeps
the same physical size on every iPhone/iPad and in every orientation — it is
never cropped by scaleAspectFill and never resized by the device aspect ratio,
so the handoff to Flutter's fixed-size SplashScreen stays calm.

Light and dark appearance variants mirror the two Flutter splash themes
(CitroColors.light / darkColors). The background is a named color asset with
the same light/dark pair.

Run from flutter/:
    python tool/make_launch_images.py

Requires Pillow. Re-run after changing the logo, splash colors or type scale.
"""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'ios' / 'Runner' / 'Assets.xcassets'
IMAGESET = ASSETS / 'LaunchBrand.imageset'
COLORSET = ASSETS / 'LaunchBackground.colorset'
LOGO = ROOT / 'assets' / 'images' / 'logo.webp'
FONT_400 = ROOT / 'assets' / 'fonts' / 'rounded-400-app.ttf'
FONT_500 = ROOT / 'assets' / 'fonts' / 'rounded-500-app.ttf'
FONT_700 = ROOT / 'assets' / 'fonts' / 'rounded-700-app.ttf'

# The storyboard pins the image view to these point dimensions.
CANVAS_W, CANVAS_H = 240, 352

# CitroColors.light / darkColors (lib/theme/tokens.dart). ink_soft uses ink2:
# 4.65:1 on the cream background, which clears WCAG AA for the 16pt subtitle.
LIGHT = {
    'bg': (249, 237, 215),
    'ink': (97, 74, 68),
    'ink_soft': (125, 101, 94),
    'accent': (169, 201, 196),
    'accent_lt': (220, 234, 231),
    'accent_ink': (62, 90, 85),
    'chip_alpha': 120,
}
DARK = {
    'bg': (30, 26, 24),
    'ink': (242, 237, 228),
    'ink_soft': (207, 197, 184),
    'accent': (184, 212, 208),
    'accent_lt': (46, 58, 56),
    'accent_ink': (216, 232, 229),
    'chip_alpha': 70,
}

SCALES = (1, 2, 3)


def radial_mask(diameter: int, max_alpha: int) -> Image.Image:
    base = ImageOps.invert(Image.radial_gradient('L'))
    base = base.resize((diameter, diameter), Image.LANCZOS)
    return base.point(lambda p: p * max_alpha // 255)


def soft_spot(
    canvas: Image.Image,
    color: tuple[int, int, int],
    center: tuple[float, float],
    diameter: int,
    max_alpha: int,
    blur: float,
) -> None:
    mask = radial_mask(diameter, max_alpha).filter(
        ImageFilter.GaussianBlur(blur)
    )
    layer = Image.new('RGBA', (diameter, diameter), color + (0,))
    layer.putalpha(mask)
    canvas.alpha_composite(
        layer,
        (round(center[0] - diameter / 2), round(center[1] - diameter / 2)),
    )


def draw_tracked(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    center_x: float,
    center_y: float,
    tracking: float = 0,
) -> None:
    widths = [draw.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * max(0, len(text) - 1)
    x = center_x - total / 2
    for ch, width in zip(text, widths):
        draw.text((x, center_y), ch, font=font, fill=fill, anchor='lm')
        x += width + tracking


def draw_sparkle(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    radius: float,
    fill: tuple[int, int, int, int],
    points: int = 4,
) -> None:
    import math

    vertices = []
    for i in range(points * 2):
        angle = -math.pi / 2 + i * math.pi / points
        r = radius if i % 2 == 0 else radius * 0.28
        vertices.append(
            (center[0] + math.cos(angle) * r, center[1] + math.sin(angle) * r)
        )
    draw.polygon(vertices, fill=fill)


def render(palette: dict, scale: int) -> Image.Image:
    s = scale
    canvas = Image.new('RGBA', (CANVAS_W * s, CANVAS_H * s), (0, 0, 0, 0))

    word_font = ImageFont.truetype(str(FONT_700), round(34 * s))
    sub_font = ImageFont.truetype(str(FONT_400), round(16 * s))
    chip_font = ImageFont.truetype(str(FONT_500), round(11 * s))

    word_h = 34 * 1.25 * s
    sub_h = 16 * 1.4 * s
    chip_text_h = 11 * 1.4 * s
    chip_h = chip_text_h + 16 * s
    block_h = 176 * s + 28 * s + word_h + 10 * s + sub_h
    block_h += 18 * s + chip_h
    cx = CANVAS_W * s / 2
    top = (CANVAS_H * s - block_h) / 2
    logo_center = (cx, top + 88 * s)

    soft_spot(
        canvas, palette['accent_lt'], logo_center, round(160 * s), 98, 2 * s,
    )
    logo = Image.open(LOGO).convert('RGBA')
    logo_side = round(148 * s)
    logo = logo.resize((logo_side, logo_side), Image.LANCZOS)
    canvas.alpha_composite(
        logo,
        (round(logo_center[0] - logo_side / 2),
         round(logo_center[1] - logo_side / 2)),
    )

    draw = ImageDraw.Draw(canvas)
    draw_sparkle(
        draw,
        (logo_center[0] + 67 * s, logo_center[1] - 71 * s),
        9 * s,
        palette['accent'] + (145,),
    )

    word_y = top + 176 * s + 28 * s + word_h / 2
    word = 'Citro'
    word_w = sum(draw.textlength(ch, font=word_font) for ch in word)
    word_w += .5 * s * (len(word) - 1)
    dot = 7 * s
    gap = 8 * s
    group_w = word_w + gap + dot
    draw_tracked(
        draw, word, word_font, palette['ink'],
        cx - group_w / 2 + word_w / 2, word_y, .5 * s,
    )
    dot_x = cx - group_w / 2 + word_w + gap + dot / 2
    draw.ellipse(
        (dot_x - dot / 2, word_y - dot / 2, dot_x + dot / 2, word_y + dot / 2),
        fill=palette['accent'],
    )

    sub_y = word_y + word_h / 2 + 10 * s + sub_h / 2
    draw_tracked(
        draw, '今天也要开心', sub_font, palette['ink_soft'], cx, sub_y, 3 * s,
    )

    chip_y = sub_y + sub_h / 2 + 18 * s + chip_h / 2
    chip_text = '记录 · 收藏 · 陪伴'
    tracking = 1.2 * s
    chip_text_w = sum(
        draw.textlength(ch, font=chip_font) for ch in chip_text
    ) + tracking * (len(chip_text) - 1)
    dot_gap = 8 * s
    mark = 5 * s
    pad_x = 14 * s
    chip_w = pad_x * 2 + mark + dot_gap + chip_text_w
    chip_left = cx - chip_w / 2
    chip_top = chip_y - chip_h / 2
    draw.rounded_rectangle(
        (chip_left, chip_top, chip_left + chip_w, chip_top + chip_h),
        radius=chip_h / 2,
        fill=palette['accent_lt'] + (palette['chip_alpha'],),
        outline=palette['accent'] + (60,),
        width=max(1, round(s)),
    )
    mark_x = chip_left + pad_x + mark / 2
    draw.ellipse(
        (mark_x - mark / 2, chip_y - mark / 2,
         mark_x + mark / 2, chip_y + mark / 2),
        fill=palette['accent'],
    )
    draw_tracked(
        draw, chip_text, chip_font, palette['accent_ink'],
        mark_x + mark / 2 + dot_gap + chip_text_w / 2, chip_y, tracking,
    )
    return canvas


def write_images() -> None:
    IMAGESET.mkdir(parents=True, exist_ok=True)
    entries = []
    for scale in SCALES:
        name = 'LaunchBrand.png' if scale == 1 else f'LaunchBrand@{scale}x.png'
        render(LIGHT, scale).save(IMAGESET / name, 'PNG', optimize=True)
        entries.append({'filename': name, 'idiom': 'universal', 'scale': f'{scale}x'})
    for scale in SCALES:
        name = (
            'LaunchBrandDark.png'
            if scale == 1
            else f'LaunchBrandDark@{scale}x.png'
        )
        render(DARK, scale).save(IMAGESET / name, 'PNG', optimize=True)
        entries.append({
            'appearances': [{'appearance': 'luminosity', 'value': 'dark'}],
            'filename': name,
            'idiom': 'universal',
            'scale': f'{scale}x',
        })
    meta = {'images': entries, 'info': {'author': 'xcode', 'version': 1}}
    with open(IMAGESET / 'Contents.json', 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(meta, indent=2) + '\n')


def write_background() -> None:
    COLORSET.mkdir(parents=True, exist_ok=True)

    def components(rgb: tuple[int, int, int]) -> dict:
        return {
            'alpha': '1.000',
            'blue': f'{rgb[2] / 255:.3f}',
            'green': f'{rgb[1] / 255:.3f}',
            'red': f'{rgb[0] / 255:.3f}',
        }

    meta = {
        'colors': [
            {
                'color': {
                    'color-space': 'srgb',
                    'components': components(LIGHT['bg']),
                },
                'idiom': 'universal',
            },
            {
                'appearances': [{'appearance': 'luminosity', 'value': 'dark'}],
                'color': {
                    'color-space': 'srgb',
                    'components': components(DARK['bg']),
                },
                'idiom': 'universal',
            },
        ],
        'info': {'author': 'xcode', 'version': 1},
    }
    with open(COLORSET / 'Contents.json', 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(meta, indent=2) + '\n')


def main() -> None:
    write_images()
    write_background()
    for scale in SCALES:
        print(f'LaunchBrand {CANVAS_W * scale}x{CANVAS_H * scale} pt x{scale}')
    print('LaunchBackground light/dark')


if __name__ == '__main__':
    main()