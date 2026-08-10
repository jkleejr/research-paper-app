#!/usr/bin/env python3
"""Compose App Store marketing screenshots (6.9", 1320x2868) from raw captures.

Each frame: caption on a deep ink gradient, with the device capture inset below
under rounded corners and a soft shadow.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(REPO, "screenshots", "raw")
OUT = os.path.join(REPO, "screenshots", "appstore")
W, H = 1320, 2868

# Ink-navy gradient: dark enough that the white app screens read as the subject.
TOP = (11, 24, 46)
BOTTOM = (26, 56, 99)
ACCENT = (94, 168, 255)

FONT = "/System/Library/Fonts/SFNS.ttf"

FRAMES = [
    ("01-library", "Turn research papers\ninto audio",
     "Import a PDF, or start with the\nincluded sample."),
    ("03-reader-playing", "Follow along,\nsentence by sentence",
     "Headers, page numbers and citation clutter\nare cleaned out first."),
    ("08-voices", "Eight narration voices",
     "Pick a voice, and listen at 0.75× to 2×."),
    ("05-library-miniplayer", "Pick up exactly\nwhere you left off",
     "Papers, audio and progress stay on your device."),
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


def gradient():
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


def draw_centered(draw, text, y, f, fill, line_gap=14):
    for line in text.split("\n"):
        w = draw.textbbox((0, 0), line, font=f)[2]
        draw.text(((W - w) / 2, y), line, font=f, fill=fill)
        y += f.size + line_gap
    return y


def compose(order, name, headline, sub):
    shot = Image.open(os.path.join(RAW, name + ".png")).convert("RGB")
    canvas = gradient()
    draw = ImageDraw.Draw(canvas)

    head_f = font(96, "Bold")
    sub_f = font(48, "Regular")

    y = 168
    y = draw_centered(draw, headline, y, head_f, (255, 255, 255), line_gap=18)
    y += 26
    draw_centered(draw, sub, y, sub_f, (176, 199, 228))

    # Accent rule under the caption block.
    rule_y = y + sub_f.size * (sub.count("\n") + 1) + 52
    draw.rounded_rectangle([W / 2 - 46, rule_y, W / 2 + 46, rule_y + 7], radius=4, fill=ACCENT)

    # Device capture.
    shot_w = 946
    shot_h = round(shot_w * H / W)
    shot = shot.resize((shot_w, shot_h), Image.LANCZOS)
    radius = round(55 * 3 * shot_w / W)          # device corner radius, scaled
    shot = rounded(shot, radius)
    sx, sy = (W - shot_w) // 2, 700

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [sx + 10, sy + 26, sx + shot_w - 10, sy + shot_h + 26], radius=radius,
        fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.paste(shot, (sx, sy), shot)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{order:02d}-{name.split('-', 1)[1]}.png")
    canvas.convert("RGB").save(path, "PNG")
    return path


if __name__ == "__main__":
    for i, (name, headline, sub) in enumerate(FRAMES, start=1):
        p = compose(i, name, headline, sub)
        print("wrote", os.path.basename(p), Image.open(p).size)
