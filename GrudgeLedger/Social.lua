-- Observe only this client's outgoing built-in emote requests, never other players' chat.
-- Blizzard's ChatFrameEditBox and ChatFrameMenuButton call C_ChatInfo.PerformEmote;
-- its documented arguments are (emoteName, targetName?, suppressMoveError?).
-- https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua
-- https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua
local GL = GrudgeLedger
local gestures = {
    KISS = 1, WINK = 1, HUG = 1, WAVE = 1, THANK = 1, BOW = 1,
    SALUTE = 1, CHEER = 1, APPLAUD = 1, SMILE = 1, LOVE = 1,
    COMFORT = 1, PAT = 1, SOOTHE = 1,
    RUDE = -1, INSULT = -1, TAUNT = -1, MOCK = -1, SPIT = -1,
    SLAP = -1, GLARE = -1, ANGRY = -1, FROWN = -1, BOO = -1, SNUB = -1,
}
local recentGestures, installed, sending = {}, nil, false

local function explicitTarget(target)
    -- Token arguments (as used by existing Forever addons) must still resolve to players.
    if target == "target" or target == "mouseover" or target == "focus"
        or target:match("^party%d+$") or target:match("^raid%d+$") or target:match("^nameplate%d+$") then
        return GL.Identity(target)
    end
    -- Never fall back to the selected player when a different recipient was specified.
    -- A bare first name is ambiguous on Forever; only an exact full name is accepted.
    local wanted = target:lower()
    local found, ambiguous
    local function consider(unit)
        unit = GL.Clean(unit, "string")
        local identity = unit and GL.Identity(unit)
        if identity and identity.surname and identity.fullName:lower() == wanted then
            if found and found.key ~= identity.key then ambiguous = true else found = identity end
        end
    end
    consider("target") consider("mouseover") consider("focus")
    for i = 1, 4 do consider("party" .. i) end
    for i = 1, 40 do consider("raid" .. i) end
    local plates = C_NamePlate and GL.Safe(C_NamePlate.GetNamePlates)
    if type(plates) == "table" then
        for _, plate in ipairs(plates) do
            local unit = GL.Clean(plate.namePlateUnitToken, "string")
                or (plate.UnitFrame and GL.Clean(plate.UnitFrame.unit, "string"))
            if unit then consider(unit) end
        end
    end
    if not ambiguous then return found end
end

local function recordGesture(token, identity)
    local delta = gestures[token]
    if not delta or not identity then return end
    local now = GL.Clean(GL.Safe(GetTimePreciseSec), "number")
        or GL.Clean(GL.Safe(GetTime), "number") or GL.Now()
    -- ponytail: retain only 30 seconds of outgoing opinions. Record references keep
    -- GUID promotion stable; sentiment windows also absorb legacy/modern dual hooks.
    for record, times in pairs(recentGestures) do
        for sentiment, at in pairs(times) do
            if now < at or now - at >= 30 then times[sentiment] = nil end
        end
        if not next(times) then recentGestures[record] = nil end
    end
    local record = GL.Get(identity)
    if record and recentGestures[record] and recentGestures[record][delta] then return end
    -- A secure post-hook exposes arguments, not the server's delivery/recipient response.
    -- This records the outgoing gesture intent, never a confirmed reaction by the other player.
    local reason = (delta > 0 and "Geste amical envoyé : /" or "Geste négatif envoyé : /") .. token:lower()
    record = GL.AdjustReputation(identity, delta, reason, "emote")
    if record then
        recentGestures[record] = recentGestures[record] or {}
        recentGestures[record][delta] = now
    end
end

local function outgoing(emoteName, targetName)
    if sending or not GL.db or not GL.Settings().socialTracking then return end
    emoteName = GL.Clean(emoteName, "string")
    if not emoteName then return end
    local token = emoteName:upper()
    if not gestures[token] then return end
    -- A secret target argument is not equivalent to an omitted one.
    local cleanedTarget = GL.Clean(targetName, "string")
    if cleanedTarget == nil and type(targetName) ~= "nil" then return end
    targetName = cleanedTarget
    if targetName then targetName = targetName:match("^%s*(.-)%s*$") end
    local identity
    if not targetName or targetName == "" then identity = GL.Identity("target")
    elseif targetName:lower() ~= "none" then identity = explicitTarget(targetName) end
    recordGesture(token, identity)
end

function GL.SendGesture(token)
    if token ~= "KISS" and token ~= "SPIT" then return false end
    local identity = GL.Identity("target")
    if not identity then GL.Print("Sélectionne un joueur pour lui envoyer ce geste.") return false end
    if not GL.Settings().socialTracking then GL.Print("Active « Avis via mes émotes » dans les réglages.") return false end
    local modern = C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function"
    local perform = modern and C_ChatInfo.PerformEmote or DoEmote
    if type(perform) ~= "function" then GL.Print("Les émotes ne sont pas disponibles sur ce client.") return false end
    -- Match the native bare /kiss or /spit: "" uses the selected unit. The literal
    -- "target" is a character NAME to this API, not a unit token (Forever full names too).
    -- The native Forever chat parser treats a truthy return as RESTRICTED, despite
    -- generated API docs calling it "success". Legacy DoEmote has no such contract.
    -- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua
    sending = true -- Suppress our hooks until rejection is known; preserve the clicked identity.
    local ok, restricted = pcall(perform, token, "")
    sending = false
    local publicResult = GL.Clean(restricted)
    if not ok or (modern and (publicResult == nil and type(restricted) ~= "nil" or publicResult)) then
        GL.Print("Le jeu a refusé le geste. Aucun avis ajouté.") return false
    end
    recordGesture(token, identity)
    return true
end

GL.On("READY", function()
    if installed then return end
    installed = true
    if type(hooksecurefunc) ~= "function" then
        GL.Debug("Les gestes sortants ne sont pas disponibles : hooksecurefunc absent.")
        return
    end
    if C_ChatInfo and type(C_ChatInfo.PerformEmote) == "function" then
        local ok, err = pcall(hooksecurefunc, C_ChatInfo, "PerformEmote", outgoing)
        if not ok then GL.Debug("Gestes sortants : " .. tostring(err)) end
    end
    if type(DoEmote) == "function" then
        local ok, err = pcall(hooksecurefunc, "DoEmote", outgoing)
        if not ok then GL.Debug("Gestes hérités : " .. tostring(err)) end
    end
end)
