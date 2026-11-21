-- The Armory slot order mirrors the character sheet: two rails and three weapon slots.
local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local L = GL.L
local qualityID = {POOR=0, COMMON=1, UNCOMMON=2, RARE=3, EPIC=4, LEGENDARY=5, ARTIFACT=6, HEIRLOOM=7}
local inventorySlots = {"HeadSlot","NeckSlot","ShoulderSlot","BackSlot","ChestSlot","ShirtSlot","TabardSlot","WristSlot",
    "HandsSlot","WaistSlot","LegsSlot","FeetSlot","Finger0Slot","Finger1Slot","Trinket0Slot","Trinket1Slot",
    "MainHandSlot","SecondaryHandSlot","RangedSlot"}

-- Inventory slot numbers never changed; the game's lookup only adds the empty-slot picture.
local slotNumbers = {1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18}

local function closeTip(button)
    button.waitingForItem=nil
    if GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner() == button then GameTooltip:Hide() end
end
-- A piece seen well before the latest snapshot may have been replaced since: say when it was seen.
local function addSeenLine(button)
    if button.seenAt then
        GameTooltip:AddLine(L("Vu le %s, avant le dernier relevé."):format(date("%d/%m/%Y %H:%M",button.seenAt)),.95,.75,.35,true)
    end
end
local function openTip(button)
    if not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_CURSOR")
    local link=button.inspectedLink or GL.ArmoryItemLink(button.item)
    button.waitingForItem=not link and button.item and button.item.ref
    if link and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(link)
        GameTooltip:AddLine(L("Maj + clic pour insérer dans la discussion."),.75,.75,.75)
        addSeenLine(button)
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
        addSeenLine(button)
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
    b.slotID=GL.Clean(b.slotID,"number") or slotNumbers[index]
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

-- Optional photos from the Avatar Replay Lab studio (a separate addon). Nothing is read when it
-- is not installed; its read-only function returns the bust and the poses of a player.
function GL.StudioPhotos(guid)
    local api = type(AvatarReplayLabPhotos) == "table" and AvatarReplayLabPhotos
    if not api or type(api.Get) ~= "function" or type(guid) ~= "string" then
        return
    end
    local ok, photos = pcall(api.Get, guid)
    if ok and type(photos) == "table" and type(photos.bust) == "string" and type(photos.poses) == "table" then
        return photos
    end
