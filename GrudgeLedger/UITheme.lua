-- Shared native widgets and campaign journal skin.
local GL = GrudgeLedger
local media = "Interface\\AddOns\\GrudgeLedger\\Media\\"
local theme = { paper = { 0.94, 0.87, 0.72 }, muted = { 0.73, 0.64, 0.51 }, gold = { 0.52, 0.38, 0.20 }, brass = { 0.91, 0.77, 0.48 },
    background = { 0.075, 0.045, 0.035 }, panel = { 0.115, 0.075, 0.055 }, red = { 0.30, 0.075, 0.075 },
    ink = { 0.20, 0.13, 0.08 }, inkMuted = { 0.36, 0.25, 0.16 }, selection = { 0.91, 0.80, 0.62 },
    disabledInk = { 0.24, 0.19, 0.13 }, disabledGold = { 0.89, 0.80, 0.65 } }

local function surface(parent, color, inset, sublevel)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel or 0)
    texture:SetPoint("TOPLEFT", inset or 0, -(inset or 0))
    texture:SetPoint("BOTTOMRIGHT", -(inset or 0), inset or 0)
    texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return texture
end

local function plain(text) return tostring(text or ""):gsub("|", "||") end
local journalFonts = {}
local fontDir = media .. "Fonts\\PTSerif-"
local locale = GetLocale and GetLocale()
local nativeScript = locale == "koKR" or locale == "zhCN" or locale == "zhTW"
local function journalFont(region, decorative, size, italic)
    journalFonts[region] = { decorative, size, italic }
    local r, g, b, a = GL.Safe(region.GetTextColor, region)
    local spacing = GL.Safe(region.GetSpacing, region)
    local horizontal = GL.Safe(region.GetJustifyH, region)
    local vertical = GL.Safe(region.GetJustifyV, region)
    local settings = GL.Settings()
    local heading = decorative == "GameFontNormalLarge" or decorative:match("^Fancy%d+Font$")
    local classic = settings.readableFont
    region:SetFontObject(classic and "ChatFontNormal" or (heading and "GameFontNormalLarge" or decorative))
    local nativePath, _, flags = region:GetFont()
    local pixels = size * (settings.readingScale or 1)
    local face = italic and "Italic" or heading and "Bold" or "Regular"
    local loaded = false
    if not classic and not nativeScript then
        local path = fontDir .. face .. ".ttf"
        local ok, result = pcall(region.SetFont, region, path, pixels, "")
        -- On Forever a successful SetFont can have no return value. Check the applied face.
        if ok and result ~= false then
            local applied = result == nil and GL.Safe(region.GetFont, region)
            loaded = result ~= nil or (type(applied) == "string" and applied:gsub("/", "\\"):lower() == path:lower())
        end
    end
    if not loaded and nativePath then region:SetFont(nativePath, pixels, flags) end
    if region.SetShadowOffset then
        region:SetShadowOffset(0, 0)
    end
    if r then region:SetTextColor(r, g, b, a) end
    if spacing then region:SetSpacing(spacing) end
    if horizontal then region:SetJustifyH(horizontal) end
    if vertical then region:SetJustifyV(vertical) end
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

local function paintReferenceButton(b, textureName, tint, sliced)
    b.skin:ClearAllPoints()
    if sliced then
        -- ponytail: 12px caps suit the Journal's 26–34px controls; rescale the caps if their height range changes.
        local cap = math.min(12, (b:GetWidth() - 1) / 2)
        b.skin:SetPoint("TOPLEFT", cap, 0)
        b.skin:SetPoint("BOTTOMRIGHT", -cap, 0)
        b.skin:SetTexCoord(0.125, 0.875, 0, 1)
        if not b.skinCaps then
            b.skinCaps = { b:CreateTexture(nil, "ARTWORK"), b:CreateTexture(nil, "ARTWORK") }
            b.skinCaps[1]:SetPoint("TOPLEFT")
            b.skinCaps[1]:SetPoint("BOTTOMLEFT")
            b.skinCaps[1]:SetTexCoord(0, 0.125, 0, 1)
            b.skinCaps[2]:SetPoint("TOPRIGHT")
            b.skinCaps[2]:SetPoint("BOTTOMRIGHT")
            b.skinCaps[2]:SetTexCoord(0.875, 1, 0, 1)
        end
        for _, piece in ipairs(b.skinCaps) do
            piece:SetWidth(cap)
            piece:SetTexture(media .. textureName)
            piece:SetVertexColor(tint, tint, tint)
            piece:Show()
        end
    else
        b.skin:SetAllPoints()
        b.skin:SetTexCoord(0, 1, 0, 1)
        for _, piece in ipairs(b.skinCaps or {}) do piece:Hide() end
    end
    b.skin:SetTexture(media .. textureName)
    b.skin:SetVertexColor(tint, tint, tint)
