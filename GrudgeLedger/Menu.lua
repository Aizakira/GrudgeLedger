-- Menu API integration adapted from Worth Remembering by Kyle (GPL-3.0).
-- Direct relations and one-step reputation changes share the same player record.
local GL = GrudgeLedger
local L = GL.L
if not (Menu and Menu.ModifyMenu) then return end

local tags = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
    "MENU_UNIT_PARTY", "MENU_UNIT_RAID", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND",
    "MENU_UNIT_FRIEND_OFFLINE", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_WOW_MEMBER", "MENU_UNIT_GUILD", "MENU_UNIT_GUILD_OFFLINE",
    "MENU_UNIT_CHAT_ROSTER",
}

local function fromName(full, suffix, guid)
    full = GL.Clean(full, "string")
    suffix = GL.Clean(suffix, "string")
    guid = GL.Clean(guid, "string")
    if not full or full == "" then return nil end
    local first, last = full:match("^(%S+)%s+(.+)$")
    if first then full, suffix = first, last end
    local mine = GL.Clean(GL.Safe(UnitGUID, "player"), "string")
    if guid and mine and guid == mine then return nil end
    return GL.IdentityFromName(full, suffix, guid)
end

local function fromContext(data)
    data = GL.Clean(data, "table")
    if not data then return nil end
    local unit = GL.Clean(data.unit, "string")
    if unit and unit ~= "" then return GL.Identity(unit) end
    local lineID = GL.Clean(data.lineID, "number")
    if lineID and C_ChatInfo then
        local sender = GL.Safe(C_ChatInfo.GetChatLineSenderName, lineID)
        local guid = GL.Safe(C_ChatInfo.GetChatLineSenderGUID, lineID)
        local identity = fromName(sender, nil, guid)
        if identity then return identity end
    end
    return fromName(data.name, GL.Clean(data.surname, "string") or GL.Clean(data.server, "string"), data.guid)
end

local function onMenu(_, root, data)
    if not GL.db then return end
    local identity = fromContext(data)
    if not identity then return end
    -- Freeze the identity: changing targets while this menu is open must never
    -- apply an opinion to the newly targeted player.
    local captured = {}
    for k, v in pairs(identity) do captured[k] = v end
    local known = GL.Get(identity)
    if not captured.guild and not GL.Clean(data.unit, "string") and known then captured.guild, captured.realm = known.guild, known.realm end
    root:CreateDivider()
    root = root:CreateButton("Grudge Ledger")
    for _, choice in ipairs({ { "Ami", "friend" }, { "Méfiance", "warning" }, { "Ennemi", "enemy" }, { "Automatique", "neutral" } }) do
        local relation = choice[2]
        local entry = root:CreateButton(L(choice[1]), function() GL.SetReaction(captured, relation) end)
        if entry.AddInitializer then
            entry:AddInitializer(function(b)
                if not b.AttachTexture or not b.fontString then return end
                local icon = b:AttachTexture()
                icon:SetTexture("Interface\\AddOns\\GrudgeLedger\\Media\\Relation" .. relation:gsub("^%l", string.upper))
                icon:SetSize(16, 16)
                icon:SetPoint("RIGHT", -3, 0)
                return b.fontString:GetUnboundedStringWidth() + 42, 22
            end)
        end
    end
    root:CreateButton(L("Avis positif (+1)"), function() GL.AdjustReputation(captured, 1, "Avis personnel", "manual") end)
    root:CreateButton(L("Avis négatif (-1)"), function() GL.AdjustReputation(captured, -1, "Avis personnel", "manual") end)
    root:CreateButton(L("Ajouter une note"), function() GL.EditNote(captured) end)
    root:CreateButton(L("Ouvrir la fiche"), function()
        local record = GL.Remember(captured)
        if record then GL.ShowLedger(record.key) end
    end)
    if captured.guild then
        root:CreateDivider()
        root = root:CreateButton(L("Guilde"))
        for _, choice in ipairs({ { "Guilde : amie", "friend" }, { "Guilde : méfiance", "warning" }, { "Guilde : ennemie", "enemy" }, { "Guilde : neutre", "neutral" } }) do
            local reaction = choice[2]
            root:CreateButton(L(choice[1]), function() GL.SetGuildReaction(captured, reaction) end)
        end
        root:CreateButton(L("Guilde : gérer / ajouter une note"), function() GL.ShowGuilds(captured) end)
    end
end

for _, tag in ipairs(tags) do
    local ok, err = pcall(Menu.ModifyMenu, tag, onMenu)
    if not ok then GL.Debug(L("Menu %s : %s"):format(tag, tostring(err))) end
end
