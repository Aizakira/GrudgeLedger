"""Import verified Forever Armory character sheets and portraits into a private local addon."""
import argparse
import gzip
import hashlib
import io
import json
import math
import os
import re
import tempfile
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

from PIL import Image, UnidentifiedImageError


GUID = r"Player-[0-9]{1,10}-[0-9A-Fa-f]{1,16}"
ALIAS = re.compile(r'^\s*\["name:([^"\\|\x00-\x1f]{1,160})"\]\s*=\s*"guid:(' + GUID + r')",?\s*$', re.M)
NAME_ONLY = re.compile(r'^\s*\["(name:([^"\\|\x00-\x1f]{1,160}))"\]\s*=\s*"\1",?\s*$', re.M)
REQUEST = re.compile(r'^\s*\["(guid:' + GUID + r'|name:[^"\\|\x00-\x1f]{1,160})\|([^"\\|\x00-\x1f]{1,160})"\]\s*=\s*(\d{1,12}),?\s*$', re.M)
NAME_STEM = r"Name-[0-9a-f]{64}"
PROFILE = re.compile(r"\bvar\s+characterProfileInitialState\s*=\s*")
TOC = b"## Interface: 16001\n## Title: Grudge Ledger - Private portraits\nPortraits.lua\n"


def fetch(url, limit):
    request = Request(url, headers={"User-Agent": "GrudgeLedger/armory-import", "Accept-Encoding": "gzip"})
    with urlopen(request, timeout=12) as response:
        if urlsplit(response.geturl()).netloc != urlsplit(url).netloc:
            raise ValueError("unexpected redirect")
        data = response.read(limit + 1)
        if response.headers.get("Content-Encoding", "").lower() == "gzip" and len(data) <= limit:
            with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
                data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError("oversized response")
    return data


def armory_state(region, name, suffix="", locale="en-us"):
    if locale not in ("en-us", "fr-fr", "es-es"):
        raise ValueError("unsupported Armory language")
    slug = "-".join(name.casefold().split())
    html = fetch(f"https://worldofwarcraft.blizzard.com/{locale}/forever/{region}/armory/character/{quote(slug, safe='')}{suffix}", 4_000_000).decode()
    start = PROFILE.search(html)
    model = re.search(r'<script id="model">\s*model\s*=\s*', html)
    if model:
        mounts = json.JSONDecoder().raw_decode(html[model.end():].lstrip())[0]["reactMounts"]
        return next((m["initialState"] for m in mounts if m.get("id") == "character-profile-mount"), {})
    if start:
        return json.JSONDecoder().raw_decode(html[start.end():].lstrip())[0]
    raise ValueError("no Armory profile")


def character_profile(region, name, guid, locale="en-us"):
    if (guid is not None and not re.fullmatch(GUID, guid)) or region not in ("eu", "us", "kr", "tw"):
        raise ValueError("invalid character or region")
    state = armory_state(region, name, locale=locale)
    data = state["character"]

    if data["region"] != region or (data["name"] + " " + data["surname"]).casefold() != name.casefold():
        raise ValueError("character name or region mismatch")
    media = data["avatar"]["url"]
    avatar = re.fullmatch(rf"https://render\.worldofwarcraft\.com/forever-{region}/character/[0-9]+/([1-9][0-9]{{0,19}})-avatar\.jpg", media)
    if not avatar or (guid and int(avatar[1]) != int(guid.rsplit("-", 1)[1], 16)):
        raise ValueError("no individual avatar matching the saved character ID")
    return dict(data, characterHex=format(int(avatar[1]), "x"), supportedArmoryTabs=state.get("supportedArmoryTabs", []))


def portrait(data):
    media = data["avatar"]["url"]
    with Image.open(io.BytesIO(fetch(media, 512_000))) as img:
        if img.format != "JPEG" or img.width != img.height or not 32 <= img.width <= 512:
            raise ValueError("unexpected avatar format")
        buf = io.BytesIO()
        img.convert("RGB").resize((64, 64), Image.Resampling.LANCZOS).save(buf, format="TGA")
        return buf.getvalue()


