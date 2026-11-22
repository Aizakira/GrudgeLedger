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
elseif locale == "deDE" then
    language = "de"
elseif locale == "ptBR" then
    language = "pt"
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
    -- German and Brazilian Portuguese (0.60.0): "von Tanaris", "de Tanaris".
    if language == "de" then return "von " .. name end
    if language == "pt" then return "de " .. name end
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

-- Seeds differ only in their last characters (your identifier, the week): each character is mixed
-- by a multiplication, then three more rounds, so that close seeds land far apart in the pool.
-- Products stay below 2^47, exact in Lua's numbers.
local function hash(text)
    local h = 5381
    for i = 1, #text do
        h = ((h + text:byte(i)) * 48271) % 2147483647
    end
    for _ = 1, 3 do
        h = (h * 48271) % 2147483647
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
        L("Le Voyageur"),
        L("Le Promeneur"),
        L("L’Explorateur pacifique"),
        L("Le Touriste d’Azeroth"),
        L("Le Pèlerin"),
        L("La Brise légère"),
        L("Le Passant discret"),
        L("L’Herboriste du dimanche"),
        L("Le Randonneur"),
        L("L’Ombre tranquille"),
        L("Le Contemplatif"),
        L("Le Cueilleur de fleurs"),
        L("Le Figurant"),
        L("La Plante verte"),
        L("Le Pacifiste convaincu"),
        L("Le Pêcheur à la ligne"),
        L("L’Ermite"),
        L("Le Touriste en sandales"),
        L("Le Pro de la pierre de foyer"),
        L("Le PNJ en vacances"),
    },
    avenger = {
        L("Le Vengeur"),
        L("La Rancune incarnée"),
        L("Le Comptable des dettes"),
        L("L’Éléphant (n’oublie jamais)"),
        L("Le Justicier"),
        L("Le Créancier"),
        L("La Mémoire longue"),
        L("Le Rendeur de coups"),
        L("Le Collecteur de dettes"),
        L("Œil pour œil"),
        L("Le Carnet noir"),
        L("La Dette réglée"),
        L("Le Rancunier professionnel"),
        L("L’Huissier"),
        L("Le Boomerang"),
        L("Le Retour de bâton"),
        L("La Facture salée"),
        L("Le Service après-vente"),
        L("Le Plat qui se mange froid"),
        L("Le Retour à l’envoyeur"),
    },
    savior = {
        L("Le Sauveur"),
        L("L’Ange gardien"),
        L("Le Coup de main"),
        L("Le Second couteau"),
        L("Le Roi de la passe décisive"),
        L("L’Assistant de direction"),
        L("L’Avant-dernier coup"),
        L("L’Ami providentiel"),
        L("Le Héros de l’ombre"),
        L("Le Faire-valoir"),
        L("Le Donneur d’honneur"),
        L("Le Chevalier servant"),
        L("La Cavalerie"),
        L("Le Renfort"),
        L("Le Généreux"),
        L("Le Coéquipier modèle"),
        L("Le Mécène des coups fatals"),
        L("L’Éternel deuxième"),
        L("Le Sous-traitant"),
        L("Le Soutien moral (et physique)"),
    },
    nightowl = {
        L("Le Noctambule"),
        L("Le Vampire"),
        L("L’Insomniaque"),
        L("Le Hibou"),
        L("La Chauve-souris"),
        L("Le Veilleur de nuit"),
        L("Le Cerne ambulant"),
        L("Le Rôdeur de minuit"),
        L("Le Lève-tard"),
        L("L’Ennemi du sommeil"),
        L("Le Café serré"),
        L("L’Ami de la lune"),
        L("Le Fantôme de 3 heures"),
        L("Le Rebelle du couvre-feu"),
        L("Le Zombie du lendemain"),
        L("L’Oiseau de nuit"),
        L("Le Somnambule"),
        L("Le Marchand de sable licencié"),
        L("L’Horloge déréglée"),
        L("La Nuit blanche"),
    },
    predator = {
        L("Le Prédateur"),
        L("Le Loup d’Azeroth"),
        L("Le Faucheur"),
        L("Le Grand Méchant"),
        L("La Terreur des chemins"),
        L("Le Chasseur de têtes"),
        L("Le Sommet de la chaîne"),
        L("Le Requin des plaines"),
        L("La Lame qui frappe la première"),
        L("Le Cauchemar ambulant"),
        L("Le Croque-mitaine"),
        L("La Faux"),
        L("Le Fauve"),
        L("L’Alpha"),
        L("Le Chasseur de primes"),
        L("Le Premier sang"),
        L("Le Mangeur d’honneur"),
        L("Le Fournisseur du cimetière"),
        L("Le Point final"),
        L("Le Rapace"),
    },
    ganker = {
        L("Le Gankeur"),
        L("La Brute de la cour de récré"),
        L("Le Racketteur de goûters"),
        L("Le Gros bras"),
        L("Le Tondeur de bas niveaux"),
        L("Le Héros des petits niveaux"),
        L("Le Courageux (contre plus petit)"),
        L("Le Cauchemar des débutants"),
        L("Le Gros poisson du petit bassin"),
        L("Le Faux dur"),
        L("Le Videur de zone de départ"),
        L("Le Vautour"),
        L("Le Sans-gêne"),
        L("Le Tueur de niveaux gris"),
        L("L’Honneur à zéro"),
        L("Le Caïd"),
        L("L’Écraseur de fourmis"),
        L("Le Champion des poids plume"),
        L("Le Tyran de bac à sable"),
        L("Le Fléau des bas niveaux"),
    },
    giantslayer = {
        L("Le Tueur de géants"),
        L("Le Petit qui mord"),
        L("L’Outsider"),
        L("Le Mauvais calcul"),
        L("Le Tombeur de colosses"),
        L("La Fronde"),
        L("Le Cauchemar des gros niveaux"),
        L("Le Petit mais costaud"),
        L("L’Anomalie statistique"),
        L("Le Bûcheron de chênes"),
        L("Le Chasseur de crânes"),
        L("Le Moustique"),
        L("Le Grain de sable"),
        L("L’Insolent"),
        L("Le Sans complexe"),
        L("Le Dompteur de géants"),
        L("Le Casse-noisette"),
        L("Le Problème des grands"),
        L("Le Renverseur de pronostics"),
        L("La Revanche des petits"),
    },
    teamplayer = {
        L("Le Joueur d’équipe"),
        L("Le Mousquetaire"),
        L("Le Maillon de la chaîne"),
        L("La Meute"),
        L("L’Esprit de groupe"),
        L("Le Frère de raid"),
        L("Tous pour un"),
        L("La Fanfare"),
        L("Le Banc de piranhas"),
        L("L’Essaim"),
        L("Le Courage collectif"),
        L("Le Chef d’orchestre"),
        L("Le Sport collectif"),
        L("Le Ciment du groupe"),
        L("Le Membre de la chorale"),
        L("Le Rouleau compresseur"),
        L("L’Union fait la force"),
        L("Le Partageur d’honneur"),
        L("Jamais sans mes potes"),
        L("Le Bus de l’honneur"),
    },
    rampart = {
        L("Le Rempart"),
        L("Le Roc"),
        L("La Forteresse"),
        L("Le Mur"),
        L("L’Inébranlable"),
        L("Le Bastion"),
        L("Le Brise-lames"),
        L("Le Piège à agresseurs"),
        L("Le Hérisson"),
        L("Le Gardien"),
        L("La Porte close"),
        L("Le Mauvais choix"),
        L("Le Cactus"),
        L("La Mauvaise surprise"),
        L("L’Erreur de casting"),
        L("Le Coffre-fort"),
        L("La Tortue blindée"),
        L("Le Contre-attaquant"),
        L("Le Morceau trop gros"),
        L("Le Chien qui dort"),
    },
    victimhigher = {
        L("Le Petit Timmy"),
        L("Le Souffre-douleur des grands"),
        L("Le Goûter des gros niveaux"),
        L("Le Locataire du casier"),
        L("Le Ballon des grands"),
        L("L’Argent du goûter"),
        L("Le Petit dernier de la cour"),
        L("La Victime des têtes de mort"),
        L("Pas encore assez grand"),
        L("Le Marchepied"),
        L("Le Bizuth"),
        L("Le Chaton chez les tigres"),
        L("L’Écolier perdu"),
        L("Dix niveaux de retard"),
        L("Le Jouet de la cour de récré"),
        L("Le Presque assez rapide"),
        L("Le Dragonnet"),
        L("Le Futur grand (un jour)"),
        L("L’Apprenti martyr"),
        L("Le Petit frère de service"),
    },
    victimpack = {
        L("La Proie de la meute"),
        L("Le Buffet à volonté"),
        L("La Piñata"),
        L("La Pizza à partager"),
        L("La Fête surprise"),
        L("Le Plat principal"),
        L("Le Seul contre tous"),
        L("L’Invité d’honneur"),
        L("Le Duel à cinq"),
        L("Le Centre d’attention"),
        L("Le Ballon de rugby"),
        L("Le Partage équitable"),
        L("Le Gibier de battue"),
        L("Le Pique-nique"),
        L("L’Agneau parmi les loups"),
        L("L’Os à ronger"),
        L("Le Trophée de groupe"),
        L("Le Vote unanime"),
        L("Le Projet d’équipe"),
        L("Le Point de ralliement"),
    },
    victimambush = {
        L("Le Distrait"),
        L("Le Cueilli à froid"),
        L("Le Lecteur de quêtes"),
        L("Le Dos ouvert"),
        L("L’Herboriste imprudent"),
        L("Le Mineur trop concentré"),
        L("Le Pêcheur pris à l’hameçon"),
        L("La Surprise du chef"),
        L("Le Repas interrompu"),
        L("L’Aimant à embuscades"),
        L("Le Rêveur"),
        L("Le Sans-radar"),
        L("Le Bonjour dans le dos"),
        L("L’Éternel étonné"),
        L("L’AFK de trop"),
        L("Le Cou tendu"),
        L("Le Dernier informé"),
        L("Le Lacet défait"),
        L("La Cible fixe"),
        L("Le Regard ailleurs"),
    },
    victimone = {
        L("Le Jouet préféré"),
        L("L’Obsession"),
        L("Le Rendez-vous régulier"),
        L("La Proie attitrée"),
        L("Le Fan club involontaire"),
        L("Le Projet personnel"),
        L("Le Hobby de quelqu’un"),
        L("L’Abonnement premium"),
        L("La Relation compliquée"),
        L("L’Élu (du mauvais côté)"),
        L("Le Rival à sens unique"),
        L("La Carte de fidélité"),
        L("L’Animal de compagnie"),
        L("Le Sujet d’étude"),
        L("La Victime de série"),
        L("Le Cœur de cible"),
        L("Le Feuilleton"),
        L("Le Disque rayé"),
        L("Le Nom sur la liste"),
        L("Le Rituel"),
    },
    victimzone = {
        L("Le Maudit des lieux"),
        L("Le Mauvais endroit"),
        L("Le Fantôme du coin"),
        L("L’Abonné de la zone"),
        L("La Malédiction du coin"),
        L("Le Résident permanent"),
        L("Le Paroissien du cimetière"),
        L("Le Touriste obstiné"),
        L("La Carte postale funèbre"),
        L("Le Mauvais GPS"),
        L("Le Retour sur les lieux du crime"),
        L("Le Jardinier des tombes"),
        L("La Concession à perpétuité"),
        L("Celui qui devrait déménager"),
        L("La Figure locale"),
        L("Le Meuble du coin"),
        L("L’Aimant à malheur"),
        L("Le Pied dans le piège"),
        L("Le Cartographe des tombes"),
        L("L’Habitant malchanceux"),
    },
    target = {
        L("La Cible"),
        L("Le Punching-ball"),
        L("Le Paillasson"),
        L("Le Souffre-douleur"),
        L("L’Abonné du cimetière"),
        L("La Réserve d’honneur"),
        L("Le Revenant"),
        L("Le Martyr"),
        L("L’Increvable (qui meurt quand même)"),
        L("Le Pain béni des ennemis"),
        L("Le Tapis de bienvenue"),
        L("Le Coureur de cimetières"),
        L("La Victime désignée"),
        L("Le Mannequin d’entraînement"),
        L("Le Distributeur d’honneur"),
        L("Le Pass annuel du cimetière"),
        L("L’Ami des guérisseurs spirituels"),
        L("Le Marathonien du cadavre"),
        L("La Durabilité à zéro"),
        L("Le Mal de résurrection"),
    },
    duelist = {
        L("Le Duelliste"),
        L("L’Équilibriste"),
        L("Pile ou face"),
        L("Le Bretteur"),
        L("La Balance"),
        L("Le Joueur de dés"),
        L("Coup pour coup"),
        L("Le Funambule"),
        L("Le Gladiateur"),
        L("L’Indécis"),
        L("Le Match nul"),
        L("L’Échange de bons procédés"),
        L("Le Pendule"),
        L("Le Yo-yo"),
        L("La Bascule"),
        L("Le Ping-pong"),
        L("Le Score serré"),
        L("L’Éternel ex aequo"),
        L("Le Cinquante-cinquante"),
        L("Le Boxeur aux points"),
    },
}
-- The same, with a name of your own book: your nemesis, your prey, your zone. Three times as likely.
local PERSONAL = {
    avenger = {
        nemesis = {
            L("Le Cauchemar %s"),
            L("Le Créancier %s"),
            L("Le Comptable %s"),
            L("Le Remords %s"),
        },
    },
    predator = {
        zone = {
            L("Le Loup %s"),
            L("Le Prédateur %s"),
            L("L’Ogre %s"),
            L("Le Chasseur %s"),
        },
    },
    ganker = {
        zone = {
            L("La Brute %s"),
            L("Le Racketteur %s"),
            L("Le Petit chef %s"),
        },
    },
    rampart = {
        zone = {
            L("Le Rempart %s"),
            L("Le Gardien %s"),
            L("La Sentinelle %s"),
            L("La Muraille %s"),
        },
    },
    victimhigher = {
        nemesis = {
            L("Le Petit frère %s"),
            L("Le Goûter %s"),
            L("Le Ballon %s"),
            L("Le Stagiaire %s"),
        },
    },
    victimone = {
        nemesis = {
            L("Le Passe-temps %s"),
            L("La Mascotte %s"),
            L("Le Rendez-vous %s"),
            L("L’Obsession %s"),
            L("La Collection %s"),
        },
    },
    victimzone = {
        zone = {
            L("Le Maudit %s"),
            L("Le Résident %s"),
            L("L’Engrais %s"),
            L("Le Locataire du cimetière %s"),
        },
    },
    target = {
        nemesis = {
            L("Le Jouet %s"),
            L("La Proie %s"),
            L("Le Souffre-douleur %s"),
            L("Le Cadeau %s"),
            L("La Tirelire %s"),
        },
        zone = {
            L("Le Fantôme %s"),
            L("L’Habitué du cimetière %s"),
            L("Le Marathonien %s"),
            L("Le Revenant %s"),
        },
    },
    duelist = {
        nemesis = {
            L("Le Rival %s"),
            L("L’Ennemi intime %s"),
            L("Le Partenaire de duel %s"),
            L("Le Miroir %s"),
        },
    },
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
        L("Le cimetière a perdu votre adresse : trop peu de combats pour vous juger."),
        L("Votre épée est restée au fourreau. Votre monture, elle, a beaucoup travaillé."),
    },
    avenger = {
        L("Vous n’oubliez rien : %d de vos victoires sont des revanches."),
        L("%d revanches : chaque dette finit par être payée."),
        L("Ceux qui vous ont tué l’ont regretté %d fois."),
        L("%d fois, vous leur avez rendu la monnaie de leur pièce. Avec les intérêts."),
        L("Le cimetière vous renvoie, vous renvoyez l’addition : %d revanches."),
    },
    savior = {
        L("Vous préparez le terrain, les autres signent le coup final : %d assistances."),
        L("%d assistances : vous tapez, ils encaissent l’honneur."),
        L("Toujours là au bon moment, jamais pour le coup final : %d assistances."),
        L("%d fois, vous avez fait le gros du travail. Les autres ont pris la photo."),
        L("Sans vous, %d ennemis seraient encore debout. Personne ne vous remerciera."),
    },
    nightowl = {
        L("Minuit passé, et vous êtes encore là : %s pour %s."),
        L("Les honnêtes gens dorment. Vous, vous comptez : %s pour %s."),
        L("Bilan nocturne : %s et %s. Le réveil va piquer."),
        L("Entre minuit et l’aube, %s pour %s. Votre lit vous attend toujours."),
        L("La lune a tout vu : %s pour %s. Elle ne dira rien."),
    },
    predator = {
        L("Vous frappez le premier, et vous gagnez : %s pour %s."),
        L("Vous choisissez vos combats, et vous les gagnez : %s pour %s."),
        L("Quand vous attaquez, ça se termine bien pour vous : %s pour %s."),
        L("Vous ouvrez le bal, vous fermez le cercueil : %s pour %s."),
        L("Premier coup, dernier mot : %s pour %s."),
    },
    predatorUnknown = {
        L("Vous gagnez bien plus que vous ne tombez : %s pour %s."),
        L("Le cimetière vous connaît à peine : %s pour %s."),
        L("Vos adversaires visitent le cimetière plus souvent que vous : %s pour %s."),
    },
    ganker = {
        L("Vous choisissez des adversaires à votre taille. En plus petit : %s pour %s."),
        L("%s pour %s, surtout contre des niveaux plus bas. Le courage a ses limites."),
        L("Les nouveaux venus vous connaissent bien : %s pour %s."),
        L("Victoires faciles, honneur discutable : %s pour %s."),
        L("Vous gagnez surtout contre plus petit que vous : %s pour %s. Leurs grands frères arrivent."),
    },
    giantslayer = {
        L("Plus ils sont grands, plus ils tombent de haut : %s pour %s."),
        L("Le niveau n’est qu’un chiffre, et vous le prouvez : %s pour %s."),
        L("Vous tapez au-dessus de votre catégorie : %s pour %s."),
        L("Eux avaient les niveaux, vous aviez l’audace : %s pour %s."),
        L("Quelque part, un gros niveau se demande encore ce qui s’est passé : %s pour %s."),
    },
    teamplayer = {
        L("Seul on va vite, ensemble on gagne : %s pour %s."),
        L("La moitié de vos victoires se fêtent à plusieurs : %s pour %s."),
        L("Vos amis tapent, vous tapez, l’ennemi s’allonge : %s pour %s."),
        L("Le fair-play, c’est surfait. Le nombre, c’est efficace : %s pour %s."),
        L("En groupe, vous êtes redoutable. Seul, on verra : %s pour %s."),
    },
    rampart = {
        L("On vous attaque, et vous tenez : %s pour %s."),
        L("Ceux qui vous cherchent vous trouvent, et le regrettent : %s pour %s."),
        L("Vous attaquer est une mauvaise idée, les chiffres le disent : %s pour %s."),
        L("Ils frappent les premiers, vous frappez les derniers : %s pour %s."),
        L("Vous tendre une embuscade, c’est un aller simple pour le cimetière : %s pour %s."),
    },
    victimhigher = {
        L("Les grands de la cour vous ont repéré : %s pour %s."),
        L("Ils ont plus de niveaux, plus d’équipement et aucune pitié : %s pour %s."),
        L("Vous mourez surtout contre plus grand que vous : %s pour %s. Grandissez vite."),
        L("Le niveau n’est qu’un chiffre. Le leur est juste plus gros : %s pour %s."),
        L("Un jour vous serez grand, et ils auront intérêt à courir : %s pour %s."),
    },
    victimpack = {
        L("Ils étaient plusieurs, vous étiez seul : %s pour %s."),
        L("La moitié de vos morts sont des travaux de groupe : %s pour %s."),
        L("Vos ennemis ne sortent jamais seuls. Vous, si : %s pour %s."),
        L("Un contre un, c’est démodé, apparemment : %s pour %s."),
        L("Vous rassemblez les foules. Surtout autour de votre cadavre : %s pour %s."),
    },
    victimambush = {
        L("Vous ne les voyez jamais venir : %s pour %s."),
        L("Le premier coup est toujours pour vous, et pas dans le bon sens : %s pour %s."),
        L("Regardez derrière vous. Non, encore plus derrière : %s pour %s."),
        L("Surpris en train de miner, de pêcher, de manger : %s pour %s."),
        L("Vos ennemis adorent les surprises. Vous, de moins en moins : %s pour %s."),
    },
    victimone = {
        L("Quelqu’un vous a pris en affection, et ça fait mal : %s pour %s."),
        L("Une seule personne a fait la moitié du travail : %s pour %s."),
        L("Vous avez un admirateur. Il s’exprime à coups d’épée : %s pour %s."),
        L("Toujours le même nom dans votre journal des morts : %s pour %s."),
        L("Ce n’est plus un ennemi, c’est une habitude : %s pour %s."),
    },
    victimzone = {
        L("Un seul endroit, la moitié de vos morts : %s pour %s. Évitez le coin."),
        L("Vous aimez ce coin. Lui aussi, il aime vous voir mourir : %s pour %s."),
        L("Ce lieu est maudit, et vous y retournez quand même : %s pour %s."),
        L("Le cimetière du coin vous réserve une place : %s pour %s."),
        L("Il existe d’autres zones en Azeroth, promis : %s pour %s."),
    },
    target = {
        L("On vous chasse : %s pour %s. Les dettes s’accumulent."),
        L("Le chemin du cimetière n’a plus de secret pour vous : %s pour %s."),
        L("Vos ennemis vous remercient pour l’honneur : %s pour %s."),
        L("Vous tombez souvent, vous vous relevez toujours : %s pour %s."),
        L("Votre armure passe plus de temps chez le réparateur que sur vous : %s pour %s."),
    },
    duelist = {
        L("Combat après combat, l’équilibre : %s, %s."),
        L("Ni vainqueur ni vaincu, toujours debout : %s, %s."),
        L("Une pièce lancée en l’air à chaque combat : %s, %s."),
        L("Un coup pour vous, un coup pour eux. Le cimetière reste neutre : %s, %s."),
        L("Ni héros ni victime : %s et %s. La suite au prochain épisode."),
    },
}
function E.Sentence(kind, seed)
    return E.Pick(SENTENCES[kind] or SENTENCES.duelist, seed)
