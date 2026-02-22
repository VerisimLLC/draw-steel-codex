local mod = dmhub.GetModLoading()

--A RollCheck instance has the following fields:
-- type = "test_power_roll"/"resistance_power_roll"/"skill"/"initiative"/"flat"/"table"/"custom"
-- id = the test_power_roll, resistance_power_roll, or skill being tested
-- tableRef = a RollTableReference if type is "table".
-- info = (optional) a table of additional information about the roll.
-- roll = (optional) the actual roll to make. Only valid if "custom" is the type of roll.
-- text = a textual description.
-- explanation = (optional) an explanation of why the roll is taking place.
-- consequences = (optional) a description to the requester of the roll of consequences based on the roll.
-- options = (optional) a table of options. All optional.
--           tiers: an array of tiers for the power roll.
--           casterid: ID of the character requiring this roll.
--           nocover: if true, cover can't benefit this check.
--           magic: if present and true, this is a magical effect.
--           condition: if present, the id of a condition that is being tested. Can use "concentration" for concentration checks.
--           specializations: if present, a {k -> true} map of specialization ID's for this check.
--           forcedmodifiers: if present, forces a list of modifiers on character for roll 
RegisterGameType("RollCheck")

--A RollRequest instance has the following fields:
-- checks = a list of RollChecks that the token can choose from. Most often this will just have one option.
-- tokens = map of token id -> result table. Result table begins empty and is filled by the target. May have a checks list which is a list of indexes into checks that are available to this token.
-- contest = (optional) if true this is a contested roll between the tokens. The tokens map will have a "team" identifier to signal which side of the contest they are on.
RegisterGameType("RollRequest")

RollCheck.consequences = ''
RollCheck.explanation = ''

RollRequest.contest = false

RollCheck.customChecks = {}

--register a custom check. options = {
--	id = string,
--	Describe = function(RollCheck, bool isplayer),
--	GetRoll = function(RollCheck, creature),
--	GetModifiers = (optional) function(RollCheck, creature),
--	ShowDialog = (optional) function(RollCheck, dialogOptions)
--}
function RollCheck.RegisterCustom(options)
	RollCheck.customChecks[options.id] = options
end

function RollCheck:CustomInfo()
	return RollCheck.customChecks[self.id]
end

function RollRequest:GetTokenOutcome(tokenid, checkNumber)
	local tokenInfo = self.tokens[tokenid]
	if tokenInfo == nil then
		return nil
	end

	return tokenInfo.outcome
end

function RollRequest:GetTokenResult(tokenid, checkNumber)
	local tokenInfo = self.tokens[tokenid]
	if tokenInfo == nil then
		return nil
	end

	if tokenInfo.forcedResult ~= nil then
		return tokenInfo.forcedResult
	end

	if tokenInfo.result == nil then
		return nil
	end

	return nil
end


function RollRequest:Describe(isplayer)
	return self.checks[1]:Describe(isplayer)
end

function RollCheck:GetSkill()
	local options = self:try_get("options", {})
    local skill = nil
    for _,s in ipairs(options.skills or {}) do
		local skillsTable = dmhub.GetTable(Skill.tableName)
		skill = skillsTable[s]
        if skill ~= nil then
            break
        end
    end
    return skill
end

function RollCheck:Describe(isplayer)
	if self:CustomInfo() ~= nil then
		return self:CustomInfo().Describe(self, isplayer)
	end
	
	if self.type == "test_power_roll" then

        local skill = self:GetSkill()
        if skill ~= nil then
		    return string.format("%s (%s) test", skill.name, self.text)
        else
		    return string.format("%s test", self.text)
        end
	elseif self.type == "resistance_power_roll" then
		local conditionStr = ""
		local options = self:try_get("options", {})
		if options.condition then
			local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
			local condition = conditionsTable[options.condition]
			if condition ~= nil then
				conditionStr = string.format(" against %s", condition.name)
			end
		end
		return string.format("%s resistance%s", self.text, conditionStr)
	elseif self.type == "initiative" then
		return "Roll for Initiative"
	elseif self.type == "flat" then
		return "Flat Check"
	elseif self.type == "table" then
		return "Roll on Table"
	elseif self.type == "custom" then
		return self:try_get("text", "Custom Roll")
	else
		local specializationText = ""
		if self:has_key("options") and self.options.specializations ~= nil then
			local skillsTable = dmhub.GetTable(Skill.tableName)
			local skill = skillsTable[self.id]
			if skill ~= nil then
				for k,_ in pairs(self.options.specializations) do
					local s = Skill.GetSpecializationById(skill, k)
					if s ~= nil then
						if specializationText ~= "" then
							specializationText = specializationText .. ", "
						end
						specializationText = specializationText .. s.text
					end
				end
			end
		end

		if specializationText ~= "" then
			specializationText = string.format(" (%s)", specializationText)
		end

		return string.format("%s%s check", self.text, specializationText)
	end
end

function RollCheck:GetRoll(creature)
	if self:CustomInfo() ~= nil then
		return self:CustomInfo().GetRoll(self, creature)
	end

	if self.type == "test_power_roll" or self.type == "opposed_power_roll" then
		return string.format("%s+%d", GameSystem.BaseSkillRoll, creature:AttributeMod(self.id))
	elseif self.type == "initiative" then
		return string.format("%s+%d", GameSystem.BaseInitiativeRoll, creature:InitiativeBonus())
	elseif self.type == "flat" then
		return GameSystem.FlatRoll
	elseif self.type == "table" then
		if self:has_key("tableRef") == false then
			return "1d100"
		end

		local rollInfo = self.tableRef:GetTable():CalculateRollInfo()
		if rollInfo == nil then
			return "1d100"
		end
		return rollInfo.roll
	elseif self.type == "custom" then
		return self:try_get("roll", "1d6")
	else
		return string.format("%s+%d", GameSystem.BaseSkillRoll, creature:SkillMod(Skill.SkillsById[self.id]))
	end
end

