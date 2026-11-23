"""Export the reference PNG kit without changing the legacy journal textures.

Usage: python tools/import_reference_journal.py PATH_TO_PNG_KIT
       python tools/import_reference_journal.py --check

The book keeps its full 1448 x 1086 canvas. Isolated pieces use their visible
alpha bounds; related states share a crop. TGA storage is stretched to powers
of two: display at the manifest's aspect ratio, with full 0..1 texture UVs.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

from import_art import corners_clear, read_tga, write_tga

ROOT = Path(__file__).resolve().parent.parent
MASTERS = ROOT / "art" / "reference-journal"
MEDIA = ROOT / "GrudgeLedger" / "Media"
MANIFEST = MASTERS / "manifest.json"
ASSETS = {
    "Livre": ("JournalReferenceBook", (2048, 2048)),
    "Onglet": ("JournalReferenceTab", (512, 128)),
    "Onglet-actif": ("JournalReferenceTabActive", (512, 128)),
    "BoutonParchemin": ("JournalReferenceButton", (512, 128)),
    "BoutonRouge": ("JournalReferenceButtonRed", (512, 128)),
    "BoutonRouge-enfonce": ("JournalReferenceButtonPressed", (512, 128)),
    "BoutonCuir": ("JournalReferenceDarkButton", (512, 128)),
    "BoutonCarre": ("JournalReferenceSquare", (128, 128)),
    "FlecheGauche": ("JournalReferenceArrowLeft", (128, 128)),
    "FlecheDroite": ("JournalReferenceArrowRight", (128, 128)),
    "FlecheCuirGauche": ("JournalReferenceDarkArrowLeft", (128, 128)),
    "FlecheCuirDroite": ("JournalReferenceDarkArrowRight", (128, 128)),
    "CadrePortrait": ("JournalReferencePortrait", (256, 256)),
    "CadreChiffres": ("JournalReferenceStats", (512, 128)),
    "LigneChoisie": ("JournalReferenceSelected", (512, 128)),
    "Champ": ("JournalReferenceField", (512, 128)),
    "Separateur": ("JournalReferenceRule", (1024, 32)),
    "SignetAmis": ("JournalBookmarkFriend", (128, 512)),
    "SignetAmis-choisi": ("JournalBookmarkFriendActive", (128, 512)),
    "SignetRancunes": ("JournalBookmarkDebt", (128, 512)),
    "SignetRancunes-choisi": ("JournalBookmarkDebtActive", (128, 512)),
    "EmblemeHorde": ("JournalReferenceHorde", (256, 256)),
    "EmblemeAlliance": ("JournalReferenceAlliance", (256, 256)),
    "DrapeHorde": ("JournalReferenceDrapeHorde", (1024, 512)),
    "DrapeAlliance": ("JournalReferenceDrapeAlliance", (1024, 512)),
    "Oeil": ("JournalReferenceEye", (256, 128)),
    "CoeurBrise": ("JournalReferenceHeart", (256, 256)),
}
STATE_GROUPS = (
    ("Onglet", "Onglet-actif"),
    ("BoutonParchemin", "BoutonRouge"),
    ("FlecheGauche", "FlecheDroite", "FlecheCuirGauche", "FlecheCuirDroite"),
    ("SignetAmis", "SignetAmis-choisi"),
    ("SignetRancunes", "SignetRancunes-choisi"),
)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    assert set(manifest["assets"]) == set(ASSETS), "asset list changed"
    for name, (slot, size) in ASSETS.items():
        entry = manifest["assets"][name]
        master, target = MASTERS / (name + ".png"), MEDIA / (slot + ".tga")
        assert sha256(master) == entry["master_sha256"], f"master changed: {name}"
        assert sha256(target) == entry["tga_sha256"], f"export changed: {slot}"
        image = read_tga(target)
        assert image.size == size and all(n & (n - 1) == 0 for n in size), slot
        assert image.mode == "RGBA" and image.getchannel("A").getextrema()[0] == 0, slot
        assert image.getchannel("A").getextrema()[1] >= 240 and corners_clear(image), slot
        if name == "CadrePortrait":
            assert image.getchannel("A").getpixel((size[0] // 2, size[1] // 2)) == 0, "portrait opening filled"
    assert manifest["assets"]["Livre"]["crop"] == [0, 0, 1448, 1086], "book canvas was cropped"
    for group in STATE_GROUPS:
        assert len({tuple(manifest["assets"][name]["crop"]) for name in group}) == 1, "state crops differ"
    print(f"Verified {len(ASSETS)} PNG masters and uncompressed RGBA TGA exports.")


def export(source):
    images, boxes = {}, {}
    for name in ASSETS:
        path = source / (name + ".png")
        with Image.open(path) as image:
            if image.format != "PNG" or image.mode != "RGBA":
                raise ValueError(f"Expected a real RGBA PNG: {path.name}")
            image.load()
            images[name] = image.copy()
        visible = images[name].getchannel("A").point(lambda alpha: 255 if alpha > 24 else 0).getbbox()
        if visible is None:
            raise ValueError(f"Empty image: {path.name}")
        # ponytail: two source pixels keep edge antialiasing; generated alpha noise below 25 is ignored for bounds only.
        boxes[name] = (max(0, visible[0] - 2), max(0, visible[1] - 2),
                       min(images[name].width, visible[2] + 2), min(images[name].height, visible[3] + 2))
        master = MASTERS / path.name
        if master.resolve() != path.resolve() and master.exists() and sha256(master) != sha256(path):
            raise ValueError(f"Archive the previous master before replacing {master.name}")
    if images["Livre"].size != (1448, 1086):
        raise ValueError("Livre.png must retain the approved 1448 x 1086 coordinate system")
    boxes["Livre"] = (0, 0, 1448, 1086)
    for group in STATE_GROUPS:
        if len({images[name].size for name in group}) != 1:
            raise ValueError(f"State canvases differ: {group}")
        union = (min(boxes[n][0] for n in group), min(boxes[n][1] for n in group),
                 max(boxes[n][2] for n in group), max(boxes[n][3] for n in group))
        for name in group:
            boxes[name] = union
    MASTERS.mkdir(parents=True, exist_ok=True)
    MEDIA.mkdir(parents=True, exist_ok=True)
    entries = {}
    for name, (slot, size) in ASSETS.items():
        master, target = MASTERS / (name + ".png"), MEDIA / (slot + ".tga")
        if master.resolve() != (source / master.name).resolve():
            master.write_bytes((source / master.name).read_bytes())
        crop = boxes[name]
        result = images[name].crop(crop).resize(size, Image.Resampling.LANCZOS)
        write_tga(target, result)
        entries[name] = {
            "source": master.name,
            "master": "art/reference-journal/" + master.name,
            "master_sha256": sha256(master),
            "source_size": images[name].size,
            "crop": crop,
            "display_aspect_ratio": (crop[2] - crop[0]) / (crop[3] - crop[1]),
            "texture": "GrudgeLedger/Media/" + target.name,
            "texture_size": size,
            "uv": [0, 1, 0, 1],
            "tga_sha256": sha256(target),
        }
    MANIFEST.write_text(json.dumps({"schema": 1, "provenance": "Original PNG kit generated with OpenAI image_gen from the approved reference",
                                    "book_display_size": [960, 720], "assets": entries}, indent=2) + "\n", encoding="utf-8")
    check()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        check()
    elif args.source:
        export(args.source)
    else:
        parser.error("provide the PNG kit directory or --check")
