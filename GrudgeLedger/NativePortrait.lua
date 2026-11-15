-- The Windows companion reads only this 64-pixel portrait and its identity strip.
local GL = GrudgeLedger
local pending, offered = {}, {}
local frame, pixels, active
local function showNext()
    active = table.remove(pending, 1)
    if not active then frame:Hide(); return end
    local guid = active.guid
    local payload = ("GLP1" .. guid:sub(8)) .. string.rep("\0", 27 - #guid:sub(8))
    local checksum = 0
    for i = 1, #payload do checksum = (checksum + i * payload:byte(i)) % 251 end
    payload = payload .. string.char(checksum)
    for i = 1, #payload do
        local value = payload:byte(i)
        for bit = 0, 7 do
            local white = math.floor(value / 2^(7-bit)) % 2
            pixels[(i-1)*8+bit+1]:SetColorTexture(white,white,white,1)
        end
    end
    local _, height = GetPhysicalScreenSize()
    frame:SetScale(UIParent:GetHeight() / height)
    active.face:Show()
    frame:Show()
    C_Timer.After(2, function()
        active.face:Hide()
        active.face:SetTexture(nil)
        frame.free[#frame.free+1] = active.face
        showNext()
    end)
end

function GL.QueueNativePortrait(unit, guid)
    if type(GrudgeLedgerNativePortraits) ~= "table" or GrudgeLedgerNativePortraits[guid]
        or not guid:match("^Player%-%d+%-%x+$") or #guid:sub(8)>27 or #pending>=12
        or (offered[guid] and GetTime()-offered[guid]<300) then return end
    if not frame then
        frame = CreateFrame("Frame",nil,UIParent)
        frame:SetFrameStrata("TOOLTIP")
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
        frame:SetSize(64,80)
        frame:Hide()
        frame.free, pixels = {}, {}
        local bg=frame:CreateTexture(nil,"BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0,0,0,1)
        for i=0,255 do
            local t=frame:CreateTexture(nil,"OVERLAY")
            t:SetPoint("TOPLEFT", frame, "TOPLEFT", 2*(i%32), -2*math.floor(i/32))
            t:SetSize(2,2)
            pixels[i+1]=t
        end
    end
    local face=table.remove(frame.free)
    if not face then
        face=frame:CreateTexture(nil,"ARTWORK")
        face:SetPoint("TOPLEFT",frame,"TOPLEFT",0,-16)
        face:SetSize(64,64)
    end
    face:Hide()
    if not pcall(SetPortraitTexture,face,unit,true) or UnitGUID(unit)~=guid then
        frame.free[#frame.free+1]=face
        return
    end
    offered[guid]=GetTime()
    pending[#pending+1]={guid=guid,face=face}
    if not active then showNext() end
end
