local mod = dmhub.GetModLoading()

-- The "Puzzle Lock" type for the Interactable map-object component: the
-- Director adds it to any object (a terminal, a keypad, a bomb) and points it at
-- what solving or failing the puzzle does. Players near the object click
-- Interact to open the puzzle. The host applies the effects (PuzzleFramework's
-- outcome handlers), each claimed first so nothing runs twice.
--
-- A lock stores only its puzzle id on the object, so a copied object shares the
-- puzzle. Each lock's targets live in the puzzle's config under locks[lockKey].

---@class PuzzleEffectDef
---@field id string
---@field name string shown in the Add menu
---@field Apply fun(effect: table)
---@field Undo? fun(effect: table)
---@field Describe? fun(effect: table): string

PuzzleEffect = {}

---@type table<string, PuzzleEffectDef>
local g_customEffects = {}

--Register an effect a lock can run on solve or fail (an alarm, lights, guards).
--Apply runs on the host and must be safe to run twice. effect is the stored
--table; put parameters on it from your own setup code.
---@param def PuzzleEffectDef
function PuzzleEffect.Register(def)
    g_customEffects[def.id] = def
end

---@class PuzzleLockInteractive: Interactive
--- @field new fun(o?: table): PuzzleLockInteractive
--- @field puzzleid string
PuzzleLockInteractive = RegisterGameType("PuzzleLockInteractive", "Interactive")
PuzzleLockInteractive.id = "PuzzleLock"
PuzzleLockInteractive.text = "Puzzle Lock"
PuzzleLockInteractive.puzzleid = ""

Interactive.Register(PuzzleLockInteractive)

function PuzzleLockInteractive.Create()
    return PuzzleLockInteractive.new{}
end

--The engine only offers Interact within the component's own range, measured from
--one token. The lock does its own range check over all of a player's tokens.
local ENGINE_DISTANCE = 100000
local DEFAULT_RANGE = 2
--A door effect finds its door again by position: door ids change on every toggle.
local DOOR_MATCH_TILES = 1.5
local POINT_OUT_SECONDS = 4
local POINT_OUT_EVENT = "puzzleLockTargets"

---@param floorid string
---@param objid string
---@return string
local function LockKey(floorid, objid)
    return Puzzle.SafeId(tostring(floorid) .. "_" .. tostring(objid))
end

--------------------------------------------------------------------------------
-- Targets: doors and objects on the lock's floor
--------------------------------------------------------------------------------

---@param pts number[]
---@return number x, number y
local function PathMidpoint(pts)
    local sx, sy, n = 0, 0, 0
    for i = 1, #pts - 1, 2 do
        sx, sy, n = sx + pts[i], sy + pts[i + 1], n + 1
    end
    if n == 0 then
        return 0, 0
    end
    return sx / n, sy / n
end

---@param dx number
---@param dy number
---@return string
local function DirectionText(dx, dy)
    if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then
        return "here"
    end
    local names = { "east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast" }
    local angle = math.deg(math.atan(dy, dx)) % 360
    return names[(math.floor((angle + 22.5) / 45) % 8) + 1]
end

---@param fromX number
---@param fromY number
---@param x number
---@param y number
---@return string
local function WhereText(fromX, fromY, x, y)
    local dx, dy = x - fromX, y - fromY
    local squares = math.floor(math.max(math.abs(dx), math.abs(dy)) + 0.5)
    local dir = DirectionText(dx, dy)
    if dir == "here" then
        return "right here"
    end
    return string.format("%d %s %s", squares, cond(squares == 1, "square", "squares"), dir)
end

---@class PuzzleLockTarget
---@field kind "door"|"doorobj"|"object"
---@field x number
---@field y number
---@field objid string|nil
---@field label string
---@field distance number

