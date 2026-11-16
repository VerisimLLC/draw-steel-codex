-- Symbols shared by puzzle types: the ten named runes (combination lock, warded seal) and
-- the warded seal's thread colours and patterns. Loading this file runs no engine code, so
-- the ward generator's offline tests can load it with the bundled lua.exe.

PuzzleRunes = {}

--The runes, in a fixed order: puzzles store a rune as its index here. Placeholder phosphor
--icons; swap the art here and every puzzle using runes picks it up.
PuzzleRunes.list = {
    { name = "Flame", icon = "phosphor/flame-fill.png" },
    { name = "Eye", icon = "phosphor/eye-fill.png" },
    { name = "Key", icon = "phosphor/key-fill.png" },
    { name = "Moon", icon = "phosphor/moon-fill.png" },
    { name = "Sun", icon = "phosphor/sun-fill.png" },
    { name = "Skull", icon = "phosphor/skull-fill.png" },
    { name = "Star", icon = "phosphor/star-fill.png" },
    { name = "Sword", icon = "phosphor/sword-fill.png" },
    { name = "Crown", icon = "phosphor/crown-simple-fill.png" },
    { name = "Hourglass", icon = "phosphor/hourglass-fill.png" },
}

---@param i integer
---@return string
function PuzzleRunes.Name(i)
    local r = PuzzleRunes.list[i]
    return r ~= nil and r.name or "?"
end

--Thread colours: the Okabe-Ito colour-blind-safe set, each with a name the hands reads
--out. Threads never rely on colour alone (see patterns).
PuzzleRunes.threadColours = {
    { name = "Crimson", color = "#D55E00ff" },
    { name = "Amber", color = "#E69F00ff" },
    { name = "Gold", color = "#F0E442ff" },
    { name = "Jade", color = "#009E73ff" },
    { name = "Azure", color = "#56B4E9ff" },
    { name = "Rose", color = "#CC79A7ff" },
}

PuzzleRunes.threadPatterns = {
    { name = "solid" },
    { name = "dashed", segment = 22, gap = 10 },
    { name = "dotted", segment = 8, gap = 8 },
}

--A thread drawn as a row of segments: one bar when solid.
---@param colour integer index into threadColours
---@param pattern integer index into threadPatterns
---@param width number
---@param thickness number
---@return Panel
function PuzzleRunes.ThreadPanel(colour, pattern, width, thickness)
    local c = PuzzleRunes.threadColours[colour] or PuzzleRunes.threadColours[1]
    local p = PuzzleRunes.threadPatterns[pattern] or PuzzleRunes.threadPatterns[1]
    local segments = {}
    if p.segment == nil then
        segments[1] = gui.Panel{ bgimage = "panels/square.png", bgcolor = c.color, width = width, height = thickness, valign = "center", interactable = false }
    else
        local scale = thickness / 8
        local seg = math.max(2, math.floor(p.segment * scale))
        local gap = math.max(2, math.floor(p.gap * scale))
        for _ = 1, math.max(1, math.floor(width / (seg + gap))) do
            segments[#segments + 1] = gui.Panel{ bgimage = "panels/square.png", bgcolor = c.color, width = seg, height = thickness, rmargin = gap, valign = "center", interactable = false }
        end
    end
    return gui.Panel{ flow = "horizontal", width = width, height = thickness * 2.5, valign = "center", interactable = false, children = segments }
end
