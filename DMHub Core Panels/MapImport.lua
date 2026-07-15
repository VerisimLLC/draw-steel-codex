local mod = dmhub.GetModLoading()

-- Upper bound on per-axis tile count the import dialog will accept.
-- MapGridController.BuildMesh (C# engine) iterates O(width * height^2) on its
-- point-cull path, so a pathological manifest (one imported map in the wild
-- was 48358 x 19199) pegs a CPU core for hours before the map finishes
-- loading. MapGridController has its own 4M-cell bailout as a last resort;
-- this is the user-facing cap so the dialog refuses to ever produce one.
local MAX_MAP_TILES_PER_AXIS = 2000

local g_modalDialog = nil

-- Settings for the UVTT/Foundry import asset picker. Defaults match the
-- constants that were previously hardcoded in CreateMapDialog.lua so existing
-- import paths (and any caller of FinishMapImport that bypasses the picker)
-- continue to behave the same way.
setting{
    id = "mapimport:wall_asset_id",
    description = "UVTT Import: Wall Material",
    editor = "text",
    default = "-MGADhKw0vw30yXNF2-e",
    storage = "preference",
}
setting{
    id = "mapimport:object_wall_asset_id",
    description = "UVTT Import: Object Occluder Wall Material",
    editor = "text",
    default = "eae7f3fe-d278-455c-853a-ac43f948c743",
    storage = "preference",
}
setting{
    id = "mapimport:terrain_wall_asset_id",
    description = "UVTT Import: Terrain Wall Material",
    editor = "text",
    default = "",
    storage = "preference",
}
setting{
    id = "mapimport:invisible_wall_asset_id",
    description = "UVTT Import: Invisible Wall Material",
    editor = "text",
    default = "",
    storage = "preference",
}
setting{
    id = "mapimport:transparent_window_wall_asset_id",
    description = "UVTT Import: Transparent Window Wall Material",
    editor = "text",
    default = "",
    storage = "preference",
}
setting{
    id = "mapimport:unrecognized_wall_asset_id",
    description = "UVTT Import: Unrecognized Wall Material",
    editor = "text",
    default = "-MGADhKw0vw30yXNF2-e",
    storage = "preference",
}
setting{
    id = "mapimport:door_object_id",
    description = "UVTT Import: Door Object",
    editor = "text",
    default = "-MfWx0b2IlyApLQwasYg",
    storage = "preference",
}
setting{
    id = "mapimport:window_object_id",
    description = "UVTT Import: Window Object",
    editor = "text",
    default = "-MDd3Knydcq2WsjStef2",
    storage = "preference",
}
setting{
    id = "mapimport:secret_door_object_id",
    description = "UVTT Import: Secret Door Object",
    editor = "text",
    default = "-MfWx0b2IlyApLQwasYg",
    storage = "preference",
}
setting{
    id = "mapimport:light_object_id",
    description = "UVTT Import: Light Object",
    editor = "text",
    default = "2339211c-c35a-4e0a-a5fa-79d2e446bd3b",
    storage = "preference",
}
setting{
    id = "mapimport:structural_wall_mode",
    description = "UVTT Import: Structural wall behavior",
    editor = "text",
    default = "wall",
    storage = "preference",
}
setting{
    id = "mapimport:object_wall_mode",
    description = "UVTT Import: Object occluder behavior",
    editor = "text",
    default = "wall",
    storage = "preference",
}
setting{
    id = "mapimport:terrain_wall_mode",
    description = "UVTT Import: Foundry terrain wall behavior",
    editor = "text",
    default = "wall",
    storage = "preference",
}
setting{
    id = "mapimport:invisible_wall_mode",
    description = "UVTT Import: Foundry invisible wall behavior",
    editor = "text",
    default = "",
    storage = "preference",
}
-- Legacy setting retained so existing saved movement-wall choices can be read.
setting{
    id = "mapimport:movement_wall_mode",
    description = "UVTT Import: Legacy Foundry invisible wall behavior",
    editor = "text",
    default = "wall",
    storage = "preference",
}
setting{
    id = "mapimport:unrecognized_wall_mode",
    description = "UVTT Import: Unrecognized wall behavior",
    editor = "text",
    default = "none",
    storage = "preference",
}
setting{
    id = "mapimport:door_mode",
    description = "UVTT Import: Door behavior",
    editor = "text",
    default = "asset",
    storage = "preference",
}
setting{
    id = "mapimport:window_mode",
    description = "UVTT Import: Window behavior",
    editor = "text",
    default = "asset",
    storage = "preference",
}
setting{
    id = "mapimport:secret_door_mode",
    description = "UVTT Import: Secret door behavior",
    editor = "text",
    default = "asset",
    storage = "preference",
}
setting{
    id = "mapimport:light_mode",
    description = "UVTT Import: Light behavior",
    editor = "text",
    default = "asset",
    storage = "preference",
}
-- Some door/window assets are modelled with their long axis along X (the
-- door is "horizontal" by default) while others have it along Y. The
-- standard placement formula rotates by +90 to fit the wall orientation,
-- which is correct for one convention and produces 90-degree-rotated
-- (perpendicular) doors for the other. If your chosen asset places
-- doors perpendicular to walls, flip this setting to 0.
setting{
    id = "mapimport:portal_rotation_offset",
    description = "UVTT Import: Portal rotation offset (90 or 0 if doors appear perpendicular)",
    editor = "text",
    default = 90,
    storage = "preference",
}
setting{
    id = "mapimport:portal_object_scale_multiplier",
    description = "UVTT Import: Door/window art scale multiplier",
    editor = "text",
    default = 1,
    storage = "preference",
}
setting{
    id = "mapimport:flip_foundry_terrain_walls",
    description = "UVTT Import: Flip Foundry terrain wall direction",
    editor = "check",
    default = false,
    storage = "preference",
}

local function ProgressPanel()

	return gui.Panel{
		flow = "vertical",
		halign = "center",
		valign = "center",
		width = "100%",
		height = 256,

		gui.ProgressBar{
			width = "80%",
			height = 64,
			value = 0,
		},

		gui.Label{
			text = "Importing...",
			width = "auto",
			height = "auto",
			fontSize = 16,
			margin = 6,
		},
	}
end

local function ErrorPanel(msg)
    return gui.Label{
        width = "auto",
        height = "auto",
        maxWidth = 500,
        halign = "center",
        valign = "center",
        fontSize = 18,
        text = msg,
    }
end

local function ComponentTypeMatches(value, componentType)
    if value == nil then
        return false
    end

    local text = tostring(value)
    return text == componentType or text == ("ObjectComponent" .. componentType)
end

local function ComponentField(component, field)
    local ok, value = pcall(function()
        return component[field]
    end)
    if ok then
        return value
    end

    return nil
end

local function ComponentMatches(component, key, componentType)
    if ComponentTypeMatches(key, componentType) then
        return true
    end

    return ComponentTypeMatches(ComponentField(component, "name"), componentType)
        or ComponentTypeMatches(ComponentField(component, "type"), componentType)
        or ComponentTypeMatches(ComponentField(component, "componentType"), componentType)
        or ComponentTypeMatches(ComponentField(component, "@class"), componentType)
end

local function ObjectNodeHasComponent(id, componentType)
    local node = id and assets:GetObjectNode(id)
    if node == nil or node.components == nil then
        return false
    end

    for key, component in pairs(node.components) do
        if ComponentMatches(component, key, componentType) then
            return true
        end
    end

    return false
end

mod.shared.ImportMapDialog = function(paths, options)
    options = options or {}

    local resultPanel
    local importPanel

    local tileType = options.tileType or "squares"

    -- 140 PPS auto-detection state.
    local perfectFitChecked = false
    local perfectFitActive = false

    -- Forward-declare so the confirmButton closure (defined below) can capture them as upvalues.
    -- Set later inside the floorImport branch when the user clicks "Match Existing Map".
    local matchApplied = false
    local capturedMatchCalibration = nil

    local confirmButton = gui.Button{
        classes = {"sizeL", "hidden"},
        text = "Finish",
        valign = "center",
        halign = "center",
        click = function()
            resultPanel.children = {
                ProgressPanel()
            }
            importPanel:Confirm(function(progress, info)

                if progress == nil then
                    -- Capture values before closing the modal destroys the panel.
                    local imgW = importPanel.imageWidth
                    local imgH = importPanel.imageHeight

                    printf("FLOOR_ALIGN_DIAG:: Confirm finish (Finish button). imgW=%s imgH=%s info.width=%s info.height=%s matchApplied=%s",
                        tostring(imgW), tostring(imgH), tostring(info.width), tostring(info.height), tostring(matchApplied))
                    printf("FLOOR_ALIGN_DIAG:: Confirm info=%s", json(info))

                    gui.CloseModal()

                    g_modalDialog = nil

                    if options.finish ~= nil then
                        -- Attach the local file paths and image dimensions for the alignment dialog.
                        info.paths = paths
                        info.imageWidth = imgW
                        info.imageHeight = imgH
                        if matchApplied and capturedMatchCalibration ~= nil then
                            info.matchCalibration = capturedMatchCalibration
                            printf("FLOOR_ALIGN_DIAG:: Attached matchCalibration to info: %s", json(capturedMatchCalibration))
                        end
                        options.finish(info)
                    end
                    return
                end

                resultPanel:FireEventTree("progress", progress)
            end)
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
            end
        end,

        vmargin = 16,
    }

    -- "Match Existing Map" panel for floor imports.
    local matchMapPanel = nil

    if options.floorImport then
        local dim = game.currentMap.dimensions
        local mapW = dim.x2 - dim.x1
        local mapH = dim.y2 - dim.y1

        printf("FLOOR_ALIGN_DIAG:: ImportMapDialog opened with floorImport=true. Existing currentMap.dimensions: x1=%s y1=%s x2=%s y2=%s -> mapW=%d mapH=%d",
            json(dim.x1), json(dim.y1), json(dim.x2), json(dim.y2), mapW, mapH)

        -- Try to find the existing primary map LevelObject so we can compare calibration later.
        local existingMapObj = nil
        for _, floor in ipairs(game.currentMap.floors) do
            for _, obj in pairs(floor.objects) do
                if obj:GetComponent("Map") ~= nil then
                    existingMapObj = obj
                    break
                end
            end
            if existingMapObj ~= nil then break end
        end
        if existingMapObj ~= nil then
            local d = existingMapObj.mapAlignmentDiagnostic
            if d ~= nil then
                printf("FLOOR_ALIGN_DIAG:: Existing map LevelObject calibration: %s", json(d))
            else
                printf("FLOOR_ALIGN_DIAG:: existingMapObj had no mapAlignmentDiagnostic (component not yet calculated?)")
            end
        else
            printf("FLOOR_ALIGN_DIAG:: No existing map LevelObject with a Map component found on currentMap.")
        end

        if mapW > 0 and mapH > 0 then
            local matchInfoLabel = gui.Label{
                width = 380,
                height = "auto",
                fontSize = 14,
                text = "",
                wrap = true,
            }

            matchMapPanel = gui.Panel{
                classes = {"hidden"},
                flow = "vertical",
                width = 400,
                height = "auto",
                vmargin = 8,

                updateMatchInfo = function(element, imgW, imgH)
                    local tileW = imgW / mapW
                    local tileH = imgH / mapH
                    local ratio = math.abs(tileW - tileH) / math.max(tileW, tileH)
                    printf("FLOOR_ALIGN_DIAG:: updateMatchInfo: imgW=%s imgH=%s mapW=%d mapH=%d -> tileW=%.4f tileH=%.4f ratio=%.4f",
                        tostring(imgW), tostring(imgH), mapW, mapH, tileW, tileH, ratio)
                    if ratio < 0.02 then
                        matchInfoLabel.text = string.format("Image dimensions match the existing map. Tile size would be %.0f x %.0f px.", tileW, tileH)
                    else
                        matchInfoLabel.text = string.format("Tile size would be %.1f x %.1f px (non-square tiles).", tileW, tileH)
                    end
                end,

                gui.Label{
                    width = 400,
                    height = "auto",
                    fontSize = 14,
                    wrap = true,
                    text = string.format("The existing map is %dx%d tiles.", mapW, mapH),
                },

                matchInfoLabel,

                gui.Button{
                    classes = {"sizeL"},
                    text = "Match Existing Map",
                    halign = "left",
                    vmargin = 4,
                    click = function(element)
                        printf("FLOOR_ALIGN_DIAG:: 'Match Existing Map' clicked. Calling CreateGridless + SetMapDimensions(%d, %d). imgW=%s imgH=%s",
                            mapW, mapH, tostring(importPanel.imageWidth), tostring(importPanel.imageHeight))

                        -- Capture the existing Map LevelObject's calibration so the
                        -- new floor can copy controlPoints/scaling/mapType verbatim.
                        -- This makes the new image render with identical _tileDim and
                        -- _mapPivot, so it occupies the same world bounds as the existing
                        -- when placed at the same (obj.x, obj.y).
                        capturedMatchCalibration = nil
                        for _, floor in ipairs(game.currentMap.floors) do
                            for _, obj in pairs(floor.objects) do
                                if obj:GetComponent("Map") ~= nil then
                                    local d = obj.mapAlignmentDiagnostic
                                    if d ~= nil then
                                        local cps = {}
                                        local cpCount = d.controlPointCount or 0
                                        if d.controlPoints ~= nil then
                                            for i = 1, cpCount do
                                                local p = d.controlPoints[i]
                                                if p ~= nil then
                                                    cps[#cps+1] = {x = p.x, y = p.y}
                                                end
                                            end
                                        end
                                        capturedMatchCalibration = {
                                            controlPoints = cps,
                                            scaling = d.scaling or 1,
                                            mapType = d.mapType or "squares",
                                            x = d.x or 0,
                                            y = d.y or 0,
                                            sourceFloorid = d.floorid,
                                            sourceObjid = d.objid,
                                            sourceTileDimX = d.tileDimX,
                                            sourceTileDimY = d.tileDimY,
                                        }
                                        printf("FLOOR_ALIGN_DIAG:: Captured match calibration from %s/%s: cps=%d, scaling=%d, mapType=%s, x=%.4f, y=%.4f",
                                            d.floorid, d.objid, #cps, d.scaling or 1, tostring(d.mapType), d.x or 0, d.y or 0)
                                        break
                                    end
                                end
                            end
                            if capturedMatchCalibration ~= nil then break end
                        end
                        if capturedMatchCalibration == nil then
                            printf("FLOOR_ALIGN_DIAG:: WARNING: Match Existing Map clicked but no existing Map LevelObject found to capture from.")
                        end

                        importPanel:CreateGridless()
                        gridlessChoice.value = false
                        importPanel:SetMapDimensions(mapW, mapH)
                        matchApplied = true
                    end,
                },
            }
        end
    end

    local instructionsPanel = gui.Panel{
        width = 400,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        instructionsText,
        gridlessChoice,
        matchMapPanel,
    }

    -- "A Perfect Fit!" panel for 140 PPS auto-detection.
    local perfectFitPanel
    perfectFitPanel = gui.Panel{
        classes = {"hidden"},
        flow = "vertical",
        width = 400,
        height = "auto",
        halign = "left",
        valign = "top",

        gui.Label{
            width = 400,
            height = "auto",
            fontSize = 28,
            bold = true,
            color = "@success",
            text = "A Perfect Fit!",
            vmargin = 4,
        },

        gui.Label{
            id = "perfectFitDescription",
            width = 380,
            height = "auto",
            fontSize = 16,
            wrap = true,
            text = "",
            vmargin = 8,
        },

        gui.Label{
            id = "perfectFitDimensions",
            width = 380,
            height = "auto",
            fontSize = 20,
            text = "",
            vmargin = 4,
        },

        gui.Panel{
            width = 1,
            height = 24,
        },

        gui.Button{
            classes = {"sizeL"},
            id = "perfectFitAccept",
            text = "Accept",
            halign = "left",
            click = function(element)
                -- Trigger the same confirm flow as the Finish button.
                resultPanel.children = {
                    ProgressPanel()
                }
                importPanel:Confirm(function(progress, info)
                    if progress == nil then
                        local imgW = importPanel.imageWidth
                        local imgH = importPanel.imageHeight
                        gui.CloseModal()
                        g_modalDialog = nil
                        if options.finish ~= nil then
                            info.paths = paths
                            info.imageWidth = imgW
                            info.imageHeight = imgH
                            options.finish(info)
                        end
                        return
                    end
                    resultPanel:FireEventTree("progress", progress)
                end)
            end,
        },

        gui.Button{
            classes = {"sizeL"},
            text = "Customize Grid...",
            halign = "left",
            vmargin = 8,
            click = function(element)
                perfectFitActive = false
                perfectFitPanel:SetClass("hidden", true)
                instructionsPanel:SetClass("hidden", false)
                importPanel:ClearMarkers()
                gridlessChoice.value = true
            end,
        },
    }

    local statusWidth = gui.Input{
        fontSize = 16,
        width = 80,
        height = 24,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val >= 8 and val <= 4096 then
                importPanel:SetWidth(val)
            end
        end,
    }
    local statusHeight = gui.Input{
        fontSize = 16,
        width = 80,
        height = 24,
        change = function(element)
            local val = tonumber(element.text)
            if val ~= nil and val >= 8 and val <= 4096 then
                importPanel:SetHeight(val)
            end
        end,
    }

    -- Try to parse map dimensions from filename (e.g. "dungeon_20x18.png").
    local inferredMapW, inferredMapH = nil, nil
    if paths and #paths > 0 then
        local filename = paths[1]
        -- Strip directory separators to get just the filename.
        filename = string.match(filename, "[^/\\]+$") or filename
        -- Look for NxM pattern (digits x digits).
        local w, h = string.match(filename, "(%d+)x(%d+)")
        if w and h then
            w, h = tonumber(w), tonumber(h)
            if w >= 1 and w <= 500 and h >= 1 and h <= 500 then
                inferredMapW, inferredMapH = w, h
            end
        end
    end

    -- Track whether we're showing tile dimensions or map dimensions mode.
    local dimMode = "tile" -- "tile" or "map"

    -- Track which map dimension fields the user has manually edited.
    local mapWidthTouched = false
    local mapHeightTouched = false

    local tileDimPanel
    local mapDimPanel

    tileDimPanel = gui.Panel{
        flow = "vertical",
        width = "auto",
        height = "auto",

        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            gui.Label{
                classes = {"sizeL"},
                width = 90,
                height = "auto",
                text = "Width:",
            },
            statusWidth,
            gui.Label{
                classes = {"sizeL"},
                lmargin = 4,
                width = "auto",
                height = "auto",
                text = "px",
            },
        },

        gui.Button{
            classes = {"sizeM"},
            vmargin = 8,
            icon = "icons/icon_tool/icon_tool_30_unlocked.png",

            data = {
                unlocked = true,
            },

            press = function(element)
                element.data.unlocked = not element.data.unlocked
                importPanel.lockDimensions = not element.data.unlocked
                element.bgimage = cond(element.data.unlocked, "icons/icon_tool/icon_tool_30_unlocked.png", "icons/icon_tool/icon_tool_30.png")
            end,
        },

        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            gui.Label{
                classes = {"sizeL"},
                width = 90,
                height = "auto",
                text = "Height:",
            },
            statusHeight,
            gui.Label{
                classes = {"sizeL"},
                lmargin = 4,
                width = "auto",
                height = "auto",
                text = "px",
            },
        },
    }

    -- Get image dimensions using simple float properties (more robust than vec2).
    local function getImageDim()
        local w = importPanel.imageWidth
        local h = importPanel.imageHeight
        if w ~= nil and h ~= nil and w > 0 and h > 0 then
            return w, h
        end
        return nil, nil
    end

    local mapDimInfoLabel
    local mapDimWidth
    local mapDimHeight

    -- Shared handler: called when either map dimension field is edited.
    -- `source` is "width" or "height", `val` is the parsed integer from that field.
    local function onMapDimEdit(source, val)
        if val == nil or val < 1 or val ~= math.floor(val) then
            return
        end

        -- Cap per-axis tile count. See MAX_MAP_TILES_PER_AXIS above for why.
        if val > MAX_MAP_TILES_PER_AXIS then
            val = MAX_MAP_TILES_PER_AXIS
            if source == "width" then
                mapDimWidth.textNoNotify = tostring(val)
            else
                mapDimHeight.textNoNotify = tostring(val)
            end
        end

        local imgW, imgH = getImageDim()
        if imgW == nil then
            return
        end

        if source == "width" then
            mapWidthTouched = true
            if not mapHeightTouched then
                local inferredH = math.floor(val * (imgH / imgW) + 0.5)
                if inferredH < 1 then inferredH = 1 end
                if inferredH > MAX_MAP_TILES_PER_AXIS then inferredH = MAX_MAP_TILES_PER_AXIS end
                mapDimHeight.textNoNotify = tostring(inferredH)
                importPanel:SetMapDimensions(val, inferredH)
            else
                local hVal = tonumber(mapDimHeight.text)
                if hVal ~= nil and hVal >= 1 and hVal == math.floor(hVal) then
                    if hVal > MAX_MAP_TILES_PER_AXIS then
                        hVal = MAX_MAP_TILES_PER_AXIS
                        mapDimHeight.textNoNotify = tostring(hVal)
                    end
                    importPanel:SetMapDimensions(val, hVal)
                end
            end
        else
            mapHeightTouched = true
            if not mapWidthTouched then
                local inferredW = math.floor(val * (imgW / imgH) + 0.5)
                if inferredW < 1 then inferredW = 1 end
                if inferredW > MAX_MAP_TILES_PER_AXIS then inferredW = MAX_MAP_TILES_PER_AXIS end
                mapDimWidth.textNoNotify = tostring(inferredW)
                importPanel:SetMapDimensions(inferredW, val)
            else
                local wVal = tonumber(mapDimWidth.text)
                if wVal ~= nil and wVal >= 1 and wVal == math.floor(wVal) then
                    if wVal > MAX_MAP_TILES_PER_AXIS then
                        wVal = MAX_MAP_TILES_PER_AXIS
                        mapDimWidth.textNoNotify = tostring(wVal)
                    end
                    importPanel:SetMapDimensions(wVal, val)
                end
            end
        end

        mapDimInfoLabel:FireEvent("updateInfo")
    end

    mapDimWidth = gui.Input{
        fontSize = 16,
        width = 80,
        height = 24,
        placeholderText = "width",
        edit = function(element)
            onMapDimEdit("width", tonumber(element.text))
        end,
        change = function(element)
            onMapDimEdit("width", tonumber(element.text))
        end,
    }

    mapDimHeight = gui.Input{
        fontSize = 16,
        width = 80,
        height = 24,
        placeholderText = "height",
        edit = function(element)
            onMapDimEdit("height", tonumber(element.text))
        end,
        change = function(element)
            onMapDimEdit("height", tonumber(element.text))
        end,
    }

    mapDimInfoLabel = gui.Label{
        width = 280,
        height = "auto",
        fontSize = 14,
        text = "",

        updateInfo = function(element)
            local wVal = tonumber(mapDimWidth.text)
            local hVal = tonumber(mapDimHeight.text)
            local imgW, imgH = getImageDim()
            if wVal and hVal and wVal >= 1 and hVal >= 1 and imgW then
                local tileW = imgW / wVal
                local tileH = imgH / hVal
                local txt = string.format("Tile size: %.1f x %.1f px", tileW, tileH)
                if wVal >= MAX_MAP_TILES_PER_AXIS or hVal >= MAX_MAP_TILES_PER_AXIS then
                    txt = txt .. string.format("\n<color=#ffaa55>Clamped at %d tiles per axis.</color>", MAX_MAP_TILES_PER_AXIS)
                end
                element.text = txt
            else
                element.text = ""
            end
        end,
    }

    mapDimPanel = gui.Panel{
        classes = {"hidden"},
        flow = "vertical",
        width = "auto",
        height = "auto",

        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            gui.Label{
                width = 90,
                height = "auto",
                text = "Width:",
                fontSize = 18,
            },
            mapDimWidth,
            gui.Label{
                width = "auto",
                height = "auto",
                text = " tiles",
                fontSize = 18,
            },
        },

        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            gui.Label{
                width = 90,
                height = "auto",
                text = "Height:",
                fontSize = 18,
            },
            mapDimHeight,
            gui.Label{
                width = "auto",
                height = "auto",
                text = " tiles",
                fontSize = 18,
            },
        },

        mapDimInfoLabel,
    }

    local dimModeChoice = gui.EnumeratedSliderControl{
        options = {
            {id = "tile", text = "Tile Dimensions"},
            {id = "map", text = "Map Dimensions"},
        },

        width = 280,

        value = cond(inferredMapW ~= nil, "map", "tile"),

        change = function(element)
            dimMode = element.value
            tileDimPanel:SetClass("hidden", dimMode ~= "tile")
            mapDimPanel:SetClass("hidden", dimMode ~= "map")
        end,

        create = function(element)
            dimMode = element.value
            tileDimPanel:SetClass("hidden", dimMode ~= "tile")
            mapDimPanel:SetClass("hidden", dimMode ~= "map")
        end,

        vmargin = 4,
    }

    local statusPanel = gui.Panel{
        classes = {"hidden"},
        flow = "vertical",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "center",

        dimModeChoice,

        tileDimPanel,
        mapDimPanel,

        --some padding.
        gui.Panel{
            width = 1,
            height = 40,
        },

        gui.Panel{
            classes = {cond(tileType == "squares", nil, "hidden")},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            gui.Label{
                classes = {"sizeL"},
                hmargin = 4,
                width = "auto",
                height = "auto",
                text = "1 tile = ",
            },

            gui.Input{
                characterLimit = 3,
                width = 90,
                text = tostring(MeasurementSystem.NativeToDisplayString(dmhub.unitsPerSquare)),
                edit = function(element)
                    local num = MeasurementSystem.DisplayToNative(tonumber(element.text))
                    if num ~= nil then
                        num = math.floor(num)
                    end
                    if num == nil or num%dmhub.unitsPerSquare ~= 0 or num <= 0 then
                        element.parent.parent:FireEventTree("scalingError")
                        return
                    end

                    element:FireEvent("change")
                end,
                change = function(element)
                    if importPanel == nil then
                        return
                    end
                    local num = MeasurementSystem.DisplayToNative(tonumber(element.text))
                    if num ~= nil then
                        num = math.floor(num)
                    end
                    if num == nil or num%dmhub.unitsPerSquare ~= 0 or num <= 0 then
                        element.text = tostring(MeasurementSystem.NativeToDisplayString(importPanel.tileScaling*dmhub.unitsPerSquare))
                        element.parent.parent:FireEventTree("updateScaling")
                        return
                    end

                    importPanel.tileScaling = num/dmhub.unitsPerSquare
                    element.text = tostring(MeasurementSystem.NativeToDisplayString(importPanel.tileScaling*dmhub.unitsPerSquare))
                    element.parent.parent:FireEventTree("updateScaling")
                end,
            },
            
            gui.Label{
                classes = {"sizeL"},
                lmargin = 4,
                width = "auto",
                height = "auto",
                text = string.format(" %s", string.lower(MeasurementSystem.UnitName())),
            },
        },

        gui.Label{
            classes = {"form", "sizeL"},
            tmargin = 8,
            lmargin = 52,
            width = 280,
            height = "auto",
            create = function(element)
                element:FireEvent("updateScaling")
            end,

            updateScaling = function(element)
                if importPanel.tileScaling == 1 then
                    element.text = "A tile in the imported map will become 1 tile in Draw Steel."
                    return
                end

                element.text = string.format("A tile in the imported map will become %dx%d tiles in Draw Steel.", importPanel.tileScaling, importPanel.tileScaling)
            end,

            scalingError = function(element)
                element.text = string.format("Enter a multiple of %s", tostring(MeasurementSystem.CurrentSystem().tileSize))
            end,

        }
    }

    local layerIndex = 1

    local layersPagingPanel
    if #paths > 1 then
        layersPagingPanel = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "center",

            gui.Button{
                classes = {"pagingArrow", "sizeXl"},
                height = 24,
                press = function(element)
                    layerIndex = layerIndex-1
                    if layerIndex == 0 then
                        layerIndex = #paths
                    end

                    resultPanel:FireEventTree("refresh")
                end,
            },

            gui.Label{
                width = 160,
                height = 20,
                fontSize = 14,
                textAlignment = "center",

                refresh = function(element)
                    element.text = string.format("Layer %d/%d", layerIndex, #paths)
                end,
            },

            gui.Button{
                classes = {"pagingArrow", "sizeXl", "right"},
                height = 24,
                press = function(element)
                    layerIndex = layerIndex+1
                    if layerIndex == #paths+1 then
                        layerIndex = 1
                    end

                    resultPanel:FireEventTree("refresh")
                end,
            },
        }
    end

    local zoomSlider = gui.Slider{
		style = {
			height = 20,
			width = 200,
			fontSize = 14,
		},
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
            importPanel.zoom = element.value*0.01
        end,
        think = function(element)
            if not element.dragging then
                element.data.setValueNoEvent(importPanel.zoom*100)
            end
        end,

    }

    importPanel = gui.MapImport{
        paths = paths,
        width = 800,
        height = 800,
        halign = "right",
        valign = "top",
        y = 26,

        tileType = tileType,

        refresh = function(element)
            element.pathIndex = layerIndex
        end,

        thinkTime = 0.05,

        think = function(element)
            -- One-shot 140 PPS detection.
            if not perfectFitChecked and not options.floorImport and tileType == "squares" then
                local imgW = element.imageWidth
                local imgH = element.imageHeight
                if imgW ~= nil and imgW > 0 and imgH ~= nil and imgH > 0 then
                    perfectFitChecked = true
                    local pps = 140
                    local tilesW = imgW / pps
                    local tilesH = imgH / pps
                    local rW = math.abs(tilesW - math.floor(tilesW + 0.5))
                    local rH = math.abs(tilesH - math.floor(tilesH + 0.5))
                    if rW < 0.01 and rH < 0.01 then
                        tilesW = math.floor(tilesW + 0.5)
                        tilesH = math.floor(tilesH + 0.5)
                        if tilesW >= 1 and tilesH >= 1
                           and tilesW <= MAX_MAP_TILES_PER_AXIS
                           and tilesH <= MAX_MAP_TILES_PER_AXIS then
                            perfectFitActive = true

                            -- Configure the grid preview at detected dimensions.
                            element:CreateGridless()
                            element:SetMapDimensions(tilesW, tilesH)

                            -- Populate the panel text.
                            perfectFitPanel:Get("perfectFitDescription").text = string.format(
                                "This image is %dx%d pixels, which perfectly fits a %dx%d tile grid at 140 pixels per square -- the standard used by most professional map creators.",
                                imgW, imgH, tilesW, tilesH
                            )
                            perfectFitPanel:Get("perfectFitDimensions").text = string.format(
                                "%d x %d tiles", tilesW, tilesH
                            )

                            -- Show perfect fit panel, hide normal instructions.
                            perfectFitPanel:SetClass("hidden", false)
                            instructionsPanel:SetClass("hidden", true)
                        end
                    end
                end
            end

            -- While perfect fit is active, hide the normal calibration controls.
            if perfectFitActive then
                previousButton:SetClass("hidden", true)
                continueButton:SetClass("hidden", true)
                confirmButton:SetClass("hidden", true)
                statusPanel:SetClass("hidden", true)
                return
            end

            gridlessChoice:SetClass("hidden", gridlessChoice.value and (element.haveNext or element.havePrevious or element.haveConfirm or not string.starts_with(element.instructionsText, "Pick a grid square")))
            previousButton:SetClass("hidden", not element.havePrevious)
            continueButton:SetClass("hidden", not element.haveNext)
            confirmButton:SetClass("hidden", not element.haveConfirm)

            -- Show/hide "Match Existing Map" panel for floor imports.
            if matchMapPanel ~= nil then
                local inSizing = element.haveNext or element.havePrevious or element.haveConfirm
                local imgW = element.imageWidth
                local imgH = element.imageHeight
                local haveImg = imgW ~= nil and imgW > 0 and imgH ~= nil and imgH > 0
                local showMatch = haveImg and not inSizing and not matchApplied
                matchMapPanel:SetClass("hidden", not showMatch)
                if showMatch then
                    matchMapPanel:FireEvent("updateMatchInfo", imgW, imgH)
                end
            end
            instructionsText.text = element.instructionsText

            local tileDim = element.tileDim
            if tileDim == nil then
                statusPanel:SetClass("hidden", true)
            else
                statusPanel:SetClass("hidden", false)

                -- Show the mode toggle only in gridless mode.
                local isGridless = gridlessChoice.value == false
                dimModeChoice:SetClass("hidden", not isGridless)
                -- In grid mode, always show tile dimensions.
                if not isGridless then
                    tileDimPanel:SetClass("hidden", false)
                    mapDimPanel:SetClass("hidden", true)
                end

                if (not statusWidth.hasInputFocus) and (not statusHeight.hasInputFocus) then
                    statusWidth.textNoNotify = string.format("%.2f", tileDim.x)
                    statusHeight.textNoNotify = string.format("%.2f", tileDim.y)
                end

                -- Apply inferred dimensions from filename on first availability.
                local imgW = element.imageWidth
                local imgH = element.imageHeight
                local haveImageDim = imgW ~= nil and imgW > 0 and imgH ~= nil and imgH > 0

                if inferredMapW ~= nil and haveImageDim then
                    local w, h = inferredMapW, inferredMapH
                    inferredMapW, inferredMapH = nil, nil
                    mapWidthTouched = true
                    mapHeightTouched = true
                    mapDimWidth.textNoNotify = tostring(w)
                    mapDimHeight.textNoNotify = tostring(h)
                    element:SetMapDimensions(w, h)
                end

                -- Update map dimension display from current tile dims (only when user is not editing).
                if haveImageDim and (not mapDimWidth.hasInputFocus) and (not mapDimHeight.hasInputFocus) and dimMode ~= "map" then
                    mapDimWidth.textNoNotify = string.format("%d", math.floor(imgW / tileDim.x + 0.5))
                    mapDimHeight.textNoNotify = string.format("%d", math.floor(imgH / tileDim.y + 0.5))
                end

                mapDimInfoLabel:FireEvent("updateInfo")
            end

            if element.error ~= nil then
                resultPanel.children = {
                    ErrorPanel(string.format("Error: %s", element.error))
                }
                return

            end
        end,
    }

    importPanel.pathIndex = layerIndex

    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        bgimage = "panels/square.png",
        flow = "none",
        zoomSlider,
        layersPagingPanel,
        importPanel,
        buttonsPanel,
        instructionsPanel,
        perfectFitPanel,
        statusPanel,
    }

    if importPanel.errorMessage ~= nil then
        local msg = importPanel.errorMessage
        resultPanel.children = {
            gui.Label{
                halign = "center",
                valign = "center",
                width = "auto",
                height = "auto",
                fontSize = 18,
                text = importPanel.errorMessage
            }
        }
    end

    resultPanel:FireEventTree("refresh")

    return resultPanel