--- @param creature creature
--- @param rollRequest RollRequest|nil
function RollCheck:GetModifiers(creature, rollRequest)
	if self:CustomInfo() ~= nil then
		if self:CustomInfo().GetModifiers then
            print("CharacterModifier:: Get modifiers custom")
			return self:CustomInfo().GetModifiers(self, creature)
		else
			return {}
		end
	end

	if self.type == "test_power_roll" then
		local skill = self:GetSkill()
		local skills = nil
		if skill ~= nil then
			skills = {skill.id}
		end

        print("POWER ROLL:: GET MODIFIERS REQUEST:", json(rollRequest))
        local title = rollRequest ~= nil and rollRequest:try_get("title")
		local result = creature:GetModifiersForPowerRoll(self:GetRoll(creature), self.type, {attribute = self.id, skills = skills, title = title})
        if skill ~= nil and creature:ProficientInSkill(skill) then
            for _,mod in ipairs(result) do
                if mod.modifier.name == "Skilled" then
                    mod.hint.result = true
                end
            end
        end
        return result
	elseif self.type == "opposed_power_roll" then
		local skill = self:GetSkill()
		local skills = nil
		if skill ~= nil then
			skills = {skill.id}
		end

		--Modifiers included from the Roll
		local rollModifiers = self:try_get("modifiers", {})
		--Modifiers for the creature making the roll
		local result = creature:GetModifiersForPowerRoll(self:GetRoll(creature), "test_power_roll", {attribute = self.id, skills = skills})
		if creature:ProficientInSkill(skill) then
            for _,mod in ipairs(result) do
                if mod.modifier.name == "Skilled" then
                    mod.hint.result = true
                end
            end
        end
		--Add roll modifiers to the result
		for _, mod in pairs(rollModifiers ) do
			result[#result+1] = mod
		end
		return result
	elseif self.type == "table" then
		return {}
	elseif self.type == "flat" then
		return {}
	elseif self.type == "custom" then
		return {}
	else
		return creature:GetModifiersForSkillCheckRoll(Skill.SkillsById[self.id], self:try_get("options"))
	end
	
end

local initiativeChecks = {
	{
		type = 'initiative',
		id = 'initiative',
		text = 'Initiative',
	}
}

local g_tableGroupSetting = setting{
	id = "rollTableGroup",
	text = "Table Group",
	default = "lootTables",
	storage = "preference",
}

--called by skills once the skills are loaded.
function RollCheck.LoadSkills()

	local attributeRollChecks = {}
	local saveChecks = {}

	for i,attr in ipairs(creature.attributeIds) do
		local info = creature.attributesInfo[attr]
		attributeRollChecks[#attributeRollChecks+1] = {
			type = 'test_power_roll',
			id = info.id,
			text = info.description,
		}
	end

	for key,info in pairs(creature.savingThrowInfo) do
		saveChecks[#saveChecks+1] = {
			type = 'resistance_power_roll',
			id = key,
			text = info.description,
			order = info.order,
		}
	end

	table.sort(saveChecks, function(a,b) return a.order < b.order end)

	local skillRollChecks = {}
	for i,skillInfo in ipairs(Skill.SkillsInfo) do
		skillRollChecks[#skillRollChecks+1] = {
			type = 'skill',
			id = skillInfo.id,
			text = skillInfo.name,
			specializations = Skill.GetSpecializations(skillInfo),
		}
	end

	local tableGroups = {}
	local tableChecks = {}
	for tableid,info in pairs(Compendium.rollableTables) do
		tableGroups[#tableGroups+1] = {
			id = tableid,
			text = info.text,
		}
		local t = dmhub.GetTable(tableid) or {}
		for k,v in pairs(t) do
			if not v:try_get("hidden", false) then
				tableChecks[#tableChecks+1] = {
					type = 'table',
					id = tableid,
					group = tableid,
					tableRef = RollTableReference.CreateRef(tableid, k),

					text = v.name,
				}
			end
		end
	end

	table.sort(tableGroups, function(a,b) return a.text < b.text end)
	print("TABLE CHECKS::", json(tableChecks))
	print("TABLE CHECKS:: GROUPS", json(tableGroups))

	RollCheck.Checks = {
		{
			name = 'Test',
			checks = attributeRollChecks,
            skills = true,
		},
		{
			name = 'Table',
			group = g_tableGroupSetting,
			groups = tableGroups,
			checks = tableChecks,
		},
	}
end


--this is a hidden panel which just listens for required rolls.
function GameHud:RequireRollListenerPanel()

	local autoRollId = nil
	local autoCancelId = nil

	--tracks the ID of the roll dialog we are showing. This way we can cancel that dialog
	--if needed due to the roll request being retracted.
	local showingRollId = nil
	local rollRequestId = nil

	--track rolls we currently have ongoing
	local currentRolls = {}

	local resultPanel = gui.Panel{
		floating = true,
		width = 0,
		height = 0,

		monitorGame = "/actionRequests",

		refreshGame = function(element)
			if self.rollDialog.data.IsShown() then
				if showingRollId == gamehud.rollDialog.data.rollid then
					--we requested the current roll dialog that is shown. See if our reason
					--for doing so has been canceled, in which case we want to close that dialog.
					if dmhub.GetPlayerActionRequest(rollRequestId) == nil then
						self.rollDialog.data.Cancel()
					end
				end

				--we are currently blocked by the roll dialog. Try again in a little while.
				element:ScheduleEvent("refreshGame", 0.2)

				return
			end

			local requests = dmhub.GetPlayerActionRequests()
			for k,request in pairs(requests) do
				if request.info.typeName == 'RestRequest' then
					--request for resting, see if we want to handle it and if we do go over to that.
					if self:TryHandleRestRequest(k, request) then
						return
					end

				elseif request.info.typeName == 'RollRequest' then
					local numPrompts = 0

					local havePlayersOnline = false
					if #dmhub.users > 1 then
						for _,userid in ipairs(dmhub.users) do
							local session = dmhub.GetSessionInfo(userid)
							if session ~= nil and session.dm == false and session.loggedOut == false then
								havePlayersOnline = true
							end
						end
					end

					for tokid_tmp,info_tmp in pairs(request.info.tokens) do
						local tokid = tokid_tmp
						local info = info_tmp
						if info.status == nil then
							local tok = dmhub.GetTokenById(tokid)
							local rollid = k .. tokid
							if tok ~= nil and tok.properties and ((info.forceuserid == nil and tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)) or info.forceuserid == dmhub.loginUserid) and not currentRolls[rollid] then
								numPrompts = numPrompts+1
							end
						end
					end


					for tokid_tmp,info_tmp in pairs(request.info.tokens) do
						local tokid = tokid_tmp
						local info = info_tmp
						if info.status == nil then
							local tok = dmhub.GetTokenById(tokid)
							local rollid = k .. tokid
							if tok ~= nil and tok.properties and ((info.forceuserid == nil and tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)) or info.forceuserid == dmhub.loginUserid) and not currentRolls[rollid] then

								local checks = {}

								for index,c in ipairs(request.info.checks) do
									local canUseThisCheck = true
									if info.checks ~= nil then
										canUseThisCheck = false
										for _,checkIndex in ipairs(info.checks) do
											if checkIndex == index then
												canUseThisCheck = true
											end
										end
									end

									if canUseThisCheck then
										checks[#checks+1] = c
									end
								end

								local rollProperties = nil

								local ShowPromptDialog
								ShowPromptDialog = function(checkIndex, nofadein)
									local check = checks[checkIndex]

									--build a list of alternate options.
									local alternateOptions = {}
									for _,c in ipairs(checks) do
										alternateOptions[#alternateOptions+1] = {
											text = c.text,
										}
									end
									
                                    if check:has_key("rollProperties") then
                                        rollProperties = check.rollProperties
                                    elseif check:has_key("tableRef") then
										rollProperties = RollProperties.new{}
										rollProperties.tableRef = check.tableRef
									end

									local autoroll = nil
									if autoRollId == k then
										autoroll = true
										if autoCancelId == k then
											autoroll = "cancel"
										end
									elseif dmhub.isDM and tok.playerControlled == false then
										if check.type == "resistance_power_roll" then
											autoroll = {
												id = "monsterSaves",
												text = "monster saves",
											}
											dmhub.Debug("AUTOROLL SAVE")
										end
									end

									local rollType = "test_power_roll"
									if check.type == "table" then
										rollType = "table"
									elseif check:CustomInfo() ~= nil then
										rollType = check:CustomInfo().rollType or rollType
                                    elseif check.type == "custom" then
                                        --a custom roll probably doesn't have any special properties?
                                        rollType = "custom"
									end

									local rollAllPromptsSet = false

									currentRolls[rollid] = true

									rollRequestId = k

                                    local PopulateCustom = nil
                                    if check:try_get("options", {}).tiers ~= nil then
                                        PopulateCustom = ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom(check.options)
                                        rollProperties = RollPropertiesPowerTable.new{
                                            tiers = check.options.tiers,
                                        }
                                    end

									local dialogParams = {
										title = string.format("%s for %s", check:Describe(not dmhub.isDM), tok.description),
										description = check:Describe(not dmhub.isDM),
										explanation = check.explanation,
										roll = check:GetRoll(tok.properties),
										modifiers = check:GetModifiers(tok.properties, request.info),
										rollProperties = rollProperties,
										creature = tok.properties,
										tableRef = check:try_get("tableRef"),
										type = rollType,
										subtype = check.type,
										nofadein = nofadein,

                                        PopulateCustom = PopulateCustom,

										alternateOptions = alternateOptions,
										alternateChosen = checkIndex,
										chooseAlternate = function(alternateIndex)
										    gamehud.rollDialog.data.Cancel()
											ShowPromptDialog(alternateIndex, true)
										end,

										numPrompts = numPrompts,
										rollAllPrompts = function()
											rollAllPromptsSet = true
											autoRollId = k
											dmhub.Debug("ROLL:: ALL PROMPTS")
										end,
										autoroll = autoroll,
										beginRoll = function()
											local req = dmhub.GetPlayerActionRequest(k)
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'rolling'
												req:CompleteChanges("Begin roll")
											end
										end,
										completeRoll = function(rollInfo)
											local req = dmhub.GetPlayerActionRequest(k)
                                                print("ROLLINFO:: XCOMPLETE ROLL", req)
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'complete'
												req.info.tokens[tokid].result = rollInfo.total
												req.info.tokens[tokid].boons = rollInfo.boons
												req.info.tokens[tokid].banes = rollInfo.banes

												if rollInfo.forcedResult then
													req.info.tokens[tokid].forcedResult = rollInfo.autosuccess
												end
												
												if rollInfo.properties then
													local matchingOutcome = rollInfo.properties:try_get("overrideOutcome") or rollInfo.properties:GetOutcome(rollInfo)
													if matchingOutcome then
														req.info.tokens[tokid].outcome = matchingOutcome
													end
												end

												req:CompleteChanges("Complete roll")


												if check.type == "initiative" then
													creature.CompleteInitiative(tok.properties, rollInfo)
												end


											end

											currentRolls[rollid] = nil
										end,
										cancelRoll = function()
											if rollAllPromptsSet then
												autoCancelId = k
											end

											local req = dmhub.GetPlayerActionRequest(k)
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'cancel'
												req:CompleteChanges("Cancel roll dialog")
											end

											currentRolls[rollid] = nil
										end,
									}

                                    print("SHOWDIALOG:: PARAMS", json(dialogParams))

									if check:CustomInfo() ~= nil and check:CustomInfo().ShowDialog ~= nil then
										showingRollId = check:CustomInfo().ShowDialog(check, dialogParams)
									else
										showingRollId = gamehud.rollDialog.data.ShowDialog(dialogParams)
									end
								end

								ShowPromptDialog(1)

								--if we didn't kick off an auto roll set us to dialog status now.
								request = dmhub.GetPlayerActionRequest(k)
								if request.info.tokens[tokid].status == nil then
									request:BeginChanges()
									request.info.tokens[tokid].status = 'dialog'
									request.info.tokens[tokid].userid = dmhub.userid
									request:CompleteChanges("Show roll dialog")
								end

								return
							end
						end
					end
				end
			end
		end,
	}

	return resultPanel
