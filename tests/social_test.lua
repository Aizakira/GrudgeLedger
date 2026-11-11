local now = 1000
local units, frames, hooks = {}, {}, {}
local secret = setmetatable({}, { __eq = function() error("secret compared") end, __tostring = function() error("secret printed") end })
issecretvalue = function(v) return rawequal(v, secret) end
time = function() return math.floor(now) end
GetTime = function() return now end
GetRealZoneText = function() return "Hurlevent" end
UnitExists = function(unit) return units[unit] ~= nil end
UnitIsPlayer = function(unit) return units[unit] and units[unit].player ~= false end
UnitIsUnit = function(a, b) return units[a] and units[b] and units[a].guid == units[b].guid or false end
UnitName = function(unit) local u = units[unit]; if u then return u.name, u.surname end end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitClass = function() return "Mage", "MAGE" end
UnitFactionGroup = function(unit) return units[unit] and units[unit].faction or "Alliance" end
UnitLevel = function() return 34 end
CreateFrame = function()
    local frame = { events = {}, scripts = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    frames[#frames + 1] = frame
    return frame
end
local sent = 0
C_ChatInfo = { PerformEmote = function(emote, target, suppress)
    sent = sent + 1
    return true, "original return", suppress
end }
DoEmote = function(...) return C_ChatInfo.PerformEmote(...) end
-- Emulates post-hooks only; original arguments and return values are preserved.
hooksecurefunc = function(object, key, callback)
    if type(object) == "string" then callback, key, object = key, object, _G end
    local original = object[key]
    assert(type(original) == "function")
    hooks[#hooks + 1] = key
    object[key] = function(...)
        local result = { original(...) }
        callback(...)
        return unpack(result)
    end
end
C_NamePlate = { GetNamePlates = function() return { { namePlateUnitToken = "nameplate1" }, { namePlateUnitToken = "nameplate2" } } end }
units.player = { name = "Me", surname = "Self", guid = "Player-1-1" }
units.target = { name = "Friend", surname = "One", guid = "Player-1-11" }
units.mouseover = { name = "Other", surname = "Horde", guid = "Player-1-22", faction = "Horde" }
units.nameplate1 = units.mouseover
units.nameplate2 = { name = "Guard", surname = "NPC", guid = "Creature-1-33", player = false }
assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
local GL = GrudgeLedger
GL.InitDB()
local friend, other = GL.Identity("target"), GL.Identity("mouseover")
assert(loadfile(TEST_ROOT .. "/Social.lua"))()
GL.Emit("READY")
assert(#hooks == 2)
GL.Emit("READY")
assert(#hooks == 2, "ready re-entry must not install duplicate hooks")
local ok, originalReturn, suppress = DoEmote("KISS", nil, true)
assert(ok == true and originalReturn == "original return" and suppress == true and sent == 1)
local record = assert(GL.Get(friend))
assert(record.reputation == 1 and GL.Relation(record) == "friend")
assert(#record.history == 1 and record.history[1].source == "emote")
assert(record.history[1].evidence == "Geste amical envoyé : /kiss")
assert(not record.history[1].confidence, "gesture intent is never a confirmed recipient response")
-- Repeated positive gestures share one window, including different tokens/APIs.
DoEmote("KISS")
assert(record.reputation == 1 and #record.history == 1)
now = now + 0.5
C_ChatInfo.PerformEmote("wink", "")
assert(record.reputation == 1)
now = now + 1
C_ChatInfo.PerformEmote("RUDE")
assert(record.reputation == 0)

-- Explicit targets never silently fall back to whoever happens to be selected.
C_ChatInfo.PerformEmote("HUG", "Other Horde")
assert(GL.Get(other).reputation == 1 and record.reputation == 0)
C_ChatInfo.PerformEmote("THANK", "mouseover")
assert(GL.Get(other).reputation == 1)
C_ChatInfo.PerformEmote("INSULT", "Other Horde")
assert(GL.Get(other).reputation == 0)
local before = #record.history
for _, target in ipairs({ "Unknown Person", "Guard NPC", "none", "Friend", "Me Self" }) do
    C_ChatInfo.PerformEmote("KISS", target)
end
assert(#record.history == before)
assert(GL.Get(GL.IdentityFromName("Guard", "NPC")) == nil)

-- Two distinct GUIDs with the same full name are ambiguous, even if selected.
units.focus = { name = "Friend", surname = "One", guid = "Player-1-99" }
C_ChatInfo.PerformEmote("HUG", "Friend One")
assert(#record.history == before)
units.focus = nil

-- No callback subscribes to incoming text. Other players' emotes cannot create opinions.
for _, frame in ipairs(frames) do
    assert(not frame.events.CHAT_MSG_TEXT_EMOTE and not frame.events.CHAT_MSG_EMOTE)
end
assert(#record.history == before)

-- Identity is captured before adjustment listeners can change the target.
GL.On("CHANGED", function() units.target = units.mouseover end)
now = now + 30
C_ChatInfo.PerformEmote("WAVE")
assert(record.reputation == 1 and GL.Get(other).reputation == 0)
assert(units.target == units.mouseover)
now = now + 1
C_ChatInfo.PerformEmote("TAUNT")
assert(GL.Get(other).reputation == -1)
now = now + 1
C_ChatInfo.PerformEmote("INSULT")
assert(GL.Get(other).reputation == -1 and GL.Relation(GL.Get(other)) == "warning")

-- Self/NPC/no target/secret inputs, unrelated emotes and disabled tracking are ignored.
before = #GL.Get(other).history
units.target = units.player
C_ChatInfo.PerformEmote("KISS")
units.target = units.nameplate2
C_ChatInfo.PerformEmote("WINK")
units.target = nil
C_ChatInfo.PerformEmote("HUG")
units.target = units.mouseover
C_ChatInfo.PerformEmote(secret)
C_ChatInfo.PerformEmote("KISS", secret)
C_ChatInfo.PerformEmote("KISS", 10)
C_ChatInfo.PerformEmote("DANCE")
GL.SetSetting("socialTracking", false)
C_ChatInfo.PerformEmote("KISS")
assert(#GL.Get(other).history == before)
GL.SetSetting("socialTracking", true)
now = now + 30
C_ChatInfo.PerformEmote("HUG")
assert(#GL.Get(other).history == before + 1)

-- Exact 30-second boundary and long alternating bursts never bypass the window.
units.focus = { name = "Burst", surname = "Player", guid = "Player-1-burst" }
local burst = GL.Identity("focus")
local started = now
DoEmote("KISS", "focus")
local burstRecord = assert(GL.Get(burst))
now = started + 29.999
C_ChatInfo.PerformEmote("WINK", "focus")
assert(burstRecord.reputation == 1 and #burstRecord.history == 1)
now = started + 30
DoEmote("HUG", "focus")
assert(burstRecord.reputation == 2 and #burstRecord.history == 2)
for i = 1, 899 do
    now = started + 30 + i / 10
    if i % 2 == 0 then DoEmote("KISS", "focus") else C_ChatInfo.PerformEmote("WINK", "focus") end
end
assert(burstRecord.reputation == 4 and #burstRecord.history == 4, "long burst accepts only t=0,30,60,90")
now = started + 120
DoEmote("WAVE", "focus")
assert(burstRecord.reputation == 5 and #burstRecord.history == 5)
DoEmote("RUDE", "focus")
C_ChatInfo.PerformEmote("INSULT", "focus")
assert(burstRecord.reputation == 4 and #burstRecord.history == 6, "negative sentiment has its own window")

-- Manual adjustments remain unrestricted during the automatic cooldown.
GL.AdjustReputation(burst, 1, "Manual", "manual")
GL.AdjustReputation(burst, 1, "Manual", "manual")
C_ChatInfo.PerformEmote("THANK", "focus")
assert(burstRecord.reputation == 6 and #burstRecord.history == 8)

-- A name-only record gaining its GUID must not reset the same player's window.
units.focus = { name = "Provisional", surname = "Player" }
C_ChatInfo.PerformEmote("KISS", "focus")
local provisional = assert(GL.Get(GL.Identity("focus")))
units.focus.guid = "Player-1-promoted"
now = now + 1
DoEmote("WINK", "focus")
assert(GL.Get(GL.Identity("focus")) == provisional and provisional.reputation == 1)
now = now + 29
DoEmote("WINK", "focus")
assert(GL.Get(GL.Identity("focus")) == provisional and provisional.reputation == 2)
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS social: outgoing-only hooks, immutable identities, dual-hook dedup, 30-second sentiment windows/boundaries/bursts/promotion, unrestricted manual opinions, API returns, cross-faction explicit targets, ambiguity/NPC/self/secrets/opt-out")
