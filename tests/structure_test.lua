-- Structure guard rails. These checks read the source files; they never run the addon.
-- Rules and their reasons: AGENTS.md ("Structure rules"). Fix the code, never the check.
-- A frozen list below records today's exceptions. A list may only shrink.

local function read(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local text = file:read("*a")
    file:close()
    -- Drop the UTF-8 byte order mark some editors add.
    return (text:gsub("^\239\187\191", ""))
end

local function addonFiles()
    local files = {}
    for line in read(TEST_ROOT .. "/GrudgeLedger.toc"):gmatch("[^\r\n]+") do
        local name = line:match("^%s*([%w_]+%.lua)%s*$")
        if name then
            files[#files + 1] = name
        end
    end
    assert(#files > 0, "the TOC lists no Lua file")
    return files
end

-- Source with comments removed and string contents emptied, line breaks kept.
-- Protocol strings such as "S1;P;" would otherwise look like several statements.
local function codeOnly(text)
    local out, position, length = {}, 1, #text
    while position <= length do
        local start = text:find("[%-\"'%[]", position)
        if not start then
            out[#out + 1] = text:sub(position)
            break
        end
        out[#out + 1] = text:sub(position, start - 1)
        local character = text:sub(start, start)
        local longLevel = text:match("^%-%-%[(=*)%[", start) or text:match("^%[(=*)%[", start)
        if longLevel then
            local _, finish = text:find("]" .. longLevel .. "]", start, true)
            finish = finish or length
            out[#out + 1] = (text:sub(start, finish):gsub("[^\n]", ""))
            position = finish + 1
        elseif text:sub(start, start + 1) == "--" then
            position = text:find("\n", start, true) or length + 1
        elseif character == '"' or character == "'" then
            local cursor = start + 1
            while cursor <= length do
                local current = text:sub(cursor, cursor)
                if current == "\\" then
                    cursor = cursor + 2
                elseif current == character or current == "\n" then
                    break
                else
                    cursor = cursor + 1
                end
            end
            out[#out + 1] = character .. character
            position = cursor + 1
        else
            out[#out + 1] = character
            position = start + 1
        end
    end
    return table.concat(out)
end

local function sortedKeys(set)
    local keys = {}
    for key in pairs(set) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local files = addonFiles()
local source, code = {}, {}
for _, name in ipairs(files) do
    source[name] = read(TEST_ROOT .. "/" .. name)
    code[name] = codeOnly(source[name])
end

-- Rule 1: dependency direction. Core.lua emits events; it does not call other files.
-- Each name below is a call from Core.lua into a later file. Remove a name when the
-- call becomes an event (GL.Emit in Core.lua, GL.On in the other module).
local coreDebt = {
    Bounties = true, DruidRadarReport = true, GroupDuration = true, GuildProfiles = true,
    HasTag = true, IdentityLabels = true, InspectDossierUnit = true, LocalizeEvidence = true,
    MergeTags = true, ProbeResultText = true, SharedDossiers = true, TagText = true,
    VisiblePortraitUnit = true,
}
-- Fields set where the GrudgeLedger table is created.
local coreOwn = { errors = true, icon = true, minimapIcon = true }
for name in code["Core.lua"]:gmatch("function GL%.([%a_]+)") do
    coreOwn[name] = true
end
for name in code["Core.lua"]:gmatch("\n%s*GL%.([%a_]+)%s*=[^=]") do
    coreOwn[name] = true
end
local coreCalls = {}
for name in code["Core.lua"]:gmatch("%f[%w_]GL%.([%a_]+)") do
    if not coreOwn[name] then
        coreCalls[name] = true
    end
end
for _, name in ipairs(sortedKeys(coreCalls)) do
    assert(coreDebt[name], "Core.lua calls GL." .. name
        .. ", defined in another file. Emit an event from Core.lua and subscribe with GL.On instead.")
end
for _, name in ipairs(sortedKeys(coreDebt)) do
    assert(coreCalls[name], "Core.lua no longer calls GL." .. name
        .. ": remove it from coreDebt in tests/structure_test.lua.")
end

-- Rule 2: one door to the network. Addon messages go through the transport file only.
local doors = {
    SendAddonMessage = { ["Bounties.lua"] = true },
    RegisterAddonMessagePrefix = { ["Bounties.lua"] = true },
    CHAT_MSG_ADDON = { ["Bounties.lua"] = true },
    -- Visible chat written for the player (party warning) has its own single door.
    SendChatMessage = { ["Display.lua"] = true },
}
for token, allowed in pairs(doors) do
    for _, name in ipairs(files) do
        local used = source[name]:find(token, 1, true) ~= nil
        assert(not used or allowed[name], name .. " uses " .. token
            .. ". Hand the message to the transport module instead of talking to the game directly.")
    end
end

-- Rule 3: one answer for character data (value, source, provider, date).
-- Only these files may read the raw snapshots; the lists may only shrink.
local rawSnapshots = {
    ["armorySnapshot"] = { ["Core.lua"] = true },
    ["GrudgeLedgerArmory"] = { ["Core.lua"] = true, ["SharedDossiers.lua"] = true },
    [".inspection"] = { ["UI.lua"] = true, ["DossierInspect.lua"] = true, ["SharedDossiers.lua"] = true },
    [".dossiers"] = { ["SharedDossiers.lua"] = true },
    ["socialReports"] = { ["SharedDossiers.lua"] = true },
    ["sharedSource"] = { ["SharedDossiers.lua"] = true, ["PlayerDossier.lua"] = true },
}
for token, allowed in pairs(rawSnapshots) do
    for _, name in ipairs(files) do
        local used = code[name]:find(token, 1, true) ~= nil
        assert(not used or allowed[name], name .. " reads " .. token
            .. " directly. Ask the module that owns character snapshots instead.")
    end
    for name in pairs(allowed) do
        assert(code[name] and code[name]:find(token, 1, true), name .. " no longer reads " .. token
            .. ": remove it from rawSnapshots in tests/structure_test.lua.")
    end
end

-- Rule 4: readable code. One statement per line and lines of at most 160 characters.
-- Ceilings are today's counts: { lines with several statements, long lines }.
-- A file may improve, never get worse. A new file starts at { 0, 0 }.
local dataFiles = { ["Locales.lua"] = true, ["DossierTalentData.lua"] = true }
local ceilings = {
    ["Core.lua"] = { 4, 7 }, ["Tracker.lua"] = { 0, 4 }, ["Display.lua"] = { 2, 3 },
    ["NativePortrait.lua"] = { 1, 0 }, ["UI.lua"] = { 6, 83 }, ["Menu.lua"] = { 0, 1 },
    ["QuickGestures.lua"] = { 0, 1 }, ["MinimapProbe.lua"] = { 7, 2 }, ["DruidRadar.lua"] = { 0, 4 },
    ["Bounties.lua"] = { 29, 3 }, ["GuildProfiles.lua"] = { 2, 0 }, ["GuildProfilesUI.lua"] = { 12, 0 },
    ["DossierEquipment.lua"] = { 1, 0 }, ["DossierTalents.lua"] = { 11, 0 }, ["DossierInspect.lua"] = { 2, 0 },
    ["SharedDossiers.lua"] = { 30, 3 }, ["PlayerDossier.lua"] = { 39, 3 }, ["BountyUI.lua"] = { 93, 0 },
}
local function readability(name)
    local several, long = 0, 0
    for line in (code[name] .. "\n"):gmatch("([^\n]*)\n") do
        if line:find(";", 1, true) then
            several = several + 1
        end
    end
    for line in (source[name] .. "\n"):gmatch("([^\n]*)\n") do
        if #line > 160 then
            long = long + 1
        end
    end
    return several, long
end
for _, name in ipairs(files) do
    if not dataFiles[name] then
        local ceiling = ceilings[name] or { 0, 0 }
        local several, long = readability(name)
        assert(several <= ceiling[1], name .. ": " .. several .. " lines hold several statements (ceiling "
            .. ceiling[1] .. "). Write one statement per line.")
        assert(long <= ceiling[2], name .. ": " .. long .. " lines exceed 160 characters (ceiling "
            .. ceiling[2] .. "). Break the long lines.")
    end
end

-- Rule 5: saved data and guild messages stay documented in one place.
local document = read(TEST_WORK .. "/docs/protocole-et-sauvegarde.fr.md")
local function documented(word, what)
    assert(document:find("`" .. word .. "`", 1, true), what .. " `" .. word
        .. "` is missing from docs/protocole-et-sauvegarde.fr.md. Describe it there in the same change.")
end
local savedKeys = {}
for _, name in ipairs(files) do
    for key in code[name]:gmatch("%f[%w_]GL%.db%.([%a_]+)") do
        savedKeys[key] = true
    end
end
for _, key in ipairs(sortedKeys(savedKeys)) do
    documented(key, "Saved key")
end
local guildFields = {}
for _, name in ipairs({ "Bounties.lua", "GuildProfiles.lua", "SharedDossiers.lua" }) do
    for field in code[name]:gmatch("%f[%w_]s%.([%a_]+)") do
        guildFields[field] = true
    end
    for field in code[name]:gmatch("%f[%w_]j%.([%a_]+)") do
        guildFields[field] = true
    end
end
for _, field in ipairs(sortedKeys(guildFields)) do
    documented(field, "Guild field")
end
local eventKinds = {}
for kind in source["Bounties.lua"]:gmatch('kind==%"(%u)%"') do
    eventKinds[kind] = true
end
assert(next(eventKinds), "no bounty event kind found in Bounties.lua")
for _, kind in ipairs(sortedKeys(eventKinds)) do
    documented(kind, "Bounty event kind")
end

print("PASS structure: dependency direction, single network door, single snapshot owner, "
    .. "readability ceilings, saved data and guild messages documented")
