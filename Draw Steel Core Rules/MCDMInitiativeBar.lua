local mod = dmhub.GetModLoading()

local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local g_triggeredResourceId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"

local anthemLimited = setting{
    id = "anthemlimited",
    description = "Limit Anthem Lengths",
    editor = "check",
    default = true,
    ord = 101,
    storage = "game",
    section = "audio",
    classes = {"dmonly"},
}

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

	monitorVisible = {'anthemlimited'},
	visible = function()
		return dmhub.GetSettingValue('anthemlimited')
	end
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
        uiscale = 0.8,
        width = 120,
        height = 120,
        halign = "center",
		valign = "top",
        y = 50,



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
                fontSize = 22,
            },
            {
                selectors = {"text", "clickable", "parent:hover"},
                fontSize = 24,
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
                    text = cond(playersGoFirst, "Set Monsters to Go First Each Round", "Set Players to Go First Each Round"),
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

							local monsterCount = 0
							for initiativeid,_ in pairs(dmhub.initiativeQueue.entries) do
								local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
								for _,tok in ipairs(tokens) do
									if not tok.properties:IsHero() then
										monsterCount = monsterCount + 1
									end
								end
							end

							track("malice_at_combat_end", {
								maliceRemaining = CharacterResource.GetMalice(),
								roundCount = dmhub.initiativeQueue.round,
								monsterCount = monsterCount,
								dailyLimit = 10,
							})

							dmhub.initiativeQueue.hidden = true
							dmhub.initiativeQueue.gameMode = "exploration"
							dmhub:UploadInitiativeQueue()

                            CharacterResource.SetMalice(0, "End of Combat")

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
            brightness = 2,
            width = "auto",
            height = "auto",
            minWidth = 120,
            --bgimage = mod.images.heroturntext,
            bgcolor = "white",
            --width = 69,
            --height = 39,
            vmargin = 10,
            halign = "center",
			valign = "center",
            y = 26,

			classes = {"text", "clickable", "selected"},

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
            text = "Claim\n<size=80%>Turn</size>",
            textAlignment = "center",
            width = "auto",
            height = "auto",
            minWidth = 120,
            --bgimage = mod.images.heroturntext,
            bgcolor = "white",
            --width = 69,
            --height = 39,
            y = 26,
            halign = "center",
			valign = "center",

			classes = {"text", "clickable", "selected"},

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
                element.selfStyle.rotateNumber = angleDegrees - 90

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
            bgcolor = "white",
            width = "auto",
            height = "auto",
            halign = "center",
			valign = "center",
            y = 26,


			classes = {"text", "clickable", "selected"},

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
			valign = "bottom",
            vmargin = 10,
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
	local respiteBar = nil

	choiceInitiativeBar = self:CreateInitiativeBarChoicePanel(info)
	self.choiceInitiativeBar = choiceInitiativeBar

	respiteBar = self:CreateRespiteBar(info)
	self.respiteBar = respiteBar

    local resetTurnButton = nil

    if dmhub.isDM then
        --Combat settings button: visible whenever the initiative bar is up. Click
        --opens a dropdown that includes "Revert Turn" (when a checkpoint exists),
        --plus the menu items that used to live behind the bubble's right-click.
        resetTurnButton = gui.Panel {
            bgimage = "panels/hud/gear.png",
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
                checkpointReason = "Revert Turn",
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
                if q == nil or q.hidden then
                    --Combat is over -- hide the button entirely.
                    element:SetClass("unavailable", true)
                    return
                end
                --Combat is active -- show the settings button.
                element:SetClass("unavailable", false)

                --Track the pre-turn checkpoint so Revert restores the state from
                --BEFORE the upcoming turn was selected. We must capture during
                --ChoosingTurn (between turns) -- capturing mid-turn would miss the
                --turn-selection itself and any action taken in the first frame.
                if q:ChoosingTurn() then
                    local needCheckpoint = element.data.checkpoint == nil
                        or element.data.checkpointTurn ~= q.turn
                        or element.data.checkpointRound ~= q.round
                        or element.data.checkpointCombatid ~= q.guid
                    if needCheckpoint then
                        element.data.checkpointTurn = q.turn
                        element.data.checkpointRound = q.round
                        element.data.checkpointCombatid = q.guid
                        element.data.checkpoint = backup.CreateCombatCheckpoint()
                        element.data.checkpointReason = "Revert Turn"
                        element.data.checkpointReasonTurn = nil
                    end
                else
                    --Mid-turn: q.currentTurn is now set, so we can build a label
                    --like "Revert to start of <Name>'s turn" for the dropdown.
                    if element.data.checkpointReasonTurn ~= q.currentTurn then
                        element.data.checkpointReasonTurn = q.currentTurn
                        local tokens = self:GetTokensForInitiativeId(info, q.currentTurn)
                        table.sort(tokens, function(a,b)
                            return creature.ScoreTokenImportance(a) < creature.ScoreTokenImportance(b)
                        end)
                        if #tokens > 0 then
                            element.data.checkpointReason = string.format("Revert to start of %s's turn", creature.GetTokenDescription(tokens[1]))
                        else
                            element.data.checkpointReason = "Revert Turn"
                        end
                    end
                end
            end,

            hover = function(element)
                gui.Tooltip("Combat Settings")(element)
            end,

            press = function(element)
                local q = dmhub.initiativeQueue
                if q == nil or q.hidden then return end
                if not CanControlInitiative() then return end

                local entries = {}

                --Revert Turn -- only when a mid-turn checkpoint is available.
                local canRevert = element.data.checkpoint ~= nil and not q:ChoosingTurn()
                if canRevert then
                    local checkpoint = element.data.checkpoint
                    entries[#entries+1] = {
                        text = element.data.checkpointReason,
                        click = function()
                            element.popup = nil
                            checkpoint:Restore()
                            audio.DispatchSoundEvent("Notify.Director_Undo")
                        end,
                    }
                end

                --Switch to the other side's turn (only when both sides still have entries).
                if q:BothSidesHaveUnmovedEntries() then
                    entries[#entries+1] = {
                        text = cond(q.playersTurn, "Switch to Monster Turn", "Switch to Player Turn"),
                        click = function()
                            element.popup = nil
                            q.playersTurn = not q.playersTurn
                            dmhub:UploadInitiativeQueue()
                        end,
                    }
                end

                --Set which side goes first each round.
                local playersGoFirst = q.playersGoFirst
                entries[#entries+1] = {
                    text = cond(playersGoFirst, "Set Monsters to Go First Each Round", "Set Players to Go First Each Round"),
                    click = function()
                        element.popup = nil
                        q.playersGoFirst = not playersGoFirst
                        dmhub:UploadInitiativeQueue()
                    end,
                }

                --Skip to Next Round -- if a turn is in progress, end it first.
                entries[#entries+1] = {
                    text = "Skip to Next Round",
                    click = function()
                        element.popup = nil
                        local nextRound = function()
                            q:NextRound()
                            GameHud.instance:NewRound()
                            dmhub:UploadInitiativeQueue()
                        end
                        if not q:ChoosingTurn() then
                            GameHud.instance:NextInitiative(function() end)
                            dmhub.Schedule(0.3, nextRound)
                        else
                            nextRound()
                        end
                    end,
                }

                --End Combat.
                entries[#entries+1] = {
                    text = "End Combat",
                    click = function()
                        element.popup = nil
                        UploadDayNightInfo()

                        local monsterCount = 0
                        for initiativeid,_ in pairs(q.entries) do
                            local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
                            for _,tok in ipairs(tokens) do
                                if not tok.properties:IsHero() then
                                    monsterCount = monsterCount + 1
                                end
                            end
                        end

                        track("malice_at_combat_end", {
                            maliceRemaining = CharacterResource.GetMalice(),
                            roundCount = q.round,
                            monsterCount = monsterCount,
                            dailyLimit = 10,
                        })

                        q.hidden = true
                        q.gameMode = "exploration"
                        dmhub:UploadInitiativeQueue()

                        CharacterResource.SetMalice(0, "End of Combat")

                        for initiativeid,_ in pairs(q.entries) do
                            local tokens = GameHud.instance:GetTokensForInitiativeId(GameHud.instance.initiativeInterface, initiativeid)
                            for _,tok in ipairs(tokens) do
                                tok.properties:EndCombat()
                                tok.properties:DispatchEvent("endcombat", {})
                            end
                        end
                    end,
                }

                element.popup = gui.ContextMenu{entries = entries}
            end,
        }
        --Expose the settings button so card-level revert buttons can pull the
        --start-of-turn checkpoint off of it without duplicating the bookkeeping.
        self.combatSettingsButton = resetTurnButton
    end

	local addCharacters
	local addMonsters

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
				height = 72,
				width = tostring(CardWidthPercent) .. "% height",
				valign = 'center',
				halign = 'center',
				flow = 'none',
			},

			{
				selectors = {"initiativeEntryPanel", "turn"},
                transitionTime = 0,
			},

			{
				selectors = {"initiativeEntryBackground"},
				width = "100%",
				height = "100%",
				valign = "center",
				halign = "center",
				borderWidth = 0,
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
				brightness = 2.0,
				transitionTime = 0,
			},

			{
				selectors = {"initiativeEntryBorder", "parent:hadTurn"},
				brightness = 0.3,
				transitionTime = 0,
			},
			{
				selectors = {"initiativeEntryBorder", "parent:selected"},
                borderColor = "yellow",
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

							if info.initiativeQueue.gameMode == "downtime" then
								local settings = DTSettings.CreateNew()
								if settings then
									settings:SetPauseRolls(false)
								end
								for _, token in pairs(dmhub.GetTokens({playerControlled = true})) do
									token.properties:DispatchEvent("startdowntime", {})
								end
							else
								local settings = DTSettings.CreateNew()
								if settings then
									settings:SetPauseRolls(true)
								end
							end

							if info.initiativeQueue.gameMode == "respite" then
								for _, token in pairs(dmhub.GetTokens({playerControlled = true})) do
									token.properties:DispatchEvent("startrespite", {})
								end
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
					tmargin = 4,

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
			respiteBar,
		},
	})