end

local function CountImportFeatures(uvttData)
    local counts = {
        structural = 0,
        object = 0,
        terrain = 0,
        invisible = 0,
        unrecognized = 0,
        doors = 0,
        windows = 0,
        secretDoors = 0,
        lights = 0,
    }
    if uvttData == nil then return counts end

    local function countSegments(lineSet)
        local n = 0
        if type(lineSet) ~= "table" then
            return 0
        end
        for _, segment in ipairs(lineSet) do
            if type(segment) == "table" and #segment >= 2 then
                n = n + 1
            end
        end
        return n
    end

    local function addOne(d)
        if type(d) ~= "table" then return end
        counts.structural = counts.structural + countSegments(d.line_of_sight)
        counts.object = counts.object + countSegments(d.objects_line_of_sight)
        if type(d.portals) == "table" then
            for _, portal in ipairs(d.portals) do
                if type(portal) == "table" then
                    if portal.closed == true then
                        if portal.secret == true then
                            counts.secretDoors = counts.secretDoors + 1
                        else
                            counts.doors = counts.doors + 1
                        end
                    else
                        counts.windows = counts.windows + 1
                    end
                end
            end
        end
        if type(d.lights) == "table" then
            counts.lights = counts.lights + #d.lights
        end
        if d.foundry_terrain_walls ~= nil then
            counts.terrain = counts.terrain + #d.foundry_terrain_walls
        end
        if d.foundry_invisible_walls ~= nil then
            counts.invisible = counts.invisible + #d.foundry_invisible_walls
        end
        if d.foundry_movement_walls ~= nil then
            counts.invisible = counts.invisible + #d.foundry_movement_walls
        end
        if d.foundry_unrecognized_walls ~= nil then
            counts.unrecognized = counts.unrecognized + #d.foundry_unrecognized_walls
        end

        if type(d.line_of_sight) ~= "table" and type(d.walls) == "table" then
            for _, wall in ipairs(d.walls) do
                if type(wall) == "table" then
                    local points = wall.c
                    if type(points) == "table" and #points == 4 then
                        local door = tonumber(wall.door) or 0
                        local move = tonumber(wall.move) or 20
                        local sight = tonumber(wall.sight) or 20
                        local light = tonumber(wall.light) or 20
                        local dir = tonumber(wall.dir) or 0
                        local threshold = type(wall.threshold) == "table" and wall.threshold or nil
                        local windowLike = threshold ~= nil
                            and threshold.light ~= nil and threshold.sight ~= nil
                            and light ~= move and sight ~= move

                        if (door == 0 or door == 2) and windowLike then
                            counts.windows = counts.windows + 1
                        elseif door == 1 then
                            counts.doors = counts.doors + 1
                        elseif door == 2 then
                            counts.secretDoors = counts.secretDoors + 1
                        elseif door == 0 and dir ~= 0 then
                            counts.unrecognized = counts.unrecognized + 1
                        elseif door ~= 0 and door ~= 1 and door ~= 2 then
                            counts.unrecognized = counts.unrecognized + 1
                        elseif door == 0 and sight == 20 and move == 20 then
                            counts.structural = counts.structural + 1
                        elseif door == 0 and sight == 10 and move == 20 then
                            counts.terrain = counts.terrain + 1
                        elseif door == 0 and sight == 0 and move == 20 then
                            counts.invisible = counts.invisible + 1
                        elseif door == 0 then
                            counts.unrecognized = counts.unrecognized + 1
                        end
                    end
                end
            end
        end
    end
    addOne(uvttData)
    if type(uvttData) == "table" then
        for _,d in ipairs(uvttData) do
            addOne(d)
        end
    end
    return counts
