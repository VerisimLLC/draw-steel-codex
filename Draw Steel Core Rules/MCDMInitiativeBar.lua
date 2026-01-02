local mod = dmhub.GetModLoading()

local g_triggeredResourceId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"

local anthemDuration = setting{
    id = "anthemlength",
    description = "Anthem Duration",
    editor = "slider",
    min = 1,
    max = 30,
    default = 10,
    ord = 100,
    labelFormat = "%d",

	storage = "game",
	section = "audio",
	classes = {"dmonly"},
}

local playersControlInitiativeSetting = setting{
	id = "permission:playersinitiative",
	description = "Players can control initiative",
	editor = "check",
	default = false,

	storage = "game",
	section = "game",
	classes = {"dmonly"},
}

local CanControlInitiative = function()
	return dmhub.isDM or playersControlInitiativeSetting:Get()
end

local function CreateDrawSteelBubble()

    local ShouldShowEndTurn = function()
        if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
            return false
        end

        local currentInitiativeId = dmhub.initiativeQueue.currentTurn
		if currentInitiativeId == nil or dmhub.initiativeQueue.currentTurn == false or dmhub.initiativeQueue:ChoosingTurn() then
            return false
		else
			--Find the list of tokens for the first entry in the initiative queue. If we have control of any of them show
			--the button, otherwise don't.
			local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, currentInitiativeId)
			local foundControllable = false
			for i,tok in ipairs(tokens) do
				if tok.canControl then
					foundControllable = true
					break
				end
			end

			--note that the dm always shows entries, and doesn't auto-remove entries since they might be for a different map.
			return foundControllable or dmhub.isDM
		end
    end

    local bubblePanel

    local playerArrow = gui.Panel {
        bgimage = mod.images.bubblearrow,
        bgcolor = "white",
        width = 71,
        height = 36,
        rotate = 90,

        x = -44,
        y = 38,

        classes = "arrow",

        press = function(element)
            if not element:HasClass("selected") and CanControlInitiative() and dmhub.initiativeQueue:ChoosingTurn() then
                dmhub.initiativeQueue.playersTurn = true
                dmhub:UploadInitiativeQueue()
                bubblePanel:FireEventTree("refresh")
            end
        end,

        refresh = function(self)
            if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                self:SetClass("selected", false)
                return
            end

            local isPlayersTurn = dmhub.initiativeQueue:IsPlayersTurn()

            if isPlayersTurn then
                self:SetClass("selected", true)
            else
                self:SetClass("selected", false)
            end
        end,
    }


    local enemyArrow = gui.Panel {

        bgimage = mod.images.bubblearrow,
        bgcolor = "white",
        width = 71,
        height = 36,
        rotate = 270,

        x = 93,
        y = 38,

        classes = { "arrow", "selected" },

        press = function(element)
            if not element:HasClass("selected") and CanControlInitiative() and dmhub.initiativeQueue:ChoosingTurn() then
                dmhub.initiativeQueue.playersTurn = false
                dmhub:UploadInitiativeQueue()
                bubblePanel:FireEventTree("refresh")
            end
        end,

        refresh = function(self)
            if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                self:SetClass("selected", false)
                return
            end

            local isPlayersTurn = dmhub.initiativeQueue:IsPlayersTurn()

            if isPlayersTurn then
                self:SetClass("selected", false)
            else
                self:SetClass("selected", true)
            end
        end,
    }

    --bubble king panel
    bubblePanel = gui.Panel{

        bgimage = true,
        bgcolor = "clear",
        width = 120,
        height = 120,
        halign = "center",
		valign = "top",



		styles = {

			{
				selectors = {"arrow"},
				opacity = 0,
			},

			{
				selectors = {"arrow", "hover"},
				opacity = 0.3,
				transitionTime = 0.3,
			},

			{
				selectors = {"arrow", "selected"},
				opacity = 1,
				transitionTime = 0.1,
			},

			{
				selectors = {"glow"},
				opacity = 0,
			},

			{
				selectors = {"glow", "selected"},
				opacity = 1,
                transitionTime = 0.3,
			},

			{
				selectors = {"text"},
				opacity = 0,
                transitionTime = 0,
			},


			{
				selectors = {"text", "selected"},
				opacity = 1,
                transitionTime = 0,
			},
            {
                selectors = {"text", "clickable"},
                fontSize = 32,
            },
            {
                selectors = {"text", "clickable", "parent:hover"},
                fontSize = 36,
                transitionTime = 0,
                soundEvent = "Mouse.Hover",
            },
            {
                selectors = {"text", "clickable", "parent:press"},
                soundEvent = "Mouse.Click",
            },



		},

        hover = function(element)
            if ShouldShowEndTurn() or not dmhub.initiativeQueue:ChoosingTurn() then
                element:SetClass("highlightSwords", false)
                return
            end

            local canSelectToken = false
            local token = dmhub.selectedOrPrimaryTokens[1]
            if token ~= nil and token.canControl then
                local initiativeid = InitiativeQueue.GetInitiativeId(token)
                if initiativeid ~= nil and dmhub.initiativeQueue:IsEntryPlayer(initiativeid) and token.topsheet ~= nil then
                    canSelectToken = true
                end
            end

            if not canSelectToken then
                element:FireEvent("dehover")
                element:SetClass("highlightSwords", false)
                return
            end

            element:SetClass("highlightSwords", true)

            local tokens = dmhub.allTokens
            for _,tok in ipairs(tokens) do
                if tok.topsheet ~= nil then
                    local swords = tok.topsheet:GetChildrenWithClassRecursive("swords")[1]
                    if swords ~= nil then
                        swords:SetClass("highlight", tok.charid == token.charid)
                        swords:SetClass("highlightActive", true)
                    end
                end
            end
        end,

        dehover = function(element)
            if element:HasClass("highlightSwords") == false and ShouldShowEndTurn() or not dmhub.initiativeQueue:ChoosingTurn() then
                element:SetClass("highlightSwords", false)
                return
            end

            element:SetClass("highlightSwords", false)

            local tokens = dmhub.allTokens
            for _,token in ipairs(tokens) do
                if token.topsheet ~= nil then
                    local swords = token.topsheet:GetChildrenWithClassRecursive("swords")[1]
                    if swords ~= nil then
                        swords:SetClass("highlight", false)
                        swords:SetClass("highlightActive", false)
                    end
                end
            end
        end,
        
        press = function(self)
            if ShouldShowEndTurn() then
				GameHud.instance:NextInitiative(function()
				    dmhub:UploadInitiativeQueue()
                    bubblePanel:FireEventTree("refresh")
                end)

                return
            end

            if not dmhub.initiativeQueue:ChoosingTurn() then
                return
            end

            local token = dmhub.selectedOrPrimaryTokens[1]
            if token ~= nil and token.canControl then
                local initiativeid = InitiativeQueue.GetInitiativeId(token)
                if initiativeid ~= nil and (dmhub.initiativeQueue:IsEntryPlayer(initiativeid) == dmhub.initiativeQueue:IsPlayersTurn()) and token.topsheet ~= nil then
                    local nameplate = token.topsheet:GetChildrenWithClassRecursive("nameplate")[1]
                    if nameplate ~= nil then
                        nameplate:FireEvent("press")
                    end
                    return
                end
            end
        end,

		rightClick = function (self)

			if not CanControlInitiative() then
				return
			end

            local playersGoFirst = dmhub.initiativeQueue.playersGoFirst
			
			local closeMenu = {
                {
                    text = cond(dmhub.initiativeQueue.playersTurn, "Switch to Monster Turn", "Switch to Player Turn"),
                    click = function()
                        self.popup = nil
                        dmhub.initiativeQueue.playersTurn = not dmhub.initiativeQueue.playersTurn
                        dmhub:UploadInitiativeQueue()
                        bubblePanel:FireEventTree("refresh")
                    end,
                    hidden = not dmhub.initiativeQueue:BothSidesHaveUnmovedEntries(),
                },

                {
                    text = cond(playersGoFirst, "Set Enemies to Go First Each Round", "Set Players to Go First Each Round"),
                    click = function()
                        self.popup = nil
					    dmhub.initiativeQueue.playersGoFirst = not playersGoFirst
					    dmhub:UploadInitiativeQueue()
                    end,
                },
                {
                    text = "Skip to Next Round",
                    click = function()
                        self.popup = nil
						if dmhub.initiativeQueue ~= nil then
                            local nextRound = function()
                                dmhub.initiativeQueue:NextRound()
                                GameHud.instance:NewRound()
                                dmhub:UploadInitiativeQueue()
                            end
                            if ShouldShowEndTurn() then
                                bubblePanel:FireEventTree("press")
                                dmhub.Schedule(0.3, nextRound)
                            else
                                nextRound()
                            end
						end
                    end,
                },

				{
					text = "End Combat",
					click = function ()

						self.popup = nil

						if dmhub.initiativeQueue ~= nil then
							UploadDayNightInfo()
							dmhub.initiativeQueue.hidden = true
							dmhub.initiativeQueue.gameMode = "exploration"
							dmhub:UploadInitiativeQueue()

							for initiativeid,_ in pairs(dmhub.initiativeQueue.entries) do
								local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
								for _,tok in ipairs(tokens) do
                                    tok.properties:EndCombat()
									tok.properties:DispatchEvent("endcombat", {})
								end
							end


						end
						
					end
				}

			}


			self.popup = gui.ContextMenu{entries = closeMenu}



		end,

        --bubblebg
        gui.Panel{

            bgimage = mod.images.bubblebg,
            bgcolor = "white",
            width = 116,
            height = 116,
            halign = "center",


			

        },

        gui.Panel{

            bgimage = mod.images.bubbleglow,
            width = 112,
            height = 112,
            halign = "center",
            bgcolor = "#1194FF",
            brightness = 2,

			classes = "glow",

            claiming = function(element, prompt)
                element:SetClass("prompt", prompt)
            end,

			switch = function(self)
				self:SetClass("selected", not self:HasClass("selected"))
			end,

			refresh = function (self)
                if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                    self:SetClass("selected", false)
                    return
                end

				local isPlayersTurn = dmhub.initiativeQueue:IsPlayersTurn()

				if isPlayersTurn then
					self:SetClass("selected", true)
				else
					self:SetClass("selected", false)
				end
				
			end,

        },

		gui.Label{

            fontFace = "Book",
            text = "Hero\n<size=90%>Turn</size>",
            textAlignment = "center",
            fontSize = 26,
            brightness = 2,
            width = "auto",
            height = "auto",
            minWidth = 120,
            --bgimage = mod.images.heroturntext,
            bgcolor = "white",
            --width = 69,
            --height = 39,
            halign = "center",
			valign = "center",

			classes = "text",

            claiming = function(element, val)
                element:SetClass("hidden", val)
            end,

			refresh = function (element)
                if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                    element:SetClass("selected", false)
                    return
                end

                if ShouldShowEndTurn() then
                    element:SetClass("selected", false)
                    return
                end

				local isPlayersTurn = dmhub.initiativeQueue:IsPlayersTurn()

				if not isPlayersTurn then
					element:SetClass("selected", false)
                elseif not element:HasClass("selected") then
                    local delay = 0
                    if dmhub.initiativeQueue.turn == 1 and dmhub.initiativeQueue.round ~= 1 then
                        delay = 1.5
                    end
                    audio.FireSoundEvent("UI.TurnStart_Hero", {delay = delay})
					element:SetClass("selected", true)
				end
			end,
        },

		gui.Label{

            fontFace = "Book",
            text = "Claim\n<size=90%>Turn</size>",
            textAlignment = "center",
            fontSize = 26,
            width = "auto",
            height = "auto",
            minWidth = 120,
            --bgimage = mod.images.heroturntext,
            bgcolor = "white",
            --width = 69,
            --height = 39,
            halign = "center",
			valign = "center",

			classes = "text",

            claiming = function(element, prompt)
                element:SetClass("hidden", not prompt)
                if not prompt then
                    element:SetClass("big", false)
                    element.data.bigTime = nil
                    element.selfStyle.scale = 1
                else
                    local t = dmhub.Time()
                    local r = math.sin(t*2*math.pi)
                    if element.parent:HasClass("hover") then
                        r = 1
                    end
                    element.selfStyle.scale = 1 + (r * 0.05)
                end
            end,

            think = function(element)
                if not dmhub.initiativeQueue:ChoosingTurn() then
                    element.parent:FireEventTree("claiming", false)
                    return
                end

                local token = dmhub.selectedOrPrimaryTokens[1]
                if token ~= nil and token.canControl then
                    local initiativeid = InitiativeQueue.GetInitiativeId(token)
                    if initiativeid ~= nil and (dmhub.initiativeQueue:IsEntryPlayer(initiativeid) == dmhub.initiativeQueue:IsPlayersTurn()) then
                        element.parent:FireEventTree("claiming", true)
                        return
                    end
                end

                element.parent:FireEventTree("claiming", false)
            end,

			refresh = function (element)
                if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                    element:SetClass("selected", false)
                    element.thinkTime = nil
                    element.parent:FireEventTree("claiming", false)
                    return
                end

                if ShouldShowEndTurn() then
                    element:SetClass("selected", false)
                    element.thinkTime = nil
                    element.parent:FireEventTree("claiming", false)
                    return
                end

                if not element:HasClass("selected") then
                    local delay = 0
                    if dmhub.initiativeQueue.turn == 1 and dmhub.initiativeQueue.round ~= 1 then
                        delay = 1.5
                    end
					element:SetClass("selected", true)
                    element.thinkTime = 0.01
                    element:FireEvent("think")
                else
                    element.thinkTime = 0.01
                    element:FireEvent("think")
				end
			end,
        },



        gui.Panel{

            width = 1,
            height = 172,
            halign = "center",
            valign = "center",
            thinkTime = 0.2,
            think = function(element)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden or (not GameHud.instance) then
                    element:SetClass("invisible", true)
                    element.thinkTime = 0.2
                    playerArrow:SetClass("hidden", false)
                    enemyArrow:SetClass("hidden", false)
                    return
                end

                local initiativeid = q:CurrentInitiativeId()
                if initiativeid == nil then
                    element:SetClass("invisible", true)
                    element.thinkTime = 0.2
                    playerArrow:SetClass("hidden", false)
                    enemyArrow:SetClass("hidden", false)
                    return
                end


                local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
                if tokens == nil or #tokens == 0 then
                    element:SetClass("invisible", true)
                    element.thinkTime = 0.2
                    playerArrow:SetClass("hidden", false)
                    enemyArrow:SetClass("hidden", false)
                    return
                end

                element:SetClass("invisible", false)
                playerArrow:SetClass("hidden", true)
                enemyArrow:SetClass("hidden", true)

                local pos = {x = 0, y = 0}
                for _,tok in ipairs(tokens) do
                    local p = tok.posWithParallax
                    pos.x = pos.x + p.x
                    pos.y = pos.y + p.y
                end
                pos.x = pos.x / #tokens
                pos.y = pos.y / #tokens

                local worldPos = element.positionInWorldSpace

                local deltax = pos.x - worldPos.x
                local deltay = pos.y - worldPos.y

                local angle = math.atan(deltay, deltax)
                local angleDegrees = math.deg(angle)
                element.selfStyle.rotate = angleDegrees - 90

                element.thinkTime = 0.01
            end,
            gui.Panel{

                styles = {
                    {
                        opacity = 1,
                    },
                    {
                        selectors = {"parent:invisible"},
                        priority = 100,
                        opacity = 0,
                    },
                    {
                        selectors = {"hover"},
                        brightness = 2,
                    },
                    {
                        selectors = {"press"},
                        brightness = 0.5,
                    },
                },

                swallowPress = true,

                press = function(element)
                    local q = dmhub.initiativeQueue
                    if q == nil or q.hidden or (not GameHud.instance) then
                        return
                    end
                    local initiativeid = q:CurrentInitiativeId()
                    if initiativeid == nil then
                        return
                    end
                    local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface,
                        initiativeid)
                    if tokens == nil or #tokens == 0 then
                        return
                    end

                    dmhub.CenterOnToken(tokens[1].charid, {smooth = true})
                end,

                bgimage = mod.images.bubblearrow,
                bgcolor = "white",
                width = 71,
                height = 36,
                valign = "top",
                halign = "center",
            }
        },

        playerArrow,

        gui.Panel{
			
            bgimage = mod.images.bubbleglow,
            bgcolor = "#DE1E47",
            brightness = 2,
            width = 112,
            height = 112,
            halign = "center",
			scale = {x = -1, y = 1},

			classes = {"glow", "selected"},

			refresh = function (element)
                if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                    element:SetClass("selected", false)
                    return
                end

				local isPlayersTurn = dmhub.initiativeQueue:IsPlayersTurn()

				if isPlayersTurn then
					element:SetClass("selected", false)
				else
					element:SetClass("selected", true)
				end
				
			end,

        },

		gui.Label{

            --bgimage = mod.images.enemyturntext,
            fontFace = "Book",
            text = "Enemy\n<size=90%>Turn</size>",
            textAlignment = "center",
            fontSize = 26,
            bgcolor = "white",
            width = "auto",
            height = "auto",
            halign = "center",
			valign = "center",

			classes = {"text", "selected"},

            claiming = function(element, val)
                element:SetClass("hidden", val)
            end,

			refresh = function (self)
                if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
                    self:SetClass("selected", false)
                    return
                end

                if ShouldShowEndTurn() then
                    self:SetClass("selected", false)
                    return
                end

				local isPlayersTurn = dmhub.initiativeQueue:IsPlayersTurn()

				if isPlayersTurn then
					self:SetClass("selected", false)
                elseif not self:HasClass("selected") then
                    local delay = 0
                    if dmhub.initiativeQueue.turn == 1 and dmhub.initiativeQueue.round ~= 1 then
                        delay = 1.5
                    end
                    audio.FireSoundEvent("UI.TurnStart_Enemy", {delay = delay})
					self:SetClass("selected", true)
				end
			end,

        },

        enemyArrow,

		gui.Label{
            --bgimage = mod.images.enemyturntext,
            fontFace = "Book",
            text = "End\n<size=80%>Turn</size>",
            textAlignment = "center",
            bgcolor = "white",
            width = "auto",
            height = "auto",
            halign = "center",
			valign = "center",
            textWrap = false,
            interactable = false,

			classes = {"text", "clickable", "selected"},

			refresh = function(element)
                element:SetClass("hidden", not ShouldShowEndTurn())
			end,
        },
    }

    return bubblePanel
