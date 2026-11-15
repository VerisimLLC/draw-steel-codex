local mod = dmhub.GetModLoading()

-- The Director's "Puzzles" panel: every puzzle in the game (from Puzzle.Index),
-- its state, who is at it, and a line for each place it lives (checked each
-- time the panel builds) with Go to / Open / Remove from here, or Clear for a
-- place that is gone. Remove forgets the puzzle; Remove from every place keeps it.
-- "New puzzle" makes a standalone puzzle that lives only here: the Director
-- opens it, or launches it for everyone with Show everyone.

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

---@class PuzzleListHome
---@field key string
---@field home PuzzleHome
---@field live boolean
---@field text string
---@field map any the lock's map, while the lock is there

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
---@field homes PuzzleListHome[]

---@param id string
---@param key string
---@param home PuzzleHome
---@return PuzzleListHome
local function BuildHome(id, key, home)
    local live = PuzzlePlace.HomeLive(id, home)
    local kindText = cond(home.kind == "lock", "Lock", "Page")
    local result = {
        key = key,
        home = home,
        live = live,
        text = string.format("%s: %s%s", kindText, PuzzlePlace.HomeName(home), cond(live, "", " (gone)")),
        map = nil,
    }
    if live and home.kind == "lock" and home.floorid ~= nil then
        result.map = FindFloor(home.floorid)
    end
    return result