end

local function updateButtonState(b)
    local enabled = b:IsEnabled()
    if b.referenceSkin then
        local navigation = b.selectionTexture == "JournalReferenceTabActive"
        local hot = enabled and b.hovered
        -- The chosen opinion and the primary action are filled red, like the selected tab.
        local red = hot or (b.active and enabled)
        local textureName = red and (navigation and "JournalReferenceTabActive" or "JournalReferenceButtonRed")
            or b.arrowTextureName or (navigation and "JournalReferenceTab" or b.paper and "JournalReferenceButton" or "JournalReferenceDarkButton")
        local tint = not enabled and not b.arrowTextureName and 0.82 or hot and b.pressed and 0.78 or 1
        paintReferenceButton(b, textureName, tint, not b.arrowTextureName or red)
        b.caption:SetTextColor(unpack(red and { 1, 1, 1 } or b.paper and (enabled and { 0, 0, 0 } or theme.disabledInk)
            or (enabled and theme.paper or theme.disabledGold)))
        b.caption:SetShown(not b.arrowTextureName or hot)
        -- A page arrow keeps its look when there is no page that way; it only fades.
        local fade = b.arrowTextureName and not enabled and 0.4 or 1
        b.skin:SetAlpha(fade)
        for _, piece in ipairs(b.skinCaps or {}) do piece:SetAlpha(fade) end
        b.normalSurface:SetColorTexture(unpack(red and theme.red or b.paper and theme.paper or theme.panel))
        b.normalSurface:SetAlpha(0.15)
        b.pressArtwork:SetAlpha(0)
        if b.selection then
            b.selection:SetAlpha(enabled and 1 or 0.6)
            if navigation then b.selection:SetVertexColor(tint, tint, tint)
            -- The red face already says "chosen": the old underline stays logical but transparent.
            else b.selection:SetColorTexture(0, 0, 0, 0) end
        end
        return
    end
    local tint = enabled and 1 or (b.paper and 0.88 or 0.76)
    b.skin:SetVertexColor(tint, tint, tint)
    if b.selection then b.selection:SetAlpha(enabled and 1 or 0.86) end
    local light = b.paper and not b.active
    b.caption:SetTextColor(unpack(enabled and (light and theme.ink or theme.brass)
        or (light and theme.disabledInk or theme.disabledGold)))
    b.edge:SetColorTexture(unpack(enabled and theme.gold or theme.disabledInk))
end

