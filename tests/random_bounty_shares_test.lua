-- Randomised bounty shares (25/11): orders drawn at random, a winner with up to five helpers, pots
-- from several payers, mails sent and arrived in random pieces that may overlap. Rules that must
-- always hold: the shares of a pot add up to the pot, nobody outside the group gets anything, what
-- is due or still awaited stays between nothing and the share, and an arrival never makes more due.
-- Synthetic members only. Deterministic.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL = GrudgeLedger
local B = GL.Bounties
local seed = 4242
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648 return math.floor(seed / 65536) % n + 1 end
local members = {}
for i = 1, 8 do members[i] = ("Player-1-m%07d"):format(i) end
for run = 1, 3000 do
    local label = "run " .. run .. ": "
    -- The group: a winner and distinct helpers, in any order.
    local pool = {}
    for i = 1, #members do pool[i] = members[i] end
    for i = #pool, 2, -1 do
        local j = rnd(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local helpers = {}
    for i = 2, rnd(6) do helpers[#helpers + 1] = pool[i] end
    local group = { [pool[1]] = true }
    for _, h in ipairs(helpers) do group[h] = true end
    local o = { winner = { actor = pool[1], detail = table.concat(helpers, ",") }, pot = {}, paid = {}, arrivals = {} }
    local payers = {}
    for i = 1, rnd(3) do
        local payer = members[rnd(#members)]
        if not o.pot[payer] then
            o.pot[payer] = rnd(3) == 1 and rnd(7) or rnd(500000)
            payers[#payers + 1] = payer
        end
    end
    for _, payer in ipairs(payers) do
        local sum, kept = 0, 0
        for _, hunter in ipairs(members) do
            local mail, keep = B.Share(o, payer, hunter)
            assert(mail >= 0 and keep >= 0 and mail == math.floor(mail), label .. "share")
            if not group[hunter] then assert(mail == 0 and keep == 0, label .. "outside the group") end
            if payer == hunter then assert(mail == 0, label .. "nobody mails themself") end
            sum, kept = sum + mail, kept + keep
        end
        assert(sum + kept == o.pot[payer], label .. ("shares %d + %d for a pot of %d"):format(sum, kept, o.pot[payer]))
        -- Mails and arrivals, in pieces that may overlap or go past the share.
        for _, hunter in ipairs(members) do
            local share = B.Share(o, payer, hunter)
            if share > 0 then
                local pair = payer .. "/" .. hunter
                local before = B.Payment(o, payer, hunter)
                assert(before == share, label .. "nothing sent, all due")
                if rnd(2) == 1 then o.paid[pair] = rnd(share + 10) - 1 end
                o.arrivals[pair] = {}
                for _ = 1, rnd(4) - 1 do
                    -- Arrivals only grow: a second piece at the same place keeps the longer one.
                    local at, length = rnd(share + 5) - 1, rnd(share + 5)
                    o.arrivals[pair][at] = math.max(o.arrivals[pair][at] or 0, length)
                    local due, awaited, arrived = B.Payment(o, payer, hunter)
                    assert(due >= 0 and due <= share and awaited >= 0 and awaited <= share, label .. "due or awaited out of bounds")
                    assert(arrived >= 0 and arrived <= share and arrived + awaited == share, label .. ("arrived %d awaited %d share %d"):format(arrived, awaited, share))
                    assert(due <= before, label .. "an arrival made more due")
                    before = due
                    assert(B.Due(o, payer, hunter) == due, label .. "Due is Payment")
                end
            end
        end
    end
end
assert(#GL.errors == 0, GL.errors[1] and GL.errors[1].text)
print("PASS random bounty shares: 3000 orders, shares add up to the pot, bounds hold, arrivals only lower what is due")
