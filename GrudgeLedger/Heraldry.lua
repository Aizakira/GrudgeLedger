-- The guilds' armorial (owner's kit, 26/11): fifteen crests and six alphabets, loaded after Art.lua.
-- Crests: centre of the monogram in a 128 px square, and its widest width.
-- Glyphs: the ink box (left, top, right excluded, bottom excluded) in a 64 px cell.
local GL = GrudgeLedger
GL.Art.GuildHeraldry = {
    root = "Interface\\AddOns\\GrudgeLedger\\Media\\",
    cell = 64,
    columns = 8,
    rows = 4,
    fields = { file = "GuildCrestFields", columns = 8, rows = 16 },
    patterns = { "Uni", "Parti", "Coupé", "Bande", "Chevron", "Pal" },
    palettes = {
        { base = { 0.13333, 0.27059, 0.46667 }, accent = { 0.65098, 0.68235, 0.71765 } }, -- Outremer
        { base = { 0.43922, 0.25098, 0.16078 }, accent = { 0.88627, 0.64314, 0.37255 } }, -- Braise
        { base = { 0.50588, 0.21961, 0.18039 }, accent = { 0.18824, 0.18039, 0.23922 } }, -- Carmin
        { base = { 0.34510, 0.26667, 0.44314 }, accent = { 0.74510, 0.69412, 0.78824 } }, -- Améthyste
        { base = { 0.14510, 0.39216, 0.39216 }, accent = { 0.77647, 0.64706, 0.40784 } }, -- Jade
        { base = { 0.22353, 0.27451, 0.31373 }, accent = { 0.65490, 0.58431, 0.61176 } }, -- Ardoise
    },
    crests = {
        [1] = { file = "Crest1", x = 64, y = 65, width = 63 }, -- Hurlevent
        [2] = { file = "Crest2", x = 64, y = 65, width = 67 }, -- Forgefer
        [3] = { file = "Crest3", x = 64, y = 62, width = 62 }, -- Orgrimmar
        [4] = { file = "Crest4", x = 64, y = 64, width = 56 }, -- Kaldorei
        [5] = { file = "Crest5", x = 63, y = 63, width = 59 }, -- Sombrelances
        [6] = { file = "Crest6", x = 63, y = 61, width = 55 }, -- Réprouvés
        [7] = { file = "Crest7", x = 64, y = 65, width = 57 }, -- Mulgore
        [8] = { file = "Crest8", x = 64, y = 60, width = 45 }, -- Lune-d’Argent
        [9] = { file = "Crest9", x = 64, y = 65, width = 61 }, -- Gnomeregan
        [10] = { file = "Crest10", x = 64, y = 67, width = 58 }, -- Dalaran
        [11] = { file = "Crest11", x = 64, y = 65, width = 61 }, -- Kul Tiras
        [12] = { file = "Crest12", x = 64, y = 65, width = 57 }, -- Amani
        [13] = { file = "Crest13", x = 64, y = 67, width = 62 }, -- Sombrefer
        [14] = { file = "Crest14", x = 64, y = 65, width = 54 }, -- Cercle cénarien
        [15] = { file = "Crest15", x = 64, y = 64, width = 57, shadow = true }, -- Aube d’argent
    },
    alphabets = {
        [1] = {
            file = "LettersHurlevent",
            glyphs = {
                A = { 7, 9, 57, 54 },
                B = { 8, 9, 56, 54 },
                C = { 11, 9, 53, 54 },
                D = { 8, 9, 56, 54 },
                E = { 10, 9, 54, 54 },
                F = { 12, 9, 53, 54 },
                G = { 9, 9, 55, 54 },
                H = { 10, 9, 54, 54 },
                I = { 20, 9, 45, 54 },
                J = { 13, 9, 51, 56 },
                K = { 9, 9, 55, 54 },
                L = { 13, 9, 51, 54 },
                M = { 5, 9, 59, 54 },
                N = { 8, 9, 56, 54 },
                O = { 10, 9, 54, 53 },
                P = { 11, 9, 53, 54 },
                Q = { 11, 9, 53, 56 },
                R = { 10, 9, 54, 54 },
                S = { 13, 9, 51, 54 },
                T = { 12, 9, 52, 54 },
                U = { 9, 9, 56, 54 },
                V = { 8, 9, 56, 53 },
                W = { 5, 9, 59, 54 },
                X = { 7, 9, 57, 54 },
                Y = { 8, 9, 56, 54 },
                Z = { 11, 9, 53, 54 },
            },
        },
        [3] = {
            file = "LettersChanteguerre",
            glyphs = {
                A = { 11, 9, 53, 53 },
                B = { 10, 10, 55, 53 },
                C = { 12, 9, 52, 54 },
                D = { 9, 9, 55, 53 },
                E = { 11, 9, 53, 53 },
                F = { 12, 9, 52, 53 },
                G = { 10, 10, 54, 54 },
                H = { 10, 9, 55, 53 },
                I = { 16, 10, 48, 53 },
                J = { 11, 10, 54, 56 },
                K = { 11, 10, 53, 53 },
                L = { 13, 9, 50, 53 },
                M = { 10, 10, 55, 53 },
                N = { 9, 9, 55, 53 },
                O = { 10, 9, 54, 53 },
                P = { 11, 10, 53, 53 },
                Q = { 13, 10, 51, 56 },
                R = { 12, 10, 52, 53 },
                S = { 11, 9, 53, 53 },
                T = { 14, 10, 51, 53 },
                U = { 13, 10, 51, 54 },
                V = { 13, 10, 51, 53 },
                W = { 11, 10, 54, 53 },
                X = { 11, 10, 53, 53 },
                Y = { 14, 9, 51, 53 },
                Z = { 11, 9, 53, 54 },
            },
        },
        [4] = {
            file = "LettersKaldorei",
            glyphs = {
                A = { 9, 9, 55, 53 },
                B = { 11, 9, 54, 53 },
                C = { 11, 9, 53, 54 },
                D = { 9, 9, 56, 53 },
                E = { 12, 9, 52, 53 },
                F = { 14, 9, 51, 53 },
                G = { 11, 9, 53, 53 },
                H = { 10, 9, 54, 53 },
                I = { 23, 9, 42, 53 },
                J = { 14, 9, 49, 56 },
                K = { 10, 9, 55, 53 },
                L = { 12, 9, 53, 53 },
                M = { 6, 9, 58, 53 },
                N = { 10, 9, 55, 53 },
                O = { 9, 9, 55, 54 },
                P = { 13, 9, 52, 54 },
                Q = { 11, 9, 53, 56 },
                R = { 11, 9, 53, 53 },
                S = { 15, 9, 50, 53 },
                T = { 13, 9, 51, 53 },
                U = { 11, 9, 54, 54 },
                V = { 9, 9, 55, 53 },
                W = { 6, 9, 58, 53 },
                X = { 10, 9, 55, 53 },
                Y = { 10, 9, 54, 53 },
                Z = { 11, 9, 53, 53 },
            },
        },
        [9] = {
            file = "LettersGnomeregan",
            glyphs = {
                A = { 9, 9, 55, 54 },
                B = { 9, 9, 55, 54 },
                C = { 13, 9, 52, 54 },
                D = { 10, 9, 54, 54 },
                E = { 12, 9, 52, 54 },
                F = { 12, 9, 52, 54 },
                G = { 13, 9, 51, 54 },
                H = { 12, 9, 53, 54 },
                I = { 20, 9, 44, 54 },
                J = { 13, 9, 51, 56 },
                K = { 11, 9, 53, 54 },
                L = { 11, 9, 53, 54 },
                M = { 7, 9, 57, 54 },
                N = { 10, 9, 54, 54 },
                O = { 10, 9, 54, 53 },
                P = { 12, 9, 52, 54 },
                Q = { 12, 9, 52, 56 },
                R = { 11, 9, 53, 54 },
                S = { 12, 9, 52, 54 },
                T = { 11, 9, 53, 54 },
                U = { 10, 9, 54, 54 },
                V = { 9, 9, 55, 54 },
                W = { 7, 9, 57, 54 },
                X = { 10, 9, 54, 54 },
                Y = { 11, 9, 53, 54 },
                Z = { 12, 9, 53, 54 },
            },
        },
        [18] = {
            file = "LettersKarazhan",
            glyphs = {
                A = { 9, 10, 55, 53 },
                B = { 12, 9, 53, 53 },
                C = { 10, 9, 54, 54 },
                D = { 7, 9, 58, 53 },
                E = { 11, 10, 53, 53 },
                F = { 12, 10, 52, 53 },
                G = { 10, 10, 54, 53 },
                H = { 9, 9, 55, 53 },
                I = { 17, 9, 47, 53 },
                J = { 16, 9, 48, 56 },
                K = { 8, 9, 56, 53 },
                L = { 10, 9, 54, 53 },
                M = { 8, 9, 56, 53 },
                N = { 8, 9, 56, 53 },
                O = { 11, 9, 53, 54 },
                P = { 10, 10, 54, 53 },
                Q = { 10, 9, 54, 56 },
                R = { 9, 10, 55, 54 },
                S = { 16, 9, 49, 54 },
                T = { 9, 9, 55, 53 },
                U = { 9, 9, 55, 54 },
                V = { 7, 10, 56, 53 },
                W = { 5, 9, 59, 53 },
                X = { 7, 9, 57, 53 },
                Y = { 9, 9, 55, 53 },
                Z = { 13, 10, 52, 53 },
            },
        },
        [19] = {
            file = "LettersAmani",
            glyphs = {
                A = { 10, 9, 54, 54 },
                B = { 8, 9, 56, 54 },
                C = { 12, 9, 52, 54 },
                D = { 5, 9, 59, 53 },
                E = { 12, 9, 53, 54 },
                F = { 13, 9, 51, 54 },
                G = { 12, 9, 52, 54 },
                H = { 10, 9, 54, 54 },
                I = { 20, 9, 45, 54 },
                J = { 11, 9, 53, 56 },
                K = { 11, 9, 54, 54 },
                L = { 11, 9, 53, 54 },
                M = { 8, 9, 56, 54 },
                N = { 10, 9, 54, 54 },
                O = { 8, 9, 56, 54 },
                P = { 11, 9, 53, 54 },
                Q = { 11, 9, 54, 56 },
                R = { 11, 9, 53, 54 },
                S = { 11, 9, 53, 54 },
                T = { 11, 9, 53, 54 },
                U = { 10, 9, 54, 54 },
                V = { 7, 9, 57, 54 },
                W = { 4, 12, 60, 54 },
                X = { 8, 9, 56, 54 },
                Y = { 8, 9, 56, 54 },
                Z = { 10, 9, 54, 54 },
            },
        },
    },
}

