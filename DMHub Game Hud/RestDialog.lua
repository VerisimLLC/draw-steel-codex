local mod = dmhub.GetModLoading()

--This file implements resting, including the dialog and communication for resting.

--A RestRequestToken instance has the following fields:
-- complete = bool
RegisterGameType("RestRequestToken")

--A RestRequest instance has the following fields:
-- type = "short" / "long"
-- tokens = string -> RequestRequestToken table.
RegisterGameType("RestRequest")

local CreateRestDialog

LaunchablePanel.Register{
	name = "Respite",
    menu = "game",
	icon = "icons/icon_activity/icon_activity_117.png",
	halign = "center",
	valign = "center",
	filtered = function()
		return not dmhub.isDM
	end,
	content = function()
		return CreateRestDialog()
	end,
}

CreateRestDialog = function()

	local tokenIdsSelected = {}

	local restTypes = {"Respite"}

	local restTypePanels = {}

	local restTypeSelected = 1

	local timeLapseInput = gui.Input{
			fontSize = 18,
			color = "white",
			width = "20%",
			height = 18,
			halign = "left",
			valign = "center",
			text = "1",
		}

	for i,t in ipairs(restTypes) do
		local index = i
		restTypePanels[#restTypePanels+1] = gui.Label{
			bgimage = "panels/square.png",
			text = t,
			classes = {'restElement', cond(i == restTypeSelected, 'selected')},

			click = function(element)
				restTypeSelected = index
				for j,panel in ipairs(restTypePanels) do
					panel:SetClass('selected', j == restTypeSelected)
				end

				--1 hour for a short rest, 8 hours for a long rest.
				timeLapseInput.text = cond(index == 1, '1', '8')
			end,
		}
	end

	local timeLapsePanel = gui.Panel{
		flow = "horizontal",
		width = 200,
		height = "auto",
		halign = "left",

		timeLapseInput,

		gui.Label{
			width = "50%",
			height = "auto",
			fontSize = 20,
			halign = "center",
			valign = "center",
			text = "Hours",
		},
	}

	local m_elapseTime = true

	local resultPanel

	local restButton = gui.PrettyButton{
		text = "Rest",
		floating = true,
		fontSize = 20,
		bold = true,
		halign = "right",
		valign = "bottom",
		hmargin = 16,
		vmargin = 16,
		width = 160,
		height = 50,

		click = function(element)
			if m_elapseTime then
				local amount = tonumber(timeLapseInput.text)
				if amount ~= nil then
					amount = amount / 24
					MoveGameTime(amount)
				end

			end

			local request = RestRequest.new{
				type = "long",
				tokens = {},
			}

			for i,tokid in ipairs(tokenIdsSelected) do
				request.tokens[tokid] = RestRequestToken.new{
					complete = false,
				}
			end

			dmhub.SendActionRequest(request)

			resultPanel.parent:FireEvent("close")
		end,
	}

	

	resultPanel = gui.Panel{
		id = 'rest-dialog',

		styles = {

			{
				valign = "top",
			},
			{
				classes = {'restElement'},
				bgcolor = '#ffffff00',
				color = 'white',
				width = 140,
				height = 22,
				fontSize = 14,
				textAlignment = 'center',
				halign = 'center',
			},

			gui.Style{
				selectors = {'restElement', 'hover'},
				bgcolor = '#ffffff66',
			},
			gui.Style{
				selectors = {'restElement', 'selected'},
				bgcolor = '#ff9999aa',
			},

			gui.Style{
				selectors = {'restElement', 'press'},
				bgcolor = '#ff9999cc',
			},
		},

		width = 600,
		height = 500,

		valign = "center",

		flow = "vertical",

		draggable = true,
		drag = function(element)
			element.x = element.xdrag
			element.y = element.ydrag
		end,

		gui.Label{
			fontSize = 30,
			width = "auto",
			height = "auto",
			text = "Respite",
			halign = "center",
			valign = "top",
			vmargin = 16,
		},

		gui.Panel{
			id = "restTypePanel",
			flow = "horizontal",
			width = "auto",
			height = "auto",
			valign = "top",
			halign = "center",

			children = restTypePanels,
		},

		gui.Panel{
			flow = "vertical",
			halign = "center",
			width = 240,
			height = "auto",
			vmargin = 16,

			gui.Check{
				halign = "left",
				text = "Elapse Time",
				value = m_elapseTime,
				change = function(element)
					m_elapseTime = element.value
					timeLapsePanel:SetClass('hidden', not element.value)
				end,
			},

			timeLapsePanel,
		},

		gamehud:CreatePartyTokenPoolSelector{
			halign = "center",
			selection = 'All',
			changeSelection = function(element, tokenids)
				tokenIdsSelected = tokenids
				restButton:SetClass("hidden", #tokenids == 0)
			end,
		},

		restButton,		
	}

	return resultPanel
end

function GameHud:TryHandleRestRequest(requestid, request)
	local hasTokens = false
	for tokid,info in pairs(request.info.tokens) do
		local tok = dmhub.GetTokenById(tokid)
		if tok ~= nil and info.complete == false and tok.canControl then
			hasTokens = true
		end
	end

	if not hasTokens then
		return false
	end

	if self:try_get('restingDialog') ~= nil and self.restingDialog.data.requestid ~= requestid then
		self.restingDialog:DestroySelf()
		self.restingDialog = nil
	end

	if self:try_get('restingDialog') == nil then
		self.restingDialog = self:CreateRestingDialog(requestid, request)
		self.mainDialogPanel:AddChild(self.restingDialog)
	end

	self.restingDialog:FireEventTree("refreshRequest", request)

	return true
end

function GameHud:CreateRestingDialog(requestid, request)

	local restingDialog

	local hitDiceTokenId = nil
	local hitDiceSelected = {}

	local tokenPanels = {}

	local currentRoll = ''

	local isrolling = false

	local rollPanel = nil
	local rollInput = nil

	local RefreshRoll = function()
		local roll = ''
		local modifier = 0
		for k,quantity in pairs(hitDiceSelected) do
			if quantity > 0 then
				local token = dmhub.GetTokenById(hitDiceTokenId)
				if roll ~= '' then
					roll = roll .. '+'
				end
				roll = roll .. tostring(quantity) .. 'd' .. k

				if token ~= nil then
					modifier = modifier + quantity*token.properties:AttributeMod('con')
				end
			end
		end

		if roll == '' then
			chat.PreviewChat('')
		else
			roll = string.format("%s + %d", roll, modifier)
			chat.PreviewChat(string.format('/roll %s', roll))
		end

		currentRoll = roll
		rollInput.text = currentRoll
		rollPanel:SetClass("hidden", roll == '')
	end

	if request.info.type == 'short' then
		rollInput = gui.Input{
			height = 20,
			width = 180,
			valign = 'center',
			fontSize = 16,
			change = function(element)
				currentRoll = element.text
				chat.PreviewChat(string.format('/roll %s', currentRoll))
			end,
		}

		rollPanel = gui.Panel{
			classes = {'hidden'},
			halign = "center",
			width = "auto",
			height = "auto",
			flow = "vertical",
			gui.Panel{
				width = 'auto',
				height = 'auto',
				halign = 'center',
				flow = 'horizontal',
				gui.Label{
					fontSize = 16,
					width = 'auto',
					height = 'auto',
					text = 'Roll:',
					hmargin = 8,
					valign = "center",
				},
				rollInput,
			},
			gui.PrettyButton{
				width = 200,
				height = 50,
				fontSize = 18,
				bold = true,
				valign = "bottom",
				vmargin = 16,
				text = "Roll Hit Dice",
				click = function(element)
					restingDialog:FireEvent("submit")
				end,
			}
		}
	end

	restingDialog = gui.Panel{
		id = 'rest-dialog',
		classes = {'framedPanel'},
		halign = "center",
		valign = "center",

		destroy = function(element)
			if element.data.listening then
					chat.events:Unlisten(restingDialog)
			end
		end,

		--chat submission/dice roll.
		submit = function(element)
			local tokenid = hitDiceTokenId
			local hitdice = DeepCopy(hitDiceSelected)
			local token = dmhub.GetTokenById(hitDiceTokenId)
			local roll = currentRoll
			hitDiceTokenId = nil
			hitDiceSelected = {}
			restingDialog:FireEventTree("refreshHitDiceTokenId", nil) --clear selection.
			RefreshRoll()
			if token ~= nil then
				isrolling = true
				dmhub.Roll{
					roll = roll,
					tokenid = hitDiceTokenId,
					creature = token.properties,
					description = "Hit Die",
					complete = function(rollInfo)
						isrolling = false

						local token = dmhub.GetTokenById(tokenid)

						if token ~= nil and rollInfo.total > 0 then
							token:ModifyProperties{
								description = "Hit Dice Healing",
								execute = function()
									token.properties:Heal(rollInfo.total, 'Rolled hit dice during a short rest')

									--consume the hit dice.
									for diceType,quantity in pairs(hitdice) do
										local resourceid = string.format("hitDie%s", diceType)
										token.properties:ConsumeResource(resourceid, 'long', quantity)
										dmhub.Debug(string.format('EEE: consume resource %s / %d', resourceid, quantity))
									end
								end
							}

						end

						restingDialog:FireEventTree("rollComplete")
					end,
				}
			end
		end,

		data = {
			requestid = requestid,
			listening = false,
		},

		styles = {
			Styles.Panel,
			{
				valign = "top",
			},
			{
				classes = {'tokenList'},
				halign = "center",
				flow = "vertical",
				vpad = 16,
				width = 500,
				height = 'auto',
			},
			{
				classes = {'tokenPanel'},
				bgimage = 'panels/square.png',
				bgcolor = 'black',
				width = 440,
				height = 80,
				halign = "center",
				flow = 'horizontal',
			},
			{
				classes = {'token-image'},
			},
			{
				classes = {'token-image-frame'},
			},
			{
				classes = {'hitdie'},
				width = 20,
				height = 20,
				bgcolor = 'white',
				valign = "center",
				halign = "left",
				hmargin = 0,
			},
			{
				classes = {'hitdie', 'hover', '~expended'},
				priority = 5,
				brightness = 1.6,
			},

		},

		width = 600,
		height = 700,

		valign = "center",

		flow = "vertical",

		draggable = true,
		drag = function(element)
			element.x = element.xdrag
			element.y = element.ydrag
		end,

		gui.Label{
			fontSize = 30,
			width = "auto",
			height = "auto",
			text = "Respite",
			halign = "center",
			valign = "top",
			vmargin = 16,
		},

		gui.Panel{
			--scroll container containing the tokens list.
			width = "95%",
			height = 400,
			valign = "center",
			halign = "center",
			vscroll = true,

			gui.Panel{
				classes = {'tokenList'},
				refreshRequest = function(element, request)
					local tokens = {}
					for k,tok in pairs(request.info.tokens) do
						local token = dmhub.GetTokenById(k)
						if token ~= nil then
							tokens[#tokens+1] = {
								tokenid = k,
								token = token,
								info = tok,
								sortOrder = cond(token.canControl, 1, 0) + cond(token.primaryCharacter, 2, 0)
							}
						end
					end

					local children = {}

					table.sort(tokens, function(a,b) return a.sortOrder > b.sortOrder end)
					for i,tokenInfo in ipairs(tokens) do

						local hitDicePanel = nil
						if request.info.type == 'short' and tokenInfo.token.canControl then

							hitDicePanel = gui.Panel{
								id = "hitDicePanel",
								width = 120,
								height = 'auto',
								halign = "left",
								valign = 'center',
								flow = 'horizontal',
								wrap = true,

								monitorGame = tokenInfo.token.monitorPath,
								refreshGame = function(element)
									element:FireEvent("create")
								end,

								rollComplete = function(element)
									element:FireEvent("create")
								end,

								create = function(element)
									local creature = tokenInfo.token.properties
									local resources = creature:GetResources()

									local resourceTable = dmhub.GetTable("characterResources") or {}

									local hitDice = {}

									for k,quantity in pairs(resources) do
										local resourceInfo = resourceTable[k]
										if resourceInfo ~= nil and resourceInfo.grouping == 'Hit Dice' then
											hitDice[#hitDice+1] = {
												resourceid = k,
												resourceInfo = resourceInfo,
												quantity = quantity,
											}
										end
									end

									table.sort(hitDice, function(a,b) return tonumber(a.resourceInfo.diceType) > tonumber(b.resourceInfo.diceType) end)

									local children = {}

									for i,diceInfo in ipairs(hitDice) do
										local usage = creature:GetResourceUsage(diceInfo.resourceid, diceInfo.resourceInfo.usageLimit)
										dmhub.Debug(string.format('EEE: usage of %s = %d / %d; limit = %s', diceInfo.resourceid, usage, diceInfo.quantity, diceInfo.resourceInfo.usageLimit))
										for j=1,diceInfo.quantity do
											children[#children+1] = gui.Panel{
												classes = {'hitdie', cond(j > diceInfo.quantity-usage, 'expended')},
												bgimage = diceInfo.resourceInfo.iconid,

												styles = {
													diceInfo.resourceInfo:CreateStyles()
												},

												click = function(element)
													if isrolling or element:HasClass('expended') then
														return
													end

													if hitDiceTokenId ~= tokenInfo.tokenid then
														hitDiceSelected = {}
														hitDiceTokenId = tokenInfo.tokenid
														restingDialog:FireEventTree("refreshHitDiceTokenId", hitDiceTokenId)
													end

													element:SetClass("highlight", not element:HasClass("highlight"))

													if element:HasClass("highlight") then
														hitDiceSelected[diceInfo.resourceInfo.diceType] = (hitDiceSelected[diceInfo.resourceInfo.diceType] or 0) + 1
													else
														hitDiceSelected[diceInfo.resourceInfo.diceType] = (hitDiceSelected[diceInfo.resourceInfo.diceType] or 0) - 1
													end

													RefreshRoll()

												end,

												refreshHitDiceTokenId = function(element, newid)
													if newid ~= tokenInfo.tokenid then
														element:SetClass('highlight', false)
													end
												end,
											}
										end
										
									end

									element.children = children
								end,
							}
						end

						local panel = tokenPanels[tokenInfo.tokenid] or gui.Panel{
							classes = {'tokenPanel'},

							gui.CreateTokenImage(tokenInfo.token, {
								halign = "left",
								width = 60,
								height = 60,
							}),

							gui.Label{
								id = "hitpointsLabel",
								bgimage = "panels/square.png",
								styles = {
									{
										bgcolor = "black",
									}
								},
								fontSize = 20,
								color = 'white',
								valign = 'center',
								width = 80,
								height = 22,
								data = {
								},

								monitorGame = tokenInfo.token.monitorPath,
								refreshGame = function(element)
									element:FireEvent("create")
								end,

								create = function(element)
									element:FireEvent("rollComplete")
								end,
								rollComplete = function(element)
									local token = dmhub.GetTokenById(tokenInfo.tokenid)
									if token ~= nil then
										element.text = string.format("%d/%d", token.properties:CurrentHitpoints(), token.properties:MaxHitpoints())
										if element.data.prevHitpoints ~= nil and token.properties:CurrentHitpoints() > element.data.prevHitpoints then
											element:PulseClass("highlight_good")
										end

										element.data.prevHitpoints = token.properties:CurrentHitpoints()
									end
								end,
							},

							hitDicePanel
						}

						tokenPanels[tokenInfo.tokenid] = panel

						children[#children+1] = panel
					end

					element.children = children
				end,
			},
		},

		rollPanel,

		gui.PrettyButton{
			classes = cond(dmhub.isDM, nil, "hidden"),
			width = 220,
			height = 50,
			fontSize = 22,
			bold = true,
			valign = "bottom",
			halign = "center",
			vmargin = 16,
			text = "Finish Respite",
			click = function(element)
				dmhub.CancelActionRequest(requestid)
				chat.PreviewChat('')

				for k,tok in pairs(request.info.tokens) do
					local token = dmhub.GetTokenById(k)
					if token ~= nil then
						token:ModifyProperties{
							description = "Respite",
							execute = function()
								if token.properties ~= nil then
									token.properties:Rest(request.info.type)
								end
							end
						}
					end
					
				end

				self.restingDialog:DestroySelf()
				self.restingDialog = nil
			end,
		},


		gui.CloseButton{
			classes = cond(dmhub.isDM, "hidden"), --the DM doesn't get access to this since they should formally finish the rest when ready.
			floating = true,
			valign = "top",
			halign = "right",
			click = function(element)
				self.restingDialog:DestroySelf()
				self.restingDialog = nil
			end,
		},
		
		monitorGame = "/actionRequests",

		refreshGame = function(element)
			if dmhub.GetPlayerActionRequest(requestid) == nil then
				--rest dialog is all done with.
				self.restingDialog:DestroySelf()
				self.restingDialog = nil
			end
		end,
	}

	if request.info.type == 'short' then
		chat.events:Listen(restingDialog)
		restingDialog.data.listening = true
	end

	restingDialog:PulseClass("fadein")

	return restingDialog
	
end
