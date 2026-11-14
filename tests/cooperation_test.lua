-- Exercise the shipped TOC, the native trade peer (independent of targeting),
-- and the roster clock. No real contacts or transactions.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL, fire, units = GrudgeLedger, mock.Fire, mock.units
local function click(b) b:GetScript("OnClick")(b) end
local now, area = 1000, "none"
GetServerTime = function() return now end
IsInInstance = function() return area ~= "none", area end
ERR_TRADE_COMPLETE, ERR_TRADE_CANCELLED = "Échange terminé.", "Échange annulé."
local aqua = GL.SetReaction(GL.Identity("target"), "friend")
local merchant = {name="Alix", surname="Exemple", guid="Player-8-alix"}
units.npc = merchant
local alix = GL.SetReaction(GL.Identity("npc"), "enemy")
GetPlayerTradeMoney = function() return 10203 end
GetTargetTradeMoney = function() return 400 end
GetTradePlayerItemInfo = function(i) if i == 1 then return "Étoffe", 121, 4 elseif i == 7 then return "Épée à enchanter", 121, 1 end end
GetTradeTargetItemInfo = function(i) if i == 1 then return "Silex", 32, 1 end end
local function complete() fire("UI_INFO_MESSAGE", 123, ERR_TRADE_COMPLETE) end
local function trades(record)
    local list = {}
    for _, e in ipairs(record.history) do if e.kind == "trade" then list[#list+1] = e end end
    return list
end
local function exchange()
    fire("TRADE_SHOW") fire("TRADE_ACCEPT_UPDATE", 1, 1) fire("TRADE_CLOSED") complete()
end
exchange()
assert(#trades(alix) == 0 and GL.Settings().tradeTracking == false)
GL.SetSetting("tradeTracking", true)
exchange()
local e = assert(trades(alix)[1])
assert(e.kind == "trade" and e.actorGUID == units.player.guid and e.opponentName == "Alix Exemple")
assert(e.evidence == "Donné : 1 po 2 pa 3 pc, Étoffe ×4\nReçu : 4 pa, Silex")
assert(#trades(aqua) == 0 and alix.reputation == -10 and GL.Relation(alix) == "enemy")
assert(#GL.JournalEvents({kind="trade",query="silex"}) == 1 and #GL.JournalEvents({kind="trade",scope="legacy"}) == 0)
complete() assert(#trades(alix) == 1, "duplicate receipt")
fire("TRADE_SHOW") fire("TRADE_REQUEST_CANCEL") complete()
assert(#trades(alix) == 1)
fire("TRADE_SHOW") fire("UI_INFO_MESSAGE",1,ERR_TRADE_CANCELLED) complete()
assert(#trades(alix) == 1, "cancelled trade")
fire("TRADE_SHOW") fire("TRADE_CLOSED") now = now + 7 complete()
assert(#trades(alix) == 1, "stale receipt")
fire("TRADE_SHOW") fire("TRADE_CLOSED") fire("TRADE_SHOW") complete()
assert(#trades(alix) == 1, "receipt from prior window cannot settle the new one")
now = now + 7
fire("TRADE_SHOW") units.npc = units.target fire("TRADE_UPDATE") complete()
assert(#trades(alix) == 1 and #trades(aqua) == 0, "peer changed within same trade")
units.npc = nil
exchange() assert(#trades(aqua) == 0, "a selected target never substitutes for the missing peer")
units.npc = {name="Stranger",surname="From Elsewhere",guid="Player-99-unknown"}
exchange() assert(not GL.Get(GL.Identity("npc")), "trade with a stranger does not enter the ledger")
units.npc = merchant
fire("TRADE_SHOW") GL.SetSetting("tradeTracking", false) GL.SetSetting("tradeTracking", true) complete()
area = "pvp" exchange() area = "none" assert(#trades(alix) == 1)
GetPlayerTradeMoney = function() return mock.secret end
GetTargetTradeMoney = function() return -1 end
GetTradePlayerItemInfo = function(i) if i == 1 then return "|cfffake", 0, 2 end end
GetTradeTargetItemInfo = function() return mock.secret end
exchange()
assert(#trades(alix) == 2 and trades(alix)[2].evidence == "", "unavailable offer details must never be invented")
GL.SetSetting("guideSeen",true) GL.ShowLedger(alix.key)
local book = GrudgeLedgerWindow
click(book.detailTabs.history) click(book.historyPage.options.trade)
assert(book.historyPage.rows[2].title:GetText() == "Échange terminé" and book.historyPage.rows[2].hint:GetText():find("Étoffe",1,true))
click(book.historyPage.rows[2].details)
assert(GrudgeLedgerCorrections.proof:GetText():find("Donné : 1 po 2 pa 3 pc",1,true))
local oldactor = units.player.guid
units.player.guid = "Player-7-another"
assert(#GL.JournalEvents({kind="trade",scope="character"}) == 0)
units.player.guid = oldactor

local online, selfOnline = true, true
UnitIsConnected = function(unit) return unit == "player" and selfOnline or unit == "party1" and online end
GetNumGroupMembers = function() return 2 end
units.party1 = units.target
fire("GROUP_ROSTER_UPDATE")
local session = aqua.history[#aqua.history]
assert(session.kind == "grouped" and GL.GroupDuration(session) == 0)
now = now + 90 fire("GROUP_ROSTER_UPDATE") assert(GL.GroupDuration(session) == 90)
online = false fire("UNIT_CONNECTION","party1")
now = now + 150 assert(GL.GroupDuration(session) == 90)
online = true fire("UNIT_CONNECTION","party1") now = now + 30
selfOnline = false fire("UNIT_CONNECTION","player")
now = now + 90 assert(GL.GroupDuration(session) == 120, "observer disconnected")
selfOnline = true fire("UNIT_CONNECTION","player")
GL.SetSetting("groupTracking",false) assert(GL.GroupDuration(session) == 120)
now = now + 600 GL.SetSetting("groupTracking",true) now = now + 60
fire("PLAYER_LEAVING_WORLD") now = now + 120 fire("GROUP_ROSTER_UPDATE")
area="pvp" fire("PLAYER_ENTERING_WORLD") now = now + 120 fire("PLAYER_LEAVING_WORLD")
area="none" fire("PLAYER_ENTERING_WORLD") now = now + 60 fire("PLAYER_LOGOUT")
assert(session.seconds == 240 and aqua.groupCount == 1 and GL.Relation(aqua) == "friend")
local ranked = GL.PlayerStatistics("friendsOnline")
assert(#ranked == 1 and ranked[1].record == aqua and ranked[1].value == 240)
GL.ShowStatistics("players")
local stats = GrudgeLedgerStatistics
click(stats.groups[2]) click(stats.choices[5])
assert(stats.rows[1].item.record == aqua and stats.rows[1].value:GetText() == "4 min")
GL.ShowLedger(aqua.key) click(book.detailTabs.history) click(book.historyPage.options.group)
assert(book.historyPage.rows[1].title:GetText():find("4 min en ligne",1,true))
assert(#GL.errors == 0)
print("PASS cooperation: successful trade receipt, immutable peer, directional items and money, privacy, scope, filters, incomplete data, live roster time, disconnected and PvP exclusions")
