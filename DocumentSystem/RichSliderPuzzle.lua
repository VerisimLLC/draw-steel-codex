local mod = dmhub.GetModLoading()

-- The slider puzzle type: an image cut into tiles with one missing. Clicking a
-- tile in the gap's row or column slides it (and any tiles between) into the
-- gap. Registered with the puzzle framework (PuzzleFramework.lua), which owns
-- storage, the solved banner and the Director controls.
--
-- Also the old [[sliderpuzzle:Name]] journal tag: it now shows a framework
-- puzzle, copying its setup and saved board across the first time it is opened.

local MIN_GRID = 3
local MAX_GRID = 6

---@param config table
---@return integer
local function GridSize(config)
    local n = math.floor(tonumber(config.grid) or 3)
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
local function TilesSolved(tiles)
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
    if TilesSolved(tiles) then
        local pick = Neighbors(gap, n)[1]
        tiles[gap], tiles[pick] = tiles[pick], tiles[gap]
    end
    return tiles
end

--Tiles are stored as a comma string: a Lua list would be uploaded whole, and a
--string arrives exactly as written.
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

---@param state table
---@param n integer
---@return integer[]
local function StateTiles(state, n)
    return ParseTiles(state.tiles, n) or SolvedTiles(n)
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

---@param ctx PuzzleContext
---@return Panel
local function Render(ctx)
    local m_ctx = ctx
    local m_aspect = 1
    local m_imageInfoFor = nil
    local m_builtGrid = nil
    local m_tilePanels = {} ---@type Panel[]

    local resultPanel
    local board
    local placeholder
    local Layout

    local function RequestImageShape()
        local image = m_ctx.config.image
        if image == m_imageInfoFor then
            return
        end
        m_imageInfoFor = image
        m_aspect = 1
        if not image then
            return
        end
        --GetImageInfo can call back more than once; only the latest image counts.
        dmhub.GetImageInfo(image, function(info)
            if mod.unloaded or not resultPanel.valid or image ~= m_ctx.config.image then
                return
            end
            if info ~= nil and info.width ~= nil and info.width > 0 then
                m_aspect = info.height / info.width
                Layout()
            end
        end)
    end

    local function BuildTiles(n)
        m_builtGrid = n
        m_tilePanels = {}
        local children = {}
        for t = 1, n * n do
            local tile = gui.Panel{
                classes = {"sliderTile"},
                bgimage = "panels/square.png",
                bgcolor = "white",
                halign = "left",
                valign = "top",
                border = 1,
                borderColor = "#ffffff26",
                data = { pos = t },
                press = function(element)
                    if m_ctx.readonly or not m_ctx.config.image then
                        return
                    end
                    local pos = element.data.pos
                    m_ctx:Change(function(state, config)
                        local size = GridSize(config)
                        local tiles = StateTiles(state, size)
                        if not Slide(tiles, size, pos) then
                            return false
                        end
                        state.tiles = table.concat(tiles, ",")
                        state.moves = (math.tointeger(state.moves) or 0) + 1
                    end, "Slide puzzle move")
                end,
                gui.Label{
                    classes = {"hidden", "sizeL", "bold"},
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    interactable = false,
                    text = tostring(t),
                },
            }
            m_tilePanels[t] = tile
            children[#children + 1] = tile
        end
        board.children = children
    end

    Layout = function()
        if not resultPanel.valid then
            return
        end
        local ctx = m_ctx
        local config = ctx.config
        RequestImageShape()
        local hasImage = config.image and true or false
        board:SetClass("collapsed", not hasImage)
        placeholder:SetClass("collapsed", hasImage)
        if not hasImage or ctx.state == nil then
            return
        end

        local n = GridSize(config)
        if m_builtGrid ~= n then
            BuildTiles(n)
        end

        local w = tonumber(config.boardWidth) or 360
        local h = round(w * math.max(0.4, math.min(2.5, m_aspect)))
        board.selfStyle.width = w
        board.selfStyle.height = h
        resultPanel.selfStyle.width = w

        local tiles = StateTiles(ctx.state, n)
        local solved = TilesSolved(tiles) or ctx.solved
        local numbers = ctx:Assist("numbers")
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
                tile.bgimage = config.image
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
                tile.children[1]:SetClass("hidden", not numbers or solved)
            end
        end
    end

    board = gui.Panel{
        flow = "none",
        width = 360,
        height = 360,
        halign = "left",
        bgimage = "panels/square.png",
        bgcolor = "#00000066",
        styles = {
            { selectors = {"sliderTile", "hover"}, borderColor = "#ffffff99" },
        },
    }

    placeholder = gui.Label{
        classes = {"collapsed", "sizeS", "bordered"},
        width = 340,
        height = 64,
        halign = "left",
        textAlignment = "center",
        text = "Slider puzzle: choose an image in the annotations strip below.",
    }

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        refreshPuzzle = function(element, ctx)
            m_ctx = ctx
            Layout()
        end,
        board,
        placeholder,
    }
    return resultPanel
