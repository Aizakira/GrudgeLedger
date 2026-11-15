"""Regenerate the shared Forever talent layout from the installed client's DB2 build.

python tools/forever_talents.py CACHE_DIR
Reads the matching Blizzard DB2 tables via wago.tools once; never runs in WoW.
"""
import argparse
import csv
import json
from pathlib import Path
from urllib.request import Request, urlopen

BUILD = "1.60.1.70938"
# One trait tree per class. Its three visible groups come from TraitNodeGroupDisplayInfo.
CLASSES = {1082:"SHAMAN", 1089:"DRUID", 1091:"HUNTER", 1100:"PALADIN", 1111:"ROGUE",
           1112:"MAGE", 1114:"PRIEST", 1116:"WARLOCK", 1117:"WARRIOR"}
OUTPUT = Path(__file__).resolve().parents[1] / "GrudgeLedger" / "DossierTalentData.lua"


def generate(cache):
    cache.mkdir(parents=True, exist_ok=True)

    def table(name, locale="enUS"):
        path = cache / (name + (".fr" if locale == "frFR" else "") + ".csv")
        if not path.exists():
            url = f"https://wago.tools/db2/{name}/csv?build={BUILD}&locale={locale}"
            req = Request(url, headers={"User-Agent":"GrudgeLedger/talent-catalog"})
            with urlopen(req, timeout=20) as response:
                path.write_bytes(response.read())
        with path.open(encoding="utf-8-sig", newline="") as stream:
            return list(csv.DictReader(stream))

    def index(name, locale="enUS"):
        return {r["ID"]:r for r in table(name, locale)}

    def lua(value):
        if isinstance(value, list):
            return "{" + ",".join(map(lua, value)) + "}"
        return json.dumps(value, ensure_ascii=False)

    nodes, entries, defs = (index(n) for n in ("TraitNode","TraitNodeEntry","TraitDefinition"))
    links = {r["TraitNodeID"]:r["TraitNodeEntryID"] for r in table("TraitNodeXTraitNodeEntry")}
    groups = table("TraitNodeGroupDisplayInfo")
    members = {}
    for r in table("TraitNodeGroupXTraitNode"):
        members.setdefault(r["TraitNodeGroupID"], []).append(r["TraitNodeID"])
    names, names_fr = index("SpellName"), index("SpellName","frFR")
    skills, skills_fr = index("SkillLine"), index("SkillLine","frFR")
    icons = {r["SpellID"]:int(r["SpellIconFileDataID"]) for r in table("SpellMisc") if r["DifficultyID"] == "0"}
    edges = table("TraitEdge")
    lines = [f"-- Generated from Blizzard Forever DB2 {BUILD} by tools/forever_talents.py.",
             "-- Node fields: definitionID, spellID, column, row, maxRanks, iconFileID, English name, French name.",
             "GrudgeLedger.DossierTalentData = {"]
    total = 0
    for tree_id, class_file in sorted(CLASSES.items()):
        lines.append(f"  {class_file} = {{")
        groups_for_class = sorted((g for g in groups if int(g["TraitTreeID"]) == tree_id), key=lambda g:int(g["OrderIndex"]))
        assert len(groups_for_class) == 3
        for g in groups_for_class:
            skill, branch = g["SkillLineID"], int(g["OrderIndex"])
            data, positioned, cells = [], {}, set()
            for node_id in members[g["TraitNodeGroupID"]]:
                node = nodes[node_id]
                x = (int(node["PosX"]) - (1020, 5020, 9080)[branch]) / 600
                y = (int(node["PosY"]) - 2130) / 600
                col, row = round(x), round(y)
                if not (0 <= col < 4 and 0 <= row < 7 and abs(col-x) < .1 and abs(row-y) < .1):
                    # Three retired/off-canvas records on this build; never invent positions for them.
                    if node_id not in {"104982", "105003", "105865"}:
                        raise ValueError(f"Review off-grid talent {node_id} on {BUILD}")
                    continue
                assert (col,row) not in cells
                cells.add((col,row))
                entry = entries[links[node_id]]
                did = entry["TraitDefinitionID"]
                spell = defs[did]["SpellID"]
                icon = int(defs[did]["OverrideIcon"]) or icons[spell]
                assert icon and int(entry["MaxRanks"]) > 0
                data.append([int(did),int(spell),col,row,int(entry["MaxRanks"]),icon,
                             names[spell]["Name_lang"],names_fr[spell]["Name_lang"]])
                positioned[node_id] = int(did)
            arrows = []
            for edge in edges:
                a, b = edge["LeftTraitNodeID"], edge["RightTraitNodeID"]
                if edge["Type"] in ("2","3") and a in positioned and b in positioned:
                    arrows.append([positioned[a],positioned[b]])
            data.sort(key=lambda r:(r[3],r[2]))
            lines.append("    {en="+lua(skills[skill]["DisplayName_lang"])+",fr="+lua(skills_fr[skill]["DisplayName_lang"])+",nodes={")
            lines.extend("      "+lua(v)+"," for v in data)
            lines.append("    },edges="+lua(sorted(arrows))+"},")
            total += len(data)
        lines.append("  },")
    lines.append("}")
    assert total == 467, f"Review visible class talents: {total}"
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path, help=f"directory for DB2 CSVs of build {BUILD} only")
    OUTPUT.write_text(generate(parser.parse_args().cache), encoding="utf-8", newline="\n")
