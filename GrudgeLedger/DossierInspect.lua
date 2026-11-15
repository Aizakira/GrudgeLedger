-- Capture what the client can see while the opponent still has a unit token.
local GL = GrudgeLedger
local recent, order = {}, {}
local pending, nextRequest = nil, 0
local events = CreateFrame("Frame")

local function stateFor(guid)
    if not recent[guid] then
        -- ponytail: at most 32 transient opponents. The journal owns recorded snapshots.
        if #order == 32 then recent[table.remove(order, 1)] = nil end
        order[#order + 1] = guid
        recent[guid] = {}
    end
    return recent[guid]
end

local function captureStats(unit)
    local stats = {}
    local function add(key, value)
        if type(value) == "number" and value > 0 then stats[key] = value end
    end
    add("HEALTH", GL.Safe(UnitHealthMax, unit))
    local power, token = GL.Safe(UnitPowerType, unit)
    if type(token) == "string" and power then add(token, GL.Safe(UnitPowerMax, unit, power)) end
    for i, key in ipairs({"STRENGTH", "AGILITY", "STAMINA", "INTELLECT"}) do
        local _, effective = GL.Safe(UnitStat, unit, i)
        add(key, effective)
    end
    local _, armor = GL.Safe(UnitArmor, unit)
    add("ARMOR", armor)
    return next(stats) and stats
end

local function publish(guid, state)
    local record = GL.Get("guid:" .. guid)
    if record and next(state.snapshot) then record.inspection = state.snapshot end
    GL.Emit("DOSSIER_UPDATED", guid)
end

local function readGear(unit)
    local gear, unresolved = {}, false
    for slot = 1, 19 do
        local link = GL.Safe(GetInventoryItemLink, unit, slot)
        if type(link) == "string" and link:match("|Hitem:%d+[^|]*|h%[") then
            gear[slot] = link
        elseif GL.Safe(GetInventoryItemID, unit, slot) or GL.Safe(GetInventoryItemTexture, unit, slot) then
            unresolved = true
        end
    end
    return next(gear) and gear, unresolved
end

function GL.InspectDossierUnit(unit, guid)
    if type(guid) ~= "string" or not guid:match("^Player%-") or not unit
        or GL.Safe(UnitGUID, unit) ~= guid or GL.Safe(UnitIsVisible, unit) ~= true or GL.IsPvPInstance() then return end
    local now = GL.Now()
    local state = stateFor(guid)
    local record = GL.Get("guid:" .. guid)
    state.snapshot = state.snapshot or (record and record.inspection) or {}
    local snapshot = state.snapshot
    if record and next(snapshot) then record.inspection = snapshot end
    if not state.statsRead or now - state.statsRead >= 60 then
        state.statsRead = now
        local stats = captureStats(unit)
        if stats then
            snapshot.stats = snapshot.stats or {}
            for key, value in pairs(stats) do snapshot.stats[key] = value end
            snapshot.statsAt = now
        end
        -- Some units already expose cached item links even when a new inspect is unavailable.
        local gear = not snapshot.gear and readGear(unit)
        if gear then snapshot.gear, snapshot.gearAt, snapshot.partialGear = gear, now, true end
        if stats or gear then publish(guid, state) end
    end
    if not NotifyInspect or now < (state.retryAt or 0)
        or (snapshot.gearAt and not snapshot.partialGear and snapshot.talentsAt and now - math.min(snapshot.gearAt, snapshot.talentsAt) < 300)
        or (pending and pending.guid == guid) then return end
    if pending or now < nextRequest then
        if not state.queued then
            state.queued = true
            C_Timer.After(2, function()
                state.queued = nil
                if recent[guid] == state then GL.InspectDossierUnit(unit, guid) end
            end)
        end
        return
    end
    state.retryAt = now + 1
    if (InspectFrame and InspectFrame:IsShown()) or (PlayerSpellsFrame and GL.Safe(PlayerSpellsFrame.IsInspecting, PlayerSpellsFrame))
        or GL.Safe(CanInspect, unit) ~= true
        or (CheckInteractDistance and GL.Safe(CheckInteractDistance, unit, 1) == false) then return end
    local request = {guid = guid, unit = unit, state = state}
    pending, nextRequest = request, now + 2
    state.attempts = (state.attempts or 0) + 1
    state.retryAt = now + (state.attempts < 3 and 3 or 30)
    if state.attempts >= 3 then state.attempts = 0 end
    if not pcall(NotifyInspect, unit) then pending = nil; return end
    GL.Emit("DOSSIER_UPDATED", guid)
    C_Timer.After(3, function()
        if pending ~= request then return end
        pending = nil
        GL.Emit("DOSSIER_UPDATED", guid)
        GL.InspectDossierUnit(unit, guid)
    end)
end

function GL.DossierInspection(record)
    local state = recent[record.guid]
    return record.inspection or (state and state.snapshot), pending and pending.guid == record.guid
end

GL.On("CHANGED", function(record, reason)
    if not record or not record.guid or reason == "deleted" then
        if record and reason == "deleted" and recent[record.guid] then
            recent[record.guid] = nil
            for i, guid in ipairs(order) do
                if guid == record.guid then table.remove(order, i); break end
            end
            if pending and pending.guid == record.guid then pending = nil end
        end
        return
    end
    local state = recent[record.guid]
    if state and state.snapshot and next(state.snapshot) then record.inspection = state.snapshot end
    if record.pvp and ((record.pvp.deaths or 0) > 0 or (record.pvp.kills or 0) > 0 or (record.pvp.aggressions or 0) > 0 or reason == "opening") then
        GL.InspectDossierUnit(GL.VisiblePortraitUnit(record), record.guid)
    end
end)

events:RegisterEvent("INSPECT_READY")
events:SetScript("OnEvent", function(_, _, guid)
    guid = GL.Clean(guid, "string")
    if not pending or pending.guid ~= guid then return end
    local request = pending
    local unit = request.unit
    if GL.Safe(UnitGUID, unit) ~= guid then unit = GL.VisiblePortraitUnit({guid = guid}) end
    if not unit or GL.Safe(UnitGUID, unit) ~= guid or not GL.Safe(UnitIsVisible, unit) or GL.IsPvPInstance() then return end
    pending = nil
    local state = request.state
    local snapshot, now = state.snapshot, GL.Now()
    local gear, unresolved = readGear(unit)
    if gear and (not unresolved or not snapshot.gear or snapshot.partialGear) then
        if unresolved and snapshot.gear then
            for slot, link in pairs(snapshot.gear) do gear[slot] = gear[slot] or link end
        end
        snapshot.gear, snapshot.gearAt, snapshot.partialGear = gear, now, unresolved or nil
        local level = GL.Safe(C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel, unit)
        if type(level) == "number" and level > 0 then snapshot.averageItemLevel = math.floor(level + .5) end
    end
    local _, class = GL.Safe(UnitClass, unit)
    local trees = GL.ReadInspectedTalents(class)
    if trees then snapshot.trees, snapshot.talentsAt = trees, now end
    if snapshot.gear and not snapshot.partialGear and trees then state.attempts = 0 end
    publish(guid, state)
    if unresolved or not gear or not trees then
        C_Timer.After(3, function()
            if recent[guid] == state then GL.InspectDossierUnit(unit, guid) end
        end)
    end
end)
