-- Reference Journal controls: real callbacks, synthetic records, no live input.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local GL, UI = GrudgeLedger, GrudgeLedger.UITheme
local methods = getmetatable(UIParent).__index
function methods:SetAlpha(value) self.alpha = value end
function methods:SetOwner(owner) self.owner = owner end
local record = GL.SetReaction(GL.IdentityFromName("Control", "Example", "Player-9-C001"), "enemy")
GL.ShowLedger(record.key)
local f = GrudgeLedgerWindow
assert(f.portraitRim:GetWidth() == 71 and f.portraitRim:GetHeight() == 72)
assert(f.reactions.warning.relationIcon:GetWidth() == 24 and f.reactions.warning.relationIcon:GetHeight() == 14)
local function event(control, name, ...)
    assert(control.scripts[name], name)(control, ...)
end
local function white(control)
    for i = 1, 3 do assert(control.caption.color[i] == 1, "hover/press text must be white") end
end
local function rest(control)
    assert(not control.hovered and not control.pressed)
    assert(control.skin.texture:match("JournalReferenceButton$"), "actions return to their light parchment face")
    for i = 1, 3 do assert(control.caption.color[i] == 0, "resting action text must be black") end
end

local function red(control)
    assert(not control.hovered and not control.pressed)
    assert(control.skin.texture:match("JournalReferenceButtonRed$"), "the primary action and the chosen opinion rest red")
    white(control)
end
assert(not f.openSheet.active, "only the chosen opinion and the open tab are red; opening the sheet rests on parchment")
assert(not f.contactBounty.active and not f.contactBounty.selection)
for _, action in ipairs({ f.openSheet, f.contactBounty }) do
    local idle = action.active and red or rest
    idle(action)
    event(action, "OnEnter")
    assert(action.skin.texture:match("JournalReferenceButtonRed$"))
    white(action)
    event(action, "OnMouseDown", "LeftButton")
    assert(action.pressed and action.skin.vertex[1] < 1)
    white(action)
    event(action, "OnMouseUp", "LeftButton")
    assert(not action.pressed and action.hovered and action.skin.vertex[1] == 1)
    white(action)
    event(action, "OnLeave")
    idle(action)
    event(action, "OnEnter")
    event(action, "OnMouseDown", "LeftButton")
    action:SetEnabled(false)
    assert(not action.hovered and not action.pressed and action.skin.vertex[1] < 1 and not GameTooltip:IsShown())
    assert(action.skin.texture:match("JournalReferenceButton$") and action.caption.color[1] < 0.5,
        "disabling either action removes the red face without losing its logical primary state")
    action:SetEnabled(true)
    idle(action)
    event(action, "OnEnter")
    action:Hide()
    action:Show()
    idle(action)
end

local reaction = f.reactions.enemy
assert(reaction.active and reaction.selection:IsShown() and reaction.selection:GetHeight() == 2)
assert(reaction.selection.color[4] == 0, "the old underline is transparent")
red(reaction)
event(reaction, "OnEnter")
UI.selectButton(reaction, false)
white(reaction)
UI.selectButton(reaction, true)
white(reaction)
event(reaction, "OnLeave")
assert(not reaction.hovered and not reaction.pressed and reaction.active)
assert(reaction.skin.texture:match("JournalReferenceButtonRed$") and reaction.selection.color[4] == 0,
    "leaving preserves the chosen red opinion without the old underline")
white(reaction)
UI.selectButton(reaction, false)
rest(reaction)
UI.selectButton(reaction, true)
red(reaction)
GL.SetReaction(record, "warning")
assert(f.detailIcon:GetWidth() == 36 and f.detailIcon:GetHeight() == 22)
assert(f.rows[1].relationIcon:GetWidth() == 20 and f.rows[1].relationIcon:GetHeight() == 12)
GL.SetReaction(record, "enemy")
assert(f.detailIcon:GetWidth() == 36 and f.detailIcon:GetHeight() == 36)
local tab = f.navigation.ledger
assert(tab.active and tab.skin.texture:match("JournalReferenceTabActive$"), "the active navigation tab remains red")
event(f.openFilters, "OnEnter")
white(f.openFilters)
assert(f.openFilters.skin.texture:match("JournalReferenceButtonRed$"))
event(f.openFilters, "OnLeave")
assert(f.openFilters.skin.texture:match("JournalReferenceDarkButton$"))

for _, pair in ipairs({ { f.previous, "DarkArrowLeft" }, { f.next, "DarkArrowRight" },
    { f.detailScroll.prev, "ArrowLeft" }, { f.detailScroll.next, "ArrowRight" } }) do
    local arrow, artwork = pair[1], pair[2]
    arrow:SetEnabled(true)
    assert(arrow.skin.texture:match("JournalReference" .. artwork .. "$"))
    assert(not arrow.caption:IsShown(), "normal artwork already contains its arrow")
    event(arrow, "OnEnter")
    assert(arrow.skin.texture:match("JournalReferenceButtonRed$") and arrow.caption:IsShown())
    white(arrow)
    event(arrow, "OnMouseDown", "LeftButton")
    event(arrow, "OnLeave")
    assert(not arrow.pressed and not arrow.caption:IsShown() and arrow.skin.texture:match(artwork .. "$"))
    event(arrow, "OnEnter")
    arrow:SetEnabled(false)
    assert(not arrow.caption:IsShown() and arrow.skin.texture:match(artwork .. "$"))
    assert(arrow.skin.alpha == 0.4, "disabled page arrows keep their artwork and fade")
    arrow:SetEnabled(true)
    assert(arrow.skin.alpha == 1, "reenabling restores the complete arrow")
end

for _, width in ipairs({ 32, 74, 123, 185 }) do
    local control = UI.button(f, "Test", 0, 0, width, nil, nil, true)
    for _, piece in ipairs(control.skinCaps) do assert(piece:GetWidth() == 12, "bevel caps do not stretch with button width") end
    event(control, "OnEnter")
    for _, piece in ipairs(control.skinCaps) do
        assert(piece:GetWidth() == 12 and piece.texture:match("JournalReferenceButtonRed$"))
    end
end
-- Owner, 23/11: no window keeps the old buttons, the small dialogs included.
local dialog = UI.button(UIParent, "Dialogue", 0, 0, 100, nil, true, true)
UI.selectButton(dialog, true)
assert(dialog.referenceSkin and dialog.skin.texture:match("JournalReferenceButtonRed$") and dialog.caption.color[1] > 0.9,
    "a dialog's chosen button is the red reference one")
local pager = UI.button(UIParent, "›", 0, 0, 30)
assert(pager.arrowTextureName == "JournalReferenceDarkArrowRight", "dialog pagers get the painted arrows")
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS reference controls: hover, press, leave, disable, hide, selections, directional arrows and fixed bevel caps")