--Doors (drawn doors and door objects) and other objects on a floor, nearest first.
---@param floorid string
---@param fromX number
---@param fromY number
---@param exceptObjid string|nil
---@return PuzzleLockTarget[] doors, PuzzleLockTarget[] objects
local function ListTargets(floorid, fromX, fromY, exceptObjid)
    local doors, objects = {}, {}
    local floor = game.GetFloor(floorid)
    if floor == nil then
        return doors, objects
    end
    local ok, ops = pcall(function() return floor:GetDoorOperations() end)
    if ok and ops ~= nil then
        for _, door in ipairs(ops) do
            local path = door.paths ~= nil and door.paths[1] or nil
            if path ~= nil then
                local x, y = PathMidpoint(path)
                doors[#doors + 1] = {
                    kind = "door", x = x, y = y,
                    label = "Door " .. WhereText(fromX, fromY, x, y),
                    distance = math.max(math.abs(x - fromX), math.abs(y - fromY)),
                }
            end
        end
    end
    for objid, obj in pairs(floor.objects or {}) do
        if objid ~= exceptObjid then
            local isDoor = false
            pcall(function() isDoor = obj:GetComponent("Door") ~= nil end)
            local name = obj.description
            if type(name) ~= "string" or name == "" then
                name = "Object"
            end
            local target = {
                kind = cond(isDoor, "doorobj", "object"), x = obj.x, y = obj.y, objid = objid,
                label = string.format("%s %s", name, WhereText(fromX, fromY, obj.x, obj.y)),
                distance = math.max(math.abs(obj.x - fromX), math.abs(obj.y - fromY)),
            }
            if isDoor then
                doors[#doors + 1] = target
            else
                objects[#objects + 1] = target
            end
        end
    end
    table.sort(doors, function(a, b) return a.distance < b.distance end)
    table.sort(objects, function(a, b) return a.distance < b.distance end)
    return doors, objects
end

--The drawn door nearest a stored position, or nil.
---@param floor any
---@param x number
---@param y number
---@return table|nil
local function FindDoor(floor, x, y)
    local best, bestDist = nil, DOOR_MATCH_TILES
    for _, door in ipairs(floor:GetDoorOperations()) do
        local path = door.paths ~= nil and door.paths[1] or nil
        if path ~= nil then
            local dx, dy = PathMidpoint(path)
            local d = math.max(math.abs(dx - x), math.abs(dy - y))
            if d <= bestDist then
                best, bestDist = door, d
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- Effects
--------------------------------------------------------------------------------

local EFFECT_KINDS = {
    { id = "unlock", text = "Unlock a door" },
    { id = "open", text = "Unlock and open a door" },
    { id = "reveal", text = "Reveal an object" },
    { id = "hide", text = "Hide an object" },
    { id = "chat", text = "Post a chat message" },
}

---@param effect table
---@return string
local function DescribeEffect(effect)
    local custom = g_customEffects[effect.kind]
    if custom ~= nil then
        if custom.Describe ~= nil then
            return custom.Describe(effect)
        end
        return custom.name
    end
    if effect.kind == "door" or effect.kind == "doorobj" then
        return string.format("%s: %s", cond(effect.open, "Unlock and open", "Unlock"), effect.label or "door")
    elseif effect.kind == "reveal" then
        return string.format("Reveal: %s", effect.label or "object")
    elseif effect.kind == "hide" then
        return string.format("Hide: %s", effect.label or "object")
    elseif effect.kind == "chat" then
        return string.format("Chat: \"%s\"", tostring(effect.text or ""))
    end
    return tostring(effect.kind)
end

--Apply an effect, or reverse it when undo is true. Runs on the host (apply) or
--the client pressing Reset (undo).
---@param effect table
---@param undo boolean
local function RunEffectUnsafe(effect, undo)
    local custom = g_customEffects[effect.kind]
    if custom ~= nil then
        if not undo then
            custom.Apply(effect)
        elseif custom.Undo ~= nil then
            custom.Undo(effect)
        end
        return
    end
    if effect.kind == "chat" then
        if not undo and type(effect.text) == "string" and effect.text ~= "" then
            chat.Send(effect.text)
        end
        return
    end
    local floor = game.GetFloor(effect.floorid)
    if floor == nil then
        return
    end
    if effect.kind == "door" then
        local door = FindDoor(floor, effect.x, effect.y)
        if door ~= nil then
            local open = nil
            if undo then
                open = false
            elseif effect.open then
                open = true
            end
            floor:SetDoorState{ opid = door.opid, layer = door.layer, locked = undo, open = open }
        end
    elseif effect.kind == "doorobj" then
        local obj = floor:GetObject(effect.objid)
        local comp = obj ~= nil and obj:GetComponent("Door") or nil
        if comp ~= nil then
            local props = { locked = undo }
            if undo then
                props.opened = false
            elseif effect.open then
                props.opened = true
            end
            comp:SetAndUploadProperties(props)
        end
    elseif effect.kind == "reveal" or effect.kind == "hide" then
        local obj = floor:GetObject(effect.objid)
        if obj ~= nil then
            local hidden = effect.kind == "hide"
            if undo then
                hidden = not hidden
            end
            obj.inactive = hidden
        end
    end
end

--One broken target (a deleted object, a removed door) must not stop the rest.
---@param effect table
---@param undo boolean
local function RunEffect(effect, undo)
    local ok, err = pcall(RunEffectUnsafe, effect, undo)
    if not ok then
        print("PUZZLE:: effect failed:", tostring(effect.kind), err)
    end
end

--------------------------------------------------------------------------------
-- Pointing out targets
--------------------------------------------------------------------------------

--Outline doors and objects on this client for a few seconds, when they are on
--the map it is viewing.
---@param targets {floorid: string, x: number, y: number, objid: string|nil, kind: string}[]
local function PointOut(targets)
    local lines = {}
    for _, t in ipairs(targets) do
        local floor = game.GetFloor(t.floorid)
        --floorIndex is -1 for a floor that is not on the map this client is viewing.
        local floorIndex = floor ~= nil and floor.floorIndex or -1
        if floorIndex >= 0 then
            local x1, y1, x2, y2 = t.x - 0.7, t.y - 0.7, t.x + 0.7, t.y + 0.7
            if t.objid ~= nil then
                local obj = game.LookupObject(t.floorid, t.objid)
                local area = obj ~= nil and obj.area or nil
                --a tiny object still gets a door-sized outline, or it reads as a dot.
                if type(area) == "table" and area.x1 ~= nil then
                    x1, y1 = math.min(area.x1, x1), math.min(area.y1, y1)
                    x2, y2 = math.max(area.x2, x2), math.max(area.y2, y2)
                end
            end
            local corners = { {x1, y1}, {x2, y1}, {x2, y2}, {x1, y2} }
            for i = 1, 4 do
                local a, b = corners[i], corners[i % 4 + 1]
                lines[#lines + 1] = dmhub.HighlightLine{
                    color = "#ffcc00",
                    a = core.Vector2(a[1], a[2]),
                    b = core.Vector2(b[1], b[2]),
                    floorIndex = floorIndex,
                    terrainParallax = true,
                }
            end
        end
    end
    dmhub.Schedule(POINT_OUT_SECONDS, function()
        for _, line in ipairs(lines) do
            pcall(function() line:Destroy() end)
        end
    end)
end

dmhub.RegisterRemoteEvent(POINT_OUT_EVENT, function(args)
    if mod.unloaded or type(args) ~= "table" or type(args.targets) ~= "table" then
        return
    end
    PointOut(args.targets)
end)

---@param effect table
---@return table|nil
local function EffectTarget(effect)
    if effect.kind == "door" or effect.kind == "doorobj" or effect.kind == "reveal" or effect.kind == "hide" then
        return { floorid = effect.floorid, x = effect.x, y = effect.y, objid = effect.objid, kind = effect.kind }
    end
    return nil
end

--------------------------------------------------------------------------------
-- Outcome handler: the host applies every lock's effects
--------------------------------------------------------------------------------

---@param id string
---@return table<string, table>
local function Locks(id)
    local config = Puzzle.ReadConfig(id)
    if type(config.locks) == "table" then
        return config.locks
    end
    return {}
end

Puzzle.RegisterOutcomeHandler("locks", {
    apply = function(id, outcome, status)
        local pointOut = {}
        for lockKey, lock in pairs(Locks(id)) do
            local list = cond(outcome == "solve", lock.onSolve, lock.onFail) or {}
            for i, effect in ipairs(list) do
                if Puzzle.ClaimEffect(id, string.format("%s:%s:%d", outcome, lockKey, i)) then
                    RunEffect(effect, false)
                    pointOut[#pointOut + 1] = EffectTarget(effect)
                end
            end
            if outcome == "solve" and lock.hideWhenSolved and Puzzle.ClaimEffect(id, "hideself:" .. lockKey) then
                RunEffect({ kind = "hide", floorid = lock.floorid, objid = lock.objid }, false)
            end
        end
        if #pointOut > 0 then
            PointOut(pointOut)
            dmhub.BroadcastRemoteEvent(POINT_OUT_EVENT, id, { targets = pointOut }, true, true)
        end
    end,
    undo = function(id, status)
        local applied = status.applied
        if type(applied) ~= "table" then
            return
        end
        local locks = Locks(id)
        for key in pairs(applied) do
            local outcome, lockKey, index = string.match(key, "^(%a+):(.+):(%d+)$")
            local hideKey = string.match(key, "^hideself:(.+)$")
            if outcome ~= nil then
                local lock = locks[lockKey]
                local list = lock ~= nil and cond(outcome == "solve", lock.onSolve, lock.onFail) or nil
                local effect = list ~= nil and list[math.tointeger(tonumber(index))] or nil
                if effect ~= nil then
                    RunEffect(effect, true)
                end
            elseif hideKey ~= nil and locks[hideKey] ~= nil then
                local lock = locks[hideKey]
                RunEffect({ kind = "hide", floorid = lock.floorid, objid = lock.objid }, true)
            end
        end
    end,
})

--------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------

--A short message at the bottom of the screen that goes away by itself.
---@param text string
local function Toast(text)
    local toast
    toast = gui.Label{
        classes = {"framedPanel", "sizeM"},
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "bottom",
        vmargin = 160,
        pad = 10,
        borderBox = true,
        text = text,
        data = { born = dmhub.Time() },
        thinkTime = 0.5,
        think = function(element)
            if dmhub.Time() - element.data.born > 3 then
                element:DestroySelf()
            end
        end,
    }
    gui.ShowDialog(mod, toast)
end

--------------------------------------------------------------------------------
-- Director setup window
--------------------------------------------------------------------------------

---@type table<string, Panel>
local g_setupWindows = {}

---@param id string
---@param floorid string
---@param objid string
local function OpenSetup(id, floorid, objid)
    local lockKey = LockKey(floorid, objid)
    local existing = g_setupWindows[lockKey]
    if existing ~= nil and existing.valid then
        return
    end
    local lockObj = game.LookupObject(floorid, objid)
    local fromX, fromY = 0, 0
    if lockObj ~= nil then
        fromX, fromY = lockObj.x, lockObj.y
    end

    local window
    local body

    ---@return table
    local function ReadLock()
        local lock = Locks(id)[lockKey]
        if type(lock) ~= "table" then
            lock = { floorid = floorid, objid = objid, range = DEFAULT_RANGE, onSolve = {}, onFail = {} }
        end
        lock.onSolve = lock.onSolve or {}
        lock.onFail = lock.onFail or {}
        return lock
    end

    ---@param lock table
    local function WriteLock(lock)
        local locks = Locks(id)
        locks[lockKey] = lock
        Puzzle.SetConfig(id, { locks = locks })
    end

    local Rebuild

    ---@param listName "onSolve"|"onFail"
    ---@return Panel[]
    local function EffectSection(listName)
        local lock = ReadLock()
        local rows = {}
        for i, effect in ipairs(lock[listName]) do
            local index = i
            local target = EffectTarget(effect)
            rows[#rows + 1] = gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                vmargin = 1,
                gui.Label{
                    classes = {"sizeS"},
                    width = 300,
                    height = "auto",
                    valign = "center",
                    text = DescribeEffect(effect),
                },
                target ~= nil and gui.Button{
                    classes = {"sizeXs"},
                    text = "Show",
                    width = 56,
                    height = 22,
                    hmargin = 2,
                    click = function(element)
                        PointOut({ target })
                    end,
                } or nil,
                gui.Button{
                    classes = {"sizeXs"},
                    text = "Remove",
                    width = 64,
                    height = 22,
                    hmargin = 2,
                    click = function(element)
                        local current = ReadLock()
                        table.remove(current[listName], index)
                        WriteLock(current)
                        Rebuild()
                    end,
                },
            }
        end
        if #rows == 0 then
            rows[1] = gui.Label{
                classes = {"sizeS", "fgMuted"},
                width = "auto",
                height = "auto",
                text = "Nothing yet.",
            }
        end

        --Adding: pick what kind of effect, then (for doors and objects) which one.
        local targetRow
        local kindOptions = {}
        for _, k in ipairs(EFFECT_KINDS) do
            kindOptions[#kindOptions + 1] = k
        end
        for _, def in pairs(g_customEffects) do
            kindOptions[#kindOptions + 1] = { id = "custom:" .. def.id, text = def.name }
        end
        targetRow = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
        }
        local function AddEffect(effect)
            local current = ReadLock()
            table.insert(current[listName], effect)
            WriteLock(current)
            Rebuild()
        end
        rows[#rows + 1] = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            vmargin = 2,
            gui.Dropdown{
                width = 220,
                options = kindOptions,
                textDefault = "Add...",
                change = function(dropdown)
                    ---@cast dropdown Dropdown
                    local kind = tostring(dropdown.idChosen)
                    if string.sub(kind, 1, 7) == "custom:" then
                        AddEffect({ kind = string.sub(kind, 8) })
                        return
                    end
                    if kind == "chat" then
                        targetRow.children = {
                            gui.Input{
                                width = 260,
                                height = 26,
                                bgimage = "panels/square.png",
                                bgcolor = "#00000059",
                                border = 1,
                                borderColor = "#ffffff47",
                                hpad = 6,
                                borderBox = true,
                                placeholderText = "Message...",
                                change = function(input)
                                    if input.text ~= "" then
                                        AddEffect({ kind = "chat", text = input.text })
                                    end
                                end,
                            },
                        }
                        return
                    end
                    local doors, objects = ListTargets(floorid, fromX, fromY, objid)
                    local list = cond(kind == "unlock" or kind == "open", doors, objects)
                    local options = {}
                    for i, t in ipairs(list) do
                        options[#options + 1] = { id = tostring(i), text = t.label }
                    end
                    if #options == 0 then
                        targetRow.children = {
                            gui.Label{
                                classes = {"sizeS", "warning"},
                                width = "auto",
                                height = "auto",
                                valign = "center",
                                text = cond(kind == "unlock" or kind == "open", "No doors on this floor.", "No other objects on this floor."),
                            },
                        }
                        return
                    end
                    targetRow.children = {
                        gui.Dropdown{
                            width = 260,
                            options = options,
                            textDefault = "Choose...",
                            change = function(d)
                                ---@cast d Dropdown
                                local t = list[math.tointeger(tonumber(d.idChosen)) or 0]
                                if t == nil then
                                    return
                                end
                                local effect = { floorid = floorid, x = t.x, y = t.y, objid = t.objid, label = t.label }
                                if kind == "unlock" or kind == "open" then
                                    effect.kind = cond(t.kind == "doorobj", "doorobj", "door")
                                    effect.open = kind == "open"
                                else
                                    effect.kind = kind
                                end
                                AddEffect(effect)
                            end,
                        },
                    }
                end,
            },
            targetRow,
        }
        return rows
    end

    Rebuild = function()
        if window == nil or not window.valid then
            return
        end
        local lock = ReadLock()
        local children = {}

        children[#children + 1] = gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", text = "Name:" }
        children[#children + 1] = gui.Input{
            width = 280,
            height = 26,
            bgimage = "panels/square.png",
            bgcolor = "#00000059",
            border = 1,
            borderColor = "#ffffff47",
            hpad = 6,
            borderBox = true,
            text = cond(Puzzle.Exists(id), Puzzle.Title(id), ""),
            placeholderText = "The terminal",
            change = function(input)
                if input.text ~= "" and Puzzle.Exists(id) then
                    Puzzle.SetTitle(id, input.text)
                end
            end,
        }

        children[#children + 1] = Puzzle.SetupPanel(id, function(typeid)
            --keep the locks (targets) when the Director changes the puzzle's type.
            Puzzle.Create(id, typeid, { locks = Locks(id) }, Puzzle.Exists(id) and Puzzle.Title(id) or nil)
            Rebuild()
        end)

        children[#children + 1] = gui.Label{ classes = {"sizeM", "bold"}, width = "auto", height = "auto", tmargin = 10, text = "When solved:" }
        for _, row in ipairs(EffectSection("onSolve")) do
            children[#children + 1] = row
        end
        children[#children + 1] = gui.Label{ classes = {"sizeM", "bold"}, width = "auto", height = "auto", tmargin = 10, text = "When failed:" }
        for _, row in ipairs(EffectSection("onFail")) do
            children[#children + 1] = row
        end

        children[#children + 1] = gui.Label{ classes = {"sizeS"}, width = "auto", height = "auto", tmargin = 10, text = "Players can use it from (squares):" }
        children[#children + 1] = gui.Slider{
            width = 200,
            labelWidth = 48,
            height = 20,
            minValue = 1,
            maxValue = 10,
            handleSize = "100%",
            value = tonumber(lock.range) or DEFAULT_RANGE,
            change = function(slider)
                local current = ReadLock()
                current.range = round(slider.value)
                WriteLock(current)
            end,
        }
        children[#children + 1] = gui.Check{
            classes = {"sizeS"},
            width = "auto",
            height = 24,
            text = "Hide this object when solved",
            value = lock.hideWhenSolved == true,
            change = function(element)
                local current = ReadLock()
                current.hideWhenSolved = element.value
                WriteLock(current)
            end,
        }
        children[#children + 1] = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            tmargin = 8,
            gui.Button{
                classes = {"sizeS"},
                text = "Open puzzle",
                width = 130,
                hmargin = 2,
                click = function(element)
                    if Puzzle.Exists(id) then
                        Puzzle.OpenWindow(id)
                    end
                end,
            },
            gui.Button{
                classes = {"sizeS"},
                text = "Show everyone",
                width = 130,
                hmargin = 2,
                click = function(element)
                    if Puzzle.Exists(id) then
                        Puzzle.PushToEveryone(id)
                    end
                end,
            },
        }
        body.children = children
    end

    body = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
    }

    window = gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        width = 480,
        height = "auto",
        halign = "left",
        valign = "center",
        hmargin = 80,
        flow = "vertical",
        pad = 12,
        borderBox = true,
        draggable = true,
        dragMove = true,
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,
        destroy = function(element)
            g_setupWindows[lockKey] = nil
        end,
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            gui.Label{
                classes = {"sizeL", "bold"},
                width = "auto",
                height = "auto",
                text = "Puzzle lock",
            },
            gui.Button{
                classes = {"closeButton"},
                halign = "right",
                valign = "top",
                click = function(element)
                    window:DestroySelf()
                end,
            },
        },
        body,
    }
    gui.ShowDialog(mod, window)
    g_setupWindows[lockKey] = window
    Rebuild()
end

--------------------------------------------------------------------------------
-- Interact
--------------------------------------------------------------------------------

--The title-bar buttons a Director sees on a lock's puzzle window.
---@param floorid string|nil
---@param objid string|nil
---@return fun(id: string): Panel|nil
local function DirectorHeader(floorid, objid)
    return function(id)
        if not IsDMOrPlayerHost() then
            return nil
        end
        return gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "center",
            hmargin = 8,
            (floorid ~= nil and objid ~= nil) and gui.Button{
                classes = {"sizeXs"},
                text = "Lock setup",
                width = 84,
                height = 22,
                hmargin = 2,
                click = function(element)
                    OpenSetup(id, floorid --[[@as string]], objid --[[@as string]])
                end,
            } or nil,
            gui.Button{
                classes = {"sizeXs"},
                text = "Show everyone",
                width = 100,
                height = 22,
                hmargin = 2,
                click = function(element)
                    Puzzle.PushToEveryone(id)
                end,
            },
        }
    end
end

Puzzle.OpenForJoin = function(id)
    Puzzle.OpenWindow(id, { header = DirectorHeader(nil, nil) })
end

--True when one of this player's tokens on the lock's floor is within range.
---@param obj any
---@param range number
---@return boolean
local function InRange(obj, range)
    for _, tok in ipairs(dmhub.GetTokens{ playerControlled = true } or {}) do
        local mine = false
        pcall(function() mine = tok.canControlAsUser == true end)
        if mine and tok.floorIndex == obj.floorIndex then
            local loc = tok.loc
            local reach = range + (tonumber(tok.radiusInTiles) or 0.5)
            if math.abs(loc.x - obj.x) <= reach and math.abs(loc.y - obj.y) <= reach then
                return true
            end
        end
    end
    return false
end

--The Director's Edit command on the object: straight to the lock setup.
function PuzzleLockInteractive:Edit(controller)
    if self.puzzleid == "" then
        controller:BeginChanges()
        self.puzzleid = "lock_" .. Puzzle.SafeId(dmhub.GenerateGuid())
        controller:CompleteChanges("Set up puzzle lock")
        pcall(function() controller:SetAndUploadProperties{ distance = ENGINE_DISTANCE } end)
    end
    OpenSetup(self.puzzleid, controller.floorid, controller.objid)
    return nil
end

function PuzzleLockInteractive:Interact(controller, token)
    local floorid, objid = controller.floorid, controller.objid
    local director = IsDMOrPlayerHost()

    if director then
        --first use: give the lock its own puzzle and lift the engine's range limit.
        if self.puzzleid == "" then
            controller:BeginChanges()
            self.puzzleid = "lock_" .. Puzzle.SafeId(dmhub.GenerateGuid())
            controller:CompleteChanges("Set up puzzle lock")
            pcall(function() controller:SetAndUploadProperties{ distance = ENGINE_DISTANCE } end)
        end
        local id = self.puzzleid
        if not Puzzle.Exists(id) then
            OpenSetup(id, floorid, objid)
            return nil
        end
        Puzzle.OpenWindow(id, { header = DirectorHeader(floorid, objid) })
        return nil
    end

    local id = self.puzzleid
    if id == "" or not Puzzle.Exists(id) then
        Toast("Nothing happens.")
        return nil
    end
    local lock = Locks(id)[LockKey(floorid, objid)]
    local range = (type(lock) == "table" and tonumber(lock.range)) or DEFAULT_RANGE
    local obj = game.LookupObject(floorid, objid)
    if obj ~= nil and not InRange(obj, range) then
        Toast("Too far away. Move closer.")
        return nil
    end
    Puzzle.OpenWindow(id, { header = DirectorHeader(nil, nil) })
    return nil
end
