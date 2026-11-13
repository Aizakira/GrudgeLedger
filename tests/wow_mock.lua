-- Deterministic native-frame fixture shared by UI and integrated addon smoke tests.
local frames, messages, cvars, menuHooks = {}, {}, {}, {}
local secret = {}
function issecretvalue(v) return v == secret end
function time() return 1794400000 end
function GetServerTime() return time() end
function date() return "11/11/2026 12:00" end
function GetRealZoneText() return "Hurlevent" end
function GetSubZoneText() return "Quartier commerçant" end
local inCombat = false
function InCombatLockdown() return inCombat end
function SetCVar(k, v) cvars[k] = v end
function GetCVar(k) return cvars[k] and tostring(cvars[k]) or nil end
function GetCursorPosition() return 200, 200 end
UISpecialFrames, SlashCmdList = {}, {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
local units = {
    player = { name = "Testeur", surname = "Exemple", guid = "Player-1-self" },
    target = { name = "Aqua", surname = "Water", guid = "Player-1-aqua" },
    npc = { name = "Guard", guid = "Creature-1-guard", npc = true },
}
function UnitExists(unit) return units[unit] ~= nil end
function UnitIsPlayer(unit) return units[unit] and not units[unit].npc or false end
function UnitIsUnit(a, b) return units[a] and units[b] and units[a].guid == units[b].guid end
function UnitName(unit) local u = units[unit] return u and u.name, u and u.surname end
function UnitGUID(unit) return units[unit] and units[unit].guid end
function UnitClass() return "Mage", "MAGE" end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 42 end
function GetRealmName() return "Forever" end
function GetGuildInfo(unit) local u = units[unit] return u and u.guild, nil, nil, u and u.realm end

local validPoints = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
local methods = {}
function methods:SetPoint(point, relative, relativePoint)
    assert(validPoints[point], "invalid anchor " .. tostring(point))
    if type(relative) == "table" and relativePoint then assert(validPoints[relativePoint], "invalid relative anchor") end
end
function methods:SetSize(w, h) assert(w > 0 and h > 0) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 100 end
function methods:GetHeight() return self.height or 100 end
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:GetScript(event) return self.scripts[event] end
function methods:SetText(text)
    self.text = tostring(text or "")
    if self.fontString then self.fontString:SetText(self.text) end
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function methods:GetText() return self.text or "" end
function methods:GetStringHeight() local _, lines = self:GetText():gsub("\n", "") return (lines + 1) * 14 end
function methods:GetNumLines() local _, lines = self:GetText():gsub("\n", "") return lines + 1 end
function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 13, "" end
function methods:GetSpacing() return 0 end
function methods:Show()
    local changed = not self.shown
    self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide() self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
function methods:IsShown() return self.shown end
function methods:SetEnabled(v)
    local changed = self.enabled ~= v
    self.enabled = v
    local callback = self.scripts[v and "OnEnable" or "OnDisable"]
    if changed and callback then callback(self) end
end
function methods:IsEnabled() return self.enabled end
function methods:SetToplevel(v) self.topLevel = v end
function methods:Raise() self.raised = (self.raised or 0) + 1 end
function methods:SetChecked(v) self.checked = v end
function methods:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
function methods:SetValueStep(step) self.step = step end
function methods:SetValue(value)
    value = math.max(self.minValue, math.min(self.maxValue, value))
    if self.value ~= value then
        self.value = value
        if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
    end
end
function methods:GetValue() return self.value end
function methods:GetChecked() return self.checked end
function methods:SetFocus() self.focus = true end
function methods:ClearFocus() self.focus = false end
function methods:SetVerticalScroll(v) self.vertical = v end
function methods:GetVerticalScroll() return self.vertical or 0 end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:SetScale(scale) assert(scale > 0 and scale <= 1) self.scale = scale end
function methods:GetCenter() return 100, 100 end
function methods:GetEffectiveScale() return 1 end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
function methods:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function methods:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
function methods:SetNormalFontObject(value) self.normalFont = value end
function methods:SetHighlightFontObject(value) self.highlightFont = value end
function methods:SetDisabledFontObject(value) self.disabledFont = value end
function methods:SetFont(path, size, flags) self.font = { path, size, flags } return true end
function methods:SetBlendMode(value) self.blendMode = value end
function methods:SetTexCoord(...) self.texCoord = { ... } end
function methods:AddMaskTexture(value) self.mask = value end
function methods:SetHitRectInsets(...) self.hitRectInsets = { ... } end
function methods:SetNormalTexture(value) self.normalTexture = value end
function methods:GetNormalTexture() return type(self.normalTexture) == "table" and self.normalTexture or nil end
function methods:SetHighlightTexture(value) self.highlightTexture = value end
function methods:LockHighlight() self.highlightLocked = true end
function methods:SetPushedTexture(value) self.pushedTexture = value end
function methods:SetDisabledTexture(value) self.disabledTexture = value end
function methods:SetFontString(value) self.fontString = value end
function methods:GetScale() return self.scale or 1 end
function methods:GetPoint() return "CENTER", self.parent, "CENTER", 0, 0 end
function methods:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end fn(...) end
end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:UnregisterEvent(event) self.events[event] = nil end
for _, name in ipairs({ "SetFrameStrata", "SetClampedToScreen", "EnableMouse", "SetMovable", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetAllPoints", "SetJustifyH", "SetSpacing", "SetAutoFocus", "SetMaxLetters", "SetMultiLine", "SetFontObject", "SetTextInsets", "ClearAllPoints", "RegisterForClicks", "SetTexture", "SetAlpha", "SetDrawLayer" }) do
    methods[name] = function() end
end
local function newRegion(parent, name)
    local f = setmetatable({ parent = parent, name = name, children = {}, scripts = {}, events = {}, shown = true, enabled = true }, { __index = methods })
    if parent then parent.children[#parent.children + 1] = f end
    if name then assert(not _G[name], "duplicate frame name " .. name) _G[name] = f end
    frames[#frames + 1] = f
    return f
end
function methods:CreateTexture() return newRegion(self) end
function methods:CreateMaskTexture() return newRegion(self) end
function methods:CreateFontString() return newRegion(self) end
function CreateFrame(_, name, parent) return newRegion(parent, name) end
UIParent = newRegion(nil)
UIParent:SetSize(1920, 1080)
Minimap = newRegion(UIParent)
Menu = { ModifyMenu = function(tag, fn) menuHooks[tag] = fn end }
C_ChatInfo = {
    GetChatLineSenderName = function(id) return id == 10 and "Darkness FordDustiness" or nil end,
    GetChatLineSenderGUID = function(id) return id == 10 and "Player-1-darkness" or nil end,
}


GL_TEST_MOCK = {
    frames = frames, messages = messages, cvars = cvars, menuHooks = menuHooks,
    units = units, secret = secret,
    SetCombat = function(value) inCombat = value end,
    Fire = function(event, ...)
        local count = #frames
        for i = 1, count do
            local f = frames[i]
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end,
}
-- Native Menu descriptions become hover submenus when children are added.
function GL_TEST_MOCK.NewMenu()
    local menu = { buttons = {}, children = {}, entries = {} }
    function menu:AddInitializer(callback) self.initializer = callback end
    function menu:CreateDivider() self.entries[#self.entries + 1] = { kind = "divider" } end
    function menu:CreateTitle(text) self.entries[#self.entries + 1] = { kind = "title", text = text } end
    function menu:CreateButton(text, callback)
        local child = GL_TEST_MOCK.NewMenu()
        self.buttons[text], self.children[text] = callback, child
        self.entries[#self.entries + 1] = { kind = "button", text = text, callback = callback, child = child }
        return child
    end
    return menu
end
return GL_TEST_MOCK
