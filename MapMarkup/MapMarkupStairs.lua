local mod = dmhub.GetModLoading()

--Map Markup panel: Stairs, the built-in last chip of the Props tab.
--
--A staircase is NOT an object: it is a markupZones record on the floor the stairs
--start on, {category="stairs", width, points={x1,y1,x2,y2,...}, cutHole, ord}, where
--points is the stairs' centerline drawn from the bottom to the top. The engine
--(MarkupStairs.cs) reads these records directly and derives all the gameplay: the
--ramp, the top edge that moves creatures between floors, and the hole in the floor
--above. This file only draws, edits and lists them. See MARKUP_STAIRS_PLAN.md.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

K.STAIRS_CATEGORY = "stairs"
K.STAIRS_MIN_WIDTH = 1
K.STAIRS_MAX_WIDTH = 8
K.STAIRS_COLOR = "#ffc86b"
K.STAIRS_SELECTED_COLOR = "#ffffff"
K.STAIRS_TOP_COLOR = "#7dff9a"
K.STAIRS_CHEVRON_SPACING = 1.0
K.STAIRS_CHEVRON_SIZE = 0.3

--active: the Stairs chip is the selected Props chip (only while no prop type is
--selected -- picking a prop type, here or by clicking a prop on the map, wins).
--width/cutHole: the settings for the next staircase drawn, or for the selected one.
m.stairs = {
    active = false,
    width = 2,
    cutHole = true,
    selectedId = nil,
    message = nil,
}

local function StairsActive()
    return m.stairs.active == true and m.props.selected == nil
end

--============================================================================
--Floors: stairs live on a floor record (never a layer), and rise to the next
--floor up.
--============================================================================

--The floor record a floor or layer belongs to.
local function ParentFloor(floor)
    --a floor still loading (just after a map change) is not valid yet, and reading
    --its fields raises.
    if floor == nil or not floor.valid then
        return nil
    end
    local parentId = floor.parentFloor
    if parentId ~= nil and parentId ~= "" then
        return game.GetFloor(parentId)
    end
    return floor
end

--The floor record above the given floor record, or nil on the top floor. Floor
--lists run bottom to top with each floor's layers directly below it, so the next
--floor up is the next entry after this one that is not a layer.
local function FloorAbove(floor)
    local map = game.currentMap
    if floor == nil or map == nil then
        return nil
    end
    local floors = map.floors
    local index = nil
    for i,f in ipairs(floors) do
        if f.floorid == floor.floorid then
            index = i
            break
        end
    end
    if index == nil then
        return nil
    end
    for i = index + 1, #floors do
        local f = floors[i]
        if f.parentFloor == nil or f.parentFloor == "" then
            return f
        end
    end
    return nil
end

--Defined under Records below; declared here so StairsArrivingOn binds to it.
local StairsOnFloor

