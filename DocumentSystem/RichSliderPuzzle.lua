local mod = dmhub.GetModLoading()

-- The [[sliderpuzzle:Name]] journal widget: the Director picks an image and a grid
--size in the annotations strip, and the page shows that image cut into tiles
--with one missing. Clicking a tile in the gap's row or column slides it (and
--any tiles between) into the gap. The board is shared: every client reads and
--writes the same shared document, so the whole table solves it together.

---@class RichSliderPuzzle: RichTag
--- @field new fun(o?: table): RichSliderPuzzle
--- @field identifier string|false
--- @field image string|false
--- @field grid number
--- @field boardWidth number
RichSliderPuzzle = RegisterGameType("RichSliderPuzzle", "RichTag")
RichSliderPuzzle.tag = "sliderpuzzle"
RichSliderPuzzle.identifier = false
RichSliderPuzzle.image = false
RichSliderPuzzle.grid = 3
RichSliderPuzzle.boardWidth = 360

--One shared document holds every puzzle's board, keyed by PuzzleKey.
local PUZZLE_DOC = "sliderpuzzles"

local MIN_GRID = 3
local MAX_GRID = 6

function RichSliderPuzzle.Create()
    return RichSliderPuzzle.new{}
end

--The board's key in the shared document: owning journal page + tag name, so
--two puzzles on different pages never share a board. Only characters that are
--legal as cloud keys survive. Nil when the tag has no owning page yet.
---@param tag RichSliderPuzzle
---@return string|nil
local function PuzzleKey(tag)
    local doc = tag:GetDocument()
    if doc == nil then
        return nil
    end
    local raw = string.format("%s_%s", tostring(doc.id), tostring(tag.identifier or "default"))
    return (string.gsub(raw, "[^%w_%-]", "_"))
end

---@param tag RichSliderPuzzle
---@return integer
local function GridSize(tag)
    local n = math.floor(tonumber(tag.grid) or 3)
    return math.max(MIN_GRID, math.min(MAX_GRID, n))
end

--Tiles are a list indexed by board position holding tile numbers 1..n*n. Tile
--n*n is the gap. Solved means tiles[i] == i everywhere.
---@param n integer
---@return integer[]
local function SolvedTiles(n)
    local tiles = {}
    for i = 1, n * n do
        tiles[i] = i
    end
    return tiles
end

---@param tiles integer[]
---@return boolean
local function IsSolved(tiles)
    for i, t in ipairs(tiles) do
        if t ~= i then
            return false
        end
    end
    return true
end

---@param tiles integer[]
---@param n integer
---@return integer
local function GapPosition(tiles, n)
    for i, t in ipairs(tiles) do
        if t == n * n then
            return i
        end
    end
    return n * n
end

