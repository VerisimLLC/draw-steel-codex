local mod = dmhub.GetModLoading()

-- The shell game: a game of chance (GameOfChance.lua) where the dealer hides a
-- pea under one of three cups and shuffles them. The shuffle is a real seeded
-- swap list every client replays from the same start time, so watching closely
-- genuinely tells you where the pea went; whether the dealer palms it is decided
-- by the host only when it is needed, so it cannot be read in advance.
--
-- Options (and keys 1-3) are table positions, left to right, not cups.

local DIFFICULTY = {
    easy = { swaps = 5, seconds = 4 },
    medium = { swaps = 8, seconds = 6 },
    hard = { swaps = 13, seconds = 8 },
}

--The cups and pea are the game's own art (art slots for commissioned art
--later), so they keep their colours whatever the theme.
local CUP_COLOR = "#8a5a2bff"
local CUP_RIM = "#5e3b1aff"
local CUP_SHADE = "#6f4520ff"
local PEA_COLOR = "#e2b13cff"
local TABLE_COLOR = "#2f5a34ff"

---@param data table
---@return {a: integer, b: integer}[]
local function Swaps(data)
    local result = {}
    for pair in string.gmatch(tostring(data.swaps or ""), "%d%d") do
        result[#result + 1] = { a = tonumber(string.sub(pair, 1, 1)) or 1, b = tonumber(string.sub(pair, 2, 2)) or 2 }
    end
    return result
end

--Which position each cup is at after the first n swaps: cup -> position.
---@param swaps {a: integer, b: integer}[]
---@param n integer
---@return integer[]
local function PositionsAfter(swaps, n)
    local at = { 1, 2, 3 }
    for i = 1, math.min(n, #swaps) do
        local s = swaps[i]
        for cup = 1, 3 do
            if at[cup] == s.a then
                at[cup] = s.b
            elseif at[cup] == s.b then
                at[cup] = s.a
            end
        end
    end
    return at
end

--Where the pea ended up (a position), if the dealer played it straight.
---@param data table
---@return integer
local function FinalPosition(data)
    local swaps = Swaps(data)
    local at = PositionsAfter(swaps, #swaps)
    return at[tonumber(data.pea) or 1] or 1
end

---@param data table
---@return number
local function Duration(data)
    return tonumber(data.seconds) or 6
end

local OPTIONS = { "cup 1", "cup 2", "cup 3" }

--The board: a felt table, three cups, the pea, numbers and pointer tags.
---@return Panel
local function Board()
    local m_view = nil ---@type ChanceView|nil
    local scale = 1
    local cups = {}
    local tags = {}
    local numbers = {}
    local pea
    local felt
    local note

    local CUP_W, CUP_H, SPACING, LIFT, TOP = 80, 96, 130, 48, 56

    local function SlotX(pos)
        return (20 + (pos - 1) * SPACING) * scale
    end

    local function Layout(view)
        m_view = view
        local large = view.large == true
        local newScale = cond(large, 1.5, 1)
        if newScale ~= scale then
            scale = newScale
            felt.selfStyle.width = (40 + SPACING * 2 + CUP_W) * scale
            felt.selfStyle.height = (TOP + CUP_H + 24) * scale
            for i = 1, 3 do
                cups[i].selfStyle.width = CUP_W * scale
                cups[i].selfStyle.height = CUP_H * scale
            end
            pea.selfStyle.width = 34 * scale
            pea.selfStyle.height = 34 * scale
        end

        local data = view.data
        --cup -> {x position (fractional), lift, opacity}
        local place = {}
        local peaCup = nil
        local peaShown = false
        if data == nil then
            for cup = 1, 3 do
                place[cup] = { pos = cup, lift = 0, alpha = 1 }
            end
        else
            local swaps = Swaps(data)
            peaCup = tonumber(data.pea) or 1
            if view.countdown ~= nil then
                --before the deal: show everyone where the pea starts.
                for cup = 1, 3 do
                    place[cup] = { pos = cup, lift = cond(cup == peaCup, 1, 0), alpha = 1 }
                end
                peaShown = true
            elseif view.t ~= nil and not view.viewDone then
                local per = Duration(data) / math.max(1, #swaps)
                local k = math.floor(view.t / per)
                local f = (view.t - k * per) / per
                local before = PositionsAfter(swaps, k)
                local after = PositionsAfter(swaps, k + 1)
                for cup = 1, 3 do
                    local a, b = before[cup], after[cup]
                    if a == b then
                        place[cup] = { pos = a, lift = 0, alpha = 1, arc = 0 }
                    elseif view.reduceMotion then
                        --no sliding: the two cups fade out and back in, swapped.
                        place[cup] = { pos = cond(f < 0.5, a, b), lift = 0, alpha = math.abs(1 - 2 * f) }
                    else
                        local eased = (1 - math.cos(math.pi * f)) / 2
                        place[cup] = { pos = a + (b - a) * eased, lift = 0, alpha = 1, arc = cond(a < b, 1, -1) * math.sin(math.pi * f) }
                    end
                end
            else
                local final = PositionsAfter(swaps, #swaps)
                local reveal = view.reveal
                for cup = 1, 3 do
                    local lift = 0
                    if reveal ~= nil and (view.phase == "revealed" or view.phase == "over") then
                        lift = 1
                    end
                    place[cup] = { pos = final[cup], lift = lift, alpha = 1 }
                end
                if reveal ~= nil and not reveal.cheated and (view.phase == "revealed" or view.phase == "over") then
                    peaShown = true
                end
            end
        end

        for cup = 1, 3 do
            local p = place[cup]
            local element = cups[cup]
            element.x = SlotX(p.pos)
            element.y = (TOP - p.lift * LIFT + (p.arc or 0) * 14) * scale
            element.selfStyle.opacity = p.alpha
            element.data.pos = math.floor(p.pos + 0.5)
            element:SetClass("pointed", view.myPoint ~= nil and view.myPoint == element.data.pos and view.viewDone)
        end

        if peaShown and peaCup ~= nil and place[peaCup] ~= nil then
            pea:SetClass("hidden", false)
            pea.x = SlotX(place[peaCup].pos) + (CUP_W / 2 - 17) * scale
            pea.y = (TOP + CUP_H - 34) * scale
        else
            pea:SetClass("hidden", true)
        end

        local cheated = view.reveal ~= nil and view.reveal.cheated and (view.phase == "revealed" or view.phase == "over")
        note.text = cond(cheated, "No pea under any cup -- the dealer palmed it!", "")
        note:SetClass("collapsed", not cheated)

        for pos = 1, 3 do
            local names = view.pointers[pos] or {}
            tags[pos].text = table.concat(names, "\n")
            numbers[pos].text = string.format("%d", pos)
            numbers[pos]:SetClass("bold", view.myPoint == pos)
        end
    end

    for cup = 1, 3 do
        cups[cup] = gui.Panel{
            classes = {"shellCup"},
            bgimage = "panels/square.png",
            bgcolor = CUP_COLOR,
            width = CUP_W,
            height = CUP_H,
            halign = "left",
            valign = "top",
            flow = "vertical",
            data = { pos = cup },
            styles = {
                { selectors = {"shellCup"}, border = 2, borderColor = CUP_RIM },
                { selectors = {"shellCup", "hover"}, brightness = 1.25 },
                { selectors = {"shellCup", "pointed"}, borderColor = "#ffffffff", border = 3 },
            },
            click = function(element)
                if m_view ~= nil then
                    m_view.choose(element.data.pos)
                end
            end,
            gui.Panel{
                bgimage = "panels/square.png",
                bgcolor = CUP_SHADE,
                width = "60%",
                height = 10,
                halign = "center",
                valign = "top",
                tmargin = 8,
                interactable = false,
            },
            gui.Panel{
                bgimage = "panels/square.png",
                bgcolor = CUP_RIM,
                width = "100%",
                height = 12,
                halign = "center",
                valign = "bottom",
                interactable = false,
            },
        }
    end

    pea = gui.Panel{
        classes = {"hidden"},
        bgimage = "phosphor/coin.png",
        bgcolor = PEA_COLOR,
        width = 34,
        height = 34,
        halign = "left",
        valign = "top",
        interactable = false,
    }

    note = gui.Label{
        classes = {"sizeM", "bold", "collapsed"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "bottom",
        textAlignment = "center",
        bmargin = 6,
        interactable = false,
        text = "",
    }

    --the pea first, so a lowered cup covers it.
    local tableChildren = { pea }
    for cup = 1, 3 do
        tableChildren[#tableChildren + 1] = cups[cup]
    end
    tableChildren[#tableChildren + 1] = note

    felt = gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = TABLE_COLOR,
        width = 40 + SPACING * 2 + CUP_W,
        height = TOP + CUP_H + 24,
        halign = "left",
        flow = "none",
        children = tableChildren,
    }

    local labelRow = {}
    for pos = 1, 3 do
        numbers[pos] = gui.Label{
            classes = {"sizeM"},
            width = "100%",
            height = "auto",
            textAlignment = "center",
            text = tostring(pos),
        }
        tags[pos] = gui.Label{
            classes = {"sizeS"},
            width = "100%",
            height = "auto",
            textAlignment = "center",
            text = "",
        }
        local p = pos
        labelRow[pos] = gui.Panel{
            flow = "vertical",
            width = SPACING,
            height = "auto",
            valign = "top",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            click = function(element)
                if m_view ~= nil then
                    m_view.choose(p)
                end
            end,
            numbers[pos],
            tags[pos],
        }
    end

    local labels = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        lmargin = 20 + CUP_W / 2 - SPACING / 2,
        children = labelRow,
    }

    return gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        vmargin = 6,
        chanceView = function(element, view)
            Layout(view)
            labels.selfStyle.lmargin = (20 + CUP_W / 2 - SPACING / 2) * scale
            for pos = 1, 3 do
                labelRow[pos].selfStyle.width = SPACING * scale
            end
        end,
        felt,
        labels,
    }
end

GameOfChance.Register{
    id = "shellgame",
    name = "Shell game",
    perception = "inu",
    test = {
        id = "follow",
        label = "Watch closely",
        skill = "Alertness",
        Success = function(data)
            return string.format("It ended under cup %d", FinalPosition(data))
        end,
    },
    cheatText = "the dealer palmed the pea",
    DealRound = function(config, random, difficulty)
        local d = DIFFICULTY[difficulty] or DIFFICULTY.medium
        local choices = { "12", "23", "13" }
        local swaps = {}
        for i = 1, d.swaps do
            swaps[i] = choices[random(3)]
        end
        --a string, not a list: lists are uploaded whole.
        return { pea = random(3), swaps = table.concat(swaps, ","), seconds = d.seconds }
    end,
    Duration = Duration,
    Options = function(data)
        return OPTIONS
    end,
    Judge = function(data, option, cheated)
        if cheated then
            return "lose"
        end
        return cond(option == FinalPosition(data), "win", "lose")
    end,
    Board = Board,
}