local H = GL.Art.GuildHeraldry
-- The valid alphabets, in a fixed order: a guild keeps its letters from one visit to the next.
H.alphabetIds = { 1, 3, 4, 9, 18, 19 }
-- The crest follows the guild's side (owner, 26/11): the Horde's banners for a Horde guild, the
-- Alliance's for an Alliance one; Dalaran, the Cenarion Circle and the Argent Dawn go to both.
-- A guild whose side is unknown may get any of the fifteen.
H.families = {
    Horde = { 3, 5, 6, 7, 8, 12, 10, 14, 15 },
    Alliance = { 1, 2, 4, 9, 11, 13, 10, 14, 15 },
    any = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
}

local function seed(text)
    local h = 5381
    text = tostring(text or ""):lower()
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
    return h
end

-- Always the same crest for the same guild: its key (name and realm) is the seed.
function H.Choose(key, faction)
    local h = seed(key)
    local family = H.families[faction] or H.families.any
    return {
        crest = family[h % #family + 1],
        alphabet = H.alphabetIds[math.floor(h / 16) % #H.alphabetIds + 1],
        -- Pattern 1 leaves the crest in its own colours; 2 to 6 lay a motif over it.
        pattern = math.floor(h / 97) % #H.patterns + 1,
        palette = math.floor(h / 613) % #H.palettes + 1,
    }
end

-- The capitals drawn from the alphabets: an accented letter gives its plain one ("É" gives "E").
-- Any other letter (a digit, another script) returns nil, and the page writes the initials as text.
local plain = {}
for letter, variants in pairs({
    A = "ÀÁÂÃÄÅàáâãäåÆæ", C = "Çç", E = "ÈÉÊËèéêë", I = "ÌÍÎÏìíîï", N = "Ññ",
    O = "ÒÓÔÕÖØòóôõöøŒœ", U = "ÙÚÛÜùúûü", Y = "ÝŸýÿ",
}) do
    for character in variants:gmatch("[\194-\244][\128-\191]+") do plain[character] = letter end
end
function H.Letters(initials)
    local letters = {}
    for character in tostring(initials or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local letter = plain[character] or character:upper()
        if not letter:match("^[A-Z]$") then return nil end
        letters[#letters + 1] = letter
    end
    if #letters == 0 or #letters > 2 then return nil end
    return letters
end

-- Where each letter goes, in the crest's 128 px square (origin at the top left): one letter about
-- 39 px high and at most min(48, width) wide, a pair about 27 px high with 2 px between their inks,
-- the pair shrunk as a whole if wider than the crest allows. The group is centred on the crest's
-- centre; letters share their cell's top, so they keep a common baseline.
function H.Layout(crestId, alphabetId, letters)
    local crest, alphabet = H.crests[crestId], H.alphabets[alphabetId]
    if not crest or not alphabet or type(letters) ~= "table" or #letters == 0 then return nil end
    local boxes, tallest, minTop, maxBottom = {}, 0, math.huge, 0
    for i, letter in ipairs(letters) do
        local box = alphabet.glyphs[letter]
        if not box then return nil end
        boxes[i] = box
        tallest = math.max(tallest, box[4] - box[2])
        minTop, maxBottom = math.min(minTop, box[2]), math.max(maxBottom, box[4])
    end
    local scale = (#letters == 1 and 39 or 27) / tallest
    local gap = #letters == 1 and 0 or 2
    local width = gap * (#letters - 1)
    for _, box in ipairs(boxes) do width = width + (box[3] - box[1]) * scale end
    local limit = #letters == 1 and math.min(48, crest.width) or crest.width
    if width > limit then
        local factor = limit / width
        scale, gap, width = scale * factor, gap * factor, limit
    end
    local top = crest.y - (maxBottom - minTop) * scale / 2 - minTop * scale
    local x, placed = crest.x - width / 2, {}
    for i, box in ipairs(boxes) do
        local cell = letters[i]:byte() - 65
        placed[i] = {
            letter = letters[i], col = cell % H.columns, row = math.floor(cell / H.columns),
            left = x - box[1] * scale, top = top, side = H.cell * scale,
            ink = { x, top + box[2] * scale, x + (box[3] - box[1]) * scale, top + box[4] * scale },
        }
        x = x + (box[3] - box[1]) * scale + gap
    end
    return placed
end