end

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
        homes = {},
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

    local gone = 0
    for key, home in pairs(Puzzle.Homes(id)) do
        local h = BuildHome(id, key, home)
        row.homes[#row.homes + 1] = h
        if not h.live then
            gone = gone + 1
        end
    end
    table.sort(row.homes, function(a, b) return a.text < b.text end)

    if #row.homes == 0 then
        row.where = cond(entry.kind == "standalone", "In the Puzzles panel", "Not in any place")
    else
        row.where = string.format("%d %s%s", #row.homes, cond(#row.homes == 1, "place", "places"),
            cond(gone > 0, string.format(", %d gone", gone), ""))
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
        width = cond(#text > 14, 160, cond(#text > 8, 112, 72)),
        height = 22,
        hmargin = 2,
        click = function(element)
            click()
        end,
    }
end

--Move the camera to a lock, switching maps first when it is on another one.
---@param map any
---@param floorid string
---@param objid string
local function GoTo(map, floorid, objid)
    local function Center()
        local obj = game.LookupObject(floorid, objid)
        if obj ~= nil and obj.valid then
            obj:CenterCamera{ smooth = true }
        end
    end
    if game.currentMap ~= nil and game.currentMap.id == map.id then
        Center()
    else
        game.ChangeMap(map)
        dmhub.Schedule(1.5, function()
            if not mod.unloaded then
                Center()
            end
        end)
    end
end

--The type's setup as a popup under a button: the same setup the journal cog
--and Lock setup show. Choosing another type starts the puzzle over.
---@type fun(button: Panel, id: string)
local ShowSetup
---@param button Panel
---@param id string
ShowSetup = function(button, id)
    if button.popup ~= nil then
        button.popup = nil
        return
    end
    button.popupsInheritStyles = true
    button.popup = Puzzle.SetupPanel(id, function(typeid)
        Puzzle.Create(id, typeid, nil, Puzzle.Title(id))
        button.popup = nil
        ShowSetup(button, id)
    end)
end

---@param title string
---@param lines string[]
---@param confirmText string
---@param confirm fun()
local function Confirm(title, lines, confirmText, confirm)
    local labels = {}
    for _, line in ipairs(lines) do
        labels[#labels + 1] = gui.Label{
            classes = {"modalMessage"},
            width = "100%",
            height = "auto",
            vmargin = 2,
            text = line,
        }
    end
    GameHud.instance:ModalDialog{
        title = title,
        width = 640,
        height = 200 + 40 * #lines,
        buttonsHalign = "center",
        buttons = {
            { text = "Cancel", escapeActivates = true, click = function() end },
            { text = confirmText, click = confirm },
        },
        gui.Panel{
            flow = "vertical",
            width = 560,
            height = "auto",
            halign = "center",
            valign = "center",
            children = labels,
        },
    }
end

---@param row PuzzleListRow
---@return string|nil
local function PeopleLine(row)
    if #row.people == 0 then
        return nil
    end
    return "In it now: " .. table.concat(row.people, ", ") .. "."
end

---@param row PuzzleListRow
---@return string[]
local function LiveHomeNames(row)
    local names = {}
    for _, h in ipairs(row.homes) do
        if h.live then
            names[#names + 1] = PuzzlePlace.HomeName(h.home)
        end
    end
    return names
end

---@param row PuzzleListRow
---@param h PuzzleListHome
---@return Panel
local function HomePanel(row, h)
    local id = row.id
    local home = h.home
    local buttons = {}
    if h.live then
        if h.map ~= nil and home.floorid ~= nil and home.objid ~= nil then
            local map, floorid, objid = h.map, home.floorid --[[@as string]], home.objid --[[@as string]]
            buttons[#buttons + 1] = RowButton("Go to", function()
                GoTo(map, floorid, objid)
            end)
        end
        if Puzzle.Exists(id) or home.kind == "journal" then
            buttons[#buttons + 1] = RowButton("Open", function()
                if home.kind == "lock" then
                    Puzzle.OpenLockWindow(id, home.floorid --[[@as string]], home.objid --[[@as string]])
                else
                    local page = (dmhub.GetTable(CustomDocument.tableName) or {})[home.docid]
                    if page ~= nil then
                        page:ShowDocument()
                    end
                end
            end)
        end
        buttons[#buttons + 1] = RowButton("Remove from here", function()
            local lines = {}
            if home.kind == "lock" then
                lines[#lines + 1] = cond(home.placed == "object", "The lock object is taken off the map.",
                    cond(home.placed == "component", "The object stops being a lock.", "The object keeps its Puzzle Lock, with no puzzle set."))
                lines[#lines + 1] = "What this lock opens is forgotten."
            else
                lines[#lines + 1] = "The puzzle is taken off the page."
            end
            lines[#lines + 1] = "The puzzle stays in this panel."
            Confirm(string.format("Remove from %s?", PuzzlePlace.HomeName(home)), lines, "Remove", function()
                PuzzlePlace.RemoveHome(id, h.key)
            end)
        end)
    else
        buttons[#buttons + 1] = RowButton("Clear", function()
            if home.kind == "lock" and home.floorid ~= nil and home.objid ~= nil and Puzzle.Exists(id) then
                local locks = Puzzle.ReadConfig(id).locks
                local lockKey = Puzzle.LockKey(home.floorid, home.objid)
                if type(locks) == "table" and locks[lockKey] ~= nil then
                    locks[lockKey] = nil
                    Puzzle.SetConfig(id, { locks = locks })
                end
            end
            Puzzle.RemoveHome(id, h.key)
        end)
    end
    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        lmargin = 8,
        vmargin = 1,
        gui.Label{
            classes = {"sizeS", cond(h.live, nil, "fgMuted")},
            width = "100%",
            height = "auto",
            text = h.text,
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            children = buttons,
        },
    }
end

---@param row PuzzleListRow
---@return Panel
local function RowPanel(row)
    local id = row.id
    local buttons = {}
    local liveNames = LiveHomeNames(row)
    if Puzzle.Exists(id) then
        buttons[#buttons + 1] = RowButton("Open", function()
            Puzzle.OpenWindow(id)
        end)
        buttons[#buttons + 1] = RowButton("Show everyone", function()
            Puzzle.PushToEveryone(id)
        end)
    end
    if row.entry.kind == "standalone" then
        local setupButton
        setupButton = RowButton("Setup", function()
            ShowSetup(setupButton, id)
        end)
        buttons[#buttons + 1] = setupButton
    end

    local removeButtons = {}
    if #liveNames > 0 then
        removeButtons[#removeButtons + 1] = RowButton("Remove from every place", function()
            local lines = { "It is taken out of: " .. table.concat(liveNames, ", ") .. ".",
                "The puzzle stays in this panel." }
            lines[#lines + 1] = PeopleLine(row)
            Confirm("Remove from every place?", lines, "Remove", function()
                PuzzlePlace.RemoveEverywhere(id)
            end)
        end)
    end
    removeButtons[#removeButtons + 1] = RowButton("Remove", function()
        local lines = { "Its board and status are cleared. This cannot be undone." }
        if #liveNames > 0 then
            lines[#lines + 1] = "It is in: " .. table.concat(liveNames, ", ") .. "."
            lines[#lines + 1] = "Its locks stop opening anything, and its pages show an empty puzzle."
        end
        lines[#lines + 1] = PeopleLine(row)
        Confirm("Remove this puzzle?", lines, "Remove", function()
            PuzzlePlace.Forget(id)
        end)
    end)

    local people = cond(#row.people > 0, "At it: " .. table.concat(row.people, ", "), nil)

    local children = {
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
    }
    if people ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"sizeS", "info"},
            width = "100%",
            height = "auto",
            text = people,
        }
    end
    children[#children + 1] = gui.Label{
        classes = {"sizeS", "fgMuted"},
        width = "100%",
        height = "auto",
        text = row.where,
    }
    for _, h in ipairs(row.homes) do
        children[#children + 1] = HomePanel(row, h)
    end
    children[#children + 1] = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 4,
        children = buttons,
    }
    children[#children + 1] = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 2,
        children = removeButtons,
    }

    return gui.Panel{
        classes = {"bordered"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        vmargin = 3,
        pad = 6,
        borderBox = true,
        children = children,
    }
end

--"New puzzle": a name and a type, then the type's setup.
---@param button Panel
local function ShowNewPuzzle(button)
    if button.popup ~= nil then
        button.popup = nil
        return
    end
    local types = {}
    for _, t in ipairs(PuzzleType.List()) do
        types[#types + 1] = { id = t.id, text = t.name }
    end
    local m_type = types[1] ~= nil and types[1].id or nil
    local nameInput
    local function Create()
        if m_type == nil then
            return
        end
        local def = PuzzleType.Get(m_type)
        local name = string.gsub(tostring(nameInput.text or ""), "^%s*(.-)%s*$", "%1")
        if name == "" then
            name = def ~= nil and def.name or "Puzzle"
        end
        local id = "solo_" .. Puzzle.SafeId(dmhub.GenerateGuid())
        Puzzle.Create(id, m_type, nil, name)
        Puzzle.IndexPuzzle(id, { kind = "standalone" })
        button.popup = nil
        ShowSetup(button, id)
    end
    nameInput = gui.Input{
        width = 240,
        height = 26,
        bgimage = "panels/square.png",
        bgcolor = "#00000059",
        border = 1,
        borderColor = "#ffffff47",
        hpad = 6,
        borderBox = true,
        characterLimit = 80,
        placeholderText = "Name players will see",
        text = "",
        submit = function(element)
            Create()
        end,
    }
    button.popupsInheritStyles = true
    button.popup = gui.Panel{
        classes = {"bordered", "bg"},
        width = "auto",
        height = "auto",
        flow = "vertical",
        pad = 8,
        borderBox = true,
        gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", text = "Name:" },
        nameInput,
        gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", tmargin = 6, text = "Puzzle type:" },
        gui.Dropdown{
            options = types,
            idChosen = m_type,
            change = function(dropdown)
                ---@cast dropdown Dropdown
                m_type = tostring(dropdown.idChosen)
            end,
        },
        gui.Button{
            classes = {"sizeS"},
            text = "Create",
            width = 120,
            height = 28,
            halign = "right",
            tmargin = 8,
            click = function(element)
                Create()
            end,
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
            local homes = {}
            for _, h in ipairs(row.homes) do
                homes[#homes + 1] = h.key .. ":" .. h.text .. ":" .. tostring(h.map ~= nil)
            end
            parts[#parts + 1] = table.concat({ row.id, row.title, row.typeName, row.state, row.where,
                table.concat(row.people, ","), table.concat(homes, ","), tostring(Puzzle.Exists(row.id)) }, "|")
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
        text = "No puzzles yet. Press New puzzle, add one to a journal page, or put a Puzzle Lock on a map object.",
    }

    list = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    local newButton
    newButton = gui.Button{
        classes = {"sizeS", cond(dmhub.isDMOrPlayerHost, nil, "collapsed")},
        text = "New puzzle",
        width = 140,
        height = 28,
        halign = "left",
        vmargin = 4,
        click = function(element)
            ShowNewPuzzle(newButton)
        end,
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
        newButton,
        empty,
        list,
    }
end

DockablePanel.Register{
    name = "Puzzles",
    icon = "phosphor/puzzle-piece.png",
    --the host of a game with no Director runs its puzzles too.
    hostonly = true,
    minHeight = 200,
    vscroll = false,
    content = function()
        return CreatePuzzleList()
    end,
}
