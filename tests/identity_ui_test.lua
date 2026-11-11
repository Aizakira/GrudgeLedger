-- Actual Core + UI: faction and relation are independent, race/class are observed.
local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
local units, secret = mock.units, mock.secret
function UnitClass(unit) local u = units[unit] return u and u.className, u and u.class end
function UnitRace(unit) local u = units[unit] return u and u.raceName, u and u.race end
function UnitSex(unit) return units[unit] and units[unit].sex end
function UnitFactionGroup(unit) return units[unit] and units[unit].faction end
LOCALIZED_CLASS_NAMES_MALE = { SHAMAN = "Chaman", MAGE = "Mage" }
LOCALIZED_CLASS_NAMES_FEMALE = { SHAMAN = "Chamane", MAGE = "Mage" }
function GetClassAtlas(class) return "classicon-" .. class end
local knownAtlas = { ["classicon-shaman"] = true, ["raceicon128-dwarf-female"] = true }
C_Texture = { GetAtlasInfo = function(atlas) return knownAtlas[atlas] and {} or nil end }
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }
local methods = getmetatable(UIParent).__index
function methods:SetAtlas(atlas) assert(knownAtlas[atlas]) self.atlas, self.texture = atlas, nil end
function methods:SetTexture(path) self.texture, self.atlas = path, nil end

assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UI.lua"))()
local GL = GrudgeLedger
GL.InitDB()
units.target = { name = "Dwarf", surname = "Companion", guid = "Player-1-dwarf",
    faction = "Alliance", race = "Dwarf", raceName = "Naine", class = "SHAMAN", className = "Chamane", sex = 3 }
local dwarf = GL.Identity("target")
local record = GL.SetReaction(dwarf, "friend")
assert(record.race == "Dwarf" and record.raceName == "Naine" and record.class == "SHAMAN" and record.sex == 3,
    "custom race/class combinations must be recorded without inferred restrictions")
GL.AddNote(record, "A good companion")
units.target.class, units.target.race, units.target.sex, units.target.faction = secret, secret, secret, secret
units.target.className, units.target.raceName = "Guerrier", "Orc"
GL.RecordSeen(GL.Identity("target"))
assert(record.className == "Chamane" and record.raceName == "Naine" and record.faction == "Alliance" and record.sex == 3,
    "partial/secret observations preserve known pairs and faction")

local function add(name, faction, relation)
    local id = GL.IdentityFromName(name, "Example", "Player-1-" .. name)
    id.faction = faction
    return GL.SetReaction(id, relation)
end
local hordeFriend = add("HordeFriend", "Horde", "friend")
local hordeEnemy = add("HordeEnemy", "Horde", "enemy")
local allianceEnemy = add("AllianceEnemy", "Alliance", "enemy")
local warning = add("Caution", "Horde", "warning")
local unknown = add("Unknown", nil, "friend")
local neutral = add("NeutralFaction", "Neutral", "friend")
GL.ShowLedger(dwarf.key)
local f = GrudgeLedgerWindow
local function click(button) button.scripts.OnClick(button, "LeftButton") end
local function rowFor(key)
    for _, row in ipairs(f.rows) do if row:IsShown() and row.key == key then return row end end
end
local row = assert(rowFor(record.key))
assert(row.identity:GetText() == "Alliance · Naine · Chamane")
assert(row.raceIcon.atlas == "raceicon128-dwarf-female" and row.classIcon.atlas == "classicon-shaman")
assert(f.detailIdentity:GetText() == "Alliance · Naine · Chamane")
click(f.filters.friend) click(f.factions.Horde)
assert(f.total:GetText() == "1 personne(s) · Ami · Horde" and f.rows[1].key == hordeFriend.key)
assert(not f.actions[1].enabled, "a filtered-out record must not remain the active detail")
click(f.rows[1])
assert(f.detailIdentity:GetText():find("Horde", 1, true))
click(f.filters.enemy)
assert(f.rows[1].key == hordeEnemy.key and f.total:GetText():find("1 personne(s)", 1, true))
click(f.factions.Alliance)
assert(f.rows[1].key == allianceEnemy.key)
click(f.filters.warning) click(f.factions.Horde)
assert(f.rows[1].key == warning.key)
click(f.filters.friend) click(f.factions.unknown)
assert(f.rows[1].key == unknown.key and not f.rows[2]:IsShown(), "neutral is known, not unknown")
assert(f.rows[1].classIcon.texture:find("QuestionMark") and not f.rows[1].classIcon.atlas,
    "recycled rows reset known atlases for unknown identities")
