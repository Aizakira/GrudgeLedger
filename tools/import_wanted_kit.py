"""Imports the owner's wanted-poster kit for Ennemis de la guilde (v6, 27/11).

Usage: python tools/import_wanted_kit.py PATH_TO/kit-ennemis-guilde-v6 [PATH_TO/collection-affiches-v8]

The v8 collection (owner, 27/11) gives ten families of papers, each a tall one for the first poster
and a small one for the others, plain and gold (a bounty): Affiche<Family><Grande|Carree> and
Prime<Family><Grande|Carree>.

Each PNG is cropped to what can be seen (alpha > 8), given two clear pixels around it, then resized
to a power-of-two texture. The game stretches a texture to its region: the addon draws each piece at
its true proportions (printed here, copied into Art.lua as GL.Art.WantedRatio), which restores the
drawing. Alpha at 8 or less (the kit's near-invisible residue) is cleared.

The tapestry keeps its whole 4:3 canvas (the page is 705 x 531 with its torn edges, 4:3), lit from
its centre: a radial light (owner, 27/11) that leaves the edges at the kit's dark blue or red. Its four
corners are drawn apart at the page's corners, without their rule stubs (the book has its rules).

The papers carry their tilt in the drawing. For each, the text zone is read from the manifest and
given as fractions of the cropped drawing (left, top, right, bottom margins), with the foot: the
margin under the lowest opaque row across the paper's middle, where the ribbon and the button sit.
Both go to Art.lua as GL.Art.WantedText.

The forged nails (v6) are drawn in perspective, their point entering the paper off the canvas's
centre: GL.Art.WantedNail gives that point in fractions of the cropped drawing. The Alliance banner
gives the lion's place on it (GL.Art.WantedEmblem, fractions of the cropped banner).
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
    # The owner keeps the classic arms (27/11): the tall banner, the v2 lion, the crest in the cloth.
    "FanionAlliance": ("v5:factions/alliance-banner-blank.png", 128, 256),
    "FanionHorde": ("factions/horde-banner-blank.png", 128, 256),
    "EmblemeAlliance": ("v2:factions/alliance-emblem.png", 128, 128),
    "EmblemeHorde": ("factions/horde-emblem.png", 128, 128),
    "FiligraneAlliance": ("v5:factions/alliance-watermark.png", 128, 128),
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
    "ClouFace": ("details/nail-forged-front.png", 64, 64),
    "ClouGauche": ("details/nail-forged-left.png", 64, 64),
    "ClouDroite": ("details/nail-forged-right.png", 64, 64),
    "Chevron": ("details/dropdown-chevron.png", 32, 16),
}
# The tapestry's border (owner, 27/11: the gold rules link the flourishes): four corners and four
# straight edges, drawn apart at the page's corners and along its sides; the edges stretch.
for side, faction in (("alliance", "Alliance"), ("horde", "Horde")):
    for part, corner in (("tl", "HG"), ("tr", "HD"), ("bl", "BG"), ("br", "BD")):
        ASSETS[f"Coin{faction}{corner}"] = (f"backgrounds/{side}-corner-{part}.png", 128, 128)
    for part, edge in (("top", "Haut"), ("bottom", "Bas"), ("left", "Gauche"), ("right", "Droite")):
        ASSETS[f"Bord{faction}{edge}"] = (f"backgrounds/{side}-edge-{part}.png", 64, 64)
PAD = 2
# How much the tapestry's centre is lit: its colour times 1 + LIGHT at the centre, times 1 at the edges.
LIGHT = 0.55


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


# The book's frame ornament at the page's bottom right reaches over the page: the tapestry covers
# it, so the addon draws it again over the tapestry, cut from the book's painting (960 x 720 units)
# along the ornament's inner edge, traced by hand (owner, 27/11: the frame stays above).
FRAME_CORNER = (880, 628, 944, 692)
FRAME_EDGE = [(944, 628), (937, 632), (935, 641), (932, 651), (928, 660), (922, 667), (914, 673), (904, 678),
              (894, 683), (888, 685), (880, 686), (880, 692), (944, 692)]


def frame_corner():
    from PIL import ImageDraw, ImageFilter
    book = Image.open(ROOT / "GrudgeLedger" / "Media" / "JournalReferenceSheetBook.tga").convert("RGBA")
    sx, sy = book.width / 960, book.height / 720
    left, top, right, bottom = FRAME_CORNER
    piece = book.crop((round(left * sx), round(top * sy), round(right * sx), round(bottom * sy))).resize((128, 128), Image.LANCZOS)
    mask = Image.new("L", (512, 512), 0)
    k = 512 / (right - left)
    ImageDraw.Draw(mask).polygon([((x - left) * k, (y - top) * k) for x, y in FRAME_EDGE], fill=255)
    piece.putalpha(mask.resize((128, 128), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.6)))
    for x in (0, 127):
        for y in (0, 127):
            piece.putpixel((x, y), (0, 0, 0, 0))
    return piece


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


def paper_zone(image, entry, pad=12):
    """Where the addon writes on a paper, as margins (left, top, right, bottom) in fractions of its
    cropped drawing: on each side the roomier of the kit's text zone and the inside of the printed
    frame less 12 pixels (the kit's zone is careful: the squares' leave a third of the paper empty)."""
    box = image.getchannel("A").getbbox()
    left, top, right, bottom = box
    w, h = right - left, bottom - top
    tl, tt, tr, tb = entry.get("text_rect_px") or entry["suggested_text_roi_px"]
    fl, ft, fr, fb = inner_frame(image)
    zl, zt, zr, zb = min(tl, fl + pad), min(tt, ft + pad), max(tr, fr - pad), max(tb, fb - pad)
    return box, (round((zl - left) / w, 3), round((zt - top) / h, 3), round((right - zr) / w, 3), round((bottom - zb) / h, 3))


def main(kit):
    OUT.mkdir(parents=True, exist_ok=True)
    kit = Path(kit)
    manifest = {a["file"]: a for a in json.loads((kit / "manifest.json").read_text(encoding="utf-8"))["assets"]}
    ratios, zones, marks = {}, {}, {}
    for side, faction in (("alliance", "Alliance"), ("horde", "Horde")):
        cloth = Image.open(kit / f"backgrounds/{side}-cloth.png").convert("RGBA").resize((1024, 512), Image.LANCZOS)
        write_tga(OUT / f"Toile{faction}.tga", lit(cloth))
    write_tga(OUT / "CadreCoinBD.tga", frame_corner())
    for name, (source, width, height) in ASSETS.items():
        path, older = kit / source, source[:1] == "v" and ":" in source
        if older:
            version, source = source.split(":", 1)
            path = kit.parent / ("kit-ennemis-guilde" + ("" if version == "v2" else "-" + version)) / source
        image = clean(Image.open(path).convert("RGBA"))
        if source.startswith("posters/poster-"):
            box, zones[name] = paper_zone(image, manifest[source])
        elif source.startswith("backgrounds/"):
            box = (0, 0) + image.size
        else:
            box = image.getchannel("A").getbbox()
        # The marks of this kit's manifest belong to its own drawings, not to an older kit's.
        entry = {} if older else manifest.get(source, {})
        w, h = box[2] - box[0], box[3] - box[1]
        if entry.get("entry_point_px"):
            x, y = entry["entry_point_px"]
            marks[name] = (round((x - box[0]) / w, 3), round((y - box[1]) / h, 3))
        if entry.get("emblem_rect_px"):
            left, top, right, bottom = entry["emblem_rect_px"]
            marks[name] = (round((left - box[0]) / w, 3), round((top - box[1]) / h, 3),
                           round((right - box[0]) / w, 3), round((bottom - box[1]) / h, 3))
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
    print("-- Nails: where the point enters the paper; banner: the lion's place (left, top, right, bottom)")
    for name, mark in marks.items():
        print(f"    {name} = {{ {', '.join(str(v) for v in mark)} }},")


FAMILIES = {"01-humain": "Humain", "02-elfe-nuit": "ElfeNuit", "03-elfe-sang": "ElfeSang", "04-aerien": "Aerien",
            "05-roublard": "Roublard", "06-demoniste": "Demoniste", "07-troll": "Troll", "08-orc": "Orc",
            "09-tauren": "Tauren", "10-mort-vivant": "MortVivant"}


def collection(folder):
    folder = Path(folder)
    records = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))["records"]
    ratios, zones = {}, {}
    for record in records:
        family = FAMILIES[record["file"].split("/")[0]]
        tall = record["format"] == "hero"
        name = ("Prime" if record["edition"] == "gold" else "Affiche") + family + ("Grande" if tall else "Carree")
        image = clean(Image.open(folder / record["file"]).convert("RGBA"))
        # Their printed frames are richer: the writing keeps further from them.
        box, zones[name] = paper_zone(image, record, 26)
        image = image.crop(box)
        ratios[name] = round(image.width / image.height, 3)
        write_tga(OUT / (name + ".tga"), fitted(image, 256, 512 if tall else 256))
    print("-- v8 collection")
    for name in sorted(ratios):
        print(f"    {name} = {ratios[name]}, -- zone {{ {', '.join(str(v) for v in zones[name])} }}")


if __name__ == "__main__":
    main(sys.argv[1])
    if len(sys.argv) > 2:
        collection(sys.argv[2])
