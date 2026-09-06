local mod = dmhub.GetModLoading()

--Map Markup panel: the Props tab builder.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--========================================================================
--Props mode UI: the prop-type palette (object assets tagged "markup"),
--component-aware property editors (bound to the map-selected prop when
--there is one, else to the selected type's defaults), and click-to-place
--via map focus. Moving/selecting placed props is the engine object tool,
--scoped by the object-editing filter to markup props.
--========================================================================
--Builds the tab's content panel. Returns {panel, toolPanel, prime}:
--toolPanel is what TakeMarkupFocus re-fires 'think' on, prime is run once
--by CreateMarkupEditor after the whole panel is assembled.
function MM.BuildPropsMode()
    local propPalettePanel
    local propPropertiesPanel
    local propsPanel

    --All placed markup props on the current floor; pass an assetid to
    --restrict to one prop type, nil for every markup prop.
    local PropsOnCurrentFloor = function(assetid)
        local result = {}
        local floor = game.currentFloor
        if floor == nil then
            return result
        end
        for _,obj in pairs(floor.objects) do
            local kw = obj.keywords
            if kw ~= nil and kw[K.MARKUP_PROP_KEYWORD] ~= nil
                and (assetid == nil or obj.assetid == assetid) then
                result[#result+1] = obj
            end
        end
        return result
    end

    --The placed prop bound to the property editors, if it still exists. Any
    --markup prop binds, even one whose asset left the palette - the editors
    --key off the INSTANCE's components, so deletion and light editing keep
    --working for legacy props.
    local GetEditingProp = function()
        if m.props.editingId == nil then
            return nil
        end
        local floor = game.currentFloor
        if floor == nil then
            return nil
        end
        local obj = floor:GetObject(m.props.editingId)
        if obj == nil then
            return nil
        end
        local kw = obj.keywords
        if kw == nil or kw[K.MARKUP_PROP_KEYWORD] == nil then
            return nil
        end
        return obj
    end

    --Every prop bound to the editors (shift+click multi-selects), still
    --alive and markup-tagged. Property edits apply to all of these.
    local GetEditingProps = function()
        local result = {}
        local ids = m.props.editingIds
        if ids == nil then
            return result
        end
        local floor = game.currentFloor
        if floor == nil then
            return result
        end
        for _,objid in ipairs(ids) do
            local obj = floor:GetObject(objid)
            if obj ~= nil and obj.valid then
                local kw = obj.keywords
                if kw ~= nil and kw[K.MARKUP_PROP_KEYWORD] ~= nil then
                    result[#result+1] = obj
                end
            end
        end
        return result
    end

    --Component property writes want color userdata, not hex strings; the
    --defaults store whatever the picker last produced, so normalize on write.
    local ToColorValue = function(val)
        if type(val) == "string" then
            local ok, result = pcall(function() return core.Color(val) end)
            if ok and result ~= nil then
                return result
            end
            return core.Color("#ffffff")
        end
        return val
    end

    local RefreshPropUI = function()
        if propsPanel ~= nil and propsPanel.valid then
            propsPanel:FireEventTree("refreshprops")
        end
    end

    --Session light defaults for one palette asset, seeded lazily from the
    --asset's own Light component so a "Torch" chip starts at the torch's
    --authored color/radius rather than a generic white light.
    local LightDefaultsFor = function(assetid)
        if assetid == nil then
            return nil
        end
        local d = m.props.defaults[assetid]
        if d == nil then
            d = { color = "#ffffff", intensity = 0.5, radius = 4, flicker = 0 }
            local node = assets:GetObjectNode(assetid)
            if node ~= nil then
                local comp = MM.NodeGetComponent(node, "Light")
                if comp ~= nil then
                    local v = MM.GetComponentFieldValue(comp, "color")
                    if v ~= nil then
                        d.color = v
                    end
                    v = tonumber(MM.GetComponentFieldValue(comp, "intensity"))
                    if v ~= nil then
                        d.intensity = v
                    end
                    v = tonumber(MM.GetComponentFieldValue(comp, "radius"))
                    if v ~= nil then
                        d.radius = v
                    end
                    v = tonumber(MM.GetComponentFieldValue(comp, "flicker"))
                    if v ~= nil then
                        d.flicker = v
                    end
                end
            end
            m.props.defaults[assetid] = d
        end
        return d
    end

    --Component awareness: the light editors show when ANY bound prop has a
    --Light component, or (with nothing bound) when the selected palette
    --asset does.
    local LightEditorVisible = function()
        local editing = GetEditingProps()
        if #editing > 0 then
            for _,obj in ipairs(editing) do
                if obj:GetComponent("Light") ~= nil then
                    return true
                end
            end
            return false
        end
        if m.props.selected == nil then
            return false
        end
        local node = assets:GetObjectNode(m.props.selected)
        return node ~= nil and MM.NodeGetComponent(node, "Light") ~= nil
    end

    --Apply a light property: onto EVERY bound prop that has a Light
    --component (shift+click selections edit together), updating each one's
    --asset defaults; with nothing bound, into the session defaults for the
    --selected asset (the next placement inherits them).
    local ApplyLightProperty = function(id, value)
        local applied = false
        for _,obj in ipairs(GetEditingProps()) do
            local light = obj:GetComponent("Light")
            if light ~= nil then
                light:SetAndUploadProperties{ [id] = value }
                local d = LightDefaultsFor(obj.assetid)
                if d ~= nil then
                    d[id] = value
                end
                applied = true
            end
        end
        if applied then
            return
        end
        local d = LightDefaultsFor(m.props.selected)
        if d ~= nil then
            d[id] = value
        end
    end

    --The value feeding a light editor: the first bound light's, else the
    --session default for the selected asset.
    local ReadLightProperty = function(id)
        for _,obj in ipairs(GetEditingProps()) do
            local light = obj:GetComponent("Light")
            if light ~= nil then
                local value = MM.GetComponentFieldValue(light, id)
                if value ~= nil then
                    return value
                end
                local d = LightDefaultsFor(obj.assetid)
                if d ~= nil then
                    return d[id]
                end
                return nil
            end
        end
        local d = LightDefaultsFor(m.props.selected)
        if d ~= nil then
            return d[id]
        end
        return nil
    end

    --Session text defaults for one palette asset, seeded lazily from the
    --asset's own Text component so a "Label" chip starts at the font, size
    --and color it was authored with. Like the light defaults these then
    --track the last values edited, so consecutive labels inherit the look
    --(and the wording, which is usually a small edit of the last one).
    local TextDefaultsFor = function(assetid)
        if assetid == nil then
            return nil
        end
        local d = m.props.textDefaults[assetid]
        if d == nil then
            d = { text = "", font = "", fontSize = 40, color = "#ffffff" }
            local node = assets:GetObjectNode(assetid)
            if node ~= nil then
                local comp = MM.NodeGetComponent(node, "Text")
                if comp ~= nil then
                    local v = MM.GetComponentFieldValue(comp, "text")
                    if v ~= nil then
                        d.text = tostring(v)
                    end
                    v = MM.GetComponentFieldValue(comp, "font")
                    if v ~= nil then
                        d.font = tostring(v)
                    end
                    v = tonumber(MM.GetComponentFieldValue(comp, "fontSize"))
                    if v ~= nil then
                        d.fontSize = v
                    end
                    v = MM.GetComponentFieldValue(comp, "color")
                    if v ~= nil then
                        d.color = v
                    end
                end
            end
            m.props.textDefaults[assetid] = d
        end
        return d
    end

    --Component awareness for text, mirroring the light editors: shown when
    --ANY bound prop has a Text component, or (with nothing bound) when the
    --selected palette asset does.
    local TextEditorVisible = function()
        local editing = GetEditingProps()
        if #editing > 0 then
            for _,obj in ipairs(editing) do
                if obj:GetComponent("Text") ~= nil then
                    return true
                end
            end
            return false
        end
        if m.props.selected == nil then
            return false
        end
        local node = assets:GetObjectNode(m.props.selected)
        return node ~= nil and MM.NodeGetComponent(node, "Text") ~= nil
    end

    --Apply a text property onto EVERY bound prop that has a Text component,
    --updating each one's asset defaults; with nothing bound, into the
    --session defaults for the selected asset (the next placement inherits
    --them).
    local ApplyTextProperty = function(id, value)
        local applied = false
        for _,obj in ipairs(GetEditingProps()) do
            local comp = obj:GetComponent("Text")
            if comp ~= nil then
                comp:SetAndUploadProperties{ [id] = value }
                local d = TextDefaultsFor(obj.assetid)
                if d ~= nil then
                    d[id] = value
                end
                applied = true
            end
        end
        if applied then
            return
        end
        local d = TextDefaultsFor(m.props.selected)
        if d ~= nil then
            d[id] = value
        end
    end

    --The value feeding a text editor: the first bound Text component's, else
    --the session default for the selected asset.
    local ReadTextProperty = function(id)
        for _,obj in ipairs(GetEditingProps()) do
            local comp = obj:GetComponent("Text")
            if comp ~= nil then
                local value = MM.GetComponentFieldValue(comp, id)
                if value ~= nil then
                    return value
                end
                local d = TextDefaultsFor(obj.assetid)
                if d ~= nil then
                    return d[id]
                end
                return nil
            end
        end
        local d = TextDefaultsFor(m.props.selected)
        if d ~= nil then
            return d[id]
        end
        return nil
    end

    --Every bound prop with a Teleporter component: {obj, comp, link} each.
    local EditingTeleporters = function()
        local result = {}
        for _,obj in ipairs(GetEditingProps()) do
            local comp = obj:GetComponent("Teleporter")
            if comp ~= nil then
                result[#result+1] = {
                    obj = obj,
                    comp = comp,
                    link = tostring(MM.GetComponentFieldValue(comp, "linkName") or ""),
                }
            end
        end
        return result
    end

    --The distinct link names among the bound teleporters (a set of link
    --keys plus a count). Renaming is only offered when there is exactly one
    --distinct link - renaming a mixed selection would merge separate pairs
    --into one link group.
    local EditingTeleporterLinks = function()
        local links = {}
        local count = 0
        for _,entry in ipairs(EditingTeleporters()) do
            local key = MM.LinkKey(entry.link)
            if key ~= "" and links[key] == nil then
                links[key] = entry.link
                count = count + 1
            end
        end
        return links, count
    end

    --Component awareness for teleporters, mirroring the light editors.
    local TeleporterEditorVisible = function()
        local editing = GetEditingProps()
        if #editing > 0 then
            for _,obj in ipairs(editing) do
                if obj:GetComponent("Teleporter") ~= nil then
                    return true
                end
            end
            return false
        end
        if m.props.selected == nil then
            return false
        end
        local node = assets:GetObjectNode(m.props.selected)
        return node ~= nil and MM.NodeGetComponent(node, "Teleporter") ~= nil
    end

    --The link name the editors show: the first bound teleporter's, else the
    --half-placed pair's, else the name the next pair will use.
    local ReadTeleporterLink = function()
        local teleporters = EditingTeleporters()
        if #teleporters > 0 then
            return teleporters[1].link
        end
        if m.props.pendingPartnerId ~= nil and m.props.pendingLink ~= nil then
            return m.props.pendingLink
        end
        return MM.CurrentTeleporterLinkName()
    end

    --Rename every markup teleporter on the map that carries oldLink - both
    --ends of a pair rename together, so editing the name never breaks the
    --pairing. Also carries the half-placed pair's name along.
    local RenameTeleporterLink = function(oldLink, newLink)
        newLink = trim(tostring(newLink or ""))
        if newLink == "" or MM.LinkKey(newLink) == MM.LinkKey(oldLink) then
            return
        end
        for _,entry in ipairs(MM.MarkupTeleportersOnMap()) do
            if MM.LinkKey(entry.link) == MM.LinkKey(oldLink) then
                entry.comp:SetAndUploadProperties{ linkName = newLink }
            end
        end
        if m.props.pendingLink ~= nil and MM.LinkKey(m.props.pendingLink) == MM.LinkKey(oldLink) then
            m.props.pendingLink = newLink
        end
    end

    --Everything a delete of the current selection should remove: every
    --bound prop, plus the whole pair of every bound teleporter (every
    --markup teleporter sharing its link name, on any floor).
    local GetDeletionSet = function()
        local result = {}
        local byId = {}
        local links = {}
        for _,obj in ipairs(GetEditingProps()) do
            if byId[obj.objid] == nil then
                byId[obj.objid] = true
                result[#result+1] = obj
            end
            local comp = obj:GetComponent("Teleporter")
            if comp ~= nil then
                local link = MM.GetComponentFieldValue(comp, "linkName")
                if link ~= nil and trim(tostring(link)) ~= "" then
                    links[MM.LinkKey(link)] = true
                end
            end
        end
        if next(links) ~= nil then
            for _,entry in ipairs(MM.MarkupTeleportersOnMap()) do
                if links[MM.LinkKey(entry.link)] and byId[entry.obj.objid] == nil then
                    byId[entry.obj.objid] = true
                    result[#result+1] = entry.obj
                end
            end
        end
        return result
    end

    --The style ("teleport"/"stairwell") the editors show: the first bound
    --teleporter's, else the default stamped on new pairs.
    local ReadTeleporterStyle = function()
        local teleporters = EditingTeleporters()
        if #teleporters > 0 then
            local v = MM.GetComponentFieldValue(teleporters[1].comp, "style")
            if v ~= nil and v ~= "" then
                return tostring(v)
            end
        end
        return m.props.teleStyle
    end

    --Apply a style choice: remember it for new pairs, and write it to EVERY
    --markup teleporter sharing any bound teleporter's link name - the ends
    --of a pair always keep the same styling, and a shift+click multi
    --selection styles all its pairs together.
    local ApplyTeleporterStyle = function(value)
        m.props.teleStyle = value

        local links = {}
        local haveLink = false
        for _,entry in ipairs(EditingTeleporters()) do
            local key = MM.LinkKey(entry.link)
            if key ~= "" then
                links[key] = true
                haveLink = true
            else
                --an unlinked teleporter has no pair: style just it.
                entry.comp:SetAndUploadProperties{ style = value }
            end
        end

        if not haveLink and m.props.pendingPartnerId ~= nil and m.props.pendingLink ~= nil then
            links[MM.LinkKey(m.props.pendingLink)] = true
            haveLink = true
        end

        if haveLink then
            for _,entry in ipairs(MM.MarkupTeleportersOnMap()) do
                if links[MM.LinkKey(entry.link)] then
                    entry.comp:SetAndUploadProperties{ style = value }
                end
            end
        end
    end

    --Place a new prop of the given palette asset at a map point. One upload:
    --spawn the asset locally, configure the components, then MarkUndo +
    --Upload. The instance keeps the asset's own name.
    local PlaceProp = function(assetid, point)
        local floor = game.currentFloor
        if floor == nil then
            return
        end

        local node = assets:GetObjectNode(assetid)
        if node == nil then
            return
        end

        --Hard gate: without the engine's object-editing filter a placed prop
        --is invisible AND unselectable, i.e. unremovable through the UI.
        if not MM.PropsSupported() then
            return
        end

        local obj = floor:SpawnObjectLocal(assetid, { posx = point.x, posy = point.y })
        if obj == nil then
            dmhub.Debug("MARKUP:: could not spawn prop object " .. tostring(assetid))
            return
        end

        --The engine filter and the selection handler match the INSTANCE's
        --Core-component keywords, but the palette tag lives on the asset's
        --search keywords - a different store. Stamp "markup" onto the
        --instance, preserving any Core keywords cloned from the asset.
        local coreComponent = obj:GetComponent("Core")
        if coreComponent ~= nil then
            local kws = {}
            local hasMarkup = false
            local existing = obj.keywords
            if existing ~= nil then
                for kw,_ in pairs(existing) do
                    kws[#kws+1] = kw
                    if string.lower(kw) == K.MARKUP_PROP_KEYWORD then
                        hasMarkup = true
                    end
                end
            end
            if not hasMarkup then
                kws[#kws+1] = K.MARKUP_PROP_KEYWORD
            end
            coreComponent:SetProperty("keywords", kws)
        end

        --locked: inert to the object tool everywhere except this tab (the
        --object-editing filter treats matching props as unlocked).
        obj.locked = true

        local light = obj:GetComponent("Light")
        if light ~= nil then
            local d = LightDefaultsFor(assetid)
            if d ~= nil then
                light:SetProperty("color", ToColorValue(d.color))
                light:SetProperty("intensity", d.intensity)
                light:SetProperty("radius", d.radius)
                light:SetProperty("flicker", d.flicker)
            end
        end

        --the wording typed into the editors is what the new label says: for
        --text props the panel doubles as the compose field, so a click on
        --the map drops a finished label rather than a blank one to go back
        --and fill in.
        local textcomp = obj:GetComponent("Text")
        if textcomp ~= nil then
            local d = TextDefaultsFor(assetid)
            if d ~= nil then
                textcomp:SetProperty("text", tostring(d.text or ""))
                if d.font ~= nil and tostring(d.font) ~= "" then
                    textcomp:SetProperty("font", tostring(d.font))
                end
                local size = tonumber(d.fontSize)
                if size ~= nil then
                    textcomp:SetProperty("fontSize", size)
                end
                textcomp:SetProperty("color", ToColorValue(d.color))
            end
        end

        --Teleporters place as a PAIR sharing one link name and style: the
        --first placement arms the pending-partner state, the second completes
        --the pair and retires the link name so the next pair generates a
        --fresh one.
        local teleporter = obj:GetComponent("Teleporter")
        local completedPair = false
        if teleporter ~= nil then
            local link
            if m.props.pendingPartnerId ~= nil then
                link = m.props.pendingLink or MM.CurrentTeleporterLinkName()
                completedPair = true
            else
                link = MM.CurrentTeleporterLinkName()
            end
            teleporter:SetProperty("linkName", link)
            teleporter:SetProperty("style", m.props.teleStyle)
        end

        obj:MarkUndo()
        obj:Upload()

        if teleporter ~= nil then
            if completedPair then
                m.props.pendingPartnerId = nil
                m.props.pendingLink = nil
                m.props.pendingFloorId = nil
                --this name is taken now; the next pair generates a new one.
                m.props.teleLink = nil
            else
                m.props.pendingPartnerId = obj.objid
                m.props.pendingLink = m.props.teleLink
                m.props.pendingFloorId = obj.floorid
            end
        end

        MM.track("markup_prop_place", { prop = tostring(node.description) })

        RefreshPropUI()
    end

    local CreatePropChip = function(node)
        local tip = tostring(node.description) .. ": click the map to place one."
        if MM.NodeGetComponent(node, "Light") ~= nil then
            tip = tip .. " An invisible light source: players see the light it casts, never the marker."
        end
        if MM.NodeGetComponent(node, "Text") ~= nil then
            tip = tip .. " Type the wording below before placing it; every placed one can be re-edited by clicking it."
        end

        return gui.Panel{
            classes = {"markupChip", cond(node.id == m.props.selected, "selected")},
            width = "48%",
            height = 34,
            flow = "horizontal",
            bgimage = true,
            pad = 6,
            borderBox = true,
            hmargin = 2,
            vmargin = 2,

            data = {
                propid = node.id,
            },

            hover = gui.Tooltip(tip),

            press = function(element)
                --switching type abandons a half-placed teleporter pair;
                --re-pressing the already-selected chip does not.
                if element.data.propid ~= m.props.selected then
                    MM.AbortPendingTeleporterPair()
                end
                m.props.selected = element.data.propid
                m.props.editingId = nil
                m.props.editingIds = nil
                dmhub.ClearSelectedObjects()
                RefreshPropUI()
                --panel focus is what turns the object-editing filter on, and
                --map focus must be taken NOW rather than up to thinkTime
                --(0.3s) later: without it, a click on the map in the moment
                --right after picking a type lands with no map focus and
                --silently does nothing.
                MM.TakeMarkupFocus()
            end,

            gui.Panel{
                width = 18,
                height = 18,
                valign = "center",
                bgimageStreamed = node.thumbnailId,
                bgcolor = "white",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = tostring(node.description),
                width = "100%-26",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },
        }
    end

    --A cheap identity for the current palette roster: rebuild the chips only
    --when the set of tagged assets (or a name) actually changes, never on
    --the routine refreshprops that follows every selection or placement -
    --rebuilding mid-press would destroy the pressed chip under its own
    --handler.
    local PropRosterSignature = function(nodes)
        local parts = {}
        for _,node in ipairs(nodes) do
            parts[#parts+1] = node.id .. "=" .. tostring(node.description)
        end
        return table.concat(parts, ";")
    end

    --NOTE the palette and the property editors render even when the engine
    --half is missing (PropsSupported false) - only PLACEMENT is gated. What a
    --stale engine breaks is showing/selecting/dragging placed props, so
    --placing would strand them; browsing the types and setting defaults is
    --harmless, and keeps the tab legible instead of a bare error line.
    propPalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        --the roster is data-driven, so tagging/untagging/renaming an object
        --shows up here live.
        monitorAssets = true,

        data = {
            signature = nil,
        },

        events = {
            refreshAssets = function(element)
                element:FireEvent("syncchips")
            end,

            refreshprops = function(element)
                element:FireEvent("syncchips")
            end,

            syncchips = function(element)
                local nodes = MM.MarkupPropAssets()
                local sig = PropRosterSignature(nodes)
                if sig ~= element.data.signature then
                    element.data.signature = sig

                    --heal a dead selection (asset untagged or deleted) to
                    --the first chip.
                    local found = false
                    for _,node in ipairs(nodes) do
                        if node.id == m.props.selected then
                            found = true
                            break
                        end
                    end
                    if not found then
                        local first = nodes[1]
                        if first ~= nil then
                            m.props.selected = first.id
                        else
                            m.props.selected = nil
                        end
                    end

                    local chips = {}
                    for _,node in ipairs(nodes) do
                        chips[#chips+1] = CreatePropChip(node)
                    end
                    if #chips == 0 then
                        chips[1] = gui.Label{
                            classes = {"fgMuted", "sizeXs"},
                            text = "No prop objects found. Add the keyword \"markup\" to an object in the Objects panel and it will appear here as a placeable prop type.",
                            width = "96%",
                            height = "auto",
                            halign = "center",
                            vmargin = 6,
                            textAlignment = "center",
                        }
                    end
                    element.children = chips
                else
                    for _,chip in ipairs(element.children) do
                        if chip.data ~= nil and chip.data.propid ~= nil then
                            chip:SetClass("selected", chip.data.propid == m.props.selected)
                        end
                    end
                end
            end,
        },

        create = function(element)
            element:FireEvent("syncchips")
        end,
    }

    local CreateLightSliderRow = function(labelText, fieldId, minValue, maxValue)
        return gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = labelText,
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Slider{
                value = tonumber(ReadLightProperty(fieldId)) or minValue,
                minValue = minValue,
                maxValue = maxValue,
                sliderWidth = 150,
                labelWidth = 40,
                valign = "center",
                data = {
                    refreshing = false,
                },
                events = {
                    --programmatically setting .value fires change; guard so
                    --refreshes don't echo back into uploads.
                    refreshprops = function(element)
                        element.data.refreshing = true
                        element.value = tonumber(ReadLightProperty(fieldId)) or minValue
                        element.data.refreshing = false
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyLightProperty(fieldId, element.value)
                    end,
                },
            },
        }
    end

    --Which prop the editors are bound to: the selected placed prop when one
    --is bound, else the selected palette type's defaults. Standalone (not
    --inside the light editors) so it reads correctly for props with no Light
    --component too.
    local propStatusLabel = gui.Label{
        classes = {"fgMuted", "sizeXs"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 4,

        refreshprops = function(element)
            if m.props.pendingPartnerId ~= nil then
                element:SetClass("collapsed", false)
                element.text = string.format(
                    "Now place the partner for '%s': click the map where the second teleporter should go (any floor). Press Escape to cancel and remove the first one.",
                    tostring(m.props.pendingLink or ""))
                return
            end
            local editing = GetEditingProps()
            if #editing > 0 then
                element:SetClass("collapsed", false)
                local teleporters = EditingTeleporters()
                local _, linkCount = EditingTeleporterLinks()
                if #editing >= 2 and #teleporters == #editing and linkCount == 1 then
                    element.text = string.format(
                        "Editing the teleporter pair '%s': changes and deletion apply to both ends.",
                        tostring(ReadTeleporterLink()))
                elseif #editing >= 2 then
                    element.text = string.format(
                        "Editing %d selected props: property changes apply to all of them.",
                        #editing)
                elseif #teleporters == 1 then
                    --the partner may be on another floor (not co-selected),
                    --so check the map before calling it unpaired.
                    local pairSize = 0
                    local key = MM.LinkKey(teleporters[1].link)
                    if key ~= "" then
                        for _,entry in ipairs(MM.MarkupTeleportersOnMap()) do
                            if MM.LinkKey(entry.link) == key then
                                pairSize = pairSize + 1
                            end
                        end
                    end
                    if pairSize >= 2 then
                        element.text = string.format(
                            "Editing the teleporter pair '%s': changes and deletion apply to both ends.",
                            tostring(ReadTeleporterLink()))
                    else
                        element.text = string.format(
                            "Editing the selected %s. It has no partner - place or rename another teleporter to '%s' to pair it.",
                            tostring(editing[1].name), tostring(ReadTeleporterLink()))
                    end
                else
                    element.text = string.format("Editing the selected %s.", tostring(editing[1].name))
                end
                return
            end
            if m.props.selected == nil then
                element:SetClass("collapsed", true)
                return
            end
            local node = assets:GetObjectNode(m.props.selected)
            if node == nil then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)
            element.text = string.format("Defaults for new %s placements. Click a placed prop on the map to edit it.", tostring(node.description))
        end,
    }

    --The asset "Save as New Light Type" clones: the first bound prop's
    --asset when a placed light is being edited, else the selected palette
    --asset - the same precedence the editors read with, so the saved type
    --always matches what the sliders show.
    local SaveLightTypeSourceNode = function()
        for _,obj in ipairs(GetEditingProps()) do
            if obj:GetComponent("Light") ~= nil then
                local node = assets:GetObjectNode(obj.assetid)
                if node ~= nil then
                    return node
                end
            end
        end
        if m.props.selected == nil then
            return nil
        end
        local node = assets:GetObjectNode(m.props.selected)
        if node ~= nil and MM.NodeGetComponent(node, "Light") ~= nil then
            return node
        end
        return nil
    end

    --Create a new palette asset: the source asset's components with the
    --current editor values baked into the Light component. Baked-in values
    --are what make it a durable TYPE - session defaults seed from asset
    --values, so the type looks the same in every later session.
    local CreateLightTypeAsset = function(name)
        local src = SaveLightTypeSourceNode()
        if src == nil then
            return
        end
        local color = ToColorValue(ReadLightProperty("color") or "#ffffff")
        local intensity = tonumber(ReadLightProperty("intensity"))
        local radius = tonumber(ReadLightProperty("radius"))
        local flicker = tonumber(ReadLightProperty("flicker"))

        local comps = {}
        for key, comp in pairs(src.components) do
            local doc = src:ComponentToJson(key)
            if doc ~= nil then
                if comp.name == "Light" then
                    doc.color = { r = color.r, g = color.g, b = color.b, a = color.a }
                    if intensity ~= nil then
                        doc.intensity = intensity
                    end
                    if radius ~= nil then
                        doc.radius = radius
                    end
                    if flicker ~= nil then
                        doc.flicker = flicker
                    end
                end
                comps[key] = doc
            end
        end

        local srcKeywords = tostring(src.keywords or "")
        local guid = assets:UploadNewObject{
            description = name,
            imageId = src.imageId,
            parentFolder = src.parentFolder,
            components = comps,
        }
        if guid == nil then
            return
        end

        --keywords cannot ride through UploadNewObject (the string form does
        --not convert), so stamp them once the node lands. Selecting the new
        --type waits for the same moment: its chip only exists once the
        --"markup" keyword is on and the roster refresh sees it.
        dmhub.ScheduleWhen(function()
            return assets:GetObjectNode(guid) ~= nil
        end,
        function()
            if mod.unloaded then
                return
            end
            local node = assets:GetObjectNode(guid)
            local kw = srcKeywords
            local hasMarkup = false
            for _,part in ipairs(string.split(string.lower(kw), ",")) do
                if string.trim(part) == K.MARKUP_PROP_KEYWORD then
                    hasMarkup = true
                end
            end
            if not hasMarkup then
                if kw == "" then
                    kw = K.MARKUP_PROP_KEYWORD
                else
                    kw = kw .. "," .. K.MARKUP_PROP_KEYWORD
                end
            end
            node.keywords = kw
            node:Upload()
            m.props.selected = guid
            RefreshPropUI()
        end)

        MM.track("markup_light_type_create", {})
    end

    --Name prompt for saving the current light settings as a new palette
    --type. Modeled on ShowZoneHeightDialog.
    local ShowSaveLightTypeDialog = function(owner)
        local nameText = ""
        local modalLayer = nil
        local Confirm = function()
            local name = string.trim(nameText)
            if name == "" then
                name = "New Light"
            end
            CreateLightTypeAsset(name)
            gui.CloseModalInLayer(modalLayer)
        end
        local dialogPanel
        dialogPanel = gui.Panel{
            id = "MarkupSaveLightTypeDialog",
            classes = {"framedPanel"},
            width = "94%",
            maxWidth = 380,
            height = "auto",
            pad = 16,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                Styles.Panel,
                MM.MarkupChipStyles(),
            },

            gui.Label{
                classes = {"dialogTitle"},
                text = "New Light Type",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = "",
                    width = 160,
                    characterLimit = 40,
                    selectAllOnFocus = true,
                    hasInputFocus = true,
                    change = function(element)
                        nameText = element.text
                    end,
                    submit = function(element)
                        nameText = element.text
                        Confirm()
                    end,
                },
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "Saves the current color, brightness, radius and flicker as a new type in the palette, so the same light can be placed anywhere on any map.",
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 2,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            gui.CloseModalInLayer(modalLayer)
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            Confirm()
                        end,
                    },
                },
            },
        }

        modalLayer = gui.ShowModal(dialogPanel, {owner = owner})
    end

    --The light editors: shown when the bound prop - or, unbound, the
    --selected palette asset - has a Light component.
    propPropertiesPanel = gui.Panel{
        classes = {cond(not LightEditorVisible(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", not LightEditorVisible())
            end,
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Color:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.ColorPicker{
                width = 24,
                height = 18,
                valign = "center",
                borderWidth = 1,
                borderColor = "@border",
                value = ReadLightProperty("color") or "#ffffff",
                data = {
                    refreshing = false,
                },
                events = {
                    refreshprops = function(element)
                        local v = ReadLightProperty("color")
                        if v ~= nil then
                            element.data.refreshing = true
                            element.value = v
                            element.data.refreshing = false
                        end
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyLightProperty("color", ToColorValue(element.value))
                    end,
                },
            },
        },

        CreateLightSliderRow("Brightness:", "intensity", 0, 2),
        CreateLightSliderRow("Radius:", "radius", 0, 25),
        CreateLightSliderRow("Flicker:", "flicker", 0, 1),

        gui.Button{
            classes = {"sizeM"},
            text = "Save as New Light Type",
            halign = "center",
            vmargin = 4,
            hover = gui.Tooltip("Save these light settings as a named type in the palette, so the same light can be placed anywhere."),
            events = {
                click = function(element)
                    ShowSaveLightTypeDialog(element)
                end,
            },
        },
    }

    --The font picker's options. The ids gui.availableFonts hands back are
    --lowercase while a component stores whatever case the asset was authored
    --with ("Berling"); GameConfig.GetFont lowercases before looking up, so a
    --lowercase id resolves to exactly the same face - just compare
    --case-insensitively when reading the current value back.
    --
    --A font the build does not ship (the white-label font lists differ, so
    --e.g. an asset authored as "Cambria" has no face here and renders in the
    --fallback) gets a synthetic entry at the top rather than leaving the
    --picker blank on a value that IS set.
    local m_textFontOptions = nil
    local TextFontOptions = function(current)
        if m_textFontOptions == nil then
            m_textFontOptions = {}
            for _,f in ipairs(gui.availableFonts or {}) do
                local name = tostring(f)
                if name ~= "" then
                    m_textFontOptions[#m_textFontOptions+1] = {
                        id = string.lower(name),
                        text = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2),
                    }
                end
            end
        end

        current = string.lower(tostring(current or ""))
        if current == "" then
            return m_textFontOptions
        end
        for _,opt in ipairs(m_textFontOptions) do
            if opt.id == current then
                return m_textFontOptions
            end
        end

        local result = { { id = current, text = current .. " (missing)" } }
        for _,opt in ipairs(m_textFontOptions) do
            result[#result+1] = opt
        end
        return result
    end

    --Commit the text field. Enter submits and focus loss changes, so both
    --events land here - lastApplied makes one edit upload once, and stops a
    --refresh-driven re-push of the same wording from writing at all.
    local ApplyEditedText = function(element)
        local typed = tostring(element.text or "")
        if element.data.lastApplied == typed then
            return
        end
        element.data.lastApplied = typed
        ApplyTextProperty("text", typed)
        RefreshPropUI()
    end

    --The text editors: what the label actually says, plus the three fields
    --that decide whether it reads at all on the map - font, size and color.
    --Shown when the bound prop - or, unbound, the selected palette asset -
    --has a Text component. Unbound the fields ARE the next placement: what
    --is typed here is what the label says when it lands.
    local propTextPanel = gui.Panel{
        classes = {cond(not TextEditorVisible(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", not TextEditorVisible())
            end,
        },

        gui.Panel{
            width = "96%",
            height = "auto",
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Text:",
                width = 80,
                height = "auto",
                valign = "center",
                hover = gui.Tooltip("What this label says on the map. Enter applies it; shift+Enter starts a new line."),
            },

            gui.Input{
                classes = {"sizeXs"},
                text = "",
                width = "100%-84",
                height = 44,
                valign = "center",
                multiline = true,
                lineType = "MultiLineSubmit",
                textAlignment = "topleft",
                characterLimit = 400,
                placeholderText = "Label text",

                data = {
                    lastApplied = "",
                },

                refreshprops = function(element)
                    --don't stomp the field while the user is typing in it.
                    if element.hasInputFocus then
                        return
                    end
                    --textNoNotify, NOT text: a plain assignment fires change,
                    --and change re-refreshes, so the refresh that follows
                    --every edit would bounce back into another upload.
                    local value = tostring(ReadTextProperty("text") or "")
                    element.textNoNotify = value
                    element.data.lastApplied = value
                end,

                change = function(element)
                    ApplyEditedText(element)
                end,

                submit = function(element)
                    ApplyEditedText(element)
                end,
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Font:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Dropdown{
                --wider than the panel's other 150px controls: font names run
                --long, and a wrapped two-line name in a 26px row is unreadable.
                width = "100%-84",
                height = 26,
                valign = "center",
                options = TextFontOptions(ReadTextProperty("font")),
                idChosen = string.lower(tostring(ReadTextProperty("font") or "")),
                data = {
                    refreshing = false,
                    optionsFor = string.lower(tostring(ReadTextProperty("font") or "")),
                },

                refreshprops = function(element)
                    local font = string.lower(tostring(ReadTextProperty("font") or ""))
                    if font ~= "" and element.idChosen ~= font then
                        element.data.refreshing = true
                        --a rebuild only when the list would actually differ:
                        --reassigning options on every refresh churns the
                        --dropdown for nothing.
                        if element.data.optionsFor ~= font then
                            element.data.optionsFor = font
                            element.options = TextFontOptions(font)
                        end
                        element.idChosen = font
                        element.data.refreshing = false
                    end
                end,

                change = function(element)
                    if element.data.refreshing then
                        return
                    end
                    ApplyTextProperty("font", element.idChosen)
                    RefreshPropUI()
                end,
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Font Size:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Slider{
                value = tonumber(ReadTextProperty("fontSize")) or 40,
                minValue = 8,
                maxValue = 160,
                sliderWidth = 150,
                labelWidth = 40,
                --whole points: the default "%.2f" readout ("40.00") is noise
                --at this range, and a fractional point size buys nothing.
                labelFormat = "%d",
                valign = "center",
                data = {
                    refreshing = false,
                },
                events = {
                    --programmatically setting .value fires change; guard so
                    --refreshes don't echo back into uploads.
                    refreshprops = function(element)
                        element.data.refreshing = true
                        element.value = tonumber(ReadTextProperty("fontSize")) or 40
                        element.data.refreshing = false
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyTextProperty("fontSize", math.floor((tonumber(element.value) or 40) + 0.5))
                    end,
                },
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Color:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.ColorPicker{
                width = 24,
                height = 18,
                valign = "center",
                borderWidth = 1,
                borderColor = "@border",
                value = ReadTextProperty("color") or "#ffffff",
                data = {
                    refreshing = false,
                },
                events = {
                    refreshprops = function(element)
                        local v = ReadTextProperty("color")
                        if v ~= nil then
                            element.data.refreshing = true
                            element.value = v
                            element.data.refreshing = false
                        end
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyTextProperty("color", ToColorValue(element.value))
                        RefreshPropUI()
                    end,
                },
            },
        },
    }

    --The teleporter editors: link name + trip styling. Shown when the bound
    --prop - or, unbound, the selected palette asset - has a Teleporter
    --component. Edits to either field keep both ends of a pair identical.
    local propTeleporterPanel = gui.Panel{
        classes = {cond(not TeleporterEditorVisible(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", not TeleporterEditorVisible())
            end,
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            events = {
                --renaming a selection that spans SEVERAL links would merge
                --separate pairs into one link group; offer the rename only
                --when the bound teleporters share a single link.
                refreshprops = function(element)
                    local _, linkCount = EditingTeleporterLinks()
                    element:SetClass("collapsed", linkCount > 1)
                end,
            },

            gui.Label{
                classes = {"sizeXs"},
                text = "Link Name:",
                width = 80,
                height = "auto",
                valign = "center",
                hover = gui.Tooltip("Teleporters with the same link name are a pair; a creature entering one comes out at the other. Renaming here renames both ends together."),
            },

            gui.Input{
                classes = {"sizeXs"},
                text = "",
                width = 150,
                height = 20,
                valign = "center",
                characterLimit = 40,
                selectAllOnFocus = true,

                refreshprops = function(element)
                    --don't stomp the field while the user is typing in it.
                    if element.hasInputFocus then
                        return
                    end
                    element.text = ReadTeleporterLink()
                end,

                change = function(element)
                    local typed = trim(tostring(element.text or ""))
                    if typed == "" then
                        element.text = ReadTeleporterLink()
                        return
                    end

                    local teleporters = EditingTeleporters()
                    if #teleporters > 0 then
                        RenameTeleporterLink(teleporters[1].link, typed)
                    elseif m.props.pendingPartnerId ~= nil then
                        RenameTeleporterLink(m.props.pendingLink, typed)
                    else
                        m.props.teleLink = typed
                    end
                    RefreshPropUI()
                end,
            },
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Style:",
                width = 80,
                height = "auto",
                valign = "center",
                hover = gui.Tooltip("How the trip looks and sounds. Teleport plays the token's teleport effect; Stairwell just moves the token with a footsteps sound. Both ends of a pair always share the style."),
            },

            gui.Dropdown{
                width = 150,
                height = 26,
                valign = "center",
                idChosen = "teleport",
                options = {
                    { id = "teleport", text = "Teleport" },
                    { id = "stairwell", text = "Stairwell" },
                },
                data = {
                    refreshing = false,
                },

                refreshprops = function(element)
                    local style = ReadTeleporterStyle()
                    if element.idChosen ~= style then
                        element.data.refreshing = true
                        element.idChosen = style
                        element.data.refreshing = false
                    end
                end,

                change = function(element)
                    if element.data.refreshing then
                        return
                    end
                    ApplyTeleporterStyle(element.idChosen)
                    RefreshPropUI()
                end,
            },
        },
    }

    --Standalone (outside the light editors) so any bound prop can be
    --deleted, whatever components it carries. Teleporters delete as a PAIR:
    --both ends go together, whatever floor the partner is on.
    local propDeleteButton = gui.Button{
        classes = {"sizeM", "collapsed"},
        text = "Delete Prop",
        halign = "center",
        vmargin = 4,

        refreshprops = function(element)
            local toDelete = GetDeletionSet()
            element:SetClass("collapsed", #toDelete == 0)
            if #toDelete == 0 then
                return
            end
            local teleporters = EditingTeleporters()
            local _, linkCount = EditingTeleporterLinks()
            if #toDelete >= 2 and #teleporters == #GetEditingProps() and linkCount == 1 then
                element.text = "Delete Teleporter Pair"
            elseif #toDelete >= 2 then
                element.text = string.format("Delete %d Props", #toDelete)
            else
                element.text = "Delete Prop"
            end
        end,

        click = function(element)
            local toDelete = GetDeletionSet()
            if #toDelete == 0 then
                return
            end
            local propName = tostring(toDelete[1].name)

            --deleting the half-placed first teleporter IS the abort; just
            --clear the pending state rather than double-destroying.
            for _,d in ipairs(toDelete) do
                if d.objid == m.props.pendingPartnerId then
                    m.props.pendingPartnerId = nil
                    m.props.pendingLink = nil
                    m.props.pendingFloorId = nil
                end
            end

            dmhub.ClearSelectedObjects()
            m.props.editingId = nil
            m.props.editingIds = nil
            for _,d in ipairs(toDelete) do
                if d.valid then
                    d:Destroy()
                end
            end
            MM.track("markup_prop_delete", { prop = propName, count = #toDelete })
            RefreshPropUI()
        end,
    }

    --Rough map location for a prop row ("NE Corner", "Center", ...): the
    --same 3x3 cut of the map extent the zone list uses. obj positions are
    --continuous world coordinates, so no half-tile centroid shift.
    local PropAreaDescription = function(x, y)
        local dims = nil
        pcall(function()
            local map = game.currentMap
            if map ~= nil then
                dims = map.dimensions
            end
        end)
        if dims == nil then
            return nil
        end
        local w = dims.z - dims.x
        local h = dims.w - dims.y
        if w <= 0 or h <= 0 then
            return nil
        end
        local col = 1 + math.floor(((x - dims.x) / w) * 3)
        local row = 1 + math.floor(((y - dims.y) / h) * 3)
        if col < 1 then col = 1 elseif col > 3 then col = 3 end
        if row < 1 then row = 1 elseif row > 3 then row = 3 end
        return K.ZONE_AREA_NAMES[row][col]
    end

    --Pan the camera to the first of a list of props and flash a highlight
    --box around each of them for a moment (a teleporter-pair row flashes
    --both ends). The scheduled cleanup deliberately has NO mod.unloaded
    --guard: HighlightLine markers are engine objects that outlive a Lua
    --reload, so the stale closure destroying them is exactly what we want.
    local propFlashHandles = nil
    local JumpToProps = function(objs)
        if #objs == 0 then
            return
        end

        pcall(function()
            dmhub.CenterOnLoc{
                x = math.floor(objs[1].x + 0.5),
                y = math.floor(objs[1].y + 0.5),
                floorid = objs[1].floorid,
                smooth = true,
            }
        end)

        if propFlashHandles ~= nil then
            for _,h in ipairs(propFlashHandles) do
                pcall(function() h:Destroy() end)
            end
            propFlashHandles = nil
        end

        local floorIndex = game.currentFloorIndex
        local handles = {}
        for _,obj in ipairs(objs) do
            local x, y = obj.x, obj.y
            local R = 0.55
            local corners = {
                { x - R, y - R, x + R, y - R },
                { x + R, y - R, x + R, y + R },
                { x + R, y + R, x - R, y + R },
                { x - R, y + R, x - R, y - R },
            }
            for _,c in ipairs(corners) do
                local ok, handle = pcall(function()
                    return dmhub.HighlightLine{
                        color = "#7fd4ff",
                        a = core.Vector2(c[1], c[2]),
                        b = core.Vector2(c[3], c[4]),
                        floorIndex = floorIndex,
                        terrainParallax = true,
                    }
                end)
                if ok and handle ~= nil then
                    handles[#handles+1] = handle
                end
            end
        end
        propFlashHandles = handles

        dmhub.Schedule(1.0, function()
            --double-destroy of an already-replaced flash is pcall-safe.
            for _,h in ipairs(handles) do
                pcall(function() h:Destroy() end)
            end
        end)
    end

    --The wording a placed text prop shows, flattened to one line and cut to
    --a row-sized length; nil for a prop with no Text component, "" for one
    --whose text is blank. The cut backs off any UTF-8 continuation bytes so
    --a multi-byte character never gets sliced in half into a garbage glyph.
    local PropDisplayText = function(obj)
        local comp = obj:GetComponent("Text")
        if comp == nil then
            return nil
        end
        local raw = tostring(MM.GetComponentFieldValue(comp, "text") or "")
        raw = trim((string.gsub(raw, "%s+", " ")))
        if #raw > 40 then
            local cut = 40
            while cut > 1 do
                local b = string.byte(raw, cut + 1)
                if b == nil or b < 128 or b >= 192 then
                    break
                end
                cut = cut - 1
            end
            raw = string.sub(raw, 1, cut) .. "..."
        end
        return raw
    end

    --One row in the placed-props list. An entry is ONE prop - or one whole
    --TELEPORTER PAIR: both ends of a pair share a single row (entry.objs
    --holds each end on this floor, entry.link the pair's link name).
    --Click: select the entry's props (the editors bind through the engine
    --selection callback) and pan the camera to them. Shift+click: toggle
    --the whole entry in or out of the selection without clearing the rest,
    --to edit several entries together.
    local CreatePropRow = function(entry, node)
        local objs = entry.objs
        local first = objs[1]

        local title = tostring(first.name)
        if entry.link ~= nil then
            title = string.format("%s '%s'", title, entry.link)
        end

        --a text prop is identified by WHAT IT SAYS: every one of them carries
        --the same asset name (and the header above already names the type),
        --so the wording replaces it as the row's label. A linked prop keeps
        --its name+link and merely gains the wording, since the link is what
        --identifies it there.
        local shownText = PropDisplayText(first)
        if shownText ~= nil then
            if shownText == "" then
                title = title .. " (blank)"
            elseif entry.link ~= nil then
                title = string.format("%s \"%s\"", title, shownText)
            else
                title = string.format("\"%s\"", shownText)
            end
        end

        local areas = {}
        for _,obj in ipairs(objs) do
            local area = PropAreaDescription(obj.x, obj.y)
            if area ~= nil then
                areas[#areas+1] = area
            end
        end
        if #areas >= 2 then
            if areas[1] == areas[2] then
                title = title .. " -- " .. areas[1]
            else
                title = title .. " -- " .. areas[1] .. " to " .. areas[2]
            end
        elseif #areas == 1 then
            title = title .. " -- " .. areas[1]
        end

        --a linked teleporter with only one end on this floor: say where the
        --rest of the pair is rather than listing a confusing lone end.
        if entry.link ~= nil and #objs == 1 then
            if (entry.pairSize or 1) >= 2 then
                title = title .. " (partner on another floor)"
            else
                title = title .. " (unpaired)"
            end
        end

        local swatch
        local light = first:GetComponent("Light")
        local swatchColor = nil
        if light ~= nil then
            swatchColor = MM.GetComponentFieldValue(light, "color")
        end
        if swatchColor == nil then
            --a text prop's color is the one thing distinguishing it at a
            --glance; the thumbnail is identical across all of them.
            local textcomp = first:GetComponent("Text")
            if textcomp ~= nil then
                swatchColor = MM.GetComponentFieldValue(textcomp, "color")
            end
        end
        if swatchColor ~= nil then
            swatch = gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = swatchColor,
                borderWidth = 1,
                borderColor = "@border",
            }
        else
            local thumb = nil
            if node ~= nil then
                thumb = node.thumbnailId
            end
            swatch = gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimageStreamed = thumb,
                bgcolor = "white",
            }
        end

        local ids = {}
        for _,obj in ipairs(objs) do
            ids[#ids+1] = obj.objid
        end

        local what = "this prop"
        if entry.link ~= nil then
            what = "this teleporter pair"
        end

        return gui.Panel{
            classes = {"markupChip"},
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            data = {
                propRowIds = ids,
            },

            hover = gui.Tooltip(string.format("Click to select %s and pan to it. Shift+click to add it to the selection and edit several together.", what)),

            press = function(element)
                --focus FIRST: the selection callback binds selections to
                --this panel's editors only while the panel holds focus.
                MM.TakeMarkupFocus()

                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                local rowObjs = {}
                local inRow = {}
                for _,objid in ipairs(element.data.propRowIds) do
                    local o = floor:GetObject(objid)
                    if o ~= nil and o.valid then
                        rowObjs[#rowObjs+1] = o
                        inRow[objid] = true
                    end
                end
                if #rowObjs == 0 then
                    RefreshPropUI()
                    return
                end

                local shift = false
                pcall(function()
                    shift = dmhub.modKeys.shift == true
                end)

                if shift then
                    --toggle the WHOLE entry: any end selected = deselect
                    --both, else select both. The selection callback rebinds
                    --the editors to whatever remains selected.
                    local anySelected = false
                    for _,o in ipairs(rowObjs) do
                        if o.editorSelection then
                            anySelected = true
                            break
                        end
                    end
                    for _,o in ipairs(rowObjs) do
                        o.editorSelection = not anySelected
                    end
                else
                    --deselect the previous binding per-object, NOT via
                    --dmhub.ClearSelectedObjects: the global clear dispatches
                    --the selection callback INLINE, so the panel renders one
                    --unbound frame (delete button collapsing, status/link
                    --text swapping to placement defaults) before next
                    --frame's re-bind - a whole-panel flicker on every click.
                    --Individual editorSelection writes only bump the
                    --selection seq, batching everything into ONE callback
                    --next frame: the panel transitions straight from the old
                    --binding to the new one.
                    for _,objid in ipairs(m.props.editingIds or {}) do
                        if not inRow[objid] then
                            local prev = floor:GetObject(objid)
                            if prev ~= nil and prev.valid then
                                prev.editorSelection = false
                            end
                        end
                    end
                    for _,o in ipairs(rowObjs) do
                        o.editorSelection = true
                    end
                    JumpToProps(rowObjs)
                end
            end,

            swatch,

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = title,
                width = "100%-20",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },
        }
    end

    local propListHeader = gui.Label{
        classes = {"bold"},
        text = "",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 2,
    }

    local propListRows = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local propListHint = gui.Label{
        classes = {"fgMuted", "sizeXs"},
        text = "Click the map to place one; drag a placed prop to move it; Delete removes it.",
        width = "90%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        textAlignment = "center",
    }

    --The placed props of the selected type on this floor, replacing the old
    --bare count line. Rows rebuild only when the roster/positions/labels
    --actually change (a rebuild mid-press would destroy the pressed row);
    --selection highlights sync on every refresh. The slow think keeps the
    --list fresh as props are added/moved/removed, including by other
    --clients.
    local propListPanel = gui.Panel{
        classes = {cond(not MM.PropsSupported(), "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        thinkTime = 1,

        data = {
            signature = nil,
        },

        events = {
            think = function(element)
                if m.mode == "props" then
                    element:FireEvent("syncrows")
                end
            end,

            refreshprops = function(element)
                local show = MM.PropsSupported() and m.props.selected ~= nil
                element:SetClass("collapsed", not show)
                if show then
                    element:FireEvent("syncrows")
                end
            end,

            syncrows = function(element)
                if m.props.selected == nil then
                    return
                end
                local node = assets:GetObjectNode(m.props.selected)
                if node == nil then
                    return
                end

                local props = PropsOnCurrentFloor(m.props.selected)
                table.sort(props, function(a, b)
                    return tostring(a.objid) < tostring(b.objid)
                end)

                --group into list ENTRIES: a teleporter pair is one entry
                --holding both of its ends on this floor; everything else is
                --one entry per prop. entry = {objs, link, pairSize} where
                --pairSize counts the pair's ends map-WIDE, so a lone end
                --here can say "partner on another floor" vs "(unpaired)".
                local entries = {}
                local groups = {}
                local mapPairSizes = nil
                for _,obj in ipairs(props) do
                    local link = nil
                    local teleporter = obj:GetComponent("Teleporter")
                    if teleporter ~= nil then
                        local raw = trim(tostring(MM.GetComponentFieldValue(teleporter, "linkName") or ""))
                        if raw ~= "" then
                            link = raw
                        end
                    end

                    if link ~= nil then
                        if mapPairSizes == nil then
                            mapPairSizes = {}
                            for _,tp in ipairs(MM.MarkupTeleportersOnMap()) do
                                local key = MM.LinkKey(tp.link)
                                if key ~= "" then
                                    mapPairSizes[key] = (mapPairSizes[key] or 0) + 1
                                end
                            end
                        end
                        local key = MM.LinkKey(link)
                        local group = groups[key]
                        if group == nil then
                            group = { objs = {}, link = link, pairSize = mapPairSizes[key] or 1 }
                            groups[key] = group
                            entries[#entries+1] = group
                        end
                        group.objs[#group.objs+1] = obj
                    else
                        entries[#entries+1] = { objs = { obj } }
                    end
                end

                local name = tostring(node.description)
                propListHeader.text = string.format("%s%s on This Floor (%d)",
                    name, cond(#entries == 1, "", "s"), #entries)

                --signature includes position and the label-feeding fields so
                --drags, renames, recolors and cross-floor partner changes
                --refresh the rows too.
                local parts = { tostring(m.props.selected), tostring(game.currentFloorId) }
                for _,entry in ipairs(entries) do
                    for _,obj in ipairs(entry.objs) do
                        local extra = ""
                        local light = obj:GetComponent("Light")
                        if light ~= nil then
                            --NOT tostring(color): global tostring of a
                            --LuaColor is a constant ("LuaColor{}"), blind to
                            --the actual value. The .tostring PROPERTY is the
                            --real "#RRGGBBAA" string.
                            local c = MM.GetComponentFieldValue(light, "color")
                            if c ~= nil then
                                pcall(function()
                                    extra = tostring(c.tostring)
                                end)
                            end
                        end
                        --the wording and its color feed the row label and
                        --swatch, so retyping a label rebuilds the rows.
                        local textcomp = obj:GetComponent("Text")
                        if textcomp ~= nil then
                            extra = extra .. "|" .. tostring(MM.GetComponentFieldValue(textcomp, "text") or "")
                            local c = MM.GetComponentFieldValue(textcomp, "color")
                            if c ~= nil then
                                pcall(function()
                                    extra = extra .. "|" .. tostring(c.tostring)
                                end)
                            end
                        end
                        parts[#parts+1] = string.format("%s:%.1f,%.1f:%s", tostring(obj.objid), obj.x, obj.y, extra)
                    end
                    if entry.link ~= nil then
                        parts[#parts+1] = string.format("L:%s=%d", MM.LinkKey(entry.link), entry.pairSize or 1)
                    end
                end
                local sig = table.concat(parts, ";")

                if sig ~= element.data.signature then
                    element.data.signature = sig
                    local rows = {}
                    for _,entry in ipairs(entries) do
                        rows[#rows+1] = CreatePropRow(entry, node)
                    end
                    if #rows == 0 then
                        rows[1] = gui.Label{
                            classes = {"fgMuted", "sizeXs"},
                            text = string.format("No %ss on this floor yet. Click the map to place one.", name),
                            width = "90%",
                            height = "auto",
                            halign = "center",
                            vmargin = 4,
                            textAlignment = "center",
                        }
                    end
                    propListRows.children = rows
                end

                --selection highlight follows the bound multi-selection: a
                --row highlights when ANY of its props is bound (a pair row
                --lights up whichever end was selected).
                local selectedSet = {}
                for _,objid in ipairs(m.props.editingIds or {}) do
                    selectedSet[objid] = true
                end
                for _,row in ipairs(propListRows.children) do
                    if row.data ~= nil and row.data.propRowIds ~= nil then
                        local anySelected = false
                        for _,objid in ipairs(row.data.propRowIds) do
                            if selectedSet[objid] then
                                anySelected = true
                                break
                            end
                        end
                        row:SetClass("selected", anySelected)
                    end
                end
            end,
        },

        propListHeader,
        propListRows,
        propListHint,
    }

    propsPanel = gui.Panel{
        classes = {cond(m.mode ~= "props", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        --keeps map focus in sync with mode/focus/type; map focus is the
        --placement input surface (mappress) and suppresses token selection
        --while the tab is armed. The engine object tool is NOT suppressed by
        --map focus, which is exactly what lets placed props drag normally.
        thinkTime = 0.3,

        events = {
            markupmode = function(element)
                --leaving the Props tab abandons a half-placed teleporter pair.
                if m.mode ~= "props" then
                    MM.AbortPendingTeleporterPair()
                end
                element:SetClass("collapsed", m.mode ~= "props")
                if m.mode == "props" then
                    element:FireEventTree("refreshprops")
                end
                --grab (or release) map focus on the mode switch itself, so the
                --first map click after switching tabs is not swallowed by the
                --think interval. Also releases promptly when switching away.
                element:FireEvent("think")
            end,

            think = function(element)
                local want = m.mode == "props" and MM.PropsSupported()
                    and m.props.selected ~= nil
                    and m.arm.Armed()

                if m.props.pendingPartnerId ~= nil then
                    if not want then
                        --disarmed (focus lost, tab left, panel closed) with a
                        --pair half-placed: abort, deleting the first one.
                        MM.AbortPendingTeleporterPair()
                    else
                        --the first teleporter can also die under us (another
                        --client, undo): quietly stop waiting for a partner.
                        local floor = nil
                        if m.props.pendingFloorId ~= nil then
                            floor = game.GetFloor(m.props.pendingFloorId)
                        end
                        local pendingObj = nil
                        if floor ~= nil then
                            pendingObj = floor:GetObject(m.props.pendingPartnerId)
                        end
                        if pendingObj == nil or not pendingObj.valid then
                            m.props.pendingPartnerId = nil
                            m.props.pendingLink = nil
                            m.props.pendingFloorId = nil
                            RefreshPropUI()
                        end
                    end
                end

                if want then
                    if not element.mapfocus then
                        element.mapfocus = true
                    end
                else
                    if element.mapfocus then
                        element.mapfocus = false
                    end
                end
            end,

            mappress = function(element, loc, point)
                if m.mode ~= "props" or m.props.selected == nil then
                    return
                end

                --clicks on or near ANY existing markup prop are select/drag
                --(the engine object tool owns those, and every markup prop
                --matches the editing filter); only place on empty ground.
                for _,obj in ipairs(PropsOnCurrentFloor(nil)) do
                    local dx = obj.x - point.x
                    local dy = obj.y - point.y
                    if dx*dx + dy*dy < 0.36 then
                        return
                    end
                end

                local placePoint = point
                if MM.GhostSupported() then
                    --the ghost is the source of truth for "this click
                    --places": while a prop is bound the ghost is not
                    --published (the click unbinds via the engine's
                    --selection-clear instead), and a nil preview position
                    --means the engine is in select/drag stance (hovering a
                    --prop) even when the 0.6-tile check above missed it.
                    --When it IS showing, place at exactly the previewed
                    --(snapped) position so the prop lands under the ghost.
                    if m.props.editingId ~= nil then
                        return
                    end
                    local ghostPos = nil
                    pcall(function()
                        ghostPos = editor.objectPlacementPreviewPos
                    end)
                    if ghostPos == nil then
                        return
                    end
                    placePoint = ghostPos
                end

                PlaceProp(m.props.selected, placePoint)
            end,

            create = function(element)
                --a Lua reload can rebuild the panel with props already the
                --active mode; the editors then get no markupmode event, so
                --sync them here.
                if m.mode == "props" then
                    element:FireEventTree("refreshprops")
                end
            end,

            destroy = function(element)
                if element.mapfocus then
                    element.mapfocus = false
                end
            end,
        },

        children = {
            --NOT muted: this explains why clicking the map does nothing, and
            --muted small text got missed in exactly that situation.
            gui.Label{
                classes = {"bold", "sizeXs", cond(MM.PropsSupported(), "collapsed")},
                text = "Placing props is DISABLED: this build cannot show or move placed props yet, so they would be stranded invisibly. Rebuild the app to enable it. The settings below still work.",
                width = "90%",
                height = "auto",
                halign = "center",
                vmargin = 8,
                textAlignment = "center",
            },

            propPalettePanel,
            propStatusLabel,
            propPropertiesPanel,
            propTextPanel,
            propTeleporterPanel,
            propDeleteButton,
            propListPanel,
        },
    }


    return {
        panel = propsPanel,
        toolPanel = propsPanel,
        prime = function()
            propsPanel:FireEventTree("refreshprops")
        end,
    }
end
