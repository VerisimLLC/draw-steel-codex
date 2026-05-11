local mod = dmhub.GetModLoading()

--Functions which control the GameHud's handling of the initiative bar.
--This drives the display of the initiative bar at the top of the screen.

--the card width as a percentage of the height
local CardWidthPercent = 78

--Create the initiative bar.
--   self: the GameHud object
--   info: the dmhub info object which gives us access to important game information. Some parameters we use here:
--      info.initiativeQueue: this is the initiative queue data. See initiative-queue.lua for the definition of this object. It is
--                            networked between systems.
--      info.UploadInitiative(): Whenever we change info.initiativeQueue we must call this to ensure that initiativeQueue gets networked.
--      info.tokens: This contains a table of tokens currently in the game. We scan this to check that we can see tokens and should show their initiative.
--      info.selectedOrPrimaryTokens: This contains a table of tokens that are selected, which we use to choose which tokens to roll dice for.
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMInitiativeBar.lua:993
function GameHud.CreateInitiativeBar(self, info)

	self.initiativeInterface = info

	local mainInitiativeBar = nil

	--The label we display instructing the DM to click to start tracking initiative. Only shows up when the DM is hovering over the initiative bar.
	local clickLabel = gui.Label({
				id = 'initiative-click-prompt',
				text = 'Click to start tracking initiative',

				events = {
					refresh = function(element)
						element:SetClass('hidden', info.initiativeQueue ~= nil and info.initiativeQueue.hidden == false)
					end,
				},

				selfStyle = {
					fontSize = '40%',
					color = '#ccccbb',
					valign = 'bottom',
					halign = 'center',
					vmargin = 12,
					textAlignment = 'center',
					width = 'auto',
					height = 'auto',
				},

				styles = {
					{
						opacity = 0,
					},
					{
						selectors = {'hover-initiative'},
						opacity = 1,
						transitionTime = 0.2,
					}
				}
			})

	--This is the main area which shows all the token avatars in their queue.
	mainInitiativeBar = self:CreateMainInitiativePanel(info)

	--The parent / top-level initiative bar.
	return gui.Panel({
		floating = true,
		selfStyle = {
			valign = 'top',
			halign = 'center',
		},

		className = 'initiative-panel',

		styles = {
			{
				width = 600,
				height = 120,
				bgcolor = 'white',
			},
			{
				selectors = {'initiative-panel'},
				inherit_selectors = true,
				bgcolor = 'black',
			},
			{
				selectors = { 'initiative-panel', 'no-initiative' },
				y = -300,
				transitionTime = 0.5,
			},

			--make it so the close button on child panels are on the right, unless
			--the panel is on the left side of the carousel in which case it goes on the left.
			{
				selectors = {'close-button'},
				priority = 5,
				halign = "right",
			},

			{
				selectors = {'close-button', 'parent:hadTurn'},
				priority = 5,
				halign = "left",
			},

			{
				selectors = {'initiativeArrow'},
				bgimage = "panels/initiative-arrow.png",
				bgcolor = "white",
				y = -40,
				width = 63,
				height = 45,
				valign = "top",
				opacity = 0,
				hidden = 1,
			},
			{
				selectors = {'initiativeArrow', 'parent:turn'},
				y = 10,
				transitionTime = 1,
				opacity = 1,
				hidden = 0,
			},

			{
				selectors = {"initiativeEntryPanel"},
				height = "100%",
				width = tostring(CardWidthPercent) .. "% height",
				valign = 'top',
				halign = 'center',
				flow = 'none',

				--make it so when the initiative queue is recalculated, entries will slide along into place over time
				--rather than instantly jumping to their new location.
				moveTime = 0.5,
			},
			{
				selectors = {"initiativeEntryBackground"},
				width = "100%+32",
				height = "100%+32",
				valign = "center",
				halign = "center",
				borderWidth = 16,
				borderColor = "#000000aa",
				borderFade = true,
			},
			{
				selectors = {"initiativeEntryBorder"},
				bgcolor = "clear",
				width = "100%",
				height = "100%",
				border = 2,
				borderColor = Styles.textColor,
				opacity = 1,
			},
			{
				selectors = {"initiativeEntryBorder", "parent:turn"},
				brightness = 3,
				transitionTime = 0.5,
			},
			{
				selectors = {"initiativeEntryBorder", "parent:hadTurn"},
				brightness = 0.3,
				transitionTime = 0.5,
			},
		},

		events = {

			--when we hover/dehover make sure the prompt label is shown or not.
			hover = function(element)
				clickLabel:SetClass('hover-initiative', true)
			end,

			dehover = function(element)
				clickLabel:SetClass('hover-initiative', false)
			end,

			refresh = function(element)
				--detect if we are using initiative. If we aren't, then hide the initiative bar completely for players
				--and simply show a slither of it for the DM so they can click on it to activate initiative.
				element:SetClass('no-initiative', info.initiativeQueue == nil or info.initiativeQueue.hidden)
				element:SetClass('hidden', element:HasClass('no-initiative'))
			end,

			click = function(element)
				--when clicked, if initiative isn't active, initialize the initiative queue.
				--This means creating it in the game document and then uploading it. This will cause all
				--players to now see the initiative queue.
				if info.initiativeQueue == nil or info.initiativeQueue.hidden then
					UploadDayNightInfo()
					info.initiativeQueue = InitiativeQueue.Create()
					info.UploadInitiative()
				end
			end,
		},

		children = {
			--background shadow
			gui.Panel{
				id = "initiativeShadow",
				interactable = false,
				bgimage = 'panels/initiative/shadow.png',
				width = "160%",
				height = 400,
				valign = "top",
				halign = "center",
			},

			--text at the top saying initiative.
			gui.Panel{
				halign = "center",
				valign = "top",
				width = "auto",
				height = "auto",
				flow = "vertical",

				gui.Label({
					text = 'Initiative',

					vmargin = 8,
					fontFace = "SupernaturalKnight",
					fontSize = 30,
					color = Styles.textColor,
					valign = 'top',
					halign = 'center',
					textAlignment = 'center',
					width = 'auto',
					height = 'auto',
				}),

				gui.Label{
					text = '',
					fontFace = "Varta",
					fontSize = 22,
					color = Styles.textColor,
					valign = 'top',
					halign = 'center',
					textAlignment = 'center',
					width = 180,
					height = 24,
					vmargin = 0,
					y = -6,

					refresh = function(element)
						if info.initiativeQueue == nil or info.initiativeQueue.hidden then
							element.text = ''
						else
							element.text = string.format('Round %d', info.initiativeQueue.round)
						end
					end,
				},
			},

			clickLabel,

			mainInitiativeBar,

			--button to close the initiative queue.
			gui.CloseButton({
				escapeActivates = false,

				events = {
					refresh = function(element)
						--only show this if initiative is currently actually active.
						element:SetClass('hidden', info.initiativeQueue == nil or info.initiativeQueue.hidden)
					end,

					--when clicked we destroy the initiative queue by setting it to nil and upload changes. This will
					--remove the initiative queue completely from player view.
					click = function(element)
						if info.initiativeQueue ~= nil then
							UploadDayNightInfo()
							info.initiativeQueue.hidden = true
							info.UploadInitiative()

							for initiativeid,_ in pairs(info.initiativeQueue.entries) do
								local tokens = self:GetTokensForInitiativeId(info, initiativeid)
								for _,tok in ipairs(tokens) do
									tok.properties:DispatchEvent("endcombat", {})
								end
							end
						end
					end
				},

				selfStyle = {
					halign = 'center',
					valign = 'top',
					x = 82,
					y = 4,
					width = 20,
					height = 20,
				},

				styles = {
					{
						--only show the close initiative button to the DM, so for players hide it.
						selectors = {'player'},
						hidden = 1,
					},
				}
			}),

		----The button that can be pressed to roll for initiative.
		--gui.Panel({
		--
		--	--show a D20 icon.
		--	bgimage = 'ui-icons/d20.png',
		--
		--	events = {
		--		refresh = function(element)
		--			--This button is hidden if initiative isn't active, or if no tokens are currently selected.
		--			if info.initiativeQueue == nil or info.initiativeQueue.hidden or #info.selectedOrPrimaryTokens == 0 then
		--				element:SetClass('hidden', true)
		--			else
		--				element:SetClass('hidden', false)
		--
		--				--see if all our tokens have initiative already, if they do then we mark this as greyed, otherwise
		--				--we want the player to click it so we make it bright and appealing to click.
		--
		--				local hasInitiative = true
		--				for i,tok in ipairs(info.selectedOrPrimaryTokens) do
		--					local initiativeId = InitiativeQueue.GetInitiativeId(tok)
		--					if not info.initiativeQueue:HasInitiative(initiativeId) then
		--						hasInitiative = false
		--					end
		--				end
		--
		--				element:SetClass('highlight', not hasInitiative)
		--			end
		--		end,
		--
		--		refreshSelectedTokens = function(element)
		--			--when the selected tokens have been changed trigger a refresh to see if this should be shown or not.
		--			element:FireEvent('refresh')
		--		end,
		--
		--		click = function(element)
		--			--when the player clicks this, we trigger an initiative roll.
		--
		--			--Iterate over the selected tokens and roll for each of them. (Note: the most common case is just one token is selected)
		--			--Monsters of the same type should only have one roll and will have the same
		--			--initiative ID, so record the initiative ID's we have rolled for and don't
		--			--roll the same initiative ID multiple times.
		--			local initiativeIdsSeen = {}
		--			for i,token in ipairs(info.selectedOrPrimaryTokens) do
		--				if token.properties ~= nil then
		--
		--					--get the initiative ID for this token. This will be the token id for a character,
		--					--or the monster type (prefixed by MONSTER-) for monsters.
		--					local initiativeId = InitiativeQueue.GetInitiativeId(token)
		--					if initiativeIdsSeen[initiativeId] == nil then
		--
		--						initiativeIdsSeen[initiativeId] = true
		--
		--						--We call creature.RollInitiative here (see creature.lua)
		--						local dexterity = token.properties.attributes.dex.baseValue 
		--						token.properties:RollInitiative()
		--					end
		--				end
		--			end
		--		end,
		--
		--		--When the roll for initiative button is hovered show a nice tooltip.
		--		hover = gui.Tooltip("Click to roll for initiative"),
		--	},
		--
		--	--Styling for roll for initiative button.
		--	selfStyle = {
		--		halign = 'left',
		--		valign = 'bottom',
		--		width = 48,
		--		height = 48,
		--	},
		--
		--	styles = {
		--		--button is a little dull by default and highlights a purple color when hovered.
		--		{
		--			bgcolor = '#aaaaaaff',
		--		},
		--		{
		--			--if we want people to click this because they haven't rolled initiative yet.
		--			selectors = { 'highlight' },
		--			brightness = 5.5,
		--			bgcolor = '#ffffffff',
		--		},
		--		{
		--			selectors = { 'hover' },
		--			bgcolor = '#ffaaff',
		--			transitionTime = 0.1,
		--		},
		--		{
		--			selectors = { 'press' },
		--			brightness = 1.5,
		--			transitionTime = 0.1,
		--		},
		--	},
		--}),

			--The 'End Turn' button which is pressed to end the current token's turn. It is only shown to the DM
			--and to players if it is currently their turn (their token is first in the initiative queue).
			gui.FancyButton({
				bgimage = 'panels/square.png',
				text = 'End Turn',
				y = 210,
				halign = "center",
				width = 120,
				height = 36,
				fontSize = 20,
				events = {
					click = function(element)
						self:NextInitiative()
						info.UploadInitiative()
					end,

					refresh = function(element)
						if info.initiativeQueue == nil or info.initiativeQueue.hidden or not self:has_key('currentInitiativeId') then

							--If there is no initiative then hide the button.
							element:AddClass('hidden')
						else
							--Find the list of tokens for the first entry in the initiative queue. If we have control of any of them show
							--the button, otherwise don't.
							local tokens = self:GetTokensForInitiativeId(info, self.currentInitiativeId)
							local foundControllable = false
							for i,tok in ipairs(tokens) do
								if tok.canControl then
									foundControllable = true
									break
								end
							end

							--note that the dm always shows entries, and doesn't auto-remove entries since they might be for a different map.
							if foundControllable or dmhub.isDM then
								element:RemoveClass('hidden')
							else
								element:AddClass('hidden')
							end
						end
					end,
				},
			}),

		},
	})
