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
                    gui.CloseModal()

                    g_modalDialog = nil

                    if options.finish ~= nil then
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