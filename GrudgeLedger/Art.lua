-- Every picture shared by several places of the addon, named once (owner, 25/11): change a path
-- here and the picture changes everywhere it is used. A page asks GL.Art for its pictures and never
-- writes a path itself. Paths go to SetTexture without the extension.
local GL = GrudgeLedger
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"
GL.Art = {
    -- The marks of a fight, drawn in colour by the page that shows them: the map of fights and its
    -- legend. The game's own pictures for now; the owner will replace them (25/11).
    Death = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    Victory = "Interface\\CURSOR\\Attack",
    -- The same outcomes as coloured seals, for the parchment pages (owner's kit, 25/11): shown as they
    -- are, never tinted.
    DeathSeal = media .. "Rivalites\\RivalDeath",
    VictorySeal = media .. "Rivalites\\RivalVictory",
    -- Crossed swords: a mixed fight, a helping hand, an attack without an end.
    Swords = media .. "RelationsCarte\\rivalites",
    -- Rivalités: the strip of parchment, the unfolded sheet, the band where you face your rival
    -- (Alliance blue on your side, Horde red on theirs).
    RivalStrip = media .. "Rivalites\\bande-rivalite",
    RivalSheet = media .. "Rivalites\\RivalSheet",
    RivalDuel = media .. "Rivalites\\RivalDuel",
    -- The map page: its separator, and the frame around the map in four corners and four edges.
    Separator = media .. "RelationsCarte\\separateur-carte",
    MapFrame = media .. "RelationsCarte\\cadre-",
    -- The icons of the Relations entries, by entry.
    EntryIcon = media .. "RelationsCarte\\",
    -- The guild's journal as a register (owner's kit, 26/11): the engraved header with its book, the
    -- two fleurons around the count, the pennant of the new fights, and the outcomes in colour
    -- (crossed swords, skull), shown as they are.
    GuildLogHeader = media .. "JournalGuilde\\EnteteGravee",
    GuildLogFleuronLeft = media .. "JournalGuilde\\FleuronGauche",
    GuildLogFleuronRight = media .. "JournalGuilde\\FleuronDroit",
    GuildLogPennant = media .. "JournalGuilde\\Fanion",
    GuildLogVictory = media .. "JournalGuilde\\Victoire",
    GuildLogDeath = media .. "JournalGuilde\\Mort",
    -- The guild's enemies as wanted posters (owner's kit, 27/11): a picture is Wanted .. its name
    -- (ToileAlliance, PrimeGrande…). Each is a power-of-two texture stretched from its drawing:
    -- WantedRatio gives the width over height to draw it at (tools/import_wanted_kit.py prints them).
    Wanted = media .. "AvisRecherche\\",
}
GL.Art.WantedRatio = {
    FanionAlliance = 1.102, FanionHorde = 0.805, EmblemeAlliance = 0.754, EmblemeHorde = 0.641,
    FiligraneAlliance = 0.76, FiligraneHorde = 0.641,
    AfficheGrande1 = 0.665, AfficheGrande2 = 0.695, AfficheCarree1 = 0.982, AfficheCarree2 = 0.96,
    PrimeGrande1 = 0.667, PrimeGrande2 = 0.706, PrimeCarree1 = 0.991, PrimeCarree2 = 0.963,
    CadrePortrait = 1.006, Medaillon = 0.989, MedaillonUn = 0.975, Bandeau = 5.066, SceauPrime = 0.989, Tampon = 4.094,
    Cartouche = 7.659, SeparateurEncre = 28.06, SeparateurOr = 19.363, IconeMembres = 1.685, IconeCrane = 0.913,
    ClouFace = 0.725, ClouGauche = 1.011, ClouDroite = 0.73, Chevron = 1.667,
    -- The v8 collection (owner, 27/11): ten families, a tall paper and a small one, plain and gold.
    AfficheAerienCarree = 1.024, AfficheAerienGrande = 0.674, AfficheDemonisteCarree = 0.989, AfficheDemonisteGrande = 0.642,
    AfficheElfeNuitCarree = 0.992, AfficheElfeNuitGrande = 0.666, AfficheElfeSangCarree = 0.974, AfficheElfeSangGrande = 0.658,
    AfficheHumainCarree = 0.884, AfficheHumainGrande = 0.663, AfficheMortVivantCarree = 0.989, AfficheMortVivantGrande = 0.664,
    AfficheOrcCarree = 0.98, AfficheOrcGrande = 0.663, AfficheRoublardCarree = 0.972, AfficheRoublardGrande = 0.646,
    AfficheTaurenCarree = 0.99, AfficheTaurenGrande = 0.659, AfficheTrollCarree = 0.965, AfficheTrollGrande = 0.664,
    PrimeAerienCarree = 1.023, PrimeAerienGrande = 0.676, PrimeDemonisteCarree = 0.989, PrimeDemonisteGrande = 0.641,
    PrimeElfeNuitCarree = 0.993, PrimeElfeNuitGrande = 0.666, PrimeElfeSangCarree = 0.977, PrimeElfeSangGrande = 0.659,
    PrimeHumainCarree = 0.885, PrimeHumainGrande = 0.664, PrimeMortVivantCarree = 0.989, PrimeMortVivantGrande = 0.663,
    PrimeOrcCarree = 0.98, PrimeOrcGrande = 0.662, PrimeRoublardCarree = 0.97, PrimeRoublardGrande = 0.647,
    PrimeTaurenCarree = 0.99, PrimeTaurenGrande = 0.658, PrimeTrollCarree = 0.964, PrimeTrollGrande = 0.664,
    -- The tribal papers (v9, v10; owner, 28/11): one size, no gold edition.
    AfficheOrcChef = 0.786, AfficheOrcGuerre = 0.801,
    AfficheTrollMarais = 0.801, AfficheGnollMarais = 0.8,
    AfficheGnollRavins = 0.812, AfficheOgreChef = 0.834,
}
-- The forged nails (v6) are drawn in perspective: where the point enters the paper, in fractions of
-- the drawing from its top left. A banner may give its arms' place (left, top, right, bottom): the
-- classic ones (owner, 27/11) are centred instead.
GL.Art.WantedNail = { ClouFace = { 0.659, 0.933 }, ClouGauche = { 0.869, 0.971 }, ClouDroite = { 0.108, 0.921 } }
GL.Art.WantedEmblem = {}
-- Where the posters' papers take writing (v5, 27/11): margins left, top, right, bottom in fractions of
-- the drawing, inside its printed frame (tools/import_wanted_kit.py prints them). 1 and 2 are the two
-- tilts drawn in the paper; the text itself stands straight.
GL.Art.WantedText = {
    AfficheGrande1 = { 0.134, 0.099, 0.122, 0.09 }, AfficheGrande2 = { 0.12, 0.101, 0.124, 0.081 },
    AfficheCarree1 = { 0.095, 0.123, 0.109, 0.127 }, AfficheCarree2 = { 0.1, 0.105, 0.093, 0.099 },
    PrimeGrande1 = { 0.136, 0.087, 0.128, 0.091 }, PrimeGrande2 = { 0.099, 0.103, 0.136, 0.081 },
    PrimeCarree1 = { 0.079, 0.112, 0.123, 0.132 }, PrimeCarree2 = { 0.094, 0.102, 0.104, 0.108 },
    AfficheAerienCarree = { 0.094, 0.136, 0.11, 0.099 }, AfficheAerienGrande = { 0.105, 0.123, 0.109, 0.074 },
    AfficheDemonisteCarree = { 0.142, 0.178, 0.142, 0.102 }, AfficheDemonisteGrande = { 0.146, 0.141, 0.122, 0.081 },
    AfficheElfeNuitCarree = { 0.141, 0.17, 0.155, 0.135 }, AfficheElfeNuitGrande = { 0.101, 0.086, 0.118, 0.07 },
    AfficheElfeSangCarree = { 0.088, 0.13, 0.105, 0.1 }, AfficheElfeSangGrande = { 0.11, 0.106, 0.12, 0.087 },
    AfficheHumainCarree = { 0.113, 0.121, 0.091, 0.089 }, AfficheHumainGrande = { 0.141, 0.096, 0.103, 0.087 },
    AfficheMortVivantCarree = { 0.107, 0.115, 0.115, 0.113 }, AfficheMortVivantGrande = { 0.135, 0.087, 0.132, 0.073 },
    AfficheOrcCarree = { 0.119, 0.116, 0.127, 0.12 }, AfficheOrcGrande = { 0.145, 0.119, 0.123, 0.095 },
    AfficheRoublardCarree = { 0.121, 0.135, 0.135, 0.108 }, AfficheRoublardGrande = { 0.143, 0.119, 0.134, 0.082 },
    AfficheTaurenCarree = { 0.106, 0.148, 0.102, 0.097 }, AfficheTaurenGrande = { 0.12, 0.108, 0.117, 0.084 },
    AfficheTrollCarree = { 0.123, 0.125, 0.114, 0.11 }, AfficheTrollGrande = { 0.145, 0.132, 0.113, 0.083 },
    PrimeAerienCarree = { 0.091, 0.136, 0.105, 0.099 }, PrimeAerienGrande = { 0.111, 0.124, 0.116, 0.078 },
    PrimeDemonisteCarree = { 0.132, 0.169, 0.133, 0.106 }, PrimeDemonisteGrande = { 0.124, 0.141, 0.115, 0.084 },
    PrimeElfeNuitCarree = { 0.119, 0.127, 0.132, 0.136 }, PrimeElfeNuitGrande = { 0.102, 0.088, 0.111, 0.071 },
    PrimeElfeSangCarree = { 0.088, 0.135, 0.108, 0.108 }, PrimeElfeSangGrande = { 0.103, 0.105, 0.114, 0.091 },
    PrimeHumainCarree = { 0.113, 0.127, 0.104, 0.107 }, PrimeHumainGrande = { 0.117, 0.099, 0.102, 0.089 },
    PrimeMortVivantCarree = { 0.103, 0.112, 0.103, 0.112 }, PrimeMortVivantGrande = { 0.131, 0.087, 0.136, 0.072 },
    PrimeOrcCarree = { 0.109, 0.104, 0.118, 0.12 }, PrimeOrcGrande = { 0.138, 0.108, 0.114, 0.088 },
    PrimeRoublardCarree = { 0.108, 0.129, 0.119, 0.11 }, PrimeRoublardGrande = { 0.127, 0.119, 0.131, 0.084 },
    PrimeTaurenCarree = { 0.107, 0.148, 0.103, 0.099 }, PrimeTaurenGrande = { 0.116, 0.107, 0.116, 0.085 },
    PrimeTrollCarree = { 0.122, 0.121, 0.115, 0.107 }, PrimeTrollGrande = { 0.145, 0.134, 0.114, 0.083 },
    -- Tribal papers: the largest plain rectangle around their centre, clear of the painted motifs.
    AfficheOrcChef = { 0.145, 0.202, 0.168, 0.11 }, AfficheOrcGuerre = { 0.176, 0.181, 0.114, 0.093 },
    AfficheTrollMarais = { 0.184, 0.181, 0.129, 0.118 }, AfficheGnollMarais = { 0.106, 0.168, 0.121, 0.131 },
    AfficheGnollRavins = { 0.106, 0.158, 0.137, 0.126 }, AfficheOgreChef = { 0.168, 0.155, 0.184, 0.181 },
}
