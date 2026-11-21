-- Guild vision (0.49.0, completed in 0.50.0): the fights of the guild, shared.
-- A member who ticks "Vision de guilde" tells the guild each of their victories and deaths: where
-- (map and place), when, and against whom. They see those of the members who ticked it too: on the
-- map of fights, and as a "Tueur de guilde" alert when they meet a player who killed a member.
-- It is one short message a fight, never a journal: a guild of a hundred stays light, on the wire
-- and in the saved file (150 members at most, 40 fights each). A member who joins or ticks the box
-- asks once and receives what the guild knows: each member answers with their own fights, and one
-- of them passes on those of absent members. Nothing is sent, and nothing received is kept, while
-- the box is unticked. Unticking asks the guild to forget your fights.
local GL = GrudgeLedger
local M = {}
GL.GuildMap = M
local DAY = 86400
local KEEP = 38 * DAY -- like the other guild events
local PER_MEMBER = 40 -- fights kept for one member, the latest
local MEMBERS = 150 -- members kept at once
local RELAYED = 120 -- fights of other members passed on to a member who asks
local ASK_GAP = 30 -- seconds between two answers to the same member

local function guid(text)
    return type(text) == "string" and #text <= 32 and text:match("^Player%-%w+%-%w+$") ~= nil
end
local function whole(text, low, high)
    local n = tonumber(text)
    return n and n == math.floor(n) and n >= low and n <= high and n or nil
end
local function plainName(text)
    return type(text) == "string" and #text <= 48 and not text:find(";", 1, true) and not GL.ContainsControlOrMarkup(text)
end
local function UI_plain(text)
    return GL.UITheme and GL.UITheme.plain and (GL.UITheme.plain(text)) or tostring(text)
end
local function scope()
    if not GL.Bounties or not GL.Bounties.GuildScope then return nil end
    return GL.Bounties.GuildScope()
end
-- On unless the member unticked the box (0.51.0).
local function on(s, me)
    return type(s) == "table" and not (type(s.shareMap) == "table" and s.shareMap[me] == false)
end
-- One fight, as kept and as sent: time, map, x and y in thousandths, d (death) or k (victory),
-- then the opponent (identifier and name, either may be empty).
local function line(at, map, x, y, kind, target, name)
    return table.concat({ at, map, x, y, kind, target or "", name or "" }, ";")
end
-- Reads a fight back. Anything malformed, in the future or too old is refused.
local function read(text)
    if type(text) ~= "string" or #text > 140 then return nil end
    local at, map, x, y, kind, target, name = text:match("^(%d+);(%d+);(%d+);(%d+);([dk]);([^;]*);([^;]*)$")
    at, map, x, y = whole(at, 1, GL.Now() + 60), whole(map, 1, 999999), whole(x, 0, 1000), whole(y, 0, 1000)
    if not (at and map and x and y) or at < GL.Now() - KEEP then return nil end
    if (target ~= "" and not guid(target)) or not plainName(name) then return nil end
    return at, map, x, y, kind, target, name
end
-- Who killed members of the guild, worked out once and again only when the fights change.
local index, indexed
-- The guild's fights change only when one is kept or forgotten: until then the sorted list is
-- given again as it is (a guild of a hundred holds up to 6 000 lines).
local version, sorted = 0, {}
local function forgetIndex()
    index, indexed = nil, nil
    version = version + 1
end
-- Keeps a member's fight: the latest first, one a second, a bounded number. False when it was
-- already known or too old to enter the list.
local function keep(s, actor, text)
    local at = read(text)
    if not at then return false end
    s.places = type(s.places) == "table" and s.places or {}
    local list = s.places[actor]
    if type(list) ~= "table" then
        -- A full table drops the member heard longest ago.
        local count, oldest, oldestAt = 0, nil, nil
        for other, theirs in pairs(s.places) do
            count = count + 1
            local latest = type(theirs) == "table" and read(theirs[1]) or 0
            local mine = GL.Bounties and GL.Bounties.GuildScope and select(2, GL.Bounties.GuildScope()) == other
            if not mine and (not oldestAt or latest < oldestAt) then
                oldest, oldestAt = other, latest
            end
        end
        if count >= MEMBERS and oldest then s.places[oldest] = nil end
        list = {}
        s.places[actor] = list
    end
    local position = #list + 1
    for i, known in ipairs(list) do
        local other = read(known) or 0
        if other == at then return false end
        if other < at then
            position = i
            break
        end
    end
    if position > PER_MEMBER then return false end
    table.insert(list, position, text)
    for i = #list, PER_MEMBER + 1, -1 do list[i] = nil end
    forgetIndex()
    return true