end
-- Pose shown on the equipment stage: the studio's own order when it gives one (its poses change
-- between versions, "menace" replaced "recherche"), else this order; a click shows the next one.
local POSE_ORDER = {"menace", "recherche", "combat", "amical", "vaincu", "moqueur"}
local function poseList(photos)
    local list, seen = {}, {}
    local order = type(photos.order) == "table" and photos.order or POSE_ORDER
    for _, name in ipairs(order) do
        if type(name) == "string" and not seen[name] and type(photos.poses[name]) == "string" then
            list[#list + 1], seen[name] = name, true
        end
    end
    return list
end

-- Kept models. Measured in the game (0.34.1 probe): a PlayerModel set once from a player keeps his
-- real look, gear included, after he is deselected and out of sight. The game refuses to inspect an
-- enemy, so this is the one way the addon alone can show what the player who killed you wore.
-- Twelve models, the oldest recycled first; a model is taken again after five minutes, since gear
-- changes. Nothing is saved: the models are gone at the next reload.
local KEPT_MAX, KEPT_FRESH = 12, 300
local kept, keptOrder, keptHost, keptUnsupported = {}, {}, nil, false
local function park(entry)
    entry.shown = nil
    entry.frame:SetParent(keptHost)
    entry.frame:ClearAllPoints()
    -- Parked on screen and fully transparent: a model outside the screen may never be loaded.
    entry.frame:SetPoint("TOPLEFT", keptHost, "TOPLEFT", 0, 0)
    entry.frame:SetSize(200, 400)
    entry.frame:SetAlpha(0)
end
-- The stalest model that is not on a sheet gives its frame; a model taken in the last five minutes
-- is never evicted, so a crowd of thirteen cannot make the pool retake models at every poll.
local function recycled(now)
    local oldest
    for i, guid in ipairs(keptOrder) do
        local entry = kept[guid]
        if not entry.shown and (not oldest or entry.at < kept[keptOrder[oldest]].at) then oldest = i end
    end
    local entry = oldest and kept[keptOrder[oldest]]
    if not entry or (entry.at > 0 and now - entry.at < KEPT_FRESH) then return nil end
    kept[table.remove(keptOrder, oldest)] = nil
    return entry
end
function GL.KeepModel(unit, guid)
    if keptUnsupported or type(guid) ~= "string" then return false end
    local now, entry = GL.Now(), kept[guid]
    if entry and (entry.shown or now - entry.at < KEPT_FRESH) then return entry.at > 0 end
    if GL.Safe(UnitGUID, unit) ~= guid or (IsUnitModelReadyForUI and not GL.Safe(IsUnitModelReadyForUI, unit)) then return false end
    if not entry then
        if #keptOrder >= KEPT_MAX then
            entry = recycled(now)
            if not entry then return false end
        else
            keptHost = keptHost or CreateFrame("Frame", nil, UIParent)
            keptHost:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
            keptHost:SetSize(1, 1)
            entry = { frame = CreateFrame("PlayerModel", nil, keptHost) }
            if not entry.frame.SetUnit then
                keptUnsupported = true
                return false
            end
            entry.frame:EnableMouse(false)
            GL.Safe(entry.frame.SetKeepModelOnHide, entry.frame, true)
            park(entry)
        end
        kept[guid] = entry
        keptOrder[#keptOrder + 1] = guid
    end
    GL.Safe(entry.frame.ClearModel, entry.frame)
    local ok, loaded = pcall(entry.frame.SetUnit, entry.frame, unit)
    entry.at = ok and loaded ~= false and now or 0
    return entry.at > 0
end
-- When the model of this player was taken, or nil.
function GL.KeptModelAt(guid)
    local entry = kept[guid]
    return entry and entry.at > 0 and entry.at or nil
end
local function showKept(view, guid)
    local entry = guid and kept[guid]
    if entry and entry.at == 0 then entry = nil end
    if view.kept and view.kept ~= entry then
        park(view.kept)
        view.kept = nil
    end
    if entry and view.kept ~= entry then
        entry.shown = true
        entry.frame:SetParent(view.stage)
        entry.frame:ClearAllPoints()
        entry.frame:SetAllPoints(view.model)
        entry.frame:SetAlpha(1)
        entry.frame:Show()
        view.kept = entry
    end
end

local function clearModel(view)
    if view.modelUnit and view.model.ClearModel then view.model:ClearModel() end
    view.modelUnit,view.modelGUID=nil,nil
    view.model:Hide()
end
local positionButton
local function applyOutfit(view)
    local actor=view.preview
    actor:Undress()
    for i,b in ipairs(view.buttons) do
        if i<=12 or i==17 or i==18 or (i==19 and not view.buttons[17].item and not view.buttons[17].inspectedLink) then
            local link=b.inspectedLink or (b.item and (b.item.ref or (b.item.id and ("item:"..b.item.id))))
            if link then
                local id=tonumber(link:match("item:(%d+)"))
                if C_Item and C_Item.IsItemDataCachedByID and id and not C_Item.IsItemDataCachedByID(id) then
                    if not view.pendingItems[id] then
                        view.pendingItems[id]=true
                        GL.Safe(C_Item.RequestLoadItemDataByID,id)
                    end
                else
                    GL.Safe(actor.TryOn,actor,link,i==18 and "SECONDARYHANDSLOT" or nil)
                end
            end
        end
    end
end

-- Four levels: the live model when the player is visible, then the model kept from the last time
-- he was seen this session, then the studio photos, then the standard model of the race wearing
-- the recorded gear.
local function layoutBody(view)
    local live=view.modelGUID~=nil
    local held=not live and view.kept
    local poses=not live and not held and view.photos and poseList(view.photos) or {}
    local photo=poses[(view.photoIndex-1)%math.max(1,#poses)+1]
    local outfit=not live and not held and not photo and view.previewReady
    view.preview:SetAlpha(outfit and 1 or 0)
    if live or held or outfit or photo then view.face:Hide() else view.face:Show() end
    if photo then
        view.photo:SetTexture(view.photos.poses[photo])
        view.photo:Show()
        view.photoButton:Show()
    else
        view.photo:Hide()
        view.photoButton:Hide()
    end
    local caption=live and L("Modèle en jeu") or outfit and L("Tenue reconstituée") or L("Portrait")
    if photo then
        caption=L("Photo du studio · %s"):format(GL.Safe(date,"%d/%m/%Y",view.photos.at) or "?")
    end
    if held then
        caption=L("Vu en jeu à %s"):format(GL.Safe(date,"%H:%M",held.at) or "?")
    end
    view.caption:SetText(caption)
    view.stage:Show()
    local rail=math.floor(view.w*.32)
    if rail~=view.rail then
        for i,b in ipairs(view.buttons) do positionButton(b,i,view.w,view.h,rail,view.rowHeight) end
        view.rail=rail
    end
end

local function finishPreview(view)
    local model=view.preview
    if not view.displayID or view.previewReady or model:GetDisplayInfo()~=view.displayID then return end
    local file=model:GetModelFileID()
    if not file or file==0 then return end
    view.previewReady=true
    applyOutfit(view)
    layoutBody(view)
end

local function paintBody(view)
    local record=view.record
    if not record then return end
    local unit=GL.VisiblePortraitUnit(record)
    if unit and record.guid and GL.Safe(UnitGUID,unit)==record.guid and view.model.SetUnit
        and (not IsUnitModelReadyForUI or GL.Safe(IsUnitModelReadyForUI,unit)) then
        if view.modelUnit~=unit or view.modelGUID~=record.guid then
            clearModel(view)
            local ok,result=pcall(view.model.SetUnit,view.model,unit)
            if ok and result~=false then view.modelUnit,view.modelGUID=unit,record.guid end
        end
        if view.modelGUID==record.guid then view.model:Show() end
    else
        clearModel(view)
    end
    showKept(view,not view.modelGUID and record.guid)
    finishPreview(view)
    layoutBody(view)
end
local function build(parent,slots)
    local view=CreateFrame("Frame",nil,parent)
    view:SetAllPoints()
    view.stage=CreateFrame("Frame",nil,view)
    view.model=CreateFrame("PlayerModel",nil,view.stage)
    view.model:SetPoint("TOPLEFT",view.stage,"TOPLEFT",2,-2)
    view.model:SetPoint("BOTTOMRIGHT",view.stage,"BOTTOMRIGHT",-2,24)
    view.model:EnableMouse(false)
    GL.Safe(view.model.SetPortraitZoom,view.model,0)
    view.preview=CreateFrame("DressUpModel",nil,view.stage)
    view.preview:SetAllPoints(view.model)
    view.preview:EnableMouse(false)
    GL.Safe(view.preview.SetKeepModelOnHide,view.preview,true)
    GL.Safe(view.preview.SetPortraitZoom,view.preview,0)
    view.preview:SetAlpha(0)
    view.preview:SetScript("OnModelLoaded",function() finishPreview(view) end)
    view.face=CreateFrame("Frame",nil,view.stage)
    view.face:SetPoint("CENTER",view.stage,"CENTER",0,8)
    view.face.raceIcon=view.face:CreateTexture(nil,"ARTWORK")
    view.face.raceIcon:SetAllPoints()
    view.face.classIcon=view.face:CreateTexture(nil,"OVERLAY")
    view.face.classIcon:SetSize(16,16)
    view.face.classIcon:SetPoint("BOTTOMRIGHT")
    -- A studio photo is a 1:2 transparent cutout; a click on it shows the next pose.
    view.photo=view.stage:CreateTexture(nil,"ARTWORK")
    view.photo:SetPoint("BOTTOM",view.stage,"BOTTOM",0,24)
    view.photo:Hide()
    view.photoButton=CreateFrame("Button",nil,view.stage)
    view.photoButton:SetAllPoints(view.photo)
    view.photoButton:SetScript("OnClick",function()
        view.photoIndex=view.photoIndex+1
        layoutBody(view)
    end)
    view.photoButton:Hide()
    view.photoIndex=1
    view.caption=oneLine(view.stage,11,UI.theme.ink)
    view.caption:SetPoint("BOTTOM",view.stage,"BOTTOM",0,8)
    view.caption:SetJustifyH("CENTER")
    view.buttons={}
    for index, slot in ipairs(slots) do view.buttons[index]=slotButton(view,slot,index) end
    view:SetScript("OnHide",function(self)
        for _,b in ipairs(self.buttons) do closeTip(b) end
        clearModel(self)
        showKept(self,nil)
    end)
    view:SetScript("OnShow",paintBody)
    -- ponytail: native models are needed only while the selected player is visible.
    view:SetScript("OnEvent",function(self,event,id,success)
        if not self:IsVisible() then return end
        if event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT" then
            if view.pendingItems and view.pendingItems[id] then
                if success then
                    view.pendingItems[id]=nil
                    if view.previewReady then applyOutfit(view); layoutBody(view) end
                elseif not view.itemRetries[id] and C_Timer and C_Timer.After then
                    local pending=view.pendingItems
                    view.itemRetries[id]=true
                    C_Timer.After(1,function()
                        if view.pendingItems==pending and pending[id] then GL.Safe(C_Item.RequestLoadItemDataByID,id) end
                    end)
                end
            end
            local owner=GameTooltip and GameTooltip:GetOwner()
            if success and owner and owner.waitingForItem and owner:GetParent()==self and owner.item.id==id then
                openTip(owner)
                owner.waitingForItem=nil
            end
        else paintBody(self) end
    end)
    for _,event in ipairs({"PLAYER_TARGET_CHANGED","UPDATE_MOUSEOVER_UNIT","PLAYER_FOCUS_CHANGED",
        "NAME_PLATE_UNIT_ADDED","NAME_PLATE_UNIT_REMOVED","UNIT_MODEL_CHANGED","UNIT_PORTRAIT_UPDATE","GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD","GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT"}) do
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
local raceByID={"Human","Orc","Dwarf","NightElf","Scourge","Tauren","Gnome","Troll"}
-- Classic humanoid NPC displays with a baked skin in CreatureDisplayInfoExtra.
-- The bare player display IDs carry no skin when loaded outside a unit.
local dressedDisplays={
    Human={2080,3977}, Orc={3851,1378}, Dwarf={8709,4112}, NightElf={2595,1937},
    Scourge={1574,15952}, Tauren={3813,2118}, Gnome={15265,3124}, Troll={2588,6430},
}
-- Forever uses one file token for two Skyborne races with distinct baked HD skins.
local skyborneDisplays={[95]={136836,136837},[96]={136966,137633}}
function GL.MannequinDisplay(record,identity)
    local race=record.race or raceByID[record.raceID]
    local catalogRace=type(identity)=="table" and raceByID[identity.raceID]
    local sex=record.sex or (catalogRace and (not race or catalogRace==race) and identity.sex)
    local displays=dressedDisplays[race or catalogRace]
    if race=="Skyborne" or not race then
        local raceID=record.raceID or (type(identity)=="table" and identity.raceID)
        if skyborneDisplays[raceID] then
            displays=skyborneDisplays[raceID]
            if sex~=2 and sex~=3 and type(identity)=="table" and identity.raceID==raceID then sex=identity.sex end
        end
    end
    return displays and (sex==2 or sex==3) and displays[sex-1]
end
local function dressPreview(view,identity)
    local id=GL.MannequinDisplay(view.record,identity)
    view.pendingItems={}
    view.itemRetries={}
    if id and view.displayID==id then
        if view.previewReady then applyOutfit(view) else finishPreview(view) end
        return
    end
    local model=view.preview
    view.displayID,view.previewReady=nil,nil
    model:SetAlpha(0)
    if not (model.ClearModel and model.GetDisplayInfo and model.GetModelFileID and model.SetDisplayInfo and model.TryOn and model.Undress) then return end
    model:ClearModel()
    if not id then return end
    view.displayID=id
    model:SetDisplayInfo(id)
    finishPreview(view)
end
function GL.DrawDossierEquipment(parent,record,profile,slots,slotOrder,itemDetails)
    local view=parent.equipment or build(parent,slots)
    parent.equipment=view
    if view.record~=record then
        view.photoIndex=1
    end
    view.record=record
    view.photos=record and GL.StudioPhotos(record.guid)
    local w,h=parent:GetWidth(),parent:GetHeight()
    local rowHeight=math.min(45,math.floor((h-6)/9))
    view.w,view.h,view.rowHeight,view.rail=w,h,rowHeight,nil
    local rail=math.floor(w*.32)
    local stageWidth,stageHeight=w-2*rail-8,rowHeight*8-2
    view.stage:ClearAllPoints()
    view.stage:SetPoint("TOP",view,"TOP",0,0)
    view.stage:SetSize(stageWidth,stageHeight)
    view.caption:SetWidth(stageWidth-4)
    local faceSize=math.min(96,stageWidth-4,stageHeight-28)
    view.face:SetSize(faceSize,faceSize)
    local photoHeight=stageHeight-30
    view.photo:SetSize(photoHeight/2,photoHeight)
    GL.PaintBookPortrait(view.face,record)
    -- Pieces older than the snapshot by more than an hour are marked, not hidden.
    local pieceDates=type(profile.dates)=="table" and profile.dates.gear or {}
    local snapshotAt=tonumber(profile.gearAt)
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
        local seen=not link and key and tonumber(pieceDates[key])
        b.seenAt=seen and snapshotAt and snapshotAt-seen>3600 and seen or nil
        b.icon:SetAlpha(((link or b.item or not texture) and 1 or .45)*(b.seenAt and .7 or 1))
        b.title:SetText(b.itemName or "—")
    end
    dressPreview(view,profile.identity)
    paintBody(view)
end
