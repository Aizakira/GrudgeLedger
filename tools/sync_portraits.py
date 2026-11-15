"""Import verified Forever Armory character sheets and portraits into a private local addon."""
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
    if not re.fullmatch(GUID, guid) or region not in ("eu", "us", "kr", "tw"):
        raise ValueError("invalid character or region")
    state = armory_state(region, name, locale=locale)
    data = state["character"]

    if data["region"] != region or (data["name"] + " " + data["surname"]).casefold() != name.casefold():
        raise ValueError("character name or region mismatch")
    media = data["avatar"]["url"]
    player_id = int(guid.rsplit("-", 1)[1], 16)
    if not re.fullmatch(rf"https://render\.worldofwarcraft\.com/forever-{region}/character/[0-9]+/{player_id}-avatar\.jpg", media):
        raise ValueError("no individual avatar matching the saved character ID")
    return dict(data, supportedArmoryTabs=state.get("supportedArmoryTabs", []))


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
        gear[slot] = details({k: item[k] for k in ("id", "name", "quality", "level", "armor", "weapon",
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
    identity["classFile"] = data.get("class", {}).get("enum")
    return {"armorySchema": 2, "identity": identity, "stats": stats, "honorableKills": pvp.get("honorableKills", {}).get("value"),
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


def publish_profiles(folder):
    profiles, variants, indices = {}, [], {}
    for file in sorted(folder.glob("Player-*.json")):
        if not re.fullmatch(GUID, file.stem):
            continue
        profile = json.loads(file.read_text("utf8"))
        if (folder / (file.stem + "-body.tga")).is_file():
            profile["body"] = True
        for slot, item in profile["gear"].items():
            key = lua(item)
            if key not in indices:
                variants.append(item)
                indices[key] = len(variants)
            profile["gear"][slot] = indices[key]
        profiles[file.stem] = profile
    write_atomic(folder / "Profiles.lua", ("GrudgeLedgerArmory = " +
                 lua({"profiles": profiles, "items": variants}) + "\n").encode())


def sync(root, region, contacts, force=False, profiles_only=False, achievements=False, locale="en-us"):
    addons = root / "Interface" / "AddOns"
    if not (addons / "GrudgeLedger" / "GrudgeLedger.toc").is_file():
        raise ValueError("Grudge Ledger is missing from the selected game folder")
    folder = addons / "GrudgeLedgerPortraits"
    folder.mkdir(exist_ok=True)
    updated = fresh = unavailable = 0
    if any(not re.fullmatch(GUID, guid) for guid in contacts):
        raise ValueError("invalid character GUID")
    for guid, names in sorted(contacts.items(), key=lambda pair: (folder / (pair[0] + ".json")).is_file()):
        path = folder / (guid + ".tga")
        cache = path.with_suffix(".json")
        required = (cache,) if profiles_only else (cache, path)
        previous = json.loads(cache.read_text("utf8")) if cache.is_file() else {}
        fresh_achievements = 0 <= time.time() - (previous.get("achievementsAt") or 0) < 7 * 86400
        same_locale = previous.get("locale", "en-us") == locale
        media_current = profiles_only or previous.get("bodyChecked")
        if not force and same_locale and previous.get("armorySchema") == 2 and media_current and (not achievements or fresh_achievements) and all(
                f.is_file() and 0 <= time.time() - f.stat().st_mtime < 7 * 86400 for f in required):
            fresh += 1
            continue
        for name in sorted(names):
            try:
                character = character_profile(region, name, guid, locale)
                snapshot = compact(character)
                snapshot["locale"] = locale
                snapshot["bodyChecked"] = previous.get("bodyChecked", False)
                for section, key in (("pvp", "battlegrounds"), ("reputation", "reputations")):
                    if same_locale and key in previous:
                        snapshot[key], snapshot[key+"At"] = previous[key], previous.get(key+"At")
                    if section in character["supportedArmoryTabs"]:
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
                if achievements:
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
                            write_atomic(folder / (guid + "-body.tga"), body)
                        snapshot["bodyChecked"] = True
                    except (ValueError, KeyError, OSError) as exc:
                        print(f"Character render unavailable for {guid}: {ascii(str(exc))}")
                profile = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")).encode()
            except HTTPError as exc:
                if exc.code == 404:
                    continue
                print(f"Armory HTTP {exc.code} for {guid}")
                continue
            except (OSError, ValueError, KeyError):
                continue
            write_atomic(cache, profile)
            cache.touch()
            if not profiles_only and data is not None:
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
    print(f"{updated} updated, {fresh} recent, {unavailable} unavailable. {len(keys)} portraits in {folder}", flush=True)
    return unavailable


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path, help="the _forever_ directory")
    parser.add_argument("--region", choices=("eu", "us", "kr", "tw"), required=True)
    parser.add_argument("--locale", choices=("en-us", "fr-fr", "es-es"), default="en-us", help="language of equipment, enchantments and talents")
    parser.add_argument("--name", help="only synchronize this full character name")
    parser.add_argument("--force", action="store_true", help="refresh even within seven days")
    parser.add_argument("--profiles-only", action="store_true", help="import gear and talents without downloading images")
    parser.add_argument("--pvp-achievements", action="store_true", help="also fetch completed PvP achievements")
    parser.add_argument("--watch", action="store_true", help="watch locally saved journals; stop with Ctrl+C")
    args = parser.parse_args()
    if not (args.game / "Interface/AddOns/GrudgeLedger/GrudgeLedger.toc").is_file():
        parser.error("select the _forever_ folder containing GrudgeLedger")
    last, check_at = None, 0
    while True:
        try:
            saves = sorted((args.game / "WTF/Account").glob("*/SavedVariables/GrudgeLedger.lua"))
            revision = [(s, s.stat().st_mtime_ns, s.stat().st_size) for s in saves]
            if revision != last or time.monotonic() >= check_at:
                contacts = {}
                for save in saves:
                    for name, guid in ALIAS.findall(save.read_text(encoding="utf-8-sig")):
                        if not args.name or name.casefold() == args.name.casefold():
                            contacts.setdefault(guid, set()).add(name)
                unavailable = 0
                if contacts:
                    unavailable = sync(args.game, args.region, contacts, args.force, args.profiles_only, args.pvp_achievements, args.locale)
                    args.force = False
                elif not args.watch:
                    parser.exit(1, "No matching saved contacts. Save the journal with /reload and try again.\n")
                last, check_at = revision, time.monotonic() + (1800 if unavailable else 86400)
        except (ValueError, OSError, URLError) as exc:
            if not args.watch:
                parser.exit(1, f"Portrait import interrupted: {exc}\n")
            print(f"Import paused; will retry: {exc}", flush=True)
        if not args.watch:
            return
        time.sleep(5)


if __name__ == "__main__":
    main()
