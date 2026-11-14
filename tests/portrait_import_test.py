"""Run with Python and Pillow. Uses synthetic Armory responses and a temporary game folder."""
import io
import json
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import sync_portraits as portraits


guid = "Player-42-0000002A"
url = "https://render.worldofwarcraft.com/forever-eu/character/42/42-avatar.jpg"
character = {"region": "eu", "name": "Test", "surname": "Keeper", "avatar": {"url": url}}
photo = io.BytesIO()
Image.new("RGB", (84, 84), "#663311").save(photo, format="JPEG")


def fetch(address, _limit):
    if address == url:
        return photo.getvalue()
    assert address.endswith("/forever/eu/armory/character/test-keeper")
    return ("var characterProfileInitialState = " + json.dumps({"character": character})).encode()


with TemporaryDirectory() as tmp, patch.object(portraits, "fetch", side_effect=fetch) as requests:
    root = Path(tmp)
    addon = root / "Interface/AddOns/GrudgeLedger"
    addon.mkdir(parents=True)
    (addon / "GrudgeLedger.toc").touch()
    contacts = {guid: {"test keeper"}}
    portraits.sync(root, "eu", contacts)
    folder = addon.parent / "GrudgeLedgerPortraits"
    texture = folder / (guid + ".tga")
    with Image.open(texture) as image:
        assert image.size == (64, 64) and image.mode == "RGB"
    before = texture.read_bytes()
    assert guid in (folder / "Portraits.lua").read_text()
    requests.reset_mock()
    portraits.sync(root, "eu", contacts)
    assert requests.call_count == 0
    for field, invalid in (("region", "us"), ("surname", "Other"), ("avatar", {"url": url.replace("42-avatar", "43-avatar")}),
                           ("avatar", {"url": "https://render.worldofwarcraft.com/raceicon.png"})):
        with patch.dict(character, {field: invalid}):
            portraits.sync(root, "eu", contacts, force=True)
        assert texture.read_bytes() == before
    assert requests.call_count == 4
print("PASS exact offline GUID match, 64px TGA, cache reuse and preserving a good avatar on failure")
