#!/usr/bin/env python3
"""Compose App Store marketing screenshots from raw captures.

Each frame: caption on a deep ink gradient, with the device capture inset below
under rounded corners and a soft shadow.

Emits both iPhone sizes App Store Connect offers. 6.9" is the one a new iPhone-only
app is required to fill; 6.5" is optional, and its upload box rejects 6.9" images —
dropping a 1320x2868 file there is what produces "the dimensions of one or more
screenshots are wrong". Layout is authored at 6.9" and scaled by SCALE for the rest.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(REPO, "screenshots", "raw")

# (label, width, height, output directory)
SIZES = [
    ('6.9"', 1320, 2868, os.path.join(REPO, "screenshots", "appstore")),
    ('6.5"', 1242, 2688, os.path.join(REPO, "screenshots", "appstore-6.5")),
]

BASE_W = 1320  # the width the layout numbers below were chosen against

# Ink-navy gradient: dark enough that the white app screens read as the subject.
TOP = (11, 24, 46)
BOTTOM = (26, 56, 99)
ACCENT = (94, 168, 255)

FONT = "/System/Library/Fonts/SFNS.ttf"

FRAMES = [
    ("05-library-miniplayer", "Turn research papers\ninto audio",
     "Import a PDF, or start with the sample —\nand pick up where you left off."),
    ("03-reader-playing", "Follow along,\nsentence by sentence",
     "Headers, page numbers and citation clutter\nare cleaned out first."),
    ("08-voices", "Eight narration voices",
     "Pick a voice, and listen at any speed\nfrom 0.5× to 2×."),
    ("07-api-key", "Bring your own\nAPI key",
     "No subscription. Usage is billed to your\nown Google account."),
]


def font(size, weight="Bold"):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def gradient(W, H):
    base = Image.new("RGB", (1, H))
    px = base.load()
    for y in range(H):
        t = y / (H - 1)
        # Ease the ramp so the top stays dark behind the caption.
        t = t ** 1.25
        px[0, y] = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return base.resize((W, H), Image.BICUBIC)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1],
                                           radius=radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def draw_centered(draw, W, text, y, f, fill, line_gap):
    for line in text.split("\n"):
        w = draw.textbbox((0, 0), line, font=f)[2]
        draw.text(((W - w) / 2, y), line, font=f, fill=fill)
        y += f.size + line_gap
    return y


def compose(order, name, headline, sub, W, H, out_dir):
    s = W / BASE_W                               # scale the 6.9" layout to this canvas
    px = lambda n: round(n * s)

    shot = Image.open(os.path.join(RAW, name + ".png")).convert("RGB")
    canvas = gradient(W, H)
    draw = ImageDraw.Draw(canvas)

    head_f = font(px(96), "Bold")
    sub_f = font(px(48), "Regular")

    y = px(168)
    y = draw_centered(draw, W, headline, y, head_f, (255, 255, 255), px(18))
    y += px(26)
    draw_centered(draw, W, sub, y, sub_f, (176, 199, 228), px(14))

    # Accent rule under the caption block.
    rule_y = y + sub_f.size * (sub.count("\n") + 1) + px(52)
    draw.rounded_rectangle([W / 2 - px(46), rule_y, W / 2 + px(46), rule_y + px(7)],
                           radius=px(4), fill=ACCENT)

    # Device capture. Keep the capture's own aspect ratio — the raw shots are 6.9"
    # native, so deriving height from the canvas would squash them at other sizes.
    shot_w = px(946)
    shot_h = round(shot_w * shot.size[1] / shot.size[0])
    shot = shot.resize((shot_w, shot_h), Image.LANCZOS)
    radius = round(55 * 3 * shot_w / W)          # device corner radius, scaled
    shot = rounded(shot, radius)
    sx, sy = (W - shot_w) // 2, px(700)

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [sx + px(10), sy + px(26), sx + shot_w - px(10), sy + shot_h + px(26)],
        radius=radius, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(34)))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.paste(shot, (sx, sy), shot)

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{order:02d}-{name.split('-', 1)[1]}.png")
    canvas.convert("RGB").save(path, "PNG")
    return path


if __name__ == "__main__":
    for label, W, H, out_dir in SIZES:
        print(f"{label} -> {os.path.relpath(out_dir, REPO)}")
        for i, (name, headline, sub) in enumerate(FRAMES, start=1):
            p = compose(i, name, headline, sub, W, H, out_dir)
            print("  wrote", os.path.basename(p), Image.open(p).size)
