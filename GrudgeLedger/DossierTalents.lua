-- The Armory reports purchased trait definition IDs, not spell IDs or screen positions.
local GL,UI=GrudgeLedger,GrudgeLedger.UITheme
local L=GL.L
local french=not GetLocale or GetLocale()=="frFR"
local function array(v) return type(v)=="table" and v or {} end
local function label(v) return type(v)=="string" and v~="" and UI.plain(v) or nil end
local classByTalent,branchByTalent={},{}
for class,trees in pairs(GL.DossierTalentData) do
    for i,branch in ipairs(trees) do
        for _,node in ipairs(branch.nodes) do classByTalent[node[1]],branchByTalent[node[1]]=class,i end
    end
end

function GL.ReadInspectedTalents(class)
    local catalog=GL.DossierTalentData[class]
    local configID=Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID
    if not catalog or not configID or not C_Traits or not GL.Safe(C_Traits.HasValidInspectData) then return end
    local config=GL.Safe(C_Traits.GetConfigInfo,configID)
    if not config or not config.treeIDs or #config.treeIDs==0 then return end
    local result,matched={},false
    for index,branch in ipairs(catalog) do
        result[index]={id=branch.en:lower():gsub(" ","-"),name=L(branch.fr),points=0,talents={}}
    end
    for _,treeID in ipairs(config.treeIDs) do
        local nodes=GL.Safe(C_Traits.GetTreeNodes,treeID)
        if not nodes or #nodes==0 then return end
        for _,nodeID in ipairs(nodes) do
            local node=GL.Safe(C_Traits.GetNodeInfo,configID,nodeID)
            if not node then return end
            local rank=GL.Clean(node.ranksPurchased,"number") or GL.Clean(node.activeRank,"number")
            if not rank then return end
            if rank>0 or not matched then
                local entryID=node.activeEntry and node.activeEntry.entryID or (node.entryIDs and node.entryIDs[1])
                local entry=entryID and GL.Safe(C_Traits.GetEntryInfo,configID,entryID)
                local id=entry and GL.Clean(entry.definitionID,"number")
                if id and classByTalent[id]==class then
                    matched=true
                    if rank>0 then
                        local branch=result[branchByTalent[id]]
                        branch.talents[#branch.talents+1]={id,nil,rank}
                        branch.points=branch.points+rank
                    end
                elseif rank>0 then return end
            end
        end
    end
    return matched and result or nil
end

local function classOf(record,profile)
    local class=array(profile.identity).classFile or record.class
    if GL.DossierTalentData[class] then return class end
    for _,tree in ipairs(array(profile.trees)) do
        for _,talent in ipairs(array(tree.talents)) do
            if classByTalent[talent[1]] then return classByTalent[talent[1]] end
        end
    end
end

local function readBuild(trees,class)
    local ranked,branches,unplaced={}, {}, {}
    local complete=#trees>0
    for _,tree in ipairs(trees) do
        local points=0
        local branch
        for _,t in ipairs(array(tree.talents)) do
            if type(t)=="table" and type(t[1])=="number" and type(t[3])=="number" and t[3]>0 then
                points=points+t[3]
                if class and classByTalent[t[1]]==class then
                    branch=branchByTalent[t[1]]
                    ranked[t[1]]=t
                else
                    unplaced[#unplaced+1]=t
                end
            end
        end
        if not branch then
            for i,d in ipairs(GL.DossierTalentData[class] or {}) do
                local slug=d.en:lower():gsub(" ","-")
                if slug==tree.id or d.en==tree.name or d.fr==tree.name or L(d.fr)==tree.name then branch=i; break end
            end
        end
        if branch then branches[branch]=tree end
        if points~=tree.points or (points>0 and not branch) then complete=false end
    end
    return ranked,branches,unplaced,complete
end

local function nodeName(node, savedName)
    local name = node and GL.Safe(C_Spell and C_Spell.GetSpellName or GetSpellInfo, node[2])
    return label(name) or label(savedName) or (node and (french and node[8] or node[7])) or L("Talent")
end

local function hideTip(button)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end
local function hover(button)
    if not GameTooltip then return end
    local node,t=button.node,button.learned
    local name=nodeName(node, t and t[2])
    GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
    GameTooltip:SetText(name,1,.85,.45)
    if button.rank~=nil then
        GameTooltip:AddLine(L("Rang ")..button.rank..(node and (" / "..node[5]) or ""),1,1,1)
    else
        GameTooltip:AddLine(L("Rang non renseigné"),.75,.75,.75)
    end
    local desc=label(t and t[5])
    if not desc and node and C_Spell and C_Spell.GetSpellDescription then
        desc=label(GL.Safe(C_Spell.GetSpellDescription,node[2]))
        if desc and button.rank and button.rank>0 then
            GameTooltip:AddLine(L("Description du sort de base"),.8,.8,.8)
        end
    end
    if desc then GameTooltip:AddLine(desc,1,.85,.55,true) end
    if button.requires then
        GameTooltip:AddLine(L("Talent lié : ")..button.requires,.8,.8,.8,true)
    end
    GameTooltip:Show()
end

local function drawNode(parent,index,x,y,node,learned,known,wide)
    local button=parent.talentButtons[index]
    if not button then
        button=CreateFrame("Button",nil,parent)
        button.rim=UI.surface(button,{.35,.30,.24})
        button.icon=button:CreateTexture(nil,"ARTWORK"); button.icon:SetPoint("TOPLEFT",2,-2); button.icon:SetSize(29,29)
        button.rankText=button:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        button.rankText:SetPoint("BOTTOMRIGHT",-2,1)
        button:SetScript("OnEnter",hover); button:SetScript("OnLeave",hideTip); button:SetScript("OnHide",hideTip)
        parent.talentButtons[index]=button
    end
    button:ClearAllPoints(); button:SetPoint("TOPLEFT",x,-y); button:SetSize(wide or 33,33)
    button.node,button.learned,button.requires=node,learned,nil
    button.rank=learned and learned[3] or (known and 0 or nil)
    local active=button.rank and button.rank>0
    button.icon:SetTexture((learned and learned[4]) or (node and node[6]) or 134400)
    GL.Safe(button.icon.SetDesaturated,button.icon,not active)
    local brightness=active and 1 or .54
    button.icon:SetVertexColor(brightness,brightness,brightness)
    if active then button.rim:SetColorTexture(1,.77,.17) else button.rim:SetColorTexture(.41,.38,.34) end
    button.rankText:SetText(active and tostring(button.rank) or "")
    if wide then
        button.caption=button.caption or UI.label(button,"",nil,39,-3,wide-66)
        button.caption:SetText(label(learned[2]) or "?"); button.caption:Show()
    elseif button.caption then button.caption:Hide() end
    button:Show()
    return button
end

local function caption(parent,index,value,x,y,w,footer)
    local text=parent.talentLabels[index] or UI.label(parent,"",nil,0,0,w)
    parent.talentLabels[index]=text
    text:ClearAllPoints(); text:SetPoint("TOPLEFT",x,-y); text:SetWidth(w)
    text:SetJustifyH(footer and "LEFT" or "CENTER")
    text:SetTextColor(unpack(footer and UI.theme.inkMuted or UI.theme.brass))
    text:SetText(value); text:Show()
end

function GL.DrawDossierTalents(parent,record,profile)
    local width=parent:GetWidth()
    local class=classOf(record,profile)
    local catalog=GL.DossierTalentData[class]
    local ranked,branches,extras,known=readBuild(array(profile.trees),class)
    local n,labels,lines=0,0,0
    if not parent.talentButtons then
        parent.talentButtons,parent.talentLabels,parent.talentLines={},{},{}
        parent.talentSurface=parent:CreateTexture(nil,"BACKGROUND",nil,-2)
        parent.talentBackground=parent:CreateTexture(nil,"BACKGROUND",nil,-1)
        for _,t in ipairs({parent.talentSurface,parent.talentBackground}) do
            t:SetPoint("TOPLEFT"); t:SetHeight(342); t:SetWidth(width)
        end
        parent.talentSurface:SetColorTexture(.11,.09,.08)
        parent.talentBackground:SetVertexColor(.49,.49,.49)
    end
    for _,button in ipairs(parent.talentButtons) do hideTip(button); button:Hide() end
    for _,t in ipairs(parent.talentLabels) do t:Hide() end
    for _,line in ipairs(parent.talentLines) do line:Hide() end
    parent.talentSurface:Hide(); parent.talentBackground:Hide()
    local function line(x,y,w,h,active)
        lines=lines+1
        local t=parent.talentLines[lines] or parent:CreateTexture(nil,"BORDER")
        parent.talentLines[lines]=t; t:ClearAllPoints(); t:SetPoint("TOPLEFT",x,-y); t:SetSize(w,h)
        if active then t:SetColorTexture(.91,.66,.18) else t:SetColorTexture(.39,.37,.33) end
        t:Show()
    end
    local height=0
    if catalog then
        parent.talentSurface:Show()
        local atlas="talent-background-"..class:lower()
        if parent.talentBackground.SetAtlas and C_Texture and GL.Safe(C_Texture.GetAtlasInfo,atlas) then
            parent.talentBackground:SetAtlas(atlas,false)
            parent.talentBackground:Show()
        end
        local bw=width/3
        for i,d in ipairs(catalog) do
            local branch=branches[i]
            local name=L(d.fr)
            local points=branch and branch.points or (known and 0)
            local left=(i-1)*bw
            if i>1 then line(left,3,1,336) end
            labels=labels+1
            caption(parent,labels,name.."\n"..(points and (points.." pts") or "—"),left+2,5,bw-4)
            local positions={}
            for _,node in ipairs(d.nodes) do
                local x=left+math.floor((bw-4*35)/2)+35*node[3]
                local y=51+42*node[4]
                n=n+1
                local button=drawNode(parent,n,x,y,node,ranked[node[1]],known)
                positions[node[1]]={x=x+16,y=y+16,node=node,button=button}
            end
            for _,edge in ipairs(d.edges) do
                local a,b=positions[edge[1]],positions[edge[2]]
                if a and b then
                    local lit=ranked[edge[1]] and ranked[edge[2]]
                    if a.x==b.x then
                        local step=b.y>a.y and 1 or -1
                        line(a.x-1,math.min(a.y,b.y),2,math.abs(a.y-b.y),lit)
                        for j=1,3 do line(b.x-j,b.y-step*(17+j),j*2,1,lit) end
                    elseif a.y==b.y then
                        local step=b.x>a.x and 1 or -1
                        line(math.min(a.x,b.x),a.y-1,math.abs(a.x-b.x),2,lit)
                        for j=1,3 do line(b.x-step*(17+j),b.y-j,1,j*2,lit) end
                    end
                    local req=nodeName(a.node, a.button.learned and a.button.learned[2])
                    b.button.requires=b.button.requires and (b.button.requires..", "..req) or req
                end
            end
        end
        height=349
        labels=labels+1
        caption(parent,labels,known and L("En couleur : points investis. En gris : talent non appris.")
            or L("Répartition incomplète ou non publiée. Les rangs inconnus sont indiqués au survol."),5,height,width-10,true)
        height=height+39
    end
    if #extras>0 then
        labels=labels+1
        caption(parent,labels,L("Talents publiés sans emplacement connu"),4,height,width-8,true)
        height=height+29
        for i,t in ipairs(extras) do
            n=n+1
            local w=math.floor(width/2)-5
            drawNode(parent,n,((i-1)%2)*(w+5),height+math.floor((i-1)/2)*35,nil,t,true,w)
        end
        height=height+35*math.ceil(#extras/2)
    elseif not catalog then
        caption(parent,1,L("Aucun arbre de talents publié pour ce joueur."),6,8,width-12,true)
        height=40
    end
    return height
end
