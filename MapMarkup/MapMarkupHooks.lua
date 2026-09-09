local mod = dmhub.GetModLoading()

--Map Markup: panel state, explicit arming, the focus-gated selection helpers
--and the engine hook chaining that publishes them.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--Panel state + the engine-polled selection hook.
--============================================================================

m.markupHud = nil
m.markupHudRef = function() return m.markupHud end
m.mode = "walls"
m.markupModeRef = function() return m.mode end
m.selectedIndex = 1
m.paletteEntries = {}
--"rectangle" / "line" / "free" draw walls through the engine building tools,
--and "points" drives the engine's wall vertex-editing tool the same way;
--"erase" / "delete" and the solid shape tools are custom map tools driven
--from this panel. Reset to each mode's first tool when the panel is built.
m.toolId = "rectangle"

--Materializes the wall asset behind the SELECTED palette entry, creating it
--if that entry is still a bare preset. Assigned by the panel builder, whose
--closure owns MaterializeEntry and the palette-writing helpers; nil while no
--panel exists. See m.arm.Set for why arming is what calls it.
m.MaterializeSelectedWall = nil

--============================================================================
--ARMED: whether this panel's tool is live, i.e. whether clicks on the map do
--markup. EXPLICIT, and deliberately NOT derived from GUI focus any more.
--
--Focus used to BE the armed state, and it disarmed for reasons the user never
--performed: focus parked on a chip died when a stroke rebuilt the chip list
--(one stroke landed, every later one silently did nothing), and the Building
--editor's palette stole focus a frame after a tool press (wall drawing simply
--stopped, and the only way back was clicking a wall type). Both needed
--defensive workarounds -- see TakeMarkupFocus's comment and the late
--ReassertMarkupFocus -- and neither made the state predictable.
--
--Now arming is a verb: pressing a tool arms it, pressing the armed tool again
--disarms, Escape disarms, closing the panel disarms, and NOTHING else does.
--Focus is still taken so the panel keeps its keyboard routing, but losing it
--no longer means anything, which is what makes the state worth showing.
--ONE table, not a flag plus two functions, grouping the related state.
--Everything arming needs hangs off m.arm.
m.arm = {}
m.arm.on = false

--The one predicate every drawing path gates on. Also requires the hud to
--exist: an armed flag with no panel behind it must not publish tools.
function m.arm.Armed()
    return m.arm.on and m.markupHud ~= nil and m.markupHud.valid
end

--Arm or disarm, and tell the panel. The `markuparmed` event already drives
--the armed dot on the mode tab; firing `think` re-runs the tool registration
--paths, which are gated on m.arm.Armed() and so register or unregister the
--engine's custom map tools as the state flips.
function m.arm.Set(on)
    on = on == true

    --A preset palette entry has no wall ASSET behind it until something
    --materializes one (MaterializeEntry): the default palette is six preset
    --tokens with no guids, and the panel AUTO-selects entry 1 when it builds
    --- a path that never goes through SelectChip. On a map whose palette had
    --never been touched, the panel therefore came up looking completely ready
    --- Walls tab active, chip lit, tool lit, armed - while
    --GetMarkupSelectedWall found no asset behind the selection, published
    --nil, and so left the engine's building tools inactive: every click on
    --the map fell through to token selection and markup was silently dead
    --until the user happened to click a wall type chip. Arming is the
    --explicit "I want to draw this", exactly like pressing the chip, so it
    --is the right moment to make the selection real.
    --
    --Deliberately BEFORE the no-change early return: arm state is module
    --state and outlives any one panel instance, so a rebuilt panel can arrive
    --already armed, and Set(true) would return without ever reaching this.
    --Deliberately NOT at panel-build time either: content is built for
    --panels nobody has shown yet (a restored dock layout), and that must not
    --create wall assets and write the map's palette setting behind the
    --user's back.
    if on and m.mode == "walls" and m.MaterializeSelectedWall ~= nil then
        m.MaterializeSelectedWall()
    end

    --Arming is a CLAIM on the map: exactly one map tool is live at a time,
    --and claiming puts every other one down (see
    --DMHub Core UI/MapToolArbiter.lua). Without this, THIS panel staying
    --armed behind another tab silently outranked whatever the user armed
    --next - the engine breaks a tie between two armed tools by priority, so
    --the Effects editor drew WALLS.
    --
    --Deliberately BEFORE the no-change early return, for the same reason the
    --materialize above is: arm state is module state that outlives any one
    --panel instance, so a rebuilt panel can arrive already armed and Set(true)
    --would return without ever reaching this.
    if on then
        MapTools.Claim("mapmarkup")
    else
        MapTools.Release("mapmarkup")
    end

    if m.arm.on == on then
        return
    end
    m.arm.on = on
    if m.markupHud ~= nil and m.markupHud.valid then
        m.markupHud:FireEventTree("markuparmed", on)
        --the tool strip lights its tool only while live (see refreshtools),
        --so every arm change has to repaint it...
        m.markupHud:FireEventTree("refreshtools")
        --...and think re-runs the registration paths, which are gated on
        --m.arm.Armed() and so hand the engine's custom map tools out or take
        --them back as the state flips.
        m.markupHud:FireEventTree("think")
    end