end

function GameHud.CreateInitiativeBarChoicePanel(self, info)

	local choicePanel

	--Gradients for the thin underline bar beneath each card. Blue for unmoved heroes,
	--red for unmoved enemies, gray (via the shared grayscaleGradient) for cards that
	--have already taken their turn. Colors match the player/enemy bubble accents.
	local heroBarGradient = gui.Gradient{
		point_a = {x = 0, y = 0},
		point_b = {x = 1, y = 0},
		stops = {
			{position = 0,   color = "#0a4d8a"},
			{position = 0.5, color = "#1194FF"},
			{position = 1,   color = "#0a4d8a"},
		},
	}
	local enemyBarGradient = gui.Gradient{
		point_a = {x = 0, y = 0},
		point_b = {x = 1, y = 0},
		stops = {
			{position = 0,   color = "#7a0f26"},
			{position = 0.5, color = "#DE1E47"},
			{position = 1,   color = "#7a0f26"},
		},
	}

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

		--Underline bar: one per side, floating below the cards. Holds two segments
		--(gray for hadTurn, colored for unmoved) with a small spacer between them
		--mirroring the gap between cards. Widths set in refresh. Each segment owns
		--a floating label that only appears when this side is the one choosing.
		local m_hadTurnLabel = gui.Label{
			classes = {"initiativeBarLabel", "hadTurn"},
			floating = true,
			halign = "center",
			valign = "bottom",
			y = 16,
			fontSize = 12,
			width = "auto",
			height = "auto",
			textAlignment = "center",
			text = "Already Moved",
		}
		local m_unmovedLabel = gui.Label{
			classes = {"initiativeBarLabel", "unmoved", cond(playerside, "player", "monster")},
			floating = true,
			halign = "center",
			valign = "bottom",
			y = 16,
			fontSize = 12,
			width = "auto",
			height = "auto",
			textAlignment = "center",
			text = cond(playerside, "Ready Heroes", "Ready Monsters"),
		}
		local m_hadTurnSegment = gui.Panel{
			classes = {"initiativeBarSegment", "hadTurn"},
			height = "100%",
			width = 0,
			m_hadTurnLabel,
		}
		local m_unmovedSegment = gui.Panel{
			classes = {"initiativeBarSegment", "unmoved", cond(playerside, "player", "monster")},
			height = "100%",
			width = 0,
			m_unmovedLabel,
		}
		local m_segmentSpacer = gui.Panel{
			classes = {"initiativeBarSpacer"},
			height = "100%",
			width = 0,
			bgcolor = "clear",
		}
		local m_bar = gui.Panel{
			classes = {"initiativeBar"},
			floating = true,
			halign = cond(playerside, "right", "left"),
			valign = "bottom",
			y = 0,
			height = 5,
			width = "auto",
			flow = "horizontal",
			children = (playerside
				and {m_hadTurnSegment, m_segmentSpacer, m_unmovedSegment}
				or {m_unmovedSegment, m_segmentSpacer, m_hadTurnSegment}),
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
            bgimage = true,
			halign = cond(playerside, "left", "right"),
			width = 480,
			height = 80,
			flow = "horizontal",
			data = {
				player = playerside,
				label = m_label,
				wonInitiativeIndicator = m_wonInitiativeIndicator,
				bar = m_bar,
				hadTurnSegment = m_hadTurnSegment,
				unmovedSegment = m_unmovedSegment,
				segmentSpacer = m_segmentSpacer,
				hadTurnLabel = m_hadTurnLabel,
				unmovedLabel = m_unmovedLabel,
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

			--The bar is attached here at construction so its segments/labels aren't
			--orphaned before the first refresh. The refresh handler does NOT include
			--m_bar when it reassigns .children -- it relies on the construction-time
			--attachment to keep the bar alive without re-attach churn.
			m_bar,
		}
	end

    
	local playerContainer = CreateContainer(true)
	local monsterContainer = CreateContainer(false)

	--Radial gradients used to tint the center slot's background based on whose
	--turn it currently is. Bright accent at the middle, dark at the edge.
	--Radial gradients must be plain tables with type = "radial" -- gui.Gradient{}
	--is for linear gradients and would silently drop the type field.
	local heroCenterGradient = gui.Gradient{
		type = "radial",
		point_a = {x = 2.0, y = 0.5},
		point_b = {x = 0.0, y = 0.7},
		stops = {
			{position = 0,   color = "#1194FF"},
			{position = 0.6, color = "#0a3b66"},
			{position = 1,   color = "#04101c"},
		},
	}
	local enemyCenterGradient = gui.Gradient{
		type = "radial",
		point_a = {x = 2.0, y = 0.5},
		point_b = {x = 0.0, y = 0.7},
		stops = {
			{position = 0,   color = "#DE1E47"},
			{position = 0.6, color = "#5c0a1d"},
			{position = 1,   color = "#1c0309"},
		},
	}

	--Scaled-up slot for the currently active turn card. Sits in the middle, over the bubble.
	--Always present: when no turn is chosen the slot is empty and acts as a drop target
	--so a card can be dragged in to claim that turn.
	--Prompt shown inside the empty center slot while we're choosing the next turn.
	--Tells the user where to drop a card; side ("Hero"/"Monster") is set in refresh.
	local centerPromptLabel = gui.Label{
		classes = {"initiativeCenterPrompt"},
		floating = true,
		halign = "center",
		valign = "center",
		width = "85%",
		height = "auto",
		fontSize = 14,
		bold = true,
		color = "#ffffff80",
		textAlignment = "center",
		textWrap = true,
		text = "Drag Hero Here",
	}

	local centerContainer = gui.Panel{
		halign = "center",
		valign = "center",
		width = 90,
		height = 120,
        y = 6,
		flow = "none",
		dragTarget = true,
		classes = {"initiativeCenterContainer"},
		styles = {
			{
				selectors = {"initiativeCenterContainer"},
				bgimage = "panels/square.png",
				bgcolor = "white",
				border = 2,
				borderColor = "#ffffff66",
				gradient = heroCenterGradient,
			},
			{
				selectors = {"initiativeCenterContainer", "monster"},
				gradient = enemyCenterGradient,
			},
			{
				selectors = {"initiativeCenterContainer", "drag-target"},
				borderColor = "white",
			},
			{
				selectors = {"initiativeCenterContainer", "drag-target-hover"},
				borderColor = "yellow",
			},
			{
				selectors = {"initiativeCenterPrompt"},
				hidden = 1,
			},
			{
				selectors = {"initiativeCenterPrompt", "parent:choosing"},
				hidden = 0,
			},
		},
		data = {
			promptLabel = centerPromptLabel,
		},

		centerPromptLabel,
	}

    local drawSteelBubble = CreateDrawSteelBubble()

	choicePanel = gui.Panel{
		width = 1140,
		height = 96,
		y = 30,
		flow = "none",
        halign = "center",

		styles = {
			{
				selectors = {"initiativeEntryPanel"},

			},
			{
				selectors = {"initiativeEntryBackground"},
				width = "100%",
				height = "100%",
				valign = "center",
				halign = "center",
				borderWidth = 0,
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
                lmargin = 0,
                rmargin = 0,
                --transitionTime = 0.5,
                moveTime = 0.5,
            },

			--One bar per side, positioned a little below the cards. Made of two
			--horizontally-packed segments: a gray segment under the cards that have
			--taken their turn, and a colored segment (blue/red) under the cards still
			--to act. The segment widths are recomputed each refresh from card counts.
			{
				selectors = {"initiativeBarSegment"},
				bgimage = "panels/square.png",
				bgcolor = "white",
				saturation = 0.75,
			},
			{
				selectors = {"initiativeBarSegment", "parent:active"},
				saturation = 1,
			},
			{
				selectors = {"initiativeBarSegment", "hadTurn"},
				gradient = Styles.grayscaleGradient,
			},
			{
				selectors = {"initiativeBarSegment", "unmoved", "player"},
				gradient = heroBarGradient,
			},
			{
				selectors = {"initiativeBarSegment", "unmoved", "monster"},
				gradient = enemyBarGradient,
			},

			--Side labels under each bar segment: only visible when the segment's
			--owning side is the one currently choosing a turn. The dark backdrop
			--with a faded border gives the colored text enough contrast against
			--the busy battlemap behind it.
			{
				selectors = {"initiativeBarLabel"},
				hidden = 1,
				bold = true,
				bgimage = "panels/square.png",
				bgcolor = "#000000bb",
				borderWidth = 10,
				borderColor = "#000000bb",
				borderFade = true,
				hpad = 6,
				vpad = 2,
			},
			{
				selectors = {"initiativeBarLabel", "parent:active"},
				hidden = 0,
			},
			{
				selectors = {"initiativeBarLabel", "unmoved", "player"},
				color = "#80C8FF",
			},
			{
				selectors = {"initiativeBarLabel", "unmoved", "monster"},
				color = "#FF6680",
			},
			{
				selectors = {"initiativeBarLabel", "hadTurn"},
				color = "#E5E5E5",
			},

            Styles.TriggerStyles,
		},

		playerContainer,
        drawSteelBubble,
		monsterContainer,
		centerContainer,

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

            local initiativeids = {}
            local tokens = dmhub.selectedTokens
            for _,token in ipairs(tokens) do
                local initiativeid = InitiativeQueue.GetInitiativeId(token)
                initiativeids[initiativeid] = true
            end

			local playerChildren = {playerContainer.data.label.parent, playerContainer.data.bar}
			local monsterChildren = {monsterContainer.data.label.parent, monsterContainer.data.bar}
			--Seed centerChildren with the prompt label so reassigning .children on
			--the center container doesn't dispose it.
			local centerChildren = {centerContainer.data.promptLabel}
			local playerCards = {}
			local monsterCards = {}
			local centerCards = {}
			local newEntries = {}

			--Split entries into player/monster lists, then sort so cards that have
			--already taken their turn are pushed to the outer edge of each side:
			--player hadTurn first (left), monster hadTurn last (right). Within the same
			--unmoved bucket we preserve a stable order by initiative id.
			local playerList = {}
			local monsterList = {}
			for k,v in pairs(initiativeQueue.entries) do
				local rec = { k = k, v = v, unmoved = initiativeQueue:EntryUnmoved(v) }
				if initiativeQueue:IsEntryPlayer(k) then
					playerList[#playerList+1] = rec
				else
					monsterList[#monsterList+1] = rec
				end
			end
			table.sort(playerList, function(a, b)
				if a.unmoved ~= b.unmoved then return not a.unmoved end
				return a.k < b.k
			end)
			table.sort(monsterList, function(a, b)
				if a.unmoved ~= b.unmoved then return a.unmoved end
				return a.k < b.k
			end)

			local processEntry = function(k, v, isplayer)
				--A card's wrapper can't cleanly move between containers via .children
				--reassignment, so if the desired container for this card has changed since
				--the last refresh we must recreate the entry. Otherwise the wrapper gets
				--orphaned and the card isn't visible until the next refresh.
				local turn = initiativeQueue.currentTurn == k
				local desiredContainer = turn and "center" or (isplayer and "player" or "monster")
				local cached = entries[k]
				local cacheHit = cached ~= nil
					and cached.data ~= nil
					and cached.data.isplayer == isplayer
					and cached.data.container == desiredContainer
				if cacheHit then
					newEntries[k] = cached
				else
					newEntries[k] = self:CreateInitiativeEntry(info, k, {
						selectinitiative = function(element)

							--Use the live queue (dmhub.initiativeQueue), not the closure-
							--captured initiativeQueue from when refresh ran -- the latter
							--can be stale after a turn transition, which made SelectTurn a
							--silent no-op for drag-to-claim after ending the previous turn.
							local q = dmhub.initiativeQueue
							if q == nil or q.hidden then return end

							if CanControlInitiative() == false and ((not q:ChoosingTurn()) or (not q:IsPlayersTurn()) or (not q:EntriesUnmoved()[k]) or (not q:IsEntryPlayer(k))) then
								return
							end
							q:SelectTurn(k)
							dmhub:UploadInitiativeQueue()

							--Use the loop key (the initiative id) rather than v.initiativeid;
							--group entries don't populate v.initiativeid, which left BeginTurn
							--unfired and the drag-to-claim a no-op for monster groups.
							local tokens = self:GetTokensForInitiativeId(info, k)
							local tokenIds = {}
							for i,tok in ipairs(tokens) do
								if tok.properties ~= nil then
									tok.properties:BeginTurn()
									tokenIds[#tokenIds+1] = tok.charid
								end
							end

							if #tokenIds > 0 then
								chat.SendCustom(StartOfTurnChatMessage.new{
									tokenids = tokenIds,
								})
							end
						end,
					})
					newEntries[k]:SetClass("player", isplayer)
					newEntries[k]:SetClass("monster", not isplayer)

					--parent this panel to a new panel so we can center it.
					--Explicit pixel sizes (not "auto") so cards pack flush; FitCards updates these.
					gui.Panel{
                        classes = {"initiativeEntryParent"},
						halign = cond(isplayer, "right", "left"),
						valign = "center",
						height = 72,
						width = 54,
                        hmargin = 2,
						newEntries[k],
					}
				end

				local panel = newEntries[k]
				panel.data.isplayer = isplayer
				panel.data.container = desiredContainer

				local unmoved = initiativeQueue:EntryUnmoved(v)
				panel:SetClass("turn", turn)
				panel.parent:SetClass("repel", turn)
				panel:SetClass("unmoved", unmoved)
				panel:SetClass("hadTurn", not unmoved)
				panel:SetClass("unselectable", (not unmoved) or (isPlayersTurn ~= isplayer))
                panel:SetClass("selected", initiativeids[k])
				--Propagate state classes to the wrapper so the underline bar style can match.
				panel.parent:SetClass("player", isplayer)
				panel.parent:SetClass("monster", not isplayer)
				panel.parent:SetClass("unmoved", unmoved)
				panel.parent:SetClass("hadTurn", not unmoved)

				--Determine whether this entry has any token the local player can see.
				--Entries with no visible tokens still get added to children (their
				--wrapper will be collapsed by the card's own refresh), but they are
				--excluded from the *Cards lists so FitCards and the underline bar
				--ignore them for sizing.
				local visible = false
				local entryTokens = self:GetTokensForInitiativeId(info, k)
				for _,tok in ipairs(entryTokens) do
					if tok.canSee or tok.playerControlled then
						visible = true
						break
					end
				end

				if turn then
					centerChildren[#centerChildren+1] = panel.parent
					if visible then centerCards[#centerCards+1] = panel end
				elseif isplayer then
					playerChildren[#playerChildren+1] = panel.parent
					if visible then playerCards[#playerCards+1] = panel end
				else
					monsterChildren[#monsterChildren+1] = panel.parent
					if visible then monsterCards[#monsterCards+1] = panel end
				end
			end

			for _,e in ipairs(playerList) do processEntry(e.k, e.v, true) end
			for _,e in ipairs(monsterList) do processEntry(e.k, e.v, false) end

			--Assign the destination container first to reduce the chance the wrapper
			--gets destroyed in transit when it moves between containers.
			centerContainer.children = centerChildren
			playerContainer.children = playerChildren
			monsterContainer.children = monsterChildren

			--Apply the scaled-up size to the active (centered) card. Override both
			--width and height explicitly -- the class-style "75% height" width formula
			--resolves against the class height, not selfStyle, so width must be pinned.
			--Sized to fully fill the centerContainer (which is 90x120, same 0.75 aspect).
			local centerCardH = 120
			local centerCardW = centerCardH * (CardWidthPercent * 0.01)
			local centerIsPlayer = nil
			for _,card in ipairs(centerCards) do
				card.selfStyle.height = centerCardH
				card.selfStyle.width = centerCardW
				card.selfStyle.valign = "center"
				card.parent.selfStyle.height = centerCardH
				card.parent.selfStyle.width = centerCardW
				card.parent.selfStyle.halign = "center"
				if centerIsPlayer == nil then
					centerIsPlayer = card.data.isplayer
				end
			end
			--Tint the center container based on whose turn it is (blue/red gradient).
			--During ChoosingTurn there is no centered card yet -- fall back to whichever
			--side is currently picking so the gradient still shows the right color.
			local choosing = initiativeQueue:ChoosingTurn()
			if centerIsPlayer == nil and choosing then
				centerIsPlayer = initiativeQueue:IsPlayersTurn()
			end
			centerContainer:SetClass("player", centerIsPlayer == true)
			centerContainer:SetClass("monster", centerIsPlayer == false)

			--Empty-slot prompt: visible only while choosing a turn (no card in center).
			centerContainer:SetClass("choosing", choosing and #centerCards == 0)
			centerContainer.data.promptLabel.text = (centerIsPlayer == false)
				and "Drag Monster Here"
				or "Drag Hero Here"

			--Shrink cards uniformly if the row would otherwise overflow the container.
			--Container is 480w x 80h; cards are 75% of container height by default,
			--and width is CardWidthPercent% of card height (square aspect ratio).
			--We set explicit pixel dimensions on the wrapper too, because the card's
			--"75% height" width formula breaks "auto" sizing on the parent.
			local containerW = 480
			local containerH = 80
			--Cards default to 90% of the side container's height (~20% bigger than
			--the previous 75% baseline). The centered card uses its own size.
			local baseFactor = 0.9
			local aspect = CardWidthPercent * 0.01
			local desiredH = containerH * baseFactor
			local desiredW = desiredH * aspect
			--Cards in the same bucket pack with the normal hmargin (4px between them).
			--At the boundary between hadTurn and unmoved we add bucketGapExtra extra
			--pixels of left margin on the first card of the second bucket so there's
			--a visible separation between "already moved" and "ready" cards.
			local bucketGapExtra = 8
			local FitCards = function(cards, isplayer)
				local n = #cards
				if n == 0 then return end
				local totalW = n * desiredW
				local finalH = desiredH
				if totalW > containerW then
					finalH = desiredH * (containerW / totalW)
				end
				local finalW = finalH * aspect
				local halign = cond(isplayer, "right", "left")
				local prevBucket = nil
				for _,card in ipairs(cards) do
					local bucket = card:HasClass("hadTurn") and "hadTurn" or "unmoved"
					local isBoundary = prevBucket ~= nil and prevBucket ~= bucket
					prevBucket = bucket
					card.selfStyle.height = finalH
					card.selfStyle.width = finalW
					card.selfStyle.valign = "center"
					card.parent.selfStyle.height = finalH
					card.parent.selfStyle.width = finalW
					card.parent.selfStyle.halign = halign
					card.parent.selfStyle.lmargin = isBoundary and (2 + bucketGapExtra) or nil
				end
			end
			FitCards(playerCards, true)
			FitCards(monsterCards, false)

			--Size the per-side underline bar segments to span the cards above them.
			--Each card wrapper has hmargin = 2, so the per-card horizontal slot is
			--cardW + 2 * hmargin wide -- the bar segments need to include that gap.
			--A side is "active" when it's the side currently choosing whose turn goes
			--next; the active side's bar shows at full saturation, the other at 50%.
			local cardHMargin = 2
			local choosingPlayer = false
			local choosingMonster = false
			if initiativeQueue:ChoosingTurn() then
				if initiativeQueue:IsPlayersTurn() then
					choosingPlayer = true
				else
					choosingMonster = true
				end
			end
			local SizeBar = function(container, cards, active)
				--cards is already filtered to entries the local player can see.
				local n = #cards
				local cardW = desiredW
				if n > 0 then
					local totalW = n * desiredW
					local finalH = desiredH
					if totalW > containerW then
						finalH = desiredH * (containerW / totalW)
					end
					cardW = finalH * aspect
				end
				local slotW = cardW + 2 * cardHMargin
				local hadTurnCount, unmovedCount = 0, 0
				for _,c in ipairs(cards) do
					if c:HasClass("hadTurn") then
						hadTurnCount = hadTurnCount + 1
					else
						unmovedCount = unmovedCount + 1
					end
				end
				--Segments include the outer margins of their edge cards. When both
				--segments are present, the spacer takes the place of one card's outer
				--margin (2px) from each side, so we subtract cardHMargin from each
				--segment to keep the visible bar-gap aligned with the card-to-card gap.
				local showBoth = hadTurnCount > 0 and unmovedCount > 0
				local hadTurnW = hadTurnCount * slotW
				local unmovedW = unmovedCount * slotW
				if showBoth then
					hadTurnW = hadTurnW - cardHMargin
					unmovedW = unmovedW - cardHMargin
				end
				--Wrap segment/label updates in pcall: when the container's .children
				--gets reassigned during a refresh, the engine can dispose the old
				--bar/segment panels even though the Lua references in `data` still
				--point at them, which makes the next selfStyle access raise a C#
				--NullReferenceException. Skipping silently is fine -- next refresh
				--will see fresh panels.
				pcall(function()
					container.data.hadTurnSegment.selfStyle.width = hadTurnW
					container.data.unmovedSegment.selfStyle.width = unmovedW
					--Spacer matches the card-to-card visible gap: 4px normal + bucketGapExtra
					--at the bucket boundary, so the bar's break lines up with the card gap.
					container.data.segmentSpacer.selfStyle.width = showBoth and (2 * cardHMargin + bucketGapExtra) or 0
					container.data.bar:SetClass("active", active)
					--Labels use parent:active to show themselves; parent is the segment.
					container.data.hadTurnSegment:SetClass("active", active)
					container.data.unmovedSegment:SetClass("active", active)
					--Shorten the label text when the segment is only one card wide so it
					--still fits beneath the bar.
					container.data.hadTurnLabel.text = (hadTurnCount == 1) and "Moved" or "Already Moved"
					container.data.unmovedLabel.text = (unmovedCount == 1) and "Ready"
						or (container.data.player and "Ready Heroes" or "Ready Monsters")
					--Labels only show when this side is currently choosing the next turn,
					--and the bucket has at least one card to label.
					container.data.hadTurnLabel.selfStyle.hidden = (active and hadTurnCount > 0) and 0 or 1
					container.data.unmovedLabel.selfStyle.hidden = (active and unmovedCount > 0) and 0 or 1
				end)
			end
			SizeBar(playerContainer, playerCards, choosingPlayer)
			SizeBar(monsterContainer, monsterCards, choosingMonster)

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

                if anthemToken ~= nil and (anthemDuration:Get() >= 1 or not anthemLimited:Get()) then
                    if anthemToken.charid ~= m_anthemTokenId then
                        StopAnthem()
                        m_anthemTokenId = anthemToken.charid
                        local asset = assets.audioTable[anthemToken.anthem]
                        if asset ~= nil then
                            m_anthemEventInstance = asset:Play()
                            m_anthemEventInstance.volume = anthemToken.anthemVolume
                            if anthemLimited:Get() then
                                m_anthemEventInstance:SetStopAfter(anthemDuration:Get())
                            end
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

function GameHud.CreateRespiteBar(self, info)
	return gui.Panel{
		classes = { "hidden" },
		width = 400,
		height = 60,
		y = 40,
		halign = "center",
		valign = "top",

		refresh = function(element)
			local isRespite = info.initiativeQueue ~= nil
				and info.initiativeQueue.hidden
				and info.initiativeQueue.gameMode == "respite"
			element:SetClass("hidden", not isRespite)
		end,

		gui.Button{
			text = "End Respite",
			halign = "Center",
			valign = "Bottom",
			fontSize = 22,
			press = function(element)
                local groupid = dmhub.GenerateGuid()
				if not CanControlInitiative() then return end
				if info.initiativeQueue ~= nil then
					info.initiativeQueue.gameMode = "exploration"
					info.UploadInitiative()
					for _, token in pairs(dmhub.GetTokens({playerControlled = true})) do
						local currentXp = token.properties:try_get("xp", 0)
                        token:ModifyProperties{
                            description = "Respite",
                            combine = true,
                            groupid = groupid,
                            execute = function()
						        token.properties:Rest("long")
                            end,
                        }
						local newXp = token.properties:try_get("xp", 0)

						token.properties:DispatchEvent("endrespite", {xpgained = newXp - currentXp})
						
					end
				end
			end,
		}
	}
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
                if tok.properties:IsTurnSkipped(tok) then
                    -- Suppress EndTurn: save-ends and end-of-turn effects do not trigger.
                else
				    tok.properties:EndTurn(tok)
                end
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

    local isNew = true
    local newStyle = cond(isNew, "new")

    local resultPanel

    resultPanel = gui.Panel{
        styles = g_beginRoundStyles,
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        vmargin = 6,

        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = "auto",
            halign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#111111",
            cornerRadius = 4,
            vpad = 4,

            gui.Panel{
                classes = {"leftSword", newStyle},
                bgimage = "panels/initiative/drawsteel-sword.png",
                bgcolor = "white",
                width = 60,
                height = "50% width",
                valign = "center",
                halign = "center",
            },

            gui.Label{
                classes = {newStyle,"chat-message-text"},
                text = cond(self.round == 1, "Draw Steel!", string.format("ROUND %d", self.round)),
                bold = true,
                width = "auto",
                height = "auto",
                fontSize = 16,
                color = "white",
                valign = "center",
                halign = "center",
                hmargin = 8,
            },

            gui.Panel{
                classes = {"rightSword", newStyle},
                bgimage = "panels/initiative/drawsteel-sword.png",
                bgcolor = "white",
                width = 60,
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

--- @class StartOfTurnChatMessage
StartOfTurnChatMessage = RegisterGameType("StartOfTurnChatMessage")
StartOfTurnChatMessage.tokenids = {}

function StartOfTurnChatMessage.Render(self, message)
    local tokens = {}
    for _,charid in ipairs(self.tokenids) do
        local tok = dmhub.GetCharacterById(charid)
        if tok ~= nil and tok.valid then
            tokens[#tokens+1] = tok
        end
    end

    local primaryToken = tokens[1]
    if primaryToken == nil then
        return gui.Panel{width = 0, height = 0}
    end

    local card = CreateActionLogCard{
        token = primaryToken,
        content = {
            gui.Label{
                classes = {"action-log-subtext", "sizeXxs", "fgMuted"},
                text = "Start of Turn",
            },
        },
    }

    local resultPanel = gui.Panel{
        classes = {"chat-message-panel"},
        flow = "vertical",
        width = "100%",
        height = "auto",
        refreshMessage = function(element, message)
        end,
        card,
    }

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
        uiscale = 0.8,
        hmargin = 2,
        vmargin = 3,
        width = 24,
        height = 60,
		refresh = function(element)
			if token == nil or (not token.valid) or token.properties.minion then
				element:SetClass("collapsed", true)
				return
			end

			element:SetClass("collapsed", false)

            local charid = token.charid

			local resources = token.properties:GetResources()
			local usage = token.properties:GetResourceUsage(g_triggeredResourceId, "round")
			local expended = (usage >= (resources[g_triggeredResourceId] or 0))

            local children = {}
            local newTriggeredActionPanels = {}
            local triggeredActions = token.properties:GetTriggeredActions()
            for _,action in ipairs(triggeredActions) do
                if action.type == "trigger" then
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

	--Revert-turn button: only visible while this entry is the current turn.
	--Pressed -> cancels the turn (sends us back to the choose-next-turn state).
	if CanControlInitiative() then

		closeButton = gui.Button{
            classes = {"closeButton", "revertTurnButton"},
			halign = "right",
			valign = "top",
			hmargin = 2,
			vmargin = 2,
			-- The closeButton kind class auto-binds Escape (escapeActivates=true).
			-- Reverting the current turn from a stray Escape press is far too
			-- destructive, so opt this specific button out of escape activation.
			escapeActivates = false,

			styles = {
				{
					selectors = {"revertTurnButton"},
					hidden = 1,
				},
				{
					selectors = {"revertTurnButton", "parent:turn"},
					hidden = 0,
				},
			},

			hover = gui.Tooltip("Revert Turn"),

			events = {
				click = function(element)
					--Prefer a full checkpoint restore (same as the settings menu's
					--Revert Turn), which undoes any in-turn changes. Fall back to
					--CancelTurn when no checkpoint is available.
					local settingsButton = self:try_get("combatSettingsButton")
					local checkpoint = settingsButton ~= nil and settingsButton.data.checkpoint or nil
					if checkpoint ~= nil then
						checkpoint:Restore()
						audio.DispatchSoundEvent("Notify.Director_Undo")
					elseif info.initiativeQueue ~= nil then
						info.initiativeQueue:CancelTurn(initiativeid)
						info.UploadInitiative()
					end
				end,
			},
		}
	end

	local playerColor = "black"
	if token ~= nil then
		playercolor = token.playerColor.tostring
	end

	local m_bossTurnsPanel = nil
    local m_containerPanel = nil

	--this is the initiative entry panel.
	return gui.Panel({

		classes = {"initiativeEntryPanel"},

		draggable = CanControlInitiative(),
		drag = function(element, target)
			if target == nil then
				return
			end

			--Dropping on the center slot claims the turn (same effect as clicking the card
			--when it's eligible to take its turn).
			if target:HasClass("initiativeCenterContainer") then
				if options.selectinitiative ~= nil then
					options.selectinitiative(element)
				end
				return
			end

			if not target:HasClass("initiativeEntryContainer") then
				return
			end

			local entry = info.initiativeQueue.entries[initiativeid]
			if entry ~= nil and entry:try_get("player") ~= target.data.player then
				entry.player = target.data.player
				info.UploadInitiative()
			end
		end,
		canDragOnto = function(element, target)
			if target ~= nil and (target:HasClass("initiativeEntryContainer") or target:HasClass("initiativeCenterContainer")) then
				return true
			end

			return false
		end,

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

                if q.currentTurn ~= initiativeid then
                    entries[#entries+1] = {
                        text = "Remove from Initiative",
                        click = function()
                            element.popup = nil
                            info.initiativeQueue:RemoveInitiative(initiativeid)
                            info.UploadInitiative()
                        end,
                    }
                end

                if q.currentTurn == initiativeid then
                    entries[#entries+1] = {
                        text = "Revert Turn",
                        click = function()
                            element.popup = nil
                            --Prefer the full checkpoint restore captured by the
                            --combat settings button so heroic resources, stamina,
                            --and other start-of-turn side effects are undone too.
                            --CancelTurn alone only rewinds the initiative pointer.
                            local settingsButton = self:try_get("combatSettingsButton")
                            local checkpoint = settingsButton ~= nil and settingsButton.data.checkpoint or nil
                            if checkpoint ~= nil then
                                checkpoint:Restore()
                                audio.DispatchSoundEvent("Notify.Director_Undo")
                            else
                                q:CancelTurn(initiativeid)
                                info.UploadInitiative()
                            end
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
				element:SetClassTree("turntaken", entry ~= nil and entry.round == info.initiativeQueue.round+1)

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