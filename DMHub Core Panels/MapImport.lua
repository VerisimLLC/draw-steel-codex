local mod = dmhub.GetModLoading()

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

mod.shared.ImportMapDialog = function(paths, options)
    options = options or {}

    local resultPanel
    local importPanel

    local tileType = options.tileType or "squares"


    local confirmButton = gui.PrettyButton{
        classes = {"hidden"},
        text = "Finish",
        height = 50,
        width = 180,
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

                    gui.CloseModal()

                    g_modalDialog = nil

                    if options.finish ~= nil then
                        -- Attach the local file paths and image dimensions for the alignment dialog.
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
            end
        end,

        vmargin = 16,
    }

    -- "Match Existing Map" panel for floor imports.
    local matchMapPanel = nil
    local matchApplied = false

    if options.floorImport then
        local dim = game.currentMap.dimensions
        local mapW = dim.x2 - dim.x1
        local mapH = dim.y2 - dim.y1

        if mapW > 0 and mapH > 0 then
            local matchInfoLabel = gui.Label{
                width = 380,
                height = "auto",
                fontSize = 14,
                color = "#cccccc",
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

                gui.PrettyButton{
                    text = "Match Existing Map",
                    width = 200,
                    height = 40,
                    halign = "left",
                    vmargin = 4,
                    fontSize = 18,
                    click = function(element)
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
                width = 90,
                height = "auto",
                text = "Width:",
                fontSize = 18,
            },
            statusWidth,
            gui.Label{
                width = "auto",
                height = "auto",
                text = "px",
                fontSize = 18,
            },
        },

        gui.Panel{
            bgimage = "icons/icon_tool/icon_tool_30_unlocked.png",
            width = 16,
            height = 16,
            bgcolor = "white",

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
                width = 90,
                height = "auto",
                text = "Height:",
                fontSize = 18,
            },
            statusHeight,
            gui.Label{
                width = "auto",
                height = "auto",
                text = "px",
                fontSize = 18,
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

        local imgW, imgH = getImageDim()
        if imgW == nil then
            return
        end

        if source == "width" then
            mapWidthTouched = true
            if not mapHeightTouched then
                local inferredH = math.floor(val * (imgH / imgW) + 0.5)
                if inferredH < 1 then inferredH = 1 end
                mapDimHeight.textNoNotify = tostring(inferredH)
                importPanel:SetMapDimensions(val, inferredH)
            else
                local hVal = tonumber(mapDimHeight.text)
                if hVal ~= nil and hVal >= 1 and hVal == math.floor(hVal) then
                    importPanel:SetMapDimensions(val, hVal)
                end
            end
        else
            mapHeightTouched = true
            if not mapWidthTouched then
                local inferredW = math.floor(val * (imgW / imgH) + 0.5)
                if inferredW < 1 then inferredW = 1 end
                mapDimWidth.textNoNotify = tostring(inferredW)
                importPanel:SetMapDimensions(inferredW, val)
            else
                local wVal = tonumber(mapDimWidth.text)
                if wVal ~= nil and wVal >= 1 and wVal == math.floor(wVal) then
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
        color = "#cccccc",
        text = "",

        updateInfo = function(element)
            local wVal = tonumber(mapDimWidth.text)
            local hVal = tonumber(mapDimHeight.text)
            local imgW, imgH = getImageDim()
            if wVal and hVal and wVal >= 1 and hVal >= 1 and imgW then
                local tileW = imgW / wVal
                local tileH = imgH / hVal
                element.text = string.format("Tile size: %.1f x %.1f px", tileW, tileH)
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
                width = "auto",
                height = "auto",
                text = "1 tile = ",
                fontSize = 18,
            },

            gui.Input{
                characterLimit = 3,
                width = 90,
                height = 20,
                fontSize = 18,
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
                width = "auto",
                height = "auto",
                text = string.format(" %s", string.lower(MeasurementSystem.UnitName())),
                fontSize = 18,
            },
        },

        gui.Label{
            width = 280,
            height = "auto",
            fontSize = 18,
            create = function(element)
                element:FireEvent("updateScaling")
            end,

            updateScaling = function(element)
                if importPanel.tileScaling == 1 then
                    element.text = "A tile in the imported map will become 1 tile in DMHub."
                    return
                end

                element.text = string.format("A tile in the imported map will become %dx%d tiles in DMHub.", importPanel.tileScaling, importPanel.tileScaling)
            end,

            scalingError = function(element)
                element.text = string.format("Enter a multiple of %s", tostring(MeasurementSystem.CurrentSystem().tileSize))
            end,

        }
    }

    local layerIndex = 1

    local layersPagingPanel
    
    printf("IMPORT:: PATHS = %d", #paths)
    if #paths > 1 then
        layersPagingPanel = gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            valign = "top",
            halign = "center",

            gui.PagingArrow{
                facing = -1,
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

            gui.PagingArrow{
                facing = 1,
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

    print("LAYER::SET", json(layerIndex))
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
                color = "white",
                text = importPanel.errorMessage
            }
        }
    end

    resultPanel:FireEventTree("refresh")

    return resultPanel
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

                if allowUVTT and (string.ends_with(paths[1], ".dd2vtt") or string.ends_with(paths[1], ".uvtt") or string.ends_with(paths[1], ".json")) then
                    for _,path in ipairs(paths) do
                        if (not string.ends_with(path, ".dd2vtt")) and (not string.ends_with(path, ".uvtt")) and (not string.ends_with(path, ".json")) then
                            gui.ModalMessage{
                                title = "Error Importing",
                                message = "Cannot import layers of mixed file types.",
                            }
                            return
                        end
                    end
                    assets:ImportUniversalVTT(paths, function(info)
                        if options.finish ~= nil then
                            options.finish(info)
                            gui.CloseModal()
                        end
                    end,
                    function(error)

                        printf("ERROR: Importing: %s", error)
                        gui.ModalMessage{
                            title = "Error Importing",
                            message = error,
                        }
                    end)
                else

                    for _,path in ipairs(paths) do
                        if string.ends_with(path, ".dd2vtt") or string.ends_with(path, ".uvtt") or string.ends_with(path, ".json") then
                            gui.ModalMessage{
                                title = "Error Importing",
                                message = "Cannot import layers of mixed file types.",
                            }
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

			styles = {
				{
					width = "80%",
					height = "60%",
					valign = "center",
					selectors = {"dropArea"},
					bgcolor = "#ffffff33",
					borderColor = "white",
					borderWidth = 6,
					cornerRadius = 16,
				},
				{
					selectors = {"dropArea","hover"},
					bgcolor = "#ffffff99",
				}

			},

			gui.Label{
				color = "white",
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
			color = "white",
			width = "auto",
			height = "auto",
			text = "-or-",
		},

		gui.Button{
			text = "Choose Files",
			width = 320,
			height = 70,
            fontSize = 36,
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
		styles = {
			Styles.Default,
			Styles.Panel,
		},

		destroy = function(element)
			if g_modalDialog == element then
				g_modalDialog = nil
			end
		end,

		output = function(element, info)
			dmhub.Debug(string.format("OPEN FILES: update = %s; sheets = %s", json(info), json(importer.sheets)))

			element:FireEventTree("refresh")
		end,

		gui.Label{
			classes = {"dialogTitle"},
			text = "Import Map from Image",
		},

		contentPanel,

	--gui.ProgressBar{
	--	width = "80%",
	--	height = 64,
	--	value = 0,
	--	thinkTime = 0.1,
	--	think = function(element)
	--		element.value = element.value + 0.01
	--	end,
	--},

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