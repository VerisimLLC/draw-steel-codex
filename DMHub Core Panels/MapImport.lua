local mod = dmhub.GetModLoading()

-- Upper bound on per-axis tile count the import dialog will accept.
-- MapGridController.BuildMesh (C# engine) iterates O(width * height^2) on its
-- point-cull path, so a pathological manifest (one imported map in the wild
-- was 48358 x 19199) pegs a CPU core for hours before the map finishes
-- loading. MapGridController has its own 4M-cell bailout as a last resort;
-- this is the user-facing cap so the dialog refuses to ever produce one.
local MAX_MAP_TILES_PER_AXIS = 2000

local g_modalDialog = nil

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

----------------------------------------------------------------------
--MapGridDetection: finding the grid drawn on a map image, shared by the
--table's Add Image dialog (TableDropDialog.lua) and the import wizard below,
--so both suggest the same grid. The engine (assets:DetectImageGrid) does the
--work on a worker thread and runs each file once, so the wizard opening after
--the drop dialog gets the drop dialog's answer at once.

--- @class ImageGridDetection
--- @field found boolean
--- @field type string 'square', 'rectangular', 'hexpointy', 'hexflat' or 'none'
--- @field tileType string the import tile type: 'squares', 'pointtop' or 'flattop'
--- @field cellWidth number a cell (or a hex's bounding box) in pixels
--- @field cellHeight number
--- @field periodX number the grid's repeat along x and y, in pixels
--- @field periodY number
--- @field originX number a line crossing or hex centre, pixels from the top-left, y down
--- @field originY number
--- @field angle number the grid's rotation in degrees (0 if aligned)
--- @field confidence number 0..1
--- @field imageWidth number
--- @field imageHeight number
--- @field decodeMs number
--- @field detectMs number
--- @field message string

--- What a map image's grid should be imported as: the 140 px "perfect fit", or the
--- grid the detector found.
--- @class MapGridChoice
--- @field source string 'fit' or 'detected'
--- @field tileType string 'squares', 'flattop' or 'pointtop'
--- @field hex boolean
--- @field tilesW number tiles (or hexes) across the image, rounded
--- @field tilesH number
--- @field cellW number pixels
--- @field cellH number
--- @field confirmed boolean a fit whose drawn grid the detector found too
--- @field overrodeFit boolean a detected grid that won over a 140 px fit
--- @field detection nil|ImageGridDetection

--- @class MapGridDetection
MapGridDetection = {}

--Map art is most often made at this many pixels per square: an image a whole
--number of them across and down is a "perfect fit".
MapGridDetection.FIT_PIXELS = 140

--The detector must be at least this confident to override a perfect fit.
--Measured on gridalign's test maps, the drawn 70 px grids of 140-fit maps
--score 0.99-1.00 and every false positive 0.36 or less.
MapGridDetection.OVERRIDE_CONFIDENCE = 0.90

--Same limits as the map import's per-axis tile cap and the hex tile shape
--the import accepts (SheetMapImport.HexTileShapeValid).
local MAX_DETECTED_TILES = MAX_MAP_TILES_PER_AXIS
local MIN_HEX_SHAPE = 0.5
local MAX_HEX_SHAPE = 2

local IMAGE_EXTENSIONS = {png = true, jpg = true, jpeg = true, webp = true, bmp = true, tga = true, gif = true}

--path -> ImageGridDetection, or false if it couldn't be read; and the
--callbacks waiting for a path still being detected.
local g_gridResults = {}
local g_gridWaiting = {}

--- True for a file the detector can read (not a video or a VTT file).
--- @param path string
--- @return boolean
function MapGridDetection.CanDetect(path)
    local ext = string.match(string.lower(path or ""), "%.(%w+)$")
    return ext ~= nil and IMAGE_EXTENSIONS[ext] == true
end

--- The detection of a file, if it has finished: the result, false if the
--- file couldn't be read, or nil if not asked for or still running.
--- @param path string
--- @return nil|false|ImageGridDetection
function MapGridDetection.Result(path)
    return g_gridResults[path]
end

--- Starts detecting the grid on a local image file (once per file), and calls
--- callback(result) when it is done: at once if it already is. result is
--- false if the file couldn't be read.
--- @param path string
--- @param callback nil|fun(result: false|ImageGridDetection)
function MapGridDetection.Request(path, callback)
    if not MapGridDetection.CanDetect(path) then
        return
    end
    local done = g_gridResults[path]
    if done ~= nil then
        if callback ~= nil then
            callback(done)
        end
        return
    end
    local waiting = g_gridWaiting[path]
    if waiting ~= nil then
        waiting[#waiting+1] = callback
        return
    end
    waiting = {callback}
    g_gridWaiting[path] = waiting
    local function Finish(result)
        if mod.unloaded then
            return
        end
        g_gridResults[path] = result
        g_gridWaiting[path] = nil
        for _, fn in ipairs(waiting) do
            fn(result)
        end
    end
    assets:DetectImageGrid{
        path = path,
        done = function(result)
            Finish(result)
        end,
        error = function(message)
            printf("GRIDDETECT:: %s: %s", path, tostring(message))
            Finish(false)
        end,
    }
end

--The size in squares an image of w x h pixels fits exactly at FIT_PIXELS,
--with at least minSquares on its short side, or nil.
local function PerfectFit(w, h, minSquares)
    if w == nil or h == nil or w <= 0 or h <= 0 then
        return nil, nil
    end
    local pps = MapGridDetection.FIT_PIXELS
    local tw = w / pps
    local th = h / pps
    if math.abs(tw - math.floor(tw + 0.5)) > 0.01 or math.abs(th - math.floor(th + 0.5)) > 0.01 then
        return nil, nil
    end
    tw = math.floor(tw + 0.5)
    th = math.floor(th + 0.5)
    if math.min(tw, th) < (minSquares or 1) or math.max(tw, th) > MAX_MAP_TILES_PER_AXIS then
        return nil, nil
    end
    return tw, th
end

--A detected grid the import can use: found, not rotated (a map's grid is
--always aligned with its image), and a tile count and hex shape the import accepts.
--- @param d nil|false|ImageGridDetection
--- @return boolean
local function Usable(d)
    if not d or not d.found or d.type == "none" or d.angle ~= 0 then
        return false
    end
    if d.periodX <= 0 or d.periodY <= 0 then
        return false
    end
    local hex = d.tileType ~= "squares"
    local across, down
    if not hex then
        across, down = d.imageWidth / d.cellWidth, d.imageHeight / d.cellHeight
    elseif d.tileType == "flattop" then
        across, down = d.imageWidth / d.periodX, d.imageHeight / (2 * d.periodY)
        local shape = d.periodX / (2 * d.periodY)
        if shape < MIN_HEX_SHAPE or shape > MAX_HEX_SHAPE then
            return false
        end
    else
        across, down = d.imageWidth / (2 * d.periodX), d.imageHeight / d.periodY
        local shape = d.periodY / (2 * d.periodX)
        if shape < MIN_HEX_SHAPE or shape > MAX_HEX_SHAPE then
            return false
        end
    end
    return across >= 1 and down >= 1 and across <= MAX_DETECTED_TILES and down <= MAX_DETECTED_TILES
end

--A detected square grid that is the perfect fit's own grid: 140 px cells
--whose lines sit on the image's edges.
--- @param d ImageGridDetection
local function SameAsFit(d)
    local pps = MapGridDetection.FIT_PIXELS
    if d.tileType ~= "squares" then
        return false
    end
    if math.abs(d.cellWidth / pps - 1) > 0.01 or math.abs(d.cellHeight / pps - 1) > 0.01 then
        return false
    end
    local function NearLine(v)
        local r = v % pps
        return math.min(r, pps - r) <= 3
    end
    return NearLine(d.originX) and NearLine(d.originY)
end

--- How to grid a w x h map image, given its detection (nil while it runs, or
--- false if it failed): a perfect fit wins unless the detector found another
--- grid with at least OVERRIDE_CONFIDENCE; otherwise any usable detected grid.
--- nil when neither applies. minSquares: the fewest squares a fit may have on
--- its short side (default 1).
--- @param w number
--- @param h number
--- @param detection nil|false|ImageGridDetection
--- @param minSquares nil|number
--- @return nil|MapGridChoice
function MapGridDetection.Choose(w, h, detection, minSquares)
    local fitW, fitH = PerfectFit(w, h, minSquares)
    local d = nil
    if Usable(detection) then
        d = detection --[[@as ImageGridDetection]]
    end

    if fitW ~= nil and (d == nil or SameAsFit(d) or d.confidence < MapGridDetection.OVERRIDE_CONFIDENCE) then
        local pps = MapGridDetection.FIT_PIXELS
        return {
            source = "fit",
            tileType = "squares",
            hex = false,
            tilesW = fitW,
            tilesH = fitH,
            cellW = pps,
            cellH = pps,
            confirmed = d ~= nil and SameAsFit(d),
            overrodeFit = false,
            detection = d,
        }
    end

    if d == nil then
        return nil
    end
    -- The detector reads the file itself, but an image too big to load is shown
    -- shrunk (8192 px at most): put its grid in the shown image's pixels.
    if d.imageWidth ~= nil and d.imageWidth > 0 and d.imageHeight ~= nil and d.imageHeight > 0
        and (math.abs(d.imageWidth - w) > 0.5 or math.abs(d.imageHeight - h) > 0.5) then
        local sx, sy = w / d.imageWidth, h / d.imageHeight
        local scaled = {}
        for k, v in pairs(d) do
            scaled[k] = v
        end
        scaled.cellWidth, scaled.cellHeight = d.cellWidth * sx, d.cellHeight * sy
        scaled.periodX, scaled.periodY = d.periodX * sx, d.periodY * sy
        scaled.originX, scaled.originY = d.originX * sx, d.originY * sy
        scaled.imageWidth, scaled.imageHeight = w, h
        d = scaled --[[@as ImageGridDetection]]
    end
    local hex = d.tileType ~= "squares"
    local across, down
    if not hex then
        across, down = w / d.cellWidth, h / d.cellHeight
    elseif d.tileType == "flattop" then
        across, down = w / d.periodX, h / (2 * d.periodY)
    else
        across, down = w / (2 * d.periodX), h / d.periodY
    end
    return {
        source = "detected",
        tileType = d.tileType,
        hex = hex,
        tilesW = math.max(1, math.floor(across + 0.5)),
        tilesH = math.max(1, math.floor(down + 0.5)),
        cellW = d.cellWidth,
        cellH = d.cellHeight,
        confirmed = false,
        overrodeFit = fitW ~= nil,
        detection = d,
    }
end

--Pixels as shown to the user: whole when they are (nearly) whole.
local function Px(v)
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then
        return string.format("%d", math.floor(v + 0.5))
    end
    return string.format("%.1f", v)
end

--- Words for a choice, for the dialogs: title ('A Perfect Fit!', 'Grid
--- Detected', 'Hex Grid Detected'), a sentence about it, and a short line
--- for a caption ('20 x 15 squares at 140 px each').
--- @param choice MapGridChoice
--- @param w number the image's size in pixels
--- @param h number
--- @return {title: string, text: string, short: string}
function MapGridDetection.Describe(choice, w, h)
    if choice.source == "fit" then
        local text = string.format("This image is %dx%d pixels, which perfectly fits a %dx%d tile grid at %d pixels per square -- the standard used by most professional map creators.",
            w, h, choice.tilesW, choice.tilesH, MapGridDetection.FIT_PIXELS)
        if choice.confirmed then
            text = text .. " The grid drawn on the map lines up with it too."
        end
        return {
            title = "A Perfect Fit!",
            text = text,
            short = string.format("%d x %d squares at %d px each", choice.tilesW, choice.tilesH, MapGridDetection.FIT_PIXELS),
        }
    end

    local d = choice.detection --[[@as ImageGridDetection]]
    local sure = string.format("%d%% sure", math.floor(d.confidence * 100 + 0.5))
    if choice.hex then
        local kind = cond(choice.tileType == "flattop", "flat-top", "pointy-top")
        return {
            title = "Hex Grid Detected",
            text = string.format("This map has a %s hex grid drawn on it: hexes %s x %s pixels, about %d x %d of them (%s).",
                kind, Px(choice.cellW), Px(choice.cellH), choice.tilesW, choice.tilesH, sure),
            short = string.format("Hex grid: %s x %s px %s hexes", Px(choice.cellW), Px(choice.cellH), kind),
        }
    end

    local shape = cond(math.abs(choice.cellW - choice.cellH) <= 0.02 * math.max(choice.cellW, choice.cellH), "squares", "cells")
    local text = string.format("This map has a grid drawn on it: %s x %s pixel %s, about %d x %d of them (%s).",
        Px(choice.cellW), Px(choice.cellH), shape, choice.tilesW, choice.tilesH, sure)
    if choice.overrodeFit then
        text = text .. string.format(" Its size also fits %d px squares exactly, but the grid drawn on it is %s px.", MapGridDetection.FIT_PIXELS, Px(choice.cellW))
    end
    return {
        title = "Grid Detected",
        text = text,
        short = string.format("About %d x %d %s at %s px each", choice.tilesW, choice.tilesH, shape, Px(choice.cellW)),
    }
end

mod.shared.ImportMapDialog = function(paths, options)
    options = options or {}

    local resultPanel
    local importPanel

    local tileType = options.tileType or "squares"

    -- Map Type for the new map, as in Map Settings > Map Type: a Battlemap, or a
    -- World Map whose tiles are miles across. Until the user picks, a hex grid
    -- means World Map. A World Map starts at the game's default scale (6 miles a
    -- tile unless the Director set another). A floor shares its map's type, so
    -- floor imports don't offer it.
    local chosenMapType = nil
    local worldAmount = tonumber(dmhub.GetSettingValue("worldmap:defaulttilesize")) or 6
    local worldUnit = dmhub.GetSettingValue("worldmap:defaultunit") or "miles"
    local worldUnitName = dmhub.GetSettingValue("worldmap:defaultunitname") or ""

    local function MapType()
        if chosenMapType ~= nil then
            return chosenMapType
        end
        return cond(tileType == "squares", "battlemap", "world")
    end

    --- @type Panel|nil
    local mapTypePanel = nil

    -- Call when tileType or the choice changes: the default type follows the grid.
    local function RefreshMapType()
        if mapTypePanel ~= nil then
            mapTypePanel:FireEventTree("refreshMapType")
        end
    end

    -- Puts a World Map choice into the settings FinishMapImport applies to the new map.
    local function AddMapTypeSettings(info)
        if options.floorImport or MapType() ~= "world" then
            return
        end
        local settings = info.mapSettings or {}
        settings["map:maptype"] = "world"
        settings["map:worldtilesize"] = worldAmount
        settings["map:worldunit"] = worldUnit
        settings["map:worldunitname"] = worldUnitName
        info.mapSettings = settings
    end

    -- Automatic grid: the 140 PPS perfect fit, or the grid MapGridDetection finds.
    -- perfectFitActive: the auto panel is showing (until "Set Grid by Hand...").
    local perfectFitChecked = false
    local perfectFitActive = false
    local autoChoice = nil
    local userChoseManual = false
    local detectPath = paths ~= nil and paths[1] or nil
    if options.floorImport or detectPath == nil or not MapGridDetection.CanDetect(detectPath) then
        detectPath = nil
    end

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
                        AddMapTypeSettings(info)
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

    -- The Map Type control; its state is set up next to tileType.
    if not options.floorImport then
        local unitOptions = {}
        for _,unit in ipairs(MeasurementSystem.worldUnits) do
            unitOptions[#unitOptions+1] = { id = unit.id, text = unit.text }
        end

        local function ValidAmount(text)
            local n = tonumber(text)
            if n == nil or n ~= math.floor(n) or n < 1 or n > 99999 then
                return nil
            end
            return math.tointeger(n)
        end

        mapTypePanel = gui.Panel{
            flow = "vertical",
            width = 400,
            height = "auto",
            halign = "left",
            vmargin = 8,

            gui.Label{
                width = 400,
                height = "auto",
                fontSize = 16,
                text = "Map Type:",
            },

            gui.EnumeratedSliderControl{
                options = {
                    {id = "battlemap", text = "Battlemap"},
                    {id = "world", text = "World Map"},
                },
                width = 400,
                value = MapType(),
                hover = gui.Tooltip("Battlemap: a tactical map, each tile a few feet across. World Map: a region or world map, each tile miles across. The measuring tool reports distances in the map's units. You can change this later in Map Settings."),
                change = function(element)
                    if element.value == MapType() then
                        return
                    end
                    chosenMapType = element.value
                    RefreshMapType()
                end,
                refreshMapType = function(element)
                    if element.value ~= MapType() then
                        element.value = MapType()
                    end
                end,
            },

            -- The world scale: "Each hex is: [6] [Miles]".
            gui.Panel{
                classes = {cond(MapType() ~= "world", "collapsed")},
                flow = "horizontal",
                width = 400,
                height = 30,
                tmargin = 6,
                refreshMapType = function(element)
                    element:SetClass("collapsed", MapType() ~= "world")
                end,

                gui.Label{
                    width = "auto",
                    height = "auto",
                    fontSize = 16,
                    valign = "center",
                    rmargin = 8,
                    text = cond(tileType == "squares", "Each tile is:", "Each hex is:"),
                    refreshMapType = function(element)
                        element.text = cond(tileType == "squares", "Each tile is:", "Each hex is:")
                    end,
                },

                gui.Input{
                    fontSize = 16,
                    width = 60,
                    height = 24,
                    valign = "center",
                    characterLimit = 5,
                    text = MeasurementSystem.ToString(worldAmount),
                    hover = gui.Tooltip("How many units one tile spans, as a whole number."),
                    edit = function(element)
                        local n = ValidAmount(element.text)
                        if n ~= nil then
                            worldAmount = n
                        end
                    end,
                    change = function(element)
                        local n = ValidAmount(element.text)
                        if n == nil then
                            element.textNoNotify = MeasurementSystem.ToString(worldAmount)
                            return
                        end
                        worldAmount = n
                    end,
                },

                gui.Dropdown{
                    width = 150,
                    height = 24,
                    fontSize = 16,
                    valign = "center",
                    lmargin = 8,
                    options = unitOptions,
                    idChosen = worldUnit,
                    change = function(element)
                        ---@cast element Dropdown
                        worldUnit = element.idChosen
                        RefreshMapType()
                    end,
                },
            },

            -- The unit's name, only for a custom unit.
            gui.Panel{
                classes = {cond(MapType() ~= "world" or worldUnit ~= "custom", "collapsed")},
                flow = "horizontal",
                width = 400,
                height = 30,
                tmargin = 4,
                refreshMapType = function(element)
                    element:SetClass("collapsed", MapType() ~= "world" or worldUnit ~= "custom")
                end,

                gui.Label{
                    width = "auto",
                    height = "auto",
                    fontSize = 16,
                    valign = "center",
                    rmargin = 8,
                    text = "Unit Name:",
                },

                gui.Input{
                    fontSize = 16,
                    width = 200,
                    height = 24,
                    valign = "center",
                    characterLimit = 24,
                    placeholderText = "e.g. days",
                    text = worldUnitName,
                    edit = function(element)
                        worldUnitName = string.match(element.text, "^%s*(.-)%s*$")
                    end,
                    change = function(element)
                        worldUnitName = string.match(element.text, "^%s*(.-)%s*$")
                    end,
                },
            },
        }
    end

    -- Squares or hexes, for sizing by hand. Changing it starts the sizing over.
    -- A floor must match its map, so floor imports don't offer it.
    local tileTypeChoice = gui.EnumeratedSliderControl{
        options = {
            {id = "squares", text = "Squares"},
            {id = "flattop", text = "Flat Top"},
            {id = "pointtop", text = "Pointy Top"},
        },
        width = 400,
        valign = "top",
        value = tileType,
        change = function(element)
            if element.value == tileType then
                return
            end
            tileType = element.value
            importPanel.tileType = element.value
            gridlessChoice.value = true
            RefreshMapType()
        end,
        vmargin = 8,
    }
    --(not via classes: they would replace the control's own.)
    if options.floorImport then
        tileTypeChoice:SetClass("hidden", true)
    end

    -- While the grid detector runs, and if it finds nothing.
    local detectStatusLabel = gui.Label{
        classes = {"hidden"},
        width = 400,
        height = "auto",
        fontSize = 15,
        wrap = true,
        color = "@fgMuted",
        vmargin = 6,
        text = "",
    }

    local instructionsPanel = gui.Panel{
        width = 400,
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",
        detectStatusLabel,
        tileTypeChoice,
        instructionsText,
        gridlessChoice,
        matchMapPanel,
    }

    -- Unchecked, the automatic grid is hidden so the user can compare it with the bare map.
    local drawGridCheck = gui.Check{
        text = "Draw Grid",
        value = true,
        halign = "left",
        vmargin = 4,
        change = function(element)
            importPanel.showGrid = element.value
        end,
    }

    -- The automatic grid is drawn thick and yellow so it is easy to judge against
    -- the map; sizing by hand goes back to the thin default lines.
    local function SetAutoGridStyle(on)
        if on then
            importPanel.gridColor = "#ffd21f"
            importPanel.gridThickness = 3
            importPanel.showGrid = drawGridCheck.value
        else
            importPanel.gridColor = nil
            importPanel.gridThickness = 1
            importPanel.showGrid = true
        end
    end

    -- Held directly rather than found with Get(): Get falls back to searching the
    -- whole UI tree from the root, so a broken panel anywhere else could throw
    -- here and leave the dialog with no way forward (8CMXRYPW).
    local perfectFitTitle = gui.Label{
        id = "perfectFitTitle",
        width = 400,
        height = "auto",
        fontSize = 28,
        bold = true,
        color = "@success",
        text = "A Perfect Fit!",
        vmargin = 4,
    }

    local perfectFitDescription = gui.Label{
        id = "perfectFitDescription",
        width = 380,
        height = "auto",
        fontSize = 16,
        wrap = true,
        text = "",
        vmargin = 8,
    }

    local perfectFitDimensions = gui.Label{
        id = "perfectFitDimensions",
        width = 380,
        height = "auto",
        fontSize = 20,
        text = "",
        vmargin = 4,
    }

    -- The automatic grid panel: "A Perfect Fit!" (140 PPS) or a detected grid,
    -- with Accept and Set Grid by Hand.
    local perfectFitPanel
    perfectFitPanel = gui.Panel{
        classes = {"collapsed"},
        flow = "vertical",
        width = 400,
        height = "auto",
        halign = "left",
        valign = "top",

        drawGridCheck,

        perfectFitTitle,
        perfectFitDescription,
        perfectFitDimensions,

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
                            AddMapTypeSettings(info)
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
            text = "Set Grid by Hand...",
            halign = "left",
            vmargin = 8,
            click = function(element)
                perfectFitActive = false
                userChoseManual = true
                perfectFitPanel:SetClass("collapsed", true)
                instructionsPanel:SetClass("collapsed", false)
                detectStatusLabel:SetClass("hidden", true)
                --ResetCalibration, not ClearMarkers: a detected grid marks every
                --sizing step done, and sizing by hand must start from the first.
                importPanel:ResetCalibration()
                SetAutoGridStyle(false)
                tileTypeChoice.value = tileType
                gridlessChoice.value = true
            end,
        },
    }

    -- Shows a choice (MapGridDetection.Choose) on the import panel and in the auto
    -- panel. Returns false if the panel couldn't take it (image not loaded yet).
    local function ShowAutoChoice(element, choice)
        local imgW = element.imageWidth
        local imgH = element.imageHeight
        if choice.source == "fit" then
            --a fit's grid starts at the image's corner: gridless markers sized to it.
            if choice.tileType ~= tileType then
                tileType = choice.tileType
                element.tileType = tileType
            end
            element:ResetCalibration()
            element:CreateGridless()
            element:SetMapDimensions(choice.tilesW, choice.tilesH)
        else
            local d = choice.detection --[[@as ImageGridDetection]]
            if not element:ApplyDetectedGrid{
                tileType = d.tileType,
                periodX = d.periodX,
                periodY = d.periodY,
                originX = d.originX,
                originY = d.originY,
            } then
                return false
            end
            tileType = d.tileType
        end
        autoChoice = choice
        tileTypeChoice.value = tileType
        RefreshMapType()

        local words = MapGridDetection.Describe(choice, imgW, imgH)
        perfectFitTitle.text = words.title
        perfectFitDescription.text = words.text
        perfectFitDimensions.text = string.format("%d x %d %s",
            choice.tilesW, choice.tilesH, cond(choice.hex, "hexes", "tiles"))
        perfectFitPanel:SetClass("collapsed", false)
        instructionsPanel:SetClass("collapsed", true)

        --Last: once set, the think handler hides Previous/Continue/Confirm, so an
        --error above must leave the normal controls usable rather than none at all.
        perfectFitActive = true
        SetAutoGridStyle(true)
        return true
    end

    -- True when two choices would import the same grid and say the same thing
    -- (a fit the detector later confirms is re-shown, to say so).
    local function SameChoice(a, b)
        if a == nil or b == nil then
            return a == b
        end
        return a.source == b.source and a.tileType == b.tileType and a.confirmed == b.confirmed
            and math.abs(a.cellW - b.cellW) < 0.01 and math.abs(a.cellH - b.cellH) < 0.01
    end

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

    --Set by the row's create handler; read by the think handler (see perfectFitTitle).
    --- @type Panel|nil
    local tileScalingRow = nil

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
            id = "tileScalingRow",
            classes = {cond(tileType == "squares", nil, "hidden")},
            create = function(element)
                tileScalingRow = element
            end,
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

    -- Shown over the map preview while the engine shrinks an over-size image or
    -- converts a video on a background thread, which takes a while on big files.
    -- Left-aligned in a fixed width so the animated dots don't shift the text.
    local processingLabel = gui.Label{
        width = 280,
        height = "auto",
        halign = "center",
        valign = "center",
        fontSize = 26,
        textAlignment = "left",
        textWrap = false,
        text = "",
    }
    -- Covers the preview, which is blank white until there is an image.
    local processingOverlay = gui.Panel{
        classes = {"hidden"},
        width = 800,
        height = 800,
        halign = "right",
        valign = "top",
        y = 26,
        bgimage = "panels/square.png",
        bgcolor = "@bgAlt",
        processingLabel,
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
            local processing = element.processingMessage
            processingOverlay:SetClass("hidden", processing == nil)
            -- The sizing steps mean nothing until there is a map to size.
            instructionsPanel:SetClass("hidden", processing ~= nil)
            if processing ~= nil then
                -- 0 to 3 dots, one step every 0.4 s, so it reads as still working.
                local dots = math.floor(dmhub.Time() / 0.4) % 4
                processingLabel.text = processing .. string.rep(".", dots)
            end

            -- One-shot automatic grid, once the image has loaded: the 140 PPS
            -- perfect fit at once if the image is one, then whatever the grid
            -- detector finds (MapGridDetection.Choose decides between them).
            if not perfectFitChecked and not options.floorImport and tileType == "squares" then
                local imgW = element.imageWidth
                local imgH = element.imageHeight
                if imgW ~= nil and imgW > 0 and imgH ~= nil and imgH > 0 then
                    perfectFitChecked = true
                    local known = detectPath ~= nil and MapGridDetection.Result(detectPath) or nil
                    local choice = MapGridDetection.Choose(imgW, imgH, known)
                    if choice ~= nil then
                        ShowAutoChoice(element, choice)
                    end

                    if detectPath ~= nil and known == nil then
                        detectStatusLabel.text = "Looking for a grid on this map..."
                        detectStatusLabel:SetClass("hidden", false)
                        MapGridDetection.Request(detectPath, function(result)
                            if not element.valid or userChoseManual then
                                return
                            end
                            local found = MapGridDetection.Choose(imgW, imgH, result)
                            if found ~= nil and not SameChoice(found, autoChoice) then
                                ShowAutoChoice(element, found)
                            end
                            if autoChoice == nil then
                                detectStatusLabel.text = "No grid was found on this map. Mark one of its squares below, or choose Gridless."
                            else
                                detectStatusLabel:SetClass("hidden", true)
                            end
                        end)
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
                --tile scaling is for squares only; the tile type can change by hand now.
                if tileScalingRow ~= nil then
                    tileScalingRow:SetClass("hidden", tileType ~= "squares")
                end

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
        processingOverlay,
        buttonsPanel,
        -- The left column: the sizing instructions or the automatic grid
        -- (one at a time), then the Map Type choice under either.
        gui.Panel{
            flow = "vertical",
            width = 400,
            height = "auto",
            halign = "left",
            valign = "top",
            instructionsPanel,
            perfectFitPanel,
            mapTypePanel,
        },
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
                    --walls, doors and lights come from the stock assets
                    --(ImportMapToFloorCo); lighting is tuned afterwards in
                    --the map's UVTT Settings panel, which opens by itself.
                    assets:ImportUniversalVTT(paths, function(info)
                        if options.finish ~= nil then
                            options.finish(info)
                            gui.CloseModal()
                        end
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
