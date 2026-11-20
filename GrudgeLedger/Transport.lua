-- The single door between Grudge Ledger and the guild addon channel.
-- Other modules hand over finished messages; this file sends, retries, receives,
-- splits long bodies and reassembles them. It knows nothing about bounties or dossiers.
local GL = GrudgeLedger
local T = {}
GL.Transport = T

local PREFIX = "GLBounty1"
-- Long transfers are only sent after every pending bounty or guild-card message.
local urgent, bulk = {}, {}
local queuedText = {}
local batches = {}
local active
local receiver

-- Enum.SendAddonMessageResult on Forever 1.60.1 (build 70959).
local SUCCESS = 0
-- Temporary refusals: keep the message and try again on a later tick.
local WAIT = { [3] = true, [8] = true, [11] = true }
local GENERAL_ERROR = 9
-- A message refused for an unknown reason is retried three times, then dropped.
local MAX_ATTEMPTS = 3
-- 512 waiting fragments is about eight minutes of sending at the game's sustained rate.
local BULK_LIMIT = 512

local function reset(scope)
    if active == scope then
        return
    end
    active = scope
    urgent = {}
    bulk = {}
    queuedText = {}
    batches = {}
end

function T.Available()
    return C_ChatInfo ~= nil and C_ChatInfo.RegisterAddonMessagePrefix ~= nil and C_ChatInfo.SendAddonMessage ~= nil
        and C_Timer ~= nil and C_Timer.NewTicker ~= nil
end

-- Bounty events, catch-up and guild cards: one message each, sent first.
function T.Send(scope, text)
    reset(scope)
    if queuedText[text] then
        return
    end
    queuedText[text] = true
    urgent[#urgent + 1] = { text = text }
end

-- A batch of fragments sent in order after urgent messages.
-- opts.key names the batch so it can be cancelled before its first fragment leaves.
-- opts.delay holds the batch back for that many seconds.
function T.SendBatch(scope, messages, opts)
    reset(scope)
    opts = opts or {}
    if #bulk + #messages > BULK_LIMIT then
        return false
    end
    local batch = { key = opts.key, due = GL.Now() + (opts.delay or 0), started = false }
    for _, text in ipairs(messages) do
        bulk[#bulk + 1] = { text = text, batch = batch }
    end
    if batch.key then
        batches[batch.key] = batch
    end
    return true
end

-- "queued" while no fragment has left, "sending" afterwards, nil once finished or unknown.
function T.State(scope, key)
    if active ~= scope then
        return nil
    end
    local batch = batches[key]
    if not batch then
        return nil
    end
    return batch.started and "sending" or "queued"
end

local function removeBatch(batch)
    local kept = {}
    for _, item in ipairs(bulk) do
        if item.batch ~= batch then
            kept[#kept + 1] = item
        end
    end
    bulk = kept
    if batch.key and batches[batch.key] == batch then
        batches[batch.key] = nil
    end
end

-- Removes a batch that has not started. A started batch finishes so receivers are not left with half a transfer.
function T.Cancel(scope, key)
    if active ~= scope then
        return false
    end
    local batch = batches[key]
    if not batch or batch.started then
        return false
    end
    removeBatch(batch)
    return true
end

function T.Pending(scope)
    if active ~= scope then
        return 0, 0
    end
    return #urgent, #bulk
end

function T.Split(body, size)
    local parts = {}
    for first = 1, #body, size do
        parts[#parts + 1] = body:sub(first, first + size - 1)
    end
    return parts
end

-- Reassembly with bounded memory.
-- A transfer opens only on its first fragment, a sender has one open transfer at a time,
-- fragments must follow in order and a silent transfer expires.
function T.Reassembler(limits)
    local open = {}
    local assembler = {}
    function assembler.Add(sender, id, part, total, body)
        local now = GL.Now()
        local count = 0
        for key, transfer in pairs(open) do
            if now - transfer.last > limits.idle then
                open[key] = nil
            else
                count = count + 1
            end
        end
        local transfer = open[sender]
        if part == 1 then
            if transfer and transfer.id == id and transfer.parts[1] == body then
                return nil
            end
            if not transfer and count >= limits.slots then
                return nil
            end
            transfer = { id = id, total = total, parts = {}, last = now }
            open[sender] = transfer
        elseif not transfer or transfer.id ~= id or transfer.total ~= total then
            return nil
        end
        local received = #transfer.parts
        if part <= received then
            if transfer.parts[part] ~= body then
                open[sender] = nil
            end
            return nil
        end
        if part ~= received + 1 then
            open[sender] = nil
            return nil
        end
        transfer.parts[part] = body
        transfer.last = now
        if part < total then
            return nil
        end
        open[sender] = nil
        return table.concat(transfer.parts)
    end
    function assembler.Open()
        local n = 0
        for _ in pairs(open) do
            n = n + 1
        end
        return n
    end
    return assembler
end

function T.OnReceive(handler)
    receiver = handler
end

local function nextItem()
    if urgent[1] then
        return urgent, urgent[1]
    end
    local item = bulk[1]
    if item and item.batch.due <= GL.Now() then
        return bulk, item
    end
end

local function finish(lane, item)
    table.remove(lane, 1)
    if lane == urgent then
        queuedText[item.text] = nil
        return
    end
    local batch = item.batch
    local following = bulk[1]
    if not following or following.batch ~= batch then
        if batch.key and batches[batch.key] == batch then
            batches[batch.key] = nil
        end
    end
end

local function drop(lane, item)
    if lane == urgent then
        finish(lane, item)
        return
    end
    -- The rest of a batch is useless once one of its fragments is lost.
    removeBatch(item.batch)
end

local function messagingLocked()
    local check = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not check then
        return false
    end
    local ok, locked = pcall(check)
    return ok and locked == true
end

local function tick()
    -- Messages queued for a guild the player has left are never sent to the new one.
    if not active or not GL.Bounties or GL.Bounties.GuildScope() ~= active or messagingLocked() then
        return
    end
    local lane, item = nextItem()
    if not item then
        return
    end
    if lane == bulk then
        item.batch.started = true
    end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, "GUILD")
    -- Older clients return nothing or a boolean; Forever returns a result code.
    if ok and (result == nil or result == true or result == SUCCESS) then
        finish(lane, item)
        return
    end
    if ok and WAIT[result] then
        return
    end
    if not ok or result == false or result == GENERAL_ERROR then
        item.attempts = (item.attempts or 0) + 1
        if item.attempts < MAX_ATTEMPTS then
            return
        end
    end
    drop(lane, item)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if not T.Available() then
        return
    end
    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        -- Two attempts per second; the game's own limit answers 3 when the prefix allowance is spent.
        C_Timer.NewTicker(0.5, tick)
        return
    end
    if prefix ~= PREFIX or channel ~= "GUILD" or not receiver then
        return
    end
    receiver(text, sender)
end)
