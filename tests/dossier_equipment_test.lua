local mock=assert(loadfile(TEST_WORK.."/tests/wow_mock.lua"))()
for _,file in ipairs({"Core","UITheme","UI","DossierEquipment"}) do
    assert(loadfile(TEST_ROOT.."/"..file..".lua"))("GrudgeLedger")
end
local GL=GrudgeLedger
GL.InitDB()
for raceID,ids in pairs({[5]={1574,15952},[95]={136836,136837},[96]={136966,137633}}) do
    for i,id in ipairs(ids) do
        assert(GL.MannequinDisplay({}, {raceID=raceID,sex=i+1})==id)
        assert(GL.MannequinDisplay({raceID=raceID,sex=i+1})==id)
    end
end
assert(GL.MannequinDisplay({race="Skyborne"}, {raceID=96,sex=3})==137633)
assert(not GL.MannequinDisplay({race="Skyborne"}, {raceID=5,sex=2}))
local parent=CreateFrame("Frame",nil,UIParent)
parent:SetSize(515,398)
local slots,order={},{}
for i,key in ipairs({"head","neck","shoulder","back","chest","shirt","tabard","wrist","hand","waist","leg","foot",
    "leftfinger","rightfinger","lefttrinket","righttrinket","weapon","offhand","ranged"}) do
    slots[i]={key,key,key}
    order[key]=i
end
local archived,live="Player-1-00AA","Player-1-00BB"
local cape={id=9890,ref="item:9890::::::::::::1:12733",name="Cape | bleue",icon=134,quality={type="RARE"},variant="Endurance +7"}
GrudgeLedgerArmory={profiles={[archived]={body=true,gear={back=2,leftFinger=99}},[live]={gear={}}},items={{id=7,variant="Wrong"},cape}}
GameTooltip={
    GetOwner=function(self) return self.owner end, SetOwner=function(self,o) self.owner=o end,
    SetText=function(self,title) self.title=title self.lines={} end,
    AddLine=function(self,line) table.insert(self.lines,line) end,
    Hide=function(self) self.shown=false self.owner=nil end, Show=function(self) self.shown=true end,
}
local function draw(guid)
    GL.DrawDossierEquipment(parent,{guid=guid,race=guid==archived and "Scourge" or nil,sex=2},GrudgeLedgerArmory.profiles[guid],slots,
        function(key) return order[key:lower()] or 20 end,function(item) return item.variant end)
    return parent.equipment
end
local create=CreateFrame
local dressed={}
function CreateFrame(kind,...)
    local widget=create(kind,...)
    if kind=="DressUpModel" then
        function widget:ClearModel() self.display=nil; self.file=nil end
        function widget:SetDisplayInfo(id) self.requested=id; self.requests=(self.requests or 0)+1 end
        function widget:GetDisplayInfo() return self.display end
        function widget:GetModelFileID() return self.file end
        function widget:Undress() dressed={} end
        function widget:TryOn(link) dressed[link]=true end
    end
    return widget
