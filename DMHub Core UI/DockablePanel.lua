--Use /BroadcastDefaultSetting dockablepanelsplayer_v1 to broadcast new dockable panel setup.
--Use /BroadcastDefaultSetting dockablepanelsgm_v2 to broadcast new gm dockable panel setup.

setting{
    id = "centerdockoffscreen",
    default = false,
    storage = "transient",
}

--types of registered dockable panels.
local dockablePanels = {}

local dockablePanelsPlayerSetting = "dockablepanelsplayer_v1"
local dockablePanelsDMSetting = "dockablepanelsgm_v2"

local g_dockGap = 0

function GetDockablePanelsSetting()
	return cond(dmhub.isDM, dockablePanelsDMSetting, dockablePanelsPlayerSetting)
end

local GetPanelsConfig = function()
	return dmhub.GetSettingValue(GetDockablePanelsSetting())
end

local SetPanelsConfig = function(val)
	dmhub.SetSettingValue(GetDockablePanelsSetting(), val)
end

setting{
	id = dockablePanelsPlayerSetting,
	description = "Dockable Panels set up for player view.",
	help = "",
	storage = "pergamepreference",
	default = {
		docks = {
			{
				panels = {},
			},
			{
				panels = {},
			},
		}
	},
}

setting{
	id = dockablePanelsDMSetting,
	description = "Dockable Panels set up for Director view.",
	help = "",
	storage = "pergamepreference",
	default = {
		docks = {
			{
				panels = {},
			},
			{
				panels = {},
			},
		}
	},
}

local DockablePanelBorder = 8

local DockablePanelTheme = {
	{
		selectors = {"dock"},
	},

	{
		selectors = {"dock", "offscreen", "left"},
		x = -380,
		transitionTime = 0.2,
	},

	{
		selectors = {"dock", "offscreen", "right"},
		x = 380,
		transitionTime = 0.2,
	},

	{
		selectors = {"dockFrame"},
		--bgimage = 'panels/hud/button_09_frame_custom.png',
        bgimage = true,
		bgcolor = '#00000000',
		width = "100%",
		height = string.format("100%%+%d", round(g_dockGap)),
        valign = "bottom",
	},

    {
        selectors = {"dockFrame", "~uiblur"},
        bgcolor = "#000000",
    },

	{
		selectors = {"dockFrame", "parent:empty"},
        collapsed = 1,
	},


	{
		selectors = {"dockablePanel"},
		width = "100%",
		height = "100%",
		halign = "center",
		valign = "center",

		vpad = 4,
	},

	{
		selectors = {"dockablePanel", "highlightPanel"},
		--bgimage = 'panels/hud/button_09_frame_highlight.png',
	},


	{
		selectors = {"tabContainer"},
        bgimage = true,
        gradient = Styles.RichBlackGradient,
        bgcolor = "white",
        borderColor = Styles.Gold02,
        border = {x1 = 0, x2 = 0, y1 = 0, y2 = 1},
	},

    {
        selectors = {"tabContainer", "~mono"},
        border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},
    },

	{
		selectors = {"dragGhost"},
		opacity = 0,
		bgcolor = "#4444ff",
	},

	{
		selectors = {"dragGhost", "dragging"},
		opacity = 0.5,
	},
	{
		selectors = {"dragGhost", "dragging", "deleting"},
		bgcolor = "#ff4444",
	},
    {
        selectors = {"dragGhost", "floatingTarget"},
        opacity = 0,
    },
	{
		selectors = {"verticalDragInvisibleHandle"},
		width = "100%",
		y = -4,
		height = 8,
		opacity = 0,
		bgimage = "panels/square.png",
		bgcolor = "white",
		valign = "top",
		halign = "center",
	},

	{
		selectors = {"verticalDragDivider"},
		width = "100%-8",
		halign = "center",
		valign = "top",
		height = 2,
		--opacity = 1,
		--bgimage = "panels/square.png",
		--bgcolor = "clear",
	},
	{
		selectors = {"verticalDragInvisibleHandle", "tabs"},
	},
	{
		selectors = {"verticalDragDivider", "tabs"},
	},

	{
		selectors = {"highlightPanel"},
		--bgimage = "panels/square.png",
		--bgcolor = "#ffffff33",
	},

    {
		selectors = {"dockHandle"},
		width = 32,
		height = 64,
		bgimage = "panels/dock-handle.png",
		bgcolor = "white",
		valign = "bottom",
		halign = "right",
		saturation = 0,
		brightness = 2,
        opacity = 0.5,
	},

	{
		selectors = {"dockHandle", "left"},
		scale = {x = -1},
		x = 16,
		y = 8,
	},

	{
		selectors = {"dockHandle", "left", "hover", "~parent:offscreen"},
		x = 16,
		transitionTime = 0.1,
	},

	{
		selectors = {"dockHandle", "left", "parent:offscreen"},
		x = 16,
		transitionTime = 0.1,
	},

	{
		selectors = {"dockHandle", "right"},
		halign = "left",
		x = -16,
		y = 8,
	},

	{
		selectors = {"dockHandle", "right", "hover", "~parent:offscreen"},
		x = -16,
		transitionTime = 0.1,
	},

	{
		selectors = {"dockHandle", "right", "parent:offscreen"},
		x = -16,
		transitionTime = 0.1,
	},

	{
		selectors = {"dockHandle", "hover"},
		brightness = 2,
	},

	

	{
		selectors = {"dockHandle", "parent:empty"},
		collapsed = 1,
	},


    {
        selectors = {"tab"},
		width = 20,
		height = 20,
        bgcolor = "white",
        halign = "center",
        valign = "center",
    },

    {
        selectors = {"tabLabel", "crowded", "~selected"},
        collapsed = 1,
    },

    {
        selectors = {"buttonContainer"},
        bgimage = true,
        bgcolor = "clear",
        borderColor = Styles.Gold02,
        border = {y1 = 1, x1 = 0, x2 = 0, y2 = 0},

    },
    {
        selectors = {"buttonContainer", "selected"},
        bgimage = true,
        bgcolor = Styles.RichBlack02,
        border = {y1 = 0, x1 = 1, x2 = 1, y2 = 1},
    },
    {
        selectors = {"buttonContainer", "mono"},
        bgcolor = "clear",
        border = {y1 = 0, x1 = 0, x2 = 0, y2 = 0},
    }
}

gui.RegisterTheme("DockablePanel", "Main", DockablePanelTheme)

