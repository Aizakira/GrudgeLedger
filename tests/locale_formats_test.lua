-- Every translation keeps the format codes of its French key, in the same order (25/11): a "%d"
-- turned into "%s", lost or moved would raise an error, or show a wrong number, only for the
-- players of that language, where no test of the French interface can see it.
local function load(file, locale)
    local private = {}
    local env = setmetatable({ GetLocale = function() return locale end }, { __index = _G })
    local chunk = assert(loadfile(TEST_WORK .. "/GrudgeLedger/" .. file))
    setfenv(chunk, env)
    -- The English table first, as the game loads it: deDE and ptBR write over it.
    if file ~= "Locales.lua" then
        local base = assert(loadfile(TEST_WORK .. "/GrudgeLedger/Locales.lua"))
        setfenv(base, env)
        base("GrudgeLedger", private)
    end
    chunk("GrudgeLedger", private)
    return private.translations or {}
end
local function codes(text)
    local list = {}
    for code in text:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*[cdiouxXeEfgGqs]") do list[#list + 1] = code end
    return table.concat(list, " ")
end
local checked, wrong = 0, {}
-- Enough values for the longest sentence (the radar report asks for eleven).
local ONES = {}
for i = 1, 30 do ONES[i] = 1 end
for _, case in ipairs({ { "Locales.lua", "esES" }, { "Locales.lua", "enUS" }, { "Locales_deDE.lua", "deDE" }, { "Locales_ptBR.lua", "ptBR" } }) do
    local file, locale = case[1], case[2]
    for key, value in pairs(load(file, locale)) do
        if type(key) == "string" and type(value) == "string" then
            checked = checked + 1
            if codes(key) ~= codes(value) then
                wrong[#wrong + 1] = locale .. ": " .. key .. " -> " .. value .. " [" .. codes(key) .. " / " .. codes(value) .. "]"
            end
            -- A lone "%" at the end, or one before a letter the format does not know, breaks format().
            local ok = pcall(string.format, (value:gsub("%%[%-%+ #0]*%d*%.?%d*[cdiouxX]", "%%d")
                :gsub("%%[%-%+ #0]*%d*%.?%d*[eEfgG]", "%%f"):gsub("%%[%-%+ #0]*%d*%.?%d*[qs]", "%%s")), unpack(ONES))
            if not ok and codes(key) ~= "" then wrong[#wrong + 1] = locale .. ": unusable format: " .. value end
        end
    end
end
-- The labels of the books' entries and of the Registre's sections go through a variable, out of
-- reach of the check on L("..."): each one must be in every language (owner, 25/11).
local source = assert(io.open(TEST_WORK .. "/GrudgeLedger/Relations.lua", "rb")):read("*a")
local books = source:match("local BOOKS = (%b{})")
assert(books, "the books of Relations.lua")
for _, case in ipairs({ { "Locales.lua", "esES" }, { "Locales.lua", "enUS" }, { "Locales_deDE.lua", "deDE" }, { "Locales_ptBR.lua", "ptBR" } }) do
    local table_ = load(case[1], case[2])
    local labels = 0
    for _ in books:gmatch('{ "%w+", "([^"]+)"') do labels = labels + 1 end
    assert(labels >= 12, "the menu labels were read: " .. labels)
    for label in books:gmatch('{ "%w+", "([^"]+)"') do
        if not table_[label] then wrong[#wrong + 1] = case[2] .. ": menu label without translation: " .. label end
    end
end
table.sort(wrong)
assert(#wrong == 0, #wrong .. " translations with other format codes:\n" .. table.concat(wrong, "\n", 1, math.min(#wrong, 25)))
assert(checked > 4000, "the four tables were read: " .. checked)
print(("PASS locale formats: %d translations keep their format codes, in order"):format(checked))