end
local function message(actor, text)
    return "M;1;" .. actor .. ";" .. text
end
-- Answers a member who asks. "full" (a member ticked the box): your own fights at once, then the
-- relay. A login (0.58.0): only the relay, so that a guild of a hundred does not answer a hundred
-- times. The relay holds the latest fights of everyone, yours included; it leaves after a random
-- delay and is dropped when another member started one first. Sent behind the urgent messages.
local function answer(s, me, full)
    local T = GL.Transport
    local own = {}
    for _, text in ipairs(full and type(s.places) == "table" and type(s.places[me]) == "table" and s.places[me] or {}) do
        if read(text) then own[#own + 1] = message(me, text) end
    end
    local sent = false
    if #own > 0 and not T.State(s, "map:own") then sent = T.SendBatch(s, own, { key = "map:own", delay = 2 + math.random(0, 8) }) == true end
    local others = {}
    for actor, list in pairs(type(s.places) == "table" and s.places or {}) do
        if (actor ~= me or not full) and guid(actor) and type(list) == "table" then
            for _, text in ipairs(list) do
                local at = read(text)
                if at then others[#others + 1] = { at = at, text = "R;" .. message(actor, text) } end
            end
        end
    end
    if #others == 0 or T.State(s, "map:relay") then return sent end
    table.sort(others, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return a.text < b.text
    end)
    local relayed = {}
    for i = 1, math.min(RELAYED, #others) do relayed[i] = others[i].text end
    return T.SendBatch(s, relayed, { key = "map:relay", delay = 4 + math.random(0, 16) }) == true or sent
end
-- Your latest fights from your own journal, so that ticking the box shows something at once.
local function seed(s, me)
    local found = {}
    for _, record in pairs(GL.db and GL.db.players or {}) do
        for _, e in ipairs(type(record) == "table" and type(record.history) == "table" and record.history or {}) do
            if type(e) == "table" and not e.voided and (e.kind == "kill" or e.kind == "death") and type(e.time) == "number"
                and type(e.mapID) == "number" and type(e.mapX) == "number" and type(e.mapY) == "number" and e.time >= GL.Now() - KEEP then
                found[#found + 1] = { event = e, record = record }
            end
        end
    end
    table.sort(found, function(a, b) return a.event.time > b.event.time end)
    for i = 1, math.min(PER_MEMBER, #found) do
        local e, record = found[i].event, found[i].record
        local name = record.fullName or record.name
        keep(s, me, line(e.time, e.mapID, math.floor(e.mapX * 1000 + 0.5), math.floor(e.mapY * 1000 + 0.5), e.kind == "death" and "d" or "k",
            guid(record.guid) and record.guid or "", plainName(name) and name or ""))
    end
end
-- A guild catch-up brings hundreds of fights in a few seconds: the open pages are drawn again
-- once every fifth of a second at most, not once per fight.
local refreshing = false
local function refresh()
    if not (GL.RelationsPages and GL.RelationsPages.Refresh) then return end
    if not (C_Timer and C_Timer.After) then GL.RelationsPages.Refresh() return end
    if refreshing then return end
    refreshing = true
    C_Timer.After(0.2, function()
        refreshing = false
        GL.RelationsPages.Refresh()
    end)
end

-- Once the guild is known: your latest fights are made ready for the members who will ask, and
-- the player is told once, in the chat, that the addon shares with the guild and where to stop it.
local ready = {}
function M.Join()
    local s, me = scope()
    if type(s) ~= "table" then return false end
    -- Once per guild, not once per account: another character may be in another guild.
    if not s.noticed then
        s.noticed = GL.Now()
        GL.Print(GL.L("Grudge Ledger partage avec votre guilde vos victoires, vos morts (avec l’endroit), vos repérages et vos avis. "
            .. "Pour arrêter : options, pages Relations et Alertes, et la case « Vision de guilde » de la carte."))
    end
    if not on(s, me) or ready[s] then return false end
    ready[s] = true
    seed(s, me)
    return true
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
    forgetIndex()
    if enabled == true then
        seed(s, me)
        answer(s, me, true)
        GL.Transport.Send(s, "MQ")
    else
        -- Nothing is kept while the box is unticked, and the guild is asked to forget yours.
        s.places = nil
        GL.Transport.Cancel(s, "map:own")
        GL.Transport.Cancel(s, "map:relay")
        GL.Transport.Send(s, "MX")
    end
    refresh()
    return true
end
-- A victory ("k") or a death ("d") of yours, just now, against this player: it goes to the guild.
function M.Fight(kind, target, name)
    local s, me = scope()
    if not on(s, me) or (kind ~= "d" and kind ~= "k") or not C_Map then return false end
    if GL.Safe(IsInInstance) == true then return false end
    local map = GL.Clean(GL.Safe(C_Map.GetBestMapForUnit, "player"), "number")
    local position = map and GL.Safe(C_Map.GetPlayerMapPosition, map, "player")
    local x, y
    if type(position) == "table" and type(position.GetXY) == "function" then x, y = GL.Safe(position.GetXY, position) end
    x, y = GL.Clean(x, "number"), GL.Clean(y, "number")
    if not (x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1) or not whole(map, 1, 999999) then return false end
    target = guid(target) and target or ""
    local record = target ~= "" and GL.Get and GL.Get("guid:" .. target)
    name = type(record) == "table" and (record.fullName or record.name) or name
    local text = line(GL.Now(), map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5), kind, target, plainName(name) and name or "")
    if not keep(s, me, text) then return false end
    GL.Transport.Send(s, message(me, text))
    return true
end
-- A guild message about fights. The sender is a member of the roster, checked by the caller.
-- A fight heard from its own author is trusted as theirs. A fight passed on by another member
-- ("relay") is guild testimony, like every relay: it fills the map of a member who was away, and
-- never brings back the fights of a member who asked to be forgotten.
local asked = {}
function M.Receive(s, me, sender, raw, relay)
    if type(s) ~= "table" or not guid(sender) or sender == me or type(raw) ~= "string" then return false end
    if raw == "MX" then
        if relay then return false end
        s.mapForgot = type(s.mapForgot) == "table" and s.mapForgot or {}
        s.mapForgot[sender] = GL.Now()
        if type(s.places) == "table" and s.places[sender] then
            s.places[sender] = nil
            forgetIndex()
            refresh()
        end
        return true
    end
    -- You see the guild's fights only while you show yours.
    if not on(s, me) then return false end
    if raw == "MQ" then
        if relay then return false end
        M.CatchUp(s, me, sender, true)
        return true
    end
    local actor, rest = raw:match("^M;1;([^;]+);(.+)$")
    if not guid(actor) or actor == me then return false end
    local forgot = type(s.mapForgot) == "table" and s.mapForgot[actor]
    if relay then
        -- Only the fights of a member of the guild, well formed and not forgotten, are kept; then
        -- another member is passing the guild's fights on, and ours would only repeat them.
        local at = read(rest)
        if not at or (forgot and at <= forgot) or not (GL.Bounties and GL.Bounties.IsMember and GL.Bounties.IsMember(actor)) then return false end
        GL.Transport.Cancel(s, "map:relay")
    elseif actor ~= sender then
        return false
    elseif forgot then
        s.mapForgot[actor] = nil
    end
    if not keep(s, actor, rest) then return false end
    refresh()
    return true
end
-- A member asked what the guild knows: MQ when ticking the box ("full"), Q at login (the relay).
function M.CatchUp(s, me, sender, full)
    if not on(s, me) then return end
    local now = GL.Now()
    if sender and asked[sender] and now - asked[sender] < ASK_GAP then return end
    -- An answer that had nothing to say does not use up the member's turn.
    if answer(s, me, full) and sender then asked[sender] = now end
end

-- Versions (0.58.0): each member tells the guild which version of the addon it runs, at login, and
-- answers a newcomer once every ten seconds at most. A member heard from without a version runs one older
-- than 0.58.0. Kept in memory only, never saved.
local versions, heard, warned, answered = {}, {}, {}, {}
local function numbers(value)
    local a, b, c = tostring(value):match("^(%d+)%.(%d+)%.?(%d*)")
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end
local function older(value, than)
    local a, b, c = numbers(value)
    local x, y, z = numbers(than)
    if a ~= x then return a < x end
    if b ~= y then return b < y end
    return c < z
end
local function memberName(id)
    return GL.Bounties and GL.Bounties.MemberName and GL.Bounties.MemberName(id) or GL.L("Un membre de la guilde")
end
-- GLV: "I arrive, here is my version". GLVR: the answer of a member already there.
function M.Announce(s, reply)
    if type(s) ~= "table" or type(GL.version) ~= "string" or not GL.version:match("^%d+%.%d+") then return false end
    GL.Transport.Send(s, (reply and "GLVR;" or "GLV;") .. GL.version)
    return true
end
-- Any guild message of the addon: its sender runs Grudge Ledger. Without a version a minute later,
-- it runs one older than 0.58.0, and the player is told once.
function M.Heard(sender)
    if not guid(sender) or heard[sender] then return end
    heard[sender] = GL.Now()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(60, function()
            if versions[sender] or warned[sender] then return end
            warned[sender] = true
            GL.Print(GL.L("%s utilise une version de Grudge Ledger antérieure à la 0.58 : une partie des échanges de guilde ne lui parvient pas.")
                :format(UI_plain(memberName(sender))))
        end)
    end
end
function M.Version(s, me, sender, value, relay, reply)
    if relay or not guid(sender) or sender == me or type(value) ~= "string" or #value > 16 or not value:match("^%d+%.%d+[%.%d]*$") then
        return false
    end
    heard[sender] = heard[sender] or GL.Now()
    versions[sender] = value
    -- A member arriving learns the versions of the others: each answers it once every ten seconds at most.
    -- An answer is never answered, so the guild does not echo.
    if not reply and GL.Now() - (answered[sender] or 0) >= 10 then
        answered[sender] = GL.Now()
        M.Announce(s, true)
    elseif not reply and not answered["later:" .. sender] and C_Timer and C_Timer.After then
        -- A second arrival within ten seconds (two /reload): answered once, a little later, instead of
        -- never; otherwise the member believes everyone runs an old version (review 0.58.5).
        answered["later:" .. sender] = true
        C_Timer.After(10, function()
            answered["later:" .. sender] = nil
            answered[sender] = GL.Now()
            M.Announce(s, true)
        end)
    end
    if older(value, GL.version) and not warned[sender] then
        warned[sender] = true
        GL.Print(GL.L("%s utilise une ancienne version de Grudge Ledger (%s, la vôtre : %s) : une partie des échanges de guilde ne lui parvient pas.")
            :format(UI_plain(memberName(sender)), value, GL.version))
    elseif older(GL.version, value) and not warned.self then
        warned.self = true
        GL.Print(GL.L("Votre guilde utilise une version plus récente de Grudge Ledger (%s). Pensez à mettre à jour."):format(value))
    end
    refresh()
    return true
end
-- The members heard this session: how many run your version or a newer one, out of how many.
function M.Versions()
    local current, total = 0, 0
    for sender in pairs(heard) do
        total = total + 1
        if versions[sender] and not older(versions[sender], GL.version) then current = current + 1 end
    end
    return current, total
end
-- The guild's fights, the latest first: who, when, which map, where (0 to 1), death or kill, and
-- against whom. Yours are left out (the map reads them in your journal) unless asked for.
function M.Points(withMine)
    local s, me = scope()
    local points = {}
    if not on(s, me) or type(s.places) ~= "table" then return points end
    -- Kept a quarter of an hour at most: fights older than 38 days leave the list on their own.
    local key = tostring(s) .. (withMine and ":all:" or ":others:") .. version .. ":" .. math.floor(GL.Now() / 900)
    if sorted[withMine and 1 or 2] and sorted[withMine and 1 or 2].key == key then return sorted[withMine and 1 or 2].points end
    for actor, list in pairs(s.places) do
        if (withMine or actor ~= me) and guid(actor) and type(list) == "table" then
            for i = 1, math.min(PER_MEMBER, #list) do
                local at, map, x, y, kind, target, name = read(list[i])
                if at then
                    points[#points + 1] = { actor = actor, mine = actor == me or nil, time = at, mapID = map, x = x / 1000, y = y / 1000,
                        kind = kind == "d" and "death" or "kill", target = target ~= "" and target or nil, name = name ~= "" and name or nil }
                end
            end
        end
    end
    table.sort(points, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.actor < b.actor
    end)
    sorted[withMine and 1 or 2] = { key = key, points = points }
    return points
end
-- Whether this player killed members of the guild: how many deaths, and the latest one (which
-- member, when, on which map). Your own deaths are your journal's business, not counted here.
function M.Killer(target)
    local s, me = scope()
    if not guid(target) or not on(s, me) or type(s.places) ~= "table" then return nil end
    if indexed ~= s or not index then
        index, indexed = {}, s
        for actor, list in pairs(s.places) do
            if actor ~= me and guid(actor) and type(list) == "table" then
                for _, text in ipairs(list) do
                    local at, map, _, _, kind, victim, name = read(text)
                    if at and kind == "d" and victim ~= "" then
                        local entry = index[victim] or { deaths = 0, time = 0 }
                        index[victim] = entry
                        entry.deaths = entry.deaths + 1
                        if at > entry.time then
                            entry.time, entry.actor, entry.mapID, entry.name = at, actor, map, name ~= "" and name or nil
                        end
                    end
                end
            end
        end
    end
    return index[target]
end
