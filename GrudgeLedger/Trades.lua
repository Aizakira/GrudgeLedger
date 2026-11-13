-- The native trade window uses the "npc" unit for its partner and six transferable slots.
-- https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/TradeFrame.lua
local GL = GrudgeLedger
local L = GL.L
local frame = CreateFrame("Frame")
local trade, ambiguousUntil
local events = { "TRADE_SHOW", "TRADE_UPDATE", "TRADE_MONEY_CHANGED", "PLAYER_TRADE_MONEY",
    "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_CLOSED",
    "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "PLAYER_LEAVING_WORLD", "PLAYER_ENTERING_WORLD" }

function GL.LocalizeTradeReceipt(text)
    return (text:gsub("[^\n]+", function(line)
        local label, contents = line:match("^(Donné) : (.+)$")
        if not label then label, contents = line:match("^(Reçu) : (.+)$") end
        if not label then return line end
        -- Only the first comma-delimited field can hold coin totals. Item names are native text.
        local first, rest = contents:match("^([^,]+)(.*)$")
        if first and first:gsub("%d+ p[oac]", ""):match("^%s*$") then
            contents = first:gsub("(%d+) (p[oac])", function(amount, unit)
                return L("%s " .. unit):format(amount)
            end) .. rest
        end
        return (label == "Donné" and L("Donné : %s") or L("Reçu : %s")):format(contents)
    end))
end

local function offered(moneyFn, itemFn)
    local parts = {}
    local money = GL.Clean(GL.Safe(moneyFn), "number")
    if money and money > 0 and money < 1e15 and money == math.floor(money) then
        local gold, silver, copper = math.floor(money / 10000), math.floor(money / 100) % 100, money % 100
        if gold > 0 then parts[#parts + 1] = gold .. " po" end
        if silver > 0 then parts[#parts + 1] = silver .. " pa" end
        if copper > 0 then parts[#parts + 1] = copper .. " pc" end
    end
    local coins = table.concat(parts, " ")
    parts = coins ~= "" and { coins } or {}
    for slot = 1, 6 do
        local name, _, count = GL.Safe(itemFn, slot)
        if type(name) == "string" and #name > 0 and #name <= 250 and not GL.ContainsControlOrMarkup(name) then
            count = GL.Clean(count, "number")
            local qty = count and count > 1 and count < 1e9 and count == math.floor(count)
            parts[#parts + 1] = qty and (name .. " ×" .. count) or name
        end
    end
    return table.concat(parts, ", ")
end

local function snapshot()
    local given = offered(GetPlayerTradeMoney, GetTradePlayerItemInfo)
    local received = offered(GetTargetTradeMoney, GetTradeTargetItemInfo)
    local lines = {}
    if given ~= "" then lines[#lines + 1] = "Donné : " .. given end
    if received ~= "" then lines[#lines + 1] = "Reçu : " .. received end
    return table.concat(lines, "\n")
end

local function handle(_, event, first, second)
    if not trade and event ~= "TRADE_SHOW" then return end
    if not GL.db or not GL.Settings().tradeTracking then trade, ambiguousUntil = nil, nil return end
    if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_ENTERING_WORLD" or GL.IsPvPInstance() then
        trade, ambiguousUntil = nil, nil
    elseif event == "TRADE_SHOW" then
        local now = GL.Now()
        -- ponytail: completion carries no trade ID. Suppress an ambiguous late receipt
        -- when a different window supersedes a still-unconfirmed trade.
        if trade and (not trade.closed or now - trade.closed <= 5) then ambiguousUntil = now + 5 end
        local partner = GL.Identity("npc")
        local record = partner and partner.guid and GL.Get(partner)
        trade = { partner = record and not GL.IsGroupOnly(record) and partner or nil }
        if trade.partner then trade.summary = snapshot() end
    elseif trade then
        if event == "TRADE_REQUEST_CANCEL" then
            trade = nil
        elseif event == "TRADE_CLOSED" then
            trade.closed = trade.closed or GL.Now()
        elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
            local msg = GL.Clean(second, "string") or GL.Clean(first, "string")
            if msg and ERR_TRADE_CANCELLED and msg == ERR_TRADE_CANCELLED then
                trade = nil
            elseif msg and ERR_TRADE_COMPLETE and msg == ERR_TRADE_COMPLETE then
                local completed, now = trade, GL.Now()
                trade = nil
                if completed.partner and (not completed.closed or now >= completed.closed and now - completed.closed <= 5)
                    and (not ambiguousUntil or now > ambiguousUntil) then
                    GL.RecordTrade(completed.partner, completed.summary)
                end
            end
        elseif trade.partner and not trade.closed then
            local guid = GL.Clean(GL.Safe(UnitGUID, "npc"), "string")
            if guid == trade.partner.guid then trade.summary = snapshot()
            elseif guid then trade.partner = nil
            else trade.summary = "" end
        end
    end
end

frame:SetScript("OnEvent", handle)
local enabled
local function configure()
    local wanted = GL.Settings().tradeTracking
    if wanted == enabled then return end
    enabled, trade, ambiguousUntil = wanted, nil, nil
    for _, event in ipairs(events) do
        if wanted then GL.Safe(frame.RegisterEvent, frame, event)
        else GL.Safe(frame.UnregisterEvent, frame, event) end
    end
end
GL.On("READY", configure)
GL.On("SETTINGS", configure)
