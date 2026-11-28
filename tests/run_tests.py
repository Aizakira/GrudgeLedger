"""Run source and behavior checks with Lua 5.1, the WoW addon language version."""
from pathlib import Path
from hashlib import sha256
import sys
import subprocess

work = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(work / "test-runtime"))
from lupa.lua51 import LuaRuntime

addon = work / "GrudgeLedger"
font_dir = addon / "Media" / "Fonts"
assert "SIL OPEN FONT LICENSE" in (font_dir / "OFL.txt").read_text(encoding="utf-8")
# Unmodified static fonts and their upstream OFL, pinned in CREDITS.txt.
for filename, digest in {
    "PTSerif-Regular.ttf": "a4951fade06ff8f09b7673aa81ffb65a8cd409e24d3289a6dc670bc4dda2557a",
    "PTSerif-Bold.ttf": "038ba7336bd7ea14f12ad155bed51a4345cac5153275d521dec3ba04021c526e",
    "PTSerif-Italic.ttf": "f57e95ff9dc85691a3b2e193f2028db36f6663939a46c0fc4f286d618b80b7ce",
    "OFL.txt": "ddf311c28ddf5a5ad9747649837346b67bed9d356789c3072bb27dbce49e514d",
    # The posters' display fonts (owner, 27/11), upstream google/fonts, with their OFL.
    "NewRocker-Regular.ttf": "28a499ce5b8bcf0652f8b2e25135183eaddf0c3c8c3e251259b075c71d1ef14c",
    "CinzelDecorative-Bold.ttf": "e854e68a388aa50d742a4415c1ae5c17a617ef7956c95a70021d0a4a44f20518",
    "GermaniaOne-Regular.ttf": "3ee3d56584bab8c9e3f59cc3360aa8a36e219dcf0a9f3c8928e3da5a19277e3f",
    "OFL-GermaniaOne.txt": "b7574cd4c76770e5e3915d16bd93f09663bd77cb041a4ec09d824c52b540529a",
    "Skranji-Bold.ttf": "cfe2e3847d4c4d63efb207533539933b1acaaa7ea71e8df86758c01b7de6e9ab",
    "OFL-Skranji.txt": "ea3a629259e2df37adeb16ff728e28cc7d669fb341edde948af89dbdb64e7caa",
    "OFL-NewRocker.txt": "3b9f1bbe33dc7c6f93cf5e010b3de066efb635c0c7f34281790e7c9f61207b43",
    "OFL-CinzelDecorative.txt": "1e5d6660366ddcfca4f2fc10e2acfba9fa4d97d40aec80d7dbfd41d730a420ae",
}.items():
    assert sha256((font_dir / filename).read_bytes()).hexdigest() == digest, filename
# Owner report (0.29.0): "→" showed as an empty box in game, the bundled font has no such glyph.
# Every non-ASCII character written in the addon must exist in the three bundled faces.
# Exceptions: combining accents (search normalisation, never drawn) and the native menu's check mark.
from PIL import ImageFont
faces = [ImageFont.truetype(str(font_dir / name), 32) for name in ("PTSerif-Regular.ttf", "PTSerif-Bold.ttf", "PTSerif-Italic.ttf")]
def has_glyph(face, char):
    drawn, blank = face.getmask(char), face.getmask("￿")
    return not (drawn.size == blank.size and bytes(drawn) == bytes(blank))
for source in sorted(addon.glob("*.lua")):
    for char in sorted(set(source.read_text(encoding="utf-8-sig"))):
        if ord(char) > 127 and not 0x300 <= ord(char) <= 0x36F and char != "✓":
            assert all(has_glyph(face, char) for face in faces), f"{source.name}: {char!r} is not in the bundled font"
