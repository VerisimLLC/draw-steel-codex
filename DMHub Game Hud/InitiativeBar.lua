local mod = dmhub.GetModLoading()

--Functions which control the GameHud's handling of the initiative bar.
--This drives the display of the initiative bar at the top of the screen.

--the card width as a percentage of the height
local CardWidthPercent = 78

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
