-- Two native WoW icons; clicks use the same outgoing gesture path as /kiss and /spit.
local GL = GrudgeLedger
local bar
local function position()
    bar:ClearAllPoints()
    local saved = GL.db.gesturePosition
    if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number"
        and saved.x >= 0 and saved.x <= 1 and saved.y >= 0 and saved.y <= 1 then
        bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", saved.x * UIParent:GetWidth(), saved.y * UIParent:GetHeight())
    elseif ChatFrame1 then bar:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 40)
    else bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 24, 264) end
end
local function update()
    if not bar then return end
    if GL.Settings().quickGestures then bar:Show() else bar:Hide() end
end
GL.On("READY", function()
    if bar then position() update() return end
    bar = CreateFrame("Frame", "GrudgeLedgerGestures", UIParent)
    bar:SetSize(88, 40)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar.buttons = {}
    for i, action in ipairs({
        { "KISS", "Bisou", "INV_ValentinesCandy", "Geste amical : +1" },
        { "SPIT", "Crachat", "Spell_Nature_CorrosiveBreath", "Geste négatif : −1" },
    }) do
        local token = action[1]
        local b = CreateFrame("Button", nil, bar)
        bar.buttons[token] = b
        b:SetSize(40, 40)
        b:SetPoint("TOPLEFT", (i - 1) * 48, 0)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 4, -4) icon:SetPoint("BOTTOMRIGHT", -4, 4)
        icon:SetTexture("Interface\\Icons\\" .. action[3])
        b:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
        b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:RegisterForClicks("LeftButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnClick", function(self)
            if self.dragged then self.dragged = nil return end
            if GL.Safe(IsControlKeyDown) then return end
            GL.SendGesture(token)
        end)
        b:SetScript("OnDragStart", function(self)
            if GL.Safe(IsControlKeyDown) ~= true then return end
            self.dragged = true
            bar:StartMoving()
        end)
        b:SetScript("OnDragStop", function(self)
            if not self.dragged then return end
            bar:StopMovingOrSizing()
            local x, y = bar:GetLeft(), bar:GetBottom()
            if type(x) == "number" and type(y) == "number" then
                GL.db.gesturePosition = { x = math.max(0, math.min(1, x / UIParent:GetWidth())),
                    y = math.max(0, math.min(1, y / UIParent:GetHeight())) }
            end
            if C_Timer and C_Timer.After then C_Timer.After(0, function() self.dragged = nil end) end
        end)
        local title, help = action[2], action[4]
        b:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(title)
            GameTooltip:AddLine(help .. " sur le joueur ciblé.", 1, 0.85, 0.6)
            GameTooltip:AddLine("Même avis au plus une fois par 30 s.\nCtrl + glisser : déplacer les deux boutons.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    position() update()
end)
GL.On("SETTINGS", update)
function GL.ResetGesturePosition() GL.db.gesturePosition = nil if bar then position() end end
