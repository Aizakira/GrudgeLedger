-- Guild vision of the map of fights (0.49.0).
-- A member who ticks "Vision de guilde" tells the guild where each of their victories and deaths
-- happened (map, place, kind, time) and sees those of the members who ticked it too. It is one
-- short message a fight, never a journal: a guild of a hundred stays light, on the wire and in the
-- saved file (150 members at most, 40 places each). Nothing is sent, and nothing received is kept,
-- while the box is unticked. Unticking asks the guild to forget your places.
local GL = GrudgeLedger
local M = {}
GL.GuildMap = M
local DAY = 86400
local KEEP = 38 * DAY -- like the other guild events
local PER_MEMBER = 40 -- places kept for one member, the latest
local MEMBERS = 150 -- members kept at once
local REPLAYED = 15 -- of your own places, sent again when a member asks
local ASK_GAP = 30 -- seconds between two answers to the same member

local function guid(text)
    return type(text) == "string" and #text <= 32 and text:match("^Player%-%w+%-%w+$") ~= nil
end
local function whole(text, low, high)
    local n = tonumber(text)
    return n and n == math.floor(n) and n >= low and n <= high and n or nil
end
local function scope()
    if not GL.Bounties or not GL.Bounties.GuildScope then return nil end
    return GL.Bounties.GuildScope()
end
local function on(s, me)
    return type(s) == "table" and type(s.shareMap) == "table" and s.shareMap[me] == true
end
-- One place, as kept and as sent: time, map, x and y in thousandths, d (death) or k (victory).
local function line(at, map, x, y, kind)
    return table.concat({ at, map, x, y, kind }, ";")
end
-- Reads a place back. Anything malformed, in the future or too old is refused.
local function read(text)
    if type(text) ~= "string" or #text > 64 then return nil end
    local at, map, x, y, kind = text:match("^(%d+);(%d+);(%d+);(%d+);([dk])$")
    at, map, x, y = whole(at, 1, GL.Now() + 60), whole(map, 1, 999999), whole(x, 0, 1000), whole(y, 0, 1000)
    if not (at and map and x and y) or at < GL.Now() - KEEP then return nil end
    return at, map, x, y, kind
end
-- Keeps a member's place: the latest first, one a second, a bounded number. False when it was
-- already known or too old to enter the list.
local function keep(s, actor, at, map, x, y, kind)
    s.places = type(s.places) == "table" and s.places or {}
    local list = s.places[actor]
    if type(list) ~= "table" then
        -- A full table drops the member heard longest ago.
        local count, oldest, oldestAt = 0, nil, nil
        for other, theirs in pairs(s.places) do
            count = count + 1
            local latest = type(theirs) == "table" and read(theirs[1]) or 0
            if not oldestAt or latest < oldestAt then
                oldest, oldestAt = other, latest
            end
        end
        if count >= MEMBERS and oldest then s.places[oldest] = nil end
        list = {}
        s.places[actor] = list
    end
    local position = #list + 1
    for i, text in ipairs(list) do
        local other = read(text) or 0
        if other == at then return false end
        if other < at then
            position = i
            break
        end
    end
    if position > PER_MEMBER then return false end
    table.insert(list, position, line(at, map, x, y, kind))
    for i = #list, PER_MEMBER + 1, -1 do list[i] = nil end
    return true
end
local function message(actor, text)
    return "M;1;" .. actor .. ";" .. text
