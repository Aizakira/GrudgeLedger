local mock=assert(loadfile(TEST_WORK.."/tests/wow_mock.lua"))()
for _,file in ipairs({"Core","UITheme","UI","DossierEquipment"}) do
    assert(loadfile(TEST_ROOT.."/"..file..".lua"))("GrudgeLedger")
end
local GL=GrudgeLedger
GL.InitDB()
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
    GL.DrawDossierEquipment(parent,{guid=guid},GrudgeLedgerArmory.profiles[guid],slots,
        function(key) return order[key:lower()] or 20 end,function(item) return item.variant end)
    return parent.equipment
end
local view=draw(archived)
assert(#view.buttons==19 and view.stage:GetWidth()>=150)
assert(view.buttons[17].slotName=="weapon" and view.buttons[19].slotName=="ranged")
assert(not view.stage:IsShown(), "a web body flagged as individual is still unverified")
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
assert(not view.model:IsShown() and view.model.loaded==nil and not view.stage:IsShown()
    and back:GetWidth()>parent:GetWidth()*.45,"without a body the two gear columns reclaim the space")
missing.scripts.OnEnter(missing)
view:Hide()
assert(not GameTooltip.shown)
GrudgeLedgerNativePortraits={[archived]=true}
draw(archived)
assert(view.model.loaded==archived and view.model:IsShown() and view.stage:IsShown(),"live GUID wins even with an archived web body")
print("PASS equipment: body or expanded gear, model GUID, native variant tooltip, cold cache and chat draft")
