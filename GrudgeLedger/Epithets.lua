-- Epithets (0.59.0): the archetypes and titles of the Bilan, and the nicknames of players. The rules
-- that choose a category stay in Recap.lua and CharacterInsights.lua; this file holds large pools
-- of names so that two friends, or two weeks, rarely read the same one. A name is drawn from a seed
-- (your identifier, the category, the period, the week; or the player's identifier): the same seed
-- always gives the same name, so a card never changes while you read it.
local GL = GrudgeLedger
local L = GL.L
local E = {}
GL.Epithets = E

local locale = GetLocale and GetLocale() or "frFR"
local language = "en"
if locale == "frFR" then
    language = "fr"
elseif locale == "esES" or locale == "esMX" then
    language = "es"
end

-- "de Tanaris", "d’Orgrimmar", "des Paluns", "du Bois de la Pénombre"; "del Valle"; "of the Barrens".
local ACCENTED = { ["À"] = true, ["Â"] = true, ["É"] = true, ["È"] = true, ["Ê"] = true, ["Î"] = true, ["Ô"] = true, ["Û"] = true }
local function vowel(name)
    return name:match("^[AEIOUYaeiouy]") ~= nil or ACCENTED[name:sub(1, 2)] == true
end
-- The game gives zone names without their article ("Vallée de Strangleronce"): the first word
-- says which one to use ("de la Vallée de Strangleronce", "du Bois de la Pénombre").
local FRENCH = {}
for word in ("Vallée Forêt Île Cité Côte Clairière Contrée Montagne Péninsule Grotte Mer Mine Baie Toundra Gorge Crête "
    .. "Fosse Citadelle Tour Ville Combe Lande Prairie Passe Arène Caverne Steppe Jungle Cascade Rive"):gmatch("%S+") do
    FRENCH[word] = "f"
end
for word in ("Bois Marais Désert Mont Val Pic Cratère Défilé Col Massif Fjord Lac Plateau Bassin Rivage Bourbier Port "
    .. "Canyon Repos Bastion Fort Temple Camp Village Donjon Sanctuaire Bosquet Gouffre Promontoire Littoral Hameau"):gmatch("%S+") do
    FRENCH[word] = "m"
end
for word in ("Terres Marches Hautes-terres Contreforts Maleterres Paluns Tarides Plaines Montagnes Îles Mille Steppes "
    .. "Collines Gorges Grottes Ruines Profondeurs Tréfonds"):gmatch("%S+") do
    FRENCH[word] = "p"
end
local SPANISH = {}
for word in ("Valle Bosque Pantano Desierto Monte Cráter Paso Lago Puerto Cañón Templo Campamento Pico Mar Fuerte"):gmatch("%S+") do
    SPANISH[word] = "del "
end
for word in ("Selva Montaña Costa Isla Ciudad Península Tierra Mina Bahía Cueva Ciénaga Playa Cumbre Garganta"):gmatch("%S+") do
    SPANISH[word] = "de la "
end
for word in ("Tierras Montañas Islas Estepas Colinas Ruinas Marismas"):gmatch("%S+") do
    SPANISH[word] = "de las "
end
for word in ("Picos Montes Baldíos Páramos Claros"):gmatch("%S+") do
    SPANISH[word] = "de los "
end
function E.Of(name)
    name = tostring(name or "")
    if language == "en" then
        local rest = name:match("^The (.+)$")
        return rest and ("of the " .. rest) or ("of " .. name)
    end
    if language == "es" then
        local rest = name:match("^El (.+)$")
        if rest then return "del " .. rest end
        local article, after = name:match("^(L[ao]s?) (.+)$")
        if article then return "de " .. article:lower() .. " " .. after end
        return (SPANISH[name:match("^(%S+)") or ""] or "de ") .. name
    end
    local kind = FRENCH[name:match("^(%S+)") or ""]
    if kind == "p" then return "des " .. name end
    if kind and vowel(name) then return "de l’" .. name end
    if kind == "f" then return "de la " .. name end
    if kind == "m" then return "du " .. name end
    local rest = name:match("^Les (.+)$")
    if rest then return "des " .. rest end
    rest = name:match("^Le (.+)$")
    if rest then return "du " .. rest end
    rest = name:match("^La (.+)$")
    if rest then return "de la " .. rest end
    rest = name:match("^L’(.+)$") or name:match("^L'(.+)$")
    if rest then return "de l’" .. rest end
    if vowel(name) then return "d’" .. name end
    return "de " .. name
end

local function hash(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + text:byte(i)) % 2147483647
    end
    return h
end
function E.Pick(list, seed)
    if type(list) ~= "table" or #list == 0 then return nil end
    return list[hash(tostring(seed or "")) % #list + 1]
end

-- The archetypes of the Bilan: one pool for each way of fighting.
local ARCHETYPES = {
    traveler = {
        L("Le Voyageur"), L("Le Promeneur"), L("L’Explorateur pacifique"), L("Le Touriste d’Azeroth"),
        L("Le Pèlerin"), L("La Brise légère"), L("Le Passant discret"), L("L’Herboriste du dimanche"),
        L("Le Randonneur"), L("L’Ombre tranquille"), L("Le Contemplatif"), L("Le Cueilleur de fleurs"),
    },
    avenger = {
        L("Le Vengeur"), L("La Rancune incarnée"), L("Le Comptable des dettes"), L("L’Éléphant (n’oublie jamais)"),
        L("Le Justicier"), L("Le Créancier"), L("La Mémoire longue"), L("Le Rendeur de coups"),
        L("Le Collecteur de dettes"), L("Œil pour œil"), L("Le Carnet noir"), L("La Dette réglée"),
    },
    predator = {
        L("Le Prédateur"), L("Le Loup d’Azeroth"), L("Le Faucheur"), L("Le Grand Méchant"),
        L("La Terreur des chemins"), L("Le Chasseur de têtes"), L("Le Sommet de la chaîne"), L("Le Requin des plaines"),
        L("La Lame qui frappe la première"), L("Le Cauchemar ambulant"), L("Le Croque-mitaine"), L("La Faux"),
    },
    rampart = {
        L("Le Rempart"), L("Le Roc"), L("La Forteresse"), L("Le Mur"),
        L("L’Inébranlable"), L("Le Bastion"), L("Le Brise-lames"), L("Le Piège à agresseurs"),
        L("Le Hérisson"), L("Le Gardien"), L("La Porte close"), L("Le Mauvais choix"),
    },
    target = {
        L("La Cible"), L("Le Punching-ball"), L("Le Paillasson"), L("Le Souffre-douleur"),
        L("L’Abonné du cimetière"), L("La Réserve d’honneur"), L("Le Revenant"), L("Le Martyr"),
        L("L’Increvable (qui meurt quand même)"), L("Le Pain béni des ennemis"), L("Le Tapis de bienvenue"),
        L("Le Coureur de cimetières"), L("La Victime désignée"), L("Le Mannequin d’entraînement"),
    },
    duelist = {
        L("Le Duelliste"), L("L’Équilibriste"), L("Pile ou face"), L("Le Bretteur"),
        L("La Balance"), L("Le Joueur de dés"), L("Coup pour coup"), L("Le Funambule"),
        L("Le Gladiateur"), L("L’Indécis"), L("Le Match nul"), L("L’Échange de bons procédés"),
    },
}
-- The same, with a name of your own book: your nemesis, your prey, your zone. Three times as likely.
local PERSONAL = {
    target = { nemesis = { L("Le Jouet %s"), L("La Proie %s"), L("Le Souffre-douleur %s") },
        zone = { L("Le Fantôme %s"), L("L’Habitué du cimetière %s") } },
    avenger = { nemesis = { L("Le Cauchemar %s"), L("Le Créancier %s") } },
    predator = { zone = { L("Le Loup %s"), L("Le Prédateur %s") } },
    rampart = { zone = { L("Le Rempart %s"), L("Le Gardien %s") } },
    duelist = { nemesis = { L("Le Rival %s"), L("L’Ennemi intime %s") } },
}
-- about.nemesis: a player's name; about.zone: a zone's name. Either may be missing.
function E.Archetype(kind, seed, about)
    local list = {}
    for _, name in ipairs(ARCHETYPES[kind] or ARCHETYPES.duelist) do list[#list + 1] = name end
    about = about or {}
    for field, templates in pairs(PERSONAL[kind] or {}) do
        if type(about[field]) == "string" and about[field] ~= "" then
            for _, template in ipairs(templates) do
                local name = template:format(E.Of(about[field]))
                for _ = 1, 3 do list[#list + 1] = name end
            end
        end
    end
    return E.Pick(list, seed)
end

-- The sentence under the archetype. Each pool keeps the values of its first sentence, in order.
local SENTENCES = {
    traveler = {
        L("Peu de combats sur cette période : vous traversez le monde sans faire de vagues."),
        L("Azeroth vous laisse en paix, ou c’est vous qui la laissez en paix."),
        L("Vos armes prennent la poussière : le monde n’a pas encore remarqué votre passage."),
    },
    avenger = {
        L("Vous n’oubliez rien : %d de vos victoires sont des revanches."),
        L("%d revanches : chaque dette finit par être payée."),
        L("Ceux qui vous ont tué l’ont regretté %d fois."),
    },
    predator = {
        L("Vous frappez le premier, et vous gagnez : %s pour %s."),
        L("Vous choisissez vos combats, et vous les gagnez : %s pour %s."),
        L("Quand vous attaquez, ça se termine bien pour vous : %s pour %s."),
    },
    -- When who struck first is not known: nothing is said about it.
    predatorUnknown = {
        L("Vous gagnez bien plus que vous ne tombez : %s pour %s."),
        L("Le cimetière vous connaît à peine : %s pour %s."),
    },
    rampart = {
        L("On vous attaque, et vous tenez : %s pour %s."),
        L("Ceux qui vous cherchent vous trouvent, et le regrettent : %s pour %s."),
    },
    target = {
        L("On vous chasse : %s pour %s. Les dettes s’accumulent."),
        L("Le chemin du cimetière n’a plus de secret pour vous : %s pour %s."),
        L("Vos ennemis vous remercient pour l’honneur : %s pour %s."),
        L("Vous tombez souvent, vous vous relevez toujours : %s pour %s."),
    },
    duelist = {
        L("Combat après combat, l’équilibre : %s, %s."),
        L("Ni vainqueur ni vaincu, toujours debout : %s, %s."),
        L("Une pièce lancée en l’air à chaque combat : %s, %s."),
    },
}
function E.Sentence(kind, seed)
    return E.Pick(SENTENCES[kind] or SENTENCES.duelist, seed)
end

-- The title earned in a zone where you win most (« Le Fléau de Feralas »).
local TITLES = {
    L("Le Fléau %s"), L("La Terreur %s"), L("Le Boucher %s"), L("Le Seigneur %s"), L("Le Fossoyeur %s"),
    L("Le Shérif %s"), L("Le Cauchemar %s"), L("Le Gardien %s"), L("Le Roi %s"), L("Le Tyran %s"),
}
function E.Title(seed, zone)
    return E.Pick(TITLES, seed):format(E.Of(zone))
end

-- Nicknames of the players, by what the facts say of them (see CharacterInsights.Nickname).
local NICKNAMES = {
    camper = {
        L("Le Campeur"), L("Le Campeur de cimetière"), L("Le Comité d’accueil"), L("Le Guetteur de cadavres"),
        L("Celui qui attend au tournant"),
    },
    nemesis = {
        L("Votre cauchemar"), L("Le Croque-mitaine"), L("L’Ombre qui vous suit"), L("Votre bourreau"),
        L("Votre malédiction personnelle"), L("Le Fléau de votre existence"),
    },
    zone = {
        L("Le Fléau %s"), L("Le Boucher %s"), L("Le Fossoyeur %s"), L("La Terreur %s"),
        L("Le Cauchemar %s"), L("Le Rôdeur %s"), L("Le Coupe-jarret %s"), L("Le Gardien du cimetière %s"),
    },
    backstab = {
        L("Frappe dans le dos"), L("L’Embusqué"), L("Le Coupe-gorge"), L("L’Ombre dans le dos"),
        L("Le Lâche des buissons"), L("Le Surgi-de-nulle-part"),
    },
    pack = {
        L("Chasse en meute"), L("Le Chacal"), L("Jamais seul"), L("Courage en bande"),
        L("Le Chef de meute"), L("L’Armée d’un seul homme (et ses amis)"),
    },
    prey = {
        L("Votre proie favorite"), L("Le Sac d’honneur"), L("Le Client régulier"), L("Votre abonné"),
        L("Le Paillasson"), L("Le Punching-ball"),
    },
    rival = {
        L("Le Rival"), L("L’Ennemi intime"), L("Le Vieil ennemi"), L("La Revanche sans fin"),
        L("Votre double maléfique"), L("Le Partenaire de danse"),
    },
    companion = {
        L("Fidèle compagnon"), L("Le Frère d’armes"), L("L’Ami de toujours"), L("Le Bouclier"),
        L("Le Compagnon de route"), L("La Bonne étoile"),
    },
}
function E.Nickname(kind, seed, zone)
    local name = E.Pick(NICKNAMES[kind], seed)
    if name and kind == "zone" then name = name:format(E.Of(zone)) end
    return name
end

-- For the tests: whether a name is one a pool can give (templates compared without their place).
function E.Known(kind, text)
    if type(text) ~= "string" then return false end
    local pools = { ARCHETYPES[kind] or {}, NICKNAMES[kind] or {}, SENTENCES[kind] or {}, kind == "title" and TITLES or {} }
    for _, pool in ipairs(pools) do
        for _, name in ipairs(pool) do
            if name == text then return true end
            local head = name:match("^(.-) %%s")
            if head and text:sub(1, #head + 1) == head .. " " then return true end
        end
    end
    for _, templates in pairs(PERSONAL[kind] or {}) do
        for _, template in ipairs(templates) do
            local head = template:match("^(.-) %%s")
            if head and text:sub(1, #head + 1) == head .. " " then return true end
        end
    end
    return false
end
