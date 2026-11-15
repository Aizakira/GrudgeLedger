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
local function iconID(v)
    if type(v) == "number" and v > 0 and v == math.floor(v) then return v end
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
local function draw(f)
    local localRecord=GL.Get("guid:"..f.guid)
    local record=localRecord or {guid=f.guid}
    local archive=object(GrudgeLedgerArmory)
    local profile=object(type(archive.profiles)=="table" and GL.ArmoryProfile(record))
    local public=object(profile.identity)
    local name=text(record.fullName) or text(public.name) or text(f.knownName)
    if not name and GL.Bounties and GL.Bounties.MemberName then name=text(GL.Bounties.MemberName(f.guid)) end
    f.nameLabel:SetText(name or unknown)
    GL.PaintBookPortrait(f.portrait,record)
    local source=f.portrait.portraitUnit and tr("Portrait en jeu","Live portrait")
        or f.portrait.livePortraitGUID and tr("Portrait vu en jeu","Observed portrait")
        or f.portrait.archivedPortrait and tr("Portrait de l’Armurerie","Armory portrait")
        or tr("Portrait individuel indisponible","Individual portrait unavailable")
    local faction,race,class=GL.IdentityLabels(record)
    local identity = {
        localRecord and (record.race or record.raceName) and text(race) or text(public.race) or unknown,
        localRecord and (record.class or record.className) and text(class) or text(public.class) or unknown,
        record.faction and text(faction) or text(public.faction) or unknown,
    }
    local event=latestCombat(record)
    local combat=object(event and event.combat)
    local info={table.concat(identity," · "), field(tr("Guilde","Guild"),text(record.guild) or text(public.guild)),source,"",
        field(tr("Niveau Armurerie","Armory level"),valueOf(profile.level)),
        field(tr("Relevé Armurerie","Armory snapshot"),timestamp(profile.updated)),"",
        field(tr("Niveau vu en jeu","Last observed level"),text(GL.ValidLevel(record.level))),
        field(tr("Dernière rencontre","Last encounter"),timestamp(record.lastEncounterAt or record.lastDirectEncounterAt)),"",
        field(tr("Dernier combat","Last combat"),timestamp(event and event.time)),
        field(tr("Niveau adverse au combat","Opponent level in combat"),text(GL.ValidLevel(combat.opponentLevel))),
        field(tr("Niveau de votre personnage au combat","Your character’s combat level"),text(GL.ValidLevel(combat.playerLevel)))}
    f.identity:SetText(table.concat(info,"\n"))
    f.identityBody:SetHeight(math.max(f.identityScroll:GetHeight(),f.identity:GetStringHeight()+8))
    f.source:SetText(tr("Armurerie · ","Armory · ")..timestamp(profile.updated))
    for key,b in pairs(f.tabs) do UI.selectButton(b, f.page==key) end
    local count,height=0,0
    -- ponytail: reuse visible dossier rows, up to the largest profile opened this session.
    local function row(caption,texture,slot,heading)
        count=count+1
        local r=f.rows[count]
        if not r then
            r=CreateFrame("Button",nil,f.body)
            f.rows[count]=r
            r.selected=UI.surface(r,{0.60,0.38,0.14,0.19},0,0)
            r.icon=r:CreateTexture(nil,"ARTWORK"); r.icon:SetSize(25,25); r.icon:SetPoint("TOPLEFT",4,-2)
            r.caption=UI.label(r,"",nil,0,0,468)
            r:SetScript("OnClick",function(self)
                if self.slot then
                    local slot=self.slot
                    local anchor=self.offset-f.scroll:GetVerticalScroll()
                    f.slot=slot
                    draw(f)
                    -- Expanding the new piece can collapse hundreds of pixels above it.
                    for _,entry in ipairs(f.rows) do
                        if entry:IsShown() and entry.slot==slot then
                            f.scroll:SetVerticalScroll(math.max(0,math.min(entry.offset-anchor,f.body:GetHeight()-f.scroll:GetHeight())))
                            break
                        end
                    end
                end
            end)
        end
        r.slot,r.offset=slot,height
        local id=iconID(texture)
        r.icon:SetTexture(id)
        if id then r.icon:Show() else r.icon:Hide() end
        local left=(id and 36 or 8)
        r.caption:ClearAllPoints(); r.caption:SetPoint("TOPLEFT",left,-4); r.caption:SetWidth(514-left)
        r.caption:SetText(caption); r.caption:SetTextColor(unpack(heading and UI.theme.ink or UI.theme.inkMuted))
        if heading then UI.journalFont(r.caption,"GameFontNormalLarge",16) else UI.journalFont(r.caption,"GameFontHighlight",13) end
        local h=math.max(id and 31 or 23,r.caption:GetStringHeight()+10)
        r:ClearAllPoints(); r:SetPoint("TOPLEFT",0,-height); r:SetSize(518,h)
        if slot and f.slot==slot then r.selected:Show() else r.selected:Hide() end
        r:EnableMouse(slot~=nil); r:Show(); height=height+h
    end
    if f.page=="gear" then
        row(field(tr("Niveau d’objet moyen","Average item level"),valueOf(profile.averageItemLevel)),nil,nil,true)
        local gear=object(profile.gear)
        local keys=sortedKeys(gear)
        table.sort(keys,function(a,b)
            local i,j=slotOrder(a),slotOrder(b)
            return i<j or (i==j and a<b)
        end)
        if not gear[f.slot] then f.slot=keys[1] end
        for _,slot in ipairs(keys) do
            local item=object(type(archive.items)=="table" and GL.ArmoryItem(record,slot))
            local s=slots[slotOrder(slot)]
            local title=s and tr(s[2],s[3]) or text(prettyKey(slot))
            row(field(title,text(item.name)),item.icon,slot,true)
            if f.slot==slot then row(itemDetails(item)) end
        end
        if #keys==0 then row(tr("Équipement non renseigné.","Equipment unavailable.")) end
    elseif f.page=="talents" then
        local trees=object(profile.trees)
        if #trees==0 then row(tr("Aucun arbre de talents publié.","No talent trees published.")) end
        for _,rawTree in ipairs(trees) do
            local tree=object(rawTree)
            row((text(tree.name) or unknown).." · "..(text(tree.points) or "?").." points",nil,nil,true)
            if #object(tree.talents)==0 then row(tr("Aucun talent détaillé.","No talents listed.")) end
            for _,rawTalent in ipairs(object(tree.talents)) do
                local t=object(rawTalent)
                row((text(t[2]) or unknown).." · "..tr("rang ","rank ")..(text(t[3]) or "?"),t[4])
            end
        end
    else
        row(tr("JcJ public · Armurerie","Public PvP · Armory"),nil,nil,true)
        row(field(tr("Victoires honorables","Honorable kills"),valueOf(profile.honorableKills))
            .."\n"..field(tr("Rang JcJ","PvP rank"),valueOf(profile.pvpRank)))
        local stats=object(profile.stats)
        for _,key in ipairs(sortedKeys(stats)) do
            local v=stats[key]
            local val=valueOf(v)
            if type(v)=="table" and text(v[1]) and text(v[2]) then val=text(v[1]).." – "..text(v[2]) end
            row(field(statNames[key] or text(prettyKey(key)),val))
        end
        row(field(tr("Hauts faits JcJ","PvP achievements"),type(profile.achievements)=="table" and tostring(#profile.achievements)),nil,nil,true)
        if profile.achievementsAt then row(field(tr("Relevé","Snapshot"),timestamp(profile.achievementsAt))) end
        for _,achievement in ipairs(object(profile.achievements)) do
            local a=object(achievement)
            row((text(a.name) or unknown)..(a.accountWide and tr(" (compte)"," (account)") or ""),a.icon)
        end
        row(tr("Vos combats contre cette cible · Journal personnel","Your fights against this target · Personal journal"),nil,nil,true)
        if localRecord then
            local p=GL.ContactMatchup(record)
            row(field(tr("Victoires","Wins"),text(p.kills)).." · "..field(tr("Morts","Deaths"),text(p.deaths))
                .."\n"..field(tr("Honneur attribué","Attributed honor"),p.honorAwards>0 and text(p.honor)))
        else row(tr("Aucune rencontre personnelle enregistrée.","No personal encounters recorded.")) end
        row(tr("Combats transmis par la guilde","Fights shared by guild members"),nil,nil,true)
        if GL.Bounties and GL.Safe(GetGuildInfo,"player") then
            local wins,losses=GL.Bounties.GuildFights(f.guid)
            if wins==0 and losses==0 then row(tr("Aucun résultat partagé pour cette cible.","No shared results for this target."))
            else row(field(tr("Victoires","Wins"),text(wins)).." · "..field(tr("Morts","Deaths"),text(losses))) end
        else row(unknown) end
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
    f.nameLabel=UI.label(f,"","large",111,-198,183)
    f.identityScroll,f.identityBody=scrollArea(f,40,-271,241,315)
    f.identity=UI.label(f.identityBody,"",nil,0,0,237)
    f.bounty=UI.button(f,tr("Prime de ce joueur","Player bounty"),40,-612,247,function() GL.OpenContactBounty(f.guid) end)
    f.tabs={}; f.rows={}
    for i,s in ipairs({{"gear","Équipement","Equipment"},{"talents","Talents","Talents"},{"pvp","Statistiques JcJ","PvP statistics"}}) do
        local key=s[1]
        f.tabs[key]=UI.button(f,tr(s[2],s[3]),351+(i-1)*174,-156,167,function()
            f.page=key; f.scroll:SetVerticalScroll(0); draw(f)
        end,true,true)
    end
    f.source=UI.label(f,"",nil,355,-191,535); f.source:SetTextColor(unpack(UI.theme.inkMuted))
    f.scroll,f.body=scrollArea(f,352,-218,523,420)
    return f
end
function GL.OpenPlayerDossier(guid,onReturn,knownName)
    if type(guid)~="string" or #guid>32 or not guid:match("^Player%-%w+%-%w+$") then return false end
    frame=frame or build()
    frame.guid,frame.onReturn,frame.knownName,frame.page,frame.slot=guid,onReturn,knownName,"gear",nil
    frame.scroll:SetVerticalScroll(0); frame.identityScroll:SetVerticalScroll(0)
    draw(frame)
    GL.ShowBookPage(frame)
    return true
end
