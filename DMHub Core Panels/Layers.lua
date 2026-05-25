local mod = dmhub.GetModLoading()

local g_layersDisplay = nil

local CreateFloorPanel = function(index, floorInfo)
    local descriptionLabel = gui.Label{
        classes = {"floorLabel"},
        text = floorInfo.description,
        characterLimit = 16,
        change = function(element)
            if element.text == "" then
                element.text = floorInfo.description
            else
                floorInfo.description = element.text
            end
        end,
    }

	--Canopy-only sub-panel. Shown when the layer type is "Canopy"; collapsed for plain roofs.
	--Plain roofs render fully transparent wherever the player has vision and fully opaque
	--elsewhere -- no tunable cutaway. Canopy adds the vision multiplier + cutaway controls
	--for tree-foliage / partial-cover roof setups.
	local dialogPanelCanopyOptions = gui.Panel{
		classes = cond(floorInfo.canopy, nil, "collapsed"),
		width = "auto",
		height = "auto",
		flow = "vertical",

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"form"},
				text = "Vision Multiplier:",
				linger = gui.Tooltip("The vision multiplier allows players to see further on the canopy layer than they can on other layers."),
			},

			gui.Slider{
				style = {
					height = 20,
					width = 160,
					valign = "center",
				},
				sliderWidth = 100,
				minValue = 0.1,
				maxValue = 8,
				labelWidth = 60,
				value = floorInfo.visionMultiplier,
				labelFormat = "rawpercent",
				events = {
					change = function(element)
						floorInfo.visionMultiplierNoUpload = element.value
					end,
					confirm = function(element)
						floorInfo.visionMultiplier = element.value
					end,
				},
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"form"},
				text = "Cutaway Radius:",
				linger = gui.Tooltip("The cutaway radius (in tiles) around any token with vision. Pixels of the canopy within this distance of a token are cut away to reveal the layer below. Set negative to disable the cutaway entirely (the canopy will always be fully shown). For tree foliage, try a small value like 6-10."),
			},

			gui.Slider{
				style = {
					height = 20,
					width = 160,
					valign = "center",
				},
				sliderWidth = 100,
				minValue = -1,
				maxValue = 40,
				labelWidth = 60,
				labelFormat = "%d",
				value = floorInfo.roofVisionExclusion,
				events = {
					change = function(element)
						floorInfo.roofVisionExclusionNoUpload = element.value
					end,
					confirm = function(element)
						floorInfo.roofVisionExclusion = element.value
					end,
				},
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"form"},
				text = "Cutaway Fade:",
				linger = gui.Tooltip("Width (in tiles) of the smooth fade band at the outer edge of the cutaway. Larger values give a softer transition back to the full canopy; a fade of 0 produces a hard edge."),
			},

			gui.Slider{
				style = {
					height = 20,
					width = 160,
					valign = "center",
				},
				sliderWidth = 100,
				labelFormat = "%.1f",
				minValue = 0,
				maxValue = 2,
				labelWidth = 60,
				value = floorInfo.roofVisionExclusionFade,
				events = {
					change = function(element)
						floorInfo.roofVisionExclusionFadeNoUpload = element.value
					end,
					confirm = function(element)
						floorInfo.roofVisionExclusionFade = element.value
					end,
				},
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"form"},
				text = "Minimum Opacity:",
				linger = gui.Tooltip("The minimum opacity that the canopy layer will have within the cutaway zone. 0 means fully transparent at the token; raise it to keep some of the canopy visible even directly above a token."),
			},

			gui.Slider{
				style = {
					height = 20,
					width = 160,
					valign = "center",
				},
				sliderWidth = 100,
				labelFormat = "rawpercent",
				minValue = 0.0,
				maxValue = 1.0,
				labelWidth = 60,
				value = floorInfo.roofMinimumOpacity,
				events = {
					change = function(element)
						floorInfo.roofMinimumOpacityNoUpload = element.value
					end,
					confirm = function(element)
						floorInfo.roofMinimumOpacity = element.value
					end,
				},
			},
		},
	}

	local dialogPanelRoofLayerOptions = gui.Panel{
		classes = cond(floorInfo.roof, nil, "collapsed"),
		width = "auto",
		height = "auto",
		flow = "vertical",

		gui.Check{
			text = "Hide roof when players are inside",
			value = not floorInfo.roofShowWhenInside,
			style = {
				height = 20,
				width = "40%",
			},
			events = {
				change = function(element)
					floorInfo.roofShowWhenInside = not element.value
				end,
				linger = gui.Tooltip("This layer will be hidden when players are inside."),
			},
		},

		dialogPanelCanopyOptions,
	}

	local function CurrentLayerType()
		if floorInfo.canopy then
			return "canopy"
		elseif floorInfo.roof then
			return "roof"
		else
			return "floor"
		end
	end

    return gui.Panel{
        classes = {"floorPanel", "offscreen"},
        data = {
            index = index,
        },
        onscreen = function(element)
            element:SetClass("offscreen", false)
        end,
        offscreen = function(element)
            element:SetClass("offscreen", true)
        end,
        hover = function(element)
            dmhub.LayerCamera:SetHighlight(index, true)
        end,
        dehover = function(element)
            dmhub.LayerCamera:SetHighlight(index, element:HasClass("selected"))
        end,
        press = function(element)
            for _,p in ipairs(element.parent.children) do
                p:FireEvent("select", p == element)
            end
        end,

        select = function(element, val)
            element:SetClass("selected", val)
            dmhub.LayerCamera:SetHighlight(element.data.index, val)
            descriptionLabel.editable = val
        end,

        descriptionLabel,

        gui.Panel{
            classes = {"floorConfig"},
            gui.Dropdown{
                height = 18,
                fontSize = 14,
                width = 100,
                valign = "center",
                options = {
                    {id = "floor", text = "Floor"},
                    {id = "roof", text = "Roof"},
                    {id = "canopy", text = "Canopy"},
                },
                idChosen = CurrentLayerType(),
                change = function(element)
                    local id = element.idChosen
                    if id == "floor" then
                        floorInfo.roof = false
                        floorInfo.canopy = false
                    elseif id == "roof" then
                        floorInfo.roof = true
                        floorInfo.canopy = false
                    elseif id == "canopy" then
                        floorInfo.roof = true
                        floorInfo.canopy = true
                    end
                    dialogPanelRoofLayerOptions:SetClass("collapsed", not floorInfo.roof)
                    dialogPanelCanopyOptions:SetClass("collapsed", not floorInfo.canopy)
                end,
            },

            dialogPanelRoofLayerOptions,

        },
    }