--Board positions orthogonally next to pos.
---@param pos integer
---@param n integer
---@return integer[]
local function Neighbors(pos, n)
    local row = (pos - 1) // n
    local col = (pos - 1) % n
    local result = {}
    if row > 0 then result[#result + 1] = pos - n end
    if row < n - 1 then result[#result + 1] = pos + n end
    if col > 0 then result[#result + 1] = pos - 1 end
    if col < n - 1 then result[#result + 1] = pos + 1 end
    return result
end

--Scramble by making random legal moves from the solved board, which always
--leaves a solvable puzzle (a random permutation is unsolvable half the time).
--random(k) must return an integer in 1..k.
---@param n integer
---@param random fun(k: integer): integer
---@return integer[]
local function Scramble(n, random)
    local tiles = SolvedTiles(n)
    local gap = n * n
    local previous = nil
    for _ = 1, n * n * 30 do
        local options = {}
        for _, pos in ipairs(Neighbors(gap, n)) do
            --never undo the move just made, or the scramble wanders in place.
            if pos ~= previous then
                options[#options + 1] = pos
            end
        end
        local pick = options[random(#options)]
        tiles[gap], tiles[pick] = tiles[pick], tiles[gap]
        previous = gap
        gap = pick
    end
    if IsSolved(tiles) then
        local pick = Neighbors(gap, n)[1]
        tiles[gap], tiles[pick] = tiles[pick], tiles[gap]
    end
    return tiles
end

--A small seeded generator so every client computes the SAME opening scramble
--for a puzzle nobody has touched yet, without anyone having to write it first.
---@param seedText string
---@return fun(k: integer): integer
local function SeededRandom(seedText)
    local seed = 7
    for i = 1, #seedText do
        seed = (seed * 31 + string.byte(seedText, i)) % 2147483648
    end
    return function(k)
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed // 65536) % k + 1
    end
end

---@param text any
---@param n integer
---@return integer[]|nil
local function ParseTiles(text, n)
    if type(text) ~= "string" then
        return nil
    end
    local tiles = {}
    local seen = {}
    for part in string.gmatch(text, "[^,]+") do
        local t = math.tointeger(tonumber(part))
        if t == nil or t < 1 or t > n * n or seen[t] then
            return nil
        end
        seen[t] = true
        tiles[#tiles + 1] = t
    end
    if #tiles ~= n * n then
        return nil
    end
    return tiles
end

--Read this puzzle's board. A board saved for a different grid size (the
--Director changed it) is ignored and the puzzle starts over.
---@param tag RichSliderPuzzle
---@return integer[] tiles
---@return integer moves
local function ReadBoard(tag)
    local n = GridSize(tag)
    local key = PuzzleKey(tag)
    if key ~= nil then
        local entry = mod:GetDocumentSnapshot(PUZZLE_DOC).data[key]
        if type(entry) == "table" and entry.n == n then
            local tiles = ParseTiles(entry.tiles, n)
            if tiles ~= nil then
                return tiles, math.tointeger(entry.moves) or 0
            end
        end
    end
    return Scramble(n, SeededRandom(string.format("%s:%d", key or "local", n))), 0
end

--Tiles go up as a comma string rather than a list: an int-keyed list can be
--reshaped by the cloud on upload, and a string arrives exactly as written.
---@param tag RichSliderPuzzle
---@param tiles integer[]
---@param moves integer
---@param description string
local function WriteBoard(tag, tiles, moves, description)
    local key = PuzzleKey(tag)
    if key == nil then
        return
    end
    local doc = mod:GetDocumentSnapshot(PUZZLE_DOC)
    doc:BeginChange()
    doc.data[key] = {
        n = GridSize(tag),
        tiles = table.concat(tiles, ","),
        moves = moves,
    }
    doc:CompleteChange(description, {undoable = false})
end

--Slide the tile at pos toward the gap, carrying every tile between them.
--Returns false when pos is not in the gap's row or column.
---@param tiles integer[]
---@param n integer
---@param pos integer
---@return boolean
local function Slide(tiles, n, pos)
    local gap = GapPosition(tiles, n)
    if pos == gap then
        return false
    end
    local step
    if (pos - 1) // n == (gap - 1) // n then
        step = cond(pos > gap, 1, -1)
    elseif (pos - 1) % n == (gap - 1) % n then
        step = cond(pos > gap, n, -n)
    else
        return false
    end
    local cur = gap
    while cur ~= pos do
        tiles[cur] = tiles[cur + step]
        cur = cur + step
    end
    tiles[pos] = n * n
    return true
end

function RichSliderPuzzle.CreateDisplay(self)
    local m_token = nil
    local m_aspect = 1
    local m_imageInfoFor = nil
    local m_builtGrid = nil
    local m_tilePanels = {}

    local resultPanel
    local board
    local placeholder
    local statusLabel
    local directorRow
    local Refresh

    --The board's pixel height follows the image's shape, clamped so a very
    --tall or wide picture still gives clickable tiles.
    local function BoardHeight()
        return round(self.boardWidth * math.max(0.4, math.min(2.5, m_aspect)))
    end

    local function RequestImageShape()
        if self.image == m_imageInfoFor then
            return
        end
        m_imageInfoFor = self.image
        m_aspect = 1
        local requested = self.image
        if not requested then
            return
        end
        --GetImageInfo can call back more than once; only the latest image counts.
        dmhub.GetImageInfo(requested, function(info)
            if mod.unloaded or not resultPanel.valid or requested ~= self.image then
                return
            end
            if info ~= nil and info.width ~= nil and info.width > 0 then
                m_aspect = info.height / info.width
                Refresh()
            end
        end)
    end

    local function BuildTiles(n)
        m_builtGrid = n
        m_tilePanels = {}
        local children = {}
        for t = 1, n * n do
            local tileNumber = t
            local tile
            tile = gui.Panel{
                classes = {"sliderTile"},
                bgimage = "panels/square.png",
                bgcolor = "white",
                halign = "left",
                valign = "top",
                border = 1,
                borderColor = "#ffffff26",
                data = { pos = t },
                press = function(element)
                    if not self.image or m_token == nil or m_token.editor then
                        return
                    end
                    local tiles, moves = ReadBoard(self)
                    if IsSolved(tiles) then
                        return
                    end
                    if Slide(tiles, n, element.data.pos) then
                        WriteBoard(self, tiles, moves + 1, "Slide puzzle move")
                        Refresh()
                    end
                end,
            }
            m_tilePanels[tileNumber] = tile
            children[#children + 1] = tile
        end
        board.children = children
    end

    Refresh = function()
        if not resultPanel.valid then
            return
        end
        RequestImageShape()

        local hasImage = self.image and true or false
        board:SetClass("collapsed", not hasImage)
        placeholder:SetClass("collapsed", hasImage)
        directorRow:SetClass("collapsed", not dmhub.isDM or m_token == nil or m_token.player == true)
        if not hasImage then
            statusLabel.text = ""
            return
        end

        local n = GridSize(self)
        if m_builtGrid ~= n then
            BuildTiles(n)
        end

        local w = self.boardWidth
        local h = BoardHeight()
        board.selfStyle.width = w
        board.selfStyle.height = h
        resultPanel.selfStyle.width = w

        local tiles, moves = ReadBoard(self)
        local solved = IsSolved(tiles)
        local cellW = w / n
        local cellH = h / n

        for pos, t in ipairs(tiles) do
            local tile = m_tilePanels[t]
            if tile ~= nil then
                local row = (pos - 1) // n
                local col = (pos - 1) % n
                local homeRow = (t - 1) // n
                local homeCol = (t - 1) % n
                tile.data.pos = pos
                tile.bgimage = self.image
                --imageRect is in texture UVs, whose y runs bottom-up.
                tile.selfStyle.imageRect = {
                    x1 = homeCol / n,
                    x2 = (homeCol + 1) / n,
                    y1 = 1 - (homeRow + 1) / n,
                    y2 = 1 - homeRow / n,
                }
                tile.selfStyle.x = col * cellW
                tile.selfStyle.y = row * cellH
                tile.selfStyle.width = cellW
                tile.selfStyle.height = cellH
                --the gap tile stays hidden until the picture is complete.
                tile:SetClass("hidden", t == n * n and not solved)
                tile.selfStyle.borderWidth = cond(solved, 0, 1)
            end
        end

        if solved then
            statusLabel.text = cond(moves > 0, string.format("Solved in %d moves!", moves), "Solved")
        else
            statusLabel.text = string.format("Moves: %d", moves)
        end
    end

    board = gui.Panel{
        flow = "none",
        width = self.boardWidth,
        height = self.boardWidth,
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = "#00000066",
        styles = {
            { selectors = {"sliderTile", "hover"}, borderColor = "#ffffff99" },
        },
    }

    placeholder = gui.Label{
        classes = {"collapsed"},
        width = 340,
        height = 64,
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = "#00000044",
        border = 1,
        borderColor = "#99999977",
        fontSize = 14,
        color = "#aaaaaa",
        textAlignment = "center",
        text = "Slider puzzle: choose an image in the annotations strip below.",
    }

    statusLabel = gui.Label{
        classes = {"sizeS"},
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        text = "",
    }

    directorRow = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        gui.Button{
            classes = {"sizeXs"},
            text = "Shuffle",
            width = 72,
            height = 22,
            hmargin = 2,
            press = function(element)
                WriteBoard(self, Scramble(GridSize(self), math.random), 0, "Shuffle slide puzzle")
                Refresh()
            end,
        },
        gui.Button{
            classes = {"sizeXs"},
            text = "Solve",
            width = 72,
            height = 22,
            hmargin = 2,
            press = function(element)
                WriteBoard(self, SolvedTiles(GridSize(self)), 0, "Solve slide puzzle")
                Refresh()
            end,
        },
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = self.boardWidth,
        height = "auto",
        halign = "left",
        valign = "top",
        vmargin = 4,
        monitorGame = mod:GetDocumentPath(PUZZLE_DOC),
        refreshGame = function(element)
            Refresh()
        end,
        refreshTag = function(element, tag, match, token)
            self = tag or self
            m_token = token
            Refresh()
        end,
        --the annotation editors change image/grid on the tag object directly
        --with no event, so poll cheaply while a page is in edit mode.
        thinkTime = 0.5,
        think = function(element)
            if m_token ~= nil and m_token.editor then
                Refresh()
            end
        end,

        board,
        placeholder,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 26,
            tmargin = 2,
            statusLabel,
            directorRow,
        },
    }

    return resultPanel
end

function RichSliderPuzzle.CreateEditor(self)
    return gui.Panel{
        flow = "none",
        width = 96,
        height = "100%",
        refreshEditor = function(element, richTag)
            self = richTag or self
        end,
        gui.Button{
            classes = {"settingsButton", "sizeXxs"},
            halign = "right",
            valign = "top",
            press = function(element)
                if element.popup ~= nil then
                    element.popup = nil
                    return
                end
                local gridOptions = {}
                for n = MIN_GRID, MAX_GRID do
                    gridOptions[#gridOptions + 1] = { id = tostring(n), text = string.format("%d x %d", n, n) }
                end
                element.popupsInheritStyles = true
                element.popup = gui.Panel{
                    classes = {"bordered", "bg"},
                    width = "auto",
                    height = "auto",
                    flow = "vertical",
                    pad = 8,
                    borderBox = true,
                    gui.Label{
                        classes = {"sizeS"},
                        width = "auto",
                        height = "auto",
                        text = "Grid:",
                    },
                    gui.Dropdown{
                        options = gridOptions,
                        idChosen = tostring(GridSize(self)),
                        change = function(dropdown)
                            ---@cast dropdown Dropdown
                            self.grid = tonumber(dropdown.idChosen) or 3
                        end,
                    },
                    gui.Label{
                        classes = {"sizeS"},
                        width = "auto",
                        height = "auto",
                        tmargin = 6,
                        text = "Board width:",
                    },
                    gui.Slider{
                        width = 200,
                        labelWidth = 48,
                        height = 20,
                        minValue = 200,
                        maxValue = 720,
                        handleSize = "100%",
                        value = self.boardWidth,
                        change = function(slider)
                            self.boardWidth = round(slider.value)
                        end,
                    },
                }
            end,
        },
        gui.IconEditor{
            width = 64,
            height = 64,
            halign = "center",
            valign = "center",
            library = "Avatar",
            value = self.image or nil,
            change = function(element)
                self.image = element.value
            end,
        },
    }
end

MarkdownDocument.RegisterRichTag(RichSliderPuzzle)
