local mod = dmhub.GetModLoading()

--Map Markup: markup props - the prop asset roster, teleporter links and the
--teleporter arrow overlay.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--Props mode: invisible gameplay objects placed on the map. The palette is
--DATA-DRIVEN: every object asset tagged with the "markup" keyword (the
--Keywords field in the object's properties in the Objects panel) is a prop
--type, shown under the asset's own name and art. Placing one spawns an
--instance of that asset, stamps "markup" onto the instance's Core keywords,
--and locks it so it is inert everywhere except this panel. The engine's
--object-editing filter (dmhub.GetObjectEditingFilter, needs an engine build)
--makes every markup prop visible and draggable while the Props tab is
--focused. The property editors are component-aware: an asset with a Light
--component gets the light editing UI (color/brightness/radius/flicker).
--============================================================================

--The tag that makes an object asset a prop type, and the Core keyword the
--engine filter + selection handler match on placed instances.
K.MARKUP_PROP_KEYWORD = "markup"

--Object assets tagged "markup" form the props palette. GetObjectsWithKeyword
--matches the asset's keywords exactly (case-insensitive) but does NOT skip
--deleted (hidden) assets or folders, so filter those here. Sorted by name so
--the chip order is stable.
local function MarkupPropAssets()
    local result = {}
    for _,node in ipairs(assets:GetObjectsWithKeyword(K.MARKUP_PROP_KEYWORD)) do
        if (not node.isfolder) and (not node.hidden) then
            result[#result+1] = node
        end
    end
    table.sort(result, function(a, b)
        local an = string.lower(tostring(a.description or ""))
        local bn = string.lower(tostring(b.description or ""))
        if an == bn then
            return a.id < b.id
        end
        return an < bn
    end)
    return result
end

--Find a component on an object ASSET node by its display name ("Light",
--"Core", "Mount", ...) - node.components is keyed by component guid, and
--comp.name carries the component type's description.
local function NodeGetComponent(node, componentName)
    local comps = node.components
    if comps == nil then
        return nil
    end
    for _,comp in pairs(comps) do
        if comp.name == componentName then
            return comp
        end
    end
    return nil
end

--Read a component field's live value (component.fields carries the engine's
--reflected descriptors). Works on asset-node components and placed-instance
--components alike.
local function GetComponentFieldValue(comp, id)
    for _,f in ipairs(comp.fields) do
        if f.id == id then
            return f.currentValue
        end
    end
    return nil
end

--Props mode state: the selected prop type (assetid of a palette chip), the
--placed prop currently bound to the property editors (clicked on the map),
--and per-asset session defaults stamped onto newly placed props. Defaults
--are seeded lazily from the asset's own component values and then track the
--last values edited, so consecutive placements inherit them.
--
--Teleporter state: teleLink is the link name the NEXT pair will use
--(auto-generated unique when nil/blank; the user can edit it), teleStyle the
--style ("teleport"/"stairwell") stamped on new pairs and kept identical
--across both ends of a pair. pendingPartnerId/pendingLink/pendingFloorId
--track a placed first teleporter awaiting its partner: the next placement
--completes the pair, and ANY abort (Escape, chip/tab switch, focus loss,
--selecting something else) deletes the first one again.
m.props = {
    selected = nil,
    editingId = nil,    --primary bound prop (single-value reads)
    editingIds = nil,   --the FULL bound selection; property edits hit all of them
    defaults = {},
    --text defaults live in their own table: Light and Text both have a
    --"color" field, so one shared per-asset table would cross-contaminate.
    textDefaults = {},

    teleLink = nil,
    teleStyle = "teleport",
    pendingPartnerId = nil,
    pendingLink = nil,
    pendingFloorId = nil,
}

--The engine pairs teleporters by trimmed, lowercased linkName
--(ObjectComponentTeleporter.FindPartner); mirror that when comparing.
local function LinkKey(name)
    return string.lower(trim(tostring(name or "")))
end

--Every markup teleporter prop on the current map (all floors): entries of
--{obj, comp, link, floorid}.
local function MarkupTeleportersOnMap()
    local result = {}
    local map = game.currentMap
    if map == nil then
        return result
    end
    for _,floor in ipairs(map.floors or {}) do
        for _,obj in pairs(floor.objects or {}) do
            local kw = obj.keywords
            if kw ~= nil and kw[K.MARKUP_PROP_KEYWORD] ~= nil then
                local comp = obj:GetComponent("Teleporter")
                if comp ~= nil then
                    result[#result+1] = {
                        obj = obj,
                        comp = comp,
                        link = tostring(GetComponentFieldValue(comp, "linkName") or ""),
                        floorid = obj.floorid,
                    }
                end
            end
        end
    end
    return result
end

--Generate the next free "teleporterN" name. Uniqueness is checked against
--EVERY teleporter component on the current map (markup or not - a clash with
--an art teleporter would mis-pair just the same). Cross-map clashes are not
--checked (no Lua access to other maps' teleporter indexes), but the engine
--prefers a same-map partner, so a local pair always wins.
local function GenerateTeleporterLinkName()
    local used = {}
    local map = game.currentMap
    if map ~= nil then
        for _,floor in ipairs(map.floors or {}) do
            for _,obj in pairs(floor.objects or {}) do
                local comp = obj:GetComponent("Teleporter")
                if comp ~= nil then
                    used[LinkKey(GetComponentFieldValue(comp, "linkName"))] = true
                end
            end
        end
    end
    local n = 1
    while used["teleporter" .. n] ~= nil do
        n = n + 1
    end
    return "teleporter" .. n
end

--The link name the next pair will use, generating a fresh unique one when
--none is set (first use, or after a pair was completed).
local function CurrentTeleporterLinkName()
    if m.props.teleLink == nil or trim(m.props.teleLink) == "" then
        m.props.teleLink = GenerateTeleporterLinkName()
    end
    return m.props.teleLink
end

--Abort a half-placed teleporter pair: delete the first teleporter and clear
--the pending state. Safe to call when nothing is pending.
local function AbortPendingTeleporterPair()
    local pendingId = m.props.pendingPartnerId
    if pendingId == nil then
        return
    end
    local pendingFloorId = m.props.pendingFloorId
    m.props.pendingPartnerId = nil
    m.props.pendingLink = nil
    m.props.pendingFloorId = nil

    local floor = nil
    if pendingFloorId ~= nil then
        floor = game.GetFloor(pendingFloorId)
    end
    if floor == nil then
        floor = game.currentFloor
    end
    if floor ~= nil then
        local obj = floor:GetObject(pendingId)
        if obj ~= nil and obj.valid then
            obj:Destroy()
        end
    end

    if m.markupHud ~= nil and m.markupHud.valid then
        m.markupHud:FireEventTree("refreshprops")
    end
end

--The props engine half (the object-editing filter) needs an engine build. A
--stale build shows a muted message instead of the props UI - placing props it
--cannot show or manipulate would strand them invisibly on the map.
--
--GOTCHA: the callback itself CANNOT be probed. Unknown properties on the dmhub
--bridge read as nil AND accept writes silently (verified live 2026-07-28), so
--both "read it" and "assign it, read it back" succeed on a stale engine. Hence
--the dedicated supportsObjectEditingFilter probe property, the same pattern as
--floor.supportsSolidOperations. pcall + == true: nil on older builds.
--============================================================================
--Teleporter pair arrows: whenever the Props tab is armed (same gate as the
--object-editing filter, so arrows show exactly when the teleporter markers
--themselves are visible), every markup teleporter pair with both ends on the
--current floor gets a double-headed arrow drawn between them out of
--HighlightLine markers (shaft + two head strokes per end). Driven by a
--self-rescheduling poll rather than panel think so the arrows reliably clear
--when the panel is defocused, hidden, or closed - and so dragging an end
--re-routes the arrow within half a second.
--============================================================================

--Reload safety: HighlightLine markers are engine objects that survive a Lua
--reload, so the live handles are shared through MapMarkupHooks and stale
--ones from a previous load of this file are destroyed here.
if MapMarkupHooks.teleporterArrowHandles ~= nil then
    for _,handle in ipairs(MapMarkupHooks.teleporterArrowHandles) do
        pcall(function() handle:Destroy() end)
    end
end
m.teleporterArrowHandles = {}
MapMarkupHooks.teleporterArrowHandles = m.teleporterArrowHandles
m.teleporterArrowKey = nil

--The object pairs currently drawn as arrows ({aObjid, bObjid, key=linkkey}
--each) plus the floor they were computed for: the FAST poll re-reads just
--these objects' positions so a dragged end re-routes its arrow in real time,
--while the slow poll owns membership (pairs appearing/disappearing).
m.teleporterArrowPairIds = {}
m.teleporterArrowFloorId = nil
m.teleporterArrowFastActive = false

local function ClearTeleporterArrows()
    for _,handle in ipairs(m.teleporterArrowHandles) do
        pcall(function() handle:Destroy() end)
    end
    for i = #m.teleporterArrowHandles, 1, -1 do
        m.teleporterArrowHandles[i] = nil
    end
    m.teleporterArrowKey = nil
end

K.ARROW_COLOR = "#7fd4ff"
K.ARROW_HEAD_LENGTH = 0.45
K.ARROW_HEAD_ANGLE = 0.45  --radians, ~26 degrees off the shaft
K.ARROW_END_INSET = 0.35   --pull the ends off the teleporter markers

local function AddArrowLine(floorIndex, x1, y1, x2, y2)
    local handle = dmhub.HighlightLine{
        color = K.ARROW_COLOR,
        a = core.Vector2(x1, y1),
        b = core.Vector2(x2, y2),
        floorIndex = floorIndex,
        terrainParallax = true,
    }
    if handle ~= nil then
        m.teleporterArrowHandles[#m.teleporterArrowHandles+1] = handle
    end
end

local function RotateVec(x, y, cosA, sinA)
    return x*cosA - y*sinA, x*sinA + y*cosA
end

--A double-headed arrow between two teleporters (both directions work).
local function AddPairArrow(floorIndex, x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.6 then
        --ends on top of each other: an arrow would be unreadable scribble.
        return
    end
    local ux = dx/len
    local uy = dy/len
    if len > 2*K.ARROW_END_INSET + 0.5 then
        x1 = x1 + ux*K.ARROW_END_INSET
        y1 = y1 + uy*K.ARROW_END_INSET
        x2 = x2 - ux*K.ARROW_END_INSET
        y2 = y2 - uy*K.ARROW_END_INSET
    end

    AddArrowLine(floorIndex, x1, y1, x2, y2)

    local cosA = math.cos(K.ARROW_HEAD_ANGLE)
    local sinA = math.sin(K.ARROW_HEAD_ANGLE)
    --head at (x2,y2): strokes angled back along the shaft.
    local hx, hy = RotateVec(-ux, -uy, cosA, sinA)
    AddArrowLine(floorIndex, x2, y2, x2 + hx*K.ARROW_HEAD_LENGTH, y2 + hy*K.ARROW_HEAD_LENGTH)
    hx, hy = RotateVec(-ux, -uy, cosA, -sinA)
    AddArrowLine(floorIndex, x2, y2, x2 + hx*K.ARROW_HEAD_LENGTH, y2 + hy*K.ARROW_HEAD_LENGTH)
    --head at (x1,y1): strokes angled forward along the shaft.
    hx, hy = RotateVec(ux, uy, cosA, sinA)
    AddArrowLine(floorIndex, x1, y1, x1 + hx*K.ARROW_HEAD_LENGTH, y1 + hy*K.ARROW_HEAD_LENGTH)
    hx, hy = RotateVec(ux, uy, cosA, -sinA)
    AddArrowLine(floorIndex, x1, y1, x1 + hx*K.ARROW_HEAD_LENGTH, y1 + hy*K.ARROW_HEAD_LENGTH)
end

local function UpdateTeleporterArrows()
    --same gate as the engine filter: props tab focused. When it goes nil the
    --teleporter markers themselves disappear, so the arrows must too.
    local show = MM.GetMarkupObjectEditingFilter() ~= nil and game.currentFloor ~= nil
    if not show then
        if #m.teleporterArrowHandles > 0 or m.teleporterArrowKey ~= nil then
            ClearTeleporterArrows()
        end
        m.teleporterArrowPairIds = {}
        return
    end

    --group markup teleporters on the CURRENT floor by link key; a group of
    --two or more gets an arrow between consecutive members (normal case: a
    --pair and one arrow). Cross-floor pairs draw nothing - there is no
    --sensible line to draw to another floor.
    local currentFloorId = game.currentFloorId
    local groups = {}
    local order = {}
    for _,entry in ipairs(MarkupTeleportersOnMap()) do
        local key = LinkKey(entry.link)
        if key ~= "" and entry.floorid == currentFloorId then
            local group = groups[key]
            if group == nil then
                group = {}
                groups[key] = group
                order[#order+1] = key
            end
            group[#group+1] = entry
        end
    end
    table.sort(order)

    local floorIndex = game.currentFloorIndex
    local arrows = {}
    local pairIds = {}
    local keyParts = { tostring(floorIndex) }
    for _,key in ipairs(order) do
        local group = groups[key]
        if #group >= 2 then
            table.sort(group, function(a, b)
                return tostring(a.obj.objid) < tostring(b.obj.objid)
            end)
            for i = 1, #group - 1 do
                local a = group[i].obj
                local b = group[i+1].obj
                arrows[#arrows+1] = { a.x, a.y, b.x, b.y }
                pairIds[#pairIds+1] = { a.objid, b.objid, key = key }
                keyParts[#keyParts+1] = string.format("%s:%.2f,%.2f-%.2f,%.2f", key, a.x, a.y, b.x, b.y)
            end
        end
    end

    --hand the drawn membership to the fast poll (position tracking during
    --drags); recorded even when nothing changed so the first slow pass after
    --arming primes it.
    m.teleporterArrowPairIds = pairIds
    m.teleporterArrowFloorId = game.currentFloorId

    --rebuild only when an endpoint/pair actually changed; the markers are
    --parallax-baked so camera movement needs no rebuild.
    local arrowKey = table.concat(keyParts, ";")
    if arrowKey == m.teleporterArrowKey then
        return
    end

    ClearTeleporterArrows()
    for _,arrow in ipairs(arrows) do
        AddPairArrow(floorIndex, arrow[1], arrow[2], arrow[3], arrow[4])
    end
    m.teleporterArrowKey = arrowKey
end

--The FAST poll: while the Props tab is armed and arrows are on screen, track
--the drawn pairs' positions at 20Hz so dragging a teleporter end re-routes
--its arrow in real time (the engine updates the dragged object's data pos
--every frame mid-drag). Membership is the slow poll's job - this only moves
--EXISTING arrows, and hands back to the slow poll (which restarts it) the
--moment the tab disarms, the floor changes, or the arrows empty.
local function TeleporterArrowFastPoll()
    if mod.unloaded then
        m.teleporterArrowFastActive = false
        return
    end

    local keepRunning = false
    local ok, err = pcall(function()
        if #m.teleporterArrowPairIds == 0 or MM.GetMarkupObjectEditingFilter() == nil then
            return
        end
        if game.currentFloorId ~= m.teleporterArrowFloorId then
            return
        end
        local floor = game.currentFloor
        if floor == nil then
            return
        end
        keepRunning = true

        local floorIndex = game.currentFloorIndex
        local arrows = {}
        local keyParts = { tostring(floorIndex) }
        for _,pair in ipairs(m.teleporterArrowPairIds) do
            local a = floor:GetObject(pair[1])
            local b = floor:GetObject(pair[2])
            if a ~= nil and a.valid and b ~= nil and b.valid then
                arrows[#arrows+1] = { a.x, a.y, b.x, b.y }
                --EXACT same key format as the slow poll, so neither loop
                --rebuilds arrows the other just drew.
                keyParts[#keyParts+1] = string.format("%s:%.2f,%.2f-%.2f,%.2f", pair.key, a.x, a.y, b.x, b.y)
            end
        end

        local arrowKey = table.concat(keyParts, ";")
        if arrowKey ~= m.teleporterArrowKey then
            ClearTeleporterArrows()
            for _,arrow in ipairs(arrows) do
                AddPairArrow(floorIndex, arrow[1], arrow[2], arrow[3], arrow[4])
            end
            m.teleporterArrowKey = arrowKey
        end
    end)
    if not ok then
        dmhub.Debug("MARKUP:: teleporter arrow fast poll error: " .. tostring(err))
    end

    if keepRunning then
        dmhub.Schedule(0.05, TeleporterArrowFastPoll)
    else
        m.teleporterArrowFastActive = false
    end
end

local function TeleporterArrowPoll()
    if mod.unloaded then
        --a newer load of this file owns the shared handles now and has
        --already destroyed any we left behind.
        return
    end
    local ok, err = pcall(UpdateTeleporterArrows)
    if not ok then
        dmhub.Debug("MARKUP:: teleporter arrows error: " .. tostring(err))
    end

    --spin up the fast tracker whenever arrows exist and the tab is armed;
    --it shuts itself down (and this restarts it) as conditions change.
    if not m.teleporterArrowFastActive and #m.teleporterArrowPairIds > 0
        and MM.GetMarkupObjectEditingFilter() ~= nil then
        m.teleporterArrowFastActive = true
        dmhub.Schedule(0.05, TeleporterArrowFastPoll)
    end

    dmhub.Schedule(0.4, TeleporterArrowPoll)
end
dmhub.Schedule(0.4, TeleporterArrowPoll)

--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.AbortPendingTeleporterPair = AbortPendingTeleporterPair
MM.AddArrowLine = AddArrowLine
MM.AddPairArrow = AddPairArrow
MM.ClearTeleporterArrows = ClearTeleporterArrows
MM.CurrentTeleporterLinkName = CurrentTeleporterLinkName
MM.GenerateTeleporterLinkName = GenerateTeleporterLinkName
MM.GetComponentFieldValue = GetComponentFieldValue
MM.LinkKey = LinkKey
MM.MarkupPropAssets = MarkupPropAssets
MM.MarkupTeleportersOnMap = MarkupTeleportersOnMap
MM.NodeGetComponent = NodeGetComponent
MM.RotateVec = RotateVec
MM.TeleporterArrowFastPoll = TeleporterArrowFastPoll
MM.TeleporterArrowPoll = TeleporterArrowPoll
MM.UpdateTeleporterArrows = UpdateTeleporterArrows
