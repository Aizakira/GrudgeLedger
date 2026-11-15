assert(loadfile(TEST_WORK.."/tests/wow_mock.lua"))()
assert(loadfile(TEST_ROOT.."/Core.lua"))("GrudgeLedger")
assert(loadfile(TEST_ROOT.."/UITheme.lua"))()
assert(loadfile(TEST_ROOT.."/DossierTalentData.lua"))()
assert(loadfile(TEST_ROOT.."/DossierTalents.lua"))()
local GL=GrudgeLedger
GL.InitDB()
local n,classes=0,0
for _,branches in pairs(GL.DossierTalentData) do
    classes=classes+1; assert(#branches==3)
    for _,b in ipairs(branches) do
        local cells,ids={},{}
        for _,t in ipairs(b.nodes) do
            local col,row=t[3],t[4]
            assert(col>=0 and col<4 and row>=0 and row<7 and not cells[10*row+col])
            cells[10*row+col],ids[t[1]]=true,true
            assert(t[5]>0 and t[6]>0 and #t[7]>0 and #t[8]>0)
            n=n+1
        end
        for _,edge in ipairs(b.edges) do assert(ids[edge[1]] and ids[edge[2]]) end
    end
end
assert(classes==9 and n==467)
GameTooltip={owner=nil,lines={}}
function GameTooltip:SetOwner(v) self.owner=v; self.lines={} end
function GameTooltip:SetText(v) self.lines[1]=v end
function GameTooltip:AddLine(v) self.lines[#self.lines+1]=v end
function GameTooltip:IsOwned(v) return self.owner==v end
function GameTooltip:Show() self.shown=true end
function GameTooltip:Hide() self.owner=nil; self.shown=false end
local parent=CreateFrame("Frame",nil,UIParent)
parent:SetSize(543,391)
local published={{points=2,name="Combat farouche",id="feral-combat",talents={{134399,"Férocité",2,132190,"Effet de rang deux."}}}}
local function cell(id)
    for _,b in ipairs(parent.talentButtons) do if b:IsShown() and b.node and b.node[1]==id then return b end end
end
assert(GL.DrawDossierTalents(parent,{}, {trees=published})<=391)
local learned=assert(cell(134399)); local other=assert(cell(134400))
assert(learned.rank==2 and other.rank==0 and not learned.scripts.OnClick)
learned.scripts.OnEnter(learned)
assert(GameTooltip:IsOwned(learned) and GameTooltip.lines[3]=="Effet de rang deux.")
other.scripts.OnLeave(other); assert(GameTooltip.shown)
learned.scripts.OnLeave(learned); assert(not GameTooltip.shown)
learned.scripts.OnEnter(learned)
GL.DrawDossierTalents(parent,{class="DRUID"},{})
assert(not GameTooltip.shown and cell(134399)==learned and learned.rank==nil)
published[1].points=3
GL.DrawDossierTalents(parent,{class="DRUID"},{trees=published})
assert(learned.rank==2 and other.rank==nil)
GL.DrawDossierTalents(parent,{}, {trees={{points=1,talents={{900001,"Nouveau talent",1,nil,"Effet"}}}}})
assert(not cell(134399))
local b=parent.talentButtons[1]; b.scripts.OnEnter(b)
assert(b:IsShown() and not b.node and GameTooltip.lines[1]=="Nouveau talent" and GameTooltip.lines[3]=="Effet")
print("PASS Forever talent catalog, real layout, published vs unknown ranks, archived spell hover and player switching")
