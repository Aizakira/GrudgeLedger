"""Import verified Forever Armory avatars into a private, optional WoW media addon."""
import argparse
import gzip
import io
import json
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


def armory_state(region, name, suffix=""):
    slug = "-".join(name.casefold().split())
    html = fetch(f"https://worldofwarcraft.blizzard.com/en-us/forever/{region}/armory/character/{quote(slug, safe='')}{suffix}", 4_000_000).decode()
    start = PROFILE.search(html)
    model = re.search(r'<script id="model">\s*model\s*=\s*', html)
    if model:
        mounts = json.JSONDecoder().raw_decode(html[model.end():].lstrip())[0]["reactMounts"]
        return next((m["initialState"] for m in mounts if m.get("id") == "character-profile-mount"), {})
    if start:
        return json.JSONDecoder().raw_decode(html[start.end():].lstrip())[0]
    raise ValueError("no Armory profile")


def character_profile(region, name, guid):
    if not re.fullmatch(GUID, guid) or region not in ("eu", "us", "kr", "tw"):
        raise ValueError("invalid character or region")
    data = armory_state(region, name)["character"]

    if data["region"] != region or (data["name"] + " " + data["surname"]).casefold() != name.casefold():
        raise ValueError("character name or region mismatch")
    media = data["avatar"]["url"]
    player_id = int(guid.rsplit("-", 1)[1], 16)
    if not re.fullmatch(rf"https://render\.worldofwarcraft\.com/forever-{region}/character/[0-9]+/{player_id}-avatar\.jpg", media):
        raise ValueError("no individual avatar matching the saved character ID")
    return data


def portrait(data):
    media = data["avatar"]["url"]
    with Image.open(io.BytesIO(fetch(media, 512_000))) as img:
        if img.format != "JPEG" or img.width != img.height or not 32 <= img.width <= 512:
            raise ValueError("unexpected avatar format")
        buf = io.BytesIO()
        img.convert("RGB").resize((64, 64), Image.Resampling.LANCZOS).save(buf, format="TGA")
        return buf.getvalue()


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


