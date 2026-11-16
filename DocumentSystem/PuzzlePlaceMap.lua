local mod = dmhub.GetModLoading()

-- Putting a puzzle on the map from the Puzzles panel: drag a row onto an object
-- (it becomes a lock), next to a door (a lock object that opens it) or onto
-- empty floor (a lock object); or press Place on map and click; or Lock the
-- selected object. While dragging or placing, the target is outlined and a card
-- by the mouse says in words what a drop does. A puzzle that already has a lock
-- asks Share or Make a copy; an object locked with another puzzle asks before
-- Replace. Each placement opens the lock's setup and leaves a status line in the
-- panel with Undo. The building blocks are in PuzzlePlace.lua.

--------------------------------------------------------------------------------
-- Status line with Undo
--------------------------------------------------------------------------------

--How long the panel keeps showing the last placement.
local STATUS_SECONDS = 60

---@class PuzzlePlaceStatus
---@field text string
---@field undo (fun())|nil
---@field time number

---@type PuzzlePlaceStatus|nil
local g_status = nil

---@param text string
---@param undo (fun())|nil
local function SetStatus(text, undo)
    g_status = { text = text, undo = undo, time = dmhub.Time() }
end
PuzzlePlace.SetStatus = SetStatus

--The last placement's line for the Puzzles panel, while it is fresh.
---@return PuzzlePlaceStatus|nil
function PuzzlePlace.Status()
    if g_status ~= nil and dmhub.Time() - g_status.time > STATUS_SECONDS then
        g_status = nil
    end
    return g_status
end

function PuzzlePlace.ClearStatus()
    g_status = nil
end

--Run the last placement's Undo once.
function PuzzlePlace.UndoLast()
    local status = g_status
    g_status = nil
    if status ~= nil and status.undo ~= nil then
        status.undo()
    end
end

---@param id string
---@return string
local function PlacesText(id)
    local n = 0
    for _ in pairs(Puzzle.Homes(id)) do
        n = n + 1
    end
    return string.format("Now in %d %s.", n, cond(n == 1, "place", "places"))
end

--------------------------------------------------------------------------------
-- What is under the mouse
--------------------------------------------------------------------------------

---@class PuzzlePlaceTarget
---@field kind "object"|"door"|"floor"
---@field floorid string
---@field x number
---@field y number
---@field obj any|nil the object to lock
---@field doorX number|nil the door a new lock object opens
---@field doorY number|nil
---@field doorObjid string|nil a door object (not a drawn door)

---@param obj any
---@return boolean
local function IsDoorObject(obj)
    local door = false
    pcall(function() door = obj:GetComponent("Door") ~= nil end)
    return door
end

---@param obj any
---@return string
local function ObjectName(obj)
    local name = obj.description
    if type(name) ~= "string" or name == "" then
        return "object"
    end
    return name
end

--What a drop at (x, y) on a floor does. Objects win over doors within their
--padded bounds (PuzzlePlace.ObjectAt); a door object counts as a door.
---@param floorid string
---@param x number
---@param y number
---@return PuzzlePlaceTarget
function PuzzlePlace.TargetAt(floorid, x, y)
    local obj = PuzzlePlace.ObjectAt(floorid, x, y)
    if obj ~= nil and not IsDoorObject(obj) then
        return { kind = "object", floorid = floorid, x = x, y = y, obj = obj }
    end
    if obj ~= nil then
        return { kind = "door", floorid = floorid, x = x, y = y, doorX = obj.x, doorY = obj.y, doorObjid = obj.objid }
    end
    local door = PuzzlePlace.DoorAt(floorid, x, y)
    if door ~= nil then
        return { kind = "door", floorid = floorid, x = x, y = y, doorX = door.x, doorY = door.y }
    end
    return { kind = "floor", floorid = floorid, x = x, y = y }
end