function GameHud:CreateSingleDock(params)
    local floating = params.floating or false
    params.floating = nil

	local resultPanel = nil

	local offscreenSetting = string.format("%sdockoffscreen", params.halign)

	local framePanel = gui.Panel{
		classes = {"dockFrame", cond(floating, "floatingDock")},
        bgimage = true,
        blurBackground = not floating,
		floating = true,
        interactable = not floating,
	}

    if floating then
        --absolutely force the panel to be clear if we are floating.
        framePanel.selfStyle.bgcolor = "clear"
    end

    local closeHandle
    if not floating then
        closeHandle = gui.Panel{
            idprefix = "dockHandle",
            classes = {"dockHandle", params.halign},
            floating = true,

            monitor = offscreenSetting,

            events = {
                press = function(element)
                    dmhub.SetSettingValue(offscreenSetting, not dmhub.GetSettingValue(offscreenSetting))
                end,

                monitor = function(element)
                    resultPanel:SetClass("offscreen", dmhub.GetSettingValue(offscreenSetting))
                    dmhub.UpdateScreenHudArea(cond(resultPanel:HasClass("offscreen"), 0, 1))
                end,

                create = function(element)
                    element:FireEvent("monitor")
                end,
            }
        }
    end

	local DockHeight = (params.height or 1080)
	params.height = DockHeight

	local verticalResizingInfo = nil

	--functions to compress and expand the vertical size of panels. We have deltaPixels to work with
	--and we prefer to apply as many as possible to the panel at the given index, but will step to the
	--next panel once height constraints would be violated, stepping in the direction of 'dir'.
	local CompressVerticalResizing = function(heights, index, dir, deltaPixels)
		local startingDeltaPixels = deltaPixels
		local resultHeights = DeepCopy(heights)
		while deltaPixels > 0 and heights[index] ~= nil do
			local element = resultPanel.data.GetChildren()[index]
			local available = heights[index] - element.data.minHeight
			if available > deltaPixels then
				resultHeights[index] = heights[index] - deltaPixels
				deltaPixels = 0
			else
				resultHeights[index] = element.data.minHeight
				deltaPixels = deltaPixels - available
			end
			index = index + dir
		end

		return {
			pixels = startingDeltaPixels - deltaPixels,
			heights = resultHeights,
		}
	end

	local ExpandVerticalResizing = function(heights, index, dir, deltaPixels)
		local startingDeltaPixels = deltaPixels
		local resultHeights = DeepCopy(heights)
		while deltaPixels > 0 and heights[index] ~= nil do
			local element = resultPanel.data.GetChildren()[index]
			local available = element.data.maxHeight - heights[index]
			if available > deltaPixels then
				resultHeights[index] = heights[index] + deltaPixels
				deltaPixels = 0
			else
				resultHeights[index] = element.data.maxHeight
				deltaPixels = deltaPixels - available
			end
			index = index + dir
		end

		return {
			pixels = startingDeltaPixels - deltaPixels,
			heights = resultHeights,
		}
	end

    local width = DockablePanel.ContentWidth + g_dockGap*2
    if floating then
        width = (1920 * ((dmhub.screenDimensions.x/dmhub.screenDimensions.y)/(1920/1080))) - width*2 - DockablePanel.FloatingDockMargin
    end

	local args = {
		id = params.id,
		flow = cond(floating, "none", "vertical"),
		interactable = false,
		width = width,
		classes = {"dock", params.halign},
		dragTarget = true,
		data = {
            floating = floating,
			maximizedChild = nil,
			dockedPanels = {},
			DockHeight = DockHeight,

			--how to halign tooltips on this dock.
			TooltipAlignment = function()
				return cond(params.halign == "left", "right", "left")
			end,

			SetChildren = function(children)
				table.insert(children, 1, framePanel)
				table.insert(children, 1, closeHandle)
				resultPanel.children = children
			end,

			GetChildren = function()
				return resultPanel:GetChildrenWithClasses({"dockablePanelContainer", "~collapsed"})
			end,
		},

		layoutChanged = function(element)
            local children = element.data.GetChildren()
            if not floating then
                for i,child in ipairs(children) do
                    child:FireEventTree("draggable", i > 1)

                    child:SetClassTree("single", #children == 1)
                end
            end

			element:SetClass("empty", #children == 0)
		end,

		addPanel = function(element, newPanel)
			element:FireEvent("ensureNoMaximize")

			newPanel:FireEvent("dock", element)

			local children = element.data.GetChildren()
			children[#children+1] = newPanel
			resultPanel.data.SetChildren(children)

			element:FireEvent("sizeChild", newPanel, element.data.DockHeight/#element.data.GetChildren())
			element:FireEventTree("layoutChanged")
		end,

		addPanelNoSize = function(element, newPanel)
			element:FireEvent("ensureNoMaximize")

			newPanel:FireEvent("dock", element)

			local children = element.data.GetChildren()
			children[#children+1] = newPanel
			resultPanel.data.SetChildren(children)

			element:FireEventTree("layoutChanged")
		end,

		clearPanels = function(element)
			element:FireEvent("ensureNoMaximize")
			element.children = {closeHandle, framePanel}
		end,


		beginDragDockablePanel = function(element)
			element:FireEvent("ensureNoMaximize")

			element.data.childrenAtDragStart = element.data.GetChildren()
			for _,child in ipairs(element.data.childrenAtDragStart) do
				child.data.startDragHeight = child.selfStyle.height
			end
		end,

		endDragDockablePanel = function(element)
			element.data.childrenAtDragStart = nil
			for _,child in ipairs(element.data.GetChildren()) do
				child.data.startDragHeight = nil
			end
		end,


		--called when we start resizing panels using dragging, record the current layout
		--of heights so they can be manipulated based on dragging.
		beginVerticalResizing = function(element, childElement)
			verticalResizingInfo = { heights = {} }
			local children = element.data.GetChildren()
			for i,child in ipairs(children) do
				if child == childElement then
					verticalResizingInfo.index = i-1
					verticalResizingInfo.childElement = children[i-1]
					verticalResizingInfo.nextElement = children[i]
				end

				verticalResizingInfo.heights[i] = child.selfStyle.height
			end
		end,

		--called per frame when we resize panels using dragging, do the resizing in here.
		verticalSizeChild = function(element, ydelta)
            if floating then
                return
            end
			local compress, expand
			local delta = math.abs(ydelta)

			--first pass, find the maximum delta we can tolerate without violating minimum or maximum height constraints.
			if ydelta < 0 then
				compress = CompressVerticalResizing(verticalResizingInfo.heights, verticalResizingInfo.index, -1, -ydelta)
				expand = ExpandVerticalResizing(verticalResizingInfo.heights, verticalResizingInfo.index+1, 1, -ydelta)
			else
				expand = ExpandVerticalResizing(verticalResizingInfo.heights, verticalResizingInfo.index, -1, ydelta)
				compress = CompressVerticalResizing(verticalResizingInfo.heights, verticalResizingInfo.index+1, 1, ydelta)
			end

			delta = math.min(delta, math.min(compress.pixels, expand.pixels))

			--second pass, now we know the actual delta calculate our new heights.
			local heights
			if ydelta < 0 then
				heights = CompressVerticalResizing(ExpandVerticalResizing(verticalResizingInfo.heights, verticalResizingInfo.index+1, 1, delta).heights, verticalResizingInfo.index, -1, delta).heights
			else
				heights = ExpandVerticalResizing(CompressVerticalResizing(verticalResizingInfo.heights, verticalResizingInfo.index+1, 1, delta).heights, verticalResizingInfo.index, -1, delta).heights
			end

			local children = element.data.GetChildren()
			for i,height in ipairs(heights) do
				children[i].selfStyle.height = height
			end
		end,

		minimizeChild = function(element, child)
			local container = child:FindParentWithClass("dockablePanelContainer")
			if container == nil or not container.data.maximized then
				return
			end

			container.data.maximized = false

            if floating then
                container:FireEvent("minimizeFloating")
                return
            end


			local children = element:GetChildrenWithClasses({"dockablePanelContainer"})
			for _,child in ipairs(children) do
				child:SetClass("collapsed", false)
			end

			element:FireEvent("fitChildren")

			container:FireEventTree("minimize")

			element.data.maximizedChild = nil
		end,

		maximizeChild = function(element, child)

			local container = child:FindParentWithClass("dockablePanelContainer")
			if container == nil then
				return
			end

			container.data.maximized = true

            if floating then
                container:FireEvent("maximizeFloating")
                return
            end


			local children = element.data.GetChildren()
			for _,child in ipairs(children) do
				child:SetClass("collapsed", child ~= container)
			end

			element:FireEvent("fitChildren")

			container:FireEventTree("maximize")

			element.data.maximizedChild = child
		end,

		ensureNoMaximize = function(element)
			if element.data.maximizedChild ~= nil and element.data.maximizedChild.valid then
				element.data.maximizedChild:FireEventOnParents("minimizeChild", element.data.maximizedChild)
			end
		end,

		fitChildren = function(element)
            if floating then
                return
            end
			local children = {}
			
			for _,child in ipairs(element.data.GetChildren()) do
				if child:HasClass("collapsed") == false then
					if child.data.startDragHeight ~= nil then
						child.selfStyle.height = child.data.startDragHeight
					end

					children[#children+1] = child
				end
			end

			if #children == 0 then
				return
			end

			local shrinkAvailable = 0
			local growAvailable = 0

			local shrinkingPanels = {}
			local growingPanels = {}

			local currentHeight = 0

			for _,child in ipairs(element.data.GetChildren()) do
				if child.selfStyle.height < child.data.minHeight then
					child.selfStyle.height = child.data.minHeight
				elseif child.selfStyle.height > child.data.maxHeight then
					child.selfStyle.height = child.data.maxHeight
				end
			end

			for _,child in ipairs(element.data.GetChildren()) do
				currentHeight = currentHeight + child.selfStyle.height
				if child.selfStyle.height > child.data.minHeight and not child.data.locked then
					shrinkingPanels[#shrinkingPanels+1] = child
					shrinkAvailable = shrinkAvailable + (child.selfStyle.height - child.data.minHeight)
				end

				if child.selfStyle.height < child.data.maxHeight and not child.data.locked then
					growingPanels[#growingPanels+1] = child
					growAvailable = growAvailable + (child.data.maxHeight - child.selfStyle.height)
				end
			end

			local delta = DockHeight - currentHeight

			if delta < 0 then
				local shrinkRequired = -delta
				local shrinkAmount = math.min(shrinkRequired, shrinkAvailable)
				local shrinkRatio = 1 - shrinkAmount/shrinkAvailable
				for _,child in ipairs(shrinkingPanels) do
					child.selfStyle.height = child.data.minHeight + (child.selfStyle.height - child.data.minHeight)*shrinkRatio
				end
			else
				local growRequired = delta
				local growAmount = math.min(growRequired, growAvailable)
				local growRatio = growAmount/growAvailable
				for _,child in ipairs(growingPanels) do
					child.selfStyle.height = child.selfStyle.height + (child.data.maxHeight - child.selfStyle.height)*growRatio
				end
			end

			--See if we conform with the dock height after shrinking or growing all available space. If we still don't, then
			--we violate min/max panel heights in order to conform.
			currentHeight = 0
			for _,child in ipairs(element.data.GetChildren()) do
				currentHeight = currentHeight + child.selfStyle.height
			end

			if currentHeight > 0 and currentHeight ~= DockHeight then
				local ratio = DockHeight/currentHeight
				for _,child in ipairs(element.data.GetChildren()) do
					child.selfStyle.height = child.selfStyle.height*ratio
				end
			end

            for i,child in ipairs(element.data.GetChildren()) do
                print("CHILD::", i, child.selfStyle.height, child.data.minHeight, child.data.maxHeight)
            end
		end,

		sizeChild = function(element, childElement, sz)
            if floating then
                return
            end
			local children = element.data.GetChildren()
			if #children == 1 then
				children[1].selfStyle.height = DockHeight
			elseif #children > 1 then

				local shrinkingPanels = {}
				local shrinkAvailable = 0

				local currentHeight = 0
				for _,child in ipairs(children) do
					if child ~= childElement then
						currentHeight = currentHeight + child.selfStyle.height

						if child.selfStyle.height > child.data.minHeight and not child.data.locked then
							shrinkingPanels[#shrinkingPanels+1] = child
							shrinkAvailable = shrinkAvailable + (child.selfStyle.height - child.data.minHeight)
						end
					end
				end

				local available = DockHeight - sz

				local shrinkRequired = currentHeight - available
				local shrinkAmount = math.min(shrinkRequired, shrinkAvailable)
				local shrinkRatio = 1 - shrinkAmount/shrinkAvailable
				for _,child in ipairs(shrinkingPanels) do
					child.selfStyle.height = child.data.minHeight + (child.selfStyle.height - child.data.minHeight)*shrinkRatio
				end

				if shrinkAmount < shrinkRequired then
					sz = sz - (shrinkRequired - shrinkAmount)
				end

				childElement.selfStyle.height = sz

				element:FireEvent("fitChildren")
			end

		end,
	}

	for k,v in pairs(params) do
		args[k] = params[k]
	end

	resultPanel = gui.Panel(args)

	return resultPanel
end


function GameHud:CreateDocks()

	self.leftDock = self:CreateSingleDock{
		height = 1080 - 32 - g_dockGap,
		id = "leftDock",
		halign = "left",
		valign = "bottom",
	}
	self.rightDock = self:CreateSingleDock{
		height = 1080 - 32 - g_dockGap,
		id = "rightDock",
		halign = "right",
		valign = "bottom",
	}

    self.floatingDock = self:CreateSingleDock{
		height = 1080 - 32 - g_dockGap,
        id = "floatingDock",
        halign = "center",
        valign = "bottom",
        floating = true,
        dragTargetPriority = 5,
    }

	local resultPanel = gui.Panel{
		theme = "DockablePanel.Main",
		width = "100%",
		height = "100%",
		valign = "center",
		halign = "center",
		flow = "none",

		self.leftDock,
		self.rightDock,
        self.floatingDock,
	}

	return resultPanel
end

local CreateDockablePanelTabbedContainer
CreateDockablePanelTabbedContainer = function(options)

	local panelInstances = options.panelInstances
    local panelSpacing = 16

	local CalculatePanelMetrics = function()
		local min = nil
		local max = nil
		for _,p in ipairs(panelInstances) do
			if min == nil or p.data.minHeight < min then
				min = p.data.minHeight
			end

			if max == nil or p.data.maxHeight > max then
				max = p.data.maxHeight
			end
		end

		local tabSpacing = 40 --cond(#panelInstances > 1, 32, 0)

		return {
			minHeight = min + tabSpacing, -- + panelSpacing*2,
			maxHeight = max + tabSpacing, -- + panelSpacing*2,
		}
	end

	local metrics = CalculatePanelMetrics()

	local dock = nil

	local resultPanel

	local beginDragY = nil
	local beginDragHeight = nil

	local CalculateCurrentY = function()
		local y = 0
		local found = false
		for _,el in ipairs(dock.data.GetChildren()) do
			if el == resultPanel then
				found = true
			end

			if not found then
				y = y + el.selfStyle.height
			end
		end
		return y
	end

	local CalculateBestDragPosition = function(targetDock, children, yoffset, forceResult)

        if targetDock.data.floating then
            return {
                index = cond(forceResult, #children+1, #children),
                tab = false,
            }
            
        end

		local y = beginDragY + yoffset + resultPanel.data.startDragHeight/2

		local items = {}
		for i,child in ipairs(children) do
			if child ~= resultPanel then
				items[#items+1] = child
			end
		end

		local bestIndex = nil
		local bestDelta = nil
		local jointab = false

		local ypos = 0
		for i=1,#items+2 do
			local delta = math.abs(y - ypos)

			if delta < resultPanel.data.startDragHeight or forceResult then --only consider anything which we are actually overlapping.
				if bestDelta == nil or delta < bestDelta then
					bestIndex = i
					bestDelta = delta
					jointab = false
				end
			end

			local item = items[i] or items[i-1]

			if item ~= nil then
				--consider dragging onto this item instead of between items, to make tabs.
				ypos = ypos + item.data.startDragHeight/2
				local delta = math.abs(y - ypos)
				if delta < resultPanel.data.startDragHeight or forceResult then --only consider anything which we are actually overlapping.
					if bestDelta == nil or delta < bestDelta then
						bestIndex = i
						bestDelta = delta
						jointab = true
					end
				end


				ypos = ypos + item.data.startDragHeight/2
			end
		end

		if bestIndex == nil then
			return nil
		else
			return {
				index = bestIndex,
				tab = jointab,
			}
		end

	end

	local dragGhost = gui.Panel{
		idprefix = "dragGhost",
		classes = {"dockablePanel", "dragGhost"},
        valign = "top",
        halign = "left",
		draggable = true,
		floating = true,
		monitor = "uilocked",
		canDragOnto = function(element, target)
			return target:HasClass("dock")
		end,
		events = {
			create = function(element)
				element:FireEvent("monitor")
			end,
			monitor = function(element)
				element.interactable = not dmhub.GetSettingValue("uilocked")
			end,

			click = function(element)
				element.popup = nil

				local selectedIndex = resultPanel.data.GetSelectedTabIndex()
				if selectedIndex ~= nil then
					panelInstances[selectedIndex]:FireEventTree("clickpanel")
				end

                if dock ~= nil and dock.data.floating then
                    resultPanel:SetAsLastSibling()
                end
			end,

			rightClick = function(element)
				element.popup = gui.ContextMenu{
					halign = "right",
					valign = "bottom",
					entries = {
						{
							text = "Close",
							click = function()

								element.popup = nil
								resultPanel:DestroySelf()
								dock:FireEvent("fitChildren")
								dock:FireEvent("layoutChanged")
								DockablePanel.Serialize()
							end,
						},
					}
				}
			end,

			beginDrag = function(element)
				dock.root:FireEventTree("beginDragDockablePanel")
				beginDragY = CalculateCurrentY()
				beginDragHeight = resultPanel.selfStyle.height
			end,

			drag = function(element, target)
				dock.root:FireEventTree("endDragDockablePanel")

				if target == nil or resultPanel:HasClass("collapsed") then
					resultPanel:DestroySelf()
					dock:FireEvent("fitChildren")
                elseif dock.data.floating then
                    local pos = element.positionInScreenSpace
                    local xstretch = 0 --(dmhub.screenDimensions.x/dmhub.screenDimensions.y)/(1920/1080)

                    local xadjustment = xstretch*(1920*dmhub.screenDimensions.y/1080-1920)*0.5
                    resultPanel.x = xadjustment + pos.x - DockablePanel.DockWidth*1 - DockablePanel.FloatingDockMargin/2 - resultPanel.renderedWidth/2
                    resultPanel.y = 1080-pos.y-element.renderedHeight/2-32
				end

				DockablePanel.Serialize()
			end,

			dragging = function(element, target)
				if target == nil then
					element:SetClass("deleting", true)
					return
				end

				element:SetClass("deleting", false)

				local bestDrag = CalculateBestDragPosition(target, target.data.childrenAtDragStart, element.dragDelta.y, target ~= dock)
				if bestDrag == nil then
					--we don't have a new good position so just abort.
					return
				end

				--dragging to a new dock, add to that dock.
				if target ~= dock then
					dmhub.Debug("MOVE TARGET")
					resultPanel:Unparent()
					dock:FireEvent("fitChildren")
					dock:FireEvent("layoutChanged")

		            resultPanel.selfStyle.width = DockablePanel.DockWidth
					resultPanel.selfStyle.height = beginDragHeight
					resultPanel:FireEvent("dock", target)
					target:FireEvent("addPanelNoSize", resultPanel)

					target:FireEvent("sizeChild", resultPanel, dock.data.DockHeight/#dock.data.GetChildren())
					target:FireEventTree("layoutChanged")

                    if not target.data.floating then
                        resultPanel.x = 0
                        resultPanel.y = 0
                    end
				end

                element:SetClass("floatingTarget", target.data.floating)

                if target.data.floating then
                    local pos = element.positionInScreenSpace
                    local xstretch = 0 --(dmhub.screenDimensions.x/dmhub.screenDimensions.y)/(1920/1080)

                    local xadjustment = xstretch*(1920*dmhub.screenDimensions.y/1080-1920)*0.5
                    resultPanel.x = xadjustment + pos.x - DockablePanel.DockWidth*1 - DockablePanel.FloatingDockMargin/2 - resultPanel.renderedWidth/2
                    resultPanel.y = 1080-pos.y-element.renderedHeight/2-32
                end


				local needsDemerge = (resultPanel.data.demerge ~= nil)

				--if bestDrag.tab ~= (resultPanel.data.mergedWith ~= nil) and needsDemerge then
				--	resultPanel.data.demerge()
				--end

				local currentIndex = -1
				local ourPanel = resultPanel.data.mergedWith or resultPanel
				for index,child in ipairs(dock.data.GetChildren()) do
					if child == ourPanel then
						currentIndex = index
					end
				end

				if bestDrag.index ~= currentIndex or (bestDrag.tab ~= (resultPanel.data.mergedWith ~= nil)) then
					
					if resultPanel.data.demerge ~= nil then
						resultPanel.data.demerge()
					end

					if bestDrag.tab then
						if dock ~= nil and (not dock.data.floating) and dock.data.childrenAtDragStart[bestDrag.index] ~= nil then
							dock.data.childrenAtDragStart[bestDrag.index]:FireEvent("merge", resultPanel)
						end
					else

						local children = {}
						for _,child in ipairs(dock.data.childrenAtDragStart) do
							if child ~= resultPanel then
								children[#children+1] = child
							end
						end

						if bestDrag.index > #children+1 then
							bestDrag.index = #children+1
						end

                        if bestDrag.index < 1 then
                            bestDrag.index = 1
                        end
					
						table.insert(children, bestDrag.index, resultPanel)
						dock.data.SetChildren(children)
					end
				end

				dock:FireEvent("fitChildren")
				dock:FireEvent("layoutChanged")
			end,
		},
	}

	local contentPanel
	local tabPanel

	local verticalDragHandle = gui.Panel{
		classes = {"verticalDragInvisibleHandle"},

		hoverCursor = "vertical-expand",
		floating = true,
		draggable = true,
		dragBounds = {y1 = -4096, y2 = 4096, x1 = 0, x2 = 0},
		monitor = "uilocked",

		events = {
			create = function(element)
				element:FireEvent("monitor")
			end,
			monitor = function(element)
				element.interactable = not dmhub.GetSettingValue("uilocked")
			end,

			beginDrag = function(element)
				dock:FireEvent("beginVerticalResizing", resultPanel)
			end,
			dragging = function(element)
				dock:FireEvent("verticalSizeChild", element.dragDelta.y)
			end,
			drag = function(element)
				--finished dragging so serialize the new sizes.
				DockablePanel.Serialize()
			end,
			draggable = function(element, isdraggable)
				element:SetClass("collapsed", not isdraggable)
			end,

			--if we have a tab, this gets shoved down.
			updatetabs = function(element)
				element:SetClass("tabs", #panelInstances > 1)
			end

		}
	}

	local verticalDragDivider = gui.Panel{
		classes = {"verticalDragDivider"},
		floating = true,
		interactable = false,
		draggable = function(element, isdraggable)
			element:SetClass("collapsed", not isdraggable)
		end,

		--if we have a tab, this gets shoved down.
		updatetabs = function(element)
			element:SetClass("tabs", #panelInstances > 1)
		end
	}

	local CreateTab = function(p)
		local DetachPanelInstance = function(element)
			if #panelInstances == 1 then
				local result = panelInstances[1]
				result:Unparent()
				resultPanel:DestroySelf()

				dock:FireEvent("fitChildren")
				dock:FireEvent("layoutChanged")
				return result

			else
				local wasSelected = element:HasClass("selected")
				local parent = element.parent

				local index = nil
				for i,panel in ipairs(panelInstances) do
					if p == panel then
						index = i
					end
				end

				local result = nil

				if index ~= nil then
					result = panelInstances[index]
					result:Unparent()
					element:DestroySelf()
					table.remove(panelInstances, index)
				end

				if wasSelected then
					parent.children[1]:FireEvent("click")
				end

				resultPanel:FireEventTree("updatetabs")
				return result
			end
		end

		local button
        local label
		local buttonContainer

		local dockInfo = dockablePanels[p.data.identifier]

		local newContentMarker = nil
		if dockInfo.hasNewContent ~= nil and dockInfo.hasNewContent() then
			newContentMarker = gui.NewContentAlert{
				x = 0,
				valign = "top",
			}
		end

		button = gui.Panel{
			classes = {"tab"},
			id = string.format("TabIcon%s", p.data.name),
		    bgimage = p.data.icon,
            numTabs = function(element, n)
                element.interactable = n > 1
            end,

			newContentMarker,

			moduleInstalled = function(element)
				if dockInfo.hasNewContent ~= nil and dockInfo.hasNewContent() then
					if newContentMarker == nil then
						newContentMarker = gui.NewContentAlert{
							x = 0,
							valign = "top",
						}
						element:AddChild(newContentMarker)
					end
				elseif newContentMarker ~= nil then
					newContentMarker:DestroySelf()
					newContentMarker = nil
				end
			end,


			events = {

			},
		}

        label = gui.Label{
            classes = {"tabLabel"},
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 4,
            text = p.data.name,
            textOverflow = "truncate",
            textWrap = false,
            fontSize = 14,

            numTabs = function(element, n)
                element.interactable = n > 1
            end,

            availableWidth = function(element, width)
                element.selfStyle.maxWidth = width
            end,
        }

		buttonContainer = gui.Panel{
            classes = {"buttonContainer"},
			width = "auto",
			height = "100%",
            flow = "horizontal",
            valign = "center",
            hmargin = 0,
            hpad = 4,
			dragTarget = true,
			draggable = true,
			dragBounds = { x1 = -32*8, y1 = 0, x2 = 32*8, y2 = 0 },
            numTabs = function(element, n)
                element.interactable = n > 1
            end,

			hover = gui.Tooltip{
				text = p.data.name,
				valign = "top",
			},


			select = function(element)
				for _,b in ipairs(tabPanel.children) do
					b:SetClassTree("selected", b == buttonContainer)
				end

				for _,panel in ipairs(p.parent.children) do
					local val = (panel ~= p)
					if (not val) or val ~= panel:HasClass("collapsed") then
						panel:SetClass("collapsed", panel ~= p)
						if val then
							panel:FireEventTree("hidepanel")
						else
							panel:FireEventTree("showpanel")
						end
					end
				end
			end,


			canDragOnto = function(element, target)
				return target.parent == tabPanel
			end,

			dragging = function(element, target)
				if target == nil or target == buttonContainer then
					return
				end

				local i1 = nil
				local i2 = nil

				for i,button in ipairs(tabPanel.children) do
					if button == buttonContainer then
						i1 = i
					elseif button == target then
						i2 = i
					end
				end

				if i1 ~= nil and i2 ~= nil then
					local tmp = panelInstances[i1]
					panelInstances[i1] = panelInstances[i2]
					panelInstances[i2] = tmp
					contentPanel.children = panelInstances
					
					local tabs = tabPanel.children
					tmp = tabs[i1]
					tabs[i1] = tabs[i2]
					tabs[i2] = tmp
					tabPanel.children = tabs

					DockablePanel.Serialize()
				end
			end,


			closeByIdentifier = function(element, identifier)

				if p.data.identifier == identifier then
					element:FireEvent("close")
				end
			end,

			showByIdentifier = function(element, identifier)
				if p.data.identifier == identifier then
					element:FireEvent("press")
				end
			end,

			close = function(element)
				local panelInstance = DetachPanelInstance(element)
				if panelInstance ~= nil then
					panelInstance:DestroySelf()
					DockablePanel.Serialize()
				end
			end,

			press = function(element)
				element:FireEvent("select")
				DockablePanel.Serialize()
			end,
			rightClick = function(element)
				element.popup = gui.ContextMenu{
					halign = "right",
					valign = "bottom",
					entries = {
						{
							text = "Close",
							click = function()
								element.popup = nil
								element:FireEvent("close")
							end,
						},
						{
							text = "Detach",
							click = function()
								element.popup = nil
								local panelInstance = DetachPanelInstance(element)
								if panelInstance ~= nil then
									local newPanel = CreateDockablePanelTabbedContainer{
										panelInstances = {panelInstance},
									}

									dock:FireEvent("addPanel", newPanel)
									DockablePanel.Serialize()
								end
							end,
						},
					},
				}
			end,
			button,
            label,
		}

		return buttonContainer
	end

    local collapseArrow = gui.CollapseArrow{
        styles = {
            gui.Style{
                selectors = {"single"},
                collapsed = 1,
            },
        },
        width = 18,
        height = 12,
        halign = "right",
        valign = "top",
        hmargin = 6,
        vmargin = 12,
        floating = true,
        press = function(element)
            element:SetClass("collapseSet", not element:HasClass("collapseSet"))
            if element:HasClass("collapseSet") then
                element:FireEventOnParents("maximizeChild", element)
            else
                element:FireEventOnParents("minimizeChild", element)
            end
        end,
    }

	local tabs = {}

	for _,p in ipairs(panelInstances) do
		tabs[#tabs+1] = CreateTab(p)
	end

	tabPanel = gui.Panel{
		classes = {"tabContainer"},
		height = 32,
		hpad = 0,
        tmargin = 1,
        interactable = false,
		width = "100%",
		flow = "horizontal",
		children = tabs,
		updatetabs = function(element)
			--element:SetClass("collapsed", #element.children <= 1)
            local numChildren = #element.children
            element:FireEventTree("numTabs", numChildren)
            element:SetClassTree("mono", numChildren <= 1)
            element:SetClassTree("crowded", numChildren >= 3)
			metrics = CalculatePanelMetrics()
			resultPanel.data.minHeight = metrics.minHeight
			resultPanel.data.maxHeight = metrics.maxHeight

            local availableWidth = 350
            local tabBaseWidth = 28
            local availableWidth = math.max(0, availableWidth - tabBaseWidth*#element.children)
            element:FireEventTree("availableWidth", availableWidth)
		end,
	}

	contentPanel = gui.Panel{
		idprefix = "contentPanel",
        valign = "center",
        halign = "center",
		height = "100%-32",
		width = "100%",
		children = panelInstances,
		updatetabs = function(element)
			element.selfStyle.height = "100%-32"
		end,
	}

    local m_baseWidth = 0
    local m_baseHeight = 0

    local dragHandle = gui.Panel{
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        width = 32,
        height = 32,
        halign = "right",
        valign = "bottom",
        hoverCursor = "diagonal-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        thinkTime = 1.0,
        think = function(element)
            if not element.dragging then
                m_baseWidth = resultPanel.selfStyle.width
                m_baseHeight = resultPanel.selfStyle.height
            end
        end,
        draggable = true,
        drag = function(element)
            m_baseWidth = resultPanel.selfStyle.width
            m_baseHeight = resultPanel.selfStyle.height
        end,
        dragging = function(element)
            resultPanel.selfStyle.width = math.max(DockablePanel.DockWidth, m_baseWidth + element.dragDelta.x)
            resultPanel.selfStyle.height = math.max(100, m_baseHeight + element.dragDelta.y)
        end,
    }


	resultPanel = gui.Panel{
		idprefix = "dockablePanelContainer",
		classes = {"dockablePanelContainer"},
		width = DockablePanel.DockWidth,
        halign = "center",
		selfStyle = {
			height = 0,
		},

		data = {
			maximized = false,
			minHeight = metrics.minHeight,
			maxHeight = metrics.maxHeight,
			locked = false,

			GetPanelInstances = function()
				return panelInstances
			end,

			GetSelectedTabIndex = function()
				for i,tab in ipairs(tabPanel.children) do
					if tab:HasClass("selected") then
						return i
					end
				end

				return nil
			end,

			SelectTabIndex = function(index)
				local tab = tabPanel.children[index]
				if tab ~= nil then
					tab:FireEvent("select")
				end
			end,

			PillagePanelInstances = function()
				local result = panelInstances
				panelInstances = {}

				for _,p in ipairs(result) do
					p:Unparent()
				end
				tabPanel.children = {}
				resultPanel:SetClass("collapsed", true)
				return result
			end,

			RestorePanelInstances = function(panels)
				panelInstances = panels
				contentPanel.children = panelInstances

				local tabs = {}
				for _,p in ipairs(panelInstances) do
					tabs[#tabs+1] = CreateTab(p)
				end

				tabPanel.children = tabs
				resultPanel:SetClass("collapsed", false)
			end,

			GetDock = function()
				return dock
			end,

			--function which will undo the merge which collapsed us.
			demerge = nil,

			--the panel we are currently merged with, or nil if we aren't currently merged.
			--merged is just a temporary state while dragging.
			mergedWith = nil,
		},

        deserialize = function(element, data)
            if data.x then
                element.x = data.x
            end
            if data.y then
                element.y = data.y
            end
            if data.width then
                element.selfStyle.width = data.width
            end

            if data.height then
                element.selfStyle.height = data.height
            end
        end,

        minimizeFloating = function(element)
            if element.data.rememberMaximize == nil then
                return
            end

            element.x = element.data.rememberMaximize.x
            element.y = element.data.rememberMaximize.y
            element.selfStyle.width = element.data.rememberMaximize.width
            element.selfStyle.height = element.data.rememberMaximize.height

            element.data.rememberMaximize = nil
            element:SetAsLastSibling()
        end,

        maximizeFloating = function(element)
            element.data.rememberMaximize = {
                x = element.x,
                y = element.y,
                width = element.selfStyle.width,
                height = element.selfStyle.height,
            }
            element.x = -DockablePanel.FloatingDockMargin/2
            element.y = 0 
            element.selfStyle.width = dock.renderedWidth + DockablePanel.FloatingDockMargin
            element.selfStyle.height = dock.renderedHeight
            element:SetAsLastSibling()
        end,

		dock = function(element, newDock)
			dock = newDock

            local floating = dock.data.floating
            if floating then
                element.selfStyle.halign = "left"
                element.selfStyle.valign = "top"
                dragHandle.selfStyle.hidden = false
                dragGhost:SetClass("floatingTarget", true)
            else
                element.x = 0
                element.y = 0
                element.selfStyle.halign = "center"
                element.selfStyle.valign = "top"
                dragHandle.selfStyle.hidden = true
                dragGhost:SetClass("floatingTarget", false)
            end
            print("DOCK::", dock.id)
		end,

		merge = function(element, other)
			if other == element then
				return
			end

			if other.data.mergedWith == element then
				return
			end

			if other.data.demerge ~= nil then
				other.data.demerge()
			end

			local tabs = tabPanel.children

			element.data.tabIndexSelectedBeforePillage = element.data.GetSelectedTabIndex()
			other.data.tabIndexSelectedBeforePillage = other.data.GetSelectedTabIndex()

			local tabSelectedIndex = nil
			if other.data.tabIndexSelectedBeforePillage ~= nil then
				tabSelectedIndex = #tabPanel.children + other.data.tabIndexSelectedBeforePillage
			end
			
			local newTabs = {}

			local pillagedInstances = other.data.PillagePanelInstances()
			for _,instance in ipairs(pillagedInstances) do
				panelInstances[#panelInstances+1] = instance
				local newTab = CreateTab(instance)
				tabs[#tabs+1] = newTab
				newTabs[#newTabs+1] = newTab
			end

			contentPanel.children = panelInstances
			tabPanel.children = tabs

			if tabSelectedIndex ~= nil then
				tabPanel.children[tabSelectedIndex]:FireEvent("select")
			end

			resultPanel:FireEventTree("updatetabs")

			other.data.mergedWith = element
			other.data.demerge = function()
				--filter tabs back to what they were before the merge.
				local tabs = tabPanel.children
				local tabsFiltered = {}
				for _,tab in ipairs(tabs) do
					local found = false
					for _,newTab in ipairs(newTabs) do
						if newTab == tab then
							found = true
						end
					end

					if not found then
						tabsFiltered[#tabsFiltered+1] = tab
					end
				end

				tabPanel.children = tabsFiltered

				--filter panels back to what they were before the merge
				for _,pillaged in ipairs(pillagedInstances) do
					pillaged:Unparent()
				end

				panelInstances = contentPanel.children

				other.data.RestorePanelInstances(pillagedInstances)
				other.data.demerge = nil
				other.data.mergedWith = nil

				element.data.GetDock():FireEvent("fitChildren")
				if other.data.GetDock() ~= element.data.GetDock() then
					other.data.GetDock():FireEvent("fitChildren")
				end

				if element.data.tabIndexSelectedBeforePillage ~= nil then
					element.data.SelectTabIndex(element.data.tabIndexSelectedBeforePillage)
				end

				if other.data.tabIndexSelectedBeforePillage ~= nil then
					other.data.SelectTabIndex(other.data.tabIndexSelectedBeforePillage)
				end

				element.data.tabIndexSelectedBeforePillage = nil
				other.data.tabIndexSelectedBeforePillage = nil

				element:FireEventTree("updatetabs")
				other:FireEventTree("updatetabs")
			end


			element.data.GetDock():FireEvent("fitChildren")
			if other.data.GetDock() ~= element.data.GetDock() then
				other.data.GetDock():FireEvent("fitChildren")
			end
		end,

        gui.Panel{
            bgimage = true,
            bgcolor = "#222222e9",
            flow = "vertical",
            height = string.format("100%%-%d", round(g_dockGap + cond(g_dockGap == 0, -1, 0))),
            width = "100%",
            borderColor = Styles.Gold02,
            border = {x1 = 0, x2 = 0, y1 = 1, y2 = 0},

            dragGhost,
            verticalDragHandle,
            verticalDragDivider,
            tabPanel,
            collapseArrow,
            contentPanel,
        },
        dragHandle,
	}

	local tab = tabs[options.selectedTab or 1]
	if tab == nil then
		tab = tabs[1]
	end

	tab:FireEvent("select")
	resultPanel:FireEventTree("updatetabs")

	return resultPanel
end



local CreateDockablePanelInstance = function(panelOptions)

	local options = panelOptions

	local resultPanel

	resultPanel = gui.Panel{  --gui.Canvas
		idprefix = "dockablePanelInstance",
		classes = {"dockablePanel", "collapsed"},
		interactable = false,
		flow = "vertical",

		init = function(element)

			element.data = {
				guid = options.guid,
				name = options.name,
				icon = options.icon,
				stickyFocus = options.stickyFocus,
				identifier = options.identifier,
				minHeight = (options.minHeight or 40),
				maxHeight = (options.maxHeight or 1080),
				locked = false,
			}

			if options.vscroll ~= false then
				local hideObjectsOutOfScroll = options.hideObjectsOutOfScroll
				if hideObjectsOutOfScroll == nil then
					hideObjectsOutOfScroll = true
				end
				element.children = {
					gui.Panel{
						idprefix = "dockablePanelScrollParent",
						interactable = false,
						width = "100%",
						height = "100%",
						pad = 2,
						vscroll = true,
						hideObjectsOutOfScroll = hideObjectsOutOfScroll,
						children = {
							options.content(),
						},
					}
				}
			else
				element.children = {
					gui.Panel{
						width = "100%",
						halign = "center",
                        hmargin = 0,
                        hpad = 0,
						idprefix = "dockablePanelNoScrollParent",
						height = "100%",
						children = {
							options.content()
						}
					}
				}
			end
		end,

		monitorMod = options.modid,
		refreshMod = function(element)
			--check if this panel's info has been updated, in which case we re-initialize the panel.
			local info = dockablePanels[options.identifier]
			if info ~= nil and info.guid ~= options.guid then
				options = info
				element:FireEvent("init")
			end
		end,
	}

	resultPanel:FireEvent("init")

	return resultPanel
end





DockablePanel = {}

DockablePanel = {
	ContentWidth = 364,
	DockWidth = 364,
    FloatingDockMargin = 100,

	Register = function(args)
		if args.dmonly and not dmhub.isDM then
			return
		end
		
		local guid = dmhub.GenerateGuid()

		local panelInfo = DeepCopy(args)
		local modLoading = dmhub.GetModLoading()
		if modLoading ~= nil then
			panelInfo.modid = modLoading.modid
		end
		panelInfo.guid = guid

		panelInfo.identifier = string.format("%s-%s", panelInfo.modid or "CORE", panelInfo.name)

		--if there is an existing panel with the same name we prefer to overwrite it.
		for k,v in pairs(dockablePanels) do
			if v.name == args.name then
				panelInfo.identifier = v.identifier
			end
		end

		dockablePanels[panelInfo.identifier] = panelInfo
	end,

	Deregister = function(name)
		for k,v in pairs(dockablePanels) do
			if v.name == name then
				dockablePanels[k] = nil
				return
			end
		end
	end,

	GetMenuItems = function(flat)
		local subfolders = {}
		local result = {}
		for k,p in pairs(dockablePanels) do

			local available = (not p.devonly) or devmode()

			if available then

				local instance = DockablePanel.FindInstance(p.identifier)

				local target = result

				if (not flat) and p.folder ~= nil then
					local folder = subfolders[p.folder]

					if folder == nil then
						folder = {}
						target[#target+1] = {
							id = string.format("Folder%s", p.folder),
							text = p.folder,
							submenu = folder,
						}
						subfolders[p.folder] = folder
					end

					target = folder
				end

				local bind = dmhub.GetCommandBinding(string.format("togglepanel %s", string.lower(p.name)))

				target[#target+1] = {
					id = string.format("Menu%s", p.name),
					text = p.name,
					icon = p.icon,
					bind = bind,
					check =  instance ~= nil and instance.enabled,
                    
                    ---@param operation nil|'toggle'|'show'|'hide'
					click = function(operation)
						local uilocked = dmhub.GetSettingValue("uilocked")

						local instance = nil
					
						if not p.multipleInstances then
							instance = DockablePanel.FindInstance(p.identifier)
						end

						if instance ~= nil then

							--if not shown then we raise it, otherwise we close it.
							local eventName = cond(instance.enabled and (not uilocked), "closeByIdentifier", "showByIdentifier")
                            if instance.enabled and operation == "show" then
                                return
                            end

                            if (not instance.enabled) and operation == "hide" then
                                return
                            end
							for _,dock in ipairs({gamehud.leftDock, gamehud.rightDock, gamehud.floatingDock}) do
								dock:FireEventTree(eventName, p.identifier)
							end

						else
							if uilocked then
								--cannot open a panel if it's locked.
								return
							end

                            if operation == "hide" then
                                return
                            end

							local newPanel = CreateDockablePanelTabbedContainer{
								panelInstances = {CreateDockablePanelInstance(p)},
							}

							local targetDock = gamehud.leftDock

							if dmhub.GetSettingValue("leftdockoffscreen") and not dmhub.GetSettingValue("rightdockoffscreen") then
								targetDock = gamehud.rightDock
							elseif dmhub.GetSettingValue("leftdockoffscreen") then
								dmhub.SetSettingValue("leftdockoffscreen", false)
							end

							targetDock:FireEvent("addPanel", newPanel)
						end

						DockablePanel.Serialize()
					end,
				}
			end
		end

		for _,item in ipairs(result) do
			if item.submenu ~= nil then
				table.sort(item.submenu, function(a,b) return a.text < b.text end)
			end
		end

		table.sort(result, function(a,b)
			local asub = a.submenu ~= nil
			local bsub = b.submenu ~= nil
			if asub ~= bsub then
				return bsub
			end

			return a.text < b.text
		end)
		return result
	end,

    --- @param str string
    --- @param operation nil|'toggle'|'show'|'hide'
	LaunchPanelByName = function(str, operation)
		str = string.lower(str)
		local items = DockablePanel.GetMenuItems(true)
		for _,item in ipairs(items) do
			if item.text ~= nil and string.lower(item.text) == str then
				item.click(operation)
				return true
			end
		end

		return false
	end,


	FindInstance = function(identifier)
        if rawget(gamehud,"leftDock") == nil then
            return nil
        end
		for _,dock in ipairs({gamehud.leftDock, gamehud.rightDock, gamehud.floatingDock}) do
			for _,child in ipairs(dock.data.GetChildren()) do
				for _,instance in ipairs(child.data.GetPanelInstances()) do
					if instance.data.identifier == identifier then
						return instance
					end
				end
			end
		end

		return nil
	end,

	GetAllInstancesByIdentifier = function()
		local result = {}

		for _,dock in ipairs(gamehud:Docks()) do
			for _,child in ipairs(dock.data.GetChildren()) do
				for _,instance in ipairs(child.data.GetPanelInstances()) do
					if instance.data.identifier ~= nil then
						result[instance.data.identifier] = instance
					end
				end
			end
		end

		return result
	end,

	Serialize = function()
		local doc = {docks = {}}
		for _,dock in ipairs(gamehud:Docks()) do
			local panels = {}

			for _,child in ipairs(dock.data.GetChildren()) do
				local panel = {
					height = child.selfStyle.height,
					tabs = {},
					selected = child.data.GetSelectedTabIndex(),
				}

                if dock == gamehud.floatingDock then
                    panel.x = child.x
                    panel.y = child.y
                    panel.width = child.selfStyle.width
                    panel.height = child.selfStyle.height
                end

				for _,instance in ipairs(child.data.GetPanelInstances()) do
					panel.tabs[#panel.tabs+1] = instance.data.identifier
				end

				panels[#panels+1] = panel
			end

			doc.docks[#doc.docks+1] = {
				panels = panels,
			}
		end

		SetPanelsConfig(doc)
	end,

	Deserialize = function()
		local doc = GetPanelsConfig()

		local existingInstances = DockablePanel.GetAllInstancesByIdentifier()

		for i,dock in ipairs(gamehud:Docks()) do

			dock:FireEvent("clearPanels")
			local dockInfo = doc.docks[i]
			if dockInfo ~= nil then
				local panelsAdded = {}
				for _,panelInfo in ipairs(dockInfo.panels) do
					
					local panelInstances = {}

					--try to find the panel with this identifier and create it.
					
					for _,panelid in ipairs(panelInfo.tabs) do
					
						if existingInstances[panelid] ~= nil then
							panelInstances[#panelInstances+1] = existingInstances[panelid]
							existingInstances[panelid] = nil
						else
							for k,p in pairs(dockablePanels) do
								if p.identifier == panelid then
									panelInstances[#panelInstances+1] = CreateDockablePanelInstance(p)
								end
							end
						end
					end


					if #panelInstances > 0 then
						local newPanel = CreateDockablePanelTabbedContainer{
							panelInstances = panelInstances,
							selectedTab = panelInfo.selected,
						}

                        newPanel:FireEvent("deserialize", panelInfo)

						dock:FireEvent("addPanelNoSize", newPanel)

						panelsAdded[#panelsAdded+1] = panelInfo
					end
				end

				--now set the preferred heights.
				for i,child in ipairs(dock.data.GetChildren()) do
					child.selfStyle.height = panelsAdded[i].height
				end

				--make sure we do fit after deserialize
				dock:FireEvent("fitChildren")
				dock:FireEventTree("layoutChanged")
			end
		end

		for _,oldInstance in pairs(existingInstances) do
			oldInstance:DestroySelf()
		end
	end,
}

--called by dmhub to init dockable panels.
function InitDockablePanels()
	DockablePanel.Deserialize()
end

dmhub.RegisterOnUnloadModFunction(function(modid)
	local deleteGuids = {}

	for k,p in pairs(dockablePanels) do
		if p.modid == modid then
			deleteGuids[#deleteGuids+1] = k
		end
	end

	for _,k in ipairs(deleteGuids) do
		dockablePanels[k] = nil
	end
end)
