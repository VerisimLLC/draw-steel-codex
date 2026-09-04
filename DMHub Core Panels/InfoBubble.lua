local mod = dmhub.GetModLoading()

RegisterGameType("InfoBubble")

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
	}
}

--DMHub calls this when it wants to create an info bubble.
function CreateInfoBubble(info)
	local eventHandler = nil
	local showingTip = false
	info.sheet.sheet = gui.Panel{
		classes = {cond(info.floorid == game.currentFloorId, "currentFloor")},
		interactable = info.floorid == game.currentFloorId,
		bgimage = 'panels/square.png',
		styles = styles,
		--blocksGameInteraction = false,

		create = function(element)
			eventHandler = dmhub.RegisterEventHandler("ChangeCurrentFloor", function() element.interactable = info.floorid == game.currentFloorId; element:SetClass("currentFloor", info.floorid == game.currentFloorId) end)
		end,

		destroy = function(element)
			dmhub.DeregisterEventHandler(eventHandler)
		end,

		children = {
			gui.Label{
				interactable = false,
				blocksGameInteraction = false,
				text = info.icon,
				selfStyle = {
					width = "auto",
					height = "auto",
				},
				events = {
					refreshBubble = function(element)
						element.text = info.icon
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
				element.popup = gui.ContextMenu{
					entries = {
						{
							text = "Delete",
							click = function()
								element.popup = nil
								info:Delete()
							end,
						}
					},
				}
			end,
		},
	}
end