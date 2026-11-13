-- The same persisted records are displayed in two clients without rewriting their evidence.
local receipt = { kind = "trade", evidence = "Donné : 1 po 2 pa 3 pc, Étoffe ×4\nReçu : Silex 2 po" }
local pet = { kind = "death", evidence = "Le familier de ce joueur vous a porté le coup fatal." }
local combat = { kind = "aggression", evidence = "Journal de combat : dégâts reçus de ce joueur hostile (SWING_DAMAGE)." }
local emote = { kind = "reputation", source = "emote", evidence = "Geste amical envoyé : /wink" }
local manual = { kind = "reputation", source = "manual", evidence = emote.evidence }
assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
for _, lang in ipairs({
    { "enUS", "Gave: 1 gold 2 silver 3 copper, Étoffe ×4\nReceived: Silex 2 po", "pet", "Friendly emote", "Combat log" },
    { "esES", "Entregado: 1 oro 2 plata 3 cobre, Étoffe ×4\nRecibido: Silex 2 po", "mascota", "Gesto amistoso", "Registro de combate" },
}) do
    GetLocale = function() return lang[1] end
    local private = {}
    for _, file in ipairs({"Locales.lua", "Core.lua", "Tracker.lua", "Trades.lua"}) do
        assert(loadfile(TEST_ROOT .. "/" .. file))("GrudgeLedger", private)
    end
    local render = GrudgeLedger.LocalizeEvidence
    assert(render(receipt) == lang[2] and render(pet):find(lang[3], 1, true))
    assert(render(emote) == lang[4] .. (lang[1] == "enUS" and " sent: /wink" or " enviado: /wink"))
    assert(render(combat):find(lang[5], 1, true) and render(combat):find("(SWING_DAMAGE)", 1, true))
    assert(render(manual) == emote.evidence and render({kind="note", evidence="Ami"}) == "Ami")
    assert(render({kind="trade"}) == nil and render({kind="death",evidence="Custom evidence"}) == "Custom evidence")
end
assert(receipt.evidence == "Donné : 1 po 2 pa 3 pc, Étoffe ×4\nReçu : Silex 2 po")
print("PASS localized evidence: historical records, readable combat and gestures, item and note preservation")
