"""Turn a picture made outside the game (PNG from an image generator) into a texture the addon reads.

The game wants uncompressed 32-bit TGA files with power-of-two sizes; image generators give PNG
files of any size. This tool crops or pads the picture to the size of its slot, checks that the
corners are transparent when the slot needs it, writes the TGA and a preview on parchment.

    python -I tools/import_art.py slots
        lists every slot: the textures the addon already draws, and the new ones planned.
    python -I tools/import_art.py <picture.png> <slot> [--fit cover|contain] [--out DIR] [--install]
        writes <slot>.tga and <slot>-apercu.png in DIR (default: next to the picture).
        --install also replaces the file in GrudgeLedger/Media (existing slots only), after
        saving the old one next to the preview.

    python -I tools/import_art.py letters <Name> [--out DIR] A-G=<picture.png> H-N=<picture.png> ...
        cuts the letters of a hand-drawn alphabet out of pictures that each hold a few letters, well
        apart, in reading order, and stores them in Letters<Name>.tga (512 x 256, cells of 64, A to Z,
        eight a row). A picture can be imported again alone: its letters replace the old ones.

A slot that exists keeps the size of its file in Media, so nothing can be imported at a wrong size.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image

MEDIA = Path(__file__).resolve().parent.parent / "GrudgeLedger" / "Media"
PARCHMENT = (240, 222, 184)

# Pieces that do not exist yet in the addon: size, transparent corners, what it is for.
PLANNED = {
    "AlertWanted": (512, 128, True, "cadre de l'alerte dorée (cible mise à prix), centre vide"),
    "AlertGuildKiller": (512, 128, True, "cadre de l'alerte Tueur de guilde, médaillon à gauche, centre vide"),
    "AlertPlain": (512, 128, True, "cadre sobre des alertes ordinaires, centre vide"),
    "RecapCard": (1024, 1024, True, "cadre d'enluminure de la carte du Bilan, centre vide"),
    "BountyPoster": (512, 512, True, "affiche d'avis de recherche du contrat, centre vide"),
    "RuleSimple": (512, 32, True, "filet simple"),
    "RuleDouble": (512, 32, True, "filet double"),
    "RuleOrnate": (512, 32, True, "filet orné"),
    "IconSkull": (64, 64, True, "icône crâne, blanc ou gris clair"),
    "IconSword": (64, 64, True, "icône épée, blanc ou gris clair"),
    "IconCoin": (64, 64, True, "icône pièce, blanc ou gris clair"),
    "IconPurse": (64, 64, True, "icône bourse, blanc ou gris clair"),
    "IconQuill": (64, 64, True, "icône plume, blanc ou gris clair"),
    "IconSeal": (64, 64, True, "icône sceau, blanc ou gris clair"),
}
for number in range(1, 21):
    PLANNED["Crest%d" % number] = (128, 128, True, "blason de guilde %d, blanc ou gris clair, centre vide" % number)


def read_tga(path):
    data = path.read_bytes()
    assert data[2] == 2 and data[16] == 32, "%s: uncompressed 32-bit TGA expected" % path.name
    width, height = int.from_bytes(data[12:14], "little"), int.from_bytes(data[14:16], "little")
    start = 18 + data[0]
    image = Image.frombytes("RGBA", (width, height), data[start:start + width * height * 4], "raw", "BGRA")
    if not data[17] & 0x20:
        image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    return image


def write_tga(path, image):
    # Uncompressed true color, 32 bits, 8 alpha bits, rows from the top.
    width, height = image.size
    header = bytearray(18)
    header[2] = 2
    header[12:14] = width.to_bytes(2, "little")
    header[14:16] = height.to_bytes(2, "little")
    header[16] = 32
    header[17] = 0x28
    path.write_bytes(bytes(header) + image.tobytes("raw", "BGRA"))


def corners_clear(image, limit=3):
    width, height = image.size
    alpha = image.getchannel("A")
    return all(alpha.getpixel((x, y)) <= limit for x in (0, width - 1) for y in (0, height - 1))


def slot_of(name):
    """Size, whether corners must be transparent, description, and the Media file when it exists."""
    existing = MEDIA / (name + ".tga")
    if existing.exists():
        current = read_tga(existing)
        return current.size[0], current.size[1], corners_clear(current), "texture déjà dessinée par l'addon", existing
    if name in PLANNED:
        width, height, clear, about = PLANNED[name]
        return width, height, clear, about, None
    return None


def fit(image, width, height, mode):
    image = image.convert("RGBA")
    # A generator leaves empty margins around the piece: only what is drawn is kept.
    box = image.getchannel("A").getbbox()
    if box:
        image = image.crop(box)
    scale = (max if mode == "cover" else min)(width / image.width, height / image.height)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.paste(image, ((width - size[0]) // 2, (height - size[1]) // 2))
    return canvas


CELL, COLUMNS, SHEET = 64, 8, (512, 256)


def spans(flags, gap):
    """Runs of True in flags, merging runs separated by fewer than gap False values."""
    runs, start, last = [], None, None
    for index, on in enumerate(flags):
        if on:
            if start is None:
                start = index
            elif index - last > gap:
                runs.append((start, last + 1))
                start = index
            last = index
    if start is not None:
        runs.append((start, last + 1))
    return runs


def glyphs(image):
    """The boxes of the pieces drawn in a picture, in reading order: rows first, then columns."""
    alpha = image.convert("RGBA").getchannel("A").point(lambda value: 255 if value > 24 else 0)
    width, height = alpha.size
    data = alpha.load()
    rows = spans([any(data[x, y] for x in range(width)) for y in range(height)], max(2, height // 100))
    boxes = []
    for top, bottom in rows:
        if bottom - top < height // 30:
            continue
        columns = spans([any(data[x, y] for y in range(top, bottom)) for x in range(width)], max(2, width // 150))
        for left, right in columns:
            if right - left < width // 80:
                continue
            box = alpha.crop((left, top, right, bottom)).getbbox()
            boxes.append((left + box[0], top + box[1], left + box[2], top + box[3]))
    return boxes


def import_letters(name, specs, out):
    out.mkdir(parents=True, exist_ok=True)
    target = out / ("Letters%s.tga" % name)
    sheet = read_tga(target) if target.exists() else Image.new("RGBA", SHEET, (0, 0, 0, 0))
    problems = 0
    for spec in specs:
        letters, _, path = spec.partition("=")
        first, _, last = letters.upper().partition("-")
        last = last or first
        wanted = [chr(code) for code in range(ord(first), ord(last) + 1)]
        picture = Image.open(path).convert("RGBA")
        found = glyphs(picture)
        if len(found) != len(wanted):
            problems += 1
            print("ATTENTION %s : %d lettres attendues (%s à %s), %d formes trouvées. Rien n'est rangé pour cette image."
                  % (Path(path).name, len(wanted), first, last, len(found)))
            print("  Demandez des lettres plus espacées, sans ornement détaché, ou moins de lettres par image.")
            continue
        # One scale for the whole picture, set on the median height of its letters (capitals share
        # it, whatever the picture): letters keep their proportions, from one picture to the next too.
        heights = sorted(box[3] - box[1] for box in found)
        common = 44 / heights[len(heights) // 2]
        for letter, box in zip(wanted, found):
            glyph = picture.crop(box)
            scale = min(common, (CELL - 4) / glyph.width, (CELL - 4) / glyph.height)
            size = (max(1, round(glyph.width * scale)), max(1, round(glyph.height * scale)))
            glyph = glyph.resize(size, Image.Resampling.LANCZOS)
            index = ord(letter) - ord("A")
            cell = ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL)
            sheet.paste(Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)), cell)
            sheet.paste(glyph, (cell[0] + (CELL - size[0]) // 2, cell[1] + (CELL - size[1]) // 2))
        print("%s : %s à %s rangées" % (Path(path).name, first, last))
    write_tga(target, sheet)
    preview = Image.new("RGBA", SHEET, PARCHMENT + (255,))
    ink = Image.new("RGBA", SHEET, (58, 36, 19, 255))
    preview.paste(ink, (0, 0), sheet.getchannel("A"))
    preview.convert("RGB").save(out / ("Letters%s-apercu.png" % name))
    missing = [chr(ord("A") + i) for i in range(26)
               if not sheet.crop(((i % COLUMNS) * CELL, (i // COLUMNS) * CELL, (i % COLUMNS + 1) * CELL, (i // COLUMNS + 1) * CELL)).getbbox()]
    print("écrit : %s" % target)
    print("lettres manquantes : %s" % (" ".join(missing) if missing else "aucune"))
    return 1 if problems or missing else 0


def list_slots():
    print("Textures déjà dessinées par l'addon (remplaçables sans toucher au code) :")
    for path in sorted(MEDIA.glob("*.tga")):
        image = read_tga(path)
        print("  %-28s %4d x %-4d %s" % (path.stem, image.size[0], image.size[1],
                                      "coins transparents" if corners_clear(image) else "opaque"))
    print("Pièces nouvelles prévues (le code les lira une fois ajoutées) :")
    for name, (width, height, clear, about) in PLANNED.items():
        print("  %-28s %4d x %-4d %s" % (name, width, height, about))


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) >= 4 and sys.argv[1] == "letters":
        rest = sys.argv[3:]
        out = None
        if rest[0] == "--out":
            out, rest = Path(rest[1]), rest[2:]
        return import_letters(sys.argv[2], rest, out or Path(rest[0].partition("=")[2]).parent)
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("picture")
    parser.add_argument("slot", nargs="?")
    parser.add_argument("--fit", choices=("cover", "contain"), default="contain")
    parser.add_argument("--out")
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    if args.picture == "slots":
        list_slots()
        return 0
    slot = args.slot and slot_of(args.slot)
    if not slot:
        print("Emplacement inconnu : %s. Lancez « slots » pour la liste." % args.slot)
        return 2
    width, height, clear, about, existing = slot
    source = Path(args.picture)
    picture = Image.open(source)
    result = fit(picture, width, height, args.fit)
    problems = []
    if picture.mode not in ("RGBA", "LA") and clear:
        problems.append("l'image n'a pas de transparence : demandez un PNG à fond transparent")
    if clear and not corners_clear(result):
        problems.append("les coins ne sont pas transparents")
    if not clear and result.getchannel("A").getextrema()[0] < 255:
        problems.append("cette texture doit être opaque partout : essayez --fit cover")
    if picture.width < width or picture.height < height:
        problems.append("image plus petite que l'emplacement (%d x %d < %d x %d) : elle sera floue"
                        % (picture.width, picture.height, width, height))
    out = Path(args.out) if args.out else source.parent
    out.mkdir(parents=True, exist_ok=True)
    target = out / (args.slot + ".tga")
    write_tga(target, result)
    preview = Image.new("RGBA", (width, height), PARCHMENT + (255,))
    preview.alpha_composite(result)
    preview.convert("RGB").save(out / (args.slot + "-apercu.png"))
    print("%s : %d x %d, %s" % (args.slot, width, height, about))
    print("  écrit : %s" % target)
    for problem in problems:
        print("  ATTENTION : " + problem)
    if args.install:
        if not existing:
            print("  non installé : cette pièce est nouvelle, le code doit d'abord apprendre à la dessiner")
        elif problems:
            print("  non installé : corrigez d'abord les points ci-dessus")
        else:
            (out / (args.slot + "-ancien.tga")).write_bytes(existing.read_bytes())
            existing.write_bytes(target.read_bytes())
            print("  installé dans Media (l'ancien fichier est gardé : %s-ancien.tga)" % args.slot)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