--The puzzle an object's lock shows now, or nil.
---@param obj any
---@return string|nil
local function LockedWith(obj)
    for _, ref in ipairs(PuzzlePlace.Locks(obj.floorid, obj.objid)) do
        if ref.lock.puzzleid ~= "" then
            return ref.lock.puzzleid
        end
    end
    return nil
end

--What a drop on the target does, in words.
---@param id string
---@param target PuzzlePlaceTarget|nil nil: not over the map
---@return string text, boolean ok
function PuzzlePlace.TargetText(id, target)
    if target == nil then
        return "Can't place here", false
    end
    if target.kind == "object" then
        local name = ObjectName(target.obj)
        local current = LockedWith(target.obj)
        if current == id then
            return string.format("The %s is already locked with this puzzle", name), false
        elseif current ~= nil and Puzzle.Exists(current) then
            return string.format("Lock the %s (replaces %s)", name, Puzzle.Title(current)), true
        end
        return string.format("Lock the %s", name), true
    elseif target.kind == "door" then
        return "Place a puzzle lock that opens this door", true
    end
    return "Place a puzzle lock here", true
end

--------------------------------------------------------------------------------
-- Outline and the card by the mouse
--------------------------------------------------------------------------------

---@type {key: string, lines: any[]}|nil
local g_outline = nil

local function ClearOutline()
    if g_outline ~= nil then
        for _, line in ipairs(g_outline.lines) do
            pcall(function() line:Destroy() end)
        end
    end
    g_outline = nil
end

--Outline what a drop lands on: the object's bounds, the door, or the tile a
--lock object would go on.
---@param target PuzzlePlaceTarget|nil
local function ShowOutline(target)
    local key = "none"
    local x1, y1, x2, y2 = 0, 0, 0, 0
    if target ~= nil then
        if target.kind == "object" then
            local area = target.obj.area
            key = "obj:" .. tostring(target.obj.objid)
            x1, y1 = math.min(area.x1, area.x2), math.min(area.y1, area.y2)
            x2, y2 = math.max(area.x1, area.x2), math.max(area.y1, area.y2)
            --a small object still gets a tile-sized outline, or it reads as a dot.
            local cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
            x1, y1 = math.min(x1, cx - 0.5), math.min(y1, cy - 0.5)
            x2, y2 = math.max(x2, cx + 0.5), math.max(y2, cy + 0.5)
        else
            local cx, cy = math.floor(target.x) + 0.5, math.floor(target.y) + 0.5
            key = string.format("%s:%.0f:%.0f", target.kind, cx, cy)
            x1, y1, x2, y2 = cx - 0.5, cy - 0.5, cx + 0.5, cy + 0.5
            if target.kind == "door" then
                key = key .. string.format(":%.1f:%.1f", target.doorX, target.doorY)
            end
        end
    end
    if g_outline ~= nil and g_outline.key == key then
        return
    end
    ClearOutline()
    if target == nil then
        return
    end
    local floor = game.GetFloor(target.floorid)
    local floorIndex = floor ~= nil and floor.floorIndex or -1
    if floorIndex < 0 then
        return
    end
    local lines = {}
    local function Box(bx1, by1, bx2, by2, color)
        local corners = { {bx1, by1}, {bx2, by1}, {bx2, by2}, {bx1, by2} }
        for i = 1, 4 do
            local a, b = corners[i], corners[i % 4 + 1]
            lines[#lines + 1] = dmhub.HighlightLine{
                color = color,
                a = core.Vector2(a[1], a[2]),
                b = core.Vector2(b[1], b[2]),
                floorIndex = floorIndex,
                terrainParallax = true,
            }
        end
    end
    Box(x1, y1, x2, y2, "#ffcc00")
    if target.kind == "door" then
        Box(target.doorX - 0.6, target.doorY - 0.6, target.doorX + 0.6, target.doorY + 0.6, "#ffcc0099")
    end
    g_outline = { key = key, lines = lines }
end