end
function UnitSex(unit) return unit=="player" and 3 or nil end
function UnitIsVisible(unit) return unit=="player" end
local timers={}
C_Timer={After=function(delay,cb) timers[#timers+1]=cb end}
local cachedForPreview=false
C_Item={IsItemDataCachedByID=function() return cachedForPreview end,RequestLoadItemDataByID=function(id) assert(id==9890) end}
local view=draw(archived)
local model=view.preview
assert(#view.buttons==19 and view.stage:GetWidth()>=150)
assert(view.buttons[17].slotName=="weapon" and view.buttons[19].slotName=="ranged")
assert(view.stage:IsShown() and view.face:IsShown() and model.requested==1574,"offline male undead loads without a matching visible donor or scene")
draw(archived)
assert(model.requests==1,"redrawing while the native model is streaming must not restart it")
model.display,model.file=3851,111
model.scripts.OnModelLoaded(model)
assert(view.face:IsShown() and not view.previewReady,"a stale orc load is rejected")
model.display,model.file=model.requested,42
model.scripts.OnModelLoaded(model)
assert(view.previewReady and not view.face:IsShown() and not dressed[cape.ref] and view.pendingItems[9890])
view.scripts.OnEvent(view,"ITEM_DATA_LOAD_RESULT",9890,false)
assert(not view.face:IsShown() and view.itemRetries[9890],"one uncached item cannot replace the body with a portrait")
timers[#timers]()
cachedForPreview=true
view.scripts.OnEvent(view,"ITEM_DATA_LOAD_RESULT",9890,true)
assert(dressed[cape.ref] and not view.pendingItems[9890],"cold item is worn when the cache supplies it")
local back=view.buttons[4]
assert(back.item==cape and back.scripts.OnClick)
function strsplit(delim,s)
    local parts={}
    for part in (s..delim):gmatch("([^"..delim.."]*)"..delim) do parts[#parts+1]=part end
    return unpack(parts)
end
function back:GetParent() return view end
local cached,shift,draft=nil,true,"Avant "
C_Item={GetItemInfo=function(ref) assert(ref==cape.ref); return cape.name,cached end}
function IsModifiedClick(which) return which=="CHATLINK" and shift end
ChatFrameUtil={InsertLink=function(link) draft=draft..link end}
function GameTooltip:SetHyperlink(link) self.link=link; self.lines={} end
back.scripts.OnEnter(back)
assert(GameTooltip.shown and GameTooltip.title=="Cape || bleue" and GameTooltip.lines[2]=="Endurance +7")
back.scripts.OnClick(back,"LeftButton")
assert(draft=="Avant ")
cached="|cff1eff00|Hitem:9890::::::::41:1484:::1:12733:::::::|h[Cape de puissance]|h|r"
view.scripts.OnEvent(view,"GET_ITEM_INFO_RECEIVED",9890,true)
assert(GameTooltip.link==cached and draft=="Avant ")
shift=false; back.scripts.OnClick(back,"LeftButton"); assert(draft=="Avant ")
shift=true; back.scripts.OnClick(back,"LeftButton"); assert(draft=="Avant "..cached)
local original=draft
cached=cached:gsub("12733","12734")
back.scripts.OnClick(back,"LeftButton")
assert(draft==original and not GL.ArmoryItemLink(cape),"never share a different variant of the same base item")
view.buttons[3].scripts.OnLeave(view.buttons[3])
assert(GameTooltip.shown,"leaving an old icon cannot close another item's tooltip")
back.scripts.OnLeave(back)
assert(not GameTooltip.shown)
local missing=view.buttons[13]
missing.scripts.OnEnter(missing)
assert(GameTooltip.lines[1]:find("indisponibles",1,true))
-- A target change cannot leave another character's image, gear or tooltip on the sheet.
mock.units.target.guid=live
function UnitIsVisible(unit) return UnitGUID(unit)~=nil end
function SetPortraitTexture() end
view.model.SetUnit=function(self,unit) self.loaded=UnitGUID(unit) end
view.model.ClearModel=function(self) self.loaded=nil end
draw(live)
assert(view.model:IsShown() and view.model.loaded==live)
assert(not GameTooltip.shown and not back.item)
mock.units.target.guid=archived
view.scripts.OnEvent(view,"PLAYER_TARGET_CHANGED")
assert(not view.model:IsShown() and view.model.loaded==nil and view.stage:IsShown() and view.face:IsShown(),
    "without a matching model the contact portrait stays on the equipment page")
missing.scripts.OnEnter(missing)
view:Hide()
assert(not GameTooltip.shown)
GrudgeLedgerNativePortraits={[archived]=true}
draw(archived)
assert(not view.face:IsShown() and view.model.loaded==archived and view.model:IsShown() and view.stage:IsShown(),"live GUID wins even with an archived web body")
print("PASS equipment: body or expanded gear, model GUID, native variant tooltip, cold cache and chat draft")
