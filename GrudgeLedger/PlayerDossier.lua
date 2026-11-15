-- Character dossiers are read-only views over the personal journal and private Armory archive.
local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local french = not GetLocale or GetLocale() == "frFR"
local function tr(fr, en) return french and fr or en end
local unknown = tr("Non renseigné", "Unknown")
local function object(value) return type(value) == "table" and value or {} end
local function text(value)
    if type(value) == "string" and value ~= "" then return UI.plain(value) end
    if type(value) == "number" then return tostring(value) end
end
local function valueOf(value)
    if type(value) == "table" then return text(value.display_string) or text(value.name) or text(value.value) end
    return text(value)
end
local function timestamp(value)
    value = tonumber(value)
    if not value or value <= 0 then return unknown end
    if value >= 100000000000 then value = value / 1000 end -- Armory uses milliseconds; game clocks use seconds.
    return GL.Safe(date, "%d/%m/%Y %H:%M", math.floor(value)) or unknown
end
local function field(label, value) return label .. " : " .. (value or unknown) end
local slots = {
    {"head","Tête","Head"}, {"neck","Cou","Neck"}, {"shoulder","Épaules","Shoulders"},
    {"back","Dos","Back"}, {"chest","Torse","Chest"}, {"shirt","Chemise","Shirt"},
    {"tabard","Tabard","Tabard"}, {"wrist","Poignets","Wrists"}, {"hand","Mains","Hands"},
    {"waist","Taille","Waist"}, {"leg","Jambes","Legs"}, {"foot","Pieds","Feet"},
    {"leftfinger","Anneau 1","Ring 1"}, {"rightfinger","Anneau 2","Ring 2"},
    {"lefttrinket","Bijou 1","Trinket 1"}, {"righttrinket","Bijou 2","Trinket 2"},
    {"weapon","Main droite","Main hand"}, {"offhand","Main gauche","Off hand"}, {"ranged","À distance","Ranged"},
}
local slotIndex = {}
for i, s in ipairs(slots) do slotIndex[s[1]] = i end
local aliases = { finger1="leftfinger",finger2="rightfinger",trinket1="lefttrinket",trinket2="righttrinket",
    mainhand="weapon",legs="leg",feet="foot",hands="hand",shoulders="shoulder",wrists="wrist",shield="offhand" }