end
--]==]

--Function to create the main area of the initiative panel, all the initiative entries displayed in order.
function GameHud.CreateMainInitiativePanel(self, info)

	--this is a master table of initiative id -> panel showing that initiative id.
	--every time initiative changes we recalculate this table, but we keep any panels
	--from last time we created it, so we don't destroy and re-create panels all the time
	--but keep them where possible.
	local entries = {
	}


	local currentTurn = nil
	local mainInitiativeBar

	--anthem data.
	local m_anthemEventInstance = nil
	local m_anthemTokenId = nil

	local StopAnthem = function()
		if m_anthemEventInstance ~= nil then
			m_anthemEventInstance:Stop()
			m_anthemEventInstance = nil
			m_anthemTokenId = nil
			mainInitiativeBar.monitorGame = nil
		end
	end

	mainInitiativeBar = gui.Carousel({
		horizontalCurve = 0.6,
		maximumVelocity = 2,
		y = 36,

		events = {
			drag = function(element)
				if dmhub.isDM then
					element.targetPosition = round(element.currentPosition)
				end
			end,

			disable = function(element)
				StopAnthem()
			end,

			--fired when the token playing the anthem changes. Will update the volume of the anthem.
			refreshGame = function(element)
				printf("MONITOR:: REFRESH GAME...")
				if m_anthemEventInstance ~= nil and m_anthemTokenId ~= nil then
					local tok = dmhub.GetTokenById(m_anthemTokenId)
					if tok ~= nil then
						m_anthemEventInstance.volume = tok.anthemVolume
				printf("MONITOR:: REFRESH GAME... SET VOL %f", tok.anthemVolume)
					else
						StopAnthem()
					end
				end
			end,

			refresh = function(element)



				if info.initiativeQueue == nil or info.initiativeQueue.hidden then
					--initiative queue is inactive so just hide this.
					element:SetClass('hidden', true)
					entries = {}
				else
					element:SetClass('hidden', false)


					--calculate out the entries we show. Also calculate whose turn it is
					--currently and store this in currentInitiativeId
					local newEntries = {}
					local ordered = {}

					--iterate over all entries in the initiative queue.
					for k,v in pairs(info.initiativeQueue.entries) do
						if entries[k] ~= nil then
							newEntries[k] = entries[k]
						else
							newEntries[k] = self:CreateInitiativeEntry(info, k)
							dmhub.Debug(string.format("INITIATIVE:: %s -> %s", k, cond(newEntries[k], "yes", "no")))
						end

						if newEntries[k] ~= nil and v ~= nil then --CreateInitiativeEntry() can return nil, in which case don't add it.

							--this calculates the ordering of an item in the initiative queue. round >> initiative value >> dexterity
							local ord = InitiativeQueue.GetEntryOrd(v)

							ordered[#ordered+1] = {
								info = v,
								entry = newEntries[k],
								ord = ord,
								ordAbsolute = InitiativeQueue.GetEntryOrdAbsolute(v),
								tokenid = k,
								initiativeid = v.initiativeid,
							}
						end
					end

					--Get an ordered list of the initiative entries.
					table.sort(ordered, function(a,b)
						return a.ord > b.ord or (a.ord == b.ord and a.initiativeid > b.initiativeid)
					end)

					--choose the first item from the ordered list (if there is one) to be the current turn.
					if #ordered > 0 then
						currentTurn = ordered[1].tokenid

					else
						currentTurn = nil
					end

					self.currentInitiativeId = currentTurn

					--now we have calculated our new list of initiative entries, add them as children in appropriate order.
					local carouselPosition = 0
					for i,v in ipairs(ordered) do
						v.entry:SetClass("turn", i == 1)
						v.entry:SetClass("hadTurn", v.info.round > ordered[1].info.round)

						if v.info.round > ordered[1].info.round then
							carouselPosition = carouselPosition + 1
						end

					end

					table.sort(ordered, function(a,b)
						return a.ordAbsolute > b.ordAbsolute or (a.ordAbsolute == b.ordAbsolute and a.tokenid > b.tokenid)
					end)

					local children = {}
					for i,v in ipairs(ordered) do
						children[#children+1] = v.entry
					end

					element.children = children

					if #ordered > 0 then
						element.targetPosition = -carouselPosition - #ordered*2*ordered[#ordered].info.round
					end

					entries = newEntries

					--calculate anthem of the currently playing token.
					local anthemToken = nil
					if self:try_get("currentInitiativeId") ~= nil then
						local tokens = self:GetTokensForInitiativeId(info, self.currentInitiativeId)
						for i,tok in ipairs(tokens) do
							local anthem = tok.anthem
							if anthem ~= nil and anthem ~= "" then
								anthemToken = tok
							end
						end
					end

					if anthemToken ~= nil then
						if anthemToken.charid ~= m_anthemTokenId then
							StopAnthem()
							m_anthemTokenId = anthemToken.charid
							local asset = assets.audioTable[anthemToken.anthem]
							if asset ~= nil then
								m_anthemEventInstance = asset:Play()
								m_anthemEventInstance.volume = anthemToken.anthemVolume
								element.monitorGame = anthemToken.monitorPath
								printf("MONITOR:: Monitoring %s", anthemToken.monitorPath)
							end
						end
					else
						StopAnthem()
					end

				end
			end,
		},

		styles = {
			{
				width = '80%',
				height = '80%',
				valign = 'center',
				halign = 'center',
			},
			{
				selectors = {"avatar", "parent:hadTurn"},
				brightness = 0.1,
				saturation = 0.5,
				transitionTime = 0.5,
			},
			{
				selectors = {"initiativeDice", "parent:hadTurn"},
				brightness = 0.1,
				saturation = 0.5,
				transitionTime = 0.5,
			},
		},

	})

	self.initiativeCarousel = mainInitiativeBar

	return mainInitiativeBar
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMInitiativeBar.lua:1940
function GameHud:NextInitiative()
	local info = self.initiativeInterface
	local mainInitiativeBar = self.initiativeCarousel

	--End the turn in initiative queue data and upload the changes.
	if self:has_key('currentInitiativeId') then
		local tokens = self:GetTokensForInitiativeId(info, self.currentInitiativeId)
		for i,tok in ipairs(tokens) do
			if tok.properties ~= nil then
				tok.properties:EndTurn(tok)
			end
		end
		
		info.initiativeQueue:NextTurn(self.currentInitiativeId)

		--recalculate self.currentInitiativeId
		mainInitiativeBar:FireEvent("refresh")
		if self:has_key('currentInitiativeId') then
			local tokens = self:GetTokensForInitiativeId(info, self.currentInitiativeId)
			for i,tok in ipairs(tokens) do
				if tok.properties ~= nil then
					tok.properties:BeginTurn()
				end
			end
		end

	end

end
--]==]

