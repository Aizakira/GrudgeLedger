-- Forever passes the incoming event and all chat fields, after applying class colors.
local GL = GrudgeLedger

local badges = {}
for _, relation in ipairs({ "Friend", "Warning", "Enemy", "Neutral" }) do
    badges[relation:lower()] = "|TInterface\\AddOns\\GrudgeLedger\\Media\\Relation" .. relation .. ":14:14|t "
end
local channels = { CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_WHISPER = true,
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_CHANNEL = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true }
local function decorate(event, decoratedName, ...)
    if not GL.Settings().chatBadges or not channels[GL.Clean(event, "string")] then return end
    local guid = GL.Clean(select(12, ...), "string")
    if not guid or #guid > 128 or not guid:match("^Player%-%w") then return end
    local record = GL.Get("guid:" .. guid)
    if record and record.guid == guid and GL.Clean(decoratedName, "string") and not GL.IsPvPInstance() and not GL.IsGroupOnly(record) then
        return badges[GL.Relation(record)] .. decoratedName
    end
end
local installed = false
local function configure()
    if not (ChatFrameUtil and type(ChatFrameUtil.AddSenderNameFilter) == "function"
        and type(ChatFrameUtil.RemoveSenderNameFilter) == "function") then return end
    local enabled = GL.Settings().chatBadges
    if installed ~= enabled then
        local change = enabled and ChatFrameUtil.AddSenderNameFilter or ChatFrameUtil.RemoveSenderNameFilter
        if pcall(change, decorate) then installed = enabled end
    end
end
GL.On("READY", configure)
GL.On("SETTINGS", configure)
