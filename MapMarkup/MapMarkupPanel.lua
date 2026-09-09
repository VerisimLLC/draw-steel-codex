local mod = dmhub.GetModLoading()

--Map Markup panel: mode/tool tables, styles, delete-tool geometry and
--CreateMarkupEditor, the panel shell that assembles the per-tab builders
--(MapMarkup*Mode.lua). See MapMarkupCore.lua for the file map.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--The panel.
--============================================================================

K.MODES = {
    {
        id = "walls",
        text = "Walls",
    },
    {
        id = "zones",
        text = "Zones",
    },
    {
        id = "surfaces",
        text = "Footsteps",
    },
    {
        id = "elevation",
        text = "Elevation",
    },
    {
        id = "props",
        text = "Props",
    },
}

--mode tab widths: five tabs share the strip; on a pack map they yield the
--remainder to the share-markup icon at the right end.
K.TAB_WIDTH = "20%"
K.TAB_WIDTH_WITH_SHARE = "18%"

--Tools with a `tool` field drive the engine building tools (drawing).
--Tools with a `mapTool` field are custom map tools (editor.SetMapTool) whose
--strokes come back to this panel as 'tool' events. The eraser and Delete
--Wall tools are shared between the thin and solid tool strips.
K.TOOL_ERASE = {
    id = "erase",
    text = "Erase",
    icon = "phosphor/eraser-fill.png",
    mapTool = "rectangle",
    mapToolClosed = true,
    --draws the engine's stroke preview red instead of white (see the think
    --handler's SetMapTool call), like the zone and footstep erasers.
    erase = true,
    help = "Eraser: drag a rectangle to erase every markup wall (and markup solid block) inside it. Visible art walls are not affected.",
}

K.TOOL_DELETE = {
    id = "delete",
    text = "Delete",
    icon = "ui-icons/close.png",
    --Inert sentinel: keeping a custom map tool alive (wallSkeletons=true)
    --leaves the grey wall skeleton overlay up so the user can see the walls
    --they are removing. This string matches no real map tool ("free",
    --"rectangle", "shape"...), so it captures no drawing - the Delete tool's
    --input comes from map focus (maphover/mappress) instead. See the think
    --loop and the maphover/mappress handlers below.
    mapTool = "markupdelete",
    mapToolClosed = false,
    help = "Delete Wall: hover a markup wall to highlight the segment under the cursor, then click to remove just that segment. Visible art walls are not affected.",
}

--Apply Type ("retype"): converts drawn markup walls to the SELECTED palette
--type. Two gestures through one real rectangle map tool: a click converts
--the WHOLE drawn operation under the cursor (the same hover machinery as
--Delete, tinted the target type's color and extended to the full wall
--path), and a drag converts every wall edge the rectangle touches, at edge
--granularity, with the captured edges highlighted live as the rect grows.
--Input arrives twice over - map focus (mappress, like Delete) AND the
--rectangle stroke (a click is a degenerate stroke) - because which of the
--two the engine delivers for a click depends on how it arbitrates a live
--custom tool against map focus; handling both is safe since retyping an
--already-converted wall is a no-op (RetypeWallEdges skips ops already of
--the target type).
K.TOOL_RETYPE = {
    id = "retype",
    text = "Retype",
    icon = "phosphor/paint-roller-fill.png",
    mapTool = "rectangle",
    mapToolClosed = true,
    help = "Apply Type: click a markup wall to change that whole drawn wall to the selected wall type, or drag a rectangle starting on empty space to convert every wall edge it touches. Visible art walls are not affected.",
}

--Secret Door ("secret"): toggles the doorSecret flag on the markup DOOR
--under the cursor. A secret door is invisible to players in EVERY state -
--no icon, leaf or lock badge, open or closed - so they perceive plain wall
--(an open one is simply a gap they can pass and see through); the Director
--sees it violet-tinted with an eye-slash badge, and can also reveal it from
--the door icon's right-click menu in play. Same inert-sentinel machinery as
--Delete Wall: input arrives via map focus (maphover/mappress), the door is
--found by nearest door EDGE against the door ops' own paths
--(MM.FindDoorAtPoint - so open doors, which have no wall geometry, are
--found too), and a click flips the flag through floor:SetDoorState. Only
--offered while the selected wall type is openable (K.DOOR_TOOLS), like the
--door chip preview: doors are what that selection is about.
K.TOOL_SECRET = {
    id = "secret",
    text = "Secret",
    icon = "phosphor/eye-slash-fill.png",
    mapTool = "markupsecret",
    mapToolClosed = false,
    help = "Secret Door: hover a markup door to highlight it, then click to make it secret - players see only wall, open or closed, until you reveal it (click it again here, or right-click its icon in play). Its open/close sounds still play for everyone.",
}

--Hover tint for the Secret Door tool: the door that a click will MAKE
--secret. Matches the engine's Director-side secret-door tint.
K.SECRET_DOOR_COLOR = "#b88cff"