local function button(parent, text, x, y, width, callback, selectable, paper)
    local b = CreateFrame("Button", nil, parent)
    b.paper = paper
    b.referenceSkin = parent.referenceSkin
    if b.referenceSkin and width <= 40 and (text == "‹" or text == "›") then
        b.arrowTextureName = "JournalReference" .. (paper and "" or "Dark") .. (text == "‹" and "ArrowLeft" or "ArrowRight")
    end
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
    normal:SetDrawLayer("BACKGROUND", 0)
    local pushed = surface(b, paper and theme.selection or theme.brass, 1)
    b.pressArtwork = pushed
    pushed:SetAlpha(paper and 0.24 or 0.18)
    b:SetPushedTexture(pushed)
    pushed:SetDrawLayer("ARTWORK", 2)
    local disabled = surface(b, paper and theme.paper or theme.background, 1)
    disabled:SetAlpha(paper and 0.08 or 0)
    b:SetDisabledTexture(disabled)
    disabled:SetDrawLayer("BACKGROUND", 0)
    -- Native button setters may choose their own layer. The gold skin sits above
    -- normal/disabled fills; only the translucent press feedback goes over it.
    local skin = b:CreateTexture(nil, "ARTWORK")
    skin:SetAllPoints()
    if b.referenceSkin then
        edge:SetAlpha(0)
    else
        skin:SetTexture(media .. "JournalButtons")
        skin:SetTexCoord(36 / 1254, 1218 / 1254, (paper and 880 or 150) / 1254, (paper and 1130 or 402) / 1254)
    end
    b.skin = skin
    local highlight = b:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 1, -1)
    highlight:SetPoint("BOTTOMRIGHT", -1, 1)
    highlight:SetColorTexture(0.57, 0.39, 0.18, 0.22)
    if b.referenceSkin then highlight:SetAlpha(0) end
    b:SetHighlightTexture(highlight)
    local caption = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.caption = caption
    b:SetFontString(caption)
    b:SetText(text)
    journalFont(caption, "GameFontHighlightSmall", b.arrowTextureName and 18 or b.referenceSkin and 14 or 12)
    caption:ClearAllPoints()
    caption:SetPoint("CENTER")
    caption:SetSize(width - 14, 22)
    caption:SetJustifyH("CENTER")
    GL.Safe(caption.SetJustifyV, caption, "MIDDLE")
    GL.Safe(caption.SetWordWrap, caption, false)
    GL.Safe(caption.SetMaxLines, caption, 1)
    b:SetScript("OnEnable", updateButtonState)
    b:SetScript("OnDisable", updateButtonState)
    updateButtonState(b)
    b:SetScript("OnClick", callback)
    if b.referenceSkin then
        local function leave(self)
            self.hovered, self.pressed = nil, nil
            if self.tooltipActive and GameTooltip then GameTooltip:Hide() end
            self.tooltipActive = nil
            updateButtonState(self)
        end
        -- Large reading can ellipsize a fixed-width caption; its full translated label stays available.
        b:SetScript("OnEnter", function(self)
            self.hovered = self:IsEnabled()
            updateButtonState(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.arrowTextureName and GL.L(text == "‹" and "Précédent" or "Suivant") or self.caption:GetText())
                GameTooltip:Show()
                self.tooltipActive = true
            end
        end)
        b:SetScript("OnLeave", leave)
        b:SetScript("OnHide", leave)
        b:SetScript("OnDisable", leave)
        b:SetScript("OnMouseDown", function(self, mouseButton)
            self.pressed = mouseButton == "LeftButton" and self:IsEnabled() and self.hovered
            updateButtonState(self)
        end)
        b:SetScript("OnMouseUp", function(self)
            self.pressed = nil
            updateButtonState(self)
        end)
        b:HookScript("OnSizeChanged", updateButtonState)
    end
    return b
end

local function selectButton(control, active)
    if not control.selection then
        control.selection = control:CreateTexture(nil, "ARTWORK", nil, 1)
        if control.referenceSkin then
            if control.selectionTexture == "JournalReferenceTabActive" then
                control.selection:SetAllPoints()
                control.selection:SetTexture(media .. control.selectionTexture)
            else
                control.selection:SetPoint("BOTTOMLEFT", 6, 3)
                control.selection:SetPoint("BOTTOMRIGHT", -6, 3)
                control.selection:SetHeight(2)
            end
        else
            control.selection:SetAllPoints()
            control.selection:SetTexture(media .. "JournalButtons")
            control.selection:SetTexCoord(36 / 1254, 1218 / 1254, 514 / 1254, 768 / 1254)
        end
    end
    control.active = active
    control.normalSurface:SetColorTexture(unpack(active and theme.red or (control.paper and theme.paper or theme.panel)))
    control.normalSurface:SetAlpha(active and 1 or 0.15)
    updateButtonState(control)
    if active then control.selection:Show() else control.selection:Hide() end
end

local function styleInput(edit, multiline, paper)
    local edge = surface(edit, theme.gold, 0, -1)
    local fill = surface(edit, paper and theme.paper or theme.background, 1)
    if edit.referenceSkin and not paper then
        local skin = edit:CreateTexture(nil, "BACKGROUND", nil, 1)
        skin:SetAllPoints()
        skin:SetTexture(media .. "JournalReferenceField")
    end
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