end

local g_requireRollDialog = nil

local function CloseRequireRollDialog()
	if g_requireRollDialog ~= nil then
		g_requireRollDialog.parent:FireEvent("close")
	end
end

function GameHud:CreatePartyTokenPoolSelector(args)
	local initiative = args.initiative
	args.initiative = nil
	local resultPanel
	local tokenPanels = {}

	local selection = args.selection
	args.selection = nil

	local GetSelectedTokens = function()
		local result = {}
		for i,panel in ipairs(tokenPanels) do
			if panel:HasClass('selected') then
				result[#result+1] = panel.data.token.id
			end
		end
		return result
	end


	local candidateTokens = dmhub.GetTokens{ playerControlled = true, haveProperties = true }

	local selectedTokens = dmhub.selectedTokens
	for _,tok in ipairs(selectedTokens) do
		local found = false
		for _,existing in ipairs(candidateTokens) do
			if existing == tok then
				found = true
			end

			--for initiative, don't duplicate monsters of the same type.
			if initiative and InitiativeQueue.GetInitiativeId(tok) == InitiativeQueue.GetInitiativeId(existing) then
				found = true
			end
		end

		if not found then
			candidateTokens[#candidateTokens+1] = tok
		end
	end

    --- @param token CharacterToken
	local CreateTokenPanel = function(token)

		return gui.Panel{
			bgimage = 'panels/square.png',
			classes = 'token-panel',
			data = {
				token = token,
			},

			gui.CreateTokenImage(token),

            hover = function(element)
                gui.Tooltip(token.description)(element)
            end,

			press = function(element)
				element:SetClass('selected', not element:HasClass('selected'))
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		}

	end

	local startingSelection = {}

	for i,tok in ipairs(candidateTokens) do
		tokenPanels[#tokenPanels+1] = CreateTokenPanel(tok)
		for i,selectedTok in ipairs(selectedTokens) do
			if selectedTok == tok then
				startingSelection[#startingSelection+1] = tokenPanels[#tokenPanels]
			end
		end
	end

	local tokenPool = gui.Panel{
		bgimage = 'panels/square.png',
		bgcolor = 'black',
		cornerRadius = 8,
		border = 2,
		borderColor = '#888888',
		width = 210,
		height = 210,
		pad = 4,
		vscroll = true,
		vmargin = 8,
		flow = 'horizontal',
		wrap = true,

		styles = {
			{
				classes = {'token-panel'},
				bgcolor = 'black',
				cornerRadius = 8,
				width = 64,
				height = 64,
				halign = 'left',
			},
			{
				classes = {'token-panel', 'hover'},
				borderColor = 'grey',
				borderWidth = 2,
				bgcolor = '#441111',
			},
			{
				classes = {'token-panel', 'selected'},
				borderColor = 'white',
				borderWidth = 2,
				bgcolor = '#882222',
			},

		},

		children = tokenPanels
	}

	local tokenPoolSelection = gui.Panel{
		flow = 'horizontal',
		halign = 'center',
		width = 'auto',
		height = 'auto',

		styles = {
			{
				classes = {'token-pool-shortcut'},
				color = '#aaaaaa',
				fontSize = 16,
				width = 'auto',
				height = 'auto',
				valign = 'center',
				halign = 'center',
			},
			{
				classes = {'token-pool-shortcut', 'hover'},
				color = 'white',
			},
			{
				classes = {'shortcut-divider'},
				bgimage = 'panels/square.png',
				halign = 'center',
				valign = 'center',
				margin = 4,
				width = 2,
				height = 16,
				bgcolor = '#aaaaaa',
			},

		},

		gui.Label{
			classes = 'token-pool-shortcut',
			text = 'All',
			create = function(element)
				if selection == 'All' then
					element:FireEvent("click")
				else
					element:FireEvent("selectStarting")
				end
			end,
			click = function(element)
				for i,tokenPanel in ipairs(tokenPanels) do
					tokenPanel:SetClass('selected', true)
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
			selectStarting = function(element)
				for i,tokenPanel in ipairs(startingSelection) do
					tokenPanel:SetClass('selected', true)
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		},
		gui.Panel{
			classes = {'shortcut-divider'},
		},
		gui.Label{
			classes = 'token-pool-shortcut',
			text = 'Party',
			create = function(element)
				if selection == 'Party' then
					element:FireEvent("click")
				end
			end,
			click = function(element)
				for i,tokenPanel in ipairs(tokenPanels) do
					tokenPanel:SetClass('selected', tokenPanel.data.token.valid and tokenPanel.data.token.playerControlledNotShared and tokenPanel.data.token.properties ~= nil and tokenPanel.data.token.properties.typeName == 'character')
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		},
		gui.Panel{
			classes = {'shortcut-divider'},
		},
		gui.Label{
			classes = 'token-pool-shortcut',
			text = 'None',
			click = function(element)
				for i,tokenPanel in ipairs(tokenPanels) do
					tokenPanel:SetClass('selected', false)
				end
				resultPanel:FireEventTree('changeSelection', GetSelectedTokens())
			end,
		},
	}

	local options = {
		width = 'auto',
		height = 'auto',
		flow = "vertical",

		tokenPool,
		tokenPoolSelection,
	}

	for k,v in pairs(args) do
		options[k] = v
	end

	resultPanel = gui.Panel(options)

	return resultPanel
end

local g_selectedPowerRoll = setting{
    id = "selectedPowerRoll",
    description = "Selected Power Roll",
    editor = "dropdown",
    default = false,
    storage = "preference",
    classes = {"dmonly"},
}

function ShowRequireRollDialog(args)

	args = args or {}
	
	local tokenIdsSelected = {}

	local checkSelectedIndex = -1
	local checkTypeIndex = 1
	local checkTypeName = ''
	local checkTypeIndexes = {checkTypeIndex} --the actual multi-selection of which items we have selected.

    local m_skills = args.skills

    local m_tierInputs = nil
	local specializationChecks = {}

	local CreateRollTypeOption = function(options)
		return gui.Label{
			classes = {'roll-type-option', cond(options.selected, 'selected', nil)},
			bgimage = 'panels/square.png',
			text = options.text,
			press = function(element)
				local siblings = element.parent:GetChildrenWithClass('roll-type-option')
				for i,item in ipairs(siblings) do
					item:SetClass('selected', item == element)
				end

				checkSelectedIndex = options.index
				g_requireRollDialog:FireEventTree('refreshDiceCheck')
			end,
		}
	end

	local rollTypes = {}

	for i,check in ipairs(RollCheck.Checks) do
		if args.checkType == nil or args.checkType == check.name then
			if checkSelectedIndex == -1 then
				checkSelectedIndex = i
			end
			if #rollTypes ~= 0 then

				rollTypes[#rollTypes+1] = gui.Panel{
					bgimage = 'panels/square.png',
					bgcolor = '#aaaaaa',
					hmargin = 8,
					width = 2,
					height = 20,
					valign = 'center',
					halign = 'center',
				}
			end
			rollTypes[#rollTypes+1] = CreateRollTypeOption{ index = i, text = check.name, selected = (i == checkSelectedIndex) }
		end
	end

	dmhub.Debug(string.format("CREATE REQUIRE ROLLS: %s", json(g_requireRollDialog ~= nil)))

	g_requireRollDialog = gui.Panel{
		id = 'require-roll-dialog',

		destroy = function(element)
			if g_requireRollDialog == element then
				g_requireRollDialog = nil
			end
		end,

		styles = {
			{
				classes = {'formLabel'},
				fontSize = 18,
				color = 'white',
				width = 'auto',
				height = 'auto',
			},

			{
				classes = {'input'},
				width = 140,
				height = 20,
				fontSize = 18,
			},

			{
				classes = {'check-summary'},
				width = '100%',
				height = 80,
				valign = 'top',
				textAlignment = 'center',
				fontSize = 28,
				color = 'white',
			},

			{
				classes = {'result-panel'},
				flow = "horizontal",
				width = "100%",
				height = 70,
				valign = 'top',
			},

			{
				classes = {'result-panel-scroll'},
				width = '94%',
				height = 340,
				valign = 'center',
				flow = 'vertical',
			},

			{
				classes = {'result-status-label'},
				fontSize = 18,
				color = 'white',
				width = 80,
				textAlignment = 'left',
				height = 'auto',
				halign = 'left',
				valign = 'center',
			},
			{
				classes = {'result-outcome-label'},
				fontSize = 14,
				color = 'white',
				width = 100,
				textAlignment = 'left',
				height = 'auto',
				halign = 'left',
				valign = 'center',
			},
			{
				classes = {'result-consequences-table'},
				width = 140,
				flow = "vertical",
				height = "auto",
				valign = "center",
			},
			{
				classes = {'consequenceLabel'},
				width = 140,
				fontSize = 14,
				color = 'red',
				height = "auto",
			},
			{
				classes = {'consequenceLabel', 'avoided'},
				color = 'grey',
			},
		},

		halign = 'center',
		valign = 'center',

		width = 900,
		height = 600,

		flow = 'vertical',

        gui.Label{
            tmargin = 16,
            width = "auto",
            height = "auto",
            fontSize = 24,
            text = args.title or "",
            halign = "center",
        },
		
		gui.Panel{
			id = 'roll-type-panel',
			flow = 'horizontal',
			halign = 'center',
			valign = 'top',
			vmargin = 6,
			flow = 'horizontal',
			width = 'auto',
			height = 'auto',
            create = function(element)
                element:SetClass("collapsed", args.powerRollTable ~= nil)
            end,

			styles = {
				{
					classes = 'roll-type-option',
					fontSize = 24,
					width = 'auto',
					height = 'auto',
					color = '#aaaaaa',
					bgcolor = 'clear',
				},
				{
					classes = {'roll-type-option', 'hover'},
					color = '#ffffff',
					transitionTime = 0.1,
				},
				{
					classes = {'roll-type-option', 'selected'},
					color = '#ffffff',
					border = { x1 = 0, x2 = 0, y2 = 0, y1 = 2 },
					borderColor = '#ffffff',
					transitionTime = 0.2,
				},
			},

			children = rollTypes,
		},

		gui.Panel{
			id = 'main-check-panel',
			flow = 'horizontal',

			vmargin = 10,
			width = '90%',
			height = '80%',
			halign = 'center',
			valign = 'top',

            gui.Panel{
                classes = {cond(args.check == nil, "collapsed")},
                vscroll = true,
                width = "70%",
                height = "100%",
                create = function(element)
                    if args.check == nil then
                        return
                    end

                    
                end,
            },

			gui.Panel{
                classes = {cond(args.check ~= nil, "collapsed")},
				height = "100%",
				width = 200,
				pad = 4,
				halign = "left",
				flow = "vertical",

				gui.Panel{
					width = "auto",
					height = "auto",
					classes = {"collapsed"},
					refreshDiceCheck = function(element)
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						if checkInfo.group == nil then
							element:SetClass("collapsed", true)
							return
						end

						element:SetClass("collapsed", false)

						element.children = {
							gui.Dropdown{
								options = checkInfo.groups,
								idChosen = checkInfo.group:Get(),
								width = 160,
								change = function(element)
									checkInfo.group:Set(element.idChosen)
									g_requireRollDialog:FireEventTree('refreshDiceCheck')
								end,
							}
						}

					end,
				},

				gui.Panel{
					id = 'check-type-list',
					height = '100% available',
					width = 210,
					flow = 'vertical',
					vscroll = true,
					styles = {
						{
							classes = 'check-type-item',
							bgimage = 'panels/square.png',
							bgcolor = 'clear',
							fontSize = 16,
							minFontSize = 12,
							textAlignment = 'left',
							hpad = 3,
							halign = 'left',
							valign = 'top',
							width = 200,
							minHeight = 22,
							height = "auto",
						},
						{
							classes = {'check-type-item', 'selected'},
							bgcolor = '#660000',
						},
						{
							classes = {'check-type-item', 'hover'},
							bgcolor = '#660000',
						},
					},
					

					refreshDiceCheck = function(element)
						local children = {}

						local checkInfo = RollCheck.Checks[checkSelectedIndex]

						if #checkInfo.checks > 0 and (checkTypeIndex > #checkInfo.checks or checkInfo.checks[checkTypeIndex].text ~= checkTypeName) then
							checkTypeIndex = 1
							checkTypeName = checkInfo.checks[checkTypeIndex].text
							checkTypeIndexes = {checkTypeIndex}
						end

                        if args.characteristics and not table.empty(args.characteristics) then
                            checkTypeIndexes = {}
                        end

						for i,check in ipairs(checkInfo.checks) do
                            local selected = (i == checkTypeIndex)
                            if args.characteristics then
                                selected = args.characteristics[check.id]
                                if selected then
                                    checkTypeIndex = i
                                    checkTypeName = check.text
                                    checkTypeIndexes[#checkTypeIndexes+1] = i
                                end
                            end
							children[#children+1] = gui.Label{
								classes = {'check-type-item', cond(selected, 'selected'), cond(checkInfo.group ~= nil and checkInfo.group:Get() ~= check.group, 'collapsed')},
								text = check.text,
								press = function(element)
									local multiselect = dmhub.modKeys.ctrl or dmhub.modKeys.shift

									if multiselect then
										element:SetClass('selected', not element:HasClass('selected'))

										--make sure at least one item is selected.
										local hasSelection = false
										for _,el in ipairs(element.parent.children) do
											if el:HasClass("selected") then
												hasSelection = true
											end
										end

										if not hasSelection then
											element:SetClass('selected', true)
										end
									else
										for j,item in ipairs(element.parent.children) do
											item:SetClass('selected', j == i)
										end
									end

									if element:HasClass("selected") then
										checkTypeIndex = i
										checkTypeName = checkInfo.checks[checkTypeIndex].text
									end

									--refresh which indexes we have selected, since we support multi-selection.
									checkTypeIndexes = {}
									for index,el in ipairs(element.parent.children) do
										if el:HasClass("selected") then
											checkTypeIndexes[#checkTypeIndexes+1] = index
										end
									end

									g_requireRollDialog:FireEventTree("refreshSkill")
								end,
							}
						end

						element.children = children

						g_requireRollDialog:FireEventTree("refreshSkill")
					end,
				},

                gui.SetEditor{
                    options = Skill.skillsDropdownOptions,
                    value = table.list_to_set(m_skills),
                    addItemText = "Choose Skill...",
                    change = function(element, val)
                        m_skills = table.set_to_list(val)
                    end,
					refreshDiceCheck = function(element)
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
                        element:SetClass("collapsed", not checkInfo.skills)
                    end,
                },
			},

            --[[
			gui.Panel{
				flow = 'vertical',
				width = 220,
				height = '80%',
				valign = "top",
				vscroll = true,
				gui.Panel{
					halign = "left",
					width = 200,
					height = "auto",
					flow = "vertical",
					hpad = 4,

					refreshSkill = function(element)

						specializationChecks = {}
						
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						local skillInfo = checkInfo.checks[checkTypeIndex]
						if skillInfo == nil then
							element.children = {}
							return
						end

						if rawget(skillInfo, "specializations") == nil or #skillInfo.specializations == 0 then
							element.children = {}
							return
						end

						local children = {}
						for _,s in ipairs(skillInfo.specializations) do
							local check = gui.Check{
								data = {
									key = s.id,
								},
								text = s.text,
								fontSize = 16,
								value = false,
								height = 20,
								halign = "left",
								valign = "top",
							}
							children[#children+1] = check
						end

						element.children = children
						specializationChecks = children
					end,
				},
			},
            --]]

            --power table selection.
            gui.Panel{
                flow = 'vertical',
                width = "auto",
                height = "auto",
                refreshSkill = function(element)
                    local checkInfo = RollCheck.Checks[checkSelectedIndex]
                    local check = checkInfo.checks[checkTypeIndex]

                    if check == nil or (check.type ~= "resistance_power_roll" and check.type ~= "test_power_roll") then
                        element:SetClass("collapsed", true)
                        return
                    end

                    element:SetClass("collapsed", false)

                    print("CHECKINFO::", check)

                end,

                gui.Dropdown{
                    textDefault = "Choose Table...",
                    width = 320,
                    height = 24,
                    hasSearch = true,
                    create = function(element)
                        element:SetClass("collapsed", args.powerRollTable ~= nil)
                    end,
                    options = PowerRollTableGroup.CreateDropdownOptions(),
                    idChosen = g_selectedPowerRoll:Get(),
                    change = function(element)
                        g_selectedPowerRoll:Set(element.idChosen)
                        element.parent:FireEventTree("update")
                    end,
                },
                gui.Table{
                    width = 340,
                    height = "auto",
                    flow = "vertical",
                    create = function(element)

                        local children = {}

                        m_tierInputs = {}

                        for i=1,#GameSystem.TierNames do
                            local name = GameSystem.TierNames[i]
                            local input = gui.Input{
                                width = "70%",
                                height = "auto",
                                minHeight = 22,
                                wrap = true,
                                lineType = "multilinenewline",
                                characterLimit = 200,
                                fontSize = 18,
                                text = "",
                                update = function(element)
                                    local powerTable = args.powerRollTable or PowerRollTableGroup.GetPowerTable(g_selectedPowerRoll:Get())
                                    if powerTable ~= nil then
                                        element.text = powerTable.tiers[i] or ""
                                    end
                                end,
                                change = function(element)
                                end,
                            }

                            input:FireEvent("update")

                            m_tierInputs[i] = input

                            local panel = gui.TableRow{
                                width = "100%",
                                height = "auto",
                                gui.Label{
                                    width = "30%",
                                    height = 22,
                                    valign = "center",
                                    fontSize = 18,
                                    color = Styles.textColor,
                                    text = name,
                                },
                                input,
                            }

                            children[#children+1] = panel
                        end

                        element.children = children
                    end,
                }


            },

			gui.Panel{
				flow = 'vertical',
				width = 'auto',
				height = 'auto',
                halign = 'right',
				valign = 'top',

				gamehud:CreatePartyTokenPoolSelector{
					initiative = (args.checkType == "Initiative"),
					changeSelection = function(element, tokenids)
						tokenIdsSelected = tokenids
						g_requireRollDialog:FireEventTree('changePartySelection', tokenids)
					end
				}
			},
		},

		gui.PrettyButton{
			text = 'Submit',
			floating = true,
			halign = 'right',
			valign = 'bottom',
			margin = 18,
			create = function(element)
				element:SetClass('hidden', #tokenIdsSelected == 0)
			end,
			changePartySelection = function(element)
				element:FireEvent('create')
			end,

			click = function(element)

				local ensureInitiativeShown = false

				local checks = {}

                if args.check ~= nil then
                    checks = {args.check}
                else
                    for _,n in ipairs(checkTypeIndexes) do
                        local checkInfo = RollCheck.Checks[checkSelectedIndex]
                        local check = RollCheck.new(checkInfo.checks[n])

                        local specializations = {}
                        for _,check in ipairs(specializationChecks) do
                            if check.value then
                                specializations[check.data.key] = true
                            end
                        end

                        check:get_or_add("options", {})
                        check.options.specializations = specializations

                        check.options.skills = m_skills

                        if m_tierInputs ~= nil then
                            local tiers = {}
                            for i=1,#m_tierInputs do
                                tiers[i] = m_tierInputs[i].text
                            end

                            check.options.tiers = tiers
                        end

                        checks[#checks+1] = check

                        if check.type == "initiative" then
                            ensureInitiativeShown = true
                        end
                    end
                end

                print("CHECKINFO:: CHECKS = ", json(checks), "INDEXES =", checkTypeIndexes)

				if ensureInitiativeShown then
					local info = gamehud.initiativeInterface
					if info.initiativeQueue == nil or info.initiativeQueue.hidden then
						UploadDayNightInfo()
						info.initiativeQueue = InitiativeQueue.Create()
						info.UploadInitiative()
					end
				end
			
				local tokensSelected = {}
				for i,tok in ipairs(tokenIdsSelected) do
					tokensSelected[tok] = {}
				end
				local actionid = dmhub.SendActionRequest(RollRequest.new{
                    title = args.title,
					checks = checks,
					tokens = tokensSelected,
				})

				gamehud:ShowRollSummaryDialog(actionid)
			end,
		},

	}

	g_requireRollDialog:FireEventTree('refreshDiceCheck')
	return g_requireRollDialog
end

--resultTable gets marked with a 'result' = true/false for completion or cancel.
function GameHud:ShowRollSummaryDialog(actionid, resultTable)
	if resultTable == nil then
		resultTable = {}
	end


	local iscomplete = false

	local closeButton = gui.PrettyButton{
			text = 'Cancel',
			floating = true,
			halign = 'right',
			valign = 'bottom',
			margin = 24,
			click = function(element)
				resultTable.result = iscomplete
				resultTable.action = dmhub.GetPlayerActionRequest(actionid)

				if resultTable.action ~= nil and resultTable.action.info ~= nil then
					local info = resultTable.action.info
					print("INFO:: ", info, json(info))
				else
					print("INFO:: NONE")
				end
				dmhub.CancelActionRequest(actionid)
				CloseRequireRollDialog()
			end,
            destroy = function(element)
                --if this was exited some way that didn't have a result, then set it to no result / cancel.
                if resultTable.result == nil then
                    resultTable.result = false
                end
            end,
		}

	local action = dmhub.GetPlayerActionRequest(actionid)
	if action == nil then
		CloseRequireRollDialog()
		resultTable.result = false
		return
	end

	--ensure the request rolls dialog exists.
	LaunchablePanel.GetOrLaunchPanel("Request Rolls")


	local summaryPanel = gui.Label{
		text = string.format("Requested a %s", action.info:Describe()),
		classes = {'check-summary'},
		interactable = false,
	}

	local havePlayersOnline = false
	if #dmhub.users > 1 then
		for _,userid in ipairs(dmhub.users) do
			local session = dmhub.GetSessionInfo(userid)
			if session ~= nil and session.dm == false and session.loggedOut == false then
				havePlayersOnline = true
			end
		end
	end

    local numTokens = 0
    local numLocal = 0

	local resultsPanels = {}

	for k,v in pairs(action.info.tokens) do
		local tok = dmhub.GetCharacterById(k)
		if tok ~= nil then

            numTokens = numTokens + 1
			if ((v.forceuserid == nil and tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)) or v.forceuserid == dmhub.loginUserid) then
                numLocal = numLocal + 1
            end

            local checkInfo = action.info.checks[1]

			local outcomeLabel = gui.Label{
				classes = {'result-outcome-label'},
				text = '',
			}

			local consequencesTable = gui.Panel{
				classes = {'result-consequences-table'},
			}

			local againButton = nil
			
			if dmhub.isDM then
				againButton = gui.Button{
					text = 'Re-roll',
					halign = 'right',
					width = 80,
					height = 24,
					fontSize = 16,
					margin = 16,
					data = {
						takeroll = false,
					},
					takeroll = function(element, take)
						element.data.takeroll = take
						element.text = cond(take, "Take Roll", "Re-roll")
						element:SetClass("hidden", false)
					end,
					click = function(element)
						local actionInfo = action.info.tokens[k]
						if actionInfo ~= nil then
							outcomeLabel.text = ''
							action:BeginChanges()

							if element.data.takeroll and dmhub.isDM then
								action.info.tokens[k] = { forceuserid = dmhub.loginUserid }
							else
								action.info.tokens[k] = {}
							end
							action:CompleteChanges("Request roll again")
						end
						
					end,
				}
			end

			local panel

			local removeButton = gui.Button{
				classes = {"hidden"},
				text = 'Remove',
				halign = "right",
				width = 80,
				height = 24,
				fontSize = 14,
				margin = 16,
				click = function(element)
					action:BeginChanges()
					action.info.tokens[k] = nil
					action:CompleteChanges("Removed roll")
					panel:DestroySelf()
				end,

			}

			panel = gui.Panel{
				classes = {'result-panel'},

				gui.CreateTokenImage(tok),

				gui.Label{
					classes = {'result-status-label'},
					create = function(element)
						element:FireEvent('refreshAction')
					end,

					refreshAction = function(element)
						local actionInfo = action.info.tokens[k]
						if actionInfo ~= nil then
							removeButton:SetClass("hidden", true)
							if actionInfo.status == 'dialog' then
								if actionInfo.userid ~= nil then
									element.text = string.format("%s is preparing to roll...", dmhub.GetDisplayName(actionInfo.userid))
								else
									element.text = 'Reviewing Prompt'
								end

								if againButton ~= nil then
									againButton:FireEvent("takeroll", true)
								end
							elseif actionInfo.status == 'rolling' then
								element.text = 'Rolling'
								if againButton ~= nil then
									againButton:FireEvent("takeroll", false)
								end
							elseif actionInfo.status == 'complete' then
								element.text = 'Rolled'

								local text = string.format("<b>%d</b>", actionInfo.result)
								if actionInfo.outcome then
									text = string.format("<color=%s>%s (%s)</color>", actionInfo.outcome.color, text, actionInfo.outcome.outcome)
								end

								outcomeLabel.text = text
								if againButton ~= nil then
									againButton:FireEvent("takeroll", false)
								end

                                if numTokens == 1 and numLocal == 1 then
                                    iscomplete = true
                                    closeButton:FireEvent("click")
                                end

							elseif actionInfo.status == 'cancel' then
								element.text = 'Declined'
								removeButton:SetClass("hidden", false)
								if againButton ~= nil then
									againButton:SetClass("hidden", false)
									againButton:FireEvent("takeroll", false)
								end

                                if numTokens == 1 and numLocal == 1 then
                                    iscomplete = false
                                    closeButton:FireEvent("click")
                                end
							else
								element.text = 'Waiting...'
								if againButton ~= nil then
									againButton:FireEvent("takeroll", true)
								end
							end
						end

						if actionInfo ~= nil and actionInfo.status == 'complete' and actionInfo.outcome and checkInfo.consequences ~= nil then
							local children = {}
							local success = string.lower(actionInfo.outcome.outcome) == "success"

							local damageCalc = nil
							local damageEntry = nil
							for _,entry in ipairs(checkInfo.consequences.damage or {}) do
								if entry.tokens == nil or entry.tokens[k] then
									damageCalc = GameSystem.SavingThrowDamageCalculation(actionInfo.outcome, entry.success)
									damageEntry = entry
								end
							end

							if success then

								if damageCalc ~= nil then
									children[#children+1] = gui.Label{
										classes = {"consequenceLabel", "avoided"},
										text = string.format("%s %s (%s)", damageEntry.amount, damageEntry.damageType, damageCalc.summary or "saved"),
										color = damageCalc.color,
									}
								else
									children[#children+1] = gui.Label{
										classes = {"consequenceLabel", "avoided"},
										text = "Avoided",
									}
								end
							else
								if damageCalc ~= nil then
									children[#children+1] = gui.Label{
										classes = {"consequenceLabel"},
										text = string.format("%s %s (%s)", damageEntry.amount, damageEntry.damageType, damageCalc.summary or "full damage"),
										color = damageCalc.color,
									}
								else
									for _,entry in ipairs(checkInfo.consequences.conditions or {}) do
										local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
										local ongoingEffect = characterOngoingEffects[entry.conditionid]
										if ongoingEffect ~= nil then
											if entry.tokens == nil or entry.tokens[k] then
												children[#children+1] = gui.Label{
													classes = {"consequenceLabel"},
													text = string.format("%s", ongoingEffect.name),
												}
											end
										end
									end

									for _,entry in ipairs(checkInfo.consequences.text or {}) do
										if entry.tokens == nil or entry.tokens[k] then
											children[#children+1] = gui.Label{
												classes = {"consequenceLabel"},
												text = entry.text,
											}
										end
									end
								end
							end

							consequencesTable.children = children
						else
							consequencesTable.children = {}
						end
					end
				},

				outcomeLabel,

				consequencesTable,

				againButton,

				removeButton,
			}

			resultsPanels[#resultsPanels+1] = panel
		end
	end

    if numLocal == 1 and numTokens == 1 then
        g_requireRollDialog.parent:SetClass("hidden", true)
    end

	local resultPanelScroll = gui.Panel{
		classes = {'result-panel-scroll'},
		vscroll = true,
		children = resultsPanels,

		monitorGame = "/actionRequests",

		refreshGame = function(element)
			action = dmhub.GetPlayerActionRequest(actionid)
			if action == nil then
				CloseRequireRollDialog()
				return
			elseif g_requireRollDialog ~= nil then
				g_requireRollDialog:FireEventTree("refreshAction")

				local hasIncomplete = false
				for k,v in pairs(action.info.tokens) do
					if v.status ~= 'complete' then
						hasIncomplete = true
					end
				end


				iscomplete = not hasIncomplete

				closeButton.text = cond(hasIncomplete, 'Cancel', 'Proceed')
			end
		end,

	}

	local consequencesLabel = gui.Label{
		width = "55%",
		height = "auto",
		fontSize = 14,
		halign = "left",
		hmargin = 80,
		text = "",
		refreshAction = function(element)
			local checkInfo = action.info.checks[1]
			if checkInfo ~= nil and checkInfo.consequences ~= '' then
				element.text = ActivatedAbility.DescribeSavingThrowConsquences(checkInfo.consequences)
			else
				element.text = ""
			end
		end
	}

	g_requireRollDialog.children = {

		summaryPanel,

		resultPanelScroll,

		consequencesLabel,

		closeButton,

	}
end

--this is a silent/non-gui version of GameHud:ShowRollSummaryDialog that monitors an actionid for completion.
--designed to be run in a coroutine. Will cancel the request and time out eventually.
function AwaitRequestedActionCoroutine(actionid, resultTable)
	resultTable = resultTable or {}

	local delay = 0.2
	local iterations = 60*5/delay
	local action = dmhub.GetPlayerActionRequest(actionid)
	while action ~= nil and iterations > 0 do
		local incomplete = false
		for k,actionInfo in pairs(action.info.tokens) do
			if actionInfo.status ~= 'complete' and actionInfo.status ~= 'cancel' then
				incomplete = true
			end
		end

		if incomplete == false then
			resultTable.result = true
			resultTable.action = action
			dmhub.CancelActionRequest(actionid)
			return resultTable
		end

		coroutine.yield(delay)
		action = dmhub.GetPlayerActionRequest(actionid)

		iterations = iterations - 1
	end
	
	if action ~= nil then
		dmhub.CancelActionRequest(actionid)
	end
	resultTable.result = false

	return resultTable
end



LaunchablePanel.Register{
	name = "Request Rolls",
    menu = "game",
	icon = "game-icons/dice-twenty-faces-twenty.png",
	halign = "center",
	valign = "center",
	hidden = function()
		return not dmhub.isDM
	end,
	content = function(args)
		g_requireRollDialog = ShowRequireRollDialog(args)
		return g_requireRollDialog
	end,
}
