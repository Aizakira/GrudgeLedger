-- Real alerts follow the chat without becoming its children; custom-chat clients
-- lacking the native frame still get a lower-left alert, never a central popup.
for _, withChat in ipairs({ true, false }) do
    local mock = assert(loadfile(TEST_WORK .. "/tests/wow_mock.lua"))()
    local methods = getmetatable(UIParent).__index
    function methods:SetPoint(...) self.anchor = { ... } end
    function methods:SetClampedToScreen(value) self.clamped = value end
    function methods:SetVertexColor(...) self.vertex = { ... } end
    ChatFrame1 = withChat and CreateFrame("Frame", "ChatFrame1", UIParent) or nil
    if ChatFrame1 then ChatFrame1:Hide() end
    GrudgeLedgerDB = nil
    assert(loadfile(TEST_ROOT .. "/Core.lua"))("GrudgeLedger")
    assert(loadfile(TEST_ROOT .. "/Display.lua"))()
    local GL = GrudgeLedger
    GL.InitDB()
    GL.SetReaction(GL.Identity("target"), "enemy")
    GL.Display.OnEvent(nil, "PLAYER_TARGET_CHANGED")
    local alert = assert(GrudgeLedgerNearbyAlert)
    local point, relative, relativePoint, x, y = unpack(alert.anchor)
    assert(alert:IsShown() and alert.parent == UIParent and alert.clamped,
        "hiding chat must not hide its alert, and the alert must stay on screen")
    assert(point == "BOTTOMLEFT")
    if withChat then
        assert(relative == ChatFrame1 and relativePoint == "TOPLEFT" and x == 0 and y == 96,
            "native anchoring must follow chat moves/resizes, with space above its tabs")
    else
        assert(relative == UIParent and relativePoint == "BOTTOMLEFT" and x == 24 and y == 320)
    end
    assert(#GL.errors == 0)
    for _, frame in ipairs(mock.frames) do if frame.name then _G[frame.name] = nil end end
    GrudgeLedgerNearbyAlert = nil
end
print("PASS alert position: above chat, independent visibility, screen clamp and lower-left fallback")
