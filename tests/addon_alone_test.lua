-- What a user sees with the addon alone: no Armory archive, no studio photo, nothing but the game.
-- Until 0.34.1 every sheet in the tests and in the visual checks had an archive behind it, so the
-- state every user starts from, the sheet of the player who just killed them, was never looked at.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
assert(GrudgeLedgerArmory == nil and AvatarReplayLabPhotos == nil, "nothing from outside the game")
local function click(b) b.scripts.OnClick(b, "LeftButton") end
local killer = "Player-9-0F4E"
GetPlayerInfoByGUID = function(id)
    if id == killer then return "Voleur", "ROGUE", "Mort-vivant", "Scourge", 2 end
end
-- He struck from out of sight: never targeted, no unit, nothing read on him.
local id = GL.IdentityFromName("Helvard", "Lamenoire", killer)
GL.RecordAggression(id, "confirmed", "Combat log", "alone-a")
local record = GL.RecordPvP(id, "death", "confirmed", "Combat log", "alone-d")
local me = UnitGUID("player")
for _, e in ipairs(record.history) do
    if e.kind == "death" then
        e.report = { live = {
            { src = killer, dst = me, spell = "Embuscade", amount = 412, at = 1 },
            { src = killer, dst = me, spell = "Attaque pernicieuse", amount = 188, at = 2 },
            { src = killer, dst = me, spell = "Éviscération", amount = 356, at = 4, fatal = true },
            { src = "Player-9-0F4F", dst = me, from = "Second Larron", spell = "Tir", amount = 90, at = 3 } } }
    end
end
assert(GL.OpenPlayerDossier(killer))
local f = GrudgeLedgerPlayerDossier
local o = f.overview
-- Who he is comes from the GUID alone; how he killed you comes from the combat log. Nothing to wait for.
assert(record.class == "ROGUE" and record.raceName == "Mort-vivant" and record.faction == "Horde" and record.sex == 2)
assert(o.recapTitle:GetText() == "Comment il vous a tué", o.recapTitle:GetText())
assert(o.recap:GetText() == "Embuscade 412 · Éviscération 356 · Attaque pernicieuse 188\n"
    .. "956 dégâts en 3 s · coup fatal : Éviscération · 1 autre source de dégâts", o.recap:GetText())
-- No column of dashes, and no promise the game cannot keep: an enemy is never inspected on Forever.
assert(f.keyHeading:GetText() == "" and f.observed:GetText():find("le jeu ne laisse pas inspecter un joueur ennemi", 1, true), f.observed:GetText())
for _, cell in ipairs(f.statCells) do assert(not cell:IsShown(), "no empty line") end

-- The in-game reading succeeded: what was read is listed, what the game never gives has no line.
local function item(itemID, label) return "|cff1eff00|Hitem:" .. itemID .. "::::::::38:::::|h[" .. label .. "]|h|r" end
record.level = 38
record.inspection = { stats = { HEALTH = 2140, ENERGY = 100 }, statsAt = GL.Now(), gearAt = GL.Now(), averageItemLevel = 34,
    gear = { [1] = item(10008, "Coiffe d’ombrecuir"), [15] = item(4011, "Cape du rôdeur"), [16] = item(2244, "Lame de Krol") } }
assert(GL.OpenPlayerDossier(killer))
local cells, shown = {}, 0
for _, cell in ipairs(f.statCells) do
    if cell:IsShown() then
        cells[cell.label:GetText()] = cell.value:GetText()
        shown = shown + 1
    end
end
assert(shown == 3 and cells.Vie == "2140" and cells["Énergie"] == "100" and cells["Niv. objet"] == "34", shown)
assert(f.keyHeading:GetText() == "Chiffres clés")
-- A rogue never read shows energy, not mana, the day a first value arrives.
record.inspection.stats.ENERGY = nil
assert(GL.OpenPlayerDossier(killer))
for _, cell in ipairs(f.statCells) do assert(not cell:IsShown() or cell.label:GetText() ~= "Mana") end
-- The pieces land in their slots by number, even where the game's slot lookup is missing.
assert(GetInventorySlotInfo == nil, "this harness has no slot lookup: the fixed numbers are used")
click(f.tabs.gear)
local buttons = f.equipment.equipment.buttons
assert(buttons[1].itemName == "Coiffe d’ombrecuir" and buttons[4].itemName == "Cape du rôdeur", tostring(buttons[1].itemName))
assert(buttons[17].itemName == "Lame de Krol" and buttons[2].itemName == nil)
-- Ten minutes later you win another fight: the last fight is no longer a death, so no recap.
local later = GL.Now() + 600
GetServerTime = function() return later end
GL.RecordPvP(id, "kill", "confirmed", "Combat log", "alone-k")
assert(GL.OpenPlayerDossier(killer))
click(f.tabs.overview)
assert(o.recapTitle:GetText() == "" and o.recap:GetText() == "")

-- Kept model. The game refuses to inspect an enemy, but a model taken while he was in sight keeps
-- his real look: the equipment tab shows it once he is gone, until the next reload.
local methods = getmetatable(UIParent).__index
local taken = {}
function methods:SetUnit(unit) taken[#taken + 1] = UnitGUID(unit) return true end
function methods:ClearModel() end
function methods:SetParent(parent) self.parent = parent end
UnitIsVisible = UnitExists
mock.units.target = { guid = killer, name = "Helvard", surname = "Lamenoire", isPlayer = true }
assert(GL.KeepModel("target", "Player-9-FFFF") == false, "the unit must be that player")
assert(GL.KeepModel("target", killer) == true and GL.KeptModelAt(killer) == later)
local count = #taken
assert(GL.KeepModel("target", killer) == true and #taken == count, "a fresh model is not taken twice")
mock.units.target = nil
assert(GL.OpenPlayerDossier(killer))
click(f.tabs.gear)
local view = f.equipment.equipment
assert(view.kept and view.kept.frame.parent == view.stage, "the kept model stands on the equipment stage")
assert(view.caption:GetText():find("^Vu en jeu à "), view.caption:GetText())
-- Another player's sheet does not show it, and thirteen opponents never grow the pool past twelve.
local shown = view.kept
assert(GL.OpenPlayerDossier("Player-9-0A0A", nil, "Autre Joueur"))
click(f.tabs.gear)
assert(view.kept == nil and shown.frame.parent ~= view.stage and not shown.shown)
-- Six minutes later twelve more opponents arrive: the pool makes eleven new frames and recycles the
-- killer's stale one. A thirteenth finds only fresh models and evicts none (no thrashing in a crowd).
local frames = #mock.frames
local muchLater = later + 360
GetServerTime = function() return muchLater end
for i = 1, 12 do
    local other = ("Player-9-1%03d"):format(i)
    mock.units.target = { guid = other, name = "Autre", surname = "N" .. i, isPlayer = true }
    assert(GL.KeepModel("target", other), i)
end
assert(#mock.frames - frames == 11 and GL.KeptModelAt(killer) == nil, "the stalest model is recycled")
mock.units.target = { guid = "Player-9-1099", name = "Autre", surname = "Dernier", isPlayer = true }
assert(GL.KeepModel("target", "Player-9-1099") == false and GL.KeptModelAt("Player-9-1001") == muchLater, "a fresh model is never evicted")
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS addon alone: class and faction from the GUID, how the last death happened from the combat log, "
    .. "no dash column, in-game reading listed, gear placed by slot number, kept model shown and recycled")
