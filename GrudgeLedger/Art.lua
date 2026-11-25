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
}