end

-- The title earned in a zone where you win most (« Le Fléau de Feralas »).
local TITLES = {
    L("Le Fléau %s"),
    L("La Terreur %s"),
    L("Le Boucher %s"),
    L("Le Seigneur %s"),
    L("Le Fossoyeur %s"),
    L("Le Shérif %s"),
    L("Le Cauchemar %s"),
    L("Le Gardien %s"),
    L("Le Roi %s"),
    L("Le Tyran %s"),
    L("Le Baron %s"),
    L("Le Maire %s"),
    L("Le Parrain %s"),
    L("Le Gouverneur %s"),
    L("Le Percepteur %s"),
    L("Le Croque-mort %s"),
    L("Le Patron %s"),
    L("Le Loup-garou %s"),
    L("L’Empereur %s"),
    L("Le Champion %s"),
    L("Le Marchand de cercueils %s"),
    L("Le Grand Manitou %s"),
    L("La Légende %s"),
    L("Le Propriétaire %s"),
    L("Le Videur %s"),
    L("Le Faucheur %s"),
    L("Le Duc %s"),
    L("L’Épouvantail %s"),
    L("Le Gendarme %s"),
    L("Le Bourreau %s"),
}
function E.Title(seed, zone)
    return E.Pick(TITLES, seed):format(E.Of(zone))
