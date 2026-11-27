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
    FanionAlliance = 1.204, FanionHorde = 0.844, EmblemeAlliance = 1.207, EmblemeHorde = 0.641,
    FiligraneAlliance = 1.207, FiligraneHorde = 0.641,
    AfficheGrande1 = 0.665, AfficheGrande2 = 0.695, AfficheCarree1 = 0.982, AfficheCarree2 = 0.96,
    PrimeGrande1 = 0.667, PrimeGrande2 = 0.706, PrimeCarree1 = 0.991, PrimeCarree2 = 0.963,
    CadrePortrait = 1.006, Medaillon = 0.989, MedaillonUn = 0.975, Bandeau = 5.066, SceauPrime = 0.989, Tampon = 4.094,
    Cartouche = 7.659, SeparateurEncre = 28.06, SeparateurOr = 19.363, IconeMembres = 1.685, IconeCrane = 0.913,
    ClouFace = 0.725, ClouGauche = 1.011, ClouDroite = 0.73, Chevron = 1.667,
}
-- The forged nails (v6) are drawn in perspective: where the point enters the paper, in fractions of
-- the drawing from its top left. The Alliance banner gives its lion's place (left, top, right, bottom).
GL.Art.WantedNail = { ClouFace = { 0.659, 0.933 }, ClouGauche = { 0.869, 0.971 }, ClouDroite = { 0.108, 0.921 } }
GL.Art.WantedEmblem = { Alliance = { 0.165, 0.173, 0.833, 0.84 } }
-- Where the posters' papers take writing (v5, 27/11): margins left, top, right, bottom in fractions of
-- the drawing, inside its printed frame (tools/import_wanted_kit.py prints them). 1 and 2 are the two
-- tilts drawn in the paper; the text itself stands straight.
GL.Art.WantedText = {
    AfficheGrande1 = { 0.134, 0.099, 0.122, 0.09 }, AfficheGrande2 = { 0.12, 0.101, 0.124, 0.081 },
    AfficheCarree1 = { 0.095, 0.123, 0.109, 0.127 }, AfficheCarree2 = { 0.1, 0.105, 0.093, 0.099 },
    PrimeGrande1 = { 0.136, 0.087, 0.128, 0.091 }, PrimeGrande2 = { 0.099, 0.103, 0.136, 0.081 },
    PrimeCarree1 = { 0.079, 0.112, 0.123, 0.132 }, PrimeCarree2 = { 0.094, 0.102, 0.104, 0.108 },
}