local function slotOrder(k)
    local key = k:lower():gsub("[^%a%d]", "")
    return slotIndex[aliases[key] or key] or (#slots + 1)
end
local function sortedKeys(t)
    local keys = {}
    for k in pairs(object(t)) do if type(k) == "string" then keys[#keys+1] = k end end
    table.sort(keys)
    return keys
end
local function prettyKey(k)
    return (k:gsub("(%l)(%u)", "%1 %2"):gsub("_"," "):lower():gsub("^%l", string.upper))
end
local statNames = {
    ITEMLEVEL=tr("Niveau d’objet","Item level"), MOVEMENTSPEED=tr("Vitesse de déplacement","Movement speed"),
    HEALTH=tr("Vie","Health"), MANA=tr("Mana","Mana"), ARMOR=tr("Armure","Armor"),
    ATTACKPOWER=tr("Puissance d’attaque","Attack power"), SPELLPOWER=tr("Puissance des sorts","Spell power"),
    STRENGTH=tr("Force","Strength"), AGILITY=tr("Agilité","Agility"), STAMINA=tr("Endurance","Stamina"),
    INTELLECT=tr("Intelligence","Intellect"), CRITICALSTRIKE=tr("Coup critique","Critical strike"),
    HASTE=tr("Hâte","Haste"), MASTERY=tr("Maîtrise","Mastery"), BONUSARMOR=tr("Armure supplémentaire","Bonus armor"),
    VERSATILITY=tr("Polyvalence","Versatility"), AVOIDANCE=tr("Évitement","Avoidance"),
    DAMAGE=tr("Dégâts","Damage"), ATTACKSPEED=tr("Vitesse d’attaque","Attack speed"),
    ATTACKDPS=tr("Dégâts par seconde","Attack DPS"), MANAREGEN=tr("Régénération de mana","Mana regeneration"),
    ENERGY=tr("Énergie","Energy"), RAGE=tr("Rage","Rage"), FOCUS=tr("Focalisation","Focus"),
    SPIRIT=tr("Esprit","Spirit"), RUNICPOWER=tr("Puissance runique","Runic power"),
    DODGE=tr("Esquive","Dodge"), PARRY=tr("Parade","Parry"), BLOCK=tr("Blocage","Block"),
}
local function itemDetails(item)
    local lines = {}
    local function add(label, v)
        if v then lines[#lines+1] = field(label, v) end
    end
    add(tr("Niveau d’objet","Item level"),valueOf(object(item.level).value) or valueOf(item.level))
    add(tr("Qualité","Quality"),valueOf(item.quality))
    add(tr("Armure","Armor"),valueOf(item.armor))
    for _,stat in ipairs(object(item.stats)) do
        local display = valueOf(object(stat).display)
        if display then lines[#lines+1] = display
        else
            local st=object(object(stat).type)
            add(statNames[st.type] or valueOf(st) or text(st.type) or tr("Statistique","Stat"),valueOf(object(stat).value))
        end
    end
    local weapon=object(item.weapon)
    add(tr("Dégâts","Damage"),valueOf(weapon.damage)); add(tr("Vitesse","Speed"),valueOf(weapon.attack_speed))
    add("DPS",valueOf(weapon.dps))
    for _,e in ipairs(object(item.enchantments)) do
        add(tr("Enchantement","Enchantment"),valueOf(e) or valueOf(object(e).source_item) or text(object(e).enchantment_id))
    end
    for _,s in ipairs(object(item.sockets)) do
        add(tr("Châsse","Socket"),valueOf(object(s).item) or valueOf(object(s).socket_type) or valueOf(s))
    end
    for _,s in ipairs(object(item.spells)) do
        local name, desc = valueOf(object(s).spell), text(object(s).description) or valueOf(s)
        add(tr("Effet","Effect"),name and desc and (name.." — "..desc) or desc or name)
    end
    local set=object(item.set)
    add(tr("Ensemble","Set"),valueOf(set.item_set) or valueOf(item.set))
    for _,effect in ipairs(object(set.effects)) do add(tr("Effet d’ensemble","Set effect"),valueOf(effect) or text(object(effect).description)) end
    for _,key in ipairs(sortedKeys(item.requirements)) do
        add(tr("Requis","Requires"),valueOf(item.requirements[key]))
    end
    local bonus={}
    for _,id in ipairs(object(item.bonus_list)) do if text(id) then bonus[#bonus+1]=text(id) end end
    if #bonus>0 then add(tr("Bonus de variante","Variant bonuses"),table.concat(bonus,", ")) end
    add(tr("Identifiant d’objet","Item ID"),text(item.id))
    return #lines>0 and table.concat(lines,"\n") or tr("Détails de la pièce non publiés.","No item details published.")
end
local function latestCombat(record)
    local latest
    for _,e in ipairs(object(record.history)) do
        if type(e)=="table" and not e.voided and e.voidReason~="battleground"
            and (e.kind=="kill" or e.kind=="death" or e.kind=="aggression") and type(e.time)=="number"
            and (not latest or e.time>=latest.time) then latest=e end
    end
    return latest
end

local frame
local percentages={CRITICALSTRIKE=true,DODGE=true,PARRY=true,BLOCK=true,HASTE=true,VERSATILITY=true,AVOIDANCE=true}
local function statValue(key,v)
    local function number(n)
        local s=("%.1f"):format(n):gsub("[.,]0$","")
        return french and s:gsub("%.",",") or s
    end
    if type(v)=="number" then return number(v)..(percentages[key] and " %" or "") end
    if type(v)=="table" and tonumber(v[1]) and tonumber(v[2]) then return number(v[1]).." – "..number(v[2]) end
    return valueOf(v)
end
local function draw(f)
    local localRecord=GL.Get("guid:"..f.guid)
    local record=localRecord or {guid=f.guid}
    local profile=object(GL.ArmoryProfile(record))
    local public=object(profile.identity)
    local name=text(record.fullName) or text(public.name) or text(f.knownName)
    if not name and GL.Bounties and GL.Bounties.MemberName then name=text(GL.Bounties.MemberName(f.guid)) end
    f.nameLabel:SetText(name or unknown)
    GL.PaintBookPortrait(f.portrait,record)
    local faction,race,class=GL.IdentityLabels(record)
    f.identity:SetText(table.concat({
        (record.race or record.raceName) and text(race) or text(public.race) or unknown,
        (record.class or record.className) and text(class) or text(public.class) or unknown,
        record.faction and text(faction) or text(public.faction) or unknown}," · "))
    local event=latestCombat(record)
    local combat=object(event and event.combat)
    local stats=object(profile.stats)
    -- Reuse the two-column stat rows as the selected character changes.
    local used,seen,y=0,{},0
    local function addStat(key)
        local val=statValue(key,stats[key])
        if not val then return end
        local c=f.statCells[used+1]
        if not c then
            c=CreateFrame("Frame",nil,f.identityBody); c:SetSize(117,44)
            c.value=UI.label(c,"","large",0,0,116); c.value:SetTextColor(unpack(UI.theme.paper))
            c.label=UI.label(c,"",nil,0,-23,117); UI.journalFont(c.label,"GameFontHighlight",11)
            c.label:SetTextColor(unpack(UI.theme.brass)); f.statCells[used+1]=c
        end
        c:ClearAllPoints(); c:SetPoint("TOPLEFT",(used%2)*122,-math.floor(used/2)*47); used=used+1
        c.value:SetText(val); c.label:SetText(statNames[key] or text(prettyKey(key))); c:Show(); seen[key]=true
    end
    for _,key in ipairs({"HEALTH","MANA","ENERGY","RAGE","FOCUS","RUNICPOWER","STRENGTH","AGILITY","STAMINA","INTELLECT","SPIRIT","ARMOR","CRITICALSTRIKE"}) do addStat(key) end
    for _,key in ipairs(sortedKeys(stats)) do if not seen[key] and key~="ITEMLEVEL" then addStat(key) end end
    for i=used+1,#f.statCells do f.statCells[i]:Hide() end
    y=math.ceil(used/2)*47
    local info={}
    if used==0 then info[1]=tr("Caractéristiques non publiées.\n","No attributes published.\n") end
    info[#info+1]=field(tr("Guilde","Guild"),text(record.guild) or text(public.guild))
    info[#info+1]=field(tr("Niveau Armurerie","Armory level"),valueOf(profile.level))
    info[#info+1]=field(tr("Niveau vu en jeu","Last observed level"),text(GL.ValidLevel(record.level)))
    info[#info+1]=field(tr("Dernière rencontre","Last encounter"),timestamp(record.lastEncounterAt or record.lastDirectEncounterAt))
    if event then
        info[#info+1]=field(tr("Dernier combat","Last combat"),timestamp(event.time))
        info[#info+1]=field(tr("Niveau adverse au combat","Opponent level in combat"),text(GL.ValidLevel(combat.opponentLevel)))
        info[#info+1]=field(tr("Votre niveau au combat","Your level in combat"),text(GL.ValidLevel(combat.playerLevel)))
    end
    f.observed:ClearAllPoints(); f.observed:SetPoint("TOPLEFT",0,-y-5); f.observed:SetText(table.concat(info,"\n"))
    f.identityBody:SetHeight(math.max(f.identityScroll:GetHeight(),y+f.observed:GetStringHeight()+12))
    local snap=f.page=="reputation" and profile.reputationsAt or profile.updated
    f.source:SetText(tr("Relevé Armurerie : ","Armory snapshot: ")..timestamp(snap))
    f.ilvl:SetText(f.page=="gear" and field(tr("Niv. d’objet moyen","Average item level"),valueOf(profile.averageItemLevel)) or "")
    for key,b in pairs(f.tabs) do UI.selectButton(b,f.page==key) end
    local gear,talents=f.page=="gear",f.page=="talents"
    if gear then f.equipment:Show(); GL.DrawDossierEquipment(f.equipment,record,profile,slots,slotOrder,itemDetails) else f.equipment:Hide() end
    if talents then
        f.talentScroll:Show()
        local h=GL.DrawDossierTalents(f.talents,record,profile)
        f.talents:SetHeight(math.max(f.talentScroll:GetHeight(),h))
        f.talentScroll:SetVerticalScroll(0)
    else f.talentScroll:Hide() end
    if gear or talents then f.scroll:Hide(); return end
    f.scroll:Show()
    local count,height=0,0
    local function row(label,amount,heading)
        count=count+1
        local r=f.rows[count]
        if not r then
            r=CreateFrame("Frame",nil,f.body); f.rows[count]=r
            r.caption=UI.label(r,"",nil,7,-4,510)
            r.amount=UI.label(r,"",nil,308,-4,198); r.amount:SetJustifyH("RIGHT")
            r.rule=r:CreateTexture(nil,"BACKGROUND"); r.rule:SetPoint("BOTTOMLEFT"); r.rule:SetPoint("BOTTOMRIGHT")
            r.rule:SetHeight(1); r.rule:SetColorTexture(.45,.28,.11,.21)
        end
        r.caption:SetWidth(amount and 292 or 500)
        UI.journalFont(r.caption,heading and "GameFontNormalLarge" or "GameFontHighlight",heading and 17 or 13)
        r.caption:SetTextColor(unpack(heading and UI.theme.red or UI.theme.ink)); r.amount:SetTextColor(unpack(UI.theme.ink))
        r.caption:SetText(label); r.amount:SetText(amount or "")
        local h=math.max(heading and 35 or 26,r.caption:GetStringHeight()+10,r.amount:GetStringHeight()+10)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT",0,-height); r:SetSize(514,h); r:Show(); height=height+h
    end
    if f.page=="reputation" then
        row(tr("Réputations auprès des factions","Faction reputations"),nil,true)
        local reps=object(profile.reputations)
        if #reps==0 then row(profile.reputations and tr("Aucune faction publiée.","No factions published.") or tr("Réputations non disponibles dans ce relevé.","Reputations are unavailable in this snapshot.")) end
        local group
        for _,v in ipairs(reps) do
            if v.group and v.group~=group then group=v.group; row(text(group) or unknown,nil,true) end
            local points=valueOf(v.value)
            if points and valueOf(v.max) then points=points.." / "..valueOf(v.max) end
            row(text(v.name) or unknown,(valueOf(v.standing) or unknown)..(points and (" · "..points) or ""))
        end
    else
        row(tr("Palmarès JcJ · Armurerie","PvP record · Armory"),nil,true)
        row(tr("Victoires honorables","Honorable kills"),valueOf(profile.honorableKills) or unknown)
        row(tr("Rang JcJ","PvP rank"),valueOf(profile.pvpRank) or unknown)
        row(tr("Champs de bataille","Battlegrounds"),profile.battlegroundsAt and timestamp(profile.battlegroundsAt),true)
        if #object(profile.battlegrounds)==0 then row(profile.battlegrounds and tr("Aucun champ de bataille publié.","No battlegrounds published.") or tr("Champs de bataille non renseignés.","Battlegrounds unavailable.")) end
        for _,v in ipairs(object(profile.battlegrounds)) do
            row(text(v.name) or unknown,(valueOf(v.games) or "—")..tr(" parties"," games").." · "..(valueOf(v.wins) or "—")..tr(" V"," W").." / "..(valueOf(v.losses) or "—")..tr(" D"," L"))
        end
        row(tr("Votre face-à-face · Journal","Your encounters · Journal"),nil,true)
        if localRecord then
            local p=GL.ContactMatchup(record)
            row(tr("Victoires / morts","Wins / deaths"),p.kills.." / "..p.deaths)
            row(tr("Honneur attribué","Attributed honor"),p.honorAwards>0 and text(p.honor) or unknown)
        else row(tr("Aucune rencontre personnelle enregistrée.","No personal encounters recorded.")) end
        row(tr("Face-à-face de la guilde","Guild encounters"),nil,true)
        if GL.Bounties and GL.Safe(GetGuildInfo,"player") then
            local wins,losses=GL.Bounties.GuildFights(f.guid)
            if wins==0 and losses==0 then row(tr("Aucun résultat partagé pour cette cible.","No shared results for this target."))
            else row(tr("Victoires / morts","Wins / deaths"),wins.." / "..losses) end
        else row(unknown) end
        row(tr("Hauts faits JcJ","PvP achievements"),type(profile.achievements)=="table" and tostring(#profile.achievements) or unknown,true)
        if profile.achievementsAt then row(field(tr("Relevé","Snapshot"),timestamp(profile.achievementsAt))) end
        for _,a in ipairs(object(profile.achievements)) do
            row((text(a.name) or unknown)..(a.accountWide and tr(" (compte)"," (account)") or ""))
        end
    end
    for i=count+1,#f.rows do f.rows[i]:Hide() end
    f.body:SetHeight(math.max(f.scroll:GetHeight(),height))
end

local function scrollArea(f,x,y,w,h)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",x,y); scroll:SetSize(w,h)
    local body=CreateFrame("Frame",nil,scroll)
    body:SetSize(w,h); scroll:SetScrollChild(body)
    return scroll,body
end
local function build()
    local f=UI.bookWindow("GrudgeLedgerPlayerDossier","Grudge Ledger")
    GL.SetupBookNavigation(f,"ledger")
    f.back=UI.button(f,tr("Retour","Back"),39,-154,116,function()
        f:Hide()
        if f.onReturn then f.onReturn() else GL.ShowLedger("guid:"..f.guid) end
    end)
    f.portrait=CreateFrame("Frame",nil,f); f.portrait:SetPoint("TOPLEFT",40,-193); f.portrait:SetSize(64,64)
    f.portrait.raceIcon=f.portrait:CreateTexture(nil,"ARTWORK"); f.portrait.raceIcon:SetAllPoints()
    f.portrait.classIcon=f.portrait:CreateTexture(nil,"OVERLAY"); f.portrait.classIcon:SetSize(16,16)
    f.portrait.classIcon:SetPoint("BOTTOMRIGHT")
    f.nameLabel=UI.label(f,"","large",111,-192,193)
    GL.Safe(f.nameLabel.SetMaxLines,f.nameLabel,2)
    f.identity=UI.label(f,"",nil,111,-237,193)
    UI.journalFont(f.identity,"GameFontHighlight",11)
    f.statHeading=UI.label(f,tr("Caractéristiques","Attributes"),"large",40,-266,255); f.statHeading:SetTextColor(unpack(UI.theme.brass))
    f.identityScroll,f.identityBody=scrollArea(f,40,-297,243,296)
    f.observed=UI.label(f.identityBody,"",nil,0,0,239); f.observed:SetTextColor(unpack(UI.theme.muted))
    f.bounty=UI.button(f,tr("Prime de ce joueur","Player bounty"),40,-612,247,function() GL.OpenContactBounty(f.guid) end)
    f.tabs={}; f.rows={}; f.statCells={}
    for i,s in ipairs({{"gear","Équipement","Equipment"},{"talents","Talents","Talents"},{"pvp","JcJ","PvP"},{"reputation","Réputations","Reputations"}}) do
        local key=s[1]
        f.tabs[key]=UI.button(f,tr(s[2],s[3]),352+(i-1)*137,-156,132,function()
            f.page=key; f.scroll:SetVerticalScroll(0); draw(f)
        end,true,true)
    end
    f.source=UI.label(f,"",nil,355,-196,312); f.source:SetTextColor(unpack(UI.theme.inkMuted))
    f.ilvl=UI.label(f,"",nil,669,-196,222); f.ilvl:SetJustifyH("RIGHT"); f.ilvl:SetTextColor(unpack(UI.theme.ink))
    f.scroll,f.body=scrollArea(f,352,-225,520,408)
    f.equipment=CreateFrame("Frame",nil,f); f.equipment:SetPoint("TOPLEFT",359,-229); f.equipment:SetSize(515,398)
    f.talentScroll,f.talents=scrollArea(f,352,-225,529,403)
    f.talentScroll.scrollBarHideable=true
    return f
end
function GL.OpenPlayerDossier(guid,onReturn,knownName)
    if type(guid)~="string" or #guid>32 or not guid:match("^Player%-%w+%-%w+$") then return false end
    frame=frame or build()
    frame.guid,frame.onReturn,frame.knownName,frame.page=guid,onReturn,knownName,"gear"
    frame.scroll:SetVerticalScroll(0); frame.identityScroll:SetVerticalScroll(0)
    GL.ShowBookPage(frame)
    draw(frame)
    return true
end
