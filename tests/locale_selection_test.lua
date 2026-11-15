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
-- Parity alone misses a newly added source string absent from both catalogs.
for line in io.lines(TEST_ROOT .. "/GrudgeLedger.toc") do
    local name=line:match("^%s*(.-%.lua)%s*$")
    if name and name ~= "Locales.lua" then
        local file=assert(io.open(TEST_ROOT.."/"..name))
        local source=file:read("*a")
        file:close()
        for key in source:gmatch('%f[%w_]M?L%(%s*"([^"\\]*)"%s*%)') do
            assert(english[key],name..": missing localized text "..key)
        end
    end
end
print("PASS client language selection, language fallback, catalog parity and format arguments")

-- Load a fresh copy of the real TOC for each client. Exercise visible buttons,
-- runtime data, and a failed command, which dictionary parity alone cannot check.
local words = {
    fr = {"À chasser", "Créer la prime", "Tête", "Réputations de factions", "Caractéristiques", "Butin ninja", "Aucun envoi incertain à vérifier."},
    en = {"To hunt", "Post bounty", "Head", "Faction reputations", "Attributes", "Ninja looting", "No uncertain mail to check."},
    es = {"Por cazar", "Publicar recompensa", "Cabeza", "Reputación de facciones", "Atributos", "Robo de botín", "No hay envíos pendientes de verificación."},
}
for locale, lang in pairs({frFR="fr", enUS="en", enGB="en", esES="es", esMX="es", deDE="en"}) do
    local e=setmetatable({}, {__index=_G})
    e._G=e
    e.GetLocale=function() return locale end
    e.loadfile=function(path) return setfenv(assert(loadfile(path)), e) end
    local mock=e.loadfile(TEST_WORK.."/tests/addon_mock.lua")()
    local GL, expected=e.GrudgeLedger, words[lang]
    local f=GL.OpenBounties()
    assert(f.activeTab:GetText()==expected[1] and f.form.publish:GetText()==expected[2],locale.." bounty")
    local identity=GL.Identity("target")
    assert(GL.ToggleTag(identity,"ninja"))
    assert(GL.TagText(GL.Get(identity))==expected[6],locale.." tags")
    assert(GL.OpenPlayerDossier(identity.guid))
    local dossier=e.GrudgeLedgerPlayerDossier
    assert(dossier.equipment.equipment.buttons[1].slotName==expected[3],locale.." item slot")
    assert(dossier.tabs.reputation:GetText()==expected[4] and dossier.statHeading:GetText()==expected[5],locale.." dossier")
    assert(not dossier.bounty:IsShown(),locale.." ally should not offer a bounty")
    e.SlashCmdList.GLBOUNTY(lang=="es" and "correo enviado" or lang=="en" and "mail sent" or "courrier envoye")
    assert(mock.messages[#mock.messages]:find(expected[7],1,true),locale.." mail message: "..mock.messages[#mock.messages])
    assert(#GL.errors==0,locale.." runtime error")
end
print("PASS localized bounty controls, private tags, dossier, and mailbox reconciliation across six real TOC loads")
