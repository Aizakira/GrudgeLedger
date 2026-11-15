-- The Armory slot order mirrors the character sheet: two rails and three weapon slots.
local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local L = GL.L
local qualityID = {POOR=0, COMMON=1, UNCOMMON=2, RARE=3, EPIC=4, LEGENDARY=5, ARTIFACT=6, HEIRLOOM=7}
local inventorySlots = {"HeadSlot","NeckSlot","ShoulderSlot","BackSlot","ChestSlot","ShirtSlot","TabardSlot","WristSlot",
    "HandsSlot","WaistSlot","LegsSlot","FeetSlot","Finger0Slot","Finger1Slot","Trinket0Slot","Trinket1Slot",
    "MainHandSlot","SecondaryHandSlot","RangedSlot"}

local function closeTip(button)
    button.waitingForItem=nil
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end
local function openTip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    local link=button.inspectedLink or GL.ArmoryItemLink(button.item)
    button.waitingForItem=not link and button.item and button.item.ref
    if link and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(L("Maj + clic pour insérer dans la discussion."),.75,.75,.75)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText(button.itemName or button.slotName, unpack(button.color))
    if button.itemName then GameTooltip:AddLine(button.slotName, .85, .76, .59) end
    if button.item then
        for line in button.itemDetails(button.item):gmatch("[^\n]+") do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
        GameTooltip:AddLine(L("Relevé Armurerie · lien en jeu indisponible."),.75,.75,.75,true)
    else
        GameTooltip:AddLine(button.hasVariant and L("Détails de l’objet indisponibles.")
            or L("Aucune pièce publiée pour cet emplacement."), 1, 1, 1, true)
    end
    GameTooltip:Show()
end
local function insertItem(button,mouseButton)
    if mouseButton~="LeftButton" or not IsModifiedClick("CHATLINK") then return end
    local link=button.inspectedLink or GL.ArmoryItemLink(button.item)
    if link then
        local insert=ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
        if insert then insert(link) end
    end
end
local function oneLine(parent, size, color)
    local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    UI.journalFont(label,"GameFontHighlight",size)
    label:SetTextColor(unpack(color))
    GL.Safe(label.SetWordWrap, label, false)
    GL.Safe(label.SetMaxLines, label, 1)
    return label
end

local function slotButton(parent, slot, index)
    local b=CreateFrame("Button",nil,parent)
    b.slotName=L(slot[2])
    b.slotID,b.emptyIcon=GL.Safe(GetInventorySlotInfo or (C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo),inventorySlots[index])
    b.trim=b:CreateTexture(nil,"BACKGROUND")
    b.icon=b:CreateTexture(nil,"ARTWORK")
    b.icon:SetPoint("TOPLEFT",b.trim,"TOPLEFT",1,-1)
    b.icon:SetPoint("BOTTOMRIGHT",b.trim,"BOTTOMRIGHT",-1,1)
    b.icon:SetTexCoord(.07,.93,.07,.93)
    b.label=oneLine(b,11,UI.theme.inkMuted)
    b.label:SetText(b.slotName)
    b.title=oneLine(b,13,UI.theme.ink)
    local highlight=UI.surface(b,{.7,.49,.23,.15})
    b:SetHighlightTexture(highlight)
    b:SetScript("OnEnter",openTip)
    b:SetScript("OnLeave",closeTip)
    b:SetScript("OnHide",closeTip)
    return b
end

local function clearModel(view)
    if view.modelUnit and view.model.ClearModel then view.model:ClearModel() end
    view.modelUnit,view.modelGUID=nil,nil
    view.model:Hide()
end
local positionButton
local function paintBody(view)
    local record=view.record
    if not record then return end
    view.image:Hide()
    local unit=not view.bodyPath and GL.VisiblePortraitUnit(record)
    if view.bodyPath then
        clearModel(view)
        view.image:SetTexture(view.bodyPath)
        view.image:Show()
        view.caption:SetText(L("Armurerie"))
    elseif unit and GL.Safe(UnitGUID,unit)==record.guid and view.model.SetUnit
        and (not IsUnitModelReadyForUI or GL.Safe(IsUnitModelReadyForUI,unit)) then
        if view.modelUnit~=unit or view.modelGUID~=record.guid then
            clearModel(view)
            local ok,result=pcall(view.model.SetUnit,view.model,unit)
            if ok and result~=false then view.modelUnit,view.modelGUID=unit,record.guid end
        end
        if view.modelGUID==record.guid then
            view.model:Show()
            view.caption:SetText(L("Modèle en jeu"))
        end
    else
        clearModel(view)
    end
    local hasBody=view.bodyPath or view.modelGUID
    if hasBody then view.stage:Show() else view.stage:Hide() end
    local rail=hasBody and math.floor(view.w*.32) or math.floor((view.w-8)/2)
    if rail~=view.rail then
        for i,b in ipairs(view.buttons) do positionButton(b,i,view.w,view.h,rail,view.rowHeight) end
        view.rail=rail
    end
