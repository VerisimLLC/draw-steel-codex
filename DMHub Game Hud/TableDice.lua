local mod = dmhub.GetModLoading()

--Table dice (TABLE_DICE_BRIEF.md at the repo root): 3D dice the Director puts
--on the tabletop that stay there. Anyone can click one to roll it in place, or
--drag it and let go fast to throw it; it rests on whatever face it lands on.
--No chat message: it is a fidget roll.
--
--The engine draws, picks and animates each die (dice.CreateTableDie,
--TableDieLua). This file decides which dice exist and keeps everyone in step:
--  - Dice out on the table live in the shared document "tabledice". A roll is
--    written there as a small record (from, to, face, seed...) that the other
--    clients replay; a late joiner just sees the resting face.
--  - Dice behind the Director's Screen are the Director's alone: they live in
--    a per-game preference, so players' machines never receive them, and show
--    only while the screen is open.
--  - Spots are kept as fractions of the table, so every screen puts a die in
--    the same place on its own table.
--The Director adds dice from the dice button on the table (bottom left) or on
--the Director's Screen (beside its caption); right-click a die to roll or
--remove it.

TableDice = {}

local DOC_ID = "tabledice"

--The Director's private dice, as JSON {dice = {[id] = record}}.
local g_privateSetting = setting{
    id = "tabledice:private",
    storage = "pergamepreference",
    default = "",
}

--Dev gate for the Director's tray (the Table items drawer and its two
--buttons). No editor entry, so it never shows in the settings UI; toggle
--from chat with /toggle dev:directortray. Things already on the table show
--for everyone either way.
TableDice.traySetting = setting{
    id = "dev:directortray",
    default = false,
    storage = "preference",
}

--- Whether this user gets the tray: the Director, with dev:directortray on.
--- @return boolean
function TableDice.TrayEnabled()
    return dmhub.isDM and TableDice.traySetting:Get() == true
end

--The dice set new dice wear ("" = the default set).
local g_setSetting = setting{
    id = "tabledice:set",
    storage = "pergamepreference",
    default = "",
}

--- @class TableDieRecord
--- @field faces number
--- @field model string
--- @field fx number spot, as a fraction of the table's width
--- @field fy number spot, as a fraction of the table's height
--- @field face number
--- @field yaw number
--- @field pick number
--- @field seq number bumped on every change, so clients see what is new
--- @field roll nil|table the latest roll, in table fractions
--- @field rollAt nil|number dmhub.serverTime when it started
--- @field rollBy nil|string who rolled it

local g = {
    --id -> {die = TableDieLua, seq = number, private = boolean}
    handles = {},
    layer = nil,
    tableButton = nil,
    menuAnchor = nil,
    --ids of rolls this client started and wrote, so it does not replay them.
    ownSeq = {},
    --id -> {figure = TableFigureLua, seq = number, private = boolean, blob = string}
    figures = {},
    --id -> tracker handle (BuildTracker). Their panels sit in the documents
    --layer with the windows (TrackerLayers): shared ones in trackerLayer,
    --under everything; the Director's private ones in trackerScreenLayer,
    --over the Director's Screen.
    trackers = {},
    trackerLayer = nil,
    trackerScreenLayer = nil,
    --- @type Panel|nil the table pass's image (TrackerLayers)
    tableImage = nil,
    --- @type number|nil the image's crop, as last set
    tableImageCrop = nil,
}

----------------------------------------------------------------------
--Where things are: table fractions <-> screen pixels (top-left origin).

--- @return number w, number h the table's size (documents-layer units)
local function TableSize()
    local rect = Tabletop.LayerRect()
    return rect.w, rect.h
end

--- @return number scale layer units per screen pixel
--- @return number top the table's top, in screen pixels
local function Mapping()
    local _, h = TableSize()
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if below.y <= 0 then
        return 1, 0
    end
    return h / below.y, screen.y - below.y
end

--- @return number fx, number fy
local function ScreenToTable(px, py)
    local w, h = TableSize()
    local scale, top = Mapping()
    return (px * scale) / math.max(1, w), ((py - top) * scale) / math.max(1, h)
end

--- @return number px, number py
local function TableToScreen(fx, fy)
    local w, h = TableSize()
    local scale, top = Mapping()
    return (fx * w) / scale, top + (fy * h) / scale
end

--Throws stay on the table (screen pixels).
--- @return number x1, number y1, number x2, number y2
local function TableBounds()
    local w, h = TableSize()
    local scale, top = Mapping()
    return 0, top, w / scale, top + h / scale
end

----------------------------------------------------------------------
--The two stores.

local function SharedDoc()
    return mod:GetDocumentSnapshot(DOC_ID)
end

--Both stores hold two kinds of thing: "dice" and "figures" (TableFigures).
--- @param kind? string
--- @return table<string, table>
local function SharedItems(kind)
    local items = SharedDoc().data[kind or "dice"]
    if type(items) ~= "table" then
        return {}
    end
    return items
end

--- @return table<string, TableDieRecord>
local function SharedDice()
    return SharedItems("dice")
end

--The private store, as {dice = {...}, figures = {...}}.
--- @return table
local function ReadPrivate()
    local text = g_privateSetting:Get()
    if type(text) ~= "string" or text == "" then
        return {}
    end
    local parsed = dmhub.FromJson(text)
    if parsed == nil or type(parsed.result) ~= "table" then
        return {}
    end
    return parsed.result
end

--- @param kind? string
--- @return table<string, table>
local function PrivateItems(kind)
    local items = ReadPrivate()[kind or "dice"]
    if type(items) ~= "table" then
        return {}
    end
    return items
end

--- @return table<string, TableDieRecord>
local function PrivateDice()
    return PrivateItems("dice")
end

--- @param items table<string, table>
--- @param kind? string
local function SavePrivate(items, kind)
    local all = ReadPrivate()
    all[kind or "dice"] = items
    g_privateSetting:Set(dmhub.ToJson(all))
end

--Changes one record in its store: fn(record) edits it in place, or returns
--false to remove it.
--- @param id string
--- @param private boolean
--- @param description string
--- @param fn fun(record: table): nil|boolean
--- @param kind? string
local function Modify(id, private, description, fn, kind)
    kind = kind or "dice"
    if private then
        local items = PrivateItems(kind)
        local record = items[id]
        if record == nil then
            return
        end
        if fn(record) == false then
            items[id] = nil
        end
        SavePrivate(items, kind)
        return
    end
    local doc = SharedDoc()
    doc:BeginChange()
    doc.data[kind] = doc.data[kind] or {}
    local record = doc.data[kind][id]
    if record ~= nil then
        if fn(record) == false then
            doc.data[kind][id] = nil
        end
    end
    doc:CompleteChange(description, {undoable = false})
end

--Adds a record to a store.
--- @param id string
--- @param private boolean
--- @param record table
--- @param kind? string
local function Add(id, private, record, kind)
    kind = kind or "dice"
    if private then
        local items = PrivateItems(kind)
        items[id] = record
        SavePrivate(items, kind)
        return
    end
    local doc = SharedDoc()
    doc:BeginChange()
    doc.data[kind] = doc.data[kind] or {}
    doc.data[kind][id] = record
    local descriptions = {figures = "Add a table figure", trackers = "Add a table tracker"}
    doc:CompleteChange(descriptions[kind] or "Add a table die", {undoable = false})
end

