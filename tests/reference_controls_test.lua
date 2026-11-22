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
local action = f.openSheet
assert(action.active, "opening the sheet is the one primary action, filled red as on the reference")
red(action)
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
red(action)
event(action, "OnEnter")
event(action, "OnMouseDown", "LeftButton")
action:SetEnabled(false)
assert(not action.hovered and not action.pressed and action.skin.texture:match("JournalReferenceButton$"))
assert(action.skin.vertex[1] < 1 and action.caption.color[1] < 0.5 and not GameTooltip:IsShown())
action:SetEnabled(true)
red(action)
event(action, "OnEnter")
action:Hide()
action:Show()
red(action)

local reaction = f.reactions.enemy
assert(reaction.active and reaction.selection:IsShown())
red(reaction)
event(reaction, "OnEnter")
UI.selectButton(reaction, false)
white(reaction)
UI.selectButton(reaction, true)
white(reaction)
event(reaction, "OnLeave")
red(reaction)
UI.selectButton(reaction, false)
rest(reaction)
UI.selectButton(reaction, true)
assert(reaction.active and reaction.selection:IsShown(), "leaving keeps the chosen opinion red")
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
end

for _, width in ipairs({ 32, 74, 123, 185 }) do
    local control = UI.button(f, "Test", 0, 0, width, nil, nil, true)
    for _, piece in ipairs(control.skinCaps) do assert(piece:GetWidth() == 12, "bevel caps do not stretch with button width") end
    event(control, "OnEnter")
    for _, piece in ipairs(control.skinCaps) do
        assert(piece:GetWidth() == 12 and piece.texture:match("JournalReferenceButtonRed$"))
    end
end
local legacy = UI.button(UIParent, "Legacy", 0, 0, 100, nil, true, true)
UI.selectButton(legacy, true)
assert(legacy.skin.texture:match("JournalButtons$") and legacy.selection:IsShown() and legacy.caption.color[1] > 0.9,
    "other pages retain their legacy selection and colors")
assert(#GL.errors == 0, (GL.errors[1] or {}).text)
print("PASS reference controls: hover, press, leave, disable, hide, selections, directional arrows and fixed bevel caps")