end
local function build(parent,slots)
    local view=CreateFrame("Frame",nil,parent)
    view:SetAllPoints()
    view.stage=CreateFrame("Frame",nil,view)
    UI.surface(view.stage,UI.theme.gold,0,-1)
    UI.surface(view.stage,{.16,.105,.075},1)
    view.image=view.stage:CreateTexture(nil,"ARTWORK")
    view.image:SetPoint("CENTER",view.stage,"CENTER",0,8)
    view.model=CreateFrame("PlayerModel",nil,view.stage)
    view.model:SetPoint("TOPLEFT",view.stage,"TOPLEFT",2,-2)
    view.model:SetPoint("BOTTOMRIGHT",view.stage,"BOTTOMRIGHT",-2,24)
    view.model:EnableMouse(false)
    GL.Safe(view.model.SetPortraitZoom,view.model,0)
    view.caption=oneLine(view.stage,11,UI.theme.paper)
    view.caption:SetPoint("BOTTOM",view.stage,"BOTTOM",0,8)
    view.caption:SetJustifyH("CENTER")
    view.buttons={}
    for index, slot in ipairs(slots) do view.buttons[index]=slotButton(view,slot,index) end
    view:SetScript("OnHide",function(self)
        for _,b in ipairs(self.buttons) do closeTip(b) end
        clearModel(self)
    end)
    view:SetScript("OnShow",paintBody)
    -- ponytail: native models are needed only while an unarchived visible profile is open.
    view:SetScript("OnEvent",function(self,event,id,success)
        if not self:IsVisible() then return end
        if event=="GET_ITEM_INFO_RECEIVED" then
            local owner=GameTooltip and GameTooltip:GetOwner()
            if success and owner and owner.waitingForItem and owner:GetParent()==self and owner.item.id==id then
                openTip(owner)
                owner.waitingForItem=nil
            end
        elseif not self.bodyPath then paintBody(self) end
    end)
    for _,event in ipairs({"PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","UNIT_MODEL_CHANGED","UNIT_PORTRAIT_UPDATE","GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD","GET_ITEM_INFO_RECEIVED"}) do
        GL.Safe(view.RegisterEvent,view,event)
    end
    return view
end
positionButton=function(b,i,w,h,rail,rowHeight)
    local weapon=i>16
    local right=i>8 and not weapon
    local size=math.min(34,math.floor(rowHeight)-4)
    local width=weapon and math.floor((w-8)/3) or rail
    local x=weapon and (i-17)*(width+4) or right and w-width or 0
    local y=weapon and h-rowHeight or ((i-1)%8)*rowHeight
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",x,-y)
    b:SetSize(width,rowHeight-1)
    local anchor=right and "RIGHT" or "LEFT"
    local direction=right and -1 or 1
    b.trim:ClearAllPoints()
    b.trim:SetPoint(anchor,b,anchor,direction*2,0)
    b.trim:SetSize(size,size)
    for line,label in ipairs({b.label,b.title}) do
        label:ClearAllPoints()
        label:SetPoint(anchor,b,anchor,direction*(size+7),line==1 and 8 or -7)
        label:SetWidth(math.max(1,width-size-9))
        label:SetJustifyH(anchor)
    end
end
function GL.DrawDossierEquipment(parent,record,profile,slots,slotOrder,itemDetails)
    local view=parent.equipment or build(parent,slots)
    parent.equipment=view
    view.record=record
    local mediaKey=profile.mediaKey or record.guid
    view.bodyPath=GrudgeLedgerArmory and profile.body==true and type(mediaKey)=="string"
        and (mediaKey:match("^Player%-%d+%-%x+$") or mediaKey:match("^Name%-%x+$"))
        and ("Interface\\AddOns\\GrudgeLedgerPortraits\\"..mediaKey.."-body.tga") or nil
    local w,h=parent:GetWidth(),parent:GetHeight()
    local rowHeight=math.min(45,math.floor((h-6)/9))
    view.w,view.h,view.rowHeight,view.rail=w,h,rowHeight,nil
    local rail=math.floor(w*.32)
    local stageWidth,stageHeight=w-2*rail-8,rowHeight*8-2
    view.stage:ClearAllPoints()
    view.stage:SetPoint("TOP",view,"TOP",0,0)
    view.stage:SetSize(stageWidth,stageHeight)
    local imageWidth=math.min(stageWidth-4,(stageHeight-32)/2)
    view.image:SetSize(imageWidth,imageWidth*2)
    view.caption:SetWidth(stageWidth-4)
    paintBody(view)
    local variantKeys={}
    if type(profile.gear)=="table" then
        for key in pairs(profile.gear) do
            if type(key)=="string" then variantKeys[slotOrder(key)]=key end
        end
    end
    for i,b in ipairs(view.buttons) do
        closeTip(b)
        local key=variantKeys[i]
        local item=key and GL.ArmoryItem(record,key)
        local link=profile.inspectedGear and profile.inspectedGear[b.slotID]
        b.inspectedLink=link
        if profile.inspectedGear and (link or not profile.partialGear) then item=nil end
        b.item=type(item)=="table" and item or nil
        b:SetScript("OnClick",(link or (b.item and b.item.ref)) and insertItem or nil)
        b.itemDetails,b.hasVariant=itemDetails,b.item~=nil or (not profile.inspectedGear and key~=nil)
        local name=link and link:match("|h%[(.-)%]|h") or (b.item and item.name)
        b.itemName=type(name)=="string" and UI.plain(name) or nil
        local quality=b.item and type(item.quality)=="table" and qualityID[item.quality.type]
        local r,g,blue
        if quality then r,g,blue=GL.Safe(GetItemQualityColor,quality) end
        b.color=r and {r,g,blue} or UI.theme.paper
        if r then b.trim:SetColorTexture(r,g,blue) else b.trim:SetColorTexture(unpack(UI.theme.gold)) end
        local icon=link and GL.Safe(C_Item and C_Item.GetItemIconByID or GetItemIcon,link) or (b.item and tonumber(item.icon))
        local texture=(icon and icon>0 and icon) or b.emptyIcon
        if texture then b.icon:SetTexture(texture) else b.icon:SetColorTexture(unpack(UI.theme.panel)) end
        b.icon:SetAlpha((link or b.item or not texture) and 1 or .45)
        b.title:SetText(b.itemName or "—")
    end
end
