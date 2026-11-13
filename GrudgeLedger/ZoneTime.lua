-- Optional connected, non-AFK time in the open world. Never store positions.
local GL = GrudgeLedger
local frame = CreateFrame("Frame")
local inWorld, since, actor, zone, ticker
local day = 86400
local checked = setmetatable({}, { __mode = "k" })

local function validNumber(n)
    return type(n) == "number" and n >= 0 and n < math.huge
end

local function validate(entry)
    if checked[entry] then return end
    checked[entry] = true
    if type(entry.years) ~= "table" then entry.years = {} end
    for year, places in pairs(entry.years) do
        if type(year) ~= "string" or not year:match("^%d%d%d%d$") or type(places) ~= "table" then
            entry.years[year] = nil
        else
            for place, seconds in pairs(places) do
                if type(place) ~= "string" or place == "" or not validNumber(seconds) then places[place] = nil end
            end
        end
    end
    if not validNumber(entry.clippedAt) then entry.clippedAt = nil end
    local visits = {}
    if type(entry.recent) == "table" then
        for _, v in pairs(entry.recent) do
            if type(v) == "table" and type(v[1]) == "string" and v[1] ~= "" and validNumber(v[2])
                and validNumber(v[3]) and v[3] > v[2] then
                visits[#visits + 1] = v
            else entry.clippedAt = GL.Now() end
        end
        table.sort(visits, function(a, b) return a[3] < b[3] end)
    elseif entry.recent ~= nil then entry.clippedAt = GL.Now() end
    entry.recent = visits
end

local function addAnnual(years, year, place, seconds)
    years[year] = years[year] or {}
    years[year][place] = (years[year][place] or 0) + seconds
end

local function record(a, z, start, finish)
    local year, endYear = GL.Safe(date, "%Y", start), GL.Safe(date, "%Y", finish - 1)
    if not year or not endYear or not tonumber(year) or not tonumber(endYear) then return end
    local data = GL.db.zoneExposure
    if type(data) ~= "table" then data = {} GL.db.zoneExposure = data end
    local entry = data[a]
    if type(entry) ~= "table" then entry = {years = {}, recent = {}} data[a] = entry end
    validate(entry)
    if year ~= endYear then
        -- Locate local New Year using the same calendar as Journal periods.
        local lo, hi = start, finish
        while hi - lo > 1 do
            local mid = math.floor((hi + lo) / 2)
            if date("%Y", mid) == year then lo = mid else hi = mid end
        end
        addAnnual(entry.years, year, z, hi - start)
        addAnnual(entry.years, endYear, z, finish - hi)
    else addAnnual(entry.years, year, z, finish - start) end

    local recent = entry.recent
    local last = recent[#recent]
    if last and last[1] == z and last[3] == start then last[3] = finish
    else recent[#recent + 1] = {z, start, finish} end
    -- ponytail: merge contiguous sessions, cap the rolling window per character;
    -- annual totals stay exact. Mark a truncated rolling window as a lower bound.
    if #recent > 2048 or recent[1][3] <= finish - 30 * day then
        local cut = #recent > 2048 and 128 or 0
        while recent[cut + 1] and recent[cut + 1][3] <= finish - 30 * day do cut = cut + 1 end
        entry.clippedAt = math.max(entry.clippedAt or 0, recent[cut][3])
        for i = 1, #recent do recent[i] = recent[i + cut] end
    end
end

local function update()
    if not GL.db then return end
    local now = GL.Now()
    -- A missed heartbeat (suspend/disconnect) cannot establish presence.
    if actor and now > since and now - since <= 90 then record(actor, zone, since, now) end
    since, actor, zone = now, nil, nil
    if not inWorld or not GL.Settings().zoneTime then return end
    local inside, kind = GL.Safe(IsInInstance)
    if inside ~= false or kind ~= "none" or GL.Safe(UnitIsAFK, "player") ~= false
        or GL.Safe(UnitIsConnected, "player") ~= true then return end
    local guid, place = GL.Clean(GL.Safe(UnitGUID, "player"), "string"), GL.Where()
    if guid and guid:match("^Player%-%w") and place ~= "?" and place ~= "" then actor, zone = guid, place end
end

local function configure()
    update()
    if inWorld and GL.Settings().zoneTime then
        if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(60, update) end
    elseif ticker then ticker:Cancel() ticker = nil end
end

frame:SetScript("OnEvent", function(_, e, unit)
    if e == "PLAYER_FLAGS_CHANGED" or e == "UNIT_CONNECTION" then
        if unit and unit ~= "player" then return end
    elseif e == "PLAYER_ENTERING_WORLD" then inWorld = true
    elseif e == "PLAYER_LEAVING_WORLD" or e == "PLAYER_LOGOUT" then inWorld = false end
    configure()
end)
for _, e in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_FLAGS_CHANGED", "UNIT_CONNECTION"}) do GL.Safe(frame.RegisterEvent, frame, e) end
GL.On("SETTINGS", configure)

function GL.ZoneTimes(options)
    options = options or {}
    if actor then update() end
    local totals, partial = {}, false
    local guid, now = GL.Clean(GL.Safe(UnitGUID, "player"), "string"), GL.Now()
    local span = options.period == "week" and 7 * day or options.period == "month" and 30 * day
    local year = options.period == "year" and tostring(options.year or GL.Safe(date, "%Y", now))
    for key, entry in pairs(type(GL.db.zoneExposure) == "table" and GL.db.zoneExposure or {}) do
        if type(entry) == "table" and (key == guid and (options.scope or "character") == "character" or options.scope == "all") then
            validate(entry)
            if span then
                local from = now - span
                if (entry.clippedAt or 0) > from then partial = true end
                for _, visit in ipairs(entry.recent) do
                    local seconds = math.min(now, visit[3]) - math.max(from, visit[2])
                    if seconds > 0 then totals[visit[1]] = (totals[visit[1]] or 0) + seconds end
                end
            else
                for when, zones in pairs(entry.years) do
                    if not year or year == when then
                        for place, seconds in pairs(zones) do totals[place] = (totals[place] or 0) + seconds end
                    end
                end
            end
        end
    end
    return totals, partial
end
