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

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"form"},
				text = "Vision Multiplier:",
				linger = gui.Tooltip("The vision multiplier allows players to see further on the roof layer than they can on other layers."),
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
				linger = gui.Tooltip("The cutaway radius is the distance to which we prefer to show the radius the player is on if they have vision of it instead of the roof layer. For roofs of buildings you most likely want this to be 100%, but for tree foliage you might want it lower than 100%. The lower it is the more elements on the roof layer will occlude vision."),
			},

			gui.Slider{
				style = {
					height = 20,
					width = 160,
					valign = "center",
				},
				sliderWidth = 100,
				minValue = 0.0,
				maxValue = 1.0,
				labelWidth = 60,
				labelFormat = "rawpercent",
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
				linger = gui.Tooltip("The roof cutaway fade controls how quickly vision fades from showing the layer the player is on to the roof layer."),
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
				linger = gui.Tooltip("The minimum opacity that the roof layer will have when it is cut away to show the layer the player is on."),
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
            gui.Check{
                text = "Roof",
                value = floorInfo.roof,
				style = {
					height = 14,
                    -- fontSize = 12,
                    -- color = "#bbbbbbff",
				},
				events = {
					change = function(element)
						floorInfo.roof = element.value
                        dialogPanelRoofLayerOptions:SetClass("collapsed", not floorInfo.roof)
					end,
					linger = gui.Tooltip("A roof layer will be displayed for players who are on a floor beneath it. It will only be displayed in areas they can't see."),
				},
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