--Screen pixels to a hud layer's units (the layers sit below the title bar and
--may be scaled).
---@param layer Panel
---@param px number
---@param py number
---@return number, number
local function ScreenToLayer(layer, px, py)
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if below.y <= 0 then
        return px, py
    end
    local scale = layer.renderedHeight / below.y
    return px * scale, (py - (screen.y - below.y)) * scale
end

---@return Panel|nil
local function BannerLayer()
    local hud = GameHud.instance --[[@as GameHud|nil]]
    if hud == nil then
        return nil
    end
    local layer = hud.bannerLayer
    if layer == nil or not layer.valid then
        layer = hud.documentsPanel
    end
    if layer == nil or not layer.valid then
        return nil
    end
    return layer
end

--The card by the mouse. Set its text with :FireEvent("setText", text, ok).
---@return Panel|nil
local function CreateGhost()
    local layer = BannerLayer()
    if layer == nil then
        return nil
    end
    local label = gui.Label{
        classes = {"sizeM"},
        width = "auto",
        maxWidth = 360,
        height = "auto",
        valign = "center",
        text = "",
    }
    local ghost = gui.Panel{
        classes = {"bordered", "bg"},
        styles = ThemeEngine.GetStyles(),
        halign = "left",
        valign = "top",
        width = "auto",
        height = "auto",
        hpad = 8,
        vpad = 6,
        borderBox = true,
        bgimage = true,
        thinkTime = 0.01,
        think = function(element)
            local mouse = dmhub.mouseScreenPosition
            element.x, element.y = ScreenToLayer(layer, mouse.x + 18, mouse.y + 22)
        end,
        setText = function(element, text, ok)
            label.text = text
            label:SetClass("warning", not ok)
        end,
        label,
    }
    layer:AddChild(ghost)
    ghost:MakeNonInteractiveRecursive()
    ghost:SetAsLastSibling()
    return ghost
end

--The target under the mouse right now, or nil when it is not over the map.
---@param overMap boolean
---@return PuzzlePlaceTarget|nil
local function TargetUnderMouse(overMap)
    if not overMap or game.currentFloorId == nil then
        return nil
    end
    local point = dmhub.GetMouseWorldPoint()
    if point == nil then
        return nil
    end
    return PuzzlePlace.TargetAt(game.currentFloorId, point.x, point.y)
end

--------------------------------------------------------------------------------
-- Confirms
--------------------------------------------------------------------------------

---@class PuzzlePlaceChoice
---@field text string
---@field click fun()

