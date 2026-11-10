local mod = dmhub.GetModLoading()

--- @class InfoBubble: GameType
--- @field new fun(o?: table): InfoBubble
InfoBubble = RegisterGameType("InfoBubble")

local styles = {
	{
		bgcolor = 'black',
		color = "white",
		cornerRadius = "50% height",
		borderColor = "white",
		borderWidth = 2,
		width = 50,
		height = 50,
		fontSize = 26,
		halign = "center",
		valign = "center",
		textAlignment = "center",
	},
	{
		selectors = {"parent:hover", "parent:currentFloor"},
		color = "yellow",
		borderColor = "yellow",
	},
	{
		selectors = {"hover", "currentFloor"},
		color = "yellow",
		borderColor = "yellow",
	},
	{
		selectors = {"parent:press", "parent:currentFloor"},
		color = "orange",
		borderColor = "orange",
	},
	{
		selectors = {"press", "currentFloor"},
		color = "orange",
		borderColor = "orange",
	},
	{
		transitionTime = 0.4,
		selectors = {"~currentFloor"},
		bgcolor = "#333333",
	},
	{
		transitionTime = 0.4,
		selectors = {"~parent:currentFloor"},
		opacity = 0.4,
	},

	--a bubble with a custom image (info.image) shows just the picture, lit up on hover.
	{
		selectors = {"imageBubble"},
		bgcolor = "white",
		borderWidth = 0,
		cornerRadius = 0,
	},
	{
		selectors = {"imageBubble", "hover", "currentFloor"},
		brightness = 1.25,
	},
	{
		selectors = {"imageBubble", "press", "currentFloor"},
		brightness = 0.85,
	},
	{
		transitionTime = 0.4,
		selectors = {"imageBubble", "~currentFloor"},
		bgcolor = "white",
		opacity = 0.4,
	},
}

--Size in gui units of a bubble's custom image: the bubble canvas has 100 units
--per tile, and a 0 width or height copies the other (both 0 = 1 tile).
local function ImageBubbleSize(info)
	local w = info.width
	local h = info.height
	if w <= 0 then w = h end
	if h <= 0 then h = w end
	if w <= 0 then
		w = 1
		h = 1
	end
	return w*100, h*100
end

--Shows the bubble as its custom image, or as the round icon badge when it has none.
local function ApplyBubbleLook(element, info)
	local image = info.image
	element:SetClass("imageBubble", image ~= nil)
	if image ~= nil then
		local w, h = ImageBubbleSize(info)
		element.bgimage = image
		element.selfStyle.width = w
		element.selfStyle.height = h
	else
		element.bgimage = 'panels/square.png'
		element.selfStyle.width = 50
		element.selfStyle.height = 50
	end
end

--DMHub calls this when it wants to create an info bubble.
function CreateInfoBubble(info)
	local eventHandler = nil
	local showingTip = false
	info.sheet.sheet = gui.Panel{
		classes = {cond(info.floorid == game.currentFloorId, "currentFloor")},
		interactable = info.floorid == game.currentFloorId,
		bgimage = 'panels/square.png',
		styles = styles,
		inworld = true,
		--blocksGameInteraction = false,

		create = function(element)
			ApplyBubbleLook(element, info)
			eventHandler = dmhub.RegisterEventHandler("ChangeCurrentFloor", function() element.interactable = info.floorid == game.currentFloorId; element:SetClass("currentFloor", info.floorid == game.currentFloorId) end)
		end,

		refreshBubble = function(element)
			ApplyBubbleLook(element, info)
		end,

		destroy = function(element)
			dmhub.DeregisterEventHandler(eventHandler)
		end,

		children = {
			gui.Label{
				interactable = false,
				blocksGameInteraction = false,
				text = cond(info.image == nil, info.icon, ""),
				selfStyle = {
					width = "auto",
					height = "auto",
				},
				events = {
					refreshBubble = function(element)
						--an image bubble's picture is its whole face: no icon text over it.
						element.text = cond(info.image == nil, info.icon, "")
					end,
				},
			}
		},

		events = {
			linger = function(element)
				if gamehud ~= nil and not gamehud:IsDocumentDialogOpen() and not element.popup then
					gamehud:ShowInfoBubbleTip(info)
					showingTip = true
				end
			end,
			dehover = function(element)
				if gamehud ~= nil and showingTip then
					gamehud:HideInfoBubbleTip(info)
					showingTip = false
				end
			end,

			press = function(element)
				if not element:HasClass("currentFloor") then
					return
				end

				--players may be able to see bubbles (map setting) but never move them.
				if not dmhub.isDM then
					return
				end

				printf("LOCKED: %s", json(info.locked))
				if not info.locked then
					info:BeginDragging()
				end
			end,

			click = function(element)
				if not element:HasClass("currentFloor") then
					return
				end

				if info.draggedRecently then
					return
				end
				dmhub.Debug('show document')
				gamehud:DisplayDocument(info)
			end,
			rightClick = function(element)
				if not element:HasClass("currentFloor") then
					return
				end

				--only the DM can delete bubbles.
				if not dmhub.isDM then
					return
				end
				dmhub.Debug('right click')
				--"Allow Dragging" is session-transient: info.locked lives on the
				--bubble's hud object, not in the saved map data, so it resets to
				--locked whenever the bubble is recreated.
				element.popup = gui.ContextMenu{
					entries = {
						{
							text = "Allow Dragging",
							check = not info.locked,
							click = function()
								element.popup = nil
								info.locked = not info.locked
							end,
						},
						{
							text = "Delete",
							click = function()
								element.popup = nil
								info:Delete()
							end,
						},
					},
				}
			end,
		},
	}
end