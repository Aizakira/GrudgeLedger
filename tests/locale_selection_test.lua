-- Use the WoW addon loader contract. A client allocates at most one dictionary.
local function catalog(locale)
    local context = {}
    local chunk = assert(loadfile(TEST_ROOT .. "/Locales.lua"))
    setfenv(chunk, { GetLocale = function() return locale end })
    chunk("GrudgeLedger", context)
    return context.translations
end

local english, spanish = catalog("enUS"), catalog("esES")
assert(not catalog("frFR"))
local function placeholders(text)
    local args = {}
    for item in text:gmatch("%%[-+ #0%d%.]*[cdiouxXeEfgGqs%%]") do args[#args + 1] = item end
    return table.concat(args, ",")
end
for _, pair in ipairs({{english, spanish}, {spanish, english}, {english, catalog("enGB")},
                       {spanish, catalog("esMX")}, {english, catalog("deDE")}}) do
    for key, translation in pairs(pair[1]) do
        assert(pair[2][key] and #translation > 0, key)
        assert(placeholders(key) == placeholders(translation), key .. ": invalid placeholders")
    end
end
assert(english["Ennemi"] == "Enemy" and spanish["Ennemi"] == "Enemigo")
assert(catalog("enGB")["Ennemi"] == "Enemy" and catalog("deDE")["Ennemi"] == "Enemy")
assert(catalog("esMX")["Ennemi"] == "Enemigo")
print("PASS client language selection, language fallback, catalog parity and format arguments")
