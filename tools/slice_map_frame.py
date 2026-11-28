"""Cuts the owner's map frame into four corners and four edges (25/11).

Usage: python tools/slice_map_frame.py PATH_TO/cadre-carte.png

Stretched whole, the frame's corners took the shape of the map and its lines changed width. Cut
this way, the corners keep their drawing and the straight edges stretch. Each corner is 126 pixels
of the master inside a 128 texture, with 2 transparent pixels on its outer sides (game textures need
clear corners); the edges are straight pieces taken from the middle of each side.
Writes GrudgeLedger/Media/RelationsCarte/cadre-*.tga.
"""
import sys
from pathlib import Path

from PIL import Image

from import_art import corners_clear, write_tga

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "GrudgeLedger" / "Media" / "RelationsCarte"
C, PAD = 126, 2


def main(path):
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    corners = {
        "cadre-hg": ((0, 0, C, C), (PAD, PAD)),
        "cadre-hd": ((w - C, 0, w, C), (0, PAD)),
        "cadre-bg": ((0, h - C, C, h), (PAD, 0)),
        "cadre-bd": ((w - C, h - C, w, h), (0, 0)),
    }
    for name, (box, at) in corners.items():
        tile = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        tile.paste(im.crop(box), at)
        assert corners_clear(tile, 0), name
        write_tga(OUT / (name + ".tga"), tile)
    middle_x, middle_y = w // 2 - 256, h // 2 - 128
    edges = {
        "cadre-haut": (middle_x, 0, middle_x + 512, 32),
        "cadre-bas": (middle_x, h - 32, middle_x + 512, h),
        "cadre-gauche": (0, middle_y, 32, middle_y + 256),
        "cadre-droite": (w - 32, middle_y, w, middle_y + 256),
    }
    for name, box in edges.items():
        tile = im.crop(box)
        assert corners_clear(tile, 0), name
        write_tga(OUT / (name + ".tga"), tile)
    print("frame cut:", ", ".join(list(corners) + list(edges)))


if __name__ == "__main__":
    main(sys.argv[1])
