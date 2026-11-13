-- Shared native widgets and campaign journal skin.
local GL = GrudgeLedger
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"
local theme = { paper = { 0.94, 0.87, 0.72 }, muted = { 0.73, 0.64, 0.51 }, gold = { 0.52, 0.38, 0.20 }, brass = { 0.91, 0.77, 0.48 },
    background = { 0.075, 0.045, 0.035 }, panel = { 0.115, 0.075, 0.055 }, red = { 0.30, 0.075, 0.075 },
    ink = { 0.20, 0.13, 0.08 }, inkMuted = { 0.36, 0.25, 0.16 }, selection = { 0.91, 0.80, 0.62 }, disabledInk = { 0.50, 0.44, 0.36 } }

local function surface(parent, color, inset, sublevel)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 0)
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return texture
end

local function plain(text) return tostring(text or ""):gsub("|", "||") end
local journalFonts = {}
local function journalFont(region, decorative, size)
    journalFonts[region] = { decorative, size }
    local r, g, b, a = GL.Safe(region.GetTextColor, region)
    local spacing = GL.Safe(region.GetSpacing, region)
    local settings = GL.Settings()
    local font = decorative:match("^Fancy%d+Font$") and "GameFontNormalLarge" or decorative
    region:SetFontObject(settings.readableFont and "ChatFontNormal" or font)
    local path, _, flags = region:GetFont()
    if path then region:SetFont(path, size * (settings.readingScale or 1), flags) end
    if r then region:SetTextColor(r, g, b, a) end
    if spacing then region:SetSpacing(spacing) end