local function fitToScreen(frame)
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if w > 24 and h > 24 then
        frame:SetScale(math.min(1, (w - 24) / frame:GetWidth(), (h - 24) / frame:GetHeight()))
    end
end

-- WoW stores placement by frame name. All pages inherit this frame's position and scale.
local bookAnchor = _G.GrudgeLedgerBookAnchor
if not bookAnchor then
    bookAnchor = CreateFrame("Frame", "GrudgeLedgerBookAnchor", UIParent)
    bookAnchor:SetSize(960, 720)
    bookAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    bookAnchor:SetMovable(true)
    bookAnchor:SetClampedToScreen(true)
    bookAnchor:EnableMouse(false)
    UIParent:HookScript("OnSizeChanged", function() fitToScreen(bookAnchor) end)
end

local function window(name, title, width, height, isBook)
    local f = CreateFrame("Frame", name, isBook and bookAnchor or UIParent)
    f.referenceSkin = isBook and name == "GrudgeLedgerWindow"
    f:SetSize(width, height)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    if isBook then
        if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    else
        f:SetMovable(true)
        f:SetClampedToScreen(true)
    end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnMouseDown", function(self) self:Raise() end)
    local mover = isBook and bookAnchor or f
    local dragging = false
    f:SetScript("OnDragStart", function()
        mover:StartMoving()
        dragging = true
    end)
    local function stopMoving()
        if dragging then
            mover:StopMovingOrSizing()
            dragging = false
        end
    end
    f:SetScript("OnDragStop", stopMoving)
    f:SetScript("OnHide", stopMoving)
    f.lining = surface(f, theme.background, isBook and 20 or 14, -4)
    if not isBook then
        local cover = f:CreateTexture(nil, "BACKGROUND", nil, -2)
        cover:SetAllPoints()
        cover:SetTexture(media .. "JournalDialog")
    end
    local seal = f:CreateTexture(nil, "ARTWORK")
    f.seal = seal
    seal:SetSize(34, 34)
    seal:SetPoint("TOPLEFT", 9, -5)
    seal:SetTexture(GL.icon or "Interface\\Icons\\INV_Misc_Book_09")
    f.title = label(f, title, "large", 53, -13, width - 107)
    f.title:SetTextColor(0.91, 0.77, 0.48)
    f.title:SetHeight(24)
    GL.Safe(f.title.SetWordWrap, f.title, false)
    f.closeButton = iconButton(f, "JournalClose", GL.L("Fermer"), width - 37, -9, 26, function() f:Hide() end)
    f:SetScript("OnShow", function(self)
        self:Raise()
        fitToScreen(mover)
        if isBook then
            self:ClearAllPoints()
            self:SetPoint("CENTER", bookAnchor, "CENTER", 0, 0)
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    f:Hide()
    return f
end

-- narrow: the player sheet's variant, its left column about 20 % of the window.
local function bookWindow(name, title, narrow)
    local reference = name == "GrudgeLedgerWindow"
    local f = window(name, title, 960, 700, true)
    f.referenceSkin = reference
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
    journalFont(f.title, "GameFontNormalLarge", 31)
    f.title:SetTextColor(1, 0.83, 0.49)
    f.wordmark = f:CreateTexture(nil, "ARTWORK")
    f.wordmark:SetPoint("CENTER", f.title, "CENTER", 0, 0)
    f.wordmark:SetSize(248, 62)
    if f.wordmark:SetTexture(media .. "JournalWordmark") ~= false then f.title:Hide() end
    f.indexPaper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.indexPaper:SetPoint("TOPLEFT", 25, -145)
    f.indexPaper:SetSize(narrow and 189 or 295, 520)
    f.indexPaper:SetColorTexture(unpack(theme.panel))
    f.paper = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.paper:SetPoint("TOPLEFT", narrow and 226 or 340, -145)
    f.paper:SetSize(narrow and 704 or 590, 520)
    f.paper:SetColorTexture(unpack(theme.paper))
    f.bookSurface = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    f.bookSurface:SetAllPoints()
    f.bookSurface:SetTexture(media .. (narrow and "JournalBookSurfaceSheet" or "JournalBookSurface"))
    if reference then
        -- The same window, title and buttons as the other pages: the book must not jump between tabs
        -- (owner, 23/11). The painting keeps its 960 x 720 canvas, 10 units above and below the window,
        -- and its frame is painted on the frame of the other pages.
        f.bookSurface:ClearAllPoints()
        f.bookSurface:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 10)
        f.bookSurface:SetSize(960, 720)
        f.bookSurface:SetTexture(media .. "JournalReferenceBook")
        f.lining:Hide()
        f.indexPaper:ClearAllPoints()
        f.indexPaper:SetPoint("TOPLEFT", 74, -149)
        f.indexPaper:SetSize(272, 476)
        f.paper:ClearAllPoints()
        f.paper:SetPoint("TOPLEFT", 356, -153)
        f.paper:SetSize(541, 473)
    end
    return f