--A modal with Cancel (the default, and Esc) and the given choices.
---@param title string
---@param lines string[]
---@param choices PuzzlePlaceChoice[]
local function Ask(title, lines, choices)
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
    local buttons = { { text = "Cancel", escapeActivates = true, click = function() end } }
    --a confirm answered by the Enter that opened it would place twice.
    local opened = dmhub.Time()
    for _, choice in ipairs(choices) do
        local c = choice
        buttons[#buttons + 1] = {
            text = c.text,
            click = function()
                if dmhub.Time() - opened < 0.3 then
                    return
                end
                --after this dialog closes: the dialog closes the top modal once
                --its button returns, which would be a confirm the choice opens.
                dmhub.Schedule(0.05, function()
                    if not mod.unloaded then
                        c.click()
                    end
                end)
            end,
        }
    end
    GameHud.instance:ModalDialog{
        title = title,
        width = 720,
        height = 200 + 40 * #lines,
        buttonsHalign = "center",
        buttons = buttons,
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

--The live locks a puzzle already has, as names.
---@param id string
---@return string[]
local function LockNames(id)
    local names = {}
    for _, home in pairs(Puzzle.Homes(id)) do
        if home.kind == "lock" and PuzzlePlace.HomeLive(id, home) then
            names[#names + 1] = PuzzlePlace.HomeName(home)
        end
    end
    table.sort(names)
    return names
end

--A new puzzle with the same type and setup, for a second lock solved on its own.
---@param id string
---@return string
local function CopyPuzzle(id)
    local newId = "lock_" .. Puzzle.SafeId(dmhub.GenerateGuid())
    local config = Puzzle.ReadConfig(id)
    config.locks = nil
    local typeid = Puzzle.GetTypeId(id)
    if typeid ~= nil then
        Puzzle.Create(newId, typeid, config, Puzzle.Title(id) .. " (copy)")
    end
    return newId
end

--A puzzle that already locks something asks: share it, or make a copy.
---@param id string
---@param go fun(useId: string, copied: boolean)
local function ShareOrCopy(id, go)
    local names = LockNames(id)
    if #names == 0 then
        go(id, false)
        return
    end
    Ask("This puzzle already has a lock", {
        string.format("%s already locks: %s.", Puzzle.Title(id), table.concat(names, ", ")),
        "Share it: solving it at either lock solves both.",
        "Make a copy: this lock gets its own puzzle, set up the same way.",
    }, {
        { text = "Make a copy", click = function() go(CopyPuzzle(id), true) end },
        { text = "Share", click = function() go(id, false) end },
    })
end

--------------------------------------------------------------------------------
-- Placing
--------------------------------------------------------------------------------

---@param floorid string
---@return string
local function FloorText(floorid)
    local floor = game.GetFloor(floorid)
    local name = floor ~= nil and floor.description or nil
    if type(name) == "string" and name ~= "" then
        return string.format(" (%s)", name)
    end
    return ""
end

--Undo for a copy made for this placement: the copy goes too.
---@param copied boolean
---@param useId string
---@param undo fun()
---@return fun()
local function WithCopyUndo(copied, useId, undo)
    if not copied then
        return undo
    end
    return function()
        undo()
        PuzzlePlace.Forget(useId)
    end
end

--Lock an object with the puzzle (asking first when it is locked with another).
---@param id string
---@param target PuzzlePlaceTarget
local function LockTarget(id, target)
    local obj = target.obj
    local floorid, objid = obj.floorid, obj.objid
    local name = ObjectName(obj)
    local current = LockedWith(obj)
    if current == id then
        SetStatus(string.format("The %s is already locked with %s.", name, Puzzle.Title(id)), nil)
        return
    end
    ShareOrCopy(id, function(useId, copied)
        local function Done(undo)
            Puzzle.OpenLockSetup(useId, floorid, objid)
            SetStatus(string.format("Locked the %s%s with %s. %s", name, FloorText(floorid), Puzzle.Title(useId), PlacesText(useId)),
                WithCopyUndo(copied, useId, function()
                    Puzzle.CloseLockSetup(floorid, objid)
                    undo()
                end))
        end
        if current ~= nil and Puzzle.Exists(current) then
            Ask(string.format("Replace the lock on the %s?", name), {
                string.format("It is locked with %s.", Puzzle.Title(current)),
                string.format("What it opens and its range move to %s, and %s loses this lock.", Puzzle.Title(useId), Puzzle.Title(current)),
                "The door it opens stays.",
            }, {
                { text = "Replace", click = function()
                    PuzzlePlace.MoveLock(current, floorid, objid, useId)
                    Done(function()
                        PuzzlePlace.MoveLock(useId, floorid, objid, current)
                    end)
                end },
            })
            return
        end
        if current ~= nil then
            PuzzlePlace.MoveLock(current, floorid, objid, useId)
        elseif not PuzzlePlace.LockObject(floorid, objid, useId) then
            SetStatus("That object is gone.", nil)
            return
        end
        Done(function()
            local key = Puzzle.HomeKey({ kind = "lock", floorid = floorid, objid = objid })
            if key ~= nil then
                PuzzlePlace.RemoveHome(useId, key)
            end
        end)
    end)
end

--Place a lock object at the target (opening the door when it is by one).
---@param id string
---@param target PuzzlePlaceTarget
local function PlaceTarget(id, target)
    ShareOrCopy(id, function(useId, copied)
        local floorid = target.floorid
        local obj = PuzzlePlace.PlaceLockObject(floorid, target.x, target.y, useId)
        if obj == nil then
            SetStatus("Couldn't place a puzzle lock there.", nil)
            return
        end
        local objid = obj.objid
        local lock = { floorid = floorid, objid = objid, range = Puzzle.DEFAULT_LOCK_RANGE, onSolve = {}, onFail = {} }
        if target.kind == "door" then
            lock.onSolve[1] = Puzzle.DoorEffect(floorid, target.x, target.y, target.doorX, target.doorY, target.doorObjid)
        end
        if Puzzle.GetTypeId(useId) == "combination" then
            lock.bypassAttr = "mgt"
        end
        local locks = Puzzle.ReadConfig(useId).locks
        if type(locks) ~= "table" then
            locks = {}
        end
        locks[Puzzle.LockKey(floorid, objid)] = lock
        Puzzle.SetConfig(useId, { locks = locks })
        Puzzle.OpenLockSetup(useId, floorid, objid)
        local what = cond(target.kind == "door", "Placed a puzzle lock that opens the door, with %s.", "Placed a puzzle lock for %s.")
        SetStatus(string.format(what, Puzzle.Title(useId)) .. " " .. PlacesText(useId),
            WithCopyUndo(copied, useId, function()
                Puzzle.CloseLockSetup(floorid, objid)
                local key = Puzzle.HomeKey({ kind = "lock", floorid = floorid, objid = objid })
                if key ~= nil then
                    PuzzlePlace.RemoveHome(useId, key)
                end
            end))
    end)
end

--Put the puzzle on the map at a target.
---@param id string
---@param target PuzzlePlaceTarget
function PuzzlePlace.PlaceAt(id, target)
    if target.kind == "object" then
        LockTarget(id, target)
    else
        PlaceTarget(id, target)
    end
end

--------------------------------------------------------------------------------
-- Dragging a panel row
--------------------------------------------------------------------------------

---@type Panel|nil
local g_dragGhost = nil

--A Puzzles panel row is being dragged: outline the target and say what a drop
--does. Called every frame from the row's dragging event.
---@param id string
function PuzzlePlace.RowDragging(id)
    local overMap = dmhub.panelDropSurface == "map"
    local target = TargetUnderMouse(overMap)
    ShowOutline(target)
    if g_dragGhost == nil or not g_dragGhost.valid then
        g_dragGhost = CreateGhost()
    end
    if g_dragGhost ~= nil then
        local text, ok = PuzzlePlace.TargetText(id, target)
        if dmhub.panelDropSurface == nil then
            text, ok = "Can't place here", false
        end
        g_dragGhost:FireEvent("setText", text, ok)
    end
end

function PuzzlePlace.RowDragEnded()
    ClearOutline()
    if g_dragGhost ~= nil and g_dragGhost.valid then
        g_dragGhost:DestroySelf()
    end
    g_dragGhost = nil
end

--The row was released. Over the map it places; anywhere else it does nothing.
---@param id string
function PuzzlePlace.RowDropped(id)
    local target = TargetUnderMouse(dmhub.panelDropSurface == "map")
    PuzzlePlace.RowDragEnded()
    if target == nil then
        return
    end
    PuzzlePlace.PlaceAt(id, target)
end

--------------------------------------------------------------------------------
-- Place on map: a banner, then a click
--------------------------------------------------------------------------------

---@type Panel|nil
local g_banner = nil

--True when the mouse is over the live map (in the tabletop view, inside its
--window; otherwise the map is the whole screen).
---@return boolean
local function MouseOverLiveMap()
    if not Tabletop.IsActive() then
        return true
    end
    local map = game.currentMap
    local rect = map ~= nil and Tabletop.MapWindowRect(map.id) or nil
    local layer = GameHud.instance ~= nil and GameHud.instance.documentsPanel or nil
    if rect == nil or layer == nil or not layer.valid then
        return false
    end
    local mouse = dmhub.mouseScreenPosition
    local x, y = ScreenToLayer(layer, mouse.x, mouse.y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

--Close the Place on map banner, if up.
function PuzzlePlace.CancelPlacing()
    if g_banner ~= nil and g_banner.valid then
        g_banner:DestroySelf()
    end
    g_banner = nil
end

--Place on map: a banner at the top, then a click on an object, by a door, or
--on empty floor. The click goes to a see-through layer over everything, so it
--never selects what is under it. Esc or Cancel stops.
---@param id string
function PuzzlePlace.StartPlacing(id)
    PuzzlePlace.CancelPlacing()
    local layer = BannerLayer()
    if layer == nil then
        return
    end
    local ghost = nil

    local catcher = gui.Panel{
        width = "100%",
        height = "100%",
        bgimage = true,
        bgcolor = "clear",
        thinkTime = 0.05,
        think = function(element)
            local target = TargetUnderMouse(MouseOverLiveMap())
            ShowOutline(target)
            if ghost == nil or not ghost.valid then
                ghost = CreateGhost()
            end
            if ghost ~= nil then
                ghost:FireEvent("setText", PuzzlePlace.TargetText(id, target))
            end
        end,
        press = function(element)
            local target = TargetUnderMouse(MouseOverLiveMap())
            if target == nil then
                return
            end
            PuzzlePlace.CancelPlacing()
            PuzzlePlace.PlaceAt(id, target)
        end,
    }

    local banner
    banner = gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = "100%",
        height = "100%",
        flow = "none",
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            PuzzlePlace.CancelPlacing()
        end,
        destroy = function(element)
            ClearOutline()
            if ghost ~= nil and ghost.valid then
                ghost:DestroySelf()
            end
            if g_banner == element then
                g_banner = nil
            end
        end,
        catcher,
        gui.Panel{
            classes = {"framedPanel"},
            width = 640,
            height = "auto",
            minHeight = 54,
            halign = "center",
            valign = "top",
            vmargin = 80,
            flow = "horizontal",
            hpad = 14,
            vpad = 12,
            borderBox = true,
            bgimage = true,
            gui.Label{
                classes = {"sizeS"},
                width = "100%-110",
                height = "auto",
                valign = "center",
                text = string.format("Click an object to lock it with %s, a door to place a lock that opens it, or empty floor to place a lock there.", Puzzle.Title(id)),
            },
            gui.Button{
                classes = {"sizeS"},
                width = 90,
                halign = "right",
                valign = "center",
                text = "Cancel",
                swallowPress = true,
                click = function(element)
                    PuzzlePlace.CancelPlacing()
                end,
            },
        },
    }
    layer:AddChild(banner)
    g_banner = banner
    gui.SetFocus(banner)
end

--------------------------------------------------------------------------------
-- Lock the selected object
--------------------------------------------------------------------------------

--The objects selected on the current floor.
---@return any[]
local function SelectedObjects()
    local result = {}
    local floor = game.currentFloor
    if floor == nil then
        return result
    end
    for _, obj in pairs(floor.objects or {}) do
        local selected = false
        pcall(function() selected = obj.editorSelection == true end)
        if selected then
            result[#result + 1] = obj
        end
    end
    return result
end

--Lock the one selected object with the puzzle.
---@param id string
function PuzzlePlace.LockSelected(id)
    local selected = SelectedObjects()
    if #selected == 0 then
        SetStatus("Select an object on the map first.", nil)
        return
    elseif #selected > 1 then
        SetStatus("Select just one object on the map.", nil)
        return
    end
    local obj = selected[1]
    PuzzlePlace.PlaceAt(id, { kind = "object", floorid = obj.floorid, x = obj.x, y = obj.y, obj = obj })
end
