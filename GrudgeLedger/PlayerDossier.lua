-- Character dossiers are read-only views over the personal journal and private Armory archive.
local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local L = GL.L
local locale = GetLocale and GetLocale() or "frFR"
local decimalComma = locale == "frFR" or locale == "esES"
local unknown = L("Non renseigné")
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
local function field(label, value) return L("%s : %s"):format(label, value or unknown) end
local slots = {
    {"head","Tête"}, {"neck","Cou"}, {"shoulder","Épaules"},
    {"back","Dos"}, {"chest","Torse"}, {"shirt","Chemise"},
    {"tabard","Tabard"}, {"wrist","Poignets"}, {"hand","Mains"},
    {"waist","Taille"}, {"leg","Jambes"}, {"foot","Pieds"},
    {"leftfinger","Anneau 1"}, {"rightfinger","Anneau 2"},
    {"lefttrinket","Bijou 1"}, {"righttrinket","Bijou 2"},
    {"weapon","Main droite"}, {"offhand","Main gauche"}, {"ranged","À distance"},
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
    ITEMLEVEL=L("Niveau d’objet"), MOVEMENTSPEED=L("Vitesse de déplacement"),
    HEALTH=L("Vie"), MANA=L("Mana"), ARMOR=L("Armure"),
    ATTACKPOWER=L("Puissance d’attaque"), SPELLPOWER=L("Puissance des sorts"),
    STRENGTH=L("Force"), AGILITY=L("Agilité"), STAMINA=L("Endurance"),
    INTELLECT=L("Intelligence"), CRITICALSTRIKE=L("Coup critique"),
    HASTE=L("Hâte"), MASTERY=L("Maîtrise"), BONUSARMOR=L("Armure supplémentaire"),
    VERSATILITY=L("Polyvalence"), AVOIDANCE=L("Évitement"),
    DAMAGE=L("Dégâts"), ATTACKSPEED=L("Vitesse d’attaque"),
    ATTACKDPS=L("Dégâts par seconde"), MANAREGEN=L("Régénération de mana"),
    ENERGY=L("Énergie"), RAGE=L("Rage"), FOCUS=L("Focalisation"),
    SPIRIT=L("Esprit"), RUNICPOWER=L("Puissance runique"),
    DODGE=L("Esquive"), PARRY=L("Parade"), BLOCK=L("Blocage"),
}
local function itemDetails(item)
    local lines = {}
    local function add(label, v)
        if v then lines[#lines+1] = field(label, v) end
    end
    add(L("Niveau d’objet"),valueOf(object(item.level).value) or valueOf(item.level))
    add(L("Qualité"),valueOf(item.quality))
    add(L("Armure"),valueOf(item.armor))
    for _,stat in ipairs(object(item.stats)) do
        local display = valueOf(object(stat).display)
        if display then lines[#lines+1] = display
        else
            local st=object(object(stat).type)
            add(statNames[st.type] or valueOf(st) or text(st.type) or L("Statistique"),valueOf(object(stat).value))
        end
    end
    local weapon=object(item.weapon)
    add(L("Dégâts"),valueOf(weapon.damage)); add(L("Vitesse"),valueOf(weapon.attack_speed))
    add("DPS",valueOf(weapon.dps))
    for _,e in ipairs(object(item.enchantments)) do
        add(L("Enchantement"),valueOf(e) or valueOf(object(e).source_item) or text(object(e).enchantment_id))
    end
    for _,s in ipairs(object(item.sockets)) do
        add(L("Châsse"),valueOf(object(s).item) or valueOf(object(s).socket_type) or valueOf(s))
    end
    for _,s in ipairs(object(item.spells)) do
        local name, desc = valueOf(object(s).spell), text(object(s).description) or valueOf(s)
        add(L("Effet"),name and desc and (name.." — "..desc) or desc or name)
    end
    local set=object(item.set)
    add(L("Ensemble"),valueOf(set.item_set) or valueOf(item.set))
    for _,effect in ipairs(object(set.effects)) do add(L("Effet d’ensemble"),valueOf(effect) or text(object(effect).description)) end
    for _,key in ipairs(sortedKeys(item.requirements)) do
        add(L("Requis"),valueOf(item.requirements[key]))
    end
    local bonus={}
    for _,id in ipairs(object(item.bonus_list)) do if text(id) then bonus[#bonus+1]=text(id) end end
    if #bonus>0 then add(L("Bonus de variante"),table.concat(bonus,", ")) end
    add(L("Identifiant d’objet"),text(item.id))
    return #lines>0 and table.concat(lines,"\n") or L("Détails de la pièce non publiés.")
end
local relationNames={friend=L("Ami"),warning=L("Méfiance"),enemy=L("Ennemi"),neutral=L("Neutre")}
local frame
-- Assigned below; the expandable facts and the page arrows redraw the sheet.
local draw,paginate,showPager
local function armoryURL(fullName)
    local region=GL.ArmoryRegion()
    if not region or type(fullName)~="string" or not fullName:find(" ",1,true) then return end
    local slug=(strlower or string.lower)(fullName):gsub(" +","-"):gsub("[^a-z0-9%-]",function(c)
        return ("%%%02X"):format(c:byte())
    end)
    local lang=locale=="frFR" and "fr-fr" or (locale=="esES" or locale=="esMX") and "es-es" or "en-us"
    return "https://worldofwarcraft.blizzard.com/"..lang.."/forever/"..region.."/armory/character/"..slug
end
local percentages={CRITICALSTRIKE=true,DODGE=true,PARRY=true,BLOCK=true,HASTE=true,VERSATILITY=true,AVOIDANCE=true}
local function statValue(key,v)
    local function number(n)
        local s=("%.1f"):format(n):gsub("[.,]0$","")
        return decimalComma and s:gsub("%.",",") or s
    end
    if type(v)=="number" then return number(v)..(percentages[key] and L(" %") or "") end
    if type(v)=="table" and tonumber(v[1]) and tonumber(v[2]) then return number(v[1]).." – "..number(v[2]) end
    return valueOf(v)
end
-- Which dossier field each tab shows, for its "source · observer · date" line.
local pageFields={gear="gear",talents="trees",combat="honorableKills"}
local function memberName(guid)
    return UI.plain(GL.Bounties.MemberName(guid) or L("Membre de guilde"))
end
-- Names who observed the tab's data and when: "Inspection de Megumin · 19/11/2026 22:12".
-- Our own observations read "Votre inspection"; a relayed snapshot also names the relay.
local function provenanceLabel(profile,page)
    local key=pageFields[page]
    local p=key and profile.provenance and profile.provenance[key]
    if key=="honorableKills" and not p then p=profile.provenance and (profile.provenance.pvpRank or profile.provenance.battlegrounds) end
    if not p or not p.at then return end
    local me=GL.Safe(UnitGUID,"player")
    local label
    if p.by==me then
        label=p.source=="armory" and L("Votre relevé Armurerie") or L("Votre inspection")
    elseif p.by then
        label=(p.source=="armory" and L("Relevé Armurerie de %s") or L("Inspection de %s")):format(memberName(p.by))
    else
        label=p.source=="armory" and L("Relevé Armurerie") or L("Inspection")
    end
    if p.via and p.via~=p.by and p.via~=me then label=label..L(", reçu de %s"):format(memberName(p.via)) end
    return label.." · "..timestamp(p.at)
end
-- The profile the dossier shows: the archive, overlaid by this session's inspection when it is newer.
local function resolve(f)
    local localRecord=GL.Get(f.key)
    local record=localRecord or {guid=f.guid}
    f.guid=record.guid
    local archive=object(GL.ArmoryProfile(record,localRecord~=nil))
    local profile=setmetatable({}, {__index=archive})
    local inspection,pending
    if GL.DossierInspection then
        inspection,pending=GL.DossierInspection(record)
    end
    inspection=object(inspection)
    local archivedAt=tonumber(archive.updated) or 0
    if archivedAt>=100000000000 then
        archivedAt=archivedAt/1000
    end
    if inspection.gear and (not archive.gear or inspection.gearAt>=(archive.gearAt or archivedAt)) then
        profile.inspectedGear,profile.partialGear=inspection.gear,inspection.partialGear
    end
    if inspection.trees and (not archive.trees or inspection.talentsAt>=(archive.treesAt or archivedAt)) then
        profile.trees=inspection.trees
    end
    local stats=object(profile.stats)
    local liveStats=inspection.stats and (not next(stats) or inspection.statsAt>=(archive.statsAt or archivedAt))
    if liveStats then
        local combined={}
        for key,v in pairs(stats) do
            combined[key]=v
        end
        for key,v in pairs(inspection.stats) do
            combined[key]=v
        end
        stats=combined
    end
    local itemLevel=profile.averageItemLevel
    if profile.inspectedGear then
        itemLevel=inspection.averageItemLevel or itemLevel
    end
    return {record=record,localRecord=localRecord,archive=archive,profile=profile,live=inspection,
        pending=pending,archivedAt=archivedAt,stats=stats,liveStats=liveStats,itemLevel=itemLevel}
end

-- Main specialization: the talent tree with the most points.
local function specName(trees)
    local best,most
    for _,tree in ipairs(object(trees)) do
        local points=type(tree)=="table" and tonumber(tree.points) or 0
        if points>0 and (not most or points>most) then
            best,most=text(tree.name),points
        end
    end
    return best
end
-- Levels only rise: keep the highest of what we saw in game and what the Armory says.
local function levelOf(d)
    local armory=d.profile.level
    if type(armory)=="table" then
        armory=tonumber(armory.value)
    end
    local seen,published=GL.ValidLevel(d.record.level),GL.ValidLevel(armory)
    if seen and published then
        return math.max(seen,published)
    end
    return seen or published
end
local function identityText(d)
    local record,public=d.record,object(d.profile.identity)
    local faction,race,class=GL.IdentityLabels(record)
    race=(record.race or record.raceName) and text(race) or text(public.race) or unknown
    class=(record.class or record.className) and text(class) or text(public.class) or unknown
    faction=record.faction and text(faction) or text(public.faction) or unknown
    local spec,level=specName(d.profile.trees),levelOf(d)
    local lines={(level and (L("Niv. %d"):format(level).." · ") or "")..class}
    if spec then
        lines[#lines+1]=spec
    end
    lines[#lines+1]=race.." · "..faction
    local guild=text(record.guild) or text(public.guild)
    if guild then
        lines[#lines+1]="<"..guild..">"
    end
    return table.concat(lines,"\n")
end
local function openBounty(guid)
    local B=GL.Bounties
    return guid and B and B.OpenFor and B.OpenFor(guid)
end
local function bountyAmount(order)
    return GL.BountyMoney and GL.BountyMoney(GL.BountyTotal(order)) or unknown
end
local Panels=GL.DossierPanels
-- "il y a 2 h": recent dates read as a distance; older ones as a date.
local function ago(at)
    at=tonumber(at)
    if not at then
        return nil
    end
    local delta=GL.Now()-at
    if delta<60 then
        return L("à l'instant")
    elseif delta<3600 then
        return L("il y a %d min"):format(math.floor(delta/60))
    elseif delta<86400 then
        return L("il y a %d h"):format(math.floor(delta/3600))
    elseif delta<30*86400 then
        return L("il y a %d j"):format(math.floor(delta/86400))
    end
    return GL.Safe(date,"%d/%m/%Y",at) or "?"
end
local function guildOpinion(guid)
    local reports=GL.SharedDossiers and guid and GL.SharedDossiers.SocialReports(guid) or {}
    local sum=0
    for _,report in ipairs(reports) do
        sum=sum+(tonumber(report.score) or 0)
    end
    local kind="neutral"
    if #reports>0 then
        kind=sum<=-10 and "enemy" or sum<0 and "warning" or sum>=10 and "friend" or "neutral"
    end
    return sum,#reports,kind
end
local positiveTags={reliable=true}
-- Labelled rows, "Vous", "Guilde", "Prime", then each tag: {text, kind, row label, tooltip}.
local function verdictItems(d,guid)
    local record,items=d.localRecord,{}
    if record then
        local relation=GL.RelationSource(record)=="guildmates" and "neutral" or GL.Relation(record)
        local formula=GL.BalanceFormula(record)
        local nemesisKey,companionKey=GL.Titles()
        local name=record.key==nemesisKey and L("Némésis") or record.key==companionKey and L("Compagnon") or relationNames[relation] or unknown
        items[1]={name.." · "..("%+d"):format(record.reputation or 0),relation,L("Vous"),
            formula~="" and (L("Votre solde : %s"):format(formula)) or nil}
    else
        items[1]={L("Aucune rencontre"),"neutral",L("Vous")}
    end
    local sum,count,kind=guildOpinion(guid)
    if count>0 then
        items[2]={relationNames[kind].." · "..("%+d"):format(sum),kind,L("Guilde"),L("%d avis"):format(count)}
    else
        items[2]={L("Aucun avis"),"neutral",L("Guilde")}
    end
    local order=openBounty(guid)
    if order then
        items[#items+1]={bountyAmount(order),"outline",L("Prime"),L("Prime ouverte · %s"):format(bountyAmount(order))}
    end
    for _,choice in ipairs(GL.TagChoices or {}) do
        if record and GL.HasTag and GL.HasTag(record,choice[1]) then
            items[#items+1]={L(choice[2]),positiveTags[choice[1]] and "friend" or "enemy"}
        end
    end
    return items
end
local combatKinds={kill=true,death=true,aggression=true}
-- Whole fights, newest first: an aggression and the death it caused are one entry.
local function fights(record)
    return record and GL.Fights(record) or {}
end
local function fightText(fight)
    local e=fight.main
    local combat=object(e.combat)
    local line=GL.FightTitle(fight)..(text(e.zone) and e.zone~="?" and (" · "..text(e.zone)) or "")
    local his,mine=GL.ValidLevel(combat.opponentLevel),GL.ValidLevel(combat.playerLevel)
    if his or mine then
        line=line.."\n"..L("Niveaux : lui %s · vous %s"):format(his or "?",mine or "?")
    end
    return line
end
-- A player of your own faction you never fought: met in groups, trades and tags.
local function allyVariant(d)
    local faction=d.record.faction or object(d.profile.identity).faction
    return type(faction)=="string" and faction==GL.Safe(UnitFactionGroup,"player") and #fights(d.localRecord)==0
end
-- Groups, trades and members who tagged this player, for the same-faction variant.
local function encounters(d,guid)
    local result={groups=0,groupTime=0,trades=0,taggers=0,events={}}
    for _,e in ipairs(object(d.localRecord and d.localRecord.history)) do
        if type(e)=="table" and not e.voided and (e.kind=="grouped" or e.kind=="group") then
            result.groups=result.groups+1
            result.groupTime=result.groupTime+(GL.GroupDuration and GL.GroupDuration(e) or 0)
            result.events[#result.events+1]=e
        elseif type(e)=="table" and not e.voided and e.kind=="trade" then
            result.trades=result.trades+1
            result.lastTrade=math.max(result.lastTrade or 0,e.time or 0)
            result.events[#result.events+1]=e
        end
    end
    local G,me=GL.GuildProfiles,GL.Safe(UnitGUID,"player")
    local card=G and guid and G.ForTarget(guid)
    local seen={}
    for _,e in ipairs(card and G.View(card) or {}) do
        if e.on and e.actor~=me and not seen[e.actor] then
            seen[e.actor]=true
            result.taggers=result.taggers+1
        end
    end
    table.sort(result.events,function(a,b) return (a.time or 0)>(b.time or 0) end)
    return result
end
local powers={"MANA","ENERGY","RAGE","FOCUS","RUNICPOWER"}
-- The three statistics that matter for each class; a feral druid reads like a rogue.
local classStats={
    WARRIOR={"STRENGTH","ARMOR","CRITICALSTRIKE"}, ROGUE={"AGILITY","CRITICALSTRIKE","STAMINA"},
    HUNTER={"AGILITY","CRITICALSTRIKE","STAMINA"}, MAGE={"INTELLECT","CRITICALSTRIKE","STAMINA"},
    WARLOCK={"INTELLECT","CRITICALSTRIKE","STAMINA"}, PRIEST={"INTELLECT","SPIRIT","CRITICALSTRIKE"},
    PALADIN={"STRENGTH","INTELLECT","ARMOR"}, SHAMAN={"INTELLECT","AGILITY","CRITICALSTRIKE"},
    DRUID={"INTELLECT","SPIRIT","CRITICALSTRIKE"}, FERAL={"AGILITY","ARMOR","CRITICALSTRIKE"},
}
local function classToken(d)
    local token=text(object(d.profile.identity).classFile) or text(d.record.class)
    token=token and token:upper()
    if token=="DRUID" then
        -- Feral Combat is the second tree; its name also tells it when the order is unknown.
        local trees,best,most,name=object(d.profile.trees),nil,0,""
        for i,tree in ipairs(trees) do
            local points=type(tree)=="table" and tonumber(tree.points) or 0
            if points>most then
                best,most,name=i,points,(text(tree.name) or ""):lower()
            end
        end
        if best==2 or name:find("farouche",1,true) or name:find("feral",1,true) then
            return "FERAL","DRUID"
        end
    end
    return token,token
end
-- Seven lines: health, power, item level, the three statistics of the class, then honorable
-- kills, or for the same-faction variant groups, trades and reports.
local classPower={ROGUE="ENERGY",WARRIOR="RAGE",FERAL="ENERGY"}
local function keyFigures(d,ally,met)
    local token=classToken(d)
    local stats,power=d.stats,classPower[token] or "MANA"
    for i=#powers,1,-1 do
        if stats[powers[i]] then
            power=powers[i]
        end
    end
    local chosen=classStats[token]
    if not chosen then
        local main,best="AGILITY",-1
        for _,key in ipairs({"STRENGTH","AGILITY","INTELLECT"}) do
            local value=tonumber(stats[key])
            if value and value>best then
                main,best=key,value
            end
        end
        chosen={main,"STAMINA","CRITICALSTRIKE"}
    end
    local figures={
        {statValue("HEALTH",stats.HEALTH),statNames.HEALTH},
        {statValue(power,stats[power]),statNames[power]},
        {valueOf(d.itemLevel),L("Niv. objet")},
    }
    for _,key in ipairs(chosen) do
        figures[#figures+1]={statValue(key,stats[key]),key=="CRITICALSTRIKE" and L("Critique") or statNames[key]}
    end
    if ally then
        figures[5]={tostring(met.groups),L("Groupes")}
        figures[6]={tostring(met.trades),L("Échanges")}
        figures[7]={tostring(met.taggers),L("Signalements")}
    else
        figures[7]={valueOf(d.profile.honorableKills),L("Vict. honorables")}
    end
    return figures
end
local function seenText(d,unread)
    local record,lines=d.record,{}
    local at=record.lastSeen or record.lastEncounterAt
    if at then
        local zone=text(record.lastZone) or text(record.lastEncounterZone)
        lines[1]=L("Vu %s"):format(ago(at))..(zone and (" · "..zone) or "")
    else
        lines[1]=L("Pas encore croisé")
    end
    local readings={}
    local inspectedAt=d.live.gearAt or d.live.statsAt or d.live.talentsAt
    if inspectedAt then
        readings[#readings+1]=L("inspection du %s"):format(GL.Safe(date,"%d/%m",inspectedAt) or "?")
    end
    if d.archivedAt>0 then
        readings[#readings+1]=L("Armurerie du %s"):format(GL.Safe(date,"%d/%m",math.floor(d.archivedAt)) or "?")
    end
    lines[#lines+1]=#readings>0 and L("Relevés : %s"):format(table.concat(readings," · "))
        or unread and L("Aucun relevé : ciblez-le à moins de 30 m, la lecture se fait seule") or L("Aucun relevé chargé")
    return table.concat(lines,"\n")
end
local COLUMN=166
local function keyCell(f,i)
    local c=f.statCells[i]
    if c then
        return c
    end
    c=CreateFrame("Frame",nil,f.identityBody)
    c:SetSize(COLUMN,18)
    c.label=UI.label(c,"",nil,0,-2,104)
    UI.journalFont(c.label,"GameFontHighlight",11)
    c.label:SetTextColor(unpack(UI.theme.brass))
    c.value=UI.label(c,"",nil,COLUMN-64,0,64)
    UI.journalFont(c.value,"GameFontNormalLarge",13)
    c.value:SetJustifyH("RIGHT")
    c.rule=c:CreateTexture(nil,"BACKGROUND")
    c.rule:SetPoint("BOTTOMLEFT")
    c.rule:SetSize(COLUMN,1)
    c.rule:SetColorTexture(.55,.40,.20,.30)
    f.statCells[i]=c
    return c
end
-- The identity column is the same on every tab: who, the verdict, six key figures, when last seen.
local function drawIdentity(f,d)
    local record=d.record
    local name=text(record.fullName) or text(object(d.profile.identity).name) or text(f.knownName)
    if not name and f.guid and GL.Bounties and GL.Bounties.MemberName then
        name=text(GL.Bounties.MemberName(f.guid))
    end
    Panels.Fit(f.nameLabel,name or unknown,100,18,12,true)
    GL.PaintBookPortrait(f.portrait,record)
    -- The studio bust, when the Avatar Replay Lab has photographed this player.
    local photos=GL.StudioPhotos and GL.StudioPhotos(f.guid)
    if photos then
        f.portrait.photo:SetTexture(photos.bust)
        f.portrait.photo:Show()
        f.portrait.raceIcon:Hide()
    else
        f.portrait.photo:Hide()
        f.portrait.raceIcon:Show()
    end
    f.identity:SetText(identityText(d))
    local mode=GL.ContactBountyMode(record)
    f.bounty:SetText(mode=="view" and L("Voir la prime") or L("Créer une prime"))
    if mode then
        f.bounty:Show()
    else
        f.bounty:Hide()
    end
    local ally=allyVariant(d)
    local met=encounters(d,f.guid)
    local sameFaction=(d.record.faction or object(d.profile.identity).faction)==GL.Safe(UnitFactionGroup,"player")
    f.contactName=sameFaction and not mode and name or nil
    f.whisper:SetShown(f.contactName~=nil)
    f.invite:SetShown(f.contactName~=nil)
    local y=0
    local function place(region,height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT",0,-y)
        y=y+height
    end
    f.verdictHeading:Hide()
    -- One labelled row each for you, the guild and an open bounty; the tags flow after.
    -- The calculation behind your balance is the tooltip of your pill.
    local items=verdictItems(d,f.guid)
    for _,pill in ipairs(f.pills) do
        pill:Hide()
        pill.note:Hide()
    end
    local x=0
    for i,item in ipairs(items) do
        local pill=f.pills[i] or Panels.Pill(f.identityBody)
        if not f.pills[i] then
            pill.note=Panels.Text(f.identityBody,0,0,46,11,false,UI.theme.brass)
            GL.Safe(pill.note.SetMaxLines,pill.note,1)
            GL.Safe(pill.EnableMouse,pill,true)
            pill:SetScript("OnEnter",function(self)
                if self.tip and GameTooltip then
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                    GameTooltip:SetText(self.tip,1,1,1,1,true)
                    GameTooltip:Show()
                end
            end)
            pill:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
            f.pills[i]=pill
        end
        pill.tip=item[4]
        pill:Set(item[1],item[2])
        pill:ClearAllPoints()
        if item[3] then
            if x>0 then
                y=y+26
                x=0
            end
            pill:SetPoint("TOPLEFT",48,-y)
            pill.note:ClearAllPoints()
            pill.note:SetPoint("TOPLEFT",0,-y-4)
            pill.note:SetText(item[3])
            pill.note:Show()
            y=y+25
        else
            if x+pill:GetWidth()>COLUMN then
                y=y+26
                x=0
            end
            pill:SetPoint("TOPLEFT",x,-y)
            x=x+pill:GetWidth()+6
        end
    end
    if x>0 then
        y=y+26
    end
    y=y+4
    local figures=keyFigures(d,ally,met)
    -- The column lists only what was read: a dash says nothing, and when nothing was read at all,
    -- one sentence on how the reading happens says more than seven dashes.
    local known={}
    for _,figure in ipairs(figures) do
        if figure[1] then
            known[#known+1]=figure
        end
    end
    figures=known
    local unread=#figures==0
    f.keyHeading:SetText(unread and "" or L("Chiffres clés"))
    if not unread then
        place(f.keyHeading,18)
    end
    for i,figure in ipairs(figures) do
        local c=keyCell(f,i)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT",0,-(y+(i-1)*18))
        c.value:SetText(figure[1] or "—")
        c.value:SetTextColor(unpack(figure[1] and UI.theme.paper or UI.theme.muted))
        c.label:SetText(figure[2])
        c:Show()
    end
    for i=#figures+1,#f.statCells do
        f.statCells[i]:Hide()
    end
    y=y+#figures*18+8
    f.observed:SetText(seenText(d,unread))
    place(f.observed,f.observed:GetStringHeight()+8)
end

local function fightLine(e)
    local combat=object(e.combat)
    local line=GL.HistoryTitle(e)..(text(e.zone) and e.zone~="?" and (" · "..text(e.zone)) or "")
    local his,mine=GL.ValidLevel(combat.opponentLevel),GL.ValidLevel(combat.playerLevel)
    if his or mine then
        line=line.."\n"..L("Niveaux : lui %s · vous %s"):format(his or "?",mine or "?")
    end
    return line
end
local function score(wins,losses)
    return wins..L(" V").." / "..losses..L(" D")
end
local function inGuild(f)
    return f.guid and GL.Bounties and GL.Safe(GetGuildInfo,"player")
end
local function bountyDossier(guid)
    local B=GL.Bounties
    return B and B.TargetRecord and B.TargetRecord(guid) or {orders={},count=0}
end
local function gold(copper)
    return GL.BountyMoney and GL.BountyMoney(copper or 0) or tostring(math.floor((copper or 0)/10000))
end
-- "Mis à prix 4 fois · 140 PO promis", then "Tué 3 fois · 1 expirée · contrats honorés 3/3".
local function bountySummary(r)
    local first=L("Mis à prix %d fois · %s promis"):format(r.count,gold(r.promised))
    local second=L("Tué %d fois"):format(r.killed)
    if r.expired>0 then
        second=second.." · "..(r.expired==1 and L("%d expirée") or L("%d expirées")):format(r.expired)
    end
    if r.withdrawn>0 then
        second=second.." · "..(r.withdrawn==1 and L("%d retirée") or L("%d retirées")):format(r.withdrawn)
    end
    if r.completed>0 then
        second=second.." · "..L("contrats honorés %d/%d"):format(r.honored,r.completed)
    end
    return first.."\n"..second
end
local bountyStates={open=L("ouverte"),claimed=L("réclamée, en attente de validation"),fulfilled=L("paiement en attente"),
    sent=L("payée, réception à confirmer"),paid=L("payée"),withdrawn=L("retirée"),expired=L("expirée sans victoire")}
local function delay(seconds)
    local hours=math.max(0,math.floor(seconds/3600))
    if hours<48 then
        return L("%d h"):format(hours)
    end
    return L("%d j"):format(math.floor(hours/24))
end
-- "18/11/2026 · 60 PO · remplie par Kazuma (+1) en 2 h · payée"
local function bountyLine(e)
    local line=timestamp(e.at).." · "..gold(e.pot)
    if e.hunter then
        local helpers=0
        for _ in (e.helpers or ""):gmatch("[^,]+") do
            helpers=helpers+1
        end
        local name=UI.plain(GL.Bounties.MemberName(e.hunter) or L("Membre de guilde"))
        line=line.." · "..L("remplie par %s"):format(name..(helpers>0 and (" (+"..helpers..")") or ""))
        line=line.." "..L("en %s"):format(delay((e.killedAt or e.at)-e.at))
    end
    return line.." · "..(bountyStates[e.state] or unknown)
end
-- "Ce que chacun en pense": you first, then each member with a relation pill and their fights.
local function memberRows(f,row,record)
    local B,S=GL.Bounties,GL.SharedDossiers
    local members,me={},GL.Safe(UnitGUID,"player")
    local function member(id)
        members[id]=members[id] or {id=id}
        return members[id]
    end
    for _,report in ipairs(S and S.SocialReports(f.guid) or {}) do
        local m=member(report.actor)
        m.score,m.relation,m.name=report.score,report.relation,report.authorName
    end
    local scope=inGuild(f) and B.GuildScope()
    for id,fights in pairs(scope and scope.scores and scope.scores[f.guid] or {}) do
        member(id).fights=fights
    end
    members[me]=nil
    if record then
        local p=GL.ContactMatchup(record)
        local relation=GL.RelationSource(record)=="guildmates" and "neutral" or GL.Relation(record)
        local mine=(relationNames[relation] or unknown).." · "..("%+d"):format(record.reputation or 0)
        row(L("Vous"),score(p.kills,p.deaths),nil,nil,nil,{pill={mine,relation}})
    else
        row(L("Vous"),nil,nil,nil,nil,{pill={L("Aucune rencontre"),"neutral"}})
    end
    local list={}
    for _,m in pairs(members) do
        m.label=UI.plain(B and B.MemberName(m.id) or m.name or L("Membre de guilde"))
        list[#list+1]=m
    end
    table.sort(list,function(a,b)
        if (a.score or math.huge)~=(b.score or math.huge) then
            return (a.score or math.huge)<(b.score or math.huge)
        end
        return a.label<b.label
    end)
    for _,m in ipairs(list) do
        local pill=m.score and {(relationNames[m.relation] or unknown).." · "..("%+d"):format(m.score),m.relation} or {L("Sans avis"),"neutral"}
        row(m.label,m.fights and score(m.fights[1],m.fights[2]) or "",nil,nil,nil,{pill=pill})
    end
    local sum,count,kind=guildOpinion(f.guid)
    if count>0 then
        row(L("Total de la guilde"),L("%d avis"):format(count),nil,nil,nil,{pill={relationNames[kind].." · "..("%+d"):format(sum),kind}})
    elseif #list==0 then
        row(L("Aucun historique ni solde partagé par les autres membres."))
    end
end
local filters={{"mine","Moi",58},{"guild","Guilde",92},{"all","Tout",58}}
local function firstName(name)
    return (tostring(name or ""):match("^(%S+)") or name)
end
local function dayLabel(at)
    local key=GL.CharacterInsights and GL.CharacterInsights.DayKey
    if key and key(at)==key(GL.Now()) then
        return L("Aujourd’hui")
    elseif key and key(at)==key(GL.Now()-86400) then
        return L("Hier")
    end
    return GL.Safe(date,"%d/%m/%Y",at) or "?"
end
local function relationsPage(f,record,row)
    local B,G,S=GL.Bounties,GL.GuildProfiles,GL.SharedDossiers
    local me,filter=GL.Safe(UnitGUID,"player"),f.relationFilter or "all"
    local timeline={}
    local function add(at,description,author,mine,event)
        if filter=="all" or (filter=="mine")==(mine==true) then
            timeline[#timeline+1]={at=tonumber(at) or 0,description=description,author=mine and L("Vous") or firstName(author),
                mine=mine,seq=#timeline+1,event=event}
        end
    end
    local story=GL.CharacterInsights and record and GL.CharacterInsights.Story(record) or {}
    if #story>0 then
        local name=f.nameLabel:GetText() or ""
        row(L("Votre histoire avec lui"),L("Copier"),true,function()
            GL.DeathReport.ShowText(L("Votre histoire avec %s"):format(name),name.."\n"..table.concat(story,"\n"))
        end)
        for _,line in ipairs(story) do
            row(line)
        end
    end
    row(L("Ce que chacun en pense"),L("Avis · contre lui"),true)
    memberRows(f,row,record)
    -- Audit 0.12.0, problem 11: only this record's events, not the whole journal sorted.
    for _,fight in ipairs(fights(record)) do
        local zone=text(fight.main.zone) and fight.main.zone~="?" and (" · "..UI.plain(fight.main.zone)) or ""
        add(fight.at,GL.FightTitle(fight)..zone,nil,true,fight.main)
    end
    for _,item in ipairs(record and GL.RecordEvents(record) or {}) do
        local e=item.event
        local description=GL.HistoryTitle(e)
        if e.text then
            description=description.."\n"..UI.plain(e.text)
        end
        if e.zone and e.zone~="?" then
            description=description.." · "..UI.plain(e.zone)
        end
        if e.voided then
            description=description.." · "..L("Annulé · exclu")
        end
        -- Active fight events are shown above, one line per fight.
        if e.voided or e.voidReason=="battleground" or not combatKinds[e.kind] then
            add(e.time,description,nil,true,e)
        end
    end
    for _,report in ipairs(S and S.SocialReports(f.guid) or {}) do
        local author=UI.plain(B.MemberName(report.actor) or report.authorName or L("Membre de guilde"))
        for _,e in ipairs(report.events) do
            local title=GL.HistoryTitle(e,author,f.nameLabel:GetText())..(e.zone and (" · "..UI.plain(e.zone)) or "")
            add(e.time,title,author,report.actor==me)
        end
    end
    local seen,tagNames={},{}
    for _,choice in ipairs(G and G.choices or {}) do
        tagNames[choice[1]]=L(choice[2])
    end
    for _,card in ipairs(G and G.List() or {}) do
        if card.target==f.guid then
            for _,e in ipairs(G.View(card)) do
                local key=e.actor..":"..e.seq
                if not seen[key] then
                    seen[key]=true
                    local change=(e.on and L("Étiquette ajoutée : ") or L("Étiquette retirée : "))..(tagNames[e.tag] or unknown)
                    add(e.time,change,UI.plain(e.authorName),e.actor==me)
                end
            end
        end
    end
    for _,order in ipairs(bountyDossier(f.guid).orders) do
        local author=UI.plain(B.MemberName(order.owner) or L("Membre de guilde"))
        add(order.at,L("Mise à prix créée"),author,order.owner==me)
        if order.endedAt then
            add(order.endedAt,L("Fin de la mise à prix"),author,order.owner==me)
        end
    end
    table.sort(timeline,function(a,b)
        if a.at~=b.at then
            return a.at>b.at
        end
        return a.seq>b.seq
    end)
    row(L("Chronologie"),nil,true)
    if #timeline==0 then
        row(L("Aucune interaction datée disponible."))
    end
    -- Grouped by day; each line names its author in a small chip instead of repeating it in text.
    local lastDay
    for _,entry in ipairs(timeline) do
        local day=dayLabel(entry.at)
        if day~=lastDay then
            lastDay=day
            row(day,nil,nil,nil,nil,{small=true})
        end
        local e=entry.event
        local open=e and combatKinds[e.kind] and function() GL.InspectEvent(record,e) end
        row(entry.description,open and L("Détail") or nil,nil,open,nil,{time=GL.Safe(date,"%H:%M",entry.at),chip={entry.author,entry.mine}})
    end
    row(L("Les témoignages restent signés ; ils ne changent pas votre avis."),nil,nil,nil,nil,{small=true})
end
local MAX_FACTS=10
local function factRow(record,row,fact)
    local e=fact.event
    if not e then
        local zone=text(fact.zone)
        row(timestamp(fact.at).." · "..L("Vu à proximité")..(zone and (" · "..zone) or ""),nil,nil,nil,true)
        return
    end
    local zone=text(e.zone) and e.zone~="?" and (" · "..text(e.zone)) or ""
    local open=combatKinds[e.kind] and function() GL.InspectEvent(record,e) end
    row(timestamp(fact.at).." · "..GL.HistoryTitle(e)..zone,open and L("Détail") or nil,nil,open,true)
end
-- Dated facts only, no score: each sentence opens the events that justify it.
local function insightsSection(f,d,row)
    local I=GL.CharacterInsights
    local list=I and d.localRecord and I.Facts(d.localRecord,f.guid) or {}
    row(L("À savoir"),nil,true)
    if #list==0 then
        row(L("Pas encore assez de faits datés pour en tirer des habitudes."))
        return
    end
    for _,item in ipairs(list) do
        local open=f.expanded[item.key]
        row(item.text,open and L("Masquer") or L("Faits (%d)"):format(#item.facts),nil,function()
            f.expanded[item.key]=not f.expanded[item.key]
            draw(f)
        end)
        if open then
            for i=1,math.min(MAX_FACTS,#item.facts) do
                factRow(d.localRecord,row,item.facts[i])
            end
            if #item.facts>MAX_FACTS then
                row(L("… et %d autres"):format(#item.facts-MAX_FACTS),nil,nil,nil,true)
            end
        end
    end
end
local dayNames={"Lun","Mar","Mer","Jeu","Ven","Sam","Dim"}
local fullDays={"Lundi","Mardi","Mercredi","Jeudi","Vendredi","Samedi","Dimanche"}
local monthNames={"janv.","févr.","mars","avr.","mai","juin","juil.","août","sept.","oct.","nov.","déc."}
-- Four levels instead of a shade relative to the busiest cell: a player met every Friday
-- evening no longer turns the whole grid pale. 1, 2, 3 to 4, 5 and more.
local LEVELS={1,2,3,5}
local function level(n)
    local result=0
    for i,threshold in ipairs(LEVELS) do
        if n>=threshold then
            result=i
        end
    end
    return result
end
local function paintLevel(texture,n)
    local l=level(n)
    if l==0 then
        texture:SetColorTexture(.45,.28,.11,.10)
    else
        texture:SetColorTexture(.55,.08,.05,({.3,.5,.75,1})[l])
    end
end
local function sightings(n)
    if n==0 then
        return L("Pas vu")
    end
    return n==1 and L("1 apparition") or L("%d apparitions"):format(n)
end
local function showTip(self)
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    GameTooltip:SetText(self.title)
    GameTooltip:AddLine(sightings(self.count),1,1,1)
    GameTooltip:Show()
end
local function hideTip()
    GameTooltip:Hide()
end
local function gridCell(parent,w,h)
    local cell=CreateFrame("Button",nil,parent)
    cell:SetSize(w,h)
    cell.fill=cell:CreateTexture(nil,"ARTWORK")
    cell.fill:SetAllPoints()
    cell:SetScript("OnEnter",showTip)
    cell:SetScript("OnLeave",hideTip)
    cell.count=0
    return cell
end
local function smallLabel(parent,value,x,y,w)
    local label=UI.label(parent,value,nil,x,y,w)
    UI.journalFont(label,"GameFontHighlight",10)
    label:SetTextColor(unpack(UI.theme.inkMuted))
    return label
end
-- Legend under a grid: "1  2  3-4  5+" with their colours.
local function legend(parent,y)
    local x=36
    smallLabel(parent,L("Apparitions :"),0,y,80)
    x=x+50
    for i,value in ipairs({"1","2","3-4","5+"}) do
        local swatch=parent:CreateTexture(nil,"ARTWORK")
        swatch:SetSize(10,10)
        swatch:SetPoint("TOPLEFT",x,y-1)
        paintLevel(swatch,LEVELS[i])
        smallLabel(parent,value,x+13,y,30)
        x=x+46
    end
end
local function heatmap(parent)
    local m=CreateFrame("Frame",nil,parent)
    m:SetSize(640,7*14+36)
    m.cells={}
    for day=1,7 do
        smallLabel(m,L(dayNames[day]),0,-(day-1)*14,32)
        for hour=0,23 do
            local cell=gridCell(m,22,12)
            cell:SetPoint("TOPLEFT",36+hour*25,-(day-1)*14-1)
            cell.title=L("%s, de %d h à %d h"):format(L(fullDays[day]),hour,(hour+1)%24)
            m.cells[(day-1)*24+hour]=cell
        end
    end
    for _,hour in ipairs({0,6,12,18,23}) do
        smallLabel(m,L("%d h"):format(hour),34+hour*25,-7*14-3,40)
    end
    legend(m,-7*14-19)
    m:Hide()
    return m
end
local function paintHeatmap(m,presence)
    for key,cell in pairs(m.cells) do
        cell.count=presence.grid[key] or 0
        paintLevel(cell.fill,cell.count)
    end
end
-- Weekly squares for the twelve-month strip, oldest first, from per-day sightings.
local function weeks(presence)
    local now=GL.Now()
    local out={}
    local dayKey=GL.CharacterInsights and GL.CharacterInsights.DayKey or function(at) return math.floor(at/86400) end
    for i=1,52 do
        local count,first,last=0,nil,nil
        for back=0,6 do
            local daysAgo=(52-i)*7+back
            local at=now-daysAgo*86400
            count=count+(presence.days[dayKey(at)] or 0)
            first=at
            last=last or at
        end
        local t=GL.Safe(date,"*t",first)
        out[i]={count=count,title=(GL.Safe(date,"%d/%m",first) or "?").." – "..(GL.Safe(date,"%d/%m",last) or "?"),
            detail=sightings(count),month=type(t)=="table" and t.month or nil,
            monthName=type(t)=="table" and t.month and L(monthNames[t.month]) or nil}
    end
    return out
end
-- How the last death happened, from the combat log alone: nothing to read on the player and
-- nothing to wait for. His heaviest spells first, then the total, the length and the killing blow.
local function deathRecap(record,fight)
    local event,D=fight and fight.main,GL.DeathReport
    if not event or event.kind~="death" or not D then
        return nil
    end
    local analysis=D.Analyse(event,record.guid,function() return "" end)
    local his
    for _,source in ipairs(analysis.sources) do
        if source.opponent then
            his=source
        end
    end
    if not his then
        return nil
    end
    local hits={}
    for i=1,math.min(4,#his.spellList) do
        hits[i]=UI.plain(his.spellList[i].name).." "..his.spellList[i].amount
    end
    local sums={L("%d dégâts en %d s"):format(his.total,math.max(1,analysis.duration or 1))}
    if analysis.fatal and analysis.fatal.opponent then
        sums[#sums+1]=L("coup fatal : %s"):format(UI.plain(analysis.fatal.spell))
    end
    local others=#analysis.sources-1
    if others>0 then
        sums[#sums+1]=others==1 and L("1 autre source de dégâts") or L("%d autres sources de dégâts"):format(others)
    end
    return table.concat(hits," · ").."\n"..table.concat(sums," · ")
end
local function buildOverview(f)
    local o=CreateFrame("Frame",nil,f)
    o:SetPoint("TOPLEFT",232,-197)
    o:SetSize(640,408)
    o.tiles={}
    for i=1,4 do
        local tile=Panels.Tile(o,154,82)
        tile:SetPoint("TOPLEFT",(i-1)*162,0)
        o.tiles[i]=tile
    end
    o.bar=Panels.Bar(o.tiles[1],134)
    o.bar:SetPoint("TOPLEFT",10,-56)
    o.factsTitle=Panels.Text(o,0,-96,300,16,true,UI.theme.red)
    o.factsLink=Panels.Link(o,440,-98,200,function()
        f.factsMode,f.pageNumber=true,1
        draw(f)
    end)
    o.cards={}
    for i=1,6 do
        local card=Panels.FactCard(o,208,54)
        card:SetPoint("TOPLEFT",((i-1)%3)*216,-120-math.floor((i-1)/3)*62)
        card:SetScript("OnClick",function(self)
            f.factsMode,f.pageNumber=true,1
            f.expanded[self.key]=true
            draw(f)
        end)
        o.cards[i]=card
    end
    o.noFacts=Panels.Text(o,0,-126,640,13,false,UI.theme.inkMuted)
    o.recapTitle=Panels.Text(o,0,-186,640,14,true,UI.theme.red)
    o.recap=Panels.Text(o,0,-206,640,12)
    o.presenceTitle=Panels.Text(o,0,-254,300,16,true,UI.theme.red)
    o.presenceLink=Panels.Link(o,440,-256,200,function()
        f.page,f.pageNumber="habits",1
        draw(f)
    end)
    o.strip=Panels.YearStrip(o,640)
    o.strip:SetPoint("TOPLEFT",0,-276)
    o.rule=o:CreateTexture(nil,"BACKGROUND")
    o.rule:SetPoint("TOPLEFT",0,-326)
    o.rule:SetSize(640,1)
    o.rule:SetColorTexture(.45,.28,.11,.35)
    o.lastCaption=Panels.Text(o,0,-338,110,11,false,UI.theme.inkMuted)
    o.lastText=Panels.Text(o,110,-336,450,12)
    o.lastLink=Panels.Link(o,570,-336,70,nil)
    o:Hide()
    return o
end
local function setTile(tile,caption,value,detail,small)
    tile.caption:SetText(caption)
    UI.journalFont(tile.value,"GameFontNormalLarge",small and 12 or 17)
    tile.value:SetText(value or "—")
    tile.detail:SetText(detail or "")
end
local function lastSightings(d,guid)
    local record=d.localRecord
    local mine=record and (record.lastEncounterAt or record.lastSeen)
    local guild=GL.SharedDossiers and guid and GL.SharedDossiers.GuildSighting(guid)
    local you=mine and L("Vous : %s"):format(ago(mine)) or L("Vous : jamais")
    local others=guild and L("Guilde : %s, %s"):format(ago(guild.at),UI.plain(guild.name or L("Membre de guilde"))) or L("Guilde : jamais")
    return you,others
end
-- The overview fits one page: four tiles, four facts, the year strip and the latest event.
local function paintOverview(f,d)
    local o,record=f.overview,d.localRecord
    local ally=allyVariant(d)
    local you,others=lastSightings(d,f.guid)
    if ally then
        local met=encounters(d,f.guid)
        local hours=math.floor(met.groupTime/3600)
        local together=met.groupTime>0 and L("%d h %02d au total"):format(hours,math.floor(met.groupTime/60)%60)
        setTile(o.tiles[1],L("En groupe avec vous"),L("%d fois"):format(met.groups),together)
        setTile(o.tiles[2],L("Signalé par"),L("%d membres"):format(met.taggers),record and GL.HasTag and GL.HasTag(record) and L("et vous") or nil)
        setTile(o.tiles[4],L("Échanges"),tostring(met.trades),met.lastTrade and L("le dernier le %s"):format(GL.Safe(date,"%d/%m",met.lastTrade) or "?"))
        o.bar:Hide()
    else
        local p=record and GL.ContactMatchup(d.record) or {kills=0,deaths=0}
        setTile(o.tiles[1],L("Vous contre lui"),score(p.kills,p.deaths))
        o.bar:Set(p.kills,p.deaths)
        o.bar:Show()
        local wins,losses,members=0,0,0
        if inGuild(f) then
            wins,losses=GL.Bounties.GuildFights(f.guid)
            local scope=GL.Bounties.GuildScope()
            local me=GL.Safe(UnitGUID,"player")
            for member in pairs(scope and scope.scores and scope.scores[f.guid] or {}) do
                if member~=me then
                    members=members+1
                end
            end
        end
        setTile(o.tiles[2],L("La guilde"),score(wins,losses),L("%d membres"):format(members))
        local order,dossier=openBounty(f.guid),bountyDossier(f.guid)
        local value=order and L("Ouverte · %s"):format(bountyAmount(order))
            or dossier.count>0 and L("%d posées · %d remplies"):format(dossier.count,dossier.completed or 0) or L("Aucune")
        setTile(o.tiles[4],L("Primes"),value,dossier.count>0 and L("%s promis"):format(gold(dossier.promised)),true)
    end
    setTile(o.tiles[3],L("Dernière rencontre"),you,others,true)
    -- Four facts in large type; the full list with its dated events is one click away.
    local I=GL.CharacterInsights
    local list=I and record and I.Facts(record,f.guid) or {}
    o.factsTitle:SetText(L("À savoir"))
    o.factsLink:SetText(L("Tous les faits (%d)"):format(#list))
    o.factsLink:SetShown(#list>0)
    local story=I and record and I.Story(record) or {}
    o.noFacts:SetText(#story>0 and table.concat(story,"\n") or L("Pas encore assez de faits datés pour en tirer des habitudes."))
    o.noFacts:SetShown(#list==0)
    for i,card in ipairs(o.cards) do
        local item=list[i]
        card:SetShown(item~=nil)
        if item then
            card.key=item.key
            Panels.Fit(card.value,item.value or "",96,18,11,true)
            card.caption:SetText(item.caption or item.text)
        end
    end
    -- With one row of facts the second is free: say how the last death happened.
    local last=not ally and fights(record)[1]
    local recap=last and #list<=3 and (#list>0 or #story<=3) and deathRecap(record,last)
    o.recapTitle:SetText(recap and L("Comment il vous a tué") or "")
    o.recap:SetText(recap or "")
    o.presenceTitle:SetText(L("Présence sur douze mois"))
    o.presenceLink:SetText(L("Voir les habitudes"))
    local presence=I and record and I.Presence(record,f.guid) or {days={},total=0}
    o.strip:Set(weeks(presence),paintLevel)
    local event=ally and encounters(d,f.guid).events[1] or last and last.main
    o.lastCaption:SetText(ally and L("Dernier fait") or L("Dernier combat"))
    if event then
        local zone=text(event.zone) and event.zone~="?" and (" · "..text(event.zone)) or ""
        local combat=object(event.combat)
        local levels=combat.opponentLevel and combat.playerLevel and L(" · lui %s, vous %s"):format(combat.opponentLevel,combat.playerLevel) or ""
        local title=last and GL.FightTitle(last) or GL.HistoryTitle(event)
        o.lastText:SetText((GL.Safe(date,"%d/%m",last and last.at or event.time) or "?").." · "..title..zone..levels)
        o.lastLink:SetText(L("Détail"))
        o.lastLink:SetScript("OnClick",function() GL.InspectEvent(record,event) end)
        o.lastLink:SetShown(combatKinds[event.kind]==true)
    else
        o.lastText:SetText(L("Aucun pour l’instant."))
        o.lastLink:Hide()
    end
end
-- The facts list: every sentence, each opening its dated events, then back to the overview.
local function factsPage(f,d,row)
    row(L("Tous les faits"),L("Retour à l’aperçu"),true,function()
        f.factsMode,f.pageNumber=false,1
        draw(f)
    end)
    insightsSection(f,d,row)
end
local changeLabels={level=L("Niveau : de %s à %s"),ilvl=L("Niveau d’objet : de %s à %s")}
local function changeText(c)
    if changeLabels[c.key] then
        return changeLabels[c.key]:format(tostring(c.previous),tostring(c.value))
    elseif c.key=="spec" then
        return L("Spécialisation : %s"):format(tostring(c.value))
    elseif c.key=="guild" then
        return L("Guilde : %s"):format(UI.plain(tostring(c.value)))
    end
    local slot=c.key:match("^gear:(.+)$")
    for _,s in ipairs(slots) do
        if s[1]==slot then
            return L("Pièce changée : %s"):format(L(s[2]))
        end
    end
    return L("Pièce changée")
end
local function buildHabits(f)
    local h=CreateFrame("Frame",nil,f)
    h:SetPoint("TOPLEFT",232,-197)
    h:SetSize(640,408)
    h.tiles={}
    for i=1,3 do
        local tile=Panels.Tile(h,208,58)
        tile:SetPoint("TOPLEFT",(i-1)*216,0)
        h.tiles[i]=tile
    end
    h.gridTitle=Panels.Text(h,0,-70,300,16,true,UI.theme.red)
    h.grid=heatmap(h)
    h.grid:ClearAllPoints()
    h.grid:SetPoint("TOPLEFT",0,-92)
    h.zones=Panels.ListBlock(h,314,4)
    h.zones:SetPoint("TOPLEFT",0,-236)
    h.changes=Panels.ListBlock(h,314,4)
    h.changes:SetPoint("TOPLEFT",326,-236)
    h:Hide()
    return h
end
local function paintHabits(f,d)
    local h,record=f.habits,d.localRecord
    local I=GL.CharacterInsights
    local presence=I and record and I.Presence(record,f.guid) or {days={},grid={},zones={},total=0,max=0}
    local total,days=0,0
    for _,week in ipairs(weeks(presence)) do
        total=total+week.count
    end
    for back=0,363 do
        if (presence.days[I and I.DayKey(GL.Now()-back*86400) or 0] or 0)>0 then
            days=days+1
        end
    end
    local zones=I and I.ZoneList(presence) or {}
    setTile(h.tiles[1],L("Apparitions, 12 mois"),tostring(total))
    setTile(h.tiles[2],L("Jours différents"),tostring(days))
    setTile(h.tiles[3],L("Zone principale"),zones[1] and text(zones[1].name) or "—",nil,true)
    h.gridTitle:SetText(L("Jour et heure"))
    paintHeatmap(h.grid,presence)
    h.grid:Show()
    local items={}
    for _,zone in ipairs(zones) do
        items[#items+1]={text=text(zone.name) or "?",value=tostring(zone.count),share=zone.count/math.max(1,zones[1].count)}
    end
    h.zones:Set(L("Zones · %d"):format(#zones),items,L("Aucune zone notée pour l’instant."))
    local changes={}
    for _,c in ipairs(f.guid and GL.CharacterHistory and GL.CharacterHistory.Changes(f.guid) or {}) do
        changes[#changes+1]={text=changeText(c),value=GL.Safe(date,"%d/%m",c.at) or "?"}
    end
    h.changes:Set(L("Évolution · %d"):format(#changes),changes,L("Aucun changement relevé pour l’instant."))
end
-- Groups, trades and tags of a player of your own faction, newest first.
local function encountersPage(f,d,row)
    local met=encounters(d,f.guid)
    row(L("Vos rencontres"),nil,true)
    -- Where you crossed them, even without a group or a trade.
    local r=d.localRecord
    local seen=r and type(r.encounters)=="table" and tonumber(r.encounters.count) or 0
    local zone=r and text(r.lastEncounterZone)
    if zone then
        local sub=text(r.lastEncounterSubzone)
        local place=sub and sub~=zone and (sub.." · "..zone) or zone
        row(L("Croisé %d fois · dernière fois : %s"):format(math.max(seen,1),place),nil,nil,nil,nil,
            {time=r.lastEncounterAt and GL.Safe(date,"%d/%m",r.lastEncounterAt) or nil,chip={L("Vous"),true}})
    end
    local duels=object(r and r.duels)
    if (duels.wins or 0)+(duels.losses or 0)>0 then
        row(L("Duels"),L("%d gagnés · %d perdus"):format(duels.wins or 0,duels.losses or 0))
    end
    if #met.events==0 then
        row(L("Aucun groupe ni échange enregistré."))
    end
    for _,e in ipairs(met.events) do
        local zone=text(e.zone) and e.zone~="?" and (" · "..text(e.zone)) or ""
        row(GL.HistoryTitle(e)..zone,nil,nil,nil,nil,{time=GL.Safe(date,"%d/%m",e.time),chip={L("Vous"),true}})
    end
    row(L("Signalements de la guilde"),nil,true)
    local G=GL.GuildProfiles
    local card=G and f.guid and G.ForTarget(f.guid)
    local tagNames={}
    for _,choice in ipairs(G and G.choices or {}) do
        tagNames[choice[1]]=L(choice[2])
    end
    local shown=0
    for _,e in ipairs(card and G.View(card) or {}) do
        if e.on then
            shown=shown+1
            row(tagNames[e.tag] or unknown,nil,nil,nil,nil,{time=GL.Safe(date,"%d/%m",e.time),chip={firstName(UI.plain(e.authorName)),false}})
        end
    end
    if shown==0 then
        row(L("Aucun membre n’a étiqueté ce joueur."))
    end
end
local MAX_FIGHTS=15
local combatTabs={{"you","Vous",70},{"guild","Guilde",74},{"bounties","Primes",74},{"armory","Armurerie",96}}
local function combatPage(f,d,row)
    local profile,record=d.profile,d.localRecord
    local tab=f.combatTab or "you"
    if tab=="you" then
    if record then
        local p=GL.ContactMatchup(d.record)
        local list=fights(record)
        row(L("Victoires / morts"),p.kills.." / "..p.deaths.." · "..L("%d combats"):format(#list),true)
        local formula=GL.BalanceFormula(record)
        if formula~="" then
            local _,fightBalance=GL.AutomaticBalance(record)
            row(L("Solde %+d = %s"):format(fightBalance or 0,formula))
        end
        row(L("Honneur attribué"),p.honorAwards>0 and text(p.honor) or unknown)
        local duels=object(record.duels)
        if (duels.wins or 0)+(duels.losses or 0)>0 then
            row(L("Duels"),L("%d gagnés · %d perdus"):format(duels.wins or 0,duels.losses or 0))
        end
        for i=1,math.min(MAX_FIGHTS,#list) do
            local fight=list[i]
            row(timestamp(fight.at).." · "..fightText(fight),L("Détail"),nil,function() GL.InspectEvent(record,fight.main) end)
        end
        if #list>MAX_FIGHTS then
            row(L("%d combats plus anciens dans l’Histoire du journal."):format(#list-MAX_FIGHTS))
        end
        -- Same action style as "Détail": a quiet line rather than a large button.
        if GL.DeathReport and #GL.DeathReport.Deaths(f.guid)>0 then
            row(L("Vos morts contre ce joueur, en texte pour une IA"),L("Exporter"),nil,function()
                GL.DeathReport.ShowExport(f.guid)
            end)
        end
    else
        row(L("Aucune rencontre personnelle enregistrée."))
    end
    elseif tab=="guild" then
    row(L("Face-à-face de la guilde"),nil,true)
    if inGuild(f) then
        local wins,losses=GL.Bounties.GuildFights(f.guid)
        if wins==0 and losses==0 then
            row(L("Aucun résultat partagé pour cette cible."))
        else
            row(L("Victoires / morts"),wins.." / "..losses)
        end
        local scope=GL.Bounties.GuildScope()
        local members=scope and scope.scores and scope.scores[f.guid] or {}
        for _,member in ipairs(sortedKeys(members)) do
            local s=members[member]
            row(GL.Bounties.MemberName(member) or L("Membre de guilde"),s[1]..L(" V").." / "..s[2]..L(" D"))
        end
    else
        row(unknown)
    end
    elseif tab=="bounties" then
    row(L("Dossier de primes"),nil,true)
    local dossier=bountyDossier(f.guid)
    if dossier.count==0 then
        row(L("Jamais mis à prix dans votre guilde."))
    else
        row(bountySummary(dossier))
        for _,e in ipairs(dossier.orders) do
            local by=UI.plain(GL.Bounties.MemberName(e.owner) or L("Membre de guilde"))
            row(bountyLine(e),L("par %s"):format(by))
        end
    end
    else
    row(L("Palmarès JcJ · Armurerie"),nil,true)
    row(profile.updated and (L("Relevé Armurerie : ")..timestamp(profile.updated)) or L("Aucun relevé Armurerie chargé"))
    row(L("Victoires honorables"),valueOf(profile.honorableKills) or unknown)
    row(L("Rang JcJ"),valueOf(profile.pvpRank) or unknown)
    row(L("Champs de bataille"),profile.battlegroundsAt and timestamp(profile.battlegroundsAt),true)
    if #object(profile.battlegrounds)==0 then
        row(profile.battlegrounds and L("Aucun champ de bataille publié.") or L("Champs de bataille non renseignés."))
    end
    for _,v in ipairs(object(profile.battlegrounds)) do
        local games,wins,losses=valueOf(v.games) or "—",valueOf(v.wins) or "—",valueOf(v.losses) or "—"
        row(text(v.name) or unknown,games..L(" parties").." · "..wins..L(" V").." / "..losses..L(" D"))
    end
    row(L("Hauts faits JcJ"),type(profile.achievements)=="table" and tostring(#profile.achievements) or unknown,true)
    if profile.achievementsAt then
        row(field(L("Relevé"),timestamp(profile.achievementsAt)))
    end
    for _,a in ipairs(object(profile.achievements)) do
        row((text(a.name) or unknown)..(a.accountWide and L(" (compte)") or ""))
    end
    end
end
local statOrder={"HEALTH","MANA","ENERGY","RAGE","FOCUS","RUNICPOWER","STRENGTH","AGILITY","STAMINA","INTELLECT","SPIRIT","ARMOR","CRITICALSTRIKE"}
-- Every statistic, moved out of the identity column into the Equipment tab.
local function statsPage(d,row)
    row(L("Caractéristiques"),nil,true)
    if d.liveStats then
        row(field(L("Caractéristiques vues en jeu"),timestamp(d.live.statsAt)))
    end
    local seen,count={},0
    local function add(key)
        local val=not seen[key] and key~="ITEMLEVEL" and statValue(key,d.stats[key])
        if val then
            row(statNames[key] or text(prettyKey(key)),val)
            seen[key],count=true,count+1
        end
    end
    for _,key in ipairs(statOrder) do
        add(key)
    end
    for _,key in ipairs(sortedKeys(d.stats)) do
        add(key)
    end
    if count==0 then
        row(L("Aucun relevé de caractéristiques."))
    end
end
local function sourceText(f,d)
    if f.page=="overview" or f.page=="habits" or f.page=="combat" then
        return ""
    end
    if f.page=="relations" then
        return L("Journal personnel et témoignages de guilde")
    end
    local profile,inspection=d.profile,d.live
    local observedAt=f.page=="gear" and profile.inspectedGear and inspection.gearAt
        or f.page=="talents" and inspection.trees and profile.trees==inspection.trees and inspection.talentsAt
    local shared=not observedAt and provenanceLabel(profile,f.page)
    if shared then
        return shared
    end
    if observedAt then
        local partial=f.page=="gear" and profile.partialGear
        return (partial and L("Inspection partielle · ") or L("Inspection en jeu · "))..timestamp(observedAt)
    end
    if profile.updated then
        return L("Relevé Armurerie : ")..timestamp(profile.updated)
    end
    if f.page~="gear" and f.page~="talents" then
        return L("Aucun relevé Armurerie chargé")
    end
    if d.pending then
        return L("Inspection en cours…")
    end
    return GL.VisiblePortraitUnit(d.record) and L("Aucun relevé disponible en jeu")
        or L("Aucun relevé : ciblez-le à moins de 30 m, la lecture se fait seule")
end
draw=function(f)
    local d=resolve(f)
    drawIdentity(f,d)
    f.source:SetText(sourceText(f,d))
    local public=object(d.profile.identity)
    f.armoryURL=armoryURL(d.record.fullName or public.name or f.knownName)
    if f.armoryURL then
        f.armoryButton:Show()
    else
        f.armoryButton:Hide()
        f.armoryLink:Hide()
    end
    f.ilvl:SetText(f.page=="gear" and field(L("Niv. d’objet moyen"),valueOf(d.itemLevel)) or "")
    for key,b in pairs(f.tabs) do
        UI.selectButton(b,f.page==key)
    end
    for key,b in pairs(f.filters) do
        UI.selectButton(b,(f.relationFilter or "all")==key)
    end
    for _,control in ipairs({f.filters.mine,f.filters.guild,f.filters.all}) do
        if f.page=="relations" then
            control:Show()
        else
            control:Hide()
        end
    end
    f.statsToggle:SetText(f.gearStats and L("Voir le mannequin") or L("Voir les caractéristiques"))
    if f.page=="gear" then
        f.statsToggle:Show()
    else
        f.statsToggle:Hide()
    end
    -- Same format for everyone; for a player of your faction never fought, Combats reads Encounters.
    local ally=allyVariant(d)
    f.tabs.combat:SetText(ally and L("Rencontres") or L("Combats"))
    for key,b in pairs(f.combatTabs) do
        b:SetShown(f.page=="combat" and not ally)
        UI.selectButton(b,(f.combatTab or "you")==key)
    end
    local overview=f.page=="overview" and not f.factsMode
    f.overview:SetShown(overview)
    if overview then
        paintOverview(f,d)
    end
    f.habits:SetShown(f.page=="habits")
    if f.page=="habits" then
        paintHabits(f,d)
    end
    if overview or f.page=="habits" then
        f.equipment:Hide()
        f.talents:Hide()
        f.body:Hide()
        showPager(f,0)
        return
    end
    local gear,talents=f.page=="gear" and not f.gearStats,f.page=="talents"
    if gear then
        f.equipment:Show()
        GL.DrawDossierEquipment(f.equipment,d.record,d.profile,slots,slotOrder,itemDetails)
    else
        f.equipment:Hide()
    end
    if talents then
        f.talents:Show()
        GL.DrawDossierTalents(f.talents,d.record,d.profile)
    else
        f.talents:Hide()
    end
    if gear or talents then
        f.body:Hide()
        showPager(f,0)
        return
    end
    f.body:Show()
    local specs={}
    local function row(label,amount,heading,onClick,indent,extra)
        specs[#specs+1]={label=label,amount=amount,heading=heading,onClick=onClick,indent=indent,extra=extra}
    end
    if f.page=="relations" then
        relationsPage(f,d.localRecord,row)
    elseif f.page=="overview" then
        factsPage(f,d,row)
    elseif f.page=="combat" and ally then
        encountersPage(f,d,row)
    elseif f.page=="combat" then
        combatPage(f,d,row)
    else
        statsPage(d,row)
    end
    paginate(f,specs)
end

-- One row of a page: caption, optional amount or action on the right, a thin rule below.
local function rowFrame(f,count)
    local r=f.rows[count]
    if not r then
        r=CreateFrame("Button",nil,f.body)
        f.rows[count]=r
        r.caption=UI.label(r,"",nil,7,-4,630)
        r.amount=UI.label(r,"",nil,428,-4,198)
        r.amount:SetJustifyH("RIGHT")
        r.rule=r:CreateTexture(nil,"BACKGROUND")
        r.rule:SetPoint("BOTTOMLEFT")
        r.rule:SetPoint("BOTTOMRIGHT")
        r.rule:SetHeight(1)
        r.rule:SetColorTexture(.45,.28,.11,.21)
        r.hover=r:CreateTexture(nil,"HIGHLIGHT")
        r.hover:SetAllPoints()
        r.hover:SetColorTexture(.45,.28,.11,.12)
    end
    return r
end
local function fillRow(r,s)
    local label,amount,heading,onClick,indent=s.label,s.amount,s.heading,s.onClick,s.indent
    local extra=s.extra or {}
    r:EnableMouse(onClick~=nil)
    r:SetScript("OnClick",onClick)
    local left=indent and 27 or 7
    -- A time, then the author's chip, then the text.
    if extra.time then
        r.time=r.time or Panels.Text(r,7,-6,44,11,false,UI.theme.inkMuted)
        r.time:SetText(extra.time)
        r.time:Show()
        left=54
    elseif r.time then
        r.time:Hide()
    end
    if extra.chip then
        r.chip=r.chip or Panels.Pill(r)
        r.chip:Set(extra.chip[1] or "?",extra.chip[2] and "mine" or "member")
        r.chip:ClearAllPoints()
        r.chip:SetPoint("TOPLEFT",left,-3)
        left=left+math.max(r.chip:GetWidth(),52)+8
    elseif r.chip then
        r.chip:Hide()
    end
    if extra.pill then
        r.pill=r.pill or Panels.Pill(r)
        r.pill:Set(extra.pill[1],extra.pill[2])
        r.pill:ClearAllPoints()
        r.pill:SetPoint("TOPLEFT",250,-3)
    elseif r.pill then
        r.pill:Hide()
    end
    r.caption:ClearAllPoints()
    r.caption:SetPoint("TOPLEFT",left,-4)
    -- A clickable row has a short action on the right ("Détail", "Faits (3)"): give the text more room.
    local width=(amount and (onClick and 520 or 412) or 620)-(left-7)
    r.caption:SetWidth(extra.pill and 236 or width)
    UI.journalFont(r.caption,heading and "GameFontNormalLarge" or "GameFontHighlight",heading and 17 or extra.small and 11 or 13)
    r.caption:SetTextColor(unpack(heading and UI.theme.red or (indent or extra.small) and UI.theme.inkMuted or UI.theme.ink))
    r.amount:SetTextColor(unpack(onClick and UI.theme.red or UI.theme.ink))
    r.caption:SetText(label)
    r.amount:SetText(amount or "")
    local h=math.max(heading and 35 or extra.small and 22 or 26,r.caption:GetStringHeight()+10,r.amount:GetStringHeight()+10)
    r:SetSize(634,h)
    return h
end
-- No scroll bar: rows fill the page, the rest goes on the next pages. A heading never ends a
-- page alone. Small arrows at the bottom right, or the mouse wheel, turn the pages.
paginate=function(f,specs)
    local limit,count=f.body:GetHeight(),0
    for _,s in ipairs(specs) do
        if not s.region then
            count=count+1
            s.frame=rowFrame(f,count)
            s.h=fillRow(s.frame,s)
        end
    end
    local pages,used={{}},0
    for i,s in ipairs(specs) do
        local need=s.h+(s.heading and specs[i+1] and specs[i+1].h or 0)
        if #pages[#pages]>0 and used+need>limit then
            pages[#pages+1]={}
            used=0
        end
        local page=pages[#pages]
        page[#page+1]=s
        used=used+s.h
    end
    for _,r in ipairs(f.rows) do
        r:Hide()
    end
    for _,s in ipairs(specs) do
        if s.region then
            s.region:Hide()
        end
    end
    f.pageNumber=math.max(1,math.min(f.pageNumber or 1,#pages))
    local y=0
    for _,s in ipairs(pages[f.pageNumber]) do
        local region=s.frame or s.region
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT",s.region and 7 or 0,-y)
        region:Show()
        y=y+s.h
    end
    showPager(f,#pages)
end
showPager=function(f,total)
    f.pageCount=total
    local shown=total>1
    for _,control in ipairs({f.pagePrev,f.pageNext,f.pageLabel}) do
        if shown then
            control:Show()
        else
            control:Hide()
        end
    end
    if shown then
        f.pageLabel:SetText(("%d / %d"):format(f.pageNumber,total))
        f.pagePrev:SetEnabled(f.pageNumber>1)
        f.pageNext:SetEnabled(f.pageNumber<total)
    end
end
local function turnPage(f,step)
    local target=(f.pageNumber or 1)+step
    if f.pageCount and target>=1 and target<=f.pageCount then
        f.pageNumber=target
        draw(f)
    end
end
local tabs={{"overview","Aperçu"},{"combat","Combats"},{"habits","Habitudes"},{"relations","Relations"},{"gear","Équipement"},{"talents","Talents"}}
local function build()
    local f=UI.bookWindow("GrudgeLedgerPlayerDossier","Grudge Ledger",true)
    GL.SetupBookNavigation(f,"ledger")
    f.back=UI.button(f,L("Retour"),39,-154,116,function()
        f:Hide()
        if f.onReturn then
            f.onReturn()
        else
            GL.ShowLedger(f.key)
        end
    end)
    f.portrait=CreateFrame("Frame",nil,f)
    f.portrait:SetPoint("TOPLEFT",36,-186)
    f.portrait:SetSize(64,64)
    f.portrait.raceIcon=f.portrait:CreateTexture(nil,"ARTWORK")
    f.portrait.raceIcon:SetAllPoints()
    f.portrait.photo=f.portrait:CreateTexture(nil,"ARTWORK",nil,1)
    f.portrait.photo:SetAllPoints()
    f.portrait.photo:Hide()
    f.portrait.classIcon=f.portrait:CreateTexture(nil,"OVERLAY")
    f.portrait.classIcon:SetSize(16,16)
    f.portrait.classIcon:SetPoint("BOTTOMRIGHT")
    f.nameLabel=UI.label(f,"","large",106,-190,100)
    GL.Safe(f.nameLabel.SetMaxLines,f.nameLabel,2)
    f.identity=UI.label(f,"",nil,38,-256,168)
    UI.journalFont(f.identity,"GameFontHighlight",11)
    GL.Safe(f.identity.SetMaxLines,f.identity,4)
    -- The identity column is fixed: verdict, six figures and the last sighting fit without scrolling.
    f.identityBody=CreateFrame("Frame",nil,f)
    f.identityBody:SetPoint("TOPLEFT",38,-312)
    f.identityBody:SetSize(168,296)
    f.verdictHeading=Panels.Text(f.identityBody,0,0,166,12,true,UI.theme.brass)
    f.verdictHeading:SetText(L("Verdict"))
    f.keyHeading=Panels.Text(f.identityBody,0,0,166,12,true,UI.theme.brass)
    f.keyHeading:SetText(L("Chiffres clés"))
    f.observed=UI.label(f.identityBody,"",nil,0,0,166)
    UI.journalFont(f.observed,"GameFontHighlight",11)
    f.observed:SetTextColor(unpack(UI.theme.muted))
    f.bounty=UI.button(f,"",38,-612,168,function() GL.OpenContactBounty(f.guid) end)
    f.whisper=UI.button(f,L("Chuchoter"),38,-612,82,function()
        if f.contactName then GL.Safe(ChatFrame_SendTell,f.contactName) end
    end)
    f.invite=UI.button(f,L("Inviter"),124,-612,82,function()
        local invite=C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
        if f.contactName then GL.Safe(invite,f.contactName) end
    end)
    f.armoryButton=UI.button(f,L("Lien Armurerie"),38,-643,168,function()
        f.armoryLink:SetText(f.armoryURL)
        f.armoryLink:Show()
        f.armoryLink:SetFocus()
        f.armoryLink:HighlightText()
    end)
    f.armoryLink=CreateFrame("EditBox",nil,f.armoryButton,"InputBoxTemplate")
    f.armoryLink:SetSize(166,24)
    f.armoryLink:SetPoint("CENTER")
    f.armoryLink:SetAutoFocus(false)
    f.armoryLink:Hide()
    f.armoryLink:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    f.armoryLink:SetScript("OnEditFocusLost",function(self) self:Hide() end)
    f.tabs,f.rows,f.statCells,f.pills={},{},{},{}
    for i,s in ipairs(tabs) do
        local key=s[1]
        f.tabs[key]=UI.button(f,L(s[2]),232+(i-1)*106,-156,102,function()
            f.page,f.pageNumber,f.factsMode=key,1,false
            draw(f)
        end,true,true)
    end
    f.source=UI.label(f,"",nil,235,-196,430)
    f.combatTabs={}
    local cx=232
    for _,s in ipairs(combatTabs) do
        local key=s[1]
        f.combatTabs[key]=UI.button(f,L(s[2]),cx,-190,s[3],function()
            f.combatTab,f.pageNumber=key,1
            draw(f)
        end,true,true)
        cx=cx+s[3]+3
    end
    f.source:SetTextColor(unpack(UI.theme.inkMuted))
    f.ilvl=UI.label(f,"",nil,669,-196,222)
    f.ilvl:SetJustifyH("RIGHT")
    f.ilvl:SetTextColor(unpack(UI.theme.ink))
    f.body=CreateFrame("Frame",nil,f)
    f.body:SetPoint("TOPLEFT",232,-225)
    f.body:SetSize(640,408)
    GL.Safe(f.body.EnableMouseWheel,f.body,true)
    f.body:SetScript("OnMouseWheel",function(_,delta) turnPage(f,delta>0 and -1 or 1) end)
    f.overview=buildOverview(f)
    f.habits=buildHabits(f)
    f.expanded={}
    f.equipment=CreateFrame("Frame",nil,f)
    f.equipment:SetPoint("TOPLEFT",239,-229)
    f.equipment:SetSize(635,398)
    f.talents=CreateFrame("Frame",nil,f)
    f.talents:SetPoint("TOPLEFT",232,-225)
    f.talents:SetSize(649,403)
    f.statsToggle=UI.button(f,"",232,-645,230,function()
        f.gearStats,f.pageNumber=not f.gearStats,1
        draw(f)
    end,nil,true)
    f.pagePrev=UI.button(f,"‹",770,-645,30,function() turnPage(f,-1) end,nil,true)
    f.pageNext=UI.button(f,"›",860,-645,30,function() turnPage(f,1) end,nil,true)
    f.pageLabel=UI.label(f,"",nil,802,-652,56)
    f.pageLabel:SetJustifyH("CENTER")
    f.pageLabel:SetTextColor(unpack(UI.theme.inkMuted))
    f.filters={}
    local x=671
    for _,s in ipairs(filters) do
        local key=s[1]
        f.filters[key]=UI.button(f,L(s[2]),x,-190,s[3],function()
            f.relationFilter,f.pageNumber=key,1
            draw(f)
        end,true,true)
        x=x+s[3]+3
    end
    return f
end
-- page: optional tab to open; the sheet opens on the overview by default.
function GL.OpenPlayerDossier(id,onReturn,knownName,page)
    if type(id)~="string" then
        return false
    end
    local key,guid
    if #id<=32 and id:match("^Player%-%w+%-%w+$") then
        key,guid="guid:"..id,id
    elseif id:match("^name:") and GL.Get(id) then
        local contact=GL.Get(id)
        key,guid=contact.key,contact.guid
    else
        return false
    end
    local contact=GL.Get(key)
    GL.RequestArmory(key,(contact and contact.fullName) or knownName,guid)
    frame=frame or build()
    frame.armoryLink:Hide()
    frame.key,frame.guid,frame.onReturn,frame.knownName=key,guid,onReturn,knownName
    frame.page=frame.tabs[page] and page or "overview"
    frame.pageNumber,frame.gearStats,frame.relationFilter,frame.expanded,frame.factsMode=1,false,"all",{},false
    frame.combatTab="you"
    if GL.InspectDossierUnit then
        GL.InspectDossierUnit(GL.VisiblePortraitUnit({guid=guid}),guid)
    end
    GL.ShowBookPage(frame)
    draw(frame)
    if guid and GL.SharedDossiers then
        GL.SharedDossiers.Request(guid)
    end
    return true
end

GL.On("DOSSIER_UPDATED",function(guid)
    if frame and frame:IsShown() and (not guid or frame.guid==guid) then
        draw(frame)
    end
end)
for _,event in ipairs({"CHANGED","GUILD_PROFILES","BOUNTIES_CHANGED"}) do
    GL.On(event,function()
        if frame and frame:IsShown() then
            draw(frame)
        end
    end)
end
