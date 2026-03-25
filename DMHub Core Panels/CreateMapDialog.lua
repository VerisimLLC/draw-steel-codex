local mod = dmhub.GetModLoading()

mod.shared.ShowCreateMapDialog = function()

    local selectedMap = nil

    local m_mapName = "New Map"

    local MapItemPress = function(element)
        selectedMap = element
        for _,el in ipairs(element.parent.children) do
            el:SetClass("selected", el == element)
        end
    end

    local tileType = "squares"

	local dialogPanel = gui.Panel{
		classes = {'framedPanel'},
		width = 1400,
		height = 940,
		styles = {
			Styles.Panel,
            {
                selectors = {"mapItem"},
                bgimage = "panels/square.png",
                bgcolor = "black",
                cornerRadius = 12,
                width = 1920*0.1,
                height = 1080*0.1,
                halign = "center",
                hmargin = 8,
            },
            {
                selectors = {"mapItem", "hover"},
                borderWidth = 2,
                borderColor = "#ffffff44",
            },
            {
                selectors = {"mapItem", "selected"},
                borderWidth = 2,
                borderColor = "white",
            },
            {
                selectors = {"mapText"},
                color = "white",
                fontSize = 14,
                width = "auto",
                height = "auto",
                textAlignment = "center",
            },
		},

        gui.Panel{
            width = "100%-24",
            height = "100%-48",
            halign = "center",
            valign = "center",

            flow = "vertical",

            gui.Label{
                classes = {"dialogTitle"},
                text = "Create Map",
            },

            gui.Panel{
                flow = "horizontal",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                vmargin = 16,

                gui.Panel{
                    classes = {"mapItem", "selected"},
                    press = MapItemPress,
                    create = function(element)
                        selectedMap = element
                    end,
                    data = {
                        type = "empty",
                    },
                    gui.Label{
                        classes = {"mapText"},
                        text = "Empty Map",
                        interactable = false,
                    },
                },

                gui.Panel{
                    classes = {"mapItem"},
                    press = MapItemPress,
                    data = {
                        type = "import",
                    },
                    gui.Label{
                        classes = {"mapText"},
                        text = "Import an Image\nor UVTT file",
                        interactable = false,
                    },
                },
            },

            gui.Panel{
                width = 600,
                height = "auto",
                flow = "vertical",
                valign = "top",
                vmargin = 16,

                styles = {
                    Styles.Form,
                    {
                        selectors = {"formPanel"},
                        width = 600,
                    },
                    {
                        selectors = {"formLabel"},
                        halign = "left",
                        minWidth = 180,
                    },
                    {
                        selectors = {"formData"},
                        halign = "left",
                    },
                },

                gui.Panel{
                    classes = {"formPanel"},
                    halign = "center",
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Map Name:",
                    },
                    gui.Input{
                        classes = {"formInput", "formData"},
                        text = m_mapName,
                        change = function(element)
                            m_mapName = element.text
                        end,
                    },
                },


                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        text = "Tile Type:",
                    },

                    gui.Panel{
                        classes = {"formData"},
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "left",

                        select = function(element, target)
                            tileType = target.data.id
                            for _,child in ipairs(element.children) do
                                child:SetClass("selected", target == child)
                            end
                        end,

                        gui.HudIconButton{
                            classes = {"selected"},
                            data = {id = "squares"},
                            hmargin = 8,
                            icon = "ui-icons/tile-square.png",
                            click = function(element) element.parent:FireEvent("select", element) end,
                        },
                        gui.HudIconButton{
                            data = {id = "flattop"},
                            hmargin = 8,
                            icon = "ui-icons/tile-flathex.png",
                            click = function(element) element.parent:FireEvent("select", element) end,
                        },
                        gui.HudIconButton{
                            data = {id = "pointtop"},
                            hmargin = 8,
                            icon = "ui-icons/tile-pointyhex.png",
                            click = function(element) element.parent:FireEvent("select", element) end,
                        },
                    }
                }
            },

            gui.Panel{
                width = 600,
                height = 48,
                halign = "center",
                valign = "bottom",

                gui.PrettyButton{
                    halign = "left",
                    text = "Create Map",
                    width = 160,
                    click = function(element)
                        local mapType = selectedMap.data.type

                        gui.CloseModal()
                        dmhub.Debug("TILE TYPE: " .. tileType)

                        if mapType == "import" then
                            mod.shared.ImportMap{
                                tileType = tileType,
                                nofade = true,
                                --SheetMapImport.cs controls the contents of info. Alternatively, AssetLua.cs:ImportUniversalVTT.
                                --Will include
                                --objids: asset objids of the map objects created.
                                --width/height.
                                --mapSettings (optional): map of settings to set when entering the map.
                                --uvttData (optional): list of json uvtt data which we can use to build the map.
                                finish = function(info)
                                    mod.shared.FinishMapImport(m_mapName, info)
                                end,
                            }
                        else

                            local guid = game.CreateMap{
                                description = m_mapName
                            }
                            dmhub.Coroutine(function()
                                while game.GetMap(guid) == nil do
                                    coroutine.yield(0.05)
                                end


                                local map = game.GetMap(guid)

                                map:Travel()

                                while game.currentMapId ~= guid do
                                    coroutine.yield(0.05)
                                end

                                dmhub.SetSettingValue("maplayout:tiletype", tileType)

                                printf("SETTING: Set: %s vs %s", dmhub.GetSettingValue("maplayout:tiletype"), tileType)


                            end)

                        end
                    end,
                },

                gui.PrettyButton{
                    halign = "right",
                    text = "Cancel",
                    width = 160,
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                    click = function(element)
                        gui.CloseModal()
                    end,
                },
            }
        }
    }

    gui.ShowModal(dialogPanel)

end

local function isClockwise(polygon)
    local sum = 0
    local n = #polygon

    for i = 1, n do
        local j = (i % n) + 1
        sum = sum + (polygon[j].x - polygon[i].x) * (polygon[j].y + polygon[i].y)
    end

    return sum > 0
end

