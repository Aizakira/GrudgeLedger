-- The guilds' armorial (owner's kit, 26/11): a crest of the guild's side, always the same for the
-- same guild, and letters that stay inside it, for every crest, alphabet and pair of capitals.
-- Synthetic guilds only.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local H = GL.Art.GuildHeraldry
assert(H and H.Choose and H.Layout and H.Letters, "the armorial is loaded after Art.lua")

-- Every crest and every alphabet named by the catalogue, with all 26 capitals.
for id = 1, 15 do assert(H.crests[id] and H.crests[id].file == "Crest" .. id, "crest " .. id) end
for _, id in ipairs(H.alphabetIds) do
    local alphabet = assert(H.alphabets[id], "alphabet " .. id)
    for code = 65, 90 do assert(alphabet.glyphs[string.char(code)], id .. ": " .. string.char(code)) end
end

-- The side chooses the family, and the same guild always gets the same crest.
local allianceOnly, hordeOnly = { [1] = true, [2] = true, [4] = true, [9] = true, [11] = true, [13] = true },
    { [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [12] = true }
local seen, mixed = { Horde = {}, Alliance = {}, any = {} }, 0
for i = 1, 600 do
    local key = "guild:Synthetic Guild " .. i .. "-Realm" .. (i % 7)
    local horde, alliance, any = H.Choose(key, "Horde"), H.Choose(key, "Alliance"), H.Choose(key, nil)
    assert(not allianceOnly[horde.crest], key .. ": a Horde guild under an Alliance banner")
    assert(not hordeOnly[alliance.crest], key .. ": an Alliance guild under a Horde banner")
    local again = H.Choose(key:upper(), "Horde")
    assert(again.crest == horde.crest and again.alphabet == horde.alphabet and again.alphabet2 == horde.alphabet2
        and again.pattern == horde.pattern,
        key .. ": the crest changes from one visit to the next")
    for side, choice in pairs({ Horde = horde, Alliance = alliance, any = any }) do
        seen[side][choice.crest] = true
        assert(H.alphabets[choice.alphabet] and H.alphabets[choice.alphabet2] and H.patterns[choice.pattern]
            and H.palettes[choice.palette], key .. ": a valid choice")
        if choice.alphabet ~= choice.alphabet2 then mixed = mixed + 1 end
    end
end
local function count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end
assert(count(seen.Horde) == 9 and count(seen.Alliance) == 9 and count(seen.any) == 15, "every crest of a family is used")
-- The two letters mostly come from two alphabets (owner, 26/11), sometimes from the same one.
assert(mixed > 1200 and mixed < 1800, "mixed alphabets: " .. mixed .. " of 1800")

-- Letters: the plain capital of an accented one, nothing the alphabets cannot draw.
local function same(a, b) return table.concat(a or {}, ",") == table.concat(b or {}, ",") end
assert(same(H.Letters("OB"), { "O", "B" }) and same(H.Letters("D"), { "D" }), "plain capitals")
assert(same(H.Letters("ÉØ"), { "E", "O" }) and same(H.Letters("ç"), { "C" }), "accented capitals")
assert(H.Letters("") == nil and H.Letters("1") == nil and H.Letters("Д") == nil and H.Letters("ABC") == nil, "no letters to draw")

-- Every crest, alphabet, single capital and pair: the ink stays inside the crest's width, centred
-- on its centre, the two letters never touch, and nothing leaves the 128 px square.
local checked = 0
for crestId, crest in ipairs(H.crests) do
    for _, alphabetId in ipairs(H.alphabetIds) do
      for _, alphabet2 in ipairs(H.alphabetIds) do
        for a = 65, 90 do
            for b = alphabet2 == alphabetId and 64 or 65, 90 do
                local letters = b == 64 and { string.char(a) } or { string.char(a), string.char(b) }
                local placed = assert(H.Layout(crestId, { alphabetId, alphabet2 }, letters), "a layout")
                assert(placed[#placed].alphabet == (#letters == 1 and alphabetId or alphabet2), "each letter its alphabet")
                local left, right = placed[1].ink[1], placed[#placed].ink[3]
                local width = #letters == 1 and math.min(48, crest.width) or crest.width
                assert(right - left <= width + 0.01, ("%d/%d %s: wider than the crest"):format(crestId, alphabetId, table.concat(letters)))
                assert(math.abs((left + right) / 2 - crest.x) < 0.01, "centred across")
                if #letters == 2 then assert(placed[2].ink[1] - placed[1].ink[3] > 0, "the pair does not touch") end
                for _, spot in ipairs(placed) do
                    assert(spot.ink[2] >= 0 and spot.ink[4] <= 128 and spot.ink[1] >= 0 and spot.ink[3] <= 128, "inside the square")
                    assert(spot.ink[4] - spot.ink[2] <= (#letters == 1 and 39 or 27) + 0.01, "not taller than asked")
                end
                checked = checked + 1
            end
        end
      end
    end
end

-- The page: drawn letters on the crest, the initials as text only when no alphabet can draw them.
local R = GL.RelationsPages
local frame = R.CrestFrame(UIParent, 38)
R.PaintCrest(frame, { key = "guild:ok bodycount-realm", name = "Ok Bodycount", faction = "Horde" })
assert(frame.placed and #frame.placed == 2 and frame.label:GetText() == "", "two drawn letters")
assert(not allianceOnly[frame.choice.crest], "a Horde crest")
R.PaintCrest(frame, { key = "guild:42-realm", name = "42 Club" })
assert(frame.placed and #frame.placed == 1, "the digit is skipped, the C is drawn")
R.PaintCrest(frame, { key = "guild:1337-realm", name = "1337" })
assert(frame.placed == nil and frame.label:GetText() == "", "no letter at all: nothing drawn, no text")

-- The side of a guild: most of its known members.
GL.db.players = {
    a = { key = "a", guild = "Synthetic Order", realm = "Realm", faction = "Horde", history = {}, pvp = {} },
    b = { key = "b", guild = "Synthetic Order", realm = "Realm", faction = "Horde", history = {}, pvp = {} },
    c = { key = "c", guild = "Synthetic Order", realm = "Realm", faction = "Alliance", history = {}, pvp = {} },
    d = { key = "d", guild = "Even Order", realm = "Realm", faction = "Alliance", history = {}, pvp = {} },
    e = { key = "e", guild = "Even Order", realm = "Realm", faction = "Horde", history = {}, pvp = {} },
}
local sides = {}
for _, row in ipairs(GL.GuildStatistics()) do sides[row.name] = row.faction or "none" end
assert(sides["Synthetic Order"] == "Horde", "most members are Horde: " .. tostring(sides["Synthetic Order"]))
assert(sides["Even Order"] == "none", "an even split decides nothing")
print(("PASS heraldry: crests by side, %d layouts inside their crest, letters or text"):format(checked))