end

-- Read-only text in pages, like a book: never a scroll bar. Whole lines only: a page ends before
-- the line that would overflow it. The arrows at the bottom right and the wheel turn the pages.
local function textPages(parent, width, height)
    local view = CreateFrame("Frame", nil, parent)
    view.referenceSkin = parent.referenceSkin
    view:SetSize(width, height)
    view.body = label(view, "", nil, 0, 0, width - 4)
    view.body:SetTextColor(unpack(theme.ink))
    view.pages, view.page = { "" }, 1
    local function turn(step)
        view.page = math.max(1, math.min(#view.pages, view.page + step))
        view:Paint()
    end
    view.next = button(view, "›", 0, 0, 34, function() turn(1) end, nil, true)
    view.next:ClearAllPoints()
    view.next:SetPoint("BOTTOMRIGHT", 0, 0)
    view.pageLabel = label(view, "", nil, 0, 0, 56)
    view.pageLabel:ClearAllPoints()
    view.pageLabel:SetPoint("BOTTOMRIGHT", -36, 6)
    view.pageLabel:SetJustifyH("CENTER")
    view.pageLabel:SetTextColor(unpack(theme.inkMuted))
    view.prev = button(view, "‹", 0, 0, 34, function() turn(-1) end, nil, true)
    view.prev:ClearAllPoints()
    view.prev:SetPoint("BOTTOMRIGHT", -94, 0)
    GL.Safe(view.EnableMouseWheel, view, true)
    view:SetScript("OnMouseWheel", function(_, delta) turn(delta > 0 and -1 or 1) end)
    function view:Paint()
        local many = #self.pages > 1
        self.body:SetText(self.pages[self.page] or "")
        self.pageLabel:SetText(many and (self.page .. " / " .. #self.pages) or "")
        self.prev:SetShown(many)
        self.next:SetShown(many)
        self.prev:SetEnabled(self.page > 1)
        self.next:SetEnabled(self.page < #self.pages)
    end
    function view:SetText(text, keepPage)
        self.fullText = text or ""
        local room = math.max(20, (self:GetHeight() or height) - 30)
        local pages, current = {}, {}
        for line in ((text or "") .. "\n"):gmatch("(.-)\n") do
            if line ~= "" or #current > 0 then
                current[#current + 1] = line
                self.body:SetText(table.concat(current, "\n"))
                if #current > 1 and (self.body:GetStringHeight() or 0) > room then
                    current[#current] = nil
                    pages[#pages + 1] = table.concat(current, "\n")
                    current = line ~= "" and { line } or {}
                end
            end
        end
        if #current > 0 or #pages == 0 then pages[#pages + 1] = table.concat(current, "\n") end
        self.pages = pages
        self.page = keepPage and math.min(self.page, #pages) or 1
        self:Paint()
    end
    return view
end

-- A text box (notes, diagnostic) shows no bar: the wheel moves its text by three lines.
local function wheelScroll(scroll)
    GL.Safe(scroll.EnableMouseWheel, scroll, true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        local most = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * 42)))
    end)
end

GL.UITheme = {
    textPages = textPages, wheelScroll = wheelScroll,
    theme = theme, journalFonts = journalFonts,
    surface = surface, plain = plain, label = label, button = button,
    selectButton = selectButton,
    styleInput = styleInput, window = window, bookWindow = bookWindow, iconButton = iconButton,
    journalFont = journalFont,
}