end

local LayerSettingsDisplay = function()
    local resultPanel
    
    resultPanel = gui.Panel{
        halign = "right",
        valign = "center",
        height = 800,
        width = 400,
        vscroll = true,

        styles = ThemeEngine.MergeStyles({
            {
                selectors = {"floorPanel"},
                bgimage = true,
                bgcolor = "@bg",
                width = "100%",
                height = "auto",
                flow = "vertical",
                vmargin = 2,
            },
            {
                selectors = {"floorPanel", "hover"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"floorPanel", "offscreen"},
                transitionTime = 0.3,
                x = 420,
            },

            {
                selectors = {"floorLabel"},
                bold = true,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "left",
                hmargin = 4,
                vmargin = 4,
            },
            {
                selectors = {"floorLabel", "parent:hover"},
                color = "@fgStrong",
            },

            {
                selectors = {"floorConfig"},
                flow = "vertical",
                width = "auto",
                height = "auto",
                collapsed = 1,
                uiscale = { x = 1, y = 0.001 },
            },
            {
                selectors = {"floorConfig", "parent:selected"},
                collapsed = 0,
                uiscale = { x = 1, y = 1 },
                transitionTime = 0.1,
            },
        }),

        gui.Panel{
            width = "95%",
            height = "auto",
            halign = "left",
            flow = "vertical",
            create = function(element)
                local delay = 0.5
                local children = {}
	            for i = #game.currentMap.floors,1,-1 do
                    local floorInfo = game.currentMap.floors[i]
                    if floorInfo.parentFloor == nil then
                        local floorPanel = CreateFloorPanel(i, floorInfo)
                        floorPanel:ScheduleEvent("onscreen", delay)
                        delay = delay + 0.1
                        children[#children+1] = floorPanel
                    end
                end

                element.children = children
            end,
            beginClose = function(element)
                local delay = 0
                for i,child in ipairs(element.children) do
                    child:ScheduleEvent("offscreen", delay)
                    delay = delay + 0.1
                end

            end,
        }
    }

    return resultPanel
end

mod.shared.CreateLayersDisplay = function()
    if g_layersDisplay ~= nil then
        g_layersDisplay:DestroySelf()
        g_layersDisplay = nil
    end


    g_layersDisplay = gui.Panel{
        classes = {"layersDisplay"},
        width = "100%",
        height = "100%",
        bgcolor = "white",
        bgimage = "#MapLayers",

        styles = {
            {
                selectors = {"layersDisplay", "create"},
                transitionTime = 0.2,
                opacity = 0,
            },
            {
                selectors = {"layersDisplay", "destroy"},
                transitionTime = 0.2,
                opacity = 0,
            },
            {
                selectors = {"layersDisplay"},
                opacity = 1,
            },
        },

        LayerSettingsDisplay(),

		captureEscape = true,
		escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            dmhub.LayerCamera:BeginFade()
            element.captureEscape = false
            element.interactable = false

            g_layersDisplay = nil

            element:FireEventTree("beginClose")
            element:ScheduleEvent("beginDestroy", 0.8)
        end,

        beginDestroy = function(element)
            element:SetClass("destroy", true)
            element:ScheduleEvent("completeDestroy", 0.3)
        end,

        completeDestroy = function(element)
            element:DestroySelf()
        end,
    }

    gamehud.dialog.sheet:AddChild(g_layersDisplay)
end

mod.unloadHandlers[#mod.unloadHandlers+1] = function()
    if g_layersDisplay ~= nil then
        g_layersDisplay:DestroySelf()
        g_layersDisplay = nil
    end
end