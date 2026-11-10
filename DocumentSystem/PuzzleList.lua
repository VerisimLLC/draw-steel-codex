local mod = dmhub.GetModLoading()

-- The Director's "Puzzles" panel: every puzzle in the game (from Puzzle.Index),
-- its state, who is at it, and where it lives, with Open / Show everyone /
-- Go to, and Remove for a puzzle whose lock object or journal page is gone.

--Which map a floor belongs to, by scanning the game's maps.
---@param floorid string
---@return any map, any floor
local function FindFloor(floorid)
    for _, m in ipairs(game.maps or {}) do
        for _, f in ipairs(m.floors or {}) do
            if f.floorid == floorid then
                return m, f
            end
        end
    end
    return nil, nil
end

---@param seconds number
---@return string
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

---@class PuzzleListRow
---@field id string
---@field entry PuzzleIndexEntry
---@field title string
---@field typeName string
---@field state string
---@field stateClass string|nil
---@field rank integer
---@field people string[]
---@field where string
---@field missing boolean
---@field map any

---@param id string
---@param entry PuzzleIndexEntry
---@return PuzzleListRow
local function BuildRow(id, entry)
    local def = Puzzle.GetType(id)
    local status = Puzzle.Status(id)
    local row = {
        id = id,
        entry = entry,
        title = Puzzle.Title(id),
        typeName = def ~= nil and def.name or "Not set up",
        state = "In progress",
        stateClass = nil,
        rank = 2,
        people = {},
        where = "",
        missing = false,
        map = nil,
    }
    if def == nil then
        row.state, row.rank = "Not set up", 3
    elseif status.solved then
        row.state, row.stateClass, row.rank = cond(status.bypassed, "Bypassed", "Solved"), "success", 4
    elseif status.failed then
        row.state, row.stateClass, row.rank = "Failed", "danger", 4
    else
        local left = Puzzle.TimeLeft(id)
        if left ~= nil then
            row.state = string.format("In progress, %s left%s", FormatTime(left), cond(Puzzle.TimerPaused(id), " (paused)", ""))
        end
    end

    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        row.people[#row.people + 1] = Puzzle.UserName(userid)
    end
    if #row.people > 0 and row.rank == 2 then
        row.rank = 1
    end

    if entry.kind == "lock" and entry.floorid ~= nil then
        local m = FindFloor(entry.floorid)
        local obj = nil
        if m ~= nil and entry.objid ~= nil then
            obj = game.LookupObject(entry.floorid, entry.objid)
        end
        if m == nil or obj == nil or not obj.valid then
            row.missing = true
            row.where = "Lock: its object is gone"
        else
            row.map = m
            row.where = string.format("Lock on %s", tostring(m.description))
        end
    elseif entry.kind == "journal" and entry.docid ~= nil then
        local page = (dmhub.GetTable(CustomDocument.tableName) or {})[entry.docid]
        if page == nil then
            row.missing = true
            row.where = "Journal: its page is gone"
        else
            row.where = string.format("Journal: %s", tostring(page.description))
        end
    else
        row.where = "Location not recorded yet"
    end
    return row
end

---@param text string
---@param click fun()
---@return Panel
local function RowButton(text, click)
    return gui.Button{
        classes = {"sizeXs"},
        text = text,
        width = cond(#text > 8, 112, 72),
        height = 22,
        hmargin = 2,
        click = function(element)
            click()
        end,
    }
end

--Move the camera to a lock, switching maps first when it is on another one.
---@param row PuzzleListRow
local function GoTo(row)
    local entry = row.entry
    if row.map == nil or entry.floorid == nil or entry.objid == nil then
        return
    end
    local floorid, objid = entry.floorid --[[@as string]], entry.objid --[[@as string]]
    local function Center()
        local obj = game.LookupObject(floorid, objid)
        if obj ~= nil and obj.valid then
            obj:CenterCamera{ smooth = true }
        end
    end
    if game.currentMap ~= nil and game.currentMap.id == row.map.id then
        Center()
    else
        game.ChangeMap(row.map)
        dmhub.Schedule(1.5, function()
            if not mod.unloaded then
                Center()
            end
        end)
    end
end

---@param row PuzzleListRow
---@return Panel
local function RowPanel(row)
    local id = row.id
    local buttons = {}
    if not row.missing and Puzzle.Exists(id) then
        buttons[#buttons + 1] = RowButton("Open", function()
            if row.entry.kind == "lock" and row.entry.floorid ~= nil and row.entry.objid ~= nil then
                Puzzle.OpenLockWindow(id, row.entry.floorid, row.entry.objid)
            else
                Puzzle.OpenWindow(id)
            end
        end)
        buttons[#buttons + 1] = RowButton("Show everyone", function()
            Puzzle.PushToEveryone(id)
        end)
    end
    if row.map ~= nil then
        buttons[#buttons + 1] = RowButton("Go to", function()
            GoTo(row)
        end)
    end
    if row.missing then
        buttons[#buttons + 1] = RowButton("Remove", function()
            GameHud.instance:ModalDialog{
                title = "Remove this puzzle?",
                width = 640,
                height = 280,
                buttonsHalign = "center",
                buttons = {
                    { text = "Cancel", escapeActivates = true, click = function() end },
                    { text = "Remove", click = function() Puzzle.Forget(id) end },
                },
                gui.Panel{
                    width = 520,
                    height = 80,
                    halign = "center",
                    valign = "center",
                    gui.Label{
                        classes = {"modalMessage"},
                        text = "Its board and status are cleared. This cannot be undone.",
                    },
                },
            }
        end)
    end

    local people = cond(#row.people > 0, "At it: " .. table.concat(row.people, ", "), nil)

    return gui.Panel{
        classes = {"bordered"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        vmargin = 3,
        pad = 6,
        borderBox = true,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            gui.Label{
                classes = {"sizeM", "bold"},
                width = "auto",
                height = "auto",
                halign = "left",
                text = row.title,
            },
            gui.Label{
                classes = {"sizeS", "fgMuted"},
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                text = row.typeName,
            },
        },
        gui.Label{
            classes = {"sizeS", row.stateClass},
            width = "100%",
            height = "auto",
            text = row.state,
        },
        people ~= nil and gui.Label{
            classes = {"sizeS", "info"},
            width = "100%",
            height = "auto",
            text = people,
        } or nil,
        gui.Label{
            classes = {"sizeS", cond(row.missing, "warning", "fgMuted")},
            width = "100%",
            height = "auto",
            text = row.where,
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            tmargin = 2,
            children = buttons,
        },
    }
end

local function CreatePuzzleList()
    local list
    local empty
    local m_signature = nil

    --Rebuilds only when something shown changed, so buttons are not swapped out
    --under the mouse every second (a running timer still changes once a second).
    local function Refresh()
        local rows = {}
        for id, entry in pairs(Puzzle.Index()) do
            rows[#rows + 1] = BuildRow(id, entry)
        end
        table.sort(rows, function(a, b)
            if a.rank ~= b.rank then
                return a.rank < b.rank
            end
            return a.title < b.title
        end)
        local parts = {}
        for _, row in ipairs(rows) do
            parts[#parts + 1] = table.concat({ row.id, row.title, row.typeName, row.state, row.where,
                table.concat(row.people, ","), tostring(row.missing), tostring(Puzzle.Exists(row.id)) }, "|")
        end
        local signature = table.concat(parts, ";")
        if signature == m_signature then
            return
        end
        m_signature = signature
        local children = {}
        for _, row in ipairs(rows) do
            children[#children + 1] = RowPanel(row)
        end
        list.children = children
        empty:SetClass("collapsed", #rows > 0)
    end

    empty = gui.Label{
        classes = {"sizeS", "fgMuted", "collapsed"},
        width = "100%",
        height = "auto",
        pad = 8,
        borderBox = true,
        text = "No puzzles yet. Add one to a journal page, or a Puzzle Lock to a map object.",
    }

    list = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%",
        vscroll = true,
        pad = 6,
        borderBox = true,
        monitorGame = Puzzle.ListMonitorPaths(),
        refreshGame = function(element)
            Refresh()
        end,
        create = function(element)
            Refresh()
        end,
        --timers count down with no write; keep the times fresh while it is open.
        thinkTime = 1,
        think = function(element)
            Refresh()
        end,
        empty,
        list,
    }
end

DockablePanel.Register{
    name = "Puzzles",
    icon = "icons/standard/Icon_App_Check.png",
    dmonly = true,
    minHeight = 200,
    vscroll = false,
    content = function()
        return CreatePuzzleList()
    end,
}