end

local PICKER_LIMIT = 20
local PICKER_UI = {
    dialogWidth = 760,
    dialogHeight = 720,
    tooltipWidth = 304,
    tooltipContentWidth = 280,
    tooltipWallWidth = 240,
    tooltipWallHeight = 60,
    tooltipObjectSize = 220,
    tileLabelLength = 28,
    summaryLength = 44,
    summaryWidth = 330,
    headerLabelWidth = 190,
    headerHeight = 42,
    searchWidth = 320,
    inputWidth = 80,
    inputHeight = 24,
    thumbnail = {
        square = {tileW = 96, tileH = 120, imageW = 80, imageH = 80},
        wide = {tileW = 160, tileH = 80, imageW = 144, imageH = 44},
    },
    preview = {
        square = {outerW = 38, outerH = 38, innerW = 30, innerH = 30},
        wide = {outerW = 86, outerH = 34, innerW = 74, innerH = 22},
    },
}

local function ShortLabel(s, maxLen)
    s = tostring(s or "")
    s = string.gsub(s, "[\r\n]+", " ")
    if #s <= maxLen then return s end
    return string.sub(s, 1, maxLen - 3) .. "..."
end

-- Keep search focused on the asset title/header rather than long item lore.
local SEARCH_HEAD_LEN = 60

