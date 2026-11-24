"""Build the balance's ornaments (owner, 24/11): BalanceGlow.tga and the two stars.

BalanceGlow: a soft halo computed here (no generated picture): a white ellipse with a gaussian
falloff, tinted in the game to the balance's colour. The stars come from ChatGPT's lot
art/reference-journal/2026-11-24-etoiles-solde-lueur (owner-local): they are resized to 64 x 64.
Where the lot is absent (GitHub), the stars already in Media are kept.
"""
from pathlib import Path
import math
from PIL import Image

WORK = Path(__file__).resolve().parent.parent
MEDIA = WORK / "GrudgeLedger" / "Media"
LOT = WORK / "art" / "reference-journal" / "2026-11-24-etoiles-solde-lueur"


def glow():
    w, h = 256, 128
    image = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    px = image.load()
    for y in range(h):
        for x in range(w):
            dx, dy = (x + 0.5 - w / 2) / (w / 2), (y + 0.5 - h / 2) / (h / 2)
            d = dx * dx + dy * dy
            a = math.exp(-d * 3.2) - math.exp(-3.2)
            px[x, y] = (255, 255, 255, max(0, min(255, int(a / (1 - math.exp(-3.2)) * 255))))
    image.save(MEDIA / "BalanceGlow.tga", compression=None)


def star(source, target):
    if not source.exists():
        print("kept", target.name)
        return
    image = Image.open(source).convert("RGBA").resize((64, 64), Image.LANCZOS)
    for x in (0, 63):
        for y in (0, 63):
            image.putpixel((x, y), (0, 0, 0, 0))
    image.save(MEDIA / target.name, compression=None)


glow()
star(LOT / "Etoile-rubis.png", MEDIA / "BalanceStarRuby.tga")
star(LOT / "Etoile-or.png", MEDIA / "BalanceStarGold.tga")
print("balance art ready")