--Creates a single initiative entry. This consists of a panel with an image, a display of the initiative number, etc.
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMInitiativeBar.lua:2185
function GameHud.CreateInitiativeEntry(self, info, initiativeid)

	--A function which will conveniently return the token for this entry. If there are multiple tokens (because it's a monster entry)
	--it will just return the first one.
	local GetMatchingToken = function()
		local tokens = self:GetTokensForInitiativeId(info, initiativeid)
		if #tokens > 0 then
			return tokens[1]
		else
			return nil
		end
	end

	local token = GetMatchingToken()
	--if token == nil and not dmhub.isDM then
	--	return nil
	--end

	--this label shows how many tokens this entry represents. Will just be empty text if there is only one token.
	local quantityLabel = gui.Label({
				text = '',
				y = 2,
				margin = 4,
				style = {
					valign = 'bottom',
					halign = 'right',
					textAlignment = 'center',
					hpad = 0,
					width = 'auto',
					height = 'auto',
					fontSize = '30%',
				}
			})


	local closeButton = nil

	--The DM has an 'X' button which lets them remove initiative entries.
	if dmhub.isDM then

		closeButton = gui.CloseButton({
			events = {
				--remove the initiative entry.
				click = function(element)
					
					if self:has_key("currentInitiativeId") and self.currentInitiativeId == initiativeid then
						--if it's currently this creature's turn, move to next
						self:NextInitiative()
					end

					info.initiativeQueue:RemoveInitiative(initiativeid)
					info.UploadInitiative()
				end
			},

			selfStyle = {
				valign = 'top',
				hmargin = 0,
				vmargin = 0,
				width = 24,
				height = 24,
			},
		})

		--this isn't shown by default, only when hovering over the panel.
		closeButton:AddClass('hidden')
	end

	local playerColor = "black"
	if token ~= nil then
		playercolor = token.playerColor.tostring
	end

	--this is the initiative entry panel.
	return gui.Panel({
		classes = {"initiativeEntryPanel"},

		events = {
			click = function(element)
				local tokens = self:GetTokensForInitiativeId(info, initiativeid)
				if tokens ~= nil and #tokens > 0 then
					for i,tok in ipairs(tokens) do
						if i == 1 then
							dmhub.SelectToken(tok.id)
							dmhub.CenterOnToken(tok.id)
						else
							dmhub.AddTokenToSelection(tok.id)
						end
					end
				end
			end,

			refresh = function(element)
				--check if the token still exists. If it doesn't we collapse this entry unless we're the DM.
				token = GetMatchingToken()
				--if token == nil and not dmhub.isDM then
				--	element:AddClass('collapsed')
				--else
					element:RemoveClass('collapsed')
				--end
			end,

			--If we're the DM and the close button is a thing, then show/hide it when we hover or dehover this panel.
			hover = function(element)
				local tokens = self:GetTokensForInitiativeId(info, initiativeid)
				if tokens ~= nil and #tokens > 0 then
					for _,tok in ipairs(tokens) do
						dmhub.PulseHighlightToken(tok.id)
					end
				end

				if closeButton ~= nil then
					closeButton:RemoveClass('hidden')
				end

				local tooltip = nil
				if token ~= nil then
					if token.canLocalPlayerSeeName then
						tooltip = token.name
					end

					if tooltip == nil or tooltip == '' then
						if dmhub.isDM and token.properties ~= nil and token.properties:GetMonsterType() ~= nil then
							tooltip = token.properties:GetMonsterType()
						else
							tooltip = 'NPC/Monster'
						end
					else
						local playerName = token.playerName
						if playerName ~= tooltip then
							tooltip = string.format('%s (%s)', tooltip, playerName)
						end
					end
				elseif dmhub.isDM and info.initiativeQueue ~= nil and info.initiativeQueue:HasInitiative(initiativeid) then
					tooltip = info.initiativeQueue:DescribeEntry(initiativeid) .. "\nNot on this map"
				end

				if tooltip ~= nil and tooltip ~= "" then
					gui.Tooltip(tooltip)(element)
				end
			end,

			dehover = function(element)
				if closeButton ~= nil then
					closeButton:AddClass('hidden')
				end
			end,
		},

		children = {
			gui.Panel{
				classes = {"initiativeEntryBackground"},
				bgimage = "panels/square.png",
		
				selfStyle = {
					bgcolor = 'white',

					--make the background a nice gradient that is in the player's color.
					gradient = {
						type = 'radial',
						point_a = { x = 0.5, y = 0.8, },
						point_b = { x = 0.5, y = 0, },
						stops = {
							{
								position = 0,
								color = playerColor,
							},

							{
								position = 1,
								color = '#000000',
							},
						}
					},
				},
			},

			--an image which will display the avatar of the token for this initiative entry.
			gui.Panel({
				classes = {"avatar"},
				bgimage = 'panels/square.png',
				height = "100%",
				width = "100%",
				valign = 'top',
				halign = 'center',
				bgcolor = 'white',

				events = {
					refresh = function(element)
						--find which token this represents and display their avatar.
						--Also count the number of tokens so we can display the quantity.
						local tokens = self:GetTokensForInitiativeId(info, initiativeid)
						local found = false
						local quantity = 0


						for i,tok in ipairs(tokens) do
							if tok.canSee or tok.playerControlled then

								if found == false then
									token = tok

									--set the image shown here with the current portion of the image.
									element.bgimage = token.portrait
									element.selfStyle.imageRect = token:GetPortraitRectForAspect(CardWidthPercent*0.01)
									found = true
								end

								quantity = quantity+1
							end
						end

						dmhub.Debug('TOKENS FOR INITIATIVE ' .. initiativeid .. ': ' .. quantity)

						if found == false then
							--we can't see any of the tokens associated with this entry so show that it is unknown.
							element.bgimage = 'game-icons/perspective-dice-six-faces-random.png'
							element.selfStyle.imageRect = nil
						end

						--display the quantity here.
						if quantity <= 1 then
							quantityLabel.text = ''
						else
							quantityLabel.text = string.format("x%d", quantity)
						end
					end,
				},
			}),

			gui.Panel{
				classes = {"initiativeEntryBorder"},
				bgimage = "panels/square.png",
			},

			quantityLabel,

			--the panel that displays the initiative value of this entry. A faint d20 icon in the background with the number on top.
			gui.Panel({
				classes = {"initiativeDice"},
				bgimage = 'panels/initiative/d20.png',
				y = 12,
				bgcolor = "white",
				style = {
					height = 28,
					width = 32,
					valign = 'bottom',
					halign = 'center',
					bgcolor = 'white', --for now don't show the d20.
				},
				children = {
					gui.Label({
						text = '',

						--the DM can edit this value to change the initiative at their discretion.
						editable = dmhub.isDM,
						characterLimit = 2,

						selfStyle = {
							width = '100%',
							height = 'auto',
							halign = 'center',
							valign = 'center',
							textAlignment = 'center',
							fontFace = "varta",
							fontSize = 18,
							color = "black",
							bold = true,
						},

						events = {
							refresh = function(element)
								--look up the initiative value for this entry and show it.
								if info.initiativeQueue == nil then
									return
								end

								local initiativeEntry = info.initiativeQueue.entries[initiativeid]
								if initiativeEntry == nil then
									return
								end

								element.text = string.format("%d", round(initiativeEntry.initiative))
							end,

							--The DM edited this initiative value so change and upload.
							change = function(element)
								local num = tonumber(element.text) or 0
								info.initiativeQueue:SetInitiative(initiativeid, num)
								info.UploadInitiative()
							end,
						},

					})
				},
			}),

			gui.Panel{
				classes = {"initiativeArrow"},
				floating = true,
				press = function(element)
					self.initiativeCarousel:FireEvent("refresh")
				end,
			},

			closeButton,
		}
	})
end
--]==]

--This utility function is given an initiative ID and finds the list of tokens that match that initiative ID.
--For a character this will give back that single character token.
--For monsters it will give back all monsters of that type.
--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMInitiativeBar.lua:2789
function GameHud.GetTokensForInitiativeId(self, info, initiativeid)
	local result = {}
	if string.starts_with(initiativeid, 'MONSTER-') then
		local monsterType = string.sub(initiativeid, 9, -1)

		for k,tok in pairs(info.tokens) do
			if tok.properties ~= nil and tok.properties:GetMonsterType() == monsterType and (dmhub.isDM or not tok.invisibleToPlayers) then
				result[#result+1] = tok
			end
		end
	else
		result[#result+1] = info.tokens[initiativeid]
	end

	return result
end
--]==]