end

--Somebody else armed a map tool: put this one down. m.arm.Set does the
--visible half (the armed dot on the mode tab goes out, the tool strip
--unlights, the custom map tools unregister on the next think); dropping focus
--puts the host's focus highlight out with it, and is what lets the next click
--on this panel re-arm - both hosts skip the panelFocused nudge while focus is
--already here.
MapTools.Register("mapmarkup", function()
    m.arm.Set(false)

    if m.markupHud ~= nil and m.markupHud.valid and gui.ChildHasFocus(m.markupHud) then
        gui.SetFocus(nil)
    end
end)

--Draw mode, independent of which wall type is selected: false draws thin
--walls (barriers on a tile boundary), true draws area-filling solid blocks
--of the SAME wall type. Toggled by the Thin/Solid control by the tool strip.
m.solidMode = false

--Zones mode state: the selected zone-type chip (index into
--m.zonePaletteEntries), the active zone tool, and the target zone new
--strokes merge into (nil = auto-pick / create by selected type).
m.zonePaletteEntries = {}
m.zoneSelectedType = 1
m.zoneToolId = "zonerect"
m.zoneTargetId = nil

--Footsteps mode state: the selected surface family (AudioSurfaceTypes id)
--and the active paint tool.
m.footstepSelected = 1
m.footstepToolId = "footrect"

local function PropsSupported()
    local supported = false
    pcall(function()
        supported = dmhub.supportsObjectEditingFilter == true
    end)
    return supported
end

--Props mode's half of the engine's object-editing filter poll. Non-nil makes
--objects tagged with the returned keyword visible/selectable/draggable (and
--everything else inert) - so it must be non-nil only while the Props tab is
--focused. Every markup prop matches, whatever its type: with a data-driven
--roster, scoping interaction to just the selected chip would make the rest
--of the DM's placed props invisible AND inert, which reads as "my props
--vanished". Clicking a prop selects its palette chip instead (see
--MarkupHandleObjectsSelected).
local function GetMarkupObjectEditingFilter()
    if m.mode ~= "props" then
        return nil
    end

    if not m.arm.Armed() then
        return nil
    end

    return K.MARKUP_PROP_KEYWORD
end

--The placement ghost needs an engine build beyond the object-editing filter:
--the object tool must show its preview WITHOUT placing on click while the
--filter is active (this panel owns placement, so the engine placing too
--would drop a second unconfigured copy), keep props mouseoverable while the
--preview is armed, and expose the preview's snapped position. Probe
--property, same pattern as supportsObjectEditingFilter.
local function GhostSupported()
    local supported = false
    pcall(function()
        supported = editor.supportsObjectPlacementPreview == true
    end)
    return supported
end

