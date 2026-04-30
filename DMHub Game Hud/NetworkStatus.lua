local mod = dmhub.GetModLoading()

local currentOperationsTable = nil
local currentOperation = nil

--function called by dmhub whenever a 'blocking' network operation is going on.
function ShowNetworkStatus(dialog, operations)
	currentOperationsTable = operations
	local haveOperation = false
	for k,op in pairs(operations) do
		haveOperation = true
	end

	if not haveOperation then
		dialog.sheet = nil
		return
	end

	if dialog.sheet == nil then

		local progressWidget = gui.Panel{
			flow = "vertical",
			halign = "center",
			valign = "center",
			width = "100%",
			height = 128,

			gui.ProgressBar{
				width = "80%",
				height = 64,
				halign = "center",
				value = 0,
				refreshOperation = function(element, operation)
					element:FireEventTree("progress", operation.progress)
				end,
			},

			gui.Label{
				text = "Importing...",
				width = "auto",
				height = "auto",
				halign = "center",
				fontSize = 16,
				margin = 6,
				refreshOperation = function(element, operation)
					element.text = operation.status
				end,
			},
		}


		local dialogPanel = gui.Panel{
			id = "UploadDialog",
			classes = {"framedPanel"},
			width = 1200,
			height = 800,
			halign = "center",
			valign = "center",
			pad = 8,
			flow = "none",
			styles = {
				Styles.Default,
				Styles.Panel,
			},

			gui.Label{
				halign = "center",
				valign = "top",
				vmargin = 20,
				fontSize = 28,
				width = "auto",
				height = "auto",
				minHeight = 40,
				minWidth = "50%",
				textAlignment = "center",

				refreshOperation = function(element, operation)
					element.text = operation.description
				end,
			},

			progressWidget,

			gui.Label{
				halign = "center",
				valign = "top",
				vmargin = 100,
				fontSize = 28,
				color = "red",
				width = "auto",
				height = "auto",
				minWidth = "50%",
				minHeight = 40,
				textAlignment = "center",

				refreshOperation = function(element, operation)
					if operation.error == nil or operation.error == '' then
						element.text  = ""
					else
						element.text = operation.error
					end
				end,
			},

			gui.FancyButton{
				halign = "center",
				valign = "center",
				width = 200,
				height = 60,
				text = "Close",

				click = function(element)
					currentOperationsTable[currentOperation.id] = nil
					ShowNetworkStatus(dialog, currentOperationsTable)
				end,

				refreshOperation = function(element, operation)
					if operation.error == nil or operation.error == '' then
						element:SetClass("hidden", true)
					else
						element:SetClass("hidden", false)
					end
				end,
			},
		}

		dialog.sheet = gui.Panel{
			width = "100%",
			height = "100%",
			bgimage = "panels/square.png",
			bgcolor = "#000000ee",
			dialogPanel,
		}
	end

	local displayedOperation = false
	for k,op in pairs(operations) do
		if not displayedOperation then
			currentOperation = op
			dialog.sheet:FireEventTree("refreshOperation", op)
			displayedOperation = true
		end
	end
end


function GameHud:ConnectionStatusPanel()

	local eventGuid = nil

	local m_children = nil

	local resultPanel
	resultPanel = gui.Panel{
		classes = {"statusPanel", "noerror"},
		bgimage = "panels/square.png",
		bgcolor = "black",
		opacity = 0.9,
		width = 360,
		height = 160,
		halign = "left",
		valign = "top",
		hmargin = 8,
		vmargin = 8,
		cornerRadius = 12,
		interactable = false,

		styles = {
			{
				selectors = {"collapsedIfError", "connectionError"},
				collapsed = 1,
			},
			{
				selectors = {"collapsedUnlessError", "~connectionError"},
				collapsed = 1,
			},

			{
				selectors = {"statusPanel"},
			},
			{
				selectors = {"statusPanel", "noerror"},
				transitionTime = 0.2,
				y = -140,
				hidden = 1,
			},
		},

		data = {
			lastConnection = nil,
			errorStartTime = nil,
			errorShown = false,
		},

		hide = function(element)
			if element:HasClass("connectionError") == false then
				element:SetClass("noerror", true)
			end
		end,

		refreshConnectionStatus = function(element, info)
			if info == nil then
				if element.data.errorShown then
					-- Fire on recovery, not on failure: by definition the
					-- connection is healthy at this moment, so the event has
					-- the best chance of actually reaching the analytics
					-- backend. durationSeconds is the buckettable signal --
					-- short blips vs long outages tell very different stories.
					local now = os.time()
					local startedAt = element.data.errorStartTime or now
					analytics.Event{
						type = "connectionOutage",
						dailyLimit = 20,
						durationSeconds = now - startedAt,
						startedAt = startedAt,
						endedAt = now,
						lastSuccessTime = element.data.lastConnection or 0,
					}

					element:SetClassTree("connectionError", false)
					element:ScheduleEvent("hide", 1.5)
				end
				element.data.lastConnection = nil
				element.data.errorStartTime = nil
				element.data.errorShown = false
			else
				if element.data.errorStartTime == nil then
					element.data.errorStartTime = os.time()
				end

				-- Suppress the dialog for the first 3 seconds of an error so
				-- a quick reconnect (NAT rebind, brief edge close, etc.)
				-- doesn't surface a scary modal that vanishes again before
				-- the player can read it.
				if element.data.errorShown == false and os.time() - element.data.errorStartTime < 3 then
					return
				end

				element.data.errorShown = true
				element.data.lastConnection = info.lastSuccessTime

				element:SetClass("noerror", false)

				if m_children == nil then
					m_children = {
						gui.Label{
							classes = {"collapsedIfError"},
							fontSize = 16,
							fontWeight = "bold",
							width = "auto",
							height = "auto",
							halign = "center",
							valign = "center",
							text = "...and we're back!",
						},

						gui.Panel{
							classes = {"collapsedUnlessError"},
							flow = "none",
							width = "100%-16",
							height = "100%-16",
							halign  = "center",
							valign = "center",

							gui.Label{
								fontSize = 16,
								fontWeight = "bold",
								text = "Connection Error",
								width = "100%",
								height = "auto",
								valign = "top",
								halign = "left",
							},

							gui.Label{
								fontSize = 14,
								width = "100%",
								height = "auto",
								halign = "left",
								valign = "center",

								refreshConnectionStatus = function(element, info)
									if info == nil then
										return
									end

									if info.lastSuccessTime > 0 then
										element.text = "We're having trouble connecting to the DMHub servers.\nWe will try to reconnect periodically."
									else
										element.text = "Some operations are having trouble making their way to our servers."
									end
								end,
							},
						},
					}
					element.children = m_children
					element:MakeNonInteractiveRecursive()
				end

				element:SetClassTree("connectionError", true)
			end
		end,

		create = function(element)
			dmhub.RegisterEventHandler("refreshConnectionStatus", function(info)
				element:FireEventTree("refreshConnectionStatus", info)
			end)
		end,
		
		destroy = function(element)
			if eventGuid ~= nil then
				dmhub.DeregisterEventHandler(eventGuid)
			end
		end,
	}

	return resultPanel
end