print("PASS glyphs: every character written by the addon exists in the bundled font", flush=True)
for name, expected_width, expected_height, transparent in (
    ("LedgerBook.tga", 256, 256, True),
    ("JournalMedallion.tga", 128, 128, True), ("JournalSettings.tga", 64, 64, True),
    ("JournalClose.tga", 64, 64, True),
    ("JournalTags.tga", 256, 128, True),
    ("JournalDialog.tga", 512, 512, True),
    ("JournalTitlePlate.tga", 512, 64, True),
    ("JournalWordmark.tga", 512, 128, True),
    ("RelationFriend.tga", 128, 128, True), ("RelationWarning.tga", 128, 128, True), ("RelationEnemy.tga", 128, 128, True),
    ("RelationNeutral.tga", 128, 128, True),
    ("JournalPaper.tga", 512, 512, False),
    ("JournalBookSurface.tga", 1024, 1024, True),
    ("JournalBookSurfaceSheet.tga", 1024, 1024, True),
    ("JournalButtons.tga", 512, 512, True),
    ("GestureKiss.tga", 128, 128, False),
    ("MapFeather.tga", 64, 64, True),
    ("PreyReticle.tga", 64, 64, True),
    ("BalanceGlow.tga", 256, 128, True), ("BalanceStarRuby.tga", 64, 64, True), ("BalanceStarGold.tga", 64, 64, True),
    # The map page's kit (owner, 25/11): the frame of the map and the six icons of the Relations entries.
    ("RelationsCarte/cadre-hg.tga", 128, 128, True), ("RelationsCarte/cadre-hd.tga", 128, 128, True),
    ("RelationsCarte/cadre-bg.tga", 128, 128, True), ("RelationsCarte/cadre-bd.tga", 128, 128, True),
    ("RelationsCarte/cadre-haut.tga", 512, 32, True), ("RelationsCarte/cadre-bas.tga", 512, 32, True),
    ("RelationsCarte/cadre-gauche.tga", 32, 256, True), ("RelationsCarte/cadre-droite.tga", 32, 256, True),
    ("RelationsCarte/separateur-carte.tga", 512, 32, True), ("Rivalites/bande-rivalite.tga", 1024, 128, True),
    ("Rivalites/RivalSheet.tga", 1024, 256, True), ("Rivalites/RivalDuel.tga", 1024, 128, True),
    ("Rivalites/RivalDeath.tga", 64, 64, True), ("Rivalites/RivalVictory.tga", 64, 64, True),
    ("RelationsCarte/bilan.tga", 64, 64, True),
    ("RelationsCarte/tableaux-detailles.tga", 64, 64, True), ("RelationsCarte/dettes.tga", 64, 64, True),
    ("RelationsCarte/rivalites.tga", 64, 64, True), ("RelationsCarte/carte.tga", 64, 64, True),
    ("RelationsCarte/classements.tga", 64, 64, True),
    # The guilds' armorial (owner's kit, 26/11): fifteen crests, their motifs, six alphabets.
    *((f"Crest{i}.tga", 128, 128, True) for i in range(1, 16)),
    ("GuildCrestFields.tga", 512, 1024, True),
    # The guild's journal as a register (owner's kit, 26/11).
    ("JournalGuilde/EnteteGravee.tga", 1024, 128, True), ("JournalGuilde/FleuronGauche.tga", 256, 32, True),
    ("JournalGuilde/FleuronDroit.tga", 256, 32, True), ("JournalGuilde/Fanion.tga", 32, 64, True),
    ("JournalGuilde/Victoire.tga", 64, 64, True), ("JournalGuilde/Mort.tga", 64, 64, True),
    *((f"Letters{name}.tga", 512, 256, True) for name in ("Hurlevent", "Chanteguerre", "Kaldorei", "Gnomeregan", "Karazhan", "Amani")),
    # The guild's enemies as wanted posters (owner's kit, 27/11; tools/import_wanted_kit.py).
    ("AvisRecherche/ToileAlliance.tga", 1024, 512, False), ("AvisRecherche/ToileHorde.tga", 1024, 512, False),
    *((f"AvisRecherche/{name}.tga", w, h, True) for name, w, h in (
        *((f"Coin{faction}{corner}", 128, 128) for faction in ("Alliance", "Horde") for corner in ("HG", "HD", "BG", "BD")),
        *((f"Bord{faction}{edge}", 64, 64) for faction in ("Alliance", "Horde") for edge in ("Haut", "Bas", "Gauche", "Droite")),
        ("FanionAlliance", 128, 128), ("CadreCoinBD", 128, 128), ("FanionHorde", 128, 256), ("EmblemeAlliance", 128, 128), ("EmblemeHorde", 128, 128),
        ("FiligraneAlliance", 128, 128), ("FiligraneHorde", 128, 128),
        ("EcussonAlliance", 256, 256), ("ChampAlliance", 256, 32), ("RangAlliance", 128, 128), ("BandeauAlliance", 256, 64),
        ("SeparateurAlliance", 512, 32), ("Triangle", 32, 32),
        *((f"{paper}{format}{tilt}", 256, 512 if format == "Grande" else 256)
          for paper in ("Affiche", "Prime") for format in ("Grande", "Carree") for tilt in (1, 2)),
        # The tribal papers (v9, v10; owner, 28/11): the Horde's posters.
        *((f"Affiche{name}", 256, 512) for name in ("OrcChef", "OrcGuerre", "TrollMarais", "GnollMarais", "GnollRavins", "OgreChef")),
        # The v8 collection (owner, 27/11): ten families, tall and small, plain and gold.
        *((f"{paper}{family}{format}", 256, 512 if format == "Grande" else 256) for paper in ("Affiche", "Prime")
          for family in ("Humain", "ElfeNuit", "ElfeSang", "Aerien", "Roublard", "Demoniste", "Troll", "Orc", "Tauren", "MortVivant")
          for format in ("Grande", "Carree")),
        ("CadrePortrait", 128, 128), ("Medaillon", 128, 128), ("MedaillonUn", 128, 128), ("Chevron", 32, 16),
        ("Bandeau", 256, 64), ("SceauPrime", 64, 64),
        ("Tampon", 256, 64), ("Cartouche", 256, 32), ("SeparateurEncre", 256, 16), ("SeparateurOr", 256, 16),
        ("IconeMembres", 64, 64), ("IconeCrane", 64, 64), ("IconeLieu", 64, 64), ("ClouFace", 64, 64), ("ClouGauche", 64, 64), ("ClouDroite", 64, 64))),
):
    texture = (addon / "Media" / name).read_bytes()
    width = int.from_bytes(texture[12:14], "little")
    height = int.from_bytes(texture[14:16], "little")
    assert texture[1:3] == bytes((0, 2)) and texture[16] == 32 and texture[17] & 15 == 8, "uncompressed RGBA TGA required"
    assert (width, height) == (expected_width, expected_height), "game texture must have the expected power-of-two dimensions"
    pixels = 18 + texture[0]
    assert len(texture) >= pixels + width * height * 4
    alpha = texture[pixels + 3:pixels + width * height * 4:4]
    if transparent:
        # Resampling preserves generated alpha; allow an imperceptible 3/255 fringe.
        corner_limit = 3 if name in ("JournalBookSurface.tga", "JournalBookSurfaceSheet.tga", "JournalButtons.tga", "JournalDialog.tga") else 0
        assert all(alpha[y * width + x] <= corner_limit for x in (0, width - 1) for y in (0, height - 1)), name + ": artwork corners must be transparent"
    else:
        assert all(a == 255 for a in alpha), "opaque artwork must remain opaque"
    assert any(alpha), "artwork must not be empty"
