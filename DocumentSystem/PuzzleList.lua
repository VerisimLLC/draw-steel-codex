local mod = dmhub.GetModLoading()

-- The Director's "Puzzles" panel: every puzzle in the game (from Puzzle.Index),
-- grouped Needs you / In play / Ready / Not set up / Done. A row is closed by
-- default: title, state, type and places. Open, it lists each place the puzzle
-- lives (checked each time the panel builds) and the main actions; the rest are
-- in the row's "..." menu, which right-click also opens. Remove from every place
-- keeps the puzzle; Delete puzzle forgets it.

--A puzzle stays In play this long after its last player leaves, so a flicker
--of presence does not bounce it between groups.
local LEAVE_PLAY_SECONDS = 5
--After the Director's own action, the panel rebuilds even under the mouse.
local FORCE_SECONDS = 3

--Which rows are open, this session only.
---@type table<string, boolean>
local g_open = {}
local g_doneOpen = false
--serverTime each puzzle was last seen in play.
---@type table<string, number>
local g_lastInPlay = {}
--How long a row stays lit after a player first opens its puzzle.
local HIGHLIGHT_SECONDS = 4
--Who this client has seen at each puzzle; a new name lights the row. The
--first look after loading only records, so presence that is already there
--is not a "join".
---@type table<string, table<string, boolean>>
local g_seenPeople = {}
local g_peoplePrimed = false
--A join lights its row from the next time the row looks, until this serverTime.
---@type table<string, boolean>
local g_highlightPending = {}
---@type table<string, number>
local g_highlightUntil = {}
--The outcome the Director has seen on each puzzle, for the rail's alert dot.
---@type table<string, string>
local g_seenOutcome = {}
--Timers that Pause all timers stopped, so Resume all restarts only those.
---@type table<string, boolean>
local g_pausedByAll = {}

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

