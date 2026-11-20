-- Building blocks of the player sheet: tiles, relation pills, fact cards, a win/loss bar,
-- a twelve-month strip and lists that turn their own pages. No scroll bar anywhere: a block
-- has a fixed size, and what does not fit goes on its next page.
local GL = GrudgeLedger
local L = GL.L
local UI = GL.UITheme
local P = {}
GL.DossierPanels = P

local colors = {
    tile = {0.91, 0.83, 0.65}, card = {0.96, 0.91, 0.78}, border = {0.79, 0.66, 0.42},
    empty = {0.85, 0.75, 0.55}, win = {0.25, 0.42, 0.23}, loss = {0.55, 0.12, 0.12},
}
-- Relation colours, told apart by lightness as well as hue.
local pills = {
    enemy = {{0.55, 0.12, 0.12}, {0.98, 0.90, 0.87}}, warning = {{0.54, 0.35, 0.07}, {1, 0.95, 0.84}},
    friend = {{0.18, 0.37, 0.20}, {0.90, 0.96, 0.89}}, neutral = {{0.36, 0.25, 0.16}, {0.94, 0.87, 0.72}},
    -- Author chips on parchment: you in dark red, a guild member in pale ink.
    mine = {{0.30, 0.075, 0.075}, {0.94, 0.87, 0.72}}, member = {{0.85, 0.75, 0.55}, {0.20, 0.13, 0.08}},
}
P.colors = colors

