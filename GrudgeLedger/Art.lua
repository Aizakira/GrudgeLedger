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
    FanionAlliance = 0.753, FanionHorde = 0.844, EmblemeAlliance = 0.754, EmblemeHorde = 0.645,
    AfficheGrande = 0.638, AfficheMoyenne = 0.755, AffichePetite = 1.014,
    PrimeGrande = 0.621, PrimeMoyenne = 0.758, PrimePetite = 1.065,
    CadrePortrait = 1.006, Medaillon = 0.966, Bandeau = 5.985, SceauPrime = 0.989, Tampon = 4.094,
    Cartouche = 7.659, SeparateurEncre = 28.06, SeparateurOr = 19.363, IconeMembres = 1.685, IconeCrane = 0.913,
    ClouLaiton = 0.953, ClouFer = 0.976,
}