mod.shared.ImportMapToFloorCo = function(info)

    print("IMPORT:: IMPORTING:", info, info.floor.name, info.primaryFloor.name)

    local obj = info.floor:SpawnObjectLocal(info.objid)
    if obj == nil then
        printf("IMPORT:: Could not spawn object with id = %s", info.objid)
        return
    end

    obj.x = 0
    obj.y = 0
    obj:Upload()

    local pointsEqual = function(a,b)
        return a.x == b.x and a.y == b.y
    end

    if info.uvttData ~= nil then
        dmhub.Debug("HAS UVTT DATA")
        local maxcount = 0
        while (obj.area == nil or (obj.area.x1 == 0 and obj.area.x2 == 0)) and maxcount < 20 do
            coroutine.yield(0.1)
            maxcount = maxcount + 1
        end

        --wait a few frames to make sure the object is in sync.
        maxcount = 0
        while maxcount < 60 do
            coroutine.yield(0.01)
            maxcount = maxcount + 1
        end

        local area = obj.area
        if area ~= nil then

            local data = info.uvttData

            local portals = data.portals
            local line_of_sight = data.line_of_sight
            local convertedFromFoundry = false

            if line_of_sight == nil and data.walls ~= nil then
                --foundry format walls.
                convertedFromFoundry = true
                line_of_sight = {}
                portals = {}

                for i,wall in ipairs(data.walls) do
                    local points = wall.c

                    if points ~= nil and type(points) == "table" and #points == 4 then
                        line_of_sight[#line_of_sight+1] = {
                            {x = points[1]/data.grid, y = points[2]/data.grid},
                            {x = points[3]/data.grid, y = points[4]/data.grid},
                        }

                        if wall.door == 1 then
                            portals[#portals+1] = {
                                bounds = {
                                    {x = points[1]/data.grid, y = points[2]/data.grid},
                                    {x = points[3]/data.grid, y = points[4]/data.grid},
                                },
                                closed = true,
                            }
                        end
                    end
                end
            end

            local wallAsset = "-MGADhKw0vw30yXNF2-e"
            local objectWallAsset = "eae7f3fe-d278-455c-853a-ac43f948c743"
            for i,line_of_sight in ipairs({data.line_of_sight, data.objects_line_of_sight}) do
                local objectWalls = (i == 2)

                if line_of_sight ~= nil then

            print("LINE_OF_SIGHT::", line_of_sight)



                    --uvtt format walls.
                    local segments = DeepCopy(line_of_sight)
                    local segmentsDeleted = {}

                    local changes = true
                    local ncount = 0

                    while (not objectWalls) and changes and ncount < 50 do
                        changes = false
                        ncount = ncount+1
                    
                        for i,segment in ipairs(segments) do
                            if segmentsDeleted[i] == nil then
                                for j,nextSegment in ipairs(segments) do
                                    if i ~= j and segmentsDeleted[j] == nil and pointsEqual(segment[#segment], nextSegment[1]) then
                                        for _,point in ipairs(nextSegment) do
                                            segment[#segment+1] = point
                                        end

                                        segmentsDeleted[j] = true
                                        changes = true
                                    end
                                end
                            end
                        end
                    end

                    print("SEGMENTS::", segments)

                    local polygons = {}
                    for i,seg in ipairs(segments) do
                        if segmentsDeleted[i] == nil then
                            if objectWalls and (not isClockwise(seg)) and pointsEqual(seg[1], seg[#seg]) then
                                local objectPoints = {}
                                for j=#seg,1,-1 do
                                    objectPoints[#objectPoints+1] = seg[j]
                                end
                                polygons[#polygons+1] = objectPoints
                            else
                                polygons[#polygons+1] = seg
                            end
                        end
                    end

                    print("POLYGONS::", polygons)

                    local pointsList = {}
                    local objectsPointsList = {}

                    for j,poly in ipairs(polygons) do
                        local points = {}

                        local isObject = objectWalls and pointsEqual(poly[1], poly[#poly])

                        for i,p in ipairs(poly) do
                            if (not isObject) or i ~= #poly then
                                points[#points+1] = area.x1 + tonumber(p.x)
                                points[#points+1] = area.y2 - tonumber(p.y)

                                if j == 1 and i == 1 then
                                    print("FIRST::", #polygons, #poly, points, "FROM", area.x1, area.y2, p.x, p.y, "isobject =", isObject)
                                end
                            end
                        end

                        if not isObject then
                            pointsList[#pointsList+1] = points
                        else
                            objectsPointsList[#objectsPointsList+1] = points
                        end
                    end

                    if #pointsList > 0 then
                        print("POLY::", area, pointsList)
                        info.primaryFloor:ExecutePolygonOperation{
                            points = pointsList,
                            tileid = nil,
                            wallid = wallAsset,
                            erase = false,
                            closed = false,
                        }
                    end

                    if #objectsPointsList > 0 then
                        print("POLY::", objectsPointsList)
                        info.primaryFloor:ExecutePolygonOperation{
                            points = objectsPointsList,
                            tileid = nil,
                            wallid = objectWallAsset,
                            erase = false,
                            closed = true,
                        }
                    end

                end
            end

            local windownode = "-MDd3Knydcq2WsjStef2"
            local doornode = "-MfWx0b2IlyApLQwasYg"
            if portals ~= nil then
                for i,portal in ipairs(portals) do
                    local bounds = portal.bounds
                    if bounds ~= nil and #bounds == 2 then
                        --add a wall in here.
                        local points = {area.x1 + tonumber(bounds[1].x), area.y2 - tonumber(bounds[1].y),
                                        area.x1 + tonumber(bounds[2].x), area.y2 - tonumber(bounds[2].y)}

                        if not convertedFromFoundry then
                            info.primaryFloor:ExecutePolygonOperation{
                                points = {points},
                                tileid = nil,
                                wallid = "-MGADhKw0vw30yXNF2-e",
                                erase = false,
                                closed = false,
                            }
                        end

                        local obj = info.primaryFloor:SpawnObjectLocal(cond(portal.closed, doornode, windownode))
                        obj.x = area.x1 + tonumber(bounds[1].x)
                        obj.y = area.y2 - tonumber(bounds[1].y)

                        --note y axis is intentionally inverted.
                        local delta = core.Vector2(bounds[2].x - bounds[1].x, bounds[1].y - bounds[2].y)

                        obj.rotation = delta.angle + 90
                        obj.scale = delta.length*cond(portal.closed, 0.7, 1)

                        dmhub.Debug(string.format("SPAWN_OBJ: %f, %f", obj.x, obj.y))
                        obj:Upload()
                    end
                end
            end

            --lights can be in either of these formats:
            -- uvtt: (here units are in tiles)
            -- { position: { x: number, y: number }, range: number, intensity: number, color: string, shadows: boolean }
            -- foundry: (here units are in pixels)
            -- { x: number, y: number, dim: number, bright: number, tintColor: string, tintAlpha: number }
@if MCDM
            local lightnode = "2339211c-c35a-4e0a-a5fa-79d2e446bd3b"
@else
            local lightnode = "-MGBXtOnKAXNhhLK89_9"
@end
            if data.lights ~= nil then -- always use any lights regardless of baked_lighting setting? --and (data.environment == nil or not data.environment.baked_lighting) then
                for i,light in ipairs(data.lights) do
                    local obj = info.floor:SpawnObjectLocal(lightnode)
                    local component = obj:GetComponent("Light")

                    if light.position ~= nil then
                        --uvtt format.
                        obj.x = area.x1 + light.position.x
                        obj.y = area.y2 - light.position.y

                        component:SetProperty("radius", tonumber(light.range))
                        component:SetProperty("intensity", ((tonumber(light.intensity) or 1)*0.5)^0.5)
                        component:SetProperty("castsShadows", light.shadows)
                        component:SetProperty("color", core.Color("#" .. light.color))
                    else
                        --foundry format.
                        obj.x = area.x1 + light.x/data.grid
                        obj.y = area.y2 - light.y/data.grid


                        component:SetProperty("radius", light.dim)
                        component:SetProperty("intensity", (light.tintAlpha or 0.1)*3)
                        component:SetProperty("color", core.Color(light.tintColor or "#ffffff"))
                        printf("ADDED LIGHT: %s", json(light))
                    end

                    obj:Upload()
                end
            end

            if data.environment ~= nil then
                if data.environment.ambient_light ~= nil then
                    local ambientColor = core.Color("#" .. data.environment.ambient_light)
                    dmhub.SetSettingValue("undergroundillumination", ambientColor.value)
                else
                    dmhub.SetSettingValue("undergroundillumination", 1.0)
                end
            end
        end
    end


end

mod.shared.FinishMapImport = function(mapName, info)
    local floors = {}

    for i,objid in ipairs(info.objids) do
        floors[#floors+1] = {
            description = cond(#info.objids == 1, "Main Floor", string.format("Floor %d", i)),
            layerDescription = "Map Layer",
            parentFloor = #floors+1,
        }

        floors[#floors+1] = {
            description = cond(#info.objids == 1, "Main Floor", string.format("Floor %d", i)),
        }
    end


    local guid = game.CreateMap{
        description = mapName,
        groundLevel = #floors,
        floors = floors,
    }
    dmhub.Coroutine(function()
        dmhub.Debug("INSTANCE OBJECT START")
        while game.GetMap(guid) == nil do
            coroutine.yield(0.05)
        end

        local w = math.ceil(info.width)
        local h = math.ceil(info.height)

        printf("DIMENSIONS:: %s / %s", json(info.width), json(info.height))

        local map = game.GetMap(guid)
        map.description = mapName
        map.dimensions = {
            x1 = -math.ceil(w/2) + 1,
            y1 = -math.ceil(h/2) + 1,
            x2 = math.ceil(w/2) - 1,
            y2 = math.ceil(h/2),
        }
        map:Upload()

        map:Travel()
        dmhub.Debug("INSTANCE OBJECT NEXT")

        while game.currentMapId ~= guid do
            coroutine.yield(0.05)
        end

        --try to wait a bit to make sure we are synced on the new map.
        for i=1,120 do
            coroutine.yield(0.01)
        end

        local settings = info.mapSettings
        if settings ~= nil then
            for k,v in pairs(settings) do
                dmhub.SetSettingValue(k, v)
                printf("SETTING: Set %s -> %s", json(k), json(v))
            end
        end

        local floors = game.currentMap.floorsWithoutLayers

        for i,floor in ipairs(floors) do
            local uvttData = nil
            if info.uvttData ~= nil then
                uvttData = info.uvttData[i]
            end

            --send to the map layer instead of the primary floor.
            local targetFloor = floor
            for i,layer in ipairs(game.currentMap.floors) do
                if layer.parentFloor == floor.floorid then
                    targetFloor = layer
                    break
                end
            end

            mod.shared.ImportMapToFloorCo{
                objid = info.objids[i],
                floor = targetFloor,
                primaryFloor = floor,
                uvttData = uvttData,
            }
        end

    end)
end

-- Show a dialog to let the user align a new floor image to the existing map.
-- info: the import result with objids, width, height, paths, imageWidth, imageHeight.
mod.shared.ShowFloorAlignmentDialog = function(info)
    if info.objids == nil or #info.objids == 0 then
        return
    end

    local currentMap = game.currentMap
    if currentMap == nil then
        return
    end

    local dim = currentMap.dimensions
    local mapW = dim.x2 - dim.x1
    local mapH = dim.y2 - dim.y1
    local floorW = math.ceil(info.width)
    local floorH = math.ceil(info.height)

    -- Default: align top-left corners.
    local offsetX = dim.x1
    local offsetY = dim.y1

    -- Check if the new floor is the same size as the existing map.
    printf("FLOOR_ALIGN:: ShowFloorAlignmentDialog called: mapW=%d mapH=%d floorW=%d floorH=%d", mapW, mapH, floorW, floorH)
    printf("FLOOR_ALIGN:: Existing map dims: x1=%s y1=%s x2=%s y2=%s", json(dim.x1), json(dim.y1), json(dim.x2), json(dim.y2))
    printf("FLOOR_ALIGN:: Default offset: (%d, %d)", offsetX, offsetY)

    local sameSize = (floorW == mapW and floorH == mapH)

    if sameSize then
        printf("FLOOR_ALIGN:: Same size detected, skipping alignment dialog")
        mod.shared.FinishFloorImport(info, offsetX, offsetY)
        return
    end

    -- Find the existing map's floor image for display.
    -- Look for a map object on the ground floor's map layer.
    local existingImageId = nil
    local floors = currentMap.floorsWithoutLayers
    if #floors > 0 then
        for _, floor in ipairs(currentMap.floors) do
            for _, obj in pairs(floor.objects) do
                if obj:GetComponent("Map") ~= nil then
                    existingImageId = obj.imageid
                    break
                end
            end
            if existingImageId ~= nil then break end
        end
    end

    -- The new floor's image: use the first imported asset's imageid.
    local newImageId = info.objids[1]

    local newFloorOpacity = 0.6

    -- Build the alignment UI.
    local previewLabel
    local previewPanel

    local function fireUpdatePreview()
        if previewLabel == nil or previewPanel == nil then
            return
        end
        previewLabel:FireEvent("updatePreview")
        previewPanel:FireEvent("updatePreview")
    end

    local offsetXInput = gui.Input{
        fontSize = 18,
        width = 60,
        height = 24,
        text = tostring(offsetX),
        edit = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val == math.floor(val) then
                offsetX = val
                fireUpdatePreview()
            end
        end,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val == math.floor(val) then
                offsetX = val
            else
                element.text = tostring(offsetX)
            end
            fireUpdatePreview()
        end,
    }

    local offsetYInput = gui.Input{
        fontSize = 18,
        width = 60,
        height = 24,
        text = tostring(offsetY),
        edit = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val == math.floor(val) then
                offsetY = val
                fireUpdatePreview()
            end
        end,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val == math.floor(val) then
                offsetY = val
            else
                element.text = tostring(offsetY)
            end
            fireUpdatePreview()
        end,
    }

    previewLabel = gui.Label{
        width = "100%",
        height = "auto",
        fontSize = 14,
        color = "#cccccc",
        wrap = true,
        halign = "left",
        text = "",

        updatePreview = function(element)
            local newX2 = offsetX + floorW
            local newY2 = offsetY + floorH

            local canvasX1 = math.min(dim.x1, offsetX)
            local canvasY1 = math.min(dim.y1, offsetY)
            local canvasX2 = math.max(dim.x2, newX2)
            local canvasY2 = math.max(dim.y2, newY2)
            local canvasW = canvasX2 - canvasX1
            local canvasH = canvasY2 - canvasY1

            local needsExpand = (canvasX1 < dim.x1 or canvasY1 < dim.y1 or canvasX2 > dim.x2 or canvasY2 > dim.y2)

            local lines = {}
            lines[#lines+1] = string.format("New floor at (%d, %d) to (%d, %d).", offsetX, offsetY, newX2, newY2)
            if needsExpand then
                lines[#lines+1] = string.format("Map canvas will expand to %dx%d tiles.", canvasW, canvasH)
            else
                lines[#lines+1] = "New floor fits within the existing canvas."
            end

            element.text = table.concat(lines, " ")
        end,
    }

    -- The preview area: shows actual images of both floors with grid overlay.
    -- Supports mouse wheel zoom, right-drag to pan, left-drag to move new floor.
    local previewSize = 700

    -- View state: zoom level and center position in tile coordinates.
    -- Start zoomed out to fit everything.
    local canvasX1Init = math.min(dim.x1, offsetX)
    local canvasY1Init = math.min(dim.y1, offsetY)
    local canvasX2Init = math.max(dim.x2, offsetX + floorW)
    local canvasY2Init = math.max(dim.y2, offsetY + floorH)
    local canvasWInit = canvasX2Init - canvasX1Init
    local canvasHInit = canvasY2Init - canvasY1Init

    local viewCenterX = (canvasX1Init + canvasX2Init) / 2
    local viewCenterY = (canvasY1Init + canvasY2Init) / 2
    -- Pixels per tile at zoom=1: fit the initial canvas with padding.
    local basePixelsPerTile = (previewSize - 20) / (math.max(canvasWInit, canvasHInit) * 1.1)
    local viewZoom = 1.0
    local minZoom = 0.5
    local maxZoom = 20.0

    -- Drag state for moving the new floor.
    local isDraggingFloor = false
    local dragStartOffsetX = 0
    local dragStartOffsetY = 0
    -- Pan drag state: track the view center at drag start.
    local panStartCenterX = 0
    local panStartCenterY = 0

    local function getPixelsPerTile()
        return basePixelsPerTile * viewZoom
    end

    -- Convert tile coords to pixel coords in the preview panel.
    -- Map coords: +X right, +Y UP. Panel coords: +X right, +Y DOWN.
    -- So we negate Y to flip the vertical axis.
    local function tileToPixel(tx, ty)
        local ppt = getPixelsPerTile()
        local cx = previewSize / 2
        local cy = previewSize / 2
        return cx + (tx - viewCenterX) * ppt, cy - (ty - viewCenterY) * ppt
    end

    -- Convert pixel coords in the preview panel to tile coords.
    local function pixelToTile(px, py)
        local ppt = getPixelsPerTile()
        local cx = previewSize / 2
        local cy = previewSize / 2
        return viewCenterX + (px - cx) / ppt, viewCenterY - (py - cy) / ppt
    end

    local function updateInputsFromOffset()
        offsetXInput.textNoNotify = tostring(offsetX)
        offsetYInput.textNoNotify = tostring(offsetY)
    end

    -- Get panel top-left pixel position for a tile rect.
    -- Map coords: +Y up. Panel coords: +Y down.
    -- The top of the rect (tileY + tileH, highest Y) maps to the smallest pixel Y.
    local function rectToPanel(tileX, tileY, tileW, tileH)
        local ppt = getPixelsPerTile()
        local px, _ = tileToPixel(tileX, 0)
        local _, py = tileToPixel(0, tileY + tileH)
        return px, py, tileW * ppt, tileH * ppt
    end

    previewPanel = gui.Panel{
        width = previewSize,
        height = previewSize,
        halign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#111111",
        flow = "none",
        borderColor = "#555555",
        borderWidth = 1,
        clip = true,

        -- Dragging: right-drag to pan, left-drag to move new floor.
        draggable = true,
        dragMove = false,
        dragThreshold = 2,

        events = {
            press = function(element)
                local mp = element.mousePoint
                -- mousePoint: (0,0) at panel center, +y up (Unity convention).
                -- Convert to panel pixel coords where (0,0) is top-left, +y down.
                local mx = mp.x + previewSize / 2
                local my = previewSize / 2 - mp.y

                -- Middle mouse or right mouse always pans.
                if element:GetMouseButton(1) or element:GetMouseButton(2) then
                    isDraggingFloor = false
                    panStartCenterX = viewCenterX
                    panStartCenterY = viewCenterY
                    return
                end

                -- Left mouse: check if over the new floor image.
                local nx, ny, nw, nh = rectToPanel(offsetX, offsetY, floorW, floorH)
                if mx >= nx and mx <= nx + nw and my >= ny and my <= ny + nh then
                    isDraggingFloor = true
                    dragStartOffsetX = offsetX
                    dragStartOffsetY = offsetY
                else
                    isDraggingFloor = false
                    panStartCenterX = viewCenterX
                    panStartCenterY = viewCenterY
                end
            end,

            dragging = function(element)
                -- dragDelta is cumulative from drag start, in panel pixel coords.
                local dd = element.dragDelta
                -- Convert pixel delta to tile delta using pixelToTile math.
                -- pixelToTile: tileX = viewCenterX + (px - cx) / ppt
                -- So a pixel delta of dd.x maps to tile delta of dd.x / ppt (for X)
                -- and dd.y maps to tile delta of -dd.y / ppt (for Y, because Y is flipped)
                local ppt = getPixelsPerTile()
                local dtx = dd.x / ppt
                local dty = -dd.y / ppt  -- negate: panel +y is down, tile +y is up
                if isDraggingFloor then
                    -- Move the new floor, snapping to tile boundaries.
                    local newOX = dragStartOffsetX + math.floor(dtx + 0.5)
                    local newOY = dragStartOffsetY + math.floor(dty + 0.5)
                    if newOX ~= offsetX or newOY ~= offsetY then
                        offsetX = newOX
                        offsetY = newOY
                        updateInputsFromOffset()
                        fireUpdatePreview()
                    end
                else
                    -- Pan the view using cumulative delta from start.
                    viewCenterX = panStartCenterX - dtx
                    viewCenterY = panStartCenterY - dty
                    element:FireEvent("updatePreview")
                end
            end,

            drag = function(element)
                -- Drag ended.
                isDraggingFloor = false
                fireUpdatePreview()
            end,
        },

        -- Mouse wheel zoom.
        thinkTime = 0.02,
        think = function(element)
            local wheel = dmhub.mouseWheel
            if wheel ~= 0 and element.mousePoint.x ~= 0 and element.mousePoint.y ~= 0 then
                -- Zoom toward mouse position.
                local mp = element.mousePoint
                -- mousePoint: +y up. Convert to panel pixel coords: +y down.
                local mx = mp.x + previewSize / 2
                local my = previewSize / 2 - mp.y
                local tileBefore_x, tileBefore_y = pixelToTile(mx, my)

                if wheel > 0 then
                    viewZoom = math.min(maxZoom, viewZoom * 1.15)
                else
                    viewZoom = math.max(minZoom, viewZoom / 1.15)
                end

                -- Adjust center so the tile under the mouse stays in place.
                local tileAfter_x, tileAfter_y = pixelToTile(mx, my)
                viewCenterX = viewCenterX + (tileBefore_x - tileAfter_x)
                viewCenterY = viewCenterY + (tileBefore_y - tileAfter_y)

                element:FireEvent("updatePreview")
            end
        end,

        updatePreview = function(element)
            local ppt = getPixelsPerTile()

            local children = {}

            -- Existing map image.
            if existingImageId ~= nil then
                local ex, ey, ew, eh = rectToPanel(dim.x1, dim.y1, mapW, mapH)
                children[#children+1] = gui.Panel{
                    bgimage = existingImageId,
                    bgimageStreamed = existingImageId,
                    bgcolor = "white",
                    halign = "left", valign = "top",
                    x = ex, y = ey,
                    width = ew, height = eh,
                }
            end

            -- New floor image.
            if newImageId ~= nil then
                local nx, ny, nw, nh = rectToPanel(offsetX, offsetY, floorW, floorH)
                children[#children+1] = gui.Panel{
                    bgimage = newImageId,
                    bgimageInit = true,
                    bgcolor = "white",
                    opacity = newFloorOpacity,
                    halign = "left", valign = "top",
                    x = nx, y = ny,
                    width = nw, height = nh,
                }
            end

            -- Grid lines: only draw visible ones.
            -- Compute visible tile range from viewport.
            local visTileX1, visTileY1 = pixelToTile(0, 0)
            local visTileX2, visTileY2 = pixelToTile(previewSize, previewSize)
            -- Ensure x1 < x2, y1 < y2.
            if visTileX1 > visTileX2 then visTileX1, visTileX2 = visTileX2, visTileX1 end
            if visTileY1 > visTileY2 then visTileY1, visTileY2 = visTileY2, visTileY1 end

            local gridX1 = math.floor(visTileX1)
            local gridX2 = math.ceil(visTileX2)
            local gridY1 = math.floor(visTileY1)
            local gridY2 = math.ceil(visTileY2)

            -- Skip grid lines if too dense (more than ~200 visible).
            local gridCountX = gridX2 - gridX1
            local gridCountY = gridY2 - gridY1
            if gridCountX <= 200 and gridCountY <= 200 then
                -- Determine grid line thickness based on zoom.
                local lineW = math.max(1, math.floor(ppt / 32))

                -- Vertical grid lines.
                for tx = gridX1, gridX2 do
                    local px, _ = tileToPixel(tx, 0)
                    children[#children+1] = gui.Panel{
                        bgimage = "panels/square.png",
                        bgcolor = "#ffffff18",
                        halign = "left", valign = "top",
                        x = px, y = 0,
                        width = lineW, height = previewSize,
                    }
                end

                -- Horizontal grid lines.
                for ty = gridY1, gridY2 do
                    local _, py = tileToPixel(0, ty)
                    children[#children+1] = gui.Panel{
                        bgimage = "panels/square.png",
                        bgcolor = "#ffffff18",
                        halign = "left", valign = "top",
                        x = 0, y = py,
                        width = previewSize, height = lineW,
                    }
                end
            end

            -- Existing map border.
            do
                local bx, by, bw, bh = rectToPanel(dim.x1, dim.y1, mapW, mapH)
                children[#children+1] = gui.Panel{
                    halign = "left", valign = "top",
                    x = bx, y = by,
                    width = bw, height = bh,
                    borderColor = "#6699cc",
                    borderWidth = 2,
                }
            end

            -- New floor border.
            do
                local bx, by, bw, bh = rectToPanel(offsetX, offsetY, floorW, floorH)
                children[#children+1] = gui.Panel{
                    halign = "left", valign = "top",
                    x = bx, y = by,
                    width = bw, height = bh,
                    borderColor = "#cc9966",
                    borderWidth = 2,
                }
            end

            element.children = children
        end,
    }

    local opacitySlider = gui.Slider{
        style = {
            height = 20,
            width = 200,
            fontSize = 14,
        },
        halign = "left",
        sliderWidth = 140,
        labelWidth = 60,
        labelFormat = "percent",
        minValue = 0,
        maxValue = 100,
        value = 60,
        change = function(element)
            newFloorOpacity = element.value * 0.01
            fireUpdatePreview()
        end,
    }

    local function resetView()
        local cx1 = math.min(dim.x1, offsetX)
        local cy1 = math.min(dim.y1, offsetY)
        local cx2 = math.max(dim.x2, offsetX + floorW)
        local cy2 = math.max(dim.y2, offsetY + floorH)
        viewCenterX = (cx1 + cx2) / 2
        viewCenterY = (cy1 + cy2) / 2
        local cw = cx2 - cx1
        local ch = cy2 - cy1
        basePixelsPerTile = (previewSize - 20) / (math.max(cw, ch) * 1.1)
        viewZoom = 1.0
        fireUpdatePreview()
    end

    local controlsPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        vmargin = 4,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",

                gui.Label{
                    width = "auto",
                    height = "auto",
                    fontSize = 16,
                    text = "Top-left at tile: ",
                },
                offsetXInput,
                gui.Label{
                    width = "auto",
                    height = "auto",
                    fontSize = 16,
                    text = " , ",
                },
                offsetYInput,
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                hmargin = 16,

                gui.Label{
                    width = "auto",
                    height = "auto",
                    fontSize = 16,
                    text = "Opacity: ",
                },
                opacitySlider,
            },

            gui.PrettyButton{
                text = "Reset View",
                width = 100,
                height = 28,
                fontSize = 14,
                halign = "right",
                click = function()
                    resetView()
                end,
            },
        },

        gui.Label{
            width = "auto",
            height = "auto",
            fontSize = 12,
            color = "#888888",
            text = "Drag the new floor to position it. Scroll to zoom. Middle-click drag or drag background to pan.",
        },
    }

    local dialogPanel = gui.Panel{
        id = "alignDialog",
        classes = {"framedPanel"},
        width = 1000,
        height = 900,
        pad = 16,
        flow = "vertical",
        styles = {
            Styles.Default,
            Styles.Panel,
        },

        gui.Label{
            classes = {"dialogTitle"},
            text = "Align New Floor",
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 4,

            gui.Label{
                width = "auto",
                height = "auto",
                fontSize = 14,
                text = string.format("Existing map: %dx%d tiles  |  New floor: %dx%d tiles", mapW, mapH, floorW, floorH),
            },
        },

        previewPanel,

        controlsPanel,
        previewLabel,

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            halign = "center",
            vmargin = 8,

            gui.PrettyButton{
                text = "Confirm",
                width = 160,
                height = 50,
                click = function()
                    printf("FLOOR_ALIGN:: Confirm clicked: offsetX=%d offsetY=%d", offsetX, offsetY)
                    gui.CloseModal()
                    mod.shared.FinishFloorImport(info, offsetX, offsetY)
                end,
            },

            gui.PrettyButton{
                text = "Cancel",
                width = 160,
                height = 50,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                end,
            },
        },

        gui.CloseButton{
            halign = "right",
            valign = "top",
            floating = true,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function()
                gui.CloseModal()
            end,
        },

        create = function(element)
            fireUpdatePreview()
        end,
    }

    gui.ShowModal(dialogPanel)
end

-- Reimport map sizing: re-run the grid calibration on an existing map object.
-- floor: the MapFloorLua that contains the map object
-- mapObj: the LuaObjectInstance with a Map component
mod.shared.ReimportMapSizing = function(floor, mapObj)
    local imageId = mapObj.imageid
    if imageId == nil or imageId == "" then
        gui.ModalMessage{
            title = "Error",
            message = "Could not find image for this map object.",
        }
        return
    end

    -- Capture the current object's tile dimensions for gridless defaults.
    local currentArea = mapObj.area
    local currentTilesW = nil
    local currentTilesH = nil
    if currentArea ~= nil then
        currentTilesW = math.abs(currentArea.x2 - currentArea.x1)
        currentTilesH = math.abs(currentArea.y2 - currentArea.y1)
        printf("REIMPORT:: Current object area: (%.1f,%.1f)-(%.1f,%.1f) = %.1fx%.1f tiles",
            currentArea.x1, currentArea.y1, currentArea.x2, currentArea.y2, currentTilesW, currentTilesH)
    end

    printf("REIMPORT:: Starting reimport for object %s on floor %s, imageId=%s", mapObj.id, floor.floorid, imageId)

    -- Build a reimport dialog using gui.MapImport with imageFromId.
    local resultPanel
    local importPanel
    local gridlessInitApplied = false

    local confirmButton = gui.PrettyButton{
        classes = {"hidden"},
        text = "Apply",
        height = 50,
        width = 180,
        valign = "center",
        halign = "center",
        click = function()
            -- Get calibration data from the import panel before closing.
            local calibration = importPanel:GetCalibrationData()
            if calibration == nil then
                gui.ModalMessage{
                    title = "Error",
                    message = "Calibration data not available. Please complete the grid sizing.",
                }
                return
            end

            printf("REIMPORT:: Applying calibration: width=%.1f height=%.1f scaling=%d controlPoints=%d",
                calibration.width, calibration.height, calibration.scaling, #calibration.controlPoints)

            -- Apply the calibration directly to the existing object's Map component
            -- using the C# method (avoids JSON serialization issues with Vector2 lists).
            mapObj:MarkUndo()
            importPanel:ApplyCalibrationTo(mapObj)

            gui.CloseModal()

            mapObj:Upload()

            printf("REIMPORT:: Applied new calibration to object %s", mapObj.id)

            -- Adjust map boundaries synchronously.
            -- For the reimported floor: compute bounds from calibration data + object center
            -- (don't read obj.area which is stale until re-render).
            -- For other floors: read their area directly (they haven't changed).
            local map = game.currentMap
            if map ~= nil then
                local objX = mapObj.x
                local objY = mapObj.y
                local floorX1 = objX - calibration.width / 2
                local floorY1 = objY - calibration.height / 2
                local floorX2 = objX + calibration.width / 2
                local floorY2 = objY + calibration.height / 2
                printf("REIMPORT:: Reimported floor bounds: (%.1f,%.1f)-(%.1f,%.1f) objPos=(%.1f,%.1f)",
                    floorX1, floorY1, floorX2, floorY2, objX, objY)

                -- Start with the reimported floor's computed bounds.
                local newDimX1 = floorX1
                local newDimY1 = floorY1
                local newDimX2 = floorX2
                local newDimY2 = floorY2

                -- Union with all other map objects' areas (these are already rendered, not stale).
                for _, f in ipairs(map.floors) do
                    for _, obj in pairs(f.objects) do
                        if obj:GetComponent("Map") ~= nil and obj.id ~= mapObj.id then
                            local a = obj.area
                            if a ~= nil then
                                printf("REIMPORT::   Other floor obj %s area: (%.1f,%.1f)-(%.1f,%.1f)", obj.id, a.x1, a.y1, a.x2, a.y2)
                                newDimX1 = math.min(newDimX1, a.x1)
                                newDimY1 = math.min(newDimY1, a.y1)
                                newDimX2 = math.max(newDimX2, a.x2)
                                newDimY2 = math.max(newDimY2, a.y2)
                            end
                        end
                    end
                end

                local dim = map.dimensions
                printf("REIMPORT:: Old dims: (%s,%s)-(%s,%s)", json(dim.x1), json(dim.y1), json(dim.x2), json(dim.y2))
                printf("REIMPORT:: New dims: (%.1f,%.1f)-(%.1f,%.1f)", newDimX1, newDimY1, newDimX2, newDimY2)

                map.dimensions = {
                    x1 = math.floor(newDimX1),
                    y1 = math.floor(newDimY1),
                    x2 = math.ceil(newDimX2),
                    y2 = math.ceil(newDimY2),
                }
                map:Upload("Adjust map boundaries after reimport")
                printf("REIMPORT:: Set map boundaries to (%d,%d)-(%d,%d)",
                    math.floor(newDimX1), math.floor(newDimY1), math.ceil(newDimX2), math.ceil(newDimY2))
            end
        end,
    }

    local continueButton = gui.PrettyButton{
        classes = {"hidden"},
        text = "Continue>>",
        height = 50,
        width = 180,
        valign = "center",
        halign = "center",
        click = function()
            importPanel:Next()
        end,
    }

    local previousButton = gui.PrettyButton{
        classes = {"hidden"},
        text = "Back",
        height = 50,
        width = 180,
        valign = "center",
        halign = "left",
        click = function()
            importPanel:Previous()
        end,
    }

    local buttonsPanel = gui.Panel{
        valign = "bottom",
        halign = "center",
        width = "70%",
        height = "auto",
        flow = "none",
        previousButton,
        continueButton,
        confirmButton,
    }

    local instructionsText = gui.Label{
        width = 400,
        height = "auto",
        wrap = true,
        textAlignment = "topleft",
        fontSize = 18,
        halign = "left",
        valign = "top",
    }

    local gridlessChoice = gui.EnumeratedSliderControl{
        options = {
            {id = true, text = "Grid"},
            {id = false, text = "Gridless"},
        },
        width = 400,
        valign = "top",
        value = true,
        change = function(element)
            if element.value == true then
                importPanel:ClearMarkers()
            else
                importPanel:CreateGridless()
                -- Apply current tile dimensions as the default for gridless mode.
                if currentTilesW ~= nil and currentTilesW > 0 and currentTilesH ~= nil and currentTilesH > 0 then
                    local imgW = importPanel.imageWidth
                    local imgH = importPanel.imageHeight
                    if imgW ~= nil and imgW > 0 and imgH ~= nil and imgH > 0 then
                        local tilePixelW = imgW / currentTilesW
                        local tilePixelH = imgH / currentTilesH
                        importPanel:SetWidth(tilePixelW)
                        importPanel:SetHeight(tilePixelH)
                        printf("REIMPORT:: Set gridless defaults: %.1fx%.1f px/tile (%.0fx%.0f tiles)", tilePixelW, tilePixelH, currentTilesW, currentTilesH)
                    end
                end
            end
        end,
        vmargin = 16,
    }

    local instructionsPanel = gui.Panel{
        width = 400,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        instructionsText,
        gridlessChoice,
    }

    local statusWidth = gui.Input{
        fontSize = 16, width = 80, height = 24,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val >= 8 and val <= 4096 then
                importPanel:SetWidth(val)
            end
        end,
    }
    local statusHeight = gui.Input{
        fontSize = 16, width = 80, height = 24,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val >= 8 and val <= 4096 then
                importPanel:SetHeight(val)
            end
        end,
    }

    local statusPanel = gui.Panel{
        classes = {"hidden"},
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",

        gui.Label{
            width = "auto",
            height = "auto",
            halign = "center",
            fontSize = 22,
            bold = true,
            text = "Tile Dimensions",
        },

        gui.Panel{
            flow = "horizontal", width = "auto", height = "auto",
            gui.Label{ width = 90, height = "auto", text = "Width:", fontSize = 18 },
            statusWidth,
            gui.Label{ width = "auto", height = "auto", text = "px", fontSize = 18 },
        },

        gui.Panel{
            flow = "horizontal", width = "auto", height = "auto",
            gui.Label{ width = 90, height = "auto", text = "Height:", fontSize = 18 },
            statusHeight,
            gui.Label{ width = "auto", height = "auto", text = "px", fontSize = 18 },
        },
    }

    local zoomSlider = gui.Slider{
        style = { height = 20, width = 200, fontSize = 14 },
        halign = "right",
        valign = "top",
        sliderWidth = 140,
        labelWidth = 60,
        labelFormat = "percent",
        minValue = 0,
        maxValue = 100,
        value = 100,
        thinkTime = 0.1,
        change = function(element)
            importPanel.zoom = element.value * 0.01
        end,
        think = function(element)
            if not element.dragging then
                element.data.setValueNoEvent(importPanel.zoom * 100)
            end
        end,
    }

    -- Create the MapImport panel, loading from the cloud image ID.
    importPanel = gui.MapImport{
        width = 800,
        height = 800,
        halign = "right",
        valign = "top",
        y = 26,
        tileType = "squares",
        imageFromId = imageId,

        thinkTime = 0.05,
        think = function(element)
            gridlessChoice:SetClass("hidden", gridlessChoice.value and (element.haveNext or element.havePrevious or element.haveConfirm or not string.starts_with(element.instructionsText, "Pick a grid square")))
            previousButton:SetClass("hidden", not element.havePrevious)
            continueButton:SetClass("hidden", not element.haveNext)
            confirmButton:SetClass("hidden", not element.haveConfirm)
            instructionsText.text = element.instructionsText

            local tileDim = element.tileDim
            if tileDim == nil then
                statusPanel:SetClass("hidden", true)
            else
                statusPanel:SetClass("hidden", false)
                if (not statusWidth.hasInputFocus) and (not statusHeight.hasInputFocus) then
                    statusWidth.textNoNotify = string.format("%.2f", tileDim.x)
                    statusHeight.textNoNotify = string.format("%.2f", tileDim.y)
                end
            end

            if element.error ~= nil then
                resultPanel.children = {
                    gui.Label{
                        halign = "center", valign = "center",
                        width = "auto", height = "auto",
                        fontSize = 18, color = "white",
                        text = string.format("Error: %s", element.error),
                    }
                }
            end
        end,
    }

    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        flow = "none",
        zoomSlider,
        importPanel,
        buttonsPanel,
        instructionsPanel,
        statusPanel,
    }

    local dialogPanel = gui.Panel{
        classes = {"framedPanel"},
        width = 1400,
        height = 940,
        pad = 8,
        flow = "vertical",
        styles = {
            Styles.Default,
            Styles.Panel,
        },

        gui.Label{
            classes = {"dialogTitle"},
            text = "Reimport Map Sizing",
        },

        resultPanel,

        gui.CloseButton{
            halign = "right",
            valign = "top",
            floating = true,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function()
                gui.CloseModal()
            end,
        },
    }

    gui.ShowModal(dialogPanel)
end

-- Import a floor image into the current map as a new floor.
-- Creates a primary floor + a map layer on it (matching initial map import structure).
-- info: import result with objids, width, height, mapSettings.
-- offsetX, offsetY: tile position for the new floor's top-left corner.
mod.shared.FinishFloorImport = function(info, offsetX, offsetY)
    printf("FLOOR_IMPORT:: ===== BEGIN FinishFloorImport =====")

    if info.objids == nil or #info.objids == 0 then
        printf("FLOOR_IMPORT:: ERROR: No objids")
        return
    end

    if game.currentMap == nil then
        printf("FLOOR_IMPORT:: ERROR: No current map")
        return
    end

    local mapId = game.currentMap.id
    local floorW = math.ceil(info.width)
    local floorH = math.ceil(info.height)
    offsetX = offsetX or game.currentMap.dimensions.x1
    offsetY = offsetY or game.currentMap.dimensions.y1

    printf("FLOOR_IMPORT:: mapId=%s floorW=%d floorH=%d offsetX=%d offsetY=%d", mapId, floorW, floorH, offsetX, offsetY)

    -- Compute the object center position.
    local objCenterX = offsetX + floorW / 2
    local objCenterY = offsetY + floorH / 2
    printf("FLOOR_IMPORT:: Object center: (%.1f, %.1f)", objCenterX, objCenterY)

    -- Collect existing floor IDs before creating anything.
    local existingFloorIds = {}
    for _, floor in ipairs(game.currentMap.floors) do
        existingFloorIds[floor.floorid] = true
    end
    printf("FLOOR_IMPORT:: Existing floor count: %d", #game.currentMap.floors)

    -- Create the primary floor. Don't do any other map mutations before this --
    -- Upload() and CreateFloor() both patch the manifest and can conflict.
    game.currentMap:CreateFloor()
    printf("FLOOR_IMPORT:: Called CreateFloor(), starting coroutine to wait for sync...")

    dmhub.Coroutine(function()
        -- Helper to get the fresh map reference.
        local function getMap()
            return game.GetMap(mapId)
        end

        -- Wait for a new primary floor to appear (one not in our snapshot).
        local primaryFloor = nil
        for attempt = 1, 200 do
            local map = getMap()
            if map ~= nil then
                for _, floor in ipairs(map.floors) do
                    if not existingFloorIds[floor.floorid] and floor.isPrimaryLayerOnFloor then
                        primaryFloor = floor
                        break
                    end
                end
            end
            if primaryFloor ~= nil then break end
            coroutine.yield(0.05)
        end

        if primaryFloor == nil then
            printf("FLOOR_IMPORT:: ERROR: Timed out waiting for primary floor")
            return
        end

        printf("FLOOR_IMPORT:: Found primary floor: id=%s desc='%s'", primaryFloor.floorid, primaryFloor.description)

        -- Brief sync pause.
        for i = 1, 10 do coroutine.yield(0.01) end

        -- Step 2: Create a map layer on this primary floor.
        local existingFloorIds2 = {}
        local map = getMap()
        for _, floor in ipairs(map.floors) do
            existingFloorIds2[floor.floorid] = true
        end

        printf("FLOOR_IMPORT:: Creating map layer with parentFloor=%s", primaryFloor.floorid)
        map:CreateFloor{parentFloor = primaryFloor.floorid}

        -- Wait for the layer to appear.
        local mapLayer = nil
        for attempt = 1, 200 do
            map = getMap()
            if map ~= nil then
                for _, floor in ipairs(map.floors) do
                    if not existingFloorIds2[floor.floorid] then
                        mapLayer = floor
                        break
                    end
                end
            end
            if mapLayer ~= nil then break end
            coroutine.yield(0.05)
        end

        if mapLayer == nil then
            printf("FLOOR_IMPORT:: ERROR: Timed out waiting for map layer")
            return
        end

        printf("FLOOR_IMPORT:: Found map layer: id=%s parentFloor=%s", mapLayer.floorid, json(mapLayer.parentFloor))

        -- Label the layer.
        mapLayer.layerDescription = "Map Layer"

        -- Step 3: Expand map dimensions to encompass the new floor.
        -- Done here (after floor creation) to avoid conflicting manifest patches.
        map = getMap()
        if map ~= nil then
            local dim = map.dimensions
            local newX2 = offsetX + floorW
            local newY2 = offsetY + floorH
            local needsExpand = (offsetX < dim.x1 or offsetY < dim.y1 or newX2 > dim.x2 or newY2 > dim.y2)
            if needsExpand then
                map.dimensions = {
                    x1 = math.min(dim.x1, offsetX),
                    y1 = math.min(dim.y1, offsetY),
                    x2 = math.max(dim.x2, newX2),
                    y2 = math.max(dim.y2, newY2),
                }
                map:Upload("Expand map for new floor")
                printf("FLOOR_IMPORT:: Expanded map dimensions")
            end
        end

        -- Brief sync pause before spawning.
        for i = 1, 30 do coroutine.yield(0.01) end

        -- Step 4: Spawn the imported map image onto the layer.
        for _, objid in ipairs(info.objids) do
            printf("FLOOR_IMPORT:: Spawning objid=%s onto layer=%s at (%.1f, %.1f)", objid, mapLayer.floorid, objCenterX, objCenterY)
            local obj = mapLayer:SpawnObjectLocal(objid)
            if obj ~= nil then
                obj.x = objCenterX
                obj.y = objCenterY
                obj:Upload()
                printf("FLOOR_IMPORT:: Spawned OK. obj.x=%.1f obj.y=%.1f floorIndex=%s", obj.x, obj.y, json(obj.floorIndex))
            else
                printf("FLOOR_IMPORT:: ERROR: SpawnObjectLocal returned nil for %s", objid)
            end
        end

        -- Final state log.
        printf("FLOOR_IMPORT:: --- Final floor state ---")
        map = getMap()
        if map ~= nil then
            for i, floor in ipairs(map.floors) do
                local objCount = 0
                for _ in pairs(floor.objects) do objCount = objCount + 1 end
                printf("FLOOR_IMPORT::   [%d] id=%s desc='%s' parentFloor=%s objects=%d", i, floor.floorid, floor.description or "", json(floor.parentFloor), objCount)
            end
        end

        printf("FLOOR_IMPORT:: ===== END FinishFloorImport =====")
    end)
end