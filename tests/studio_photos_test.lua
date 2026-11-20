-- Avatar Replay Lab photos on the sheet (three-level strategy): the bust in the identity column;
-- on the equipment stage, the live model when visible, then the studio poses, then the outfit.
local mock=assert(loadfile(TEST_WORK.."/tests/addon_mock.lua"))()
local GL=GrudgeLedger
local function click(b) b.scripts.OnClick(b,"LeftButton") end
local id=GL.IdentityFromName("Photo","Subject","Player-9-00F0")
GL.Remember(id)
local guid=id.guid
assert(GL.StudioPhotos(guid)==nil,"nothing without the Lab")
assert(GL.OpenPlayerDossier(guid,nil,nil,"gear"))
local f=GrudgeLedgerPlayerDossier
local view=f.equipment.equipment
assert(not f.portrait.photo:IsShown() and f.portrait.raceIcon:IsShown() and not view.photo:IsShown())

-- The Lab is installed and has photographed this player (example paths).
local base="Interface\AddOns\AvatarReplayLab\Studio\\"..guid
AvatarReplayLabPhotos={Get=function(g)
    if g~=guid then return end
    return {at=1794400000,bust=base.."-buste",poses={recherche=base.."-recherche",combat=base.."-combat",moqueur=base.."-moqueur"},
        order={"recherche","combat","moqueur"}}
end}
assert(GL.OpenPlayerDossier(guid,nil,nil,"gear"))
assert(f.portrait.photo:IsShown() and f.portrait.photo.texture==base.."-buste" and not f.portrait.raceIcon:IsShown())
assert(view.photo:IsShown() and view.photo.texture==base.."-recherche","the wanted pose comes first")
assert(view.caption:GetText():find("Photo du studio",1,true) and not view.face:IsShown())
click(view.photoButton)
assert(view.photo.texture==base.."-combat")
click(view.photoButton)
click(view.photoButton)
assert(view.photo.texture==base.."-recherche","the poses cycle")
-- A broken Lab never breaks the sheet.
AvatarReplayLabPhotos={Get=function() error("broken") end}
assert(GL.OpenPlayerDossier(guid,nil,nil,"gear"))
assert(not f.portrait.photo:IsShown() and not view.photo:IsShown())
AvatarReplayLabPhotos=nil
assert(#GL.errors==0,(GL.errors[1] or {}).text)
print("PASS studio photos: bust in the identity column, wanted pose first on the equipment stage, click cycles poses, "
    .."nothing without the Lab, a broken Lab is ignored")
