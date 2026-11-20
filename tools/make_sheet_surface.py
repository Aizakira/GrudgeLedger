"""Build Media/JournalBookSurfaceSheet.tga from JournalBookSurface.tga: the same book with a
narrower left column (about 20 % of the window) for the player sheet. The header band, the
banners and the frame stay untouched; the parchment interior is stretched to fill.

Usage: python -I tools/make_sheet_surface.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / "GrudgeLedger" / "Media"
SOURCE, TARGET = ROOT / "JournalBookSurface.tga", ROOT / "JournalBookSurfaceSheet.tga"
HEADER_ROWS = 214          # rows above the column divider are kept as they are
NEW_DIVIDER = 228          # texture x where the left leather column now ends
DIVIDER = (365, 400)       # divider line and parchment edge in the source
RIGHT_EDGE = 960           # parchment right edge and frame, kept as they are


def read_tga(path):
    data = path.read_bytes()
    assert data[2] == 2 and data[16] == 32, "uncompressed 32-bit TGA expected"
    width, height = int.from_bytes(data[12:14], "little"), int.from_bytes(data[14:16], "little")
    start = 18 + data[0]
    image = Image.frombytes("RGBA", (width, height), data[start:start + width * height * 4], "raw", "BGRA")
    if not data[17] & 0x20:  # bottom-left origin
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return image, data[:18]


def write_tga(path, image, header):
    # Same header as the source (uncompressed, 32-bit, 8 alpha bits, same origin).
    if not header[17] & 0x20:
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    head = bytearray(header)
    head[0] = 0
    path.write_bytes(bytes(head) + image.tobytes("raw", "BGRA"))


def main():
    src, header = read_tga(SOURCE)
    w, h = src.size
    out = src.copy()
    body = (0, HEADER_ROWS, w, h)
    left = src.crop((0, HEADER_ROWS, NEW_DIVIDER, h))
    divider = src.crop((DIVIDER[0], HEADER_ROWS, DIVIDER[1], h))
    right = src.crop((RIGHT_EDGE, HEADER_ROWS, w, h))
    middle_width = w - NEW_DIVIDER - divider.width - right.width
    middle = src.crop((DIVIDER[1], HEADER_ROWS, RIGHT_EDGE, h)).resize((middle_width, h - HEADER_ROWS), Image.Resampling.LANCZOS)
    out.paste(Image.new("RGBA", (body[2], body[3] - body[1])), (0, HEADER_ROWS))
    x = 0
    for part in (left, divider, middle, right):
        out.paste(part, (x, HEADER_ROWS))
        x += part.width
    assert x == w
    write_tga(TARGET, out, header)
    print("wrote", TARGET.name, out.size)


if __name__ == "__main__":
    main()