end
-- Your own latest places, sent again: to a member who just ticked the box or just logged in.
local function replay(s, me)
    local list = type(s.places) == "table" and s.places[me]
    for i = 1, math.min(REPLAYED, type(list) == "table" and #list or 0) do
        if read(list[i]) then GL.Transport.Send(s, message(me, list[i])) end
    end
end
-- Your latest fights from your own journal, so that ticking the box shows something at once.
local function seed(s, me)
    local found = {}
    for _, record in pairs(GL.db and GL.db.players or {}) do
        for _, e in ipairs(type(record) == "table" and type(record.history) == "table" and record.history or {}) do
            if type(e) == "table" and not e.voided and (e.kind == "kill" or e.kind == "death") and type(e.time) == "number"
                and type(e.mapID) == "number" and type(e.mapX) == "number" and type(e.mapY) == "number" and e.time >= GL.Now() - KEEP then
                found[#found + 1] = e
            end
        end
    end
    table.sort(found, function(a, b) return a.time > b.time end)
    for i = 1, math.min(REPLAYED, #found) do
        local e = found[i]
        keep(s, me, e.time, e.mapID, math.floor(e.mapX * 1000 + 0.5), math.floor(e.mapY * 1000 + 0.5), e.kind == "death" and "d" or "k")
    end
end
local function refresh()
    if GL.RelationsPages and GL.RelationsPages.Refresh then GL.RelationsPages.Refresh() end
end

-- Whether the box is ticked for this character, and whether there is a guild at all.
function M.Enabled()
    local s, me = scope()
    return on(s, me), type(s) == "table"
end
function M.Enable(enabled)
    local s, me = scope()
    if type(s) ~= "table" then return false end
    s.shareMap = type(s.shareMap) == "table" and s.shareMap or {}
    s.shareMap[me] = enabled == true
    if enabled == true then
        seed(s, me)
        replay(s, me)
        GL.Transport.Send(s, "MQ")
    else
        -- Nothing is kept while the box is unticked, and the guild is asked to forget yours.
        s.places = nil
        GL.Transport.Send(s, "MX")
    end
    refresh()
    return true
end
-- A victory ("k") or a death ("d") of yours, just now: its place goes to the guild.
function M.Fight(kind)
    local s, me = scope()
    if not on(s, me) or (kind ~= "d" and kind ~= "k") or not C_Map then return false end
    if GL.Safe(IsInInstance) == true then return false end
    local map = GL.Clean(GL.Safe(C_Map.GetBestMapForUnit, "player"), "number")
    local position = map and GL.Safe(C_Map.GetPlayerMapPosition, map, "player")
    local x, y
    if type(position) == "table" and type(position.GetXY) == "function" then x, y = GL.Safe(position.GetXY, position) end
    x, y = GL.Clean(x, "number"), GL.Clean(y, "number")
    if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) or not whole(map, 1, 999999) then return false end
    local at, px, py = GL.Now(), math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
    if not keep(s, me, at, map, px, py, kind) then return false end
    GL.Transport.Send(s, message(me, line(at, map, px, py, kind)))
    return true
end
-- A guild message about places. The sender is a member of the roster, checked by the caller. A
-- place is only accepted from the member it is about: relays are refused.
local asked = {}
function M.Receive(s, me, sender, raw, relay)
    if relay or type(s) ~= "table" or not guid(sender) or sender == me or type(raw) ~= "string" then return false end
    if raw == "MX" then
        if type(s.places) == "table" and s.places[sender] then
            s.places[sender] = nil
            refresh()
        end
        return true
    end
    -- You see the guild's fights only while you show yours.
    if not on(s, me) then return false end
    if raw == "MQ" then
        local now = GL.Now()
        if asked[sender] and now - asked[sender] < ASK_GAP then return false end
        asked[sender] = now
        replay(s, me)
        return true
    end
    local actor, rest = raw:match("^M;1;([^;]+);(.+)$")
    if actor ~= sender then return false end
    local at, map, x, y, kind = read(rest)
    if not at or not keep(s, actor, at, map, x, y, kind) then return false end
    refresh()
    return true
end
-- A member asked for a catch-up at login (message Q): your latest places go with the rest.
function M.CatchUp(s, me)
    if on(s, me) then replay(s, me) end
end
-- The guild's fights, the latest first: who, when, which map, where (0 to 1), death or kill.
function M.Points()
    local s, me = scope()
    local points = {}
    if not on(s, me) or type(s.places) ~= "table" then return points end
    for actor, list in pairs(s.places) do
        if actor ~= me and guid(actor) and type(list) == "table" then
            for i = 1, math.min(PER_MEMBER, #list) do
                local at, map, x, y, kind = read(list[i])
                if at then
                    points[#points + 1] = { actor = actor, time = at, mapID = map, x = x / 1000, y = y / 1000,
                        kind = kind == "d" and "death" or "kill" }
                end
            end
        end
    end
    table.sort(points, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.actor < b.actor
    end)
    return points
end