end


--Functions which control the GameHud's handling of the initiative bar.
--This drives the display of the initiative bar at the top of the screen.

--the card width as a percentage of the height
local CardWidthPercent = Styles.portraitWidthPercentOfHeight

local function AddInitiativeEntryPanel (element, info, playerControlled)
	local parentElement = element
	local tokens = dmhub.GetTokens{
		playerControlled = playerControlled
	}

	local count = 0
	local entries = {}

	for _,tok in ipairs(tokens) do
		local initiativeId = InitiativeQueue.GetInitiativeId(tok)
		if info.initiativeQueue ~= nil and not info.initiativeQueue:HasInitiative(initiativeId) then
			if entries[initiativeId] == nil then
				count = count + 1
			end
			entries[initiativeId] = entries[initiativeId] or {}
			local list = entries[initiativeId]
			list[#list+1] = tok
		end
	end

	if count > 0 then
		local allKey = {}
		local allTokens = {}
		for key,list in pairs(entries) do
			allKey[#allKey+1] = key
			for _,item in ipairs(list) do
				allTokens[#allTokens+1] = item
			end
		end

		entries[allKey] = allTokens

	end

	local panels = {}

	for key,list in pairs(entries) do

		local ord = 0

		local tok = list[1]
		local text = tok.name
		if (text == nil or text == "") and tok.properties:GetMonsterType() ~= nil then
			text = tok.properties:GetMonsterType()
		end

		if text == nil or text == "" then
			text = "Unnamed Token"
		end

		if type(key) == "table" then
			text = "All"
			ord = -1
		end

		local tokens = {}
		for i,tok in ipairs(list) do
			tokens[#tokens+1] = gui.CreateTokenImage(tok, {
				width = 32,
				height = 32,
				x = (i-1)*48 / #list,
				halign = "left",
				valign = "center",
				floating = true,
			})
		end

		local panel = gui.Panel{
			classes = {"entryPanel"},
			bgimage = "panels/square.png",
			data = {
				ord = ord,
			},
			click = function(element)
				if type(key) == "table" then
					for _,k in ipairs(key) do
						info.initiativeQueue:SetInitiative(k, 0, 0)
					end
				else
					info.initiativeQueue:SetInitiative(key, 0, 0)
				end
				info.UploadInitiative()

				parentElement.popup = nil
			end,
			gui.Panel{
				flow = "horizontal",
				width = 24 + 48,
				height = 32,
				valign = "center",
				children = tokens,
				halign = "left",
			},
			gui.Label{
				width = 180,
				height = 32,
				fontSize = 16,
				halign = "left",
				valign = "center",
				textAlignment = "left",
				text = text,
				color = Styles.textColor,
			}
		}

		panels[#panels+1] = panel
	end

	table.sort(panels, function(a,b)
		return a.data.ord < b.data.ord
	end)

	if #panels == 0 then
		panels[#panels+1] = gui.Label{
			text = "No entries",
			width = "auto",
			height = "auto",
			color = Styles.textColor,
			fontSize = 16,
		}
	end

	element.popup = gui.TooltipFrame(
		gui.Panel{
			styles = {
				Styles.Default,

				{
					selectors = {"entryPanel"},
					flow = "horizontal",
					height = 48,
					width = "100%",
					bgcolor = "clear",
				},
				{
					selectors = {"entryPanel", "hover"},
					bgcolor = "#ff444466",
				},
			},

			vscroll = true,
			flow = "vertical",
			width = 300,
			height = "auto",
			maxHeight = 600,

			children = panels,
		},

		{
			halign = "center",
			valign = "bottom",
		}
	)
end

--Create the initiative bar.
--   self: the GameHud object
--   info: the dmhub info object which gives us access to important game information. Some parameters we use here:
--      info.initiativeQueue: this is the initiative queue data. See initiative-queue.lua for the definition of this object. It is
--                            networked between systems.
--      info.UploadInitiative(): Whenever we change info.initiativeQueue we must call this to ensure that initiativeQueue gets networked.
--      info.tokens: This contains a table of tokens currently in the game. We scan this to check that we can see tokens and should show their initiative.
--      info.selectedOrPrimaryTokens: This contains a table of tokens that are selected, which we use to choose which tokens to roll dice for.
function GameHud.CreateInitiativeBar(self, info)

	self.initiativeInterface = info

	local mainInitiativeBar = nil
	local choiceInitiativeBar = nil

	choiceInitiativeBar = self:CreateInitiativeBarChoicePanel(info)
	self.choiceInitiativeBar = choiceInitiativeBar


    local resetTurnButton = nil

    if dmhub.isDM then
        --reset turn button -- resets to checkpoint.
        resetTurnButton = gui.Panel {
            bgimage = "panels/hud/anticlockwise-rotation.png",
            bgcolor = "#ffffffaa",
            halign = "right",
            valign = "center",
            width = 24,
            height = 24,
            floating = true,
            classes = {"unavailable"},

            data = {
                checkpoint = nil,
                checkpointRound = nil,
                checkpointTurn = nil,
                checkpointCombatid = nil,
                checkpointReason = "Reset to start of turn",
            },

            styles = {
                {
                    selectors = {"hover"},
                    brightness = 2,
                    bgcolor = "white",
                    transitionTime = 0.2,
                },
                {
                    selectors = {"unavailable"},
                    opacity = 0,
                },
            },

            thinkTime = 0.1,
            think = function(element)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden or (not q:ChoosingTurn()) then
                    if q == nil or q.hidden or element.data.checkpoint == nil then
                        element:SetClass("unavailable", true)
                    elseif element:HasClass("unavailable") then
                        element:SetClass("unavailable", false)

                        --record whose turn it is who is starting.
		                local tokens = self:GetTokensForInitiativeId(info, q.currentTurn)
                        table.sort(tokens, function(a,b)
                            return creature.ScoreTokenImportance(a) < creature.ScoreTokenImportance(b)
                        end)

                        if #tokens > 0 then
                            element.data.checkpointReason = string.format("Reset to start of %s's turn", creature.GetTokenDescription(tokens[1]))
                        else
                            element.data.checkpointReason = "Reset to start of turn"
                        end
                    end
                    return
                end

                if element.data.checkpoint ~= nil and element.data.checkpointTurn == q.turn and element.data.checkpointRound == q.round and element.data.checkpointCombatid == q.guid then
                    --hidden until we start a turn.
                    element:SetClass("unavailable", true)
                    return
                end

                element.data.checkpointTurn = q.turn
                element.data.checkpointRound = q.round
                element.data.checkpointCombatid = q.guid

                element.data.checkpoint = backup.CreateCombatCheckpoint()

                --hidden until we start a turn.
                element:SetClass("unavailable", true)
            end,

            hover = function(element)
                gui.Tooltip(element.data.checkpointReason)(element)
            end,

            press = function(element)
                if element:HasClass("unavailable") then
                    return
                end
                element.data.checkpoint:Restore()
				audio.DispatchSoundEvent("Notify.Director_Undo")
            end,
        }
    end

	local addCharacters
	local addMonsters

	--[[if dmhub.isDM then

		addCharacters = gui.AddButton{
			halign = "left",
			valign = "center",
			floating = true,
			x = -60,
			width = 24,
			height = 24,
			hover = gui.Tooltip("Add Character to initiative"),
			click = function(element)
				AddInitiativeEntryPanel(element, info, true)
			end,
		}

		addMonsters = gui.AddButton{
			halign = "right",
			valign = "center",
			floating = true,
			x = 60,
			width = 24,
			height = 24,
			hover = gui.Tooltip("Add Monster to initiative"),
			click = function(element)
				AddInitiativeEntryPanel(element, info, false)
			end,
		}
	end]]

	--The parent / top-level initiative bar.
	return gui.Panel({
		floating = true,
		selfStyle = {
			valign = 'top',
			halign = 'center',
		},

		className = 'initiative-panel',
        height = 200,
        width = 500,
        tmargin = 0,

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
				--y = -300,
				transitionTime = 0,
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
				transitionTime = 0,
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
			},

			{
				selectors = {"initiativeEntryPanel", "turn"},
				y = -8,
                transitionTime = 0,
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
				brightness = 1.5,
				transitionTime = 0,
			},

			{
				selectors = {"initiativeEntryBorder", "parent:hadTurn"},
				brightness = 0.3,
				transitionTime = 0,
			},

		},

		events = {

			refresh = function(element)
				--detect if we are using initiative. If we aren't, then hide the initiative bar completely for players
				--and simply show a slither of it for the DM so they can click on it to activate initiative.
				element:SetClass('no-initiative', info.initiativeQueue == nil or info.initiativeQueue.hidden)
			end,

			click = function(element)
                if not CanControlInitiative() or (info.initiativeQueue ~= nil and (not info.initiativeQueue.hidden)) then
                    return
                end
                local entries = {}
                for i=1,#InitiativeQueue.GameModes do
                    local mod = InitiativeQueue.GameModes[i]
                    entries[#entries+1] = {
                        text = mod.text,
                        click = function()
                            element.popup = nil

					        UploadDayNightInfo()
                            if info.initiativeQueue == nil then
                                info.initiativeQueue = InitiativeQueue.Create()
                            end
                            info.initiativeQueue.gameMode = mod.id
                            info.UploadInitiative()

                            if mod.hasinitiative then
                                Commands.rollinitiative()
                                return
                            end

                        end,
                    }
                end

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
			end,
		},

		children = {
			--background shadow
			--[[gui.Panel{
				id = "initiativeShadow",
				interactable = false,
				bgimage = 'panels/initiative/shadow.png',
				width = "160%",
				height = 400,
				valign = "top",
				halign = "center",
			},]]

			--text at the top saying initiative.
			gui.Panel{
				halign = "center",
				valign = "top",
				width = "auto",
				height = "auto",
				flow = "vertical",

				--[[gui.Label({
					text = 'Draw Steel',

					vmargin = 8,
					fontFace = "SupernaturalKnight",
					fontSize = 30,
					color = Styles.textColor,
					valign = 'top',
					halign = 'center',
					textAlignment = 'center',
					width = 'auto',
					height = 'auto',
				}),]]

				gui.Label{ 
					text = '',
					fontFace = "Book",
					fontSize = 18,
					color = Styles.textColor,
					valign = 'top',
					halign = 'center',
					textAlignment = 'center',
					width = 180,
					height = 24,
					vmargin = 0,
					y = 15,

					refresh = function(element)
						if info.initiativeQueue == nil or info.initiativeQueue.hidden then
                            if info.initiativeQueue == nil then
                                element.text = "Exploration"
                            else
                                element.text = info.initiativeQueue:GameModeInfo().text
                            end
						else
							element.text = string.format('Round %d', info.initiativeQueue.round)
						end
					end,

					--[[gui.Panel{
						classes = {"clickableIcon"},
						bgimage = "panels/hud/clockwise-rotation.png",
						bgcolor = Styles.textColor,
						floating = true,
						halign = "right",
						valign = "center",
						width = 16,
						height = 16,

						hover = gui.Tooltip("Skip to next round"),

						refresh = function(element)
							if (not dmhub.isDM) or info.initiativeQueue == nil or info.initiativeQueue.hidden or (not info.initiativeQueue:ChoosingTurn()) then

								--If there is no initiative then hide the button.
								element:AddClass('hidden')
							else
								element:RemoveClass('hidden')
							end
						end,

						click = function(element)
							if info.initiativeQueue ~= nil then
								info.initiativeQueue:NextRound()
								self:NewRound()
								info.UploadInitiative()
							end
						end,
					},]]

                    resetTurnButton,

				},

				addCharacters,
				addMonsters,
			},


			mainInitiativeBar,
			choiceInitiativeBar,

			--button to close the initiative queue.
			--[[gui.CloseButton({
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
					x = 0,
					y = 35,
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
			}),]]

		},
	})
end

function GameHud.CreateInitiativeBarChoicePanel(self, info)

	local choicePanel

	--anthem data.
	local m_anthemEventInstance = nil
	local m_anthemTokenId = nil

	local StopAnthem = function()
		if m_anthemEventInstance ~= nil then
			m_anthemEventInstance:Stop()
			m_anthemEventInstance = nil
			m_anthemTokenId = nil

			choicePanel.monitorGame = nil
		end
	end

	local entries = {}

	local CreateContainer = function(playerside)
		local m_label = gui.Label{

			styles = {
				{
					color = Styles.textColor,
				},
				{
					selectors = {"inactive"},
					color = "#666666",
				},
				{
					selectors = {"inactive", "hover"},
					color = "#ffffff",
				},
			},

			press = function(element)
				if element:HasClass("inactive") and CanControlInitiative() then
					info.initiativeQueue.playersTurn = not info.initiativeQueue.playersTurn
					info.UploadInitiative()
				end
			end,

			bgimage = "panels/square.png",
			bgcolor = "#000000bb",
			cornerRadius = 6,
			pad = 2,
			fontSize = 16,
			width = "auto",
			height = "auto",
			text = cond(playerside, "Player's Turn", "Monster's Turn"),
		}

		local m_wonInitiativeIndicator = gui.Panel{
			bgimage = "panels/initiative/initiative-icon2.png",
			bgcolor = "white",
			width = 16,
			height = 16,
			halign = "left",
			valign = "center",
			hmargin = 6,
			linger = function(element)
				gui.Tooltip(string.format("%s %s Initiative", cond(playerside, "Players", "Monsters"), cond(info.initiativeQueue.playersGoFirst == playerside, "Won", "Lost")))(element)
			end,

			press = function(element)
				if CanControlInitiative() and (not element:HasClass("won")) then
					info.initiativeQueue.playersGoFirst = playerside
					info.UploadInitiative()

					element.tooltip = nil
				end
			end,

			styles = {
				{
					selectors = {"won"},
					brightness = 2.0,
				},
				{
					selectors = {"~won"},
					brightness = 0.2,
				},
				{
					selectors = {"~won", "hover"},
					brightness = 0.6,
				},
			}
		}

		return gui.Panel{
			styles = {
				{
					selectors = {"initiativeEntryContainer"},
					bgcolor = "clear",
				},
				{
					selectors = {"initiativeEntryContainer", "drag-target"},
					bgcolor = "#ffffff22",
					borderWidth = 2,
					borderColor = "white",
				},
				{
					selectors = {"initiativeEntryContainer", "drag-target-hover"},
					bgcolor = "#ffffff44",
					borderColor = "yellow",
				},
			},
			dragTarget = true,
			classes = {"initiativeEntryContainer"},
			halign = cond(playerside, "left", "right"),
			width = 260,
			height = 96,
			bgimage = "panels/square.png",
			flow = "horizontal",
			data = {
				player = playerside,
				label = m_label,
				wonInitiativeIndicator = m_wonInitiativeIndicator,
			},

			gui.Panel{
				floating = true,
				flow = "horizontal",
				height = "auto",
				width = "auto",
				halign = "center",
				valign = "bottom",
				y = 32,
				m_wonInitiativeIndicator,
				m_label,

				classes = "hidden",
			},
		}
	end

    
	local playerContainer = CreateContainer(true)
	local monsterContainer = CreateContainer(false)

    local drawSteelBubble = CreateDrawSteelBubble()

	choicePanel = gui.Panel{
		width = 800,
		height = 96,
		y = 40,
		flow = "none",
        halign = "center",

		styles = {
			{
				selectors = {"initiativeEntryPanel"},

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
				selectors = {"initiativeEntryBorder", "~parent:unselectable", "parent:hover"},
				brightness = 1.5,
				transitionTime = 0.5,
			},
			{
				selectors = {"initiativeEntryBorder", "parent:hadTurn"},
				brightness = 0.3,
				transitionTime = 0.5,
			},

			{
				selectors = {"avatar", "parent:hadTurn"},
				saturation = 0.2,
			},

            {
                selectors = {"initiativeEntryParent"},
                lmargin = 0,
                rmargin = 0,
                --transitionTime = 0.5,
                moveTime = 0.5,
            },

            {
                selectors = {"initiativeEntryParent", "repel"},
                lmargin = 60,
                rmargin = 60,
                --transitionTime = 0.5,
                moveTime = 0.5,
            },

            Styles.TriggerStyles,
		},

		playerContainer,
        drawSteelBubble,
		monsterContainer,

		--The 'End Turn' button which is pressed to end the current token's turn. It is only shown to the DM
		--and to players if it is currently their turn (their token is first in the initiative queue).
		--[[gui.FancyButton({
			floating = true,
			bgimage = 'panels/square.png',
			text = 'End Turn',
			y = 30,
			halign = "center",
			valign = "bottom",
			width = 120,
			height = 36,
			fontSize = 20,
			events = {
				click = function(element)
					self:NextInitiative()
					info.UploadInitiative()
				end,

				refresh = function(element)
					if info.initiativeQueue == nil or info.initiativeQueue.hidden or (not self:has_key('currentInitiativeId')) or info.initiativeQueue.currentTurn == false or info.initiativeQueue:ChoosingTurn() then

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
		}),]]



		refresh = function(element)

            local initiativeQueue = info.initiativeQueue
			if initiativeQueue == nil or initiativeQueue.hidden then
				--initiative queue is inactive so just hide this.
				element:SetClass('hidden', true)
				return
			else
				element:SetClass('hidden', false)
			end

			self.currentInitiativeId = initiativeQueue.currentTurn or nil

			local isPlayersTurn = initiativeQueue:IsPlayersTurn()

			playerContainer.data.label:SetClass("inactive", not isPlayersTurn)
			monsterContainer.data.label:SetClass("inactive", isPlayersTurn)

			playerContainer.data.wonInitiativeIndicator:SetClass("won", initiativeQueue.playersGoFirst)
			monsterContainer.data.wonInitiativeIndicator:SetClass("won", not initiativeQueue.playersGoFirst)
			
			local playerChildren = {playerContainer.data.label.parent}
			local monsterChildren = {monsterContainer.data.label.parent}
			local newEntries = {}
			for k,v in pairs(initiativeQueue.entries) do
				local isplayer = initiativeQueue:IsEntryPlayer(k)
				if entries[k] ~= nil and entries[k].data.isplayer == isplayer then
					newEntries[k] = entries[k]
				else
					newEntries[k] = self:CreateInitiativeEntry(info, k, {
						click = function(element)

                            print("CLICK:: CONTROL:", CanControlInitiative(), "CHOOSING:", initiativeQueue:ChoosingTurn(), "PLAYERSTURN:", initiativeQueue:IsPlayersTurn(), "UNMOVED:", initiativeQueue:EntriesUnmoved()[k])
							if CanControlInitiative() == false and ((not initiativeQueue:ChoosingTurn()) or (not initiativeQueue:IsPlayersTurn()) or (not initiativeQueue:EntriesUnmoved()[k]) or (not initiativeQueue:IsEntryPlayer(k))) then --or element:HasClass("unselectable") then
								return
							end
							initiativeQueue:SelectTurn(k)
							info.UploadInitiative()

							local tokens = self:GetTokensForInitiativeId(info, v.initiativeid)
							for i,tok in ipairs(tokens) do
								if tok.properties ~= nil then
									tok.properties:BeginTurn()
								end
							end
						end,
					})
					newEntries[k]:SetClass("player", isplayer)
					newEntries[k]:SetClass("monster", not isplayer)

					--parent this panel to a new panel so we can center it.
					gui.Panel{
                        classes = {"initiativeEntryParent"},
						halign = "center",
						valign = "center",
						height = "auto",
						width = 1,
						newEntries[k],
					}
				end

				local panel = newEntries[k]
				panel.data.isplayer = isplayer

				local turn = initiativeQueue.currentTurn == k
				local unmoved = initiativeQueue:EntryUnmoved(v)
				panel:SetClass("turn", turn)
				panel.parent:SetClass("repel", turn)
				panel:SetClass("unmoved", unmoved)
				panel:SetClass("hadTurn", not unmoved)
				panel:SetClass("unselectable", (not unmoved) or (isPlayersTurn ~= isplayer))

				if isplayer then
					playerChildren[#playerChildren+1] = panel.parent
				else
					monsterChildren[#monsterChildren+1] = panel.parent
				end
			end

			playerContainer.children = playerChildren
			monsterContainer.children = monsterChildren

			entries = newEntries


			--calculate anthem of the currently playing token.
            local currentInitiativeId = self:try_get("currentInitiativeId")
            if currentInitiativeId == nil then
                StopAnthem()
            elseif currentInitiativeId ~= element.data.anthemInitiativeId then
                local anthemToken = nil
                if currentInitiativeId ~= nil then
                    local tokens = self:GetTokensForInitiativeId(info, self.currentInitiativeId)
                    for i,tok in ipairs(tokens) do
                        local anthem = tok.anthem
                        if anthem ~= nil and anthem ~= "" then
                            anthemToken = tok
                        end
                    end
                end

                if anthemToken ~= nil and anthemDuration:Get() >= 1 then
                    if anthemToken.charid ~= m_anthemTokenId then
                        StopAnthem()
                        m_anthemTokenId = anthemToken.charid
                        local asset = assets.audioTable[anthemToken.anthem]
                        if asset ~= nil then
                            m_anthemEventInstance = asset:Play()
                            m_anthemEventInstance.volume = anthemToken.anthemVolume
                            m_anthemEventInstance:SetStopAfter(anthemDuration:Get())
                            element.monitorGame = anthemToken.monitorPath
                        end
                    end
                else
                    StopAnthem()
                end
            end

            --only recalculate anthems once per change of turn.
            element.data.anthemInitiativeId = currentInitiativeId

		end,


		disable = function(element)
			StopAnthem()
		end,

		--fired when the token playing the anthem changes. Will update the volume of the anthem.
		refreshGame = function(element)
			if m_anthemEventInstance ~= nil and m_anthemTokenId ~= nil then
				local tok = dmhub.GetTokenById(m_anthemTokenId)
				if tok ~= nil then
					m_anthemEventInstance.volume = tok.anthemVolume
				else
					StopAnthem()
				end
			end
		end,
	}

	return choicePanel
end 

function GameHud:NextInitiative(oncomplete)
	local info = self.initiativeInterface
	local mainInitiativeBar = self.choiceInitiativeBar

	--End the turn in initiative queue data and upload the changes.
	if self:has_key('currentInitiativeId') then
		local tokens = self:GetTokensForInitiativeId(info, self.currentInitiativeId)
        

        --we have to dispatch end turn BEFORE we change to the next turn,
        --otherwise effects that block until end of turn will not work for any end turn
        --events. e.g. if a creature is immune from damage for its turn but then
        --damage is done in the end turn event it still shouldn't take damage.
		for i,tok in ipairs(tokens) do
			if tok.properties ~= nil then
				tok.properties:EndTurn(tok)
			end
		end

        --wait a small delay until next round to give a chance for events to proc.
        --TODO: maybe a mechanism for counting in process abilities/coroutines and
        --waiting for them to finish before we start the next turn?
        dmhub.Schedule(0.1, function()
            local newRound = info.initiativeQueue:NextTurn(self.currentInitiativeId)

            if newRound then
                self:NewRound()
            end

            --recalculate self.currentInitiativeId
            mainInitiativeBar:FireEvent("refresh")
            if oncomplete ~= nil then
                oncomplete()
            end
        end)

	end
end

local g_beginRoundStyles = {
    gui.Style{
        selectors = {"leftSword","new"},
        transitionTime = 0.5,
        x = 50,
        opacity = 0,
    },
    gui.Style{
        selectors = {"rightSword","new"},
        transitionTime = 0.5,
        x = -50,
        opacity = 0,
    },
    gui.Style{
        selectors = {"label", "new"},
        transitionTime = 0.5,
        opacity = 0,
        scale = {x = 0, y = 1},
    }
}

--- @class BeginRoundChatMessage
BeginRoundChatMessage = RegisterGameType("BeginRoundChatMessage")
BeginRoundChatMessage.round = 0
function BeginRoundChatMessage.Render(self, message)

    local isNew = true --TimestampAgeInSeconds(message.timestamp) < 5
    local newStyle = cond(isNew, "new")

    local resultPanel

    resultPanel = gui.Panel{
        styles = g_beginRoundStyles,
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        gui.Panel{
			classes = {'separator'},
		},
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",

            gui.Panel{
                classes = {"leftSword", newStyle},
                bgimage = "panels/initiative/drawsteel-sword.png",
                bgcolor = "white",
                width = 80,
                height = "50% width",
                valign = "center",
                halign = "center",
            },

            gui.Label{
                classes = {newStyle,"chat-message-text"},
                text = string.format("Round %d", self.round),
                bold = true,
                width = "auto",
                height = "auto",
                fontSize = 16,
                color = Styles.textColor,
                valign = "center",
                halign = "center",
            },

            gui.Panel{
                classes = {"rightSword", newStyle},
                bgimage = "panels/initiative/drawsteel-sword.png",
                bgcolor = "white",
                width = 80,
                height = "50% width",
                valign = "center",
                halign = "center",
                scale = {x = -1, y = 1},
            },
        },
    }

    resultPanel:SetClassTree("new", false)

    return resultPanel
end


function GameHud:NewRound()
	local info = self.initiativeInterface

	for initiativeid,_ in pairs(info.initiativeQueue.entries) do
		local tokens = self:GetTokensForInitiativeId(info, initiativeid)
		for _,tok in ipairs(tokens) do
            tok.properties:EndRound(tok)
		end
	end

    Aura.CheckObjectAuraExpirationEndOfRound()

    local message = BeginRoundChatMessage.new{
        round = info.initiativeQueue.round,
    }
    chat.SendCustom(message)
end


local function CreateBossTurnsPanel()
	local m_panels = {}
	return gui.Panel{
		width = "auto",
		height = "auto",
		flow = "horizontal",
		halign = "left",
		valign = "bottom",
		margin = 4,
		floating = true,

		refreshBossTurns = function(element, initiativeQueue, entry)
			local total = entry.turnsPerRound
			local consumed = entry.turnsTaken
			if entry.round < initiativeQueue.round then
				consumed = 0
			elseif entry.round > initiativeQueue.round then
				consumed = total
			end

			if total ~= #m_panels then
				while total < #m_panels do
					m_panels[#m_panels] = nil
				end

				while total > #m_panels do
					m_panels[#m_panels+1] = gui.Panel{
						bgimage = "panels/square.png",
						bgcolor = "white",
						borderWidth = 1,
						borderColor = "white",
						width = 10,
						height = 10,
						cornerRadius = 5,
						hmargin = 2,
					}
				end

				element.children = m_panels
			end

			for i,p in ipairs(m_panels) do
				local isConsumed = i > total - consumed
				p.selfStyle.bgcolor = cond(isConsumed, "black", "white")
			end

		end,
	}
end

--Creates a single initiative entry. This consists of a panel with an image, a display of the initiative number, etc.
function GameHud.CreateInitiativeEntry(self, info, initiativeid, options)

	options = options or {}

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

	local bgnameLabel = gui.Label{
		fontFace = "Book",
		halign = "center",
		valign = "bottom",
		vmargin = 0,
		width = "auto",
		height = "auto",
		maxWidth = 64,
		textWrap = false,
		fontSize = 16,
		minFontSize = 6,
	}
	--[[local nameLabel = gui.Label{
		fontFace = "Book",
		halign = "center",
		valign = "bottom",
		vmargin = 0,
		width = "auto",
		height = "auto",
		maxWidth = 64,
		textWrap = false,
		fontSize = 16,
		minFontSize = 6,
		refresh = function(element)
			if token ~= nil and token.properties ~= nil and (token.canControl or not token.namePrivate) then
				element:SetClass("collapsed", false)
				bgnameLabel:SetClass("collapsed", false)

				local bglabel = bgnameLabel

				local textColor = nil
				local squad = token.properties:MinionSquad()
				if squad ~= nil then
				   textColor = DrawSteelMinion.GetSquadColor(squad)
				else
					textColor = token.playerColor
				end

				local text = token:GetNameMaxLength(30)

				if text ~= nil then
					local offsetScale = 0.85 ^ math.max(0, #text - 10)
					bglabel.x = 1.5 * offsetScale
					bglabel.y = 4 - 1.5 * offsetScale
				end

				element.selfStyle.italics = token.namePrivate
				element.selfStyle.brightness = cond(token.namePrivate, 0.8, 1)
				element.text = text

				bglabel.selfStyle.italics = token.namePrivate
				bglabel.selfStyle.brightness = cond(token.namePrivate, 0.8, 1)
				bglabel.text = text

				local lightbg = TokenHud.UseLightBackgroundColor(core.Color(textColor))
				if lightbg then
					bglabel.selfStyle.color = textColor
					element.selfStyle.color = "white"
				else
					bglabel.selfStyle.color = "black"
					element.selfStyle.color = textColor
				end
			else
				element:SetClass("collapsed", true)
				bgnameLabel:SetClass("collapsed", true)
			end
		end,
	}]]

    local m_triggeredActionPanels = {}

    local triggerPanel = gui.Panel{
        halign = "left",
        valign = "bottom",
        flow = "vertical",
        hmargin = 2,
        vmargin = 3,
        width = 24,
        height = 60,
		refresh = function(element)
			if token == nil or (not token.valid) or token.properties.minion then
				element:SetClass("collapsed", true)
				return
			end

            local charid = token.charid

			local resources = token.properties:GetResources()
			local usage = token.properties:GetResourceUsage(g_triggeredResourceId, "round")
			local expended = (usage >= (resources[g_triggeredResourceId] or 0))

            local children = {}
            local newTriggeredActionPanels = {}
            local triggeredActions = token.properties:GetTriggeredActions()
            for _,action in ipairs(triggeredActions) do
                if action.type ~= "free" then
                    local p = m_triggeredActionPanels[action.guid] or gui.TriggerPanel{
                        classes = {action.type, cond(expended, "expended")},
                        width = 20,
                        height = 20,
                        valign = "bottom",
                        lmargin = 2,
                        vmargin = 1,
                        hover = function(element)
                            element.tooltip = gui.TooltipFrame(action:Render{
                                token = dmhub.GetTokenById(charid),
                            }, {
                                halign = "center",
                                valign = "bottom",
                            })
                        end,
                    }

                    p:SetClass("expended", expended)

                    newTriggeredActionPanels[action.guid] = p
                    children[#children+1] = p
                end
            end

            m_triggeredActionPanels = newTriggeredActionPanels
            element.children = children
        end,
    }

	local closeButton = nil

	--The DM has an 'X' button which lets them remove initiative entries.
	if CanControlInitiative() then

		closeButton = gui.CloseButton({
			events = {
				--remove the initiative entry.
				click = function(element)
					
					if self:has_key("currentInitiativeId") and self.currentInitiativeId == initiativeid then
						--if it's currently this creature's turn, move to next
						info.initiativeQueue:CancelTurn(initiativeid)
					else
						info.initiativeQueue:RemoveInitiative(initiativeid)
					end

					info.UploadInitiative()
				end
			},

            --inner white bordered button. Outer button is black to give an outline.
            gui.CloseButton{
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                brightness = 1,
            },

			selfStyle = {
                bgcolor = "black",
				halign = "left",
				valign = "top",
				hmargin = 0,
				vmargin = 0,
				width = 30,
				height = 30,
			},
		})

		--this isn't shown by default, only when hovering over the panel.
		closeButton:AddClass('hidden')
	end

	local playerColor = "black"
	if token ~= nil then
		playercolor = token.playerColor.tostring
	end

	local orderLabel = gui.Label{
		classes = {"hidden"},
		floating = true,
		halign = "center",
		valign = "center",
		width = "auto",
		height = "auto",
		fontSize = 62,
		bold = true,
		color = Styles.textColor,
		text = "2",
		textOutlineWidth = 0.2,
		textOutlineColor = "black",
	}

	local m_bossTurnsPanel = nil
    local m_containerPanel = nil

	--this is the initiative entry panel.
	return gui.Panel({

		classes = {"initiativeEntryPanel"},

		draggable = CanControlInitiative(),
		drag = function(element, target)
			if target == nil or (not target:HasClass("initiativeEntryContainer")) then
				return
			end

			local entry = info.initiativeQueue.entries[initiativeid]
			if entry ~= nil and entry:try_get("player") ~= target.data.player then
				entry.player = target.data.player
				info.UploadInitiative()
			end
		end,
		canDragOnto = function(element, target)
			if target ~= nil and target:HasClass("initiativeEntryContainer") then
				return true
			end

			return false
		end,

		events = {
			click = function(element)

                print("CLICK::", options.click ~= nil)
				if options.click ~= nil then
					options.click(element)
				end

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

            rightClick = function(element)
                local q = info.initiativeQueue
                if q == nil or q.hidden then
                    return
                end

                local entry = q.entries[initiativeid]
                if entry == nil then
                    return
                end

                local entries = {}

                if q.currentTurn == initiativeid then
                    entries[#entries+1] = {
                        text = "Revert Turn",
                        click = function()
                            element.popup = nil
                            q:CancelTurn(initiativeid)
                            info.UploadInitiative()
                        end,
                    }
                elseif q:EntryUnmoved(entry) then
                    entries[#entries+1] = {
                        text = "Set Has Moved",
                        click = function()
                            element.popup = nil
                            q:SetTurnTaken(entry)
                            info.UploadInitiative()
                        end,
                    }
                else
                    entries[#entries+1] = {
                        text = "Set Has Not Moved",
                        click = function()
                            element.popup = nil
                            q:SetTurnNotTaken(entry)
                            info.UploadInitiative()
                        end,
                    }
                end

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
            end,

			refresh = function(element)
				--check if the token still exists. If it doesn't we collapse this entry
				token = GetMatchingToken()
				if token == nil or info.initiativeQueue == nil then
					element.parent:AddClass('collapsed')
                    return
				else
					element.parent:RemoveClass('collapsed')
				end

				local entry = info.initiativeQueue.entries[initiativeid]
				if entry ~= nil and entry.round == info.initiativeQueue.round+1 then
					orderLabel.text = tostring(entry.turn)
					orderLabel:RemoveClass("hidden")
				else
					orderLabel:AddClass("hidden")
				end

				if entry ~= nil and entry.turnsPerRound > 1 then
					if m_bossTurnsPanel == nil then
						m_bossTurnsPanel = CreateBossTurnsPanel()
						element:AddChild(m_bossTurnsPanel)
					end

					m_bossTurnsPanel:FireEvent("refreshBossTurns", info.initiativeQueue, entry)
				elseif m_bossTurnsPanel ~= nil then
					m_bossTurnsPanel:DestroySelf()
					m_bossTurnsPanel = nil
				end
			end,

            highlightTokens = function(element, tokens)
                local highlighted = {}
                if tokens ~= nil and #tokens > 0 then
                    for _,token in ipairs(tokens) do
                        highlighted[token.charid] = true
                        dmhub.PulseHighlightToken(token.charid)

                        if token.bottomsheet ~= nil then
                            token.bottomsheet:SetClassTree("highlighted", true)
                        end
                    end
                end

                element.data.highlighted = highlighted
            end,

            dehighlightTokens = function(element)
                local highlighted = element.data.highlighted or {}
                for charid,_ in pairs(highlighted) do
                    local token = dmhub.GetTokenById(charid)
                    if token ~= nil and token.valid and token.bottomsheet ~= nil then
                        token.bottomsheet:SetClassTree("highlighted", false)
                    end
                end
                element.data.highlighted = {}
            end,

			--If we're the DM and the close button is available, then show/hide it when we hover or dehover this panel.
			hover = function(element)
                element:FireEvent("dehighlightTokens")
				local tokens = self:GetTokensForInitiativeId(info, initiativeid)
				if tokens ~= nil and #tokens > 0 then
					for _,tok in ipairs(tokens) do
						dmhub.PulseHighlightToken(tok.id)
					end

                    element:FireEvent("highlightTokens", tokens)
				end

				if closeButton ~= nil then
					closeButton:RemoveClass('hidden')
				end

				local tooltip = nil
				if token ~= nil then
					if token.canLocalPlayerSeeName then
						tooltip = token.name
					end

					if tooltip == nil or tooltip == '' or token.properties:MinionSquad() ~= nil then
						if dmhub.isDM and token.properties ~= nil and token.properties:GetMonsterType() ~= nil then
							tooltip = token.properties:GetMonsterType()

							if token.properties:MinionSquad() ~= nil and #tokens > 1 then
								local minionType = nil
								local captainType = nil

								for i,tok in ipairs(tokens) do
									if tok.properties ~= nil then
										if tok.properties.minion then
											minionType = tok.properties:GetMonsterType()
										else
											captainType = tok.properties:GetMonsterType()
										end
									end
								end

								if minionType ~= nil then
									tooltip = token.properties:MinionSquad()
									if captainType ~= nil then
										tooltip = string.format("%s\nCaptain: %s", tooltip, captainType)
									end
								end

							end
						else
							tooltip = 'NPC/Monster'
						end
					else
						local playerName = token.playerName
						if playerName ~= tooltip then
							tooltip = string.format('%s (%s)', tooltip, playerName)
						end
					end
				end

				if tooltip ~= nil and tooltip ~= "" then
					gui.Tooltip(tooltip)(element)
				end
			end,

			dehover = function(element)
                element:FireEvent("dehighlightTokens")
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
			gui.Panel{
				classes = {"avatar"},
				bgimage = 'panels/square.png',
				height = "100%",
				width = "100%",
				valign = 'top',
				halign = 'center',
				bgcolor = 'white',

				refresh = function(element)
                    m_containerPanel = m_containerPanel or element:FindParentWithClass("initiativeEntryParent")

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
                                local portrait = token.offTokenPortrait
								element.bgimage = portrait
                                if portrait ~= token.portrait and not token.popoutPortrait then
                                    element.selfStyle.imageRect = nil
                                else
								    element.selfStyle.imageRect = token:GetPortraitRectForAspect(CardWidthPercent*0.01, portrait)
                                end
								found = true
							end

							quantity = quantity+1
						end
					end

                    if m_containerPanel ~= nil then
                        m_containerPanel:SetClass("collapsed", not found)
                    end

					--display the quantity here.
					if quantity <= 1 then
						quantityLabel.text = ''
					else
						quantityLabel.text = string.format("x%d", quantity)
					end
				end,

				gui.Panel{

					bgimage = true,
					bgcolor = "#A90004",
					opacity = 0.7,
					width = "100%",
					height = "60%",
					valign = "bottom",

					refresh = function(element)

						local tokens = self:GetTokensForInitiativeId(info, initiativeid)
						if tokens == nil or #tokens == 0 or #tokens > 1 then
							element.selfStyle.height = "0%"
							return
						end

                        if (not tokens[1].canControl) and not tokens[1].isFriendOfPlayer then
							element.selfStyle.height = "0%"
							return
                        end

						--- @type CharacterToken
						local token = tokens[1]
						local healthCalc = 100-(token.properties:CurrentHitpoints()/token.properties:MaxHitpoints())*100
						if healthCalc > 100 then 
							healthCalc = 100
						end
						local health = string.format("%f%%", healthCalc)
						

						element.selfStyle.height = health
						


					end,

				},

			},

			gui.Panel{
				classes = {"initiativeEntryBorder"},
				bgimage = "panels/square.png",
			},

			quantityLabel,
			bgnameLabel,
			--nameLabel,
            triggerPanel,


			--[[gui.Panel{
				classes = {"initiativeArrow"},
				floating = true,
				press = function(element)
				end,
			},]]
		

			closeButton,

			orderLabel,
		}
	})
end

--This utility function is given an initiative ID and finds the list of tokens that match that initiative ID.
--For a character this will give back that single character token.
--For monsters it will give back all monsters of that type.
function GameHud.GetTokensForInitiativeId(self, info, initiativeid)
    return InitiativeQueue.GetTokensForInitiativeId(initiativeid, dmhub.allTokens)
end

--automatically rebuilds with each save. turn off for graphical work
dmhub.RebuildGameHud()

--a dummy bubble for development:
--gui.ShowDialog(mod, CreateDrawSteelBubble())