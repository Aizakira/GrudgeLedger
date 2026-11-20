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
function methods:SetParent(parent) self.parent = parent end
function methods:SetAtlas(atlas) assert(knownAtlas[atlas]) self.atlas, self.texture = atlas, nil end
function methods:SetTexture(path) self.texture, self.atlas = path, nil end
function methods:SetAlpha(value) self.alpha = value end

assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT .. "/UITheme.lua"))()
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
GL.SetSetting("guideSeen", true)
local latest = GL.SearchPlayers({sort = "recent"})[1]
local events, observedAt = #latest.history, latest.lastEncounterAt
GL.ShowLedger()
local opened = GrudgeLedgerWindow
assert(opened.rows[1].key == latest.key and opened.rows[1].selection:IsShown() and opened.detailTitle:GetText() == latest.fullName,
    "a populated journal opens the first entry in chronological order")
assert(#latest.history == events and latest.lastEncounterAt == observedAt, "reading a profile is not a new encounter")
GL.ShowLedger(dwarf.key)
local f = GrudgeLedgerWindow
local function click(button) button.scripts.OnClick(button, "LeftButton") end
local function rowFor(key)
    for _, row in ipairs(f.rows) do if row:IsShown() and row.key == key then return row end end
end
local row = assert(rowFor(record.key))
assert(row.identity:GetText() == "Alliance · Naine · Chamane")
assert(row.raceIcon.texture == GL.icon and row.classIcon.atlas == "classicon-shaman")
-- A character observed in French can be viewed later on a different client.
-- Only its display changes. A custom name survives if the client has no matching token.
do
    local calls = 0
    C_CreatureInfo = { GetRaceInfo = function(id)
        calls = calls + 1
        if id == 3 then return {clientFileString="Dwarf",raceName="Enano"} end
        if id == 88 then return {clientFileString="OtherRace",raceName="No corresponde"} end
        if id == 89 then return {clientFileString="ForeverRace",raceName="Eólido"} end
    end }
    LOCALIZED_CLASS_NAMES_FEMALE.SHAMAN = "Chamana"
    GL.ShowLedger(dwarf.key)
    assert(rowFor(record.key).identity:GetText() == "Alliance · Enano · Chamana")
    assert(record.raceName == "Naine" and record.className == "Chamane" and calls == 1)
    record.race, record.raceName, record.raceID = "ForeverRace", "Éolide", 88
    record.class, record.className = "FOREVERCLASS", "Archiviste"
    GL.ShowLedger(dwarf.key)
    assert(rowFor(record.key).identity:GetText() == "Alliance · Éolide · Archiviste")
    record.raceID = 89
    GL.RecordPvP(record, "death", "confirmed", nil, "localized-race")
    GL.ShowJournal("summary")
    click(GrudgeLedgerJournal.dimensionButtons.race)
    assert(GrudgeLedgerJournal.breakdownRows[1].name:GetText() == "Eólido", "event snapshot retains its custom race ID")
    record.race, record.raceName, record.raceID = "Dwarf", "Naine", nil
    record.class, record.className = "SHAMAN", "Chamane"
    LOCALIZED_CLASS_NAMES_FEMALE.SHAMAN = "Chamane"
    C_CreatureInfo = nil
end
knownAtlas["raceicon128-dwarf-female"], knownAtlas["raceicon-dwarf-female"] = nil, true
GL.ShowLedger(dwarf.key)
assert(rowFor(record.key).raceIcon.texture == GL.icon and f.raceIcon.texture == GL.icon,
    "both the index and the profile use the book while no portrait is available")
assert(f.detailIdentity:GetText() == "Alliance · Enano · Chamane" and f.levelBadge:IsShown() and f.levelBadge.caption:GetText() == "42", "profile shares the cached native race label with the index")
click(f.relationFilter) assert(f.filters.friend.parent:IsShown())
click(f.filters.friend) assert(not f.filters.friend.parent:IsShown())
click(f.factionFilter) click(f.factions.Horde)
assert(f.total:GetText() == "1 personne" and f.rows[1].key == hordeFriend.key)
assert(f.actions[1].enabled and f.rows[1].selection:IsShown() and f.detailTitle:GetText() == hordeFriend.fullName,
    "filtering replaces an excluded contact with the first visible profile")
click(f.rows[1])
assert(f.detailIdentity:GetText():find("Horde", 1, true))
click(f.filters.enemy)
assert(f.rows[1].key == hordeEnemy.key and f.total:GetText() == "1 personne")
click(f.factions.Alliance)
assert(f.rows[1].key == allianceEnemy.key)
click(f.filters.warning) click(f.factions.Horde)
assert(f.rows[1].key == warning.key)
click(f.filters.friend) click(f.factions.unknown)
assert(f.rows[1].key == unknown.key and not f.rows[2]:IsShown(), "neutral is known, not unknown")
assert(not f.rows[1].classIcon.texture and not f.rows[1].classIcon.atlas and f.rows[1].raceIcon.texture == GL.icon,
    "recycled rows clear old class badges and show a neutral medallion for completely unknown identities")
assert(f.rows[1].raceIcon.texCoord[1] == 0 and f.rows[1].raceIcon.texCoord[2] == 1)
click(f.factions.Horde)
f.search:SetText("No match")
click(f.searchButton)
assert(f.empty:IsShown() and f.emptyPage:IsShown() and not f.rows[1]:IsShown() and not f.actions[1].enabled)
f.search:SetText("HordeFriend")
click(f.searchButton)
assert(f.rows[1].key == hordeFriend.key and not f.empty:IsShown())
GL.ShowLedger(record.key)
assert(rowFor(record.key) and f.search:GetText() == "", "direct opening resets both filters and search")

-- Legacy class-only records use localized names and native sprite fallback.
hordeFriend.class = "MAGE"
GL.ShowLedger(hordeFriend.key)
row = assert(rowFor(hordeFriend.key))
assert(row.identity:GetText():find("Mage", 1, true))
assert(row.classIcon.texture:find("UI%-CharacterCreate%-Classes") and row.classIcon.texCoord[1] == 0.25)
assert(row.raceIcon.texture == GL.icon and row.raceIcon.texCoord[1] == 0,
    "class-only contacts retain the class badge and use the book as their portrait fallback")
C_Texture, GetClassAtlas, CLASS_ICON_TCOORDS = nil, nil, nil
GL.ShowLedger(record.key)
assert(not rowFor(record.key).classIcon.texture and rowFor(record.key).raceIcon.texture == GL.icon,
    "missing atlas APIs still fall back to the book")

-- Pagination must compose with filters and return to the first page on a change.
for i = 1, 12 do add("Paged" .. i, "Horde", "enemy") end
click(f.filters.enemy) click(f.factions.Horde)
assert(f.next.enabled and #f.rows > 0)
local firstKey = f.rows[1].key
click(f.next)
assert(f.rows[1].key ~= firstKey and f.rows[1].selection:IsShown() and f.detailTitle:GetText() == GL.Get(f.rows[1].key).fullName)
for page = 2, math.ceil(13 / f.pageSize) - 1 do
    assert(f.next.enabled, "remaining filtered records must be reachable")
    click(f.next)
end
assert(not f.next.enabled, "pagination ends after all 13 filtered records")
local finalContact = f.detailTitle:GetText()
GL.SetSetting("compactMode", true)
assert(f.previous.enabled and f.detailTitle:GetText() == finalContact, "changing density keeps the current contact and its page")
click(f.previous)
assert(f.pageSize == 9 and f.rows[9]:IsShown() and not f.rows[8].raceIcon:IsShown())
click(f.next)
assert(not f.next.enabled and f.rows[4]:IsShown() and not f.rows[5]:IsShown())
GL.SetSetting("compactMode", false)
assert(f.pageSize == 6 and not f.rows[7]:IsShown() and f.rows[1].raceIcon:IsShown())
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
click(f.searchButton)
local promoted = GL.SetReaction(GL.IdentityFromName("Selected", "Promotion", "Player-1-promotion"), "friend")
GL.AddNote(promoted, "Still selected after identifying the player")
assert(f.actions[1].enabled and rowFor(promoted.key).selection:IsShown(),
    "selection follows the canonical identity through name-to-GUID promotion")
assert(f.detailScroll.fullText:find("Still selected after identifying the player", 1, true))
local roster = GL.Remember(GL.IdentityFromName("OnlyRoster", "Example", "Player-1-onlyroster"))
roster.groupCount, roster.history = 2, { { kind = "grouped", sessionId = "old-session" } }
GL.ShowLedger(record.key)
f.search:SetText("OnlyRoster")
click(f.searchButton)
assert(f.empty:IsShown() and not rowFor(roster.key), "old group-only entries must not clutter even search results")
assert(GL.Get(roster).groupCount == 2, "filtering never deletes the underlying history")
GL.ShowLedger(roster.key)
assert(rowFor(roster.key), "an explicitly requested old record remains accessible")
GL.SetReaction(roster, "neutral")
GL.ShowLedger(record.key)
f.search:SetText("OnlyRoster")
click(f.searchButton)
assert(rowFor(roster.key), "explicit neutral opinions must remain visible")
roster.reaction, roster.reputation, roster.history = nil, nil, { { kind = "grouped" } }
GL.AddNote(roster, "Personal note worth keeping")
GL.ShowLedger(record.key)
f.search:SetText("OnlyRoster")
click(f.searchButton)
assert(rowFor(roster.key), "personal notes preserve otherwise neutral records")
local guildContact = GL.IdentityFromName("Guild", "History", "Player-1-guildhistory")
guildContact.guild, guildContact.realm = "Old Guild", "Realm One"
local guildRecord = GL.RecordPvP(guildContact, "death", "confirmed", "Fixture", "ui-guild-1")
guildContact.guild = "New Guild" GL.Remember(guildContact)
GL.ShowLedger(guildRecord.key)
assert(f.detailGuild:GetText() == "New Guild")
click(f.detailTabs.history)
click(f.historyPage.rows[1].details)
assert(GrudgeLedgerCorrections.scroll.fullText:find("Guilde mémorisée : Old Guild (Realm One)",1,true))
assert(GL.VoidPvP(guildRecord, guildRecord.history[1]))
assert(GrudgeLedgerCorrections.scroll.fullText:find("Guilde mémorisée : Old Guild",1,true) and not GrudgeLedgerCorrections.confirm.enabled)
-- The same physical slot can show different contacts when the target, filter or page changes.
local unitFor = { [record.guid] = "nameplate1" }
local painted = 0
units.nameplate1 = units.target
function UnitTokenFromGUID(guid) return unitFor[guid] end
function UnitIsVisible(unit) return units[unit] and not units[unit].distant end
function SetPortraitTexture(texture, unit, square)
    assert(square) painted = painted + 1
    texture:SetTexture("face:" .. UnitGUID(unit))
end
GrudgeLedgerCorrections:Hide()
GL.ShowLedger(record.key)
row = assert(rowFor(record.key))
assert(row.raceIcon.texture == "face:" .. record.guid and f.raceIcon.texture == row.raceIcon.texture)
local watcher
for _, frame in ipairs(mock.frames) do if frame.events.PORTRAITS_UPDATED then watcher = frame end end
local function portraitEvent(event, unit)
    mock.Fire(event, unit)
    local update = watcher.scripts.OnUpdate
    if update then update(watcher, 0.016) end
end
local before = painted
portraitEvent("UNIT_PORTRAIT_UPDATE", "nameplate1")
assert(painted > before, "a changed live appearance repaints the open book")
units.nameplate1, units.target = { guid = "Player-1-different" }, nil
portraitEvent("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assert(f.raceIcon.texture == "face:" .. record.guid and row.raceIcon.texture == f.raceIcon.texture, "recycled unit token cannot paint a different face")
unitFor[record.guid] = secret
units.target = { guid = record.guid, distant = true }
portraitEvent("PLAYER_TARGET_CHANGED")
assert(f.raceIcon.texture == "face:" .. record.guid, "invisible units retain a fallback")
units.target.distant = false
portraitEvent("PLAYER_TARGET_CHANGED")
assert(f.raceIcon.texture == "face:" .. record.guid, "valid target fallback for an unavailable GUID resolver")
function SetPortraitTexture() error("restricted") end
portraitEvent("UNIT_PORTRAIT_UPDATE", "target")
assert(f.raceIcon.texture == "face:" .. record.guid, "restricted texture access clears the live slot")
f:Hide()
mock.Fire("PORTRAITS_UPDATED")
assert(not watcher.scripts.OnUpdate, "closed book does not poll portraits")
assert(record.portraitUnit == nil and record.portrait == nil, "no portrait texture or token is persisted")
local saved = GL.SetReaction(GL.IdentityFromName("Example", "Keeper", "Player-42-000000F1"), "friend")
GL.ShowLedger(saved.key)
assert(not f.archivedPortrait)
GrudgeLedgerPortraitIndex = { [saved.guid] = true }
GL.InitDB()
GL.ShowLedger(saved.key)
local path = "Interface\\AddOns\\GrudgeLedgerPortraits\\" .. saved.guid
assert(f.raceIcon.texture ~= path and not rowFor(saved.key).archivedPortrait, "an Armory URL can depict another race")
GrudgeLedgerPortraitIndex[saved.guid] = "native"
GL.ShowLedger(saved.key)
assert(f.raceIcon.texture == path .. "-native" and rowFor(saved.key).archivedPortrait == "native")
units.target = {guid=saved.guid}
SetPortraitTexture = function(texture) texture:SetTexture("current-face") end
IsUnitModelReadyForUI = function() return false end
portraitEvent("PLAYER_TARGET_CHANGED")
assert(f.raceIcon.texture == path .. "-native" and not f.portraitUnit)
IsUnitModelReadyForUI = function() return true end
portraitEvent("UNIT_PORTRAIT_UPDATE", "target")
assert(f.raceIcon.texture == "current-face" and not f.archivedPortrait)
units.target = {guid="Player-42-000000F2"}
portraitEvent("PLAYER_TARGET_CHANGED")
assert(f.raceIcon.texture == "current-face" and not f.portraitUnit)
GL.ShowLedger(record.key)
assert(not f.archivedPortrait and f.raceIcon.texture == "face:" .. record.guid, "recycled rows restore the exact previously observed face")
f:Hide()
units.target = {guid=saved.guid}
SetPortraitTexture = function(texture, unit) texture:SetTexture("closed-book:" .. UnitGUID(unit)) end
portraitEvent("UNIT_MODEL_CHANGED", "target")
units.target, GrudgeLedgerPortraitIndex = nil, nil
GL.ShowLedger(saved.key)
assert(f.raceIcon.texture == "closed-book:" .. saved.guid and rowFor(saved.key).raceIcon.texture == f.raceIcon.texture,
    "both the detail pane and the list can reuse a portrait last seen while the book was closed")
local original = f.raceIcon.texture
f:Hide()
local dossier = CreateFrame("Frame", nil, UIParent)
dossier.raceIcon = dossier:CreateTexture(nil, "ARTWORK")
dossier.classIcon = dossier:CreateTexture(nil, "OVERLAY")
GL.PaintBookPortrait(dossier, saved)
assert(dossier.livePortraitGUID == saved.guid and dossier.raceIcon.texture == original,
    "a different page borrows the off-screen Journal's exact face after the target leaves")
dossier:Hide()
GL.ShowLedger(saved.key)
assert(f.raceIcon.texture == original and rowFor(saved.key).raceIcon.texture == original,
    "both journal portraits are restored after leaving the dossier")
-- A name-only archive carries numeric race and sex even before a native encounter.
local realProfile = GL.ArmoryProfile
GL.ArmoryProfile = function() return {identity={raceID=1,sex=3,classFile="WARLOCK"}} end
C_Texture = {GetAtlasInfo=function(atlas) return knownAtlas[atlas] and {} end}
knownAtlas["raceicon128-human-female"] = true
GL.PaintBookPortrait(dossier,{fullName="Unknown Dealer"})
assert(dossier.raceIcon.texture==GL.icon and not dossier.archivedPortrait,
    "a verified identity alone is not a saved portrait")
GL.ArmoryProfile = realProfile
-- An offline contact gets an in-game, equipped approximation, even if an old
-- catalog still contains a signed web head. A saved native face is the 2D fallback.
assert(loadfile(TEST_ROOT.."/DossierEquipment.lua"))("GrudgeLedger")
local dressed, cached={},false
function methods:ClearModel() self.loadedDisplay=nil end
function methods:SetDisplayInfo(id) self.requested=id end
function methods:SetUnit(unit) self.unitSet=unit; self.loadedDisplay=110; return true end
function methods:GetDisplayInfo() return self.loadedDisplay end
function methods:GetModelFileID() return self.loadedDisplay and 400 end
function methods:SetPortraitZoom(zoom) self.zoom=zoom end
function methods:TryOn(link) dressed[link]=true end
function methods:Undress() dressed={} end
C_Item={IsItemDataCachedByID=function(id) return id~=9 or cached end,RequestLoadItemDataByID=function(id) assert(id==9) end}
GetCurrentRegion=function() return 3 end
local contact={fullName="Donor Sample", guid="Player-42-00001ABC", raceID=1, sex=3}
local profile={identity={name=contact.fullName,raceID=1,sex=3},region="eu",characterHex="1abc",avatarHex="1abc",avatarKey=contact.guid,
    gear={head=1,shoulder=2}}
GrudgeLedgerArmory={items={{id=9},{id=11}},profiles={[contact.guid]=profile}}
GrudgeLedgerPortraitIndex={[contact.guid]="armory:1abc"}
GL.PaintBookPortrait(dossier,contact)
local headshot=dossier.headshot
assert(headshot.requested==3977 and not dossier.archivedPortrait and not dossier.reconstructedPortrait)
headshot.loadedDisplay=3851
headshot.scripts.OnModelLoaded(headshot)
assert(not dossier.reconstructedPortrait,"an old orc load must never draw over a human record")
headshot.loadedDisplay=headshot.requested
headshot.scripts.OnModelLoaded(headshot)
assert(dossier.reconstructedPortrait and headshot.zoom==1 and dressed["item:11"] and not dressed["item:9"], "animate while a helmet streams")
cached=true
headshot.scripts.OnEvent(headshot,"ITEM_DATA_LOAD_RESULT",9,true)
assert(dossier.reconstructedPortrait and dressed["item:9"] and dressed["item:11"])
GrudgeLedgerNativePortraits={[contact.guid]=true}
GL.PaintBookPortrait(dossier,contact)
headshot.scripts.OnModelLoaded(headshot)
assert(dossier.archivedPortrait=="native" and dossier.reconstructedPortrait and headshot:IsShown()
    and dossier.raceIcon.alpha==0, "loaded 3D takes priority over an archived 2D face")
units.target={guid=contact.guid}
local savedContact=GL.IdentityFromName("Donor", "Sample", contact.guid)
savedContact.race,savedContact.raceID,savedContact.sex="Human",contact.raceID,contact.sex
GL.Remember(savedContact)
GL.ObservePortrait("target")
GL.PaintBookPortrait(dossier,contact)
assert(dossier.portraitUnit=="target" and dossier.liveModelPortrait and headshot.unitSet=="target" and not dossier.reconstructedPortrait)
units.target={guid="Player-42-FFFF"}
headshot.scripts.OnModelLoaded(headshot)
assert(not dossier.liveModelPortrait, "a recycled token cannot complete a live portrait for the previous character")
units.target=nil
GL.PaintBookPortrait(dossier,contact)
headshot.scripts.OnModelLoaded(headshot)
assert(dossier.livePortraitGUID==contact.guid and not dossier.reconstructedPortrait
    and dossier.raceIcon.alpha==1, "while 3D loads, the observed 2D face remains visible")
headshot.loadedDisplay=headshot.requested
headshot.scripts.OnModelLoaded(headshot)
assert(dossier.reconstructedPortrait and headshot:IsShown() and dossier.raceIcon.alpha==0,
    "outside range the loaded 3D reconstruction replaces the cached 2D face")
-- The list and detail use this same priority, including after spirit release.
dossier:Hide()
GL.ShowLedger(contact.key or ("guid:"..contact.guid))
portraitEvent("PLAYER_DEAD")
portraitEvent("PLAYER_ALIVE")
portraitEvent("PLAYER_ENTERING_WORLD")
local retained=assert(rowFor("guid:"..contact.guid))
for _, slot in ipairs({f,retained}) do
    slot.headshot.loadedDisplay=slot.headshot.requested
    slot.headshot.scripts.OnModelLoaded(slot.headshot)
    assert(slot.livePortraitGUID==contact.guid and slot.raceIcon.alpha==0
        and slot.reconstructedPortrait and slot.headshot:IsShown(),
        "3D priority in list/detail: "..tostring(slot.livePortraitGUID).."/"..tostring(slot.raceIcon.alpha)
            .."/"..tostring(slot.reconstructedPortrait).."/"..tostring(slot.headshot:IsShown()))
end
local mannequin=GL.MannequinDisplay
GL.MannequinDisplay=function() end
GL.PaintBookPortrait(dossier,contact)
headshot.scripts.OnModelLoaded(headshot)
assert((dossier.livePortraitGUID==contact.guid or dossier.archivedPortrait=="native")
    and dossier.raceIcon.alpha==1 and not headshot:IsShown(),
    "without a compatible 3D model the saved 2D portrait is used")
GL.PaintBookPortrait(dossier,{fullName="No Portrait",faction="Horde",class="MAGE"})
headshot.scripts.OnModelLoaded(headshot)
assert(dossier.raceIcon.texture==GL.icon and dossier.raceIcon.alpha==1 and not headshot:IsShown(),
    "without 3D or a saved portrait, show the book and never a stale model")
GL.MannequinDisplay=mannequin
profile.alias="name:donor sample"
GrudgeLedgerArmory.profiles={["eu:"..profile.alias]=profile}
contact.guid=nil
GL.PaintBookPortrait(dossier,contact)
headshot.loadedDisplay=headshot.requested
headshot.scripts.OnModelLoaded(headshot)
assert(dossier.reconstructedPortrait and not dossier.archivedPortrait,"name-only contacts use the same in-game preview")
profile.gear={}
GL.PaintBookPortrait(dossier,contact)
assert(dossier.reconstructedPortrait and not next(dressed), "a new contact needs no helmet or shoulders to animate")
print("PASS identity UI: filters, pagination, identity merge, historical guilds, recycled portraits, live appearance events, invisible or restricted units, persisted identity only")
