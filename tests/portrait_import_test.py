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
character = {"region": "eu", "name": "Test", "surname": "Keeper", "avatar": {"url": url},
             "race": {"id": 5, "name": "Undead"}, "gender": {"enum": "MALE"},
             "stats": {"basic": {"primary": [{"enum": "HEALTH", "value": {"value": 1900}}]}}}
photo = io.BytesIO()
gradient = Image.linear_gradient("L").resize((84, 84)).convert("RGB")
gradient.save(photo, format="JPEG")


def fetch(address, _limit):
    if address == url:
        return photo.getvalue()
    assert address.endswith("/forever/eu/armory/character/test-keeper")
    return ("var characterProfileInitialState = " + json.dumps({"character": character})).encode()


plain = {"id": 8176, "name": "Headband", "armor": {"value": 91}, "stats": [{"value": 12}]}
assert portraits.game_item(plain, 3) == {"id": 8176, "name": "Headband", "ref": "item:8176"}
assert portraits.game_item(plain, 2) is plain  # legacy snapshots can omit context
variant = dict(plain, id=9890, context=1, bonus_list=[12733],
               enchantments=[{"enchantment_id": 8488, "enchantment_slot": {"id": 0}}])
assert portraits.game_item(variant, 3)["ref"] == "item:9890:8488::::::::::1:1:12733"
assert portraits.game_item(variant, 3)["stats"] == plain["stats"]
for extra in ({"enchantments": [{"enchantment_id": 8, "enchantment_slot": {"id": 8}}]},
              {"sockets": [{"item": {"id": 9}}]}, {"bonus_list": ["12733|h"]}, {"modifiers": [1]}):
    unknown = dict(plain, **extra)
    assert portraits.game_item(unknown, 3) is unknown


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
    native = folder / (guid + "-native.tga")
    native.write_bytes(before)
    portraits.sync(root, "eu", contacts)
    assert portraits.lua(guid) + ']="native"' in (folder / "Portraits.lua").read_text()
    assert native.read_bytes() == before

    for field, invalid in (("region", "us"), ("surname", "Other"), ("avatar", {"url": url.replace("42-avatar", "43-avatar")}),
                           ("avatar", {"url": "https://render.worldofwarcraft.com/raceicon.png"})):
        with patch.dict(character, {field: invalid}):
            portraits.sync(root, "eu", contacts, force=True)
        assert texture.read_bytes() == before
    assert requests.call_count == 4
    icon = "https://render.worldofwarcraft.com/forever-eu/icons/56/133761.jpg"
    character.update(pvp={"honorableKills":{"value":0}},
                     stats={"basic":{"primary":[{"enum":"HEALTH","value":{"value":1900}}]},
                            "groups":[{"stats":[{"enum":"MANA","value":{"value":1879}},
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
    assert result["stats"]=={"HEALTH":1900,"MANA":1879,"DAMAGE":[12,18]} and result["honorableKills"]==0 and result["pvpRank"] is None
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
    # The body must match this exact avatar. Crop the Armory's transparent padding and
    # keep the figure's aspect; a race fallback or another character must never be indexed.
    body_url = url.replace("-avatar.jpg", "-main-sd-raw.png")
    png = io.BytesIO()
    figure = Image.new("RGBA", (600, 400))
    figure.paste("green", (250, 60, 350, 360))
    figure.save(png, "PNG")
    character["media"] = {"main-sd-raw": {"url": body_url}}
    def full_response(address, limit):
        if address == body_url:
            return png.getvalue()
        if address == url:
            return photo.getvalue()
        state = {"character":character, "supportedArmoryTabs":["pvp", "reputation"]}
        if address.endswith("/pvp"):
            state["pvp"] = {"battlegrounds":[{"name":"Goulet", "games":3,"winCount":0,"lossCount":3}]}
        if address.endswith("/reputation"):
            state["reputations"] = {"reputations":[{"name":"Alliance", "reputations":[
                {"name":"Aube","standing":"Amical","value":0,"maxValue":6000}]}]}
        return ("var characterProfileInitialState = " + json.dumps(state)).encode()
    with patch.object(portraits,"fetch",side_effect=full_response):
        portraits.sync(root,"eu",contacts,force=True,locale="fr-fr")
    result = json.loads((folder/(guid+".json")).read_text())
    assert result["battlegrounds"] == [{"name":"Goulet","games":3,"wins":0,"losses":3}]
    assert result["reputations"] == [{"name":"Aube","group":"Alliance","standing":"Amical","value":0,"max":6000}]
    with Image.open(folder/(guid+"-body.tga")) as body:
        assert body.size==(256,512) and body.mode=="RGBA"
        x,y,right,bottom=body.getbbox()
        assert (right-x)*3==bottom-y and x>0 and y>0
    assert '["body"]=true' in (folder/"Profiles.lua").read_text("utf8")
    with patch.object(portraits,"fetch") as unexpected:
        assert portraits.body_texture(dict(character,media={"main-sd-raw":{"url":body_url.replace("/42/","/41/")}})) is None
        unexpected.assert_not_called()
    with patch.object(portraits,"armory_state",return_value={"character":character,"pvp":{"rank":{"value":0}}}):
        assert portraits.armory_section(character,"Test Keeper","pvp","fr-fr") is None
    with patch.object(portraits,"fetch",side_effect=full_response), patch.object(portraits,"armory_section",side_effect=ValueError("unavailable")):
        portraits.sync(root,"eu",contacts,force=True,profiles_only=True,locale="fr-fr")
    stale=json.loads((folder/(guid+".json")).read_text())
    assert stale["reputations"]==result["reputations"] and stale["reputationsAt"]==result["reputationsAt"]
    with patch.object(portraits, "portrait", side_effect=OSError("image service offline")), patch.object(portraits, "fetch", side_effect=full_response):
        texture.unlink()
        portraits.sync(root, "eu", contacts, force=True, locale="fr-fr")
        assert not texture.exists() and guid in (folder/"Profiles.lua").read_text("utf8")
        assert json.loads((folder/(guid+".json")).read_bytes())["gear"]["back"]["name"] == "Cape de test"
    save=root/"WTF/Account/example/SavedVariables/GrudgeLedger.lua"
    alias = "name:test keeper"
    with patch.object(portraits, "fetch", side_effect=full_response):
        assert portraits.sync(root, "eu", {alias: {"test keeper"}}, profiles_only=True) == 0
    named_file = folder / (portraits.media_stem("eu", alias) + ".json")
    # Older schema-3 name-only records have fresh gear but no model identity.
    legacy = json.loads(named_file.read_bytes())
    del legacy["identity"]["raceID"], legacy["identity"]["sex"]
    named_file.write_text(json.dumps(legacy), encoding="utf8")
    with patch.object(portraits, "fetch", side_effect=full_response):
        assert portraits.sync(root, "eu", {alias: {"test keeper"}}, profiles_only=True) == 0
    restored = json.loads(named_file.read_bytes())["identity"]
    assert (restored["raceID"],restored["sex"]) == (5,2)
    last_good = named_file.read_bytes()
    assert json.loads(last_good)["characterHex"] == "2a" and '"eu:name:test keeper"' in (folder/"Profiles.lua").read_text("utf8")
    with patch.dict(character, {"gear": {}}), patch.object(portraits, "fetch", side_effect=full_response):
        assert portraits.sync(root, "eu", {alias: {"test keeper"}}, force=True, profiles_only=True) == 1
    assert named_file.read_bytes() == last_good
    # A broken JSON must not remove the profile from the last usable catalog.
    named_file.write_bytes(b'{"gear":')
    with patch.object(portraits, "character_profile", side_effect=OSError("offline")):
        retries = {}
        assert portraits.sync(root, "eu", {alias: {"test keeper"}}, profiles_only=True, retry_after=retries) == 1
        assert alias in retries and '"eu:name:test keeper"' in (folder/"Profiles.lua").read_text("utf8")
    with patch.object(portraits, "fetch", side_effect=full_response):
        assert portraits.sync(root, "eu", {alias: {"test keeper"}}, profiles_only=True) == 0
    assert portraits.usable_identity(json.loads(named_file.read_bytes()))
    with patch.dict(character, {"avatar":{"url":url.replace("42-avatar", "43-avatar")}}):
        assert portraits.sync(root, "eu", {alias: {"test keeper"}}, force=True, profiles_only=True) == 1
    assert named_file.read_bytes() == last_good
    save.parent.mkdir(parents=True)
    # An unrelated broken historical file cannot stall repair of other contacts.
    original_catalog = (folder/"Profiles.lua").read_bytes()
    duplicate.write_text('{"identity":{},"gear":{},"updated":NaN}', encoding="utf8")
    with patch.object(portraits, "fetch", side_effect=full_response):
        character["gear"]["back"]["name"] = "Updated while an orphan is unreadable"
        assert portraits.sync(root,"eu",{alias: {"test keeper"}},force=True,profiles_only=True) == 0
    assert (folder/"Profiles.last-good.lua.bak").read_bytes() == original_catalog
    assert "Updated while an orphan is unreadable" in (folder/"Profiles.lua").read_text("utf8")
    stamp = int(portraits.time.time())
    save.write_text('["name:Test Keeper"] = "guid:'+guid+'",\n["name:chat visitor"] = "name:chat visitor",\n'
                    + f'["guid:Player-42-0000002C|Bounty Only"] = {stamp},\n'
                    + f'["name:wrong contact|Other Contact"] = {stamp},\n')
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
        assert [len(call.args[2]) for call in watcher.call_args_list]==[3,4]
        assert watcher.call_args_list[0].args[2]["name:chat visitor"] == {"chat visitor"}
        assert watcher.call_args_list[0].args[2]["Player-42-0000002C"] == {"Bounty Only"}
print("PASS verified portraits and body renders, cached gear, talents, PvP and reputation imports")
