"""Imports the owner's wanted-poster kit for Ennemis de la guilde (v5, 27/11).

Usage: python tools/import_wanted_kit.py PATH_TO/kit-ennemis-guilde-v5

Each PNG is cropped to what can be seen (alpha > 8), given two clear pixels around it, then resized
to a power-of-two texture. The game stretches a texture to its region: the addon draws each piece at
its true proportions (printed here, copied into Art.lua as GL.Art.WantedRatio), which restores the
drawing. Alpha at 8 or less (the kit's near-invisible residue) is cleared.

The tapestry keeps its whole 4:3 canvas (the page is 705 x 531 with its torn edges, 4:3), lit from
its centre: a radial light (owner, 27/11) that leaves the edges at the kit's dark blue or red. The
border is assembled from its eight pieces as the kit's manifest places them, on the same canvas.

The papers carry their tilt in the drawing. For each, the text zone is read from the manifest and
given as fractions of the cropped drawing (left, top, right, bottom margins), with the foot: the
margin under the lowest opaque row across the paper's middle, where the ribbon and the button sit.
Both go to Art.lua as GL.Art.WantedText.
Writes GrudgeLedger/Media/AvisRecherche/*.tga.
"""
import json
import sys
from pathlib import Path

from PIL import Image

from import_art import write_tga

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "GrudgeLedger" / "Media" / "AvisRecherche"

# Media name: (kit file, width, height)
ASSETS = {
    "FanionAlliance": ("factions/alliance-banner-blank.png", 128, 256),
    "FanionHorde": ("factions/horde-banner-blank.png", 128, 256),
    "EmblemeAlliance": ("factions/alliance-emblem.png", 128, 128),
    "EmblemeHorde": ("factions/horde-emblem.png", 128, 128),
    "FiligraneAlliance": ("factions/alliance-watermark.png", 128, 128),
    "FiligraneHorde": ("factions/horde-watermark.png", 128, 128),
    "AfficheGrande1": ("posters/poster-hero-minus-2_5.png", 256, 512),
    "AfficheGrande2": ("posters/poster-hero-plus-2.png", 256, 512),
    "AfficheCarree1": ("posters/poster-square-minus-2_5.png", 256, 256),
    "AfficheCarree2": ("posters/poster-square-plus-2.png", 256, 256),
    "PrimeGrande1": ("posters/poster-bounty-hero-minus-2_5.png", 256, 512),
    "PrimeGrande2": ("posters/poster-bounty-hero-plus-2.png", 256, 512),
    "PrimeCarree1": ("posters/poster-bounty-square-minus-2_5.png", 256, 256),
    "PrimeCarree2": ("posters/poster-bounty-square-plus-2.png", 256, 256),
    "CadrePortrait": ("posters/portrait-frame-gold.png", 128, 128),
    "Medaillon": ("posters/rank-medallion-blank.png", 128, 128),
    "MedaillonUn": ("posters/rank-medallion-hero.png", 128, 128),
    "Bandeau": ("details/bounty-ribbon-blank.png", 256, 64),
    "SceauPrime": ("details/bounty-coin-seal.png", 64, 64),
    "Tampon": ("details/cold-stamp-outline.png", 256, 64),
    "Cartouche": ("details/priority-label-blank.png", 256, 32),
    "SeparateurEncre": ("details/divider-ink.png", 256, 16),
    "SeparateurOr": ("details/divider-gold.png", 256, 16),
    "IconeMembres": ("details/icon-members.png", 64, 64),
    "IconeCrane": ("details/icon-skull.png", 64, 64),
    "ClouLaiton": ("details/pin-brass.png", 64, 64),
    "ClouFer": ("details/pin-iron.png", 64, 64),
    "Chevron": ("details/dropdown-chevron.png", 32, 16),
}
PAD = 2
# How much the tapestry's centre is lit: its colour times 1 + LIGHT at the centre, times 1 at the edges.
LIGHT = 0.55
BORDER = ("corner-tl", "corner-tr", "corner-bl", "corner-br", "edge-top", "edge-bottom", "edge-left", "edge-right")


def clean(image):
    image.putalpha(image.getchannel("A").point(lambda a: 0 if a <= 8 else a))
    return image


def fitted(image, width, height):
    inner = image.resize((width - 2 * PAD, height - 2 * PAD), Image.LANCZOS)
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    out.alpha_composite(inner, (PAD, PAD))
    return clean(out)


