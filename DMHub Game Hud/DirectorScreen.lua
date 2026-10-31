local mod = dmhub.GetModLoading()

--The Director's Screen: a see-through dark band down the right side of the
--Director's table. What lies on it is the Director's alone: dragging an item
--onto it stops sharing it.
--
--Nothing is ever shared except by its share button (David, 2026-10-17): new
--items start unshared wherever they land, and dragging an item off the
--screen gives it back its share button without turning it on. On the screen
--an item is never shared and has no share button (a guarantee, David,
--2026-10-16).
--
--  - The items are the table items that can be shared: map windows (whose
--    share is the map's Player Viewable), scene windows, NPC cards and
--    journal items, and minimized map and scene windows' buttons, which
--    stand for their windows. Tabletop.ScreenItems lists them.
--  - An item is on the screen when its middle is. It joins or leaves the
--    screen when the Director drops it (DirectorScreen.ItemDropped from each
--    item's drag): onto the screen unshares it; off it leaves its share off.
--  - An item new on the table (a window, card or journal item opened any
--    way) is unshared. Lying on the open screen it joins it. One lying on
--    the screen that is already shared (a Player Viewable map's window) is
--    moved off it instead: opening a window never unshares a map.
--  - Something the Director drags onto the table (a map, scene, journal or
--    character row from a panel, a token out of its map, files from the
--    desktop) follows the drop's rule: dropped on the open screen it is
--    private (unshared even if it was shared); anywhere else its share is
--    left as it was (DirectorScreen.ItemPlaced).
--  - The items on the table when the layout loads keep their shares.
--  - Items on the screen are stuck to its edge (Venla, 2026-10-17): when the
--    edge moves (a resize, or opening and closing it) they move with it by
--    the same amount, even off the table's right side, like the art on it.
--    Each one's distance from the edge is saved with the layout, so a reload
--    puts it back where the screen carried it.
--  - A map or scene window dropped on the screen shrinks to a card (Venla,
--    2026-10-17): its picture and name at a fixed size. Double-click it or
--    its hover button to expand it there, still private; minimizing it again
--    makes the card. Dragged off the screen, a card grows back into its
--    window at full size where it was dropped, still unshared.
--  - Resizing the screen never shares or unshares: items on it go along with
--    the edge (above), and items on the table are pushed off it as it
--    widens. One that cannot get off (the screen is the whole table) goes
--    behind it, unshared.
--  - Nothing on it is ever shared: an item on it that gets shared some other
--    way (Map Settings) is moved off it.
--  - The screen resizes from its left edge or its tab, from the full width of
--    the table down to just the tab in the bottom-right corner; let go near
--    the right side and it slides shut. A click on the tab slides it open or
--    shut (Venla, 2026-10-18). Closed, the items on it are hidden (stowed), and
--    focusing a stowed map window opens the screen again (Reveal).
--  - Its size and its items are saved with the table layout (per user, per
--    game). Players have no screen.
--  - While a maximized map or scene window covers the table, the screen is
--    gone, as if closed: its band and tab are hidden, so are the items on it,
--    and nothing new can join it (David, 2026-10-16). Maximizing never changes a
--    window's share, and the maximized window keeps its share button even if
--    it came from the screen; shared that way, it leaves the screen, and is
--    moved off it when restored.
--
--  - The screen is always over everything on the table (Venla, 2026-10-17):
--    a window or card on the table that reaches onto it goes under it, and
--    only the items on the screen lie on top. The band lives in the
--    documents layer, among the windows, and KeepOnTop keeps their order:
--    the table's items (with the journal windows and table items, which
--    stack with them by focus), the screen, the icon rails, the screen's own
--    items, then any dialog. A
--    minimized button on the table (on the button layer, over every window)
--    cannot go under it, so it is nudged off the screen instead.
--
--GameHud mounts two layers: the band's (CreateLayer; the band itself is
--moved into the documents layer, see KeepOnTop), and the tab and the drop
--hint over the windows (CreateTabLayer). Neither takes the
--mouse except at the edge grip and the tab, so the table, the maps and the
--windows under the band work as before.

--- @class DirectorScreenModule
DirectorScreen = {}

--One table item, as the screen sees it (Tabletop.ScreenItems makes these).
--- @class DirectorScreenItem
--- @field key string unique among the items ("map:<window id>", "card:<charid>"...)
--- @field rect nil|{x: number, y: number, w: number, h: number} where it lies on the table (documents-layer units); nil when it has no spot (maximized, docked on a rail)
--- @field move fun(x: number, free?: boolean) moves it so its left edge is at x (kept on the table, unless free)
--- @field store TabletopShareStore its share
--- @field changed fun() call after its share was changed here
--- @field stow fun(stowed: boolean) hides it (the screen is closed) or shows it
--- @field panel fun(): Panel|nil what the Director sees of it on the table
--- @field shareButton fun(): Panel|nil its share button (hidden while it is on the screen)
--- @field showBehind fun(behind: boolean) whether it lies behind the screen (hides its grey not-shared frame)
--- @field maximized nil|boolean a maximized window (keeps its share button)
--- @field card nil|boolean a window shrunk to a card (see Tabletop's g_card)
--- @field onButtonLayer nil|boolean a minimized window's button or card, drawn over every window (KeepOnTop cannot put it under the screen)
--- @field shrink nil|fun(x: number, y: number) shrinks a map or scene window (or its button) to a card at (x, y)
--- @field grow nil|fun(x: number, y: number) grows a card back into its window at (x, y); nothing for anything else

--Sizes in documents-layer units (the table is ~1048 high).
local TAB_WIDTH = 14
local TAB_HEIGHT = 64
--between the tab and the bottom of the table.
local TAB_BOTTOM = 18
--the tab's grab area reaches this far past what is drawn, all round, so it
--is easy to hit (Venla, 2026-10-19).
local TAB_SLOP = 10
local GRIP_WIDTH = 16
--narrower than this past the right rail, the screen closes to its tab.
local MIN_OPEN = 90
--an edge dragged closer than this to the table's left side snaps all the way
--to it: the grab offset otherwise keeps it a few units short of full width.
local SNAP_FULL = 40
--how much of the table a screen opened for the first time takes.
local DEFAULT_FRACTION = 0.22
--the widest the screen gets, as a fraction of the table: all of it
--(Venla, 2026-10-19; a 0.7 cap that kept a players' side was dropped).
local MAX_FRACTION = 1
--the old cap; a saved size of exactly this is read as full width (Load).
local STALE_CAP = 0.7
--let go of the edge closer than this (past the rail) to the table's right
--side and the screen slides shut.
local SNAP_CLOSE = 200
--how long opening or closing the screen slides.
local SLIDE_SECONDS = 0.22
--after the Director moves an item across the edge, its share takes a moment
--to come back from the server; meanwhile the item is not moved off the screen.
local GRACE_SECONDS = 2.5
--how long a drop waits for the item it makes (a bestiary creature's card
--waits for the new character; a file's map waits for its import).
local PLACED_SECONDS = 60
--a click that moved the tab less than this is a click, not a resize.
local CLICK_SLOP = 4

--Covers: art shown on the screen, under its items. The art fills the screen's
--height and is cropped to its width (never stretched). It sticks to the
--screen's moving edge: `left` is the spot on the art (0..1) that the edge
--always shows, so the art travels with the edge and a wider screen shows more
--of it to the right. `veil` is the grey laid over the art to mix it into the
--band (the engine ignores alpha on image art, so it is veiled, not faded).
--Tune the veil's alpha by eye: this layer's blending is steep, e0 barely
--shows and f8 nearly hides the art. `tint` colors the art. A cover with no
--image is the plain band.
--More covers just add rows; choosing between them is still to come
--(2026-10-16, a test).
--- @class DirectorScreenCover
--- @field id string
--- @field image nil|string the bgimage id
--- @field width nil|number the image's size in pixels
--- @field height nil|number
--- @field left nil|number
--- @field tint nil|string
--- @field veil nil|string
local COVERS = {
    {id = "plain"},
    {id = "vasloria", image = "e83e6ea1-6212-4baf-8f26-a11bf7b85c6e", width = 2000, height = 633, left = 0, tint = "#ffffffff", veil = "#16171bf2"},
}
local COVER_ID = "vasloria"

--- @return DirectorScreenCover
local function CurrentCover()
    for _, cover in ipairs(COVERS) do
        if cover.id == COVER_ID then
            return cover
        end
    end
    return COVERS[1]
end

--The part of the cover's art a w x h screen shows: full height, cropped to the
--screen's shape, with its left edge at cover.left (pulled back once a wide
--screen would run off the art's right end).
--- @param cover DirectorScreenCover
--- @param w number
--- @param h number
--- @return {x1: number, y1: number, x2: number, y2: number}
local function CoverRect(cover, w, h)
    local frac = math.min(1, (w / h) / (cover.width / cover.height))
    local x1 = math.min(1 - frac, math.max(0, cover.left or 0))
    return {x1 = x1, y1 = 0, x2 = x1 + frac, y2 = 1}
end

--fraction: of the table's width; 0 while closed.
--lastFraction: the size it opens to from the tab.
--members: key -> true for the items on the screen.
--looked: whether a look has run since the layout loaded (the first one puts
--the screen's items back where it carried them).
--offsets: key -> how far right of the edge each item on the screen lies (its
--left edge minus the screen's), so it can follow the edge (FollowEdge).
--lastEdge: the edge FollowEdge last saw; nil until the first layout.
--pushed: key -> true for a shared item the last look moved off the screen
--(if it is still on it, it cannot get off).
--grace: key -> time until which the item is left alone (GRACE_SECONDS).
--placed: key -> time until which a drop's item is awaited (ItemPlaced).
--drag: {key, centre, seen} while the Director drags an item; key is nil and
--fresh is true for something new dragged from a panel (NewItemDragging).
--resize: {offset, startX, moved, before} while the edge or the tab is dragged.
--slide: {from, to, start} while the screen slides open or shut (SlideTo).
--preview: {key, mode, overlay} while a dragged item shows what dropping it
--would do (SetPreview).
--passUntil: while a drag reports in (ItemDragging, NewItemDragging), the
--grip and the tab let the mouse through until this time (LetDragsThrough).
local g = {
    fraction = DEFAULT_FRACTION,
    lastFraction = DEFAULT_FRACTION,
    members = {},
    offsets = {},
    lastEdge = nil,
    looked = false,
    pushed = {},
    grace = {},
    placed = {},
    drag = nil,
    resize = nil,
    slide = nil,
    preview = nil,
    passUntil = 0,
    passing = false,
    nextLook = 0,
    layer = nil,
    band = nil,
    grip = nil,
    cover = nil,
    coverVeil = nil,
    tabLayer = nil,
    tab = nil,
    tabFace = nil,
    hint = nil,
    hintLabel = nil,
    signature = nil,
}

local function Active()
    return dmhub.isDM and Tabletop.IsActive() and Tabletop.LayerReady()
end

local function IsOpen()
    return g.fraction > 0
end

--Whether a maximized window covers the table: the screen is then gone.
local function Hidden()
    return Tabletop.TableCovered()
end

--Open and not hidden: the screen is there, and works.
local function Shown()
    return IsOpen() and not Hidden()
end

--The table's size, in documents-layer units.
local function TableSize()
    local rect = Tabletop.LayerRect()
    return rect.w, rect.h
end

--How far in from the right the right icon rail reaches: 0 with no rail, or
--when the rail is empty, so the closed tab sits flush to the table's edge
--(Venla, 2026-10-19).
local function RailReserve()
    local occupied = rawget(_G, "RailSideOccupied")
    if occupied ~= nil and not occupied("right") then
        return 0
    end
    local fn = rawget(_G, "RailRightColumnWidth")
    if fn == nil then
        return 0
    end
    return fn() or 0
end

--The x of the screen's left edge: the table's width while it is closed.
--Fully open it reaches the table's left side (Venla, 2026-10-19).
local function Edge()
    local w = TableSize()
    if not IsOpen() then
        return w
    end
    return math.floor(w * (1 - g.fraction))
end

local function Centre(rect)
    return rect.x + rect.w / 2
end

--Whether an item lying at rect is on the screen (never while it is gone).
local function OnScreen(rect)
    return Shown() and rect ~= nil and Centre(rect) >= Edge()
end

--The mouse, in documents-layer units.
local function MouseOnTable()
    local m = dmhub.mouseScreenPosition
    local screen = dmhub.screenDimensions
    local below = dmhub.screenDimensionsBelowTitlebar
    local _, h = TableSize()
    if below.y <= 0 then
        return m.x, m.y
    end
    local scale = h / below.y
    return m.x * scale, (m.y - (screen.y - below.y)) * scale
end

local function FindItem(key)
    for _, item in ipairs(Tabletop.ScreenItems()) do
        if item.key == key then
            return item
        end
    end
    return nil
end

----------------------------------------------------------------------
--Drawing the band and the tab.

local g_styles = {
    {
        selectors = {"directorScreenBand"},
        --a soft shadow cast leftwards onto the table, so the screen reads as
        --standing above it. On the band, not the divider: the band clips its
        --children, so a shadow on the divider never reaches the table. Full
        --alpha on purpose: like the cover veil, lower alphas barely show here.
        boxShadow = {x = -10, blur = 48, color = "#000000ff"},
        bgcolor = "#16171bcc",
    },
    {
        selectors = {"directorScreenBand", "dropTarget"},
        bgcolor = "#202127dd",
    },
    {
        selectors = {"directorScreenEdge"},
        bgcolor = "@bg",
    },
    {
        selectors = {"directorScreenEdge", "lit"},
        bgcolor = "@bgRaised",
    },
    {
        selectors = {"directorScreenEdge", "dropTarget"},
        bgcolor = "#ffffffa0",
    },
    {
        selectors = {"directorScreenCaption"},
        color = "#ffffff70",
        fontSize = 13,
        bold = true,
        uppercase = true,
        width = "auto",
        height = "auto",
    },
    {
        selectors = {"directorScreenTab"},
        bgcolor = "clear",
    },
    {
        selectors = {"directorScreenTabFace"},
        bgcolor = "@bg",
        --rounded on the left only: its right side runs into the divider.
        cornerRadius = {x1 = 6, y1 = 0, x2 = 0, y2 = 6},
    },
    {
        selectors = {"directorScreenTabFace", "lit"},
        bgcolor = "@bgRaised",
    },
    {
        --flipped: the screen is at full width, so the tab lies on the screen
        --against its edge, rounded on the right (Venla, 2026-10-19).
        selectors = {"directorScreenTabFace", "flipped"},
        cornerRadius = {x1 = 0, y1 = 6, x2 = 6, y2 = 0},
    },
    {
        selectors = {"directorScreenTabX"},
        bgcolor = "#ffffff90",
        hidden = 1,
    },
    {
        selectors = {"directorScreenTabX", "parent:flipped"},
        hidden = 0,
    },
    {
        selectors = {"directorScreenTabX", "parent:lit"},
        bgcolor = "#ffffffff",
    },
    {
        selectors = {"directorScreenHint"},
        bgcolor = "#121316ee",
        borderColor = "#ffffff40",
    },
    {
        selectors = {"directorScreenHintLabel"},
        color = "#ffffffe0",
        fontSize = 14,
        width = "auto",
        height = "auto",
    },
}

--Puts the band, its edge and the tab where the screen's size says. Cheap
--when nothing changed (the table resizing changes it too).
--Moves the items on the screen along with its edge: each keeps its distance
--from it (g.offsets), even past the table's right side. Cheap when the edge
--has not moved.
--- @param edge number
local function FollowEdge(edge)
    local last = g.lastEdge
    g.lastEdge = edge
    if last == nil or last == edge or next(g.offsets) == nil then
        return
    end
    for _, item in ipairs(Tabletop.ScreenItems()) do
        local offset = g.offsets[item.key]
        if offset ~= nil and g.members[item.key] and item.rect ~= nil then
            item.move(edge + offset, true)
        end
    end
end

local function Layout(force)
    local band = g.band
    local tab = g.tab
    local face = g.tabFace
    if band == nil or not band.valid or tab == nil or not tab.valid or face == nil or not face.valid then
        return
    end
    local active = Active()
    local hidden = active and Hidden()
    local w, h = TableSize()
    local edge = Edge()
    local reserve = RailReserve()
    --IsOpen is in it: the last frames of a slide shut leave the edge at the
    --table's side while still open, so the edge alone missed the close and
    --the band (and its shadow) stayed up.
    local signature = string.format("%s|%s|%s|%d|%d|%d|%d", tostring(active), tostring(hidden), tostring(IsOpen()), math.floor(w), math.floor(h), math.floor(edge), math.floor(reserve))
    if signature == g.signature and not force then
        return
    end
    g.signature = signature

    --a maximized window covering the table hides the band and the tab too.
    band:SetClass("collapsed", not active or hidden or not IsOpen())
    tab:SetClass("collapsed", not active or hidden)
    face:SetClass("collapsed", not active or hidden)
    if not active or hidden then
        return
    end
    band.x = edge
    band.selfStyle.width = math.max(1, w - edge)
    FollowEdge(edge)

    local cover = g.cover
    if cover ~= nil and cover.valid then
        local art = CurrentCover()
        cover:SetClass("collapsed", art.image == nil)
        local veil = g.coverVeil
        if veil ~= nil and veil.valid then
            veil.selfStyle.bgcolor = art.veil or "clear"
        end
        if art.image ~= nil and w - edge >= 1 and h >= 1 then
            cover.bgimage = art.image
            cover.selfStyle.bgcolor = art.tint or "#ffffffff"
            cover.selfStyle.imageRect = CoverRect(art, w - edge, h)
        end
    end

    --the tab hangs off the screen's edge, and never under the right rail.
    local right = math.min(edge, w - reserve)
    --no room to hang off the edge (full width): it flips onto the screen and
    --shows an X.
    local flipped = IsOpen() and right < TAB_WIDTH
    face:SetClass("flipped", flipped)
    if flipped then
        right = right + TAB_WIDTH
    end
    face.x = math.max(0, right - TAB_WIDTH)
    face.y = math.max(0, h - TAB_BOTTOM - TAB_HEIGHT)
    tab.x = face.x - TAB_SLOP
    tab.y = face.y - TAB_SLOP
end

local function SetFraction(fraction)
    g.fraction = math.max(0, math.min(MAX_FRACTION, fraction))
    Layout()
end

--Slides the screen to a size (0 closes it): Slide, each frame, moves it
--along; the items on it ride along with the edge (FollowEdge).
--- @param fraction number
local function SlideTo(fraction)
    fraction = math.max(0, math.min(MAX_FRACTION, fraction))
    if fraction == g.fraction then
        g.slide = nil
        return
    end
    g.slide = {from = g.fraction, to = fraction, start = dmhub.Time()}
end

--Moves a slide on (ease out cubic); the tab layer's think calls it.
local function Slide()
    local slide = g.slide
    if slide == nil then
        return
    end
    local t = math.min(1, (dmhub.Time() - slide.start) / SLIDE_SECONDS)
    local e = 1 - (1 - t) ^ 3
    SetFraction(slide.from + (slide.to - slide.from) * e)
    if t >= 1 then
        g.slide = nil
        SetFraction(slide.to)
        Tabletop.SaveLayoutSoon()
    end
end

--Where the screen is going: a slide's end, or where it is.
local function Target()
    if g.slide ~= nil then
        return g.slide.to
    end
    return g.fraction
end

--Opens the screen to the size it last had.
local function Open()
    if Target() > 0 then
        return
    end
    SlideTo(g.lastFraction or DEFAULT_FRACTION)
end

local function Close()
    if Target() == 0 then
        return
    end
    if g.slide == nil then
        g.lastFraction = g.fraction
    end
    SlideTo(0)
end

--The edge and the tab resize the screen: the edge follows the mouse. Below
--MIN_OPEN past the rail it shows closed, and is closed on release.
local function BeginResize()
    --a drag takes over from a slide.
    if g.slide ~= nil then
        SetFraction(g.slide.to)
        g.slide = nil
    end
    local mx = MouseOnTable()
    local w = TableSize()
    --closed, the edge is where the tab is drawn, so a pull starts from there.
    local edge = math.min(Edge(), w - RailReserve())
    --before: the size to open to again if this drag ends by snapping shut.
    local before = g.lastFraction or DEFAULT_FRACTION
    if IsOpen() then
        before = g.fraction
    end
    g.resize = {offset = edge - mx, startX = mx, moved = false, before = before}
end

local function Resizing()
    local resize = g.resize
    if resize == nil then
        return
    end
    local mx = MouseOnTable()
    if math.abs(mx - resize.startX) > CLICK_SLOP then
        resize.moved = true
    end
    if not resize.moved then
        return
    end
    local w = TableSize()
    local edge = math.max(0, math.min(w, mx + resize.offset))
    if edge < SNAP_FULL then
        edge = 0
    end
    local width = w - edge
    if width < RailReserve() + MIN_OPEN then
        SetFraction(0)
    else
        SetFraction(width / w)
    end
end

local function EndResize()
    local resize = g.resize
    g.resize = nil
    if resize == nil or not resize.moved then
        return false
    end
    local w = TableSize()
    if IsOpen() and w * g.fraction < RailReserve() + SNAP_CLOSE then
        --let go near the right side: it slides shut, and opens again to the
        --size it had before this drag.
        g.lastFraction = resize.before
        SlideTo(0)
    elseif IsOpen() then
        g.lastFraction = g.fraction
    end
    Tabletop.SaveLayoutSoon()
    return true
end

--The tab's click: open or shut.
local function Toggle()
    if Target() > 0 then
        Close()
    else
        Open()
    end
end

--The drag events the edge and the tab share. dragMove is off, so the panel
--stays put and Layout moves it.
--onTab: a press that wobbles past the engine's drag threshold without moving
--sideways counts as a click. The engine starts a drag after a few pixels in
--any direction and then swallows the click, so without this a slightly
--sloppy click on the tab did nothing.
local function ResizeEvents(args, onTab)
    args.draggable = true
    args.dragMove = false
    args.beginDrag = function(element)
        BeginResize()
    end
    args.dragging = function(element)
        Resizing()
    end
    args.drag = function(element)
        if not EndResize() and onTab then
            Toggle()
        end
    end
    return args
end

--The divider and the tab are one handle: hovering either lights both.
--- @param lit boolean
local function SetLit(lit)
    local band = g.band
    if band ~= nil and band.valid then
        for _, child in ipairs(band.children) do
            if child:HasClass("directorScreenEdge") then
                child:SetClass("lit", lit)
            end
        end
    end
    local face = g.tabFace
    if face ~= nil and face.valid then
        face:SetClass("lit", lit)
    end
end

--Builds the band: its art, its edge and grip, and its caption. KeepOnTop
--adds it straight into the documents layer, among the windows, so it can lie
--over the shared ones. Only its edge takes the mouse.
--- @return Panel
local function BuildBand()
    --the band's grey over the art, so the art only partly shows through. It is
    --the art's child: a sibling drawn after it still ends up under the image.
    g.coverVeil = gui.Panel{
        floating = true,
        halign = "left",
        valign = "top",
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        interactable = false,
    }
    --the cover's art, under everything else on the band (Layout crops it).
    g.cover = gui.Panel{
        classes = {"collapsed"},
        floating = true,
        halign = "left",
        valign = "top",
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        interactable = false,
        children = {g.coverVeil},
    }
    --the band carries its own styles: it lives in the documents layer
    --(KeepOnTop), away from the layer that would otherwise style it.
    g.band = gui.Panel{
        classes = {"directorScreenBand", "collapsed"},
        styles = ThemeEngine.MergeTokens(g_styles),
        floating = true,
        halign = "left",
        valign = "top",
        width = 1,
        height = "100%",
        bgimage = "panels/square.png",
        interactable = false,
        flow = "none",
        children = {
            g.cover,
            --the edge: a thin line, with a wider grip over it.
            gui.Panel{
                classes = {"directorScreenEdge"},
                floating = true,
                halign = "left",
                valign = "top",
                width = 2,
                height = "100%",
                bgimage = "panels/square.png",
                interactable = false,
            },
            gui.Panel(ResizeEvents{
                classes = {"directorScreenGrip"},
                create = function(element)
                    g.grip = element
                    element.interactable = not g.passing
                end,
                floating = true,
                halign = "left",
                valign = "top",
                x = -GRIP_WIDTH / 2,
                width = GRIP_WIDTH,
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = "clear",
                swallowPress = true,
                hoverCursor = "horizontal-expand",
                hover = function(element)
                    SetLit(true)
                end,
                dehover = function(element)
                    SetLit(false)
                end,
            }),
            gui.Panel{
                floating = true,
                halign = "left",
                valign = "top",
                x = 18,
                y = 14,
                width = "auto",
                height = "auto",
                flow = "horizontal",
                interactable = false,
                children = {
                    gui.Panel{
                        bgimage = "phosphor/eye-slash.png",
                        bgcolor = "#ffffff70",
                        width = 16,
                        height = 16,
                        valign = "center",
                        rmargin = 6,
                        interactable = false,
                    },
                    gui.Label{
                        classes = {"directorScreenCaption"},
                        text = "Director's Screen",
                        valign = "center",
                        interactable = false,
                    },
                    --add dice behind the screen (TableDice.lua).
                    rawget(_G, "TableDice") ~= nil and TableDice.CreateScreenButton() or nil,
                },
            },
        },
    }
    return g.band
end

--- The screen's own layer, under the documents layer. The band is not in it
--- (see BuildBand); it holds the styles for nothing but keeps GameHud's
--- layer order as it was.
--- @return Panel
function DirectorScreen.CreateLayer()
    g.signature = nil
    g.band = nil
    g.layer = gui.Panel{
        id = "directorScreenLayer",
        styles = ThemeEngine.MergeTokens(g_styles),
        width = "100%",
        height = "100%",
        flow = "none",
        interactable = false,
        create = function(element)
            Layout(true)
        end,
    }
    return g.layer
end

--- The tab and the drop hint, over the windows: GameHud puts it straight
--- after the tabletop's button layer. Only the tab takes the mouse.
--- @return Panel
function DirectorScreen.CreateTabLayer()
    g.signature = nil
    --The tab is two panels. The engine never moves the panel being dragged
    --(SheetPanel skips its position while it is _draggingPanel), so a tab
    --grabbed and dragged would stay behind until released. The grab area
    --(g.tab) is invisible; what is seen is g.tabFace, which takes no mouse,
    --is never dragged, and so follows the edge as Layout moves it.
    g.tabFace = gui.Panel{
        classes = {"directorScreenTabFace", "collapsed"},
        halign = "left",
        valign = "top",
        width = TAB_WIDTH,
        height = TAB_HEIGHT,
        bgimage = "panels/square.png",
        interactable = false,
        flow = "none",
        children = {
            --shown while the tab is flipped (Layout): a click there shuts
            --the screen.
            gui.Panel{
                classes = {"directorScreenTabX"},
                bgimage = "phosphor/x-bold.png",
                halign = "center",
                valign = "center",
                width = 10,
                height = 10,
                interactable = false,
            },
        },
    }
    --the grab area is bigger than the face by TAB_SLOP all round (Layout).
    g.tab = gui.Panel(ResizeEvents({
        classes = {"directorScreenTab", "collapsed"},
        halign = "left",
        valign = "top",
        width = TAB_WIDTH + TAB_SLOP * 2,
        height = TAB_HEIGHT + TAB_SLOP * 2,
        bgimage = "panels/square.png",
        swallowPress = true,
        hoverCursor = "horizontal-expand",
        flow = "none",
        create = function(element)
            element.interactable = not g.passing
        end,
        hover = function(element)
            SetLit(true)
        end,
        dehover = function(element)
            SetLit(false)
        end,
        click = function(element)
            Toggle()
        end,
    }, true))
    g.hintLabel = gui.Label{
        classes = {"directorScreenHintLabel"},
        text = "",
        interactable = false,
    }
    g.hint = gui.Panel{
        classes = {"directorScreenHint", "collapsed"},
        halign = "left",
        valign = "top",
        width = "auto",
        height = "auto",
        hpad = 10,
        vpad = 6,
        bgimage = "panels/square.png",
        borderWidth = 1,
        cornerRadius = 6,
        flow = "horizontal",
        interactable = false,
        children = {
            gui.Panel{
                classes = {"directorScreenHintIcon"},
                bgimage = "phosphor/eye-slash.png",
                bgcolor = "#ffffffe0",
                width = 16,
                height = 16,
                valign = "center",
                rmargin = 8,
                interactable = false,
            },
            g.hintLabel,
        },
    }
    g.tabLayer = gui.Panel{
        id = "directorScreenTabLayer",
        styles = ThemeEngine.MergeTokens(g_styles),
        width = "100%",
        height = "100%",
        flow = "none",
        interactable = false,
        children = {g.tabFace, g.tab, g.hint},
        create = function(element)
            Layout(true)
        end,
        --every frame: a slide in progress moves on (Slide).
        thinkTime = 0.01,
        think = function(element)
            Slide()
        end,
    }
    return g.tabLayer
end

--While the Director drags an item: the band lights when the drop would put
--it behind the screen, and a note by the mouse says so. Coming off the
--screen shares nothing, so it has no note.
----------------------------------------------------------------------
--What a drag will do, and what a drop did (Venla, 2026-10-17). While an item
--is dragged onto the screen it shows its fate, darkened (going behind the
--screen). The look stops the moment it is released; a line saying what
--happened then shows on it for a moment and fades. Both are a panel laid
--over the item's own panel (a child, so it moves with it).

--how long a drop's flash holds before it fades, and how long the fade takes.
local FLASH_HOLD = 0.6
local FLASH_FADE = 0.5

--A panel to lay over an item's panel: darkened, with a pale outline so it
--still reads on a dark map. label: a line in its middle, or nil. bare: no
--darkening, just the label (a drop's flash: the darkening stops on release).
--- @param label nil|string
--- @param think nil|fun(element: Panel)
--- @param bare nil|boolean
--- @return Panel
local function Overlay(label, think, bare)
    local children = {}
    if label ~= nil then
        children[1] = gui.Label{
            text = label,
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            hpad = 12,
            vpad = 6,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = "#101114f8",
            cornerRadius = 6,
            fontSize = 16,
            bold = true,
            color = "#ffffffe0",
            interactable = false,
        }
    end
    return gui.Panel{
        floating = true,
        halign = "left",
        valign = "top",
        width = "100%",
        height = "100%",
        flow = "none",
        bgimage = "panels/square.png",
        bgcolor = cond(bare, "clear", "#08090cc8"),
        borderWidth = cond(bare, 0, 2),
        borderColor = "#ffffff40",
        interactable = false,
        thinkTime = cond(think ~= nil, 0.05, nil),
        think = think,
        children = children,
    }
end

--Ends the drag's preview (g.preview), if one is showing.
local function ClearPreview()
    local preview = g.preview
    g.preview = nil
    if preview ~= nil and preview.overlay.valid then
        preview.overlay:DestroySelf()
    end
end

--Darkens the dragged item while dropping it now would put it behind the
--screen; nil for nothing.
--- @param key nil|string
local function SetPreview(key)
    local preview = g.preview
    if preview ~= nil and preview.key == key and preview.overlay.valid then
        return
    end
    ClearPreview()
    if key == nil then
        return
    end
    local item = FindItem(key)
    local panel = nil
    if item ~= nil then
        panel = item.panel()
    end
    if panel == nil or not panel.valid then
        return
    end
    local overlay = Overlay(nil, nil)
    panel:AddChild(overlay)
    g.preview = {key = key, overlay = overlay}
end

--Says on an item dropped behind the screen that it is hidden, in a line
--that fades out.
--- @param item DirectorScreenItem
local function Flash(item)
    local panel = item.panel()
    if panel == nil or not panel.valid then
        return
    end
    local start = dmhub.Time()
    local fading = false
    local overlay = Overlay("Hidden from the players", function(element)
        local t = dmhub.Time() - start
        if t > FLASH_HOLD + FLASH_FADE + 0.1 then
            element:DestroySelf()
        elseif t > FLASH_HOLD and not fading then
            fading = true
            element.selfStyle.transitionTime = FLASH_FADE
            element.selfStyle.groupOpacity = 0
        end
    end, true)
    panel:AddChild(overlay)
end

local function UpdateDropHint()
    local hint = g.hint
    if hint == nil or not hint.valid then
        return
    end
    local drag = g.drag
    local text = nil
    --only a drop onto the open screen does anything to a share.
    if drag ~= nil and Active() and Shown() and drag.centre >= Edge() then
        local member = drag.key ~= nil and g.members[drag.key] == true
        if drag.fresh then
            text = "Release to keep it behind the screen"
        elseif not member then
            if drag.shared then
                text = "Release to hide it from the players"
            else
                text = "Release to keep it behind the screen"
            end
        end
    end

    --the dragged item itself shows its fate (not something new from a panel:
    --it has no item yet).
    local previewKey = nil
    if drag ~= nil and not drag.fresh and text ~= nil then
        previewKey = drag.key
    end
    SetPreview(previewKey)

    local band = g.band
    if band ~= nil and band.valid then
        band:SetClass("dropTarget", text ~= nil)
        for _, child in ipairs(band.children) do
            if child:HasClass("directorScreenEdge") then
                child:SetClass("dropTarget", text ~= nil)
            end
        end
    end

    hint:SetClass("collapsed", text == nil)
    if text == nil then
        return
    end
    if g.hintLabel ~= nil and g.hintLabel.valid then
        g.hintLabel.text = text
    end
    local mx, my = MouseOnTable()
    local w, h = TableSize()
    hint.x = math.max(0, math.min(mx + 22, w - 320))
    hint.y = math.max(0, math.min(my + 26, h - 40))
end

--The grip and the tab catch the mouse, so to the engine a drag over them is
--over UI, not the table: a map row's window preview (or a card's) would drop
--back to the row while crossing the edge. Any drag reporting in makes them
--let the mouse through until a moment after the last report.
--- @param passing boolean
local function SetPassing(passing)
    if passing == g.passing then
        return
    end
    g.passing = passing
    for _, panel in ipairs({g.grip, g.tab}) do
        if panel ~= nil and panel.valid then
            panel.interactable = not passing
        end
    end
end

local function LetDragsThrough()
    g.passUntil = dmhub.Time() + 0.3
    SetPassing(true)
end

----------------------------------------------------------------------
--The items.

--Snapping (Venla, 2026-10-19): an item dragged on the screen close to
--another item on it jumps into line with it, a neat gap beside, above or
--below it with their edges lined up. Live, through the engine's dragSnap.
--Only on the open screen; the players' side is left free.
--wider than Tabletop's SNAP (14), so a window's own edge snap on release
--(SnapWindow) does not pull it flush against its neighbour.
local SNAP_GAP = 16
--how close (in either direction) a spot must be for the item to jump to it.
local SNAP_DISTANCE = 28

--Where an item of size w x h at (x, y) snaps to on the screen, or nil.
--- @param key string the dragged item (never snapped to itself)
--- @return number|nil x
--- @return number|nil y
local function SnapSpot(key, x, y, w, h)
    if not Shown() or not OnScreen({x = x, y = y, w = w, h = h}) then
        return nil, nil
    end
    local best = SNAP_DISTANCE
    local bestX, bestY = nil, nil
    for _, other in ipairs(Tabletop.ScreenItems()) do
        local o = other.rect
        if other.key ~= key and g.members[other.key] and o ~= nil then
            local spots = {
                {o.x + o.w + SNAP_GAP, o.y},
                {o.x - w - SNAP_GAP, o.y},
                {o.x, o.y + o.h + SNAP_GAP},
                {o.x, o.y - h - SNAP_GAP},
            }
            for _, spot in ipairs(spots) do
                local d = math.max(math.abs(spot[1] - x), math.abs(spot[2] - y))
                if d < best then
                    best = d
                    bestX, bestY = spot[1], spot[2]
                end
            end
        end
    end
    return bestX, bestY
end

--Sets the engine's dragSnap. An engine older than it reads it as nil (and
--would log an error on every write), so snapping is then left off.
--- @param element Panel
--- @param offset nil|{x: number, y: number}
local function SetDragSnap(element, offset)
    if element.dragSnap == nil then
        return
    end
    element.dragSnap = offset
end

--Snaps the panel being dragged (or lets it follow the mouse again).
--- @param key string
--- @param element Panel
local function SnapDrag(key, element)
    local item = FindItem(key)
    local x, y = element.xdrag, element.ydrag
    local snapX, snapY = nil, nil
    if item ~= nil and item.rect ~= nil then
        snapX, snapY = SnapSpot(key, x, y, item.rect.w, item.rect.h)
    end
    if snapX ~= nil and snapY ~= nil then
        SetDragSnap(element, {x = snapX - x, y = snapY - y})
    else
        SetDragSnap(element, nil)
    end
end

--- Called from an item's dragging event each frame: x is where its left
--- edge would land and width its width (documents-layer units). A nil key
--- (the drag is going somewhere other than the table) clears the hint.
--- element, the panel being dragged, lets the item snap into line with
--- others on the screen (SnapDrag).
--- @param key string|nil
--- @param x number
--- @param width number
--- @param element? Panel
function DirectorScreen.ItemDragging(key, x, width, element)
    LetDragsThrough()
    if element ~= nil and element.valid then
        if key ~= nil and Active() then
            SnapDrag(key, element)
        else
            SetDragSnap(element, nil)
        end
    end
    if key == nil or not Active() then
        if g.drag ~= nil then
            g.drag = nil
            UpdateDropHint()
        end
        return
    end
    local drag = g.drag
    if drag == nil or drag.key ~= key then
        local item = FindItem(key)
        drag = {key = key, shared = item ~= nil and item.store.state() ~= nil}
        g.drag = drag
    end
    drag.centre = x + width / 2
    drag.seen = dmhub.Time()
    UpdateDropHint()
end

--- Called each frame while the Director drags something new over the table
--- from a panel (a map, scene or character row, a token out of its map): x
--- is where the left edge of what the drop makes would land and width its
--- width (documents-layer units). It shows the drop's hint, as for an item.
--- @param x number
--- @param width number
function DirectorScreen.NewItemDragging(x, width)
    LetDragsThrough()
    if not Active() then
        return
    end
    local drag = g.drag
    if drag == nil or not drag.fresh then
        drag = {fresh = true}
        g.drag = drag
    end
    drag.centre = x + width / 2
    drag.seen = dmhub.Time()
    UpdateDropHint()
end

--Puts an item behind the screen, unsharing it, or out on the table. Out on
--the table its share stays off: only its share button shares it.
--- @param item DirectorScreenItem
--- @param behind boolean
local function SetBehind(item, behind)
    local key = item.key
    g.grace[key] = dmhub.Time() + GRACE_SECONDS
    if behind then
        g.members[key] = true
        if item.store.state() ~= nil then
            item.store.unshare()
            item.changed()
        end
    else
        g.members[key] = nil
    end
    Tabletop.SaveLayoutSoon()
end

--Shrinks a window dropped on the screen to a card and says it is hidden once
--the card has appeared (after Tabletop's collapse animation), or grows a
--card dropped off it back into its window.
--- @param item DirectorScreenItem
--- @param onScreen boolean
local function ReshapeAndFlash(item, onScreen)
    local rect = item.rect
    local reshaped = false
    if rect ~= nil and onScreen and item.shrink ~= nil and not item.card then
        item.shrink(math.max(rect.x, Edge() + 12), rect.y)
        reshaped = true
    elseif rect ~= nil and not onScreen and item.grow ~= nil then
        reshaped = item.card == true
        item.grow(rect.x, rect.y)
    end
    if not onScreen then
        return
    end
    if not reshaped then
        Flash(item)
        return
    end
    local key = item.key
    dmhub.Schedule(0.32, function()
        if mod.unloaded then
            return
        end
        local now = FindItem(key)
        if now ~= nil then
            Flash(now)
        end
    end)
end

--- Called when the Director drops an item on the table, after its new spot
--- is recorded. Moving it onto the screen stops sharing it; moving it off
--- leaves it unshared, with its share button back. A nil key just ends the
--- drag's hint.
--- @param key string|nil
function DirectorScreen.ItemDropped(key)
    SetPassing(false)
    if g.drag ~= nil then
        g.drag = nil
        UpdateDropHint()
    end
    if key == nil or not Active() then
        return
    end
    local item = FindItem(key)
    if item == nil or item.rect == nil then
        return
    end
    local onScreen = OnScreen(item.rect)
    if onScreen == (g.members[key] == true) then
        return
    end
    SetBehind(item, onScreen)
    ReshapeAndFlash(item, onScreen)
end

--The rule for an item a drop made or moved (ItemPlaced), once it is on the
--table: on the screen it is private; anywhere else (or with the screen
--closed) its share is left as it is.
--- @param item DirectorScreenItem
local function SettlePlaced(item)
    g.placed[item.key] = nil
    if item.rect == nil then
        return
    end
    local onScreen = OnScreen(item.rect)
    SetBehind(item, onScreen)
    ReshapeAndFlash(item, onScreen)
end

--- Called when the Director drops something onto the table that makes an
--- item there or moves one (a map, scene or journal row, a character or
--- bestiary row, a token out of its map, files from the desktop). Dropped on
--- the screen it is private (unshared); dropped anywhere else its share is
--- left as it is, so a new item starts unshared. The item may appear later
--- (a creature's card waits for the new character), so the screen waits a
--- while for it.
--- @param key string|nil
function DirectorScreen.ItemPlaced(key)
    SetPassing(false)
    if g.drag ~= nil then
        g.drag = nil
        UpdateDropHint()
    end
    if key == nil or not Active() then
        return
    end
    g.placed[key] = dmhub.Time() + PLACED_SECONDS
    local item = FindItem(key)
    if item ~= nil then
        SettlePlaced(item)
    end
end

--- Whether an item is hidden because it is on the closed screen (or on the
--- screen while a maximized window hides it).
--- @param key string|nil
--- @return boolean
function DirectorScreen.IsStowed(key)
    return key ~= nil and g.members[key] == true and not Shown() and dmhub.isDM
end

--- Opens the screen if an item on it is hidden by its being closed: the
--- Director went to it another way (focusing its map window). Hidden only
--- under a maximized window, it is already open and shows again on restore.
--- @param key string|nil
function DirectorScreen.Reveal(key)
    if DirectorScreen.IsStowed(key) and not IsOpen() then
        Open()
        for _, item in ipairs(Tabletop.ScreenItems()) do
            item.stow(false)
        end
    end
end

--- Whether the screen is open (not closed to its tab).
--- @return boolean
function DirectorScreen.IsOpen()
    return IsOpen()
end

--- Opens (true) or closes (false) the screen.
--- @param open boolean
function DirectorScreen.SetOpen(open)
    if open then
        Open()
    else
        Close()
    end
end

--- The screen's width as a fraction of the table (0 = closed), for tests.
--- @param fraction number
function DirectorScreen.SetFraction(fraction)
    if fraction > 0 then
        g.lastFraction = fraction
    end
    SetFraction(fraction)
    Tabletop.SaveLayoutSoon()
end

--- @param set table<string, boolean>
--- @return string[]
local function SortedKeys(set)
    local result = {}
    for key, _ in pairs(set) do
        result[#result+1] = key
    end
    table.sort(result)
    return result
end

--- The keys of the items on the screen, for tests.
--- @return string[]
function DirectorScreen.Members()
    return SortedKeys(g.members)
end

--- Whether the screen hides a panel at the mouse: it is showing, the mouse
--- is over it, and the panel lies behind the band (a shared window running
--- under it). The band takes no mouse, so what is under it still answers to
--- a pointer: a drop there must not reach what the Director cannot see.
--- @param panel Panel
--- @return boolean
function DirectorScreen.Hides(panel)
    local band = g.band
    if not Shown() or band == nil or not band.valid or panel == nil or not panel.valid then
        return false
    end
    local x = MouseOnTable()
    if x < Edge() then
        return false
    end
    local docs = band.parent
    if docs == nil then
        return false
    end
    --the panel's ancestor among the band's siblings: behind the band if it
    --comes before it.
    local top = panel
    while top ~= nil and top.parent ~= docs do
        top = top.parent
    end
    if top == nil then
        return false
    end
    for _, child in ipairs(docs.children) do
        if child == band then
            return false
        end
        if child == top then
            return true
        end
    end
    return false
end

--- Where the screen's edge is (documents-layer units), or nil while it is
--- closed or gone.
--- @return number|nil
function DirectorScreen.EdgeX()
    if not Active() or not Shown() then
        return nil
    end
    return Edge()
end

--Shows an item as its side says: no share button on the screen. A maximized
--window is on neither side: it keeps its share button.
--- @param item DirectorScreenItem
local function Present(item)
    local behind = g.members[item.key] == true and Shown() and not item.maximized
    local button = item.shareButton()
    if button ~= nil and button.valid and button:HasClass("collapsed") ~= behind then
        button:SetClass("collapsed", behind)
    end
    item.showBehind(behind)
end

--Applies the side rule to one item (see the top of the file).
--- @param item DirectorScreenItem
--- @return boolean changed whether the saved layout changed
local function KeepToItsSide(item)
    local key = item.key
    local rect = item.rect
    local open = Shown()
    local edge = Edge()
    local w = TableSize()
    local state = item.store.state()

    if g.members[key] then
        if state ~= nil then
            --shared another way: nothing on the screen is shared, so it
            --comes off it, to just left of the edge.
            g.members[key] = nil
            if rect ~= nil and item.card and item.grow ~= nil then
                --a card grows back into its window first; the next look moves
                --the window off (it is shared and on the screen).
                item.grow(rect.x, rect.y)
            elseif rect ~= nil then
                item.move(math.min(edge, w - RailReserve()) - rect.w - 16)
            end
            return true
        end
        if open and rect ~= nil and Centre(rect) < edge then
            --the screen narrowed under it: it moves along with the edge,
            --wholly onto the screen when it fits.
            item.move(math.max(edge - rect.w / 2 + 8, math.min(edge + 12, w - rect.w)))
            return true
        end
        return false
    end

    if OnScreen(rect) then
        --rect is not nil here (OnScreen checked it).
        --- @cast rect -nil
        if state == nil then
            --lying on the screen, unshared (opened there): it is behind it.
            g.members[key] = true
            g.pushed[key] = nil
            return true
        end
        if g.pushed[key] then
            --moved off last time and still on it: the screen is too wide
            --for it to get off, so it goes behind it.
            g.pushed[key] = nil
            SetBehind(item, true)
            return true
        end
        --shared, and the screen widened over it (or it opened there): off it
        --goes, wholly when it fits.
        g.pushed[key] = true
        item.move(math.min(edge - rect.w / 2 - 8, math.max(edge - 12 - rect.w, 0)))
        return true
    end
    g.pushed[key] = nil

    --a table button or card reaching onto the open screen: it is drawn over
    --every window, so it cannot go under the screen (KeepOnTop). Off it goes.
    if open and item.onButtonLayer and rect ~= nil and rect.x + rect.w > edge then
        item.move(edge - rect.w - 8)
        return true
    end
    return false
end

--A look over the items, ten times a second: each is kept to its side's rule
--(KeepToItsSide), shown to match (Present), and hidden on the closed screen.
local function LookOverItems()
    local items = Tabletop.ScreenItems()
    local now = dmhub.Time()
    local open = Shown()
    local first = not g.looked
    g.looked = true
    local present = {}
    local changed = false
    for key, deadline in pairs(g.placed) do
        if deadline < now then
            g.placed[key] = nil
        end
    end
    for _, item in ipairs(items) do
        local key = item.key
        present[key] = true
        --a drop's item, arrived: the drop's rule, not a new item's.
        if g.placed[key] ~= nil then
            SettlePlaced(item)
        end
        --the first look after a load: an item on the screen goes back to where
        --the screen carried it (the table's load keeps windows on the table).
        local offset = g.offsets[key]
        if first and g.members[key] and offset ~= nil and item.rect ~= nil then
            item.move(Edge() + offset, true)
            item.rect.x = Edge() + offset
        end
        --left alone while dragged, and while a share change it was just given
        --is on its way back from the server.
        local dragged = g.drag ~= nil and g.drag.key == key
        local moved = false
        if not dragged and (g.grace[key] or 0) < now then
            moved = KeepToItsSide(item)
            changed = changed or moved
        end
        --how far right of the edge it lies, for FollowEdge (not when this look
        --just moved it: its rect is from before the move).
        if g.members[key] and item.rect ~= nil and not moved then
            local current = item.rect.x - Edge()
            if offset == nil or math.abs(current - offset) > 0.5 then
                g.offsets[key] = current
                changed = true
            end
        end
        item.stow(g.members[key] == true and not open)
    end
    for _, item in ipairs(items) do
        Present(item)
    end
    for key, _ in pairs(g.members) do
        if not present[key] then
            g.members[key] = nil
            changed = true
        end
    end
    for key, _ in pairs(g.offsets) do
        if not g.members[key] then
            g.offsets[key] = nil
        end
    end
    for key, _ in pairs(g.grace) do
        if not present[key] then
            g.grace[key] = nil
        end
    end
    for key, _ in pairs(g.pushed) do
        if not present[key] then
            g.pushed[key] = nil
        end
    end
    if changed then
        Tabletop.SaveLayoutSoon()
    end
end

--Keeps the screen over everything shared: puts the band into the documents
--layer (once per layer), and whenever a shared item has been raised over it
--(focusing a window raises it) or one of its own items has sunk under it,
--restores the order: everything else, the band, the icon rails, then the
--screen's own items. Dialogs that were above the band stay above it.
local function KeepOnTop()
    local hud = GameHud.instance
    local docs = hud ~= nil and hud.documentsPanel or nil
    if docs == nil or not docs.valid then
        return
    end
    --built straight into the layer (a panel made without a parent is lost),
    --and built again if it ever leaves it (something resetting the layer's
    --children would otherwise leave it out for good).
    local band = g.band
    if band == nil or not band.valid or band.parent ~= docs then
        if band ~= nil and band.valid then
            band:DestroySelf()
        end
        band = BuildBand()
        docs:AddChild(band)
        band:SetAsFirstSibling()
        g.signature = nil
    end
    if not Shown() then
        return
    end

    --which panels are items, and whose: the screen's own, or shared.
    local own = {}
    local items = {}
    local drag = g.drag
    for _, item in ipairs(Tabletop.ScreenItems()) do
        local panel = item.panel()
        if panel ~= nil and panel.valid then
            items[panel] = true
            local mine = g.members[item.key] == true and not item.maximized
            --while dragged (in place, see Tabletop's dragInPlace), its side is
            --where its middle is now: under the screen until it crosses the
            --edge, then over it, as dropping it there would hide it.
            if drag ~= nil and drag.key == item.key and drag.centre ~= nil then
                mine = drag.centre >= Edge()
            end
            if mine then
                own[panel] = true
            end
        end
    end

    --journal and panel windows and the table's own items (audio cards...)
    --are not shared, but they lie on the table among the shared windows and
    --raise over them on a click, so they go under the screen too. Treated as
    --dialogs above it instead, a focused map window would sink under them.
    --A maximized journal covers the table, so it stays over the screen.
    local function OnTable(child)
        if child:HasClass("tabletopItem") then
            return true
        end
        return child:HasClass("journalViewer") and not child:HasClass("journalMaximized")
    end

    --childCount/GetChild (0-based) rather than 'children', which builds a new table
    --per read: this runs 20 times a second. Nothing reorders the children until after
    --the loops below.
    local nchildren = docs.childCount
    local bandIndex = nil
    for i = 1, nchildren do
        local child = docs:GetChild(i - 1) --[[@as Panel]] --i is within childCount
        if child == band then
            bandIndex = i
            break
        end
    end
    if bandIndex == nil then
        return
    end
    local wrong = false
    for i = 1, nchildren do
        local child = docs:GetChild(i - 1) --[[@as Panel]] --i is within childCount
        if own[child] then
            wrong = wrong or i < bandIndex
        elseif OnTable(child) then
            wrong = wrong or i > bandIndex
        elseif items[child] or child:HasClass("iconRail") then
            --a shared item over the band, or a rail under it.
            wrong = wrong or (items[child] and i > bandIndex) or (not items[child] and i < bandIndex)
        end
    end
    if not wrong then
        return
    end

    local rails, mine, above = {}, {}, {}
    for i = 1, nchildren do
        local child = docs:GetChild(i - 1) --[[@as Panel]] --i is within childCount
        if own[child] then
            mine[#mine+1] = child
        elseif child:HasClass("iconRail") then
            rails[#rails+1] = child
        elseif i > bandIndex and not items[child] and not OnTable(child) then
            above[#above+1] = child
        end
    end
    band:SetAsLastSibling()
    for _, list in ipairs({rails, mine, above}) do
        for _, child in ipairs(list) do
            child:SetAsLastSibling()
        end
    end
end

--- The tabletop's think calls this (every 0.05 s).
function DirectorScreen.Sync()
    Layout()
    KeepOnTop()
    if g.passing and dmhub.Time() > g.passUntil then
        SetPassing(false)
    end
    if g.drag ~= nil and dmhub.Time() - (g.drag.seen or 0) > 0.3 then
        g.drag = nil
        UpdateDropHint()
    end
    if not Active() then
        return
    end
    local now = dmhub.Time()
    if now < g.nextLook then
        return
    end
    g.nextLook = now + 0.1
    LookOverItems()
end

--- The screen's part of the saved table layout.
--- @return table
function DirectorScreen.Save()
    return {
        fraction = g.fraction,
        lastFraction = g.lastFraction,
        members = DirectorScreen.Members(),
        offsets = g.offsets,
    }
end

--- Restores the screen from a saved table layout (nil: a new table).
--- @param saved table|nil
function DirectorScreen.Load(saved)
    g.members = {}
    g.offsets = {}
    g.lastEdge = nil
    g.looked = false
    g.pushed = {}
    g.grace = {}
    g.placed = {}
    g.drag = nil
    g.resize = nil
    g.slide = nil
    g.fraction = DEFAULT_FRACTION
    g.lastFraction = DEFAULT_FRACTION
    if type(saved) == "table" then
        g.fraction = math.max(0, math.min(MAX_FRACTION, tonumber(saved.fraction) or DEFAULT_FRACTION))
        g.lastFraction = math.max(0.05, math.min(MAX_FRACTION, tonumber(saved.lastFraction) or DEFAULT_FRACTION))
        --exactly 0.7 is the cap the screen had for a day (2026-10-18): a size
        --saved then was pinned there, so it was really "as wide as it goes".
        if g.fraction == STALE_CAP then
            g.fraction = MAX_FRACTION
        end
        if g.lastFraction == STALE_CAP then
            g.lastFraction = MAX_FRACTION
        end
        if type(saved.members) == "table" then
            for _, key in ipairs(saved.members) do
                if type(key) == "string" then
                    g.members[key] = true
                end
            end
        end
        if type(saved.offsets) == "table" then
            for key, offset in pairs(saved.offsets) do
                if type(key) == "string" and type(offset) == "number" and g.members[key] then
                    g.offsets[key] = offset
                end
            end
        end
    end
    g.signature = nil
    Layout()
end