--Moves a record from one store to the other (dragged across the screen's edge).
--- @param id string
--- @param toPrivate boolean
--- @param fx number
--- @param fy number
--- @param kind? string
--- @param changes? table fields to set on the moved record too
local function Transfer(id, toPrivate, fx, fy, kind, changes)
    kind = kind or "dice"
    local from = toPrivate and SharedItems(kind) or PrivateItems(kind)
    local record = from[id]
    if record == nil then
        return
    end
    local copy = DeepCopy(record)
    copy.fx, copy.fy = fx, fy
    for k, v in pairs(changes or {}) do
        copy[k] = v
    end
    copy.roll, copy.rollAt, copy.rollBy = nil, nil, nil
    copy.seq = (copy.seq or 0) + 1
    Modify(id, not toPrivate, "Move a table item", function() return false end, kind)
    Add(id, toPrivate, copy, kind)
end

----------------------------------------------------------------------
--What the Director's Screen means for a die.

--Whether a spot (table fractions) is behind the open Director's Screen.
local function BehindScreen(fx)
    if not dmhub.isDM or rawget(_G, "DirectorScreen") == nil then
        return false
    end
    local edge = DirectorScreen.EdgeX()
    if edge == nil then
        return false
    end
    local w = TableSize()
    return fx * w >= edge
end

----------------------------------------------------------------------
--The menus.

--How far above a die's centre its menu opens, in screen pixels at scale 1
--(a little more than a die's half-height).
local DIE_MENU_GAP = 56

local function MenuAnchor()
    if g.menuAnchor == nil or not g.menuAnchor.valid then
        if g.layer == nil or not g.layer.valid then
            return nil
        end
        --menus open from this 1px panel, moved to where they belong
        --(ShowDieMenu puts it just above the die).
        g.menuAnchor = gui.Panel{
            width = 1,
            height = 1,
            floating = true,
            halign = "left",
            valign = "top",
            interactable = false,
        }
        g.layer:AddChild(g.menuAnchor)
        g.menuAnchor.popupPositioning = "panel"
    end
    return g.menuAnchor
end

local function CloseMenu()
    local anchor = g.menuAnchor
    if anchor ~= nil and anchor.valid then
        anchor.popup = nil
    end
end

--- Puts a new die on the table, resting showing its highest face.
--- @param faces number
--- @param px number screen pixels
--- @param py number
--- @param private boolean behind the Director's Screen
--- roll (optional) is a throw as the engine's onRoll gives it (screen pixels):
--- the new die arrives by playing it, on every client.
--- @param roll? table
function TableDice.AddDie(faces, px, py, private, roll)
    if not dmhub.isDM then
        return
    end
    local fx, fy = ScreenToTable(px, py)
    --- @type TableDieRecord
    local record = {
        faces = faces,
        model = g_setSetting:Get() or "",
        fx = fx,
        fy = fy,
        --a d10 reads 0-9 on some sets: the engine settles on its real face.
        face = faces,
        yaw = math.random(-20, 20),
        pick = 0,
        seq = 1,
    }
    if roll ~= nil then
        local ffx, ffy = ScreenToTable(roll.fromx, roll.fromy)
        local tfx, tfy = ScreenToTable(roll.tox, roll.toy)
        record.fx, record.fy = tfx, tfy
        record.face, record.yaw, record.pick = roll.face, roll.yaw, roll.pick
        record.roll = {
            fromfx = ffx, fromfy = ffy, tofx = tfx, tofy = tfy,
            lift = roll.lift, face = roll.face, yaw = roll.yaw, pick = roll.pick,
            seed = roll.seed, duration = roll.duration,
        }
        record.rollAt = dmhub.serverTime
    end
    Add(dmhub.GenerateGuid(), private, record)
end

--A die's right-click menu (Director only): roll it, or take it away.
--- @param id string
local function ShowDieMenu(id)
    local handle = g.handles[id]
    local anchor = MenuAnchor()
    if handle == nil or anchor == nil or not dmhub.isDM then
        return
    end
    local private = handle.private
    --just above the die, opening upward so it never covers the die.
    local w, h = TableSize()
    local fx, fy = ScreenToTable(handle.die.x, handle.die.y)
    local scale = Mapping()
    anchor.x = fx * w
    anchor.y = fy * h - DIE_MENU_GAP * scale * handle.die.scale
    --the anchor's new spot is laid out next frame, and the menu places itself
    --from where the anchor is when it opens: so it opens a frame later.
    dmhub.Schedule(0.02, function()
        if mod.unloaded or not anchor.valid then
            return
        end
        local menu = gui.ContextMenu{
            entries = {
                {
                    text = "Remove Die",
                    click = function()
                        CloseMenu()
                        Modify(id, private, "Remove a table die", function() return false end)
                    end,
                },
            },
        }
        if menu == nil then
            return
        end
        local style = menu.selfStyle
        if style ~= nil then
            style.valign = "top"
            style.halign = "center"
        end
        anchor.popup = menu
    end)
end

----------------------------------------------------------------------
--The table items drawer (TABLE_DICE_BRIEF.md, "The table items drawer"):
--slides up from the bottom of the table. Categories down its left side are by
--what a thing IS; search covers all of them; Recent and Favourites follow the
--Director. Click a tile to drop it near where the drawer opened, or drag it to
--a spot. Only dice are built so far: every other tile shows as coming soon.

local DRAWER_HEIGHT = 345
--past the left icon rail.
local DRAWER_LEFT = 64
local TILE_WIDTH = 104
local TILE_HEIGHT = 86
local RECENT_MAX = 8

--What the Director placed lately, and starred: item ids, per user.
local g_recentSetting = setting{
    id = "tableitems:recent",
    storage = "preference",
    default = "",
}
local g_favouritesSetting = setting{
    id = "tableitems:favourites",
    storage = "preference",
    default = "",
}
--The Director's uploaded figures, as JSON [{blob, name}], kept across games.
local g_figureLibrarySetting = setting{
    id = "tableitems:figures",
    storage = "preference",
    default = "",
}

--- @return {blob: string, name: string}[]
local function FigureLibrary()
    local text = g_figureLibrarySetting:Get()
    if type(text) ~= "string" or text == "" then
        return {}
    end
    local parsed = dmhub.FromJson(text)
    if parsed == nil or type(parsed.result) ~= "table" then
        return {}
    end
    local result = {}
    for _, entry in ipairs(parsed.result) do
        if type(entry) == "table" and type(entry.blob) == "string" then
            result[#result+1] = {blob = entry.blob, name = tostring(entry.name or "Figure")}
        end
    end
    return result
end

--- @param library {blob: string, name: string}[]
local function SaveFigureLibrary(library)
    g_figureLibrarySetting:Set(dmhub.ToJson(library))
end

--- @param s table a setting holding a JSON list of item ids
--- @return string[]
local function ReadIds(s)
    local text = s:Get()
    if type(text) ~= "string" or text == "" then
        return {}
    end
    local parsed = dmhub.FromJson(text)
    if parsed == nil or type(parsed.result) ~= "table" then
        return {}
    end
    local result = {}
    for _, id in ipairs(parsed.result) do
        if type(id) == "string" then
            result[#result+1] = id
        end
    end
    return result
end

--- @param s table
--- @param ids string[]
local function WriteIds(s, ids)
    s:Set(dmhub.ToJson(ids))
end

--A die placer: drop `faces` at (px, py) screen pixels.
--- @param faces number
--- @return fun(px: number, py: number, private: boolean)
local function DiePlacer(faces)
    return function(px, py, private)
        TableDice.AddDie(faces, px, py, private)
    end
end

--- @class TableItemDef
--- @field id string
--- @field name string
--- @field note nil|string
--- @field icon string
--- @field place nil|fun(px: number, py: number, private: boolean) nil = coming soon
--- @field dice nil|number[] dice shown live in its tile (TableDice previews), by face count
--- @field model nil|string a dice-set tile: the set its die wears ("" = default)
--- @field setValue nil|string a dice-set tile: the set picking it chooses
--- @field figureBlob nil|string a figure-library tile: the uploaded figure it places
--- @field opens nil|string a tile that opens a row under the category ("figures", "heroes")
--- @field opensNoun nil|string what that row shows, for the tooltip ("your figures")
--- @field trackerText nil|string a tracker tile: the number its medallion shows
--- @field portrait nil|string a character tile (a standee): the portrait it shows
--- @field thumbnail nil|string a dice-set tile: the still picture of its die
--- @field art nil|string a dice-set tile: its store background art
--- @field action nil|fun() a tile that does something other than place an item
--- @field tracker nil|string a tracker tile: the medallion it shows (TableDice.TrackerToken)

--- @class TableItemCategory
--- @field id string
--- @field name string
--- @field icon string
--- @field test string what belongs here, in one line
--- @field items TableItemDef[]

--- @type TableItemCategory[]
local CATEGORIES = {
    {id = "dice", name = "Dice", icon = "phosphor/dice-five.png", test = "Something you roll.", items = {
        --only the dice Draw Steel uses: d10s (the 2d10 power roll), d6 and d3.
        {id = "2d10", dice = {10, 10}, name = "2d10", note = "Power roll pair", icon = "phosphor/dice-two.png", place = function(px, py, private)
            TableDice.AddDie(10, px - 34, py, private)
            TableDice.AddDie(10, px + 34, py, private)
        end},
        {id = "d10", dice = {10}, name = "d10", icon = "phosphor/polygon.png", place = DiePlacer(10)},
        {id = "d6", dice = {6}, name = "d6", icon = "phosphor/dice-six.png", place = DiePlacer(6)},
        {id = "d3", dice = {3}, name = "d3", icon = "phosphor/dice-three.png", place = DiePlacer(3)},
    }},
    {id = "trinkets", name = "Trinkets", icon = "phosphor/diamond.png", test = "Something you move or flip; it keeps no number.", items = {
        {id = "coin", name = "Coin", note = "Flip it", icon = "phosphor/coin.png", place = function(px, py, private)
            TableDice.AddTracker("coin", px, py, private, {result = "heads"})
        end},
        {id = "gem", name = "Gem", note = "The treasure", icon = "phosphor/diamond.png", place = function(px, py, private)
            TableDice.AddTracker("gem", px, py, private)
        end},
        {id = "skull", name = "Skull", note = "Danger here", icon = "phosphor/skull.png", place = function(px, py, private)
            TableDice.AddTracker("skull", px, py, private)
        end},
        {id = "key", name = "Key", note = "The locked door", icon = "phosphor/key.png", place = function(px, py, private)
            TableDice.AddTracker("key", px, py, private)
        end},
        {id = "figure", name = "Figure", note = "Your 3D minis", icon = "phosphor/user.png", opens = "figures"},
        {id = "standee", name = "Standee", note = "Any character", icon = "phosphor/user.png", opens = "standees", opensNoun = "the characters"},
        {id = "pointer", name = "Pointer", note = "Turn it to point", icon = "phosphor/arrow-fat-right.png", place = function(px, py, private)
            TableDice.AddTracker("pointer", px, py, private, {yaw = 0})
        end},
        {id = "stamp", name = "Stamp", icon = "phosphor/stamp.png"},
        {id = "ruler", name = "Ruler", icon = "phosphor/ruler.png"},
    }},
    {id = "trackers", name = "Trackers", icon = "phosphor/plus-minus.png", test = "Something that holds a value people change.", items = {
        {id = "malice", tracker = "malice", name = "Malice", note = "Director's pool", icon = "phosphor/fire.png", place = function(px, py, private)
            TableDice.AddTracker("malice", px, py, private)
        end},
        {id = "herotokens", tracker = "herotokens", name = "Hero Tokens", note = "Party pool", icon = "phosphor/coin.png", place = function(px, py, private)
            TableDice.AddTracker("herotokens", px, py, private)
        end},
        {id = "counter", tracker = "counter", name = "Counter", note = "Any name", icon = "phosphor/plus-minus.png", place = function(px, py, private)
            TableDice.AddTracker("counter", px, py, private)
        end},
        {id = "hero", tracker = "hero", name = "Hero", note = "Pick a hero", icon = "phosphor/user.png", opens = "heroes", opensNoun = "the heroes"},
        {id = "countdown", tracker = "countdown", name = "Countdown", note = "Rounds left", icon = "phosphor/timer.png", place = function(px, py, private)
            TableDice.AddTracker("countdown", px, py, private, {value = 3})
        end},
        {id = "sandtimer", tracker = "sandtimer", name = "Sand timer", note = "Flip to start", icon = "phosphor/hourglass.png", place = function(px, py, private)
            TableDice.AddTracker("sandtimer", px, py, private, {duration = 60})
        end},
        {id = "initiative", name = "Initiative strip", icon = "phosphor/list-numbers.png"},
        {id = "vote", name = "Vote", note = "One token each", icon = "phosphor/check-square.png"},
    }},
    {id = "cards", name = "Cards", icon = "phosphor/cards.png", test = "Something you draw, flip or deal.", items = {
        {id = "deck", name = "Deck", note = "Draw and flip", icon = "phosphor/cards.png"},
        {id = "card", name = "Single card", icon = "phosphor/cards-three.png"},
        {id = "hand", name = "Hand", note = "Deal to a player", icon = "phosphor/hand.png"},
    }},
    {id = "handouts", name = "Handouts", icon = "phosphor/scroll.png", test = "Something people read or look at.", items = {
        {id = "picture", name = "Picture", icon = "phosphor/image.png"},
        {id = "letter", name = "Letter", icon = "phosphor/envelope-simple.png"},
        {id = "mapscrap", name = "Map scrap", icon = "phosphor/map-trifold.png"},
        {id = "sticky", name = "Sticky note", icon = "phosphor/note.png"},
        {id = "facedown", name = "Face-down", note = "Flip to reveal", icon = "phosphor/eye-slash.png"},
        {id = "journalpage", name = "Journal page", icon = "phosphor/book-open.png"},
    }},
    {id = "buttons", name = "Buttons", icon = "phosphor/cursor-click.png", test = "Something you press to make the app do something.", items = {
        {id = "soundpad", name = "Sound pad", note = "From the soundboard", icon = "phosphor/speaker-high.png"},
        {id = "script", name = "Script button", icon = "phosphor/code.png"},
        {id = "musicbox", name = "Music box", icon = "phosphor/music-notes.png"},
        {id = "starttimer", name = "Start timer", icon = "phosphor/timer.png"},
    }},
    {id = "zones", name = "Zones", icon = "phosphor/frame-corners.png", test = "An area other things go in.", items = {
        {id = "dicetray", name = "Dice tray", note = "Rolls land inside", icon = "phosphor/tray.png"},
        {id = "playmat", name = "Play mat", icon = "phosphor/squares-four.png"},
        {id = "spotlight", name = "Spotlight", note = "Dims the rest", icon = "phosphor/sun.png"},
        {id = "frame", name = "Frame", note = "Group things", icon = "phosphor/frame-corners.png"},
    }},
}

--- @param id string
--- @return nil|TableItemDef
local function FindTableItem(id)
    for _, cat in ipairs(CATEGORIES) do
        for _, item in ipairs(cat.items) do
            if item.id == id then
                return item
            end
        end
    end
    return nil
end

--Quiet raised hovers, no accent fills (the house style for rows and tiles).
local g_drawerStyles = {
    {selectors = {"tableDrawer"}, bgcolor = "@bg", borderColor = "@border", borderWidth = 1, cornerRadius = 10},
    {selectors = {"tableDrawerDivider"}, bgcolor = "@border"},
    {selectors = {"tableDrawerCat"}, bgcolor = "clear", cornerRadius = 6},
    {selectors = {"tableDrawerCat", "hover"}, bgcolor = "@bgRaised"},
    {selectors = {"tableDrawerCat", "selected"}, bgcolor = "@bgRaised"},
    {selectors = {"tableDrawerCatLabel"}, color = "@fg", fontSize = 14, width = "auto", height = "auto"},
    {selectors = {"tableDrawerCatLabel", "parent:selected"}, color = "@fgStrong"},
    {selectors = {"tableDrawerCatIcon"}, bgcolor = "@fgMuted"},
    {selectors = {"tableDrawerCatIcon", "parent:selected"}, bgcolor = "@fgStrong"},
    {selectors = {"tableDrawerTile"}, bgcolor = "@bgAlt", borderColor = "@border", borderWidth = 1, cornerRadius = 8},
    {selectors = {"tableDrawerTile", "hover"}, bgcolor = "@bgRaised"},
    {selectors = {"tableDrawerTile", "selected"}, bgcolor = "@bgRaised", borderColor = "@fgStrong"},
    {selectors = {"tableDrawerTileIcon"}, bgcolor = "@fg"},
    {selectors = {"tableDrawerTileName"}, color = "@fgStrong", fontSize = 14, width = "auto", height = "auto", halign = "center"},
    {selectors = {"tableDrawerTileNote"}, color = "@fgMuted", fontSize = 11, width = "auto", height = "auto", halign = "center"},
    {selectors = {"tableDrawerTileIcon", "parent:soon"}, opacity = 0.4},
    {selectors = {"tableDrawerTileName", "parent:soon"}, opacity = 0.4},
    {selectors = {"tableDrawerTileNote", "parent:soon"}, opacity = 0.7},
    {selectors = {"tableDrawerText"}, color = "@fgMuted", fontSize = 12, width = "auto", height = "auto"},
    {selectors = {"tableDrawerToggle"}, bgcolor = "clear", cornerRadius = 6},
    {selectors = {"tableDrawerToggle", "hover"}, bgcolor = "@bgRaised"},
    {selectors = {"tableDrawerToggleLabel"}, color = "@fgMuted", fontSize = 12, width = "auto", height = "auto"},
    {selectors = {"tableDrawerToggleLabel", "parent:selected"}, color = "@fgStrong"},
    {selectors = {"tableDrawerToggleIcon"}, bgcolor = "@fgMuted"},
    {selectors = {"tableDrawerToggleIcon", "parent:selected"}, bgcolor = "@fgStrong"},
    {selectors = {"tableItemsButton"}, bgcolor = "@bg", borderColor = "@border", borderWidth = 1, cornerRadius = 8},
    {selectors = {"tableItemsButton", "hover"}, bgcolor = "@bgRaised"},
    {selectors = {"tableItemsButton", "selected"}, bgcolor = "@bgRaised", borderColor = "@fgMuted"},
    {selectors = {"tableItemsButtonIcon"}, bgcolor = "@fg"},
    {selectors = {"tableTrackerValue"}, color = "white", bold = true},
    {selectors = {"tableDrawerSetCard"}, bgcolor = "@bgRaised", cornerRadius = 4},
    {selectors = {"tableTrackerPlate"}, bgcolor = "@bg", borderColor = "@border", borderWidth = 1, cornerRadius = 6},
    {selectors = {"tableTrackerName"}, color = "@fgStrong", fontSize = 13, width = "auto", height = "auto"},
    {selectors = {"tableTrackerStep"}, bgcolor = "@bg", borderColor = "@border", borderWidth = 1, cornerRadius = 13},
    {selectors = {"tableTrackerStep", "hover"}, bgcolor = "@bgRaised"},
    {selectors = {"tableTrackerStepLabel"}, color = "@fgStrong", fontSize = 18, bold = true},
    {selectors = {"tableTrackerPlate", "expired"}, bgcolor = "#7A1424", borderColor = "#E0445C"},
    {selectors = {"tableTrackerPip"}, bgcolor = "#1A1A1E", borderColor = "#8A8A90", borderWidth = 1.5, cornerRadius = 6},
    {selectors = {"tableTrackerPip", "lit"}, bgcolor = "#F2C14E", borderColor = "#FFF0B8"},
    {selectors = {"tableTrackerPip", "hover"}, borderColor = "#FFFFFF"},
    {selectors = {"tableTrackerPip", "resting"}, opacity = 0.45},
    {selectors = {"tableStandeeCard"}, bgcolor = "#E8DCC4", borderColor = "#5A3A22", borderWidth = 1.5, cornerRadius = 3},
    {selectors = {"tableTrackerChip"}, bgcolor = "@bg", borderColor = "@border", borderWidth = 1, cornerRadius = 9},
    {selectors = {"tableTrackerChip", "hover"}, bgcolor = "@bgRaised"},
    {selectors = {"tableTrackerChipIcon"}, bgcolor = "#F2C14E"},
    {selectors = {"tableTrackerChipLabel"}, color = "@fgStrong", fontSize = 12, bold = true},
}

--The drawer while it exists. category is a category id, "recent" or
--"favourites"; private means clicked tiles land behind the Director's Screen.
local g_drawer = {
    --- @type Panel|nil
    panel = nil,
    --- @type Panel|nil
    grid = nil,
    --- @type Panel|nil
    side = nil,
    --- @type Panel|nil
    setRow = nil,
    --- @type Panel|nil
    title = nil,
    --- @type Panel|nil
    searchInput = nil,
    private = false,
    category = "dice",
    search = "",
    pinned = false,
    placed = 0,
    --- @type table[] the live dice on the tiles (SyncPreviews)
    previews = {},
    --a tile's row shown under its category ("figures"), or nil.
    openRow = nil,
    --- @type string[] names of STL files being prepared for the library
    uploading = {},
}

--- @return boolean
function TableDice.DrawerOpen()
    return g_drawer.panel ~= nil and g_drawer.panel.valid and not g_drawer.panel:HasClass("collapsed")
end

local function CloseDrawer()
    if g_drawer.panel ~= nil and g_drawer.panel.valid then
        g_drawer.panel:SetClass("collapsed", true)
    end
    if g.tableButton ~= nil and g.tableButton.valid then
        g.tableButton:SetClass("selected", false)
    end
end

--Layer units to screen pixels (top-left origin).
local function LayerToScreen(x, y)
    local scale, top = Mapping()
    return x / scale, top + y / scale
end

--Where a clicked tile lands: above the drawer near its left, or just inside
--the Director's Screen when it was opened there; each a little further along
--so they don't pile up.
local function DropSpot()
    local w, h = TableSize()
    local step = (g_drawer.placed % 8) * 70
    g_drawer.placed = g_drawer.placed + 1
    local y = h - DRAWER_HEIGHT - 70
    local x = DRAWER_LEFT + 140 + step
    if g_drawer.private and rawget(_G, "DirectorScreen") ~= nil then
        local edge = DirectorScreen.EdgeX()
        if edge ~= nil then
            x = math.min(w - 80, edge + 110 + step)
        end
    end
    return LayerToScreen(x, y)
end

--- @param id string
local function NoteRecent(id)
    local result = {id}
    for _, other in ipairs(ReadIds(g_recentSetting)) do
        if other ~= id and #result < RECENT_MAX then
            result[#result+1] = other
        end
    end
    WriteIds(g_recentSetting, result)
end

--- @param id string
local function ToggleFavourite(id)
    local result = {}
    local found = false
    for _, other in ipairs(ReadIds(g_favouritesSetting)) do
        if other == id then
            found = true
        else
            result[#result+1] = other
        end
    end
    if not found then
        result[#result+1] = id
    end
    WriteIds(g_favouritesSetting, result)
end

--- @param item TableItemDef
--- @param px number
--- @param py number
--- @param private boolean
local function PlaceItem(item, px, py, private)
    if item.place == nil then
        return
    end
    item.place(px, py, private)
    NoteRecent(item.id)
    if not g_drawer.pinned then
        CloseDrawer()
    end
end

local SelectDiceSet

--Live dice in the drawer's tiles (Venla, 2026-10-20): each dice tile holds
--a real table die in the chosen set, so the drawer shows what you are about
--to put down. They are engine table dice like the ones on the table, only
--local and never stored. Click one to add that item; drag one out of the
--drawer and put it down, or throw it, and it lands there.
--g_drawer.previews: {die = TableDieLua, tile = Panel, item = TableItemDef,
--faces = number, index = number, x = number, y = number} for each die shown.

local PREVIEW_SCALE = 0.55
--a 2d10 tile's pair sits a little smaller, side by side (layer units apart).
local PAIR_SCALE = 0.45
local PAIR_SPREAD = 22

local function DestroyPreviews()
    for _, preview in ipairs(g_drawer.previews) do
        local object = preview.die or preview.figure
        if object ~= nil and object.valid then
            object:Destroy()
        end
    end
    g_drawer.previews = {}
end

--A panel's centre in screen pixels: its spot in the layer (as Tabletop's
--LayerRect measures it), then the layer's mapping onto the screen.
--- @param panel Panel
--- @return number|nil px, number|nil py
local function PanelCentreOnScreen(panel)
    local layer = g.layer
    if layer == nil or not layer.valid or panel == nil or not panel.valid then
        return nil, nil
    end
    local lp = layer.positionInScreenSpace
    local p = panel.positionInScreenSpace
    local left = lp.x - layer.renderedWidth / 2
    local top = lp.y + layer.renderedHeight / 2
    return LayerToScreen(p.x - left, top - p.y)
end

--The top of the drawer, in screen pixels: a die let go below it stays in.
local function DrawerTopOnScreen()
    local _, h = TableSize()
    local _, py = LayerToScreen(0, h - DRAWER_HEIGHT - 10)
    return py
end

--Where a preview die rests: on its tile, above the name.
--- @param preview table
--- @return number|nil px, number|nil py
local function PreviewSpot(preview)
    local px, py = PanelCentreOnScreen(preview.tile)
    if px == nil or py == nil then
        return nil, nil
    end
    local scale = Mapping()
    if preview.figure ~= nil then
        --a figure stands on its base and leans up the screen: its spot is low
        --in the tile so it sits above the name, under the row's label.
        return px, py + 4 / scale
    end
    local offset = 0
    if #preview.item.dice > 1 then
        offset = (preview.index - (#preview.item.dice + 1) / 2) * 2 * PAIR_SPREAD
    end
    return px + offset / scale, py - 14 / scale
end

local function PutBack(preview)
    local px, py = PreviewSpot(preview)
    if px == nil then
        return
    end
    if preview.figure ~= nil then
        if preview.figure.valid then
            preview.x, preview.y = px, py
            preview.figure:SetRest(px, py)
        end
        return
    end
    if preview.die.valid then
        preview.x, preview.y = px, py
        preview.die:SetRest(px, py, preview.faces, 0, 0)
    end
end

--A figure-library tile's live figure: click it to place the figure, or drag
--it out of the drawer and let go.
--- @param tile Panel
--- @param item TableItemDef
local function BuildFigurePreview(tile, item)
    local figure = dice.CreateTableFigure{blob = item.figureBlob, x = 0, y = 0, height = 46, tilt = 62}
    if figure == nil then
        return
    end
    local preview = {figure = figure, tile = tile, item = item}
    figure.callbacks = {
        onClick = function(x, y)
            local px, py = DropSpot()
            PlaceItem(item, px, py, g_drawer.private)
            PutBack(preview)
        end,
        onMove = function(x, y)
            if y < DrawerTopOnScreen() then
                local fx = ScreenToTable(x, y)
                PlaceItem(item, x, y, BehindScreen(fx))
            end
            PutBack(preview)
        end,
    }
    g_drawer.previews[#g_drawer.previews+1] = preview
    PutBack(preview)
end

--- @param tile Panel
--- @param item TableItemDef
--- @param faces number
--- @param index number
local function BuildPreview(tile, item, faces, index)
    local model = item.model
    if model == nil then
        model = g_setSetting:Get() or ""
    end
    local die = dice.CreateTableDie{
        faces = faces,
        model = cond(model == "", nil, model),
        x = 0,
        y = 0,
        face = faces,
        --a d4 stands tall: it sits a little smaller to fit its tile.
        scale = cond(#item.dice > 1, PAIR_SCALE, cond(faces == 4, PREVIEW_SCALE * 0.8, PREVIEW_SCALE)),
    }
    if die == nil then
        return
    end
    --the drawer's dice sit over the drawer, not on the table under it (an
    --engine without table layering has no aboveUI: they are over it anyway).
    pcall(function() die.aboveUI = true end)
    local preview = {die = die, tile = tile, item = item, faces = faces, index = index}
    --a dice-set tile's die: clicking or moving it picks the set; it stays put.
    if item.setValue ~= nil then
        die.callbacks = {
            onRoll = function(roll)
                PutBack(preview)
                SelectDiceSet(item.setValue)
            end,
            onMove = function(x, y)
                PutBack(preview)
                SelectDiceSet(item.setValue)
            end,
        }
        g_drawer.previews[#g_drawer.previews+1] = preview
        PutBack(preview)
        return
    end
    die.callbacks = {
        --clicked (a hop in place) or thrown: a click adds the item as its tile
        --would; a throw out of the drawer lands a die where it was thrown.
        onRoll = function(roll)
            if roll.toy >= DrawerTopOnScreen() then
                local px, py = DropSpot()
                PlaceItem(item, px, py, g_drawer.private)
            else
                local fx = ScreenToTable(roll.tox, roll.toy)
                TableDice.AddDie(faces, roll.tox, roll.toy, BehindScreen(fx), roll)
                NoteRecent(item.id)
                if not g_drawer.pinned then
                    CloseDrawer()
                end
            end
            PutBack(preview)
        end,
        --dragged and put down: on the table it lands there; back in the
        --drawer it returns to its tile.
        onMove = function(x, y)
            if y < DrawerTopOnScreen() then
                local fx = ScreenToTable(x, y)
                TableDice.AddDie(faces, x, y, BehindScreen(fx))
                NoteRecent(item.id)
                if not g_drawer.pinned then
                    CloseDrawer()
                end
            end
            PutBack(preview)
        end,
    }
    g_drawer.previews[#g_drawer.previews+1] = preview
    PutBack(preview)
end

--Keeps a live die on every dice tile showing: made when the drawer shows
--them, moved when a tile moves (a scroll, a resize), gone when it closes.
--The layer's think runs it.
local function SyncPreviews()
    local panel = g_drawer.panel
    local open = panel ~= nil and panel.valid and not panel:HasClass("collapsed")
    if not open or dice.CreateTableDie == nil then
        if #g_drawer.previews > 0 then
            DestroyPreviews()
        end
        return
    end
    if #g_drawer.previews == 0 and g_drawer.grid ~= nil and g_drawer.grid.valid then
        for _, tile in ipairs(g_drawer.grid.children) do
            local item = nil
            pcall(function() item = tile.data.item end)
            if item ~= nil and item.dice ~= nil then
                for index, faces in ipairs(item.dice) do
                    BuildPreview(tile, item, faces, index)
                end
            elseif item ~= nil and item.figureBlob ~= nil and dice.CreateTableFigure ~= nil then
                BuildFigurePreview(tile, item)
            end
        end
    end
    local x1, y1, x2, y2 = TableBounds()
    for _, preview in ipairs(g_drawer.previews) do
        local object = preview.die or preview.figure
        if object ~= nil and object.valid then
            object:SetBounds(x1, y1, x2, y2)
            local px, py = PreviewSpot(preview)
            --moved only when its tile did, and never mid-throw.
            if px ~= nil and (math.abs(px - (preview.x or 0)) > 1 or math.abs(py - (preview.y or 0)) > 1)
                and math.abs(object.x - (preview.x or 0)) < 1 and math.abs(object.y - (preview.y or 0)) < 1 then
                PutBack(preview)
            end
        end
    end
end

local RebuildDrawer

--Picks the set dice from the drawer wear, and shows it.
--- @param value string a dice set id ("" = default)
SelectDiceSet = function(value)
    g_setSetting:Set(value)
    RebuildDrawer()
end

--- @param item TableItemDef
--- @return Panel
local function BuildTile(item)
    local soon = item.place == nil and item.opens == nil and item.action == nil
    local open = item.opens ~= nil and g_drawer.openRow == item.opens
    local icon
    if item.tracker ~= nil then
        --a tracker shows a small copy of its medallion, with the pool's
        --current value for a live one.
        local value = 0
        if item.tracker == "malice" then
            value = CharacterResource.GetGlobalResource(CharacterResource.maliceResourceId) or 0
        elseif item.tracker == "herotokens" then
            value = CharacterResource.GetGlobalResource(CharacterResource.heroTokenId) or 0
        elseif item.tracker == "countdown" then
            value = 3
        end
        local text = item.trackerText or string.format("%d", math.floor(value))
        if item.tracker == "sandtimer" and item.trackerText == nil then
            text = "1:00"
        end
        icon = gui.Panel{
            width = 44,
            height = 44,
            halign = "center",
            tmargin = 4,
            interactable = false,
            TableDice.TrackerToken(item.tracker, 44, gui.Label{
                classes = {"tableTrackerValue"},
                text = text,
                fontSize = 17,
                width = "100%",
                height = "100%",
                textAlignment = "center",
                interactable = false,
            }),
        }
    elseif item.portrait ~= nil then
        icon = gui.Panel{
            bgimage = item.portrait,
            bgcolor = "white",
            width = 40,
            height = 40,
            cornerRadius = 6,
            halign = "center",
            tmargin = 6,
            interactable = false,
        }
    else
        --a real die rests here (SyncPreviews); other items show their icon.
        icon = gui.Panel{
            classes = {"tableDrawerTileIcon"},
            bgimage = cond(item.dice ~= nil or item.figureBlob ~= nil, nil, item.icon),
            bgcolor = cond(item.dice ~= nil or item.figureBlob ~= nil, "clear", nil),
            width = 28,
            height = cond(item.dice ~= nil or item.figureBlob ~= nil, 44, 28),
            halign = "center",
            tmargin = cond(item.dice ~= nil or item.figureBlob ~= nil, 4, 12),
            interactable = false,
        }
    end
    return gui.Panel{
        classes = {"tableDrawerTile", cond(soon, "soon", cond(open, "selected", "ready"))},
        bgimage = "panels/square.png",
        width = TILE_WIDTH,
        height = TILE_HEIGHT,
        hmargin = 4,
        vmargin = 4,
        flow = "vertical",
        swallowPress = true,
        draggable = item.place ~= nil,
        data = {item = item},
        hover = function(element)
            if item.opens ~= nil then
                local noun = item.opensNoun or "your figures"
                gui.Tooltip(cond(open, "Hide " .. noun, "Show " .. noun))(element)
            elseif item.action ~= nil then
                gui.Tooltip(item.note or item.name)(element)
            elseif item.figureBlob ~= nil then
                gui.Tooltip("Click to add, or drag onto the table. Right-click to remove it from your figures.")(element)
            elseif soon then
                gui.Tooltip("Coming soon")(element)
            else
                gui.Tooltip("Click to add, or drag onto the table. Right-click to favourite.")(element)
            end
        end,
        click = function(element)
            if item.opens ~= nil then
                g_drawer.openRow = cond(open, nil, item.opens)
                RebuildDrawer()
                return
            end
            if item.action ~= nil then
                item.action()
                return
            end
            if soon then
                return
            end
            local px, py = DropSpot()
            PlaceItem(item, px, py, g_drawer.private)
        end,
        rightClick = function(element)
            if item.figureBlob ~= nil then
                local library = {}
                for _, entry in ipairs(FigureLibrary()) do
                    if entry.blob ~= item.figureBlob then
                        library[#library+1] = entry
                    end
                end
                SaveFigureLibrary(library)
                RebuildDrawer()
                return
            end
            ToggleFavourite(item.id)
            RebuildDrawer()
        end,
        --dropped on the table: it goes there, private if behind the screen.
        drag = function(element)
            local mouse = dmhub.mouseScreenPosition
            local fx, fy = ScreenToTable(mouse.x, mouse.y)
            local _, h = TableSize()
            --let go over the drawer: nothing.
            if fy * h > h - DRAWER_HEIGHT - 12 then
                return
            end
            PlaceItem(item, mouse.x, mouse.y, BehindScreen(fx))
        end,
        icon,
        gui.Label{
            classes = {"tableDrawerTileName"},
            text = item.name,
            tmargin = 6,
            --long names (a hero's) shrink to stay inside the tile.
            textWrap = false,
            maxWidth = TILE_WIDTH - 8,
            minFontSize = 9,
            interactable = false,
        },
        gui.Label{
            classes = {"tableDrawerTileNote"},
            text = cond(soon, "Coming soon", item.note or ""),
            textWrap = false,
            maxWidth = TILE_WIDTH - 8,
            interactable = false,
        },
    }
end

--What the drawer shows now: a search across everything, or one category.
--- @return TableItemDef[] items
--- @return string text the line above the tiles
local function ShownItems()
    if g_drawer.search ~= "" then
        local result = {}
        for _, cat in ipairs(CATEGORIES) do
            for _, item in ipairs(cat.items) do
                local text = string.lower(item.name .. " " .. (item.note or "") .. " " .. cat.name)
                if string.find(text, g_drawer.search, 1, true) ~= nil then
                    result[#result+1] = item
                end
            end
        end
        return result, cond(#result == 0, "Nothing matches.", "Results")
    end
    if g_drawer.category == "recent" or g_drawer.category == "favourites" then
        local recent = g_drawer.category == "recent"
        local result = {}
        for _, id in ipairs(ReadIds(cond(recent, g_recentSetting, g_favouritesSetting))) do
            local item = FindTableItem(id)
            if item ~= nil then
                result[#result+1] = item
            end
        end
        if recent then
            return result, cond(#result == 0, "Things you add show up here.", "What you added lately.")
        end
        return result, cond(#result == 0, "Right-click any tile to add it here.", "Your favourites.")
    end
    for _, cat in ipairs(CATEGORIES) do
        if cat.id == g_drawer.category then
            return cat.items, cat.test
        end
    end
    return {}, ""
end

--A dice set's store art: the background of its store tile (the shop item's
--dicePreview, else its diceBanner), or nil when the set has none or is not
--a store item (Default).
--- @param assetid string
--- @return nil|string
local function DiceSetArt(assetid)
    local found = nil
    pcall(function()
        for _, item in pairs(assets.shopItems) do
            if item.itemType == "Dice" and item.assetid == assetid then
                for _, cfg in ipairs({item.dicePreview, item.diceBanner}) do
                    if found == nil and type(cfg) == "table" and type(cfg.backgroundImage) == "string" and cfg.backgroundImage ~= "" then
                        found = cfg.backgroundImage
                    end
                end
            end
        end
    end)
    return found
end

--The dice sets this account has, as tiles: each shows its store art, or a
--still d10 in its set.
--- @return TableItemDef[]
local function DiceSetItems()
    local result = {}
    for _, entry in ipairs(dice.GetAvailableDice()) do
        local value = entry.value
        if value == "Default" then
            value = ""
        end
        --a still, numberless picture of the set's d10 (DiceIconManager, as the
        --Dice panel shows), not a live die: a live one read as a die to grab
        --(Venla, 2026-10-21).
        result[#result+1] = {
            id = "set:" .. tostring(value),
            name = tostring(entry.text),
            icon = "phosphor/dice-five.png",
            thumbnail = string.format("#DiceIcon:%s:d10", tostring(entry.value)),
            --the set's small store background, as its store tile shows it
            --(Venla, 2026-10-22); sets with none keep the still die.
            art = DiceSetArt(tostring(entry.value)),
            model = value,
            setValue = value,
        }
    end
    return result
end

--The picture on a dice-set tile: its store art, cropped to cover the space
--without stretching (it fades in once the art's size is known), or the still
--die when the set has no art.
--- @param item TableItemDef
--- @return Panel
local function SetPicture(item)
    local boxW, boxH = TILE_WIDTH - 12, 46
    if item.art == nil then
        --no store art: a plain card the same shape, with the still die on it,
        --so every set tile reads the same way.
        return gui.Panel{
            classes = {"tableDrawerSetCard"},
            bgimage = "panels/square.png",
            width = boxW,
            height = boxH,
            halign = "center",
            tmargin = 4,
            interactable = false,
            gui.Panel{
                bgimage = item.thumbnail,
                bgcolor = "white",
                width = 38,
                height = 38,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end
    return gui.Panel{
        bgimage = item.art,
        bgcolor = "clear",
        width = boxW,
        height = boxH,
        halign = "center",
        tmargin = 4,
        cornerRadius = 4,
        interactable = false,
        create = function(element)
            gui.GetImageDimensionsCallback(item.art, function(dims)
                if mod.unloaded or not element.valid or dims == nil or (dims.width or 0) <= 0 or (dims.height or 0) <= 0 then
                    return
                end
                --cover: the window keeps the box's aspect, centred on the art.
                local wFrac, hFrac = 1, 1
                if dims.width / dims.height > boxW / boxH then
                    wFrac = (boxW / boxH) / (dims.width / dims.height)
                else
                    hFrac = (dims.width / dims.height) / (boxW / boxH)
                end
                local left = (1 - wFrac) / 2
                local bottom = (1 - hFrac) / 2
                element.selfStyle.imageRect = {x1 = left, x2 = left + wFrac, y1 = bottom, y2 = bottom + hFrac}
                element.selfStyle.bgcolor = "white"
            end)
        end,
    }
end

--- @param item TableItemDef a dice-set item (DiceSetItems)
--- @return Panel
local function BuildSetTile(item)
    local chosen = (g_setSetting:Get() or "") == item.setValue
    return gui.Panel{
        classes = {"tableDrawerTile", cond(chosen, "selected", "ready")},
        bgimage = "panels/square.png",
        width = TILE_WIDTH,
        height = TILE_HEIGHT,
        hmargin = 4,
        vmargin = 4,
        flow = "vertical",
        swallowPress = true,
        data = {item = item},
        hover = gui.Tooltip("Dice from the drawer wear this set"),
        click = function(element)
            SelectDiceSet(item.setValue)
        end,
        SetPicture(item),
        gui.Label{
            classes = {"tableDrawerTileName"},
            text = item.name,
            fontSize = 12,
            textWrap = false,
            maxWidth = TILE_WIDTH - 8,
            tmargin = 6,
            interactable = false,
        },
    }
end

--- @param text string
--- @return Panel
local function SectionLabel(text)
    return gui.Label{
        classes = {"tableDrawerText"},
        text = text,
        width = "100%",
        tmargin = 4,
        lmargin = 4,
    }
end

RebuildDrawer = function()
    local grid = g_drawer.grid
    if grid == nil or not grid.valid then
        return
    end
    --the tiles are replaced: their dice go, and SyncPreviews makes new ones.
    DestroyPreviews()
    local items, text = ShownItems()
    local children = {}
    --the Dice category: the sets first, then the dice in the chosen set.
    if g_drawer.category == "dice" and g_drawer.search == "" then
        local current = g_setSetting:Get() or ""
        local currentName = "the default set"
        children[#children+1] = SectionLabel("Your dice sets")
        for _, setItem in ipairs(DiceSetItems()) do
            if setItem.setValue == current then
                currentName = setItem.name
            end
            children[#children+1] = BuildSetTile(setItem)
        end
        children[#children+1] = SectionLabel("In " .. currentName)
    end
    for _, item in ipairs(items) do
        children[#children+1] = BuildTile(item)
    end
    --Trinkets with Figure open: the uploaded figures, any being prepared,
    --and the tile that uploads another.
    if g_drawer.category == "trinkets" and g_drawer.search == "" and g_drawer.openRow == "figures" then
        children[#children+1] = SectionLabel("Your figures")
        for _, entry in ipairs(FigureLibrary()) do
            local blob = entry.blob
            local name = entry.name
            children[#children+1] = BuildTile{
                id = "figure:" .. blob,
                name = name,
                icon = "phosphor/user.png",
                figureBlob = blob,
                place = function(px, py, private)
                    TableDice.PlaceFigure(blob, name, px, py, private)
                end,
            }
        end
        for _, name in ipairs(g_drawer.uploading) do
            children[#children+1] = BuildTile{id = "uploading:" .. name, name = name, note = "Preparing...", icon = "phosphor/hourglass.png", action = function() end}
        end
        children[#children+1] = BuildTile{
            id = "upload-figure",
            name = "Upload STL",
            note = "Add a figure",
            icon = "phosphor/upload-simple-bold.png",
            action = function()
                TableDice.PickFigureFile()
            end,
        }
    end
    --Trinkets with Standee open: a standee for each character in the game.
    if g_drawer.category == "trinkets" and g_drawer.search == "" and g_drawer.openRow == "standees" then
        children[#children+1] = SectionLabel("Characters")
        for _, entry in ipairs(TableDice.StandeeCharacters()) do
            local charid = entry.charid
            children[#children+1] = BuildTile{
                id = "standee:" .. charid,
                name = entry.name,
                note = entry.note,
                icon = "phosphor/user.png",
                portrait = entry.portrait,
                place = function(px, py, private)
                    TableDice.AddTracker("standee", px, py, private, {charid = charid})
                end,
            }
        end
    end
    --Trackers with Hero open: a medallion for each hero in the game.
    if g_drawer.category == "trackers" and g_drawer.search == "" and g_drawer.openRow == "heroes" then
        children[#children+1] = SectionLabel("Heroes")
        local heroes = TableDice.Heroes()
        for _, hero in ipairs(heroes) do
            local charid = hero.charid
            children[#children+1] = BuildTile{
                id = "hero:" .. charid,
                tracker = "hero",
                trackerText = hero.value,
                name = hero.name,
                note = hero.resource,
                icon = "phosphor/user.png",
                place = function(px, py, private)
                    TableDice.AddTracker("hero", px, py, private, {charid = charid})
                end,
            }
        end
        if #heroes == 0 then
            children[#children+1] = BuildTile{id = "no-heroes", name = "No heroes", note = "None in this game", icon = "phosphor/user.png", action = function() end}
        end
    end
    grid.children = children
    local title = g_drawer.title
    if title ~= nil and title.valid then
        title.text = text
    end
    local side = g_drawer.side
    if side ~= nil and side.valid then
        for _, row in ipairs(side.children) do
            local catid = nil
            pcall(function() catid = row.data.catid end)
            if catid ~= nil then
                row:SetClass("selected", g_drawer.search == "" and catid == g_drawer.category)
            end
        end
    end
    local setRow = g_drawer.setRow
    if setRow ~= nil and setRow.valid then
        setRow:SetClass("collapsed", g_drawer.category ~= "dice" or g_drawer.search ~= "")
    end
end

--- @param catid string
--- @param name string
--- @param icon string
--- @return Panel
local function CategoryRow(catid, name, icon)
    return gui.Panel{
        classes = {"tableDrawerCat"},
        bgimage = "panels/square.png",
        width = "100%",
        height = 26,
        flow = "horizontal",
        hpad = 8,
        borderBox = true,
        data = {catid = catid},
        click = function(element)
            g_drawer.category = catid
            g_drawer.search = ""
            local input = g_drawer.searchInput
            if input ~= nil and input.valid then
                input.text = ""
            end
            RebuildDrawer()
        end,
        gui.Panel{
            classes = {"tableDrawerCatIcon"},
            bgimage = icon,
            width = 16,
            height = 16,
            valign = "center",
            rmargin = 8,
            interactable = false,
        },
        gui.Label{
            classes = {"tableDrawerCatLabel"},
            text = name,
            valign = "center",
            interactable = false,
        },
    }
end

--- @return Panel
local function BuildDrawer()
    local sideRows = {
        CategoryRow("recent", "Recent", "phosphor/clock-counter-clockwise.png"),
        CategoryRow("favourites", "Favourites", "phosphor/star.png"),
        gui.Panel{
            classes = {"tableDrawerDivider"},
            bgimage = "panels/square.png",
            width = "100%",
            height = 1,
            vmargin = 4,
        },
    }
    for _, cat in ipairs(CATEGORIES) do
        sideRows[#sideRows+1] = CategoryRow(cat.id, cat.name, cat.icon)
    end
    g_drawer.side = gui.Panel{
        width = 168,
        height = "100%",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        children = sideRows,
    }

    --Clear dice: only shown on the Dice category.
    g_drawer.setRow = gui.Panel{
        width = "auto",
        height = 26,
        flow = "horizontal",
        valign = "center",
        lmargin = 12,
        --takes every die off the table (or from behind the screen).
        gui.Panel{
            classes = {"tableDrawerToggle"},
            bgimage = "panels/square.png",
            width = "auto",
            height = 26,
            hpad = 8,
            lmargin = 8,
            borderBox = true,
            flow = "horizontal",
            valign = "center",
            click = function(element)
                TableDice.ClearDice(g_drawer.private)
            end,
            hover = gui.Tooltip("Take every die off the table (or from behind the screen, when opened there)"),
            gui.Panel{
                classes = {"tableDrawerToggleIcon"},
                bgimage = "phosphor/trash.png",
                width = 14,
                height = 14,
                valign = "center",
                rmargin = 6,
                interactable = false,
            },
            gui.Label{
                classes = {"tableDrawerToggleLabel"},
                text = "Clear dice",
                valign = "center",
                interactable = false,
            },
        },
    }

    g_drawer.searchInput = gui.SearchInput{
        placeholderText = "Search everything",
        text = "",
        borderBox = true,
        width = 260,
        height = 24,
        valign = "center",
        editlag = 0.1,
        edit = function(element)
            g_drawer.search = string.lower(element.text or "")
            RebuildDrawer()
        end,
        change = function(element)
            g_drawer.search = string.lower(element.text or "")
            RebuildDrawer()
        end,
    }

    local pinToggle = gui.Panel{
        classes = {"tableDrawerToggle"},
        bgimage = "panels/square.png",
        width = "auto",
        height = 26,
        hpad = 8,
        borderBox = true,
        flow = "horizontal",
        valign = "center",
        halign = "right",
        click = function(element)
            g_drawer.pinned = not g_drawer.pinned
            element:SetClass("selected", g_drawer.pinned)
        end,
        hover = gui.Tooltip("Keep the drawer open after adding something"),
        gui.Panel{
            classes = {"tableDrawerToggleIcon"},
            bgimage = "phosphor/push-pin.png",
            width = 14,
            height = 14,
            valign = "center",
            rmargin = 6,
            interactable = false,
        },
        gui.Label{
            classes = {"tableDrawerToggleLabel"},
            text = "Keep open",
            valign = "center",
            interactable = false,
        },
    }

    local closeButton = gui.Panel{
        classes = {"tableDrawerToggle"},
        bgimage = "panels/square.png",
        width = 26,
        height = 26,
        valign = "center",
        halign = "right",
        lmargin = 4,
        click = function(element)
            CloseDrawer()
        end,
        hover = gui.Tooltip("Close"),
        gui.Panel{
            classes = {"tableDrawerToggleIcon"},
            bgimage = "phosphor/x.png",
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }

    local header = gui.Panel{
        width = "100%",
        height = 30,
        flow = "horizontal",
        g_drawer.searchInput,
        g_drawer.setRow,
        pinToggle,
        closeButton,
    }

    g_drawer.title = gui.Label{
        classes = {"tableDrawerText"},
        text = "",
        tmargin = 8,
        bmargin = 4,
    }

    g_drawer.grid = gui.Panel{
        width = "100%",
        height = "100%-70",
        flow = "horizontal",
        wrap = true,
        vscroll = true,
        valign = "top",
    }

    local main = gui.Panel{
        width = "100%-169",
        height = "100%",
        flow = "vertical",
        pad = 12,
        borderBox = true,
        header,
        g_drawer.title,
        g_drawer.grid,
    }

    g_drawer.panel = gui.Panel{
        classes = {"tableDrawer", "collapsed"},
        bgimage = "panels/square.png",
        floating = true,
        halign = "left",
        valign = "bottom",
        x = DRAWER_LEFT,
        bmargin = 10,
        width = string.format("100%%-%d", DRAWER_LEFT + 16),
        height = DRAWER_HEIGHT,
        flow = "horizontal",
        swallowPress = true,
        g_drawer.side,
        gui.Panel{
            classes = {"tableDrawerDivider"},
            bgimage = "panels/square.png",
            width = 1,
            height = "100%",
        },
        main,
    }
    return g_drawer.panel
end

--- Opens the drawer, or closes it if it is already open from the same place.
--- private: tiles clicked in land behind the Director's Screen.
--- @param private boolean
function TableDice.ToggleDrawer(private)
    local panel = g_drawer.panel
    if not TableDice.TrayEnabled() or panel == nil or not panel.valid then
        return
    end
    if TableDice.DrawerOpen() and g_drawer.private == private then
        CloseDrawer()
        return
    end
    g_drawer.private = private
    panel:SetClass("collapsed", false)
    panel:SetAsLastSibling()
    if g.tableButton ~= nil and g.tableButton.valid then
        g.tableButton:SetClass("selected", not private)
    end
    RebuildDrawer()
end

--- For debugging: the trackers in each store, and which have panels.
--- @return table
function TableDice.DebugTrackers()
    local result = {shared = {}, private = {}, built = {}, kinds = {}, path = SharedDoc().path}
    for kind, items in pairs(SharedDoc().data) do
        local n = 0
        if type(items) == "table" then
            for _ in pairs(items) do
                n = n + 1
            end
        end
        result.kinds[kind] = n
    end
    for id, record in pairs(SharedItems("trackers")) do
        result.shared[id] = record.type
    end
    for id, record in pairs(PrivateItems("trackers")) do
        result.private[id] = record.type
    end
    for id, handle in pairs(g.trackers) do
        local entry = {valid = handle.panel.valid, token = handle.token ~= nil, x = handle.panel.x, y = handle.panel.y}
        if handle.token ~= nil and handle.token.valid then
            entry.image = handle.token.image
            entry.size = handle.token.size
        end
        if handle.panel.valid then
            entry.rect = Tabletop.PanelRect(handle.panel)
        end
        result.built[id] = entry
    end
    return result
end

--- For tests: every die this client shows, as {id, faces, face, private, x, y}.
--- @return table[]
function TableDice.DebugDice()
    local result = {}
    for id, handle in pairs(g.handles) do
        result[#result+1] = {id = id, faces = handle.faces, face = handle.die.face, private = handle.private, x = handle.die.x, y = handle.die.y}
    end
    return result
end

--- Whether a die was just right-clicked: the table's own right-click menu
--- (Tabletop.lua) stands down, as the same click also reaches the table.
--- @return boolean
function TableDice.DieJustRightClicked()
    return g.dieRightClickedAt ~= nil and dmhub.Time() - g.dieRightClickedAt < 0.5
end

--- For tests: opens a die's right-click menu, as a right-click on it would.
--- @param id string
function TableDice.DebugOpenDieMenu(id)
    ShowDieMenu(id)
end

--- Removes every die on the table (shared) or behind the screen (private).
--- @param private boolean
function TableDice.ClearDice(private)
    if private then
        SavePrivate({}, "dice")
        return
    end
    local doc = SharedDoc()
    doc:BeginChange()
    doc.data.dice = {}
    doc:CompleteChange("Remove table dice", {undoable = false})
end

--- The dice button for the Director's Screen's caption row (DirectorScreen.lua).
--- @return Panel
function TableDice.CreateScreenButton()
    return gui.Panel{
        classes = {"tableDiceButton", cond(TableDice.TrayEnabled(), nil, "collapsed")},
        --shown only with the dev:directortray gate on.
        monitor = "dev:directortray",
        events = {
            monitor = function(element)
                element:SetClass("collapsed", not TableDice.TrayEnabled())
            end,
        },
        bgimage = "phosphor/package.png",
        bgcolor = "#ffffff70",
        width = 16,
        height = 16,
        valign = "center",
        lmargin = 10,
        swallowPress = true,
        hover = function(element)
            element.selfStyle.bgcolor = "#ffffffe0"
            gui.Tooltip("Table items: add things behind the screen")(element)
        end,
        dehover = function(element)
            element.selfStyle.bgcolor = "#ffffff70"
        end,
        click = function(element)
            TableDice.ToggleDrawer(true)
        end,
    }
end

----------------------------------------------------------------------
--Keeping the engine's dice in step with the stores.

--- @param id string
--- @param record TableDieRecord
--- @param private boolean
--- @return nil|{die: TableDieLua, seq: number, private: boolean}
local function BuildDie(id, record, private)
    local px, py = TableToScreen(record.fx or 0.5, record.fy or 0.5)
    local model = record.model --[[@as string|nil]]
    if model == "" then
        model = nil
    end
    local die = dice.CreateTableDie{
        faces = record.faces or 20,
        model = model,
        x = px,
        y = py,
        face = record.face,
        yaw = record.yaw or 0,
    }
    if die == nil then
        return nil
    end
    local handle = {die = die, seq = record.seq or 0, private = private, faces = record.faces, model = record.model}
    die:SetRest(px, py, record.face or 1, record.yaw or 0, record.pick or 0)
    --a die thrown onto the table (out of the drawer) arrives by its throw.
    local roll = record.roll
    if roll ~= nil and record.rollAt ~= nil then
        local elapsed = dmhub.serverTime - record.rollAt
        if elapsed < (roll.duration or 1) then
            local x1, y1 = TableToScreen(roll.fromfx or record.fx, roll.fromfy or record.fy)
            local x2, y2 = TableToScreen(roll.tofx or record.fx, roll.tofy or record.fy)
            die:PlayRoll({
                fromx = x1, fromy = y1, tox = x2, toy = y2,
                lift = roll.lift, face = roll.face, yaw = roll.yaw, pick = roll.pick,
                seed = roll.seed, duration = roll.duration,
            }, math.max(0, elapsed))
        end
    end
    die.callbacks = {
        onRoll = function(roll)
            local h = g.handles[id]
            if h == nil then
                return
            end
            local ffx, ffy = ScreenToTable(roll.fromx, roll.fromy)
            local tfx, tfy = ScreenToTable(roll.tox, roll.toy)
            local shared = {
                fromfx = ffx, fromfy = ffy, tofx = tfx, tofy = tfy,
                lift = roll.lift, face = roll.face, yaw = roll.yaw, pick = roll.pick,
                seed = roll.seed, duration = roll.duration,
            }
            Modify(id, h.private, "Roll a table die", function(r)
                r.fx, r.fy = tfx, tfy
                r.face, r.yaw, r.pick = roll.face, roll.yaw, roll.pick
                r.roll = shared
                r.rollAt = dmhub.serverTime
                r.rollBy = dmhub.userid
                r.seq = (r.seq or 0) + 1
                h.seq = r.seq
            end)
        end,
        onMove = function(x, y)
            local h = g.handles[id]
            if h == nil then
                return
            end
            local fx, fy = ScreenToTable(x, y)
            --the Director moves a die across the screen's edge: its privacy follows.
            if dmhub.isDM then
                local behind = BehindScreen(fx)
                if behind ~= h.private then
                    Transfer(id, behind, fx, fy)
                    return
                end
            end
            Modify(id, h.private, "Move a table die", function(r)
                r.fx, r.fy = fx, fy
                r.roll, r.rollAt, r.rollBy = nil, nil, nil
                r.seq = (r.seq or 0) + 1
                h.seq = r.seq
            end)
        end,
        onRightClick = function(x, y)
            g.dieRightClickedAt = dmhub.Time()
            ShowDieMenu(id)
        end,
    }
    return handle
end

--- @param handle {die: TableDieLua, seq: number, private: boolean}
--- @param record TableDieRecord
local function UpdateDie(handle, record)
    if (record.seq or 0) == handle.seq then
        return
    end
    handle.seq = record.seq or 0
    local roll = record.roll
    if roll ~= nil and record.rollBy ~= dmhub.userid and record.rollAt ~= nil then
        local fx1, fy1 = TableToScreen(roll.fromfx or record.fx, roll.fromfy or record.fy)
        local fx2, fy2 = TableToScreen(roll.tofx or record.fx, roll.tofy or record.fy)
        handle.die:PlayRoll({
            fromx = fx1, fromy = fy1, tox = fx2, toy = fy2,
            lift = roll.lift, face = roll.face, yaw = roll.yaw, pick = roll.pick,
            seed = roll.seed, duration = roll.duration,
        }, math.max(0, dmhub.serverTime - record.rollAt))
        return
    end
    local px, py = TableToScreen(record.fx or 0.5, record.fy or 0.5)
    handle.die:SetRest(px, py, record.face or 1, record.yaw or 0, record.pick or 0)
end

local DestroyTrackers

local function DestroyFigures()
    for id, handle in pairs(g.figures) do
        if handle.figure.valid then
            handle.figure:Destroy()
        end
        g.figures[id] = nil
    end
end

local function DestroyAll()
    for id, handle in pairs(g.handles) do
        if handle.die.valid then
            handle.die:Destroy()
        end
        g.handles[id] = nil
    end
    DestroyFigures()
    DestroyTrackers()
end

--Every die that should exist, with whether it is private.
--- @return table<string, {record: TableDieRecord, private: boolean}>
local function Wanted()
    local result = {}
    for id, record in pairs(SharedDice()) do
        if type(record) == "table" then
            result[id] = {record = record, private = false}
        end
    end
    if dmhub.isDM then
        for id, record in pairs(PrivateDice()) do
            if type(record) == "table" then
                result[id] = {record = record, private = true}
            end
        end
    end
    return result
end

----------------------------------------------------------------------
--Figures: 3D miniatures from STL files (TableFigures.cs in the engine).
--The Director picks an STL; this machine simplifies it (cached), uploads the
--small simplified mesh, and stores only its blob id with the spot and pose,
--in the same two stores as the dice (kind "figures"). Every client makes
--the figure from the blob id. Anyone can drag a figure or click it to turn
--it; the Director right-clicks to turn or remove it.

--- @class TableFigureRecord
--- @field blob string the uploaded simplified mesh
--- @field name string
--- @field fx number
--- @field fy number
--- @field yaw number
--- @field tilt number
--- @field height number on-screen height in pixels
--- @field seq number

local FIGURE_HEIGHT = 150
local FIGURE_TILT = 62

--A figure's right-click menu (Director only): turn it, or take it away.
--- @param id string
local function ShowFigureMenu(id)
    local handle = g.figures[id]
    local anchor = MenuAnchor()
    if handle == nil or anchor == nil or not dmhub.isDM then
        return
    end
    local private = handle.private
    local w, h = TableSize()
    local fx, fy = ScreenToTable(handle.figure.x, handle.figure.y)
    local scale = Mapping()
    anchor.x = fx * w
    anchor.y = fy * h - (handle.figure.height * 0.55) * scale
    g.dieRightClickedAt = dmhub.Time()
    dmhub.Schedule(0.02, function()
        if mod.unloaded or not anchor.valid then
            return
        end
        local menu = gui.ContextMenu{
            entries = {
                {
                    text = "Turn",
                    click = function()
                        CloseMenu()
                        Modify(id, private, "Turn a table figure", function(r)
                            r.yaw = ((r.yaw or 0) + 45) % 360
                            r.seq = (r.seq or 0) + 1
                        end, "figures")
                    end,
                },
                {
                    text = "Remove Figure",
                    click = function()
                        CloseMenu()
                        Modify(id, private, "Remove a table figure", function() return false end, "figures")
                    end,
                },
            },
        }
        if menu == nil then
            return
        end
        local style = menu.selfStyle
        if style ~= nil then
            style.valign = "top"
            style.halign = "center"
        end
        anchor.popup = menu
    end)
end

--- Asks for an STL file and adds it to the Director's figures (the drawer's
--- Trinkets > Figure row). Nothing is placed: the figure is placed from there.
function TableDice.PickFigureFile()
    if not dmhub.isDM or dice.CreateTableFigure == nil then
        return
    end
    dmhub.OpenFileDialog{
        id = "tablefigure",
        extensions = {"stl"},
        multiFiles = false,
        prompt = "Choose a miniature (STL file)",
        open = function(path)
            TableDice.UploadFigureFile(path)
        end,
    }
end

--- Prepares an STL (simplified here, cached; a big file takes a while the
--- first time), uploads its small mesh, and adds it to the Director's figures.
--- @param path string
function TableDice.UploadFigureFile(path)
    local name = string.match(path, "([^/\\]+)%.[sS][tT][lL]$") or "Figure"
    local loader = dice.CreateTableFigure{path = path, x = -1000, y = -1000, height = FIGURE_HEIGHT, tilt = FIGURE_TILT}
    if loader == nil then
        gui.ModalMessage{title = "Figure", message = "That file could not be opened."}
        return
    end
    --only the upload needs it: it never shows.
    loader:SetVisible(false)
    g_drawer.uploading[#g_drawer.uploading+1] = name
    RebuildDrawer()
    local function Finish()
        for i, uploading in ipairs(g_drawer.uploading) do
            if uploading == name then
                table.remove(g_drawer.uploading, i)
                break
            end
        end
        if loader.valid then
            loader:Destroy()
        end
        RebuildDrawer()
    end
    local deadline = dmhub.Time() + 600
    local function Poll()
        if mod.unloaded or not loader.valid then
            return
        end
        local status = loader.status
        if status == "ready" then
            loader:Upload{
                done = function(blob)
                    local library = FigureLibrary()
                    local known = false
                    for _, entry in ipairs(library) do
                        if entry.blob == blob then
                            known = true
                        end
                    end
                    if not known then
                        library[#library+1] = {blob = blob, name = name}
                        SaveFigureLibrary(library)
                    end
                    Finish()
                end,
                error = function(message)
                    Finish()
                    gui.ModalMessage{title = "Figure", message = "The figure could not be uploaded: " .. tostring(message)}
                end,
            }
            return
        end
        if string.sub(status, 1, 5) == "error" or dmhub.Time() > deadline then
            Finish()
            gui.ModalMessage{title = "Figure", message = "That STL could not be read (" .. status .. ")."}
            return
        end
        dmhub.Schedule(0.25, Poll)
    end
    Poll()
end

--- Stands an uploaded figure at (px, py) screen pixels, for everyone.
--- @param blob string
--- @param name string
--- @param px number
--- @param py number
--- @param private boolean behind the Director's Screen
function TableDice.PlaceFigure(blob, name, px, py, private)
    if not dmhub.isDM then
        return
    end
    local fx, fy = ScreenToTable(px, py)
    Add(dmhub.GenerateGuid(), private, {
        blob = blob,
        name = name,
        fx = fx,
        fy = fy,
        yaw = 0,
        tilt = FIGURE_TILT,
        height = FIGURE_HEIGHT,
        seq = 1,
    }, "figures")
end

--- @param id string
--- @param record TableFigureRecord
--- @param private boolean
local function BuildFigure(id, record, private)
    local px, py = TableToScreen(record.fx or 0.5, record.fy or 0.5)
    local figure = dice.CreateTableFigure{
        blob = record.blob,
        x = px,
        y = py,
        height = record.height or FIGURE_HEIGHT,
        tilt = record.tilt or FIGURE_TILT,
        yaw = record.yaw or 0,
    }
    if figure == nil then
        return nil
    end
    local handle = {figure = figure, seq = record.seq or 0, private = private, blob = record.blob}
    figure.callbacks = {
        --yaw: the mouse wheel turns a figure while it is held.
        onMove = function(x, y, yaw)
            local h = g.figures[id]
            if h == nil then
                return
            end
            local fx, fy = ScreenToTable(x, y)
            if dmhub.isDM then
                local behind = BehindScreen(fx)
                if behind ~= h.private then
                    Transfer(id, behind, fx, fy, "figures", {yaw = yaw})
                    return
                end
            end
            Modify(id, h.private, "Move a table figure", function(r)
                r.fx, r.fy = fx, fy
                if yaw ~= nil then
                    r.yaw = yaw
                end
                r.seq = (r.seq or 0) + 1
                h.seq = r.seq
            end, "figures")
        end,
        --a click turns it a little, as you would a mini on the table.
        onClick = function(x, y)
            local h = g.figures[id]
            if h == nil then
                return
            end
            Modify(id, h.private, "Turn a table figure", function(r)
                r.yaw = ((r.yaw or 0) + 45) % 360
                r.seq = (r.seq or 0) + 1
            end, "figures")
        end,
        onRightClick = function(x, y)
            ShowFigureMenu(id)
        end,
    }
    return handle
end

--Keeps the engine's figures in line with the stores (TableDice.Sync).
--- @param covered boolean a maximized window covers the table
--- @param screenOpen boolean
--- @param x1 number
--- @param y1 number
--- @param x2 number
--- @param y2 number
local function SyncFigures(covered, screenOpen, x1, y1, x2, y2)
    if dice.CreateTableFigure == nil then
        return
    end
    local wanted = {}
    for id, record in pairs(SharedItems("figures")) do
        if type(record) == "table" and type(record.blob) == "string" then
            wanted[id] = {record = record, private = false}
        end
    end
    if dmhub.isDM then
        for id, record in pairs(PrivateItems("figures")) do
            if type(record) == "table" and type(record.blob) == "string" then
                wanted[id] = {record = record, private = true}
            end
        end
    end
    for id, handle in pairs(g.figures) do
        local want = wanted[id]
        if want == nil or not handle.figure.valid or want.private ~= handle.private or want.record.blob ~= handle.blob then
            if handle.figure.valid then
                handle.figure:Destroy()
            end
            g.figures[id] = nil
        end
    end
    for id, want in pairs(wanted) do
        local handle = g.figures[id]
        if handle == nil then
            handle = BuildFigure(id, want.record, want.private)
            g.figures[id] = handle
        elseif (want.record.seq or 0) ~= handle.seq then
            handle.seq = want.record.seq or 0
            local px, py = TableToScreen(want.record.fx or 0.5, want.record.fy or 0.5)
            handle.figure:SetRest(px, py)
            handle.figure.yaw = want.record.yaw or 0
            handle.figure.tilt = want.record.tilt or FIGURE_TILT
            handle.figure.height = want.record.height or FIGURE_HEIGHT
        end
        if handle ~= nil then
            handle.figure:SetBounds(x1, y1, x2, y2)
            handle.figure:SetVisible(not covered and (not want.private or screenOpen))
        end
    end
end

----------------------------------------------------------------------
--Trackers (TABLE_DICE_BRIEF.md, "Trackers category"): medallion tokens that
--hold a number everyone sees. Malice and Hero Tokens ARE the game's global
--resources (CharacterResource), so a change here is the same change the action
--bar and the journal's [[resource:...]] counter see. A Counter keeps its own
--number in its record. Records live in the same two stores as the dice
--(kind "trackers"); the panels are ordinary UI on this layer.

--- @class TableTrackerRecord
--- @field type string "malice", "herotokens", "counter", "hero", "countdown" or "sandtimer"
--- @field charid nil|string a hero medallion's hero
--- @field round nil|number a countdown: the initiative round it last counted
--- @field combat nil|string a countdown: the combat (initiative guid) that round belongs to
--- @field duration nil|number a sand timer's length, in seconds
--- @field startedAt nil|number a sand timer: dmhub.serverTime when it was flipped
--- @field result nil|string a coin: "heads" or "tails"
--- @field flipAt nil|number a coin: dmhub.serverTime of its last flip
--- @field flipSeq nil|number a coin: bumped on every flip, so clients play it once
--- @field yaw nil|number a pointer's turn, in degrees clockwise from pointing up the screen
--- @field fx number
--- @field fy number
--- @field seq number
--- @field name nil|string a counter's caption
--- @field value nil|number a counter's number
--- @field playersCanChange nil|boolean a counter players may change too
--- @field history nil|table[] a counter's recent changes {userid, timestamp, set, note}

--the token's size, and its - / + buttons, in layer units.
local TRACKER_SIZE = 72
local TRACKER_STEP = 26
local TRACKER_WIDTH = TRACKER_SIZE + 2 * (TRACKER_STEP + 6)
local TRACKER_HEIGHT = TRACKER_SIZE + 26
local TRACKER_HISTORY_MAX = 8

--resourceKey names the CharacterResource field holding the resource's id.
--Draw Steel's rules set those after this file loads, so they are read when used.
--- @type table<string, {name: string, resourceKey: nil|string, trinket: nil|boolean, icon: nil|string}>
local TRACKER_TYPES = {
    malice = {name = "Malice", resourceKey = "maliceResourceId"},
    herotokens = {name = "Hero Tokens", resourceKey = "heroTokenId"},
    counter = {name = "Counter"},
    hero = {name = "Hero"},
    countdown = {name = "Countdown"},
    sandtimer = {name = "Sand timer"},
    --Trinkets (TABLE_DICE_BRIEF.md, "Trinkets category"): pieces with no
    --number that anyone can move, flip, turn or remove (decision 2).
    coin = {name = "Coin", trinket = true},
    gem = {name = "Gem", trinket = true},
    skull = {name = "Skull", trinket = true, icon = "phosphor/skull.png"},
    key = {name = "Key", trinket = true, icon = "phosphor/key.png"},
    standee = {name = "Standee", trinket = true},
    pointer = {name = "Pointer", trinket = true},
}

--- @param record TableTrackerRecord
--- @return boolean
local function IsTrinket(record)
    local info = TRACKER_TYPES[record.type]
    return info ~= nil and info.trinket == true
end

--How long a flip takes (the engine's spin), and how long its result shows.
local COIN_FLIP_SECONDS = 1.1
local COIN_RESULT_SECONDS = 6

--The sand timer's lengths, in seconds (its right-click menu).
local SAND_LENGTHS = {30, 60, 180, 300}

--A hero medallion's hero (TABLE_DICE_BRIEF.md, decision 5), or nil if it is
--gone from the game.
--- @param record TableTrackerRecord
--- @return nil|CharacterToken
local function HeroToken(record)
    if type(record.charid) ~= "string" then
        return nil
    end
    return dmhub.GetCharacterById(record.charid)
end

--Whether combat is on. A hero's heroic resource and surges exist only in
--combat (the game clears them outside it), so the medallion rests then.
--- @return boolean
local function InCombat()
    local q = dmhub.initiativeQueue
    return q ~= nil and not q.hidden
end

--What a hero's big number is called: the class's heroic resource (Wrath...).
--- @param token nil|CharacterToken
--- @return string
local function HeroResourceName(token)
    local name = "Heroic Resource"
    if token ~= nil and token.properties ~= nil then
        pcall(function() name = token.properties:GetHeroicResourceName() or name end)
    end
    return name
end

--- Every hero in the game, for the drawer's Hero row: {charid, name, resource, value}.
--- @return {charid: string, name: string, resource: string, value: string}[]
function TableDice.Heroes()
    local result = {}
    for charid, token in pairs(dmhub.GetAllCharacters() or {}) do
        --a hero with a class: blank characters left from character creation
        --are heroes too, but have nothing to track.
        local isHero = false
        pcall(function()
            local props = token.properties --[[@as character]]
            isHero = props ~= nil and props:IsHero() and props:GetClass() ~= nil
        end)
        if isHero then
            local value = token.properties:GetUnboundedResourceQuantity(CharacterResource.heroicResourceId) or 0
            result[#result+1] = {
                charid = charid,
                name = token.name or "Hero",
                resource = HeroResourceName(token),
                value = string.format("%d", math.floor(value)),
            }
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--- Every character a standee can show, heroes first: {charid, name, note, portrait}.
--- @return {charid: string, name: string, note: string, portrait: nil|string}[]
function TableDice.StandeeCharacters()
    local heroes, others = {}, {}
    for charid, token in pairs(dmhub.GetAllCharacters() or {}) do
        local isHero = false
        pcall(function() isHero = token.properties ~= nil and token.properties:IsHero() end)
        --nameless characters (blanks left from character creation) are skipped.
        if type(token.name) ~= "string" or token.name == "" then
            goto continue
        end
        local entry = {
            charid = charid,
            name = token.name or "Character",
            note = cond(isHero, "Hero", "Character"),
            --no portrait: the tile shows the plain person icon instead.
            portrait = cond(type(token.portrait) == "string" and token.portrait ~= "", token.portrait, nil),
        }
        if isHero then
            heroes[#heroes+1] = entry
        else
            others[#others+1] = entry
        end
        ::continue::
    end
    local byName = function(a, b) return a.name < b.name end
    table.sort(heroes, byName)
    table.sort(others, byName)
    local result = heroes
    for _, entry in ipairs(others) do
        if #result >= 60 then
            break
        end
        result[#result+1] = entry
    end
    return result
end

--A sand timer's seconds left (its whole length until it is flipped).
--- @param record TableTrackerRecord
--- @return number
local function SandLeft(record)
    local duration = tonumber(record.duration) or 60
    if type(record.startedAt) ~= "number" then
        return duration
    end
    return math.max(0, duration - (dmhub.serverTime - record.startedAt))
end

--Whether a timer has run out: a countdown at zero, or a flipped sand timer
--that is empty.
--- @param record TableTrackerRecord
--- @return boolean
local function TrackerExpired(record)
    if record.type == "countdown" then
        return (tonumber(record.value) or 0) <= 0
    end
    if record.type == "sandtimer" then
        return type(record.startedAt) == "number" and SandLeft(record) <= 0
    end
    return false
end

--The game resource a live tracker shows, or nil for a counter.
--- @param record TableTrackerRecord
--- @return nil|string
local function TrackerResourceId(record)
    local info = TRACKER_TYPES[record.type]
    if info == nil or info.resourceKey == nil then
        return nil
    end
    return rawget(CharacterResource, info.resourceKey)
end

--- @param record TableTrackerRecord
--- @return boolean
local function TrackerChangeable(record)
    if dmhub.isDM or IsTrinket(record) then
        return true
    end
    if record.type == "herotokens" then
        return true
    end
    --a hero's own player changes their medallion (as on their sheet).
    if record.type == "hero" then
        local token = HeroToken(record)
        return token ~= nil and token.canControlAsUser == true
    end
    return record.type == "counter" and record.playersCanChange == true
end

--- @param record TableTrackerRecord
--- @return number
local function TrackerValue(record)
    local resourceid = TrackerResourceId(record)
    if resourceid ~= nil then
        return CharacterResource.GetGlobalResource(resourceid) or 0
    end
    if record.type == "hero" then
        local token = HeroToken(record)
        if token == nil or token.properties == nil then
            return 0
        end
        return token.properties:GetUnboundedResourceQuantity(CharacterResource.heroicResourceId) or 0
    end
    if record.type == "sandtimer" then
        return SandLeft(record)
    end
    return tonumber(record.value) or 0
end

--What a tracker's face shows: its number, or a sand timer's m:ss.
--- @param record TableTrackerRecord
--- @return string
local function TrackerText(record)
    local value = TrackerValue(record)
    if record.type == "sandtimer" then
        local secs = math.ceil(value)
        return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    end
    if record.type == "hero" and not InCombat() then
        return "-"
    end
    --a coin's face says H (its back says T); other trinkets say nothing.
    if record.type == "coin" then
        return "H"
    end
    if IsTrinket(record) then
        return ""
    end
    return string.format("%d", math.floor(value))
end

--- @param record TableTrackerRecord
--- @return string
local function TrackerName(record)
    if record.type == "counter" and type(record.name) == "string" and record.name ~= "" then
        return record.name
    end
    if record.type == "hero" or record.type == "standee" then
        local token = HeroToken(record)
        return (token ~= nil and token.name) or TRACKER_TYPES[record.type].name
    end
    --a coin says how it landed for a few seconds; other trinkets have no plate.
    if record.type == "coin" then
        local since = type(record.flipAt) == "number" and dmhub.serverTime - record.flipAt or nil
        if since ~= nil and since >= COIN_FLIP_SECONDS and since < COIN_FLIP_SECONDS + COIN_RESULT_SECONDS then
            return cond(record.result == "tails", "Tails", "Heads")
        end
        return ""
    end
    if IsTrinket(record) then
        return ""
    end
    if TrackerExpired(record) then
        return "Time's up"
    end
    local info = TRACKER_TYPES[record.type]
    return (info ~= nil and info.name) or "Tracker"
end

--Sets a tracker's number: the game resource for a live tracker, the record
--for a counter (with a line in its history, kept as plain tables so the
--Director's private store can hold it too).
--- @param id string
--- @param private boolean
--- @param record TableTrackerRecord
--- @param n number
--- @param note string
local function SetTrackerValue(id, private, record, n, note)
    if not TrackerChangeable(record) then
        return
    end
    n = round(n)
    local resourceid = TrackerResourceId(record)
    if resourceid ~= nil then
        local resourceInfo = (dmhub.GetTable(CharacterResource.tableName) or {})[resourceid]
        if (resourceInfo == nil or not resourceInfo.mayBeNegative) and n < 0 then
            n = 0
        end
        CharacterResource.SetGlobalResource(resourceid, n, note)
        return
    end
    if record.type == "hero" then
        local token = HeroToken(record)
        if token == nil then
            return
        end
        local current = TrackerValue(record)
        token:ModifyProperties{
            description = "Change " .. HeroResourceName(token),
            execute = function()
                token.properties:AddUnboundedResource(CharacterResource.heroicResourceId, n - current, note)
            end,
        }
        return
    end
    if record.type == "countdown" and n < 0 then
        n = 0
    end
    Modify(id, private, "Change a table counter", function(r)
        r.value = n
        local history = r.history
        if type(history) ~= "table" then
            history = {}
        end
        history[#history+1] = {userid = dmhub.userid, timestamp = ServerTimestamp(), set = n, note = note}
        while #history > TRACKER_HISTORY_MAX do
            table.remove(history, 1)
        end
        r.history = history
        r.seq = (r.seq or 0) + 1
    end, "trackers")
end

--A counter's history in the shape gui.StatsHistoryTooltip takes.
--- @param record TableTrackerRecord
--- @return table[]
local function CounterHistory(record)
    local result = {}
    for _, entry in ipairs(record.history or {}) do
        if type(entry) == "table" then
            result[#result+1] = {
                who = dmhub.GetDisplayName(entry.userid),
                color = "#ccccccff",
                when = DescribeServerTimestamp(entry.timestamp),
                value = entry.set,
                note = entry.note or "Set on the table",
            }
        end
    end
    return result
end

--- @param record TableTrackerRecord
--- @return table[]
local function TrackerHistory(record)
    local resourceid = TrackerResourceId(record)
    if resourceid ~= nil then
        return CharacterResource.GetGlobalResourceHistory(resourceid)
    end
    if record.type == "hero" then
        --read without GetStatHistory, which would make an empty one.
        local token = HeroToken(record)
        local history = token ~= nil and token.properties ~= nil and token.properties:try_get(CharacterResource.heroicResourceId .. "_history") or nil
        if history ~= nil and history.typeName == "StatHistory" then
            return history:GetHistory()
        end
        return {}
    end
    return CounterHistory(record)
end

--The history tooltip's heading: a hero's shows their resource's name.
--- @param record TableTrackerRecord
--- @return string
local function TrackerHistoryTitle(record)
    if record.type == "hero" then
        local name = HeroResourceName(HeroToken(record))
        if not InCombat() then
            return name .. " (only in combat)"
        end
        return name
    end
    return TrackerName(record)
end

--The token itself: its shape tells live trackers apart from plain ones.
--Malice is the red cost diamond (as on the action bar), Hero Tokens a gold
--coin, a Counter a neutral stone. The value label sits on top, unrotated.
--Each tracker's 3D token (TableTrackers.cs in the engine): its outline and
--metals. A hero is steel and blue enamel, a countdown bronze and black, a
--sand timer gold and sand.
local TRACKER_LOOKS = {
    malice = {shape = "diamond"},
    herotokens = {shape = "coin"},
    counter = {shape = "stone"},
    hero = {shape = "coin", bezel = "steel", face = "blueEnamel"},
    countdown = {shape = "coin", bezel = "bronze", face = "blackEnamel"},
    sandtimer = {shape = "coin", bezel = "gold", face = "sand"},
    --a pewter face, so its light H and T read (light on silver did not).
    coin = {shape = "flipcoin", bezel = "silver", face = "pewter"},
    gem = {shape = "gem", bezel = "ruby", face = "ruby"},
    skull = {shape = "coin", bezel = "steel", face = "pewter"},
    key = {shape = "coin", bezel = "steel", face = "pewter"},
    standee = {shape = "coin", bezel = "bronze", face = "blackEnamel"},
    pointer = {shape = "arrow", bezel = "gold", face = "redEnamel"},
}

--The flat medallions' colours for the round ones (the drawer's tiles, and an
--engine without 3D tokens): fill, rim, inner ring.
local FLAT_COINS = {
    herotokens = {"#B8892B", "#F0CD6A", "#8A6418"},
    hero = {"#1C2E7A", "#C9CDD3", "#3B55B8"},
    countdown = {"#141416", "#C28150", "#5A3A22"},
    sandtimer = {"#D9B27A", "#F0CD6A", "#9A7440"},
    coin = {"#C9CCD2", "#F2F3F6", "#8E929A"},
    gem = {"#9E0F28", "#E0445C", "#6A0A1A"},
    skull = {"#6E7076", "#C9CDD3", "#4A4C52"},
    key = {"#6E7076", "#C9CDD3", "#4A4C52"},
    standee = {"#141416", "#C28150", "#5A3A22"},
    pointer = {"#9E0F28", "#F0CD6A", "#6A0A1A"},
}

--- @param ttype string
--- @param size number
--- @param label Panel
--- @return Panel
function TableDice.TrackerToken(ttype, size, label)
    local shape
    if ttype == "malice" then
        shape = gui.Panel{
            width = size * 0.72,
            height = size * 0.72,
            halign = "center",
            valign = "center",
            rotate = 45,
            bgimage = true,
            bgcolor = "#DE1E47",
            borderWidth = math.max(2, size * 0.04),
            borderColor = "#FF5076",
            interactable = false,
        }
    elseif FLAT_COINS[ttype] ~= nil then
        local colors = FLAT_COINS[ttype]
        shape = gui.Panel{
            width = size * 0.9,
            height = size * 0.9,
            halign = "center",
            valign = "center",
            bgimage = true,
            bgcolor = colors[1],
            cornerRadius = size * 0.45,
            borderWidth = math.max(2, size * 0.04),
            borderColor = colors[2],
            interactable = false,
            --the coin's inner ring.
            gui.Panel{
                width = "78%",
                height = "78%",
                halign = "center",
                valign = "center",
                bgimage = true,
                bgcolor = "clear",
                cornerRadius = size * 0.35,
                borderWidth = math.max(1, size * 0.025),
                borderColor = colors[3],
                interactable = false,
            },
        }
    else
        shape = gui.Panel{
            width = size * 0.86,
            height = size * 0.86,
            halign = "center",
            valign = "center",
            bgimage = true,
            bgcolor = "#4A4A50",
            cornerRadius = size * 0.26,
            borderWidth = math.max(2, size * 0.04),
            borderColor = "#86868E",
            interactable = false,
        }
    end
    return gui.Panel{
        width = size,
        height = size,
        halign = "center",
        valign = "top",
        flow = "none",
        interactable = false,
        shape,
        label,
    }
end

--- Puts a tracker on the table, for everyone (or behind the screen).
--- @param ttype string "malice", "herotokens", "counter", "hero", "countdown" or "sandtimer"
--- @param px number screen pixels
--- @param py number
--- @param private boolean
--- @param fields? table more of the record: a hero's charid, a countdown's value, a sand timer's duration
function TableDice.AddTracker(ttype, px, py, private, fields)
    if not dmhub.isDM or TRACKER_TYPES[ttype] == nil then
        return
    end
    local fx, fy = ScreenToTable(px, py)
    local record = {
        type = ttype,
        fx = fx,
        fy = fy,
        seq = 1,
        value = 0,
        playersCanChange = false,
    }
    for k, v in pairs(fields or {}) do
        record[k] = v
    end
    Add(dmhub.GenerateGuid(), private, record, "trackers")
end

--Flips a coin, for everyone: it lands heads or tails at random. Anyone can.
--- @param id string
--- @param private boolean
local function FlipCoin(id, private)
    local tails = math.random() < 0.5
    Modify(id, private, "Flip a coin", function(r)
        r.result = cond(tails, "tails", "heads")
        r.flipAt = dmhub.serverTime
        r.flipSeq = (r.flipSeq or 0) + 1
    end, "trackers")
end

--Turns a pointer to yaw degrees, for everyone.
--- @param id string
--- @param private boolean
--- @param yaw number
local function TurnPointer(id, private, yaw)
    Modify(id, private, "Turn a pointer", function(r)
        r.yaw = yaw % 360
    end, "trackers")
end

--Flips a sand timer: it starts running out now, for everyone.
--- @param id string
--- @param private boolean
local function FlipSand(id, private)
    Modify(id, private, "Flip a sand timer", function(r)
        r.startedAt = dmhub.serverTime
        r.seq = (r.seq or 0) + 1
    end, "trackers")
end

local BuildHeroExtras
local TickCountdown
local ShowTrackerTip
local BuildStandeeCard

--A tracker's right-click menu (Director only).
--- @param id string
local function ShowTrackerMenu(id)
    local handle = g.trackers[id]
    local anchor = MenuAnchor()
    if handle == nil or anchor == nil or not (dmhub.isDM or IsTrinket(handle.record)) then
        return
    end
    local private = handle.private
    local record = handle.record
    anchor.x = handle.panel.x + TRACKER_WIDTH / 2
    anchor.y = handle.panel.y
    g.dieRightClickedAt = dmhub.Time()
    local entries = {}
    if record.type == "sandtimer" then
        entries[#entries+1] = {
            text = "Flip",
            click = function()
                CloseMenu()
                FlipSand(id, private)
            end,
        }
        for _, secs in ipairs(SAND_LENGTHS) do
            local label = cond(secs < 60, string.format("%d Seconds", secs), string.format("%d Minute%s", secs // 60, cond(secs >= 120, "s", "")))
            entries[#entries+1] = {
                text = cond((tonumber(record.duration) or 60) == secs, "* ", "") .. label,
                click = function()
                    CloseMenu()
                    Modify(id, private, "Set a sand timer", function(r)
                        r.duration = secs
                        r.startedAt = nil
                        r.seq = (r.seq or 0) + 1
                    end, "trackers")
                end,
            }
        end
    end
    if record.type == "counter" then
        entries[#entries+1] = {
            text = cond(record.playersCanChange, "Players Can Change: On", "Players Can Change: Off"),
            click = function()
                CloseMenu()
                Modify(id, private, "Change a table counter", function(r)
                    r.playersCanChange = not r.playersCanChange
                    r.seq = (r.seq or 0) + 1
                end, "trackers")
            end,
        }
        entries[#entries+1] = {
            text = "Reset to 0",
            click = function()
                CloseMenu()
                SetTrackerValue(id, private, record, 0, "Reset")
            end,
        }
    end
    entries[#entries+1] = {
        text = cond(IsTrinket(record), "Remove " .. TRACKER_TYPES[record.type].name, "Remove Tracker"),
        click = function()
            CloseMenu()
            Modify(id, private, "Remove a table tracker", function() return false end, "trackers")
        end,
    }
    dmhub.Schedule(0.02, function()
        if mod.unloaded or not anchor.valid then
            return
        end
        local menu = gui.ContextMenu{entries = entries}
        if menu == nil then
            return
        end
        local style = menu.selfStyle
        if style ~= nil then
            style.valign = "top"
            style.halign = "center"
        end
        anchor.popup = menu
    end)
end

--A hero medallion's extras (decision 5): surge pips round the top of the
--rim (click one to set the count there; click the last lit one to spend it)
--and a victories chip at its lower right (click adds one, right-click takes
--one away). handle.refreshExtras keeps them in step with the hero.
--- @param handle table
--- @param Hover fun(key: any)
--- @param Dehover fun(key: any)
--- @return Panel
BuildHeroExtras = function(handle, Hover, Dehover)
    local PIP = 12
    local pips = {}
    local container

    local function Surges(token)
        local n = 0
        pcall(function() n = token.properties:GetAvailableSurges() end)
        return n
    end
    local function MaxSurges(token)
        local n = 3
        pcall(function() n = token.properties:GetMaxSurgeCount() end)
        return math.max(1, math.min(8, n))
    end
    local function SetSurges(token, n)
        local surgeid = CharacterResource.nameToId["Surges"]
        if surgeid == nil then
            return
        end
        local current = Surges(token)
        token:ModifyProperties{
            description = "Change surges",
            execute = function()
                token.properties:AddUnboundedResource(surgeid, n - current, "Set on the table")
            end,
        }
    end
    local function SetVictories(token, n)
        token:ModifyProperties{
            description = "Change victories",
            execute = function()
                token.properties:SetVictories(math.max(0, n))
            end,
        }
    end

    local victoryLabel = gui.Label{
        classes = {"tableTrackerChipLabel"},
        text = "0",
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 2,
        interactable = false,
    }
    local chip = gui.Panel{
        classes = {"tableTrackerChip"},
        bgimage = "panels/square.png",
        floating = true,
        halign = "left",
        valign = "top",
        x = TRACKER_WIDTH / 2 + TRACKER_SIZE * 0.22,
        y = TRACKER_SIZE * 0.68,
        width = "auto",
        height = 18,
        hpad = 4,
        borderBox = true,
        flow = "horizontal",
        swallowPress = true,
        hover = function(element)
            Hover(element)
            local tip = "Victories"
            if TrackerChangeable(handle.record) then
                tip = "Victories: click to add one, right-click to take one away."
            end
            gui.Tooltip(tip)(element)
        end,
        dehover = function(element)
            Dehover(element)
        end,
        click = function(element)
            local token = HeroToken(handle.record)
            if token ~= nil and TrackerChangeable(handle.record) then
                SetVictories(token, token.properties:GetVictories() + 1)
            end
        end,
        rightClick = function(element)
            local token = HeroToken(handle.record)
            if token ~= nil and TrackerChangeable(handle.record) then
                SetVictories(token, token.properties:GetVictories() - 1)
            end
        end,
        gui.Panel{
            classes = {"tableTrackerChipIcon"},
            bgimage = "phosphor/trophy.png",
            width = 11,
            height = 11,
            valign = "center",
            interactable = false,
        },
        victoryLabel,
    }

    container = gui.Panel{
        floating = true,
        width = TRACKER_WIDTH,
        height = TRACKER_HEIGHT,
        flow = "none",
        interactable = false,
        chip,
    }

    --pips spread over the top of the rim, centred on its top.
    local function LayoutPips(count)
        for _, pip in ipairs(pips) do
            if pip.valid then
                pip:DestroySelf()
            end
        end
        pips = {}
        local radius = TRACKER_SIZE * 0.5 + 3
        local spread = math.min(140, 26 * (count - 1))
        for i = 1, count do
            local t = count == 1 and 0.5 or (i - 1) / (count - 1)
            local angle = math.rad(-90 - spread / 2 + spread * t)
            local cx = TRACKER_WIDTH / 2 + math.cos(angle) * radius
            local cy = TRACKER_SIZE / 2 + math.sin(angle) * radius
            local index = i
            local pip = gui.Panel{
                classes = {"tableTrackerPip"},
                bgimage = "panels/square.png",
                floating = true,
                halign = "left",
                valign = "top",
                x = cx - PIP / 2,
                y = cy - PIP / 2,
                width = PIP,
                height = PIP,
                swallowPress = true,
                hover = function(element)
                    Hover(element)
                    local tip = "Surges"
                    if not InCombat() then
                        tip = "Surges (only in combat)"
                    elseif TrackerChangeable(handle.record) then
                        tip = "Surges: click to set"
                    end
                    gui.Tooltip(tip)(element)
                end,
                dehover = function(element)
                    Dehover(element)
                end,
                click = function(element)
                    local token = HeroToken(handle.record)
                    if token == nil or not TrackerChangeable(handle.record) or not InCombat() then
                        return
                    end
                    local n = Surges(token)
                    SetSurges(token, cond(n >= index, index - 1, index))
                end,
            }
            container:AddChild(pip)
            pips[#pips+1] = pip
        end
    end

    local shownMax, shownSurges, shownVictories = -1, -1, -1
    local shownResting = nil
    handle.refreshExtras = function()
        local token = HeroToken(handle.record)
        if token == nil or token.properties == nil then
            return
        end
        local max = MaxSurges(token)
        local surges = Surges(token)
        if max ~= shownMax then
            shownMax = max
            shownSurges = -1
            shownResting = nil
            LayoutPips(max)
        end
        local resting = not InCombat()
        if resting ~= shownResting then
            shownResting = resting
            for _, pip in ipairs(pips) do
                if pip.valid then
                    pip:SetClass("resting", resting)
                end
            end
        end
        if surges ~= shownSurges then
            shownSurges = surges
            for i, pip in ipairs(pips) do
                if pip.valid then
                    pip:SetClass("lit", i <= surges)
                end
            end
        end
        local victories = token.properties:GetVictories()
        if victories ~= shownVictories then
            shownVictories = victories
            victoryLabel.text = string.format("%d", victories)
        end
    end
    return container
end

--What hovering a tracker shows: a trinket says what it does; a sand timer
--how to use it; the rest their change history.
--- @param element Panel
--- @param handle table
ShowTrackerTip = function(element, handle)
    local r = handle.record
    if r.type == "sandtimer" then
        gui.Tooltip(cond(dmhub.isDM, "Click to flip. Right-click to set its length.", "A sand timer"))(element)
        return
    end
    if IsTrinket(r) then
        local tips = {
            coin = "Click to flip. Drag to move.",
            pointer = "Click to turn it. Drag to move; while you hold it, the mouse wheel turns it.",
        }
        gui.Tooltip(tips[r.type] or (TrackerName(r) ~= "" and TrackerName(r) or TRACKER_TYPES[r.type].name) .. ". Drag to move; right-click to remove.")(element)
        return
    end
    element.tooltip = gui.StatsHistoryTooltip{
        description = TrackerHistoryTitle(r),
        entries = TrackerHistory(r),
    }
end

--A standee's card: the character's portrait, standing on the base (the 3D
--token) in a thin frame. It reaches above the panel; the panel still drags.
--- @param handle table
--- @param Hover fun(key: any)
--- @param Dehover fun(key: any)
--- @return Panel
BuildStandeeCard = function(handle, Hover, Dehover)
    local token = HeroToken(handle.record)
    local width = TRACKER_SIZE * 0.82
    local height = TRACKER_SIZE * 1.1
    return gui.Panel{
        classes = {"tableStandeeCard"},
        bgimage = "panels/square.png",
        floating = true,
        halign = "left",
        valign = "top",
        x = TRACKER_WIDTH / 2 - width / 2,
        y = TRACKER_SIZE * 0.42 - height,
        width = width,
        height = height,
        pad = 3,
        borderBox = true,
        interactable = false,
        gui.Panel{
            width = "100%",
            height = "100%",
            bgimage = (token ~= nil and token.portrait) or "panels/square.png",
            bgcolor = cond(token ~= nil and token.portrait ~= nil, "white", "#444448"),
            interactable = false,
        },
    }
end

--One tracker's panel. handle.record is kept current by SyncTrackers, so the
--handlers always act on the latest record.
--- @param id string
--- @param record TableTrackerRecord
--- @param private boolean
local function BuildTracker(id, record, private)
    local handle = {record = record, private = private, seq = record.seq or 0, type = record.type, shown = -1}
    --the medallion is a real 3D token when the engine has them; an older
    --engine gets the flat 2D one (TableDice.TrackerToken).
    local token = nil
    if dice.CreateTableTracker ~= nil then
        local look = TRACKER_LOOKS[record.type] or {shape = "coin"}
        token = dice.CreateTableTracker{shape = look.shape, bezel = look.bezel, face = look.face, size = TRACKER_SIZE}
        if token ~= nil and record.type == "coin" then
            token.backText = "T"
        end
    end
    handle.token = token
    --what the mouse is over: the token or a step button. The buttons show
    --while any of them is hovered (hovers go to the deepest panel only).
    local hovered = {}
    local steps = {}

    local function ShowSteps()
        --a sand timer has no steps: it is flipped, and set from its menu. A
        --hero's resource has none outside combat (there is none to change).
        local resting = handle.record.type == "hero" and not InCombat()
        local show = next(hovered) ~= nil and TrackerChangeable(handle.record) and handle.record.type ~= "sandtimer" and not resting
            and not IsTrinket(handle.record)
        for _, step in ipairs(steps) do
            if step.valid then
                step:SetClass("collapsed", not show)
            end
        end
    end
    local function Hover(key)
        hovered[key] = true
        ShowSteps()
    end
    local function Dehover(key)
        hovered[key] = nil
        dmhub.Schedule(0.1, function()
            if mod.unloaded then
                return
            end
            ShowSteps()
        end)
    end

    local function Step(delta, halign)
        local step
        step = gui.Panel{
            classes = {"tableTrackerStep", "collapsed"},
            bgimage = "panels/square.png",
            width = TRACKER_STEP,
            height = TRACKER_STEP,
            halign = halign,
            valign = "top",
            y = (TRACKER_SIZE - TRACKER_STEP) / 2,
            swallowPress = true,
            hover = function(element)
                Hover(element)
            end,
            dehover = function(element)
                Dehover(element)
            end,
            click = function(element)
                local r = handle.record
                SetTrackerValue(id, handle.private, r, TrackerValue(r) + delta, cond(delta > 0, "Added on the table", "Spent on the table"))
            end,
            gui.Label{
                classes = {"tableTrackerStepLabel"},
                text = cond(delta > 0, "+", "-"),
                width = "100%",
                height = "100%",
                textAlignment = "center",
                interactable = false,
            },
        }
        steps[#steps+1] = step
        return step
    end

    local valueLabel = gui.Label{
        classes = {"tableTrackerValue"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TRACKER_SIZE * 0.4,
        numeric = true,
        characterLimit = 3,
        text = "0",
        --a 3D token draws over the UI, so its number is the token's own and
        --this label only takes the mouse (an edit would be hidden under it).
        opacity = cond(token ~= nil, 0, 1),
        editable = token == nil and TrackerChangeable(record) and not IsTrinket(record),
        hover = function(element)
            Hover(element)
            ShowTrackerTip(element, handle)
        end,
        dehover = function(element)
            Dehover(element)
        end,
        change = function(element)
            local n = tonumber(element.text)
            if n == nil then
                handle.shown = -1
                return
            end
            SetTrackerValue(id, handle.private, handle.record, n, "Set on the table")
        end,
    }

    local nameLabel = gui.Label{
        classes = {"tableTrackerName"},
        text = TrackerName(record),
        textWrap = false,
        maxWidth = TRACKER_WIDTH,
        halign = "center",
        valign = "bottom",
        --a Director renames a counter by clicking its name.
        editable = dmhub.isDM and record.type == "counter",
        hover = function(element)
            Hover(element)
        end,
        dehover = function(element)
            Dehover(element)
        end,
        change = function(element)
            local text = (element.text or ""):gsub("^%s*(.-)%s*$", "%1")
            Modify(id, handle.private, "Rename a table counter", function(r)
                r.name = text
                r.seq = (r.seq or 0) + 1
            end, "trackers")
        end,
    }

    if record.type == "hero" then
        handle.extras = BuildHeroExtras(handle, Hover, Dehover)
    elseif record.type == "standee" then
        handle.extras = BuildStandeeCard(handle, Hover, Dehover)
    end

    --skull and key: their symbol stamped on the face (dark, with a light
    --lower edge, as if pressed into the metal).
    local stamp = nil
    local stampIcon = (TRACKER_TYPES[record.type] or {}).icon
    if stampIcon ~= nil then
        stamp = gui.Panel{
            floating = true,
            halign = "center",
            valign = "center",
            width = TRACKER_SIZE * 0.44,
            height = TRACKER_SIZE * 0.44,
            interactable = false,
            gui.Panel{
                floating = true,
                width = "100%",
                height = "100%",
                y = 1.5,
                bgimage = stampIcon,
                bgcolor = "#FFFFFF55",
                interactable = false,
            },
            gui.Panel{
                floating = true,
                width = "100%",
                height = "100%",
                bgimage = stampIcon,
                bgcolor = "#26272BE6",
                interactable = false,
            },
        }
    end

    local tokenPanel
    if token ~= nil then
        --the token's image is bigger than the token, to hold its shadow.
        local view = token.imageSize / math.max(1, token.size)
        tokenPanel = gui.Panel{
            width = TRACKER_SIZE,
            height = TRACKER_SIZE,
            halign = "center",
            valign = "top",
            flow = "none",
            gui.Panel{
                floating = true,
                halign = "center",
                valign = "center",
                width = TRACKER_SIZE * view,
                height = TRACKER_SIZE * view,
                bgimage = token.image,
                bgcolor = "white",
                interactable = false,
            },
            stamp or valueLabel,
            stamp ~= nil and valueLabel or nil,
        }
    else
        tokenPanel = TableDice.TrackerToken(record.type, TRACKER_SIZE, valueLabel)
        if stamp ~= nil then
            tokenPanel:AddChild(stamp)
        end
    end

    --the name plate; a trinket with nothing to say has none (TrackerName "").
    local plate = gui.Panel{
        classes = {"tableTrackerPlate", cond(TrackerName(record) == "", "collapsed", nil)},
        bgimage = "panels/square.png",
        width = "auto",
        height = "auto",
        hpad = 8,
        vpad = 2,
        borderBox = true,
        halign = "center",
        valign = "bottom",
        nameLabel,
    }

    local panel
    panel = gui.Panel{
        classes = {"tableTracker"},
        floating = true,
        halign = "left",
        valign = "top",
        width = TRACKER_WIDTH,
        height = TRACKER_HEIGHT,
        flow = "none",
        bgimage = true,
        bgcolor = "clear",
        swallowPress = true,
        --only the Director moves trackers (TABLE_DICE_BRIEF.md, decision 4);
        --anyone moves a trinket (Trinkets, decision 2).
        draggable = dmhub.isDM or IsTrinket(record),
        dragInPlace = true,
        data = {id = id},
        hover = function(element)
            Hover(element)
            ShowTrackerTip(element, handle)
        end,
        dehover = function(element)
            Dehover(element)
        end,
        rightClick = function(element)
            ShowTrackerMenu(id)
        end,
        click = function(element)
            local r = handle.record
            if r.type == "sandtimer" and dmhub.isDM then
                FlipSand(id, handle.private)
            elseif r.type == "coin" then
                FlipCoin(id, handle.private)
            elseif r.type == "pointer" then
                TurnPointer(id, handle.private, (tonumber(r.yaw) or 0) + 45)
            end
        end,
        --the 3D token lifts while it is carried; a held pointer turns with
        --the mouse wheel, a notch at a time, as a held figure does.
        dragging = function(element)
            local t = handle.token
            if t ~= nil and t.valid and not t.held then
                t.held = true
            end
            if handle.record.type == "pointer" and t ~= nil and t.valid then
                local wheel = dmhub.mouseWheel
                if wheel ~= 0 then
                    handle.heldYaw = ((handle.heldYaw or tonumber(handle.record.yaw) or 0) + cond(wheel > 0, -15, 15)) % 360
                    --the engine turns anticlockwise; the record counts clockwise.
                    t.yaw = -handle.heldYaw
                end
            end
        end,
        drag = function(element)
            local t = handle.token
            if t ~= nil and t.valid then
                t.held = false
            end
            local heldYaw = handle.heldYaw
            handle.heldYaw = nil
            element.x = element.xdrag
            element.y = element.ydrag
            local w, h = TableSize()
            local fx = (element.xdrag + TRACKER_WIDTH / 2) / math.max(1, w)
            local fy = (element.ydrag + TRACKER_SIZE / 2) / math.max(1, h)
            fx = math.max(0, math.min(1, fx))
            fy = math.max(0, math.min(1, fy))
            local behind = BehindScreen(fx)
            if behind ~= handle.private then
                Transfer(id, behind, fx, fy, "trackers", {yaw = heldYaw})
                return
            end
            Modify(id, handle.private, "Move a table tracker", function(r)
                r.fx, r.fy = fx, fy
                if heldYaw ~= nil then
                    r.yaw = heldYaw
                end
                r.seq = (r.seq or 0) + 1
            end, "trackers")
        end,
        tokenPanel,
        Step(-1, "left"),
        Step(1, "right"),
        plate,
        --last: nil for all but a hero or standee, which must not leave a hole.
        handle.extras,
    }
    handle.panel = panel
    handle.plate = plate
    handle.valueLabel = valueLabel
    handle.nameLabel = nameLabel
    return handle
end

--Renders a tracker's 3D token at the size it shows on screen, so it is crisp.
local function PlaceToken(handle)
    local t = handle.token
    if t == nil or not t.valid then
        return
    end
    local scale = Mapping()
    local size = TRACKER_SIZE / scale
    if math.abs(t.size - size) > 0.5 then
        t.size = size
    end
end

--The two panels trackers live in, made in the documents layer (with the
--windows) and kept in order there: the shared trackers' first, under every
--window and the Director's Screen; the private ones' last, so they lie on
--the open screen. Rebuilt if anything takes them out (their trackers are
--rebuilt with them).
--- @return nil|Panel shared
--- @return nil|Panel private
local function TrackerLayers()
    local hud = GameHud.instance
    local docs = hud ~= nil and hud.documentsPanel or nil
    if docs == nil or not docs.valid then
        return nil, nil
    end
    for _, key in ipairs({"trackerLayer", "trackerScreenLayer"}) do
        local layer = g[key]
        if layer == nil or not layer.valid or layer.parent ~= docs then
            if layer ~= nil and layer.valid then
                layer:DestroySelf()
            end
            layer = gui.Panel{
                width = "100%",
                height = "100%",
                flow = "none",
                interactable = false,
                styles = ThemeEngine.MergeTokens(g_drawerStyles),
            }
            docs:AddChild(layer)
            g[key] = layer
        end
    end
    local shared = g.trackerLayer --[[@as Panel]]
    local private = g.trackerScreenLayer --[[@as Panel]]

    --The dice and figures lying on the table, drawn by the engine's table pass
    --("#DiceTable"): over the shared trackers, under every window and panel.
    local image = g.tableImage
    if image == nil or not image.valid or image.parent ~= shared then
        image = gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            bgimage = "#DiceTable",
            bgcolor = "white",
            interactable = false,
        }
        shared:AddChild(image)
        g.tableImage = image
        g.tableImageCrop = nil
    end
    local sharedChildren = shared.children
    if sharedChildren[#sharedChildren] ~= image then
        image:SetAsLastSibling()
    end
    --the image is the whole screen; the table is the part below the title bar
    --(imageRect's y counts up from the bottom).
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    local crop = screen.y > 0 and below.y / screen.y or 1
    if crop ~= g.tableImageCrop then
        g.tableImageCrop = crop
        image.selfStyle.imageRect = {x1 = 0, x2 = 1, y1 = 0, y2 = crop}
    end
    local children = docs.children
    if children[1] ~= shared then
        shared:SetAsFirstSibling()
    end
    if children[#children] ~= private then
        private:SetAsLastSibling()
    end
    return shared, private
end

--Places a tracker's panel on its spot (table fractions -> layer units).
local function PlaceTracker(handle)
    local w, h = TableSize()
    handle.panel.x = (handle.record.fx or 0.5) * w - TRACKER_WIDTH / 2
    handle.panel.y = (handle.record.fy or 0.5) * h - TRACKER_SIZE / 2
    PlaceToken(handle)
end

local function DestroyTracker(handle)
    if handle.token ~= nil and handle.token.valid then
        handle.token:Destroy()
    end
    if handle.panel.valid then
        handle.panel:DestroySelf()
    end
end

DestroyTrackers = function()
    for id, handle in pairs(g.trackers) do
        DestroyTracker(handle)
        g.trackers[id] = nil
    end
end

--A countdown ticks down as combat rounds pass (decision 6). Only the
--Director's client writes it: it notes the combat and round it last saw,
--and takes one off for each new round since.
--- @param id string
--- @param private boolean
--- @param record TableTrackerRecord
--- @param handle table
TickCountdown = function(id, private, record, handle)
    local q = dmhub.initiativeQueue
    if q == nil or q.hidden then
        return
    end
    local round = tonumber(q.round) or 0
    local key = tostring(q.guid) .. ":" .. round
    if handle.tickedAt == key then
        return
    end
    handle.tickedAt = key
    if record.combat ~= q.guid or type(record.round) ~= "number" then
        Modify(id, private, "Start a countdown", function(r)
            r.combat = q.guid
            r.round = round
        end, "trackers")
        return
    end
    if round <= record.round then
        return
    end
    local passed = round - record.round
    Modify(id, private, "A round passed", function(r)
        r.round = round
        local value = math.max(0, (tonumber(r.value) or 0) - passed)
        r.value = value
        local history = type(r.history) == "table" and r.history or {}
        history[#history+1] = {userid = dmhub.userid, timestamp = ServerTimestamp(), set = value, note = "A round passed"}
        while #history > TRACKER_HISTORY_MAX do
            table.remove(history, 1)
        end
        r.history = history
        r.seq = (r.seq or 0) + 1
    end, "trackers")
end

--Keeps the trackers' panels in line with the stores (TableDice.Sync).
--- @param covered boolean
--- @param screenOpen boolean
local function SyncTrackers(covered, screenOpen)
    local sharedLayer, privateLayer = TrackerLayers()
    if sharedLayer == nil or privateLayer == nil then
        return
    end
    local wanted = {}
    for id, record in pairs(SharedItems("trackers")) do
        if type(record) == "table" and TRACKER_TYPES[record.type] ~= nil then
            wanted[id] = {record = record, private = false}
        end
    end
    if dmhub.isDM then
        for id, record in pairs(PrivateItems("trackers")) do
            if type(record) == "table" and TRACKER_TYPES[record.type] ~= nil then
                wanted[id] = {record = record, private = true}
            end
        end
    end
    for id, handle in pairs(g.trackers) do
        local want = wanted[id]
        if want == nil or not handle.panel.valid or want.private ~= handle.private or want.record.type ~= handle.type then
            DestroyTracker(handle)
            g.trackers[id] = nil
        end
    end
    for id, want in pairs(wanted) do
        local handle = g.trackers[id]
        if handle == nil then
            handle = BuildTracker(id, want.record, want.private)
            if want.private then
                privateLayer:AddChild(handle.panel)
            else
                sharedLayer:AddChild(handle.panel)
            end
            PlaceTracker(handle)
            g.trackers[id] = handle
        else
            handle.record = want.record
            if (want.record.seq or 0) ~= handle.seq then
                handle.seq = want.record.seq or 0
                PlaceTracker(handle)
                handle.valueLabel.editable = handle.token == nil and TrackerChangeable(want.record) and not IsTrinket(want.record)
            end
            --follows the table if the window changes size.
            PlaceToken(handle)
        end
        if want.record.type == "countdown" and dmhub.isDM then
            TickCountdown(id, want.private, want.record, handle)
        end
        local text = TrackerText(want.record)
        if text ~= handle.shown then
            handle.shown = text
            handle.valueLabel.text = text
            if handle.token ~= nil and handle.token.valid then
                handle.token.text = text
            end
        end
        if handle.refreshExtras ~= nil then
            handle.refreshExtras()
        end
        local t = handle.token
        if t ~= nil and t.valid then
            --a pointer's turn (unless it is being turned in hand).
            if want.record.type == "pointer" and handle.heldYaw == nil then
                --the engine turns anticlockwise; the record counts clockwise.
                local yaw = -(tonumber(want.record.yaw) or 0)
                if t.yaw ~= yaw then
                    t.yaw = yaw
                end
            end
            --a coin flip: played once, on every client, if it is fresh;
            --otherwise the coin just lies the way it landed.
            if want.record.type == "coin" then
                if want.record.flipSeq ~= handle.flipSeq then
                    local fresh = handle.coinSeen == true
                    if type(want.record.flipAt) == "number" and dmhub.serverTime - want.record.flipAt > 2 then
                        fresh = false
                    end
                    handle.flipSeq = want.record.flipSeq
                    t:Flip(want.record.result == "tails", fresh)
                end
                handle.coinSeen = true
            end
        end
        --a trinket's plate comes and goes with what it has to say (a coin's
        --result); everything else keeps its plate.
        local name = TrackerName(want.record)
        if name ~= handle.shownName then
            handle.shownName = name
            handle.nameLabel.text = name
            handle.plate:SetClass("collapsed", name == "")
        end
        --a timer running out: the plate says so, and it pings once (not when
        --it was already out as the table loaded).
        local expired = TrackerExpired(want.record)
        if expired ~= handle.expired then
            if expired and handle.expired == false then
                audio.FireSoundEvent("Notify.Ping")
            end
            handle.expired = expired
            handle.panel:SetClassTree("expired", expired)
        end
        local visible = not covered and (not want.private or screenOpen)
        if handle.panel:HasClass("collapsed") == visible then
            handle.panel:SetClass("collapsed", not visible)
        end
        if handle.token ~= nil and handle.token.valid then
            handle.token:SetVisible(visible)
        end
    end
end

--- Brings the engine's dice in line with the stores; the layer's think runs it.
function TableDice.Sync()
    --an engine older than table dice has no CreateTableDie: nothing to show.
    if dice.CreateTableDie == nil or not Tabletop.IsActive() or not Tabletop.LayerReady() then
        DestroyAll()
        return
    end
    local covered = Tabletop.TableCovered()
    local screenOpen = rawget(_G, "DirectorScreen") ~= nil and DirectorScreen.IsOpen()
    local x1, y1, x2, y2 = TableBounds()

    local wanted = Wanted()
    for id, handle in pairs(g.handles) do
        local want = wanted[id]
        --gone, or rebuilt as another type, set or store.
        if want == nil or not handle.die.valid or want.private ~= handle.private
            or want.record.faces ~= handle.faces or want.record.model ~= handle.model then
            if handle.die.valid then
                handle.die:Destroy()
            end
            g.handles[id] = nil
        end
    end
    for id, want in pairs(wanted) do
        local handle = g.handles[id]
        if handle == nil then
            handle = BuildDie(id, want.record, want.private)
            g.handles[id] = handle
        else
            UpdateDie(handle, want.record)
        end
        if handle ~= nil then
            handle.die:SetBounds(x1, y1, x2, y2)
            handle.die:SetVisible(not covered and (not want.private or screenOpen))
        end
    end
    SyncFigures(covered, screenOpen, x1, y1, x2, y2)
    SyncTrackers(covered, screenOpen)
end

----------------------------------------------------------------------
--The layer: the table's dice button, the menus' anchor, and the sync.

--- GameHud mounts this over the windows. Only the Director's dice button takes
--- the mouse.
--- @return Panel
function TableDice.CreateLayer()
    g.tableButton = gui.Panel{
        classes = {"tableItemsButton", "collapsed"},
        floating = true,
        halign = "left",
        valign = "bottom",
        x = 72,
        bmargin = 22,
        width = 36,
        height = 36,
        bgimage = "panels/square.png",
        swallowPress = true,
        flow = "none",
        hover = gui.Tooltip("Table items"),
        click = function(element)
            TableDice.ToggleDrawer(false)
        end,
        gui.Panel{
            classes = {"tableItemsButtonIcon"},
            bgimage = "phosphor/package.png",
            width = 20,
            height = 20,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    g.layer = gui.Panel{
        id = "tableDiceLayer",
        width = "100%",
        height = "100%",
        flow = "none",
        interactable = false,
        styles = ThemeEngine.MergeTokens(g_drawerStyles),
        children = {g.tableButton, BuildDrawer()},
        thinkTime = 0.05,
        think = function(element)
            if mod.unloaded then
                return
            end
            local shown = TableDice.TrayEnabled() and Tabletop.IsActive() and not Tabletop.TableCovered()
            local button = g.tableButton
            if button ~= nil and button.valid and button:HasClass("collapsed") == shown then
                button:SetClass("collapsed", not shown)
            end
            --the table went away (a window maximized): so does the drawer.
            if not shown and TableDice.DrawerOpen() then
                CloseDrawer()
            end
            --the screen closed under a drawer opened from it.
            if g_drawer.private and TableDice.DrawerOpen() and rawget(_G, "DirectorScreen") ~= nil and not DirectorScreen.IsOpen() then
                CloseDrawer()
            end
            TableDice.Sync()
            SyncPreviews()
        end,
        destroy = function(element)
            DestroyAll()
        end,
    }
    return g.layer
end

--A reload: the dice the old copy of this file made go with it.
if rawget(_G, "g_tableDiceUnload") ~= nil then
    pcall(g_tableDiceUnload)
end
g_tableDiceUnload = function()
    DestroyAll()
    DestroyPreviews()
    --the trackers' panels live in the documents layer, which outlives this file.
    for _, key in ipairs({"trackerLayer", "trackerScreenLayer"}) do
        local layer = g[key]
        if layer ~= nil and layer.valid then
            layer:DestroySelf()
        end
    end
end