local function ObjectBehaviorText(node)
    if node == nil or node.components == nil then return nil end
    local parts = {}
    local seen = {}
    for _,component in pairs(node.components) do
        local text = component.behaviorDescription
        if text ~= nil and text ~= "" and not seen[text] then
            parts[#parts+1] = text
            seen[text] = true
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "\n")
end

local function ObjectItemFromNode(id, node, suffix)
    local baseLabel = (node and (node.description or node.name)) or id
    return {
        id = id,
        label = (suffix and (baseLabel .. " " .. suffix)) or baseLabel,
        kind = "object",
        image = node and node.image,
        thumbnailId = node and node.thumbnailId,
        description = node and node.description,
        behavior = ObjectBehaviorText(node),
        artist = node and node.artist,
        hue = node and node.hue,
        saturation = node and node.saturation,
        brightness = node and node.brightness,
    }
end

local function SearchObjectItems(query, currentId)
    local q = string.lower(query or "")
    local items = {}
    local seen = {}
    local totalMatched = 0

    local function addCurrent()
        if currentId == nil or currentId == "" or seen[currentId] then return end
        local node = assets:GetObjectNode(currentId)
        items[#items+1] = ObjectItemFromNode(currentId, node, "(current)")
        seen[currentId] = true
    end

    addCurrent()

    local function record(id, v)
        if id == nil or seen[id] then return end
        totalMatched = totalMatched + 1
        if #items < PICKER_LIMIT then
            items[#items+1] = ObjectItemFromNode(id, v)
        end
        seen[id] = true
    end

    if q ~= "" then
        local kwObjs = assets:GetObjectsWithKeyword(q)
        if kwObjs ~= nil then
            for _,v in ipairs(kwObjs) do
                record(v.id, v)
            end
        end

        if assets.allObjects ~= nil then
            for id,v in pairs(assets.allObjects) do
                if v ~= nil and not v.isfolder and not seen[id] then
                    local head = string.lower(string.sub(
                        tostring(v.description or v.name or id), 1, SEARCH_HEAD_LEN))
                    if string.find(head, q, 1, true) ~= nil then
                        record(id, v)
                    end
                end
            end
        end
    elseif assets.allObjects ~= nil then
        for id,v in pairs(assets.allObjects) do
            if v ~= nil and not v.isfolder then
                record(id, v)
            end
        end
    end

    return items, totalMatched
end

-- TODO: Replace this raw-field summary with an engine-provided WallAsset
-- behavior description when one is exposed.
local function WallBehaviorText(wall)
    if wall == nil then return nil end
    local parts = {}
    local fields = {
        "invisible",
        "visionOneWay",
        "visionWidth",
        "movementOneWay",
        "occludesVision",
        "occludesLight",
        "blocksMovement",
        "blocksForcedMovement",
        "blocksFlying",
        "cover",
        "soundOcclusion",
        "wallHeight",
        "climbable",
        "solidity",
        "breakStamina",
        "rubbleKeyword",
        "rubbleTerrainId",
        "replacementWallId",
    }

    for _, field in ipairs(fields) do
        local value = wall[field]
        if value ~= nil then
            parts[#parts+1] = string.format("<b>%s</b>: %s", field, tostring(value))
        end
    end

    if #parts == 0 then return nil end
    return table.concat(parts, "\n")
end

local function WallItemFromAsset(id, wall, suffix)
    local baseLabel = (wall and wall.description) or id
    return {
        id = id,
        label = (suffix and (baseLabel .. " " .. suffix)) or baseLabel,
        kind = "wall",
        tint = wall and wall.tint,
        hueshift = wall and wall.hueshift,
        saturation = wall and wall.saturation,
        brightness = wall and wall.brightness,
        description = wall and wall.description,
        behavior = WallBehaviorText(wall),
        artist = wall and wall.artist,
    }
end

local function SearchWallItems(query, currentId)
    local q = string.lower(query or "")
    local items = {}
    local seen = {}
    local totalMatched = 0

    local function addCurrent()
        if currentId == nil or currentId == "" or seen[currentId] then return end
        local wall = assets.walls and assets.walls[currentId]
        items[#items+1] = WallItemFromAsset(currentId, wall, "(current)")
        seen[currentId] = true
    end

    addCurrent()

    if assets.walls ~= nil then
        for id,wall in pairs(assets.walls) do
            if not seen[id] then
                local label = string.lower(tostring(wall.description or id))
                if q == "" or string.find(label, q, 1, true) ~= nil then
                    totalMatched = totalMatched + 1
                    if #items < PICKER_LIMIT then
                        items[#items+1] = WallItemFromAsset(id, wall)
                    end
                    seen[id] = true
                end
            end
        end
    end

    return items, totalMatched
end

local function ValidateMapAssetChoices(choices)
    local counts = choices.counts or {}
    local wallModeAllowed = {wall = true, none = true}
    local assetModeAllowed = {asset = true, none = true}
    local windowModeAllowed = {asset = true, movement_wall = true, none = true}
    local function validMode(value, defaultValue, allowed)
        local mode = tostring(value or "")
        if allowed[mode] == true then
            return mode
        end
        return defaultValue
    end
    local function legacyMode(value, legacyValue, defaultValue, allowed)
        if value ~= nil and value ~= "" then
            return validMode(value, defaultValue, allowed)
        end
        return validMode(legacyValue, defaultValue, allowed)
    end
    local structuralWallMode = validMode(choices.structuralWallMode, "wall", wallModeAllowed)
    local objectWallMode = validMode(choices.objectWallMode, "wall", wallModeAllowed)
    local terrainWallMode = validMode(choices.terrainWallMode, "wall", wallModeAllowed)
    local invisibleWallMode = legacyMode(choices.invisibleWallMode, choices.movementWallMode, "wall", wallModeAllowed)
    local unrecognizedWallMode = validMode(choices.unrecognizedWallMode, cond(choices.includeUnrecognizedWalls == true, "wall", "none"), wallModeAllowed)
    local doorMode = validMode(choices.doorMode, "asset", assetModeAllowed)
    local windowMode = validMode(choices.windowMode, "asset", windowModeAllowed)
    local secretDoorMode = validMode(choices.secretDoorMode, "asset", assetModeAllowed)
    local lightMode = validMode(choices.lightMode, "asset", assetModeAllowed)
    local invisibleCount = counts.invisible or counts.movement or 0
    local terrainWallAssetId = choices.terrainWallAssetId or choices.objectWallAssetId
    local invisibleWallAssetId = choices.invisibleWallAssetId or choices.objectWallAssetId
    local transparentWindowWallAssetId = choices.transparentWindowWallAssetId or choices.objectWallAssetId
    if terrainWallAssetId == "" then terrainWallAssetId = choices.objectWallAssetId end
    if invisibleWallAssetId == "" then invisibleWallAssetId = choices.objectWallAssetId end
    if transparentWindowWallAssetId == "" then transparentWindowWallAssetId = choices.objectWallAssetId end

    local needsWallAsset =
        ((counts.structural or 0) > 0 and structuralWallMode == "wall")
        or ((counts.doors or 0) > 0 and doorMode == "asset")
        or ((counts.windows or 0) > 0 and windowMode == "asset")
        or ((counts.secretDoors or 0) > 0 and secretDoorMode == "asset")
    local needsObjectWallAsset =
        ((counts.object or 0) > 0 and objectWallMode == "wall")
    local needsTerrainWallAsset = ((counts.terrain or 0) > 0 and terrainWallMode == "wall")
    local needsInvisibleWallAsset = (invisibleCount > 0 and invisibleWallMode == "wall")
    local needsTransparentWindowWallAsset = ((counts.windows or 0) > 0 and windowMode == "movement_wall")

    if needsWallAsset and (assets.walls == nil or assets.walls[choices.wallAssetId] == nil) then
        return "The selected wall material is missing. Pick another wall material before continuing.", "wall"
    end
    if needsObjectWallAsset and (assets.walls == nil or assets.walls[choices.objectWallAssetId] == nil) then
        return "The selected object occluder material is missing. Pick another object occluder material before continuing.", "objectWall"
    end
    if needsTerrainWallAsset and (assets.walls == nil or assets.walls[terrainWallAssetId] == nil) then
        return "The selected terrain wall material is missing. Pick another terrain wall material before continuing.", "terrain"
    end
    if needsInvisibleWallAsset and (assets.walls == nil or assets.walls[invisibleWallAssetId] == nil) then
        return "The selected invisible wall material is missing. Pick another invisible wall material before continuing.", "invisible"
    end
    if needsTransparentWindowWallAsset and (assets.walls == nil or assets.walls[transparentWindowWallAssetId] == nil) then
        return "The selected transparent window wall material is missing. Pick another transparent window wall material before continuing.", "window"
    end
    if (counts.unrecognized or 0) > 0 and unrecognizedWallMode == "wall" and (assets.walls == nil or assets.walls[choices.unrecognizedWallAssetId] == nil) then
        return "The selected unrecognized wall material is missing. Pick another unrecognized wall material before continuing.", "unrecognizedWall"
    end
    if (counts.doors or 0) > 0 and doorMode == "asset" and (choices.doorObjectId == nil or assets:GetObjectNode(choices.doorObjectId) == nil) then
        return "The selected door object is missing. Pick another door before continuing.", "door"
    end
    if (counts.windows or 0) > 0 and windowMode == "asset" and (choices.windowObjectId == nil or assets:GetObjectNode(choices.windowObjectId) == nil) then
        return "The selected window object is missing. Pick another window before continuing.", "window"
    end
    if (counts.secretDoors or 0) > 0 and secretDoorMode == "asset" and (choices.secretDoorObjectId == nil or assets:GetObjectNode(choices.secretDoorObjectId) == nil) then
        return "The selected secret door object is missing. Pick another secret door before continuing.", "secretDoor"
    end
    if (counts.lights or 0) > 0 and lightMode == "asset" and (choices.lightObjectId == nil or assets:GetObjectNode(choices.lightObjectId) == nil) then
        return "The selected light object is missing. Pick another light before continuing.", "light"
    end
    if (counts.lights or 0) > 0 and lightMode == "asset" and not ObjectNodeHasComponent(choices.lightObjectId, "Light") then
        return "The selected light object does not have a Light component. Pick a light-emitting object before continuing.", "light"
    end

    return nil
end

local function BuildAssetTooltip(item)
    local children = {
        gui.Label{
            text = "<b>" .. (item.label or "(no name)") .. "</b>",
            fontSize = 18,
            color = "white",
            width = PICKER_UI.tooltipContentWidth,
            height = "auto",
            wrap = true,
        },
        gui.Panel{width = PICKER_UI.tooltipContentWidth, height = 6, interactable = false},
    }

    if item.kind == "wall" then
        children[#children+1] = gui.Panel{
            bgimageStreamed = item.id,
            bgcolor = item.tint,
            hueshift = item.hueshift,
            saturation = item.saturation and (1 + item.saturation) or nil,
            brightness = item.brightness and (1 + item.brightness) or nil,
            width = PICKER_UI.tooltipWallWidth,
            height = PICKER_UI.tooltipWallHeight,
            halign = "center",
            interactable = false,
        }
    elseif item.thumbnailId or item.image then
        children[#children+1] = gui.Panel{
            bgimage = item.thumbnailId or item.image,
            bgcolor = "white",
            hueshift = item.hue,
            saturation = item.saturation,
            brightness = item.brightness,
            width = PICKER_UI.tooltipObjectSize,
            height = PICKER_UI.tooltipObjectSize,
            halign = "center",
            interactable = false,
        }
    end

    local detail = item.behavior
    if (detail == nil or detail == "") and
            item.description and item.description ~= "" and
            item.description ~= item.label then
        detail = item.description
    end
    if detail ~= nil and detail ~= "" then
        children[#children+1] = gui.Panel{width = PICKER_UI.tooltipContentWidth, height = 6, interactable = false}
        children[#children+1] = gui.Label{
            text = detail,
            fontSize = 12,
            color = "white",
            width = PICKER_UI.tooltipContentWidth,
            height = "auto",
            wrap = true,
        }
    end

    if item.artist and item.artist ~= "" then
        children[#children+1] = gui.Panel{width = PICKER_UI.tooltipContentWidth, height = 4, interactable = false}
        children[#children+1] = gui.Label{
            classes = {"fgMuted"},
            text = "<i>Artist: " .. tostring(item.artist) .. "</i>",
            fontSize = 10,
            width = PICKER_UI.tooltipContentWidth,
            height = "auto",
        }
    end

    return gui.TooltipFrame(
        gui.Panel{
            interactable = false,
            width = PICKER_UI.tooltipWidth,
            height = "auto",
            pad = 12,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.GetStyles(),
            children = children,
        },
        {valign = "center", halign = "left"}
    )
end

local function BuildThumbnailTile(item, onClick, tileShape)
    tileShape = tileShape or "wide"

    local sizes = PICKER_UI.thumbnail[tileShape] or PICKER_UI.thumbnail.wide

    local imageChild
    if item.kind == "wall" then
        imageChild = gui.Panel{
            bgimageStreamed = item.id,
            bgcolor = item.tint,
            hueshift = item.hueshift,
            saturation = item.saturation and (1 + item.saturation) or nil,
            brightness = item.brightness and (1 + item.brightness) or nil,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
            events = {
                imageLoaded = function(element)
                    if tileShape == "square"
                            and element.bgimageWidth and element.bgimageHeight
                            and element.bgimageWidth > element.bgimageHeight * 1.5 then
                        element.selfStyle.imageRect = {
                            x1 = 0,
                            x2 = element.bgimageHeight / element.bgimageWidth,
                            y1 = 0,
                            y2 = 1,
                        }
                    end
                end,
            },
        }
    else
        imageChild = gui.Panel{
            bgimage = item.thumbnailId or item.image,
            bgcolor = "white",
            hueshift = item.hue,
            saturation = item.saturation,
            brightness = item.brightness,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
            events = {
                imageLoaded = function(element)
                    if element.bgsprite ~= nil and element.bgsprite.dimensions ~= nil then
                        local dx = element.bgsprite.dimensions.x
                        local dy = element.bgsprite.dimensions.y
                        local maxDim = math.max(dx, dy)
                        if maxDim > 0 then
                            element.selfStyle.width = tostring(dx / maxDim * 100) .. "%"
                            element.selfStyle.height = tostring(dy / maxDim * 100) .. "%"
                        end
                    end
                end,
            },
        }
    end

    local fullLabel = tostring(item.label or "")
    local shortLabel = ShortLabel(fullLabel, PICKER_UI.tileLabelLength)

    local thumb
    thumb = gui.Panel{
        classes = {"assetThumbnail"},
        bgimage = "panels/square.png",
        width = sizes.tileW,
        height = sizes.tileH,
        hmargin = 4,
        vmargin = 4,
        flow = "vertical",
        clip = true,
        data = {assetId = item.id},
        events = {
            hover = function(element)
                if element.tooltip == nil then
                    element.tooltip = BuildAssetTooltip(item)
                end
            end,
        },
        press = function(element)
            onClick(element.data.assetId)
        end,

        gui.Panel{
            width = sizes.imageW,
            height = sizes.imageH,
            halign = "center",
            valign = "top",
            interactable = false,
            imageChild,
        },

        gui.Label{
            text = shortLabel,
            width = "100%",
            height = "auto",
            maxHeight = 28,
            fontSize = 10,
            halign = "center",
            valign = "top",
            textAlignment = "center",
            wrap = true,
            interactable = false,
        },
    }
    return thumb
end

local function CurrentAssetItem(kind, id)
    if kind == "wall" then
        local wall = assets.walls and assets.walls[id]
        if wall ~= nil then
            return WallItemFromAsset(id, wall)
        end
    else
        local node = id and assets:GetObjectNode(id)
        if node ~= nil then
            return ObjectItemFromNode(id, node)
        end
    end

    return nil
end

local function BuildAssetPreviewTile(item, tileShape)
    tileShape = tileShape or "wide"

    local sizes = PICKER_UI.preview[tileShape] or PICKER_UI.preview.wide

    if item == nil then
        return gui.Panel{
            classes = {"bgAlt"},
            bgimage = "panels/square.png",
            width = sizes.outerW,
            height = sizes.outerH,
            hmargin = 6,
            valign = "center",
            flow = "none",
            interactable = false,
            gui.Label{
                classes = {"fgMuted"},
                text = "?",
                width = "100%",
                height = "100%",
                textAlignment = "center",
                valign = "center",
                fontSize = 16,
                interactable = false,
            },
        }
    end

    local imageChild
    if item.kind == "wall" then
        imageChild = gui.Panel{
            bgimageStreamed = item.id,
            bgcolor = item.tint,
            hueshift = item.hueshift,
            saturation = item.saturation and (1 + item.saturation) or nil,
            brightness = item.brightness and (1 + item.brightness) or nil,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
        }
    elseif item.thumbnailId or item.image then
        imageChild = gui.Panel{
            bgimage = item.thumbnailId or item.image,
            bgcolor = "white",
            hueshift = item.hue,
            saturation = item.saturation,
            brightness = item.brightness,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
            events = {
                imageLoaded = function(element)
                    if element.bgsprite ~= nil and element.bgsprite.dimensions ~= nil then
                        local dx = element.bgsprite.dimensions.x
                        local dy = element.bgsprite.dimensions.y
                        local maxDim = math.max(dx, dy)
                        if maxDim > 0 then
                            element.selfStyle.width = tostring(dx / maxDim * 100) .. "%"
                            element.selfStyle.height = tostring(dy / maxDim * 100) .. "%"
                        end
                    end
                end,
            },
        }
    else
        imageChild = gui.Label{
            classes = {"fgMuted"},
            text = "?",
            width = "100%",
            height = "100%",
            textAlignment = "center",
            valign = "center",
            fontSize = 16,
            interactable = false,
        }
    end

    return gui.Panel{
        classes = {"bgAlt"},
        bgimage = "panels/square.png",
        width = sizes.outerW,
        height = sizes.outerH,
        hmargin = 6,
        valign = "center",
        flow = "none",
        clip = true,
        interactable = false,
        events = {
            hover = function(element)
                if element.tooltip == nil then
                    element.tooltip = BuildAssetTooltip(item)
                end
            end,
        },
        gui.Panel{
            width = sizes.innerW,
            height = sizes.innerH,
            halign = "center",
            valign = "center",
            interactable = false,
            imageChild,
        },
    }
end

local function BuildSearchableThumbnailPicker(opts)
    local kind = opts.kind or "object"
    local query = opts.initialQuery or ""
    local currentSelection = opts.currentId
    local thumbnails = {}
    local resultPanel
    local infoLabel
    local rebuild

    local function fetch()
        if kind == "wall" then
            return SearchWallItems(query, currentSelection)
        else
            return SearchObjectItems(query, currentSelection)
        end
    end

    local function setSelection(newId, fireChange)
        currentSelection = newId
        local found = false
        for _,t in ipairs(thumbnails) do
            local match = t.data and t.data.assetId == newId
            t:SetClass("selected", match)
            if match then found = true end
        end
        if not found and rebuild ~= nil then
            rebuild()
        end
        if fireChange and opts.onChange ~= nil then
            opts.onChange(newId)
        end
    end

    rebuild = function()
        local items, totalMatched = fetch()
        local newChildren = {}
        thumbnails = {}
        for _,item in ipairs(items) do
            local thumb = BuildThumbnailTile(item, function(id)
                setSelection(id, true)
            end, opts.tileShape)
            if item.id == currentSelection then
                thumb:SetClass("selected", true)
            end
            newChildren[#newChildren+1] = thumb
            thumbnails[#thumbnails+1] = thumb
        end
        resultPanel.children = newChildren

        if infoLabel ~= nil then
            if totalMatched == 0 then
                infoLabel.text = "(no matches -- showing default only)"
            elseif totalMatched > #items then
                infoLabel.text = string.format(
                    "showing %d of %d -- type to narrow", #items, totalMatched)
            else
                infoLabel.text = string.format("%d match%s",
                    totalMatched, totalMatched == 1 and "" or "es")
            end
        end
    end

    local pickerStyles = ThemeEngine.MergeTokens({
        {
            selectors = {"assetThumbnail"},
            borderWidth = 2,
            borderColor = "@border",
            bgcolor = "@bg",
            cornerRadius = 4,
            pad = 4,
            borderBox = true,
        },
        {
            selectors = {"assetThumbnail", "hover"},
            borderColor = "@accent",
        },
        {
            selectors = {"assetThumbnail", "selected"},
            borderWidth = 3,
            borderColor = "@fg",
        },
    })

    resultPanel = gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = "100%",
        height = "auto",
        styles = pickerStyles,
    }

    infoLabel = gui.Label{
        classes = {"fgMuted"},
        text = "",
        width = "auto",
        height = "auto",
        fontSize = 11,
        hmargin = 8,
        valign = "center",
    }

    local searchInput = gui.Input{
        classes = {"form"},
        text = query,
        width = PICKER_UI.searchWidth,
        height = PICKER_UI.inputHeight,
        placeholderText = "Search...",
        change = function(element)
            query = element.text or ""
            rebuild()
        end,
    }

    rebuild()

    local panel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            vmargin = 4,
            valign = "center",
            searchInput,
            infoLabel,
        },

        resultPanel,
    }

    return panel, setSelection
end

mod.shared.ShowMapAssetPickerDialog = function(uvttData, callback)
    local wallId        = dmhub.GetSettingValue("mapimport:wall_asset_id")
    local objectWallId  = dmhub.GetSettingValue("mapimport:object_wall_asset_id")
    local terrainWallId = dmhub.GetSettingValue("mapimport:terrain_wall_asset_id")
    local invisibleWallId = dmhub.GetSettingValue("mapimport:invisible_wall_asset_id")
    local transparentWindowWallId = dmhub.GetSettingValue("mapimport:transparent_window_wall_asset_id")
    local unrecognizedWallId = dmhub.GetSettingValue("mapimport:unrecognized_wall_asset_id")
    local doorId        = dmhub.GetSettingValue("mapimport:door_object_id")
    local windowId      = dmhub.GetSettingValue("mapimport:window_object_id")
    local secretDoorId  = dmhub.GetSettingValue("mapimport:secret_door_object_id")
    local lightId       = dmhub.GetSettingValue("mapimport:light_object_id")
    local flipFoundryTerrain = dmhub.GetSettingValue("mapimport:flip_foundry_terrain_walls") == true
    local offsetX       = 0
    local offsetY       = 0

    local DEFAULT_WALL        = "-MGADhKw0vw30yXNF2-e"
    local DEFAULT_OBJECT_WALL = "eae7f3fe-d278-455c-853a-ac43f948c743"
    local DEFAULT_TERRAIN_WALL = "eae7f3fe-d278-455c-853a-ac43f948c743"
    local DEFAULT_INVISIBLE_WALL = "eae7f3fe-d278-455c-853a-ac43f948c743"
    local DEFAULT_TRANSPARENT_WINDOW_WALL = "eae7f3fe-d278-455c-853a-ac43f948c743"
    local DEFAULT_UNRECOGNIZED_WALL = "-MGADhKw0vw30yXNF2-e"
    local DEFAULT_DOOR        = "-MfWx0b2IlyApLQwasYg"
    local DEFAULT_WINDOW      = "-MDd3Knydcq2WsjStef2"
    local DEFAULT_SECRET_DOOR = "-MfWx0b2IlyApLQwasYg"
    local DEFAULT_LIGHT       = "2339211c-c35a-4e0a-a5fa-79d2e446bd3b"
    if unrecognizedWallId == nil or unrecognizedWallId == "" then
        unrecognizedWallId = wallId or DEFAULT_UNRECOGNIZED_WALL
    end
    if terrainWallId == nil or terrainWallId == "" then
        terrainWallId = objectWallId or DEFAULT_TERRAIN_WALL
    end
    if invisibleWallId == nil or invisibleWallId == "" then
        invisibleWallId = objectWallId or DEFAULT_INVISIBLE_WALL
    end
    if transparentWindowWallId == nil or transparentWindowWallId == "" then
        transparentWindowWallId = objectWallId or DEFAULT_TRANSPARENT_WINDOW_WALL
    end

    local counts = CountImportFeatures(uvttData)
    local floorCount = 1
    if type(uvttData) == "table" and uvttData[1] ~= nil then
        floorCount = #uvttData
    end

    local function ValidMode(value, defaultValue, allowed)
        local mode = tostring(value or defaultValue)
        if allowed[mode] == true then
            return mode
        end
        return defaultValue
    end

    local function LegacyMode(value, legacyValue, defaultValue, allowed)
        if value == nil or value == "" then
            value = legacyValue
        end
        return ValidMode(value, defaultValue, allowed)
    end

    local wallModeAllowed = {wall = true, none = true}
    local assetModeAllowed = {asset = true, none = true}
    local windowModeAllowed = {asset = true, movement_wall = true, none = true}
    local structuralWallMode = ValidMode(dmhub.GetSettingValue("mapimport:structural_wall_mode"), "wall", wallModeAllowed)
    local objectWallMode = ValidMode(dmhub.GetSettingValue("mapimport:object_wall_mode"), "wall", wallModeAllowed)
    local terrainWallMode = ValidMode(dmhub.GetSettingValue("mapimport:terrain_wall_mode"), "wall", wallModeAllowed)
    local invisibleWallMode = LegacyMode(dmhub.GetSettingValue("mapimport:invisible_wall_mode"), dmhub.GetSettingValue("mapimport:movement_wall_mode"), "wall", wallModeAllowed)
    local unrecognizedWallMode = ValidMode(dmhub.GetSettingValue("mapimport:unrecognized_wall_mode"), "none", wallModeAllowed)
    local doorMode = ValidMode(dmhub.GetSettingValue("mapimport:door_mode"), "asset", assetModeAllowed)
    local windowMode = ValidMode(dmhub.GetSettingValue("mapimport:window_mode"), "asset", windowModeAllowed)
    local secretDoorMode = ValidMode(dmhub.GetSettingValue("mapimport:secret_door_mode"), "asset", assetModeAllowed)
    local lightMode = ValidMode(dmhub.GetSettingValue("mapimport:light_mode"), "asset", assetModeAllowed)

    local refreshAllSummaries = nil
    local modeRefreshers = {}
    local bodyRefreshers = {}
    local allPickerPanels = {}
    local attachedPickerPanels = {}
    local function MakePicker(options)
        local picker, setter = BuildSearchableThumbnailPicker(options)
        if picker ~= nil then
            allPickerPanels[#allPickerPanels+1] = picker
        end
        return picker, setter
    end
    local function MarkPickerAttached(picker)
        if picker ~= nil then
            attachedPickerPanels[picker] = true
        end
    end

    local wallPicker,       setWall       = MakePicker{
        kind = "wall", tileShape = "wide", initialQuery = "", currentId = wallId,
        onChange = function(v)
            wallId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local objectWallPicker, setObjectWall = MakePicker{
        kind = "wall", tileShape = "wide", initialQuery = "one-direction", currentId = objectWallId,
        onChange = function(v)
            objectWallId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local terrainWallPicker, setTerrainWall = MakePicker{
        kind = "wall", tileShape = "wide", initialQuery = "one-direction", currentId = terrainWallId,
        onChange = function(v)
            terrainWallId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local invisibleWallPicker, setInvisibleWall = MakePicker{
        kind = "wall", tileShape = "wide", initialQuery = "see-thru", currentId = invisibleWallId,
        onChange = function(v)
            invisibleWallId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local transparentWindowWallPicker, setTransparentWindowWall = MakePicker{
        kind = "wall", tileShape = "wide", initialQuery = "see-thru", currentId = transparentWindowWallId,
        onChange = function(v)
            transparentWindowWallId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local unrecognizedWallPicker = nil
    local setUnrecognizedWall = nil
    if counts.unrecognized > 0 then
        unrecognizedWallPicker, setUnrecognizedWall = MakePicker{
            kind = "wall", tileShape = "wide", initialQuery = "", currentId = unrecognizedWallId,
            onChange = function(v)
                unrecognizedWallId = v
                if refreshAllSummaries ~= nil then refreshAllSummaries() end
            end,
        }
    end

    local doorPicker,       setDoor       = MakePicker{
        kind = "object", tileShape = "square", initialQuery = "door", currentId = doorId,
        onChange = function(v)
            doorId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local windowPicker,     setWindow     = MakePicker{
        kind = "object", tileShape = "square", initialQuery = "window", currentId = windowId,
        onChange = function(v)
            windowId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local secretDoorPicker, setSecretDoor = MakePicker{
        kind = "object", tileShape = "square", initialQuery = "secret", currentId = secretDoorId,
        onChange = function(v)
            secretDoorId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }
    local lightPicker,      setLight      = MakePicker{
        kind = "object", tileShape = "square", initialQuery = "light", currentId = lightId,
        onChange = function(v)
            lightId = v
            if refreshAllSummaries ~= nil then refreshAllSummaries() end
        end,
    }

    local sectionRefreshers = {}
    local sectionsById = {}
    local openSection = nil
    local importSummaryLabel = nil
    local ACTION_LABELS = {
        wall = "Line",
        none = "None",
        asset = "Asset",
        movement_wall = "Transparent Wall",
    }

    local function FormatNumber(value)
        local text = string.format("%.2f", tonumber(value) or 0)
        text = string.gsub(text, "0+$", "")
        text = string.gsub(text, "%.$", "")
        return cond(text == "-0", "0", text)
    end

    local function AdvancedSummaryText()
        local parts = {
            string.format("offset %s, %s", FormatNumber(offsetX), FormatNumber(offsetY)),
        }
        if flipFoundryTerrain then
            parts[#parts+1] = "terrain flipped"
        end
        return table.concat(parts, " | ")
    end

    local function CountLabel(count, singular, plural)
        return string.format("%d %s", count, count == 1 and singular or (plural or (singular .. "s")))
    end

    local function ImportSummaryText()
        local creating = {}
        local skipped = {}

        local function addLine(count, singular, plural, mode, createText)
            if count <= 0 then return end
            if mode == "none" then
                skipped[#skipped+1] = CountLabel(count, singular, plural)
            else
                creating[#creating+1] = string.format("%d %s", count, createText)
            end
        end

        addLine(counts.structural, "structural wall", "structural walls", structuralWallMode, "structural wall lines")
        addLine(counts.object, "object occluder", "object occluders", objectWallMode, "object occluder lines")
        addLine(counts.terrain, "terrain wall", "terrain walls", terrainWallMode, "terrain wall lines")
        addLine(counts.invisible, "invisible wall", "invisible walls", invisibleWallMode, "invisible wall lines")
        addLine(counts.unrecognized, "unrecognized wall", "unrecognized walls", unrecognizedWallMode, "unrecognized wall lines")

        if counts.doors > 0 then
            if doorMode == "asset" then
                creating[#creating+1] = string.format("%d door asset%s", counts.doors, counts.doors == 1 and "" or "s")
            else
                skipped[#skipped+1] = CountLabel(counts.doors, "door", "doors")
            end
        end
        if counts.windows > 0 then
            if windowMode == "asset" then
                creating[#creating+1] = string.format("%d window asset%s", counts.windows, counts.windows == 1 and "" or "s")
            elseif windowMode == "movement_wall" then
                creating[#creating+1] = string.format("%d transparent window wall%s", counts.windows, counts.windows == 1 and "" or "s")
            else
                skipped[#skipped+1] = CountLabel(counts.windows, "window", "windows")
            end
        end
        if counts.secretDoors > 0 then
            if secretDoorMode == "asset" then
                creating[#creating+1] = string.format("%d secret door asset%s", counts.secretDoors, counts.secretDoors == 1 and "" or "s")
            else
                skipped[#skipped+1] = CountLabel(counts.secretDoors, "secret door", "secret doors")
            end
        end
        if counts.lights > 0 then
            if lightMode == "asset" then
                creating[#creating+1] = string.format("%d light asset%s", counts.lights, counts.lights == 1 and "" or "s")
            else
                skipped[#skipped+1] = CountLabel(counts.lights, "light", "lights")
            end
        end

        local text = "Creating: " .. cond(#creating > 0, table.concat(creating, "; "), "map image only") .. "."
        if #skipped > 0 then
            text = text .. " Skipping: " .. table.concat(skipped, "; ") .. "."
        end
        return text
    end

    local function SetSectionExpanded(section, expanded)
        if section == nil then return end
        if expanded and openSection ~= nil and openSection ~= section then
            openSection.arrow:SetClass("expanded", false)
            openSection.bodyPanel:SetClass("collapsed", true)
        end

        section.arrow:SetClass("expanded", expanded)
        section.bodyPanel:SetClass("collapsed", not expanded)
        if expanded then
            openSection = section
        elseif openSection == section then
            openSection = nil
        end
    end

    local function BuildDisclosureRow(args)
        local bodyPanel = args.bodyPanel
        local summaryLabel = gui.Label{
            classes = {"fg"},
            text = "",
            width = PICKER_UI.summaryWidth,
            height = "auto",
            maxHeight = 22,
            fontSize = 12,
            valign = "center",
            textAlignment = "left",
            interactable = false,
        }
        local previewSlot = gui.Panel{
            width = "auto",
            height = "auto",
            valign = "center",
            interactable = false,
        }
        local arrow = gui.ExpandoArrow{
            interactable = false,
            hmargin = 6,
            valign = "center",
        }
        local section = {
            id = args.id,
            arrow = arrow,
            bodyPanel = bodyPanel,
        }

        local function refreshSummary()
            if args.summaryText ~= nil then
                summaryLabel.text = args.summaryText()
                summaryLabel:SetClass("fg", true)
                summaryLabel:SetClass("fgMuted", false)
                previewSlot.children = {}
                return
            end

            if args.summaryState ~= nil then
                local text, assetKind, assetId, tileShape = args.summaryState()
                summaryLabel.text = text or ""
                summaryLabel:SetClass("fg", true)
                summaryLabel:SetClass("fgMuted", false)
                if assetKind ~= nil and assetId ~= nil then
                    local item = CurrentAssetItem(assetKind, assetId)
                    previewSlot.children = {BuildAssetPreviewTile(item, tileShape)}
                else
                    previewSlot.children = {}
                end
                return
            end

            local item = CurrentAssetItem(args.assetKind, args.getId())
            if item ~= nil then
                summaryLabel.text = ShortLabel(item.label, PICKER_UI.summaryLength)
                summaryLabel:SetClass("fg", true)
                summaryLabel:SetClass("fgMuted", false)
            else
                summaryLabel.text = "(missing)"
                summaryLabel:SetClass("fg", false)
                summaryLabel:SetClass("fgMuted", true)
            end
            previewSlot.children = {BuildAssetPreviewTile(item, args.tileShape)}
        end

        section.refreshSummary = refreshSummary
        sectionRefreshers[#sectionRefreshers+1] = refreshSummary
        sectionsById[args.id] = section

        local row = gui.Panel{
            width = "100%",
            height = "auto",
            vmargin = 3,
            flow = "vertical",

            gui.Panel{
                classes = {"row", "headerRow"},
                width = "100%",
                height = PICKER_UI.headerHeight,
                flow = "horizontal",
                valign = "center",
                click = function()
                    SetSectionExpanded(section, not arrow:HasClass("expanded"))
                end,

                arrow,
                gui.Label{
                    text = "<b>" .. args.labelText .. "</b>",
                    width = PICKER_UI.headerLabelWidth,
                    height = "auto",
                    fontSize = 14,
                    valign = "center",
                    textAlignment = "left",
                    interactable = false,
                },
                summaryLabel,
                previewSlot,
            },

            bodyPanel,
        }

        refreshSummary()
        return row
    end

    local modeStyles = ThemeEngine.MergeTokens({
        {
            selectors = {"modeButton"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "@bg",
            cornerRadius = 4,
            fontSize = 12,
            height = 26,
        },
        {
            selectors = {"modeButton", "hover"},
            borderColor = "@accent",
        },
        {
            selectors = {"modeButton", "selected"},
            borderWidth = 2,
            borderColor = "@fg",
            bgcolor = "@accent",
        },
    })

    local function BuildModeControl(args)
        local buttons = {}

        local function refreshButtons()
            local mode = args.getMode()
            for _,button in ipairs(buttons) do
                button:SetClass("selected", button.data.value == mode)
            end
        end

        for _, option in ipairs(args.options) do
            local button = gui.Button{
                classes = {"modeButton"},
                text = option.label,
                width = option.width or 128,
                height = 26,
                data = {value = option.value},
                click = function(element)
                    args.setMode(element.data.value)
                    refreshButtons()
                    if refreshAllSummaries ~= nil then refreshAllSummaries() end
                end,
            }
            buttons[#buttons+1] = button
        end

        modeRefreshers[#modeRefreshers+1] = refreshButtons

        local panel = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            vmargin = 4,
            styles = modeStyles,
            children = buttons,
        }
        refreshButtons()
        return panel
    end

    local function BehaviorRow(args)
        if args.count <= 0 and args.alwaysShow ~= true then
            return nil
        end

        local modeControl = BuildModeControl{
            options = args.options,
            getMode = args.getMode,
            setMode = args.setMode,
        }

        local pickerContainers = {}
        local bodyChildren = {modeControl}

        local function addPicker(picker, visible)
            if picker == nil then
                return
            end

            local container = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                picker,
            }
            MarkPickerAttached(picker)
            pickerContainers[#pickerContainers+1] = {
                panel = container,
                visible = visible,
            }
            bodyChildren[#bodyChildren+1] = container
        end

        if args.pickers ~= nil then
            for _, pickerSpec in ipairs(args.pickers) do
                addPicker(pickerSpec.picker, pickerSpec.visible)
            end
        else
            addPicker(args.picker, args.pickerVisible)
        end

        local function refreshBody()
            local mode = args.getMode()
            for _, picker in ipairs(pickerContainers) do
                local visible = false
                if picker.visible ~= nil then
                    visible = picker.visible(mode)
                else
                    visible = mode == "asset" or mode == "wall"
                end
                picker.panel:SetClass("collapsed", not visible)
            end
        end
        bodyRefreshers[#bodyRefreshers+1] = refreshBody

        local hint = nil
        if args.hintText ~= nil then
            hint = gui.Label{
                classes = {"fgMuted"},
                text = "<i>" .. args.hintText .. "</i>",
                width = "100%",
                height = "auto",
                fontSize = 11,
                vmargin = 2,
                wrap = true,
            }
        end

        if hint ~= nil then
            table.insert(bodyChildren, 2, hint)
        end

        local bodyPanel = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            lmargin = 28,
            rmargin = 8,
            bmargin = 8,
            children = bodyChildren,
        }

        return BuildDisclosureRow{
            id = args.id,
            labelText = args.labelText,
            bodyPanel = bodyPanel,
            summaryState = function()
                refreshBody()
                local mode = args.getMode()
                local action = ACTION_LABELS[mode] or mode
                local text = CountLabel(args.count, args.singular, args.plural) .. " | " .. action
                if args.assetForMode ~= nil then
                    local asset = args.assetForMode(mode)
                    if asset ~= nil then
                        return text, asset.kind, asset.id, asset.tileShape
                    end
                end
                return text
            end,
        }
    end

    local function MaterialRow(args)
        if args.show ~= true then
            return nil
        end
        MarkPickerAttached(args.picker)

        local hint = nil
        if args.hintText ~= nil then
            hint = gui.Label{
                classes = {"fgMuted"},
                text = "<i>" .. args.hintText .. "</i>",
                width = "100%",
                height = "auto",
                fontSize = 11,
                vmargin = 2,
                wrap = true,
            }
        end

        local bodyPanel = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            lmargin = 28,
            rmargin = 8,
            bmargin = 8,
            hint,
            args.picker,
        }

        return BuildDisclosureRow{
            id = args.id,
            labelText = args.labelText,
            bodyPanel = bodyPanel,
            summaryState = function()
                return args.summaryText, args.assetKind, args.getId(), args.tileShape
            end,
        }
    end

    local function PickerRow(args)
        MarkPickerAttached(args.picker)

        local hint = nil
        if args.hintText ~= nil then
            hint = gui.Label{
                classes = {"fgMuted"},
                text = "<i>" .. args.hintText .. "</i>",
                width = "100%",
                height = "auto",
                fontSize = 11,
                vmargin = 2,
                wrap = true,
            }
        end

        local bodyPanel = gui.Panel{
            classes = {"collapsed"},
            width = "100%",
            height = "auto",
            flow = "vertical",
            lmargin = 28,
            rmargin = 8,
            bmargin = 8,
            hint,
            args.picker,
        }

        return BuildDisclosureRow{
            id = args.id,
            labelText = args.labelText,
            bodyPanel = bodyPanel,
            assetKind = args.assetKind,
            tileShape = args.tileShape,
            getId = args.getId,
        }
    end

    local floorCountRow = nil
    if floorCount > 1 then
        floorCountRow = gui.Label{
            classes = {"success"},
            text = string.format("%d floors will be imported with these behavior choices.", floorCount),
            width = "100%",
            height = "auto",
            vmargin = 4,
            fontSize = 13,
            wrap = true,
        }
    end

    local summaryRow = gui.Label{
        classes = {"success"},
        text = ImportSummaryText(),
        width = "100%",
        height = "auto",
        vmargin = 4,
        fontSize = 13,
        wrap = true,
        create = function(element)
            importSummaryLabel = element
        end,
    }

    local flipTerrainCheck = nil
    local flipTerrainRow = nil
    if counts.terrain > 0 or counts.invisible > 0 then
        flipTerrainCheck = gui.Check{
            text = "Flip Foundry terrain/invisible wall direction",
            value = flipFoundryTerrain,
            change = function(element)
                flipFoundryTerrain = element.value
                if refreshAllSummaries ~= nil then refreshAllSummaries() end
            end,
        }
        flipTerrainRow = gui.Panel{
            width = "100%",
            height = "auto",
            vmargin = 4,
            flow = "vertical",
            flipTerrainCheck,
            gui.Label{
                classes = {"fgMuted"},
                text = "Use when one-direction Foundry terrain or invisible walls face the wrong side. Closed loops are normalized automatically.",
                width = "100%",
                height = "auto",
                fontSize = 11,
                wrap = true,
            },
        }
    end

    local offsetXInput = nil
    local offsetYInput = nil

    local advancedPanel = gui.Panel{
        classes = {"collapsed"},
        width = "100%",
        height = "auto",
        flow = "vertical",
        lmargin = 28,
        rmargin = 8,
        bmargin = 8,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vmargin = 4,
            gui.Label{
                classes = {"form"},
                text = "<b>Alignment offset (tiles)</b>",
                width = "auto",
                height = "auto",
                fontSize = 14,
            },
            gui.Label{
                classes = {"fgMuted"},
                text = "<i>Shifts imported walls, doors, windows, and lights. Use only when they land off the image.</i>",
                width = "100%",
                height = "auto",
                fontSize = 11,
                wrap = true,
                vmargin = 2,
            },
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                valign = "center",
                vmargin = 4,
                gui.Label{ text = "X:", width = "auto", height = "auto", valign = "center", hmargin = 4 },
                gui.Input{
                    classes = {"form"},
                    text = "0",
                    width = PICKER_UI.inputWidth,
                    height = PICKER_UI.inputHeight,
                    create = function(element)
                        offsetXInput = element
                    end,
                    change = function(element)
                        offsetX = tonumber(element.text) or 0
                        if refreshAllSummaries ~= nil then refreshAllSummaries() end
                    end,
                },
                gui.Label{ text = "Y:", width = "auto", height = "auto", valign = "center", hmargin = 4 },
                gui.Input{
                    classes = {"form"},
                    text = "0",
                    width = PICKER_UI.inputWidth,
                    height = PICKER_UI.inputHeight,
                    create = function(element)
                        offsetYInput = element
                    end,
                    change = function(element)
                        offsetY = tonumber(element.text) or 0
                        if refreshAllSummaries ~= nil then refreshAllSummaries() end
                    end,
                },
            },
        },

        flipTerrainRow,
    }

    local wallMaterialRelevant = counts.structural > 0 or counts.doors > 0 or counts.windows > 0 or counts.secretDoors > 0
    local objectMaterialRelevant = counts.object > 0
    local wallRow = nil
    if counts.structural > 0 then
        wallRow = BehaviorRow{
            id = "wall",
            labelText = "Structural walls",
            count = counts.structural,
            singular = "structural wall",
            plural = "structural walls",
            options = {{value = "wall", label = "Line"}, {value = "none", label = "None"}},
            getMode = function() return structuralWallMode end,
            setMode = function(v) structuralWallMode = v end,
            picker = wallPicker,
            hintText = "Room boundaries and normal line-of-sight walls.",
            assetForMode = function(mode)
                if mode == "wall" then return {kind = "wall", id = wallId, tileShape = "wide"} end
                return nil
            end,
        }
    elseif wallMaterialRelevant then
        wallRow = MaterialRow{
            id = "wall",
            labelText = "Wall material",
            show = true,
            picker = wallPicker,
            hintText = "Used by UVTT portal wall lines when the source format supplies them.",
            summaryText = "Portal line material",
            assetKind = "wall",
            tileShape = "wide",
            getId = function() return wallId end,
        }
    end

    local objectWallRow = nil
    if counts.object > 0 then
        objectWallRow = BehaviorRow{
            id = "objectWall",
            labelText = "Object occluders",
            count = counts.object,
            singular = "object occluder",
            plural = "object occluders",
            options = {{value = "wall", label = "Line"}, {value = "none", label = "None"}},
            getMode = function() return objectWallMode end,
            setMode = function(v) objectWallMode = v end,
            picker = objectWallPicker,
            hintText = "Closed UVTT object occluders.",
            assetForMode = function(mode)
                if mode == "wall" then return {kind = "wall", id = objectWallId, tileShape = "wide"} end
                return nil
            end,
        }
    elseif objectMaterialRelevant then
        objectWallRow = MaterialRow{
            id = "objectWall",
            labelText = "Object occluder material",
            show = true,
            picker = objectWallPicker,
            hintText = "Used for closed UVTT object occluders.",
            summaryText = "Object occluder material",
            assetKind = "wall",
            tileShape = "wide",
            getId = function() return objectWallId end,
        }
    end

    local terrainRow = BehaviorRow{
        id = "terrain",
        labelText = "Terrain walls",
        count = counts.terrain,
        singular = "terrain wall",
        plural = "terrain walls",
        options = {{value = "wall", label = "Line"}, {value = "none", label = "None"}},
        getMode = function() return terrainWallMode end,
        setMode = function(v) terrainWallMode = v end,
        picker = terrainWallPicker,
        hintText = "Foundry partial-sight, movement-blocking walls.",
        assetForMode = function(mode)
            if mode == "wall" then return {kind = "wall", id = terrainWallId, tileShape = "wide"} end
            return nil
        end,
    }
    local invisibleRow = BehaviorRow{
        id = "invisible",
        labelText = "Invisible walls",
        count = counts.invisible,
        singular = "invisible wall",
        plural = "invisible walls",
        options = {{value = "wall", label = "Line"}, {value = "none", label = "None"}},
        getMode = function() return invisibleWallMode end,
        setMode = function(v) invisibleWallMode = v end,
        picker = invisibleWallPicker,
        hintText = "Foundry walls that block movement but not vision.",
        assetForMode = function(mode)
            if mode == "wall" then return {kind = "wall", id = invisibleWallId, tileShape = "wide"} end
            return nil
        end,
    }
    local unrecognizedWallRow = nil
    if unrecognizedWallPicker ~= nil then
        unrecognizedWallRow = BehaviorRow{
            id = "unrecognizedWall",
            labelText = "Unrecognized walls",
            count = counts.unrecognized,
            singular = "unrecognized wall",
            plural = "unrecognized walls",
            options = {{value = "wall", label = "Line"}, {value = "none", label = "None"}},
            getMode = function() return unrecognizedWallMode end,
            setMode = function(v) unrecognizedWallMode = v end,
            picker = unrecognizedWallPicker,
            hintText = "Foundry wall modes that cannot be mapped directly. Leave as None unless you want them as plain wall lines.",
            assetForMode = function(mode)
                if mode == "wall" then return {kind = "wall", id = unrecognizedWallId, tileShape = "wide"} end
                return nil
            end,
        }
    end
    local doorRow = BehaviorRow{
        id = "door",
        labelText = "Doors",
        count = counts.doors,
        singular = "door",
        plural = "doors",
        options = {{value = "asset", label = "Asset"}, {value = "none", label = "None"}},
        getMode = function() return doorMode end,
        setMode = function(v) doorMode = v end,
        picker = doorPicker,
        assetForMode = function(mode)
            if mode == "asset" then return {kind = "object", id = doorId, tileShape = "square"} end
            return nil
        end,
    }
    local windowRow = BehaviorRow{
        id = "window",
        labelText = "Windows",
        count = counts.windows,
        singular = "window",
        plural = "windows",
        options = {
            {value = "asset", label = "Asset"},
            {value = "movement_wall", label = "Transparent Wall", width = 164},
            {value = "none", label = "None"},
        },
        getMode = function() return windowMode end,
        setMode = function(v) windowMode = v end,
        pickers = {
            {picker = windowPicker, visible = function(mode) return mode == "asset" end},
            {picker = transparentWindowWallPicker, visible = function(mode) return mode == "movement_wall" end},
        },
        hintText = "Transparent Wall creates a movement-blocking, vision-transparent segment.",
        assetForMode = function(mode)
            if mode == "asset" then return {kind = "object", id = windowId, tileShape = "square"} end
            if mode == "movement_wall" then return {kind = "wall", id = transparentWindowWallId, tileShape = "wide"} end
            return nil
        end,
    }
    local secretDoorRow = BehaviorRow{
        id = "secretDoor",
        labelText = "Secret doors",
        count = counts.secretDoors,
        alwaysShow = true,
        singular = "secret door",
        plural = "secret doors",
        options = {{value = "asset", label = "Asset"}, {value = "none", label = "None"}},
        getMode = function() return secretDoorMode end,
        setMode = function(v) secretDoorMode = v end,
        picker = secretDoorPicker,
        assetForMode = function(mode)
            if mode == "asset" then return {kind = "object", id = secretDoorId, tileShape = "square"} end
            return nil
        end,
    }
    local lightRow = BehaviorRow{
        id = "light",
        labelText = "Lights",
        count = counts.lights,
        singular = "light",
        plural = "lights",
        options = {{value = "asset", label = "Asset"}, {value = "none", label = "None"}},
        getMode = function() return lightMode end,
        setMode = function(v) lightMode = v end,
        picker = lightPicker,
        assetForMode = function(mode)
            if mode == "asset" then return {kind = "object", id = lightId, tileShape = "square"} end
            return nil
        end,
    }

    local advancedRow = BuildDisclosureRow{
        id = "advanced",
        labelText = "Advanced Options",
        bodyPanel = advancedPanel,
        summaryText = AdvancedSummaryText,
    }

    refreshAllSummaries = function()
        if importSummaryLabel ~= nil then
            importSummaryLabel.text = ImportSummaryText()
        end
        for _, refresh in ipairs(modeRefreshers) do
            refresh()
        end
        for _, refresh in ipairs(bodyRefreshers) do
            refresh()
        end
        for _, refresh in ipairs(sectionRefreshers) do
            refresh()
        end
    end
    refreshAllSummaries()

    local pickerParkingChildren = {}
    for _, picker in ipairs(allPickerPanels) do
        if attachedPickerPanels[picker] ~= true then
            pickerParkingChildren[#pickerParkingChildren+1] = picker
        end
    end
    local pickerParkingPanel = nil
    if #pickerParkingChildren > 0 then
        pickerParkingPanel = gui.Panel{
            classes = {"collapsed"},
            width = 0,
            height = 0,
            children = pickerParkingChildren,
        }
    end

    local dialogPanel
    dialogPanel = gui.Panel{
        id = "MapAssetPickerDialog",
        classes = {"framedPanel"},
        width = PICKER_UI.dialogWidth,
        height = PICKER_UI.dialogHeight,
        pad = 12,
        borderBox = true,
        flow = "vertical",
        vscroll = true,
        styles = ThemeEngine.GetStyles(),

        gui.Label{
            classes = {"dialogTitle"},
            text = "UVTT Import: Behavior & Assets",
        },

        gui.Label{
            text = "Choose what UVTT import should create. Your choices are remembered.",
            width = "100%",
            height = "auto",
            fontSize = 12,
            wrap = true,
            vmargin = 4,
        },

        floorCountRow,
        summaryRow,

        wallRow,
        objectWallRow,
        terrainRow,
        invisibleRow,
        unrecognizedWallRow,
        doorRow,
        windowRow,
        secretDoorRow,
        lightRow,
        advancedRow,
        pickerParkingPanel,

        gui.Panel{
            width = "100%",
            height = 48,
            valign = "bottom",
            halign = "center",
            flow = "horizontal",
            vmargin = 8,

            gui.Button{
                classes = {"sizeL"},
                text = "Reset to defaults",
                halign = "left",
                hmargin = 4,
                click = function()
                    setWall(DEFAULT_WALL, true)
                    setObjectWall(DEFAULT_OBJECT_WALL, true)
                    setTerrainWall(DEFAULT_TERRAIN_WALL, true)
                    setInvisibleWall(DEFAULT_INVISIBLE_WALL, true)
                    setTransparentWindowWall(DEFAULT_TRANSPARENT_WINDOW_WALL, true)
                    if setUnrecognizedWall ~= nil then
                        setUnrecognizedWall(DEFAULT_UNRECOGNIZED_WALL, true)
                    end
                    setDoor(DEFAULT_DOOR, true)
                    setWindow(DEFAULT_WINDOW, true)
                    setSecretDoor(DEFAULT_SECRET_DOOR, true)
                    setLight(DEFAULT_LIGHT, true)
                    structuralWallMode = "wall"
                    objectWallMode = "wall"
                    terrainWallMode = "wall"
                    invisibleWallMode = "wall"
                    unrecognizedWallMode = "none"
                    doorMode = "asset"
                    windowMode = "asset"
                    secretDoorMode = "asset"
                    lightMode = "asset"
                    flipFoundryTerrain = false
                    offsetX = 0
                    offsetY = 0
                    if flipTerrainCheck ~= nil then
                        flipTerrainCheck.value = false
                    end
                    if offsetXInput ~= nil then
                        offsetXInput.text = "0"
                    end
                    if offsetYInput ~= nil then
                        offsetYInput.text = "0"
                    end
                    refreshAllSummaries()
                end,
            },
            gui.Button{
                classes = {"sizeL"},
                text = "Continue",
                halign = "right",
                hmargin = 4,
                click = function()
                    local choices = {
                        counts                    = counts,
                        wallAssetId              = wallId,
                        objectWallAssetId        = objectWallId,
                        terrainWallAssetId       = terrainWallId,
                        invisibleWallAssetId     = invisibleWallId,
                        transparentWindowWallAssetId = transparentWindowWallId,
                        unrecognizedWallAssetId  = unrecognizedWallId,
                        doorObjectId             = doorId,
                        windowObjectId           = windowId,
                        secretDoorObjectId       = secretDoorId,
                        lightObjectId            = lightId,
                        structuralWallMode       = structuralWallMode,
                        objectWallMode           = objectWallMode,
                        terrainWallMode          = terrainWallMode,
                        invisibleWallMode        = invisibleWallMode,
                        unrecognizedWallMode     = unrecognizedWallMode,
                        includeUnrecognizedWalls = unrecognizedWallMode == "wall",
                        doorMode                 = doorMode,
                        windowMode               = windowMode,
                        secretDoorMode           = secretDoorMode,
                        lightMode                = lightMode,
                        flipFoundryTerrainWalls  = flipFoundryTerrain,
                        alignmentOffsetX         = offsetX,
                        alignmentOffsetY         = offsetY,
                    }
                    local errorMessage, errorSection = ValidateMapAssetChoices(choices)
                    if errorMessage ~= nil then
                        SetSectionExpanded(sectionsById[errorSection], true)
                        refreshAllSummaries()
                        gui.ModalMessage{
                            title = "UVTT Import",
                            message = errorMessage,
                        }
                        return
                    end

                    dmhub.SetSettingValue("mapimport:wall_asset_id", wallId)
                    dmhub.SetSettingValue("mapimport:object_wall_asset_id", objectWallId)
                    dmhub.SetSettingValue("mapimport:terrain_wall_asset_id", terrainWallId)
                    dmhub.SetSettingValue("mapimport:invisible_wall_asset_id", invisibleWallId)
                    dmhub.SetSettingValue("mapimport:transparent_window_wall_asset_id", transparentWindowWallId)
                    dmhub.SetSettingValue("mapimport:unrecognized_wall_asset_id", unrecognizedWallId)
                    dmhub.SetSettingValue("mapimport:door_object_id", doorId)
                    dmhub.SetSettingValue("mapimport:window_object_id", windowId)
                    dmhub.SetSettingValue("mapimport:secret_door_object_id", secretDoorId)
                    dmhub.SetSettingValue("mapimport:light_object_id", lightId)
                    dmhub.SetSettingValue("mapimport:structural_wall_mode", structuralWallMode)
                    dmhub.SetSettingValue("mapimport:object_wall_mode", objectWallMode)
                    dmhub.SetSettingValue("mapimport:terrain_wall_mode", terrainWallMode)
                    dmhub.SetSettingValue("mapimport:invisible_wall_mode", invisibleWallMode)
                    dmhub.SetSettingValue("mapimport:unrecognized_wall_mode", unrecognizedWallMode)
                    dmhub.SetSettingValue("mapimport:door_mode", doorMode)
                    dmhub.SetSettingValue("mapimport:window_mode", windowMode)
                    dmhub.SetSettingValue("mapimport:secret_door_mode", secretDoorMode)
                    dmhub.SetSettingValue("mapimport:light_mode", lightMode)
                    dmhub.SetSettingValue("mapimport:flip_foundry_terrain_walls", flipFoundryTerrain)
                    gui.CloseModal()
                    callback(choices)
                end,
            },
            gui.Button{
                classes = {"sizeL"},
                text = "Cancel",
                halign = "right",
                hmargin = 4,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function()
                    gui.CloseModal()
                    callback(nil)
                end,
            },
        },
    }

    gui.ShowModal(dialogPanel)
end

local UVTT_EXTENSIONS = {".dd2vtt", ".uvtt", ".json"}

local function PathHasExtension(path, extensions)
    local lower = string.lower(tostring(path or ""))
    for _, ext in ipairs(extensions) do
        if string.ends_with(lower, ext) then
            return true
        end
    end

    return false
end

local function IsUVTTPath(path)
    return PathHasExtension(path, UVTT_EXTENSIONS)
end

local function ImportMapWizard(options)

    local imagesOnly = cond(options.imagesOnly, true, false)
    local allowUVTT = not imagesOnly

	local contentPanel

	contentPanel = gui.Panel{
		width = "95%",
		height = "94%",
		halign = "center",
		valign = "bottom",
		flow = "vertical",

		processFiles = function(element, paths)
			if paths ~= nil and #paths > 0 then
                if #paths > 12 then
                    gui.ModalMessage{
                        title = "Error Importing",
                        message = "Cannot import more than 12 layers.",
                    }
                    return
                end

                if allowUVTT and IsUVTTPath(paths[1]) then
                    for _,path in ipairs(paths) do
                        if not IsUVTTPath(path) then
                            gui.ModalMessage{
                                title = "Error Importing",
                                message = "Cannot import layers of mixed file types.",
                            }
                            return
                        end
                    end
                    assets:ImportUniversalVTT(paths, function(info)
                        mod.shared.ShowMapAssetPickerDialog(info.uvttData, function(choices)
                            if choices == nil then
                                return
                            end
                            info.assetChoices = choices
                            if options.finish ~= nil then
                                options.finish(info)
                                gui.CloseModal()
                            end
                        end)
                    end,
                    function(error)
                        gui.ModalMessage{
                            title = "Error Importing",
                            message = error,
                        }
                    end)
                else

                    for _,path in ipairs(paths) do
                        if IsUVTTPath(path) then
                            gui.ModalMessage{
                                title = "Error Importing",
                                message = "Cannot import layers of mixed file types.",
                            }
                            return
                        end
                    end

                    contentPanel.children = {mod.shared.ImportMapDialog(paths, options)}
                end
			end
		end,

		gui.Panel{
			classes = "dropArea",
			bgimage = "panels/square.png",

			dragAndDropExtensions = cond(allowUVTT,
              {".png", ".jpg", ".jpeg", ".mp4", ".webm", ".webp", ".dd2vtt", ".uvtt", ".json"},
              {".png", ".jpg", ".jpeg", ".mp4", ".webm", ".webp"}),

			dropfiles = function(element, paths)
				contentPanel:FireEvent("processFiles", paths)
			end,

			styles = ThemeEngine.MergeTokens({
				{
					width = "80%",
					height = "60%",
					valign = "center",
					selectors = {"dropArea"},
					bgcolor = "@bgAlt",
					borderColor = "@border",
					borderWidth = 6,
					cornerRadius = 16,
				},
				{
					selectors = {"dropArea","hover"},
					bgcolor = "@accent",
				}

			}),

			gui.Label{
				fontSize = 24,
				width = "auto",
				height = "auto",
				halign = "center",
				valign = "center",
				text = cond(allowUVTT, "Drag & Drop image, video, or vtt files here.\nMultiple files will create a multi-floor map.",
                                       "Drag & Drop image or video file here."),
			},
		},

		gui.Label{
			valign = "center",
			halign = "center",
			fontSize = 16,
			width = "auto",
			height = "auto",
			text = "-or-",
		},

		gui.Button{
			classes = {"sizeL"},
			text = "Choose Files",
			click = function(element)

				dmhub.OpenFileDialog{
					id = "ObjectImagePath",
					extensions = cond(allowUVTT, {"jpeg", "jpg", "png", "mp4", "webm", "webp", "dd2vtt", "uvtt", "json"}, {"jpeg", "jpg", "png", "mp4", "webm", "webp"}),
					multiFiles = true,
					prompt = cond(allowUVTT, "Choose image, video, or vtt file to use as map.", "Choose image or video file to use as a map."),
					openFiles = function(paths)
						contentPanel:FireEvent("processFiles", paths)

					end,
				}

			end,
		}

	}

	local dialogPanel
	dialogPanel = gui.Panel{
		id = "ImportMapDialog",
		classes = {"framedPanel"},
		width = 1400,
		height = 940,
		pad = 8,
		flow = "vertical",
		styles = ThemeEngine.GetStyles(),

		destroy = function(element)
			if g_modalDialog == element then
				g_modalDialog = nil
			end
		end,

			output = function(element, info)
				element:FireEventTree("refresh")
			end,

		gui.Label{
			classes = {"dialogTitle"},
			text = "Import Map from Image",
		},

		contentPanel,

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

	gui.ShowModal(dialogPanel, options)
	g_modalDialog = dialogPanel

    --gets paths at input, ready to go.
    if options.paths then
        contentPanel:FireEvent("processFiles", options.paths)
    end
end

mod.shared.ImportMap = function(options)
	ImportMapWizard(options)
end