local function fill(parent, color, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end
-- A one-pixel frame around a block.
local function border(parent, color)
    local edges = {}
    for i, side in ipairs({{"TOPLEFT", "TOPRIGHT", nil, 1}, {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 1},
            {"TOPLEFT", "BOTTOMLEFT", 1, nil}, {"TOPRIGHT", "BOTTOMRIGHT", 1, nil}}) do
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
        t:SetColorTexture(color[1], color[2], color[3], 1)
        edges[i] = t
    end
    return edges
end
function P.Text(parent, x, y, w, size, bold, color)
    local label = UI.label(parent, "", nil, x, y, w)
    UI.journalFont(label, bold and "GameFontNormalLarge" or "GameFontHighlight", size)
    label:SetTextColor(unpack(color or UI.theme.ink))
    return label
end

-- A value that never leaves its box, whatever the language: the font shrinks from its size down
-- to the smallest, measured on one line; past that, the text wraps at the smallest size.
function P.Fit(label, text, width, biggest, smallest, bold)
    local face = bold and "GameFontNormalLarge" or "GameFontHighlight"
    GL.Safe(label.SetWordWrap, label, false)
    label:SetText(text or "")
    local size = biggest
    UI.journalFont(label, face, size)
    while size > smallest and (GL.Safe(label.GetStringWidth, label) or 0) > width do
        size = size - 1
        UI.journalFont(label, face, size)
    end
    GL.Safe(label.SetWordWrap, label, (GL.Safe(label.GetStringWidth, label) or 0) > width)
    return size
end

-- A tile: a small caption, then up to two lines.
function P.Tile(parent, w, h)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetSize(w, h)
    fill(tile, colors.tile)
    border(tile, colors.border)
    tile.caption = P.Text(tile, 10, -8, w - 20, 11, false, UI.theme.inkMuted)
    tile.value = P.Text(tile, 10, -24, w - 20, 17, true)
    tile.detail = P.Text(tile, 10, -46, w - 20, 11, false, UI.theme.inkMuted)
    -- The detail follows the value, which may take two lines.
    tile.detail:ClearAllPoints()
    tile.detail:SetPoint("TOPLEFT", tile.value, "BOTTOMLEFT", 0, -3)
    return tile
end
-- Wins against losses, in proportion.
function P.Bar(parent, w)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(w, 6)
    fill(bar, colors.empty)
    bar.win = bar:CreateTexture(nil, "ARTWORK")
    bar.win:SetPoint("TOPLEFT")
    bar.win:SetPoint("BOTTOMLEFT")
    bar.win:SetColorTexture(unpack(colors.win))
    bar.loss = bar:CreateTexture(nil, "ARTWORK")
    bar.loss:SetPoint("TOPRIGHT")
    bar.loss:SetPoint("BOTTOMRIGHT")
    bar.loss:SetColorTexture(unpack(colors.loss))
    function bar:Set(wins, losses)
        local total = wins + losses
        local width = self:GetWidth()
        self.win:SetWidth(math.max(0.01, total > 0 and width * wins / total or 0))
        self.loss:SetWidth(math.max(0.01, total > 0 and width * losses / total or 0))
        self.win:SetShown(wins > 0)
        self.loss:SetShown(losses > 0)
    end
    return bar
end

-- A relation pill: "Ennemi · −11". kind is a relation, or "outline" for a bounty or a tag.
function P.Pill(parent)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetSize(80, 20)
    pill.back = fill(pill, pills.neutral[1])
    pill.edges = border(pill, UI.theme.brass)
    pill.label = P.Text(pill, 8, -4, 200, 12, true)
    function pill:Set(value, kind)
        local style = pills[kind]
        self.label:SetText(value)
        -- The test client may not measure text; a width per character stands in.
        local measured = GL.Safe(self.label.GetStringWidth, self.label) or #tostring(value or "") * 7
        local width = math.min(240, measured + 18)
        self:SetWidth(width)
        self.label:SetWidth(width - 12)
        self.back:SetShown(style ~= nil)
        for _, edge in ipairs(self.edges) do edge:SetShown(style == nil) end
        if style then
            self.back:SetColorTexture(unpack(style[1]))
            self.label:SetTextColor(unpack(style[2]))
        else
            self.label:SetTextColor(unpack(UI.theme.brass))
        end
        self:Show()
    end
    return pill
end

-- A fact card: the figure in large type, what it means beside it. A click opens the facts.
function P.FactCard(parent, w, h)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(w, h)
    fill(card, colors.card)
    border(card, colors.border)
    local hover = card:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(0.45, 0.28, 0.11, 0.10)
    card.value = P.Text(card, 10, -8, 96, 18, true, UI.theme.red)
    card.caption = P.Text(card, 110, -8, w - 120, 12)
    GL.Safe(card.caption.SetMaxLines, card.caption, 3)
    return card
end

-- A link-styled action: red text, no button frame.
function P.Link(parent, x, y, w, onClick)
    local link = CreateFrame("Button", nil, parent)
    link:SetPoint("TOPLEFT", x, y)
    link:SetSize(w, 18)
    link.label = P.Text(link, 0, -2, w, 12, false, UI.theme.red)
    link.label:SetJustifyH("RIGHT")
    link:SetScript("OnClick", onClick)
    function link:SetText(value) self.label:SetText(value) end
    function link:GetText() return self.label:GetText() end
    return link
end

-- A small "‹ 1 / 3 ›" page turner for a block.
local function turner(parent, x, y, onTurn)
    local t = CreateFrame("Frame", nil, parent)
    t:SetPoint("TOPLEFT", x, y)
    t:SetSize(86, 18)
    t.prev = UI.button(t, "‹", 0, 0, 22, function() onTurn(-1) end, nil, true)
    t.prev:SetHeight(18)
    t.label = P.Text(t, 24, -3, 38, 11, false, UI.theme.inkMuted)
    t.label:SetJustifyH("CENTER")
    t.next = UI.button(t, "›", 64, 0, 22, function() onTurn(1) end, nil, true)
    t.next:SetHeight(18)
    return t
end
-- A titled list of fixed height: rows of text, an optional proportion bar and a value.
-- items: {text=, value=, share= 0..1}. Long lists turn their own pages; the wheel turns them too.
function P.ListBlock(parent, w, rows)
    local block = CreateFrame("Frame", nil, parent)
    block.rows, block.page, block.items = {}, 1, {}
    block:SetSize(w, 24 + rows * 24)
    block.title = P.Text(block, 0, -2, w - 96, 15, true, UI.theme.red)
    local function turn(step)
        local pages = math.max(1, math.ceil(#block.items / rows))
        local target = block.page + step
        if target >= 1 and target <= pages then
            block.page = target
            block:Paint()
        end
    end
    block.turner = turner(block, w - 86, 0, turn)
    block.empty = P.Text(block, 2, -30, w - 4, 12, false, UI.theme.inkMuted)
    GL.Safe(block.EnableMouseWheel, block, true)
    block:SetScript("OnMouseWheel", function(_, delta) turn(delta > 0 and -1 or 1) end)
    for i = 1, rows do
        local row = CreateFrame("Frame", nil, block)
        row:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 24)
        row:SetSize(w, 24)
        row.rule = row:CreateTexture(nil, "BACKGROUND")
        row.rule:SetPoint("BOTTOMLEFT")
        row.rule:SetPoint("BOTTOMRIGHT")
        row.rule:SetHeight(1)
        row.rule:SetColorTexture(0.45, 0.28, 0.11, 0.21)
        row.label = P.Text(row, 2, -5, w - 120, 12)
        row.bar = P.Bar(row, 64)
        row.bar:SetPoint("TOPLEFT", w - 96, -9)
        row.bar.win:SetColorTexture(0.48, 0.12, 0.09)
        row.value = P.Text(row, w - 28, -5, 28, 12, true)
        row.value:SetJustifyH("RIGHT")
        block.rows[i] = row
    end
    function block:Set(title, items, emptyText)
        self.items = items or {}
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#self.items == 0)
        self.titleText = title
        local pages = math.max(1, math.ceil(#self.items / rows))
        self.page = math.min(self.page, pages)
        self:Paint()
    end
    function block:Paint()
        local pages = math.max(1, math.ceil(#self.items / rows))
        self.title:SetText(self.titleText)
        self.turner:SetShown(pages > 1)
        self.turner.label:SetText(("%d / %d"):format(self.page, pages))
        self.turner.prev:SetEnabled(self.page > 1)
        self.turner.next:SetEnabled(self.page < pages)
        for i, row in ipairs(self.rows) do
            local item = self.items[(self.page - 1) * rows + i]
            row:SetShown(item ~= nil)
            if item then
                row.label:SetText(item.text)
                row.label:SetWidth(item.share and w - 120 or w - 40)
                row.value:SetText(item.value or "")
                row.bar:SetShown(item.share ~= nil)
                if item.share then row.bar:Set(item.share, 0) end
            end
        end
    end
    return block
end

-- Twelve months as 52 weekly squares, the current week on the right, months above.
local WEEKS = 52
function P.YearStrip(parent, w)
    local strip = CreateFrame("Frame", nil, parent)
    local step = math.floor(w / WEEKS)
    strip:SetSize(w, 36)
    strip.cells, strip.months = {}, {}
    for week = 1, WEEKS do
        local cell = CreateFrame("Button", nil, strip)
        cell:SetPoint("TOPLEFT", (week - 1) * step, -14)
        cell:SetSize(step - 2, 18)
        cell.fill = cell:CreateTexture(nil, "ARTWORK")
        cell.fill:SetAllPoints()
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.title or "")
            GameTooltip:AddLine(self.detail or "", 1, 1, 1)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        strip.cells[week] = cell
    end
    for i = 1, 13 do
        strip.months[i] = P.Text(strip, 0, 0, 40, 10, false, UI.theme.inkMuted)
    end
    -- weeks: {count=, title=, detail=, month=} oldest first; paint(texture, count) colours a cell.
    function strip:Set(weeks, paint)
        local lastMonth, labels = nil, 0
        for _, label in ipairs(self.months) do label:Hide() end
        for i, cell in ipairs(self.cells) do
            local week = weeks[i] or {count = 0}
            cell.title, cell.detail = week.title, week.detail
            paint(cell.fill, week.count)
            if week.month and week.month ~= lastMonth then
                lastMonth = week.month
                labels = labels + 1
                local label = self.months[labels]
                if label and i <= WEEKS - 2 then
                    label:ClearAllPoints()
                    label:SetPoint("TOPLEFT", (i - 1) * step, 0)
                    label:SetText(week.monthName or "")
                    label:Show()
                end
            end
        end
    end
    return strip
end