end
local function label(parent, text, size, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", size == "large" and "GameFontNormalLarge" or "GameFontHighlight")
    journalFont(f, size == "large" and "GameFontNormalLarge" or "GameFontHighlight", size == "large" and 18 or 13)
    f:SetPoint("TOPLEFT", x, y)
    f:SetJustifyH("LEFT")
    GL.Safe(f.SetJustifyV, f, "TOP")
    f:SetTextColor(unpack(theme.paper))
    if width then f:SetWidth(width) end
    f:SetText(text or "")
    return f
end

local function button(parent, text, x, y, width, callback, selectable, paper)
    local b = CreateFrame("Button", nil, parent)
    b.paper = paper
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(width, 26)
    local edge = surface(b, theme.gold, 0, -1)
    b.edge = edge
    edge:ClearAllPoints()
    edge:SetPoint("BOTTOMLEFT")
    edge:SetPoint("BOTTOMRIGHT")
    edge:SetHeight(1)
    edge:SetAlpha(0.65)
    local normal = surface(b, paper and theme.paper or theme.panel, 1)
    normal:SetAlpha(paper and 0.15 or 0)
    b.normalSurface = normal
    b:SetNormalTexture(normal)
    local pushed = surface(b, paper and theme.selection or theme.brass, 1)
    pushed:SetAlpha(paper and 0.65 or 0.18)
    b:SetPushedTexture(pushed)
    local disabled = surface(b, paper and theme.paper or theme.background, 1)
    disabled:SetAlpha(paper and 0.08 or 0)
    b:SetDisabledTexture(disabled)
    -- Keep native state fills underneath the illustrated skin, including when
    -- the client cannot load the texture. No extra frame or update handler.
    local skin = b:CreateTexture(nil, "BORDER")
    skin:SetAllPoints()
    skin:SetTexture(media .. "JournalButtons")
    skin:SetTexCoord(36 / 1254, 1218 / 1254, (paper and 880 or 150) / 1254, (paper and 1130 or 402) / 1254)
    b.skin = skin
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(0.57, 0.39, 0.18, 0.22)
    b:SetHighlightTexture(highlight)
    local caption = label(b, text, nil, 7, -6, width - 14)
    b.caption = caption
    caption:SetJustifyH("CENTER")
    caption:SetHeight(16)
    GL.Safe(caption.SetWordWrap, caption, false)
    GL.Safe(caption.SetMaxLines, caption, 1)
    b:SetFontString(caption)
    b:SetNormalFontObject("GameFontHighlightSmall")
    b:SetHighlightFontObject("GameFontHighlightSmall")
    b:SetDisabledFontObject("GameFontDisableSmall")
    b:SetText(text)
    journalFont(caption, "GameFontHighlightSmall", 12)
    caption:SetTextColor(unpack(paper and theme.ink or theme.brass))
    b:SetScript("OnEnable", function()
        skin:SetVertexColor(1, 1, 1)
        caption:SetTextColor(unpack(b.active and theme.brass or (paper and theme.ink or theme.brass)))
        if b.selection then b.selection:SetAlpha(1) end
        edge:SetColorTexture(unpack(theme.gold))
    end)
    b:SetScript("OnDisable", function()
        skin:SetVertexColor(0.55, 0.55, 0.55)
        if b.selection then b.selection:SetAlpha(0.45) end
        if paper then caption:SetTextColor(unpack(theme.disabledInk)) else caption:SetTextColor(0.52, 0.50, 0.46) end
        edge:SetColorTexture(0.28, 0.24, 0.19, 1)
    end)
    b:SetScript("OnClick", callback)
    return b
end

local function selectButton(control, active)
    if not control.selection then
        control.selection = control:CreateTexture(nil, "BORDER", nil, 1)
        control.selection:SetAllPoints()
        control.selection:SetTexture(media .. "JournalButtons")
        control.selection:SetTexCoord(36 / 1254, 1218 / 1254, 514 / 1254, 768 / 1254)
    end
    control.active = active
    control.normalSurface:SetColorTexture(unpack(active and theme.red or (control.paper and theme.paper or theme.panel)))
    control.normalSurface:SetAlpha(active and 1 or 0.15)
    local enabled = control:IsEnabled()
    control.selection:SetAlpha(enabled and 1 or 0.45)
    control.caption:SetTextColor(unpack(not enabled and theme.disabledInk or (active and theme.brass or (control.paper and theme.ink or theme.brass))))
    if active then control.selection:Show() else control.selection:Hide() end
end

local function styleInput(edit, multiline, paper)
    local edge = surface(edit, theme.gold, 0, -1)
    local fill = surface(edit, paper and theme.paper or theme.background, 1)
    if paper then
        local texture = edit:CreateTexture(nil, "BACKGROUND", nil, 1)
        texture:SetAllPoints(fill)
        texture:SetTexture(media .. "JournalPaper")
    end
    if paper and multiline then journalFont(edit, "QuestFont_Large", 15)
    else journalFont(edit, "ChatFontNormal", 13) end
    edit:SetTextColor(unpack(paper and theme.ink or theme.paper))
    GL.Safe(edit.SetJustifyV, edit, multiline and "TOP" or "MIDDLE")
    edit:SetTextInsets(8, 8, 5, 5)
    edit:SetScript("OnEditFocusGained", function() edge:SetColorTexture(0.75, 0.57, 0.29, 1) end)
    edit:SetScript("OnEditFocusLost", function() edge:SetColorTexture(unpack(theme.gold)) end)
end

local function iconButton(parent, textureName, title, x, y, size, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(size, size)
    local normal = b:CreateTexture(nil, "ARTWORK")
    normal:SetAllPoints()
    normal:SetTexture(media .. textureName)
    b:SetNormalTexture(normal)
    local pressed = b:CreateTexture(nil, "ARTWORK")
    pressed:SetPoint("TOPLEFT", 1, -2)
    pressed:SetPoint("BOTTOMRIGHT", -1, 0)
    pressed:SetTexture(media .. textureName)
    pressed:SetVertexColor(0.8, 0.74, 0.67)
    b:SetPushedTexture(pressed)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_LEFT") GameTooltip:AddLine(title) GameTooltip:Show() end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", onClick)
    return b
end

local function window(name, title, width, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function(self) self:Raise() end)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    local shadow = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.shadow = shadow
    shadow:SetPoint("TOPLEFT", -4, 4)
    shadow:SetPoint("BOTTOMRIGHT", 4, -4)
    shadow:SetColorTexture(0, 0, 0, 0.65)
    -- ponytail: explicit native sublevels, never creation order; keep solid fills
    -- below decorative images so a missing texture cannot erase readable backing.
    f.outerBorder = surface(f, theme.gold, 0, -7)
    f.cover = surface(f, theme.red, 1, -6)
    f.innerBorder = surface(f, theme.gold, 6, -5)
    local lining = surface(f, theme.background, 7, -4)
    f.lining = lining
    local grain = f:CreateTexture(nil, "BACKGROUND", nil, -3)
    f.grain = grain
    grain:SetAllPoints(lining)
    grain:SetTexture(media .. "JournalPaper")
    GL.Safe(grain.SetVertexColor, grain, 0.13, 0.085, 0.065)
    local header = f:CreateTexture(nil, "BORDER", nil, 0)
    f.header = header
    header:SetPoint("TOPLEFT", 7, -7)
    header:SetPoint("TOPRIGHT", -7, -7)
    header:SetHeight(35)
    header:SetTexture(media .. "JournalPaper")
    GL.Safe(header.SetVertexColor, header, 0.32, 0.075, 0.065)
    local headerFill = f:CreateTexture(nil, "BORDER", nil, -1)
    f.headerFill = headerFill
    headerFill:SetAllPoints(header)
    headerFill:SetColorTexture(unpack(theme.red))
    f.headerLine = f:CreateTexture(nil, "BORDER", nil, 1)
    f.headerLine:SetPoint("TOPLEFT", 8, -42)
    f.headerLine:SetPoint("TOPRIGHT", -8, -42)
    f.headerLine:SetHeight(1)
    f.headerLine:SetColorTexture(theme.gold[1], theme.gold[2], theme.gold[3], 0.7)
    local seal = f:CreateTexture(nil, "ARTWORK")
    f.seal = seal
    seal:SetSize(34, 34)
    seal:SetPoint("TOPLEFT", 9, -5)
    seal:SetTexture(GL.icon or "Interface\\Icons\\INV_Misc_Book_09")
    f.title = label(f, title, "large", 53, -13, width - 107)
    f.title:SetTextColor(0.91, 0.77, 0.48)
    f.title:SetHeight(24)
    GL.Safe(f.title.SetWordWrap, f.title, false)
    f.closeButton = iconButton(f, "JournalClose", "Fermer", width - 37, -9, 26, function() f:Hide() end)
    f:SetScript("OnShow", function(self)
        self:Raise()
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        self:SetScale(math.min(1, (w - 24) / width, (h - 24) / height))
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

local function bookWindow(name, title)
    local f = window(name, title, 960, 700)
    for _, region in ipairs({ f.shadow, f.outerBorder, f.cover, f.innerBorder, f.grain, f.header, f.headerFill, f.headerLine }) do region:Hide() end
    f.lining:ClearAllPoints()
    f.lining:SetPoint("TOPLEFT", 20, -20)
    f.lining:SetPoint("BOTTOMRIGHT", -20, 20)
    f.closeButton:ClearAllPoints()
    f.closeButton:SetPoint("TOPLEFT", 912, -19)
    f.closeButton:SetSize(32, 32)
    f.seal:ClearAllPoints()
    f.seal:SetPoint("TOPLEFT", 289, -8)
    f.seal:SetSize(76, 76)
    local titlePlate = f:CreateTexture(nil, "BORDER")
    titlePlate:SetPoint("TOPLEFT", 323, -19)
    titlePlate:SetSize(351, 53)
    titlePlate:SetTexture(media .. "JournalTitlePlate")
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", 362, -20)
    f.title:SetSize(289, 51)
    f.title:SetJustifyH("CENTER")
    GL.Safe(f.title.SetJustifyV, f.title, "MIDDLE")
    journalFont(f.title, "GameFontNormalLarge", 30)
    f.indexPaper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.indexPaper:SetPoint("TOPLEFT", 25, -145)
    f.indexPaper:SetSize(295, 520)
    f.indexPaper:SetColorTexture(unpack(theme.panel))
    f.paper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.paper:SetPoint("TOPLEFT", 340, -145)
    f.paper:SetSize(590, 520)
    f.paper:SetColorTexture(unpack(theme.paper))
    f.bookSurface = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bookSurface:SetAllPoints()
    f.bookSurface:SetTexture(media .. "JournalBookSurface")
    return f
end

GL.UITheme = {
    theme = theme, journalFonts = journalFonts,
    surface = surface, plain = plain, label = label, button = button,
    selectButton = selectButton,
    styleInput = styleInput, window = window, bookWindow = bookWindow, iconButton = iconButton,
    journalFont = journalFont,
}
