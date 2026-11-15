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
    character.update(gear={"back":{"id":999999,"name":"New cloak","bonus_list":[14],
                                  "stats":[{"type":{"type":"AGILITY"},"value":5}]}}, specs=[])
    portraits.sync(root, "eu", contacts)
    folder = addon.parent / "GrudgeLedgerPortraits"
    texture = folder / (guid + ".tga")
    with Image.open(texture) as image:
        assert image.size == (64, 64) and image.mode == "RGB"
    before = texture.read_bytes()
    assert guid in (folder / "Portraits.lua").read_text()
    archive=(folder/"Profiles.lua").read_text()
    assert "999999" in archive and "AGILITY" in archive and "bonus_list" in archive
    other=guid.replace("2A","2B")
    duplicate=folder/(other+".json")
    duplicate.write_bytes((folder/(guid+".json")).read_bytes())
    portraits.publish_profiles(folder)
    assert (folder/"Profiles.lua").read_text().count("New cloak")==1
    second=json.loads(duplicate.read_bytes())
    second["gear"]["back"]["stats"][0]["value"]=9
    duplicate.write_text(json.dumps(second))
    portraits.publish_profiles(folder)
    assert (folder/"Profiles.lua").read_text().count("New cloak")==2
    requests.reset_mock()
    portraits.sync(root, "eu", contacts)
    assert requests.call_count == 0
    for field, invalid in (("region", "us"), ("surname", "Other"), ("avatar", {"url": url.replace("42-avatar", "43-avatar")}),
                           ("avatar", {"url": "https://render.worldofwarcraft.com/raceicon.png"})):
        with patch.dict(character, {field: invalid}):
            portraits.sync(root, "eu", contacts, force=True)
        assert texture.read_bytes() == before
    assert requests.call_count == 4
    icon = "https://render.worldofwarcraft.com/forever-eu/icons/56/133761.jpg"
    character.update(pvp={"honorableKills":{"value":0}},
                     stats={"groups":[{"stats":[{"enum":"MANA","value":{"value":1879}},
                            {"enum":"DAMAGE","value":{"type":"RANGE","min":{"value":12},"max":{"value":18}}}]}]},
                     specs=[{"name":"Feral","spentPoints":3,"talents":[{"id":11,"name":"Ferocity","rank":3,"icon":{"url":icon}}]}])
    character["gear"]["back"]["media"]={"content":{"assets":[{"key":"icon","value":icon}]}}
    category={"category":"player-vs-player","subcategories":{"ranks":{"achievements":[
        {"id":2,"name":"Earned rank","time":{"epoch":1},"accountWide":True,"icon":{"url":icon}},
        {"id":3,"name":"Locked rank"}]}}}
    with patch.object(portraits,"armory_state",side_effect=[{"character":character},
            {"character":character,"achievementCategory":category}]):
        portraits.sync(root,"eu",contacts,force=True,profiles_only=True,achievements=True)
    result=json.loads((folder/(guid+".json")).read_text())
    assert result["stats"]=={"MANA":1879,"DAMAGE":[12,18]} and result["honorableKills"]==0 and result["pvpRank"] is None
    assert result["gear"]["back"]["icon"]==result["trees"][0]["talents"][0][3]==133761
    assert [a["id"] for a in result["achievements"]]==[2] and result["achievements"][0]["accountWide"]
    with patch.object(portraits,"pvp_achievements",side_effect=ValueError("missing category")):
        portraits.sync(root,"eu",contacts,force=True,profiles_only=True,achievements=True)
    assert json.loads((folder/(guid+".json")).read_text())["achievementsAt"]==result["achievementsAt"]
    requests.reset_mock()
    character["gear"]["back"]["name"]="Cape de test"
    portraits.sync(root,"eu",contacts,locale="fr-fr",profiles_only=True)
    translated=json.loads((folder/(guid+".json")).read_text())
    assert requests.call_args.args[0].startswith("https://worldofwarcraft.blizzard.com/fr-fr/")
    assert translated["gear"]["back"]["name"]=="Cape de test" and translated["locale"]=="fr-fr"
    save=root/"WTF/Account/example/SavedVariables/GrudgeLedger.lua"
    save.parent.mkdir(parents=True)
    save.write_text('["name:Test Keeper"] = "guid:'+guid+'",\n')
    def polling_ticks():
        yield  # next pass: identical file, no second sync
        save.write_text(save.read_text()+'["name:Second Keeper"] = "guid:Player-42-0000002B",\n')
        yield
        raise KeyboardInterrupt
    ticks=polling_ticks()
    with patch.object(sys,"argv",["sync",str(root),"--region","eu","--watch"]), patch.object(portraits,"sync") as watcher, patch.object(portraits.time,"sleep",side_effect=lambda _:next(ticks)):
        try:
            portraits.main()
        except KeyboardInterrupt:
            pass
        assert [len(call.args[2]) for call in watcher.call_args_list]==[1,2]
print("PASS exact offline GUID match, 64px TGA, cache reuse and preserving a good avatar on failure")
