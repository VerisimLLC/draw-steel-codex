local mod = dmhub.GetModLoading()

--Map Preview: a look around a map-pack map before adding it. The Map
--Library's Preview button calls MapPreview.Start. The map goes into the game
--as a preview (mappacks.AddMapToGame with preview = true; see
--MAP_PREVIEW_REFERENCE.md at the dmhub repo root): the engine keeps it out of
--every map list and away from players, refuses to copy or export it, shows a
--selected token's vision on it, and deletes it with map:DiscardPreview().
--This file runs the visit: a new table window on the map, test tokens on it,
--the Floors panel beside it on a map with more than one floor, a bar over the
--map with the way out, and the clean-up when the preview ends (its End Preview
--button, or closing its window).

MapPreview = rawget(_G, "MapPreview") or {}

--the test tokens, by bestiary name: the first TEST_TOKEN_COUNT of these the
--game's bestiary has are put at the most open spot of the map.
local TEST_TOKEN_NAMES = {"Human Warrior", "Human Archer", "Human Guard", "Goblin Warrior", "Wolf"}
local TEST_TOKEN_COUNT = 4

--an imported map's ground is its map images, so no tile is standing room
--until they have loaded. Once the window's loading cover lifts, the test
--tokens keep looking for an open spot this long, this often, before falling
--back to the middle of the map.
local PLACE_WAIT_SECONDS = 5
local PLACE_RETRY_SECONDS = 0.5

--how long the map may take to arrive, or to be travelled off, before giving up.
local WAIT_SECONDS = 60

local FLOORS_PANEL = "Floors & Layers"

--room left for a column of rail buttons: the map rail inside each edge of a
--map window, and the icon rails at the edges of the table.
local RAIL_ROOM = 64
--between the preview's window and the Floors window beside it.
local FLOORS_GAP = 12

--the Player View button frames this many tiles either side of the token.
local PLAYER_VIEW_RADIUS = 6

--a map with up to this many variants gets a button for each, on a line of
--their own under the bar; with more, one dropdown there instead, so the bar
--stays narrower than the map window.
local VARIANT_BUTTONS_MAX = 6

