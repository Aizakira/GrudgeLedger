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
local cape={id=7,name="Cape | bleue",icon=134,quality={type="RARE"},variant="Endurance +7"}
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
assert(view.bodyPath:find(archived.."-body.tga",1,true) and view.image:IsShown() and not view.face:IsShown())
local back=view.buttons[4]
assert(back.item==cape and not back.scripts.OnClick)
back.scripts.OnEnter(back)
assert(GameTooltip.shown and GameTooltip.title=="Cape || bleue" and GameTooltip.lines[2]=="Endurance +7")
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
assert(view.model:IsShown() and view.model.loaded==live and not view.image:IsShown())
assert(not GameTooltip.shown and not back.item and not view.bodyPath)
mock.units.target.guid=archived
view.scripts.OnEvent(view,"PLAYER_TARGET_CHANGED")
assert(not view.model:IsShown() and view.model.loaded==nil and view.face:IsShown(),"true observed portrait after losing live unit")
missing.scripts.OnEnter(missing)
view:Hide()
assert(not GameTooltip.shown)
print("PASS equipment paper doll: 19 slots, official body, exact variant on hover only, GUID-checked live model and stale state cleanup")
