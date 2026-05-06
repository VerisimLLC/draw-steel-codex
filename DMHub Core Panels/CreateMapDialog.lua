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
		classes = {"framedPanel"},
		width = 1400,
		height = 940,
		styles = ThemeEngine.GetStyles(),

        gui.Panel{
            width = "100%-24",
            height = "100%-48",
            halign = "center",
            valign = "center",

            flow = "vertical",

            gui.Label{
                classes = {"modalTitle"},
                text = "Create Map",
            },

            gui.Panel{
                flow = "horizontal",
                halign = "center",
                valign = "top",
                width = "auto",
                height = "auto",
                vmargin = 16,

                styles = ThemeEngine.MergeTokens({
                    {
                        selectors = {"mapItem"},
                        bgimage = true,
                        bgcolor = "@bg",
                        cornerRadius = 12,
                        width = 1920*0.1,
                        height = 1080*0.1,
                        halign = "center",
                        hmargin = 8,
                    },
                    {
                        selectors = {"mapItem", "hover"},
                        borderWidth = 2,
                        borderColor = "@accent",
                    },
                    {
                        selectors = {"mapItem", "selected"},
                        borderWidth = 2,
                        borderColor = "@fg",
                    },
                    {
                        selectors = {"mapText"},
                        fontSize = 14,
                        width = "auto",
                        height = "auto",
                        textAlignment = "center",
                    },
                }),

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

                gui.Panel{
                    classes = {"formRow"},
                    gui.Label{
                        classes = {"form"},
                        text = "Map Name:",
                    },
                    gui.Input{
                        classes = {"form"},
                        text = m_mapName,
                        change = function(element)
                            m_mapName = element.text
                        end,
                    },
                },


                gui.Panel{
                    classes = {"formRow"},
                    gui.Label{
                        classes = {"form"},
                        text = "Tile Type:",
                    },

                    gui.Panel{
                        classes = {"form"},
                        width = "auto",
                        height = "auto",
                        flow = "horizontal",
                        halign = "left",

                        styles = ThemeEngine.MergeTokens({
                            {
                                selectors = {"tileButton"},
                                brightness = 0.5,
                                bgcolor = "@bgInverse",
                            },
                            {
                                selectors = {"tileButton", "selected"},
                                brightness = 1.8,
                                bgcolor = "@fgStrong",
                            },
                        }),

                        select = function(element, target)
                            tileType = target.data.id
                            for _,child in ipairs(element.children) do
                                child:SetClass("selected", target == child)
                            end
                        end,

                        gui.Button{
                            classes = {"sizeL", "tileButton", "selected"},
                            data = {id = "squares"},
                            hmargin = 8,
                            icon = "ui-icons/tile-square.png",
                            click = function(element) element.parent:FireEvent("select", element) end,
                        },
                        gui.Button{
                            classes = {"sizeL", "tileButton"},
                            data = {id = "flattop"},
                            hmargin = 8,
                            icon = "ui-icons/tile-flathex.png",
                            click = function(element) element.parent:FireEvent("select", element) end,
                        },
                        gui.Button{
                            classes = {"sizeL", "tileButton"},
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

                gui.Button{
                    classes = {"sizeL"},
                    halign = "left",
                    text = "Create Map",
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

                gui.Button{
                    classes = {"sizeL"},
                    halign = "right",
                    text = "Cancel",
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

        -- Final safety net: the import dialog clamps user input, but if any
        -- code path slips a huge value through, refuse to write it. See
        -- MAX_MAP_TILES_PER_AXIS in MapImport.lua for the full rationale.
        local MAX_DIM = 2000
        if w > MAX_DIM or h > MAX_DIM then
            dmhub.Debug(string.format("CreateMap: clamping dimensions %dx%d -> %dx%d (import-path safety net)",
                w, h, math.min(w, MAX_DIM), math.min(h, MAX_DIM)))
            w = math.min(w, MAX_DIM)
            h = math.min(h, MAX_DIM)
        end

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

-- Open the alignment dialog in "realign" mode for an already-imported floor.
-- The dialog reuses the same drag/zoom/pan UI as the new-floor flow but, instead
-- of creating a new floor on confirm, it just updates the existing object's
-- (x, y) position so the user can re-align it against the other map images.
mod.shared.ShowFloorRealignDialog = function(mapLayer, mapObj)
    if mapObj == nil then
        return
    end
    mod.shared.ShowFloorAlignmentDialog{
        realignTarget = mapObj,
    }
end

-- Show a dialog to let the user align a new floor image to the existing map.
-- info: the import result with objids, width, height, paths, imageWidth, imageHeight.
-- For realign mode, info.realignTarget is a LuaObjectInstance (with a Map component)
-- and the rest of info may be empty.
mod.shared.ShowFloorAlignmentDialog = function(info)
    -- Mode A (default): aligning a freshly-imported new floor. info has objids/width/height.
    -- Mode B (realign): info.realignTarget is the existing LuaObjectInstance to reposition.
    --   In this mode info.objids may be empty; we reuse the same UI to drag the existing
    --   floor's image around and on confirm we set obj.x/obj.y instead of creating a new floor.
    local realignTarget = info.realignTarget

    if realignTarget == nil and (info.objids == nil or #info.objids == 0) then
        return
    end

    local currentMap = game.currentMap
    if currentMap == nil then
        return
    end

    local dim = currentMap.dimensions
    local mapW = dim.x2 - dim.x1
    local mapH = dim.y2 - dim.y1

    -- floorW, floorH are the moving image's tile span. In realign mode, derive from
    -- the existing object's actual rendered span (fractional). In normal mode, use the
    -- import's reported tile count, ceil'd.
    local floorW
    local floorH
    -- references[]: list of {imageid, x1, y1, x2, y2} drawn as static backdrop in the
    -- preview panel. Normal mode renders the canvas image at canvas bounds (legacy
    -- behaviour, exactly one entry). Realign mode renders every OTHER Map object at
    -- its actual world bounds.
    local references = {}

    -- Default offset: the moving floor's top-left in world tile coords.
    local offsetX
    local offsetY

    -- Captured at setup time and used by the Confirm handler to convert offset
    -- (top-left of rendered image) back to obj.x/obj.y. The renderer's _mapPivot
    -- is rarely exactly (0.5, 0.5) -- it's wrapped to near-center but can be
    -- offset by up to one tile, so we must respect it instead of assuming centered.
    local realignPivotX = 0.5
    local realignPivotY = 0.5

    if realignTarget ~= nil then
        local d = realignTarget.mapAlignmentDiagnostic
        if d == nil then
            gui.ModalMessage{title = "Error", message = "Could not read this floor's calibration."}
            return
        end
        floorW = d.imageWorldWidth
        floorH = d.imageWorldHeight
        if (floorW or 0) <= 0 or (floorH or 0) <= 0 then
            -- Fallback to the area-derived span if the renderer hasn't computed _tileDim yet.
            floorW = (d.areaX2 or 0) - (d.areaX1 or 0)
            floorH = (d.areaY2 or 0) - (d.areaY1 or 0)
        end
        if (floorW or 0) <= 0 or (floorH or 0) <= 0 then
            gui.ModalMessage{title = "Error", message = "Could not determine this floor's size."}
            return
        end

        realignPivotX = d.mapPivotX or 0.5
        realignPivotY = d.mapPivotY or 0.5

        -- Use the actual rendered top-left (areaX1/areaY1). Falling back to
        -- pos - imageWorldDim * mapPivot if for some reason the area fields are
        -- missing -- this is the same formula the renderer uses internally.
        if d.areaX1 ~= nil and d.areaY1 ~= nil then
            offsetX = d.areaX1
            offsetY = d.areaY1
        else
            offsetX = (realignTarget.x or 0) - floorW * realignPivotX
            offsetY = (realignTarget.y or 0) - floorH * realignPivotY
        end

        -- Collect every OTHER Map object as a reference backdrop.
        for _, floor in ipairs(currentMap.floors) do
            for _, obj in pairs(floor.objects) do
                if obj:GetComponent("Map") ~= nil and obj.id ~= realignTarget.id then
                    local od = obj.mapAlignmentDiagnostic
                    if od ~= nil and od.areaX1 ~= nil then
                        references[#references+1] = {
                            imageid = obj.imageid,
                            x1 = od.areaX1, y1 = od.areaY1,
                            x2 = od.areaX2, y2 = od.areaY2,
                        }
                    end
                end
            end
        end

        printf("FLOOR_REALIGN:: target=%s/%s floorW=%.4f floorH=%.4f initialOffset=(%.4f,%.4f) refs=%d",
            d.floorid, d.objid, floorW, floorH, offsetX, offsetY, #references)
    else
        floorW = math.ceil(info.width)
        floorH = math.ceil(info.height)
        offsetX = dim.x1
        offsetY = dim.y1
    end

    -- Check if the new floor is the same size as the existing map.
    printf("FLOOR_ALIGN:: ShowFloorAlignmentDialog called: mapW=%s mapH=%s floorW=%s floorH=%s",
        tostring(mapW), tostring(mapH), tostring(floorW), tostring(floorH))
    printf("FLOOR_ALIGN:: Existing map dims: x1=%s y1=%s x2=%s y2=%s", json(dim.x1), json(dim.y1), json(dim.x2), json(dim.y2))
    printf("FLOOR_ALIGN:: Default offset: (%s, %s)", tostring(offsetX), tostring(offsetY))
    printf("FLOOR_ALIGN:: Incoming info: width=%s height=%s objids=%s imageWidth=%s imageHeight=%s",
        tostring(info.width), tostring(info.height), json(info.objids or {}), tostring(info.imageWidth), tostring(info.imageHeight))

    -- Snapshot every existing Map LevelObject's calibration so we can compare against the new one.
    do
        local count = 0
        for _, floor in ipairs(currentMap.floors) do
            for _, obj in pairs(floor.objects) do
                if obj:GetComponent("Map") ~= nil then
                    count = count + 1
                    local d = obj.mapAlignmentDiagnostic
                    if d ~= nil then
                        printf("FLOOR_ALIGN_DIAG:: Existing Map object [%d] floorid=%s objid=%s calibration=%s",
                            count, floor.floorid, obj.id, json(d))
                    else
                        printf("FLOOR_ALIGN_DIAG:: Existing Map object [%d] floorid=%s objid=%s had nil mapAlignmentDiagnostic",
                            count, floor.floorid, obj.id)
                    end
                end
            end
        end
        if count == 0 then
            printf("FLOOR_ALIGN_DIAG:: ShowFloorAlignmentDialog: no existing Map LevelObjects found.")
        end
    end

    if realignTarget == nil then
        -- If the user picked "Match Existing Map", we have a calibration captured
        -- from the existing Map LevelObject. Bypass the alignment dialog and place
        -- the new floor at the same world position as the existing one. Once
        -- FinishFloorImport applies the calibration, the new image will render
        -- with the same _tileDim/_mapPivot, so its world bounds match exactly.
        if info.matchCalibration ~= nil then
            printf("FLOOR_ALIGN:: matchCalibration present -- skipping alignment dialog and aligning to existing.")
            mod.shared.FinishFloorImport(info, offsetX, offsetY)
            return
        end

        local sameSize = (floorW == mapW and floorH == mapH)

        if sameSize then
            printf("FLOOR_ALIGN:: Same size detected, skipping alignment dialog")
            mod.shared.FinishFloorImport(info, offsetX, offsetY)
            return
        end
    end

    -- Find the existing map's floor image for display (legacy single-image backdrop in
    -- normal mode). In realign mode the references[] list above is what we render.
    local existingImageId = nil
    if realignTarget == nil then
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
    end

    -- The moving image. Normal mode: the first imported asset. Realign mode: the
    -- existing object's image.
    local newImageId
    if realignTarget ~= nil then
        newImageId = realignTarget.imageid
    else
        newImageId = info.objids[1]
    end

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

    -- Format an offset for display: integer if whole, two decimals otherwise.
    local function fmtOffset(v)
        if v == math.floor(v) then
            return tostring(math.floor(v))
        end
        return string.format("%.2f", v)
    end

    -- Realign mode allows fractional offsets (the existing object may be at a
    -- fractional world position because its image span isn't an integer number
    -- of tiles). Normal mode keeps the legacy integer-only behaviour.
    local allowFractional = realignTarget ~= nil

    local offsetXInput = gui.Input{
        fontSize = 18,
        width = 80,
        height = 24,
        text = fmtOffset(offsetX),
        edit = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetX = val
                fireUpdatePreview()
            end
        end,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetX = val
            else
                element.text = fmtOffset(offsetX)
            end
            fireUpdatePreview()
        end,
    }

    local offsetYInput = gui.Input{
        fontSize = 18,
        width = 80,
        height = 24,
        text = fmtOffset(offsetY),
        edit = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetY = val
                fireUpdatePreview()
            end
        end,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and (allowFractional or val == math.floor(val)) then
                offsetY = val
            else
                element.text = fmtOffset(offsetY)
            end
            fireUpdatePreview()
        end,
    }

    previewLabel = gui.Label{
        classes = {"form"},
        width = "100%",
        height = "auto",
        color = "#cccccc",
        wrap = true,
        halign = "left",
        text = "",

        updatePreview = function(element)
            local newX2 = offsetX + floorW
            local newY2 = offsetY + floorH

            local lines = {}
            if realignTarget ~= nil then
                local centerX = offsetX + floorW / 2
                local centerY = offsetY + floorH / 2
                lines[#lines+1] = string.format(
                    "This floor: (%s, %s) to (%s, %s); center (%s, %s).",
                    fmtOffset(offsetX), fmtOffset(offsetY),
                    fmtOffset(newX2), fmtOffset(newY2),
                    fmtOffset(centerX), fmtOffset(centerY))
                for i, ref in ipairs(references) do
                    local cx = (ref.x1 + ref.x2) / 2
                    local cy = (ref.y1 + ref.y2) / 2
                    lines[#lines+1] = string.format(
                        "Other [%d]: (%s, %s) to (%s, %s); center (%s, %s).",
                        i,
                        fmtOffset(ref.x1), fmtOffset(ref.y1),
                        fmtOffset(ref.x2), fmtOffset(ref.y2),
                        fmtOffset(cx), fmtOffset(cy))
                end
            else
                local canvasX1 = math.min(dim.x1, offsetX)
                local canvasY1 = math.min(dim.y1, offsetY)
                local canvasX2 = math.max(dim.x2, newX2)
                local canvasY2 = math.max(dim.y2, newY2)
                local canvasW = canvasX2 - canvasX1
                local canvasH = canvasY2 - canvasY1
                local needsExpand = (canvasX1 < dim.x1 or canvasY1 < dim.y1 or canvasX2 > dim.x2 or canvasY2 > dim.y2)

                lines[#lines+1] = string.format("New floor at (%d, %d) to (%d, %d).", offsetX, offsetY, newX2, newY2)
                if needsExpand then
                    lines[#lines+1] = string.format("Map canvas will expand to %dx%d tiles.", canvasW, canvasH)
                else
                    lines[#lines+1] = "New floor fits within the existing canvas."
                end
            end

            element.text = table.concat(lines, realignTarget ~= nil and "\n" or " ")
        end,
    }

    -- The preview area: shows actual images of both floors with grid overlay.
    -- Supports mouse wheel zoom, right-drag to pan, left-drag to move new floor.
    local previewSize = 620

    -- View state: zoom level and center position in tile coordinates.
    -- Start zoomed out to fit everything.
    local canvasX1Init, canvasY1Init, canvasX2Init, canvasY2Init
    if realignTarget ~= nil then
        canvasX1Init = offsetX
        canvasY1Init = offsetY
        canvasX2Init = offsetX + floorW
        canvasY2Init = offsetY + floorH
        for _, ref in ipairs(references) do
            canvasX1Init = math.min(canvasX1Init, ref.x1)
            canvasY1Init = math.min(canvasY1Init, ref.y1)
            canvasX2Init = math.max(canvasX2Init, ref.x2)
            canvasY2Init = math.max(canvasY2Init, ref.y2)
        end
    else
        canvasX1Init = math.min(dim.x1, offsetX)
        canvasY1Init = math.min(dim.y1, offsetY)
        canvasX2Init = math.max(dim.x2, offsetX + floorW)
        canvasY2Init = math.max(dim.y2, offsetY + floorH)
    end
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
        offsetXInput.textNoNotify = fmtOffset(offsetX)
        offsetYInput.textNoNotify = fmtOffset(offsetY)
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

    -- Persistent image panels: created once and re-positioned in updatePreview
    -- to avoid the white-flash that occurred when bgimage panels were rebuilt
    -- every frame during drag. A panel listed in element.children is preserved
    -- across the assignment, so we always include these in the rebuilt list.
    -- Reference panels (one per ref). Each is the static backdrop image of an
    -- already-placed Map object (realign mode), or the canvas-sized existing
    -- image (normal mode).
    local refImagePanels = {}
    local refBorderPanels = {}
    if realignTarget ~= nil then
        for i, ref in ipairs(references) do
            if ref.imageid ~= nil then
                refImagePanels[i] = gui.Panel{
                    bgimage = ref.imageid,
                    bgimageStreamed = ref.imageid,
                    bgcolor = "white",
                    halign = "left", valign = "top",
                    x = 0, y = 0,
                    width = 0, height = 0,
                }
            end
            refBorderPanels[i] = gui.Panel{
                halign = "left", valign = "top",
                x = 0, y = 0,
                width = 0, height = 0,
                borderColor = "#6699cc",
                borderWidth = 2,
            }
        end
    elseif existingImageId ~= nil then
        refImagePanels[1] = gui.Panel{
            bgimage = existingImageId,
            bgimageStreamed = existingImageId,
            bgcolor = "white",
            halign = "left", valign = "top",
            x = 0, y = 0,
            width = 0, height = 0,
        }
    end

    -- Moving floor image panel: persistent so dragging doesn't recreate it.
    local movingImagePanel = nil
    if newImageId ~= nil then
        movingImagePanel = gui.Panel{
            bgimage = newImageId,
            bgimageStreamed = newImageId,
            bgcolor = "white",
            opacity = newFloorOpacity,
            halign = "left", valign = "top",
            x = 0, y = 0,
            width = 0, height = 0,
        }
    end

    -- Moving floor border (always present, drawn on top of grid lines).
    local movingBorderPanel = gui.Panel{
        halign = "left", valign = "top",
        x = 0, y = 0,
        width = 0, height = 0,
        borderColor = "#cc9966",
        borderWidth = 2,
    }

    -- Canvas border for normal mode.
    local canvasBorderPanel = nil
    if realignTarget == nil then
        canvasBorderPanel = gui.Panel{
            halign = "left", valign = "top",
            x = 0, y = 0,
            width = 0, height = 0,
            borderColor = "#6699cc",
            borderWidth = 2,
        }
    end

    -- Right/middle-click pan state. Tracks previous mouse position while either
    -- button is held and applies a delta-pan in the think callback.
    local panPrevX = nil
    local panPrevY = nil

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
        data = {},

        -- Dragging: right-drag to pan, left-drag to move new floor.
        -- Middle-click pan is handled separately in the think callback.
        draggable = true,
        dragMove = false,
        dragThreshold = 2,

        events = {
            press = function(element)
                -- Right/middle button drags are handled in `think` (the engine's drag
                -- system only triggers `dragging` for left-click). Skip them here.
                if element:GetMouseButton(1) or element:GetMouseButton(2) then
                    isDraggingFloor = false
                    return
                end

                local mp = element.mousePoint
                if mp == nil then return end
                -- mousePoint is in normalized [0,1] panel-local coords. Convert to
                -- panel-local pixel coords (top-left = 0,0; +y down).
                local mx = mp.x * previewSize
                local my = (1 - mp.y) * previewSize

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

        -- Mouse wheel zoom + middle-click pan. Middle-click is handled here
        -- because the engine's drag system only triggers `dragging` callbacks
        -- on left/right click, not middle.
        thinkTime = 0.02,
        think = function(element)
            -- mousePoint is nil when the mouse isn't over the panel. When present,
            -- it is in normalized [0,1] panel-local coords -- multiply by previewSize
            -- to get panel-local pixels (top-left = 0,0; +y down).
            local mp = element.mousePoint
            local mouseInside = mp ~= nil
            local mx, my = 0, 0
            if mouseInside then
                mx = mp.x * previewSize
                my = (1 - mp.y) * previewSize
            end

            -- Mouse wheel zoom (only when mouse is over the panel).
            local wheel = dmhub.mouseWheel
            if mouseInside and wheel ~= 0 then
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

            -- Right-click or middle-click drag pans. The engine's drag system only
            -- fires `dragging` callbacks for left-click, so we poll GetMouseButton.
            local panning = element:GetMouseButton(1) or element:GetMouseButton(2)
            if panning and mouseInside then
                if panPrevX ~= nil then
                    local dx = mx - panPrevX
                    local dy = my - panPrevY
                    if dx ~= 0 or dy ~= 0 then
                        local ppt = getPixelsPerTile()
                        viewCenterX = viewCenterX - dx / ppt
                        viewCenterY = viewCenterY + dy / ppt
                        element:FireEvent("updatePreview")
                    end
                end
                panPrevX = mx
                panPrevY = my
            else
                panPrevX = nil
                panPrevY = nil
            end

            -- Arrow-key nudge (1 tile per press, with edge-detection so a held key
            -- moves once per think tick).
            local function arrowEdge(key, prevField)
                local down = dmhub.KeyPressed(key)
                local prev = element.data[prevField]
                element.data[prevField] = down
                return down and not prev
            end
            local nudgedX = 0
            local nudgedY = 0
            if arrowEdge("LeftArrow",  "ke_left")  then nudgedX = nudgedX - 1 end
            if arrowEdge("RightArrow", "ke_right") then nudgedX = nudgedX + 1 end
            if arrowEdge("UpArrow",    "ke_up")    then nudgedY = nudgedY + 1 end
            if arrowEdge("DownArrow",  "ke_down")  then nudgedY = nudgedY - 1 end
            if nudgedX ~= 0 or nudgedY ~= 0 then
                offsetX = offsetX + nudgedX
                offsetY = offsetY + nudgedY
                updateInputsFromOffset()
                fireUpdatePreview()
            end
        end,

        updatePreview = function(element)
            local ppt = getPixelsPerTile()

            local children = {}

            -- Update persistent backdrop panels with current positions.
            if realignTarget ~= nil then
                for i, ref in ipairs(references) do
                    local ex, ey, ew, eh = rectToPanel(ref.x1, ref.y1, ref.x2 - ref.x1, ref.y2 - ref.y1)
                    if refImagePanels[i] ~= nil then
                        refImagePanels[i].x = ex
                        refImagePanels[i].y = ey
                        refImagePanels[i].selfStyle.width = ew
                        refImagePanels[i].selfStyle.height = eh
                        children[#children+1] = refImagePanels[i]
                    end
                end
            elseif refImagePanels[1] ~= nil then
                local ex, ey, ew, eh = rectToPanel(dim.x1, dim.y1, mapW, mapH)
                refImagePanels[1].x = ex
                refImagePanels[1].y = ey
                refImagePanels[1].selfStyle.width = ew
                refImagePanels[1].selfStyle.height = eh
                children[#children+1] = refImagePanels[1]
            end

            -- Update persistent moving-floor panel.
            if movingImagePanel ~= nil then
                local nx, ny, nw, nh = rectToPanel(offsetX, offsetY, floorW, floorH)
                movingImagePanel.x = nx
                movingImagePanel.y = ny
                movingImagePanel.selfStyle.width = nw
                movingImagePanel.selfStyle.height = nh
                movingImagePanel.opacity = newFloorOpacity
                children[#children+1] = movingImagePanel
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

            -- Reference borders (persistent).
            if realignTarget ~= nil then
                for i, ref in ipairs(references) do
                    if refBorderPanels[i] ~= nil then
                        local bx, by, bw, bh = rectToPanel(ref.x1, ref.y1, ref.x2 - ref.x1, ref.y2 - ref.y1)
                        refBorderPanels[i].x = bx
                        refBorderPanels[i].y = by
                        refBorderPanels[i].selfStyle.width = bw
                        refBorderPanels[i].selfStyle.height = bh
                        children[#children+1] = refBorderPanels[i]
                    end
                end
            elseif canvasBorderPanel ~= nil then
                local bx, by, bw, bh = rectToPanel(dim.x1, dim.y1, mapW, mapH)
                canvasBorderPanel.x = bx
                canvasBorderPanel.y = by
                canvasBorderPanel.selfStyle.width = bw
                canvasBorderPanel.selfStyle.height = bh
                children[#children+1] = canvasBorderPanel
            end

            -- Moving floor border (persistent).
            do
                local bx, by, bw, bh = rectToPanel(offsetX, offsetY, floorW, floorH)
                movingBorderPanel.x = bx
                movingBorderPanel.y = by
                movingBorderPanel.selfStyle.width = bw
                movingBorderPanel.selfStyle.height = bh
                children[#children+1] = movingBorderPanel
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
        local cx1, cy1, cx2, cy2
        if realignTarget ~= nil then
            cx1 = offsetX
            cy1 = offsetY
            cx2 = offsetX + floorW
            cy2 = offsetY + floorH
            for _, ref in ipairs(references) do
                cx1 = math.min(cx1, ref.x1)
                cy1 = math.min(cy1, ref.y1)
                cx2 = math.max(cx2, ref.x2)
                cy2 = math.max(cy2, ref.y2)
            end
        else
            cx1 = math.min(dim.x1, offsetX)
            cy1 = math.min(dim.y1, offsetY)
            cx2 = math.max(dim.x2, offsetX + floorW)
            cy2 = math.max(dim.y2, offsetY + floorH)
        end
        viewCenterX = (cx1 + cx2) / 2
        viewCenterY = (cy1 + cy2) / 2
        local cw = cx2 - cx1
        local ch = cy2 - cy1
        basePixelsPerTile = (previewSize - 20) / (math.max(cw, ch) * 1.1)
        viewZoom = 1.0
        fireUpdatePreview()
    end

    -- Zoom slider, log-scaled so the user can sweep across the [minZoom, maxZoom]
    -- range smoothly. Slider value 0..100 maps to log(minZoom)..log(maxZoom).
    local logMin = math.log(minZoom)
    local logMax = math.log(maxZoom)
    local function zoomToSlider(z)
        return (math.log(z) - logMin) / (logMax - logMin) * 100
    end
    local function sliderToZoom(s)
        return math.exp(s / 100 * (logMax - logMin) + logMin)
    end

    local zoomSlider = gui.Slider{
        style = { height = 20, width = 200, fontSize = 14 },
        sliderWidth = 140,
        labelWidth = 60,
        minValue = 0,
        maxValue = 100,
        value = zoomToSlider(viewZoom),
        change = function(element)
            viewZoom = sliderToZoom(element.value)
            fireUpdatePreview()
        end,
        thinkTime = 0.1,
        think = function(element)
            if not element.dragging then
                element.data.setValueNoEvent(zoomToSlider(viewZoom))
            end
        end,
    }

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
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "Top-left at tile: ",
                },
                offsetXInput,
                gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
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
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "Opacity: ",
                },
                opacitySlider,
            },

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                hmargin = 16,

                gui.Label{
                    classes = {"sizeS"},
                    width = "auto",
                    height = "auto",
                    text = "Zoom: ",
                },
                zoomSlider,
            },

            gui.Button{
                classes = {"sizeM"},
                text = "Reset View",
                halign = "right",
                click = function()
                    resetView()
                end,
            },
        },

        gui.Label{
            classes = {"form", "sizeS"},
            width = "auto",
            height = "auto",
            text = realignTarget ~= nil
                and "Drag this floor to reposition it. Scroll or use the zoom slider. Middle-click drag or drag background to pan."
                or "Drag the new floor to position it. Scroll or use the zoom slider. Middle-click drag or drag background to pan.",
        },
    }

    local dialogPanel = gui.Panel{
        id = "alignDialog",
        classes = {"framedPanel"},
        width = 1000,
        height = 940,
        pad = 16,
        flow = "vertical",
        styles = ThemeEngine.GetStyles(),

        gui.Label{
            classes = {"modalTitle"},
            text = "Align New Floor",
        },

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            vmargin = 4,

            gui.Label{
                classes = {"sizeS"},
                width = "auto",
                height = "auto",
                text = realignTarget ~= nil
                    and string.format("Floor: %.2f x %.2f tiles  |  %d other map object(s) shown.", floorW, floorH, #references)
                    or string.format("Existing map: %dx%d tiles  |  New floor: %dx%d tiles", mapW, mapH, floorW, floorH),
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

            gui.Button{
                classes = {"sizeL"},
                text = "Confirm",
                click = function()
                    if realignTarget ~= nil then
                        -- Convert offset (top-left of rendered image, == areaX1/Y1)
                        -- back to obj.x/obj.y using the renderer's pivot. This is
                        -- the inverse of `areaX1 = pos.x - imageWorldWidth * mapPivot.x`.
                        local newPosX = offsetX + floorW * realignPivotX
                        local newPosY = offsetY + floorH * realignPivotY
                        printf("FLOOR_REALIGN:: Confirm clicked: offset=(%.4f, %.4f) pivot=(%.6f, %.6f) -> obj.x=%.4f obj.y=%.4f",
                            offsetX, offsetY, realignPivotX, realignPivotY, newPosX, newPosY)
                        gui.CloseModal()
                        realignTarget:MarkUndo()
                        realignTarget.x = newPosX
                        realignTarget.y = newPosY
                        realignTarget:Upload()
                    else
                        printf("FLOOR_ALIGN:: Confirm clicked: offsetX=%d offsetY=%d", offsetX, offsetY)
                        gui.CloseModal()
                        mod.shared.FinishFloorImport(info, offsetX, offsetY)
                    end
                end,
            },

            gui.Button{
                classes = {"sizeL"},
                text = "Cancel",
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                end,
            },
        },

        gui.Button{
            classes = {"closeButton"},
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

    local confirmButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Apply",
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

    local continueButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Continue>>",
        valign = "center",
        halign = "center",
        click = function()
            importPanel:Next()
        end,
    }

    local previousButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Back",
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
            gui.Label{ classes = {"sizeL"}, width = 90, height = "auto", text = "Width:"},
            statusWidth,
            gui.Label{ classes = {"sizeL"}, lmargin = 4, width = "auto", height = "auto", text = "px"},
        },

        gui.Panel{
            flow = "horizontal", width = "auto", height = "auto",
            gui.Label{ classes = {"sizeL"}, width = 90, height = "auto", text = "Height:"},
            statusHeight,
            gui.Label{ classes = {"sizeL"}, lmargin = 4, width = "auto", height = "auto", text = "px"},
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
                        fontSize = 18,
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
        styles = ThemeEngine.GetStyles(),

        gui.Label{
            classes = {"modalTitle"},
            text = "Reimport Map Sizing",
        },

        resultPanel,

        gui.Button{
            classes = {"closeButton"},
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
        -- Skip in match mode: the new floor occupies the same world bounds as the
        -- existing floor it's matching, which is already inside the canvas.
        if info.matchCalibration ~= nil then
            printf("FLOOR_IMPORT:: matchCalibration in effect; skipping canvas expansion.")
        else
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
        end

        -- Brief sync pause before spawning.
        for i = 1, 30 do coroutine.yield(0.01) end

        -- Step 4: Spawn the imported map image onto the layer.
        -- If matchCalibration is present, we override the new object's controlPoints/scaling/mapType
        -- with the existing map's, and place it at the existing's (x, y) so the world bounds match.
        local applyMatch = info.matchCalibration ~= nil
        if applyMatch then
            printf("FLOOR_IMPORT:: matchCalibration in effect; will override new object calibration to match existing.")
        end
        local newlySpawnedObjs = {}
        for _, objid in ipairs(info.objids) do
            local placeX = applyMatch and info.matchCalibration.x or objCenterX
            local placeY = applyMatch and info.matchCalibration.y or objCenterY
            printf("FLOOR_IMPORT:: Spawning objid=%s onto layer=%s at (%.4f, %.4f)%s",
                objid, mapLayer.floorid, placeX, placeY, applyMatch and " [match mode]" or "")
            local obj = mapLayer:SpawnObjectLocal(objid)
            if obj ~= nil then
                if applyMatch then
                    obj:ApplyMapCalibration(info.matchCalibration)
                end
                obj.x = placeX
                obj.y = placeY
                obj:Upload()
                printf("FLOOR_IMPORT:: Spawned OK. obj.x=%.4f obj.y=%.4f floorIndex=%s", obj.x, obj.y, json(obj.floorIndex))
                newlySpawnedObjs[#newlySpawnedObjs+1] = obj
            else
                printf("FLOOR_IMPORT:: ERROR: SpawnObjectLocal returned nil for %s", objid)
            end
        end

        -- Wait a few frames so the spawned objects render and ObjectComponentMap.Calculate() runs.
        for i = 1, 60 do coroutine.yield(0.01) end

        -- Diagnostic: dump calibration for every Map LevelObject on the map (existing + new).
        printf("FLOOR_ALIGN_DIAG:: ===== Post-spawn calibration dump =====")
        map = getMap()
        if map ~= nil then
            local mapCount = 0
            for _, floor in ipairs(map.floors) do
                for _, obj in pairs(floor.objects) do
                    if obj:GetComponent("Map") ~= nil then
                        mapCount = mapCount + 1
                        local d = obj.mapAlignmentDiagnostic
                        printf("FLOOR_ALIGN_DIAG:: Post-spawn Map object [%d] floorid=%s objid=%s calibration=%s",
                            mapCount, floor.floorid, obj.id, json(d))
                    end
                end
            end
            printf("FLOOR_ALIGN_DIAG:: Total Map objects on map after spawn: %d", mapCount)
        end

        -- Pairwise alignment delta check: compare the first 'existing' Map object
        -- to each newly-spawned one in tile-space and pixel-space.
        if #newlySpawnedObjs > 0 then
            map = getMap()
            local existingDiag = nil
            local existingFloorId = nil
            local existingObjId = nil
            for _, floor in ipairs(map.floors) do
                for _, obj in pairs(floor.objects) do
                    if obj:GetComponent("Map") ~= nil then
                        local isNew = false
                        for _, n in ipairs(newlySpawnedObjs) do
                            if n.id == obj.id then isNew = true break end
                        end
                        if not isNew then
                            existingDiag = obj.mapAlignmentDiagnostic
                            existingFloorId = floor.floorid
                            existingObjId = obj.id
                            break
                        end
                    end
                end
                if existingDiag ~= nil then break end
            end

            if existingDiag ~= nil then
                printf("FLOOR_ALIGN_DIAG:: Reference (existing) Map object floorid=%s objid=%s", existingFloorId, existingObjId)
                for _, newObj in ipairs(newlySpawnedObjs) do
                    local newDiag = newObj.mapAlignmentDiagnostic
                    if newDiag == nil then
                        printf("FLOOR_ALIGN_DIAG:: New object %s had nil mapAlignmentDiagnostic", newObj.id)
                    else
                        local function get(t, k) return t[k] end
                        local exTilesX = get(existingDiag, "tilesAcross") or 0
                        local newTilesX = get(newDiag, "tilesAcross") or 0
                        local exTilesY = get(existingDiag, "tilesDown") or 0
                        local newTilesY = get(newDiag, "tilesDown") or 0
                        local exImgW = get(existingDiag, "imageWorldWidth") or 0
                        local newImgW = get(newDiag, "imageWorldWidth") or 0
                        local exImgH = get(existingDiag, "imageWorldHeight") or 0
                        local newImgH = get(newDiag, "imageWorldHeight") or 0
                        local exX1 = get(existingDiag, "areaX1") or 0
                        local exY1 = get(existingDiag, "areaY1") or 0
                        local exX2 = get(existingDiag, "areaX2") or 0
                        local exY2 = get(existingDiag, "areaY2") or 0
                        local newX1 = get(newDiag, "areaX1") or 0
                        local newY1 = get(newDiag, "areaY1") or 0
                        local newX2 = get(newDiag, "areaX2") or 0
                        local newY2 = get(newDiag, "areaY2") or 0
                        printf("FLOOR_ALIGN_DIAG:: COMPARE existing vs new:")
                        printf("FLOOR_ALIGN_DIAG::   existing: pos=(%.4f, %.4f) area=(%.4f, %.4f)-(%.4f, %.4f) imgWorld=(%.4f x %.4f) tiles=(%.4f x %.4f) tileDim=(%.6f, %.6f) pivot=(%.6f, %.6f) px/tile=(%.4f x %.4f)",
                            get(existingDiag,"x") or 0, get(existingDiag,"y") or 0,
                            exX1, exY1, exX2, exY2, exImgW, exImgH, exTilesX, exTilesY,
                            get(existingDiag,"tileDimX") or 0, get(existingDiag,"tileDimY") or 0,
                            get(existingDiag,"mapPivotX") or 0, get(existingDiag,"mapPivotY") or 0,
                            get(existingDiag,"pixelsPerTileX") or 0, get(existingDiag,"pixelsPerTileY") or 0)
                        printf("FLOOR_ALIGN_DIAG::   new     : pos=(%.4f, %.4f) area=(%.4f, %.4f)-(%.4f, %.4f) imgWorld=(%.4f x %.4f) tiles=(%.4f x %.4f) tileDim=(%.6f, %.6f) pivot=(%.6f, %.6f) px/tile=(%.4f x %.4f)",
                            get(newDiag,"x") or 0, get(newDiag,"y") or 0,
                            newX1, newY1, newX2, newY2, newImgW, newImgH, newTilesX, newTilesY,
                            get(newDiag,"tileDimX") or 0, get(newDiag,"tileDimY") or 0,
                            get(newDiag,"mapPivotX") or 0, get(newDiag,"mapPivotY") or 0,
                            get(newDiag,"pixelsPerTileX") or 0, get(newDiag,"pixelsPerTileY") or 0)
                        printf("FLOOR_ALIGN_DIAG::   delta   : pos=(%.4f, %.4f) topLeft=(%.4f, %.4f) bottomRight=(%.4f, %.4f) imgWorld=(%.4f x %.4f) tilesAcross=%.6f tilesDown=%.6f",
                            (get(newDiag,"x") or 0) - (get(existingDiag,"x") or 0),
                            (get(newDiag,"y") or 0) - (get(existingDiag,"y") or 0),
                            newX1 - exX1, newY1 - exY1, newX2 - exX2, newY2 - exY2,
                            newImgW - exImgW, newImgH - exImgH,
                            newTilesX - exTilesX, newTilesY - exTilesY)
                    end
                end
            else
                printf("FLOOR_ALIGN_DIAG:: No pre-existing Map object to compare against.")
            end
        end
        printf("FLOOR_ALIGN_DIAG:: ===== End post-spawn calibration dump =====")

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