--- @class MapPreviewState
--- @field name string the map's name
--- @field returnMapId string the map that was current when the preview began
--- @field onEnd nil|fun(shown: nil|MapPackIndexEntry) called once the preview is over, with the variant last shown
--- @field mapid nil|string the preview map, once the add has answered
--- @field addDone boolean the add has answered (with a map or an error)
--- @field failure nil|string why the preview could not open
--- @field loading nil|{x: number, y: number, width: number, height: number, Close: fun(), SetStatus: fun(text: string)}
--- @field opened boolean its window has been opened
--- @field spawned boolean the map has been framed and the Floors panel opened
--- @field tokensPlaced boolean the test tokens have been put on the map
--- @field placeGiveUp nil|number dmhub.Time() after which the tokens go in the middle
--- @field placeNextTry nil|number dmhub.Time() of the next look for an open spot
--- @field floorsOpened nil|boolean the preview opened the Floors panel, so ending it closes it
--- @field testTokens nil|string[] charids of the test tokens put on the map
--- @field viewToken nil|string the token the Player View button last showed, to go back to
--- @field variants nil|{name: string, index: integer, entry: MapPackIndexEntry}[] the map's variants as the Map Library lists them, when it has more than one
--- @field variant integer the variant showing, kept in step by the watch loop (a full scene's own sceneAppearance is the truth)
--- @field bar nil|Panel the bar over the map
--- @field barHost nil|Panel the map window overlay the bar is in
--- @field ending boolean End has begun
--- @field finished boolean the preview is over

--- @type MapPreviewState|nil
local g_preview = nil

--- True when this user can preview a map now: the Director, in a game with a
--- table, with no preview already open.
--- @return boolean
function MapPreview.CanPreview()
    return dmhub.isDM and Tabletop.IsActive() and g_preview == nil
end

--- The preview map's id while a preview is open, else nil.
--- @return nil|string
function MapPreview.CurrentMapId()
    if g_preview == nil then
        return nil
    end
    return g_preview.mapid
end

local function MapLoaded(mapid)
    local map = game.GetMap(mapid)
    if map == nil or not map.valid then
        return false
    end
    local count = 0
    pcall(function() count = #map.floors end)
    return count > 0
end

--- @param preview MapPreviewState
local function CloseLoading(preview)
    if preview.loading ~= nil then
        preview.loading.Close()
        preview.loading = nil
    end
end

--- @param preview MapPreviewState
local function RemoveBar(preview)
    if preview.bar ~= nil and preview.bar.valid then
        preview.bar:DestroySelf()
    end
    preview.bar = nil
    preview.barHost = nil
end

--Whether the Floors panel is up: a window on the icon rail, or in a dock.
local function FloorsPanelOpen()
    if PanelDocument.IsPanelShown(FLOORS_PANEL) then
        return true
    end
    for _, item in ipairs(DockablePanel.GetMenuItems(true, true)) do
        if item.name == FLOORS_PANEL then
            return item.check == true
        end
    end
    return false
end

--The Floors panel goes when the preview does, unless the Director had it open
--before the preview began.
--- @param preview MapPreviewState
local function CloseFloors(preview)
    if not preview.floorsOpened then
        return
    end
    preview.floorsOpened = false
    if not mod.unloaded then
        DockablePanel.LaunchPanelByName(FLOORS_PANEL, "hide")
    end
end

--The Library entry of the variant the preview was last seen showing, or nil
--for a map with one variant.
--- @param preview MapPreviewState
--- @return nil|MapPackIndexEntry
local function ShownEntry(preview)
    for _, v in ipairs(preview.variants or {}) do
        if v.index == preview.variant then
            return v.entry
        end
    end
    return nil
end

--The preview is over: tell whoever started it (the Map Library reopens, on
--the variant last shown), then say why it failed, if it did, on top.
--- @param preview MapPreviewState
local function Finish(preview)
    if preview.finished then
        return
    end
    preview.finished = true
    CloseLoading(preview)
    RemoveBar(preview)
    CloseFloors(preview)
    if g_preview == preview then
        g_preview = nil
    end
    if mod.unloaded then
        return
    end
    if preview.onEnd ~= nil then
        preview.onEnd(ShownEntry(preview))
    end
    if preview.failure ~= nil then
        gui.ModalMessage{
            title = "Could Not Preview the Map",
            message = string.format("%s could not be previewed: %s", preview.name, preview.failure),
        }
    end
end

--Bestiary ids for the test tokens, in TEST_TOKEN_NAMES order.
local function TestTokenIds()
    local byName = {}
    for id, monster in pairs(assets.monsters) do
        local name = monster.name
        if not monster.hidden and type(name) == "string" and byName[name] == nil then
            byName[name] = id
        end
    end
    local ids = {}
    for _, name in ipairs(TEST_TOKEN_NAMES) do
        if byName[name] ~= nil and #ids < TEST_TOKEN_COUNT then
            ids[#ids + 1] = byName[name]
        end
    end
    return ids
end

--Moves the Floors window off the map: beside the preview's window (right,
--else left), or inside its right edge when the window fills the table. The
--icon rail would open it at its map-rail button, over the map. With the rail
--off the panel goes in a dock, which is already at the side.
--- @param preview MapPreviewState
local function PlaceFloorsWindow(preview)
    local dialog = PanelDocument.FindHostDialog(FLOORS_PANEL)
    local mapid = preview.mapid
    if dialog == nil or mapid == nil or dialog.renderedWidth <= 0 then
        return
    end
    local rect = Tabletop.MapWindowRect(mapid)
    if rect == nil then
        return
    end
    --the window's set size: just after it opens renderedWidth can still be
    --smaller than it will be.
    local unscaledWidth, unscaledHeight = dialog.renderedWidth, dialog.renderedHeight
    local styleWidth, styleHeight = dialog.selfStyle.width, dialog.selfStyle.height
    if type(styleWidth) == "number" then
        unscaledWidth = styleWidth
    end
    if type(styleHeight) == "number" then
        unscaledHeight = styleHeight
    end
    --both are before the Font Size zoom; what shows is scaled by it.
    local width = unscaledWidth * PanelDocument.WindowUIScale()
    local tableWidth = Tabletop.LayerSize()
    local x
    local y = rect.y
    if rect.x + rect.w + FLOORS_GAP + width <= tableWidth - RAIL_ROOM then
        x = rect.x + rect.w + FLOORS_GAP
    elseif rect.x - FLOORS_GAP - width >= RAIL_ROOM then
        x = rect.x - FLOORS_GAP - width
    else
        --clear of the map rail and the window's title bar.
        x = rect.x + rect.w - RAIL_ROOM - width
        y = rect.y + RAIL_ROOM
    end
    dialog.x, dialog.y = PanelDocument.ClampWindowOnScreen(x, y, unscaledWidth, unscaledHeight)
end

--Opens the Floors panel to switch floors on and off, on a map with more than
--one floor, and places it once its window has a size.
--- @param preview MapPreviewState
--- @param map MapManifestLua
local function OpenFloors(preview, map)
    local floors = 0
    pcall(function() floors = #map.floorsWithoutLayers end)
    if floors <= 1 or FloorsPanelOpen() then
        return
    end
    DockablePanel.ShowPanelByName(FLOORS_PANEL)
    preview.floorsOpened = true
    local deadline = dmhub.Time() + 2
    dmhub.ScheduleWhen(function()
        if mod.unloaded or g_preview ~= preview or preview.ending or dmhub.Time() > deadline then
            return true
        end
        local dialog = PanelDocument.FindHostDialog(FLOORS_PANEL)
        return dialog == nil or dialog.renderedWidth > 0
    end, function()
        if mod.unloaded or g_preview ~= preview or preview.ending then
            return
        end
        PlaceFloorsWindow(preview)
    end)
end

--Once the map is current: the whole map in view (a new window keeps the
--camera of the map before it) and the Floors panel when there are floors to
--switch between. The test tokens wait for the map's art (PlaceTestTokens).
--- @param preview MapPreviewState
local function SetUpMap(preview)
    preview.spawned = true
    dmhub.FrameMapArea()
    local map = game.GetMap(preview.mapid)
    if map ~= nil then
        OpenFloors(preview, map)
    end
end

--Called while the preview is current until it has put the test tokens down:
--at the most open spot of the floor's main walkable area (the exact middle
--can be a sealed or raised column), once the window's loading cover has
--lifted and game.FindOpenArea finds standing room, or after PLACE_WAIT_SECONDS
--in the middle of the map.
--- @param preview MapPreviewState
local function PlaceTestTokens(preview)
    if dmhub.mapTransitionMapId == preview.mapid and dmhub.mapTransitionCovered then
        return
    end
    local now = dmhub.Time()
    if preview.placeNextTry ~= nil and now < preview.placeNextTry then
        return
    end
    preview.placeGiveUp = preview.placeGiveUp or (now + PLACE_WAIT_SECONDS)
    preview.placeNextTry = now + PLACE_RETRY_SECONDS

    local floor = game.currentFloorIndex
    local spot = game.FindOpenArea(floor)
    if spot == nil and now < preview.placeGiveUp then
        return
    end

    preview.tokensPlaced = true
    local map = game.GetMap(preview.mapid)
    local ids = TestTokenIds()
    if map == nil or #ids == 0 then
        return
    end
    local x, y
    if spot ~= nil then
        x, y = spot.x, spot.y
    else
        --map dimensions are tiles (x2/y2 exclusive), which are also world units.
        local dims = map.dimensions
        x, y = (dims.x + dims.z) / 2, (dims.y + dims.w) / 2
    end
    preview.testTokens = game.SpawnBestiaryOnMap(ids, preview.mapid, x, y, floor)
end

--The token the Player View button shows: the one it showed last, else the
--first test token still on the map, else any token on the map.
--- @param preview MapPreviewState
--- @return nil|CharacterToken
local function PlayerViewToken(preview)
    local candidates = {}
    if preview.viewToken ~= nil then
        candidates[#candidates + 1] = preview.viewToken
    end
    for _, charid in ipairs(preview.testTokens or {}) do
        candidates[#candidates + 1] = charid
    end
    for _, charid in ipairs(candidates) do
        local tok = dmhub.GetTokenById(charid)
        if tok ~= nil then
            return tok
        end
    end
    return dmhub.allTokens[1]
end

--Player View: select a test token and zoom in on it, so the map shows what it
--sees (a preview turns on a selected token's vision). With any token selected
--it goes back instead: nothing selected, the Director's view of the whole map.
--Returns true when it is now showing a token's view.
--- @return boolean
local function TogglePlayerView()
    local preview = g_preview
    if preview == nil then
        return false
    end
    local selected = dmhub.selectedTokens
    if #selected > 0 then
        --a token picked by hand is the one the button comes back to.
        preview.viewToken = selected[1].charid
        dmhub.selectedTokens = {}
        dmhub.FrameMapArea()
        return false
    end
    local tok = PlayerViewToken(preview)
    if tok == nil then
        return false
    end
    preview.viewToken = tok.charid
    dmhub.SelectToken(tok.charid)
    local loc = tok.loc
    dmhub.FrameMapArea{
        x1 = loc.x - PLAYER_VIEW_RADIUS,
        y1 = loc.y - PLAYER_VIEW_RADIUS,
        x2 = loc.x + PLAYER_VIEW_RADIUS + 1,
        y2 = loc.y + PLAYER_VIEW_RADIUS + 1,
    }
    return true
end

--The map's variants as the Map Library lists them (every index entry for the
--same pack and map, in variant order): a full scene's looks (Day, Night...)
--or an ordinary map's alternate pictures. nil when it has only one.
--- @param entry MapPackIndexEntry
--- @return nil|{name: string, index: integer, entry: MapPackIndexEntry}[]
local function MapVariants(entry)
    local result = {}
    for _, other in ipairs(mappacks.Search{ text = "", pack = entry.pack, maxResults = 100000 }) do
        if other.pack == entry.pack and other.id == entry.id then
            local name = other.variant or ""
            if name == "" then
                name = cond(other.variantIndex == 0, "Default", string.format("Variant %d", other.variantIndex))
            end
            result[#result + 1] = {name = name, index = other.variantIndex, entry = other}
        end
    end
    table.sort(result, function(a, b) return a.index < b.index end)
    if #result < 2 then
        return nil
    end
    return result
end

--- @param preview MapPreviewState
--- @return integer
local function ShowingVariant(preview)
    local map = preview.mapid ~= nil and game.GetMap(preview.mapid) or nil
    if map ~= nil and map.sceneAppearances ~= nil then
        return map.sceneAppearance
    end
    return preview.variant
end

--Shows another of the map's variants, on the live preview map only. A full
--scene switches its whole look (map:SetSceneAppearance: art, lights, sounds,
--walls, weather); an ordinary map turns every Appearance component on it to
--that picture, as adding that variant from the Map Library does.
--Returns why it could not, or nil.
--- @param preview MapPreviewState
--- @param index integer
--- @return nil|string
local function SwitchVariant(preview, index)
    local map = preview.mapid ~= nil and game.GetMap(preview.mapid) or nil
    if map == nil or game.currentMapId ~= preview.mapid or index == ShowingVariant(preview) then
        return nil
    end
    if map.sceneAppearances ~= nil then
        local err = map:SetSceneAppearance(index)
        if err ~= nil then
            return err
        end
        --the look lands on the next frame; the watch loop then notes it and
        --retitles the window.
        return nil
    else
        for _, floor in ipairs(map.floors) do
            for _, obj in pairs(floor.objects) do
                local comp = obj:GetComponent("Appearance")
                if comp ~= nil and comp.valid then
                    local doc = obj:ComponentToJson(comp.componentid)
                    local swaps = doc ~= nil and doc.imageSwaps or {}
                    --index 0 is the base picture, n is imageSwaps[n].
                    local number = math.min(index, #swaps)
                    if #swaps > 0 and (doc.imageNumber or 0) ~= number then
                        comp:SetAndUploadProperties{ imageNumber = number }
                    end
                end
            end
        end
    end
    preview.variant = index
    Tabletop.RefreshTitles()
    return nil
end

--- The window title's name for the open preview's map: the name of the Map
--- Library variant it is showing, so the title follows a switch. nil when
--- mapid is not the open preview or the map has one variant (its own name is
--- right then). Called by Tabletop for a preview map's title.
--- @param mapid string
--- @return nil|string
function MapPreview.ShownName(mapid)
    local preview = g_preview
    if preview == nil or preview.mapid ~= mapid or preview.variants == nil then
        return nil
    end
    local showing = ShowingVariant(preview)
    for _, v in ipairs(preview.variants) do
        if v.index == showing then
            return v.entry.name
        end
    end
    return nil
end

--The bar's variant switcher, a line under the rest of the bar: a button per
--variant, the one showing lit, or a dropdown past VARIANT_BUTTONS_MAX. nil
--for a map with one variant, so the bar then has no second line.
--- @param preview MapPreviewState
--- @return nil|Panel
local function VariantControl(preview)
    local variants = preview.variants
    if variants == nil then
        return nil
    end

    local function Switch(index)
        local err = SwitchVariant(preview, index)
        if err ~= nil then
            gui.ModalMessage{ title = "Could not change the map's look", message = err }
            return false
        end
        return true
    end

    if #variants > VARIANT_BUTTONS_MAX then
        local options = {}
        for _, v in ipairs(variants) do
            options[#options + 1] = {id = v.index, text = v.name}
        end
        return gui.Dropdown{
            classes = {"formDropdown"},
            width = 180,
            halign = "left",
            tmargin = 8,
            options = options,
            idChosen = ShowingVariant(preview),
            thinkTime = 0.2,
            think = function(element)
                ---@cast element Dropdown
                local showing = ShowingVariant(preview)
                if element.idChosen ~= showing then
                    element.idChosen = showing
                end
            end,
            change = function(element)
                ---@cast element Dropdown
                local index = element.idChosen
                if type(index) == "number" and not Switch(index) then
                    element.idChosen = ShowingVariant(preview)
                end
            end,
        }
    end

    local buttons = {}
    for _, v in ipairs(variants) do
        buttons[#buttons + 1] = gui.Button{
            classes = {"sizeS", cond(ShowingVariant(preview) == v.index, "selected")},
            width = "auto",
            hpad = 12,
            rmargin = 4,
            valign = "center",
            text = v.name,
            thinkTime = 0.2,
            think = function(element)
                element:SetClass("selected", ShowingVariant(preview) == v.index)
            end,
            click = function(element)
                if not Switch(v.index) then
                    return
                end
                --lit at once: a scene's look lands on the next frame.
                for _, sibling in ipairs(element.parent.children) do
                    sibling:SetClass("selected", sibling == element)
                end
            end,
        }
    end
    return gui.Panel{
        width = "auto",
        height = "auto",
        halign = "left",
        tmargin = 8,
        flow = "horizontal",
        children = buttons,
    }
end

--The bar over the map: the title and help, Player View and End Preview on
--one line, and the map's variants on a line below when it has several.
--- @param preview MapPreviewState
local function BuildBar(preview)
    local mainRow = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        gui.Panel{
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 18,
            flow = "vertical",
            gui.Label{
                classes = {"sizeM"},
                width = "auto",
                height = "auto",
                bold = true,
                text = "Map Preview",
            },
            gui.Label{
                classes = {"sizeS"},
                width = "auto",
                height = "auto",
                text = "Select a test token to see what it sees. Nothing here is added to your game.",
            },
        },
        --lit while a token is selected, i.e. while the map shows a token's view.
        gui.Button{
            classes = {"sizeS"},
            width = "auto",
            hpad = 12,
            rmargin = 8,
            valign = "center",
            text = "Player View",
            thinkTime = 0.2,
            think = function(element)
                element:SetClass("selected", #dmhub.selectedTokens > 0)
            end,
            click = function(element)
                --lit at once: the selection itself may only show on the next frame.
                element:SetClass("selected", TogglePlayerView())
            end,
        },
        gui.Button{
            classes = {"sizeM"},
            width = "auto",
            hpad = 16,
            valign = "center",
            text = "End Preview",
            click = function(element)
                MapPreview.End()
            end,
        },
    }

    local rows = {mainRow}
    local variants = VariantControl(preview)
    if variants ~= nil then
        rows[#rows + 1] = variants
    end

    return gui.Panel{
        classes = {"framedPanel"},
        styles = ThemeEngine.GetStyles(),
        bgimage = true,
        floating = true,
        halign = "center",
        valign = "top",
        tmargin = 12,
        width = "auto",
        height = "auto",
        hpad = 14,
        vpad = 10,
        borderBox = true,
        flow = "vertical",
        children = rows,
    }
end

--The bar lives in the preview window's map overlay while that window shows
--the map live; anywhere else it goes.
--- @param preview MapPreviewState
local function SyncBar(preview)
    local host = nil
    if game.currentMapId == preview.mapid then
        host = Tabletop.MapOverlayHost()
    end
    if host == nil then
        RemoveBar(preview)
        return
    end
    if preview.bar ~= nil and preview.bar.valid and preview.barHost == host then
        return
    end
    RemoveBar(preview)
    preview.bar = BuildBar(preview)
    preview.barHost = host
    host:AddChild(preview.bar)
end

--Runs while the preview is open: sets the map up when it first becomes
--current, keeps the bar on it, and ends the preview once its window closes.
--- @param preview MapPreviewState
local function Watch(preview)
    dmhub.Coroutine(function()
        while g_preview == preview and not preview.ending and not mod.unloaded do
            if not Tabletop.IsActive() then
                --left the game: the next visit discards the map (MapPreview.cs).
                RemoveBar(preview)
                g_preview = nil
                return
            end
            local mapid = preview.mapid
            if mapid ~= nil and preview.opened then
                if game.GetMap(mapid) == nil then
                    --deleted from elsewhere.
                    Finish(preview)
                    return
                end
                if not Tabletop.HasMapWindow(mapid) then
                    MapPreview.End()
                    return
                end
                if game.currentMapId == mapid then
                    if not preview.spawned then
                        SetUpMap(preview)
                    end
                    if not preview.tokensPlaced then
                        PlaceTestTokens(preview)
                    end
                    --follows a look changed in the Floors dialog, or undone, too;
                    --the window title names the variant (MapPreview.ShownName).
                    local showing = ShowingVariant(preview)
                    if showing ~= preview.variant then
                        preview.variant = showing
                        Tabletop.RefreshTitles()
                    end
                end
                SyncBar(preview)
            end
            coroutine.yield(0.1)
        end
    end)
end

--Where to go when the preview ends: the map the Director was on, else any.
--- @param preview MapPreviewState
--- @return nil|MapManifestLua
local function ReturnMap(preview)
    local map = game.GetMap(preview.returnMapId)
    if map ~= nil and map.valid and not map.preview then
        return map
    end
    return game.maps[1]
end

--- @param preview MapPreviewState
local function Open(preview)
    local mapid = preview.mapid
    ---@cast mapid string
    local opened = false
    local at = preview.loading
    if at ~= nil then
        --a new window where the loading stand-in was, which travels there.
        opened = Tabletop.MapRowDropped(mapid, {at = {x = at.x, y = at.y, width = at.width, height = at.height}})
    end
    if not opened then
        Tabletop.OpenMap(mapid, {newWindow = true})
    end
    CloseLoading(preview)
    preview.opened = true
end

--- Opens a Map Library map as a Map Preview: added to the game hidden and
--- temporary, opened in a new window on the table with test tokens on it and
--- the Floors panel open. options.markupId is passed to mappacks.AddMapToGame.
--- options.onEnd is called once the preview is over and its map deleted,
--- with the Library entry of the variant last shown (nil for a map with one).
--- Returns false when a preview cannot start (see CanPreview).
--- @param entry MapPackIndexEntry
--- @param options nil|{markupId: nil|string, onEnd: nil|fun(shown: nil|MapPackIndexEntry)}
--- @return boolean
function MapPreview.Start(entry, options)
    options = options or {}
    if not MapPreview.CanPreview() then
        return false
    end

    --- @type MapPreviewState
    local preview = {
        name = entry.name,
        returnMapId = game.currentMapId,
        onEnd = options.onEnd,
        addDone = false,
        opened = false,
        spawned = false,
        tokensPlaced = false,
        variants = MapVariants(entry),
        variant = entry.variantIndex,
        ending = false,
        finished = false,
    }
    g_preview = preview

    --a map with floors gets the Floors panel beside its window (OpenFloors):
    --leave room for it from the start, so nothing has to move once it opens.
    local storeys = 0
    pcall(function()
        local stats = entry.sceneStats
        if stats ~= nil then
            storeys = stats.floors or 0
        end
    end)
    local reserve = nil
    if storeys > 1 and not FloorsPanelOpen() then
        reserve = FLOORS_GAP + PanelDocument.DefaultWidth * PanelDocument.WindowUIScale()
    end
    preview.loading = Tabletop.ShowLoadingWindow{name = entry.name, status = "Setting up the preview...", reserveRight = reserve}

    mappacks.AddMapToGame{
        pack = entry.pack,
        mapid = entry.id,
        variantIndex = entry.variantIndex,
        name = entry.name,
        markupId = options.markupId,
        preview = true,
        success = function(mapid)
            preview.mapid = mapid
            preview.addDone = true
            local deadline = dmhub.Time() + WAIT_SECONDS
            dmhub.ScheduleWhen(function()
                return mod.unloaded or preview.ending or MapLoaded(mapid) or dmhub.Time() > deadline
            end, function()
                --ended while it loaded: End discards it.
                if mod.unloaded or preview.ending then
                    return
                end
                if not MapLoaded(mapid) then
                    preview.failure = "it did not finish loading."
                    MapPreview.End()
                    return
                end
                Open(preview)
            end)
        end,
        error = function(message)
            preview.addDone = true
            preview.failure = message or "unknown error"
            MapPreview.End()
        end,
    }

    Watch(preview)
    return true
end

--- Ends the open preview: closes its window, goes back to the map the
--- Director was on, deletes the preview map with its test tokens, then calls
--- the onEnd given to Start. Safe to call at any point, even mid-load.
function MapPreview.End()
    local preview = g_preview
    if preview == nil or preview.ending then
        return
    end
    preview.ending = true
    if preview.mapid ~= nil and game.currentMapId == preview.mapid then
        preview.variant = ShowingVariant(preview)
    end
    RemoveBar(preview)
    CloseLoading(preview)
    CloseFloors(preview)

    dmhub.Coroutine(function()
        local deadline = dmhub.Time() + WAIT_SECONDS
        --an add still in flight would leave its map behind: wait for it.
        while not preview.addDone and dmhub.Time() < deadline and not mod.unloaded do
            coroutine.yield(0.1)
        end
        local mapid = preview.mapid
        if mapid ~= nil and not mod.unloaded then
            while game.GetMap(mapid) == nil and dmhub.Time() < deadline do
                coroutine.yield(0.1)
            end
            Tabletop.CloseMapWindow(mapid)
            if game.currentMapId == mapid then
                local back = ReturnMap(preview)
                if back ~= nil then
                    back:Travel()
                end
                local travelDeadline = dmhub.Time() + WAIT_SECONDS
                while game.currentMapId == mapid and dmhub.Time() < travelDeadline and not mod.unloaded do
                    coroutine.yield(0.1)
                end
            end
            local map = game.GetMap(mapid)
            if map ~= nil and map.valid and map.preview and game.currentMapId ~= mapid then
                map:DiscardPreview()
            end
        end
        Finish(preview)
    end)
end

--a Lua reload drops the bar with the old code, and loses the state above:
--pick a preview the Director is standing on back up, so its bar and clean-up
--still work. (One in a background window is discarded on the next visit.)
mod.unloadHandlers[#mod.unloadHandlers + 1] = function()
    if g_preview ~= nil then
        RemoveBar(g_preview)
    end
end

if dmhub.inGame and Tabletop.IsActive() then
    local current = game.currentMap
    if current ~= nil and current.valid and current.preview and current.previewOwner == dmhub.loginUserid then
        local maps = game.maps
        --- @type MapPreviewState
        local adopted = {
            name = current.description,
            returnMapId = maps[1] ~= nil and maps[1].id or "",
            mapid = current.id,
            addDone = true,
            opened = true,
            spawned = true,
            tokensPlaced = true,
            --(the Map Library entry is gone with the reload, so no variant switcher.)
            variant = current.sceneAppearance,
            ending = false,
            finished = false,
        }
        g_preview = adopted
        Watch(adopted)
    end
end
