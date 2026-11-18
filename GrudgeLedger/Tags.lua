-- Personal social labels follow the journal identity, independently of PvP and guild contracts.
local GL = GrudgeLedger
local L = GL.L
GL.TagChoices = {
    { "ninja", "Butin ninja" }, { "boosted", "Joueur boosté" }, { "leaver", "Départ anticipé" },
    { "toxic", "Comportement toxique" }, { "griefing", "Sabotage" }, { "reliable", "Fiable" },
}
local labels = {}
for _, choice in ipairs(GL.TagChoices) do labels[choice[1]] = L(choice[2]) end

function GL.HasTag(record, id)
    if not record or type(record.tags) ~= "table" then return false end
    if id then return labels[id] ~= nil and record.tags[id] == true end
    for key in pairs(labels) do if record.tags[key] == true then return true end end
    return false
end

function GL.TagText(record)
    if not record or type(record.tags) ~= "table" then return nil end
    local values = {}
    for _, choice in ipairs(GL.TagChoices) do
        if GL.HasTag(record, choice[1]) then values[#values + 1] = labels[choice[1]] end
    end
    return #values > 0 and table.concat(values, ", ") or nil
end

function GL.MergeTags(provisional, record)
    for _, change in ipairs(provisional.tagHistory or {}) do
        record.tagHistory = record.tagHistory or {}
        record.tagHistory[#record.tagHistory+1] = change
    end
    for id in pairs(labels) do
        if GL.HasTag(provisional, id) then
            record.tags = type(record.tags) == "table" and record.tags or {}
            record.tags[id] = true
        end
    end
    if type(provisional.tagRemindedAt) == "table" then
        record.tagRemindedAt = type(record.tagRemindedAt) == "table" and record.tagRemindedAt or {}
        for me, at in pairs(provisional.tagRemindedAt) do
            if type(me) == "string" and type(at) == "number" and at >= 0 and at < math.huge then
                record.tagRemindedAt[me] = math.max(at, tonumber(record.tagRemindedAt[me]) or 0)
            end
        end
    end
end

function GL.ToggleTag(identity, id)
    if not labels[id] then return false end
    local actor, name, account = GL.Author()
    if not actor then return false end
    local record = GL.Remember(identity, true)
    if not record then return false end
    record.tags = type(record.tags) == "table" and record.tags or {}
    record.tags[id] = record.tags[id] ~= true or nil
    local enabled = record.tags[id] == true
    record.tagHistory = record.tagHistory or {}
    record.tagHistory[#record.tagHistory+1] = { id=id, enabled=enabled, actorGUID=actor, actorName=name, account=account, time=GL.Now() }
    if GL.GuildProfiles then GL.GuildProfiles.PersonalTag(record,id,enabled) end
    if not next(record.tags) then record.tags, record.tagRemindedAt = nil, nil end
    GL.Emit("CHANGED", record, "tags")
    return true
end

local function reminder(record, me)
    local tags = GL.TagText(record)
    if not tags then return end
    local now = GL.Now()
    record.tagRemindedAt = type(record.tagRemindedAt) == "table" and record.tagRemindedAt or {}
    local last = record.tagRemindedAt[me]
    if type(last) == "number" and now >= last and now - last < 600 then return end
    record.tagRemindedAt[me] = now
    return tags
end

local frame = CreateFrame("Frame")
local present = {}
local inWorld, baseline = false, false
frame:RegisterEvent("PARTY_INVITE_REQUEST")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEAVING_WORLD")
frame:SetScript("OnEvent", function(_, event, first, ...)
    if event == "PLAYER_LEAVING_WORLD" then inWorld = false return end
    if event == "PLAYER_ENTERING_WORLD" then
        inWorld = true
        if first == true or (...) == true then baseline = true end
    end
    if not inWorld or not GL.db or not GL.Settings().tagReminders or GL.IsPvPInstance() then return end
    local me = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if not me then return end
    if event == "PARTY_INVITE_REQUEST" then
        -- Forever puts inviterGUID eighth, after isCrossShard and allowMultipleRoles.
        local identity = GL.IdentityFromName(first, nil, select(7, ...))
        local record = identity and GL.Get(identity)
        local tags = not present[record] and reminder(record, me)
        if tags then GL.Print(L("Invitation de %s — %s"):format(record.fullName, tags)) end
        return
    end
    local size = GL.Clean(GL.Safe(GetNumGroupMembers), "number")
    if not size then return end
    local raid = GL.Safe(IsInRaid) == true
    local current, joined, identified = {}, {}, 0
    for i = 1, size > 0 and (raid and math.min(40, size) or 4) or 0 do
        local unit = (raid and "raid" or "party") .. i
        local identity = GL.Identity(unit, true)
        if identity then
            identified = identified + 1
            local record = GL.Get(identity)
            if GL.HasTag(record) and not current[record] then
                current[record] = true
                if not baseline and not present[record] then
                    local tags = reminder(record, me)
                    if tags then joined[#joined + 1] = record.fullName .. " (" .. tags .. ")" end
                end
            end
        end
    end
    if identified < size - 1 then
        for record in pairs(present) do current[record] = true end
    else
        -- Roster members can appear one by one at login. Their first complete
        -- roster forms the baseline, including after an interface reload.
        baseline = false
    end
    present = current
    if #joined > 0 then GL.Print(L("Dans votre groupe : %s"):format(table.concat(joined, " · "))) end
end)