--Props mode's half of the engine's palette-selection poll
--(dmhub.GetSelectedObject): a non-nil object assetid makes the object tool
--show a placement preview ('ghost') at the cursor, exactly like the Objects
--panel's palette. Published only while the Props tab is armed for PLACEMENT:
--focused, the ghost-capable engine build, a type selected, and no placed
--prop bound to the editors (while editing, clicks should select/drag - and
--pre-ghost builds clear the object selection every frame while a palette id
--is published). The engine indexes the returned id straight into the object
--asset table, so never publish an id whose asset is missing.
local function GetMarkupSelectedObject()
    if GetMarkupObjectEditingFilter() == nil then
        return nil
    end
    if not GhostSupported() then
        return nil
    end
    if m.props.selected == nil or m.props.editingId ~= nil then
        return nil
    end
    if assets:GetObjectNode(m.props.selected) == nil then
        return nil
    end
    return m.props.selected
end

--Props mode's half of the engine's object-selection callback: when the Props
--tab is focused and everything selected is a markup prop, bind the selection
--to the panel's property editors and suppress the generic object-properties
--dialog. The engine passes LuaObjectInstance userdata (not id strings,
--despite the stub). Returns true when the selection was consumed.
local function MarkupHandleObjectsSelected(objects)
    if m.mode ~= "props" then
        return false
    end

    if not m.arm.Armed() then
        return false
    end

    local valid = {}
    for _,obj in ipairs(objects or {}) do
        if obj.valid then
            valid[#valid+1] = obj
        end
    end

    if #valid == 0 then
        --selection cleared: unbind our editors, but let the generic dialog
        --see the clear too in case it is open.
        if m.props.editingId ~= nil then
            m.props.editingId = nil
            m.props.editingIds = nil
            m.markupHud:FireEventTree("refreshprops")
        end
        return false
    end

    for _,obj in ipairs(valid) do
        local kw = obj.keywords
        if kw == nil or kw[K.MARKUP_PROP_KEYWORD] == nil then
            return false
        end
    end

    --selecting an existing prop while a teleporter pair is half-placed means
    --the user moved on without placing the partner: abort (deletes the first
    --teleporter). Selecting the pending teleporter itself keeps the pair
    --pending - clicking the thing you just placed should not destroy it.
    if m.props.pendingPartnerId ~= nil then
        local selectedPending = false
        for _,obj in ipairs(valid) do
            if obj.objid == m.props.pendingPartnerId then
                selectedPending = true
                break
            end
        end
        if not selectedPending then
            MM.AbortPendingTeleporterPair()
        end
    end

    --bind the WHOLE selection: the first prop is the primary (single-value
    --reads come from it), and property edits apply to every bound prop.
    m.props.editingId = valid[1].objid
    local ids = {}
    for _,obj in ipairs(valid) do
        ids[#ids+1] = obj.objid
    end
    m.props.editingIds = ids

    --select the clicked prop's palette chip too, so the property editors
    --and the placement type follow what the DM is looking at. A prop whose
    --asset is no longer in the palette (untagged, or a legacy prop from the
    --preset-roster build) binds to the editors without moving the selection.
    local assetid = valid[1].assetid
    if assetid ~= nil and assetid ~= m.props.selected then
        for _,node in ipairs(MM.MarkupPropAssets()) do
            if node.id == assetid then
                m.props.selected = assetid
                break
            end
        end
    end

    --Teleporters select as a UNIT: selecting one end pulls its same-floor
    --partner into the engine selection, so both ends highlight, drag
    --together, and the engine's Delete key removes both. Cross-floor
    --partners are deliberately NOT co-selected: the object tool's drag and
    --delete paths assume current-floor objects (dragging would blind-move
    --the invisible off-floor end, and DeleteObjects indexes
    --currentFloor.objects), and the selection callback stamps every entry
    --with currentFloorId. Idempotent - setting editorSelection on an
    --already-selected object is a no-op - so the next-frame re-fire of this
    --handler with both ends selected converges instead of recursing.
    local firstComp = valid[1]:GetComponent("Teleporter")
    if firstComp ~= nil then
        local link = MM.GetComponentFieldValue(firstComp, "linkName")
        if link ~= nil and trim(tostring(link)) ~= "" then
            for _,entry in ipairs(MM.MarkupTeleportersOnMap()) do
                if MM.LinkKey(entry.link) == MM.LinkKey(link)
                    and entry.obj.objid ~= valid[1].objid
                    and entry.floorid == valid[1].floorid then
                    entry.obj.editorSelection = true
                end
            end
        end
    end

    m.markupHud:FireEventTree("refreshprops")
    return true
end

--Elevation editing is a patron feature: ElevationPanel.lua only registers the
--Elevation Editor dock panel when patronTier > 0, and the engine returns a nil
--heightEditingInfo for non-patrons even while isHeightEditingEnabled is true.
--Gate our clone the same way so we can never put the engine in that state.
local function ElevationSupported()
    return dmhub.patronTier > 0
end

--Elevation mode's half of the engine's height-editing poll. The engine calls
--dmhub.GetHeightEditingInfo every frame; non-nil turns height painting on and
--carries the brush parameters. Same shape (and the same settings) as
--ElevationPanel.lua's version, focus-gated the same way -- the wrapper at the
--bottom of this file chains the two so whichever panel has focus wins.
local function GetMarkupHeightEditingInfo()
    if m.mode ~= "elevation" or not ElevationSupported() then
        return nil
    end

    if not m.arm.Armed() then
        return nil
    end

    return {
        height = dmhub.GetSettingValue("heightmap:height"),
        directional = dmhub.GetSettingValue("heightmap:gradient") == "slope",
        opacity = dmhub.GetSettingValue("heightmap:opacity"),
        blend = dmhub.GetSettingValue("heightmap:blend"),
    }
end

local function GetMarkupSelectedWall()
    if m.markupHud == nil or not m.markupHud.valid then
        return nil
    end

    --The dock ancestor is optional: panel content can be hosted outside the
    --dock (e.g. the document system's PanelDocument bridge), so only use it
    --for the highlight, never as a gate.
    local dockPanel = m.markupHud:FindParentWithClass("dockablePanel")

    --erase/delete are custom map tools, not wall drawing: publish no wall so
    --the engine building tools stay inactive while they run.
    if m.mode ~= "walls" or m.toolId == "erase" or m.toolId == "delete" or not m.arm.Armed() then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    local entry = m.paletteEntries[m.selectedIndex or 0]

    --Solid draw mode publishes no wall: solid strokes run through custom map
    --tools + ExecutePolygonOperation{solid=true}, not the engine building
    --tools. Publishing here would let the building tools draw THIN walls
    --while the panel is in Solid mode.
    --EXCEPT for the Points tool: it EDITS existing geometry (solid block
    --outlines included, with an engine build) rather than drawing, so its
    --activation token can't draw anything - and publishing it is also what
    --keeps GetWallPointsInvisibleOnly scoping the tool away from art walls.
    --Gated on the engine tool actually being "points", like the fallback
    --below, so the exception can never leak into wall drawing.
    if m.solidMode and not (m.toolId == "points" and dmhub.GetSettingValue("buildingtool") == "points") then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    local guid = nil
    if entry ~= nil then
        guid = entry.guid
    end

    if guid == nil or assets.walls[guid] == nil then
        --The points tool edits existing walls, so the published wall is only
        --the engine's activation token: fall back to the base invisible wall
        --when the palette selection is unmaterialized (fresh preset chips have
        --no asset until first clicked). Gated on the engine tool actually
        --being "points" so the fallback can never leak into wall DRAWING.
        if m.toolId == "points" and dmhub.GetSettingValue("buildingtool") == "points" then
            if assets.walls[K.BASE_INVISIBLE_WALL_ID] ~= nil then
                guid = K.BASE_INVISIBLE_WALL_ID
            end
        end
    end

    if guid == nil or assets.walls[guid] == nil then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    if dockPanel ~= nil then
        dockPanel:SetClass("highlightPanel", true)
    end
    return guid
end

--============================================================================
--Engine hook chaining. The Building editor (Terrain.lua, loaded before this
--module) assigns dmhub.GetSelectedWall / dmhub.GetBuildingSolid; we wrap
--them so whichever panel has focus wins. dmhub.GetWallHeight needs no wrap:
--it reads the building:specifywallheight settings, which our height stepper
--drives directly.
--============================================================================

--MapMarkupHooks survives reloads of this file. If dmhub.GetSelectedWall is
--already our own wrapper (this file reloaded without Terrain.lua reloading),
--unwrap to the function we chained to instead of chaining a stale wrapper.
--rawget: reading an undeclared global errors in the DMHub Lua runtime.
--
--GOTCHA: each hook read can also be NIL on reload, even though the base half
--(Terrain.lua etc.) was never unloaded. The engine's hook slots record the
--mod that last wrote them, and unloading a mod nulls every slot it last
--wrote (CodeMod.OnUnload -> LuaInterface.UnloadMod). Chaining makes THIS mod
--the last writer of every hook it wraps, so reloading this file first nulls
--the whole chain - including the base half owned by another mod. When a
--hook reads nil, resurrect the remembered prior instead of chaining to nil
--(and never overwrite a remembered prior with nil): the base closure from
--the original load is still live and correct, since its own file was not
--reloaded.
MapMarkupHooks = rawget(_G, "MapMarkupHooks") or {}

gs.priorGetSelectedWall = dmhub.GetSelectedWall
if gs.priorGetSelectedWall == MapMarkupHooks.getSelectedWallWrapper or gs.priorGetSelectedWall == nil then
    gs.priorGetSelectedWall = MapMarkupHooks.priorGetSelectedWall
end
MapMarkupHooks.priorGetSelectedWall = gs.priorGetSelectedWall
MapMarkupHooks.getSelectedWallWrapper = function()
    local result = nil
    if gs.priorGetSelectedWall ~= nil then
        result = gs.priorGetSelectedWall()
    end
    if result ~= nil then
        return result
    end
    return GetMarkupSelectedWall()
end
dmhub.GetSelectedWall = MapMarkupHooks.getSelectedWallWrapper

gs.priorGetBuildingSolid = dmhub.GetBuildingSolid
if gs.priorGetBuildingSolid == MapMarkupHooks.getBuildingSolidWrapper or gs.priorGetBuildingSolid == nil then
    gs.priorGetBuildingSolid = MapMarkupHooks.priorGetBuildingSolid
end
MapMarkupHooks.priorGetBuildingSolid = gs.priorGetBuildingSolid
MapMarkupHooks.getBuildingSolidWrapper = function()
    --When the markup panel is driving wall drawing, never draw solid blocks,
    --even if the Building editor was left in Solid mode. (The Building
    --editor's solid flag is not focus-gated.)
    if GetMarkupSelectedWall() ~= nil then
        return false
    end
    if gs.priorGetBuildingSolid ~= nil then
        return gs.priorGetBuildingSolid()
    end
    return false
end
dmhub.GetBuildingSolid = MapMarkupHooks.getBuildingSolidWrapper

--Height editing. ElevationPanel.lua (DMHub Core Panels, loaded before this
--module) assigns dmhub.GetHeightEditingInfo, gated on its own dock panel
--having focus; we chain so whichever of the two panels has focus wins. Our
--half is nil unless this panel is focused AND in Elevation mode, so the
--Elevation Editor keeps working exactly as before.
gs.priorGetHeightEditingInfo = dmhub.GetHeightEditingInfo
if gs.priorGetHeightEditingInfo == MapMarkupHooks.getHeightEditingInfoWrapper or gs.priorGetHeightEditingInfo == nil then
    gs.priorGetHeightEditingInfo = MapMarkupHooks.priorGetHeightEditingInfo
end
MapMarkupHooks.priorGetHeightEditingInfo = gs.priorGetHeightEditingInfo
MapMarkupHooks.getHeightEditingInfoWrapper = function()
    local result = GetMarkupHeightEditingInfo()
    if result ~= nil then
        return result
    end
    if gs.priorGetHeightEditingInfo ~= nil then
        return gs.priorGetHeightEditingInfo()
    end
    return nil
end
dmhub.GetHeightEditingInfo = MapMarkupHooks.getHeightEditingInfoWrapper

--Invisible-only scoping for the Edit Points tool. The engine polls
--dmhub.GetWallPointsInvisibleOnly while the points tool is active; returning
--true restricts the tool to walls with invisible assets, so vertex editing
--driven from this panel cannot disturb visible art walls (those belong to
--the Building editor - design ledger #11, same rule as erasing).
--pcall on read AND write: this hook needs an engine build. On a stale engine
--the property doesn't exist, reads/assignments raise, and the tool simply
--edits all walls like the Building editor's version does.
gs.priorGetWallPointsInvisibleOnly = nil
pcall(function()
    gs.priorGetWallPointsInvisibleOnly = dmhub.GetWallPointsInvisibleOnly
end)
if gs.priorGetWallPointsInvisibleOnly == MapMarkupHooks.getWallPointsInvisibleOnlyWrapper or gs.priorGetWallPointsInvisibleOnly == nil then
    gs.priorGetWallPointsInvisibleOnly = MapMarkupHooks.priorGetWallPointsInvisibleOnly
end
MapMarkupHooks.priorGetWallPointsInvisibleOnly = gs.priorGetWallPointsInvisibleOnly
MapMarkupHooks.getWallPointsInvisibleOnlyWrapper = function()
    --true only while THIS panel is the reason the points tool is active: the
    --shared tool setting is "points" and our (focus-gated) wall selection is
    --published. When the Building editor drives the tool instead, its own
    --selection wins the GetSelectedWall chain and we defer.
    if dmhub.GetSettingValue("buildingtool") == "points" and GetMarkupSelectedWall() ~= nil then
        return true
    end
    if gs.priorGetWallPointsInvisibleOnly ~= nil then
        return gs.priorGetWallPointsInvisibleOnly()
    end
    return false
end
pcall(function()
    dmhub.GetWallPointsInvisibleOnly = MapMarkupHooks.getWallPointsInvisibleOnlyWrapper
end)

--Object-editing filter for Props mode. The engine polls
--dmhub.GetObjectEditingFilter every frame; a non-nil keyword makes only
--matching (markup prop) objects visible/selectable/draggable and everything
--else inert to object selection. This hook is owned solely by this panel, so
--no chaining - but it needs an engine build: pcall on assignment so a stale
--engine (property does not exist -> assignment raises) leaves Props gated
--off (see PropsSupported).
MapMarkupHooks.getObjectEditingFilterWrapper = function()
    return GetMarkupObjectEditingFilter()
end
pcall(function()
    dmhub.GetObjectEditingFilter = MapMarkupHooks.getObjectEditingFilterWrapper
end)

--Object selection. ObjectPropertiesDialog (DMHub Core Panels, loaded before
--this module) assigns dmhub.ObjectsSelected to pop the generic object
--properties dialog; chain so markup props selected while the Props tab is
--focused bind to this panel's editors instead of opening that dialog.
gs.priorObjectsSelected = dmhub.ObjectsSelected
if gs.priorObjectsSelected == MapMarkupHooks.objectsSelectedWrapper or gs.priorObjectsSelected == nil then
    gs.priorObjectsSelected = MapMarkupHooks.priorObjectsSelected
end
MapMarkupHooks.priorObjectsSelected = gs.priorObjectsSelected
MapMarkupHooks.objectsSelectedWrapper = function(objects)
    if MarkupHandleObjectsSelected(objects) then
        return
    end
    if gs.priorObjectsSelected ~= nil then
        gs.priorObjectsSelected(objects)
    end
end
dmhub.ObjectsSelected = MapMarkupHooks.objectsSelectedWrapper

--Escape. SheetHud.CancelFocus routes Escape on a sticky-focused panel into
--dmhub.CancelEditing; chain so Escape aborts a half-placed teleporter pair
--(deleting the first teleporter) and consumes the press. Objects.lua (loaded
--before this module) assigns the base handler, which clears object selection.
--Focus loss is the fallback abort (the props think loop), so nothing is lost
--if some other escape consumer wins.
gs.priorCancelEditing = dmhub.CancelEditing
if gs.priorCancelEditing == MapMarkupHooks.cancelEditingWrapper or gs.priorCancelEditing == nil then
    gs.priorCancelEditing = MapMarkupHooks.priorCancelEditing
end
MapMarkupHooks.priorCancelEditing = gs.priorCancelEditing
MapMarkupHooks.cancelEditingWrapper = function(sheet)
    if m.props.pendingPartnerId ~= nil and m.mode == "props" and m.arm.Armed() then
        MM.AbortPendingTeleporterPair()
        return true
    end
    --ESCAPE PUTS THE TOOL DOWN. Ordered after the teleporter abort (that is
    --the more specific half-finished thing to back out of) and before every
    --other consumer: while a markup tool is live, Escape means "stop
    --drawing", not "clear the selection" or "close the window". Consuming it
    --is what stops the window's own escape handler closing the panel out from
    --under a single keypress.
    if m.arm.Armed() then
        --m.arm.Set repaints the strip and unregisters the map tools.
        m.arm.Set(false)
        --Drop focus with the tool, exactly like panelEscape does: both
        --hosts skip the panelFocused nudge while focus is already on the
        --panel, so keeping focus here would mean the next click on the
        --panel does NOT re-arm - the tool reads as permanently stuck down
        --(observed: placed markup props unreachable after Escape).
        if m.markupHud ~= nil and m.markupHud.valid and gui.ChildHasFocus(m.markupHud) then
            gui.SetFocus(nil)
        end
        return true
    end
    if gs.priorCancelEditing ~= nil then
        return gs.priorCancelEditing(sheet)
    end
    return false
end
dmhub.CancelEditing = MapMarkupHooks.cancelEditingWrapper

--Palette selection for the placement ghost. Objects.lua (loaded before this
--module) assigns dmhub.GetSelectedObject for the Objects panel's palette;
--the engine polls it every frame and shows a placement preview for the
--returned object assetid. Chain so the props tab's armed type publishes its
--asset; our half is focus- and mode-gated, so the Objects panel keeps
--working exactly as before.
gs.priorGetSelectedObject = dmhub.GetSelectedObject
if gs.priorGetSelectedObject == MapMarkupHooks.getSelectedObjectWrapper or gs.priorGetSelectedObject == nil then
    gs.priorGetSelectedObject = MapMarkupHooks.priorGetSelectedObject
end
MapMarkupHooks.priorGetSelectedObject = gs.priorGetSelectedObject
MapMarkupHooks.getSelectedObjectWrapper = function()
    local result = GetMarkupSelectedObject()
    if result ~= nil then
        return result
    end
    if gs.priorGetSelectedObject ~= nil then
        return gs.priorGetSelectedObject()
    end
    return nil
end
dmhub.GetSelectedObject = MapMarkupHooks.getSelectedObjectWrapper


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.ElevationSupported = ElevationSupported
MM.GetMarkupHeightEditingInfo = GetMarkupHeightEditingInfo
MM.GetMarkupObjectEditingFilter = GetMarkupObjectEditingFilter
MM.GetMarkupSelectedObject = GetMarkupSelectedObject
MM.GetMarkupSelectedWall = GetMarkupSelectedWall
MM.GhostSupported = GhostSupported
MM.MarkupHandleObjectsSelected = MarkupHandleObjectsSelected
MM.PropsSupported = PropsSupported
