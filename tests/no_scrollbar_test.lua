-- Owner rule: never a scroll bar nor a carousel anywhere. Long texts turn pages like a book
-- (UI.textPages); a text box being typed in (notes, diagnostic) has no bar either, only the wheel.
-- This check reads the sources; it fails as soon as a scroll bar template comes back.
local function read(path)
    local file = assert(io.open(path, "rb"), "missing file: " .. path)
    local text = file:read("*a")
    file:close()
    return text
end
local forbidden = { "ScrollFrameTemplate", "FauxScrollFrame", "HybridScroll", "ScrollBox", "ScrollBarTemplate", "MinimalScrollBar" }
local files, checked = {}, 0
for line in read(TEST_ROOT .. "/GrudgeLedger.toc"):gmatch("[^\r\n]+") do
    local name = line:match("^%s*([%w_]+%.lua)%s*$")
    if name then files[#files + 1] = name end
end
for _, name in ipairs(files) do
    local text = read(TEST_ROOT .. "/" .. name)
    for _, word in ipairs(forbidden) do
        assert(not text:find(word, 1, true), name .. " uses " .. word .. ": use UI.textPages (pages) instead of a scroll bar")
    end
    local frames, wheels = 0, 0
    for _ in text:gmatch('CreateFrame%("ScrollFrame"') do frames = frames + 1 end
    for _ in text:gmatch("UI%.wheelScroll%(") do wheels = wheels + 1 end
    assert(frames <= wheels, name .. ": every ScrollFrame is a bare text box moved by UI.wheelScroll, never a list")
    for slider in text:gmatch('CreateFrame%("Slider".-\n.-\n.-\n.-\n.-\n') do
        assert(slider:find('"HORIZONTAL"', 1, true), name .. ": a slider is a setting value, never a vertical scroll bar")
    end
    checked = checked + 1
end
assert(checked > 20, "the TOC lists the addon files")

-- At run time: the paged texts keep whole lines and show their arrows only when needed.
local mock = assert(loadfile(TEST_WORK .. "/tests/addon_mock.lua"))()
local UI = GrudgeLedger.UITheme
local parent = CreateFrame("Frame")
local pages = UI.textPages(parent, 300, 90)
pages:SetText("Une ligne")
assert(#pages.pages == 1 and not pages.next:IsShown() and not pages.prev:IsShown(), "one page shows no arrows")
local lines = {}
for i = 1, 40 do lines[i] = "Ligne " .. i end
pages:SetText(table.concat(lines, "\n"))
assert(#pages.pages > 1 and pages.next:IsShown() and pages.pageLabel:GetText() == "1 / " .. #pages.pages)
local seen = {}
for i = 1, #pages.pages do
    for line in (pages.pages[i] .. "\n"):gmatch("(.-)\n") do seen[#seen + 1] = line end
end
assert(table.concat(seen, "\n") == table.concat(lines, "\n"), "no line is lost or cut between pages")
pages.next.scripts.OnClick(pages.next, "LeftButton")
assert(pages.page == 2 and pages.body:GetText() == pages.pages[2])
pages:SetText(table.concat(lines, "\n"), true)
assert(pages.page == 2, "a refresh keeps the page")
pages:SetText("Court", true)
assert(pages.page == 1 and pages.fullText == "Court")
print("PASS no scroll bar: no scroll template in " .. checked .. " files, bare text boxes only, whole lines per page")
