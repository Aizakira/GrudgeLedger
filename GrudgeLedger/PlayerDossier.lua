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
-- Assigned below; the expandable facts redraw the sheet.
local draw
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
    local first=(level and (L("Niv. %d"):format(level).." · ") or "")..class
    local lines={first..(spec and (" ("..spec..")") or ""),race.." · "..faction}
    local guild=text(record.guild) or text(public.guild)
    if guild then
        lines[3]="<"..guild..">"
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
-- Your opinion first, then the guild's total, an open bounty and the tags.
local function verdictText(d,guid)
    local record,lines=d.localRecord,{}
    if record then
        local relation=relationNames[GL.Relation(record)] or unknown
        lines[1]=L("Vous : %s · %s"):format(("%+d"):format(record.reputation or 0),relation)
    else
        lines[1]=L("Vous : aucune rencontre")
    end
    local reports=GL.SharedDossiers and guid and GL.SharedDossiers.SocialReports(guid) or {}
    local sum=0
    for _,report in ipairs(reports) do
        sum=sum+(tonumber(report.score) or 0)
    end
    lines[2]=#reports>0 and L("Guilde : %s · %d avis"):format(("%+d"):format(sum),#reports) or L("Guilde : aucun avis partagé")
    local order=openBounty(guid)
    if order then
        lines[#lines+1]=L("Prime ouverte : %s"):format(bountyAmount(order))
    end
    local tags=record and GL.TagText and GL.TagText(record)
    if tags then
        lines[#lines+1]=tags
    end
    return table.concat(lines,"\n")
end
local powers={"MANA","ENERGY","RAGE","FOCUS","RUNICPOWER"}
local function keyFigures(d)
    local stats,power=d.stats,"MANA"
    for i=#powers,1,-1 do
        if stats[powers[i]] then
            power=powers[i]
        end
    end
    return {
        {statValue("HEALTH",stats.HEALTH),statNames.HEALTH},
        {statValue(power,stats[power]),statNames[power]},
        {statValue("ARMOR",stats.ARMOR),statNames.ARMOR},
        {valueOf(d.itemLevel),L("Niv. objet")},
        {valueOf(d.profile.pvpRank),L("Rang JcJ")},
        {valueOf(d.profile.honorableKills),L("Vict. hon.")},
    }
end
local function seenText(d)
    local record,lines=d.record,{}
    local at=record.lastSeen or record.lastEncounterAt
    if at then
        local zone=text(record.lastZone) or text(record.lastEncounterZone)
        lines[1]=L("Vu le %s"):format(timestamp(at))..(zone and (" · "..zone) or "")
    else
        lines[1]=L("Pas encore croisé")
    end
    local readings={}
    local inspectedAt=d.live.gearAt or d.live.statsAt or d.live.talentsAt
    if inspectedAt then
        readings[#readings+1]=L("inspection %s"):format(timestamp(inspectedAt))
    end
    if d.archivedAt>0 then
        readings[#readings+1]=L("Armurerie %s"):format(timestamp(d.archivedAt))
    end
    lines[#lines+1]=#readings>0 and L("Relevés : %s"):format(table.concat(readings," · ")) or L("Aucun relevé chargé")
    if not next(d.archive) then
        lines[#lines+1]=L("Le compagnon lit le Journal à la déconnexion ou au /reload. Après l’import, /reload affiche le relevé.")
    end
    return table.concat(lines,"\n")
end
local function keyCell(f,i)
    local c=f.statCells[i]
    if c then
        return c
    end
    c=CreateFrame("Frame",nil,f.identityBody)
    c:SetSize(78,44)
    c.value=UI.label(c,"","large",0,0,78)
    c.label=UI.label(c,"",nil,0,-23,80)
    UI.journalFont(c.label,"GameFontHighlight",11)
    c.label:SetTextColor(unpack(UI.theme.brass))
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
    f.nameLabel:SetText(name or unknown)
    GL.PaintBookPortrait(f.portrait,record)
    f.identity:SetText(identityText(d))
    local mode=GL.ContactBountyMode(record)
    f.bounty:SetText(mode=="view" and L("Voir la prime") or L("Créer une prime"))
    if mode then
        f.bounty:Show()
    else
        f.bounty:Hide()
    end
    local y=0
    local function place(region,height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT",0,-y)
        y=y+height
    end
    place(f.verdictHeading,26)
    f.verdict:SetText(verdictText(d,f.guid))
    place(f.verdict,f.verdict:GetStringHeight()+14)
    place(f.keyHeading,26)
    for i,figure in ipairs(keyFigures(d)) do
        local c=keyCell(f,i)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT",((i-1)%3)*82,-(y+math.floor((i-1)/3)*47))
        c.value:SetText(figure[1] or "—")
        c.value:SetTextColor(unpack(figure[1] and UI.theme.paper or UI.theme.muted))
        c.label:SetText(figure[2])
        c:Show()
    end
    y=y+2*47+6
    f.observed:SetText(seenText(d))
    place(f.observed,f.observed:GetStringHeight()+12)
    f.identityBody:SetHeight(math.max(f.identityScroll:GetHeight(),y))
end

local combatKinds={kill=true,death=true,aggression=true}
local function fights(record)
    local list={}
    for _,e in ipairs(object(record and record.history)) do
        if type(e)=="table" and combatKinds[e.kind] and not e.voided and e.voidReason~="battleground" and type(e.time)=="number" then
            list[#list+1]=e
        end
    end
    table.sort(list,function(a,b) return a.time>b.time end)
    return list
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
-- One row per guild member: their opinion and their fights against the target, then the guild total.
local function memberRows(f,row)
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
    local sum,count=0,0
    for _,m in ipairs(list) do
        local parts={L("sans avis")}
        if m.score then
            parts[1]=("%+d"):format(m.score).." · "..(relationNames[m.relation] or unknown)
            sum,count=sum+m.score,count+1
        end
        if m.fights then
            parts[2]=score(m.fights[1],m.fights[2])
        end
        row(m.label,table.concat(parts," · "))
    end
    if #list==0 then
        row(L("Aucun historique ni solde partagé par les autres membres."))
    end
    if count>0 then
        row(L("Total de la guilde"),L("%s · %d avis"):format(("%+d"):format(sum),count))
    end
end
local filters={{"mine","Moi",58},{"guild","Guilde",92},{"all","Tout",58}}
local function relationsPage(f,record,row)
    local B,G,S=GL.Bounties,GL.GuildProfiles,GL.SharedDossiers
    local me,filter=GL.Safe(UnitGUID,"player"),f.relationFilter or "all"
    local timeline={}
    local function add(at,description,source,mine)
        if filter=="all" or (filter=="mine")==(mine==true) then
            timeline[#timeline+1]={at=tonumber(at) or 0,description=description,source=source,seq=#timeline+1}
        end
    end
    row(L("Votre avis"),nil,true)
    if record then
        row(L("Votre carnet"),("%+d"):format(record.reputation or 0).." · "..(relationNames[GL.Relation(record)] or unknown))
        if GL.TagText and GL.TagText(record) then
            row(GL.TagText(record))
        end
        for _,item in ipairs(GL.JournalEvents()) do
            if item.record==record then
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
                add(e.time,description,L("Votre journal").." · "..UI.plain(e.actorName or L("Auteur inconnu")),true)
            end
        end
    else
        row(L("Aucune rencontre personnelle enregistrée."))
    end
    row(L("Avis de la guilde"),nil,true)
    memberRows(f,row)
    for _,report in ipairs(S and S.SocialReports(f.guid) or {}) do
        local author=UI.plain(B.MemberName(report.actor) or report.authorName or L("Membre de guilde"))
        for _,e in ipairs(report.events) do
            local title=GL.HistoryTitle(e,author,f.nameLabel:GetText())..(e.zone and (" · "..UI.plain(e.zone)) or "")
            add(e.time,title,L("Témoignage de %s"):format(author),report.actor==me)
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
                    add(e.time,change,L("Avis de %s"):format(UI.plain(e.authorName)),e.actor==me)
                end
            end
        end
    end
    for _,order in ipairs(bountyDossier(f.guid).orders) do
        local author=L("Créée par %s"):format(UI.plain(B.MemberName(order.owner) or L("Membre de guilde")))
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
    row(L("Interactions datées"),nil,true)
    row(L("Les témoignages restent attribués à leur auteur ; ils ne modifient pas votre avis."))
    local offset=math.min(f.historyOffset or 0,math.max(0,math.ceil(#timeline/40)-1)*40)
    f.historyOffset=offset
    f.historyPrev:SetEnabled(offset>0)
    f.historyNext:SetEnabled(offset+40<#timeline)
    f.historyCount:SetText(("%d–%d / %d"):format(#timeline>0 and offset+1 or 0,math.min(offset+40,#timeline),#timeline))
    if #timeline==0 then
        row(L("Aucune interaction datée disponible."))
    end
    for i=offset+1,math.min(offset+40,#timeline) do
        local entry=timeline[i]
        row(timestamp(entry.at).." · "..entry.source.."\n"..entry.description)
    end
    row(L("Le partage des faits et avis se règle dans Réglages > Relations. Les notes restent privées."))
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
local function heatmap(parent)
    local m=CreateFrame("Frame",nil,parent)
    m:SetSize(500,7*14+20)
    m.cells={}
    for day=1,7 do
        local label=UI.label(m,L(dayNames[day]),nil,0,-(day-1)*14,32)
        UI.journalFont(label,"GameFontHighlight",10)
        label:SetTextColor(unpack(UI.theme.inkMuted))
        for hour=0,23 do
            local cell=m:CreateTexture(nil,"ARTWORK")
            cell:SetSize(17,12)
            cell:SetPoint("TOPLEFT",36+hour*19,-(day-1)*14-1)
            m.cells[(day-1)*24+hour]=cell
        end
    end
    for _,hour in ipairs({0,6,12,18,23}) do
        local label=UI.label(m,L("%d h"):format(hour),nil,34+hour*19,-7*14-3,40)
        UI.journalFont(label,"GameFontHighlight",10)
        label:SetTextColor(unpack(UI.theme.inkMuted))
    end
    m:Hide()
    return m
end
local function paintHeatmap(m,presence)
    for key,cell in pairs(m.cells) do
        local n=presence.grid[key] or 0
        if n==0 then
            cell:SetColorTexture(.45,.28,.11,.08)
        else
            cell:SetColorTexture(.55,.08,.05,.3+.7*n/math.max(1,presence.max))
        end
    end
end
-- Weekday by hour, darker where the player was seen more often, then the usual zones.
local function habitsSection(f,d,row,block)
    local I=GL.CharacterInsights
    local presence=I and d.localRecord and I.Presence(d.localRecord,f.guid)
    row(L("Habitudes"),nil,true)
    if not presence or presence.total==0 then
        row(L("Aucune apparition enregistrée."))
        return
    end
    paintHeatmap(f.heatmap,presence)
    block(f.heatmap,f.heatmap:GetHeight()+6)
    local zones=text(I.Zones(presence,3))
    if zones then
        row(L("Zones : %s"):format(zones))
    end
end
local function overviewPage(f,d,row,block)
    local record=d.localRecord
    insightsSection(f,d,row)
    row(L("Dernière rencontre"),nil,true)
    local event=fights(record)[1]
    local met=record and (record.lastEncounterAt or record.lastSeen)
    if met then
        local zone=record.lastEncounterAt and text(record.lastEncounterZone) or text(record.lastZone)
        row(timestamp(met)..(zone and (" · "..zone) or ""))
    elseif not event then
        row(L("Aucune rencontre personnelle enregistrée."))
    end
    if event then
        row(L("Dernier combat · %s"):format(timestamp(event.time)).."\n"..fightLine(event),L("Détail"),nil,function()
            GL.InspectEvent(record,event)
        end)
    end
    row(L("Bilan des combats"),nil,true)
    if record then
        local p=GL.ContactMatchup(d.record)
        row(L("Vous"),score(p.kills,p.deaths))
    else
        row(L("Vous"),L("aucun combat"))
    end
    if inGuild(f) then
        local scope=GL.Bounties.GuildScope()
        local members=scope and scope.scores and scope.scores[f.guid] or {}
        for _,member in ipairs(sortedKeys(members)) do
            row(UI.plain(GL.Bounties.MemberName(member) or L("Membre de guilde")),score(members[member][1],members[member][2]))
        end
        row(L("Total de la guilde"),score(GL.Bounties.GuildFights(f.guid)))
    end
    habitsSection(f,d,row,block)
    row(L("Primes"),nil,true)
    local order=openBounty(f.guid)
    if order then
        row(L("Prime ouverte"),bountyAmount(order))
    else
        row(L("Aucune prime ouverte."))
    end
    local dossier=bountyDossier(f.guid)
    if dossier.count>0 then
        row(bountySummary(dossier))
    end
    row(L("Évolution"),nil,true)
    local lines=f.guid and GL.CharacterEvolution and GL.CharacterEvolution(f.guid) or {}
    if #lines==0 then
        row(L("Aucun changement relevé pour l’instant."))
    end
    for _,line in ipairs(lines) do
        row(line)
    end
end
local MAX_FIGHTS=15
local function combatPage(f,d,row)
    local profile,record=d.profile,d.localRecord
    row(L("Votre face-à-face · Journal"),nil,true)
    if record then
        local p=GL.ContactMatchup(d.record)
        row(L("Victoires / morts"),p.kills.." / "..p.deaths)
        row(L("Honneur attribué"),p.honorAwards>0 and text(p.honor) or unknown)
        local list=fights(record)
        for i=1,math.min(MAX_FIGHTS,#list) do
            local e=list[i]
            row(timestamp(e.time).." · "..fightLine(e),L("Détail"),nil,function() GL.InspectEvent(record,e) end)
        end
        if #list>MAX_FIGHTS then
            row(L("%d combats plus anciens dans l’Histoire du journal."):format(#list-MAX_FIGHTS))
        end
    else
        row(L("Aucune rencontre personnelle enregistrée."))
    end
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
    row(L("Palmarès JcJ · Armurerie"),nil,true)
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
    if f.page=="overview" then
        return L("Votre journal, la guilde et les derniers relevés")
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
    return GL.VisiblePortraitUnit(d.record) and L("Aucun relevé disponible en jeu") or L("Hors de vue · aucun relevé chargé")
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
    for _,control in ipairs({f.historyPrev,f.historyNext,f.historyCount,f.filters.mine,f.filters.guild,f.filters.all}) do
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
    local gear,talents=f.page=="gear" and not f.gearStats,f.page=="talents"
    if gear then
        f.equipment:Show()
        GL.DrawDossierEquipment(f.equipment,d.record,d.profile,slots,slotOrder,itemDetails)
    else
        f.equipment:Hide()
    end
    if talents then
        f.talentScroll:Show()
        local h=GL.DrawDossierTalents(f.talents,d.record,d.profile)
        f.talents:SetHeight(math.max(f.talentScroll:GetHeight(),h))
        f.talentScroll:SetVerticalScroll(0)
    else
        f.talentScroll:Hide()
    end
    if gear or talents then
        f.scroll:Hide()
        return
    end
    f.scroll:Show()
    local count,height=0,0
    local function row(label,amount,heading,onClick,indent)
        count=count+1
        local r=f.rows[count]
        if not r then
            r=CreateFrame("Button",nil,f.body)
            f.rows[count]=r
            r.caption=UI.label(r,"",nil,7,-4,510)
            r.amount=UI.label(r,"",nil,308,-4,198)
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
        r:EnableMouse(onClick~=nil)
        r:SetScript("OnClick",onClick)
        r.caption:ClearAllPoints()
        r.caption:SetPoint("TOPLEFT",indent and 27 or 7,-4)
        -- A clickable row has a short action on the right ("Détail", "Faits (3)"): give the text more room.
        r.caption:SetWidth((amount and (onClick and 400 or 292) or 500)-(indent and 20 or 0))
        UI.journalFont(r.caption,heading and "GameFontNormalLarge" or "GameFontHighlight",heading and 17 or 13)
        r.caption:SetTextColor(unpack(heading and UI.theme.red or indent and UI.theme.inkMuted or UI.theme.ink))
        r.amount:SetTextColor(unpack(onClick and UI.theme.red or UI.theme.ink))
        r.caption:SetText(label)
        r.amount:SetText(amount or "")
        local h=math.max(heading and 35 or 26,r.caption:GetStringHeight()+10,r.amount:GetStringHeight()+10)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT",0,-height)
        r:SetSize(514,h)
        r:Show()
        height=height+h
    end
    local function block(region,h)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT",7,-height)
        region:Show()
        height=height+h
    end
    f.heatmap:Hide()
    if f.page=="relations" then
        relationsPage(f,d.localRecord,row)
    elseif f.page=="overview" then
        overviewPage(f,d,row,block)
    elseif f.page=="combat" then
        combatPage(f,d,row)
    else
        statsPage(d,row)
    end
    for i=count+1,#f.rows do
        f.rows[i]:Hide()
    end
    f.body:SetHeight(math.max(f.scroll:GetHeight(),height))
end

local function scrollArea(f,x,y,w,h)
    local scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",x,y)
    scroll:SetSize(w,h)
    local body=CreateFrame("Frame",nil,scroll)
    body:SetSize(w,h)
    scroll:SetScrollChild(body)
    return scroll,body
end
local tabs={{"overview","Aperçu"},{"combat","Combats"},{"relations","Relations"},{"gear","Équipement"},{"talents","Talents"}}
local function build()
    local f=UI.bookWindow("GrudgeLedgerPlayerDossier","Grudge Ledger")
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
    f.portrait:SetPoint("TOPLEFT",40,-193)
    f.portrait:SetSize(64,64)
    f.portrait.raceIcon=f.portrait:CreateTexture(nil,"ARTWORK")
    f.portrait.raceIcon:SetAllPoints()
    f.portrait.classIcon=f.portrait:CreateTexture(nil,"OVERLAY")
    f.portrait.classIcon:SetSize(16,16)
    f.portrait.classIcon:SetPoint("BOTTOMRIGHT")
    f.nameLabel=UI.label(f,"","large",111,-192,193)
    GL.Safe(f.nameLabel.SetMaxLines,f.nameLabel,2)
    f.identity=UI.label(f,"",nil,111,-237,193)
    f.identity:ClearAllPoints()
    f.identity:SetPoint("TOPLEFT",f.nameLabel,"BOTTOMLEFT",0,-4)
    UI.journalFont(f.identity,"GameFontHighlight",11)
    GL.Safe(f.identity.SetMaxLines,f.identity,4)
    f.identityScroll,f.identityBody=scrollArea(f,40,-284,247,318)
    f.identityScroll.scrollBarHideable=true
    f.verdictHeading=UI.label(f.identityBody,L("Verdict"),"large",0,0,243)
    f.verdictHeading:SetTextColor(unpack(UI.theme.brass))
    f.verdict=UI.label(f.identityBody,"",nil,0,0,243)
    f.verdict:SetTextColor(unpack(UI.theme.paper))
    f.keyHeading=UI.label(f.identityBody,L("Chiffres clés"),"large",0,0,243)
    f.keyHeading:SetTextColor(unpack(UI.theme.brass))
    f.observed=UI.label(f.identityBody,"",nil,0,0,243)
    f.observed:SetTextColor(unpack(UI.theme.muted))
    f.bounty=UI.button(f,"",40,-612,247,function() GL.OpenContactBounty(f.guid) end)
    f.armoryButton=UI.button(f,L("Lien vers l’Armurerie"),40,-643,247,function()
        f.armoryLink:SetText(f.armoryURL)
        f.armoryLink:Show()
        f.armoryLink:SetFocus()
        f.armoryLink:HighlightText()
    end)
    f.armoryLink=CreateFrame("EditBox",nil,f.armoryButton,"InputBoxTemplate")
    f.armoryLink:SetSize(245,24)
    f.armoryLink:SetPoint("CENTER")
    f.armoryLink:SetAutoFocus(false)
    f.armoryLink:Hide()
    f.armoryLink:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    f.armoryLink:SetScript("OnEditFocusLost",function(self) self:Hide() end)
    f.tabs,f.rows,f.statCells={},{},{}
    for i,s in ipairs(tabs) do
        local key=s[1]
        f.tabs[key]=UI.button(f,L(s[2]),352+(i-1)*110,-156,105,function()
            f.page=key
            f.scroll:SetVerticalScroll(0)
            draw(f)
        end,true,true)
    end
    f.source=UI.label(f,"",nil,355,-196,312)
    f.source:SetTextColor(unpack(UI.theme.inkMuted))
    f.ilvl=UI.label(f,"",nil,669,-196,222)
    f.ilvl:SetJustifyH("RIGHT")
    f.ilvl:SetTextColor(unpack(UI.theme.ink))
    f.scroll,f.body=scrollArea(f,352,-225,520,408)
    f.heatmap=heatmap(f.body)
    f.expanded={}
    f.equipment=CreateFrame("Frame",nil,f)
    f.equipment:SetPoint("TOPLEFT",359,-229)
    f.equipment:SetSize(515,398)
    f.talentScroll,f.talents=scrollArea(f,352,-225,529,403)
    f.talentScroll.scrollBarHideable=true
    f.statsToggle=UI.button(f,"",352,-645,230,function()
        f.gearStats=not f.gearStats
        f.scroll:SetVerticalScroll(0)
        draw(f)
    end,nil,true)
    f.historyPrev=UI.button(f,L("Précédent"),352,-645,130,function()
        f.historyOffset=math.max(0,(f.historyOffset or 0)-40)
        f.scroll:SetVerticalScroll(0)
        draw(f)
    end,nil,true)
    f.historyNext=UI.button(f,L("Suivant"),758,-645,130,function()
        f.historyOffset=(f.historyOffset or 0)+40
        f.scroll:SetVerticalScroll(0)
        draw(f)
    end,nil,true)
    f.filters={}
    local x=671
    for _,s in ipairs(filters) do
        local key=s[1]
        f.filters[key]=UI.button(f,L(s[2]),x,-190,s[3],function()
            f.relationFilter=key
            f.historyOffset=0
            f.scroll:SetVerticalScroll(0)
            draw(f)
        end,true,true)
        x=x+s[3]+3
    end
    f.historyCount=UI.label(f,"",nil,493,-652,252)
    f.historyCount:SetJustifyH("CENTER")
    f.historyCount:SetTextColor(unpack(UI.theme.inkMuted))
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
    frame.historyOffset,frame.gearStats,frame.relationFilter,frame.expanded=0,false,"all",{}
    frame.scroll:SetVerticalScroll(0)
    frame.identityScroll:SetVerticalScroll(0)
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