--The staircases that arrive on the given floor record: each floor's stairs lead to
--their upFloor when it names a floor of this map, else to the floor above.
local function StairsArrivingOn(floor)
    local result = {}
    local map = game.currentMap
    if floor == nil or map == nil then
        return result
    end
    local ids = {}
    for _,f in ipairs(map.floors) do
        ids[f.floorid] = true
    end
    for _,f in ipairs(map.floors) do
        if f.floorid == floor.floorid then
            break
        end
        if f.parentFloor == nil or f.parentFloor == "" then
            local above = FloorAbove(f)
            for _,s in ipairs(StairsOnFloor(f)) do
                local target = nil
                if s.upFloor ~= nil and ids[s.upFloor] then
                    target = s.upFloor
                elseif above ~= nil then
                    target = above.floorid
                end
                if target == floor.floorid then
                    result[#result+1] = s
                end
            end
        end
    end
    return result
end

local function CurrentStairsFloor()
    return ParentFloor(game.currentFloor)
end

--============================================================================
--Records
--============================================================================

--The staircases stored on a floor record, oldest first:
--{id, width, points, cutHole, ord, upFloor, holeLength}. upFloor (optional, set by the
--Foundry importer) is the floor id the stairs lead to when it is not the next floor up.
--holeLength (optional, set by the importer on tight spirals) is how far back from the
--top, along the centerline, the hole reaches; the engine's default is the width.
function StairsOnFloor(floor)
    local result = {}
    if floor == nil then
        return result
    end
    local zones = nil
    pcall(function()
        zones = floor.markupZones
    end)
    if zones == nil then
        return result
    end
    for id,record in pairs(zones) do
        if type(record) == "table" and record.category == K.STAIRS_CATEGORY and type(record.points) == "table" then
            result[#result+1] = {
                id = id,
                width = tonumber(record.width) or 2,
                points = record.points,
                cutHole = record.cutHole ~= false,
                ord = tonumber(record.ord) or 0,
                upFloor = record.upFloor,
                holeLength = tonumber(record.holeLength),
            }
        end
    end
    table.sort(result, function(a, b)
        if a.ord ~= b.ord then
            return a.ord < b.ord
        end
        return a.id < b.id
    end)
    return result
end

local function FindStairs(id)
    if id == nil then
        return nil
    end
    for _,s in ipairs(StairsOnFloor(CurrentStairsFloor())) do
        if s.id == id then
            return s
        end
    end
    return nil
end

--Writes a staircase record. SetMarkupZone stores the table it is given, so always
--hand it a fresh one.
local function WriteStairs(floor, id, width, points, cutHole, ord, upFloor, holeLength)
    local pts = {}
    for i,v in ipairs(points) do
        pts[i] = v
    end
    floor:SetMarkupZone(id, {
        category = K.STAIRS_CATEGORY,
        width = width,
        points = pts,
        cutHole = cutHole,
        ord = ord,
        upFloor = upFloor,
        holeLength = holeLength,
    })
end

--Tile centres sit on whole-number coordinates and grid lines halfway between. An
--even-width staircase covers whole tiles when its centerline runs along grid lines;
--an odd-width one when it runs through tile centres. The line tool snaps to match.
local function WidthIsOdd(width)
    return (math.floor(width + 0.5) % 2) == 1
end

--An odd-width centerline is snapped to tile centres, so its first and last points
--are the centres of the first and last stair squares. The stairs start and end at
--those squares' far edges: push each end out half a square along the line, so the
--top edge (where creatures change floor) runs between tiles rather than through the
--middle of the top row. Ends that are not on a tile centre are left alone.
local function ExtendEndsToTileEdges(points)
    local n = #points
    if n < 4 then
        return points
    end
    local function onCentre(x, y)
        return math.abs(x - math.floor(x + 0.5)) < 0.001 and math.abs(y - math.floor(y + 0.5)) < 0.001
    end
    local result = {}
    for i,v in ipairs(points) do
        result[i] = v
    end
    local function push(ix, iy, fromx, fromy)
        local dx, dy = result[ix] - fromx, result[iy] - fromy
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0.0001 and onCentre(result[ix], result[iy]) then
            result[ix] = result[ix] + dx/len*0.5
            result[iy] = result[iy] + dy/len*0.5
        end
    end
    push(1, 2, points[3], points[4])
    push(n-1, n, points[n-3], points[n-2])
    return result
end

--True when the centerline turns back on itself somewhere (a turn sharper than
--about 150 degrees), which would make the flight overlap itself.
local function DoublesBack(points)
    for i = 5, #points - 1, 2 do
        local ax, ay = points[i-2] - points[i-4], points[i-1] - points[i-3]
        local bx, by = points[i] - points[i-2], points[i+1] - points[i-1]
        local la = math.sqrt(ax*ax + ay*ay)
        local lb = math.sqrt(bx*bx + by*by)
        if la > 0.0001 and lb > 0.0001 and (ax*bx + ay*by) / (la*lb) < -0.87 then
            return true
        end
    end
    return false
end

local function CenterlineLength(points)
    local length = 0
    for i = 3, #points - 1, 2 do
        local dx = points[i] - points[i-2]
        local dy = points[i+1] - points[i-1]
        length = length + math.sqrt(dx*dx + dy*dy)
    end
    return length
end

--Drops repeated points (a double click on the last point finishes the stroke and
--can leave a duplicate).
local function CleanPoints(points)
    local result = {}
    for i = 1, #points - 1, 2 do
        local x, y = points[i], points[i+1]
        local n = #result
        if n < 2 or math.abs(result[n-1] - x) > 0.001 or math.abs(result[n] - y) > 0.001 then
            result[n+1] = x
            result[n+2] = y
        end
    end
    return result
end

--A finished centerline stroke from the map tool: store it as a new staircase.
local function CreateStairsFromStroke(points)
    local floor = CurrentStairsFloor()
    if floor == nil then
        return
    end
    if FloorAbove(floor) == nil then
        m.stairs.message = "There is no floor above this one, so stairs here would lead nowhere."
        return
    end

    points = CleanPoints(points)
    if #points < 4 or CenterlineLength(points) < 1 then
        m.stairs.message = "That line is too short for a staircase. Draw from the bottom of the stairs to the top."
        return
    end
    if DoublesBack(points) then
        m.stairs.message = "That line turns back on itself, so the stairs would overlap. Draw a flight that only goes one way; for stairs that climb past a floor, draw one staircase per floor."
        return
    end
    if WidthIsOdd(m.stairs.width) then
        points = ExtendEndsToTileEdges(points)
    end

    local ord = 0
    for _,s in ipairs(StairsOnFloor(floor)) do
        ord = math.max(ord, s.ord)
    end

    local id = dmhub.GenerateGuid()
    WriteStairs(floor, id, m.stairs.width, points, m.stairs.cutHole, ord + 1)
    m.stairs.selectedId = id
    m.stairs.message = nil
    MM.track("markup_stairs_draw", { width = m.stairs.width, points = #points // 2 })
end

--Rewrites the selected staircase with one field changed.
local function UpdateSelectedStairs(changes)
    local s = FindStairs(m.stairs.selectedId)
    local floor = CurrentStairsFloor()
    if s == nil or floor == nil then
        return
    end
    local width = changes.width or s.width
    local points = changes.points or s.points
    local cutHole = s.cutHole
    if changes.cutHole ~= nil then
        cutHole = changes.cutHole
    end
    WriteStairs(floor, s.id, width, points, cutHole, s.ord, s.upFloor, s.holeLength)
end

local function ReversedPoints(points)
    local result = {}
    for i = #points - 1, 1, -2 do
        result[#result+1] = points[i]
        result[#result+1] = points[i+1]
    end
    return result
end

local function DeleteStairs(id)
    local floor = CurrentStairsFloor()
    if floor == nil or id == nil then
        return
    end
    floor:RemoveMarkupZone(id)
    if m.stairs.selectedId == id then
        m.stairs.selectedId = nil
    end
    MM.track("markup_stairs_delete", {})
end

--============================================================================
--Overlay: while the Map Markup panel is open, every staircase on the current
--floor is outlined, with chevrons pointing up the stairs and its top edge in
--green. On the floor above, the top edge and the hole of each staircase arriving
--from below are outlined too. HighlightLine markers survive a Lua reload, so the
--live handles are shared through MapMarkupHooks and stale ones destroyed here.
--============================================================================
if MapMarkupHooks.stairsOverlayHandles ~= nil then
    for _,handle in ipairs(MapMarkupHooks.stairsOverlayHandles) do
        pcall(function() handle:Destroy() end)
    end
end
m.stairsOverlayHandles = {}
MapMarkupHooks.stairsOverlayHandles = m.stairsOverlayHandles
m.stairsOverlayKey = nil

local function ClearStairsOverlay()
    for _,handle in ipairs(m.stairsOverlayHandles) do
        pcall(function() handle:Destroy() end)
    end
    for i = #m.stairsOverlayHandles, 1, -1 do
        m.stairsOverlayHandles[i] = nil
    end
    m.stairsOverlayKey = nil
end

local function AddOverlayLine(floorIndex, color, x1, y1, x2, y2)
    local handle = dmhub.HighlightLine{
        color = color,
        a = core.Vector2(x1, y1),
        b = core.Vector2(x2, y2),
        floorIndex = floorIndex,
        terrainParallax = true,
    }
    if handle ~= nil then
        m.stairsOverlayHandles[#m.stairsOverlayHandles+1] = handle
    end
end

--The centerline as {x, y, nx, ny, s} samples at its vertices: (nx, ny) is the
--mitred left normal, scaled so offsetting by it keeps the band's width through a
--bend; s is the distance along the centerline.
local function CenterlineSamples(points)
    local samples = {}
    local n = #points // 2
    local s = 0
    for i = 1, n do
        local x, y = points[2*i-1], points[2*i]
        if i > 1 then
            local dx = x - points[2*i-3]
            local dy = y - points[2*i-2]
            s = s + math.sqrt(dx*dx + dy*dy)
        end

        local function dir(a, b)
            local dx = points[2*b-1] - points[2*a-1]
            local dy = points[2*b] - points[2*a]
            local len = math.sqrt(dx*dx + dy*dy)
            if len < 0.0001 then
                return 0, 1
            end
            return dx/len, dy/len
        end

        local nx, ny
        if i == 1 then
            local dx, dy = dir(1, 2)
            nx, ny = -dy, dx
        elseif i == n then
            local dx, dy = dir(n-1, n)
            nx, ny = -dy, dx
        else
            local ax, ay = dir(i-1, i)
            local bx, by = dir(i, i+1)
            local mx, my = -ay - by, ax + bx
            local ml = math.sqrt(mx*mx + my*my)
            if ml < 0.0001 then
                nx, ny = -ay, ax
            else
                mx, my = mx/ml, my/ml
                local d = mx*(-ay) + my*ax
                if d < 0.2 then
                    d = 0.2
                end
                nx, ny = mx/d, my/d
            end
        end
        samples[#samples+1] = { x = x, y = y, nx = nx, ny = ny, s = s }
    end
    return samples
end

--The centerline point and direction at distance s along it.
local function PointAt(points, s)
    local n = #points // 2
    local walked = 0
    for i = 2, n do
        local ax, ay = points[2*i-3], points[2*i-2]
        local bx, by = points[2*i-1], points[2*i]
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx*dx + dy*dy)
        if len > 0.0001 and (walked + len >= s or i == n) then
            local t = math.min(1, math.max(0, (s - walked) / len))
            return ax + dx*t, ay + dy*t, dx/len, dy/len
        end
        walked = walked + len
    end
    return points[1], points[2], 0, 1
end

local function DrawStairs(floorIndex, stairs, color)
    local points = stairs.points
    local h = stairs.width * 0.5
    local samples = CenterlineSamples(points)
    if #samples < 2 then
        return
    end

    --the two long sides.
    for i = 2, #samples do
        local a, b = samples[i-1], samples[i]
        AddOverlayLine(floorIndex, color, a.x + a.nx*h, a.y + a.ny*h, b.x + b.nx*h, b.y + b.ny*h)
        AddOverlayLine(floorIndex, color, a.x - a.nx*h, a.y - a.ny*h, b.x - b.nx*h, b.y - b.ny*h)
    end

    --the bottom edge, and the top edge in the "goes up" color.
    local first, last = samples[1], samples[#samples]
    AddOverlayLine(floorIndex, color, first.x + first.nx*h, first.y + first.ny*h, first.x - first.nx*h, first.y - first.ny*h)
    AddOverlayLine(floorIndex, K.STAIRS_TOP_COLOR, last.x + last.nx*h, last.y + last.ny*h, last.x - last.nx*h, last.y - last.ny*h)

    --chevrons up the centerline.
    local length = last.s
    local size = math.min(K.STAIRS_CHEVRON_SIZE, h * 0.8)
    local s = K.STAIRS_CHEVRON_SPACING * 0.5
    while s < length - 0.2 do
        local x, y, dx, dy = PointAt(points, s)
        local lx, ly = -dy, dx
        AddOverlayLine(floorIndex, color, x - dx*size + lx*size, y - dy*size + ly*size, x, y)
        AddOverlayLine(floorIndex, color, x - dx*size - lx*size, y - dy*size - ly*size, x, y)
        s = s + K.STAIRS_CHEVRON_SPACING
    end
end

--On the floor above a staircase: its top edge and the outline of the hole it cuts
--(the top `width` of the stairs, or its holeLength).
local function DrawStairsArrival(floorIndex, stairs)
    local points = stairs.points
    local h = stairs.width * 0.5
    local samples = CenterlineSamples(points)
    if #samples < 2 then
        return
    end
    local last = samples[#samples]
    AddOverlayLine(floorIndex, K.STAIRS_TOP_COLOR, last.x + last.nx*h, last.y + last.ny*h, last.x - last.nx*h, last.y - last.ny*h)

    if not stairs.cutHole then
        return
    end
    local length = last.s
    local from = math.max(0, length - (stairs.holeLength or stairs.width))
    local steps = math.max(1, math.ceil((length - from) / 0.5))
    local prevL, prevR = nil, nil
    for i = 0, steps do
        local s = from + (length - from) * i / steps
        local x, y, dx, dy = PointAt(points, s)
        local lx, ly = -dy*h, dx*h
        local left = { x + lx, y + ly }
        local right = { x - lx, y - ly }
        if prevL ~= nil and prevR ~= nil then
            AddOverlayLine(floorIndex, K.STAIRS_COLOR, prevL[1], prevL[2], left[1], left[2])
            AddOverlayLine(floorIndex, K.STAIRS_COLOR, prevR[1], prevR[2], right[1], right[2])
        else
            AddOverlayLine(floorIndex, K.STAIRS_COLOR, left[1], left[2], right[1], right[2])
        end
        prevL, prevR = left, right
    end
end

local function StairsKeyPart(s)
    return string.format("%s:%s:%s:%s:%s", s.id, tostring(s.width), tostring(s.cutHole), tostring(s.holeLength), table.concat(s.points, ","))
end

local function UpdateStairsOverlay()
    local floor = CurrentStairsFloor()
    if floor == nil or not MM.MarkupPanelIsOpen() then
        if #m.stairsOverlayHandles > 0 or m.stairsOverlayKey ~= nil then
            ClearStairsOverlay()
        end
        return
    end

    local here = StairsOnFloor(floor)
    local below = StairsArrivingOn(floor)

    local floorIndex = game.currentFloorIndex
    local keyParts = { tostring(floorIndex), tostring(m.stairs.selectedId) }
    for _,s in ipairs(here) do
        keyParts[#keyParts+1] = StairsKeyPart(s)
    end
    keyParts[#keyParts+1] = "below"
    for _,s in ipairs(below) do
        keyParts[#keyParts+1] = StairsKeyPart(s)
    end
    local key = table.concat(keyParts, ";")
    if key == m.stairsOverlayKey then
        return
    end

    ClearStairsOverlay()
    for _,s in ipairs(here) do
        DrawStairs(floorIndex, s, cond(s.id == m.stairs.selectedId, K.STAIRS_SELECTED_COLOR, K.STAIRS_COLOR))
    end
    for _,s in ipairs(below) do
        DrawStairsArrival(floorIndex, s)
    end
    m.stairsOverlayKey = key
end

local function StairsOverlayPoll()
    if mod.unloaded then
        return
    end
    local ok, err = pcall(UpdateStairsOverlay)
    if not ok then
        dmhub.Debug("MARKUP:: stairs overlay error: " .. tostring(err))
    end
    dmhub.Schedule(0.3, StairsOverlayPoll)
end
dmhub.Schedule(0.3, StairsOverlayPoll)

--============================================================================
--Props tab UI
--============================================================================

--The Stairs chip, appended after the prop-type chips. refreshPropUI is the Props
--tab's refresh (it re-syncs every chip's selected state and the sections below).
local function CreateStairsChip(refreshPropUI)
    return gui.Panel{
        classes = {"markupChip", cond(StairsActive(), "selected")},
        width = "48%",
        height = 34,
        flow = "horizontal",
        bgimage = true,
        pad = 6,
        borderBox = true,
        hmargin = 2,
        vmargin = 2,

        data = {
            stairsChip = true,
        },

        hover = gui.Tooltip("Stairs: draw a staircase that takes creatures to the floor above. Set its width, then draw its centerline from the bottom of the stairs to the top."),

        press = function(element)
            MM.AbortPendingTeleporterPair()
            m.stairs.active = true
            m.stairs.message = nil
            m.props.selected = nil
            m.props.editingId = nil
            m.props.editingIds = nil
            dmhub.ClearSelectedObjects()
            refreshPropUI()
            MM.TakeMarkupFocus()
        end,

        gui.Label{
            classes = {"bold", "sizeXs"},
            text = "Stairs",
            width = "100%-26",
            height = "auto",
            hmargin = 4,
            valign = "center",
        },
    }
end

local function FloorName(floor)
    if floor == nil then
        return "the floor above"
    end
    local name = tostring(floor.description or "")
    if name == "" then
        return "the floor above"
    end
    return name
end

--The Stairs section of the Props tab: shown while the Stairs chip is selected.
--Owns the centerline map tool, the width / hole settings, and the list of the
--staircases on this floor.
local function BuildStairsSection(refreshPropUI)
    local section

    local refresh = function()
        if section ~= nil and section.valid then
            section:FireEventTree("refreshstairs")
        end
    end

    local instructions = gui.Label{
        classes = {"sizeXs"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 4,

        refreshstairs = function(element)
            local floor = CurrentStairsFloor()
            local above = FloorAbove(floor)
            if m.stairs.message ~= nil then
                element.text = m.stairs.message
            elseif above == nil then
                element.text = "There is no floor above this one, so there is nowhere for stairs to lead. Switch to a lower floor, or add a floor above this one."
            else
                element.text = string.format("Draw the centerline of the stairs from the BOTTOM to the TOP: click to add points (add more for L-shaped or curved stairs), then click the last point again or press Enter to finish. Walking off the top leads up to %s.", FloorName(above))
            end
        end,
    }

    local widthValue = gui.Label{
        classes = {"bold", "sizeXs"},
        text = "",
        width = 80,
        height = "auto",
        valign = "center",
        textAlignment = "center",

        refreshstairs = function(element)
            local s = FindStairs(m.stairs.selectedId)
            local width = m.stairs.width
            if s ~= nil then
                width = s.width
            end
            element.text = string.format("%d square%s", width, cond(width == 1, "", "s"))
        end,
    }

    local ChangeWidth = function(delta)
        local s = FindStairs(m.stairs.selectedId)
        local width = m.stairs.width
        if s ~= nil then
            width = s.width
        end
        width = math.max(K.STAIRS_MIN_WIDTH, math.min(K.STAIRS_MAX_WIDTH, width + delta))
        m.stairs.width = width
        if s ~= nil then
            UpdateSelectedStairs{ width = width }
        end
        refresh()
    end

    local widthRow = gui.Panel{
        width = "96%",
        height = 28,
        halign = "center",
        flow = "horizontal",
        vmargin = 2,

        gui.Label{
            classes = {"sizeXs"},
            text = "Width",
            width = 80,
            height = "auto",
            valign = "center",
        },

        gui.Button{
            text = "-",
            width = 28,
            height = 24,
            valign = "center",
            hover = gui.Tooltip("Narrower stairs."),
            click = function(element)
                ChangeWidth(-1)
            end,
        },

        widthValue,

        gui.Button{
            text = "+",
            width = 28,
            height = 24,
            valign = "center",
            hover = gui.Tooltip("Wider stairs."),
            click = function(element)
                ChangeWidth(1)
            end,
        },
    }

    local holeCheck = gui.Check{
        text = "Cut a hole in the floor above",
        hmargin = 8,
        vmargin = 2,
        tooltip = "Removes the floor above over the top of the stairs (one stair-width back from the top edge), so it does not cover them. Walking up the stairs arrives on the floor above; stepping into the hole from anywhere else falls onto the stairs.",
        value = m.stairs.cutHole,
        change = function(element)
            m.stairs.cutHole = element.value
            if FindStairs(m.stairs.selectedId) ~= nil then
                UpdateSelectedStairs{ cutHole = element.value }
            end
            refresh()
        end,

        refreshstairs = function(element)
            local s = FindStairs(m.stairs.selectedId)
            local value = m.stairs.cutHole
            if s ~= nil then
                value = s.cutHole
            end
            if element.value ~= value then
                element.value = value
            end
        end,
    }

    local selectionLabel = gui.Label{
        classes = {"fgMuted", "sizeXs"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 2,

        refreshstairs = function(element)
            if FindStairs(m.stairs.selectedId) ~= nil then
                element.text = "Width and the hole setting apply to the selected staircase. Click it again in the list to deselect it."
            else
                element.text = "Width and the hole setting apply to the next staircase you draw."
            end
        end,
    }

    local actionsRow = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        vmargin = 2,

        refreshstairs = function(element)
            element:SetClass("collapsed", FindStairs(m.stairs.selectedId) == nil)
        end,

        gui.Button{
            classes = {"sizeM"},
            text = "Reverse Direction",
            hmargin = 4,
            hover = gui.Tooltip("Swap the top and bottom of the selected staircase."),
            click = function(element)
                local s = FindStairs(m.stairs.selectedId)
                if s ~= nil then
                    UpdateSelectedStairs{ points = ReversedPoints(s.points) }
                    refresh()
                end
            end,
        },

        gui.Button{
            classes = {"sizeM"},
            text = "Delete Stairs",
            hmargin = 4,
            click = function(element)
                DeleteStairs(m.stairs.selectedId)
                refresh()
            end,
        },
    }

    local listHeader = gui.Label{
        classes = {"bold"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 2,
    }

    local listRows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local CreateStairsRow = function(s, index, above)
        local title = string.format("Stairs %d -- %d wide, up to %s", index, s.width, FloorName(above))
        if not s.cutHole then
            title = title .. " (no hole)"
        end
        return gui.Panel{
            classes = {"markupChip", cond(s.id == m.stairs.selectedId, "selected")},
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            data = {
                stairsId = s.id,
            },

            hover = gui.Tooltip("Click to select this staircase and pan to it. Right-click for more."),

            press = function(element)
                MM.TakeMarkupFocus()
                if m.stairs.selectedId == s.id then
                    m.stairs.selectedId = nil
                else
                    m.stairs.selectedId = s.id
                    local x, y = PointAt(s.points, CenterlineLength(s.points) * 0.5)
                    dmhub.CenterOnLoc{ x = math.floor(x), y = math.floor(y), smooth = true }
                end
                refresh()
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Reverse Direction",
                            click = function()
                                element.popup = nil
                                m.stairs.selectedId = s.id
                                UpdateSelectedStairs{ points = ReversedPoints(s.points) }
                                refresh()
                            end,
                        },
                        {
                            text = "Delete Stairs",
                            click = function()
                                element.popup = nil
                                DeleteStairs(s.id)
                                refresh()
                            end,
                        },
                    },
                }
            end,

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = title,
                width = "100%",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },
        }
    end

    local listPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        data = {
            signature = nil,
        },

        refreshstairs = function(element)
            local floor = CurrentStairsFloor()
            local above = FloorAbove(floor)
            local stairs = StairsOnFloor(floor)

            if m.stairs.selectedId ~= nil and FindStairs(m.stairs.selectedId) == nil then
                m.stairs.selectedId = nil
            end

            listHeader.text = string.format("Stairs on This Floor (%d)", #stairs)

            local parts = { tostring(game.currentFloorId), tostring(m.stairs.selectedId), FloorName(above) }
            for _,s in ipairs(stairs) do
                parts[#parts+1] = StairsKeyPart(s)
            end
            local sig = table.concat(parts, ";")
            if sig == element.data.signature then
                return
            end
            element.data.signature = sig

            local rows = {}
            for i,s in ipairs(stairs) do
                rows[#rows+1] = CreateStairsRow(s, i, above)
            end
            if #rows == 0 then
                rows[1] = gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = "No stairs on this floor yet.",
                    width = "90%",
                    height = "auto",
                    halign = "center",
                    vmargin = 4,
                    textAlignment = "center",
                }
            end
            listRows.children = rows
        end,

        listHeader,
        listRows,
    }

    section = gui.Panel{
        classes = {cond(not StairsActive(), "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        --re-registers the centerline tool (it expires after a second) and keeps
        --the list fresh as stairs change, including from other clients.
        thinkTime = 0.3,

        events = {
            refreshprops = function(element)
                local active = StairsActive()
                element:SetClass("collapsed", not active)
                if active then
                    element:FireEventTree("refreshstairs")
                end
            end,

            think = function(element)
                if m.mode ~= "props" or not StairsActive() then
                    return
                end

                element:FireEventTree("refreshstairs")

                if not m.arm.Armed() or FloorAbove(CurrentStairsFloor()) == nil then
                    return
                end

                --an open polyline: the stroke finishes on a click on its last
                --point, or Enter.
                local eventSource = editor:SetMapTool{
                    tool = "shape",
                    closed = false,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                    --see WidthIsOdd.
                    snapToTileCenters = WidthIsOdd(m.stairs.width),
                    editorCursor = true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m.mode ~= "props" or not StairsActive() or path == nil then
                    return
                end
                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil then
                    return
                end
                CreateStairsFromStroke(points)
                refresh()
            end,
        },

        instructions,
        widthRow,
        holeCheck,
        selectionLabel,
        actionsRow,
        listPanel,
    }

    return section
end

--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.StairsActive = StairsActive
MM.StairsOnFloor = StairsOnFloor
MM.CreateStairsChip = CreateStairsChip
MM.BuildStairsSection = BuildStairsSection
MM.ClearStairsOverlay = ClearStairsOverlay
MM.UpdateStairsOverlay = UpdateStairsOverlay
