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