end

-- Nicknames of the players, by what the facts say of them (see CharacterInsights.Nickname).
local NICKNAMES = {
    camper = {
        L("Le Campeur"),
        L("Le Campeur de cimetière"),
        L("Le Comité d’accueil"),
        L("Le Guetteur de cadavres"),
        L("Celui qui attend au tournant"),
        L("Le Locataire de votre tombe"),
        L("Le Chronomètre"),
        L("Votre réveil-matin"),
        L("Le Planton"),
        L("Le Campeur trois étoiles"),
        L("Votre ange gardien à l’envers"),
        L("Le Spécialiste du respawn"),
        L("L’Horloge du cimetière"),
        L("Le Pique-nique sur votre tombe"),
    },
    nemesis = {
        L("Votre cauchemar"),
        L("Le Croque-mitaine"),
        L("L’Ombre qui vous suit"),
        L("Votre bourreau"),
        L("Votre malédiction personnelle"),
        L("Le Fléau de votre existence"),
        L("Votre patron"),
        L("La Montagne infranchissable"),
        L("Votre plafond de verre"),
        L("L’Invaincu"),
        L("Le Boss final"),
        L("Le Collectionneur de vos os"),
        L("Votre facture de réparation"),
        L("Le Cauchemar récurrent"),
    },
    bully = {
        L("Le Caïd de la cour de récré"),
        L("Le Voleur de goûters"),
        L("Le Croqueur de novices"),
        L("Trois niveaux de courage"),
        L("Le Grand méchant loup"),
        L("L’Amateur de cibles grises"),
        L("Le Fermier à zéro honneur"),
        L("Le Roi du bac à sable"),
        L("Le Champion des poids plumes"),
        L("Le Courageux, mais pas trop"),
        L("La Brute"),
        L("S’en prend aux plus petits"),
        L("L’Effroi des débutants"),
        L("Le Gros poisson de la mare"),
    },
    nightstalker = {
        L("Le Vampire"),
        L("L’Oiseau de nuit"),
        L("L’Insomniaque"),
        L("Le Chasseur de minuit"),
        L("Le Marchand de sable"),
        L("Le Couvre-feu"),
        L("Le Gardien de nuit"),
        L("Le Cauchemar de 3 h du matin"),
        L("Le Rôdeur nocturne"),
        L("Le Service de nuit"),
        L("Le Couche-tard"),
        L("Le Loup-garou"),
        L("La Patrouille de l’aube"),
        L("Pas de dodo pour vous"),
    },
    zone = {
        L("Le Fléau %s"),
        L("Le Boucher %s"),
        L("Le Fossoyeur %s"),
        L("La Terreur %s"),
        L("Le Cauchemar %s"),
        L("Le Rôdeur %s"),
        L("Le Coupe-jarret %s"),
        L("Le Gardien du cimetière %s"),
        L("Le Propriétaire %s"),
        L("Le Péage %s"),
        L("Le Shérif autoproclamé %s"),
        L("Le Guide touristique %s"),
        L("Le Douanier %s"),
        L("La Légende locale %s"),
    },
    backstab = {
        L("Frappe dans le dos"),
        L("L’Embusqué"),
        L("Le Coupe-gorge"),
        L("L’Ombre dans le dos"),
        L("Le Lâche des buissons"),
        L("Le Surgi-de-nulle-part"),
        L("Le Ninja du dimanche"),
        L("Le Spécialiste des dos"),
        L("Le Chiropracteur"),
        L("Jamais de face"),
        L("L’Invité surprise"),
        L("Le Tueur silencieux"),
        L("Pas de préavis"),
        L("À pas de loup"),
    },
    pack = {
        L("Chasse en meute"),
        L("Le Chacal"),
        L("Jamais seul"),
        L("Courage en bande"),
        L("Le Chef de meute"),
        L("L’Armée d’un seul homme (et ses amis)"),
        L("Le Covoiturage"),
        L("Brave à cinq contre un"),
        L("La Fanfare"),
        L("Jamais sans ses potes"),
        L("L’Excursion scolaire"),
        L("Le Courage par procuration"),
        L("Le Roi de l’assist"),
        L("Le Renfort"),
    },
    giant = {
        L("Le Géant aux pieds d’argile"),
        L("La Statue déboulonnée"),
        L("Votre plus belle prise"),
        L("Le Colosse à terre"),
        L("Plus dure sera la chute"),
        L("Le Niveau ne fait pas tout"),
        L("Votre trophée de chasse"),
        L("Le Boss vaincu"),
        L("La Surprise du chef"),
        L("Le Surclassé"),
        L("L’Excès de confiance"),
        L("Votre coup de maître"),
        L("Le Niveau de façade"),
        L("Le Mammouth"),
    },
    smallfry = {
        L("Votre exploit discutable"),
        L("La Victoire sans gloire"),
        L("Votre futur cauchemar"),
        L("Celui qui reviendra plus grand"),
        L("Le Bizut"),
        L("La Cible grise"),
        L("Le Mauvais timing"),
        L("Votre petit moment de honte"),
        L("La Fourmi"),
        L("Le Moustique"),
        L("Le Trophée de pacotille"),
        L("Le Combat inégal"),
        L("L’Apprenti"),
        L("Le Pas-de-chance"),
    },
    prey = {
        L("Votre proie favorite"),
        L("Le Sac d’honneur"),
        L("Le Client régulier"),
        L("Votre abonné"),
        L("Le Paillasson"),
        L("Le Punching-ball"),
        L("Le Distributeur d’honneur"),
        L("Votre carte de fidélité"),
        L("Le Tremplin"),
        L("Le Buffet à volonté"),
        L("L’Habitué du cimetière"),
        L("Le Repas gratuit"),
        L("La Victoire garantie"),
        L("Votre fan numéro un"),
    },
    rival = {
        L("Le Rival"),
        L("L’Ennemi intime"),
        L("Le Vieil ennemi"),
        L("La Revanche sans fin"),
        L("Votre double maléfique"),
        L("Le Partenaire de danse"),
        L("Le Match retour"),
        L("Votre âme sœur au combat"),
        L("La Pièce en l’air"),
        L("Le Match nul permanent"),
        L("Le Ping-pong"),
        L("L’Équilibre parfait"),
        L("Votre meilleur ennemi"),
        L("Le Chat et la souris"),
    },
    companion = {
        L("Fidèle compagnon"),
        L("Le Frère d’armes"),
        L("L’Ami de toujours"),
        L("Le Bouclier"),
        L("Le Compagnon de route"),
        L("La Bonne étoile"),
        L("Le Complice"),
        L("Votre résurrection sur pattes"),
        L("Le Coéquipier"),
        L("Toujours sur Cupidité"),
        L("Le Garde du corps"),
        L("Le Copilote"),
        L("Le Feu de camp"),
        L("Le Porteur de potions"),
    },
    duelpartner = {
        L("Le Sparring-partner"),
        L("Le Fair-play"),
        L("Le Partenaire d’entraînement"),
        L("Rendez-vous aux portes"),
        L("Encore une petite"),
        L("Le Mauvais perdant"),
        L("Au meilleur des trois"),
        L("Le Gant jeté"),
        L("Le Compte à rebours"),
        L("Le Tournoi à deux"),
        L("Le Testeur de talents"),
        L("Le Cobaye"),
        L("Le Rival amical"),
        L("Jamais à mort"),
    },
    dungeonbuddy = {
        L("Le Tank de service"),
        L("Le Soigneur de poche"),
        L("Le Pull de trop"),
        L("L’Expert du wipe"),
        L("Le Compagnon de donjon"),
        L("Le Pilleur de coffres"),
        L("Besoin sur tout"),
        L("Le Gardien de l’aggro"),
        L("Le Cinquième du groupe"),
        L("Le Nettoyeur de donjons"),
        L("Le Porteur de torche"),
        L("Mort ensemble, rez ensemble"),
        L("AFK deux minutes"),
        L("Le Stratège du donjon"),
    },
    friend = {
        L("Le Pote"),
        L("Votre contact d’urgence"),
        L("Le Premier sur la liste"),
        L("La Bouée de sauvetage"),
        L("Le Confident"),
        L("Le Rayon de soleil"),
        L("La Valeur sûre"),
        L("Le Pilier"),
        L("Le Copain de taverne"),
        L("Le Toujours-là"),
        L("Votre ange gardien"),
        L("L’Ami en or"),
        L("Le Chouchou"),
        L("Le Trésor"),
    },
    veteran = {
        L("Le Vieux de la vieille"),
        L("Le Fossile"),
        L("Le Monument"),
        L("Le Survivant"),
        L("Le Patrimoine"),
        L("La Légende vivante"),
        L("Le Pilier du serveur"),
        L("Le Doyen"),
        L("Le Bon millésime"),
        L("Le Témoin des débuts"),
        L("Celui d’avant le patch"),
        L("Le Chêne"),
        L("L’Inoxydable"),
        L("La Mémoire du serveur"),
    },
    regular = {
        L("Le Visage familier"),
        L("L’Habitué"),
        L("Le Meuble"),
        L("Le Bonjour quotidien"),
        L("Le Collègue"),
        L("Le Repère"),
        L("Le Comité de quartier"),
        L("Le Facteur"),
        L("Encore vous"),
        L("L’Enfant du pays"),
        L("Le Café du matin"),
        L("Le Bon voisin"),
        L("Le Partenaire de farm"),
        L("Le Salut de la main"),
    },
    passerby = {
        L("Le Pacifiste"),
        L("Le Touriste"),
        L("Le Figurant"),
        L("Le Voisin de palier"),
        L("Le Hochement de tête"),
        L("Le Pacte tacite"),
        L("Le Bonjour-bonsoir"),
        L("L’Inconnu familier"),
        L("Le Nuage qui passe"),
        L("Le Badaud"),
        L("Pas aujourd’hui"),
        L("Le Mystère ambulant"),
        L("Le Combat en suspens"),
        L("Le Regard en coin"),
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