--Everyone with the puzzle open but this client: the Director's own preview
--does not make a puzzle "in play".
---@param id string
---@return string[]
local function OtherPresent(id)
    local result = {}
    for _, userid in ipairs(Puzzle.PresentUsers(id)) do
        if userid ~= dmhub.userid then
            result[#result + 1] = userid
        end
    end
    return result
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
---@field group "needs"|"play"|"ready"|"setup"|"done"
---@field exists boolean
---@field people string[] names, not this client
---@field placesText string
---@field gone integer
---@field homes PuzzleListHome[]
---@field message string|nil the Needs-you line
---@field timed boolean the puzzle has a time limit
---@field hinted boolean its type has a hint

---@param id string
---@param key string
---@param home PuzzleHome
---@return PuzzleListHome
local function BuildHome(id, key, home)
    local live = PuzzlePlace.HomeLive(id, home)
    local kindText = ({ lock = "Lock", journal = "Page", table = "Table", rail = "Rail" })[home.kind] or "Place"
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

--The Needs-you line: what happened, who did it, what its locks did.
---@param id string
---@param status PuzzleStatus
---@return string
local function OutcomeMessage(id, status)
    local text
    local effects
    if status.solved then
        text = string.format("%s solved it.", Puzzle.UserName(status.solvedBy or ""))
        effects = Puzzle.LockEffectLines(id, "onSolve")
    else
        local timedOut = status.deadline ~= nil and dmhub.serverTime >= status.deadline
        text = cond(timedOut, "Time ran out.", "It failed.")
        effects = Puzzle.LockEffectLines(id, "onFail")
    end
    if #effects > 0 then
        text = string.format("%s Its locks: %s.", text, table.concat(effects, "; "))
    end
    return text
end

---@param id string
---@param entry PuzzleIndexEntry
---@return PuzzleListRow
local function BuildRow(id, entry)
    local def = Puzzle.GetType(id)
    local status = Puzzle.Status(id)
    ---@type PuzzleListRow
    local row = {
        id = id,
        entry = entry,
        title = Puzzle.Title(id),
        typeName = def ~= nil and def.name or "No type chosen",
        group = "ready",
        exists = Puzzle.Exists(id),
        people = {},
        placesText = "",
        gone = 0,
        homes = {},
        message = nil,
        timed = false,
        hinted = def ~= nil and def.Hint ~= nil,
    }
    if def ~= nil then
        row.timed = Puzzle.EffectiveLimit(Puzzle.ReadConfig(id)) > 0
    end
    for _, userid in ipairs(OtherPresent(id)) do
        row.people[#row.people + 1] = Puzzle.UserNameWhere(id, userid)
    end

    if def == nil then
        row.group = "setup"
    elseif status.solved or status.failed then
        if Puzzle.NeedsDirector(id) then
            row.group = "needs"
            row.message = OutcomeMessage(id, status)
        else
            row.group = "done"
        end
    else
        local now = dmhub.serverTime
        if #row.people > 0 or Puzzle.TimeLeft(id) ~= nil then
            g_lastInPlay[id] = now
            row.group = "play"
        elseif g_lastInPlay[id] ~= nil and now - g_lastInPlay[id] < LEAVE_PLAY_SECONDS then
            row.group = "play"
        end
    end

    for key, home in pairs(Puzzle.Homes(id)) do
        local h = BuildHome(id, key, home)
        row.homes[#row.homes + 1] = h
        if not h.live then
            row.gone = row.gone + 1
        end
    end
    table.sort(row.homes, function(a, b) return a.text < b.text end)
    if #row.homes == 0 then
        row.placesText = "not placed"
    else
        row.placesText = string.format("%d %s", #row.homes, cond(#row.homes == 1, "place", "places"))
    end
    return row
end

---@class PuzzleStateView
---@field icon string|nil
---@field text string
---@field class string|nil
---@field kind string what decides icon and colour; a change rebuilds the row

--The right side of a row's title line. Read again every second: the timer and
--the people at it change in place, without rebuilding the row.
---@param row PuzzleListRow
---@return PuzzleStateView
local function StateView(row)
    local id = row.id
    if row.group == "setup" then
        return { icon = "phosphor/warning-fill.png", text = "Not set up", class = "fgMuted", kind = "setup" }
    end
    local status = Puzzle.Status(id)
    if row.group == "needs" or row.group == "done" then
        if status.failed then
            return { icon = "phosphor/x-circle-fill.png", text = "Failed", class = "danger", kind = "failed" }
        end
        return { icon = "phosphor/check-circle-fill.png", text = cond(status.bypassed, "Bypassed", "Solved"),
            class = "success", kind = "solved" }
    end

    local parts = {}
    local people = OtherPresent(id)
    if #people == 1 then
        parts[#parts + 1] = string.format("%s at it", Puzzle.UserName(people[1]))
    elseif #people > 1 then
        parts[#parts + 1] = string.format("%d at it", #people)
    end
    local left = Puzzle.TimeLeft(id)
    local urgent = false
    if left ~= nil then
        if Puzzle.TimerPaused(id) then
            parts[#parts + 1] = FormatTime(left) .. " paused"
        elseif left < 60 then
            parts[#parts + 1] = FormatTime(left) .. " left!"
            urgent = true
        else
            parts[#parts + 1] = FormatTime(left)
        end
    else
        local limit = Puzzle.EffectiveLimit(Puzzle.ReadConfig(id))
        if limit > 0 then
            parts[#parts + 1] = FormatTime(limit)
        end
    end
    local text = table.concat(parts, "  ")
    if urgent then
        return { icon = "phosphor/warning-fill.png", text = text, class = "warning", kind = "urgent" }
    elseif #people > 0 then
        return { icon = "phosphor/user-fill.png", text = text, class = nil, kind = "people" }
    elseif text ~= "" then
        return { icon = "phosphor/hourglass.png", text = text, class = "fgMuted", kind = "timer" }
    end
    return { icon = nil, text = "", class = nil, kind = "none" }
end

--What the panel's rows hand back to it: actions rebuild at once even under
--the mouse, and an open menu or a drag holds rebuilds.
---@class PuzzleListCtx
---@field Act fun(fn: fun())
---@field Toggle fun(id: string)
---@field SetPopupHost fun(element: Panel)
---@field SetDragging fun(dragging: boolean)

---@param text string
---@param click fun()
---@param width number|nil
---@return Panel
local function RowButton(text, click, width)
    return gui.Button{
        classes = {"sizeXs"},
        text = text,
        width = width or cond(#text > 12, 112, cond(#text > 7, 84, 64)),
        height = 24,
        halign = "left",
        hmargin = 2,
        click = function(element)
            click()
        end,
    }
end

---@param text string
---@param classes string[]
---@param width number|string|nil
---@return Panel
local function RowText(text, classes, width)
    return gui.Label{
        classes = classes,
        width = width or "auto",
        height = "auto",
        halign = "left",
        valign = "center",
        textWrap = false,
        interactable = false,
        text = text,
    }
end

---@param path string
---@param class string|nil
---@param size number|nil
---@return Panel
local function RowIcon(path, class, size)
    return gui.Panel{
        classes = {class},
        width = size or 14,
        height = size or 14,
        halign = "left",
        valign = "center",
        rmargin = 4,
        bgimage = path,
        bgcolor = "white",
        interactable = false,
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
        --a lock's targets stay with the puzzle through a type change.
        local locks = Puzzle.Exists(id) and Puzzle.ReadConfig(id).locks or nil
        Puzzle.Create(id, typeid, cond(type(locks) == "table", { locks = locks }, nil), Puzzle.Title(id))
        button.popup = nil
        ShowSetup(button, id)
    end)
end

--Same size and layout as Puzzle.ConfirmWide, for the confirms that are not
--about every place at once.
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
        width = 720,
        height = 200 + 40 * #lines,
        buttonsHalign = "center",
        buttons = {
            { text = "Cancel", escapeActivates = true, click = function() end },
            { text = confirmText, click = confirm },
        },
        gui.Panel{
            flow = "vertical",
            width = 640,
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

---@param id string
---@param home PuzzleHome
local function OpenHome(id, home)
    if home.kind == "lock" then
        Puzzle.OpenLockWindow(id, home.floorid --[[@as string]], home.objid --[[@as string]])
    else
        local page = (dmhub.GetTable(CustomDocument.tableName) or {})[home.docid]
        if page ~= nil then
            page:ShowDocument()
        end
    end
end

---@param ctx PuzzleListCtx
---@param id string
---@param h PuzzleListHome
local function ConfirmRemoveHome(ctx, id, h)
    local home = h.home
    local lines = {}
    if home.kind == "lock" then
        lines[#lines + 1] = cond(home.placed == "object", "The lock object is taken off the map.",
            cond(home.placed == "component", "The object stops being a lock.", "The object keeps its Puzzle Lock, with no puzzle set."))
        lines[#lines + 1] = "What this lock opens is forgotten."
    elseif home.kind == "table" then
        lines[#lines + 1] = "The puzzle is taken off your table, and off the players' tables if you shared it."
    elseif home.kind == "rail" then
        lines[#lines + 1] = "The button is taken off your icon rail."
    else
        lines[#lines + 1] = "The puzzle is taken off the page."
    end
    lines[#lines + 1] = "The puzzle stays in this panel."
    Confirm(string.format("Remove from %s?", PuzzlePlace.HomeName(home)), lines, "Remove", function()
        ctx.Act(function() PuzzlePlace.RemoveHome(id, h.key) end)
    end)
end

--A kebab button: its menu is built when it opens, so it never goes stale.
---@param ctx PuzzleListCtx
---@param entries fun(element: Panel): table[]
---@return Panel
local function Kebab(ctx, entries)
    return gui.Panel{
        bgimage = "panels/square.png",
        bgcolor = "clear",
        width = 28,
        height = 24,
        halign = "right",
        valign = "center",
        click = function(element)
            if element.popup ~= nil then
                element.popup = nil
                return
            end
            ctx.SetPopupHost(element)
            element.popup = gui.ContextMenu{ entries = entries(element) }
        end,
        hover = function(element)
            gui.Tooltip("More actions")(element)
        end,
        gui.Panel{
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            bgimage = "phosphor/dots-three-vertical-bold.png",
            bgcolor = "white",
            interactable = false,
        },
    }
end

--The row's "..." menu (and its right-click).
---@param ctx PuzzleListCtx
---@param row PuzzleListRow
---@param host Panel the element the menu hangs from; Setup opens there too
---@return table[]
local function RowMenuEntries(ctx, row, host)
    local id = row.id
    local function close()
        host.popup = nil
    end
    local entries = {
        { text = "Place", group = "place", submenu = PuzzlePlace.MenuEntries(id, close) },
        { text = "Setup", group = "place", click = function()
            close()
            --after the menu has gone, so the setup popup is not closed with it.
            dmhub.Schedule(0.01, function()
                if not mod.unloaded and host.valid then
                    ctx.SetPopupHost(host)
                    ShowSetup(host, id)
                end
            end)
        end },
    }
    if row.exists then
        local status = Puzzle.Status(id)
        if not status.solved then
            entries[#entries + 1] = { text = "Solve", group = "live", click = function()
                close()
                Puzzle.ConfirmWide(id, "Solve the puzzle?", { "It is marked solved for everyone." }, "Solve", function()
                    ctx.Act(function() Puzzle.Solve(id) end)
                end, { effects = "onSolve" })
            end }
            entries[#entries + 1] = { text = "Bypass", group = "live", click = function()
                close()
                Puzzle.ConfirmWide(id, "Bypass the puzzle?", { "It opens as if solved, marked as bypassed." }, "Bypass", function()
                    ctx.Act(function() Puzzle.Bypass(id) end)
                end, { effects = "onSolve" })
            end }
        end
        entries[#entries + 1] = { text = "Reset...", group = "live", click = function()
            close()
            Puzzle.ConfirmWide(id, "Reset the puzzle?", { "The table's progress will be lost, and the timer and hint start over." }, "Reset", function()
                if not mod.unloaded then
                    ctx.Act(function()
                        g_pausedByAll[id] = nil
                        Puzzle.Reset(id)
                    end)
                end
            end, { always = true, effects = "onSolve", effectsVerb = "What its locks did is undone" })
        end }
    end
    local liveNames = LiveHomeNames(row)
    if #liveNames > 0 then
        entries[#entries + 1] = { text = "Remove from every place...", group = "remove", click = function()
            close()
            local lines = { "It is taken out of: " .. table.concat(liveNames, ", ") .. ".",
                "The puzzle stays in this panel." }
            lines[#lines + 1] = PeopleLine(row)
            Confirm(string.format("Remove \"%s\" from every place?", row.title), lines, "Remove", function()
                ctx.Act(function() PuzzlePlace.RemoveEverywhere(id) end)
            end)
        end }
    end
    entries[#entries + 1] = { text = "Delete puzzle...", group = "delete", click = function()
        close()
        local lines = { "Its board and status are cleared. This cannot be undone." }
        if #liveNames > 0 then
            lines[#lines + 1] = "It is in: " .. table.concat(liveNames, ", ") .. "."
            lines[#lines + 1] = "Its locks stop opening anything, and its pages show an empty puzzle."
        end
        lines[#lines + 1] = PeopleLine(row)
        Confirm(string.format("Delete \"%s\"?", row.title), lines, "Delete", function()
            ctx.Act(function() PuzzlePlace.Forget(id) end)
        end)
    end }
    return entries
end

---@param ctx PuzzleListCtx
---@param row PuzzleListRow
---@param h PuzzleListHome
---@return Panel
local function HomeLine(ctx, row, h)
    local id = row.id
    local home = h.home
    local buttons = {}
    if not h.live then
        buttons[#buttons + 1] = RowButton("Clear", function()
            ctx.Act(function()
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
        end)
    elseif home.kind == "lock" and h.map ~= nil and home.floorid ~= nil and home.objid ~= nil then
        local map, floorid, objid = h.map, home.floorid --[[@as string]], home.objid --[[@as string]]
        buttons[#buttons + 1] = RowButton("Go to", function()
            GoTo(map, floorid, objid)
        end)
        buttons[#buttons + 1] = Kebab(ctx, function(element)
            local entries = {}
            if Puzzle.Exists(id) then
                entries[#entries + 1] = { text = "Open here", click = function()
                    element.popup = nil
                    OpenHome(id, home)
                end }
            end
            entries[#entries + 1] = { text = "Remove from here...", click = function()
                element.popup = nil
                ConfirmRemoveHome(ctx, id, h)
            end }
            return entries
        end)
    else
        if Puzzle.Exists(id) or home.kind == "journal" then
            buttons[#buttons + 1] = RowButton("Open", function()
                OpenHome(id, home)
            end)
        end
        buttons[#buttons + 1] = RowButton("Remove", function()
            ConfirmRemoveHome(ctx, id, h)
        end)
    end
    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        tmargin = 2,
        gui.Panel{ width = 24, height = 1, halign = "left" },
        RowText(h.text, {"sizeS", cond(h.live, nil, "fgMuted")}, "100%-160"),
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            children = buttons,
        },
    }
end

--The widest the state may get; longer text ends in "...", and the names
--are in its tooltip.
local STATE_MAX_WIDTH = 170

--Roughly how wide a sizeS state is, so the title can be cut to fit beside it.
---@param view PuzzleStateView
---@return number
local function StateWidth(view)
    if view.text == "" then
        return 0
    end
    return math.min(STATE_MAX_WIDTH, 22 + 8 * (#view.text + 1))
end

---@param ctx PuzzleListCtx
---@param row PuzzleListRow
---@param view PuzzleStateView
---@return Panel
local function StatePanel(ctx, row, view)
    local width = StateWidth(view)
    local label = gui.Label{
        classes = {"sizeS", view.class},
        width = cond(width >= STATE_MAX_WIDTH, width - 22, "auto"),
        height = "auto",
        valign = "center",
        textWrap = false,
        textOverflow = "ellipsis",
        interactable = false,
        text = view.text,
    }
    return gui.Panel{
        flow = "horizontal",
        width = StateWidth(view),
        height = 24,
        halign = "right",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        thinkTime = 1,
        think = function(element)
            label.text = StateView(row).text
        end,
        hover = function(element)
            local names = {}
            for _, userid in ipairs(OtherPresent(row.id)) do
                names[#names + 1] = Puzzle.UserNameWhere(row.id, userid)
            end
            if #names > 0 then
                gui.Tooltip("In it now: " .. table.concat(names, ", ") .. ".")(element)
            end
        end,
        gui.Panel{ width = "auto", height = "auto", halign = "right", valign = "center", flow = "horizontal",
            interactable = false,
            view.icon ~= nil and RowIcon(view.icon, view.class) or nil,
            label,
        },
    }
end

--A player opening a puzzle lights its row for a moment.
local function NoteJoins()
    for id in pairs(Puzzle.Index()) do
        local seen = g_seenPeople[id] or {}
        local present = {}
        for _, userid in ipairs(OtherPresent(id)) do
            present[userid] = true
            if g_peoplePrimed and not seen[userid] then
                g_highlightPending[id] = true
            end
        end
        g_seenPeople[id] = present
    end
    g_peoplePrimed = true
end

--Needs-you outcomes the Director has not seen yet: the count on the rail.
---@return integer
local function UnseenOutcomes()
    if not dmhub.isDMOrPlayerHost then
        return 0
    end
    local count = 0
    for id in pairs(Puzzle.Index()) do
        if Puzzle.NeedsDirector(id) and g_seenOutcome[id] ~= Puzzle.OutcomeKey(id) then
            count = count + 1
        end
    end
    return count
end

--The rail's hover label while the dot is lit: which puzzles, up to three.
---@return string|nil
local function UnseenOutcomesText()
    if not dmhub.isDMOrPlayerHost then
        return nil
    end
    local titles = {}
    for id in pairs(Puzzle.Index()) do
        if Puzzle.NeedsDirector(id) and g_seenOutcome[id] ~= Puzzle.OutcomeKey(id) then
            local title = Puzzle.Title(id)
            --one line beside the rail: long titles are cut short.
            if #title > 28 then
                title = string.sub(title, 1, 26) .. "..."
            end
            titles[#titles + 1] = title
        end
    end
    if #titles == 0 then
        return nil
    end
    table.sort(titles)
    local shown = {}
    for i = 1, math.min(3, #titles) do
        shown[#shown + 1] = titles[i]
    end
    local text = "Needs you: " .. table.concat(shown, ", ")
    if #titles > 3 then
        text = string.format("%s (+%d more)", text, #titles - 3)
    end
    return text
end

local function MarkOutcomesSeen()
    for id in pairs(Puzzle.Index()) do
        local key = Puzzle.OutcomeKey(id)
        if key ~= nil then
            g_seenOutcome[id] = key
        end
    end
end

---@param button Panel
---@param on boolean
local function SetEnabled(button, on)
    button:SetClass("disabled", not on)
    button.interactable = on
end

--The quick controls: fixed slots, so a control that stops applying greys out
--instead of vanishing and sliding the next one under a second click. Show
--hint, which cannot be taken back, sits last after a gap.
---@param ctx PuzzleListCtx
---@param row PuzzleListRow
---@return Panel|nil
local function QuickControls(ctx, row)
    local id = row.id
    if not (row.group == "play" or (row.group == "ready" and row.timed)) then
        return nil
    end
    if not row.timed and not row.hinted then
        return nil
    end
    local updates = {}
    local children = { gui.Panel{ width = 22, height = 1, halign = "left" } }
    if row.timed then
        local timerButton = RowButton("Start timer", function()
            ctx.Act(function()
                if Puzzle.TimeLeft(id) == nil then
                    Puzzle.StartTimer(id)
                elseif Puzzle.TimerPaused(id) then
                    g_pausedByAll[id] = nil
                    Puzzle.ResumeTimer(id)
                else
                    Puzzle.PauseTimer(id)
                end
            end)
        end, 84)
        local extendButton = RowButton("+1 min", function()
            ctx.Act(function() Puzzle.ExtendTimer(id, 60) end)
        end, 64)
        children[#children + 1] = timerButton
        children[#children + 1] = extendButton
        updates[#updates + 1] = function(status)
            local left = Puzzle.TimeLeft(id)
            local over = status.solved == true or status.failed == true
            timerButton.text = cond(left == nil, "Start timer", cond(Puzzle.TimerPaused(id), "Resume", "Pause"))
            SetEnabled(timerButton, not over)
            SetEnabled(extendButton, left ~= nil and not over)
        end
    end
    if row.hinted then
        local hintButton = RowButton("Show hint", function()
            ctx.Act(function() Puzzle.RevealHint(id) end)
        end, 84)
        children[#children + 1] = gui.Panel{ width = 14, height = 1, halign = "left" }
        children[#children + 1] = hintButton
        updates[#updates + 1] = function(status)
            hintButton.text = cond(status.hint == true, "Hint shown", "Show hint")
            SetEnabled(hintButton, status.hint ~= true and not status.solved and not status.failed)
        end
    end
    local function Update()
        local status = Puzzle.Status(id)
        for _, update in ipairs(updates) do
            update(status)
        end
    end
    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        tmargin = 4,
        create = function(element)
            Update()
        end,
        thinkTime = 0.5,
        think = function(element)
            Update()
        end,
        children = children,
    }
end

---@param ctx PuzzleListCtx
---@param row PuzzleListRow
---@param view PuzzleStateView
---@return Panel
local function RowPanel(ctx, row, view)
    local id = row.id
    local open = g_open[id] == true
    local stateWidth = StateWidth(view)

    local children = {}
    --title line: the whole line opens and closes the row.
    children[#children + 1] = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = 24,
        bgimage = "panels/square.png",
        bgcolor = "clear",
        click = function(element)
            ctx.Toggle(id)
        end,
        gui.Panel{
            width = 24,
            height = 24,
            valign = "center",
            interactable = false,
            gui.Panel{
                width = 12,
                height = 12,
                halign = "center",
                valign = "center",
                bgimage = cond(open, "phosphor/caret-down-fill.png", "phosphor/caret-right-fill.png"),
                bgcolor = "white",
                interactable = false,
            },
        },
        --the grip: the row drags. Its tooltip says how, without covering
        --the row whenever the mouse crosses it.
        gui.Panel{
            width = 14,
            height = 14,
            valign = "center",
            rmargin = 4,
            bgimage = "ui-icons/ph-dots-six-vertical-fill.png",
            bgcolor = "white",
            opacity = 0.6,
            hover = function(element)
                gui.Tooltip("Drag onto a page, an object, the table, the rail or chat. Right-click for more.")(element)
            end,
        },
        gui.Label{
            classes = {"sizeM", "bold"},
            width = string.format("100%%-%d", 42 + stateWidth),
            height = "auto",
            valign = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            interactable = false,
            text = row.title,
        },
        stateWidth > 0 and StatePanel(ctx, row, view) or nil,
    }

    local line2 = {
        gui.Panel{ width = 24, height = 1, halign = "left" },
        RowText(string.format("%s - %s", row.typeName, row.placesText), {"sizeS", "fgMuted"}),
    }
    if row.gone > 0 then
        line2[#line2 + 1] = gui.Panel{ width = 8, height = 1 }
        line2[#line2 + 1] = RowIcon("phosphor/warning-fill.png", "warning")
        line2[#line2 + 1] = RowText(string.format("%d gone", row.gone), {"sizeS", "warning"})
    end
    line2[#line2 + 1] = Kebab(ctx, function(element)
        return RowMenuEntries(ctx, row, element)
    end)
    children[#children + 1] = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        children = line2,
    }
    children[#children + 1] = QuickControls(ctx, row)

    --Needs you: what happened, then the way to it and Dismiss.
    if row.group == "needs" and row.message ~= nil then
        children[#children + 1] = gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            tmargin = 2,
            interactable = false,
            gui.Panel{ width = 24, height = 1, halign = "left" },
            gui.Label{
                classes = {"sizeS"},
                width = "100%-24",
                height = "auto",
                halign = "left",
                interactable = false,
                text = row.message,
            },
        }
        local buttons = {}
        local lock = nil
        for _, h in ipairs(row.homes) do
            if lock == nil and h.live and h.map ~= nil and h.home.kind == "lock" then
                lock = h
            end
        end
        if lock ~= nil then
            local map, floorid, objid = lock.map, lock.home.floorid --[[@as string]], lock.home.objid --[[@as string]]
            buttons[#buttons + 1] = RowButton("Go to", function()
                GoTo(map, floorid, objid)
            end)
        elseif row.exists then
            buttons[#buttons + 1] = RowButton("Open", function()
                Puzzle.OpenWindow(id)
            end)
        end
        buttons[#buttons + 1] = RowButton("Dismiss", function()
            ctx.Act(function() Puzzle.Dismiss(id) end)
        end)
        children[#children + 1] = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            lmargin = 22,
            tmargin = 4,
            children = buttons,
        }
    end

    if open then
        if #row.homes == 0 then
            children[#children + 1] = gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = "auto",
                tmargin = 2,
                interactable = false,
                gui.Panel{ width = 24, height = 1, halign = "left" },
                gui.Label{
                    classes = {"sizeS", "fgMuted"},
                    width = "100%-24",
                    height = "auto",
                    halign = "left",
                    interactable = false,
                    text = "Not placed yet. Drag it onto a page, an object, the table or chat.",
                },
            }
        end
        for _, h in ipairs(row.homes) do
            children[#children + 1] = HomeLine(ctx, row, h)
        end
        local buttons = {}
        if row.exists then
            buttons[#buttons + 1] = RowButton("Open", function()
                Puzzle.OpenWindow(id)
            end)
            buttons[#buttons + 1] = RowButton("Show everyone", function()
                Puzzle.PushToEveryone(id)
            end)
        else
            local setupButton
            setupButton = RowButton("Setup", function()
                ctx.SetPopupHost(setupButton)
                ShowSetup(setupButton, id)
            end)
            buttons[#buttons + 1] = setupButton
        end
        children[#children + 1] = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            lmargin = 22,
            tmargin = 4,
            children = buttons,
        }
    end

    ---@param element Panel
    local function UpdateHighlight(element)
        if g_highlightPending[id] then
            g_highlightPending[id] = nil
            g_highlightUntil[id] = dmhub.serverTime + HIGHLIGHT_SECONDS
        end
        local untilTime = g_highlightUntil[id]
        element:SetClass("puzzleJoined", untilTime ~= nil and dmhub.serverTime < untilTime)
    end

    return gui.Panel{
        classes = {"bordered"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        vmargin = 3,
        pad = 6,
        borderBox = true,
        styles = {
            { selectors = {"puzzleJoined"}, borderWidth = 2, borderColor = "#7fd0ffff" },
        },
        create = function(element)
            UpdateHighlight(element)
        end,
        thinkTime = 0.5,
        think = function(element)
            UpdateHighlight(element)
        end,
        --dragged onto a page, chat, the rail, the table or the map.
        draggable = true,
        canDragOnto = function(element, target)
            return PuzzlePlace.RowCanDragOnto(target)
        end,
        dragging = function(element, target)
            ctx.SetDragging(true)
            PuzzlePlace.RowDraggingAnywhere(element, id, target)
        end,
        drag = function(element, target)
            ctx.SetDragging(false)
            PuzzlePlace.RowDroppedAnywhere(element, id, target)
        end,
        destroy = function(element)
            PuzzlePlace.RowDragEnded()
        end,
        rightClick = function(element)
            ctx.SetPopupHost(element)
            element.popup = gui.ContextMenu{ entries = RowMenuEntries(ctx, row, element) }
        end,
        children = children,
    }
end

--"New puzzle": a name and a type, then the type's setup.
---@param button Panel
---@param onCreate fun(id: string)
local function ShowNewPuzzle(button, onCreate)
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
        onCreate(id)
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

local GROUPS = {
    { key = "needs", text = "NEEDS YOU" },
    { key = "play", text = "IN PLAY" },
    { key = "ready", text = "READY" },
    { key = "setup", text = "NOT SET UP" },
    { key = "done", text = "DONE" },
}

---@param text string
---@return Panel
local function GroupHeader(text)
    return gui.Label{
        classes = {"sizeS", "bold", "fgMuted"},
        width = "100%",
        height = "auto",
        tmargin = 8,
        bmargin = 2,
        text = text,
    }
end

local function CreatePuzzleList()
    local root
    local list
    local empty
    local statusPanel
    local m_signature = nil
    local m_status = nil
    local m_forceUntil = 0
    local m_dragging = false
    ---@type Panel|nil
    local m_popupHost = nil
    ---@type fun(force: boolean|nil)
    local Refresh

    --The last placement and its Undo, until it goes stale.
    local function RefreshStatus()
        local status = PuzzlePlace.Status()
        local key = status ~= nil and (status.text .. tostring(status.time)) or nil
        if key == m_status then
            return
        end
        m_status = key
        if status == nil then
            statusPanel.children = {}
            statusPanel:SetClass("collapsed", true)
            return
        end
        local children = {
            gui.Label{
                classes = {"sizeS"},
                width = "100%-150",
                height = "auto",
                valign = "center",
                text = status.text,
            },
        }
        if status.undo ~= nil then
            children[#children + 1] = RowButton("Undo", function()
                PuzzlePlace.UndoLast()
                RefreshStatus()
            end)
        end
        children[#children + 1] = RowButton("Dismiss", function()
            PuzzlePlace.ClearStatus()
            RefreshStatus()
        end)
        statusPanel.children = children
        statusPanel:SetClass("collapsed", false)
    end

    ---@type PuzzleListCtx
    local ctx = {
        Act = function(fn)
            m_forceUntil = dmhub.serverTime + FORCE_SECONDS
            fn()
        end,
        Toggle = function(id)
            g_open[id] = not g_open[id] or nil
            Refresh(true)
        end,
        SetPopupHost = function(element)
            m_popupHost = element
        end,
        SetDragging = function(dragging)
            m_dragging = dragging
        end,
    }

    --Changes the Director did not make wait while the pointer is over the
    --list, a menu is open or a row is being dragged, so nothing moves under
    --the mouse.
    local function Held()
        if dmhub.serverTime < m_forceUntil then
            return false
        end
        if m_dragging then
            return true
        end
        if m_popupHost ~= nil and m_popupHost.valid and m_popupHost.popup ~= nil then
            return true
        end
        --mousePoint is the pointer as a fraction of the panel, wherever it
        --is (SheetPanel.cs), so "inside" is both coordinates within 0..1.
        local mp = root.mousePoint
        return mp.x > 0 and mp.x < 1 and mp.y > 0 and mp.y < 1
    end

    --Rebuilds only when something shown changed, apart from the timer and the
    --names at a puzzle, which tick in place.
    Refresh = function(force)
        RefreshStatus()
        NoteJoins()
        --the Director is looking at the list, so its outcomes are seen.
        MarkOutcomesSeen()
        local rows = {}
        for id, entry in pairs(Puzzle.Index()) do
            rows[#rows + 1] = BuildRow(id, entry)
        end
        table.sort(rows, function(a, b)
            if a.title ~= b.title then
                return a.title < b.title
            end
            return a.id < b.id
        end)
        local views = {}
        local parts = { tostring(g_doneOpen) }
        for _, row in ipairs(rows) do
            local view = StateView(row)
            views[row.id] = view
            local homes = {}
            for _, h in ipairs(row.homes) do
                homes[#homes + 1] = h.key .. ":" .. h.text .. ":" .. tostring(h.map ~= nil)
            end
            parts[#parts + 1] = table.concat({ row.id, row.title, row.typeName, row.group, row.placesText,
                tostring(row.gone), view.kind, tostring(StateWidth(view)), row.message or "", tostring(row.timed), tostring(row.hinted),
                tostring(g_open[row.id] == true), table.concat(homes, ","), tostring(row.exists) }, "|")
        end
        local signature = table.concat(parts, ";")
        if signature == m_signature then
            return
        end
        if not force and m_signature ~= nil and Held() then
            return
        end
        m_signature = signature

        local children = {}
        for _, group in ipairs(GROUPS) do
            local members = {}
            for _, row in ipairs(rows) do
                if row.group == group.key then
                    members[#members + 1] = row
                end
            end
            if #members > 0 then
                if group.key == "done" then
                    children[#children + 1] = gui.Panel{
                        flow = "horizontal",
                        width = "100%",
                        height = 24,
                        tmargin = 8,
                        bgimage = "panels/square.png",
                        bgcolor = "clear",
                        click = function(element)
                            g_doneOpen = not g_doneOpen
                            Refresh(true)
                        end,
                        RowIcon(cond(g_doneOpen, "phosphor/caret-down-fill.png", "phosphor/caret-right-fill.png"), nil, 12),
                        RowText(string.format("%s (%d)", group.text, #members), {"sizeS", "bold", "fgMuted"}),
                    }
                else
                    children[#children + 1] = GroupHeader(group.text)
                end
                if group.key ~= "done" or g_doneOpen then
                    for _, row in ipairs(members) do
                        children[#children + 1] = RowPanel(ctx, row, views[row.id])
                    end
                end
            end
        end
        list.children = children
        empty:SetClass("collapsed", #rows > 0)
    end

    statusPanel = gui.Panel{
        classes = {"bordered", "collapsed"},
        flow = "horizontal",
        width = "100%",
        height = "auto",
        valign = "top",
        vmargin = 3,
        pad = 6,
        borderBox = true,
    }

    empty = gui.Label{
        classes = {"sizeS", "fgMuted", "collapsed"},
        width = "100%",
        height = "auto",
        valign = "top",
        pad = 8,
        borderBox = true,
        text = "No puzzles yet. Press New puzzle, add one to a journal page, or put a Puzzle Lock on a map object.",
    }

    list = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
    }

    local newButton
    newButton = gui.Button{
        classes = {"sizeS", cond(dmhub.isDMOrPlayerHost, nil, "collapsed")},
        text = "New puzzle",
        width = 140,
        height = 28,
        halign = "left",
        valign = "top",
        vmargin = 4,
        click = function(element)
            ctx.SetPopupHost(newButton)
            ShowNewPuzzle(newButton, function(id)
                g_open[id] = true
                m_forceUntil = dmhub.serverTime + FORCE_SECONDS
            end)
        end,
    }

    --Pause puzzle timers stops every running timer; Resume restarts the ones
    --it stopped, not those the Director paused one by one.
    local pauseAll
    local function UpdatePauseAll()
        local running, resumable = 0, 0
        for id in pairs(Puzzle.Index()) do
            local status = Puzzle.Status(id)
            if not status.solved and not status.failed and Puzzle.TimeLeft(id) ~= nil then
                if Puzzle.TimerPaused(id) then
                    if g_pausedByAll[id] then
                        resumable = resumable + 1
                    end
                else
                    running = running + 1
                end
            end
        end
        local resume = resumable > 0 and running == 0
        pauseAll.data.resume = resume
        pauseAll.text = cond(resume, "Resume puzzle timers", "Pause puzzle timers")
        SetEnabled(pauseAll, resume or running > 0)
    end
    pauseAll = gui.Button{
        classes = {"sizeS"},
        text = "Pause puzzle timers",
        width = 180,
        height = 28,
        halign = "left",
        valign = "top",
        vmargin = 4,
        lmargin = 8,
        click = function(element)
            local resume = element.data.resume == true
            ctx.Act(function()
                for id in pairs(Puzzle.Index()) do
                    local status = Puzzle.Status(id)
                    if not status.solved and not status.failed and Puzzle.TimeLeft(id) ~= nil then
                        if resume then
                            if g_pausedByAll[id] and Puzzle.TimerPaused(id) then
                                Puzzle.ResumeTimer(id)
                            end
                        elseif not Puzzle.TimerPaused(id) then
                            g_pausedByAll[id] = true
                            Puzzle.PauseTimer(id)
                        end
                    end
                end
                if resume then
                    g_pausedByAll = {}
                end
            end)
        end,
        hover = function(element)
            gui.Tooltip(cond(element.data.resume == true, "Restarts the puzzle timers you paused here.",
                "Pauses every running puzzle timer."))(element)
        end,
        create = function(element)
            UpdatePauseAll()
        end,
        thinkTime = 0.5,
        think = function(element)
            UpdatePauseAll()
        end,
    }

    local topBar = gui.Panel{
        classes = {cond(dmhub.isDMOrPlayerHost, nil, "collapsed")},
        flow = "horizontal",
        width = "100%",
        height = "auto",
        valign = "top",
        newButton,
        pauseAll,
    }

    root = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%",
        valign = "top",
        vscroll = true,
        pad = 6,
        borderBox = true,
        monitorGame = Puzzle.ListMonitorPaths(),
        refreshGame = function(element)
            Refresh()
        end,
        create = function(element)
            Refresh(true)
        end,
        --timers count down with no write, and held changes land when the
        --pointer leaves; look again every second while it is open.
        thinkTime = 1,
        think = function(element)
            Refresh()
        end,
        topBar,
        statusPanel,
        empty,
        list,
    }
    return root
end

DockablePanel.Register{
    name = "Puzzles",
    icon = "phosphor/puzzle-piece.png",
    --the host of a game with no Director runs its puzzles too.
    hostonly = true,
    minHeight = 200,
    vscroll = false,
    --the rail's alert dot: Needs-you outcomes not seen yet, with a count.
    hasNewContent = function()
        return UnseenOutcomes() > 0
    end,
    newContentCount = UnseenOutcomes,
    newContentText = UnseenOutcomesText,
    markContentSeen = MarkOutcomesSeen,
    clearNewContent = MarkOutcomesSeen,
    content = function()
        return CreatePuzzleList()
    end,
}