assert(f.rows[1].raceIcon.texCoord[1] == 0 and f.rows[1].raceIcon.texCoord[2] == 1)
click(f.factions.Horde)
f.search:SetText("No match")
assert(f.empty:IsShown() and not f.rows[1]:IsShown())
f.search:SetText("HordeFriend")
assert(f.rows[1].key == hordeFriend.key and not f.empty:IsShown())
GL.ShowLedger(record.key)
assert(rowFor(record.key) and f.search:GetText() == "", "direct opening resets both filters and search")

-- Legacy class-only records use localized names and native sprite fallback.
hordeFriend.class = "MAGE"
GL.ShowLedger(hordeFriend.key)
row = assert(rowFor(hordeFriend.key))
assert(row.identity:GetText():find("Mage", 1, true))
assert(row.classIcon.texture:find("UI%-CharacterCreate%-Classes") and row.classIcon.texCoord[1] == 0.25)
C_Texture, GetClassAtlas, CLASS_ICON_TCOORDS = nil, nil, nil
GL.ShowLedger(record.key)
assert(rowFor(record.key).classIcon.texture:find("QuestionMark"), "missing icon APIs never prevent labels")

-- Pagination must compose with filters and return to the first page on a change.
for i = 1, 12 do add("Paged" .. i, "Horde", "enemy") end
click(f.filters.enemy) click(f.factions.Horde)
assert(f.next.enabled and #f.rows == 8)
local firstKey = f.rows[1].key
click(f.next)
assert(f.rows[1].key ~= firstKey and not f.next.enabled)
click(f.factions.Alliance)
assert(f.rows[1].key == allianceEnemy.key and not f.next.enabled)

-- Conflicting provisional data must never attach a label to another token.
local provisional = GL.Remember(GL.IdentityFromName("Merge", "Pairs"))
provisional.class, provisional.className, provisional.race, provisional.raceName = "WARRIOR", "Guerrier", "Orc", "Orc"
local existing = GL.Remember(GL.IdentityFromName("Merge", nil, "Player-1-merge"))
existing.class, existing.race = "MAGE", "Human"
local combined = GL.Remember(GL.IdentityFromName("Merge", "Pairs", "Player-1-merge"))
assert(combined == existing and combined.className == nil and combined.raceName == nil)
local change = GL.IdentityFromName("Merge", "Pairs", "Player-1-merge")
change.class, change.className, change.race, change.raceName = "SHAMAN", "Chaman", "Dwarf", "Nain"
GL.RecordSeen(change)
assert(combined.className == "Chaman" and combined.raceName == "Nain")
change.class, change.className, change.race, change.raceName = "MAGE", nil, "Human", nil
GL.RecordSeen(change)
assert(combined.class == "MAGE" and combined.className == nil and combined.raceName == nil,
    "changing a token without a label must clear its old label")
GL.InitDB()
assert(GL.Get(dwarf).race == "Dwarf" and GL.Get(dwarf).className == "Chamane" and #GL.Get(dwarf).notes == 1)
assert(GL.Relation(GL.Get(dwarf)) == "friend" and #GL.errors == 0)
local named = GL.SetReaction(GL.IdentityFromName("Selected", "Promotion"), "friend")
GL.ShowLedger(named.key)
f.search:SetText("Selected Promotion")
local promoted = GL.SetReaction(GL.IdentityFromName("Selected", "Promotion", "Player-1-promotion"), "friend")
GL.AddNote(promoted, "Still selected after identifying the player")
assert(f.actions[1].enabled and rowFor(promoted.key).selection:IsShown(),
    "selection follows the canonical identity through name-to-GUID promotion")
assert(f.detailText:GetText():find("Still selected after identifying the player", 1, true))
print("PASS identity UI: combined faction/relation/search filters, counts, paging, detail selection, observed race/class, secret partials, identity merge, persistence, localized legacy labels and native icon fallbacks")
