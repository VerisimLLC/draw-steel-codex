local mod = dmhub.GetModLoading()

--Tabletop view. The screen shows a table, and maps live in
--windows on it that can be moved, resized, maximized and closed, instead of
--one map filling the screen. The engine still has a single current map, so
--only one window is live: the focused one, when its map is the current map.
--Every other window shows a frozen, greyed snapshot of what it last showed;
--clicking it travels to its map, which freezes the window that was live.
--
--Engine side: dmhub.tabletopMode, the "#MapView" and "#MapSnapshot:<mapid>"
--bgimages, and MapViewport.cs. Design, decisions and the to-do list are in
--TABLETOP_MAP_WINDOWS.md at the dmhub repo root.
--
--It is how every game is shown; only the lobby (title screen) keeps the
--engine's full-screen map.

if rawget(_G, "Tabletop") == nil then
    Tabletop = {}
end
--Kinds of table item other modules add (see DefineTableItems). A module that
--loads first creates the table itself.
Tabletop.itemKinds = Tabletop.itemKinds or {}

--This user's window layout for this game, as JSON (see SaveLayout).
local g_layoutSetting = setting{
    id = "tabletop:layout",
    storage = "pergamepreference",
    default = "",
}

--The built-in surfaces. One with `dice` (a dice-set asset id) matches that
--premium dice set and is offered only to accounts that own it.
local TABLE_SURFACES = {
    {id = "leather", text = "Leather"},
    {id = "felt", text = "Felt"},
    {id = "stars", text = "Sea of Stars", dice = "8a2a0ab2-d9e2-4ee4-a215-a480033ef6a6"},
    {id = "marble", text = "Marble"},
    {id = "darkmarble", text = "Dark Marble"},
    {id = "llianar", text = "Llianar", dice = "c9606a08-22a6-49f0-ab2e-3d137ed7c874"},
    {id = "soulkiller", text = "Soulkiller", dice = "28c8efb2-81d9-416a-996a-436f8b09e840"},
    {id = "terransteel", text = "Terran Steel", dice = "67dcc6a6-e39c-4e36-8f12-67be4b6b51c2"},
    {id = "zodiakol", text = "Zodiakol", dice = "a1dd7e1a-585e-4203-9fb1-bb3477da32ce"},
}

--Whether this account may use a surface: true unless it comes with a dice set
--the account doesn't own. Admin accounts get every one (David, 2026-10-16). dice.GetAvailableDice walks the account's shop
--inventory, and SyncSurface asks every frame, so a set once seen owned is
--remembered, and while one isn't the inventory is asked again at most every
--few seconds (it loads after the game opens, and a purchase adds to it). In a
--table, not locals: this file is at Lua's 200-local limit.
TABLE_SURFACES.owned = {}
TABLE_SURFACES.Offered = function(surface)
    local assetid = surface.dice
    if assetid == nil or TABLE_SURFACES.owned[assetid] or dmhub.isAdminAccount then
        return true
    end
    local now = dmhub.Time()
    if TABLE_SURFACES.checkedAt ~= nil and now - TABLE_SURFACES.checkedAt < 5 then
        return false
    end
    TABLE_SURFACES.checkedAt = now
    for _, entry in ipairs(dice.GetAvailableDice()) do
        if entry.value ~= nil then
            TABLE_SURFACES.owned[entry.value] = true
        end
    end
    return TABLE_SURFACES.owned[assetid] == true
end

local g_surfaceImageSetting = setting{
    id = "tabletop:surfaceimage",
    storage = "preference",
    default = "",
}

--The table's surface: one of the built-in surfaces, or "custom" for an
--image (g_surfaceImageSetting). Personal, like the rest of the table. The
--engine draws it (dmhub.tabletopSurface / dmhub.tabletopSurfaceImage); the
--tabletop's think syncs it every frame, so a change from the settings screen
--takes effect at once. Also chosen from the table's right-click menu, which
--is where a custom image is picked: the dropdown offers "Table Image" only
--once one has been chosen there.
local g_surfaceSetting = setting{
    id = "tabletop:surface",
    description = "Table Background",
    help = "What the table behind the map windows looks like.",
    storage = "preference",
    editor = "dropdown",
    default = "leather",
    enumCalc = function()
        local result = {}
        local function Add(surfaces)
            for _, surface in ipairs(surfaces) do
                if TABLE_SURFACES.Offered(surface) then
                    result[#result+1] = {value = surface.id, text = surface.text}
                end
            end
        end
        Add(TABLE_SURFACES)
        if dmhub.GetSettingValue("tabletop:surfaceimage") ~= "" then
            result[#result+1] = {value = "custom", text = "Table Image"}
        end
        return result
    end,
}

local TITLE_HEIGHT = 30
local MIN_WIDTH = 360
local MIN_HEIGHT = 240

--Window records, in creation order. Each is
--{id, mapid, x, y, width, height, maximized} plus its live panel parts
--(panel, liveBody, frozenBody, ...), which are rebuilt with each GameHud.
local g_windows = {}

--The window the user last chose. It shows the live map once its map is the
--current map.
local g_focusedId = nil

--The window showing the live map right now. It changes only when the
--current map changes (or a window showing the current map is focused), so
--the old window stays live until the engine has frozen it on leaving.
local g_liveId = nil

--Set when a map is opened into a window before travelling there:
--{mapid, windowId} -- that window takes the map when we arrive.
local g_pendingAdopt = nil

--The current map last seen, to notice the engine changing it.
local g_lastMapId = nil

--The game the records belong to.
local g_gameid = nil

local g_layer = nil
--The strip under the app title bar that a maximized map or scene window's
--titlebar moves into (see "The maximized window's strip" below): {layer,
--strip, leadSlot, controlsSlot, owner}. A table, not locals: this file is at
--Lua's 200-local limit.
local g_chrome = {}

--The overlay the map HUD was last placed in (Refresh).
local g_lastHudHost = nil

--True in a real game, where the table is up. False at the title screen and
--in the lobby game, whose hud has no table.
function Tabletop.IsActive()
    return dmhub.inGame and not dmhub.isLobbyGame
end

--The id of the window showing the live map, or nil.
function Tabletop.LiveWindowId()
    return g_liveId
end

--- How the live map window is on screen, for the map rail (MapRail in
--- DocumentSystem.lua): "maximized", "window", or nil when there is no
--- live map window on screen (none open, or it is minimized).
--- @return nil|"maximized"|"window"
function Tabletop.LiveWindowState()
    if not Tabletop.IsActive() then
        return nil
    end
    for _, rec in ipairs(g_windows) do
        if rec.id == g_liveId then
            if rec.minimized then
                return nil
            end
            return cond(rec.maximized == true, "maximized", "window")
        end
    end
    return nil
end

local function WindowById(id)
    if id == nil then
        return nil
    end
    for _,rec in ipairs(g_windows) do
        if rec.id == id then
            return rec
        end
    end
    return nil
end

local function WindowForMap(mapid)
    for _,rec in ipairs(g_windows) do
        if rec.mapid == mapid then
            return rec
        end
    end
    return nil
end

local function MapName(mapid)
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return "(missing map)"
    end
    local name = map.description
    if type(name) ~= "string" or name == "" then
        return "(unnamed map)"
    end
    return name
end

local function DocumentsLayer()
    local hud = GameHud.instance
    if not hud then
        return nil
    end
    local layer = hud.documentsPanel
    if layer == nil or not layer.valid then
        return nil
    end
    return layer
end

----------------------------------------------------------------------
--Saving the layout (per user, per game, on this machine).

local g_saveScheduled = false

--Table state other parts of this file add to the saved layout: shares
--already seen (players), and NPC cards. Each is a function(out) that writes
--its own fields, and the matching loader reads them back.
local g_layoutWriters = {}

local function SaveLayout()
    local out = {windows = {}, focused = g_focusedId}
    for _,rec in ipairs(g_windows) do
        out.windows[#out.windows+1] = {
            id = rec.id,
            mapid = rec.mapid,
            x = rec.x,
            y = rec.y,
            width = rec.width,
            height = rec.height,
            maximized = rec.maximized == true,
            minimized = rec.minimized == true,
            iconX = rec.iconX,
            iconY = rec.iconY,
            card = rec.card == true or nil,
        }
    end
    for _, writer in ipairs(g_layoutWriters) do
        writer(out)
    end
    g_layoutSetting:Set(dmhub.ToJson(out))
end

local function SaveSoon()
    if g_saveScheduled then
        return
    end
    g_saveScheduled = true
    dmhub.Schedule(0.5, function()
        g_saveScheduled = false
        if mod.unloaded then
            return
        end
        SaveLayout()
    end)
end

local function LoadLayout()
    local text = g_layoutSetting:Get()
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local parsed = dmhub.FromJson(text)
    if parsed == nil or parsed.result == nil or type(parsed.result) ~= "table" then
        return nil
    end
    return parsed.result
end

----------------------------------------------------------------------
--Window placement, in the documents layer's units (its height is fixed;
--its width follows the screen's aspect).

--Before its first layout pass a new layer reports 100x100. Placing windows
--against that sent restored layouts to the top-left corner at a tiny size
--(and the next save kept them there), so an unlaid-out layer reads as the
--size it is about to be: 1080 units per screen height, below the title bar.
local function LayerSize()
    local layer = DocumentsLayer()
    if layer ~= nil and layer.renderedWidth > 100 and layer.renderedHeight > 100 then
        return layer.renderedWidth, layer.renderedHeight
    end
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if screen.y <= 0 or below.y <= 0 then
        return 1862, 1048
    end
    local h = 1080 * below.y / screen.y
    return h * below.x / below.y, h
end

--True once the documents layer has been laid out, so LayerSize is its real
--size. The saved layout is restored only after this (see Sync).
function Tabletop.LayerReady()
    local layer = DocumentsLayer()
    return layer ~= nil and layer.renderedWidth > 100 and layer.renderedHeight > 100
end

--Centred, stepping down-right past any window already sitting at a spot so
--a new window never lands exactly on top of another. width/height (optional)
--size the window; else it gets the usual new-window size.
local function DefaultPlacement(width, height)
    local w, h = LayerSize()
    width = width or math.floor(w * 0.62)
    height = height or math.floor(h * 0.68)
    local x0 = math.floor((w - width) / 2)
    local y0 = math.floor((h - height) / 2)
    for step = 0, 11 do
        local x = x0 + 28 * (step % 6)
        local y = y0 + 28 * (step % 6)
        local taken = false
        for _,rec in ipairs(g_windows) do
            if math.abs(rec.x - x) < 8 and math.abs(rec.y - y) < 8 then
                taken = true
                break
            end
        end
        if not taken then
            return x, y, width, height
        end
    end
    return x0, y0, width, height
end

--How much of a window must stay on the table: enough titlebar to grab.
local KEEP_ON_TABLE = 120

--Keeps a window's titlebar on the table: it may hang off the left, right
--and bottom edges, but never so far that it cannot be dragged back.
local function ClampWindow(rec, x, y)
    local w, h = LayerSize()
    x = math.max(KEEP_ON_TABLE - rec.width, math.min(x, w - KEEP_ON_TABLE))
    y = math.max(0, math.min(y, h - TITLE_HEIGHT))
    return x, y
end

--Distance within which a dropped window snaps to an edge.
local SNAP = 14

--Where a window dropped at (x, y) lands: snapped flush to the table's
--edges or to another window's edges (side by side, or aligned) when it
--is close, then kept on the table.
local function SnapWindow(rec, x, y)
    local w, h = LayerSize()
    local xs = {0, w - rec.width}
    local ys = {0, h - rec.height}
    for _, other in ipairs(g_windows) do
        if other ~= rec and not other.maximized and not other.minimized then
            xs[#xs+1] = other.x
            xs[#xs+1] = other.x + other.width
            xs[#xs+1] = other.x - rec.width
            xs[#xs+1] = other.x + other.width - rec.width
            ys[#ys+1] = other.y
            ys[#ys+1] = other.y + other.height
            ys[#ys+1] = other.y - rec.height
            ys[#ys+1] = other.y + other.height - rec.height
        end
    end
    local function nearest(value, candidates)
        local best, bestDist = value, SNAP + 1
        for _, c in ipairs(candidates) do
            local d = math.abs(c - value)
            if d < bestDist then
                best, bestDist = c, d
            end
        end
        return best
    end
    return ClampWindow(rec, nearest(x, xs), nearest(y, ys))
end

local function NewWindowRecord(mapid)
    local x, y, width, height = DefaultPlacement()
    return {
        id = dmhub.GenerateGuid(),
        mapid = mapid,
        x = x,
        y = y,
        width = width,
        height = height,
        maximized = false,
    }
end

----------------------------------------------------------------------
--Building windows.

local Refresh
local Focus
local CloseWindow
local ToggleMaximize
local Minimize
local RestoreWindow
local RequestClose
local ShareControl
local UpdateShare
--Share stores and the player's viewable-map tracking (one table: this file
--is at Lua's 200-local limit). See the Sharing section.
local g_sharing = {}
--The Director's Screen (DirectorScreen.lua) sees the table items through
--these: each kind of shareable item adds a function(list) that appends a
--DirectorScreenItem for each of its items (see Tabletop.ScreenItems).
g_sharing.screenKinds = {}
--The screen's key for a map or scene window (its button stands for it), or
--nil for a window this file does not own (rec.railKey).
g_sharing.ScreenKey = function(rec)
    if rec.railKey ~= nil then
        return nil
    end
    if rec.sceneid ~= nil then
        return "scene:" .. rec.id
    end
    return "map:" .. rec.id
end
--The Director's placement reaches the players (DefineDirectorLayout): each
--kind of shareable item adds a function(list) that appends a LayoutItem
--{key, followed, get, set} for each of its items, keyed the same on every
--table ("map:<mapid>", "scene:<sceneid>", "card:<charid>", "doc:<entryid>").
g_sharing.layoutKinds = {}
--The layout key of a map or scene window, or nil for one this file does not
--own. Unlike ScreenKey it names what the window shows, not the window.
g_sharing.LayoutKey = function(rec)
    if rec.railKey ~= nil then
        return nil
    end
    if rec.sceneid ~= nil then
        return "scene:" .. rec.sceneid
    end
    return "map:" .. rec.mapid
end
local IsShared
local IsForcedHere
local ShowPreviewTooltip
local IsOpen
local Travel
--The map a travel was last started to, so a second click while it loads
--does not start another (cleared when the current map changes).
local g_travelTarget = nil
local SyncShares
local SyncCards
local TeardownCards
local SyncDocItems
local TeardownDocItems
local LoadDocItems
--Load, Sync and Teardown for items of other modules' kinds (DefineTableItems).
local g_tableItems = {}
local SyncSurface
local SyncSceneWindows
local TeardownSceneWindows
local LoadSceneWindows
local UnmaximizeScenes

--The rail layout key of a window docked to the icon rail (RailEntryTypes):
--"mapwindow:<id>", or "scenewindow:<id>" for a scene window. A window this
--file does not own names its own key (rec.railKey, see MinimizeExternal).
local function RailKey(rec)
    if rec.railKey ~= nil then
        return rec.railKey
    end
    if rec.sceneid ~= nil then
        return "scenewindow:" .. rec.id
    end
    return "mapwindow:" .. rec.id
end

--Docked on a rail that is actually showing (with the rail off, a docked
--window's button goes back on the table).
local function IsDocked(rec)
    return RailModeActive() and IconRailKeySlot(RailKey(rec)) ~= nil
end

--A caption control in the native style of the app's title bar: a
--full-height hover zone with a centred window-chrome glyph (see
--CodexTitleBar's CreateWindowControl). args: icon, click, rightClick, hover,
--danger, width, iconSize, flip (draw the glyph upside down), iconChildren
--(panels drawn over the glyph).
--When a caption control or one of this file's menu entries last acted. The
--same click can also reach a window under it -- a context menu's items take
--no clicks themselves, so the press and release land on whatever is below --
--and a window's click focuses (and travels to) its map, a control's click
--minimizes or closes. Windows and controls ignore clicks for a moment after.
local g_controlClickTime = -1

local function GuardClicks()
    g_controlClickTime = dmhub.Time()
end

local function ClicksGuarded()
    return dmhub.Time() - g_controlClickTime < 0.6
end

--A context-menu entry that guards the windows under the menu (see above).
local function GuardedEntry(text, action)
    return {
        text = text,
        click = function()
            GuardClicks()
            action()
        end,
    }
end

local function WindowControl(args)
    local click = args.click
    local classes = {"tabletopControl"}
    local iconClasses = {"tabletopControlIcon"}
    if args.danger then
        classes[#classes+1] = "tabletopControlDanger"
        iconClasses[#iconClasses+1] = "tabletopControlIconDanger"
    end
    return gui.Panel{
        classes = classes,
        bgimage = true,
        width = args.width or 36,
        height = "100%",
        valign = "center",
        --passPress: the press (and hover) reach the panel around the control,
        --so a card's titlebar stays shown, and drags the card.
        swallowPress = args.passPress ~= true,
        hover = args.hover,
        rightClick = args.rightClick,
        click = function(element)
            if ClicksGuarded() then
                return
            end
            GuardClicks()
            if click ~= nil then
                click(element)
            end
        end,
        gui.Panel{
            classes = iconClasses,
            bgimage = args.icon,
            width = args.iconSize or 14,
            height = args.iconSize or 14,
            halign = "center",
            valign = "center",
            scale = cond(args.flip, {x = 1, y = -1}, {x = 1, y = 1}),
            interactable = false,
            setIcon = function(element, icon)
                element.bgimage = icon
            end,
            children = args.iconChildren,
        },
    }
end

--The floor stepper in the live window's titlebar: the floor being viewed,
--with the floor-down/up keybinds' action on either side (a player looks
--up through the floors above their token instead). Shown only when the
--map has more than one floor.
local function TopLevelFloorCount()
    local map = game.currentMap
    if map == nil then
        return 0
    end
    local count = 0
    for _, f in ipairs(map.floors or {}) do
        if f.parentFloor == nil then
            count = count + 1
        end
    end
    return count
end

local function CurrentFloorName()
    local floor = game.currentFloor
    if floor == nil then
        return ""
    end
    if floor.parentFloor ~= nil then
        local parent = game.GetFloor(floor.parentFloor)
        if parent ~= nil then
            floor = parent
        end
    end
    local name = floor.description
    if type(name) ~= "string" or name == "" then
        return "Floor"
    end
    return name
end

local function BuildFloorControl(rec)
    local label = gui.Label{
        classes = {"tabletopFloorText"},
        width = "auto",
        maxWidth = 140,
        height = "100%",
        valign = "center",
        hmargin = 2,
        textWrap = false,
        textOverflow = "ellipsis",
        text = "",
    }
    return gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        --fired by the titlebar's name row (a collapsed panel does not think,
        --so this one cannot poll for itself).
        updateFloor = function(element)
            local show = rec.id == Tabletop.LiveWindowId() and TopLevelFloorCount() > 1
            element:SetClass("collapsed", not show)
            if show then
                local text = CurrentFloorName()
                if label.text ~= text then
                    label.text = text
                end
            end
        end,
        g_chrome.Sep(),
        WindowControl{
            icon = "phosphor/caret-down-fill.png",
            width = 22,
            iconSize = 11,
            hover = gui.Tooltip("Floor down"),
            click = function()
                FloorNavigation.ChangeFloorRelative(-1)
            end,
        },
        label,
        WindowControl{
            icon = "phosphor/caret-down-fill.png",
            flip = true,
            width = 22,
            iconSize = 11,
            hover = gui.Tooltip("Floor up"),
            click = function()
                FloorNavigation.ChangeFloorRelative(1)
            end,
        },
    }
end

--A maximized window keeps its place: focusing it from the Maps panel, a
--journal link or a map change must not bury the window being used (David,
--2026-10-25). g_chrome.StackMaximized says what does raise it.
local function BringToFront(rec)
    if rec.maximized then
        return
    end
    if rec.panel ~= nil and rec.panel.valid then
        rec.panel:SetAsLastSibling()
    end
end

--The engine moved us to a map that was already open in a window (a token
--travelled there, a journal link...): bring it out from behind the screen.
local function Highlight(rec)
    local panel = rec.panel
    if panel == nil or not panel.valid then
        return
    end
    DirectorScreen.Reveal(g_sharing.ScreenKey(rec))
end

--A panel's styles reach every panel below it, so the window's styles are
--split by where they are needed. The live body hosts the map's HUD (the
--initiative bar), which must lay out exactly as it does over the full-screen
--map, so the theme goes on the titlebar and the frozen body, never on an
--ancestor of the live body.

--The soft shadows windows and table items cast (the boxShadow style), falling
--down-right because the table's logo is lit from the upper left. A dragged
--one is lifted: its shadow grows, softens, darkens and falls further away.
local TABLE_SHADOWS = {
    rest = {x = 5, y = 9, blur = 24, spread = 5, color = "#000000f2"},
    lifted = {x = 15, y = 28, blur = 56, spread = 8, color = "#000000ff"},
}
--journal and panel windows (DocumentSystem.lua) cast the same shadows.
Tabletop.shadows = TABLE_SHADOWS

--The window frame itself. Selector-only, so nothing in the body matches.
local g_windowStyles = {
    {
        selectors = {"tabletopWindow"},
        bgcolor = "#100d0bff",
        borderWidth = 2,
        borderColor = "#00000099",
        boxShadow = TABLE_SHADOWS.rest,
    },
    --"dragging" is set by the engine while the window is dragged.
    {
        selectors = {"tabletopWindow", "dragging"},
        boxShadow = TABLE_SHADOWS.lifted,
        transitionTime = 0.15,
    },
    --a maximized window fills the table: nothing to cast a shadow on.
    {
        selectors = {"tabletopWindow", "tabletopMaximized"},
        boxShadow = false,
    },
}

--Titlebars and the strip follow the colour scheme: the bar is the scheme's
--nested surface, its text the fg ladder (g_chrome.Themed re-applies these
--when the scheme changes). The caption controls keep the app title bar's
--neutral OS-furniture colours, as CodexTitleBar's own do.
local g_titleStyles = {
    {
        selectors = {"tabletopTitle"},
        bgcolor = "@bgAlt",
    },
    {
        selectors = {"tabletopTitleText"},
        color = "@fg",
        fontSize = 14,
    },
    --the window's name, and the quieter details after it (a frozen map's
    --round, the live map's floor and position).
    {
        selectors = {"tabletopTitleName"},
        color = "@fgStrong",
        fontSize = 14,
        bold = true,
    },
    {
        selectors = {"tabletopTitleDetail"},
        color = "@fgMuted",
        fontSize = 13,
    },
    --a hairline between the groups of a titlebar.
    {
        selectors = {"tabletopTitleSep"},
        bgcolor = "@border",
    },
    --the maximized window's strip: the titlebar's look, slightly see-through
    --over the map, with an accent hairline along its foot. The see-through
    --and the fades are white alpha masks on the panels (g_chrome.AlphaMask),
    --tinted by these colours.
    {
        selectors = {"tabletopStripBody"},
        bgcolor = "@bgAlt",
    },
    {
        selectors = {"tabletopStripFade"},
        bgcolor = "@bgAlt",
    },
    {
        selectors = {"tabletopStripLine"},
        bgcolor = "@accent",
    },
    --caption controls, in the native style of the app's own title bar
    --(CodexTitleBar's CreateWindowControl and its titleBarStyleExtras).
    {
        selectors = {"tabletopControl"},
        bgcolor = "clear",
    },
    {
        selectors = {"tabletopControl", "hover"},
        bgcolor = "#ffffff1f",
    },
    {
        selectors = {"tabletopControl", "press"},
        bgcolor = "#ffffff33",
    },
    {
        selectors = {"tabletopControlDanger", "hover"},
        bgcolor = "#c42b1c",
    },
    {
        selectors = {"tabletopControlDanger", "press"},
        bgcolor = "#b3271a",
    },
    {
        selectors = {"tabletopControlIcon"},
        bgcolor = "#d4d4d4",
    },
    {
        selectors = {"tabletopControlIconDanger", "parent:hover"},
        bgcolor = "#ffffff",
    },
    {
        selectors = {"tabletopControl", "tabletopControlDisabled"},
        bgcolor = "clear",
    },
    {
        selectors = {"tabletopControlIcon", "parent:tabletopControlDisabled"},
        opacity = 0.35,
    },
    --the Director's share toggle: lit while the item is shared with every
    --player, only its top half lit while shared with some of them.
    {
        selectors = {"tabletopControlIcon", "parent:tabletopShared"},
        bgcolor = "@share",
    },
    {
        selectors = {"tabletopShareHalf"},
        bgcolor = "@share",
    },
    {
        selectors = {"tabletopFloorText"},
        color = "@fg",
        fontSize = 12,
    },
    --a frozen window's map is in combat.
    {
        selectors = {"tabletopCombatBadge"},
        bgcolor = "@danger",
    },
    --the live window is seen through tokens' eyes (g_chrome.VisionChip).
    {
        selectors = {"tabletopVisionChip"},
        bgcolor = "@bg",
        borderColor = "@accent",
        borderWidth = 1,
        cornerRadius = 4,
    },
    {
        selectors = {"tabletopVisionText"},
        color = "@fgStrong",
        fontSize = 12,
    },
}

local g_frozenStyles = {
    --the snapshot of the map as this window last showed it, drawn as it is:
    --a window that is not live looks just like the live one.
    --(the snapshot itself is a child panel, g_chrome.ShowImage; this is what
    --shows through its transparent parts, the window's colour as when live.)
    {
        selectors = {"tabletopFrozen"},
        bgcolor = "#100d0bff",
    },
    {
        selectors = {"tabletopFrozen", "tabletopPlaceholder"},
        bgcolor = "#1b1814ff",
    },
    {
        selectors = {"tabletopFrozen", "tabletopPlaceholder", "hover"},
        bgcolor = "#26221cff",
    },
    {
        selectors = {"tabletopFrozenHint"},
        color = "#e8e0d2",
        fontSize = 16,
        opacity = 0,
    },
    {
        selectors = {"tabletopFrozenHint", "parent:hover"},
        opacity = 1,
        transitionTime = 0.15,
    },
    --the window is waiting for its map's data (g_chrome.UpdateFrozenHint).
    {
        selectors = {"tabletopFrozenHint", "loading"},
        opacity = 1,
        transitionTime = 0.15,
    },
}

--Puts the engine's defaults back for everything in the map overlay. The
--documents layer the window lives in has a style with no selector (centred,
--100% x 100%), and a style with no selector applies to every panel below it.
--Over the full-screen map the HUD gets the engine defaults instead (top-left,
--100 x 100), and the closer ancestor's style wins, so this undoes the layer's.
local g_overlayStyles = {
    {
        valign = "top",
        halign = "left",
        width = 100,
        height = 100,
    },
}

----------------------------------------------------------------------
--Titlebars. Map and scene windows share one layout (David, 2026-10-15):
--the name, then the details (a map's floor, position and round; a scene's
--presentation), with the share and window controls at the right. Maximized,
--the same two rows move into the strip under the app title bar.

--The panels that root g_titleStyles (titlebars, the strip), given the
--styles again when the colour scheme changes. Pruned as they go.
g_chrome.themed = {}

--Restyles a panel built with styles = ThemeEngine.MergeStyles(g_titleStyles)
--whenever the colour scheme changes. Call it from the panel's create.
--- @param panel Panel
function g_chrome.Themed(panel)
    local list = {}
    for _, p in ipairs(g_chrome.themed) do
        if p ~= panel and p.valid then
            list[#list+1] = p
        end
    end
    list[#list+1] = panel
    g_chrome.themed = list
end

ThemeEngine.OnThemeChanged(mod, function()
    local list = {}
    for _, p in ipairs(g_chrome.themed) do
        if p.valid then
            list[#list+1] = p
            p.styles = ThemeEngine.MergeStyles(g_titleStyles)
            p:UpdateStyle()
        end
    end
    g_chrome.themed = list
end)

--A horizontal white fade for a panel's gradient: alpha only, so the panel's
--bgcolor (a themed colour, from its class) tints it.
--- @param stops {position: number, alpha: string}[] alpha as two hex digits
function g_chrome.AlphaMask(stops)
    local out = {}
    for _, stop in ipairs(stops) do
        out[#out+1] = {position = stop.position, color = "#ffffff" .. stop.alpha}
    end
    return gui.Gradient{
        type = "linear",
        point_a = {x = 0, y = 0},
        point_b = {x = 1, y = 0},
        stops = out,
    }
end

--The window's name in its titlebar.
function g_chrome.NameLabel(text)
    return gui.Label{
        classes = {"tabletopTitleName"},
        width = "auto",
        maxWidth = 320,
        height = "100%",
        valign = "center",
        hmargin = 8,
        textWrap = false,
        textOverflow = "ellipsis",
        text = text,
    }
end

--A hairline between a titlebar's groups.
function g_chrome.Sep()
    return gui.Panel{
        classes = {"tabletopTitleSep"},
        bgimage = "panels/square.png",
        width = 1,
        height = 16,
        valign = "center",
        hmargin = 8,
        interactable = false,
    }
end

--Vision Perspective: the Director seeing through tokens' eyes
--(dmhub.tokenVision, "Show Token Vision") or logged in as them
--(dmhub.tokensLoggedInAs). The live map window's titlebar shows their
--portraits and an X that ends it; VisionPerspective.lua keeps its old
--floating dialog only for when no map window is on screen.

--The chip for rec's titlebar; sets rec.visionChip. Filled and shown by
--g_chrome.RefreshVisionChip.
function g_chrome.VisionChip(rec)
    local portraits = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        lmargin = 3,
    }
    local label = gui.Label{
        classes = {"tabletopVisionText"},
        width = "auto",
        height = "100%",
        valign = "center",
        lmargin = 6,
        textWrap = false,
        text = "",
    }
    local close = WindowControl{
        width = 24,
        iconSize = 9,
        icon = "window-chrome/chrome-close.png",
        hover = gui.Tooltip("Return to your own view"),
        click = function(element)
            if dmhub.tokenVision ~= nil then
                dmhub.tokenVision = nil
            else
                dmhub.tokensLoggedInAs = nil
            end
        end,
    }
    close.escapePriority = EscapePriority.EXIT_DIALOG
    local chip = gui.Panel{
        classes = {"tabletopVisionChip", "collapsed"},
        bgimage = "panels/square.png",
        flow = "horizontal",
        width = "auto",
        height = 24,
        valign = "center",
        hmargin = 8,
        data = {key = nil, tip = nil},
        hover = function(element)
            if element.data.tip ~= nil then
                gui.Tooltip(element.data.tip)(element)
            end
        end,
        portraits,
        label,
        close,
    }
    rec.visionChip = chip
    rec.visionPortraits = portraits
    rec.visionLabel = label
    rec.visionClose = close
    return chip
end

--Shows rec's chip while its window is the live one on screen and a vision
--perspective is on; rebuilds the portraits only when the tokens change.
function g_chrome.RefreshVisionChip(rec)
    local chip = rec.visionChip
    if chip == nil or not chip.valid then
        return
    end
    local ids = dmhub.tokenVision
    local loggedIn = false
    if ids == nil then
        ids = dmhub.tokensLoggedInAs
        loggedIn = ids ~= nil
    end
    local tokens = {}
    if ids ~= nil and rec.id == g_liveId and not rec.minimized then
        for _, tokid in ipairs(ids) do
            local token = dmhub.GetTokenById(tokid)
            if token ~= nil then
                tokens[#tokens+1] = token
            end
        end
    end
    local shown = #tokens > 0
    local key = nil
    if shown then
        local parts = {cond(loggedIn, "as", "vision")}
        for _, token in ipairs(tokens) do
            parts[#parts+1] = token.charid
        end
        key = table.concat(parts, ",")
    end
    if chip.data.key == key then
        return
    end
    chip.data.key = key
    chip:SetClass("collapsed", not shown)
    --Escape ends a vision perspective, but not a log-in as players.
    rec.visionClose.escapeActivates = shown and not loggedIn
    if not shown then
        rec.visionPortraits.children = {}
        return
    end
    local children = {}
    for _, token in ipairs(tokens) do
        children[#children+1] = gui.CreateTokenImage(token, {
            width = 20,
            height = 20,
            valign = "center",
            hmargin = 1,
        })
    end
    rec.visionPortraits.children = children
    rec.visionLabel.text = cond(loggedIn, "Player Perspective", "Vision Perspective")
    chip.data.tip = cond(loggedIn, "You are logged in as though you were a player. Close this to return to being the Director.", nil)
end

--- Updates the live map window's Vision Perspective chip (VisionPerspective.lua
--- calls it when the token vision changes, and polls it while its fallback
--- dialog is up). True when a chip is showing, so the dialog is not needed.
--- @return boolean
function Tabletop.RefreshVision()
    local shown = false
    for _, rec in ipairs(g_windows) do
        g_chrome.RefreshVisionChip(rec)
        if rec.visionChip ~= nil and rec.visionChip.valid and rec.visionChip.data.key ~= nil then
            shown = true
        end
    end
    return shown
end

--Keeps a narrow window's titlebar out from under its controls. The name
--(rec.nameLabel) is cut short with an ellipsis down to 100 wide, then the
--live map's mouse position (rec.titlePosition) is dropped, then the name
--gives up the rest down to 40. In the maximized strip there is room for all.
function g_chrome.FitTitle(rec)
    local name, leadRow, controlsRow, bar = rec.nameLabel, rec.leadRow, rec.controlsRow, rec.titlebar
    if name == nil or not name.valid or leadRow == nil or not leadRow.valid or controlsRow == nil or not controlsRow.valid then
        return
    end
    local position = rec.titlePosition
    if position ~= nil and not position.valid then
        position = nil
    end
    local nameMax, showPosition = 320, true
    if leadRow.parent == rec.leadSlot and bar ~= nil and bar.valid then
        --the position only takes room while the live details show.
        local live = position ~= nil and rec.liveStatus ~= nil and rec.liveStatus.valid and not rec.liveStatus:HasClass("collapsed")
        local shownW = 0
        if live and position ~= nil and not position:HasClass("collapsed") then
            shownW = position.renderedWidth
            rec.titlePositionWidth = shownW
        end
        local positionW = rec.titlePositionWidth or 113
        --the row's width without the name and the position, which this sizes.
        local others = leadRow.renderedWidth - name.renderedWidth - shownW
        local room = bar.renderedWidth - controlsRow.renderedWidth - others - 8
        if live then
            if room - positionW < 100 then
                showPosition = false
            else
                room = room - positionW
            end
        end
        nameMax = math.max(40, math.min(320, math.floor(room)))
    end
    if rec.titleNameMax ~= nameMax then
        rec.titleNameMax = nameMax
        name.selfStyle.maxWidth = nameMax
    end
    if position ~= nil and position:HasClass("collapsed") == showPosition then
        position:SetClass("collapsed", not showPosition)
    end
end

--Builds a window's titlebar from its name-side panels (lead) and its
--controls. Each row sits in a slot, so it can move into the strip and back
--(g_chrome.Sync); sets rec.leadRow, rec.controlsRow, rec.leadSlot and
--rec.controlsSlot. leadThink, if given, runs twice a second wherever the
--row is. The row also fits itself to the titlebar (g_chrome.FitTitle)
--often enough to keep up with a resize.
function g_chrome.Titlebar(rec, lead, controls, leadThink)
    local nextLeadThink = 0
    --halign: the documents layer's selector-less style centres everything
    --under it that does not say otherwise.
    local leadRow = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        halign = "left",
        valign = "center",
        thinkTime = 0.1,
        think = function(element)
            g_chrome.FitTitle(rec)
            if leadThink ~= nil and dmhub.Time() >= nextLeadThink then
                nextLeadThink = dmhub.Time() + 0.5
                leadThink(element)
            end
        end,
        children = lead,
    }
    local controlsRow = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        children = controls,
    }
    rec.leadRow = leadRow
    rec.controlsRow = controlsRow
    rec.leadSlot = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        halign = "left",
        valign = "center",
        leadRow,
    }
    rec.controlsSlot = gui.Panel{
        floating = true,
        flow = "horizontal",
        width = "auto",
        height = "100%",
        halign = "right",
        controlsRow,
    }
    --the GameHud cascade carries no theme, so the themed controls up here
    --(the buttons, the position plate) get it from the titlebar.
    return gui.Panel{
        styles = ThemeEngine.MergeStyles(g_titleStyles),
        classes = {"tabletopTitle"},
        flow = "horizontal",
        width = "100%",
        height = TITLE_HEIGHT,
        bgimage = "panels/square.png",
        create = function(element)
            g_chrome.Themed(element)
        end,
        rec.leadSlot,
        rec.controlsSlot,
    }
end

--The maximized window's strip. A maximized map or scene window has no
--titlebar of its own: its name, details and controls move into a strip
--hung from the right of the app title bar, which fades out to the left over
--the map (David, 2026-10-15). It is chrome, like the title bar: it sits in
--its own layer over the whole hud (Tabletop.CreateChromeLayer), so it stays
--reachable over docks, dialogs and the full-screen display, and while the
--Director's scene shown to the Players alone is hidden here.

--- The layer for the maximized window's strip. GameHud puts it straight
--- after the over-the-UI full-screen display.
--- @return Panel
function Tabletop.CreateChromeLayer()
    g_chrome.leadSlot = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        lmargin = 2,
    }
    g_chrome.controlsSlot = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
    }
    g_chrome.owner = nil
    g_chrome.strip = gui.Panel{
        styles = ThemeEngine.MergeStyles(g_titleStyles),
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = TITLE_HEIGHT,
        halign = "right",
        valign = "top",
        create = function(element)
            g_chrome.Themed(element)
        end,
        --the fade: the strip's colour thinning out to nothing over the map.
        gui.Panel{
            classes = {"tabletopStripFade"},
            width = 110,
            height = "100%",
            bgimage = "panels/square.png",
            interactable = false,
            gradient = g_chrome.AlphaMask{
                {position = 0, alpha = "00"},
                {position = 1, alpha = "ee"},
            },
        },
        gui.Panel{
            classes = {"tabletopStripBody"},
            bgimage = "panels/square.png",
            flow = "horizontal",
            width = "auto",
            height = "100%",
            gradient = g_chrome.AlphaMask{
                {position = 0, alpha = "ee"},
                {position = 1, alpha = "ee"},
            },
            g_chrome.leadSlot,
            g_chrome.Sep(),
            g_chrome.controlsSlot,
        },
        --the accent hairline along the foot, fading in with the strip.
        gui.Panel{
            classes = {"tabletopStripLine"},
            floating = true,
            width = "100%",
            height = 1,
            valign = "bottom",
            bgimage = "panels/square.png",
            interactable = false,
            gradient = g_chrome.AlphaMask{
                {position = 0, alpha = "00"},
                {position = 0.3, alpha = "73"},
                {position = 1, alpha = "73"},
            },
        },
    }
    return gui.Panel{
        id = "tabletopChromeLayer",
        width = "100%",
        height = "100%",
        interactable = false,
        create = function(element)
            g_chrome.Sync()
        end,
        --opening or closing the sheet fires nothing here, so watch for it.
        thinkTime = 0.1,
        think = function(element)
            g_chrome.SyncShown()
        end,
        g_chrome.strip,
    }
end

--Moves a row into host, if it is not there.
function g_chrome.Move(row, host)
    if row == nil or not row.valid or host == nil or not host.valid then
        return
    end
    if row.parent ~= host then
        row:Unparent()
        host:AddChild(row)
    end
end

--The window whose titlebar is in the strip: a maximized scene window, else
--a maximized map window (one at a time; ToggleMaximize and
--ToggleSceneMaximize un-maximize the rest).
function g_chrome.Owner()
    local scene = g_chrome.maximizedScene ~= nil and g_chrome.maximizedScene() or nil
    if scene ~= nil and scene.panel ~= nil and scene.panel.valid then
        return scene
    end
    for _, rec in ipairs(g_windows) do
        if rec.maximized and not rec.minimized and rec.panel ~= nil and rec.panel.valid then
            return rec
        end
    end
    return nil
end

--- The maximized map or scene window's panel while it is on show among the
--- windows (not a scene under the UI at the bottom), else nil. It covers the
--- table, so the chat bubble treats it as a full-screen stage
--- (PanelDocument.FullscreenStage).
--- @return Panel|nil
function Tabletop.MaximizedWindowPanel()
    local rec = g_chrome.Owner()
    if rec == nil or rec.panel.parent ~= DocumentsLayer() or rec.panel:HasClass("collapsed") then
        return nil
    end
    return rec.panel
end

--A window leaving the strip: its rows go home to its titlebar, or are
--destroyed with it when its panel is gone.
function g_chrome.Return(rec)
    for _, pair in ipairs({{rec.leadRow, rec.leadSlot}, {rec.controlsRow, rec.controlsSlot}}) do
        local row, slot = pair[1], pair[2]
        if row ~= nil and row.valid then
            if slot ~= nil and slot.valid then
                g_chrome.Move(row, slot)
            elseif row.parent == g_chrome.leadSlot or row.parent == g_chrome.controlsSlot then
                row:DestroySelf()
            end
        end
    end
    if rec.onChrome ~= nil then
        rec.onChrome()
    end
end

--Puts the right window's titlebar in the strip, and shows the strip only
--while there is one. Called after every change to the windows, and on the
--layer's think.
function g_chrome.Sync()
    local strip = g_chrome.strip
    if strip == nil or not strip.valid then
        g_chrome.owner = nil
        return
    end
    local owner = g_chrome.Owner()
    local old = g_chrome.owner
    if old ~= nil and old ~= owner then
        g_chrome.Return(old)
    end
    g_chrome.owner = owner
    if owner ~= nil then
        g_chrome.Move(owner.leadRow, g_chrome.leadSlot)
        g_chrome.Move(owner.controlsRow, g_chrome.controlsSlot)
        if owner.onChrome ~= nil then
            owner.onChrome()
        end
    end
    g_chrome.SyncShown()
end

--The strip shows while a window owns it, except under the character sheet:
--the sheet lives in the main dialog layer, below this one, so the strip
--would cover its close button.
function g_chrome.SyncShown()
    local strip = g_chrome.strip
    if strip == nil or not strip.valid then
        return
    end
    local hide = g_chrome.owner == nil or dmhub.inCharacterSheet
    if strip:HasClass("collapsed") ~= hide then
        strip:SetClass("collapsed", hide)
    end
end

--A window being destroyed: rows of its that are in the strip go with it.
function g_chrome.Release(rec)
    if g_chrome.owner == rec then
        g_chrome.owner = nil
    end
    for _, row in ipairs({rec.leadRow, rec.controlsRow}) do
        if row ~= nil and row.valid and (row.parent == g_chrome.leadSlot or row.parent == g_chrome.controlsSlot) then
            row:DestroySelf()
        end
    end
end

--The map rail inside a window (MapRail in DocumentSystem.lua): map panels
--down the left edge, Map Settings and the map's own buttons down the right. Only on the
--live window, and not while it is maximized -- the buttons then join the
--screen rails. Rebuilt whenever MapRail.Signature changes. No bgimage, so
--between the columns it takes no mouse and the map gets it.
function g_chrome.MapRailHost(rec)
    return gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        flow = "none",
        data = { sig = nil },
        thinkTime = 0.25,
        think = function(element)
            element:FireEvent("syncMapRail")
        end,
        --also fired by ToggleMaximize, so restoring shows it at once.
        syncMapRail = function(element)
            local mapRail = rawget(_G, "MapRail")
            local sig = nil
            if mapRail ~= nil and rec.id == g_liveId and not rec.maximized and not rec.minimized then
                sig = mapRail.Signature()
            end
            if sig == element.data.sig then
                return
            end
            element.data.sig = sig
            if sig == nil or sig == "off" then
                element.children = {}
                return
            end
            element.children = PanelDocument.CreateMapRails()
            --the rail's Font Size zoom needs it attached first.
            for _, child in ipairs(element.children) do
                child:FireEvent("setRailScale")
            end
        end,
    }
end

--Switching maps between windows. The engine still has one live map, so
--focusing another window travels to its map; these hide that. In tabletop
--mode the engine plays a map change inside the windows only
--(GameController.ChangeMapInWindowCo): the old window freezes on its
--snapshot and the new one goes live in the same frame (OnCurrentMapChanged),
--covered by what it showed just before until the new map is built and its
--images are in, then the cover fades.
--
--g_chrome.cover: {windowId, mapid, image, placeholder, tokenLayer} -- the
--window to cover and with what, for the transition to mapid; nil when none.
--tokenLayer is the window's own token layer when it was showing live tokens:
--it moves into the cover so the cover is exactly what the window showed.
g_chrome.cover = nil

--Shows image (an image key, or nil for none) in holder, a panel that holds
--nothing else. Each key gets a panel of its own: switching one panel from one
--"#" image key to another can leave a white backing behind the image's
--transparent parts (the map void).
function g_chrome.ShowImage(holder, image, color, saturation)
    if holder == nil or not holder.valid then
        return
    end
    local child = holder.data.imagePanel
    if holder.data.image ~= image or child == nil or not child.valid then
        if child ~= nil and child.valid then
            child:DestroySelf()
        end
        child = nil
        if image ~= nil then
            child = gui.Panel{
                floating = true,
                interactable = false,
                halign = "left",
                valign = "top",
                width = "100%",
                height = "100%",
                bgimage = image,
                bgcolor = color or "white",
            }
            holder:AddChild(child)
        end
        holder.data.imagePanel = child
        holder.data.image = image
    end
    if child ~= nil then
        child.selfStyle.bgcolor = color or "white"
        child.selfStyle.saturation = saturation or 1
    end
end

--Crops the image ShowImage put in holder so a whole-map picture covers the
--window without being stretched (the picture has the map's shape).
function g_chrome.CoverFit(holder, body, mapid)
    local child = holder ~= nil and holder.valid and holder.data.imagePanel or nil
    if child == nil or not child.valid or body == nil or not body.valid then
        return
    end
    local w = body.renderedWidth
    local h = body.renderedHeight
    local thumbnails = rawget(_G, "MapThumbnail")
    if w == nil or h == nil or w <= 0 or h <= 0 or thumbnails == nil then
        return
    end
    local imageAspect = thumbnails.Aspect(mapid)
    local boxAspect = w / h
    if imageAspect > boxAspect then
        local f = boxAspect / imageAspect
        child.selfStyle.imageRect = {x1 = (1 - f) / 2, y1 = 0, x2 = (1 + f) / 2, y2 = 1}
    else
        local f = imageAspect / boxAspect
        child.selfStyle.imageRect = {x1 = 0, y1 = (1 - f) / 2, x2 = 1, y2 = (1 + f) / 2}
    end
end

--Adds or removes a class on a panel and everything inside it (opacity does
--not carry from a panel to its children, so the cover fades every part).
function g_chrome.SetTreeClass(panel, class, on)
    if panel == nil or not panel.valid then
        return
    end
    panel:SetClass(class, on)
    for _, child in ipairs(panel.children) do
        g_chrome.SetTreeClass(child, class, on)
    end
end

local function HolderPanel()
    return gui.Panel{
        floating = true,
        interactable = false,
        halign = "left",
        valign = "top",
        width = "100%",
        height = "100%",
        data = {},
    }
end
g_chrome.HolderPanel = HolderPanel

function g_chrome.CoverPanel(rec)
    local imageHolder = HolderPanel()
    local tokenSlot = HolderPanel()
    return gui.Panel{
        classes = {"tabletopCover", "collapsed"},
        styles = {
            {
                selectors = {"tabletopCover"},
                --the window's own colour, so the map void looks as it does live.
                bgcolor = "#100d0bff",
            },
            {
                selectors = {"coverFading"},
                opacity = 0,
                transitionTime = 0.3,
            },
        },
        floating = true,
        --the map under it keeps the mouse.
        interactable = false,
        halign = "center",
        valign = "center",
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        data = { imageHolder = imageHolder, tokenSlot = tokenSlot, tokenLayer = nil, fading = false },
        --only while shown: a collapsed panel does not think.
        thinkTime = 0.02,
        think = function(element)
            g_chrome.UpdateCover(rec)
        end,
        imageHolder,
        tokenSlot,
    }
end

--Gives a token layer lent to the cover back to its window, hidden.
function g_chrome.ReturnCoverTokens(rec, panel)
    local layer = panel.data.tokenLayer
    panel.data.tokenLayer = nil
    if layer == nil or not layer.valid then
        return
    end
    g_chrome.SetTreeClass(layer, "coverFading", false)
    layer:SetClass("collapsed", true)
    layer:Unparent()
    if rec.tokenHolder ~= nil and rec.tokenHolder.valid and rec.tokenLayer == layer then
        rec.tokenHolder:AddChild(layer)
    else
        layer:DestroySelf()
    end
end

--Shows, fades or hides the cover over a window's live map.
function g_chrome.UpdateCover(rec)
    local panel = rec.cover
    if panel == nil or not panel.valid then
        return
    end

    local cover = g_chrome.cover
    if cover ~= nil and dmhub.mapTransitionMapId ~= cover.mapid then
        --the transition is over, or another one replaced it.
        g_chrome.cover = nil
        cover = nil
    end

    if cover == nil or cover.windowId ~= rec.id or rec.id ~= g_liveId then
        if not panel:HasClass("collapsed") or panel.data.tokenLayer ~= nil then
            g_chrome.ReturnCoverTokens(rec, panel)
            panel:SetClass("collapsed", true)
            g_chrome.SetTreeClass(panel, "coverFading", false)
            panel.data.fading = false
        end
        return
    end

    if not cover.placeholder then
        g_chrome.ShowImage(panel.data.imageHolder, cover.image)
    else
        g_chrome.ShowImage(panel.data.imageHolder, nil)
    end

    local layer = cover.tokenLayer
    if layer ~= nil and layer.valid and panel.data.tokenLayer ~= layer then
        g_chrome.ReturnCoverTokens(rec, panel)
        layer:Unparent()
        panel.data.tokenSlot:AddChild(layer)
        layer:SetClass("collapsed", false)
        panel.data.tokenLayer = layer
    end

    panel:SetClass("collapsed", false)
    local fading = not dmhub.mapTransitionCovered
    if fading ~= panel.data.fading then
        panel.data.fading = fading
        g_chrome.SetTreeClass(panel, "coverFading", fading)
    end
end

--A frozen window's tokens. The window shows its map's snapshot exactly as
--it was left while nothing on that map has changed. Once a token there has
--moved, arrived or left (the game data keeps changing for every map), it
--shows the token-free copy of the snapshot ("#MapSnapshotBase:") with the
--map's tokens drawn over it where they are now, so the window stays live.
--Players only see tokens drawn in their snapshot (ones they could see when
--they left) and player-controlled ones; the Director sees every token on the
--snapshot's floor.
function g_chrome.SyncFrozenTokens(rec)
    local body = rec.frozenBody
    if body == nil or not body.valid or rec.id == g_liveId then
        return
    end

    local info = dmhub.GetMapSnapshotInfo(rec.mapid)
    local shown = {}
    local live = false
    if info ~= nil and info.hasTokenFree then
        local present = {}
        for _, t in ipairs(dmhub.GetMapTokens(rec.mapid)) do
            present[t.charid] = true
            local was = info.tokens[t.charid]
            local eligible = t.floor == info.floor and (dmhub.isDM or was ~= nil or t.playerControlled)
            if eligible then
                shown[#shown+1] = t
            end
            if was ~= nil then
                if math.abs(was.x - t.x) > 0.01 or math.abs(was.y - t.y) > 0.01 or was.floor ~= t.floor or math.abs(was.scale - t.scale) > 0.01 then
                    live = true
                end
            elseif eligible then
                live = true
            end
        end
        for charid, _ in pairs(info.tokens) do
            if not present[charid] then
                live = true
            end
        end
    end

    --The token-free snapshot is its own panel over the snapshot, made with its
    --image key (switching a panel from one "#" image key to another can leave
    --a white backing behind the image's transparent parts).
    local layer = rec.tokenLayer
    if not live or info == nil then
        if layer ~= nil and layer.valid then
            layer:SetClass("collapsed", true)
        end
        return
    end

    if layer == nil or not layer.valid or rec.tokenLayerMap ~= rec.mapid then
        if layer ~= nil and layer.valid then
            layer:DestroySelf()
        end
        layer = gui.Panel{
            floating = true,
            interactable = false,
            halign = "left",
            valign = "top",
            width = "100%",
            height = "100%",
            bgimage = "#MapSnapshotBase:" .. rec.mapid,
            bgcolor = "white",
        }
        rec.tokenLayer = layer
        rec.tokenLayerMap = rec.mapid
        rec.tokenPanels = {}
        rec.tokenHolder:AddChild(layer)
    end
    layer:SetClass("collapsed", false)

    rec.tokenPanels = rec.tokenPanels or {}
    local panels = rec.tokenPanels

    local w = body.renderedWidth
    local h = body.renderedHeight
    local ww = info.x2 - info.x1
    local wh = info.y2 - info.y1
    if w == nil or h == nil or w <= 0 or h <= 0 or ww <= 0 or wh <= 0 then
        return
    end

    local keep = {}
    for _, t in ipairs(shown) do
        local size = t.scale * w / ww
        local x = (t.x - info.x1) / ww * w - size / 2
        local y = (info.y2 - t.y) / wh * h - size / 2
        --only tokens wholly inside the window: nothing clips this layer
        --(a panel's clip mask changes how the snapshot's transparent map void
        --draws), so one at the edge would hang out of the window.
        if x >= 0 and y >= 0 and x + size <= w and y + size <= h then
            keep[t.charid] = true
        end
    end
    for _, t in ipairs(shown) do
        local size = t.scale * w / ww
        local x = (t.x - info.x1) / ww * w - size / 2
        local y = (info.y2 - t.y) / wh * h - size / 2
        local panel = nil
        if keep[t.charid] then
            panel = panels[t.charid]
        end
        if keep[t.charid] and (panel == nil or not panel.valid) then
            local token = dmhub.GetCharacterById(t.charid)
            if token ~= nil then
                panel = gui.CreateTokenImage(token, {
                    floating = true,
                    interactable = false,
                    halign = "left",
                    valign = "top",
                    width = size,
                    height = size,
                })
                panels[t.charid] = panel
                layer:AddChild(panel)
            end
        end
        if panel ~= nil and panel.valid then
            panel.x = x
            panel.y = y
            if panel.selfStyle.width ~= size then
                panel.selfStyle.width = size
                panel.selfStyle.height = size
            end
        end
    end

    for charid, panel in pairs(panels) do
        if not keep[charid] then
            if panel.valid then
                panel:DestroySelf()
            end
            panels[charid] = nil
        end
    end
end

--A frozen window's hint: "Click to view" on hover when it shows loading
--art or nothing, and "Loading..." while it waits for its map's data (only
--after a moment, so a quick switch never flashes it). A window showing a
--snapshot has no hover hint: it looks like a live map.
function g_chrome.UpdateFrozenHint(rec)
    local hint = rec.frozenHint
    if hint == nil or not hint.valid then
        return
    end

    local loading = false
    if dmhub.mapTransitionMapId == rec.mapid and game.currentMapId ~= rec.mapid then
        rec.loadingSince = rec.loadingSince or dmhub.Time()
        loading = dmhub.Time() >= rec.loadingSince + 0.3
    else
        rec.loadingSince = nil
    end

    if hint.text ~= "Loading..." then
        hint.text = "Loading..."
    end
    hint:SetClass("loading", loading)
    hint:SetClass("collapsed", not loading)
end

local function BuildWindow(rec)
    local panel

    --the Director's shape overlay, cropped the same way as the map.
    local liveChildren = {}
    if dmhub.isDM then
        liveChildren[#liveChildren+1] = gui.Panel{
            floating = true,
            interactable = false,
            width = "100%",
            height = "100%",
            bgimage = "#ShapesView",
            bgcolor = "white",
        }
    end

    --over the map while a switch to it builds it (g_chrome.UpdateCover);
    --under the map's own HUD.
    rec.cover = g_chrome.CoverPanel(rec)
    liveChildren[#liveChildren+1] = rec.cover

    --The map's own HUD, drawn over the map inside this window: the initiative
    --bar moves in here while this window is live, and dialogs presented for
    --this map (the "Draw Steel" banner) open here (MapOverlayHost). It has
    --no bgimage, so it takes no mouse itself.
    local overlay = gui.Panel{
        styles = g_overlayStyles,
        floating = true,
        valign = "top",
        width = "100%",
        height = "100%",
        --a window narrower than the HUD shrinks it to fit.
        thinkTime = 0.25,
        think = function(element)
            if rec.id == g_liveId then
                Tabletop.ScaleMapHuds(element)
            end
        end,
    }
    --the rail goes under the HUD, so the map's bars and dialogs (the
    --encounter prep bar, the Draw Steel banner) are never hidden behind it.
    rec.mapRailHost = g_chrome.MapRailHost(rec)
    liveChildren[#liveChildren+1] = rec.mapRailHost
    liveChildren[#liveChildren+1] = overlay

    --The live map: this panel's rectangle of the screen-aligned map image.
    --It does not block the map, so clicks, drags and the wheel inside it
    --reach the map; swallowPress keeps them from also dragging the window.
    --It only carries "#MapView" while this window is live (Refresh): a
    --panel showing it is where the engine puts the map, even for a frame.
    local liveBody = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "100% available",
        bgimage = "panels/square.png",
        bgcolor = "white",
        blocksGameInteraction = false,
        swallowPress = true,
        children = liveChildren,
    }

    local frozenHint = gui.Label{
        classes = {"tabletopFrozenHint"},
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        bold = true,
        text = "Click to view",
    }

    --the snapshot (or loading art), and over it the map's tokens drawn on its
    --token-free snapshot (SyncFrozenTokens): panels made per image key.
    rec.snapHolder = HolderPanel()
    rec.tokenHolder = HolderPanel()
    rec.tokenLayer = nil
    rec.tokenPanels = {}

    --Not the live map: the snapshot of what this window last showed, or
    --the map's loading-screen art before it has been shown this session.
    --Like the live map it stands in for, a press here goes to the map, not
    --to dragging the window: the switch starts on the press, and once the
    --map is live the token under it is selected (map:TravelFromPress).
    local frozenBody = gui.Panel{
        styles = ThemeEngine.MergeStyles(g_frozenStyles),
        classes = {"tabletopFrozen"},
        width = "100%",
        height = "100% available",
        bgimage = "panels/square.png",
        swallowPress = true,
        --start syncing the map as the mouse comes over, so the press finds
        --its data in.
        hover = function(element)
            local map = game.GetMap(rec.mapid)
            if map ~= nil and map.valid then
                map:Prefetch()
            end
        end,
        press = function(element)
            if ClicksGuarded() then
                return
            end
            Focus(rec, 0)
        end,
        --right and middle presses land on the map too, once it is live: the
        --context menu opens there, a held middle button pans it.
        rightPress = function(element)
            Focus(rec, 1)
        end,
        middlePress = function(element)
            Focus(rec, 2)
        end,
        --(the right-click's release must not reach the table's own menu.)
        rightClick = function(element)
        end,
        thinkTime = 0.1,
        think = function(element)
            g_chrome.UpdateFrozenHint(rec)
            g_chrome.SyncFrozenTokens(rec)
        end,
        --the Director drags a token out of the live window and drops it
        --here to teleport it onto this map (g_chrome.TeleportDrop).
        tokenDropTarget = dmhub.isDM,
        tokenDragEnter = function(element, info)
            g_chrome.TeleportDragEnter(rec, info)
        end,
        tokenDragLeave = function(element)
            g_chrome.TeleportDragLeave(rec)
        end,
        dropTokens = function(element, info)
            g_chrome.TeleportDrop(rec, info)
        end,
        --and drags a bestiary entry, hero row or card here to place it on
        --this map (g_chrome.CreatureDrop).
        creatureDragEnter = function(element, info)
            g_chrome.CreatureDragEnter(rec, info)
        end,
        creatureDragLeave = function(element)
            g_chrome.CreatureDragLeave(rec)
        end,
        dropCreatures = function(element, info)
            g_chrome.CreatureDrop(rec, info)
        end,
        rec.snapHolder,
        rec.tokenHolder,
        frozenHint,
    }

    local nameLabel = g_chrome.NameLabel(MapName(rec.mapid))

    --a frozen window's map is in combat: its round.
    local roundLabel = gui.Label{
        classes = {"tabletopTitleDetail", "collapsed"},
        width = "auto",
        height = "100%",
        valign = "center",
        rmargin = 8,
        textWrap = false,
        text = "",
    }

    --Where the live window shows the map's status: the Round panel (moved
    --here from the title bar).
    local initiativeSlot = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
    }

    local floorControl = BuildFloorControl(rec)

    --where the mouse is on the map: the first thing a narrow titlebar drops
    --(g_chrome.FitTitle).
    local positionGroup = gui.Panel{
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        g_chrome.Sep(),
        CodexTitleBar.CreateMapPosition{width = 96},
    }

    --The live map's details after its name: the floor stepper, where the
    --mouse is on the map, and the Round panel.
    local liveStatus = gui.Panel{
        classes = {"collapsed"},
        flow = "horizontal",
        width = "auto",
        height = "100%",
        valign = "center",
        floorControl,
        positionGroup,
        g_chrome.Sep(),
        initiativeSlot,
    }

    --a frozen window whose map is in combat.
    local combatBadge = gui.Panel{
        classes = {"tabletopCombatBadge", "collapsed"},
        bgimage = "phosphor/sword-fill.png",
        width = 14,
        height = 14,
        valign = "center",
        lmargin = 10,
        hover = gui.Tooltip("This map is in combat"),
    }

    local maximizeButton = WindowControl{
        icon = "window-chrome/chrome-maximize.png",
        click = function(element)
            ToggleMaximize(rec)
        end,
    }

    --the ping, left of the share button: everyone it is shared with sees
    --it flash (DefinePings).
    local controls = {
        g_sharing.PingButton(function()
            return g_sharing.LayoutKey(rec)
        end),
    }

    --the Director makes the map Player Viewable, for all players or chosen
    --ones, which opens it on their tables. Sharing again after stopping
    --also puts it back on tables whose players closed it.
    local share = nil
    if dmhub.isDM then
        share = ShareControl{
            store = g_sharing.MapStore(rec.mapid),
            what = "this map",
            iconSize = 15,
            changed = function()
                Refresh()
            end,
        }
        controls[#controls+1] = share.button
    end

    --a player who moved or resized this window gives it back to the
    --Director's placement (DefineDirectorLayout).
    controls[#controls+1] = g_sharing.FollowButton(function()
        return g_sharing.LayoutKey(rec)
    end)

    --minimize, maximize and close: hidden while a player's window is held
    --maximized by the Director (Refresh).
    local windowButtons = {
        WindowControl{
            icon = "window-chrome/chrome-minimize.png",
            click = function(element)
                Minimize(rec)
            end,
        },
        maximizeButton,
        WindowControl{
            danger = true,
            icon = "window-chrome/chrome-close.png",
            click = function(element)
                RequestClose(rec)
            end,
        },
    }
    for _, button in ipairs(windowButtons) do
        controls[#controls+1] = button
    end

    --the floor stepper cannot poll for itself (a collapsed panel does not
    --think), so the name row polls it; the row moves with the titlebar's
    --contents into the strip when maximized.
    local titlebar = g_chrome.Titlebar(rec, {combatBadge, nameLabel, roundLabel, g_chrome.VisionChip(rec), liveStatus}, controls, function()
        floorControl:FireEvent("updateFloor")
    end)

    local doc = {
        try_get = function(self, key)
            return rawget(self, key)
        end,
    }

    local resizePanel = gui.WindowResizePanel(doc, rec.width, rec.height, {
        minWidth = MIN_WIDTH,
        minHeight = MIN_HEIGHT,
        onResized = function(dialog, moved)
            rec.width = dialog.selfStyle.width
            rec.height = dialog.selfStyle.height
            rec.x, rec.y = ClampWindow(rec, dialog.x, dialog.y)
            if rec.x ~= dialog.x or rec.y ~= dialog.y then
                dialog.x = rec.x
                dialog.y = rec.y
            end
            SaveSoon()
            g_sharing.TookControl(g_sharing.LayoutKey(rec))
        end,
    })

    panel = gui.Panel{
        styles = g_windowStyles,
        classes = {"tabletopWindow"},
        --click-to-front: a press anywhere on it, even on the live map inside
        --(MapViewport raises the live window), raises it (engine walk).
        raiseOnPress = true,
        flow = "vertical",
        x = rec.x,
        y = rec.y,
        width = rec.width,
        height = rec.height,
        halign = "left",
        valign = "top",
        bgimage = "panels/square.png",
        swallowPress = true,
        draggable = true,
        --stays among the table items while dragged, so the Director's
        --Screen can lie over it (DirectorScreen KeepOnTop).
        dragInPlace = true,
        dragging = function(element)
            if not rec.maximized then
                DirectorScreen.ItemDragging(g_sharing.ScreenKey(rec), element.xdrag, rec.width, element)
            end
        end,
        drag = function(element)
            if rec.maximized then
                return
            end
            rec.x, rec.y = SnapWindow(rec, element.xdrag, element.ydrag)
            element.x = rec.x
            element.y = rec.y
            SaveSoon()
            g_sharing.TookControl(g_sharing.LayoutKey(rec))
            --onto the Director's Screen it is the Director's alone; off it,
            --the players get it (DirectorScreen.lua).
            DirectorScreen.ItemDropped(g_sharing.ScreenKey(rec))
        end,
        click = function(element)
            if ClicksGuarded() then
                return
            end
            --the press already raised it (raiseOnPress). Raising again here buried
            --a window the press had just opened from inside it: a map rail button
            --opens its panel on press and has no click handler, so the click
            --bubbles up to here (2026-10-25).
            Focus(rec, nil, true)
        end,
        children = {
            titlebar,
            liveBody,
            frozenBody,
            resizePanel,
            share and share.frame,
        },
    }

    rec.panel = panel
    rec.titlebar = titlebar
    rec.liveBody = liveBody
    rec.overlay = overlay
    rec.frozenBody = frozenBody
    rec.frozenHint = frozenHint
    rec.nameLabel = nameLabel
    rec.liveStatus = liveStatus
    rec.titlePosition = positionGroup
    rec.initiativeSlot = initiativeSlot
    rec.resizePanel = resizePanel
    rec.maximizeButton = maximizeButton
    rec.windowButtons = windowButtons
    rec.roundLabel = roundLabel
    rec.share = share
    rec.combatBadge = combatBadge
    rec.shownState = nil
end

--Puts a built window in the documents layer, mixed in with journals and
--panel windows. Maximized it stays there and covers the hud's lower layers
--(docks, Director's Screen), stacking with the other windows by click order,
--but always under the icon rails and pinned panel windows (David, 2026-10-24).
local function PlaceWindow(rec)
    local panel = rec.panel
    if panel == nil or not panel.valid then
        return
    end

    local target = DocumentsLayer()
    if target == nil or not target.valid then
        return
    end

    if panel.parent ~= target then
        if panel.parent ~= nil then
            panel:Unparent()
        end
        target:AddChild(panel)
        --appended over everything: stack it again, so what must stay above
        --a maximized map (a presented stage) is lifted back over it.
        rec.maximizedPanel = nil
    end

    g_chrome.StackMaximized(rec, rec.maximized == true)

    if rec.maximized then
        panel.x = 0
        panel.y = 0
        panel.selfStyle.width = "100%"
        panel.selfStyle.height = "100%"
    else
        panel.x = rec.x
        panel.y = rec.y
        panel.selfStyle.width = rec.width
        panel.selfStyle.height = rec.height
    end

    rec.titlebar:SetClass("collapsed", rec.maximized == true)
    rec.resizePanel:SetClass("collapsed", rec.maximized == true)
    panel.draggable = rec.maximized ~= true
    panel:SetClass("tabletopMaximized", rec.maximized == true)
    rec.maximizeButton:FireEventTree("setIcon", cond(rec.maximized, "window-chrome/chrome-restore.png", "window-chrome/chrome-maximize.png"))
    --maximized, the titlebar becomes the strip over the top of the map, so
    --the map's HUD (the initiative bar) starts below it.
    rec.overlay.y = cond(rec.maximized, TITLE_HEIGHT, 0)
    rec.overlay.selfStyle.height = cond(rec.maximized, string.format("100%%-%d", TITLE_HEIGHT), "100%")
    Tabletop.ApplyCollapsed(rec)
    g_chrome.Sync()
end

--How a map or scene window stacks while maximized among the windows
--(stacked; false windowed or under the UI). The engine keeps the rails,
--pinned windows and any dialog over it whenever it is raised (David,
--2026-10-24/25). Maximizing brings it up once: to the top, or, taking the
--maximize over from rec.stackAbove (the window it replaces), into that
--window's place, so the windows over the old map stay over it. After that
--only a click on it, Ctrl+Tab or restoring it raises it (BringToFront
--leaves a maximized window where it is).
function g_chrome.StackMaximized(rec, stacked)
    local panel = rec.panel
    panel.raiseBelowClasses = cond(stacked, PanelDocument.ABOVE_MAXIMIZED_MAP, nil)
    panel.raiseUnderNonWindows = stacked
    local above = rec.stackAbove
    rec.stackAbove = nil
    if stacked and rec.maximizedPanel ~= panel then
        if above ~= nil and above.valid and above.parent == panel.parent then
            panel:SetAsSiblingAbove(above)
        else
            panel:SetAsLastSibling()
        end
    end
    rec.maximizedPanel = cond(stacked, panel, nil)
end

--The maximized map window on show (built, not minimized), or nil.
function g_chrome.MaximizedMap()
    for _, rec in ipairs(g_windows) do
        if rec.maximized and not rec.minimized and rec.panel ~= nil and rec.panel.valid then
            return rec
        end
    end
    return nil
end

--The maximized map window covering rec when rec getting focus should take
--the maximize over from it (Focus), else nil. Not while the Director holds
--that window maximized here.
function g_chrome.CoveringMap(rec)
    if rec.maximized then
        return nil
    end
    local covering = g_chrome.MaximizedMap()
    if covering == nil or covering == rec or IsForcedHere(covering) then
        return nil
    end
    return covering
end

--A minimized window is its button (on the table or the rail); the panel
--stays built so restoring it is instant (Refresh re-applies this to every
--window). A maximized map window covers the other map windows, so they are
--hidden under it (David, 2026-10-15); every other window -- scenes,
--journals, panel windows, cards -- stays open and stacks with it by click
--order (PlaceWindow).
function Tabletop.ApplyCollapsed(rec)
    local panel = rec.panel
    if panel == nil or not panel.valid then
        return
    end
    local collapsed = rec.minimized == true or (not rec.maximized and g_chrome.MaximizedMap() ~= nil)
    --on the Director's Screen while it is closed.
    collapsed = collapsed or (not rec.maximized and DirectorScreen.IsStowed(g_sharing.ScreenKey(rec)))
    if panel:HasClass("collapsed") ~= collapsed then
        panel:SetClass("collapsed", collapsed)
    end
end

----------------------------------------------------------------------
--Minimized windows: a rail-style button floating on the table, or docked
--on the icon rail (RailEntryTypes "mapwindow"). Clicking it restores the
--window; a window collapses into its button and grows back out of it.

local BUTTON_SIZE = 40
local ANIM_SECONDS = 0.26

--Floating buttons and the collapse animation live here, above the map
--windows and journals (Tabletop.CreateButtonLayer).
local g_buttonLayer = nil

local function ButtonScale()
    return PanelDocument.WindowUIScale()
end

--A minimized window on the Director's Screen is drawn as a card (Venla,
--2026-10-17): the picture it last showed and its name, in place of the
--40-wide button. rec.card says so. It stays set while the card is expanded,
--so minimizing the window again makes a card; it clears when the window
--goes out on the table (DirectorScreen grows it). One size for every card.
--(One table, g_card, holds the card's size and helpers: this file's top
--level is near Lua's 200-local limit.)
local g_card = {width = 168, height = 112, caption = 24}

--A minimized window's button size on the table, in documents-layer units.
function g_card.Size(rec)
    local scale = ButtonScale()
    if rec.card then
        return g_card.width * scale, g_card.height * scale
    end
    return BUTTON_SIZE * scale, BUTTON_SIZE * scale
end

--A panel's rectangle in the documents layer's units (origin top-left).
--positionInScreenSpace is the panel's centre in layer units, y up.
local function LayerRect(panel, size)
    local layer = DocumentsLayer()
    if layer == nil or panel == nil or not panel.valid then
        return nil
    end
    local lp = layer.positionInScreenSpace
    local left = lp.x - layer.renderedWidth / 2
    local top = lp.y + layer.renderedHeight / 2
    local p = panel.positionInScreenSpace
    local w = size or panel.renderedWidth
    local h = size or panel.renderedHeight
    return {x = p.x - left - w / 2, y = top - p.y - h / 2, w = w, h = h}
end

--Where the window is on the table, maximized or not.
local function WindowRect(rec)
    if rec.maximized then
        local w, h = LayerSize()
        return {x = 0, y = 0, w = w, h = h}
    end
    return {x = rec.x, y = rec.y, w = rec.width, h = rec.height}
end

--The window's docked button on the rail, if the rail has drawn it.
local function RailButton(rec)
    local layer = DocumentsLayer()
    if layer == nil then
        return nil
    end
    local key = RailKey(rec)
    for _, rail in ipairs(layer.children) do
        if rail.valid and rail:HasClass("iconRail") then
            for _, button in ipairs(rail.children) do
                local buttonKey = nil
                pcall(function()
                    buttonKey = button.data.key
                end)
                if buttonKey == key then
                    return button
                end
            end
        end
    end
    return nil
end

--Where the window's button is: its rail button when docked, else its spot
--on the table.
local function ButtonRect(rec)
    local size = BUTTON_SIZE * ButtonScale()
    if IsDocked(rec) and not rec.card then
        local button = RailButton(rec)
        local rect = LayerRect(button, size)
        if rect ~= nil then
            return rect
        end
    end
    local w, h = g_card.Size(rec)
    return {x = rec.iconX or 0, y = rec.iconY or 0, w = w, h = h}
end

--A window-shaped stand-in that flies between two rectangles, showing what
--the window shows, then calls done. Ease in-out cubic.
local function AnimateGhost(rec, from, to, done)
    local layer = g_buttonLayer
    if layer == nil or not layer.valid or from == nil or to == nil then
        done()
        return
    end
    local image, placeholder
    if rec.buttonOps ~= nil then
        image, placeholder = rec.buttonOps.image(rec)
    else
        image, placeholder = Tabletop.FrozenImage(rec)
    end
    local start = dmhub.Time()
    local function lerp(a, b, t)
        return a + (b - a) * t
    end
    local ghost = gui.Panel{
        floating = true,
        interactable = false,
        halign = "left",
        valign = "top",
        x = from.x,
        y = from.y,
        width = from.w,
        height = from.h,
        bgimage = image,
        bgcolor = cond(placeholder, "#1b1814ff", "white"),
        borderWidth = 2,
        borderColor = "#00000099",
        cornerRadius = 6,
        thinkTime = 0.01,
        think = function(element)
            local t = math.min(1, (dmhub.Time() - start) / ANIM_SECONDS)
            local e
            if t < 0.5 then
                e = 4 * t * t * t
            else
                e = 1 - ((-2 * t + 2) ^ 3) / 2
            end
            element.x = lerp(from.x, to.x, e)
            element.y = lerp(from.y, to.y, e)
            element.selfStyle.width = math.max(1, lerp(from.w, to.w, e))
            element.selfStyle.height = math.max(1, lerp(from.h, to.h, e))
            element.selfStyle.cornerRadius = lerp(6, 8, e)
            if t >= 1 then
                element:DestroySelf()
                done()
            end
        end,
    }
    layer:AddChild(ghost)
end

--A card's name: its map's or its scene's.
function g_card.Name(rec)
    if rec.sceneid ~= nil then
        return Scenes.Name(rec.sceneid) or "Scene"
    end
    return MapName(rec.mapid)
end

--The part of an image a card shows: cropped to the picture's shape (the card
--above its name strip) from the middle, never stretched. aspect is the
--image's width over its height.
function g_card.Crop(aspect)
    local box = g_card.width / (g_card.height - g_card.caption)
    local w, h = 1, 1
    if aspect > box then
        w = box / aspect
    else
        h = aspect / box
    end
    return {x1 = (1 - w) / 2, y1 = (1 - h) / 2, x2 = (1 + w) / 2, y2 = (1 + h) / 2}
end

--Grows a card back into its window, on the Director's Screen, at its full
--size: where the card is, pulled left so its titlebar's buttons stay on the
--table, but never so far that its middle leaves the screen (it would be
--shared). Privacy wins when both cannot hold.
function g_card.Expand(rec, ops)
    local x = rec.iconX or rec.x
    local w = LayerSize()
    x = math.min(x, w - rec.width)
    local edge = DirectorScreen.EdgeX()
    if edge ~= nil then
        x = math.max(x, edge - rec.width / 2 + 24)
    end
    rec.x, rec.y = ClampWindow(rec, x, rec.iconY or rec.y)
    ops.restore(rec)
end

--A minimized window's card (see g_card.width): its picture, with its name on
--a strip of its own below it (Venla, 2026-10-22: nothing laid over the map,
--which made dark maps hard to read). Dragged like the button; double-click, or the expand button
--that shows on hover, grows it back into its window.
function g_card.Button(rec, ops, scale)
    local image, placeholder
    --a map card shows the whole map (its thumbnail, pack or loading art),
    --filling the card from the middle (Venla, 2026-10-19). The window's
    --snapshot is the fallback: it is see-through wherever the window showed
    --no map, so it cannot fill the card.
    local mapAspect = nil
    if ops.image ~= nil then
        image, placeholder = ops.image(rec)
    else
        local thumbnails = rawget(_G, "MapThumbnail")
        local thumb, source = nil, nil
        if thumbnails ~= nil then
            thumb, source = thumbnails.Image(rec.mapid)
        end
        if thumb ~= nil and source ~= "snapshot" then
            image, placeholder = thumb, false
            if source == "thumbnail" then
                mapAspect = thumbnails.Aspect(rec.mapid)
            end
        else
            image, placeholder = Tabletop.FrozenImage(rec)
        end
    end
    local expand = gui.Panel{
        classes = {"tabletopCardExpand", "hidden"},
        bgimage = "panels/square.png",
        bgcolor = "#16171bdd",
        cornerRadius = 5,
        floating = true,
        halign = "right",
        valign = "top",
        x = -5,
        y = 5,
        width = 24,
        height = 24,
        flow = "none",
        swallowPress = true,
        press = function(element)
            g_card.Expand(rec, ops)
        end,
        gui.Panel{
            bgimage = "phosphor/arrows-out-simple-fill.png",
            bgcolor = "#ffffffe0",
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }
    --the picture sits on a solid card: a map snapshot is see-through where the
    --window showed no map, which let what lies under the card show through.
    local picture = gui.Panel{
        bgimage = image,
        bgcolor = cond(placeholder, "#1b1814ff", "white"),
        cornerRadius = 6,
        floating = true,
        halign = "center",
        valign = "top",
        width = g_card.width,
        height = g_card.height - g_card.caption,
        interactable = false,
    }
    local card
    card = gui.Panel{
        classes = {"tabletopTableButton", "tabletopWindowCard"},
        bgimage = "panels/square.png",
        bgcolor = "#1b1814ff",
        --no frame (Venla, 2026-10-22): the picture runs to the card's edges.
        cornerRadius = 6,
        floating = true,
        halign = "left",
        valign = "top",
        x = rec.iconX or 0,
        y = rec.iconY or 0,
        width = g_card.width,
        height = g_card.height,
        flow = "none",
        swallowPress = true,
        draggable = true,

        dragging = function(element, target)
            ChatItemLinks.Dragging(function() return ops.chatItems(rec) end)
            local w = g_card.Size(rec)
            DirectorScreen.ItemDragging(g_sharing.ScreenKey(rec), element.xdrag, w, element)
        end,
        drag = function(element, target)
            if ChatItemLinks.Dropped() then
                DirectorScreen.ItemDropped(nil)
                return
            end
            local lw, lh = LayerSize()
            local w, h = g_card.Size(rec)
            rec.iconX = math.max(0, math.min(element.xdrag, lw - w))
            rec.iconY = math.max(0, math.min(element.ydrag, lh - h))
            element.x = rec.iconX
            element.y = rec.iconY
            SaveSoon()
            DirectorScreen.ItemDropped(g_sharing.ScreenKey(rec))
        end,
        doubleclick = function(element)
            if ClicksGuarded() then
                return
            end
            g_card.Expand(rec, ops)
        end,
        hover = function(element)
            expand:SetClass("hidden", false)
        end,
        dehover = function(element)
            expand:SetClass("hidden", true)
        end,
        rightClick = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    GuardedEntry("Expand", function()
                        element.popup = nil
                        g_card.Expand(rec, ops)
                    end),
                    GuardedEntry(ops.closeText, function()
                        element.popup = nil
                        ops.close(rec)
                    end),
                },
            }
        end,

        picture,
        --its name, one line, on the card below the picture.
        gui.Label{
            text = g_card.Name(rec),
            --a long name shrinks to stay on the card (about 22 characters
            --fit at 12).
            fontSize = math.max(9, math.min(12, 12 * 22 / math.max(1, #g_card.Name(rec)))),
            color = "#efe6dc",
            floating = true,
            halign = "left",
            valign = "bottom",
            x = 8,
            width = g_card.width - 16,
            height = g_card.caption,
            textAlignment = "left",
            textWrap = false,
            interactable = false,
        },
        expand,
    }
    --cropped to the card's shape: a map's thumbnail has the map's shape, its
    --snapshot its window's; anything else is measured.
    if mapAspect ~= nil then
        picture.selfStyle.imageRect = g_card.Crop(mapAspect)
    elseif type(image) == "string" and string.sub(image, 1, 13) == "#MapSnapshot:" then
        picture.selfStyle.imageRect = g_card.Crop(rec.width / math.max(1, rec.height))
    elseif type(image) == "string" and string.sub(image, 1, 1) ~= "#" and not placeholder then
        gui.GetImageDimensionsCallback(image, function(dims)
            if picture.valid and dims ~= nil and (dims.width or 0) > 0 and (dims.height or 0) > 0 then
                picture.selfStyle.imageRect = g_card.Crop(dims.width / dims.height)
            end
        end)
    end
    local layer = g_buttonLayer --[[@as Panel]]
    layer:AddChild(card)
    card.selfStyle.pivot = {x = 0, y = 1}
    card.selfStyle.uiscale = scale
    return card
end

--Builds (or rebuilds) a minimized window's floating button on the table.
--A docked window has no floating button: the rail draws it.
--What the button shows and does comes from rec.buttonOps (a scene window
--sets its own); a map window uses the defaults here. Fields: icon,
--image(rec) (the collapse animation's picture, see AnimateGhost),
--restore(rec), close(rec), closeText, hover(rec, element), chatItems(rec)
--(links for a drop on the chat), badge {icon, color} and badgeShown(rec).
local function UpdateTableButton(rec)
    local want = rec.minimized == true and (rec.card or not IsDocked(rec)) and g_buttonLayer ~= nil and g_buttonLayer.valid
    if not want then
        if rec.button ~= nil and rec.button.valid then
            rec.button:DestroySelf()
        end
        rec.button = nil
        return
    end
    if rec.button ~= nil and rec.button.valid then
        --a button that became a card (or a card a button) is rebuilt.
        if rec.buttonIsCard == (rec.card == true) then
            return
        end
        rec.button:DestroySelf()
        rec.button = nil
    end

    local ops = rec.buttonOps or {
        icon = "phosphor/map-trifold.png",
        restore = RestoreWindow,
        close = RequestClose,
        closeText = "Close Map Window",
        hover = ShowPreviewTooltip,
        chatItems = function(r)
            return {ChatItemLinks.MapItem(r.mapid)}
        end,
        --the map is in combat.
        badge = {icon = "phosphor/sword-fill.png", color = "#e0503f"},
        badgeShown = function(r)
            return Tabletop.MapInCombat(r.mapid)
        end,
    }

    local scale = ButtonScale()
    rec.buttonIsCard = rec.card == true
    if rec.card then
        rec.button = g_card.Button(rec, ops, scale)
        return
    end
    local button
    button = gui.Panel{
        classes = {"iconRailButton", "tabletopTableButton"},
        bgimage = true,
        blurBackground = true,
        floating = true,
        halign = "left",
        valign = "top",
        x = rec.iconX or 0,
        y = rec.iconY or 0,
        width = BUTTON_SIZE,
        height = BUTTON_SIZE,
        flow = "none",
        swallowPress = true,
        draggable = true,

        --drag it onto either icon rail to dock it there.
        canDragOnto = function(element, target)
            return target:HasClass("iconRail") or target:HasClass("iconRailButton")
        end,
        dragging = function(element, target)
            IconRailDocDragging(target)
            ChatItemLinks.Dragging(function() return ops.chatItems(rec) end)
            DirectorScreen.ItemDragging(g_sharing.ScreenKey(rec), element.xdrag, BUTTON_SIZE * scale, element)
        end,
        drag = function(element, target)
            IconRailDocDragging(nil)
            --dropped on the chat: a link to the map or scene, and the button
            --stays put.
            if ChatItemLinks.Dropped() then
                DirectorScreen.ItemDropped(nil)
                return
            end
            if target ~= nil and target.valid and (target:HasClass("iconRail") or target:HasClass("iconRailButton")) then
                if IconRailKeyDrop(RailKey(rec), target) then
                    UpdateTableButton(rec)
                    SaveSoon()
                    return
                end
            end
            local w, h = LayerSize()
            local size = BUTTON_SIZE * scale
            rec.iconX = math.max(0, math.min(element.xdrag, w - size))
            rec.iconY = math.max(0, math.min(element.ydrag, h - size))
            element.x = rec.iconX
            element.y = rec.iconY
            SaveSoon()
            --the button stands for its window on the Director's Screen too.
            DirectorScreen.ItemDropped(g_sharing.ScreenKey(rec))
        end,
        click = function(element)
            if ClicksGuarded() then
                return
            end
            ops.restore(rec)
        end,
        hover = function(element)
            ops.hover(rec, element)
        end,
        rightClick = function(element)
            element.popup = gui.ContextMenu{
                entries = {
                    GuardedEntry("Restore", function()
                        element.popup = nil
                        ops.restore(rec)
                    end),
                    GuardedEntry("Dock to Left Rail", function()
                        element.popup = nil
                        IconRailKeyAdd(RailKey(rec), "left")
                        UpdateTableButton(rec)
                    end),
                    GuardedEntry("Dock to Right Rail", function()
                        element.popup = nil
                        IconRailKeyAdd(RailKey(rec), "right")
                        UpdateTableButton(rec)
                    end),
                    GuardedEntry(ops.closeText, function()
                        element.popup = nil
                        ops.close(rec)
                    end),
                },
            }
        end,

        gui.Panel{
            classes = {"iconRailIcon"},
            bgimage = ops.icon,
            width = 20,
            height = 20,
            halign = "center",
            valign = "center",
            interactable = false,
        },

        --the window's badge (a map's combat, a scene on show), on the button
        --(kept up to date by the button's think: a hidden panel does not think).
        gui.Panel{
            classes = {"tabletopButtonBadge", "hidden"},
            bgimage = ops.badge.icon,
            bgcolor = ops.badge.color,
            floating = true,
            width = 12,
            height = 12,
            halign = "right",
            valign = "top",
            x = -3,
            y = 3,
            interactable = false,
        },

        thinkTime = 1,
        think = function(element)
            local shown = ops.badgeShown(rec) == true
            for _, child in ipairs(element.children) do
                if child:HasClass("tabletopButtonBadge") then
                    child:SetClass("hidden", not shown)
                end
            end
        end,
    }
    local layer = g_buttonLayer --[[@as Panel]]
    layer:AddChild(button)
    button.selfStyle.pivot = {x = 0, y = 1}
    button.selfStyle.uiscale = scale
    rec.button = button
end

--Collapses a window into its button: on the table where its middle was
--(or where its button was left last time), or on the rail if docked.
Minimize = function(rec)
    if rec.minimized or IsForcedHere(rec) then
        return
    end
    if rec.id == g_liveId then
        --the button's preview and the animation show the map as it was left.
        dmhub.CaptureMapSnapshot()
    end
    local from = WindowRect(rec)
    if rec.iconX == nil then
        local size = BUTTON_SIZE * ButtonScale()
        rec.iconX = math.floor(from.x + from.w / 2 - size / 2)
        rec.iconY = math.floor(from.y + from.h / 2 - size / 2)
    end
    rec.minimized = true
    if g_focusedId == rec.id then
        g_focusedId = nil
    end
    if rec.maximized then
        --the Director stopped looking at it: the players are released.
        Tabletop.SetForced(rec.mapid, false)
    end
    PlaceWindow(rec)
    Refresh()
    local to = ButtonRect(rec)
    AnimateGhost(rec, from, to, function()
        if IsOpen(rec) and rec.minimized then
            UpdateTableButton(rec)
            if rec.button ~= nil and rec.button.valid then
                rec.button:PulseClass("justDropped")
            end
        end
    end)
    SaveSoon()
end

--Grows a minimized window back out of its button and focuses it (which
--travels to its map; the travel starts with the animation, so the map is
--loading while the window opens).
RestoreWindow = function(rec)
    if not rec.minimized then
        Focus(rec)
        return
    end
    local from = ButtonRect(rec)
    --restored under a maximized map, it takes the maximize over when Focus
    --runs at the end: it grows out to fill the table.
    local to = WindowRect(rec)
    if g_chrome.CoveringMap(rec) ~= nil then
        local w, h = LayerSize()
        to = {x = 0, y = 0, w = w, h = h}
    end
    rec.minimized = false
    UpdateTableButton(rec)
    g_focusedId = rec.id
    Travel(rec.mapid)
    AnimateGhost(rec, from, to, function()
        if IsOpen(rec) and not rec.minimized then
            local takesOver = g_chrome.CoveringMap(rec) ~= nil
            PlaceWindow(rec)
            if rec.maximized then
                Tabletop.SetForced(rec.mapid, true)
            end
            Focus(rec)
            --a maximized window restored from its button comes up (BringToFront
            --leaves it); one taking the maximize over keeps the old one's place.
            if rec.maximized and not takesOver and rec.panel ~= nil and rec.panel.valid then
                rec.panel:SetAsLastSibling()
            end
        end
    end)
    SaveSoon()
end

----------------------------------------------------------------------
--Windows this file does not own (the PDF viewer, JournalPDFViewer.lua)
--minimize into the same buttons as map windows: on the table, or docked on
--the icon rail. The owner keeps its window and a record:
--  id, railKey (its RailEntryTypes key, "<type>:<id>"), buttonOps (see
--  UpdateTableButton; image is required);
--and this file keeps minimized, iconX/iconY and button on it. Rects are
--{x, y, w, h} in documents-layer units, origin top-left. Nothing here is
--saved with the layout: the owner's window does not outlive the session.

--- A panel's rectangle in documents-layer units, or nil.
--- @param panel Panel
--- @return nil|{x: number, y: number, w: number, h: number}
function Tabletop.PanelRect(panel)
    return LayerRect(panel)
end

--- The whole documents layer as a rect (where a maximized window sits).
--- @return {x: number, y: number, w: number, h: number}
function Tabletop.LayerRect()
    local w, h = LayerSize()
    return {x = 0, y = 0, w = w, h = h}
end

--- Whether minimized buttons can be drawn here (the tabletop is up).
--- @return boolean
function Tabletop.CanMinimizeExternal()
    return Tabletop.IsActive() and g_buttonLayer ~= nil and g_buttonLayer.valid
end

--- Whether an external window is docked on a showing icon rail (where its
--- minimized form is its rail button).
--- @param rec table
--- @return boolean
function Tabletop.IsExternalDocked(rec)
    return IsDocked(rec)
end

--- Collapses an external window into its button, flying a ghost from
--- `from` (the window's rect). The owner hides its own window.
--- @param rec table
--- @param from nil|{x: number, y: number, w: number, h: number}
function Tabletop.MinimizeExternal(rec, from)
    if rec.minimized then
        return
    end
    if rec.iconX == nil and from ~= nil then
        local size = BUTTON_SIZE * ButtonScale()
        rec.iconX = math.floor(from.x + from.w / 2 - size / 2)
        rec.iconY = math.floor(from.y + from.h / 2 - size / 2)
    end
    rec.minimized = true
    rec.closed = nil
    AnimateGhost(rec, from, ButtonRect(rec), function()
        if rec.minimized and not rec.closed then
            UpdateTableButton(rec)
            if rec.button ~= nil and rec.button.valid then
                rec.button:PulseClass("justDropped")
            end
        end
    end)
end

--- Grows an external window back out of its button towards `to`, then
--- calls done (where the owner shows its window again).
--- @param rec table
--- @param to {x: number, y: number, w: number, h: number}
--- @param done function
function Tabletop.RestoreExternal(rec, to, done)
    if not rec.minimized then
        done()
        return
    end
    local from = ButtonRect(rec)
    rec.minimized = false
    UpdateTableButton(rec)
    AnimateGhost(rec, from, to, done)
end

--- The external window closed: its button goes, and so does its rail entry.
--- @param rec table
function Tabletop.CloseExternal(rec)
    rec.closed = true
    rec.minimized = false
    UpdateTableButton(rec)
    if rec.railKey ~= nil and rawget(_G, "IconRailKeySlot") ~= nil and IconRailKeySlot(rec.railKey) ~= nil then
        IconRailKeyPurge(rec.railKey)
    end
end

--- The external window's entry left the rail (its RailEntryTypes onRemove):
--- a minimized window's button goes back on the table.
--- @param rec table
function Tabletop.UndockExternal(rec)
    if rec.closed then
        return
    end
    if rec.minimized then
        local w = LayerSize()
        rec.iconX = math.min(rec.iconX or 80, w - 80)
        rec.iconY = rec.iconY or 120
    end
    UpdateTableButton(rec)
end

--Takes the live map status back from whichever window holds it.
local function ReleaseMapStatus()
    CodexTitleBar.SetInitiativeStatusHost(nil)
    CodexTitleBar.SetMapStatusInWindow(false)
end

----------------------------------------------------------------------
--Map HUD: GameHud elements that belong to the current map rather than to
--the screen -- the initiative bar, since initiative is per map. GameHud
--builds each inside a full-size slot (MapHudSlot). In tabletop mode it moves
--into the live window's overlay, and back to its slot otherwise.

local g_mapHuds = {}

--Wraps panel (nil passes through) in its GameHud slot. Called from the
--GameHud child list.
--A panel that lays itself out to the window's width (the encounter prep
--bar) sets data.hudFullWidth: the window width below which it has to shrink.
--Others shrink below the initiative bar's full width.
function Tabletop.MapHudSlot(panel)
    if panel == nil then
        return nil
    end
    local slot = gui.Panel{
        width = "100%",
        height = "100%",
        panel,
    }
    --drop entries left over from earlier GameHuds.
    local kept = {}
    for _,entry in ipairs(g_mapHuds) do
        if entry.slot.valid then
            kept[#kept+1] = entry
        end
    end
    kept[#kept+1] = {slot = slot, panel = panel, fullWidth = (panel.data or {}).hudFullWidth}
    g_mapHuds = kept
    return slot
end

--The width the map HUD (the initiative bar's card row and its margins)
--needs at full size.
local HUD_FULL_WIDTH = 1180

--Shrinks the map HUD, about its top centre, to fit a window narrower than
--it; full size again in a wide window or back in its slot (host nil).
function Tabletop.ScaleMapHuds(host)
    local hostWidth = nil
    if host ~= nil and host.valid and host.renderedWidth > 0 then
        hostWidth = host.renderedWidth
    end
    for _,entry in ipairs(g_mapHuds) do
        local scale = 1
        if hostWidth ~= nil then
            scale = math.min(1, hostWidth / (entry.fullWidth or HUD_FULL_WIDTH))
        end
        scale = math.floor(scale * 100 + 0.5) / 100
        if entry.panel.valid and entry.scale ~= scale then
            entry.scale = scale
            entry.panel.selfStyle.pivot = {x = 0.5, y = 1}
            entry.panel.selfStyle.uiscale = scale
        end
    end
end

--Puts the map HUD into host (the live window's overlay), or back into its
--slots when host is nil. On the empty table (no live window) the slots are
--hidden: there is no map to show it over.
local function PlaceMapHuds(host)
    local hide = host == nil
    for _,entry in ipairs(g_mapHuds) do
        if entry.slot.valid and entry.panel.valid then
            local target = host
            if target == nil or not target.valid then
                target = entry.slot
            end
            if entry.panel.parent ~= target then
                entry.panel:Unparent()
                target:AddChild(entry.panel)
            end
            entry.slot:SetClass("collapsed", hide)
        end
    end
    Tabletop.ScaleMapHuds(host)
end

local function DestroyWindowPanel(rec)
    if rec.panel ~= nil and rec.panel.valid then
        if rec.id == g_liveId then
            --take the map's status and HUD out first, or they go with it.
            ReleaseMapStatus()
            PlaceMapHuds(nil)
        end
        g_chrome.Release(rec)
        rec.panel:DestroySelf()
    end
    rec.panel = nil
end

----------------------------------------------------------------------
--Which window is live, and what each window shows.

local function ResolveLive()
    local current = game.currentMapId
    local live = WindowById(g_liveId)
    if live ~= nil and live.mapid == current then
        return
    end

    local focused = WindowById(g_focusedId)
    if focused ~= nil and focused.mapid == current then
        g_liveId = focused.id
        return
    end

    local other = WindowForMap(current)
    g_liveId = other ~= nil and other.id or nil
end

--What a frozen window shows, whether that is just a placeholder (no
--snapshot this session and no loading-screen art), and whether it is the
--map's snapshot (the map as the window last showed it).
local function FrozenImage(rec)
    if dmhub.HasMapSnapshot(rec.mapid) then
        return "#MapSnapshot:" .. rec.mapid, false, true
    end
    --no snapshot yet (the engine is about to visit the map for one): the
    --map's thumbnail, else its pack art, else its loading art.
    local thumbnails = rawget(_G, "MapThumbnail")
    if thumbnails ~= nil then
        local image = thumbnails.Image(rec.mapid)
        if image ~= nil then
            return image, false, false
        end
    end
    local map = game.GetMap(rec.mapid)
    if map ~= nil and map.valid and type(map.loadingScreenImage) == "string" and map.loadingScreenImage ~= "" then
        return map.loadingScreenImage, false, false
    end
    return "panels/square.png", true, false
end

Tabletop.FrozenImage = FrozenImage

--Whether a map's own initiative is running (initiative is per map).
function Tabletop.MapInCombat(mapid)
    local queue = dmhub.GetMapInitiativeQueue(mapid)
    return queue ~= nil and not queue.hidden
end

--The hover card for a minimized window's button (floating or docked): the
--map's name, whether it is in combat or shared, and what it last showed.
ShowPreviewTooltip = function(rec, element)
    local image, placeholder = FrozenImage(rec)
    local width = 260
    local height = math.floor(width * rec.height / math.max(1, rec.width))
    height = math.max(110, math.min(200, height))

    local status = {}
    local queue = dmhub.GetMapInitiativeQueue(rec.mapid)
    if queue ~= nil and not queue.hidden then
        status[#status+1] = string.format("In combat - Round %d", queue.round)
    end
    if IsShared(rec.mapid) then
        status[#status+1] = cond(dmhub.isDM, "Shared with players", "Shared by the Director")
    end
    status[#status+1] = "Click to open"

    local content = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",
        gui.Label{
            text = MapName(rec.mapid),
            bold = true,
            fontSize = 16,
            color = "#f2ede1",
            width = "auto",
            height = "auto",
            halign = "left",
            textWrap = false,
        },
        gui.Label{
            text = table.concat(status, "  -  "),
            fontSize = 12,
            color = "#bdb3a4",
            width = "auto",
            height = "auto",
            halign = "left",
            textWrap = false,
            bmargin = 6,
        },
        gui.Panel{
            bgimage = image,
            bgcolor = cond(placeholder, "#1b1814ff", "white"),
            width = width,
            height = height,
            halign = "left",
            cornerRadius = 4,
            saturation = cond(placeholder, 1, 0.85),
        },
    }
    element.tooltip = gui.TooltipFrame(content)
end

--A frozen window's round, when its map is in combat, else nil.
local function FrozenRound(rec)
    local queue = dmhub.GetMapInitiativeQueue(rec.mapid)
    if queue ~= nil and not queue.hidden then
        return string.format("Round %d", queue.round)
    end
    return nil
end

Refresh = function()
    ResolveLive()

    local liveRec = WindowById(g_liveId)
    local liveShown = liveRec ~= nil and liveRec.panel ~= nil and liveRec.panel.valid and not liveRec.minimized
    --windowed or maximized (in the strip), the live window has the map's
    --name, position and Round; the app title bar's copies stay collapsed.
    local statusInWindow = liveShown

    --move the Round panel out of a window before that window stops being
    --live, then into the new live window.
    if not statusInWindow then
        ReleaseMapStatus()
    end

    --no window shows the map (the empty table): the hidden map's name and
    --Round stay out of the title bar too.
    if not liveShown then
        CodexTitleBar.SetMapStatusInWindow(true)
    end

    for _,rec in ipairs(g_windows) do
        local panel = rec.panel
        if panel ~= nil and panel.valid then
            local live = rec.id == g_liveId
            panel:SetClass("focused", rec.id == g_focusedId)

            --a window that stops being live: its live body stays on screen for
            --the frame its collapse takes to apply, so it shows the map's
            --snapshot (taken the frame before), not a white square.
            local liveImage = "#MapView"
            if not live then
                liveImage = cond(dmhub.HasMapSnapshot(rec.mapid), "#MapSnapshot:" .. rec.mapid, "panels/square.png")
            end
            if rec.liveImage ~= liveImage then
                rec.liveImage = liveImage
                rec.liveBody.bgimage = liveImage
            end
            rec.liveBody:SetClass("collapsed", not live)
            rec.frozenBody:SetClass("collapsed", live)
            rec.liveStatus:SetClass("collapsed", not live)
            g_chrome.RefreshVisionChip(rec)

            local name = MapName(rec.mapid)
            if rec.nameLabel.text ~= name then
                rec.nameLabel.text = name
            end
            local round = nil
            if not live then
                local image, placeholder, snapshot = FrozenImage(rec)
                if placeholder then
                    g_chrome.ShowImage(rec.snapHolder, nil)
                elseif snapshot then
                    g_chrome.ShowImage(rec.snapHolder, image)
                else
                    --a picture of the whole map (its thumbnail, pack art or
                    --loading art) until the engine visits the map for its
                    --snapshot: cropped to the window's shape, not stretched.
                    g_chrome.ShowImage(rec.snapHolder, image)
                    g_chrome.CoverFit(rec.snapHolder, rec.frozenBody, rec.mapid)
                end
                rec.frozenSnapshot = snapshot
                rec.frozenBody:SetClass("tabletopPlaceholder", placeholder)
                rec.frozenBody:SetClass("tabletopArt", not snapshot)
                g_chrome.UpdateFrozenHint(rec)
                g_chrome.SyncFrozenTokens(rec)
                round = FrozenRound(rec)
            end
            g_chrome.UpdateCover(rec)
            rec.roundLabel:SetClass("collapsed", round == nil)
            if round ~= nil and rec.roundLabel.text ~= round then
                rec.roundLabel.text = round
            end

            --held maximized by the Director: no way out of it here.
            local forced = IsForcedHere(rec)
            for _, button in ipairs(rec.windowButtons) do
                if button:HasClass("collapsed") ~= forced then
                    button:SetClass("collapsed", forced)
                end
            end

            rec.combatBadge:SetClass("collapsed", live or not Tabletop.MapInCombat(rec.mapid))
            UpdateShare(rec.share)
            Tabletop.ApplyCollapsed(rec)
        end
        UpdateTableButton(rec)
    end

    if statusInWindow and liveRec ~= nil then
        CodexTitleBar.SetMapStatusInWindow(true)
        CodexTitleBar.SetInitiativeStatusHost(liveRec.initiativeSlot)
    end

    local hudHost = nil
    if liveShown and liveRec ~= nil then
        hudHost = liveRec.overlay
    end
    --the maps open in windows stay loaded (hidden) when left, so switching
    --back to them is quick; the engine keeps up to three.
    --Shown windows whose map has no picture yet are visited by the engine
    --behind a cover so they get one (never minimized ones: being on a
    --window's map opens it back up).
    --Never the map we are already heading to (a window just dropped or
    --clicked): a visit then would bounce back to the old map, leaving the
    --new window frozen until clicked again.
    local heading = dmhub.mapTransitionMapId
    if heading == nil and g_travelTarget ~= nil and dmhub.Time() < g_travelTarget.time + 10 then
        heading = g_travelTarget.mapid
    end
    local windowMaps = {}
    local needPictures = {}
    for _, rec in ipairs(g_windows) do
        windowMaps[#windowMaps+1] = rec.mapid
        if rec.id ~= g_liveId and rec.mapid ~= heading and not rec.minimized and not dmhub.HasMapSnapshot(rec.mapid) then
            needPictures[#needPictures+1] = rec.mapid
        end
    end
    dmhub.SetTabletopWindowMaps(windowMaps, needPictures)

    PlaceMapHuds(hudHost)
    --keyed on the host actually being on screen (a window growing back out
    --of its button is still collapsed for the length of the animation).
    local visibleHost = Tabletop.MapOverlayHost()
    if visibleHost ~= g_lastHudHost then
        g_lastHudHost = visibleHost
        if visibleHost ~= nil then
            --a dialog presented for this map while no window showed it
            --(the "Draw Steel" banner) can open now.
            Tabletop.RecheckPresentedDialog()
        end
    end

    g_chrome.Sync()
end

----------------------------------------------------------------------
--Opening, focusing, closing.

--fromPress: the mouse button (0 left, 1 right, 2 middle) of a press on the
--map's frozen window that started this (map:TravelFromPress), else nil.
Travel = function(mapid, fromPress)
    if mapid == game.currentMapId then
        return
    end
    if g_travelTarget ~= nil and g_travelTarget.mapid == mapid and dmhub.Time() < g_travelTarget.time + 10 then
        return
    end
    local map = game.GetMap(mapid)
    if map ~= nil and map.valid then
        g_travelTarget = {mapid = mapid, time = dmhub.Time()}
        if fromPress then
            map:TravelFromPress(fromPress)
        else
            map:Travel()
        end
    end
end

IsOpen = function(rec)
    for _,other in ipairs(g_windows) do
        if other == rec then
            return true
        end
    end
    return false
end

local function EnsureBuilt(rec)
    if rec.panel == nil or not rec.panel.valid then
        BuildWindow(rec)
    end
    PlaceWindow(rec)
end

--fromPress: the button of a press on the window's frozen map (see Travel).
--keepPlace: focus it without raising it (the window's own click: the press
--already raised it).
Focus = function(rec, fromPress, keepPlace)
    --a click on a window's close button also reaches the window itself.
    if not IsOpen(rec) then
        return
    end
    --hidden on the closed Director's Screen: the screen opens to show it.
    DirectorScreen.Reveal(g_sharing.ScreenKey(rec))
    if rec.minimized then
        RestoreWindow(rec)
        return
    end
    --covered by the maximized map window: it takes the maximize over, and the
    --other goes back to its windowed spot under it (David, 2026-10-15).
    --ToggleMaximize focuses it again, maximized.
    if g_chrome.CoveringMap(rec) ~= nil then
        ToggleMaximize(rec)
        return
    end
    if not keepPlace then
        BringToFront(rec)
    end
    if g_focusedId ~= rec.id then
        g_focusedId = rec.id
        SaveSoon()
    end
    Travel(rec.mapid, fromPress)
    Refresh()
end

CloseWindow = function(rec)
    DestroyWindowPanel(rec)
    if rec.button ~= nil and rec.button.valid then
        rec.button:DestroySelf()
    end
    rec.button = nil
    if IsDocked(rec) then
        IconRailKeyPurge(RailKey(rec))
    end
    if rec.maximized then
        Tabletop.SetForced(rec.mapid, false)
    end
    for i,other in ipairs(g_windows) do
        if other == rec then
            table.remove(g_windows, i)
            break
        end
    end
    if g_focusedId == rec.id then
        g_focusedId = nil
    end
    local wasLive = g_liveId == rec.id
    if wasLive then
        --the map stays loaded but hidden: the table with no map on it.
        g_liveId = nil
    end
    Refresh()
    if wasLive and g_liveId == nil then
        --no window shows the loaded map any more, so its tokens cannot stay
        --selected (the action bar and sheets would still act on them). A
        --card's creature selected off the board stays selected.
        local keep = {}
        for _, tok in ipairs(dmhub.selectedTokens) do
            if not tok.onBoard then
                keep[#keep+1] = tok
            end
        end
        dmhub.selectedTokens = keep
    end
    SaveSoon()
end

--A window the Director has forced maximized here cannot be closed.
RequestClose = function(rec)
    if IsForcedHere(rec) then
        return
    end
    CloseWindow(rec)
end

ToggleMaximize = function(rec)
    if IsForcedHere(rec) then
        return
    end
    local view = Tabletop.CaptureView(rec)
    rec.maximized = not rec.maximized
    if rec.maximized then
        --one maximized window at a time
        UnmaximizeScenes()
        for _,other in ipairs(g_windows) do
            if other ~= rec and other.maximized then
                --taking the maximize over: this one goes into its place.
                rec.stackAbove = other.panel
                other.maximized = false
                PlaceWindow(other)
                Tabletop.SetForced(other.mapid, false)
            end
        end
    end
    PlaceWindow(rec)
    Tabletop.KeepView(rec, view)
    --the Director's maximize is forced on the tables of the map's players.
    Tabletop.SetForced(rec.mapid, rec.maximized == true)
    Focus(rec)
    SaveSoon()
    --the map rail moves onto (or off) the screen rails now rather than on
    --their next poll.
    local mapRail = rawget(_G, "MapRail")
    if mapRail ~= nil then
        mapRail.CheckMerged()
    end
    if rec.mapRailHost ~= nil and rec.mapRailHost.valid then
        rec.mapRailHost:FireEvent("syncMapRail")
    end
end

--Opens a map on the table (the Maps panel calls this in tabletop mode).
--A map that already has a window focuses it. Otherwise it opens in the
--focused window, or in a new window when there is no focused window or
--options.newWindow is set. Either way the window takes the map's shape
--(Tabletop.MapWindowSize) and zooms out to show all of it.
function Tabletop.OpenMap(mapid, options)
    options = options or {}

    local existing = WindowForMap(mapid)
    if existing ~= nil then
        Focus(existing)
        return
    end

    local shapedW, shapedH = Tabletop.MapWindowSize(mapid)

    local focused = WindowById(g_focusedId)
    if focused ~= nil and not options.newWindow then
        if shapedW ~= nil then
            --reshaped about its centre, kept on the table. A maximized (or
            --forced) window stays as it is and just zooms out.
            if not focused.maximized and not IsForcedHere(focused) then
                local tw, th = LayerSize()
                local cx, cy = focused.x + focused.width / 2, focused.y + focused.height / 2
                focused.width, focused.height = shapedW, shapedH
                focused.x = math.max(0, math.min(math.floor(cx - shapedW / 2), tw - shapedW))
                focused.y = math.max(0, math.min(math.floor(cy - shapedH / 2), th - shapedH))
                if not focused.minimized then
                    PlaceWindow(focused)
                end
            end
            Tabletop.FrameWhenLive(focused, mapid, {})
        end
        if focused.id == g_liveId and mapid ~= game.currentMapId then
            --the window keeps showing its map until we arrive, so the engine
            --can freeze it on the way out; then it takes the new map.
            g_pendingAdopt = {mapid = mapid, windowId = focused.id}
            Travel(mapid)
            return
        end
        focused.mapid = mapid
        if focused.panel ~= nil and focused.panel.valid then
            focused.nameLabel.text = MapName(mapid)
        end
        Focus(focused)
        SaveSoon()
        return
    end

    local rec = NewWindowRecord(mapid)
    if shapedW ~= nil then
        rec.x, rec.y, rec.width, rec.height = DefaultPlacement(shapedW, shapedH)
    end
    g_windows[#g_windows+1] = rec
    EnsureBuilt(rec)
    Focus(rec)
    SaveSoon()
    if shapedW ~= nil then
        Tabletop.FrameWhenLive(rec, mapid, {})
    end
end

--- The map windows, for the Ctrl+Tab window switcher (WindowSwitcher.lua),
--- which sorts them by their panels' activationOrder. Activating one focuses
--- it as a click does: a minimized one opens, and its map becomes live.
--- @return SwitcherWindow[]
function Tabletop.SwitcherMapWindows()
    local result = {}
    if not Tabletop.IsActive() then
        return result
    end
    for _, rec in ipairs(g_windows) do
        local image, placeholder = FrozenImage(rec)
        result[#result+1] = {
            key = "map:" .. rec.id,
            kind = "map",
            name = MapName(rec.mapid),
            panel = rec.panel,
            image = image,
            placeholder = placeholder,
            minimized = rec.minimized == true,
            maximized = rec.maximized == true,
            live = rec.id == g_liveId,
            combat = Tabletop.MapInCombat(rec.mapid),
            activate = function()
                Focus(rec)
                --picked by name: a maximized window comes up too (BringToFront leaves it).
                if rec.maximized and not rec.minimized and rec.panel ~= nil and rec.panel.valid then
                    rec.panel:SetAsLastSibling()
                end
            end,
        }
    end
    return result
end

--The engine changed the current map (travel, a token moving maps, a
--journal link...). A window already showing the new map takes over, with
--a highlight when the change was not the user's own click; otherwise the
--window that was live, or the one waiting for this map, shows it now.
local function OnCurrentMapChanged(newMapId, fromMapId)
    local adopt = g_pendingAdopt
    g_pendingAdopt = nil
    g_travelTarget = nil

    --what each window showed before the change, for the cover over the one
    --that takes the new map: the live one the old map (frozen on the way
    --out), the others their frozen image.
    local prevLiveId = g_liveId
    local prevMapIds = {}
    for _, rec in ipairs(g_windows) do
        prevMapIds[rec.id] = rec.mapid
    end

    --The engine visiting maps behind a cover to take their windows'
    --pictures (dmhub.SetTabletopWindowMaps): only which window is live
    --changes. Nothing comes forward, flashes, refocuses or is saved.
    if dmhub.mapWindowPictureVisit then
        local visited = WindowForMap(newMapId)
        g_liveId = visited ~= nil and visited.id or nil
        g_chrome.cover = nil
        Refresh()
        return
    end

    local requested = WindowById(g_focusedId)
    local target = WindowForMap(newMapId)
    local unrequested = requested == nil or requested.mapid ~= newMapId

    if target == nil then
        local adopter = nil
        if adopt ~= nil and adopt.mapid == newMapId then
            adopter = WindowById(adopt.windowId)
            unrequested = false
        end
        adopter = adopter or WindowById(g_liveId) or requested
        if adopter ~= nil then
            adopter.mapid = newMapId
            if adopter.panel ~= nil and adopter.panel.valid then
                adopter.nameLabel.text = MapName(newMapId)
            end
            target = adopter
            unrequested = false
        end
    end

    if target ~= nil then
        --a window that just took the new map stays where it is in the stack
        --(the user may be working in the Maps panel above it); a different
        --window taking over comes forward.
        if target.id ~= g_liveId then
            BringToFront(target)
        end
        g_liveId = target.id
        g_focusedId = target.id
        if target.minimized then
            --we are on its map now: it opens back up. Not a card on the
            --Director's Screen: a map row dropped there opens a window,
            --travels to its map and is shrunk to a card before the travel
            --lands (Venla, 2026-10-19); double-clicking the card grows it.
            if not target.card then
                RestoreWindow(target)
            end
        elseif g_chrome.CoveringMap(target) ~= nil then
            --hidden under the maximized map: it takes the maximize over.
            ToggleMaximize(target)
        end
        if unrequested then
            Highlight(target)
        end
    else
        g_liveId = nil
    end

    --a switch the engine plays in the windows (not behind the loading
    --screen): the window taking the map is covered until the map is ready.
    g_chrome.cover = nil
    if target ~= nil and dmhub.mapTransitionMapId == newMapId then
        local image, placeholder
        if target.id == prevLiveId and fromMapId ~= nil and dmhub.HasMapSnapshot(fromMapId) then
            image, placeholder = "#MapSnapshot:" .. fromMapId, false
        else
            image, placeholder = FrozenImage({mapid = prevMapIds[target.id] or newMapId})
        end
        g_chrome.cover = {windowId = target.id, mapid = newMapId, image = image, placeholder = placeholder}
        --a frozen window showing its map's live tokens: the cover shows them too.
        if target.id ~= prevLiveId and target.tokenLayer ~= nil and target.tokenLayer.valid and not target.tokenLayer:HasClass("collapsed") then
            g_chrome.cover.tokenLayer = target.tokenLayer
        end
    end

    Refresh()
    SaveSoon()
end

----------------------------------------------------------------------
--Lifecycle: the tabletop layer is rebuilt with every GameHud; the window
--records survive and are rebuilt into it.

local function Teardown()
    for _,rec in ipairs(g_windows) do
        DestroyWindowPanel(rec)
        if rec.button ~= nil and rec.button.valid then
            rec.button:DestroySelf()
        end
        rec.button = nil
    end
    ReleaseMapStatus()
    PlaceMapHuds(nil)
    g_chrome.Sync()
end

--Where a dialog presented for the current map (args.mapid, e.g. the "Draw
--Steel" banner) opens in the tabletop view: over the map inside its live
--window. nil outside a game, or when no window shows the map (the empty
--table), in which case GameHud waits rather than show it over the table.
function Tabletop.MapOverlayHost()
    if not Tabletop.IsActive() then
        return nil
    end
    local live = WindowById(g_liveId)
    if live == nil or live.minimized or live.overlay == nil or not live.overlay.valid then
        return nil
    end
    --covered by another maximized window: not on screen either.
    if live.panel == nil or not live.panel.valid or live.panel:HasClass("collapsed") then
        return nil
    end
    return live.overlay
end

local function MapExists(mapid)
    local map = game.GetMap(mapid)
    return map ~= nil and map.valid
end

----------------------------------------------------------------------
--Dialogs presented for a map (the "Draw Steel" banner) that this client
--missed because no window showed the map. GameHud drops a dialog past its
--ttl; one this client never showed is instead shown the next time a window
--shows its map, while that map is still in combat.

--How long a missed map dialog keeps waiting for its window.
local LATE_DIALOG_SECONDS = 1800

--Presentations this client has shown (or that predate its arrival).
local g_shownMapDialogs = {}

local function MapDialogKey(data)
    return string.format("%s|%s|%s", tostring(data.timestamp), tostring(data.dialog.dialog), tostring(data.dialog.args.mapid))
end

function Tabletop.NoteMapDialogShown(data)
    g_shownMapDialogs[MapDialogKey(data)] = true
end

function Tabletop.ShowLateMapDialog(data)
    if not Tabletop.IsActive() then
        return false
    end
    local mapid = data.dialog.args.mapid
    if mapid == nil or mapid ~= game.currentMapId or g_shownMapDialogs[MapDialogKey(data)] then
        return false
    end
    if Tabletop.MapOverlayHost() == nil or not Tabletop.MapInCombat(mapid) then
        return false
    end
    return TimestampAgeInSeconds(data.timestamp) < LATE_DIALOG_SECONDS
end

--A client arriving mid-combat does not replay the banner it was not
--there for.
local function NoteExistingMapDialog()
    local data = mod:GetDocumentSnapshot("presentdialog").data
    if type(data.dialog) == "table" and type(data.dialog.args) == "table" and data.dialog.args.mapid ~= nil then
        Tabletop.NoteMapDialogShown(data)
    end
end

--Called when a window starts showing the map: GameHud re-checks the
--presented dialog (it otherwise only looks when the document changes).
function Tabletop.RecheckPresentedDialog()
    local hud = GameHud.instance
    if hud ~= nil and hud.parentPanel ~= nil and hud.parentPanel.valid then
        hud.parentPanel:FireEvent("refreshGame")
    end
end

----------------------------------------------------------------------
--Sharing. The Director shares table items -- NPC cards, journal entries
--and scenes -- with the players' tables through the "tabletop" shared
--document:
--  data.items[itemId]  {kind = "card", charid = ..., seq = n}
--                      {kind = "doc", entryid = ..., seq = n} (a journal entry)
--                      {kind = "scene", sceneid = ..., seq = n} (a Scenes library scene)
--  data.seq            the last seq handed out
--  data.forced[mapid]  true while the Director has that map maximized
--An item shared with only some players also has users = {userid = seq}
--and all = false (all = true once every player is back in users). Without
--users it goes to every player, including ones who join later.
--Each share, and each re-share, takes a new seq. A player's table opens
--every item shared with them whose seq it has not seen yet, then leaves it
--to them: they keep, move or close it, and it comes back only when it is
--shared with them again.
--A map the Director maximizes is forced maximized on the tables of the
--players with a token on it until the Director restores it.
--Maps are not in the document: a map window's share button is the map's
--Player Viewable setting, for all players or chosen ones (g_sharing.MapStore).
--A player's table opens a map when it becomes viewable for them and closes
--it when it stops, unless they have a token there (SyncViewableMaps).

local SHARE_DOC = "tabletop"

local function ShareDoc()
    return mod:GetDocumentSnapshot(SHARE_DOC)
end

local function SharedItems()
    local items = ShareDoc().data.items
    if type(items) ~= "table" then
        return {}
    end
    return items
end

local function CardItemId(charid)
    return "card:" .. charid
end

--Whether an item goes to every player: item.all, or no item.users at all
--(as with every share made before sharing with some players).
local function SharedWithAll(item)
    return item.users == nil or item.all == true
end

--The seq a player's table opens a shared item at, or nil when the item is
--not shared with them. item.users maps userid -> seq for players given
--their own seq (added one at a time); the rest of "all" use item.seq.
local function ShareSeqFor(item, userid)
    if type(item.users) == "table" and item.users[userid] ~= nil then
        return tonumber(item.users[userid])
    end
    if SharedWithAll(item) then
        return tonumber(item.seq)
    end
    return nil
end

--The players an item can be shared with: everyone in the game but the
--Directors, by name.
local function SharePlayers()
    local result = {}
    for _, uid in ipairs(dmhub.users) do
        if not dmhub.IsUserDM(uid) then
            result[#result+1] = uid
        end
    end
    table.sort(result, function(a, b)
        return string.lower(dmhub.GetDisplayName(a) or "") < string.lower(dmhub.GetDisplayName(b) or "")
    end)
    return result
end

--nil (not shared), "all" or "some" (shared with only some players).
local function ShareState(itemId)
    local item = SharedItems()[itemId]
    if type(item) ~= "table" then
        return nil
    end
    if SharedWithAll(item) then
        return "all"
    end
    return "some"
end

--Shared at all for the Director; shared with this user for a player.
local function IsItemSharedHere(itemId)
    local item = SharedItems()[itemId]
    if type(item) ~= "table" then
        return false
    end
    return dmhub.isDM or ShareSeqFor(item, dmhub.userid) ~= nil
end

function Tabletop.IsCardShared(charid)
    return IsItemSharedHere(CardItemId(charid))
end

--- Whether the Director shares a scene, but not with this player: the
--- full-screen display then keeps it from them (FullscreenDisplay.lua). A
--- scene not shared at all is not kept back (a journal tag can show it).
--- @param sceneid string
--- @return boolean
function Tabletop.SceneShareExcludesMe(sceneid)
    if dmhub.isDM then
        return false
    end
    local item = SharedItems()["scene:" .. sceneid]
    return type(item) == "table" and ShareSeqFor(item, dmhub.userid) == nil
end

--- The path of the document shares are kept in, for monitorGame.
--- @return string
function Tabletop.ShareDocPath()
    return ShareDoc().path
end

--Shares (or shares again) an item: it opens on every player's table.
local function ShareItem(itemId, item)
    local doc = ShareDoc()
    doc:BeginChange()
    if type(doc.data.items) ~= "table" then
        doc.data.items = {}
    end
    doc.data.seq = (tonumber(doc.data.seq) or 0) + 1
    item.seq = doc.data.seq
    doc.data.items[itemId] = item
    doc:CompleteChange("Share on the table", {undoable = false})
end

local function UnshareItem(itemId)
    local doc = ShareDoc()
    if type(doc.data.items) ~= "table" or doc.data.items[itemId] == nil then
        return
    end
    doc:BeginChange()
    --a new seq so the players' tables (and the Director's other windows)
    --notice it is gone; SyncShares then closes what the share opened.
    doc.data.seq = (tonumber(doc.data.seq) or 0) + 1
    doc.data.items[itemId] = nil
    doc:CompleteChange("Stop sharing on the table", {undoable = false})
end

--Shares an item with every player, now and joining later. Players who did
--not have it get a new seq, so it opens on their tables; the rest keep
--theirs, so a table where it was closed is left alone.
local function ShareWithAll(itemId, newItem)
    local current = SharedItems()[itemId]
    if type(current) ~= "table" then
        ShareItem(itemId, newItem)
        return
    end
    local doc = ShareDoc()
    doc:BeginChange()
    doc.data.seq = (tonumber(doc.data.seq) or 0) + 1
    local item = doc.data.items[itemId]
    local users = {}
    for _, uid in ipairs(SharePlayers()) do
        users[uid] = ShareSeqFor(item, uid) or doc.data.seq
    end
    item.users = users
    item.all = true
    doc:CompleteChange("Share on the table", {undoable = false})
end

--Shares an item with one more player (it opens on their table at a new
--seq), or stops sharing it with one. Every player then gets their own entry
--in item.users; with all of them in it, it counts as shared with all again,
--and with none of them it is not shared at all.
local function SetSharedWithPlayer(itemId, newItem, userid, on)
    if type(SharedItems()[itemId]) ~= "table" and not on then
        return
    end
    local players = SharePlayers()
    local doc = ShareDoc()
    doc:BeginChange()
    if type(doc.data.items) ~= "table" then
        doc.data.items = {}
    end
    --a new seq even when nothing opens anywhere: the seq changing is how
    --the Director's other windows notice the share changed.
    doc.data.seq = (tonumber(doc.data.seq) or 0) + 1
    local item = doc.data.items[itemId]
    if type(item) ~= "table" then
        item = newItem
        item.seq = doc.data.seq
        item.users = {}
        item.all = false
        doc.data.items[itemId] = item
    end
    local users = {}
    for _, uid in ipairs(players) do
        users[uid] = ShareSeqFor(item, uid)
    end
    if on then
        users[userid] = users[userid] or doc.data.seq
    else
        users[userid] = nil
    end
    local count = 0
    for _, uid in ipairs(players) do
        if users[uid] ~= nil then
            count = count + 1
        end
    end
    if count == 0 then
        doc.data.items[itemId] = nil
    else
        item.users = users
        item.all = count == #players
    end
    doc:CompleteChange("Share on the table", {undoable = false})
end

--A share control reads and changes its item's share through a store, so a
--map's button can work on the map's Player Viewable setting while cards,
--journal entries and scenes use the shared document.
--- @class TabletopShareStore
--- @field state fun(): nil|string nil, "all" or "some"
--- @field isSharedWith fun(userid: string): boolean
--- @field share fun() share with every player (a click)
--- @field unshare fun()
--- @field shareAll fun() "All players" in the menu
--- @field setPlayer fun(userid: string, on: boolean)

--- @param itemId string
--- @param newItem fun(): table the item record to share (kind and id)
--- @return TabletopShareStore
g_sharing.DocStore = function(itemId, newItem)
    return {
        state = function()
            return ShareState(itemId)
        end,
        isSharedWith = function(userid)
            local item = SharedItems()[itemId]
            return type(item) == "table" and ShareSeqFor(item, userid) ~= nil
        end,
        share = function()
            ShareItem(itemId, newItem())
        end,
        unshare = function()
            UnshareItem(itemId)
        end,
        shareAll = function()
            ShareWithAll(itemId, newItem())
        end,
        setPlayer = function(userid, on)
            SetSharedWithPlayer(itemId, newItem(), userid, on)
        end,
    }
end

--A map's share is its Player Viewable setting: on for every player
--(players joining later too), or for the players picked one by one.
--- @param mapid string
--- @return TabletopShareStore
g_sharing.MapStore = function(mapid)
    local function Map()
        local map = game.GetMap(mapid)
        if map == nil or not map.valid then
            return nil
        end
        return map
    end
    return {
        state = function()
            local map = Map()
            if map == nil then
                return nil
            end
            if map.playerViewableAll then
                return "all"
            end
            if next(map.playerViewableUsers or {}) ~= nil then
                return "some"
            end
            return nil
        end,
        isSharedWith = function(userid)
            local map = Map()
            return map ~= nil and map:IsPlayerViewableFor(userid)
        end,
        share = function()
            local map = Map()
            if map ~= nil then
                map:SetPlayerViewable(true, nil)
            end
        end,
        unshare = function()
            local map = Map()
            if map ~= nil then
                map:SetPlayerViewable(false, nil)
            end
        end,
        shareAll = function()
            local map = Map()
            if map ~= nil then
                map:SetPlayerViewable(true, nil)
            end
        end,
        setPlayer = function(userid, on)
            local map = Map()
            if map == nil then
                return
            end
            local players = SharePlayers()
            local users = {}
            for _, uid in ipairs(players) do
                if map:IsPlayerViewableFor(uid) then
                    users[uid] = true
                end
            end
            users[userid] = on or nil
            local count = 0
            for _, uid in ipairs(players) do
                if users[uid] then
                    count = count + 1
                end
            end
            --every player picked counts as all players again, as with shares.
            if count > 0 and count == #players then
                map:SetPlayerViewable(true, nil)
            else
                map:SetPlayerViewable(false, users)
            end
        end,
    }
end

--Shared at all for the Director; viewable by this user for a player.
IsShared = function(mapid)
    local store = g_sharing.MapStore(mapid)
    if dmhub.isDM then
        return store.state() ~= nil
    end
    return store.isSharedWith(dmhub.userid)
end

--The players an item is shared with, by name, for its tooltip.
--- @param store TabletopShareStore
local function SharedNames(store)
    local names = {}
    for _, uid in ipairs(SharePlayers()) do
        if store.isSharedWith(uid) then
            names[#names+1] = dmhub.GetDisplayName(uid) or "?"
        end
    end
    return table.concat(names, ", ")
end

--The Director's pick of players for an item, opened by right-clicking its
--share control. It stays open, rebuilt after each pick, so several players
--can be checked or unchecked in a row.
local function ShowSharePlayersMenu(share, element)
    local store = share.store
    local state = store.state()
    local players = SharePlayers()

    local function Changed()
        UpdateShare(share)
        if share.changed ~= nil then
            share.changed()
        end
        if element.valid then
            ShowSharePlayersMenu(share, element)
        end
    end

    --(the first entry never gets a divider after it, so the heading keeps
    --one between "All players" and the players.)
    local entries = {
        {text = "Share with:", disabled = true, group = "heading"},
        {
            text = "All players",
            check = state == "all",
            group = "all",
            click = function()
                GuardClicks()
                if state == "all" then
                    store.unshare()
                else
                    store.shareAll()
                end
                Changed()
            end,
        },
    }
    for _, uid in ipairs(players) do
        local on = store.isSharedWith(uid)
        entries[#entries+1] = {
            text = dmhub.GetDisplayName(uid) or "?",
            check = on,
            group = "players",
            click = function()
                GuardClicks()
                store.setPlayer(uid, not on)
                Changed()
            end,
        }
    end
    if #players == 0 then
        entries[#entries+1] = {text = "No players in this game", disabled = true, group = "players"}
    end
    element.popup = gui.ContextMenu{entries = entries}
end

--The grey frame drawn around a table item the Director has not shared,
--unless it is behind the Director's Screen (where nothing is shared). Shared
--items have no frame: a blue one was too loud (David, 2026-10-16).
local function ShareFrame(cornerRadius)
    return gui.Panel{
        styles = ThemeEngine.MergeTokens{
            {
                selectors = {"tabletopShareFrame"},
                borderColor = "@fgMuted",
            },
        },
        classes = {"tabletopShareFrame", "collapsed"},
        floating = true,
        interactable = false,
        halign = "center",
        valign = "center",
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        borderWidth = 2,
        cornerRadius = cornerRadius or 0,
    }
end

--The Director's share toggle for a table item. A click shares it with
--every player or stops sharing it; a right-click picks players one by one.
--Returns {button, frame, itemId, ...}: the button goes in the titlebar's
--controls, the frame among the item's own children, and UpdateShare keeps
--both current.
--args: store (a TabletopShareStore), or itemId and newItem, a function
--making the item record to share (kind and id), for an item in the shared
--document; what ("this map") for the tooltip; changed, called after the
--Director changes the share; iconSize, width, passPress and beforeHover
--(called before the tooltip shows) for the button; cornerRadius for the
--frame.
ShareControl = function(args)
    local icon = "phosphor/share-network.png"
    --lit over the top half of the glyph while shared with some players.
    --imageRect counts up from the bottom, so the top half is 0.5 to 1.
    local half = gui.Panel{
        classes = {"tabletopShareHalf", "collapsed"},
        bgimage = icon,
        width = "100%",
        height = "50%",
        halign = "center",
        valign = "top",
        imageRect = {x1 = 0, y1 = 0.5, x2 = 1, y2 = 1},
        interactable = false,
    }
    local share = {
        store = args.store or g_sharing.DocStore(args.itemId, args.newItem),
        changed = args.changed,
        half = half,
        frame = ShareFrame(args.cornerRadius),
    }
    share.button = WindowControl{
        icon = icon,
        iconSize = args.iconSize,
        width = args.width,
        passPress = args.passPress,
        iconChildren = {half},
        hover = function(element)
            if args.beforeHover ~= nil then
                args.beforeHover()
            end
            local state = share.store.state()
            local text
            if state == "all" then
                text = "Shared with all players. Click to stop sharing; right-click to choose players."
            elseif state == "some" then
                text = string.format("Shared with %s. Click to stop sharing; right-click to choose players.", SharedNames(share.store))
            else
                text = string.format("Share %s with the players' tables. Right-click to choose players.", args.what or "this")
            end
            gui.Tooltip(text)(element)
        end,
        click = function(element)
            if share.store.state() ~= nil then
                share.store.unshare()
            else
                share.store.share()
            end
            UpdateShare(share)
            if share.changed ~= nil then
                share.changed()
            end
        end,
        rightClick = function(element)
            element.tooltip = nil
            ShowSharePlayersMenu(share, element)
        end,
    }
    UpdateShare(share)
    return share
end

--Brings a share control (nil for players, who have none) and its item's
--frame up to date with the shared document. The frame shows while the item
--is unshared and not behind the Director's Screen (share.behind).
UpdateShare = function(share)
    if share == nil then
        return
    end
    local state = share.store.state()
    share.button:SetClass("tabletopShared", state == "all")
    share.half:SetClass("collapsed", state ~= "some")
    share.frame:SetClass("collapsed", state ~= nil or share.behind == true)
end

--The Director's Screen says whether an item lies behind it, which hides the
--item's not-shared frame (DirectorScreenItem.showBehind).
g_sharing.ShowBehind = function(share, behind)
    if share == nil or share.behind == behind then
        return
    end
    share.behind = behind
    UpdateShare(share)
end

--The Director's Screen's view of a map or scene window: the window, or its
--button on the table while minimized. store and share are its share store
--and share control; apply re-applies its hidden state.
--minimize and restore collapse the window into its button (a card, with
--rec.card set) and grow it back: the screen shrinks a window dropped on it
--into a card, and grows a card dragged off it (shrink, grow).
g_sharing.ScreenWindowItem = function(rec, store, share, apply, minimize, restore)
    local rect = nil
    local size = g_card.Size(rec)
    if rec.minimized then
        if rec.card or not IsDocked(rec) then
            local w, h = g_card.Size(rec)
            rect = {x = rec.iconX or 0, y = rec.iconY or 0, w = w, h = h}
        end
    elseif not rec.maximized then
        rect = {x = rec.x, y = rec.y, w = rec.width, h = rec.height}
    end
    return {
        key = g_sharing.ScreenKey(rec),
        rect = rect,
        maximized = rec.maximized == true and not rec.minimized,
        card = rec.minimized == true and rec.card == true,
        onButtonLayer = rec.minimized == true,
        --into a card at (x, y), on the screen: a window collapses into it, a
        --plain button becomes one.
        shrink = function(x, y)
            if minimize == nil or (rec.maximized and not rec.minimized) then
                return
            end
            rec.card = true
            rec.iconX, rec.iconY = x, y
            if rec.minimized then
                UpdateTableButton(rec)
            else
                minimize(rec)
            end
            SaveSoon()
        end,
        --a card grows back into its window at (x, y), at its full size.
        grow = function(x, y)
            if restore == nil or not rec.card then
                return
            end
            rec.card = nil
            if rec.minimized then
                rec.x, rec.y = ClampWindow(rec, x, y)
                restore(rec)
            else
                UpdateTableButton(rec)
            end
            SaveSoon()
        end,
        --free: not kept on the table (the Director's Screen carries the
        --items on it off the table's side with its edge).
        move = function(x, free)
            if rec.minimized then
                local w = LayerSize()
                rec.iconX = free and x or math.max(0, math.min(x, w - size))
                if rec.button ~= nil and rec.button.valid then
                    rec.button.x = rec.iconX
                end
            elseif not rec.maximized then
                if free then
                    rec.x = x
                else
                    rec.x, rec.y = ClampWindow(rec, x, rec.y)
                end
                if rec.panel ~= nil and rec.panel.valid then
                    rec.panel.x = rec.x
                    rec.panel.y = rec.y
                end
            end
            SaveSoon()
        end,
        store = store,
        changed = function()
            UpdateShare(share)
            if share ~= nil and share.changed ~= nil then
                share.changed()
            end
        end,
        stow = function(stowed)
            apply(rec)
            local button = rec.button
            if button ~= nil and button.valid and button:HasClass("collapsed") ~= stowed then
                button:SetClass("collapsed", stowed)
            end
        end,
        panel = function()
            if rec.minimized then
                return rec.button
            end
            return rec.panel
        end,
        shareButton = function()
            return share ~= nil and share.button or nil
        end,
        showBehind = function(behind)
            g_sharing.ShowBehind(share, behind)
        end,
    }
end

g_sharing.screenKinds[#g_sharing.screenKinds+1] = function(list)
    for _, rec in ipairs(g_windows) do
        list[#list+1] = g_sharing.ScreenWindowItem(rec, g_sharing.MapStore(rec.mapid), rec.share, Tabletop.ApplyCollapsed, Minimize, RestoreWindow)
    end
end

--A map or scene window's place, for DefineDirectorLayout: its windowed
--rectangle (kept while it is maximized or minimized, which it comes back
--to). followed() says whether the Director shares it with this player.
g_sharing.WindowLayoutItem = function(rec, followed, minWidth, minHeight)
    return {
        key = g_sharing.LayoutKey(rec),
        followed = followed,
        get = function()
            return {x = rec.x, y = rec.y, w = rec.width, h = rec.height}
        end,
        --what a ping rings (DefinePings): the window, or its button while minimized.
        target = function()
            local button = nil
            if rec.minimized and rec.button ~= nil and rec.button.valid then
                button = rec.button
            end
            return {panel = rec.panel, button = button, maximized = rec.maximized == true}
        end,
        set = function(r)
            rec.width = math.max(minWidth, math.floor(r.w + 0.5))
            rec.height = math.max(minHeight, math.floor(r.h + 0.5))
            rec.x, rec.y = ClampWindow(rec, math.floor(r.x + 0.5), math.floor(r.y + 0.5))
            local panel = rec.panel
            if panel ~= nil and panel.valid and not rec.maximized then
                panel.x = rec.x
                panel.y = rec.y
                panel.selfStyle.width = rec.width
                panel.selfStyle.height = rec.height
            end
            return true
        end,
    }
end

--a map window follows while the map is Player Viewable for this player
--(that is a map's share).
g_sharing.layoutKinds[#g_sharing.layoutKinds+1] = function(list)
    for _, rec in ipairs(g_windows) do
        list[#list+1] = g_sharing.WindowLayoutItem(rec, function()
            local map = game.GetMap(rec.mapid)
            return map ~= nil and map.valid and map.playerViewable == true
        end, MIN_WIDTH, MIN_HEIGHT)
    end
end

--- The table items the Director's Screen works on (DirectorScreen.lua):
--- map and scene windows, NPC cards and journal items.
--- @return DirectorScreenItem[]
function Tabletop.ScreenItems()
    local list = {}
    for _, kind in ipairs(g_sharing.screenKinds) do
        kind(list)
    end
    return list
end

--- Saves the table layout soon (the Director's Screen is saved with it).
function Tabletop.SaveLayoutSoon()
    SaveSoon()
end

g_layoutWriters[#g_layoutWriters+1] = function(out)
    if dmhub.isDM then
        out.directorScreen = DirectorScreen.Save()
    end
end

--The Director maximizing (or restoring) a map forces it maximized (or
--releases it) on the tables of the players with a token on it.
local function SetForced(mapid, forced)
    if not dmhub.isDM then
        return
    end
    local doc = ShareDoc()
    local current = type(doc.data.forced) == "table" and doc.data.forced[mapid] == true
    if current == forced then
        return
    end
    doc:BeginChange()
    if type(doc.data.forced) ~= "table" then
        doc.data.forced = {}
    end
    if forced then
        doc.data.forced[mapid] = true
    else
        doc.data.forced[mapid] = nil
    end
    doc:CompleteChange("Force a map maximized", {undoable = false})
end
Tabletop.SetForced = SetForced

function Tabletop.ShareCard(charid)
    ShareItem(CardItemId(charid), {kind = "card", charid = charid})
end

function Tabletop.UnshareCard(charid)
    UnshareItem(CardItemId(charid))
end

--Whether this player controls a token on a map (any map, not just the
--current one: every client has every character's location).
local function LocalPlayerHasTokenOn(mapid)
    for _, tok in pairs(game.GetGameGlobalCharacters()) do
        if tok.mapid == mapid and tok.canControlAsUser then
            local despawned = false
            pcall(function()
                despawned = tok.despawned == true
            end)
            if not despawned then
                return true
            end
        end
    end
    return false
end

--Whether this user may open a map: the Director always; a player when it
--is Player Viewable for them or one of their tokens is on it (the same
--rule as the player's Maps panel).
function Tabletop.CanAccessMap(mapid)
    if dmhub.isDM then
        return true
    end
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return false
    end
    --a map opened from a chat link (Tabletop.OpenLinkedMap) stays open for
    --this session.
    if map.playerViewable or dmhub.HasLinkedMapView(mapid) then
        return true
    end
    return LocalPlayerHasTokenOn(mapid)
end

--- Opens a map from a chat link (ChatItemLinks.lua), in a new window, or
--- brings its window up. A player who could not open the map gets a view of
--- it on this client until the app closes (dmhub.GrantLinkedMapView); the
--- map's Player Viewable setting is not changed.
--- @param mapid string
function Tabletop.OpenLinkedMap(mapid)
    if not Tabletop.CanAccessMap(mapid) then
        dmhub.GrantLinkedMapView(mapid)
    end
    Tabletop.OpenMap(mapid, {newWindow = true})
end

IsForcedHere = function(rec)
    return rec.forced == true
end

--A map made Player Viewable for this player turns up on their table: its window
--comes forward, or a new one opens beside the others. It does not travel
--there; the player clicks it when they want to look.
local function OpenSharedMap(mapid)
    local rec = WindowForMap(mapid)
    if rec == nil then
        rec = NewWindowRecord(mapid)
        g_windows[#g_windows+1] = rec
        EnsureBuilt(rec)
    end
    if rec.minimized then
        if rec.button ~= nil and rec.button.valid then
            rec.button:PulseClass("justDropped")
        end
    else
        BringToFront(rec)
        Highlight(rec)
    end
    Refresh()
end

--The maps a game mode forces on this client right now: mapid -> true. The
--active custom interface's forcedMap (GameHud.RegisterCustomInterface) is
--held the way a Director's maximized, shared map is held on a player's
--table, but for a Director too, and with no share or token needed.
g_sharing.LocalForcedMaps = function()
    local result = {}
    local mapid = nil
    pcall(function()
        mapid = GameHud.CustomInterfaceForcedMap()
    end)
    if mapid ~= nil then
        result[mapid] = true
    end
    return result
end

--What the interface forced when last applied, so a change (a test starting
--or ending, the map loading) applies on the frame it happens rather than at
--the next once-a-second recheck.
g_sharing.localForcedSignature = ""

--Forces (or releases) the Director's maximized maps on this player's
--table: a map shared with them (Player Viewable) with one of their tokens
--on it is opened, maximized and focused, and cannot be restored, minimized
--or closed while forced. Maximizing never shares a map (David, 2026-10-16):
--an unshared one is not forced, until the Director shares it.
--A game mode's custom interface can also force a map on this client,
--Director or not (GameHud forcedMap; Encounter of the Week does).
local function ApplyForced(forced)
    if type(forced) ~= "table" or dmhub.isDM then
        forced = {}
    end
    local localForced = g_sharing.LocalForcedMaps()
    local function Forces(mapid)
        if localForced[mapid] == true then
            return MapExists(mapid)
        end
        return forced[mapid] == true and MapExists(mapid) and LocalPlayerHasTokenOn(mapid) and IsShared(mapid)
    end
    local candidates = {}
    for mapid, _ in pairs(forced) do
        candidates[mapid] = true
    end
    for mapid, _ in pairs(localForced) do
        candidates[mapid] = true
    end
    for mapid, _ in pairs(candidates) do
        if Forces(mapid) then
            local rec = WindowForMap(mapid)
            if rec == nil then
                rec = NewWindowRecord(mapid)
                g_windows[#g_windows+1] = rec
                EnsureBuilt(rec)
            end
            if not rec.forced then
                --the map fills the screen as it filled the window; a window
                --that was not showing its map live shows the whole map.
                local view = Tabletop.CaptureView(rec)
                rec.forced = true
                rec.prevMaximized = rec.maximized == true
                rec.minimized = false
                UpdateTableButton(rec)
                for _, other in ipairs(g_windows) do
                    if other ~= rec and other.maximized and not other.forced then
                        --into the place of the map it replaces; with none it comes to the top.
                        rec.stackAbove = other.panel
                        other.maximized = false
                        PlaceWindow(other)
                    end
                end
                rec.maximized = true
                PlaceWindow(rec)
                Tabletop.KeepView(rec, view)
                Focus(rec)
                if view == nil then
                    Tabletop.FrameWhenLive(rec, mapid, {})
                end
            end
        end
    end
    for _, rec in ipairs(g_windows) do
        if rec.forced and not Forces(rec.mapid) then
            local view = Tabletop.CaptureView(rec)
            rec.forced = false
            rec.maximized = rec.prevMaximized == true
            rec.prevMaximized = nil
            PlaceWindow(rec)
            Tabletop.KeepView(rec, view)
            Refresh()
        end
    end
end

--Shares this player's table has already opened: itemId -> seq.
local g_seenShares = {}
--What SyncShares last acted on, so it only does work when the document changes.
local g_shareSignature = nil
--What SyncViewableMaps tracks. seen: the maps that were Player Viewable for
--this player when their table last looked (mapid -> true), saved with the
--layout so a map made viewable while they were away still opens. seed: a
--table saved before seen was kept takes the current list without opening
--anything. nextCheck: when to look again.
g_sharing.viewable = {seen = {}, seed = false, nextCheck = 0}
--A window a share opened on a player's table (not one they already had
--open) is marked fromShare, and closes when the Director stops sharing it
--with them. Each kind of table item adds a function(stillShared) here that
--closes its marked windows whose item stillShared(itemId) says is gone.
g_sharing.unshareClosers = {}

g_layoutWriters[#g_layoutWriters+1] = function(out)
    out.seenShares = g_seenShares
    out.viewableMaps = g_sharing.viewable.seen
end

SyncShares = function()
    local doc = ShareDoc()
    local items = SharedItems()

    local forcedIds = {}
    if type(doc.data.forced) == "table" then
        for mapid, on in pairs(doc.data.forced) do
            if on == true then
                forcedIds[#forcedIds+1] = mapid
            end
        end
    end
    table.sort(forcedIds)
    local signature = string.format("%s|%s", tostring(doc.data.seq), table.concat(forcedIds, ","))
    if signature == g_shareSignature then
        return
    end
    g_shareSignature = signature

    if dmhub.isDM then
        Refresh()
        return
    end

    local opened = false
    for itemId, item in pairs(items) do
        local seq = type(item) == "table" and ShareSeqFor(item, dmhub.userid) or 0
        if seq > (tonumber(g_seenShares[itemId]) or 0) then
            g_seenShares[itemId] = seq
            opened = true
            if item.kind == "card" and type(item.charid) == "string" then
                Tabletop.OpenCard(item.charid, {shared = true})
            elseif item.kind == "doc" and type(item.entryid) == "string" then
                Tabletop.OpenDocItem(item.entryid, {shared = true})
            elseif item.kind == "scene" and type(item.sceneid) == "string" then
                Tabletop.OpenScene(item.sceneid, {shared = true})
            end
        end
    end
    local function StillShared(itemId)
        local item = items[itemId]
        return type(item) == "table" and ShareSeqFor(item, dmhub.userid) ~= nil
    end
    for _, closer in ipairs(g_sharing.unshareClosers) do
        closer(StillShared)
    end
    ApplyForced(doc.data.forced)
    if opened then
        SaveSoon()
    end
end

--A player's table follows the maps' Player Viewable settings, which the
--Director's share buttons write: a map that becomes viewable for this
--player opens on their table, and one that stops closes, unless one of
--their tokens is on it. Checked four times a second.
g_sharing.SyncViewableMaps = function()
    if dmhub.isDM or dmhub.Time() < g_sharing.viewable.nextCheck then
        return
    end
    g_sharing.viewable.nextCheck = dmhub.Time() + 0.25

    local maps = game.maps
    if #maps == 0 then
        --the game's maps are not in yet; an empty list would close everything.
        return
    end
    local now = {}
    for _, map in ipairs(maps) do
        if map.valid and map.playerViewable then
            now[map.id] = true
        end
    end

    if g_sharing.viewable.seed then
        g_sharing.viewable.seed = false
        g_sharing.viewable.seen = now
        SaveSoon()
        return
    end

    local changed = false
    for mapid in pairs(now) do
        if not g_sharing.viewable.seen[mapid] then
            changed = true
            OpenSharedMap(mapid)
        end
    end
    for mapid in pairs(g_sharing.viewable.seen) do
        if not now[mapid] then
            changed = true
            local rec = WindowForMap(mapid)
            if rec ~= nil and not Tabletop.CanAccessMap(mapid) then
                CloseWindow(rec)
            end
        end
    end
    if changed then
        g_sharing.viewable.seen = now
        SaveSoon()
    end
end

--A player's table shows no window on a current map they may not view (a new
--player with no hero on the starting map). When they gain access -- their
--hero is created there, or the engine follows their hero to its map -- a
--window opens on it and becomes the live one. Only the change from no access
--to access opens one, so a window the player closed stays closed.
g_sharing.currentAccess = {ok = false, nextCheck = 0}
g_sharing.SyncCurrentMapAccess = function()
    local state = g_sharing.currentAccess
    if dmhub.isDM or dmhub.Time() < state.nextCheck then
        return
    end
    state.nextCheck = dmhub.Time() + 0.25

    local mapid = game.currentMapId
    local ok = mapid ~= nil and Tabletop.CanAccessMap(mapid)
    local gained = ok and not state.ok
    state.ok = ok
    if not gained or WindowForMap(mapid) ~= nil then
        return
    end
    local rec = NewWindowRecord(mapid)
    g_windows[#g_windows+1] = rec
    EnsureBuilt(rec)
    Focus(rec)
    SaveSoon()
end

--The forced state also depends on where this player's tokens are, which
--changes without the document changing; re-checked once a second.
local function RecheckForced()
    ApplyForced(ShareDoc().data.forced)
end

--Every frame: re-applies when what the interface forces has changed.
g_sharing.SyncLocalForced = function()
    local ids = {}
    for mapid, _ in pairs(g_sharing.LocalForcedMaps()) do
        if MapExists(mapid) then
            ids[#ids+1] = mapid
        end
    end
    table.sort(ids)
    local signature = table.concat(ids, ",")
    if signature ~= g_sharing.localForcedSignature then
        g_sharing.localForcedSignature = signature
        RecheckForced()
    end
end

----------------------------------------------------------------------
--NPC cards: characters shown on the table as cards (the Encounter of the
--Week hero card), whether or not they are on a map. Dropping a creature
--from the bestiary or the character list onto the bare table makes one
--(a bestiary creature is created with no map), and so does dragging a
--token out of its map window. Cards sit among the map windows and
--journals, are per user like windows, and the Director can share them.
--
--Hovering a card shows a small see-through titlebar just above it, with the
--Director's share toggle and the close X. Any edge or corner resizes it; the
--hero card is always built at its own size and scaled, so it keeps its shape.
--The Director can drag a card onto the live map window: its placement ghost
--shows there, and the drop teleports the character to that spot.

--{charid, x, y, scale} for each card on this user's table.
local g_cards = {}

local CARD_GAP = 24
local CARD_TITLE_HEIGHT = 22
local CARD_MIN_SCALE = 0.6
local CARD_MAX_SCALE = 3
--the corner resize grips: CARD_GRIP square, CARD_GRIP_OUT of it outside the card.
local CARD_GRIP = 18
local CARD_GRIP_OUT = 8
--the edge resize grips: CARD_EDGE thick, CARD_EDGE_OUT of it outside the card.
--The top grips run along the top of the titlebar, not the card, so the
--titlebar itself is never a resize spot; its corner grips are the smaller
--CARD_TOP_GRIP, CARD_TOP_GRIP_OUT of it outside, to stay off its controls.
local CARD_EDGE = 8
local CARD_EDGE_OUT = 4
local CARD_TOP_GRIP = 12
local CARD_TOP_GRIP_OUT = 8

--The card the Director is dragging: {card, overMap, ghost}. overMap is true
--while its placement ghost shows on the map, where a drop teleports the
--character; ghost is the faded copy left at the card's spot meanwhile, to
--show the card stays on the table.
local g_cardDrag = nil

--The hero card's own size, before a card's scale.
local function CardSize()
    return EotwHeroCard.CARD_WIDTH, EotwHeroCard.CARD_HEIGHT
end

--A table item's own size, before its scale: a card's, or what a document
--item's baseSize says (its shape depends on what it shows). The resize grips
--and ApplyCardScale work on either.
local function ItemSize(item)
    if item.baseSize ~= nil then
        return item.baseSize()
    end
    return CardSize()
end

local function CardById(charid)
    for _, card in ipairs(g_cards) do
        if card.charid == charid then
            return card
        end
    end
    return nil
end

--The card's own styles: the hero card's rules, after a reset of the
--journal layer's selector-less centring (see g_overlayStyles).
local function CardStyles()
    local styles = {
        {
            valign = "top",
            halign = "left",
            width = 100,
            height = 100,
        },
        --the titlebar and every part of it, shown while the card is hovered
        --(opacity doesn't reach children, so each part carries the class).
        {
            selectors = {"tabletopCardChrome"},
            opacity = 0,
            transitionTime = 0.15,
        },
        {
            selectors = {"tabletopCardChrome", "shown"},
            opacity = 1,
            transitionTime = 0.1,
        },
        {
            selectors = {"tabletopCardTitle"},
            bgcolor = "#1d1915a0",
        },
        --the card's shadow on the table, lifted while it is dragged.
        {
            selectors = {"tabletopCard"},
            boxShadow = TABLE_SHADOWS.rest,
        },
        {
            selectors = {"tabletopCard", "dragging"},
            boxShadow = TABLE_SHADOWS.lifted,
            transitionTime = 0.15,
        },
        --over the map, the card steps aside for its placement ghost. Scale,
        --not opacity, because opacity doesn't reach children.
        {
            selectors = {"tabletopCard", "tabletopCardOverMap"},
            scale = 0.01,
        },
        --the faded copy left in the card's place meanwhile. Opacity is per
        --panel, so the class goes on every part of the copy (SetClassTree);
        --it fades label text too.
        {
            selectors = {"tabletopCardGhost"},
            opacity = 0.4,
            saturation = 0.5,
        },
    }
    for _, rule in ipairs(ThemeEngine.MergeTokens(EotwHeroCard.rules) or {}) do
        styles[#styles+1] = rule
    end
    --a selected card's ring (CardSelectRing), and the button that opens the
    --character's sheet (CardSheetButton), shown while the card is hovered.
    local cardRules = ThemeEngine.MergeTokens{
        {
            selectors = {"tabletopCardSelectRing"},
            bgcolor = "clear",
            borderColor = "@accent",
            border = 3,
        },
        {
            selectors = {"tabletopCardSheet"},
            bgcolor = "#1d1915d0",
            opacity = 0,
            transitionTime = 0.15,
        },
        {
            selectors = {"tabletopCardSheet", "shown"},
            opacity = 1,
            transitionTime = 0.1,
        },
        {
            selectors = {"tabletopCardSheet", "hover"},
            bgcolor = "@accent",
        },
        {
            selectors = {"tabletopCardSheetIcon"},
            bgcolor = "white",
        },
    }
    for _, rule in ipairs(cardRules or {}) do
        styles[#styles+1] = rule
    end
    return styles
end

--Screen pixels (top-left origin, as the engine's drop events report them)
--to the documents layer's units.
local function ScreenToLayer(px, py)
    local layer = DocumentsLayer()
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    if layer == nil or below.y <= 0 then
        return px, py
    end
    local scale = layer.renderedHeight / below.y
    return px * scale, (py - (screen.y - below.y)) * scale
end

local function IsHeroToken(tok)
    local hero = false
    pcall(function()
        hero = tok.properties:IsHero() == true
    end)
    return hero
end

--The hero card face for a character, at its own size. options are passed
--on to CreateHeroCard (dismiss, ...).
local function CardFace(charid, tok)
    return EotwHeroCard.CreateHeroCard({charid = charid, mine = false, name = tok.name}, {
        halign = "left",
        showResources = false,
        noRecoveries = not IsHeroToken(tok),
        --the press reaches the card's frame, which is what drags (and
        --swallows the press for the map); a click selects the creature. Its
        --sheet opens from the card's sheet button (CardSheetButton).
        passPress = true,
        click = function(element)
            Tabletop.CardClicked(charid)
        end,
        --a monster from the bestiary has no name of its own.
        displayName = function(t)
            return creature.GetTokenDescription(t)
        end,
        --where the creature is: a card can stand for a token on a map.
        subtitle = function(t)
            local mapid = t.mapid
            if mapid == nil or mapid == "" then
                return "Not on a map"
            end
            return MapName(mapid)
        end,
    })
end

--Scene cards (SceneElements.lua) are the table's cards: the same face, at
--the same size, with the same styles.
Tabletop.CardFace = CardFace
Tabletop.CardSize = CardSize
Tabletop.CardStyles = CardStyles

local CloseCard

----------------------------------------------------------------------
--Selecting creature cards (table cards here, scene cards in
--SceneElements.lua). A card's selection IS its creature's selection in the
--engine (dmhub.selectedTokens): the token on the live map when it has one,
--the character off the board otherwise. So a card and its token are
--selected together, chat speaks as it, and Lua sees it as the selected token.

--Card selection state and helpers, in one table: Tabletop.lua is at Lua's
--200-locals ceiling.
--  seq/set    charid -> true for what is selected, re-read when the engine's
--             selection sequence moves (Tabletop.SelectedCharids)
--  made       what the last card click or rectangle selected (see below)
--  marquee    the selection rectangle being dragged
--  ringSeq    the sequence the table cards' rings last showed
--  group      the selected table cards following a dragged one
--- @class TabletopCardSelectionState
--- @field seq nil|integer
--- @field set table<string, boolean>
--- @field made nil|table<string, boolean>
--- @field marquee nil|TabletopCardMarquee
--- @field ringSeq nil|integer
--- @field group nil|{card: table, members: {card: table, x: number, y: number}[]}
local g_cs = {set = {}}

--- @class TabletopCardMarquee
--- @field x0 number screen pixels where the drag started
--- @field y0 number
--- @field x1 number screen pixels where the mouse is
--- @field y1 number
--- @field panel Panel the rectangle drawn on the documents layer
--- @field targets fun(): {charid: string, panel: Panel}[] the cards it can select
--- @field additive boolean Shift or Ctrl was down: the selection is added to

--What the last card click or rectangle selected. While the selection is
--still exactly that, Delete removes those cards rather than deleting the
--creatures' tokens (dmhub.DeleteSelectionPressed below).

--- The selected creatures, as a set of charids (do not modify it).
--- @return table<string, boolean>
function Tabletop.SelectedCharids()
    local seq = dmhub.selectedTokensSeq
    if seq ~= g_cs.seq then
        g_cs.seq = seq
        local set = {}
        for _, tok in ipairs(dmhub.selectedTokens or {}) do
            if tok.charid ~= nil then
                set[tok.charid] = true
            end
        end
        g_cs.set = set
    end
    return g_cs.set
end

--- The creatures with a card on this user's table, by charid (Request Rolls
--- offers the heroes among them). Cards in scenes are SceneElements'.
--- @return string[]
function Tabletop.TableCardCharids()
    local result = {}
    for _, card in ipairs(g_cards) do
        result[#result+1] = card.charid
    end
    return result
end

--- Whether this user may select a card's creature: the Director, or whoever
--- controls it (the engine applies the same rule).
--- @param charid string
--- @return boolean
function Tabletop.CanSelectCard(charid)
    local tok = dmhub.GetCharacterById(charid)
    return tok ~= nil and tok.canControlAsUser == true
end

function g_cs.NoteCardSelection()
    local made = {}
    for charid in pairs(Tabletop.SelectedCharids()) do
        made[charid] = true
    end
    g_cs.made = made
end

function g_cs.SameSet(a, b)
    for k in pairs(a) do
        if not b[k] then
            return false
        end
    end
    for k in pairs(b) do
        if not a[k] then
            return false
        end
    end
    return true
end

function g_cs.AddingToSelection()
    local mods = dmhub.modKeys
    return mods.shift == true or mods.ctrl == true
end

--- A card was clicked: its creature becomes the selection. Shift or Ctrl
--- adds it to the selection, or takes it out if it is already in.
--- @param charid string
function Tabletop.CardClicked(charid)
    if not Tabletop.CanSelectCard(charid) then
        return
    end
    if g_cs.AddingToSelection() then
        if Tabletop.SelectedCharids()[charid] then
            dmhub.RemoveTokenFromSelection(charid)
        else
            dmhub.AddTokenToSelection(charid)
        end
    else
        dmhub.SelectToken(charid)
    end
    g_cs.NoteCardSelection()
end

--- Selects the creatures of the cards a selection rectangle touched; with
--- additive the current selection stays too.
--- @param charids string[]
--- @param additive boolean
function Tabletop.SelectCards(charids, additive)
    if not additive then
        dmhub.selectedTokens = {}
    end
    for _, charid in ipairs(charids) do
        if Tabletop.CanSelectCard(charid) then
            dmhub.AddTokenToSelection(charid)
        end
    end
    g_cs.NoteCardSelection()
end

--- Clears the selection (a click on the bare table or an empty part of a scene).
function Tabletop.ClearCardSelection()
    if next(Tabletop.SelectedCharids()) ~= nil then
        dmhub.selectedTokens = {}
    end
    g_cs.made = nil
end

--- The ring a selected card wears. Put it on the card's frame and call
--- Tabletop.ShowCardSelected(ring, on) as the selection changes.
--- @param cornerRadius number
--- @return Panel
function Tabletop.CardSelectRing(cornerRadius)
    return gui.Panel{
        classes = {"tabletopCardSelectRing", "collapsed"},
        floating = true,
        halign = "center",
        valign = "center",
        width = "100%+6",
        height = "100%+6",
        cornerRadius = cornerRadius + 3,
        bgimage = "panels/square.png",
        interactable = false,
    }
end

--- @param ring Panel
--- @param on boolean
function Tabletop.ShowCardSelected(ring, on)
    if ring ~= nil and ring.valid and ring:HasClass("collapsed") == on then
        ring:SetClass("collapsed", not on)
    end
end

--- The button on a card that opens its character's sheet beside the card.
--- It fades in while the card is hovered: set its "shown" class tree from the
--- card's hover (Tabletop.ShowCardSheetButton).
--- @param charid string
--- @param args nil|{x: nil|number, y: nil|number}
--- @return Panel
function Tabletop.CardSheetButton(charid, args)
    args = args or {}
    return gui.Panel{
        classes = {"tabletopCardSheet"},
        floating = true,
        halign = "right",
        valign = "top",
        x = args.x or -6,
        y = args.y or 6,
        width = 22,
        height = 22,
        cornerRadius = 11,
        bgimage = "panels/square.png",
        --the press reaches the card, so hovering here keeps it hovered and a
        --drag from here still moves the card.
        swallowPress = false,
        hover = gui.Tooltip("Open the character sheet"),
        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            local toggle = rawget(_G, "ToggleCharacterPanelDocument")
            if toggle ~= nil then
                --opens beside the card.
                toggle(charid, nil, element)
            end
        end,
        gui.Panel{
            classes = {"tabletopCardSheet", "tabletopCardSheetIcon"},
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            bgimage = "phosphor/user-fill.png",
            interactable = false,
        },
    }
end

--- @param button Panel
--- @param on boolean
function Tabletop.ShowCardSheetButton(button, on)
    if button ~= nil and button.valid then
        button:SetClassTree("shown", on)
    end
end

--Delete (Director): when the selection is the one cards made, the selected
--creatures' cards leave the table and the open scenes, the creatures stay
--where they are, and the engine deletes no tokens. Otherwise the engine
--deletes the selected map tokens as before.
dmhub.DeleteSelectionPressed = function()
    local selected = Tabletop.SelectedCharids()
    if g_cs.made == nil or next(selected) == nil or not g_cs.SameSet(selected, g_cs.made) then
        return false
    end
    local charids = {}
    for charid in pairs(selected) do
        charids[#charids+1] = charid
    end
    for _, charid in ipairs(charids) do
        local card = CardById(charid)
        if card ~= nil then
            CloseCard(card)
        end
    end
    SceneElements.RemoveCreatureCards(selected)
    dmhub.selectedTokens = {}
    g_cs.made = nil
    return true
end

----------------------------------------------------------------------
--The selection rectangle: dragged out over the bare table or an empty part
--of a scene, it selects every card it touches (Shift or Ctrl adds them to
--the selection). It is drawn on the documents layer, over the table items.


--A panel's rectangle in screen pixels from the top-left (the measure of
--dmhub.mouseScreenPosition). distancesToScreenEdge is (left, bottom, right,
--top), the vertical ones in units of the area below the title bar.
function g_cs.ScreenRect(panel)
    local d = panel.distancesToScreenEdge
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    local scale, offset = 1, 0
    if below.y > 0 then
        scale = below.y / screen.y
        offset = screen.y - below.y
    end
    return d.x, offset + d.w * scale, screen.x - d.z, screen.y - d.y * scale
end

function g_cs.PlaceMarquee(m)
    local ax, ay = ScreenToLayer(math.min(m.x0, m.x1), math.min(m.y0, m.y1))
    local bx, by = ScreenToLayer(math.max(m.x0, m.x1), math.max(m.y0, m.y1))
    m.panel.x = ax
    m.panel.y = ay
    m.panel.selfStyle.width = math.max(1, bx - ax)
    m.panel.selfStyle.height = math.max(1, by - ay)
end

function g_cs.EndMarqueePanel()
    if g_cs.marquee ~= nil and g_cs.marquee.panel.valid then
        g_cs.marquee.panel:DestroySelf()
    end
    g_cs.marquee = nil
end

--- Starts a selection rectangle at the mouse. targets lists the cards it
--- can select: {charid, panel} for each card on the surface it was started on.
--- @param targets fun(): {charid: string, panel: Panel}[]
function Tabletop.BeginCardMarquee(targets)
    g_cs.EndMarqueePanel()
    local layer = DocumentsLayer()
    if layer == nil then
        return
    end
    local mouse = dmhub.mouseScreenPosition
    local panel = gui.Panel{
        styles = ThemeEngine.MergeTokens{
            --the fill's alpha is tiny on purpose: a translucent fill shows far
            --stronger than its alpha here (0x24 already read as a grey slab).
            {
                selectors = {"tabletopMarquee"},
                bgcolor = "#ffffff0a",
                borderColor = "@accent",
                border = 1,
            },
        },
        classes = {"tabletopMarquee"},
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
        bgimage = "panels/square.png",
        interactable = false,
    }
    layer:AddChild(panel)
    panel:SetAsLastSibling()
    g_cs.marquee = {
        x0 = mouse.x,
        y0 = mouse.y,
        x1 = mouse.x,
        y1 = mouse.y,
        panel = panel,
        targets = targets,
        additive = g_cs.AddingToSelection(),
    }
    g_cs.PlaceMarquee(g_cs.marquee)
end

--- Follows the mouse while the selection rectangle is dragged.
function Tabletop.DragCardMarquee()
    local m = g_cs.marquee
    if m == nil or not m.panel.valid then
        return
    end
    local mouse = dmhub.mouseScreenPosition
    m.x1 = mouse.x
    m.y1 = mouse.y
    g_cs.PlaceMarquee(m)
end

--- Releases the selection rectangle: what it touches becomes the selection.
function Tabletop.EndCardMarquee()
    local m = g_cs.marquee
    if m == nil then
        return
    end
    Tabletop.DragCardMarquee()
    g_cs.EndMarqueePanel()
    local rx1, rx2 = math.min(m.x0, m.x1), math.max(m.x0, m.x1)
    local ry1, ry2 = math.min(m.y0, m.y1), math.max(m.y0, m.y1)
    local hits = {}
    local seen = {}
    for _, target in ipairs(m.targets()) do
        if target.panel.valid and not seen[target.charid] then
            local x1, y1, x2, y2 = g_cs.ScreenRect(target.panel)
            if x1 < rx2 and x2 > rx1 and y1 < ry2 and y2 > ry1 then
                seen[target.charid] = true
                hits[#hits+1] = target.charid
            end
        end
    end
    Tabletop.SelectCards(hits, m.additive)
end

--Every table card, as the selection rectangle's targets.
function g_cs.TableCardTargets()
    local out = {}
    for _, card in ipairs(g_cards) do
        if card.panel ~= nil and card.panel.valid then
            out[#out+1] = {charid = card.charid, panel = card.panel}
        end
    end
    return out
end

--Shows each table card's ring when the selection changes.
function g_cs.UpdateCardSelection()
    local seq = dmhub.selectedTokensSeq
    if seq == g_cs.ringSeq then
        return
    end
    g_cs.ringSeq = seq
    local selected = Tabletop.SelectedCharids()
    for _, card in ipairs(g_cards) do
        Tabletop.ShowCardSelected(card.selectRing, selected[card.charid] == true)
    end
end

--Puts a card's resize grip on its edge or corner of the card's current size,
--and stretches an edge grip along the edge between the corner grips. The
--top grips sit on the top of the titlebar (just above the card), and the
--side grips run up beside the titlebar to meet them.
local function PlaceGrip(card, grip)
    local w, h = ItemSize(card)
    local s = card.scale or 1
    local W = math.floor(w * s)
    local H = math.floor(h * s)
    local hx = grip.data.hx
    local hy = grip.data.hy
    local inset = CARD_GRIP - CARD_GRIP_OUT
    local topInset = CARD_TOP_GRIP - CARD_TOP_GRIP_OUT
    local top = -CARD_TITLE_HEIGHT
    local corner = hx ~= 0 and hy ~= 0

    local x, width
    if hx == 0 then
        local edgeInset = cond(hy < 0, topInset, inset)
        x = edgeInset
        width = math.max(1, W - 2 * edgeInset)
    elseif corner and hy < 0 then
        x = cond(hx < 0, -CARD_TOP_GRIP_OUT, W - topInset)
        width = CARD_TOP_GRIP
    elseif corner then
        x = cond(hx < 0, -CARD_GRIP_OUT, W - inset)
        width = CARD_GRIP
    else
        x = cond(hx < 0, -CARD_EDGE_OUT, W - (CARD_EDGE - CARD_EDGE_OUT))
        width = CARD_EDGE
    end

    local y, height
    if hy == 0 then
        y = top + topInset
        height = math.max(1, H - inset - y)
    elseif hy < 0 then
        if corner then
            y = top - CARD_TOP_GRIP_OUT
            height = CARD_TOP_GRIP
        else
            y = top - CARD_EDGE_OUT
            height = CARD_EDGE
        end
    elseif corner then
        y = H - inset
        height = CARD_GRIP
    else
        y = H - (CARD_EDGE - CARD_EDGE_OUT)
        height = CARD_EDGE
    end

    grip.selfStyle.width = width
    grip.selfStyle.height = height
    grip.data.homeX = x
    grip.data.homeY = y
    grip.x = x
    grip.y = y
end

--Sizes a built card to its scale. except: a grip being dragged, which is
--left where the drag has it until the drag ends.
local function ApplyCardScale(card, except)
    local panel = card.panel
    if panel == nil or not panel.valid then
        return
    end
    local w, h = ItemSize(card)
    local s = card.scale or 1
    panel.selfStyle.width = math.floor(w * s)
    panel.selfStyle.height = math.floor(h * s)
    --the frame draws nothing itself; its corners shape the face's shadow.
    panel.selfStyle.cornerRadius = (card.shadowRadius or 0) * s
    if card.selectRing ~= nil and card.selectRing.valid then
        card.selectRing.selfStyle.cornerRadius = (card.shadowRadius or 0) * s + 3
    end
    card.scaler.selfStyle.scale = s
    --the titlebar is at least as wide as the card (see BuildCard).
    if card.titlebar ~= nil and card.titlebar.valid then
        card.titlebar.selfStyle.minWidth = math.floor(w * s)
    end
    for _, grip in ipairs(card.grips) do
        if grip ~= except then
            PlaceGrip(card, grip)
        end
    end
end

local function MirrorDiagonalCursor()
    for _, id in ipairs(dmhub.cursorIds or {}) do
        if id == "diagonal-expand-mirror" then
            return id
        end
    end
    return "diagonal-expand"
end

--A grip on one edge or corner that resizes the card, keeping its shape.
--hx/hy say where it sits: -1 left/top, 1 right/bottom, 0 along the middle
--of that axis. The opposite edge stays put; an edge grip keeps the card's
--top or left where it is. A corner drag is projected onto the diagonal.
local function CardGrip(card, hx, hy)
    local cursor
    if hx == 0 then
        cursor = "vertical-expand"
    elseif hy == 0 then
        cursor = "horizontal-expand"
    elseif hx == hy then
        cursor = "diagonal-expand"
    else
        cursor = MirrorDiagonalCursor()
    end
    --whether a grip is hovered or dragged. The titlebar shows while the card
    --or a grip is hovered: hover events for the two can come in either order
    --as the mouse crosses a grip into the card, so each keeps its own flag.
    local function SetGripHover(on)
        card.gripHovered = on
        local titlebar = card.titlebar
        if titlebar ~= nil and titlebar.valid then
            titlebar:SetClassTree("shown", on or card.cardHovered == true)
        end
    end
    return gui.Panel{
        styles = {
            {
                width = CARD_GRIP,
                height = CARD_GRIP,
                halign = "left",
                valign = "top",
            },
        },
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = cursor,
        draggable = true,
        data = {
            hx = hx,
            hy = hy,
            homeX = 0,
            homeY = 0,
        },
        --a grip swallows the press, so hovering it does not hover the card;
        --it keeps the card's titlebar shown itself (the top grips sit on it).
        hover = function(element)
            SetGripHover(true)
        end,
        dehover = function(element)
            if not element.data.dragging then
                SetGripHover(false)
            end
        end,
        beginDrag = function(element)
            local w, h = ItemSize(card)
            local s = card.scale or 1
            card.panel:SetAsLastSibling()
            --the card's origin is fixed for the right edge and the bottom, so
            --size = drag position + this offset there.
            element.data.grabX = w * s - element.data.homeX
            element.data.grabY = h * s - element.data.homeY
            element.data.dragging = true
        end,
        dragging = function(element)
            local panel = card.panel
            if panel == nil or not panel.valid or not element.data.dragging then
                return
            end
            local w, h = ItemSize(card)
            local curW = w * (card.scale or 1)
            local curH = h * (card.scale or 1)
            --left and top are measured in the card's own frame, which this
            --drag moves, so the shift settles back to zero as the card follows.
            local wantW, wantH
            if hx > 0 then
                wantW = element.xdrag + element.data.grabX
            elseif hx < 0 then
                wantW = curW - (element.xdrag - element.data.homeX)
            end
            if hy > 0 then
                wantH = element.ydrag + element.data.grabY
            elseif hy < 0 then
                wantH = curH - (element.ydrag - element.data.homeY)
            end
            local s
            if wantW ~= nil and wantH ~= nil then
                s = (wantW * w + wantH * h) / (w * w + h * h)
            elseif wantW ~= nil then
                s = wantW / w
            else
                s = wantH / h
            end
            --growing left or up stops at the table's edge (and leaves room
            --for the titlebar), as moving the card does.
            if hx < 0 then
                s = math.min(s, (card.x + curW) / w)
            end
            if hy < 0 then
                s = math.min(s, (card.y + curH - CARD_TITLE_HEIGHT) / h)
            end
            --(a document item can go smaller than a card: card.minScale.)
            s = math.max(card.minScale or CARD_MIN_SCALE, math.min(CARD_MAX_SCALE, s))
            if hx < 0 then
                card.x = card.x + (curW - w * s)
                panel.x = card.x
            end
            if hy < 0 then
                card.y = card.y + (curH - h * s)
                panel.y = card.y
            end
            card.scale = s
            ApplyCardScale(card, element)
        end,
        drag = function(element)
            element.data.dragging = false
            PlaceGrip(card, element)
            SetGripHover(false)
            SaveSoon()
            g_sharing.TookControl(card.layoutKey)
        end,
    }
end

--Every resize grip for a card or document item: the edges first, so the
--corners sit above where they meet.
local function CardGrips(card)
    return {
        CardGrip(card, 0, -1),
        CardGrip(card, 0, 1),
        CardGrip(card, -1, 0),
        CardGrip(card, 1, 0),
        CardGrip(card, -1, -1),
        CardGrip(card, 1, -1),
        CardGrip(card, -1, 1),
        CardGrip(card, 1, 1),
    }
end

--Shows or hides the faded copy of a dragged card at the card's spot on the
--table, building it the first time the drag reaches the map. It is a plain
--copy of the face: no titlebar or grips, and it takes no input.
local function ShowCardGhost(drag, show)
    local ghost = drag.ghost
    if ghost == nil or not ghost.valid then
        if not show then
            return
        end
        local card = drag.card
        local layer = DocumentsLayer()
        local tok = dmhub.GetCharacterById(card.charid)
        if layer == nil or tok == nil or card.panel == nil or not card.panel.valid then
            return
        end
        local w, h = CardSize()
        ghost = gui.Panel{
            classes = {"tabletopCardGhost"},
            styles = CardStyles(),
            halign = "left",
            valign = "top",
            x = card.x,
            y = card.y,
            width = math.floor(w * card.scale),
            height = math.floor(h * card.scale),
            flow = "none",
            interactable = false,
            create = function(element)
                element:FireEventTree("refreshCard")
                element:SetClassTree("tabletopCardGhost", true)
            end,
            gui.Panel{
                halign = "center",
                valign = "center",
                width = w,
                height = h,
                scale = card.scale,
                CardFace(card.charid, tok),
            },
        }
        layer:AddChild(ghost)
        --the dragged card stays above its copy.
        card.panel:SetAsLastSibling()
        drag.ghost = ghost
    end
    ghost:SetClass("collapsed", not show)
end

local function DestroyCardGhost(drag)
    if drag.ghost ~= nil and drag.ghost.valid then
        drag.ghost:DestroySelf()
    end
    drag.ghost = nil
end

--Ends the Director's card drag. Placement mode (the card's focus) holds
--until the engine has handled the release this frame.
local function EndCardDrag(drag, panel)
    DestroyCardGhost(drag)
    dmhub.Schedule(0.2, function()
        if g_cardDrag == drag then
            g_cardDrag = nil
        end
        if panel.valid and gui.GetFocus() == panel then
            gui.SetFocus(nil)
        end
    end)
end

--Dragging a selected table card takes the other selected table cards with
--it. BeginCardGroup notes where they started; MoveCardGroup moves them by
--the dragged card's offset (home again while it is over a map); the drop
--either lands them (LandCardGroup) or, for a drop that is not a move on the
--table, puts them back (TakeCardGroup returns them home first).

function g_cs.BeginCardGroup(card)
    g_cs.group = nil
    local selected = Tabletop.SelectedCharids()
    if not selected[card.charid] then
        return
    end
    local members = {}
    for _, other in ipairs(g_cards) do
        if other ~= card and selected[other.charid] and other.panel ~= nil and other.panel.valid then
            members[#members+1] = {card = other, x = other.x, y = other.y}
        end
    end
    if #members > 0 then
        g_cs.group = {card = card, members = members}
    end
end

function g_cs.MoveCardGroup(card, dx, dy, follow)
    local group = g_cs.group
    if group == nil or group.card ~= card then
        return
    end
    if not follow then
        dx, dy = 0, 0
    end
    for _, m in ipairs(group.members) do
        local panel = m.card.panel
        if panel ~= nil and panel.valid then
            panel.x = m.x + dx
            panel.y = m.y + dy
        end
    end
end

--Ends the group drag, returning its cards home (a drop that lands them
--moves them on again with LandCardGroup).
function g_cs.TakeCardGroup(card)
    local group = g_cs.group
    g_cs.group = nil
    if group == nil or group.card ~= card then
        return nil
    end
    g_cs.MoveCardGroup(card, 0, 0, false)
    g_cs.group = nil
    return group
end

function g_cs.LandCardGroup(group, dx, dy)
    if group == nil then
        return
    end
    local lw, lh = LayerSize()
    for _, m in ipairs(group.members) do
        local other = m.card
        other.x = math.max(0, math.min(m.x + dx, lw - 60))
        other.y = math.max(CARD_TITLE_HEIGHT, math.min(m.y + dy, lh - 60))
        if other.panel ~= nil and other.panel.valid then
            other.panel.x = other.x
            other.panel.y = other.y
            other.panel:SetAsLastSibling()
        end
        g_sharing.TookControl(other.layoutKey)
    end
    --the dragged card stays on top.
    if group.card.panel ~= nil and group.card.panel.valid then
        group.card.panel:SetAsLastSibling()
    end
end

local function BuildCard(card)
    local layer = DocumentsLayer()
    local tok = dmhub.GetCharacterById(card.charid)
    if layer == nil or tok == nil then
        return
    end
    local w, h = CardSize()
    card.scale = card.scale or 1
    --the hero card face's own cornerRadius, for its shadow (ApplyCardScale).
    card.shadowRadius = 8
    --what the resize grips report a player's resize under (TookControl).
    card.layoutKey = CardItemId(card.charid)

    card.scaler = gui.Panel{
        halign = "center",
        valign = "center",
        width = w,
        height = h,
        scale = card.scale,
        CardFace(card.charid, tok),
    }

    --the ping, left of the share button (DefinePings).
    local controls = {
        g_sharing.PingButton(function()
            return card.layoutKey
        end, {iconSize = 12, width = 26, passPress = true}),
    }
    local share = nil
    if dmhub.isDM then
        share = ShareControl{
            itemId = CardItemId(card.charid),
            newItem = function()
                return {kind = "card", charid = card.charid}
            end,
            what = "this card",
            iconSize = 12,
            width = 26,
            passPress = true,
            cornerRadius = 8,
        }
        controls[#controls+1] = share.button
    end
    --the Director's Screen hides the button while the card is on it.
    card.share = share
    controls[#controls+1] = g_sharing.FollowButton(function()
        return card.layoutKey
    end, {iconSize = 12, width = 26, passPress = true})
    controls[#controls+1] = WindowControl{
        danger = true,
        icon = "window-chrome/chrome-close.png",
        iconSize = 12,
        width = 26,
        passPress = true,
        click = function(element)
            CloseCard(card)
        end,
    }

    --the GameHud cascade carries no theme, so the titlebar brings it, as a
    --map window's does. It is as wide as the card, or wider, out past the
    --card's left edge, when the controls need more room: a card made small
    --keeps its close X (ApplyCardScale keeps minWidth on the card's width).
    local titlebar = gui.Panel{
        styles = ThemeEngine.MergeStyles(g_titleStyles),
        classes = {"tabletopCardTitle", "tabletopCardChrome"},
        floating = true,
        halign = "right",
        valign = "top",
        y = -CARD_TITLE_HEIGHT,
        width = "auto",
        minWidth = math.floor(w * card.scale),
        height = CARD_TITLE_HEIGHT,
        bgimage = "panels/square.png",
        cornerRadius = 6,
        flow = "horizontal",
        --the share light follows the shared document.
        thinkTime = 1,
        think = function(element)
            UpdateShare(share)
        end,
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "100%",
            halign = "right",
            children = controls,
        },
    }
    titlebar:SetClassTree("tabletopCardChrome", true)

    card.titlebar = titlebar
    card.grips = CardGrips(card)

    --over the face: the ring a selected card wears, and the sheet button.
    card.selectRing = Tabletop.CardSelectRing(card.shadowRadius * card.scale)
    Tabletop.ShowCardSelected(card.selectRing, Tabletop.SelectedCharids()[card.charid] == true)
    card.sheetButton = Tabletop.CardSheetButton(card.charid)

    local children = {card.scaler, card.selectRing, card.sheetButton, titlebar}
    if share ~= nil then
        children[#children+1] = share.frame
    end
    for _, grip in ipairs(card.grips) do
        children[#children+1] = grip
    end

    --The Director's right-click menu: what the map's token menu offers for
    --the card's character (GameController's Assign To and Show Token Vision),
    --whichever map the character is on, or none.
    local function ShowCardMenu(element)
        local t = dmhub.GetCharacterById(card.charid)
        if t == nil then
            return
        end
        element.tooltip = nil

        local function Entry(text, check, action)
            return {
                text = text,
                check = check,
                click = function()
                    GuardClicks()
                    element.popup = nil
                    action()
                end,
            }
        end

        --the setters upload; a party's frame goes on its members, as the
        --engine's AssignTokens does.
        local owner = t.ownerId
        if owner == "" then
            owner = nil
        end
        local ownerParty = cond(owner == "PARTY", t.partyId, nil)
        local assign = {
            Entry("Director Controlled", owner == nil, function()
                if owner ~= nil then
                    t.ownerId = nil
                end
            end),
        }
        for _, partyid in ipairs(GetAllParties()) do
            local party = GetParty(partyid)
            if party ~= nil then
                assign[#assign+1] = Entry(party.name, ownerParty == partyid, function()
                    if ownerParty == partyid then
                        return
                    end
                    t.partyId = partyid
                    local frame = party:GetFrame()
                    if frame ~= nil and frame ~= "" then
                        t.portraitFrame = frame
                        t:UploadAppearance()
                    end
                end)
            end
        end
        for _, userid in ipairs(dmhub.users) do
            if userid ~= dmhub.userid then
                local info = dmhub.GetSessionInfo(userid)
                assign[#assign+1] = Entry(info.displayName or "?", owner == userid, function()
                    if owner ~= userid then
                        t.ownerId = userid
                    end
                end)
            end
        end

        local entries = {
            {text = "Assign To", submenu = assign},
        }

        --as on the map, not offered while selection already shows vision.
        local mapid = t.mapid
        if mapid ~= nil and mapid ~= "" and dmhub.GetSettingValue("selectedtokenvision") ~= true then
            local charid = card.charid
            entries[#entries+1] = Entry("Show Token Vision", nil, function()
                --its map's window comes up (a new one if none shows it) and
                --goes live; the vision waits for the token to be spawned.
                Tabletop.OpenMap(mapid, {newWindow = true})
                local deadline = dmhub.Time() + 60
                local function Arrived()
                    local rec = WindowForMap(mapid)
                    return rec ~= nil and Tabletop.LiveWindowId() == rec.id
                        and game.currentMapId == mapid and dmhub.GetTokenById(charid) ~= nil
                end
                dmhub.ScheduleWhen(function()
                    return mod.unloaded or dmhub.Time() > deadline or Arrived()
                end, function()
                    if not mod.unloaded and Arrived() then
                        dmhub.tokenVision = {charid}
                    end
                end)
            end)
        end

        element.popup = gui.ContextMenu{entries = entries}
    end

    local panel = gui.Panel{
        classes = {"tabletopCard"},
        styles = CardStyles(),
        halign = "left",
        valign = "top",
        x = card.x,
        y = card.y,
        width = math.floor(w * card.scale),
        height = math.floor(h * card.scale),
        cornerRadius = card.shadowRadius * card.scale,
        flow = "none",
        draggable = true,
        --stays among the table items while dragged, so the Director's
        --Screen can lie over it (DirectorScreen KeepOnTop).
        dragInPlace = true,
        swallowPress = true,
        --placement mode reads the focused panel's charid (CharacterPanel's
        --dmhub.GetSelectedCharacters) while the Director drags the card.
        data = {
            charid = card.charid,
            tabletopCard = true,
        },
        --click-to-front from a press anywhere on it (engine walk).
        raiseOnPress = true,
        --a hovered grip keeps the titlebar up too (see CardGrip).
        hover = function(element)
            card.cardHovered = true
            titlebar:SetClassTree("shown", true)
            Tabletop.ShowCardSheetButton(card.sheetButton, true)
        end,
        dehover = function(element)
            card.cardHovered = false
            titlebar:SetClassTree("shown", card.gripHovered == true)
            Tabletop.ShowCardSheetButton(card.sheetButton, false)
        end,
        rightClick = function(element)
            if dmhub.isDM then
                ShowCardMenu(element)
            end
        end,
        beginDrag = function(element)
            g_cs.BeginCardGroup(card)
            if dmhub.isDM then
                g_cardDrag = {card = card, overMap = false}
                gui.SetFocus(element)
            end
        end,
        dragging = function(element)
            ChatItemLinks.Dragging(function() return {ChatItemLinks.CharacterItem(card.charid)} end)
            --the other selected cards follow it while it is over the table.
            local overTable = dmhub.tabletopDragSurface ~= "map"
            g_cs.MoveCardGroup(card, element.xdrag - card.x, element.ydrag - card.y, overTable)
            if g_cardDrag == nil or g_cardDrag.card ~= card then
                return
            end
            if dmhub.tabletopDragSurface == "map" then
                --going onto a map, not the table: no Director's Screen hint.
                DirectorScreen.ItemDragging(nil, 0, 0)
            else
                local cw = CardSize()
                DirectorScreen.ItemDragging(CardItemId(card.charid), element.xdrag, cw * (card.scale or 1), element)
            end
            dmhub.SetDraggingMonster()
            local overMap = dmhub.tabletopDragSurface == "map"
            if overMap ~= g_cardDrag.overMap then
                g_cardDrag.overMap = overMap
                element:SetClass("tabletopCardOverMap", overMap)
                ShowCardGhost(g_cardDrag, overMap)
            end
        end,
        drag = function(element)
            --dropped on the chat: a link to the character; the card stays.
            local toChat = ChatItemLinks.Dropped()
            local group = g_cs.TakeCardGroup(card)
            local drag = g_cardDrag
            --dropped on a scene, or on the bare table while a scene is its
            --background: the card moves into the scene (SceneElements.lua).
            local intoScene = (toChat and SceneElements.TookCharacter(card.charid))
                or (not toChat and dmhub.panelDropSurface == "table" and SceneElements.DropOnBackground({card.charid}))
            if intoScene then
                if drag ~= nil and drag.card == card then
                    element:SetClass("tabletopCardOverMap", false)
                    EndCardDrag(drag, element)
                end
                CloseCard(card)
                return
            end
            if drag ~= nil and drag.card == card then
                element:SetClass("tabletopCardOverMap", false)
                EndCardDrag(drag, element)
                --over another map's window that window places the
                --character (g_chrome.CreatureDrop), as the map does.
                if drag.overMap or toChat or g_chrome.CreatureDropClaimed() then
                    --dropped on the map: the engine teleports the character
                    --there, and the card stays where it was.
                    element.x = card.x
                    element.y = card.y
                    return
                end
            end
            if toChat then
                element.x = card.x
                element.y = card.y
                return
            end
            local lw, lh = LayerSize()
            local dx, dy = element.xdrag - card.x, element.ydrag - card.y
            card.x = math.max(0, math.min(element.xdrag, lw - 60))
            card.y = math.max(CARD_TITLE_HEIGHT, math.min(element.ydrag, lh - 60))
            element.x = card.x
            element.y = card.y
            element:SetAsLastSibling()
            g_cs.LandCardGroup(group, dx, dy)
            SaveSoon()
            g_sharing.TookControl(card.layoutKey)
            --onto the Director's Screen it is the Director's alone; off it,
            --the players get it (DirectorScreen.lua).
            if dmhub.isDM then
                DirectorScreen.ItemDropped(CardItemId(card.charid))
            end
        end,
        --the card's portrait, stamina and conditions repaint on this cadence.
        thinkTime = 0.5,
        think = function(element)
            if dmhub.GetCharacterById(card.charid) == nil then
                --the character was deleted: its card goes too.
                CloseCard(card)
                return
            end
            element:FireEventTree("refreshCard")
        end,
        create = function(element)
            element:FireEventTree("refreshCard")
        end,
        children = children,
    }
    layer:AddChild(panel)
    card.panel = panel
    for _, grip in ipairs(card.grips) do
        PlaceGrip(card, grip)
    end
end

--Puts a character's card on this user's table (or brings its card
--forward). options.x/y place the card (documents-layer units), moving it if
--it is already on the table;
--options.shared marks a card that arrived from the Director's share;
--options.placed marks a drop, which unshares the card if it lands on the
--Director's Screen (DirectorScreen.ItemPlaced).
function Tabletop.OpenCard(charid, options)
    options = options or {}
    if not Tabletop.IsActive() or dmhub.GetCharacterById(charid) == nil then
        return
    end
    local w, h = LayerSize()
    local card = CardById(charid)
    if card == nil then
        local cw, ch = CardSize()
        card = {
            charid = charid,
            x = options.x or math.floor((w - cw) / 2),
            y = options.y or math.floor((h - ch) / 2),
            scale = 1,
            fromShare = options.shared == true or nil,
        }
        g_cards[#g_cards+1] = card
    elseif options.x ~= nil and options.y ~= nil then
        --dropped on the table again: the card moves to the drop, keeping its size.
        card.x = options.x
        card.y = options.y
    end
    card.x = math.max(0, math.min(card.x, w - 140))
    card.y = math.max(CARD_TITLE_HEIGHT, math.min(card.y, h - 200))
    if card.panel == nil or not card.panel.valid then
        BuildCard(card)
    else
        card.panel.x = card.x
        card.panel.y = card.y
    end
    if card.panel ~= nil and card.panel.valid then
        card.panel:SetAsLastSibling()
        card.panel:PulseClass("tabletopHighlight")
    end
    SaveSoon()
    if options.placed then
        DirectorScreen.ItemPlaced(CardItemId(charid))
    end
end

CloseCard = function(card)
    if g_cardDrag ~= nil and g_cardDrag.card == card then
        DestroyCardGhost(g_cardDrag)
    end
    if card.panel ~= nil and card.panel.valid then
        card.panel:DestroySelf()
    end
    card.panel = nil
    for i, other in ipairs(g_cards) do
        if other == card then
            table.remove(g_cards, i)
            break
        end
    end
    SaveSoon()
end

TeardownCards = function()
    if g_cardDrag ~= nil then
        DestroyCardGhost(g_cardDrag)
    end
    for _, card in ipairs(g_cards) do
        if card.panel ~= nil and card.panel.valid then
            card.panel:DestroySelf()
        end
        card.panel = nil
    end
end

SyncCards = function()
    for _, card in ipairs(g_cards) do
        if card.panel == nil or not card.panel.valid then
            BuildCard(card)
        end
    end
end

g_layoutWriters[#g_layoutWriters+1] = function(out)
    local cards = {}
    for _, card in ipairs(g_cards) do
        cards[#cards+1] = {charid = card.charid, x = card.x, y = card.y, scale = card.scale, fromShare = card.fromShare}
    end
    out.cards = cards
end

--The Director's Screen's view of a card or journal item: store is its
--share store, and stowing it collapses its panel.
g_sharing.ScreenCardItem = function(key, card, store)
    local w, h = ItemSize(card)
    local s = card.scale or 1
    return {
        key = key,
        rect = {x = card.x, y = card.y, w = w * s, h = h * s},
        --free: not kept on the table (see ScreenWindowItem's move).
        move = function(x, free)
            local lw = LayerSize()
            card.x = free and x or math.max(0, math.min(x, lw - 60))
            if card.panel ~= nil and card.panel.valid then
                card.panel.x = card.x
            end
            SaveSoon()
        end,
        store = store,
        changed = function() end,
        stow = function(stowed)
            local panel = card.panel
            if panel ~= nil and panel.valid and panel:HasClass("collapsed") ~= stowed then
                panel:SetClass("collapsed", stowed)
            end
        end,
        panel = function()
            return card.panel
        end,
        shareButton = function()
            return card.share ~= nil and card.share.button or nil
        end,
        showBehind = function(behind)
            g_sharing.ShowBehind(card.share, behind)
        end,
    }
end

--An NPC card's or journal item's place, for DefineDirectorLayout: its spot
--and scale. Only a built item has its size (a journal item's depends on
--what it shows), so get and set skip one that is not built yet.
g_sharing.ItemLayoutItem = function(key, card, followed)
    return {
        key = key,
        followed = followed,
        get = function()
            if card.panel == nil or not card.panel.valid then
                return nil
            end
            local w, h = ItemSize(card)
            local s = card.scale or 1
            return {x = card.x, y = card.y, w = w * s, h = h * s, s = s}
        end,
        target = function()
            return {panel = card.panel, cornerRadius = (card.shadowRadius or 0) * (card.scale or 1)}
        end,
        set = function(r)
            local panel = card.panel
            if panel == nil or not panel.valid then
                return false
            end
            if r.s ~= nil then
                card.scale = math.max(card.minScale or CARD_MIN_SCALE, math.min(CARD_MAX_SCALE, r.s))
            end
            local lw, lh = LayerSize()
            card.x = math.max(0, math.min(math.floor(r.x + 0.5), lw - 60))
            card.y = math.max(CARD_TITLE_HEIGHT, math.min(math.floor(r.y + 0.5), lh - 60))
            panel.x = card.x
            panel.y = card.y
            ApplyCardScale(card)
            return true
        end,
    }
end

g_sharing.layoutKinds[#g_sharing.layoutKinds+1] = function(list)
    for _, card in ipairs(g_cards) do
        local itemId = CardItemId(card.charid)
        list[#list+1] = g_sharing.ItemLayoutItem(itemId, card, function()
            return IsItemSharedHere(itemId)
        end)
    end
end

g_sharing.screenKinds[#g_sharing.screenKinds+1] = function(list)
    for _, card in ipairs(g_cards) do
        local charid = card.charid
        list[#list+1] = g_sharing.ScreenCardItem(CardItemId(charid), card, g_sharing.DocStore(CardItemId(charid), function()
            return {kind = "card", charid = charid}
        end))
    end
end

g_sharing.unshareClosers[#g_sharing.unshareClosers+1] = function(stillShared)
    local gone = {}
    for _, card in ipairs(g_cards) do
        if card.fromShare and not stillShared(CardItemId(card.charid)) then
            gone[#gone+1] = card
        end
    end
    for _, card in ipairs(gone) do
        CloseCard(card)
    end
end

local function LoadCards(layout)
    g_cards = {}
    if layout == nil or type(layout.cards) ~= "table" then
        return
    end
    for _, saved in ipairs(layout.cards) do
        if type(saved) == "table" and type(saved.charid) == "string" and dmhub.GetCharacterById(saved.charid) ~= nil and CardById(saved.charid) == nil then
            g_cards[#g_cards+1] = {
                charid = saved.charid,
                x = tonumber(saved.x) or 100,
                y = tonumber(saved.y) or 100,
                scale = math.max(CARD_MIN_SCALE, math.min(CARD_MAX_SCALE, tonumber(saved.scale) or 1)),
                fromShare = saved.fromShare == true or nil,
            }
        end
    end
end

--Where the cards for a drop at the mouse go: the first centred on the
--mouse, the rest stepping down-right (documents-layer units).
local function DropPlacement(screenx, screeny, i)
    local x, y = ScreenToLayer(screenx, screeny)
    local w, h = CardSize()
    return math.floor(x - w / 2) + (i - 1) * CARD_GAP, math.floor(y - h / 2) + (i - 1) * CARD_GAP
end

--- Where the i-th card of a drop at a screen point goes (documents-layer
--- units): a scene card dragged out onto the table (SceneElements.lua).
--- @param screenx number
--- @param screeny number
--- @param i integer
--- @return number, number
function Tabletop.CardDropPlacement(screenx, screeny, i)
    return DropPlacement(screenx, screeny, i)
end

----------------------------------------------------------------------
--A character or bestiary row dragged out of its panel (CharacterPanel.lua
--calls these from the row's drag events). Over the bare table it shows as
--the cards a drop there makes; over the live map window only the engine's
--placement ghost shows. The row itself shrinks away in both cases (scale,
--since opacity doesn't reach children), and is back over any panel.

--{row, previews = {panel...}, rowHidden, seen}
local g_rowDrag = nil

local MAX_PREVIEW_CARDS = 4

--options.think/thinkTime: a think for the preview (it keeps thinking while
--non-interactive).
local function BuildPreviewCard(charid, options)
    options = options or {}
    local layer = DocumentsLayer()
    local tok = dmhub.GetCharacterById(charid)
    if layer == nil or tok == nil then
        return nil
    end
    local w, h = CardSize()
    local panel = gui.Panel{
        styles = CardStyles(),
        halign = "left",
        valign = "top",
        width = w,
        height = h,
        --held up off the table, under the mouse.
        cornerRadius = 8,
        boxShadow = TABLE_SHADOWS.lifted,
        flow = "none",
        thinkTime = options.thinkTime,
        think = options.think,
        CardFace(charid, tok),
    }
    layer:AddChild(panel)
    panel:FireEventTree("refreshCard")
    --it rides under the mouse, so it must not count as a panel there (the
    --engine's table-drop test) or take the drop.
    panel:MakeNonInteractiveRecursive()
    return panel
end

--- The card a character dropped on the table would make, on the table and
--- taking no input, for a drag to move about (Tabletop.CardDropPlacement)
--- and destroy. A scene card dragged out of its scene shows it.
--- @param charid string
--- @return nil|Panel
function Tabletop.BuildCardPreview(charid)
    return BuildPreviewCard(charid)
end

function Tabletop.CharacterRowDragEnded(row)
    local drag = g_rowDrag
    if drag == nil or (row ~= nil and drag.row ~= row) then
        return
    end
    g_rowDrag = nil
    if drag.rowHidden and drag.row.valid then
        drag.row.selfStyle.scale = 1
    end
    for _, preview in ipairs(drag.previews) do
        if preview.valid then
            preview:DestroySelf()
        end
    end
end

--The card face for a bestiary creature, which is not a character until a
--drop creates it: the hero card's frame with its portrait, name and the
--"Not on a map" line the card it becomes will show. tok is the bestiary
--entry's token (assets.monsters[id].info).
local function BestiaryCardFace(tok)
    local w, h = CardSize()
    local name = ""
    pcall(function() name = creature.GetTokenDescription(tok) end)
    local face = gui.Panel{
        classes = {"eotwHeroCard"},
        width = w,
        height = h,
        halign = "left",
        cornerRadius = 8,
        bgimage = "panels/square.png",
        gui.Panel{
            classes = {"eotwCardOverlay"},
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "100%",
            height = "auto",
            flow = "vertical",
            bgimage = "panels/square.png",
            cornerRadius = 8,
            hpad = 6,
            vpad = 4,
            borderBox = true,
            gui.Label{
                classes = {"eotwHeroName"},
                text = name,
            },
            gui.Label{
                classes = {"eotwHeroPlayer"},
                text = "Not on a map",
            },
        },
    }
    EotwHeroCard.ApplyPortrait(face, tok, w / h)
    return face
end
Tabletop.BestiaryCardFace = BestiaryCardFace

local function BuildBestiaryPreviewCard(monsterid)
    local layer = DocumentsLayer()
    local monster = assets.monsters[monsterid]
    if layer == nil or monster == nil then
        return nil
    end
    local w, h = CardSize()
    local panel = gui.Panel{
        styles = CardStyles(),
        halign = "left",
        valign = "top",
        width = w,
        height = h,
        cornerRadius = 8,
        boxShadow = TABLE_SHADOWS.lifted,
        flow = "none",
        BestiaryCardFace(monster.info),
    }
    layer:AddChild(panel)
    panel:MakeNonInteractiveRecursive()
    return panel
end

--The shared body of a row drag: count is how many cards a drop makes, and
--buildPreview(i) builds the preview of the i-th.
local function RowDragging(row, count, buildPreview)
    if not Tabletop.IsActive() then
        return
    end
    if g_rowDrag ~= nil and g_rowDrag.row ~= row then
        Tabletop.CharacterRowDragEnded(nil)
    end
    if g_rowDrag == nil then
        g_rowDrag = {row = row, previews = {}, rowHidden = false}
    end
    local drag = g_rowDrag
    drag.seen = dmhub.Time()

    local surface = dmhub.tabletopDragSurface
    local hideRow = surface ~= nil
    if hideRow ~= drag.rowHidden then
        drag.rowHidden = hideRow
        row.selfStyle.scale = cond(hideRow, 0.01, 1)
    end

    local onTable = surface == "table"
    if onTable and #drag.previews == 0 then
        for i = 1, math.min(count, MAX_PREVIEW_CARDS) do
            drag.previews[#drag.previews+1] = buildPreview(i)
        end
    end

    local mouse = nil
    if onTable then
        mouse = dmhub.mouseScreenPosition
    end
    for i, preview in ipairs(drag.previews) do
        if preview.valid then
            preview:SetClass("collapsed", not onTable)
            if mouse ~= nil then
                preview.x, preview.y = DropPlacement(mouse.x, mouse.y, i)
                preview:SetAsLastSibling()
            end
        end
    end
    --whether the drop shares the cards or keeps them behind the Director's
    --Screen (DirectorScreen.lua), judged by the first.
    if mouse ~= nil then
        DirectorScreen.NewItemDragging(DropPlacement(mouse.x, mouse.y, 1), (CardSize()))
    else
        DirectorScreen.ItemDragging(nil, 0, 0)
    end
end

function Tabletop.CharacterRowDragging(row, charids)
    RowDragging(row, #charids, function(i)
        return BuildPreviewCard(charids[i])
    end)
end

--A bestiary row (CharacterPanel.lua): the same, with one preview per
--creature the drop creates (quantity: 4 for a minion squad).
function Tabletop.BestiaryRowDragging(row, monsterid, quantity)
    RowDragging(row, quantity, function(i)
        return BuildBestiaryPreviewCard(monsterid)
    end)
end

Tabletop.BestiaryRowDragEnded = Tabletop.CharacterRowDragEnded

----------------------------------------------------------------------
--A token dragged out of its map window. Over the bare table the engine
--hides the move preview and lists the dragged tokens in
--dmhub.tabletopTokenDrag; faded copies of the cards a drop makes follow the
--mouse, where the drop puts them (tabletopTokenDropped, DropPlacement).

--{key, previews = {panel...}}: key is the dragged charids, joined.
local g_tokenDrag = nil

local function EndTokenDragPreview()
    local drag = g_tokenDrag
    if drag == nil then
        return
    end
    g_tokenDrag = nil
    for _, preview in ipairs(drag.previews) do
        if preview.valid then
            preview:DestroySelf()
        end
    end
end

--Starts, moves or ends the previews to match the engine's drag. Sync calls
--it to notice a drag start; the first preview's think then calls it every
--frame, since Sync's cadence would trail the mouse.
local UpdateTokenDragPreview

UpdateTokenDragPreview = function()
    local charids = dmhub.tabletopTokenDrag
    if charids == nil or not Tabletop.IsActive() then
        EndTokenDragPreview()
        return
    end
    local key = table.concat(charids, ",")
    if g_tokenDrag ~= nil and g_tokenDrag.key ~= key then
        EndTokenDragPreview()
    end
    if g_tokenDrag == nil then
        g_tokenDrag = {key = key, previews = {}}
        for i, charid in ipairs(charids) do
            if i > MAX_PREVIEW_CARDS then
                break
            end
            local options = {}
            if i == 1 then
                options = {
                    thinkTime = 0.01,
                    think = function(element)
                        UpdateTokenDragPreview()
                    end,
                }
            end
            local preview = BuildPreviewCard(charid, options)
            if preview ~= nil then
                preview:SetClassTree("tabletopCardGhost", true)
                g_tokenDrag.previews[#g_tokenDrag.previews+1] = preview
            end
        end
    end

    local mouse = dmhub.mouseScreenPosition
    for i, preview in ipairs(g_tokenDrag.previews) do
        if preview.valid then
            preview.x, preview.y = DropPlacement(mouse.x, mouse.y, i)
            preview:SetAsLastSibling()
        end
    end
    DirectorScreen.NewItemDragging(DropPlacement(mouse.x, mouse.y, 1), (CardSize()))
end

----------------------------------------------------------------------
--A map row dragged out of the Maps panel (MapsPanel.lua calls these from
--the row's drag events). Over the bare table the row steps aside and the
--window a drop makes follows the mouse; the drop opens the map in a new
--window there, or moves the map's window there if it already has one.

--{row, mapid, preview, rowHidden, seen}
local g_mapRowDrag = nil

--The window a map dropped at the mouse gets: its own window's size (or a
--new window's), centred on the mouse and kept wholly on the table when it
--fits. Documents-layer units. With aspect (the map area to show, width over
--height) the window takes that shape instead, as big as a new window allows;
--a new window with no aspect given takes the whole map's shape.
--mapid may be nil: a map still being added to the game.
local function MapDropRect(mapid, aspect)
    local rec = mapid ~= nil and WindowForMap(mapid) or nil
    local width, height
    if rec ~= nil and not rec.maximized and aspect == nil then
        width, height = rec.width, rec.height
    else
        aspect = aspect or Tabletop.MapAspect(mapid)
        if aspect ~= nil and aspect > 0 then
            local bw, bh = Tabletop.ShapedBox()
            width, height = Tabletop.ShapeWindow(bw, bh, aspect)
        else
            local _, _, w, h = DefaultPlacement()
            width, height = w, h
        end
    end
    local mouse = dmhub.mouseScreenPosition
    local mx, my = ScreenToLayer(mouse.x, mouse.y)
    local tw, th = LayerSize()
    local x = math.floor(mx - width / 2)
    local y = math.floor(my - height / 2)
    x = math.max(0, math.min(x, tw - width))
    y = math.max(0, math.min(y, th - height))
    return x, y, width, height
end

--What the drop will make: a window frame with the map's name and its
--snapshot (or loading-screen art). Built non-interactive, since it rides
--under the mouse and must not count as a panel there.
--options (optional): name, the title when mapid is nil (a map not in the
--game yet); loading, show "Loading map..." in the body (Tabletop.ShowLoadingWindow).
--- @param mapid string|nil
--- @param options nil|{name: nil|string, loading: nil|boolean}
local function BuildMapDropPreview(mapid, width, height, options)
    options = options or {}
    local layer = DocumentsLayer()
    if layer == nil then
        return nil
    end
    local image, placeholder = "panels/square.png", true
    if mapid ~= nil then
        image, placeholder = FrozenImage({mapid = mapid})
    end
    local panel = gui.Panel{
        flow = "vertical",
        halign = "left",
        valign = "top",
        width = width,
        height = height,
        bgimage = "panels/square.png",
        bgcolor = "#100d0bff",
        borderWidth = 2,
        borderColor = "#00000099",
        --a loading stand-in rests on the table; a drag preview is lifted.
        boxShadow = cond(options.loading, TABLE_SHADOWS.rest, TABLE_SHADOWS.lifted),
        gui.Panel{
            styles = ThemeEngine.MergeStyles(g_titleStyles),
            classes = {"tabletopTitle"},
            flow = "horizontal",
            width = "100%",
            height = TITLE_HEIGHT,
            bgimage = "panels/square.png",
            gui.Label{
                classes = {"tabletopTitleText"},
                width = "auto",
                height = "100%",
                halign = "left",
                valign = "center",
                hmargin = 8,
                textWrap = false,
                text = mapid ~= nil and MapName(mapid) or (options.name or ""),
            },
        },
        gui.Panel{
            width = "100%",
            height = "100% available",
            bgimage = image,
            bgcolor = cond(placeholder, "#1b1814ff", "#8a8a8aff"),
            saturation = cond(placeholder, 1, 0.12),
            gui.Label{
                classes = {cond(options.loading, nil, "collapsed")},
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                bold = true,
                color = "#e8e0d2",
                fontSize = 16,
                text = "Loading map...",
            },
        },
    }
    layer:AddChild(panel)
    panel:MakeNonInteractiveRecursive()
    return panel
end

--Whether a map row released now goes on the table: over the bare table, or
--over any map window (the live map counts as "map"), since dropping a map
--onto another map means nothing else. The map rail's panels sit inside the
--live window but are not the map, so they don't count.
function Tabletop.MapRowOverTable()
    if not Tabletop.IsActive() then
        return false
    end
    local surface = dmhub.panelDropSurface
    if surface ~= nil then
        return true
    end
    local panel = dmhub.panelDropPanel
    while panel ~= nil do
        for _, rec in ipairs(g_windows) do
            if rec.mapRailHost == panel then
                return false
            end
            if rec.panel == panel then
                return not rec.minimized
            end
        end
        panel = panel.parent
    end
    return false
end

function Tabletop.MapRowDragEnded(row)
    local drag = g_mapRowDrag
    if drag == nil or (row ~= nil and drag.row ~= row) then
        return
    end
    g_mapRowDrag = nil
    if drag.rowHidden and drag.row.valid then
        drag.row.selfStyle.scale = 1
    end
    if drag.preview ~= nil and drag.preview.valid then
        drag.preview:DestroySelf()
    end
end

--options (optional): aspect, the shape the window will take (width over
--height of the map area it is to show); name, the title for a map not in
--the game yet (mapid nil, e.g. an encounter's Map Library map).
--- @param mapid string|nil
--- @param options nil|{aspect: nil|number, name: nil|string}
function Tabletop.MapRowDragging(row, mapid, options)
    options = options or {}
    if not Tabletop.IsActive() then
        return
    end
    if g_mapRowDrag ~= nil and g_mapRowDrag.row ~= row then
        Tabletop.MapRowDragEnded(nil)
    end
    if g_mapRowDrag == nil then
        g_mapRowDrag = {row = row, mapid = mapid, rowHidden = false}
    end
    local drag = g_mapRowDrag
    drag.seen = dmhub.Time()

    local onTable = Tabletop.MapRowOverTable()
    if onTable ~= drag.rowHidden then
        drag.rowHidden = onTable
        row.selfStyle.scale = cond(onTable, 0.01, 1)
    end

    if not onTable then
        if drag.preview ~= nil and drag.preview.valid then
            drag.preview:SetClass("collapsed", true)
        end
        DirectorScreen.ItemDragging(nil, 0, 0)
        return
    end

    local x, y, width, height = MapDropRect(mapid, options.aspect)
    if drag.preview == nil or not drag.preview.valid then
        drag.preview = BuildMapDropPreview(mapid, width, height, {name = options.name})
    end
    local preview = drag.preview
    if preview ~= nil and preview.valid then
        preview:SetClass("collapsed", false)
        preview.x = x
        preview.y = y
        preview:SetAsLastSibling()
    end
    --whether the drop shares it or keeps it behind the Director's Screen.
    DirectorScreen.NewItemDragging(x, width)
end

--A map row released with no drop target under it. On the bare table or a
--map window the map opens in a new window under the mouse, or its window
--moves there. Anywhere else it does nothing. Returns true if the drop was taken.
--options (optional):
--  aspect: the window takes this shape (width over height of its map area).
--    Without it a new window takes the whole map's shape and shows all of it.
--  frame: a map area {x1, y1, x2, y2} in tiles (x2/y2 exclusive; {} = the
--    whole map) the view zooms to fit once the window shows the map live.
--  at: the window goes exactly here ({x, y, width, height}, documents-layer
--    units) instead of under the mouse, e.g. a Tabletop.ShowLoadingWindow
--    stand-in; the mouse need not be over the table then.
--- @param options nil|{aspect: nil|number, frame: nil|{x1: nil|number, y1: nil|number, x2: nil|number, y2: nil|number}, at: nil|{x: number, y: number, width: number, height: number}}
function Tabletop.MapRowDropped(mapid, options)
    options = options or {}
    local at = options.at
    if at == nil and not Tabletop.MapRowOverTable() then
        return false
    end
    if at ~= nil and not Tabletop.IsActive() then
        return false
    end
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return false
    end

    local x, y, width, height
    if at ~= nil then
        x, y, width, height = at.x, at.y, at.width, at.height
    else
        x, y, width, height = MapDropRect(mapid, options.aspect)
    end
    local reshape = at ~= nil or options.aspect ~= nil
    local frame = options.frame
    local rec = WindowForMap(mapid)
    if rec ~= nil then
        --a maximized window stays maximized: the drop just brings it up.
        if not rec.maximized and not IsForcedHere(rec) then
            rec.x, rec.y = x, y
            if reshape then
                rec.width, rec.height = width, height
            end
            if not rec.minimized then
                PlaceWindow(rec)
            end
        end
        --Focus restores a minimized window, growing it out to its new spot.
        Focus(rec)
        Highlight(rec)
        SaveSoon()
    else
        --MapDropRect sized it: to the map (or the given shape) when it could.
        rec = NewWindowRecord(mapid)
        rec.x, rec.y, rec.width, rec.height = x, y, width, height
        g_windows[#g_windows+1] = rec
        EnsureBuilt(rec)
        Focus(rec)
        SaveSoon()
        if frame == nil and not reshape and Tabletop.MapAspect(mapid) ~= nil then
            frame = {}
        end
    end
    --dropped on the Director's Screen it stays private; anywhere else its
    --share is left as it is (DirectorScreen.lua).
    DirectorScreen.ItemPlaced(g_sharing.ScreenKey(rec))

    if frame ~= nil then
        Tabletop.FrameWhenLive(rec, mapid, frame)
    end
    return true
end

--- The box a window shaped to a map area (a whole map, or an encounter's)
--- fits in: big, so the window fills at least 80% of the table along
--- whichever side limits it, and the area is easy to read.
--- @return number width
--- @return number height
function Tabletop.ShapedBox()
    local w, h = LayerSize()
    return math.floor(w * 0.86), math.floor(h * 0.86)
end

--- A map's shape, width over height in tiles; nil for a map not in the game.
--- @param mapid string|nil
--- @return number|nil
function Tabletop.MapAspect(mapid)
    local map = mapid ~= nil and game.GetMap(mapid) or nil
    local thumbnails = rawget(_G, "MapThumbnail")
    if map == nil or not map.valid or thumbnails == nil then
        return nil
    end
    return thumbnails.Aspect(map)
end

--- The size a window opening on a map gets: the whole map's shape, as big
--- as Tabletop.ShapedBox allows. nil when the map's shape is not known.
--- @param mapid string|nil
--- @return number|nil width
--- @return number|nil height
function Tabletop.MapWindowSize(mapid)
    local aspect = Tabletop.MapAspect(mapid)
    if aspect == nil or aspect <= 0 then
        return nil, nil
    end
    local bw, bh = Tabletop.ShapedBox()
    return Tabletop.ShapeWindow(bw, bh, aspect)
end

--- The biggest window that fits a box (boxW x boxH, documents-layer units)
--- whose map body, under the titlebar, has the shape aspect (width over height).
--- @param boxW number
--- @param boxH number
--- @param aspect number
--- @return number width
--- @return number height
function Tabletop.ShapeWindow(boxW, boxH, aspect)
    local maxBodyH = boxH - TITLE_HEIGHT
    local bodyW, bodyH = boxW, boxW / aspect
    if bodyH > maxBodyH then
        bodyH = maxBodyH
        bodyW = maxBodyH * aspect
    end
    return math.max(MIN_WIDTH, math.floor(bodyW)), math.max(MIN_HEIGHT, math.floor(bodyH) + TITLE_HEIGHT)
end

--- Zooms the view to a map area once a window shows its map live (it may
--- still be travelling there). Gives up after a minute, or if another map
--- arrives in the window first.
--- @param rec table the window record
--- @param mapid string
--- @param area {x1: nil|number, y1: nil|number, x2: nil|number, y2: nil|number} tiles, x2/y2 exclusive; {} = the whole map
function Tabletop.FrameWhenLive(rec, mapid, area)
    local deadline = dmhub.Time() + 60
    dmhub.ScheduleWhen(function()
        return mod.unloaded or dmhub.Time() > deadline
            or (Tabletop.LiveWindowId() == rec.id and game.currentMapId == mapid)
    end, function()
        --a frame for the window's new size to reach the camera.
        dmhub.Schedule(0.1, function()
            if mod.unloaded or Tabletop.LiveWindowId() ~= rec.id or game.currentMapId ~= mapid then
                return
            end
            dmhub.FrameMapArea({x1 = area.x1, y1 = area.y1, x2 = area.x2, y2 = area.y2})
        end)
    end)
end

--- What a window shows of its map (world units), read before the window is
--- resized so Tabletop.KeepView can show the same area once it has its new
--- size. nil when the window is not showing its map live.
--- @param rec table the window record
--- @return nil|{mapid: string, x1: number, y1: number, x2: number, y2: number}
function Tabletop.CaptureView(rec)
    if rec.minimized or Tabletop.LiveWindowId() ~= rec.id then
        return nil
    end
    local b = dmhub.cameraUsableBounds
    if b == nil then
        return nil
    end
    return {mapid = game.currentMapId, x1 = b.x1, y1 = b.y1, x2 = b.x2, y2 = b.y2}
end

--- Zooms a resized window to the area Tabletop.CaptureView read, so the map
--- fills it as much as it did before (David, 2026-10-17): maximizing a window
--- framed on the whole map shows the whole map full screen, with bars only
--- where the shapes differ.
--- @param rec table the window record
--- @param view nil|{mapid: string, x1: number, y1: number, x2: number, y2: number}
function Tabletop.KeepView(rec, view)
    if view == nil then
        return
    end
    --a frame for the window's new size to reach the camera.
    dmhub.Schedule(0.1, function()
        if mod.unloaded or Tabletop.LiveWindowId() ~= rec.id or game.currentMapId ~= view.mapid then
            return
        end
        dmhub.FrameMapArea({world = {x1 = view.x1, y1 = view.y1, x2 = view.x2, y2 = view.y2}})
    end)
end

--- A stand-in window on the table saying "Loading map..." while a map is
--- added to the game (an encounter's Map Library map). Pass the handle to
--- Tabletop.MapRowDropped as options.at to open the real window in its place,
--- then Close it. nil when the table is not showing.
--- @param options {name: string, aspect: nil|number, atMouse: nil|boolean} atMouse: centred on the mouse (a drop); else in the middle of the table.
--- @return nil|{x: number, y: number, width: number, height: number, Close: fun()}
function Tabletop.ShowLoadingWindow(options)
    if not Tabletop.IsActive() then
        return nil
    end
    local x, y, width, height
    if options.atMouse then
        x, y, width, height = MapDropRect(nil, options.aspect)
    else
        if options.aspect ~= nil and options.aspect > 0 then
            local bw, bh = Tabletop.ShapedBox()
            width, height = Tabletop.ShapeWindow(bw, bh, options.aspect)
        else
            local _, _, w, h = DefaultPlacement()
            width, height = w, h
        end
        local tw, th = LayerSize()
        x = math.floor((tw - width) / 2)
        y = math.floor((th - height) / 2)
    end
    local panel = BuildMapDropPreview(nil, width, height, {name = options.name, loading = true})
    if panel == nil then
        return nil
    end
    panel.x = x
    panel.y = y
    panel:SetAsLastSibling()
    return {
        x = x,
        y = y,
        width = width,
        height = height,
        Close = function()
            if panel.valid then
                panel:DestroySelf()
            end
        end,
    }
end

--A drag can end without the row hearing of it (the row rebuilt mid-drag):
--the previews go once its drag events stop.
local function CheckRowDragEnded()
    if g_rowDrag ~= nil and dmhub.Time() - (g_rowDrag.seen or 0) > 0.3 then
        Tabletop.CharacterRowDragEnded(nil)
    end
    if g_mapRowDrag ~= nil and dmhub.Time() - (g_mapRowDrag.seen or 0) > 0.3 then
        Tabletop.MapRowDragEnded(nil)
    end
end

--A creature dragged from the bestiary or the character list and dropped on
--the bare table (outside any map window; the engine reports it). Existing
--characters get a card; bestiary creatures are created with no map first.
dmhub.RegisterEventHandler("tabletopCreatureDropped", function(info)
    if mod.unloaded or not Tabletop.IsActive() or type(info) ~= "table" then
        return
    end
    local screenx = tonumber(info.screenx) or 0
    local screeny = tonumber(info.screeny) or 0
    local monsterids = info.monsterids
    if type(monsterids) ~= "table" then
        monsterids = {info.monsterid}
    end
    --on a scene that is the table's background: into the scene.
    local intoScene = false
    if type(info.charids) == "table" then
        local charids = {}
        for _, charid in ipairs(info.charids) do
            if g_cardDrag == nil or g_cardDrag.card.charid ~= charid then
                charids[#charids+1] = charid
            end
        end
        intoScene = #charids > 0 and SceneElements.DropOnBackground(charids)
    elseif dmhub.isDM then
        intoScene = SceneElements.DropOnBackground(nil, monsterids)
    end
    if intoScene then
        gui.SetFocus(nil)
        return
    end
    if type(info.charids) == "table" then
        for i, charid in ipairs(info.charids) do
            --a card the Director dragged back onto the table has moved
            --itself (its drag puts the engine in placement mode).
            if g_cardDrag == nil or g_cardDrag.card.charid ~= charid then
                local x, y = DropPlacement(screenx, screeny, i)
                Tabletop.OpenCard(charid, {x = x, y = y, placed = true})
            end
        end
    elseif dmhub.isDM then
        for i, monsterid in ipairs(monsterids) do
            local tok = game.SpawnTokenFromBestiaryLocally(monsterid, nil)
            if tok ~= nil then
                tok:UploadToken()
                local charid = tok.charid
                local cx, cy = DropPlacement(screenx, screeny, i)
                --the new character arrives in the game's character list a
                --moment after the upload.
                dmhub.Coroutine(function()
                    for _ = 1, 100 do
                        if mod.unloaded then
                            return
                        end
                        if dmhub.GetCharacterById(charid) ~= nil then
                            Tabletop.OpenCard(charid, {x = cx, y = cy, placed = true})
                            return
                        end
                        coroutine.yield(0.05)
                    end
                end)
            end
        end
        game.UpdateCharacterTokens()
    end
    --the dragged row stays the focus, which would keep its placement ghost
    --following the mouse back into a map window.
    gui.SetFocus(nil)
end)

--A token dragged out of its map window and released on the table: the
--move is cancelled (engine side) and the token gets a card.
dmhub.RegisterEventHandler("tabletopTokenDropped", function(info)
    if mod.unloaded or not Tabletop.IsActive() or type(info) ~= "table" then
        return
    end
    local screenx = tonumber(info.screenx) or 0
    local screeny = tonumber(info.screeny) or 0
    local charids = info.charids
    if type(charids) ~= "table" then
        charids = {info.charid}
    end
    --on a scene that is the table's background: into the scene.
    if SceneElements.DropOnBackground(charids) then
        return
    end
    for i, charid in ipairs(charids) do
        local x, y = DropPlacement(screenx, screeny, i)
        Tabletop.OpenCard(charid, {x = x, y = y, placed = true})
    end
end)

----------------------------------------------------------------------
--Teleporting a token to another map (Director). A token dragged out of the
--live window over another map's (frozen) window shows a purple jump arrow
--across the table from the token to the mouse, and a faded copy of the
--token on the tile it would land on. Releasing there sends the dragged
--tokens to that map (game.SendTokensToMap); the arrow's tail then runs into
--its head, and the window draws the token where it arrived
--(SyncFrozenTokens). The frozen body is the engine's token drop target, so
--the move on the live map is cancelled as for any drop off the map.
--(No new top-level locals here: this file is at Lua's 200-local limit.)

--{rec, charid, charids, ghost, left, dropped} while a drag is over a frozen window.
g_chrome.teleport = nil

--Where a screen point (pixels from the top-left) falls on a frozen
--window's map: {x, y, floor} in that map's world terms, as the window's
--snapshot shows it, or nil (outside the body, or no snapshot to go by).
function g_chrome.FrozenMapPoint(rec, screenx, screeny)
    local body = rec.frozenBody
    if body == nil or not body.valid then
        return nil
    end
    local info = dmhub.GetMapSnapshotInfo(rec.mapid)
    if info == nil then
        return nil
    end
    local r = LayerRect(body)
    if r == nil or r.w <= 0 or r.h <= 0 then
        return nil
    end
    local lx, ly = ScreenToLayer(screenx, screeny)
    local fx = (lx - r.x) / r.w
    local fy = (ly - r.y) / r.h
    if fx < 0 or fx > 1 or fy < 0 or fy > 1 then
        return nil
    end
    return {
        x = info.x1 + fx * (info.x2 - info.x1),
        y = info.y2 - fy * (info.y2 - info.y1),
        floor = info.floor,
    }
end

--The grabbed token's footprint in tiles, from its size on the live map.
function g_chrome.TokenTiles(charid)
    for _, t in ipairs(dmhub.GetMapTokens(game.currentMapId)) do
        if t.charid == charid then
            return math.max(1, math.floor(t.scale + 0.5))
        end
    end
    return 1
end

function g_chrome.EndTeleportDrag(retractSeconds)
    local drag = g_chrome.teleport
    g_chrome.teleport = nil
    if drag ~= nil and drag.ghost ~= nil and drag.ghost.valid then
        drag.ghost:DestroySelf()
    end
    dmhub.HideTabletopArrow(retractSeconds)
end

--Every frame of the drag (the ghost's think): the arrow follows the mouse
--and the ghost snaps to the tile under it.
function g_chrome.UpdateTeleportDrag()
    local drag = g_chrome.teleport
    if drag == nil then
        return
    end
    --the engine fires the leave before the drop, in the same frame; the
    --drop has claimed the drag by the next frame if there was one.
    if drag.left then
        if not drag.dropped then
            g_chrome.EndTeleportDrag(0)
        end
        return
    end

    local rec = drag.rec
    local mouse = dmhub.mouseScreenPosition
    local point = g_chrome.FrozenMapPoint(rec, mouse.x, mouse.y)
    dmhub.ShowTabletopArrow{
        charid = drag.charid,
        tox = mouse.x,
        toy = mouse.y,
        arc = 0.3,
        --no snapshot to place it by: the drop does nothing.
        image = cond(point ~= nil, "purple", "grey"),
    }

    local ghost = drag.ghost
    local body = rec.frozenBody
    local info = dmhub.GetMapSnapshotInfo(rec.mapid)
    if ghost == nil or not ghost.valid or body == nil or not body.valid then
        return
    end
    if point == nil or info == nil then
        ghost:SetClass("collapsed", true)
        return
    end

    --snapped as the engine places it: an odd footprint centres on a tile,
    --an even one on a tile corner.
    local tiles = g_chrome.TokenTiles(drag.charid)
    local cx, cy
    if tiles % 2 == 1 then
        cx, cy = math.floor(point.x + 0.5), math.floor(point.y + 0.5)
    else
        cx, cy = math.floor(point.x) + 0.5, math.floor(point.y) + 0.5
    end

    local w = body.renderedWidth
    local h = body.renderedHeight
    local ww = info.x2 - info.x1
    local wh = info.y2 - info.y1
    if w == nil or h == nil or ww <= 0 or wh <= 0 then
        return
    end
    local size = tiles * w / ww
    ghost:SetClass("collapsed", false)
    ghost.x = (cx - info.x1) / ww * w - size / 2
    ghost.y = (info.y2 - cy) / wh * h - size / 2
    if ghost.selfStyle.width ~= size then
        ghost.selfStyle.width = size
        ghost.selfStyle.height = size
    end
end

function g_chrome.TeleportDragEnter(rec, info)
    if not dmhub.isDM or type(info) ~= "table" or info.charid == nil then
        return
    end
    g_chrome.EndTeleportDrag(0)

    local token = dmhub.GetCharacterById(info.charid)
    local holder = rec.tokenHolder
    if token == nil or holder == nil or not holder.valid then
        return
    end

    local ghost = gui.CreateTokenImage(token, {
        styles = {
            {
                selectors = {"tabletopTeleportGhost"},
                opacity = 0.6,
            },
        },
        classes = {"collapsed"},
        floating = true,
        interactable = false,
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
        thinkTime = 0.01,
        think = function(element)
            g_chrome.UpdateTeleportDrag()
        end,
    })
    ghost:SetClassTree("tabletopTeleportGhost", true)
    holder:AddChild(ghost)

    g_chrome.teleport = {
        rec = rec,
        charid = info.charid,
        charids = info.charids or {info.charid},
        ghost = ghost,
        left = false,
        dropped = false,
    }
    g_chrome.UpdateTeleportDrag()
end

function g_chrome.TeleportDragLeave(rec)
    local drag = g_chrome.teleport
    if drag ~= nil and drag.rec == rec then
        drag.left = true
    end
end

function g_chrome.TeleportDrop(rec, info)
    local drag = g_chrome.teleport
    if not dmhub.isDM or type(info) ~= "table" then
        g_chrome.EndTeleportDrag(0)
        return
    end
    local screenx = tonumber(info.screenx) or 0
    local screeny = tonumber(info.screeny) or 0
    local point = g_chrome.FrozenMapPoint(rec, screenx, screeny)
    if point == nil then
        g_chrome.EndTeleportDrag(0)
        return
    end

    local charids = info.charids
    if type(charids) ~= "table" then
        charids = {info.charid}
    end

    if drag ~= nil then
        drag.dropped = true
    end
    game.SendTokensToMap(charids, rec.mapid, point.x, point.y, point.floor)
    g_chrome.EndTeleportDrag(0.35)
end

----------------------------------------------------------------------
--Placing creatures on another map (Director). A bestiary entry, a hero row,
--a table card or a chat monster link dragged over a frozen window shows
--faded copies of the creatures on the tiles they would land on, planned by
--the engine exactly as the drop places them (game.PlanTokensOnMap). The
--engine hides its own placement preview there, as the window is UI, and
--tells the body (creatureDragEnter / creatureDragLeave / dropCreatures).
--Releasing creates the bestiary creatures on that map
--(game.SpawnBestiaryOnMap) or sends the characters there
--(game.SendTokensToMap); the window then draws them (SyncFrozenTokens).

--{rec, ids, isChars, groups, host, ghosts, plan, planKey, left, dropped}
--while such a drag is over a frozen window.
g_chrome.creatureDrop = nil

function g_chrome.EndCreatureDrag()
    local drag = g_chrome.creatureDrop
    g_chrome.creatureDrop = nil
    if drag ~= nil and drag.host ~= nil and drag.host.valid then
        drag.host:DestroySelf()
    end
end

--True while a creature drag released now is a frozen window's to place, so
--a table card being dragged stays where it is rather than moving under it.
function g_chrome.CreatureDropClaimed()
    local drag = g_chrome.creatureDrop
    return drag ~= nil and (drag.dropped or not drag.left)
end

--The faded image of one creature being placed: a character's token, or a
--bestiary entry's token blueprint.
function g_chrome.CreatureGhost(drag, id)
    local token = nil
    if drag.isChars then
        token = dmhub.GetCharacterById(id)
    else
        local monster = assets.monsters[id]
        if monster ~= nil then
            token = monster.info
        end
    end
    if token == nil then
        return nil
    end
    local ghost = gui.CreateTokenImage(token, {
        styles = {
            {
                selectors = {"tabletopTeleportGhost"},
                opacity = 0.6,
            },
        },
        floating = true,
        interactable = false,
        halign = "left",
        valign = "top",
        width = 1,
        height = 1,
    })
    ghost:SetClassTree("tabletopTeleportGhost", true)
    return ghost
end

--Every frame of the drag (the host's think): re-plans when the mouse has
--moved a quarter tile on the window's map, and lays the ghosts out on the plan.
function g_chrome.UpdateCreatureDrag()
    local drag = g_chrome.creatureDrop
    if drag == nil then
        return
    end
    --the engine fires the leave before the drop, in the same frame.
    if drag.left then
        if not drag.dropped then
            g_chrome.EndCreatureDrag()
        end
        return
    end

    local rec = drag.rec
    local host = drag.host
    local body = rec.frozenBody
    local info = dmhub.GetMapSnapshotInfo(rec.mapid)
    if host == nil or not host.valid or body == nil or not body.valid then
        return
    end
    --above the window's token layer, which can arrive mid-drag.
    host:SetAsLastSibling()

    local mouse = dmhub.mouseScreenPosition
    local point = g_chrome.FrozenMapPoint(rec, mouse.x, mouse.y)
    local w = body.renderedWidth
    local h = body.renderedHeight
    if point == nil or info == nil or w == nil or h == nil then
        --no snapshot to place by: the drop does nothing.
        host:SetClass("collapsed", true)
        return
    end
    local ww = info.x2 - info.x1
    local wh = info.y2 - info.y1
    if ww <= 0 or wh <= 0 then
        host:SetClass("collapsed", true)
        return
    end
    host:SetClass("collapsed", false)

    local key = string.format("%d:%d:%d", math.floor(point.x * 4), math.floor(point.y * 4), point.floor)
    if key ~= drag.planKey then
        drag.planKey = key
        drag.plan = game.PlanTokensOnMap(drag.ids, rec.mapid, point.x, point.y, point.floor)
    end

    for i, entry in ipairs(drag.plan or {}) do
        local slot = drag.ghosts[i]
        if slot == nil or slot.id ~= entry.id then
            if slot ~= nil and slot.panel ~= nil and slot.panel.valid then
                slot.panel:DestroySelf()
            end
            slot = {id = entry.id, panel = g_chrome.CreatureGhost(drag, entry.id)}
            drag.ghosts[i] = slot
            if slot.panel ~= nil then
                host:AddChild(slot.panel)
            end
        end
        local ghost = slot.panel
        if ghost ~= nil and ghost.valid then
            local size = entry.tiles * w / ww
            ghost.x = (entry.x - info.x1) / ww * w - size / 2
            ghost.y = (info.y2 - entry.y) / wh * h - size / 2
            if ghost.selfStyle.width ~= size then
                ghost.selfStyle.width = size
                ghost.selfStyle.height = size
            end
        end
    end
end

function g_chrome.CreatureDragEnter(rec, info)
    if not dmhub.isDM or type(info) ~= "table" then
        return
    end
    g_chrome.EndCreatureDrag()

    local ids, isChars
    if type(info.charids) == "table" then
        ids, isChars = info.charids, true
    elseif type(info.monsterids) == "table" then
        ids, isChars = info.monsterids, false
    else
        return
    end

    local holder = rec.tokenHolder
    if holder == nil or not holder.valid then
        return
    end
    local host = gui.Panel{
        floating = true,
        interactable = false,
        halign = "left",
        valign = "top",
        width = "100%",
        height = "100%",
        thinkTime = 0.01,
        think = function(element)
            g_chrome.UpdateCreatureDrag()
        end,
    }
    holder:AddChild(host)

    g_chrome.creatureDrop = {
        rec = rec,
        ids = ids,
        isChars = isChars,
        groups = info.groups,
        host = host,
        ghosts = {},
        left = false,
        dropped = false,
    }
    g_chrome.UpdateCreatureDrag()
end

function g_chrome.CreatureDragLeave(rec)
    local drag = g_chrome.creatureDrop
    if drag ~= nil and drag.rec == rec then
        drag.left = true
    end
end

function g_chrome.CreatureDrop(rec, info)
    local drag = g_chrome.creatureDrop
    if not dmhub.isDM or type(info) ~= "table" then
        g_chrome.EndCreatureDrag()
        return
    end
    local screenx = tonumber(info.screenx) or 0
    local screeny = tonumber(info.screeny) or 0
    local point = g_chrome.FrozenMapPoint(rec, screenx, screeny)
    if point == nil then
        g_chrome.EndCreatureDrag()
        return
    end

    if drag ~= nil then
        drag.dropped = true
    end
    if type(info.charids) == "table" then
        game.SendTokensToMap(info.charids, rec.mapid, point.x, point.y, point.floor)
    else
        --groups keep an encounter's initiative groups apart.
        local monsterids = info.groups or info.monsterids or {info.monsterid}
        game.SpawnBestiaryOnMap(monsterids, rec.mapid, point.x, point.y, point.floor)
    end
    --the dragged row stays the focus, which would keep its placement ghost
    --following the mouse back into the live window.
    gui.SetFocus(nil)
    if drag == nil then
        return
    end
    --the ghosts go now; the claim stays a moment for a dragged table card,
    --whose own drop may come after this one (CreatureDropClaimed).
    if drag.host ~= nil and drag.host.valid then
        drag.host:DestroySelf()
    end
    drag.host = nil
    dmhub.Schedule(0.1, function()
        if g_chrome.creatureDrop == drag then
            g_chrome.creatureDrop = nil
        end
    end)
end

----------------------------------------------------------------------
--Journal entries on the table. Dragging a journal row (a document, PDF,
--image or PDF bookmark) out of the journal onto the bare table puts the
--entry there as an item: a document shows as a tile with its icon and name,
--a PDF as its cover, an image or bookmark as itself. A click opens it as the
--journal would. Items move, resize and share like NPC cards (the same hover
--titlebar and edge and corner grips), and are per user like the rest of the table.
--A shared item opens for players even when the entry is not in their
--journal: the Director sharing it is what shows it to them.
--(Journal.lua's row drag calls Tabletop.JournalRowDragging and
--JournalEntryDropped; a drop on the map makes an info bubble instead.)
do
    --{entryid, x, y, scale} for each item on this user's table, plus its
    --built parts (panel, scaler, face, grips) and baseSize.
    local g_docItems = {}

    local DOC_TILE_WIDTH = 176
    local DOC_TILE_HEIGHT = 50
    local DOC_PICTURE_WIDTH = 200
    local DOC_PICTURE_INSET = 2
    --(one table, as this file is at Lua's 200-local ceiling.)
    --coverWidth: a PDF shows its cover, but about as small as a document's
    --tile. pad, icon, iconGap: the tile's side padding, icon size and the
    --gap after it. minScale: items shrink further than NPC cards
    --(CARD_MIN_SCALE). cascade: how far each further item of a minimized
    --several-document window is set off.
    local DOC = {coverWidth = 120, pad = 10, icon = 24, iconGap = 8, minScale = 0.5, cascade = 24}

    local function DocItemId(entryid)
        return "doc:" .. entryid
    end

    local function DocItemById(entryid)
        for _, item in ipairs(g_docItems) do
            if item.entryid == entryid then
                return item
            end
        end
        return nil
    end

    --(LinkResolution.lua; looked up per call, as it may load after this file.)
    local function EntryIcon(entry)
        return CustomDocument.JournalEntryIcon(entry)
    end

    local function EntryPicture(entry)
        return CustomDocument.JournalEntryPicture(entry)
    end

    --The item's own size, before its scale: a fixed tile for a document; a
    --picture's width with its shape kept (within reason) inside a thin frame.
    local function DocBaseSize(entry, entryid)
        local _, aspect = EntryPicture(entry)
        --a file dropped from the desktop knows its shape before its asset does.
        local media = TableMedia.Info(entryid)
        if media ~= nil and media.width > 0 and media.height > 0 then
            aspect = media.height / media.width
        end
        if aspect == nil then
            return DOC_TILE_WIDTH, DOC_TILE_HEIGHT
        end
        aspect = math.max(0.4, math.min(1.6, aspect))
        --a video is laid out wider, so its play bar fits.
        local width = TableMedia.BaseWidth(entryid) or cond(entry.nodeType == "pdf", DOC.coverWidth, DOC_PICTURE_WIDTH)
        local inner = width - DOC_PICTURE_INSET * 2
        return width, math.floor(inner * aspect) + DOC_PICTURE_INSET * 2
    end

    local function DocStyles()
        return {
            {
                valign = "top",
                halign = "left",
                width = 100,
                height = 100,
            },
            --the hover titlebar, as on NPC cards.
            {
                selectors = {"tabletopCardChrome"},
                opacity = 0,
                transitionTime = 0.15,
            },
            {
                selectors = {"tabletopCardChrome", "shown"},
                opacity = 1,
                transitionTime = 0.1,
            },
            {
                selectors = {"tabletopCardTitle"},
                bgcolor = "#1d1915a0",
            },
            {
                selectors = {"tabletopDoc"},
                boxShadow = TABLE_SHADOWS.rest,
            },
            {
                selectors = {"tabletopDoc", "dragging"},
                boxShadow = TABLE_SHADOWS.lifted,
                transitionTime = 0.15,
            },
            {
                selectors = {"tabletopDocFace"},
                bgcolor = "#1d1915f2",
                borderColor = "#d9d1c440",
                borderWidth = 1,
                cornerRadius = 6,
            },
            {
                selectors = {"tabletopDocFace", "lit"},
                borderColor = "#d9b56a",
                transitionTime = 0.1,
            },
            {
                selectors = {"tabletopDocFace", "tabletopHighlight"},
                borderColor = "#f0d48a",
                borderWidth = 3,
                transitionTime = 0.2,
            },
            {
                selectors = {"tabletopDocIcon"},
                bgcolor = "#d9d1c4",
            },
            {
                selectors = {"tabletopDocTitle"},
                color = "#efe8dc",
                bold = true,
            },
            {
                selectors = {"tabletopDocKind"},
                color = "#a39a8c",
                fontSize = 10,
            },
        }
    end

    --The item's face at its own size: the tile or the picture. The tile's
    --name label takes a refreshDoc event that keeps it current.
    local function DocFace(entry, entryid, w, h)
        if TableMedia.IsVideo(entryid) then
            return TableMedia.VideoFace(entryid, w, h)
        end
        local picture = EntryPicture(entry)
        if picture == nil then
            local icon = gui.Panel{
                classes = {"tabletopDocIcon"},
                bgimage = EntryIcon(entry),
                width = DOC.icon,
                height = DOC.icon,
                valign = "center",
                rmargin = DOC.iconGap,
                interactable = false,
            }
            return gui.Panel{
                classes = {"tabletopDocFace"},
                bgimage = "panels/square.png",
                width = w,
                height = h,
                flow = "horizontal",
                hpad = DOC.pad,
                borderBox = true,
                interactable = false,
                icon,
                gui.Panel{
                    width = w - DOC.pad * 2 - DOC.icon - DOC.iconGap,
                    height = "auto",
                    valign = "center",
                    flow = "vertical",
                    interactable = false,
                    gui.Label{
                        classes = {"tabletopDocTitle"},
                        width = "100%",
                        height = "auto",
                        maxHeight = 30,
                        fontSize = 13,
                        textWrap = true,
                        textOverflow = "ellipsis",
                        text = entry.description or "",
                        refreshDoc = function(element, e)
                            element.text = e.description or ""
                        end,
                    },
                    gui.Label{
                        classes = {"tabletopDocKind"},
                        width = "100%",
                        height = "auto",
                        text = CustomDocument.JournalEntryKindName(entry),
                    },
                },
            }
        end

        return gui.Panel{
            classes = {"tabletopDocFace"},
            bgimage = "panels/square.png",
            width = w,
            height = h,
            interactable = false,
            gui.Panel{
                width = w - DOC_PICTURE_INSET * 2,
                height = h - DOC_PICTURE_INSET * 2,
                halign = "center",
                valign = "center",
                bgimage = picture,
                bgcolor = "white",
                cornerRadius = 5,
                interactable = false,
            },
        }
    end

    local CloseDocItem

    --The user takes an item off the table (its close control or menu). An
    --item that is a minimized window's card (item.standsFor, see
    --Tabletop.MinimizeToDocItem) tells the window, which closes that entry.
    local function TakeOffDocItem(item)
        local standsFor = item.standsFor
        CloseDocItem(item)
        if standsFor ~= nil and standsFor.onTakenOff ~= nil then
            standsFor.onTakenOff()
        end
    end

    --The icon rail is the workspace's button bar ("New Experimental UI").
    local function RailInUse()
        return dmhub.GetSettingValue("iconrail") == true and rawget(_G, "IconRailKeyAdd") ~= nil
    end

    --Turns a table item into a rail button: place(key) puts the entry's
    --rail key on a rail and says whether it did; then the item leaves the
    --table, as a minimized map window's button does when docked.
    local function DockDocItem(item, place)
        if not place(CustomDocument.JournalRailKey(item.entryid)) then
            return false
        end
        CloseDocItem(item)
        return true
    end

    local function BuildDocItem(item)
        local layer = DocumentsLayer()
        local entry = CustomDocument.FindJournalEntry(item.entryid)
        if layer == nil or entry == nil then
            return
        end
        local w, h = DocBaseSize(entry, item.entryid)
        item.baseSize = function()
            return w, h
        end
        item.scale = item.scale or 1
        item.minScale = DOC.minScale
        --what the resize grips report a player's resize under (TookControl).
        item.layoutKey = DocItemId(item.entryid)
        --the face's cornerRadius, for its shadow (ApplyCardScale).
        item.shadowRadius = cond(TableMedia.IsVideo(item.entryid), 5, 6)

        --a video with its own controls takes clicks; anything else is a picture.
        local playable = TableMedia.HasControls(item.entryid)
        local face = DocFace(entry, item.entryid, w, h)
        item.face = face
        item.scaler = gui.Panel{
            halign = "center",
            valign = "center",
            width = w,
            height = h,
            scale = item.scale,
            interactable = playable,
            face,
        }

        --the ping, left of the share button (DefinePings).
        local controls = {
            g_sharing.PingButton(function()
                return item.layoutKey
            end, {iconSize = 12, width = 26, passPress = true}),
        }
        local share = nil
        if dmhub.isDM then
            share = ShareControl{
                itemId = DocItemId(item.entryid),
                newItem = function()
                    return {kind = "doc", entryid = item.entryid}
                end,
                what = "this",
                iconSize = 12,
                width = 26,
                passPress = true,
                cornerRadius = 6,
            }
            controls[#controls+1] = share.button
        end
        --the Director's Screen hides the button while the item is on it.
        item.share = share
        --a picture or video can become a map or a scene, opened where it lies.
        if dmhub.isDM and entry.nodeType == "image" then
            local function Middle()
                local scale = item.scale or 1
                return item.x + w * scale / 2, item.y + h * scale / 2
            end
            controls[#controls+1] = WindowControl{
                icon = "phosphor/map-trifold.png",
                iconSize = 13,
                width = 26,
                passPress = true,
                hover = function(element)
                    gui.Tooltip("Make this a map")(element)
                end,
                click = function(element)
                    local mx, my = Middle()
                    --the picture leaves the table once the map exists, not if the
                    --wizard is cancelled.
                    TableMedia.ConvertToMap(item.entryid, mx, my, function()
                        CloseDocItem(item)
                    end)
                end,
            }
            controls[#controls+1] = WindowControl{
                icon = "phosphor/mountains.png",
                iconSize = 13,
                width = 26,
                passPress = true,
                hover = function(element)
                    gui.Tooltip("Make this a scene")(element)
                end,
                click = function(element)
                    local mx, my = Middle()
                    if TableMedia.ConvertToScene(item.entryid, mx, my) then
                        CloseDocItem(item)
                    end
                end,
            }
        end
        controls[#controls+1] = g_sharing.FollowButton(function()
            return item.layoutKey
        end, {iconSize = 12, width = 26, passPress = true})
        controls[#controls+1] = WindowControl{
            danger = true,
            icon = "window-chrome/chrome-close.png",
            iconSize = 12,
            width = 26,
            passPress = true,
            click = function(element)
                TakeOffDocItem(item)
            end,
        }

        --the GameHud cascade carries no theme, so the titlebar brings it.
        --It reaches out past a small item's left edge to fit its controls,
        --as a card's does (BuildCard).
        local titlebar = gui.Panel{
            styles = ThemeEngine.MergeStyles(g_titleStyles),
            classes = {"tabletopCardTitle", "tabletopCardChrome"},
            floating = true,
            halign = "right",
            valign = "top",
            y = -CARD_TITLE_HEIGHT,
            width = "auto",
            minWidth = math.floor(w * item.scale),
            height = CARD_TITLE_HEIGHT,
            bgimage = "panels/square.png",
            cornerRadius = 6,
            flow = "horizontal",
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "100%",
                halign = "right",
                children = controls,
            },
        }
        titlebar:SetClassTree("tabletopCardChrome", true)

        item.titlebar = titlebar
        item.grips = CardGrips(item)

        local children = {item.scaler, titlebar}
        if share ~= nil then
            children[#children+1] = share.frame
        end
        for _, grip in ipairs(item.grips) do
            children[#children+1] = grip
        end

        local panel = gui.Panel{
            classes = {"tabletopDoc"},
            --click-to-front from a press anywhere on it (engine walk).
            raiseOnPress = true,
            styles = DocStyles(),
            halign = "left",
            valign = "top",
            x = item.x,
            y = item.y,
            width = math.floor(w * item.scale),
            height = math.floor(h * item.scale),
            cornerRadius = item.shadowRadius * item.scale,
            flow = "none",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            draggable = true,
            --stays among the table items while dragged, so the Director's
            --Screen can lie over it (DirectorScreen KeepOnTop).
            dragInPlace = true,
            swallowPress = true,
            hover = function(element)
                item.cardHovered = true
                titlebar:SetClassTree("shown", true)
                face:SetClass("lit", true)
                --no preview tooltip: a click opens it.
            end,
            dehover = function(element)
                item.cardHovered = false
                titlebar:SetClassTree("shown", item.gripHovered == true)
                face:SetClass("lit", false)
            end,
            click = function(element)
                if ClicksGuarded() or playable then
                    return
                end
                local e = CustomDocument.FindJournalEntry(item.entryid)
                if e ~= nil then
                    CustomDocument.OpenContent(e)
                end
            end,
            rightClick = function(element)
                element.tooltip = nil
                local entries = {
                    GuardedEntry("Open", function()
                        element.popup = nil
                        CustomDocument.OpenContent(CustomDocument.FindJournalEntry(item.entryid))
                    end),
                }
                if RailInUse() then
                    entries[#entries+1] = GuardedEntry("Dock to Left Rail", function()
                        element.popup = nil
                        DockDocItem(item, function(key) return IconRailKeyAdd(key, "left") end)
                    end)
                    entries[#entries+1] = GuardedEntry("Dock to Right Rail", function()
                        element.popup = nil
                        DockDocItem(item, function(key) return IconRailKeyAdd(key, "right") end)
                    end)
                end
                entries[#entries+1] = GuardedEntry("Take off the table", function()
                    element.popup = nil
                    TakeOffDocItem(item)
                end)
                element.popup = gui.ContextMenu{entries = entries}
            end,
            beginDrag = function(element)
                element.tooltip = nil
            end,
            --drag it onto either icon rail and it becomes a button there
            --that opens the entry (and leaves the table).
            canDragOnto = function(element, target)
                return target:HasClass("iconRail") or target:HasClass("iconRailButton")
            end,
            dragging = function(element, target)
                IconRailDocDragging(target)
                ChatItemLinks.Dragging(function() return {ChatItemLinks.DocItem(item.entryid)} end)
                local iw = ItemSize(item)
                DirectorScreen.ItemDragging(DocItemId(item.entryid), element.xdrag, iw * (item.scale or 1), element)
            end,
            drag = function(element, target)
                IconRailDocDragging(nil)
                --dropped on the chat: a link to the entry; the item stays. A
                --picture or video dropped on a scene moves into it, as does one
                --dropped on the bare table while a scene is its background.
                local dropped = ChatItemLinks.Dropped()
                if (dropped and SceneElements.Took("doc", item.entryid))
                        or (not dropped and dmhub.panelDropSurface == "table"
                            and SceneElements.DropLinksOnBackground({ChatItemLinks.DocItem(item.entryid)})) then
                    TakeOffDocItem(item)
                    return
                end
                if dropped then
                    element.x = item.x
                    element.y = item.y
                    return
                end
                if target ~= nil and target.valid and (target:HasClass("iconRail") or target:HasClass("iconRailButton")) then
                    if DockDocItem(item, function(key) return IconRailKeyDrop(key, target) end) then
                        return
                    end
                end
                local lw, lh = LayerSize()
                item.x = math.max(0, math.min(element.xdrag, lw - 60))
                item.y = math.max(CARD_TITLE_HEIGHT, math.min(element.ydrag, lh - 60))
                element.x = item.x
                element.y = item.y
                element:SetAsLastSibling()
                SaveSoon()
                g_sharing.TookControl(item.layoutKey)
                --onto the Director's Screen it is the Director's alone; off
                --it, the players get it (DirectorScreen.lua).
                DirectorScreen.ItemDropped(DocItemId(item.entryid))
            end,
            --renames reach the item, a deleted entry takes it off the table,
            --and the share light follows the shared document.
            thinkTime = 1,
            think = function(element)
                local e = CustomDocument.FindJournalEntry(item.entryid)
                if e == nil then
                    CloseDocItem(item)
                    return
                end
                element:FireEventTree("refreshDoc", e)
                UpdateShare(share)
            end,
            children = children,
        }
        layer:AddChild(panel)
        item.panel = panel
        for _, grip in ipairs(item.grips) do
            PlaceGrip(item, grip)
        end
    end

    --Puts a journal entry on this user's table (or brings its item forward).
    --options.screen: the mouse in screen pixels, where a drop centres the
    --item (moving it if it is already on the table); options.at: the same in
    --the table's own units ({x, y}); options.scale: a new item's size;
    --options.shared marks an item that arrived from the Director's share;
    --options.placed marks a drop, which unshares the item if it lands on
    --the Director's Screen (DirectorScreen.ItemPlaced).
    function Tabletop.OpenDocItem(entryid, options)
        options = options or {}
        local entry = CustomDocument.FindJournalEntry(entryid)
        if not Tabletop.IsActive() or entry == nil then
            return
        end
        local lw, lh = LayerSize()
        local bw, bh = DocBaseSize(entry, entryid)
        local item = DocItemById(entryid)
        local scale = math.max(DOC.minScale, math.min(CARD_MAX_SCALE, options.scale or 1))
        if item ~= nil then
            scale = item.scale or 1
        end
        local x, y = nil, nil
        local at = options.at
        if options.screen ~= nil then
            local sx, sy = ScreenToLayer(options.screen.x, options.screen.y)
            at = {x = sx, y = sy}
        end
        if at ~= nil then
            x = math.floor(at.x - bw * scale / 2)
            y = math.floor(at.y - bh * scale / 2)
        end
        if item == nil then
            item = {
                entryid = entryid,
                x = x or math.floor((lw - bw * scale) / 2),
                y = y or math.floor((lh - bh * scale) / 2),
                scale = scale,
                fromShare = options.shared == true or nil,
            }
            g_docItems[#g_docItems+1] = item
        elseif x ~= nil then
            item.x = x
            item.y = y
        end
        item.x = math.max(0, math.min(item.x, lw - 60))
        item.y = math.max(CARD_TITLE_HEIGHT, math.min(item.y, lh - 60))
        if item.panel == nil or not item.panel.valid then
            BuildDocItem(item)
        else
            item.panel.x = item.x
            item.panel.y = item.y
        end
        if item.panel ~= nil and item.panel.valid then
            item.panel:SetAsLastSibling()
            item.face:PulseClass("tabletopHighlight")
        end
        SaveSoon()
        if options.placed then
            DirectorScreen.ItemPlaced(DocItemId(entryid))
        end
    end

    --Minimized journal and PDF windows. A window minimizing on the table
    --becomes the table items for its entries, and a click on one opens the
    --entry, which brings the window back (CustomDocument.ShowDocument and
    --ShowPDFViewerDialog restore a minimized window that holds it). Such an
    --item carries standsFor = {token, owned, onTakenOff} (not saved): token
    --names the window, owned says the minimize put it on the table (so the
    --restore takes it off again), onTakenOff runs if the user removes it.

    --What a ghost between a window and an item shows: the item's picture,
    --else a plain dark panel (see AnimateGhost).
    local function DocGhost(entry)
        local picture = nil
        if entry ~= nil then
            picture = EntryPicture(entry)
        end
        return {
            buttonOps = {
                image = function()
                    if picture ~= nil then
                        return picture, false
                    end
                    return "panels/square.png", true
                end,
            },
        }
    end

    --- Minimizes a journal or PDF window into the table item for one of its
    --- entries: a ghost flies from `from` (the window's rect) to the item,
    --- which goes where the window's middle was (one already on the table
    --- stays put). False, with nothing done, when the table cannot take it.
    --- options: token (names the window, for RestoreFromDocItems), index
    --- (sets a window's several items off from each other, from 0),
    --- still() (false once the window is back: then no item is placed),
    --- onTakenOff() (the user took the item off the table).
    --- @param entryid string
    --- @param from {x: number, y: number, w: number, h: number}
    --- @param options {token: any, index?: integer, still?: (fun(): boolean), onTakenOff?: fun()}
    --- @return boolean
    function Tabletop.MinimizeToDocItem(entryid, from, options)
        local entry = CustomDocument.FindJournalEntry(entryid)
        if not Tabletop.IsActive() or entry == nil or DocumentsLayer() == nil or from == nil then
            return false
        end
        local bw, bh = DocBaseSize(entry, entryid)
        local existing = DocItemById(entryid)
        local at = nil
        local to
        if existing ~= nil then
            local s = existing.scale or 1
            to = {x = existing.x, y = existing.y, w = bw * s, h = bh * s}
        else
            local step = (options.index or 0) * DOC.cascade
            at = {x = from.x + from.w / 2 + step, y = from.y + from.h / 2 + step}
            to = {x = at.x - bw / 2, y = at.y - bh / 2, w = bw, h = bh}
        end
        AnimateGhost(DocGhost(entry), from, to, function()
            if options.still ~= nil and not options.still() then
                return
            end
            local owned = DocItemById(entryid) == nil
            Tabletop.OpenDocItem(entryid, {at = at})
            local item = DocItemById(entryid)
            if item ~= nil then
                item.standsFor = {token = options.token, owned = owned, onTakenOff = options.onTakenOff}
            end
        end)
        return true
    end

    --- A window minimized with MinimizeToDocItem comes back: a ghost flies
    --- from its item (fromEntryid's when given, else any of them) to `to`,
    --- then done(). Items the minimize put on the table leave it; ones that
    --- were already there stay.
    --- @param token any the window, as given to MinimizeToDocItem
    --- @param to {x: number, y: number, w: number, h: number}
    --- @param done fun()
    --- @param fromEntryid? string
    function Tabletop.RestoreFromDocItems(token, to, done, fromEntryid)
        local mine = {}
        for _, item in ipairs(g_docItems) do
            if item.standsFor ~= nil and item.standsFor.token == token then
                mine[#mine+1] = item
            end
        end
        local from, fromItem = nil, nil
        for _, item in ipairs(mine) do
            if fromItem == nil or item.entryid == fromEntryid then
                local s = item.scale or 1
                local bw, bh = 0, 0
                if item.baseSize ~= nil then
                    bw, bh = item.baseSize()
                end
                from = {x = item.x, y = item.y, w = bw * s, h = bh * s}
                fromItem = item
            end
        end
        for _, item in ipairs(mine) do
            if item.standsFor.owned then
                CloseDocItem(item)
            else
                item.standsFor = nil
            end
        end
        local entry = nil
        if fromItem ~= nil then
            entry = CustomDocument.FindJournalEntry(fromItem.entryid)
        end
        AnimateGhost(DocGhost(entry), from, to, done)
    end

    --- Whether a rail button for a journal entry can go back to the table.
    --- @param entryid string
    --- @return boolean
    function Tabletop.CanUndockDocItem(entryid)
        return Tabletop.IsActive() and DocumentsLayer() ~= nil and CustomDocument.FindJournalEntry(entryid) ~= nil
    end

    --- The reverse of docking a table item onto a rail: takes the rail
    --- button for entryid off its rail (railKey is the key it has there) and
    --- puts the entry on the table as an item again, just to the map side
    --- of where the button was.
    --- @param entryid string
    --- @param railKey string
    --- @param button Panel the rail button
    function Tabletop.UndockDocItem(entryid, railKey, button)
        local entry = CustomDocument.FindJournalEntry(entryid)
        if not Tabletop.IsActive() or entry == nil then
            return
        end
        --measured before the rail rebuilds and the button goes away.
        local rect = LayerRect(button)
        local onRight = false
        local rail = button ~= nil and button.valid and button:FindParentWithClass("iconRail") or nil
        if rail ~= nil then
            pcall(function() onRight = rail.data.side == "right" end)
        end
        IconRailKeyRemove(railKey)
        local at = nil
        if rect ~= nil then
            local item = DocItemById(entryid)
            local scale = (item ~= nil and item.scale) or 1
            local bw = DocBaseSize(entry, entryid)
            local half = bw * scale / 2
            local gap = 16
            at = {
                x = cond(onRight, rect.x - gap - half, rect.x + rect.w + gap + half),
                y = rect.y + rect.h / 2,
            }
        end
        Tabletop.OpenDocItem(entryid, {at = at})
    end

    CloseDocItem = function(item)
        if item.panel ~= nil and item.panel.valid then
            item.panel:DestroySelf()
        end
        item.panel = nil
        for i, other in ipairs(g_docItems) do
            if other == item then
                table.remove(g_docItems, i)
                break
            end
        end
        SaveSoon()
    end

    TeardownDocItems = function()
        for _, item in ipairs(g_docItems) do
            if item.panel ~= nil and item.panel.valid then
                item.panel:DestroySelf()
            end
            item.panel = nil
        end
    end

    g_layoutWriters[#g_layoutWriters+1] = function(out)
        local docs = {}
        for _, item in ipairs(g_docItems) do
            docs[#docs+1] = {entryid = item.entryid, x = item.x, y = item.y, scale = item.scale, fromShare = item.fromShare}
        end
        out.docs = docs
    end

    g_sharing.layoutKinds[#g_sharing.layoutKinds+1] = function(list)
        for _, item in ipairs(g_docItems) do
            local itemId = DocItemId(item.entryid)
            list[#list+1] = g_sharing.ItemLayoutItem(itemId, item, function()
                return IsItemSharedHere(itemId)
            end)
        end
    end

    g_sharing.screenKinds[#g_sharing.screenKinds+1] = function(list)
        for _, item in ipairs(g_docItems) do
            local entryid = item.entryid
            list[#list+1] = g_sharing.ScreenCardItem(DocItemId(entryid), item, g_sharing.DocStore(DocItemId(entryid), function()
                return {kind = "doc", entryid = entryid}
            end))
        end
    end

    g_sharing.unshareClosers[#g_sharing.unshareClosers+1] = function(stillShared)
        local gone = {}
        for _, item in ipairs(g_docItems) do
            if item.fromShare and not stillShared(DocItemId(item.entryid)) then
                gone[#gone+1] = item
            end
        end
        for _, item in ipairs(gone) do
            CloseDocItem(item)
        end
    end

    --The journal entries on this user's table, for the Windows menu.
    g_sharing.DocItemEntryIds = function()
        local result = {}
        for _, item in ipairs(g_docItems) do
            result[#result+1] = item.entryid
        end
        return result
    end

    LoadDocItems = function(layout)
        g_docItems = {}
        if layout == nil or type(layout.docs) ~= "table" then
            return
        end
        for _, saved in ipairs(layout.docs) do
            if type(saved) == "table" and type(saved.entryid) == "string" and CustomDocument.FindJournalEntry(saved.entryid) ~= nil
                    and DocItemById(saved.entryid) == nil then
                g_docItems[#g_docItems+1] = {
                    entryid = saved.entryid,
                    x = tonumber(saved.x) or 100,
                    y = tonumber(saved.y) or 100,
                    scale = math.max(DOC.minScale, math.min(CARD_MAX_SCALE, tonumber(saved.scale) or 1)),
                    fromShare = saved.fromShare == true or nil,
                }
            end
        end
    end

    --A journal row being dragged: over the bare table the row steps aside
    --(scale, since opacity doesn't reach children) and the item a drop
    --there makes follows the mouse. {row, entryid, preview, rowHidden, seen}
    local g_journalDrag = nil

    function Tabletop.JournalRowDragEnded(row)
        local drag = g_journalDrag
        if drag == nil or (row ~= nil and drag.row ~= row) then
            return
        end
        g_journalDrag = nil
        if drag.rowHidden and drag.row.valid then
            drag.row.selfStyle.scale = 1
        end
        if drag.preview ~= nil and drag.preview.valid then
            drag.preview:DestroySelf()
        end
    end

    function Tabletop.JournalRowDragging(row, entryid)
        if not Tabletop.IsActive() then
            return
        end
        if g_journalDrag ~= nil and g_journalDrag.row ~= row then
            Tabletop.JournalRowDragEnded(nil)
        end
        local entry = CustomDocument.FindJournalEntry(entryid)
        if entry == nil then
            return
        end
        if g_journalDrag == nil then
            g_journalDrag = {row = row, entryid = entryid, rowHidden = false}
        end
        local drag = g_journalDrag
        drag.seen = dmhub.Time()

        local onTable = dmhub.panelDropSurface == "table"
        if onTable ~= drag.rowHidden then
            drag.rowHidden = onTable
            row.selfStyle.scale = cond(onTable, 0.01, 1)
        end

        if onTable and drag.preview == nil then
            local layer = DocumentsLayer()
            if layer ~= nil then
                local w, h = DocBaseSize(entry, entryid)
                --at the item's current size when it is already on the table.
                local existing = DocItemById(entryid)
                local s = 1
                if existing ~= nil then
                    s = existing.scale or 1
                end
                drag.preview = gui.Panel{
                    styles = DocStyles(),
                    halign = "left",
                    valign = "top",
                    width = w,
                    height = h,
                    scale = s,
                    cornerRadius = cond(TableMedia.IsVideo(entryid), 5, 6),
                    boxShadow = TABLE_SHADOWS.lifted,
                    flow = "none",
                    DocFace(entry, entryid, w, h),
                }
                layer:AddChild(drag.preview)
                --it rides under the mouse, so it must not count as a panel
                --there (dmhub.panelDropSurface) or take the drop.
                drag.preview:MakeNonInteractiveRecursive()
            end
        end
        local preview = drag.preview
        if preview ~= nil and preview.valid then
            preview:SetClass("collapsed", not onTable)
            if onTable then
                local mouse = dmhub.mouseScreenPosition
                local mx, my = ScreenToLayer(mouse.x, mouse.y)
                --scale is about the panel's centre, so it is centred on the
                --mouse by its unscaled size.
                local w, h = DocBaseSize(entry, entryid)
                preview.x = math.floor(mx - w / 2)
                preview.y = math.floor(my - h / 2)
                preview:SetAsLastSibling()
            end
        end
    end

    SyncDocItems = function()
        --a drag can end without the row hearing of it (the journal rebuilt
        --mid-drag): the preview goes once its drag events stop.
        if g_journalDrag ~= nil and dmhub.Time() - (g_journalDrag.seen or 0) > 0.3 then
            Tabletop.JournalRowDragEnded(nil)
        end
        for _, item in ipairs(g_docItems) do
            if item.panel == nil or not item.panel.valid then
                BuildDocItem(item)
            end
        end
    end
end

----------------------------------------------------------------------
--Table items from other modules. A module describes a kind of item in
--Tabletop.itemKinds[kind] and this file puts such items on the table: moved,
--resized and taken off like NPC cards and journal items (the same hover
--titlebar and grips), saved with the layout as items ({kind, key, x, y,
--scale}), per user, not shared. The face is the module's own and may be
--interactive: a press that is not swallowed reaches the item, which drags.
--The first kind is the Audio panel's soundboard pad ("audio", Audio.lua).
--
--A kind is a table of functions taking the item's key (a string):
--  available()   whether this user may have such items at all (an item
--                that is not available stays in the layout but is not built)
--  exists(key)   false once the thing is gone: its item leaves the table
--  name(key)     shown on hover
--  size(key)     the face's own width, height (before the item's scale)
--  face(key)     builds the face at that size
--  defaultScale  (number, optional) the scale a new item starts at
--  cornerRadius  (number, optional, default 4) the face's corner radius at its
--                own size, so the item's shadow on the table matches it
--Tabletop.OpenItem(kind, key, {screen}) puts one on the table (at the mouse in
--screen pixels); Tabletop.ItemRowDragging / ItemRowDragEnded preview a drag
--from a panel, like a journal row's.
local function DefineTableItems()
    --{kind, key, x, y, scale} for each item, plus its built parts (panel,
    --scaler, face, grips, titlebar) and baseSize.
    local items = {}

    local function Kind(kind)
        local spec = Tabletop.itemKinds[kind]
        if spec == nil or not spec.available() then
            return nil
        end
        return spec
    end

    local function ItemByKey(kind, key)
        for _, item in ipairs(items) do
            if item.kind == kind and item.key == key then
                return item
            end
        end
        return nil
    end

    local function ItemStyles()
        return {
            {
                valign = "top",
                halign = "left",
            },
            {
                selectors = {"tabletopCardChrome"},
                opacity = 0,
                transitionTime = 0.15,
            },
            {
                selectors = {"tabletopCardChrome", "shown"},
                opacity = 1,
                transitionTime = 0.1,
            },
            {
                selectors = {"tabletopCardTitle"},
                bgcolor = "#1d1915a0",
            },
            {
                selectors = {"tabletopItem"},
                boxShadow = TABLE_SHADOWS.rest,
            },
            {
                selectors = {"tabletopItem", "dragging"},
                boxShadow = TABLE_SHADOWS.lifted,
                transitionTime = 0.15,
            },
        }
    end

    local CloseItem

    local function BuildItem(item)
        local layer = DocumentsLayer()
        local spec = Kind(item.kind)
        if layer == nil or spec == nil or not spec.exists(item.key) then
            return
        end
        local w, h = spec.size(item.key)
        item.baseSize = function()
            return w, h
        end
        item.scale = item.scale or 1
        --the face's cornerRadius, for its shadow (ApplyCardScale); a kind may
        --say its own.
        item.shadowRadius = spec.cornerRadius or 4

        item.face = spec.face(item.key)
        item.scaler = gui.Panel{
            halign = "center",
            valign = "center",
            width = w,
            height = h,
            scale = item.scale,
            item.face,
        }

        local titlebar = gui.Panel{
            styles = ThemeEngine.MergeStyles(g_titleStyles),
            classes = {"tabletopCardTitle", "tabletopCardChrome"},
            floating = true,
            --wider than a very small item if its X needs it (BuildCard).
            halign = "right",
            valign = "top",
            y = -CARD_TITLE_HEIGHT,
            width = "auto",
            minWidth = math.floor(w * item.scale),
            height = CARD_TITLE_HEIGHT,
            bgimage = "panels/square.png",
            cornerRadius = 6,
            flow = "horizontal",
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "100%",
                halign = "right",
                WindowControl{
                    danger = true,
                    icon = "window-chrome/chrome-close.png",
                    iconSize = 12,
                    width = 26,
                    passPress = true,
                    click = function(element)
                        CloseItem(item)
                    end,
                },
            },
        }
        titlebar:SetClassTree("tabletopCardChrome", true)
        item.titlebar = titlebar
        item.grips = CardGrips(item)

        local children = {item.scaler, titlebar}
        for _, grip in ipairs(item.grips) do
            children[#children+1] = grip
        end

        local panel = gui.Panel{
            classes = {"tabletopItem"},
            --click-to-front from a press anywhere on it (engine walk).
            raiseOnPress = true,
            styles = ItemStyles(),
            halign = "left",
            valign = "top",
            x = item.x,
            y = item.y,
            width = math.floor(w * item.scale),
            height = math.floor(h * item.scale),
            cornerRadius = item.shadowRadius * item.scale,
            flow = "none",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            draggable = true,
            --stays among the table items while dragged, so the Director's
            --Screen can lie over it (DirectorScreen KeepOnTop).
            dragInPlace = true,
            swallowPress = true,
            hover = function(element)
                item.cardHovered = true
                titlebar:SetClassTree("shown", true)
            end,
            dehover = function(element)
                item.cardHovered = false
                titlebar:SetClassTree("shown", item.gripHovered == true)
            end,
            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        GuardedEntry("Take off the table", function()
                            element.popup = nil
                            CloseItem(item)
                        end),
                    },
                }
            end,
            --over a scene the item would move into it (SceneElements.lua says
            --which kinds a scene takes: sounds).
            dragging = function(element)
                ChatItemLinks.Dragging(function() return {} end, {
                    source = element,
                    targetClass = SceneElements.LAYER_CLASS,
                    dropItems = function() return {{kind = item.kind, id = item.key}} end,
                })
            end,
            drag = function(element, target)
                local link = {kind = item.kind, id = item.key}
                local dropped = ChatItemLinks.Dropped()
                if (dropped and SceneElements.Took(item.kind, item.key))
                        or (not dropped and dmhub.panelDropSurface == "table" and SceneElements.DropLinksOnBackground({link})) then
                    CloseItem(item)
                    return
                end
                if dropped then
                    element.x = item.x
                    element.y = item.y
                    return
                end
                local lw, lh = LayerSize()
                item.x = math.max(0, math.min(element.xdrag, lw - 60))
                item.y = math.max(CARD_TITLE_HEIGHT, math.min(element.ydrag, lh - 60))
                element.x = item.x
                element.y = item.y
                element:SetAsLastSibling()
                SaveSoon()
            end,
            --a deleted clip (or whatever the item shows) takes it off the table;
            --losing the right to have it (a DJ revoked) only hides it.
            thinkTime = 1,
            think = function(element)
                local s = Tabletop.itemKinds[item.kind]
                if s == nil or not s.available() then
                    element:DestroySelf()
                    item.panel = nil
                elseif not s.exists(item.key) then
                    CloseItem(item)
                end
            end,
            children = children,
        }
        layer:AddChild(panel)
        item.panel = panel
        for _, grip in ipairs(item.grips) do
            PlaceGrip(item, grip)
        end
    end

    --Puts an item on this user's table (or brings its item forward).
    --options.screen: the mouse in screen pixels, where a drop centres the
    --item (moving it if it is already on the table).
    function Tabletop.OpenItem(kind, key, options)
        options = options or {}
        local spec = Kind(kind)
        if not Tabletop.IsActive() or spec == nil or not spec.exists(key) then
            return
        end
        local lw, lh = LayerSize()
        local bw, bh = spec.size(key)
        local item = ItemByKey(kind, key)
        local scale = spec.defaultScale or 1
        if item ~= nil then
            scale = item.scale or 1
        end
        local x, y = nil, nil
        if options.screen ~= nil then
            local mx, my = ScreenToLayer(options.screen.x, options.screen.y)
            x = math.floor(mx - bw * scale / 2)
            y = math.floor(my - bh * scale / 2)
        end
        if item == nil then
            item = {
                kind = kind,
                key = key,
                x = x or math.floor((lw - bw * scale) / 2),
                y = y or math.floor((lh - bh * scale) / 2),
                scale = scale,
            }
            items[#items+1] = item
        elseif x ~= nil then
            item.x = x
            item.y = y
        end
        item.x = math.max(0, math.min(item.x, lw - 60))
        item.y = math.max(CARD_TITLE_HEIGHT, math.min(item.y, lh - 60))
        if item.panel == nil or not item.panel.valid then
            BuildItem(item)
        else
            item.panel.x = item.x
            item.panel.y = item.y
        end
        if item.panel ~= nil and item.panel.valid then
            item.panel:SetAsLastSibling()
        end
        SaveSoon()
    end

    CloseItem = function(item)
        if item.panel ~= nil and item.panel.valid then
            item.panel:DestroySelf()
        end
        item.panel = nil
        for i, other in ipairs(items) do
            if other == item then
                table.remove(items, i)
                break
            end
        end
        SaveSoon()
    end

    g_tableItems.Teardown = function()
        for _, item in ipairs(items) do
            if item.panel ~= nil and item.panel.valid then
                item.panel:DestroySelf()
            end
            item.panel = nil
        end
    end

    g_layoutWriters[#g_layoutWriters+1] = function(out)
        local saved = {}
        for _, item in ipairs(items) do
            saved[#saved+1] = {kind = item.kind, key = item.key, x = item.x, y = item.y, scale = item.scale}
        end
        out.items = saved
    end

    --Kinds may load after this file, and their things (audio clips) after
    --the layout: items are kept as saved and checked when they are built.
    g_tableItems.Load = function(layout)
        items = {}
        if layout == nil or type(layout.items) ~= "table" then
            return
        end
        for _, saved in ipairs(layout.items) do
            if type(saved) == "table" and type(saved.kind) == "string" and type(saved.key) == "string"
                    and ItemByKey(saved.kind, saved.key) == nil then
                items[#items+1] = {
                    kind = saved.kind,
                    key = saved.key,
                    x = tonumber(saved.x) or 100,
                    y = tonumber(saved.y) or 100,
                    scale = math.max(CARD_MIN_SCALE, math.min(CARD_MAX_SCALE, tonumber(saved.scale) or 1)),
                }
            end
        end
    end

    --A panel row being dragged out (a soundboard pad): over the bare table the
    --row steps aside (scale, since opacity doesn't reach children) and the item
    --a drop there makes follows the mouse. {row, kind, key, preview, rowHidden, seen}
    local rowDrag = nil

    function Tabletop.ItemRowDragEnded(row)
        local drag = rowDrag
        if drag == nil or (row ~= nil and drag.row ~= row) then
            return
        end
        rowDrag = nil
        if drag.rowHidden and drag.row.valid then
            drag.row.selfStyle.scale = 1
        end
        if drag.preview ~= nil and drag.preview.valid then
            drag.preview:DestroySelf()
        end
    end

    function Tabletop.ItemRowDragging(row, kind, key)
        if not Tabletop.IsActive() then
            return
        end
        if rowDrag ~= nil and (rowDrag.row ~= row or rowDrag.key ~= key) then
            Tabletop.ItemRowDragEnded(nil)
        end
        local spec = Kind(kind)
        if spec == nil or not spec.exists(key) then
            return
        end
        if rowDrag == nil then
            rowDrag = {row = row, kind = kind, key = key, rowHidden = false}
        end
        local drag = rowDrag
        drag.seen = dmhub.Time()

        local onTable = dmhub.panelDropSurface == "table"
        if onTable ~= drag.rowHidden then
            drag.rowHidden = onTable
            row.selfStyle.scale = cond(onTable, 0.01, 1)
        end

        local w, h = spec.size(key)
        if onTable and drag.preview == nil then
            local layer = DocumentsLayer()
            if layer ~= nil then
                local existing = ItemByKey(kind, key)
                local s = spec.defaultScale or 1
                if existing ~= nil then
                    s = existing.scale or 1
                end
                drag.preview = gui.Panel{
                    styles = ItemStyles(),
                    width = w,
                    height = h,
                    scale = s,
                    cornerRadius = spec.cornerRadius or 4,
                    boxShadow = TABLE_SHADOWS.lifted,
                    flow = "none",
                    spec.face(key),
                }
                layer:AddChild(drag.preview)
                --it rides under the mouse, so it must not count as a panel
                --there (dmhub.panelDropSurface) or take the drop.
                drag.preview:MakeNonInteractiveRecursive()
            end
        end
        local preview = drag.preview
        if preview ~= nil and preview.valid then
            preview:SetClass("collapsed", not onTable)
            if onTable then
                local mouse = dmhub.mouseScreenPosition
                local mx, my = ScreenToLayer(mouse.x, mouse.y)
                --scale is about the panel's centre, so it is centred on the
                --mouse by its unscaled size.
                preview.x = math.floor(mx - w / 2)
                preview.y = math.floor(my - h / 2)
                preview:SetAsLastSibling()
            end
        end
    end

    g_tableItems.Sync = function()
        --a drag can end without the row hearing of it (the panel rebuilt
        --mid-drag): the preview goes once its drag events stop.
        if rowDrag ~= nil and dmhub.Time() - (rowDrag.seen or 0) > 0.3 then
            Tabletop.ItemRowDragEnded(nil)
        end
        for _, item in ipairs(items) do
            if item.panel == nil or not item.panel.valid then
                BuildItem(item)
            end
        end
    end
end
DefineTableItems()

----------------------------------------------------------------------
--Scene windows. A scene from the Scenes library (ScenesPanel.lua) dragged
--onto the table -- or clicked in the panel -- opens in its own window: the
--picture (a still or a looping video) with its caption. Scene windows move,
--resize, maximize and close like map windows, and the Director's share icon
--puts them on the players' tables. The Director maximizing a shared one
--shows it full screen to everyone (an unshared one stays the Director's
--until shared, which then shows it; David, 2026-10-16); the title bar's
--Players / All control
--(FullscreenDisplay.UpdatePresentationBar) can narrow it to the players,
--with Below UI beside it, and closing the window stops showing it. Scenes
--are per user like the rest of the table, and minimize to a button on the
--table or the icon rail as map windows do. A function rather than a do
--block: this file is at Lua's 200-local limit, and a function's locals
--count on their own.
local function DefineSceneWindows()
    --{id, sceneid, x, y, width, height, maximized, minimized, iconX, iconY,
    --buttonOps} plus the built panel parts.
    local g_sceneWindows = {}

    local SCENE_MIN_WIDTH = 240
    local SCENE_MIN_HEIGHT = 160

    local function SceneItemId(sceneid)
        return "scene:" .. sceneid
    end

    local function SceneWindowFor(sceneid)
        for _, rec in ipairs(g_sceneWindows) do
            if rec.sceneid == sceneid then
                return rec
            end
        end
        return nil
    end

    local function SceneWindowById(id)
        for _, rec in ipairs(g_sceneWindows) do
            if rec.id == id then
                return rec
            end
        end
        return nil
    end

    --A minimized window that was maximized is not: it comes back maximized
    --when restored, as a map window does.
    local function MaximizedScene()
        for _, rec in ipairs(g_sceneWindows) do
            if rec.maximized and not rec.minimized then
                return rec
            end
        end
        return nil
    end

    --a maximized scene window's titlebar goes in the strip (g_chrome.Owner).
    g_chrome.maximizedScene = MaximizedScene

    --The Director's maximized scene shown to the Players only: it stays
    --maximized (so the title bar keeps its controls) but is not drawn here.
    local function SceneHiddenHere(rec)
        return rec.maximized and dmhub.isDM and Scenes.ShowState(rec.sceneid) == true
    end

    --- Whether a maximized window covers this user's table: a maximized map
    --- window, or a maximized scene window drawn here (not the Director's one
    --- shown to the Players alone). The Director's Screen is gone meanwhile.
    --- @return boolean
    function Tabletop.TableCovered()
        if not Tabletop.IsActive() then
            return false
        end
        if g_chrome.MaximizedMap() ~= nil then
            return true
        end
        local rec = MaximizedScene()
        return rec ~= nil and rec.panel ~= nil and rec.panel.valid and not SceneHiddenHere(rec)
    end

    --- The scene in this user's maximized scene window, or nil.
    --- @return nil|string
    function Tabletop.MaximizedSceneId()
        if not Tabletop.IsActive() then
            return nil
        end
        local rec = MaximizedScene()
        if rec == nil then
            return nil
        end
        return rec.sceneid
    end

    --A new scene window: a 16:9 picture under its titlebar, centred, stepping
    --past any scene window already there.
    local function ScenePlacement()
        local w, h = LayerSize()
        local width = math.floor(w * 0.42)
        local height = math.floor(width * 9 / 16) + TITLE_HEIGHT
        local x0 = math.floor((w - width) / 2)
        local y0 = math.floor((h - height) / 2)
        for step = 0, 11 do
            local x = x0 + 28 * (step % 6)
            local y = y0 + 28 * (step % 6)
            local taken = false
            for _, rec in ipairs(g_sceneWindows) do
                if math.abs(rec.x - x) < 8 and math.abs(rec.y - y) < 8 then
                    taken = true
                    break
                end
            end
            if not taken then
                return x, y, width, height
            end
        end
        return x0, y0, width, height
    end

    local ToggleSceneMaximize
    local CloseSceneWindow
    local MinimizeScene
    local RestoreScene

    --A minimized scene window (or one still growing back out of its button)
    --is hidden, and so is the Director's maximized scene shown to the Players
    --alone. A scene window is never hidden by a maximized window: they stack
    --by click order (map windows, unlike scenes, are hidden under a
    --maximized map; ApplyCollapsed).
    local function ApplySceneCollapsed(rec)
        local panel = rec.panel
        if panel == nil or not panel.valid then
            return
        end
        local growing = rec.restoring ~= nil and dmhub.Time() - rec.restoring < ANIM_SECONDS + 0.5
        local covered = rec.minimized == true or growing or (rec.maximized == true and SceneHiddenHere(rec))
        --on the Director's Screen while it is closed.
        covered = covered or (not rec.maximized and DirectorScreen.IsStowed(g_sharing.ScreenKey(rec)))
        if panel:HasClass("collapsed") ~= covered then
            panel:SetClass("collapsed", covered)
        end
        --maximized under the UI it is the table's background: its cards'
        --layer lets the mouse through, and the table passes it the drops
        --(SceneElements.DropOnBackground).
        if rec.view ~= nil and rec.view.valid then
            rec.view:FireEvent("setBackground", rec.maximized == true and not covered and panel.parent == g_layer)
        end
    end

    g_sharing.screenKinds[#g_sharing.screenKinds+1] = function(list)
        for _, rec in ipairs(g_sceneWindows) do
            local sceneid = rec.sceneid
            local store = g_sharing.DocStore(SceneItemId(sceneid), function()
                return {kind = "scene", sceneid = sceneid}
            end)
            list[#list+1] = g_sharing.ScreenWindowItem(rec, store, rec.share, ApplySceneCollapsed, MinimizeScene, RestoreScene)
        end
    end

    g_sharing.layoutKinds[#g_sharing.layoutKinds+1] = function(list)
        for _, rec in ipairs(g_sceneWindows) do
            local itemId = SceneItemId(rec.sceneid)
            list[#list+1] = g_sharing.WindowLayoutItem(rec, function()
                return IsItemSharedHere(itemId)
            end, SCENE_MIN_WIDTH, SCENE_MIN_HEIGHT)
        end
    end

    --A maximized scene on show with the title bar's Below UI on is the
    --table's background: it sits in the bottom layer, under everything.
    --Any other maximized scene behaves as a maximized map does (David,
    --2026-10-24).
    local function SceneUnderUI(rec)
        return rec.maximized == true and Scenes.ShowState(rec.sceneid) ~= false and Scenes.IsBelowUI()
    end

    --The layer a scene window belongs in: among the windows and journals,
    --or the bottom tabletop layer (SceneUnderUI).
    local function SceneLayer(rec)
        if SceneUnderUI(rec) then
            return g_layer
        end
        return DocumentsLayer()
    end

    --Puts a built scene window in its layer (SceneLayer). Maximized it fills,
    --cropping; in a window it shows the whole picture.
    local function PlaceSceneWindow(rec)
        local panel = rec.panel
        if panel == nil or not panel.valid then
            return
        end
        local target = SceneLayer(rec)
        if target == nil or not target.valid then
            return
        end
        if panel.parent ~= target then
            if panel.parent ~= nil then
                panel:Unparent()
            end
            target:AddChild(panel)
            rec.maximizedPanel = nil
        end
        --maximized among the windows: stacked as a maximized map is.
        g_chrome.StackMaximized(rec, rec.maximized == true and target ~= g_layer)
        if rec.maximized then
            panel.x = 0
            panel.y = 0
            panel.selfStyle.width = "100%"
            panel.selfStyle.height = "100%"
        else
            panel.x = rec.x
            panel.y = rec.y
            panel.selfStyle.width = rec.width
            panel.selfStyle.height = rec.height
        end
        rec.titlebar:SetClass("collapsed", rec.maximized == true)
        rec.resizePanel:SetClass("collapsed", rec.maximized == true)
        rec.view:FireEvent("setFit", cond(rec.maximized, "cover", "contain"))
        rec.maximizeButton:FireEventTree("setIcon", cond(rec.maximized, "window-chrome/chrome-restore.png", "window-chrome/chrome-maximize.png"))
        panel.draggable = rec.maximized ~= true
        --maximized under the UI it is the table's background: the mouse goes
        --through to the table layer, so drops, file drops and the right-click
        --menu work there as on the bare table (David, 2026-10-16).
        panel.interactable = target ~= g_layer
        panel:SetClass("tabletopMaximized", rec.maximized == true)
        ApplySceneCollapsed(rec)
        if rec.presentation ~= nil then
            rec.presentation:FireEvent("refreshPresentation")
        end
        g_chrome.Sync()
    end

    local function RefreshSceneWindow(rec)
        if rec.panel == nil or not rec.panel.valid then
            return
        end
        local name = Scenes.Name(rec.sceneid)
        if rec.nameLabel.text ~= name then
            rec.nameLabel.text = name
        end
        rec.view:FireEvent("showScene", Scenes.ViewInfo(rec.sceneid))
        UpdateShare(rec.share)
    end

    local function BuildSceneWindow(rec)
        local view = FullscreenDisplay.CreateSceneView{fit = "contain", textScale = 0.5}

        local nameLabel = g_chrome.NameLabel(Scenes.Name(rec.sceneid))

        --The Director's maximized scene: who it is shown to (Players / All;
        --closing the window hides it) and whether it sits under the UI. It
        --used to be the app title bar's presentation control
        --(FullscreenDisplay.UpdatePresentationBar), which now leaves a
        --maximized scene to this. Rebuilt only when what it shows changes.
        local presentation = nil
        if dmhub.isDM then
            presentation = gui.Panel{
                classes = {"collapsed"},
                flow = "horizontal",
                width = "auto",
                height = "100%",
                valign = "center",
                data = {signature = nil},
                refreshPresentation = function(element)
                    --(not while the share is off: then nobody is shown it.)
                    local shown = rec.maximized == true and not rec.minimized and Scenes.ShowState(rec.sceneid) ~= false
                    if element:HasClass("collapsed") == shown then
                        element:SetClass("collapsed", not shown)
                    end
                    if not shown then
                        element.data.signature = nil
                        return
                    end
                    local state = Scenes.ShowState(rec.sceneid)
                    local belowui = Scenes.IsBelowUI()
                    local signature = string.format("%s|%s", tostring(state), tostring(belowui))
                    if signature == element.data.signature then
                        return
                    end
                    element.data.signature = signature
                    element.children = {
                        g_chrome.Sep(),
                        gui.EnumeratedSliderControl{
                            valign = "center",
                            width = 150,
                            options = {
                                {id = true, text = "Players"},
                                {id = "all", text = "All"},
                            },
                            value = state,
                            change = function(slider)
                                Scenes.Present(rec.sceneid, slider.value)
                            end,
                        },
                        gui.Check{
                            valign = "center",
                            lmargin = 12,
                            rmargin = 4,
                            text = "Below UI",
                            fontSize = 14,
                            value = belowui,
                            hover = gui.Tooltip("Show the scene under the game's panels, rather than over everything"),
                            change = function(check)
                                Scenes.SetBelowUI(check.value)
                            end,
                        },
                    }
                end,
            }
        end

        --the ping, left of the share button: everyone it is shared with
        --sees it flash (DefinePings).
        local controls = {
            g_sharing.PingButton(function()
                return g_sharing.LayoutKey(rec)
            end),
        }
        local share = nil
        if dmhub.isDM then
            share = ShareControl{
                itemId = SceneItemId(rec.sceneid),
                newItem = function()
                    return {kind = "scene", sceneid = rec.sceneid}
                end,
                what = "this scene",
                iconSize = 15,
                --the share is what shows a scene to the players: turning it
                --off stops showing it full screen, and turning it on shows a
                --maximized one again (as maximizing it did).
                changed = function()
                    if ShareState(SceneItemId(rec.sceneid)) == nil then
                        if Scenes.PresentedId() == rec.sceneid then
                            Scenes.Present(rec.sceneid, false)
                        end
                    elseif rec.maximized and not rec.minimized and not Scenes.ShowState(rec.sceneid) then
                        Scenes.Present(rec.sceneid, "all")
                    end
                    PlaceSceneWindow(rec)
                    Refresh()
                    FullscreenDisplay.UpdatePresentationBar()
                end,
            }
            controls[#controls+1] = share.button
            --who besides the Director may change the cards in the scene
            --(SceneElements.lua). Its icon follows the scene's document.
            local editControl = WindowControl{
                icon = SceneElements.EditModeInfo(rec.sceneid).icon,
                iconSize = 14,
                hover = function(element)
                    gui.Tooltip("Who can change this scene: " .. SceneElements.EditModeInfo(rec.sceneid).tip)(element)
                end,
                click = function(element)
                    local current = SceneElements.EditMode(rec.sceneid)
                    local entries = {}
                    for _, info in ipairs(SceneElements.EDIT_MODES) do
                        local mode = info.id
                        entries[#entries+1] = {
                            text = info.text,
                            check = current == mode,
                            click = function()
                                GuardClicks()
                                element.popup = nil
                                SceneElements.SetEditMode(rec.sceneid, mode)
                            end,
                        }
                    end
                    element.tooltip = nil
                    element.popup = gui.ContextMenu{entries = entries}
                end,
            }
            controls[#controls+1] = gui.Panel{
                width = "auto",
                height = "100%",
                valign = "center",
                flow = "horizontal",
                monitorGame = SceneElements.DocPath(rec.sceneid),
                refreshGame = function(element)
                    editControl:FireEventTree("setIcon", SceneElements.EditModeInfo(rec.sceneid).icon)
                end,
                editControl,
            }
            controls[#controls+1] = WindowControl{
                icon = "phosphor/gear-six-fill.png",
                iconSize = 14,
                hover = gui.Tooltip("Edit scene"),
                click = function(element)
                    Scenes.ShowEditor(rec.sceneid)
                end,
            }
        end
        --a player who moved or resized it gives it back to the Director.
        controls[#controls+1] = g_sharing.FollowButton(function()
            return g_sharing.LayoutKey(rec)
        end)
        controls[#controls+1] = WindowControl{
            icon = "window-chrome/chrome-minimize.png",
            click = function(element)
                MinimizeScene(rec)
            end,
        }
        local maximizeButton = WindowControl{
            icon = "window-chrome/chrome-maximize.png",
            hover = function(element)
                local text = "Restore"
                if not rec.maximized then
                    if not dmhub.isDM then
                        text = "Maximize"
                    elseif ShareState(SceneItemId(rec.sceneid)) ~= nil then
                        text = "Maximize: it shows full screen to everyone (choose Players beside its name to show only them; click share to stop showing it)"
                    else
                        text = "Maximize: only you see it until you share it"
                    end
                end
                gui.Tooltip(text)(element)
            end,
            click = function(element)
                ToggleSceneMaximize(rec)
            end,
        }
        controls[#controls+1] = maximizeButton
        controls[#controls+1] = WindowControl{
            danger = true,
            icon = "window-chrome/chrome-close.png",
            click = function(element)
                CloseSceneWindow(rec)
            end,
        }

        local titlebar = g_chrome.Titlebar(rec, {nameLabel, presentation}, controls)

        local resizeDoc = {
            try_get = function(self, key)
                return rawget(self, key)
            end,
        }
        local resizePanel = gui.WindowResizePanel(resizeDoc, rec.width, rec.height, {
            minWidth = SCENE_MIN_WIDTH,
            minHeight = SCENE_MIN_HEIGHT,
            onResized = function(dialog, moved)
                rec.width = dialog.selfStyle.width
                rec.height = dialog.selfStyle.height
                rec.x, rec.y = ClampWindow(rec, dialog.x, dialog.y)
                if rec.x ~= dialog.x or rec.y ~= dialog.y then
                    dialog.x = rec.x
                    dialog.y = rec.y
                end
                SaveSoon()
                g_sharing.TookControl(g_sharing.LayoutKey(rec))
            end,
        })

        local panel = gui.Panel{
            styles = g_windowStyles,
            classes = {"tabletopWindow"},
            --click-to-front from a press anywhere on it (engine walk).
            raiseOnPress = true,
            flow = "vertical",
            x = rec.x,
            y = rec.y,
            width = rec.width,
            height = rec.height,
            halign = "left",
            valign = "top",
            bgimage = "panels/square.png",
            swallowPress = true,
            draggable = true,
            --stays among the table items while dragged, so the Director's
            --Screen can lie over it (DirectorScreen KeepOnTop).
            dragInPlace = true,
            dragging = function(element)
                if not rec.maximized then
                    DirectorScreen.ItemDragging(g_sharing.ScreenKey(rec), element.xdrag, rec.width, element)
                end
            end,
            drag = function(element)
                if rec.maximized then
                    return
                end
                rec.x, rec.y = SnapWindow(rec, element.xdrag, element.ydrag)
                element.x = rec.x
                element.y = rec.y
                SaveSoon()
                g_sharing.TookControl(g_sharing.LayoutKey(rec))
                --onto the Director's Screen it is the Director's alone; off
                --it, the players get it (DirectorScreen.lua).
                DirectorScreen.ItemDropped(g_sharing.ScreenKey(rec))
            end,
            --kept to swallow the click. It no longer raises: the press already did
            --(raiseOnPress), and raising again on the click buried a window a press
            --inside it had just opened, as on a map window (2026-10-25).
            click = function()
            end,
            children = {
                titlebar,
                gui.Panel{
                    width = "100%",
                    height = "100% available",
                    flow = "none",
                    view,
                },
                resizePanel,
                share and share.frame,
            },
        }

        rec.panel = panel
        rec.titlebar = titlebar
        rec.view = view
        rec.nameLabel = nameLabel
        rec.presentation = presentation
        rec.maximizeButton = maximizeButton
        rec.share = share
        rec.resizePanel = resizePanel
        --in the strip, the presentation control follows the scene's show state
        --(g_chrome.Sync runs on every tick).
        rec.onChrome = function()
            if presentation ~= nil and presentation.valid then
                presentation:FireEvent("refreshPresentation")
            end
        end
        RefreshSceneWindow(rec)
    end

    local function EnsureSceneBuilt(rec)
        if rec.panel == nil or not rec.panel.valid then
            BuildSceneWindow(rec)
        end
        PlaceSceneWindow(rec)
    end

    --A map window being maximized: scene windows step down.
    UnmaximizeScenes = function()
        for _, rec in ipairs(g_sceneWindows) do
            if rec.maximized then
                rec.maximized = false
                --still on show to everyone, the full-screen display would keep
                --covering the Director's screen: narrow it to the Players.
                if dmhub.isDM and Scenes.ShowState(rec.sceneid) == "all" then
                    Scenes.Present(rec.sceneid, true)
                end
                PlaceSceneWindow(rec)
            end
        end
        FullscreenDisplay.UpdatePresentationBar()
    end

    ToggleSceneMaximize = function(rec)
        rec.maximized = not rec.maximized
        if rec.maximized then
            --one maximized window at a time: maps or scenes.
            for _, other in ipairs(g_sceneWindows) do
                if other ~= rec and other.maximized then
                    other.maximized = false
                    PlaceSceneWindow(other)
                end
            end
            local unmaximizedMap = false
            for _, other in ipairs(g_windows) do
                if other.maximized and not IsForcedHere(other) then
                    other.maximized = false
                    PlaceWindow(other)
                    Tabletop.SetForced(other.mapid, false)
                    unmaximizedMap = true
                end
            end
            if unmaximizedMap then
                --the map windows it covered come back out (ApplyCollapsed).
                Refresh()
            end
            --the Director maximizing a shared scene shows it to everyone; the
            --title bar then narrows it to the Players, and the share button
            --stops it. One already on show keeps its audience. Maximizing
            --never shares (David, 2026-10-16): an unshared scene stays the
            --Director's, and its share button shows it (share's changed).
            if dmhub.isDM and not Scenes.ShowState(rec.sceneid) and ShareState(SceneItemId(rec.sceneid)) ~= nil then
                Scenes.Present(rec.sceneid, "all")
            end
        elseif dmhub.isDM and Scenes.ShowState(rec.sceneid) == "all" then
            --restoring a scene on show to everyone: the full-screen display
            --would still cover the Director's screen (the window looks like it
            --did not restore), so the Players keep it and the Director does not.
            Scenes.Present(rec.sceneid, true)
        end
        PlaceSceneWindow(rec)
        if not rec.maximized and rec.panel ~= nil and rec.panel.valid then
            rec.panel:SetAsLastSibling()
        end
        Refresh()
        FullscreenDisplay.UpdatePresentationBar()
        SaveSoon()
    end

    CloseSceneWindow = function(rec)
        if rec.panel ~= nil and rec.panel.valid then
            g_chrome.Release(rec)
            rec.panel:DestroySelf()
        end
        rec.panel = nil
        if rec.button ~= nil and rec.button.valid then
            rec.button:DestroySelf()
        end
        rec.button = nil
        if IsDocked(rec) then
            IconRailKeyPurge(RailKey(rec))
        end
        for i, other in ipairs(g_sceneWindows) do
            if other == rec then
                table.remove(g_sceneWindows, i)
                break
            end
        end
        rec.maximized = false
        --closing a scene's window is how the Director stops showing it.
        if dmhub.isDM and Scenes.PresentedId() == rec.sceneid then
            Scenes.Present(rec.sceneid, false)
        end
        Refresh()
        FullscreenDisplay.UpdatePresentationBar()
        SaveSoon()
    end

    ----------------------------------------------------------------------
    --Minimizing: the same button on the table or the icon rail, and the same
    --collapse animation, as a map window (UpdateTableButton, AnimateGhost).

    --The picture a minimized scene shows (its button's hover card and the
    --collapse animation): its image, or a placeholder for a video or none.
    local function SceneStill(rec)
        local scene = Scenes.Get(rec.sceneid) or {}
        local image = scene.image
        if type(image) ~= "string" or image == "" or FullscreenDisplay.IsVideo(image) then
            return "panels/square.png", true
        end
        return image, false
    end

    --The hover card for a minimized scene window's button (floating or
    --docked): the scene's name, whether it is on show, and its picture.
    local function ShowScenePreview(rec, element)
        local image, placeholder = SceneStill(rec)
        local scene = Scenes.Get(rec.sceneid) or {}
        local status = {}
        if type(scene.image) == "string" and FullscreenDisplay.IsVideo(scene.image) then
            status[#status+1] = "Video"
        end
        if dmhub.isDM and Scenes.PresentedId() == rec.sceneid then
            status[#status+1] = "Showing to the players"
        end
        status[#status+1] = "Click to open"

        local width = 260
        local content = gui.Panel{
            flow = "vertical",
            width = "auto",
            height = "auto",
            gui.Label{
                text = Scenes.Name(rec.sceneid),
                bold = true,
                fontSize = 16,
                color = "#f2ede1",
                width = "auto",
                height = "auto",
                halign = "left",
                textWrap = false,
            },
            gui.Label{
                text = table.concat(status, "  -  "),
                fontSize = 12,
                color = "#bdb3a4",
                width = "auto",
                height = "auto",
                halign = "left",
                textWrap = false,
                bmargin = 6,
            },
            gui.Panel{
                bgimage = image,
                bgcolor = cond(placeholder, "#1b1814ff", "white"),
                width = width,
                height = math.floor(width * 9 / 16),
                halign = "left",
                cornerRadius = 4,
            },
        }
        element.tooltip = gui.TooltipFrame(content)
    end

    --Collapses a scene window into its button: on the table where its middle
    --was (or where its button was left last time), or on the rail if docked.
    MinimizeScene = function(rec)
        if rec.minimized then
            return
        end
        local from = WindowRect(rec)
        if rec.iconX == nil then
            local size = BUTTON_SIZE * ButtonScale()
            rec.iconX = math.floor(from.x + from.w / 2 - size / 2)
            rec.iconY = math.floor(from.y + from.h / 2 - size / 2)
        end
        rec.minimized = true
        rec.restoring = nil
        --on show to everyone, the full-screen display would keep covering the
        --Director's screen: the players keep it, and everyone gets it back
        --when the window is restored (still maximized).
        if rec.maximized and dmhub.isDM and Scenes.ShowState(rec.sceneid) == "all" then
            Scenes.Present(rec.sceneid, true)
            rec.showAllOnRestore = true
        end
        PlaceSceneWindow(rec)
        Refresh()
        FullscreenDisplay.UpdatePresentationBar()
        AnimateGhost(rec, from, ButtonRect(rec), function()
            if SceneWindowById(rec.id) == rec and rec.minimized then
                UpdateTableButton(rec)
                if rec.button ~= nil and rec.button.valid then
                    rec.button:PulseClass("justDropped")
                end
            end
        end)
        SaveSoon()
    end

    --Grows a minimized scene window back out of its button and brings it
    --forward. While it grows (rec.restoring, the time it started) the window
    --stays hidden; the time runs out on its own if the animation is lost.
    RestoreScene = function(rec)
        if not rec.minimized then
            if rec.panel ~= nil and rec.panel.valid and rec.panel.parent ~= g_layer then
                rec.panel:SetAsLastSibling()
            end
            return
        end
        local from = ButtonRect(rec)
        rec.minimized = false
        rec.restoring = dmhub.Time()
        UpdateTableButton(rec)
        AnimateGhost(rec, from, WindowRect(rec), function()
            rec.restoring = nil
            if SceneWindowById(rec.id) ~= rec or rec.minimized then
                return
            end
            if rec.maximized and rec.showAllOnRestore and dmhub.isDM and Scenes.ShowState(rec.sceneid) == true then
                Scenes.Present(rec.sceneid, "all")
            end
            rec.showAllOnRestore = nil
            PlaceSceneWindow(rec)
            if rec.panel ~= nil and rec.panel.valid and rec.panel.parent ~= g_layer then
                rec.panel:SetAsLastSibling()
            end
            Refresh()
            FullscreenDisplay.UpdatePresentationBar()
        end)
        SaveSoon()
    end

    --What a minimized scene window's button shows and does (see
    --UpdateTableButton); every scene window record carries it as buttonOps.
    local g_sceneButtonOps = {
        icon = "phosphor/image.png",
        image = SceneStill,
        restore = RestoreScene,
        close = CloseSceneWindow,
        closeText = "Close Scene Window",
        hover = ShowScenePreview,
        chatItems = function(rec)
            return {ChatItemLinks.SceneItem(rec.sceneid)}
        end,
        --the Director is showing the scene to the players.
        badge = {icon = "phosphor/eye-fill.png", color = "#ffd27a"},
        badgeShown = function(rec)
            return dmhub.isDM and Scenes.PresentedId() == rec.sceneid
        end,
    }

    --Minimized scene windows docked on the icon rail ("scenewindow:<window
    --id>" in the rail layout; see RailEntryTypes in DocumentSystem.lua), as
    --map windows are. The docked button stays on the rail while its window
    --is open, lit.
    RailEntryTypes = rawget(_G, "RailEntryTypes") or {}
    RailEntryTypes.scenewindow = {
        available = function(id)
            return Tabletop.IsActive() and SceneWindowById(id) ~= nil
        end,
        name = function(id)
            local rec = SceneWindowById(id)
            if rec == nil then
                return "Scene Window"
            end
            return Scenes.Name(rec.sceneid)
        end,
        icon = function(id)
            return "phosphor/image.png"
        end,
        isActive = function(id)
            local rec = SceneWindowById(id)
            return rec ~= nil and not rec.minimized
        end,
        --opens a minimized window; an open one collapses back onto the rail.
        activate = function(id, element)
            local rec = SceneWindowById(id)
            if rec == nil then
                return
            end
            if rec.minimized then
                RestoreScene(rec)
            else
                MinimizeScene(rec)
            end
        end,
        hover = function(id, element)
            local rec = SceneWindowById(id)
            if rec ~= nil then
                ShowScenePreview(rec, element)
            end
        end,
        menu = function(id, element)
            local rec = SceneWindowById(id)
            if rec == nil then
                return {}
            end
            return {
                GuardedEntry(cond(rec.minimized, "Restore", "Minimize"), function()
                    element.popup = nil
                    if rec.minimized then
                        RestoreScene(rec)
                    else
                        MinimizeScene(rec)
                    end
                end),
                GuardedEntry("Close Scene Window", function()
                    element.popup = nil
                    CloseSceneWindow(rec)
                end),
            }
        end,
        --taken off the rail: a minimized window's button goes back on the
        --table, next to the rail it left.
        onRemove = function(id)
            local rec = SceneWindowById(id)
            if rec == nil then
                return
            end
            if rec.minimized then
                local w = LayerSize()
                rec.iconX = math.min(rec.iconX or 80, w - 80)
                rec.iconY = rec.iconY or 120
            end
            UpdateTableButton(rec)
            SaveSoon()
        end,
    }

    --This user's scene windows, for the Windows menu.
    g_sharing.SceneWindowStates = function()
        local result = {}
        for _, rec in ipairs(g_sceneWindows) do
            result[#result+1] = {sceneid = rec.sceneid, minimized = rec.minimized == true}
        end
        return result
    end

    --- The scene windows, for the Ctrl+Tab window switcher (see
    --- Tabletop.SwitcherMapWindows). The Director's maximized scene shown to
    --- the Players alone is left out: it is not drawn on this screen.
    --- @return SwitcherWindow[]
    function Tabletop.SwitcherSceneWindows()
        local result = {}
        if not Tabletop.IsActive() then
            return result
        end
        for _, rec in ipairs(g_sceneWindows) do
            if rec.minimized or not SceneHiddenHere(rec) then
                local image, placeholder = SceneStill(rec)
                result[#result+1] = {
                    key = "scene:" .. rec.id,
                    kind = "scene",
                    name = Scenes.Name(rec.sceneid),
                    panel = rec.panel,
                    image = image,
                    placeholder = placeholder,
                    minimized = rec.minimized == true,
                    maximized = rec.maximized == true,
                    onShow = Scenes.ShowState(rec.sceneid) ~= false,
                    activate = function()
                        if rec.minimized then
                            RestoreScene(rec)
                        elseif rec.panel ~= nil and rec.panel.valid then
                            rec.panel:SetAsLastSibling()
                        end
                    end,
                }
            end
        end
        return result
    end

    --- Opens a scene on this user's table, or brings its window forward.
    --- options.x/y: where the window goes (documents-layer units);
    --- options.shared: it arrived from the Director's share.
    --- @param sceneid string
    --- @param options nil|{x: nil|number, y: nil|number, shared: nil|boolean}
    function Tabletop.OpenScene(sceneid, options)
        options = options or {}
        if not Tabletop.IsActive() or Scenes.Get(sceneid) == nil then
            return
        end
        local rec = SceneWindowFor(sceneid)
        if rec == nil then
            local x, y, width, height = ScenePlacement()
            rec = {
                id = dmhub.GenerateGuid(),
                sceneid = sceneid,
                x = options.x or x,
                y = options.y or y,
                width = width,
                height = height,
                maximized = false,
                buttonOps = g_sceneButtonOps,
                fromShare = options.shared == true or nil,
            }
            rec.x, rec.y = ClampWindow(rec, rec.x, rec.y)
            g_sceneWindows[#g_sceneWindows+1] = rec
        elseif options.x ~= nil and not rec.maximized then
            rec.x, rec.y = ClampWindow(rec, options.x, options.y)
        end
        EnsureSceneBuilt(rec)
        if rec.minimized then
            if options.shared then
                --shared again by the Director: its button says so, as a
                --minimized map window's does.
                if rec.button ~= nil and rec.button.valid then
                    rec.button:PulseClass("justDropped")
                end
            else
                --grows back out, to the drop spot if it was dropped.
                RestoreScene(rec)
            end
            SaveSoon()
            return
        end
        --a maximized one keeps its place, as a maximized map does (BringToFront).
        if not rec.maximized and rec.panel ~= nil and rec.panel.valid then
            rec.panel:SetAsLastSibling()
        end
        Highlight(rec)
        SaveSoon()
    end

    ----------------------------------------------------------------------
    --A scene row dragged out of the Scenes panel. Over the bare table the row
    --steps aside and the window a drop makes follows the mouse.

    --{row, sceneid, preview, rowHidden, seen}
    local g_sceneRowDrag = nil

    local function SceneDropRect(sceneid)
        local rec = SceneWindowFor(sceneid)
        local width, height
        if rec ~= nil and not rec.maximized then
            width, height = rec.width, rec.height
        else
            local _, _, w, h = ScenePlacement()
            width, height = w, h
        end
        local mouse = dmhub.mouseScreenPosition
        local mx, my = ScreenToLayer(mouse.x, mouse.y)
        local tw, th = LayerSize()
        local x = math.floor(mx - width / 2)
        local y = math.floor(my - height / 2)
        x = math.max(0, math.min(x, tw - width))
        y = math.max(0, math.min(y, th - height))
        return x, y, width, height
    end

    local function BuildSceneDropPreview(sceneid, width, height)
        local layer = DocumentsLayer()
        if layer == nil then
            return nil
        end
        local scene = Scenes.Get(sceneid) or {}
        local image = scene.image
        if type(image) ~= "string" or FullscreenDisplay.IsVideo(image) then
            image = nil
        end
        local panel = gui.Panel{
            flow = "vertical",
            halign = "left",
            valign = "top",
            width = width,
            height = height,
            bgimage = "panels/square.png",
            bgcolor = "#100d0bff",
            borderWidth = 2,
            borderColor = "#00000099",
            boxShadow = TABLE_SHADOWS.lifted,
            gui.Panel{
                styles = ThemeEngine.MergeStyles(g_titleStyles),
                classes = {"tabletopTitle"},
                flow = "horizontal",
                width = "100%",
                height = TITLE_HEIGHT,
                bgimage = "panels/square.png",
                gui.Label{
                    classes = {"tabletopTitleText"},
                    width = "auto",
                    height = "100%",
                    halign = "left",
                    valign = "center",
                    hmargin = 8,
                    textWrap = false,
                    text = Scenes.Name(sceneid),
                },
            },
            gui.Panel{
                width = "100%",
                height = "100% available",
                bgimage = image or "panels/square.png",
                bgcolor = cond(image ~= nil, "white", "#1b1814ff"),
            },
        }
        layer:AddChild(panel)
        panel:MakeNonInteractiveRecursive()
        return panel
    end

    function Tabletop.SceneRowDragEnded(row)
        local drag = g_sceneRowDrag
        if drag == nil or (row ~= nil and drag.row ~= row) then
            return
        end
        g_sceneRowDrag = nil
        if drag.rowHidden and drag.row.valid then
            drag.row.selfStyle.scale = 1
        end
        if drag.preview ~= nil and drag.preview.valid then
            drag.preview:DestroySelf()
        end
    end

    function Tabletop.SceneRowDragging(row, sceneid)
        if not Tabletop.IsActive() then
            return
        end
        if g_sceneRowDrag ~= nil and g_sceneRowDrag.row ~= row then
            Tabletop.SceneRowDragEnded(nil)
        end
        if g_sceneRowDrag == nil then
            g_sceneRowDrag = {row = row, sceneid = sceneid, rowHidden = false}
        end
        local drag = g_sceneRowDrag
        drag.seen = dmhub.Time()

        local onTable = dmhub.panelDropSurface == "table"
        if onTable ~= drag.rowHidden then
            drag.rowHidden = onTable
            row.selfStyle.scale = cond(onTable, 0.01, 1)
        end

        if not onTable then
            if drag.preview ~= nil and drag.preview.valid then
                drag.preview:SetClass("collapsed", true)
            end
            DirectorScreen.ItemDragging(nil, 0, 0)
            return
        end

        local x, y, width, height = SceneDropRect(sceneid)
        if drag.preview == nil or not drag.preview.valid then
            drag.preview = BuildSceneDropPreview(sceneid, width, height)
        end
        local preview = drag.preview
        if preview ~= nil and preview.valid then
            preview:SetClass("collapsed", false)
            preview.x = x
            preview.y = y
            preview:SetAsLastSibling()
        end
        --whether the drop shares it or keeps it behind the Director's Screen.
        DirectorScreen.NewItemDragging(x, width)
    end

    --- A scene row released with no drop target under it: on the bare table
    --- the scene opens there (or its window moves there). Returns true if the
    --- drop was taken.
    --- @param sceneid string
    --- @return boolean
    function Tabletop.SceneRowDropped(sceneid)
        if not Tabletop.IsActive() or dmhub.panelDropSurface ~= "table" or Scenes.Get(sceneid) == nil then
            return false
        end
        local x, y = SceneDropRect(sceneid)
        Tabletop.OpenScene(sceneid, {x = x, y = y})
        --dropped on the Director's Screen it stays private; anywhere else its
        --share is left as it is (DirectorScreen.lua).
        local rec = SceneWindowFor(sceneid)
        if rec ~= nil then
            DirectorScreen.ItemPlaced(g_sharing.ScreenKey(rec))
        end
        return true
    end

    --- Opens a scene in a new-size window centred on (mx, my), a point in
    --- documents-layer units (a file dropped on the table), kept on the table.
    --- @param sceneid string
    --- @param mx number
    --- @param my number
    function Tabletop.OpenSceneCentredAt(sceneid, mx, my)
        local _, _, width, height = ScenePlacement()
        local tw, th = LayerSize()
        local x = math.max(0, math.min(math.floor(mx - width / 2), tw - width))
        local y = math.max(0, math.min(math.floor(my - height / 2), th - height))
        Tabletop.OpenScene(sceneid, {x = x, y = y})
        --a drop: private if it lands on the Director's Screen.
        local rec = SceneWindowFor(sceneid)
        if rec ~= nil then
            DirectorScreen.ItemPlaced(g_sharing.ScreenKey(rec))
        end
    end

    ----------------------------------------------------------------------
    --Lifecycle and saving.

    --What the windows last reacted to (shares, the scene on show, whether a
    --scene shows under the UI here), and the next once-a-second refresh,
    --which picks up library edits.
    local g_sceneSignature = nil
    local g_nextSceneRefresh = 0

    SyncSceneWindows = function()
        --the library is ScenesPanel.lua, in another mod.
        if rawget(_G, "Scenes") == nil then
            return
        end
        if g_sceneRowDrag ~= nil and dmhub.Time() - (g_sceneRowDrag.seen or 0) > 0.3 then
            Tabletop.SceneRowDragEnded(nil)
        end

        --a deleted scene takes its window with it.
        for i = #g_sceneWindows, 1, -1 do
            local rec = g_sceneWindows[i]
            if Scenes.Get(rec.sceneid) == nil then
                CloseSceneWindow(rec)
            end
        end

        for _, rec in ipairs(g_sceneWindows) do
            if rec.panel == nil or not rec.panel.valid then
                EnsureSceneBuilt(rec)
            elseif rec.panel.parent ~= SceneLayer(rec) then
                --Below UI flipped, or the scene went on or off show.
                PlaceSceneWindow(rec)
            else
                ApplySceneCollapsed(rec)
            end
        end

        local signature = string.format("%s|%s", tostring(ShareDoc().data.seq), tostring(Scenes.PresentedId()))
        if signature ~= g_sceneSignature or dmhub.Time() >= g_nextSceneRefresh then
            g_sceneSignature = signature
            g_nextSceneRefresh = dmhub.Time() + 1
            for _, rec in ipairs(g_sceneWindows) do
                RefreshSceneWindow(rec)
                --a minimized window's button (built once the layer is up, and
                --moved between the table and the rail as the rail turns on/off).
                UpdateTableButton(rec)
            end
            --a maximized scene restored with the layout gets its title bar
            --control (it only rebuilds when something changed).
            FullscreenDisplay.UpdatePresentationBar()
        end
    end

    TeardownSceneWindows = function()
        for _, rec in ipairs(g_sceneWindows) do
            if rec.panel ~= nil and rec.panel.valid then
                g_chrome.Release(rec)
                rec.panel:DestroySelf()
            end
            rec.panel = nil
            if rec.button ~= nil and rec.button.valid then
                rec.button:DestroySelf()
            end
            rec.button = nil
            rec.restoring = nil
        end
        g_sceneSignature = nil
    end

    g_layoutWriters[#g_layoutWriters+1] = function(out)
        local list = {}
        for _, rec in ipairs(g_sceneWindows) do
            list[#list+1] = {
                id = rec.id,
                sceneid = rec.sceneid,
                x = rec.x,
                y = rec.y,
                width = rec.width,
                height = rec.height,
                maximized = rec.maximized == true,
                minimized = rec.minimized == true,
                iconX = rec.iconX,
                iconY = rec.iconY,
                card = rec.card == true or nil,
                fromShare = rec.fromShare,
            }
        end
        out.scenes = list
    end

    g_sharing.unshareClosers[#g_sharing.unshareClosers+1] = function(stillShared)
        local gone = {}
        for _, rec in ipairs(g_sceneWindows) do
            if rec.fromShare and not stillShared(SceneItemId(rec.sceneid)) then
                gone[#gone+1] = rec
            end
        end
        for _, rec in ipairs(gone) do
            CloseSceneWindow(rec)
        end
    end

    LoadSceneWindows = function(layout)
        g_sceneWindows = {}
        if layout == nil or type(layout.scenes) ~= "table" or rawget(_G, "Scenes") == nil then
            return
        end
        --one maximized window at a time (a minimized one counts: it comes
        --back maximized).
        local anyMaximized = false
        for _, saved in ipairs(layout.scenes) do
            if type(saved) == "table" and type(saved.sceneid) == "string" and Scenes.Get(saved.sceneid) ~= nil
                    and SceneWindowFor(saved.sceneid) == nil then
                local rec = {
                    id = saved.id or dmhub.GenerateGuid(),
                    sceneid = saved.sceneid,
                    x = tonumber(saved.x) or 100,
                    y = tonumber(saved.y) or 100,
                    width = math.max(SCENE_MIN_WIDTH, tonumber(saved.width) or 640),
                    height = math.max(SCENE_MIN_HEIGHT, tonumber(saved.height) or 400),
                    maximized = saved.maximized == true and not anyMaximized,
                    minimized = saved.minimized == true,
                    iconX = tonumber(saved.iconX),
                    iconY = tonumber(saved.iconY),
                    card = saved.card == true or nil,
                    buttonOps = g_sceneButtonOps,
                    fromShare = saved.fromShare == true or nil,
                }
                anyMaximized = anyMaximized or rec.maximized
                --below the minimum: saved against an unlaid-out layer (see
                --LayerSize), so place it afresh.
                if (tonumber(saved.width) or SCENE_MIN_WIDTH) < SCENE_MIN_WIDTH or (tonumber(saved.height) or SCENE_MIN_HEIGHT) < SCENE_MIN_HEIGHT then
                    rec.x, rec.y, rec.width, rec.height = ScenePlacement()
                end
                rec.x, rec.y = ClampWindow(rec, rec.x, rec.y)
                g_sceneWindows[#g_sceneWindows+1] = rec
            end
        end
    end
end
DefineSceneWindows()

--First time in this game (or the view was just turned on): restore the
--saved layout, else open one window on the map we are on.
----------------------------------------------------------------------
--The title bar's Windows menu (CodexTitleBar.lua): every window and item on
--this user's table, checked while it is open (not minimized). A player's
--menu also lists what the Director has shared with them AND has open on
--their own table, so a player who closed one can get it back. Picking a row
--brings it forward, opening or restoring it first.
--
--What a Director has open is published in the "tabletop" document as
--data.open[userid] = {["map:<mapid>"] = true, ["scene:<sceneid>"] = true,
--["card:<charid>"] = true, ["doc:<entryid>"] = true}, one set per Director
--(a minimized window still counts as open). Checked twice a second and
--written only when it changes. It stays after the Director leaves, so the
--players keep the list while the Director is away.
--
--Defined in a function rather than a do block: this file's main chunk is at
--Lua's 200-local limit, and a function's locals do not count against it.
g_sharing.DefineWindowsMenu = function()
    local ICONS = {
        map = "phosphor/map-trifold.png",
        scene = "phosphor/film-slate.png",
        journal = "phosphor/book-open-text.png",
        doc = "phosphor/file-text.png",
        card = "phosphor/user.png",
    }
    --the menu's sections, top to bottom; a divider goes between them.
    local GROUP_ORDER = {"map", "scene", "journal", "doc", "card"}

    local state = {signature = nil, nextCheck = 0}

    --The share keys of everything on this user's table.
    local function OpenKeys()
        local keys = {}
        for _, rec in ipairs(g_windows) do
            keys["map:" .. rec.mapid] = true
        end
        for _, scene in ipairs(g_sharing.SceneWindowStates()) do
            keys["scene:" .. scene.sceneid] = true
        end
        for _, card in ipairs(g_cards) do
            keys[CardItemId(card.charid)] = true
        end
        for _, entryid in ipairs(g_sharing.DocItemEntryIds()) do
            keys["doc:" .. entryid] = true
        end
        return keys
    end

    local function KeySignature(keys)
        local sorted = {}
        if type(keys) == "table" then
            for key, on in pairs(keys) do
                if on == true then
                    sorted[#sorted+1] = key
                end
            end
        end
        table.sort(sorted)
        return table.concat(sorted, ",")
    end

    g_sharing.PublishDirectorOpen = function()
        if not dmhub.isDM or dmhub.Time() < state.nextCheck then
            return
        end
        state.nextCheck = dmhub.Time() + 0.5
        local keys = OpenKeys()
        local signature = KeySignature(keys)
        if signature == state.signature then
            return
        end
        state.signature = signature
        local doc = ShareDoc()
        local open = doc.data.open
        --already there: written before a reload, or by this Director's other window.
        if type(open) == "table" and KeySignature(open[dmhub.userid]) == signature then
            return
        end
        doc:BeginChange()
        if type(doc.data.open) ~= "table" then
            doc.data.open = {}
        end
        doc.data.open[dmhub.userid] = keys
        doc:CompleteChange("Windows open on the table", {undoable = false})
    end

    --What the other Directors have open (every Director's set but our own).
    local function DirectorOpenKeys()
        local result = {}
        local open = ShareDoc().data.open
        if type(open) ~= "table" then
            return result
        end
        for userid, keys in pairs(open) do
            if userid ~= dmhub.userid and type(keys) == "table" then
                for key, on in pairs(keys) do
                    if on == true then
                        result[key] = true
                    end
                end
            end
        end
        return result
    end

    --- The rows of the title bar's Windows menu: this user's map, scene and
    --- journal windows and table items, and on a player's table the ones the
    --- Director shares with them and has open, which they closed. A row is
    --- checked while it is open and not minimized; picking one brings it
    --- forward, opening or restoring it first.
    --- @return ContextMenuEntry[]
    function Tabletop.WindowsMenuEntries()
        if not Tabletop.IsActive() then
            return {}
        end

        local groups = {}
        for _, group in ipairs(GROUP_ORDER) do
            groups[group] = {}
        end
        --the share keys listed already, so a shared one is not listed twice.
        local listed = {}
        --items pinged while this user had them closed or hidden (key ->
        --ping): their rows ping as the menu opens. Opening the menu uses them up.
        local pinged = g_sharing.TakePendingPings()

        local function Add(group, key, name, open, activate)
            if key ~= nil then
                listed[key] = true
            end
            local ping = key ~= nil and pinged[key] or nil
            local list = groups[group]
            list[#list+1] = {
                text = name,
                icon = ICONS[group],
                check = open,
                group = group,
                create = ping ~= nil and function(element)
                    g_sharing.PlayPing(element, ping, {spread = 10})
                end or nil,
                click = function()
                    --the click must not also press the window under the menu.
                    GuardClicks()
                    activate()
                    --and the window it opens pings too, once it is up.
                    if ping ~= nil then
                        dmhub.Schedule(0.35, function()
                            if not mod.unloaded then
                                g_sharing.ShowPing(key, ping, false)
                            end
                        end)
                    end
                end,
            }
        end

        --A row for something not on this table, when this user can open it:
        --a map they may view, or a scene, journal entry or card shared with
        --them (anything, for the Director).
        local function AddClosed(key)
            local kind, id = string.match(key, "^(%a+):(.+)$")
            if listed[key] or id == nil then
                return
            end
            if kind == "map" then
                if MapExists(id) and Tabletop.CanAccessMap(id) then
                    Add("map", key, MapName(id), false, function()
                        Tabletop.OpenMap(id, {newWindow = true})
                    end)
                end
            elseif kind == "scene" then
                if IsItemSharedHere(key) and Scenes.Get(id) ~= nil then
                    Add("scene", key, Scenes.Name(id), false, function()
                        Tabletop.OpenScene(id)
                    end)
                end
            elseif kind == "doc" then
                local entry = CustomDocument.FindJournalEntry(id)
                if IsItemSharedHere(key) and entry ~= nil then
                    Add("doc", key, entry.description or "Untitled", false, function()
                        Tabletop.OpenDocItem(id)
                    end)
                end
            elseif kind == "card" then
                local tok = dmhub.GetCharacterById(id)
                if IsItemSharedHere(key) and tok ~= nil then
                    Add("card", key, tok.name or "Character", false, function()
                        Tabletop.OpenCard(id)
                    end)
                end
            end
        end

        for _, rec in ipairs(g_windows) do
            Add("map", "map:" .. rec.mapid, MapName(rec.mapid), not rec.minimized, function()
                Focus(rec)
            end)
        end
        for _, scene in ipairs(g_sharing.SceneWindowStates()) do
            local sceneid = scene.sceneid
            Add("scene", "scene:" .. sceneid, Scenes.Name(sceneid), not scene.minimized, function()
                Tabletop.OpenScene(sceneid)
            end)
        end
        local switcher = rawget(_G, "WindowSwitcher")
        if switcher ~= nil then
            for _, entry in ipairs(switcher.JournalWindows()) do
                Add("journal", nil, entry.name, not entry.minimized, entry.activate)
            end
        end
        for _, entryid in ipairs(g_sharing.DocItemEntryIds()) do
            local entry = CustomDocument.FindJournalEntry(entryid)
            Add("doc", "doc:" .. entryid, (entry ~= nil and entry.description) or "Untitled", true, function()
                Tabletop.OpenDocItem(entryid)
            end)
        end
        for _, card in ipairs(g_cards) do
            local charid = card.charid
            local tok = dmhub.GetCharacterById(charid)
            Add("card", CardItemId(charid), (tok ~= nil and tok.name) or "Character", true, function()
                Tabletop.OpenCard(charid)
            end)
        end

        --a player's: what the Director shares with them and has open, but
        --is not on their own table.
        if not dmhub.isDM then
            for key in pairs(DirectorOpenKeys()) do
                AddClosed(key)
            end
        end
        --anything pinged that this table has closed.
        for key in pairs(pinged) do
            AddClosed(key)
        end

        local result = {}
        for _, group in ipairs(GROUP_ORDER) do
            local list = groups[group]
            table.sort(list, function(a, b)
                return string.lower(a.text or "") < string.lower(b.text or "")
            end)
            for _, entry in ipairs(list) do
                result[#result+1] = entry
            end
        end
        return result
    end
end
g_sharing.DefineWindowsMenu()

--The Director's placement on the players' tables (David, 2026-10-16). A
--shared window, card or journal item sits where the Director puts it, at the
--Director's size, and follows when the Director moves or resizes it. A
--player who moves or resizes one takes it over: the Director's moves stop
--reaching it until they click its follow button (FollowButton) to hand it
--back.
--
--The Director publishes every table item's windowed rectangle in the
--"tabletop" document as data.layout[key] = {x, y, w, h, s, tw, th, by}
--(s: a card's or journal item's scale; tw, th: the Director's table size;
--by: the Director who placed it). A player's table maps that onto its own
--size (Target) and applies it whenever the entry or their table size
--changes. What each player took over is saved with their layout
--(layoutOwned). (A function, not a do block: the main chunk is at Lua's
--200-local limit.)
g_sharing.DefineDirectorLayout = function()
    --last: key -> signature this Director last published (nil until the
    --first pass after loading, which leaves other Directors' entries alone,
    --so a reload does not overwrite another Director's newer placement).
    local publish = {nextCheck = 0, last = nil}
    --applied: key -> the entry signature (plus table size) a player's table
    --last applied, so an item is moved only when the Director moves it.
    local follow = {applied = {}}
    --{keyFn, panel} for every follow button, refreshed by the follow pass
    --(a collapsed panel does not think, so the buttons cannot poll).
    local buttons = {}
    --key -> true for each item this player has taken over.
    g_sharing.layoutOwned = {}

    local function Round(v)
        return math.floor(v + 0.5)
    end

    local function Items()
        local list = {}
        for _, kind in ipairs(g_sharing.layoutKinds) do
            kind(list)
        end
        return list
    end

    local function Signature(e)
        return string.format("%s,%s,%s,%s,%s,%s,%s", tostring(e.x), tostring(e.y), tostring(e.w), tostring(e.h), tostring(e.s), tostring(e.tw), tostring(e.th))
    end

    local function Layout()
        local layout = ShareDoc().data.layout
        if type(layout) ~= "table" then
            return {}
        end
        return layout
    end

    local function ValidEntry(e)
        return type(e) == "table" and tonumber(e.x) ~= nil and tonumber(e.y) ~= nil and tonumber(e.w) ~= nil
            and tonumber(e.h) ~= nil and (tonumber(e.tw) or 0) > 0 and (tonumber(e.th) or 0) > 0
    end

    g_sharing.PublishDirectorLayout = function()
        if not dmhub.isDM or dmhub.Time() < publish.nextCheck then
            return
        end
        publish.nextCheck = dmhub.Time() + 0.3

        local tw, th = LayerSize()
        local mine = {}
        for _, item in ipairs(Items()) do
            local r = item.key ~= nil and item.get() or nil
            if r ~= nil then
                local e = {x = Round(r.x), y = Round(r.y), w = Round(r.w), h = Round(r.h), tw = Round(tw), th = Round(th), by = dmhub.userid}
                if r.s ~= nil then
                    e.s = math.floor(r.s * 1000 + 0.5) / 1000
                end
                mine[item.key] = e
            end
        end

        local layout = Layout()
        local first = publish.last == nil
        local last = publish.last or {}
        local signatures = {}
        local writes = {}
        local any = false
        for key, e in pairs(mine) do
            local signature = Signature(e)
            signatures[key] = signature
            local there = layout[key]
            local stale = type(there) == "table" and Signature(there) ~= signature
            --after loading, only this Director's own entries are brought up to date.
            if first then
                stale = stale and there.by == dmhub.userid
            else
                stale = stale and last[key] ~= signature
            end
            if type(there) ~= "table" or stale then
                writes[key] = e
                any = true
            end
        end
        --what this Director placed and has since closed is no longer theirs to place.
        for key, there in pairs(layout) do
            if mine[key] == nil and type(there) == "table" and there.by == dmhub.userid then
                writes[key] = false
                any = true
            end
        end
        publish.last = signatures
        if not any then
            return
        end

        local doc = ShareDoc()
        doc:BeginChange()
        if type(doc.data.layout) ~= "table" then
            doc.data.layout = {}
        end
        for key, e in pairs(writes) do
            if e == false then
                doc.data.layout[key] = nil
            else
                doc.data.layout[key] = e
            end
        end
        doc:CompleteChange("Table layout", {undoable = false})
    end

    --Where a value placed at pos with size on an axis of length total lands
    --on an axis of newTotal at newSize: the same share of the free space, so
    --an item flush to an edge stays flush and a centred one stays centred.
    local function MapAxis(pos, size, newSize, total, newTotal)
        local gap = total - size
        if gap > 1 and newTotal - newSize > 0 then
            return pos / gap * (newTotal - newSize)
        end
        return (pos + size / 2) / total * newTotal - newSize / 2
    end

    --The Director's entry on this table: sizes scaled to fit (the table's
    --height is nearly fixed, so this is 1 unless the screen is narrower).
    local function Target(e)
        local pw, ph = LayerSize()
        local tw, th = tonumber(e.tw), tonumber(e.th)
        local scale = math.min(pw / tw, ph / th)
        local w, h = tonumber(e.w) * scale, tonumber(e.h) * scale
        local s = tonumber(e.s)
        return {
            x = MapAxis(tonumber(e.x), tonumber(e.w), w, tw, pw),
            y = MapAxis(tonumber(e.y), tonumber(e.h), h, th, ph),
            w = w,
            h = h,
            s = s ~= nil and s * scale or nil,
        }
    end

    local function UpdateButtons(layout, byKey)
        for i = #buttons, 1, -1 do
            local entry = buttons[i]
            if entry.panel == nil or not entry.panel.valid then
                table.remove(buttons, i)
            else
                local key = entry.keyFn()
                local item = key ~= nil and byKey[key] or nil
                local show = item ~= nil and g_sharing.layoutOwned[key] == true and ValidEntry(layout[key]) and item.followed()
                if entry.panel:HasClass("collapsed") == show then
                    entry.panel:SetClass("collapsed", not show)
                end
            end
        end
    end

    --Every tick on a player's table: shared items not taken over go where
    --the Director has them.
    g_sharing.FollowDirectorLayout = function()
        if dmhub.isDM then
            return
        end
        local layout = Layout()
        local pw, ph = LayerSize()
        local size = string.format("|%d,%d", Round(pw), Round(ph))
        local byKey = {}
        local changed = false
        for _, item in ipairs(Items()) do
            local key = item.key
            if key ~= nil then
                byKey[key] = item
                local e = layout[key]
                if not ValidEntry(e) or g_sharing.layoutOwned[key] or not item.followed() then
                    follow.applied[key] = nil
                else
                    local signature = Signature(e) .. size
                    if follow.applied[key] ~= signature and item.set(Target(e)) then
                        follow.applied[key] = signature
                        changed = true
                    end
                end
            end
        end
        for key in pairs(follow.applied) do
            if byKey[key] == nil then
                follow.applied[key] = nil
            end
        end
        --closed: taking it over ends, so a share that opens it again places
        --it where the Director has it.
        for key in pairs(g_sharing.layoutOwned) do
            if byKey[key] == nil then
                g_sharing.layoutOwned[key] = nil
                changed = true
            end
        end
        UpdateButtons(layout, byKey)
        if changed then
            SaveSoon()
        end
    end

    --Whether an item is somewhere other than the Director's placement (a
    --drag that ended where it began, or snapped back, is not a move).
    local function MovedFrom(item, e)
        local r = item.get()
        if r == nil then
            return false
        end
        local t = Target(e)
        return math.abs(r.x - t.x) > 2 or math.abs(r.y - t.y) > 2 or math.abs(r.w - t.w) > 2 or math.abs(r.h - t.h) > 2
    end

    --- A player moved or resized a table item: if it was following the
    --- Director's placement, it is theirs to place from now on.
    --- @param key nil|string
    g_sharing.TookControl = function(key)
        local e = key ~= nil and Layout()[key] or nil
        if dmhub.isDM or key == nil or g_sharing.layoutOwned[key] or not ValidEntry(e) then
            return
        end
        for _, item in ipairs(Items()) do
            if item.key == key then
                if item.followed() and MovedFrom(item, e) then
                    g_sharing.layoutOwned[key] = true
                    SaveSoon()
                    g_sharing.FollowDirectorLayout()
                end
                return
            end
        end
    end

    --The follow button in a titlebar, shown on a player's table while they
    --have taken the item over (nil for the Director). keyFn names the item:
    --a window can switch maps. args: iconSize, width, passPress, as for
    --WindowControl.
    g_sharing.FollowButton = function(keyFn, args)
        if dmhub.isDM then
            return nil
        end
        args = args or {}
        local button = WindowControl{
            icon = "phosphor/arrow-counter-clockwise.png",
            iconSize = args.iconSize or 14,
            width = args.width,
            passPress = args.passPress,
            hover = gui.Tooltip("You moved this, so the Director's moves no longer reach it. Click to put it back where the Director has it."),
            click = function(element)
                local key = keyFn()
                if key == nil then
                    return
                end
                g_sharing.layoutOwned[key] = nil
                follow.applied[key] = nil
                SaveSoon()
                g_sharing.FollowDirectorLayout()
            end,
        }
        button:SetClass("collapsed", true)
        buttons[#buttons+1] = {keyFn = keyFn, panel = button}
        return button
    end

    g_layoutWriters[#g_layoutWriters+1] = function(out)
        if not dmhub.isDM then
            out.layoutOwned = g_sharing.layoutOwned
        end
    end

    g_sharing.LoadDirectorLayout = function(layout)
        g_sharing.layoutOwned = {}
        if layout ~= nil and type(layout.layoutOwned) == "table" then
            for key, on in pairs(layout.layoutOwned) do
                if on == true then
                    g_sharing.layoutOwned[key] = true
                end
            end
        end
        follow.applied = {}
        publish.last = nil
        publish.nextCheck = 0
    end
end
g_sharing.DefineDirectorLayout()

--Pings (David, 2026-10-16). A shared window, card or journal item has a ping
--button beside its share button, for the Director and for the players it is
--shared with. Pressing it sends a remote event; everyone the item is shared
--with sees rings pulse out from its border, in the pinger's colour, with
--their name. Where the item is closed or hidden on someone's table, its
--minimized button pings instead, or else the title bar's Windows menu does,
--and that item's row pings when the menu next opens.
g_sharing.DefinePings = function()
    local PING_EVENT = "tabletopPing"
    --how long the rings run, and how long each ring takes to spread out.
    local PING_SECONDS = 2.4
    local PULSE_SECONDS = 0.8
    --how long a ping waits in the Windows menu for the menu to be opened.
    local PENDING_SECONDS = 120
    local DEFAULT_COLOR = "#ffd27aff"
    --lastSent: key -> time, so a held-down click does not flood everyone.
    --sentIds: this client's own pings, so an echo is not shown twice.
    --pending: key -> ping waiting for the Windows menu. lastPending: the
    --newest of those (the menu's ring takes its colour). menuSerial: bumped
    --per new pending ping; menuShown: the serial the menu last rang for.
    --buttons: {keyFn, panel} per ping button, shown only while shared.
    local state = {lastSent = {}, sentIds = {}, pending = {}, lastPending = nil, menuSerial = 0, menuShown = 0, buttons = {}, nextCheck = 0}

    local function ItemFor(key)
        local list = {}
        for _, kind in ipairs(g_sharing.layoutKinds) do
            kind(list)
        end
        for _, item in ipairs(list) do
            if item.key == key then
                return item
            end
        end
        return nil
    end

    --- Whether a table item is shared: with anyone, for the Director; with
    --- this player, for a player. A map's share is its Player Viewable.
    --- @param key string
    --- @return boolean
    g_sharing.IsKeyShared = function(key)
        local kind, id = string.match(key, "^(%a+):(.+)$")
        if id == nil then
            return false
        end
        if kind == "map" then
            if dmhub.isDM then
                return g_sharing.MapStore(id).state() ~= nil
            end
            local map = game.GetMap(id)
            return map ~= nil and map.valid and map.playerViewable == true
        end
        return IsItemSharedHere(key)
    end

    local function PingColor(userid)
        local color = DEFAULT_COLOR
        pcall(function()
            local info = dmhub.GetSessionInfo(userid)
            if info ~= nil then
                color = info.displayColor.tostring
            end
        end)
        return color
    end

    --- Rings pulse out from a panel's border (in from it, with inset, for a
    --- panel that fills the table). ping is {from = userid}. opts: spread
    --- (how far a ring travels, default 28), inset, cornerRadius, label
    --- (show the pinger's name), sound.
    g_sharing.PlayPing = function(target, ping, opts)
        if target == nil or not target.valid then
            return
        end
        opts = opts or {}
        local spread = opts.spread or 28
        local color = PingColor(ping.from)
        local start = dmhub.Time()

        local label = nil
        if opts.label then
            label = gui.Label{
                floating = true,
                interactable = false,
                halign = "left",
                valign = "top",
                x = cond(opts.inset, 12, 0),
                y = cond(opts.inset, TITLE_HEIGHT + 12, -28),
                width = "auto",
                height = "auto",
                hpad = 8,
                vpad = 2,
                borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#000000d9",
                borderWidth = 1,
                borderColor = color,
                cornerRadius = 4,
                fontSize = 13,
                bold = true,
                color = color,
                textWrap = false,
                text = dmhub.GetDisplayName(ping.from) or "Ping",
            }
            target:AddChild(label)
        end

        target:AddChild(gui.Panel{
            floating = true,
            interactable = false,
            halign = "left",
            valign = "top",
            x = 0,
            y = 0,
            width = math.max(1, target.renderedWidth),
            height = math.max(1, target.renderedHeight),
            bgimage = "panels/square.png",
            bgcolor = "clear",
            borderWidth = 3,
            borderColor = color,
            cornerRadius = opts.cornerRadius or 0,
            thinkTime = 0.01,
            think = function(element)
                local t = dmhub.Time() - start
                if t >= PING_SECONDS or not target.valid then
                    element:DestroySelf()
                    if label ~= nil and label.valid then
                        label:DestroySelf()
                    end
                    return
                end
                local phase = (t % PULSE_SECONDS) / PULSE_SECONDS
                local d = spread * phase
                if opts.inset then
                    d = -d
                end
                element.x = -d
                element.y = -d
                element.selfStyle.width = math.max(1, target.renderedWidth + 2 * d)
                element.selfStyle.height = math.max(1, target.renderedHeight + 2 * d)
                element.selfStyle.cornerRadius = math.max(0, (opts.cornerRadius or 0) + d)
                element.selfStyle.opacity = 1 - phase
                if label ~= nil and label.valid then
                    label.selfStyle.opacity = math.min(1, (PING_SECONDS - t) / 0.5)
                end
            end,
        })
        if opts.sound then
            audio.FireSoundEvent("Notify.Ping")
        end
    end

    local function Visible(panel)
        return panel ~= nil and panel.valid and not panel:HasClass("collapsed")
    end

    --- Shows a ping on this table: rings the item if it is in view, else
    --- its minimized button, else leaves it for the Windows menu.
    --- @param key string
    --- @param ping {from: string}
    --- @param sound boolean
    g_sharing.ShowPing = function(key, ping, sound)
        local item = ItemFor(key)
        local target = item ~= nil and item.target() or nil
        if target ~= nil and Visible(target.panel) then
            g_sharing.PlayPing(target.panel, ping, {inset = target.maximized, cornerRadius = target.cornerRadius, label = true, sound = sound})
            return
        end
        if target ~= nil and Visible(target.button) then
            g_sharing.PlayPing(target.button, ping, {spread = 12, cornerRadius = 6, label = true, sound = sound})
            return
        end
        state.pending[key] = {from = ping.from, time = dmhub.Time()}
        state.lastPending = state.pending[key]
        state.menuSerial = state.menuSerial + 1
        if sound then
            audio.FireSoundEvent("Notify.Ping")
        end
    end

    local function SendPing(key)
        if key == nil or not g_sharing.IsKeyShared(key) then
            return
        end
        local now = dmhub.Time()
        if now - (state.lastSent[key] or -10) < 1 then
            return
        end
        state.lastSent[key] = now
        local id = dmhub.GenerateGuid()
        state.sentIds[id] = true
        dmhub.BroadcastRemoteEvent(PING_EVENT, id, {id = id, key = key, from = dmhub.userid, gameid = dmhub.gameid}, true)
        g_sharing.ShowPing(key, {from = dmhub.userid}, true)
    end

    --everyone the item is shared with sees it (the Director always does).
    dmhub.RegisterRemoteEvent(PING_EVENT, function(info)
        if mod.unloaded or type(info) ~= "table" or type(info.key) ~= "string" or type(info.from) ~= "string" then
            return
        end
        if state.sentIds[info.id] or info.gameid ~= dmhub.gameid or not Tabletop.IsActive() then
            return
        end
        if not g_sharing.IsKeyShared(info.key) then
            return
        end
        g_sharing.ShowPing(info.key, {from = info.from}, true)
    end)

    --- The ping button in a titlebar, beside the share button, shown while
    --- the item is shared (IsKeyShared). keyFn names the item: a window can
    --- switch maps. args: iconSize, width, passPress, as for WindowControl.
    g_sharing.PingButton = function(keyFn, args)
        args = args or {}
        local button = WindowControl{
            icon = "phosphor/broadcast.png",
            iconSize = args.iconSize or 15,
            width = args.width,
            passPress = args.passPress,
            hover = gui.Tooltip("Ping: make this flash for everyone it is shared with"),
            click = function(element)
                SendPing(keyFn())
            end,
        }
        local key = keyFn()
        button:SetClass("collapsed", key == nil or not g_sharing.IsKeyShared(key))
        state.buttons[#state.buttons+1] = {keyFn = keyFn, panel = button}
        return button
    end

    --Four times a second: ping buttons follow their items' shares, and a
    --waiting ping whose item has come into view is no longer waiting.
    g_sharing.SyncPings = function()
        if dmhub.Time() < state.nextCheck then
            return
        end
        state.nextCheck = dmhub.Time() + 0.25
        for i = #state.buttons, 1, -1 do
            local entry = state.buttons[i]
            if entry.panel == nil or not entry.panel.valid then
                table.remove(state.buttons, i)
            else
                local key = entry.keyFn()
                local show = key ~= nil and g_sharing.IsKeyShared(key)
                if entry.panel:HasClass("collapsed") == show then
                    entry.panel:SetClass("collapsed", not show)
                end
            end
        end
        local now = dmhub.Time()
        for key, ping in pairs(state.pending) do
            local item = ItemFor(key)
            local target = item ~= nil and item.target() or nil
            if now - ping.time > PENDING_SECONDS or (target ~= nil and (Visible(target.panel) or Visible(target.button))) then
                state.pending[key] = nil
            end
        end
    end

    --- The pings waiting for the Windows menu (key -> {from, time}), which
    --- opening the menu uses up (Tabletop.WindowsMenuEntries).
    --- @return table<string, {from: string, time: number}>
    g_sharing.TakePendingPings = function()
        local result = state.pending
        state.pending = {}
        return result
    end

    --- Whether a ping is waiting for the title bar's Windows menu (its alert dot).
    --- @return boolean
    function Tabletop.HasWindowsMenuPing()
        return next(state.pending) ~= nil
    end

    --- Called by the Windows menu item as it polls: rings it once for each
    --- new waiting ping.
    --- @param element Panel
    function Tabletop.UpdateWindowsMenuPing(element)
        if state.menuShown == state.menuSerial then
            return
        end
        state.menuShown = state.menuSerial
        if state.lastPending ~= nil and next(state.pending) ~= nil then
            g_sharing.PlayPing(element, state.lastPending, {spread = 10, cornerRadius = 4})
        end
    end
end
g_sharing.DefinePings()

local function InitForGame()
    g_windows = {}
    g_focusedId = nil
    g_liveId = nil
    g_pendingAdopt = nil
    g_lastMapId = game.currentMapId

    local layout = LoadLayout()
    g_seenShares = {}
    g_shareSignature = nil
    if layout ~= nil and type(layout.seenShares) == "table" then
        g_seenShares = layout.seenShares
    end
    --a new table opens every map viewable for this player; one saved before
    --the list was kept only starts tracking from here.
    g_sharing.viewable.seen = {}
    g_sharing.viewable.seed = false
    g_sharing.viewable.nextCheck = 0
    if layout ~= nil and type(layout.viewableMaps) == "table" then
        g_sharing.viewable.seen = layout.viewableMaps
    elseif layout ~= nil then
        g_sharing.viewable.seed = true
    end
    LoadCards(layout)
    LoadDocItems(layout)
    g_tableItems.Load(layout)
    LoadSceneWindows(layout)
    g_sharing.LoadDirectorLayout(layout)
    DirectorScreen.Load(layout ~= nil and layout.directorScreen or nil)
    NoteExistingMapDialog()
    if layout ~= nil and type(layout.windows) == "table" then
        for _,saved in ipairs(layout.windows) do
            --a player's table keeps only maps they can still open (no longer
            --Player Viewable for them, their token moved on).
            if type(saved) == "table" and type(saved.mapid) == "string" and MapExists(saved.mapid) and WindowForMap(saved.mapid) == nil
                    and Tabletop.CanAccessMap(saved.mapid) then
                local rec = {
                    id = saved.id or dmhub.GenerateGuid(),
                    mapid = saved.mapid,
                    x = tonumber(saved.x) or 100,
                    y = tonumber(saved.y) or 100,
                    width = math.max(MIN_WIDTH, tonumber(saved.width) or 800),
                    height = math.max(MIN_HEIGHT, tonumber(saved.height) or 600),
                    maximized = saved.maximized == true,
                    minimized = saved.minimized == true,
                    iconX = tonumber(saved.iconX),
                    iconY = tonumber(saved.iconY),
                    card = saved.card == true or nil,
                }
                --a window can't be resized below the minimum, so a smaller
                --saved size was made against an unlaid-out layer (see
                --LayerSize): place it afresh.
                if (tonumber(saved.width) or MIN_WIDTH) < MIN_WIDTH or (tonumber(saved.height) or MIN_HEIGHT) < MIN_HEIGHT then
                    rec.x, rec.y, rec.width, rec.height = DefaultPlacement()
                end
                --the screen may be smaller than when it was saved.
                rec.x, rec.y = ClampWindow(rec, rec.x, rec.y)
                g_windows[#g_windows+1] = rec
            end
        end
        if WindowById(layout.focused) ~= nil then
            g_focusedId = layout.focused
        end
    end

    --the map we are on is the quick one to show: focus its window, or open one.
    --A player who may not view it (no hero there yet) gets no window; one
    --opens when that changes (g_sharing.SyncCurrentMapAccess).
    local canAccess = Tabletop.CanAccessMap(game.currentMapId)
    g_sharing.currentAccess = {ok = canAccess, nextCheck = 0}
    local current = WindowForMap(game.currentMapId)
    if current == nil and #g_windows == 0 and canAccess then
        current = NewWindowRecord(game.currentMapId)
        g_windows[#g_windows+1] = current
    end
    if current ~= nil then
        g_focusedId = current.id
    end
end

--Once a second: close windows whose map was deleted, and refresh the
--frozen windows' titles (another map's combat moves on without us).
local g_nextHousekeeping = 0

local function Housekeeping()
    for i = #g_windows, 1, -1 do
        local rec = g_windows[i]
        if not MapExists(rec.mapid) then
            CloseWindow(rec)
        end
    end
    RecheckForced()
    Refresh()
end

local function Sync()
    local active = Tabletop.IsActive()
    if dmhub.tabletopMode ~= active then
        dmhub.tabletopMode = active
    end

    CheckRowDragEnded()
    UpdateTokenDragPreview()

    if active then
        SyncSurface()
    end

    --leaving the game (or sitting in the lobby): no table.
    if not active then
        if #g_windows > 0 or g_gameid ~= nil then
            Teardown()
            TeardownCards()
            TeardownDocItems()
            g_tableItems.Teardown()
            TeardownSceneWindows()
            g_windows = {}
            g_gameid = nil
            --docked map windows leave the rail with the view.
            IconRailRebuildSoon()
        end
        return
    end

    if g_gameid ~= dmhub.gameid then
        --the layer's create calls this before its first layout pass; wait for
        --its real size, or the restore is clamped to a 100x100 table.
        if not Tabletop.LayerReady() then
            return
        end
        Teardown()
        TeardownCards()
        TeardownDocItems()
        g_tableItems.Teardown()
        TeardownSceneWindows()
        g_gameid = dmhub.gameid
        g_sharing.localForcedSignature = ""
        InitForGame()
        IconRailRebuildSoon()
    end

    if DocumentsLayer() == nil or g_layer == nil or not g_layer.valid then
        return
    end

    SyncShares()
    g_sharing.SyncLocalForced()
    g_sharing.SyncViewableMaps()
    g_sharing.SyncCurrentMapAccess()
    SyncCards()
    SyncDocItems()
    g_tableItems.Sync()
    SyncSceneWindows()
    g_sharing.FollowDirectorLayout()
    g_sharing.SyncPings()
    DirectorScreen.Sync()
    g_sharing.PublishDirectorOpen()
    g_sharing.PublishDirectorLayout()
    --cheap when nothing moved; catches a scene's show state changing.
    g_chrome.Sync()

    local built = false
    for _,rec in ipairs(g_windows) do
        if rec.panel == nil or not rec.panel.valid then
            EnsureBuilt(rec)
            built = true
        end
    end

    if game.currentMapId ~= g_lastMapId then
        local fromMapId = g_lastMapId
        g_lastMapId = game.currentMapId
        OnCurrentMapChanged(game.currentMapId, fromMapId)
    elseif built then
        Refresh()
        --windows are rebuilt in creation order; the live one belongs on top.
        local live = WindowById(g_liveId)
        if live ~= nil and not live.maximized then
            BringToFront(live)
        end
    elseif dmhub.Time() >= g_nextHousekeeping then
        g_nextHousekeeping = dmhub.Time() + 1
        Housekeeping()
    end
end

--The engine fires this inside the map change itself, so the windows swap
--in the same frame the new map is built (hidden behind the dissolve).
dmhub.RegisterEventHandler("ChangeCurrentFloor", function()
    if mod.unloaded or not Tabletop.IsActive() then
        return
    end
    Sync()
end)

--Keeps the engine's table surface in step with this user's choice. A
--surface no longer offered (Wood and Slate were removed) is changed to the
--default once, so the settings dropdown and the menu show what is drawn. One
--whose dice set this account doesn't own draws as leather but stays chosen:
--the inventory may just not have loaded yet.
SyncSurface = function()
    local surface = g_surfaceSetting:Get()
    if surface ~= "custom" then
        local known = nil
        for _, entry in ipairs(TABLE_SURFACES) do
            if entry.id == surface then
                known = entry
                break
            end
        end
        if known == nil then
            surface = "leather"
            g_surfaceSetting:Set(surface)
        elseif not TABLE_SURFACES.Offered(known) then
            surface = "leather"
        end
    end
    local image = g_surfaceImageSetting:Get()
    if image == "" then
        image = nil
    end
    if dmhub.tabletopSurface ~= surface then
        dmhub.tabletopSurface = surface
    end
    if dmhub.tabletopSurfaceImage ~= image then
        dmhub.tabletopSurfaceImage = image
    end
end

----------------------------------------------------------------------
--Image and video files dragged in from the desktop onto the bare table
--(Director only). The drop opens the Add Image / Add Video dialog
--(TableDropDialog.lua): a map, scenes, or pictures and videos on the table,
--each opening where they were dropped. Files over a live map window never
--reach the table: the engine places them on the map.

--The card by the mouse while files are over the table, or nil.
local g_fileDragGhost = nil

local function EndTableFileDrag()
    if g_fileDragGhost ~= nil and g_fileDragGhost.valid then
        g_fileDragGhost:DestroySelf()
    end
    g_fileDragGhost = nil
end

local function BeginTableFileDrag(paths)
    EndTableFileDrag()
    local media = {}
    local sounds = {}
    for _, path in ipairs(paths) do
        if FileDrops.IsAudio(path) then
            sounds[#sounds+1] = path
        else
            media[#media+1] = path
        end
    end
    local text
    if #media == 0 then
        text = string.format("Put %s on the table to play", FileDrops.Describe(sounds))
    elseif #sounds == 0 then
        text = string.format("Add %s to the table", FileDrops.Describe(media))
    else
        text = string.format("Add %s to the table, and %s to play",
            FileDrops.Describe(media), FileDrops.Describe(sounds))
    end
    local ghost
    ghost = FileDrops.ShowGhost(text, function()
        return g_fileDragGhost == ghost
    end)
    g_fileDragGhost = ghost
end

--- Each file becomes a scene (in the Scenes library) opened at (mx, my) on
--- the table, stepping down-right for each further file.
--- @param paths string[]
--- @param mx number
--- @param my number
function Tabletop.AddFilesAsScenes(paths, mx, my)
    for i, path in ipairs(paths) do
        local imageid = FileDrops.UploadImage(path, {library = "coverart"})
        if imageid ~= nil then
            local sceneid = Scenes.Create{
                name = FileDrops.BaseName(path),
                image = imageid,
            }
            local step = 28 * (i - 1)
            Tabletop.OpenSceneCentredAt(sceneid, mx + step, my + step)
        end
    end
end

--- The files become one new map (a floor each) through the import wizard,
--- whose window opens at (mx, my) on the table once the map exists.
--- options (optional): aspect, the image's width over height -- the window
--- takes that shape and frames the whole map once it is placed; variations,
--- more files that become the map's alternate appearances (paths is then
--- the one base image); name, the map's name (else the first file's);
--- created(mapid), called once the map exists.
--- @param paths string[]
--- @param mx number
--- @param my number
--- @param options nil|{aspect: nil|number, variations: nil|string[], name: nil|string, created: nil|fun(mapid: string)}
function Tabletop.AddFilesAsMap(paths, mx, my, options)
    options = options or {}
    local rec = nil
    ImportMapFromFiles(paths, {
        name = options.name or FileDrops.BaseName(paths[1]),
        variations = options.variations,
        created = function(mapid)
            if mod.unloaded or WindowForMap(mapid) ~= nil then
                return
            end
            rec = NewWindowRecord(mapid)
            local aspect = options.aspect
            if aspect ~= nil and aspect > 0 then
                --the picture's shape under the titlebar, as big as a map
                --opened from the Maps panel (Tabletop.ShapedBox).
                local boxW, boxH = Tabletop.ShapedBox()
                rec.width, rec.height = Tabletop.ShapeWindow(boxW, boxH, aspect)
            end
            local tw, th = LayerSize()
            rec.x = math.max(0, math.min(math.floor(mx - rec.width / 2), tw - rec.width))
            rec.y = math.max(0, math.min(math.floor(my - rec.height / 2), th - rec.height))
            g_windows[#g_windows+1] = rec
            EnsureBuilt(rec)
            Focus(rec)
            SaveSoon()
            --a drop: private if it lands on the Director's Screen.
            DirectorScreen.ItemPlaced(g_sharing.ScreenKey(rec))
            if options.created ~= nil then
                options.created(mapid)
            end
        end,
        --a window shaped like its picture shows all of it: zoom to the
        --whole map once its window is the live one.
        done = function(mapid)
            if options.aspect == nil then
                return
            end
            local deadline = dmhub.Time() + 15
            dmhub.ScheduleWhen(function()
                return mod.unloaded or dmhub.Time() > deadline
                    or (rec ~= nil and Tabletop.LiveWindowId() == rec.id and game.currentMapId == mapid)
            end, function()
                --a frame for the window's viewport to reach the camera.
                dmhub.Schedule(0.1, function()
                    if mod.unloaded or rec == nil or Tabletop.LiveWindowId() ~= rec.id or game.currentMapId ~= mapid then
                        return
                    end
                    dmhub.FrameMapArea()
                end)
            end)
        end,
    })
end

--screenPos (optional) is where they land, in screen pixels; else the mouse.
local function TableFilesDropped(allPaths, screenPos)
    EndTableFileDrag()
    if not Tabletop.IsActive() or #allPaths == 0 then
        return
    end
    --where they were dropped; by the time the dialog is answered the mouse
    --is elsewhere.
    local mouse = screenPos or dmhub.mouseScreenPosition
    local mx, my = ScreenToLayer(mouse.x, mouse.y)

    --audio files become audio widgets there (Audio.lua) with no question;
    --documents (PDF, Markdown, text, .zip) go into the journal and their
    --main entry onto the table there (DocumentImport.lua); images and videos
    --go on to the scene-or-map dialog.
    local paths = {}
    local sounds = {}
    local documents = {}
    for _, path in ipairs(allPaths) do
        if FileDrops.IsAudio(path) then
            sounds[#sounds+1] = path
        elseif FileDrops.IsDocument(path) then
            documents[#documents+1] = path
        else
            paths[#paths+1] = path
        end
    end
    if #sounds > 0 and rawget(_G, "AudioDroppedOnTable") ~= nil then
        AudioDroppedOnTable(sounds, mouse.x, mouse.y)
    end
    if #documents > 0 and rawget(_G, "DocumentImport") ~= nil then
        DocumentImport.ImportFiles(documents, {
            ready = function(entryid, index)
                --several files step down-right from the drop point (the
                --documents block's DOC.cascade).
                local step = (index - 1) * 24
                Tabletop.OpenDocItem(entryid, {at = {x = mx + step, y = my + step}, placed = true})
            end,
        })
    end
    if not dmhub.isDM or #paths == 0 then
        return
    end
    --the Add Image / Add Video dialog: map, scene, or a picture on the table.
    TableDropDialog.Show(paths, mx, my)
end

--Owns the table's right-click menu. The engine keeps a popup open while its
--owner is hovered, and the table layer is hovered wherever the table shows,
--so a menu owned by it never closed on a click away. This 1px panel has no
--image, so it is never hovered.
local g_tableMenuAnchor = nil

--Right-click on the bare table: Paste (when the clipboard holds something
--the table takes), Add Character, and the Background submenu.
local function ShowTableMenu()
    if g_layer == nil or not g_layer.valid then
        return
    end
    if g_tableMenuAnchor == nil or not g_tableMenuAnchor.valid then
        g_tableMenuAnchor = gui.Panel{
            width = 1,
            height = 1,
            floating = true,
            interactable = false,
        }
        g_layer:AddChild(g_tableMenuAnchor)
        g_tableMenuAnchor.popupPositioning = "mouse"
    end
    local anchor = g_tableMenuAnchor
    local function Close()
        if anchor.valid then
            anchor.popup = nil
        end
    end

    --pastes and cards land where the menu was opened, not where the mouse
    --is when an entry is clicked.
    local mouse = dmhub.mouseScreenPosition
    local screenx, screeny = mouse.x, mouse.y
    local entries = {}

    --Paste: files copied in Explorer (as a drop of those files), else an
    --image (saved to a file, then the same as a dropped image file).
    local canAudio = false
    local audioBar = rawget(_G, "g_drawSteelAudioBar")
    if audioBar ~= nil and audioBar.CanControlAudio() then
        canAudio = true
    end
    local files = {}
    local images, videos, sounds = 0, 0, 0
    for _, path in ipairs(dmhub.GetClipboardFiles()) do
        if FileDrops.IsAudio(path) then
            if canAudio then
                files[#files+1] = path
                sounds = sounds + 1
            end
        elseif dmhub.isDM then
            local ext = FileDrops.Extension(path)
            for _, mediaExt in ipairs(FileDrops.MEDIA_EXTENSIONS) do
                if ext == mediaExt then
                    files[#files+1] = path
                    if FileDrops.IsVideo(path) then
                        videos = videos + 1
                    else
                        images = images + 1
                    end
                    break
                end
            end
        end
    end
    if #files > 0 then
        local text
        if #files == 1 then
            text = string.format('Paste "%s%s"', FileDrops.BaseName(files[1]), FileDrops.Extension(files[1]))
        else
            local parts = {}
            local function Part(n, one, many)
                if n == 1 then
                    parts[#parts+1] = "1 " .. one
                elseif n > 1 then
                    parts[#parts+1] = string.format("%d %s", n, many)
                end
            end
            Part(images, "image", "images")
            Part(videos, "video", "videos")
            Part(sounds, "sound", "sounds")
            text = "Paste " .. table.concat(parts, ", ")
        end
        entries[#entries+1] = {
            text = text,
            click = function()
                Close()
                TableFilesDropped(files, {x = screenx, y = screeny})
            end,
        }
    elseif dmhub.isDM and dmhub.HaveImageInClipboard() then
        local text = "Paste Image"
        local size = dmhub.GetClipboardImageSize()
        if size ~= nil then
            text = string.format("Paste Image (%d x %d)", size.width, size.height)
        end
        entries[#entries+1] = {
            text = text,
            click = function()
                Close()
                local path = dmhub.SaveClipboardImageToFile()
                if path == nil then
                    gui.ModalMessage{
                        title = "Could not paste",
                        message = "The image in the clipboard could not be read.",
                    }
                    return
                end
                TableFilesDropped({path}, {x = screenx, y = screeny})
            end,
        }
    end

    --Add Character: a card for a character this user controls; the
    --Director's list is the players' party, plus All Players.
    local charids = {}
    if dmhub.isDM then
        for _, charid in ipairs(dmhub.GetCharacterIdsInParty(GetDefaultPartyID()) or {}) do
            local tok = dmhub.GetCharacterById(charid)
            if tok ~= nil and not tok.despawned then
                charids[#charids+1] = charid
            end
        end
    else
        local seen = {}
        for partyid in unhidden_pairs(dmhub.GetTable(Party.tableName) or {}) do
            for _, charid in ipairs(dmhub.GetCharacterIdsInParty(partyid) or {}) do
                local tok = dmhub.GetCharacterById(charid)
                if not seen[charid] and tok ~= nil and not tok.despawned and tok.canControlAsUser then
                    seen[charid] = true
                    charids[#charids+1] = charid
                end
            end
        end
    end
    local names = {}
    for _, charid in ipairs(charids) do
        local tok = dmhub.GetCharacterById(charid)
        names[charid] = (tok ~= nil and tok.name) or "Character"
    end
    table.sort(charids, function(a, b)
        return string.lower(names[a]) < string.lower(names[b])
    end)
    --cards for several characters sit in a row centred where the menu opened.
    local function AddCards(ids)
        local cw = CardSize()
        local _, y = DropPlacement(screenx, screeny, 1)
        local x0 = math.floor(ScreenToLayer(screenx, screeny) - (#ids * cw + (#ids - 1) * CARD_GAP) / 2)
        for i, charid in ipairs(ids) do
            Tabletop.OpenCard(charid, {x = x0 + (i - 1) * (cw + CARD_GAP), y = y})
        end
    end
    local characterEntries = {}
    for _, charid in ipairs(charids) do
        local entry = GuardedEntry(names[charid], function()
            Close()
            AddCards({charid})
        end)
        --a character already on the table: picking it moves the card here.
        entry.check = (CardById(charid) ~= nil) or nil
        entry.group = "characters"
        characterEntries[#characterEntries+1] = entry
    end
    if dmhub.isDM and #charids > 1 then
        characterEntries[#characterEntries+1] = GuardedEntry("All Players", function()
            Close()
            AddCards(charids)
        end)
    end
    entries[#entries+1] = {
        text = "Add Character",
        submenu = cond(#characterEntries > 0, characterEntries, nil),
        disabled = #characterEntries == 0,
    }

    --Background: the built-in surfaces. Only the current one carries a check
    --(check = false would draw an empty box on every other row).
    local current = g_surfaceSetting:Get()
    local surfaceEntries = {}
    local function AddSurfaces(surfaces)
        for _, surface in ipairs(surfaces) do
            if TABLE_SURFACES.Offered(surface) then
                local id = surface.id
                local entry = GuardedEntry(surface.text, function()
                    Close()
                    g_surfaceSetting:Set(id)
                end)
                entry.check = (current == id) or nil
                surfaceEntries[#surfaceEntries+1] = entry
            end
        end
    end
    AddSurfaces(TABLE_SURFACES)
    entries[#entries+1] = {
        text = "Background",
        submenu = surfaceEntries,
    }

    local menu = gui.ContextMenu{
        entries = entries,
    }
    if menu == nil then
        return
    end
    --lifted off the table like its windows; submenus too.
    menu.selfStyle.boxShadow = TABLE_SHADOWS.rest
    for _, sub in ipairs(menu:GetChildrenWithClassRecursive("contextMenu")) do
        sub.selfStyle.boxShadow = TABLE_SHADOWS.rest
    end
    anchor.popup = menu
end

--The bottom layer of the GameHud: a maximized scene on show under the UI
--lives here, under the docks and the rest of the hud, and its think drives
--the tabletop. It is
--the table itself (a clear image, so it takes the right-click), and it
--never blocks the map's own input.
function Tabletop.CreateLayer()
    g_layer = gui.Panel{
        id = "tabletopLayer",
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        --not a blocker: a creature dropped on the bare table is a table drop
        --(the engine walks up from the panel hit to the first swallowPress
        --panel looking for one that blocks game interaction).
        blocksGameInteraction = false,
        swallowPress = true,
        rightClick = function(element)
            --a right-click on a table die opens the die's menu instead.
            if rawget(_G, "TableDice") ~= nil and TableDice.DieJustRightClicked() then
                return
            end
            ShowTableMenu()
        end,

        --a click on the bare table clears the selection; a drag there draws
        --the selection rectangle over the table cards (and the cards of a
        --scene that is the table's background). Over a maximized map the
        --map takes the mouse itself, so nothing starts there.
        draggable = true,
        dragMove = false,
        click = function(element)
            if not g_cs.AddingToSelection() then
                Tabletop.ClearCardSelection()
            end
        end,
        beginDrag = function(element)
            if dmhub.panelDropSurface ~= "table" then
                return
            end
            Tabletop.BeginCardMarquee(function()
                local targets = g_cs.TableCardTargets()
                for _, t in ipairs(SceneElements.CreatureCardTargets(true)) do
                    targets[#targets+1] = t
                end
                return targets
            end)
        end,
        dragging = function(element)
            Tabletop.DragCardMarquee()
        end,
        drag = function(element)
            Tabletop.EndCardMarquee()
        end,

        --files dragged in from the desktop (see TableFilesDropped): documents
        --for anyone, pictures and videos for the Director, audio for whoever
        --controls the audio.
        dragAndDropExtensions = (function()
            local exts = {}
            for _, ext in ipairs(FileDrops.DOCUMENT_EXTENSIONS) do
                exts[#exts+1] = ext
            end
            if dmhub.isDM then
                for _, ext in ipairs(FileDrops.MEDIA_EXTENSIONS) do
                    exts[#exts+1] = ext
                end
            end
            local audioBar = rawget(_G, "g_drawSteelAudioBar")
            if audioBar ~= nil and audioBar.CanControlAudio() then
                for _, ext in ipairs(FileDrops.AUDIO_EXTENSIONS) do
                    exts[#exts+1] = ext
                end
            end
            if #exts == 0 then
                return nil
            end
            return exts
        end)(),
        dragfilesenter = function(element, paths)
            BeginTableFileDrag(paths)
        end,
        dragfilesleave = function(element)
            EndTableFileDrag()
        end,
        dropfiles = function(element, paths)
            TableFilesDropped(paths)
        end,

        thinkTime = 0.05,
        think = function(element)
            Sync()
            g_cs.UpdateCardSelection()
        end,
        create = function(element)
            Sync()
        end,
        destroy = function(element)
            --the hud is going; its windows go with it and are rebuilt into
            --the next one.
            ReleaseMapStatus()
        end,
    }
    return g_layer
end

--The layer over the map windows and journals: minimized windows' floating
--buttons, and the collapse animation. GameHud puts it straight after the
--documents layer. It has no image, so the table under it stays clickable.
function Tabletop.CreateButtonLayer()
    g_buttonLayer = gui.Panel{
        id = "tabletopButtonLayer",
        styles = MapButtons.Styles(),
        width = "100%",
        height = "100%",
        interactable = false,
    }
    return g_buttonLayer
end

--The minimized-window button layer (nil before the hud builds it). Minimized
--journal windows put their buttons here too, to share the map buttons' look.
---@return Panel?
function Tabletop.ButtonLayer()
    return g_buttonLayer
end

--the buttons' hover fill and icon colors follow the theme.
ThemeEngine.OnThemeChanged(mod, function()
    if g_buttonLayer ~= nil and g_buttonLayer.valid then
        g_buttonLayer.styles = MapButtons.Styles()
        g_buttonLayer:UpdateStyle()
    end
end)

--Minimized windows docked on the icon rail ("mapwindow:<window id>" in the
--rail layout; see RailEntryTypes in DocumentSystem.lua). The docked button
--stays on the rail while its window is open, lit, like a panel's button.
RailEntryTypes = rawget(_G, "RailEntryTypes") or {}
RailEntryTypes.mapwindow = {
    available = function(id)
        return Tabletop.IsActive() and WindowById(id) ~= nil
    end,
    name = function(id)
        local rec = WindowById(id)
        if rec == nil then
            return "Map Window"
        end
        return MapName(rec.mapid)
    end,
    icon = function(id)
        return "phosphor/map-trifold.png"
    end,
    isActive = function(id)
        local rec = WindowById(id)
        return rec ~= nil and not rec.minimized
    end,
    --opens a minimized window; a window that is open but not the one in
    --use comes forward; the window in use collapses back onto the rail.
    activate = function(id, element)
        local rec = WindowById(id)
        if rec == nil then
            return
        end
        if rec.minimized then
            RestoreWindow(rec)
        elseif g_focusedId ~= rec.id then
            Focus(rec)
        else
            Minimize(rec)
        end
    end,
    hover = function(id, element)
        local rec = WindowById(id)
        if rec ~= nil then
            ShowPreviewTooltip(rec, element)
        end
    end,
    menu = function(id, element)
        local rec = WindowById(id)
        if rec == nil then
            return {}
        end
        return {
            GuardedEntry(cond(rec.minimized, "Restore", "Minimize"), function()
                element.popup = nil
                if rec.minimized then
                    RestoreWindow(rec)
                else
                    Minimize(rec)
                end
            end),
            GuardedEntry("Close Map Window", function()
                element.popup = nil
                RequestClose(rec)
            end),
        }
    end,
    --taken off the rail: a minimized window's button goes back on the
    --table, next to the rail it left.
    onRemove = function(id)
        local rec = WindowById(id)
        if rec == nil then
            return
        end
        if rec.minimized then
            local w = LayerSize()
            rec.iconX = math.min(rec.iconX or 80, w - 80)
            rec.iconY = rec.iconY or 120
        end
        UpdateTableButton(rec)
        SaveSoon()
    end,
}

--Right-click entries for a map row in the Maps panel.
function Tabletop.MapContextMenuEntries(mapid)
    if not Tabletop.IsActive() then
        return {}
    end
    return {
        {
            text = "Open in New Map Window",
            click = function()
                Tabletop.OpenMap(mapid, {newWindow = true})
            end,
        },
    }
end