def lit(cloth):
    """The kit's cloth with a radial light: full at the centre, none on the ellipse through the edges."""
    w, h = cloth.size
    mask = Image.new("L", (w, h))
    pixels = mask.load()
    for y in range(h):
        dy = (y + 0.5 - h / 2) / (h / 2)
        for x in range(w):
            dx = (x + 0.5 - w / 2) / (w / 2)
            m = max(0.0, 1.0 - (dx * dx + dy * dy) ** 0.5)
            pixels[x, y] = int(255 * m ** 1.4 + 0.5)
    rgb = cloth.convert("RGB")
    bright = rgb.point(lambda v: min(255, int(v * (1 + LIGHT) + 0.5)))
    out = Image.composite(bright, rgb, mask).convert("RGBA")
    out.putalpha(255)
    return out


def border(kit, manifest, side):
    panel = Image.new("RGBA", (2048, 1536), (0, 0, 0, 0))
    for part in BORDER:
        name = f"backgrounds/{side}-{part}.png"
        left, top, right, bottom = manifest[name]["panel_rect_px"]
        piece = Image.open(kit / name).convert("RGBA").resize((right - left, bottom - top), Image.BICUBIC)
        panel.alpha_composite(piece, (left, top))
    out = clean(panel.resize((1024, 1024), Image.LANCZOS))
    # The game draws the border over the page's whole rectangle: its corners stay clear of the drawing.
    for x in (0, 1023):
        for y in (0, 1023):
            out.putpixel((x, y), (0, 0, 0, 0))
    return out


def inner_frame(image):
    """The inside of the paper's printed frame: on the paper's middle lines, the last dark row or
    column (the frame's rule) seen from each edge."""
    alpha, rgb = image.getchannel("A").load(), image.convert("RGB").load()
    w, h = image.size

    def mean(points):
        values = [0.2126 * rgb[p][0] + 0.7152 * rgb[p][1] + 0.0722 * rgb[p][2] for p in points if alpha[p] >= 245]
        return sum(values) / len(values) if len(values) > len(points) * 0.6 else None

    rows = [mean([(x, y) for x in range(int(w * .35), int(w * .65), 3)]) for y in range(h)]
    cols = [mean([(x, y) for y in range(int(h * .4), int(h * .6), 3)]) for x in range(w)]

    def rule(profile, indices):
        values = sorted(v for v in profile if v is not None)
        paper, last = values[len(values) // 2], None
        for i in indices:
            if profile[i] is not None and profile[i] < paper - 18:
                last = i
        return last

    return (rule(cols, range(0, int(w * .35))), rule(rows, range(0, int(h * .35))),
            rule(cols, range(w - 1, int(w * .65), -1)), rule(rows, range(h - 1, int(h * .65), -1)))


def paper_zone(image, entry):
    """Where the addon writes on a paper, as margins (left, top, right, bottom) in fractions of its
    cropped drawing: on each side the roomier of the kit's text zone and the inside of the printed
    frame less 12 pixels (the kit's zone is careful: the squares' leave a third of the paper empty)."""
    box = image.getchannel("A").getbbox()
    left, top, right, bottom = box
    w, h = right - left, bottom - top
    tl, tt, tr, tb = entry["text_rect_px"]
    fl, ft, fr, fb = inner_frame(image)
    zl, zt, zr, zb = min(tl, fl + 12), min(tt, ft + 12), max(tr, fr - 12), max(tb, fb - 12)
    return box, (round((zl - left) / w, 3), round((zt - top) / h, 3), round((right - zr) / w, 3), round((bottom - zb) / h, 3))


def main(kit):
    OUT.mkdir(parents=True, exist_ok=True)
    kit = Path(kit)
    manifest = {a["file"]: a for a in json.loads((kit / "manifest.json").read_text(encoding="utf-8"))["assets"]}
    ratios, zones = {}, {}
    for side, faction in (("alliance", "Alliance"), ("horde", "Horde")):
        cloth = Image.open(kit / f"backgrounds/{side}-cloth.png").convert("RGBA").resize((1024, 512), Image.LANCZOS)
        write_tga(OUT / f"Toile{faction}.tga", lit(cloth))
        write_tga(OUT / f"Bordure{faction}.tga", border(kit, manifest, side))
    for name, (source, width, height) in ASSETS.items():
        image = clean(Image.open(kit / source).convert("RGBA"))
        if source.startswith("posters/poster-"):
            box, zones[name] = paper_zone(image, manifest[source])
        else:
            box = image.getchannel("A").getbbox()
        image = image.crop(box)
        ratios[name] = round(image.width / image.height, 3)
        write_tga(OUT / (name + ".tga"), fitted(image, width, height))
    print("GL.Art.WantedRatio = {")
    for name, ratio in ratios.items():
        print(f"    {name} = {ratio},")
    print("}")
    print("GL.Art.WantedText = {")
    for name, zone in zones.items():
        print(f"    {name} = {{ {', '.join(str(v) for v in zone)} }},")
    print("}")


if __name__ == "__main__":
    main(sys.argv[1])