--`shape` pairs a tool with its counterpart in the other draw mode, so switching
--Thin <-> Solid keeps the shape the user picked instead of resetting the strip.
--Both strips lead with the rectangle so the two modes read the same.
K.TOOLS = {
    {
        id = "rectangle",
        shape = "rect",
        text = "Rect",
        icon = "game-icons/square.png",
        tool = "rectangle",
        help = "Rectangle tool: drag to draw a rectangle of walls.",
    },
    {
        id = "line",
        shape = "poly",
        text = "Line",
        icon = "game-icons/polygon-segments.png",
        tool = "shape",
        help = "Line tool: click to chain wall segments; double-click or press Enter to finish.",
    },
    {
        id = "free",
        shape = "free",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        tool = "free",
        help = "Freehand tool: drag to draw walls along the cursor.",
    },
    {
        id = "points",
        text = "Points",
        icon = "icons/icon_gesture/icon_gesture_47.png",
        tool = "points",
        help = "Edit Points: drag a wall vertex to move it. Right-click a vertex to delete it, click on a wall line to add a vertex, and click a one-way wall's direction marker to flip its facing.",
    },
    K.TOOL_RETYPE,
    K.TOOL_ERASE,
    K.TOOL_DELETE,
}

--Thin strip while an OPENABLE (door) wall type is selected: K.TOOLS plus
--Secret Door, slotted with the non-destructive editing tools just before
--Retype. Openable types are thin-only, so this never pairs with SOLID_TOOLS.
K.DOOR_TOOLS = {}
for _,toolInfo in ipairs(K.TOOLS) do
    if toolInfo == K.TOOL_RETYPE then
        K.DOOR_TOOLS[#K.DOOR_TOOLS+1] = K.TOOL_SECRET
    end
    K.DOOR_TOOLS[#K.DOOR_TOOLS+1] = toolInfo
end

--Tool strip in SOLID draw mode: a solid block is a filled region, not an open
--polyline, so the drawing tools are closed shapes running as custom map tools
--(like the eraser) - never the engine building tools. Their strokes come back
--as 'tool' events and turn into ExecutePolygonOperation{solid=true} (see
--markupsolid below). The Points tool is the one engine building tool in this
--strip: PointEditingTool edits solid-op outlines too (it exempts solid ops
--from its floor-op skip), reshaping the block's area. On a stale engine build
--the tool activates but shows no vertices for solids - harmless no-op.
K.SOLID_TOOLS = {
    {
        id = "solidrect",
        shape = "rect",
        text = "Rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        mapToolClosed = true,
        help = "Rectangle block: drag to fill a rectangle with a solid block of the selected wall type.",
    },
    {
        id = "solidpoly",
        shape = "poly",
        text = "Poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        mapToolClosed = true,
        help = "Polygon block: click to chain vertices around the area to fill; double-click or press Enter to finish.",
    },
    {
        id = "solidfree",
        shape = "free",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        mapToolClosed = true,
        help = "Freehand block: drag to trace the outline of the area to fill.",
    },
    {
        --same id as the thin strip's entry so switching Thin <-> Solid keeps
        --the Points tool selected (rebuildtools' validTool check passes).
        id = "points",
        text = "Points",
        icon = "icons/icon_gesture/icon_gesture_47.png",
        tool = "points",
        help = "Edit Points: drag a vertex of a solid block to reshape its area. Right-click a vertex to delete it; click on an edge to add a vertex.",
    },
    K.TOOL_RETYPE,
    K.TOOL_ERASE,
    K.TOOL_DELETE,
}

--Zone painting tools: all closed-shape custom map tools (a zone is a filled
--tile region). Strokes come back as 'tool' events and rasterize to the tiles
--whose centers the stroke contains.
K.ZONE_TOOLS = {
    {
        id = "zonerect",
        text = "Rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        help = "Rectangle: drag to paint the selected zone type over an area.",
    },
    {
        id = "zonepoly",
        text = "Poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        help = "Polygon: click to chain vertices around the area to paint; double-click or press Enter to finish.",
    },
    {
        id = "zonefree",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        help = "Freehand: drag to trace the outline of the area to paint.",
    },
    {
        id = "zoneerase",
        text = "Erase",
        icon = "phosphor/eraser-fill.png",
        mapTool = "rectangle",
        erase = true,
        help = "Eraser: drag a rectangle to remove zone tiles from every zone in the region. Holes are clipped against the region.",
    },
}

local function ZoneToolById(id)
    for _,toolInfo in ipairs(K.ZONE_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--Footsteps mode paint tools: the same closed-shape custom map tools as the
--zone tools, painting the selected surface family instead of a keyword.
K.FOOTSTEP_TOOLS = {
    {
        id = "footrect",
        text = "Rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        help = "Rectangle: drag to paint the selected footstep surface over an area.",
    },
    {
        id = "footpoly",
        text = "Poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        help = "Polygon: click to chain vertices around the area to paint; double-click or press Enter to finish.",
    },
    {
        id = "footfree",
        text = "Draw",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        help = "Freehand: drag to trace the outline of the area to paint.",
    },
    {
        id = "footerase",
        text = "Erase",
        icon = "phosphor/eraser-fill.png",
        mapTool = "rectangle",
        erase = true,
        help = "Eraser: drag a rectangle to clear painted footstep surfaces from the region.",
    },
}

local function FootstepToolById(id)
    for _,toolInfo in ipairs(K.FOOTSTEP_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--Looks a tool id up in either strip (the draw-mode switch needs the OUTGOING
--tool's shape, which by then is no longer in the active strip).
local function FindToolInfo(id)
    if id == K.TOOL_SECRET.id then
        return K.TOOL_SECRET
    end
    for _,toolInfo in ipairs(K.TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    for _,toolInfo in ipairs(K.SOLID_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--The active tool strip follows the DRAW MODE: thin mode drives the engine
--building tools, solid mode drives closed-shape custom map tools. Openable
--(door) types are thin-only - selecting one forces thin mode (SelectChip) -
--and get the thin strip plus the Secret Door tool (K.DOOR_TOOLS).
local function ActiveToolInfos()
    local openable = MM.EntryIsOpenable(m.paletteEntries[m.selectedIndex or 0])
    if m.solidMode and not openable then
        return K.SOLID_TOOLS
    end
    if openable then
        return K.DOOR_TOOLS
    end
    return K.TOOLS
end

--Chip rules are shared between the panel and the library modal: modals
--re-root the style cascade, so the modal needs its own copy of these rules.
local function MarkupChipStyles()
    return {
        {
            selectors = {"markupChip"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupChip", "hover"},
            borderColor = "@fg",
        },
        --the selected chip must be unmistakable at a glance: filled AND a
        --thicker accent border, not just a slightly brighter outline.
        {
            selectors = {"markupChip", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 2,
        },
        {
            selectors = {"markupWallLine"},
            bgcolor = "@fgMuted",
        },

        --the Wall Color swatches: a quiet outline normally, brightening on
        --hover, and a thick bright ring on the chosen swatch. The ring is
        --@fg rather than @accent because it sits on an arbitrary swatch
        --color and must read against all eight.
        {
            selectors = {"markupColorSwatch"},
            borderWidth = 1,
            borderColor = "@border",
        },
        {
            selectors = {"markupColorSwatch", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupColorSwatch", "selected"},
            borderWidth = 2,
            borderColor = "@fg",
        },

        --the zone chip's "Entire Map" toggle: a small pill that lights up
        --while this zone type blankets the whole map.
        {
            selectors = {"markupEntireMap"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupEntireMap", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupEntireMap", "lit"},
            bgcolor = "@accent",
            borderColor = "@accent",
        },
        {
            selectors = {"markupEntireMapLabel"},
            color = "@fgMuted",
        },
        {
            selectors = {"markupEntireMapLabel", "parent:hover"},
            color = "@fg",
        },
        {
            selectors = {"markupEntireMapLabel", "parent:lit"},
            color = "@fgInverse",
        },

        --small uppercase section headers ("WALL TYPES", "SHAPE", "TOOL"):
        --quieter than body text so the selectable content reads first.
        {
            selectors = {"markupSectionHeader"},
            fontSize = 12,
            bold = true,
            color = "@fgMuted",
        },

        --the armed-state dot on the active mode tab: bright while the panel
        --holds focus (drawing armed), dim when a click elsewhere disarmed it.
        {
            selectors = {"markupStateDot"},
            bgcolor = "@disabled",
        },
        {
            selectors = {"markupStateDot", "armed"},
            bgcolor = "@fgStrong",
        },

        --tool chips: icon over a small caption. The destructive pair (erase /
        --delete) is tinted @danger so it cannot be mistaken for a drawing tool.
        {
            selectors = {"markupToolChip"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupToolChip", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupToolChip", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@accent",
            borderWidth = 2,
        },
        --after selected, so a selected destructive tool keeps the red border.
        {
            selectors = {"markupToolChip", "danger"},
            borderColor = "@danger",
        },
        {
            selectors = {"markupToolIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"markupToolIcon", "danger"},
            bgcolor = "@danger",
        },
        {
            selectors = {"markupToolLabel"},
            fontSize = 10,
            color = "@fgMuted",
        },
        {
            selectors = {"markupToolLabel", "danger"},
            color = "@danger",
        },
        {
            selectors = {"markupToolDivider"},
            bgcolor = "@border",
        },

        --gui.Slider deliberately sets NO default width/height (Gui.lua: doing
        --so would be selfStyle and would beat any cascade rule the caller
        --supplied), and it sizes its handle off its own height
        --(handle width = "100% height", holding a 60% square rotated 45).
        --An unsized slider therefore renders as a giant diamond. The Edit
        --Wall dialog solves this with the same two rules; the panel body
        --needs its own copy because that dialog is a separate modal with
        --separate styles. Width leaves room for the row's 80px name label.
        {
            selectors = {"slider"},
            width = "100%-84",
            height = 24,
            valign = "center",
        },
        {
            selectors = {"sliderLabel"},
            fontSize = 14,
        },
    }
end

local function GetPanelStyles()
    return ThemeEngine.MergeStyles{
        MarkupChipStyles(),
    }
end

--Tooltip that opens to the SIDE of the hovered control - over the map, not
--over the panel - so it never covers the controls it describes. Side is
--picked per hover from where the control actually sits on screen: open
--toward whichever side has more room. The engine clamps tooltips back
--onto the screen, so opening toward a nearby screen edge would slide the
--tooltip over the control itself (the old dock-class check missed
--undocked/windowed hosts and did exactly that).
--
--In a POPOUT window there is no map to open over - the whole window is
--panel, so a tooltip that FITS the window necessarily sits on the
--controls. There the tooltip is pushed just past the window edge instead:
--the engine's tooltip promote-on-overflow (popout Phase 5.2) lifts it into
--a desktop-level child window BESIDE the OS window, vertically centered on
--the control. Gated on child-window support; without it (old engine or
--companion) the in-window clamp degrades this to today's behavior.
local function SideTooltip(text)
    if text == nil then
        return nil
    end
    return function(element)
        local halign = "right"

        local dock = element:FindParentWithClass("dock")
        local popoutHost = nil
        if dock ~= nil and dock.data.nativeWindowRoot then
            popoutHost = dock
        end

        if popoutHost ~= nil and dmhub.popoutChildWindowsSupported and
            dmhub.supportsPopoutTooltipPlacement then
            --Popout window: the tooltip opens flush beside the hovered
            --control exactly like in-app; when it does not fit the window,
            --the engine's tooltip promote-on-overflow lifts it into a
            --desktop-level child window at that same anchor-adjacent spot,
            --so it extends past the window edge (partly over the window,
            --partly over the desktop) instead of clamping onto the panel.
            --Only the SIDE choice differs from in-app: the in-window rooms
            --are all tiny in a small popout, so pick whichever side of the
            --OS window has more DESKTOP room, with the app's own screen
            --size as the best available desktop proxy. A wrong guess is
            --not fatal - the OS clamps child windows back onto the display.
            --Gated on placement-fixed engine builds: older ones return
            --mirrored distances and mirrored promotion offsets (the popout
            --canvas rect carries a -1 x scale).
            local geo = popoutHost.data.popoutGeometry
            local screenDim = dmhub.screenDimensions
            local screenX = geo ~= nil and geo.x or nil
            if screenX ~= nil and geo.width ~= nil and
                screenX > screenDim.x - (screenX + geo.width) then
                halign = "left"
            end
        else
            --x1/x2 = screen room to the left/right of the element.
            local distances = element.distancesToScreenEdge
            if distances ~= nil and distances.x2 < distances.x1 then
                halign = "left"
            end
        end

        element.tooltip = CreateTooltipPanel{
            text = text,
            halign = halign,
            valign = "center",
        }
    end
end

--============================================================================
--Delete tool helpers.
--
--The Delete tool is a hover-then-click interaction driven by map focus
--(maphover/mappress), not a stroke: moving over a wall highlights the single
--segment (edge) under the cursor, and a click erases just that edge. The
--engine's GetNearestWallSegment returns the nearest wall's WHOLE centerline
--path; we pick the nearest edge of that path ourselves so a click removes only
--the touched segment instead of the entire wall (which is what erasing the
--full path used to do - "deletes large swathes of wall").
--============================================================================

--The highlighted "about to delete" line, plus a key identifying its segment so
--the marker is only rebuilt when the target segment actually changes (maphover
--fires on every mouse move).
m.deleteHighlight = nil
m.deleteHighlightKey = nil
--The warn-once flag for engine builds lacking GetNearestWallSegment lives on
--m.mapScope (m.mapScope.deleteWarnedNoEngine) rather than in its own local,
--keeping the probe's state with the rest of the map scope.

local function DistancePointToSegment(px, py, ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local lenSq = dx*dx + dy*dy
    local t = 0
    if lenSq > 0.00000001 then
        t = ((px - ax)*dx + (py - ay)*dy) / lenSq
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx = ax + t*dx
    local cy = ay + t*dy
    local ex = px - cx
    local ey = py - cy
    return math.sqrt(ex*ex + ey*ey)
end

--Returns { a = {x,y}, b = {x,y} } for the nearest invisible-wall edge to the
--cursor world point - or, when a markup DOOR's segment is nearer, that
--segment with its object in the `door` field - or nil if nothing is within
--reach / the point is off-map.
local function FindNearestDeleteSegment(point)
    if point == nil then
        return nil
    end
    local floor = game.currentFloor
    if floor == nil then
        return nil
    end

    --The maphover/mappress point is parallax-adjusted using the mouseover
    --floor's heightmap only, but walls render projected by the full surface
    --altitude (heightmap + elevation overlay + platforms). On ground raised or
    --lowered from 0 the two disagree, so the selection landed off the wall
    --under the cursor. editor.mouseEditSurfacePoint uses the same projection
    --as wall rendering; pcall so a stale engine build degrades to the event
    --point instead of erroring every mouse move.
    local okSurface, surfacePoint = pcall(function()
        return editor.mouseEditSurfacePoint
    end)
    if okSurface and surfacePoint ~= nil then
        point = surfacePoint
    end

    --pcall: maphover fires every frame, so a stale engine build (no
    --GetNearestWallSegment) must degrade quietly instead of erroring per move.
    --atMouse: engines that support it ignore x/y and match walls in projected
    --screen space against the actual cursor -- the only approach that stays
    --accurate on steep slopes, where a wall renders far from its stored
    --coordinates and any converted point comparison can exceed maxDistance.
    --Older engines ignore the flag and use x/y as before.
    local ok, seg = pcall(function()
        return floor:GetNearestWallSegment{
            x = point.x,
            y = point.y,
            atMouse = true,
            maxDistance = 0.7,
            invisibleOnly = true,
        }
    end)
    if not ok then
        if not m.mapScope.deleteWarnedNoEngine then
            m.mapScope.deleteWarnedNoEngine = true
            dmhub.Debug("MARKUP:: delete tool needs an engine build with GetNearestWallSegment support")
        end
        return nil
    end
    if seg == nil then
        return nil
    end

    --Engines with atMouse support hand back the nearest edge directly (matched
    --in projected screen space, so it is the edge visually under the cursor
    --even on steep slopes). Prefer it over re-deriving the edge here. The
    --wall's whole path rides along in `points` (interleaved x,y) for callers
    --that preview the full wall (the Apply Type hover).
    if seg.segment ~= nil and #seg.segment >= 4 then
        return {
            a = { x = seg.segment[1], y = seg.segment[2] },
            b = { x = seg.segment[3], y = seg.segment[4] },
            points = seg.points,
        }
    end

    local pts = seg.points
    if pts == nil or #pts < 4 then
        return nil
    end

    --Older engines: pts is an interleaved x,y list of the wall's whole path;
    --find the single edge (consecutive vertex pair) closest to the cursor.
    local bestDist = nil
    local best = nil
    for i = 1, #pts - 3, 2 do
        local ax, ay = pts[i], pts[i+1]
        local bx, by = pts[i+2], pts[i+3]
        local d = DistancePointToSegment(point.x, point.y, ax, ay, bx, by)
        if bestDist == nil or d < bestDist then
            bestDist = d
            best = { a = { x = ax, y = ay }, b = { x = bx, y = by }, points = pts }
        end
    end
    return best
end

--Finds the markup DOOR nearest to a floor-space point: the door operation
--(floor:GetDoorOperations - the ops' own drawn paths, so an OPEN door with
--no wall geometry is found too) with the edge closest to the point, within
--K.DOOR_PICK_DISTANCE tiles. Returns { door = <op record>, segments =
--{ax,ay,bx,by, ...} (every edge of the door, for the whole-door highlight) }
--or nil. Used by the Secret Door tool. The point is the parallax-adjusted
--cursor point maphover/mappress deliver; editor.mouseEditSurfacePoint is
--preferred when the cursor is over the map, for the same reason
--FindNearestDeleteSegment prefers it (it uses the wall rendering's own
--surface projection, so raised/lowered ground does not skew the pick).
K.DOOR_PICK_DISTANCE = 0.7
local function FindDoorAtPoint(point)
    if point == nil then
        return nil
    end
    local floor = game.currentFloor
    if floor == nil then
        return nil
    end
    local surfacePoint = editor.mouseEditSurfacePoint
    if surfacePoint ~= nil then
        point = surfacePoint
    end

    local best = nil
    local bestDist = K.DOOR_PICK_DISTANCE
    for _,door in ipairs(floor:GetDoorOperations()) do
        local segments = {}
        local doorDist = nil
        for _,pts in ipairs(door.paths) do
            for i = 1, #pts - 3, 2 do
                local ax, ay, bx, by = pts[i], pts[i+1], pts[i+2], pts[i+3]
                segments[#segments+1] = ax
                segments[#segments+1] = ay
                segments[#segments+1] = bx
                segments[#segments+1] = by
                local d = DistancePointToSegment(point.x, point.y, ax, ay, bx, by)
                if doorDist == nil or d < doorDist then
                    doorDist = d
                end
            end
        end
        if doorDist ~= nil and doorDist <= bestDist then
            bestDist = doorDist
            best = { door = door, segments = segments }
        end
    end
    return best
end

--A hair-thin open-path erase EXACTLY along the wall centerline is unreliable on
--short segments: clipper's collinear-overlap handling (the ribbon sits right on
--the wall line) is numerically unstable -> "sometimes deletes nothing". So we
--erase a CLOSED box oriented along the segment: the wall centerline runs
--through the box INTERIOR (no collinear edge, so clipper is stable).
--
--K.DELETE_MIN_GAP guarantees the cut survives the engine's wall endpoint
--auto-merge (WallInfo.PointsCloseEnoughToMerge). That threshold used to be 0.3
--tiles - which forced MIN_GAP to 0.4 and made deleting one fine segment clear
--its neighbours too. The engine now welds only within 0.01, so the gap can be
--near-exact and a click removes just the touched segment.
--REQUIRES that engine build: against an older engine (0.3 weld) gaps this
--small heal straight back and deletion appears to do nothing.
K.DELETE_MIN_GAP = 0.05      --min cleared length along the wall (> 0.01 merge threshold)
K.DELETE_HALF_WIDTH = 0.05   --box half-width; keeps the centerline off the box edges
K.DELETE_END_OVERSHOOT = 0.02 --push the cut just past a long segment's ends so both are removed

--Given a touched edge { a = {x,y}, b = {x,y} } returns:
--  a, b : the two axis endpoints of the cleared span (for the highlight preview)
--  box  : an interleaved-coord closed quad to feed ExecutePolygonOperation
local function DeleteSegmentGeometry(seg)
    local ax, ay = seg.a.x, seg.a.y
    local bx, by = seg.b.x, seg.b.y
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.0001 then
        --degenerate edge: clear an axis-aligned chunk around the point.
        dx, dy, len = 1, 0, 1
    end
    local ux, uy = dx/len, dy/len   --unit along the segment
    local nx, ny = -uy, ux          --unit perpendicular to it
    local mx, my = (ax + bx)*0.5, (ay + by)*0.5
    local halfLen = math.max(len*0.5 + K.DELETE_END_OVERSHOOT, K.DELETE_MIN_GAP*0.5)
    local hw = K.DELETE_HALF_WIDTH

    local e1x, e1y = mx + ux*halfLen, my + uy*halfLen
    local e2x, e2y = mx - ux*halfLen, my - uy*halfLen

    return {
        a = { x = e1x, y = e1y },
        b = { x = e2x, y = e2y },
        box = {
            e1x + nx*hw, e1y + ny*hw,
            e1x - nx*hw, e1y - ny*hw,
            e2x - nx*hw, e2y - ny*hw,
            e2x + nx*hw, e2y + ny*hw,
        },
    }
end

--m.deleteHighlight holds either one HighlightLine handle (Delete's single
--edge) or a plain list of them (Apply Type's whole-wall / marquee preview).
local function ClearDeleteHighlight()
    local h = m.deleteHighlight
    m.deleteHighlight = nil
    m.deleteHighlightKey = nil
    if h == nil then
        return
    end
    if type(h) == "table" then
        for _,line in ipairs(h) do
            line:Destroy()
        end
    else
        h:Destroy()
    end
end

--Also used by the Apply Type (retype) tool, which tints the highlight the
--target type's color instead of the delete red.
local function ShowDeleteHighlight(seg, color)
    color = color or "#ff4d4d"
    local key = string.format("%.4f,%.4f,%.4f,%.4f,%s", seg.a.x, seg.a.y, seg.b.x, seg.b.y, color)
    if key == m.deleteHighlightKey and m.deleteHighlight ~= nil then
        return
    end
    ClearDeleteHighlight()
    --terrainParallax: the wall skeleton parallax-shifts with the camera + terrain
    --height every frame, so a flat (z=0) line drifts off the wall wherever the
    --map has parallax. This projects the highlight with the same parallax.
    m.deleteHighlight = dmhub.HighlightLine{
        color = color,
        a = core.Vector2(seg.a.x, seg.a.y),
        b = core.Vector2(seg.b.x, seg.b.y),
        floorIndex = game.currentFloorIndex,
        terrainParallax = true,
    }
    m.deleteHighlightKey = key
end

--Multi-line variant for the Apply Type tool: one highlight line per edge in
--a flat interleaved {ax,ay,bx,by, ...} list (the whole hovered wall on
--hover; the captured edges during a marquee drag). Shares the delete
--highlight's storage, so the two previews never stack. A field on
--m.mapScope rather than a new file-level local, keeping it with the rest of
--the map scope.
m.mapScope.ShowSegmentsHighlight = function(segments, color)
    if segments == nil or #segments < 4 then
        ClearDeleteHighlight()
        return
    end
    local parts = { color }
    for i = 1, #segments do
        parts[#parts+1] = string.format("%.3f", segments[i])
    end
    local key = table.concat(parts, ",")
    if key == m.deleteHighlightKey and m.deleteHighlight ~= nil then
        return
    end
    ClearDeleteHighlight()
    local lines = {}
    for i = 1, #segments - 3, 4 do
        lines[#lines+1] = dmhub.HighlightLine{
            color = color,
            a = core.Vector2(segments[i], segments[i+1]),
            b = core.Vector2(segments[i+2], segments[i+3]),
            floorIndex = game.currentFloorIndex,
            terrainParallax = true,
        }
    end
    m.deleteHighlight = lines
    m.deleteHighlightKey = key
end

local CreateMarkupEditor

DockablePanel.Register{
    name = "Map Markup",
    icon = "icons/standard/Icon_App_Whiteboard.png",
    vscroll = true,
    dmonly = true,
    minHeight = 200,
    folder = "Map Editing",
    stickyFocus = true,
    --a press anywhere on the panel -- its background, its title bar --
    --arms it, not just its individual tool controls.
    focusOnClick = true,
    content = function()
        MM.track("panel_open", {
            panel = "Map Markup",
            dailyLimit = 30,
        })
        return CreateMarkupEditor()
    end,
}

--============================================================================
--The panel shell: CreateMarkupEditor assembles the mode tabs, the per-tab
--builders (MapMarkup*Mode.lua) and the Fade Map row.
--============================================================================

--Small uppercase section header used by every mode's sections, quieter
--than the selectable content beneath it.
local function SectionHeader(text)
    return gui.Label{
        classes = {"markupSectionHeader"},
        text = text,
        uppercase = true,
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 4,
    }
end

--Every drawing path in this panel is focus-gated (see the tool-strip think
--handlers): the engine building tools only draw while our focus-gated wall
--selection is published, and the custom map tools are re-registered from a
--0.3s think that bails without panel focus. So ANY press that changes what
--would be drawn must also take focus and re-register immediately, or the
--click after it silently does nothing. It re-fires 'think' on the
--current mode's tool panel, read from m.modePanels.
--
--Take GUI focus for the panel and immediately (re-)register the current
--mode's map tool, instead of waiting up to thinkTime (0.3s) for the next
--tick. Called from every press that selects what gets drawn - mode tabs,
--type/surface chips, list rows - so the panel is armed the instant the
--user picks something, without them having to click a tool first.
--
--Focus goes on contentPanel, NOT on the pressed element. This matters:
--chips and list rows are TRANSIENT - the palette rebuilds its children
--whole on refreshzonepalette/refreshprops (which `monitorAssets` fires on
--any asset-table change) and the zone/footstep lists rebuild theirs on
--refreshzones. Parking focus on a chip meant the first stroke that
--materialized a preset keyword wrote the keyword table, rebuilt the chips,
--destroyed the focused chip, and left focus nil - so exactly one stroke
--landed and every later one silently did nothing. contentPanel lives as
--long as the panel does, and gui.ChildHasFocus counts the element itself.
local function TakeMarkupFocus()
    local contentPanel = m.markupHud
    if contentPanel ~= nil and contentPanel.valid then
        gui.SetFocus(contentPanel)
    end

    local toolPanel = nil
    local modeRecord = m.modePanels ~= nil and m.modePanels[m.mode] or nil
    if modeRecord ~= nil then
        toolPanel = modeRecord.toolPanel
    end

    --must run after SetFocus: the think handlers gate on panel focus.
    if toolPanel ~= nil and toolPanel.valid then
        toolPanel:FireEvent("think")
    end
end

CreateMarkupEditor = function()
    local contentPanel

    --Horizontal strip of mode tabs across the top of the panel. On a map
    --added from a map pack a share icon sits to the right of the tabs
    --(the tabs yield a little width for it); see m.ShowMarkupShareDialog.
    local modeTabs = gui.Panel{
        classes = {"tabBar"},
        width = "98%",
        height = 26,
        halign = "center",
        vmargin = 4,
        flow = "horizontal",

        --the share icon only exists on pack maps; poll the map since the
        --panel can outlive any number of map switches.
        thinkTime = 0.5,
        think = function(element)
            local map = game.currentMap
            local fromPack = map ~= nil and map.packSource ~= nil
            if element.data.fromPack == fromPack then
                return
            end
            element.data.fromPack = fromPack
            for _,child in ipairs(element.children) do
                if child.data.modeid == "share" then
                    child:SetClass("hidden", not fromPack)
                else
                    child.width = cond(fromPack, K.TAB_WIDTH_WITH_SHARE, K.TAB_WIDTH)
                end
            end
        end,
        data = {
            fromPack = false,
        },

        children = (function()
            local result = {}
            for _,modeInfo in ipairs(K.MODES) do
                result[#result+1] = gui.Label{
                    classes = {"tab", cond(modeInfo.id == m.mode, "selected")},
                    text = modeInfo.text,
                    --The theme's tab sizing (130x40 / 18pt) is for full-width
                    --tab strips; five tabs must fit in the dock width.
                    width = K.TAB_WIDTH,
                    height = "100%",
                    fontSize = 13,
                    hpad = 0,
                    data = {
                        modeid = modeInfo.id,
                        modetext = modeInfo.text,
                    },
                    press = function(element)
                        m.mode = element.data.modeid
                        for _,tab in ipairs(element.parent.children) do
                            tab:SetClass("selected", tab.data.modeid == m.mode)
                        end
                        element.parent:FireEventTree("refreshtab")
                        contentPanel:FireEventTree("markupmode")
                        --arm the new mode's tool right away: switching tabs is
                        --a deliberate "I want to draw this" click.
                        TakeMarkupFocus()
                    end,

                    --Armed-state dot on the active tab: bright while the panel
                    --holds GUI focus (every drawing path is focus-gated, so
                    --focus IS "clicks on the map will draw"), dim otherwise.
                    --Driven by contentPanel's childfocus/childdefocus, which
                    --already fire to highlight the dock title.
                    gui.Panel{
                        classes = {"markupStateDot", cond(modeInfo.id ~= m.mode, "hidden")},
                        floating = true,
                        bgimage = "game-icons/plain-circle.png",
                        width = 6,
                        height = 6,
                        halign = "right",
                        valign = "center",
                        hmargin = 5,

                        refreshtab = function(element)
                            element:SetClass("hidden", element.parent.data.modeid ~= m.mode)
                        end,

                        markuparmed = function(element, armed)
                            element:SetClass("armed", armed)
                        end,
                    },
                }
            end

            --share-markup icon: hidden until the think above finds a pack map.
            result[#result+1] = gui.Panel{
                classes = {"iconButton", "hidden"},
                bgimage = "phosphor/share-network-fill.png",
                width = 20,
                height = 20,
                halign = "right",
                valign = "center",
                hmargin = 4,
                data = {
                    modeid = "share",
                },
                press = function(element)
                    m.ShowMarkupShareDialog(element)
                end,
                hover = gui.Tooltip("Share the markup you have added to this map with everyone who adds it from its map pack."),
            }
            return result
        end)(),
    }

    --One record per tab from its builder ({panel, toolPanel, prime}); built
    --in tab order, which is also the order they appear in the panel.
    local modes = {}
    local modeOrder = {"walls", "zones", "surfaces", "elevation", "props"}
    modes.walls = MM.BuildWallsMode()
    modes.zones = MM.BuildZonesMode()
    modes.surfaces = MM.BuildFootstepsMode()
    modes.elevation = MM.BuildElevationMode()
    modes.props = MM.BuildPropsMode()

    --Placeholder for the modes that are not implemented yet.
    local placeholderPanel = gui.Label{
        classes = {"fgMuted", cond(m.mode == "walls" or m.mode == "zones" or m.mode == "surfaces" or m.mode == "elevation" or m.mode == "props", "collapsed")},
        text = "",
        width = "90%",
        height = "auto",
        halign = "center",
        vmargin = 16,
        textAlignment = "center",

        markupmode = function(element)
            local implemented = m.mode == "walls" or m.mode == "zones" or m.mode == "surfaces" or m.mode == "elevation" or m.mode == "props"
            element:SetClass("collapsed", implemented)
            if not implemented then
                local modeName = m.mode
                for _,modeInfo in ipairs(K.MODES) do
                    if modeInfo.id == m.mode then
                        modeName = modeInfo.text
                    end
                end
                element.text = string.format("The %s mode is not implemented yet.", modeName)
            end
        end,
    }

    --The old "Show Map Overlay" checkbox lived here; the overlay is now split
    --into per-layer settings (mapoverlay:walls / elevation / terrain plus
    --per-zone-type toggles) managed from the title bar's map overlay menu and
    --the Settings screen. The panel needs no toggle of its own any more: an
    --open markup tab force-renders its own readout regardless of those
    --settings (walls + solid interiors on Walls, zones on Zones, contours +
    --height numbers on Elevation; see dmhub.GetMarkupZones).
    --
    --The Fade Map slider stays: it is live in every mode (fading the art
    --helps just as much when placing props).
    local overlayPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        --stacked: the default horizontal settings row gives its label width "60%",
        --which in a dock this narrow leaves the 160px slider hanging off the right
        --edge - the top of its range was literally unreachable. Stacked puts the
        --label on its own line and the slider below it, fully in view.
        CreateSettingsEditor("markup:fade", {stacked = true}),
    }

    --(ReassertMarkupFocus lived here. It existed for one reason: presses that
    --wrote the SHARED building-tool settings made the Building editor's
    --palette re-press and refocus its own chip on the next polled monitor
    --pass, one frame after our own TakeMarkupFocus -- and because focus WAS
    --the armed state, that steal silently stopped wall drawing until the user
    --clicked a wall type again. It scheduled a re-grab 0.1s later to paper
    --over the race.
    --
    --Arming is explicit now and a focus steal changes nothing, so the race has
    --no consequence to paper over and the workaround is gone.)

    contentPanel = gui.Panel{
        id = "MapMarkupPanel",
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = GetPanelStyles(),

        --The host (dock container or rail window) fires this on a
        --user-initiated OPEN of the panel and when a press lands anywhere
        --on the panel that its own controls did not handle -- the
        --background, the title bar. It has already put focus on this
        --element. Opening or clicking the panel is asking to use it, so it
        --ARMS (agreed 2026-08-15: the explicit-arming rework first shipped
        --arrive-disarmed, walked back so opening arms like the other
        --map-mode panels; Escape and hiding still disarm, focus loss still
        --does not). TakeMarkupFocus additionally re-fires the current
        --mode's tool think, without which the very next click can land
        --before the 0.3s poll re-registers the map tool and silently do
        --nothing.
        panelFocused = function(element)
            m.arm.Set(true)
            TakeMarkupFocus()
        end,

        --ESCAPE, first refusal. The host window offers the press to its
        --active panel before closing itself (see DocumentSystem's escape
        --handler): while a tool is live, Escape means "put it down", and
        --claiming the press is what stops the same keystroke also closing
        --the window. Disarmed, we do not claim it and Escape closes as
        --usual.
        --
        --This is the path that actually runs for rail windows. The
        --dmhub.CancelEditing chain in MapMarkupHooks.lua is a DIFFERENT route (sticky
        --map focus) and never sees the press while the window has it.
        panelEscape = function(element, claim)
            if not m.arm.Armed() then
                return
            end
            m.arm.Set(false)
            --give up focus with the tool: both hosts skip the panelFocused
            --nudge while focus is already here (ClaimTabFocus /
            --FocusPanelContent guard on it), so keeping focus would mean
            --the next click on the panel does NOT re-arm. Dropping it also
            --puts the host's focus highlight out, which is the visible
            --"tool down".
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
            if claim ~= nil then
                claim.claimed = true
            end
        end,

        --openness is NOT tracked from these events -- MarkupPanelIsOpen reads
        --it from the live panel (see its comment); these manage focus and
        --arming. Showing the panel ARMS it: switching to this panel is
        --asking to draw, matching the other map-mode panels (agreed
        --2026-08-15 -- the explicit-arming rework first shipped
        --arrive-disarmed and it was walked back). The rest of explicit
        --arming stands: Escape and hiding disarm, focus loss does not.
        showpanel = function(element)
            m.arm.Set(true)
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        --Hiding it DOES disarm: a tool you cannot see must not keep eating
        --map clicks.
        hidepanel = function(element)
            m.arm.Set(false)
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end,

        --The dockablePanel ancestor can be nil: content can be hosted outside
        --the dock (PanelDocument bridge), and focus events can fire while the
        --panel is detached. Guard like Objects.lua does.
        --
        --These now only drive the host's focus HIGHLIGHT. They no longer
        --touch `markuparmed`: focus is not the armed state any more, so a
        --focus steal must not put the armed dot out while the tool is still
        --live. m.arm.Set owns that event.
        childfocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", true)
            end
        end,

        childdefocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", false)
            end
        end,

        children = {
            modeTabs,
            modes.walls.panel,
            modes.zones.panel,
            modes.surfaces.panel,
            modes.elevation.panel,
            modes.props.panel,
            placeholderPanel,
            overlayPanel,
        },
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if contentPanel ~= nil and contentPanel.valid then
            contentPanel.styles = GetPanelStyles()
        end
    end)

    --NOTE: openness is not flagged here. A saved dock layout builds this
    --content at startup without showing it; MarkupPanelIsOpen derives
    --visibility from the live panel's ancestor chain.
    m.markupHud = contentPanel
    m.modePanels = modes

    for _,modeid in ipairs(modeOrder) do
        if modes[modeid].prime ~= nil then
            modes[modeid].prime()
        end
    end
    contentPanel:FireEventTree("markupmode")

    --Prime the armed dot and the tool strip from the CURRENT arm state.
    --m.arm.Set only fires markuparmed on a transition, and arm state is
    --module state that outlives any one panel instance, so a panel rebuilt
    --while already armed came up with a dot that said "disarmed" and a tool
    --strip that said "nothing here is live" - the exact lie explicit arming
    --exists to remove, and the reason this panel reads as broken when it is
    --actually working.
    contentPanel:FireEventTree("markuparmed", m.arm.Armed())
    contentPanel:FireEventTree("refreshtools")

    return contentPanel
end

--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.ActiveToolInfos = ActiveToolInfos
MM.ClearDeleteHighlight = ClearDeleteHighlight
MM.DeleteSegmentGeometry = DeleteSegmentGeometry
MM.DistancePointToSegment = DistancePointToSegment
MM.FindDoorAtPoint = FindDoorAtPoint
MM.FindNearestDeleteSegment = FindNearestDeleteSegment
MM.FindToolInfo = FindToolInfo
MM.FootstepToolById = FootstepToolById
MM.GetPanelStyles = GetPanelStyles
MM.MarkupChipStyles = MarkupChipStyles
MM.SectionHeader = SectionHeader
MM.ShowDeleteHighlight = ShowDeleteHighlight
MM.SideTooltip = SideTooltip
MM.TakeMarkupFocus = TakeMarkupFocus
MM.ZoneToolById = ZoneToolById