def pvp_achievements(character, name):
    state = armory_state(character["region"], name, "/achievements/player-vs-player")
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
        gear[slot] = details({k: item[k] for k in ("id", "name", "quality", "level", "armor", "weapon",
            "stats", "bonus_list", "enchantments", "sockets", "spells", "set", "requirements") if k in item})
        assets = item.get("media", {}).get("content", {}).get("assets", [])
        texture = next((icon_id(a.get("value")) for a in assets if a.get("key") == "icon"), None)
        if texture:
            gear[slot]["icon"] = texture
    stats = {}
    for group in data.get("stats", {}).get("groups", []):
        for stat in group.get("stats", []):
            value = stat.get("value", {})
            if isinstance(value.get("value"), (int, float)):
                stats[stat["enum"]] = value["value"]
            elif value.get("type") == "RANGE":
                stats[stat["enum"]] = [value[k]["value"] for k in ("min", "max")]
    pvp = data.get("pvp", {})
    return {"stats": stats, "honorableKills": pvp.get("honorableKills", {}).get("value"),
            "pvpRank": pvp.get("rank", {}).get("value"),
            "gear": gear, "updated": data.get("lastUpdatedTimestamp", {}).get("epoch"),
            "level": data.get("level"), "averageItemLevel": data.get("averageItemLevel"),
            "trees": [{"name": t["name"], "points": t["spentPoints"], "talents":
                      [[v["id"], v["name"], v["rank"], icon_id(v.get("icon", {}).get("url"))]
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


def publish_profiles(folder):
    profiles, variants, indices = {}, [], {}
    for file in sorted(folder.glob("Player-*.json")):
        if not re.fullmatch(GUID, file.stem):
            continue
        profile = json.loads(file.read_text("utf8"))
        for slot, item in profile["gear"].items():
            key = lua(item)
            if key not in indices:
                variants.append(item)
                indices[key] = len(variants)
            profile["gear"][slot] = indices[key]
        profiles[file.stem] = profile
    write_atomic(folder / "Profiles.lua", ("GrudgeLedgerArmory = " +
                 lua({"profiles": profiles, "items": variants}) + "\n").encode())


def sync(root, region, contacts, force=False, profiles_only=False, achievements=False):
    addons = root / "Interface" / "AddOns"
    if not (addons / "GrudgeLedger" / "GrudgeLedger.toc").is_file():
        raise ValueError("Grudge Ledger is missing from the selected game folder")
    folder = addons / "GrudgeLedgerPortraits"
    folder.mkdir(exist_ok=True)
    updated = fresh = unavailable = 0
    for guid, names in sorted(contacts.items()):
        if not re.fullmatch(GUID, guid):
            raise ValueError("invalid character GUID")
        path = folder / (guid + ".tga")
        cache = path.with_suffix(".json")
        required = (cache,) if profiles_only else (cache, path)
        previous = json.loads(cache.read_text("utf8")) if cache.is_file() else {}
        fresh_achievements = 0 <= time.time() - (previous.get("achievementsAt") or 0) < 7 * 86400
        if not force and "stats" in previous and (not achievements or fresh_achievements) and all(
                f.is_file() and 0 <= time.time() - f.stat().st_mtime < 7 * 86400 for f in required):
            fresh += 1
            continue
        for name in sorted(names):
            try:
                character = character_profile(region, name, guid)
                snapshot = compact(character)
                if "achievements" in previous:
                    snapshot["achievements"] = previous["achievements"]
                    snapshot["achievementsAt"] = previous.get("achievementsAt")
                if achievements:
                    try:
                        snapshot["achievements"] = pvp_achievements(character, name)
                        snapshot["achievementsAt"] = int(time.time())
                    except (ValueError, KeyError, URLError) as exc:
                        print(f"PvP achievements unavailable for {name}: {exc}")
                profile = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")).encode()
                if not profiles_only:
                    data = portrait(character)
            except HTTPError as exc:
                if exc.code == 404:
                    continue
                raise
            except (ValueError, KeyError, UnidentifiedImageError):
                continue
            write_atomic(cache, profile)
            cache.touch()
            if not profiles_only:
                write_atomic(path, data)
                path.touch()
            updated += 1
            break
        else:
            unavailable += 1
    # Publish only complete textures. A later run can recover a fully written
    # portrait even if a previous import stopped before publishing the index.
    keys = sorted(p.stem for p in folder.glob("Player-*.tga") if re.fullmatch(GUID, p.stem))
    index = "GrudgeLedgerPortraitIndex = {\n" + "".join(f'    ["{k}"] = true,\n' for k in keys) + "}\n"
    write_atomic(folder / "Portraits.lua", index.encode("ascii"))
    publish_profiles(folder)
    write_atomic(folder / "GrudgeLedgerPortraits.toc", TOC + b"Profiles.lua\n")
    print(f"{updated} updated, {fresh} recent, {unavailable} unavailable. {len(keys)} portraits in {folder}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, help="the _forever_ directory")
    parser.add_argument("--region", choices=("eu", "us", "kr", "tw"), required=True)
    parser.add_argument("--name", help="only synchronize this full character name")
    parser.add_argument("--force", action="store_true", help="refresh even within seven days")
    parser.add_argument("--profiles-only", action="store_true", help="import gear and talents without downloading images")
    parser.add_argument("--pvp-achievements", action="store_true", help="also fetch completed PvP achievements")
    args = parser.parse_args()
    contacts = {}
    for save in (args.game / "WTF" / "Account").glob("*/SavedVariables/GrudgeLedger.lua"):
        for name, guid in ALIAS.findall(save.read_text(encoding="utf-8-sig")):
            if not args.name or name.casefold() == args.name.casefold():
                contacts.setdefault(guid, set()).add(name)
    if not contacts:
        parser.exit(1, "No matching saved contacts. Save the journal with /reload and try again.\n")
    try:
        sync(args.game, args.region, contacts, args.force, args.profiles_only, args.pvp_achievements)
    except (ValueError, OSError, URLError) as exc:
        parser.exit(1, f"Portrait import interrupted: {exc}\n")


if __name__ == "__main__":
    main()
