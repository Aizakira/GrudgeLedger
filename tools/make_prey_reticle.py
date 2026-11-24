"""Build Media/PreyReticle.tga: the reticle drawn over a hunted player's name (owner, 24/11).

A placeholder of ours, in the blood red of the parchment stains, until the owner's own art: a ring,
four ticks and a centre dot, with a dark edge so it reads on any background. 64 x 64, uncompressed RGBA.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent / "GrudgeLedger" / "Media"
SIZE, SCALE = 64, 8
RED, EDGE = (176, 30, 22, 255), (20, 6, 4, 230)


def draw(color, grow):
    big = SIZE * SCALE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    pen = ImageDraw.Draw(image)
    c, r, w = big // 2, 21 * SCALE, (3 + grow) * SCALE
    pen.ellipse((c - r, c - r, c + r, c + r), outline=color, width=w)
    half = (1.5 + grow / 2) * SCALE
    for a, b in (((c, 3 * SCALE), (c, 17 * SCALE)), ((c, big - 17 * SCALE), (c, big - 3 * SCALE)),
                 ((3 * SCALE, c), (17 * SCALE, c)), ((big - 17 * SCALE, c), (big - 3 * SCALE, c))):
        if a[0] == b[0]:
            pen.rectangle((a[0] - half, a[1], a[0] + half, b[1]), fill=color)
        else:
            pen.rectangle((a[0], a[1] - half, b[0], a[1] + half), fill=color)
    dot = (2.5 + grow / 2) * SCALE
    pen.ellipse((c - dot, c - dot, c + dot, c + dot), fill=color)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


edge = draw(EDGE, 2).filter(ImageFilter.GaussianBlur(0.6))
art = Image.alpha_composite(edge, draw(RED, 0))
for x in (0, SIZE - 1):
    for y in (0, SIZE - 1):
        art.putpixel((x, y), (0, 0, 0, 0))
art.save(ROOT / "PreyReticle.tga", compression=None)
print("PreyReticle.tga", art.size)