print("PASS artwork: uncompressed RGBA TGAs, correct dimensions, cutout alpha and opaque artwork", flush=True)
# The Journal's PNG masters stay on the owner's machine (generated work files, not published): their
# check runs where they are; the shipped TGAs are checked above everywhere.
if (work / "art" / "reference-journal" / "manifest.json").exists():
    subprocess.run([sys.executable, str(work / "tools" / "import_reference_journal.py"), "--check"], check=True)
else:
    print("SKIP reference journal masters: not in this checkout", flush=True)
mask = (addon / "Media" / "RadarBlank.tga").read_bytes()
assert mask[:3] == bytes((0, 0, 2)) and mask[12:18] == bytes((8, 0, 8, 0, 32, 8))
assert len(mask) == 18 + 8 * 8 * 4 and not any(mask[18:]), "radar mask must be fully transparent"
compiler = LuaRuntime(unpack_returned_tuples=True)
files = list(addon.glob("*.lua"))
for file in files:
    compiler.compile(file.read_text(encoding="utf-8-sig"), name=str(file))
print(f"PASS Lua 5.1 syntax: {len(files)} files", flush=True)
selected = sys.argv[1:]
tests = [work / "tests" / name for name in selected] if selected else sorted((work / "tests").glob("*_test.lua"))
for test in tests:
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.globals().TEST_ROOT = addon.as_posix()
    runtime.globals().TEST_WORK = work.as_posix()
    runtime.globals().print = lambda *args: print(*args, flush=True)
    runtime.execute(test.read_text(encoding="utf-8-sig"), name=str(test))
print(f"PASS {len(tests)} test scripts", flush=True)