end

local gridOptions = {}
for n = MIN_GRID, MAX_GRID do
    gridOptions[#gridOptions + 1] = { id = tostring(n), text = string.format("%d x %d", n, n) }
end

PuzzleType.Register{
    id = "slider",
    name = "Slider puzzle",
    fields = {
        { id = "image", type = "image", label = "Image", default = false },
        { id = "grid", type = "choice", label = "Grid", default = "3", options = gridOptions },
        { id = "boardWidth", type = "number", label = "Board width", default = 360, min = 200, max = 720 },
    },
    assists = {
        { id = "numbers", label = "Show tile numbers" },
    },
    ConfigKey = function(config)
        return tostring(GridSize(config))
    end,
    NewState = function(config, ctx)
        local n = GridSize(config)
        return { n = n, tiles = table.concat(Scramble(n, ctx.random), ","), moves = 0 }
    end,
    IsSolved = function(state, config)
        local n = GridSize(config)
        local tiles = ParseTiles(state.tiles, n)
        return tiles ~= nil and TilesSolved(tiles)
    end,
    SolvedState = function(config)
        local n = GridSize(config)
        return { n = n, tiles = table.concat(SolvedTiles(n), ","), moves = 0 }
    end,
    Status = function(state, config)
        return string.format("Moves: %d", math.tointeger(state.moves) or 0)
    end,
    Render = Render,
}

--------------------------------------------------------------------------------
-- The legacy [[sliderpuzzle:Name]] tag
--------------------------------------------------------------------------------

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

--Where boards were saved before the framework: one document, keyed by page + name.
local LEGACY_DOC = "sliderpuzzles"
local ID_PREFIX = "s_"

function RichSliderPuzzle.Create()
    return RichSliderPuzzle.new{}
end

--First open of an old tag: copy its setup (stored on the tag) and its saved
--board (in the old shared document) into a framework puzzle.
---@param tag RichSliderPuzzle
---@param id string|nil
local function Migrate(tag, id)
    if id == nil or Puzzle.Exists(id) then
        return
    end
    local n = GridSize(tag)
    Puzzle.Create(id, "slider", {
        image = tag.image or false,
        grid = tostring(n),
        boardWidth = tag.boardWidth,
    }, tag.identifier and tostring(tag.identifier) or nil)

    local doc = tag:GetDocument()
    local docid = doc ~= nil and doc:try_get("id") or nil
    if docid == nil then
        return
    end
    local oldKey = Puzzle.SafeId(string.format("%s_%s", tostring(docid), tostring(tag.identifier or "default")))
    local entry = mod:GetDocumentSnapshot(LEGACY_DOC).data[oldKey]
    if type(entry) == "table" and entry.n == n and ParseTiles(entry.tiles, n) ~= nil then
        local tiles = ParseTiles(entry.tiles, n) --[[@as integer[] ]]
        local solved = TilesSolved(tiles)
        Puzzle.ImportState(id, { n = n, tiles = entry.tiles, moves = math.tointeger(entry.moves) or 0 },
            cond(solved, { solved = true, solvedBy = "director", announced = true }, nil))
    end
end

function RichSliderPuzzle.CreateDisplay(self)
    local m_token = nil
    local panel = Puzzle.CreatePanel(nil, {
        editing = function() return m_token ~= nil and m_token.editor == true end,
    })
    return gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        refreshTag = function(element, tag, match, token)
            self = tag or self
            m_token = token
            local id = Puzzle.JournalId(self, ID_PREFIX)
            Migrate(self, id)
            Puzzle.IndexJournal(self, id)
            panel:FireEvent("setPuzzle", id)
            panel:FireEvent("refreshPuzzleFrame")
        end,
        panel,
    }
end

function RichSliderPuzzle.CreateEditor(self)
    return Puzzle.CreateEditor(function()
        local id = Puzzle.JournalId(self, ID_PREFIX)
        Migrate(self, id)
        return id
    end, function(id, typeid)
        Puzzle.Create(id, typeid, nil, self.identifier and tostring(self.identifier) or nil)
    end, function(tag) self = tag end)
end

MarkdownDocument.RegisterRichTag(RichSliderPuzzle)
