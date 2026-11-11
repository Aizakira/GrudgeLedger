"""Run source and behavior checks with Lua 5.1, the WoW addon language version."""
from pathlib import Path
import sys

work = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(work / "test-runtime"))
from lupa.lua51 import LuaRuntime

addon = work / "GrudgeLedger"
for name, expected_width, expected_height, transparent in (
    ("LedgerIcon.tga", 256, 256, True), ("LedgerBook.tga", 256, 256, True),
    ("RelationFriend.tga", 128, 128, True), ("RelationWarning.tga", 128, 128, True), ("RelationEnemy.tga", 128, 128, True),
    ("JournalIllustration.tga", 512, 256, True), ("JournalPaper.tga", 512, 512, False),
    ("JournalBookSurface.tga", 1024, 1024, True),
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
        # The resampled book retains its generated alpha (up to 3/255 at corners).
        corner_limit = 3 if name == "JournalBookSurface.tga" else 0
        assert all(alpha[y * width + x] <= corner_limit for x in (0, width - 1) for y in (0, height - 1)), "artwork corners must be transparent"
    else:
        assert all(a == 255 for a in alpha), "reading parchment must remain opaque"
    assert any(alpha), "artwork must not be empty"
print("PASS artwork: eight uncompressed RGBA TGAs, correct dimensions, cutout alpha and opaque reading paper", flush=True)
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
