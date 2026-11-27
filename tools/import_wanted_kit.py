"""Imports the owner's wanted-poster kit for Ennemis de la guilde (27/11).

Usage: python tools/import_wanted_kit.py PATH_TO/kit-ennemis-guilde

Each PNG is cropped to what can be seen (alpha > 8), given two clear pixels around it, then resized
to a power-of-two texture. The game stretches a texture to its region: the addon draws each piece at
its true proportions (printed here, copied into Art.lua as GL.Art.WantedRatio), which restores the
drawing. Alpha at 8 or less (the kit's near-invisible residue) is cleared. The tapestry and its
border keep their whole 4:3 canvas: the page is 664 x 510, 2 % from 4:3.
Writes GrudgeLedger/Media/AvisRecherche/*.tga.
"""
import sys
from pathlib import Path

from PIL import Image

from import_art import write_tga

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "GrudgeLedger" / "Media" / "AvisRecherche"

# Media name: (kit file, width, height, crop to the visible drawing)
ASSETS = {
    "ToileAlliance": ("backgrounds/alliance-cloth.png", 1024, 512, False),
    "ToileHorde": ("backgrounds/horde-cloth.png", 1024, 512, False),
    "BordureAlliance": ("backgrounds/alliance-trim.png", 1024, 512, False),
    "BordureHorde": ("backgrounds/horde-trim.png", 1024, 512, False),
    "FanionAlliance": ("factions/alliance-banner-blank.png", 128, 256, True),
    "FanionHorde": ("factions/horde-banner-blank.png", 128, 256, True),
    "EmblemeAlliance": ("factions/alliance-emblem.png", 128, 128, True),
    "EmblemeHorde": ("factions/horde-emblem.png", 128, 128, True),
    "AfficheGrande": ("posters/poster-hero.png", 256, 512, True),
    "AfficheMoyenne": ("posters/poster-medium.png", 256, 256, True),
    "AffichePetite": ("posters/poster-compact.png", 256, 256, True),
    "PrimeGrande": ("posters/poster-bounty-hero.png", 256, 512, True),
    "PrimeMoyenne": ("posters/poster-bounty-medium.png", 256, 256, True),
    "PrimePetite": ("posters/poster-bounty-compact.png", 256, 256, True),
    "CadrePortrait": ("posters/portrait-frame-gold.png", 128, 128, True),
    "Medaillon": ("posters/rank-medallion-blank.png", 64, 64, True),
    "Bandeau": ("details/bounty-ribbon-blank.png", 256, 64, True),
    "SceauPrime": ("details/bounty-coin-seal.png", 64, 64, True),
    "Tampon": ("details/cold-stamp-outline.png", 256, 64, True),
    "Cartouche": ("details/priority-label-blank.png", 256, 32, True),
    "SeparateurEncre": ("details/divider-ink.png", 256, 16, True),
    "SeparateurOr": ("details/divider-gold.png", 256, 16, True),
    "IconeMembres": ("details/icon-members.png", 64, 64, True),
    "IconeCrane": ("details/icon-skull.png", 64, 64, True),
    "ClouLaiton": ("details/pin-brass.png", 64, 64, True),
    "ClouFer": ("details/pin-iron.png", 64, 64, True),
}
PAD = 2


def clean(image):
    alpha = image.getchannel("A").point(lambda a: 0 if a <= 8 else a)
    image.putalpha(alpha)
    return image


def main(kit):
    OUT.mkdir(parents=True, exist_ok=True)
    kit = Path(kit)
    for name, (source, width, height, crop) in ASSETS.items():
        image = clean(Image.open(kit / source).convert("RGBA"))
        if crop:
            box = image.getchannel("A").getbbox()
            image = image.crop(box)
        w, h = image.size
        if crop:
            # The two clear pixels are kept at the texture's scale.
            inner = image.resize((width - 2 * PAD, height - 2 * PAD), Image.LANCZOS)
            image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            image.alpha_composite(inner, (PAD, PAD))
        else:
            image = image.resize((width, height), Image.LANCZOS)
        if source.endswith("-cloth.png"):
            image.putalpha(255)
        write_tga(OUT / (name + ".tga"), clean(image) if crop or "trim" in source else image)
        print(f"{name:16s} {width}x{height}  ratio {w / h:.3f}")


if __name__ == "__main__":
    main(sys.argv[1])