def body_texture(character):
    # The Armory puts the whole figure in the middle of a mostly transparent landscape canvas.
    # Its race and class fallback images also look plausible, so require the verified avatar's ID.
    prefix = character["avatar"]["url"].removesuffix("-avatar.jpg")
    for kind in ("main-sd-raw", "main-raw"):
        url = character.get("media", {}).get(kind, {}).get("url")
        if url != f"{prefix}-{kind}.png":
            continue
        with Image.open(io.BytesIO(fetch(url, 4_000_000))) as img:
            if img.format != "PNG" or not (32 <= img.width <= 4096 and 32 <= img.height <= 4096):
                raise ValueError("unexpected character render format")
            if "A" not in img.getbands() and "transparency" not in img.info:
                raise ValueError("character render has no transparent background")
            image = img.convert("RGBA")
            bounds = image.getchannel("A").getbbox()
            if not bounds:
                raise ValueError("empty character render")
            figure = image.crop(bounds)
            figure.thumbnail((252, 508), Image.Resampling.LANCZOS)
            canvas = Image.new("RGBA", (256, 512))
            canvas.paste(figure, ((256 - figure.width) // 2, (512 - figure.height) // 2))
            result = io.BytesIO()
            canvas.save(result, format="TGA")
            return result.getvalue()


def armory_section(character, name, section, locale):
    state = armory_state(character["region"], name, "/" + section, locale)
    if state["character"]["avatar"]["url"] != character["avatar"]["url"]:
        raise ValueError("section belongs to a different character")
    if section == "pvp":
        if "battlegrounds" not in state["pvp"]:
            return None
        return [{"name": bg["name"], "games": bg.get("games"), "wins": bg.get("winCount"),
                 "losses": bg.get("lossCount")} for bg in state["pvp"]["battlegrounds"]]

    def factions(rows, group=None):
        for row in rows:
            if "reputations" in row:
                yield from factions(row["reputations"], row.get("name"))
            else:
                yield {"name": row["name"], "standing": row.get("standing"), "value": row.get("value"),
                       "max": row.get("maxValue"), "group": group}
    return list(factions(state["reputations"]["reputations"]))


def write_atomic(path, data):
    if path.is_file() and path.read_bytes() == data:
        return
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            tmp = Path(stream.name)
            stream.write(data)
        os.replace(tmp, path)
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)


def icon_id(url):
    match = re.fullmatch(r"https://render\.worldofwarcraft\.com/forever-(?:eu|us|kr|tw)/icons/\d+/(\d+)\.jpg", url or "")
    if match:
        return int(match[1])


def pvp_achievements(character, name, locale="en-us"):
    state = armory_state(character["region"], name, "/achievements/player-vs-player", locale)
    category = state["achievementCategory"]
    if state["character"]["avatar"]["url"] != character["avatar"]["url"] or category["category"] != "player-vs-player":
        raise ValueError("unexpected achievement profile")

    def earned(group):
        for a in group.get("achievements", []):
            if a.get("time"):
                yield {"id": a["id"], "name": a["name"], "accountWide": a.get("accountWide"),
                       "icon": icon_id(a.get("icon", {}).get("url"))}
        for child in group.get("subcategories", {}).values():
            yield from earned(child)

    return list(earned(category))


def compact(data):
    def details(node):
        if isinstance(node, list):
            return [details(v) for v in node]
        if isinstance(node, dict):
            return {k: details(v) for k, v in node.items() if k not in
                    {"key", "media", "icon", "color", "display_color", "_links", "href"}}
        return node

    gear = {}
    for slot, item in data.get("gear", {}).items():
        gear[slot] = details({k: item[k] for k in ("id", "name", "quality", "level", "armor", "weapon", "context",
            "modifiers", "random_suffix", "random_property",
            "stats", "bonus_list", "enchantments", "sockets", "spells", "set", "requirements") if k in item})
        assets = item.get("media", {}).get("content", {}).get("assets", [])
        texture = next((icon_id(a.get("value")) for a in assets if a.get("key") == "icon"), None)
        if texture:
            gear[slot]["icon"] = texture
    stats = {}
    stat_block = data.get("stats", {})
    basic = stat_block.get("basic", {})
    sections = [basic.get("primary", []), basic.get("secondary", [])]
    sections.extend(group.get("stats", []) for group in stat_block.get("groups", []))
    for section in sections:
        for stat in section:
            value = stat.get("value", {})
            if isinstance(value.get("value"), (int, float)):
                stats[stat["enum"]] = value["value"]
            elif value.get("type") == "RANGE":
                stats[stat["enum"]] = [value[k]["value"] for k in ("min", "max")]
    pvp = data.get("pvp", {})
    # Identity also serves contacts known only through a guild contract.
    identity = {key: data[key]["name"] for key in ("race", "class", "faction", "guild")
                if isinstance(data.get(key), dict) and isinstance(data[key].get("name"), str)}
    identity["name"] = " ".join(n for n in (data.get("name"), data.get("surname")) if isinstance(n, str) and n)
    identity["raceID"] = data.get("race", {}).get("id")
    gender = data.get("gender", {}).get("enum")
    if gender in ("MALE", "FEMALE"):
        identity["sex"] = 2 if gender == "MALE" else 3
    identity["classFile"] = data.get("class", {}).get("enum")
    return {"armorySchema": 3, "identity": identity, "stats": stats, "honorableKills": pvp.get("honorableKills", {}).get("value"),
            "pvpRank": pvp.get("rank", {}).get("value"),
            "gear": gear, "updated": data.get("lastUpdatedTimestamp", {}).get("epoch"),
            "level": data.get("level"), "averageItemLevel": data.get("averageItemLevel"),
            "trees": [{"name": t["name"], "id": t.get("id"), "points": t["spentPoints"], "talents":
                      [[v["id"], v["name"], v["rank"], icon_id(v.get("icon", {}).get("url")), v.get("description")]
                       for v in t.get("talents", [])]}
                     for t in data.get("specs", [])]}


def lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return str(v).lower()
    if isinstance(v, (float, int)):
        return json.dumps(v, allow_nan=False)
    if isinstance(v, str):
        return '"' + re.sub(r'[\x00-\x1f\x7f"\\]', lambda m: chr(92) + ("%03d" % ord(m[0])), v) + '"'
    if isinstance(v, list):
        return "{" + ",".join(map(lua, v)) + "}"
    return "{" + ",".join("[" + lua(k) + "]=" + lua(val) for k,val in sorted(v.items())) + "}"


def game_item(item, schema):
    """Export the Forever item payload. Keep the Armory fallback for unrepresentable effects."""
    def valid_id(value):
        return type(value) is int and 0 < value < 2**31

    item_id = item.get("id")
    bonuses = item.get("bonus_list", [])
    context = item.get("context", 0)
    if (schema != 3 or not valid_id(item_id) or not isinstance(bonuses, list) or len(bonuses) > 64
            or not all(map(valid_id, bonuses)) or type(context) is not int or not 0 <= context < 256
            or any(item.get(k) for k in ("modifiers", "random_suffix", "random_property", "sockets"))):
        return item
    enchantments = item.get("enchantments", [])
    enchant = ""
    if enchantments:
        if not isinstance(enchantments, list) or len(enchantments) != 1 or not isinstance(enchantments[0], dict):
            return item
        effect = enchantments[0]
        slot = effect.get("enchantment_slot")
        if not isinstance(slot, dict) or slot.get("id") != 0 or not valid_id(effect.get("enchantment_id")):
            return item
        enchant = effect["enchantment_id"]
    fields = [item_id, enchant, "", "", "", "", "", "", "", "", "", context or "", len(bonuses) or "", *bonuses]
    ref = "item:" + ":".join(map(str, fields)).rstrip(":")
    if bonuses or enchant:
        return dict(item, ref=ref)
    return {**{k: item[k] for k in ("id", "name", "quality", "level", "icon") if k in item}, "ref": ref}


def media_stem(region, key):
    if re.fullmatch(GUID, key):
        return key
    if key.startswith("name:") and 0 < len(key[5:]) <= 160 and len(key[5:].split()) >= 2:
        return "Name-" + hashlib.sha256((region + ":" + key).encode()).hexdigest()
    raise ValueError("invalid journal contact")


def cached_profile(file):
    for path in (file, file.with_suffix(".json.bak")):
        try:
            profile = json.loads(path.read_bytes())
            if not isinstance(profile, dict) or not isinstance(profile.get("identity"), dict):
                continue
            json.dumps(profile, allow_nan=False)
            if not isinstance(profile.get("gear"), dict) or not all(isinstance(item, dict) for item in profile["gear"].values()):
                continue
            times = (profile.get(k) for k in ("updated", "achievementsAt", "reputationsAt", "battlegroundsAt"))
            if any(v is not None and (type(v) not in (float, int) or not math.isfinite(v)) for v in times):
                continue
            if file.stem.startswith("Name-") and (media_stem(profile["region"], profile["alias"]) != file.stem
                    or not re.fullmatch(r"[0-9a-f]+", profile["characterHex"])):
                continue
            return profile, path
        except (OSError, ValueError, OverflowError, KeyError, TypeError, AttributeError):
            continue
    return {}, None


def usable_identity(profile):
    identity = profile.get("identity", {})
    return (type(identity.get("raceID")) is int and identity["raceID"] > 0
            and identity.get("sex") in (2, 3))


def valid_texture(path, size):
    try:
        with Image.open(path) as image:
            if image.format != "TGA" or image.size != size:
                return False
            image.load()
            return True
    except (OSError, ValueError):
        return False


def publish_profiles(folder):
    profiles, variants, indices = {}, [], {}
    manifest = folder / "Profiles.lua"
    recovery = folder / "Profiles.last-good.lua.bak"
    incomplete = False
    files = set(folder.glob("*.json")) | {f.with_suffix("") for f in folder.glob("*.json.bak")}
    for file in sorted(files):
        if not re.fullmatch(GUID + "|" + NAME_STEM, file.stem):
            continue
        profile, source = cached_profile(file)
        if source is None:
            incomplete = True
            print(f"Unreadable private profile {file.stem}; continuing with the other dossiers")
            continue
        key = file.stem
        if re.fullmatch(NAME_STEM, key):
            region, alias = profile["region"], profile["alias"]
            if media_stem(region, alias) != key:
                raise ValueError("incorrect name archive key")
            key = region + ":" + alias
        for field in ("avatarReceipt", "avatarKey", "avatarHex", "mediaKey", "body", "portrait"):
            profile.pop(field, None)
        for slot, item in profile["gear"].items():
            item = game_item(item, profile.get("armorySchema"))
            variant = lua(item)
            if variant not in indices:
                variants.append(item)
                indices[variant] = len(variants)
            profile["gear"][slot] = indices[variant]
        profiles[key] = profile
    if incomplete and manifest.is_file() and not recovery.exists():
        write_atomic(recovery, manifest.read_bytes())
    catalog = ("GrudgeLedgerArmory = " + lua({"profiles": profiles, "items": variants}) + "\n").encode()
    write_atomic(manifest, catalog)
    if not incomplete and recovery.exists():
        write_atomic(recovery, catalog)


def publish(folder):
    # Publish only complete textures. A later run can recover a fully written
    # portrait even if a previous import stopped before publishing the index.
    from native_portraits_windows import native_guids
    keys = dict.fromkeys(native_guids(folder), "native")
    index = "GrudgeLedgerPortraitIndex = " + lua(keys) + "\n"
    write_atomic(folder / "Portraits.lua", index.encode("ascii"))
    publish_profiles(folder)
    native_file = b"NativePortraits.lua\n" if (folder/"NativePortraits.lua").is_file() else b""
    write_atomic(folder / "GrudgeLedgerPortraits.toc", TOC + b"Profiles.lua\n" + native_file)
    return len(keys)


def sync(root, region, contacts, force=False, profiles_only=True, achievements=False, locale="en-us", retry_after=None,
         interrupted=None):
    addons = root / "Interface" / "AddOns"
    if not (addons / "GrudgeLedger" / "GrudgeLedger.toc").is_file():
        raise ValueError("Grudge Ledger is missing from the selected game folder")
    folder = addons / "GrudgeLedgerPortraits"
    folder.mkdir(exist_ok=True)
    updated = fresh = unavailable = 0
    stems = {key: media_stem(region, key) for key in contacts}
    # Players never fetched go first. The game only loads Profiles.lua, so it is rebuilt after each
    # player instead of once at the end of the round: with seventy contacts the round is long, and
    # the player who just killed you stayed invisible in game until it finished. A journal saved
    # meanwhile (a /reload) ends the round early so its new players are served at once.
    for guid, names in sorted(contacts.items(), key=lambda pair: (folder / (stems[pair[0]] + ".json")).is_file()):
        if interrupted and interrupted():
            break
        if not force and retry_after is not None and retry_after.get(guid, 0) > time.monotonic():
            unavailable += 1
            continue
        path = folder / (stems[guid] + ".tga")
        cache = path.with_suffix(".json")
        required = (cache,) if profiles_only else (cache, path)
        previous, source = cached_profile(cache)
        fresh_achievements = 0 <= time.time() - (previous.get("achievementsAt") or 0) < 7 * 86400
        same_locale = previous.get("locale", "en-us") == locale
        media_current = profiles_only or ("bodyAvailable" in previous and previous.get("bodyChecked") and valid_texture(path, (64, 64))
                         and (not previous.get("bodyAvailable") or valid_texture(folder / (stems[guid] + "-body.tga"), (256, 512))))
        has_data = usable_identity(previous) and previous.get("stats") and previous.get("gear")
        if not force and source == cache and has_data and same_locale and previous.get("armorySchema") == 3 and media_current and (not achievements or fresh_achievements) and all(
                f.is_file() and 0 <= time.time() - f.stat().st_mtime < 7 * 86400 for f in required):
            fresh += 1
            continue
        for name in sorted(names):
            try:
                named = guid.startswith("name:")
                if named and guid[5:].casefold() != name.casefold():
                    raise ValueError("journal alias mismatch")
                if named and source is None and (cache.exists() or cache.with_suffix(".json.bak").exists()):
                    raise ValueError("cannot verify the previous owner of the damaged name archive")
                character = character_profile(region, name, None if named else guid, locale)
                snapshot = compact(character)
                snapshot.update(region=region, characterHex=character["characterHex"])
                if named:
                    snapshot["alias"] = guid
                    if previous.get("characterHex", snapshot["characterHex"]) != snapshot["characterHex"]:
                        raise ValueError("the name now belongs to a different character")
                if (previous.get("updated") or 0) > (snapshot.get("updated") or 0):
                    raise ValueError("older Armory response")
                if (not any((snapshot["stats"], snapshot["gear"], snapshot["trees"]))
                        or any(previous.get(k) and not snapshot[k] for k in ("gear", "stats"))
                        or (previous.get("trees") and not snapshot["trees"])):
                    raise ValueError("incomplete Armory response")
                for field in ("honorableKills", "pvpRank", "level", "averageItemLevel"):
                    if snapshot[field] is None:
                        snapshot[field] = previous.get(field)
                snapshot["locale"] = locale
                snapshot["bodyChecked"] = previous.get("bodyChecked", False)
                snapshot["bodyAvailable"] = previous.get("bodyAvailable", False)
                if (not usable_identity(snapshot) and usable_identity(previous)
                        and snapshot["identity"].get("raceID") in (None, previous["identity"]["raceID"])
                        and snapshot["identity"].get("race")==previous["identity"].get("race")):
                    snapshot["identity"].setdefault("sex", previous["identity"]["sex"])
                    snapshot["identity"]["raceID"] = previous["identity"]["raceID"]
                for section, key in (("pvp", "battlegrounds"), ("reputation", "reputations")):
                    if same_locale and key in previous:
                        snapshot[key], snapshot[key+"At"] = previous[key], previous.get(key+"At")
                    recent_section = (not force and same_locale and key in snapshot and
                                      0 <= time.time() - (snapshot.get(key+"At") or 0) < 7 * 86400)
                    if section in character["supportedArmoryTabs"] and not recent_section:
                        try:
                            rows = armory_section(character, name, section, locale)
                            if rows is not None:
                                snapshot[key] = rows
                                snapshot[key+"At"] = int(time.time())
                        except (ValueError, KeyError, OSError) as exc:
                            print(f"{section} unavailable for {guid}: {ascii(str(exc))}")
                if same_locale and "achievements" in previous:
                    snapshot["achievements"] = previous["achievements"]
                    snapshot["achievementsAt"] = previous.get("achievementsAt")
                if achievements and (force or not same_locale or not fresh_achievements):
                    try:
                        snapshot["achievements"] = pvp_achievements(character, name, locale)
                        snapshot["achievementsAt"] = int(time.time())
                    except (ValueError, KeyError, URLError) as exc:
                        print(f"PvP achievements unavailable for {guid}: {ascii(str(exc))}")
                if not profiles_only:
                    try:
                        data = portrait(character)
                    except (ValueError, OSError) as exc:
                        data = None
                        if not path.is_file():
                            unavailable += 1
                        print(f"Portrait unavailable for {guid}: {ascii(str(exc))}")
                    try:
                        body = body_texture(character)
                        if body:
                            write_atomic(folder / (stems[guid] + "-body.tga"), body)
                            snapshot["bodyAvailable"] = True
                        snapshot["bodyChecked"] = True
                    except (ValueError, KeyError, OSError) as exc:
                        print(f"Character render unavailable for {guid}: {ascii(str(exc))}")
                profile = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()
            except HTTPError as exc:
                if exc.code == 404:
                    continue
                print(f"Armory HTTP {exc.code} for {guid}")
                continue
            except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
                print(f"Profile unavailable for {ascii(guid)}: {ascii(str(exc))}")
                continue
            backup = cache.with_suffix(".json.bak")
            if source == cache and previous != snapshot:
                write_atomic(backup, cache.read_bytes())
            elif not backup.exists():
                write_atomic(backup, profile)
            write_atomic(cache, profile)
            cache.touch()
            if not profiles_only and data is not None:
                write_atomic(path, data)
                path.touch()
            updated += 1
            try:
                publish(folder)
            except (OSError, ValueError) as exc:
                # The game or an antivirus may hold the file during a reload: the end of the round publishes again.
                print(f"Publication postponed: {ascii(str(exc))}", flush=True)
            if retry_after is not None:
                if (not usable_identity(snapshot) or not snapshot["gear"] or not snapshot["stats"]
                        or (achievements and not 0 <= time.time() - (snapshot.get("achievementsAt") or 0) < 7 * 86400)
                        or (not profiles_only and (data is None or not snapshot["bodyChecked"]))):
                    retry_after[guid] = time.monotonic() + 1800
                else:
                    retry_after.pop(guid, None)
            break
        else:
            unavailable += 1
            if retry_after is not None:
                retry_after[guid] = time.monotonic() + 1800
    portraits = publish(folder)
    print(f"{updated} updated, {fresh} recent, {unavailable} unavailable. {portraits} portraits in {folder}", flush=True)
    return unavailable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, help="the _forever_ directory")
    parser.add_argument("--region", choices=("eu", "us", "kr", "tw"), required=True)
    parser.add_argument("--locale", choices=("en-us", "fr-fr", "es-es"), default="en-us", help="language of equipment, enchantments and talents")
    parser.add_argument("--name", help="only synchronize this full character name")
    parser.add_argument("--force", action="store_true", help="refresh even within seven days")
    parser.add_argument("--profiles-only", action="store_true", default=True, help="import character data only (default)")
    parser.add_argument("--archive-web-images", dest="profiles_only", action="store_false",
                        help="archive website artwork for reference")
    parser.add_argument("--pvp-achievements", action="store_true", help="also fetch completed PvP achievements")
    parser.add_argument("--watch", action="store_true", help="watch locally saved journals; stop with Ctrl+C")
    parser.add_argument("--native-portraits", action="store_true", help="archive observed portrait tiles on Windows while watching")
    args = parser.parse_args()
    if not (args.game / "Interface/AddOns/GrudgeLedger/GrudgeLedger.toc").is_file():
        parser.error("select the _forever_ folder containing GrudgeLedger")
    if args.native_portraits:
        if os.name != "nt" or not args.watch:
            parser.error("--native-portraits requires --watch on Windows")
        from threading import Thread
        from native_portraits_windows import watch
        folder = args.game / "Interface/AddOns/GrudgeLedgerPortraits"
        folder.mkdir(exist_ok=True)
        Thread(target=watch,args=(args.game.resolve(), folder, write_atomic, lua),daemon=True).start()
    last, check_at, retry_after = None, 0, {}
    while True:
        try:
            saves = sorted((args.game / "WTF/Account").glob("*/SavedVariables/GrudgeLedger.lua"))
            revision = [(s, s.stat().st_mtime_ns, s.stat().st_size) for s in saves]
            if revision != last or time.monotonic() >= check_at:
                contacts = {}
                for save in saves:
                    saved = save.read_text(encoding="utf-8-sig")
                    for name, guid in ALIAS.findall(saved):
                        if not args.name or name.casefold() == args.name.casefold():
                            contacts.setdefault(guid, set()).add(name)
                    for alias, name in NAME_ONLY.findall(saved):
                        if len(name.split()) >= 2 and (not args.name or name.casefold() == args.name.casefold()):
                            contacts.setdefault(alias, set()).add(name)
                    for key, name, timestamp in REQUEST.findall(saved):
                        if (0 <= time.time() - int(timestamp) < 7 * 86400 and len(name.split()) >= 2
                                and (not key.startswith("name:") or key[5:] == name.casefold())
                                and (not args.name or name.casefold() == args.name.casefold())):
                            contacts.setdefault(key.removeprefix("guid:"), set()).add(name)
                def journal_changed():
                    try:
                        return [(s, s.stat().st_mtime_ns, s.stat().st_size) for s in saves] != revision
                    except OSError:
                        return True
                unavailable = 0
                if contacts:
                    unavailable = sync(args.game, args.region, contacts, args.force, args.profiles_only, args.pvp_achievements,
                                       args.locale, retry_after, journal_changed if args.watch else None)
                    if not (args.watch and journal_changed()):
                        args.force = False
                elif not args.watch:
                    parser.exit(1, "No matching saved contacts. Save the journal with /reload and try again.\n")
                last = None if args.watch and journal_changed() else revision
                # Recheck the cache even while the saved journal is unchanged.
                check_at = min([time.monotonic() + 300] + [retry_after[k] for k in contacts if k in retry_after])
        except (ValueError, OSError, URLError) as exc:
            if not args.watch:
                parser.exit(1, f"Portrait import interrupted: {exc}\n")
            print(f"Import paused; will retry: {exc}", flush=True)
            time.sleep(30)
        if not args.watch:
            return
        time.sleep(1)


if __name__ == "__main__":
    main()
