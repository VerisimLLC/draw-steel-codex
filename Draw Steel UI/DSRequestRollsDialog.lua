local mod = dmhub.GetModLoading()

-- Style pack for `gamehud:CreatePartyTokenPoolSelector`. Applied via
-- ThemeEngine.MergeTokens on the function's result panel so the selector
-- looks the same regardless of which dialog calls it -- the function
-- carries its own styling instead of leaning on the caller's cascade.
local g_TokenPoolStyles = {
	{
		selectors = {"tokenPanel"},
		bgcolor = "@bg",
		cornerRadius = 8,
		width = 64,
		height = 64,
		halign = "left",
	},
	{
		selectors = {"tokenPanel", "hover"},
		borderColor = "@border",
		borderWidth = 2,
		bgcolor = "@bgInverse",
		color = "@fgInverse",
		brightness = 0.5,
	},
	{
		selectors = {"tokenPanel", "selected"},
		borderColor = "@fgStrong",
		borderWidth = 2,
		bgcolor = "@bgInverse",
		color = "@fgInverse",
	},
	{
		selectors = {"tokenPoolShortcut"},
		color = "@fgMuted",
		fontSize = 16,
		width = "auto",
		height = "auto",
		valign = "center",
		halign = "center",
	},
	{
		selectors = {"tokenPoolShortcut", "hover"},
		color = "@fgStrong",
	},
	{
		selectors = {"shortcutDivider"},
		bgimage = true,
		bgcolor = "@fgMuted",
		halign = "center",
		valign = "center",
		margin = 4,
		width = 2,
		height = 16,
	},
}

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
--- @class RollCheck: GameType
RollCheck = RegisterGameType("RollCheck")

--A RollRequest instance has the following fields:
-- checks = a list of RollChecks that the token can choose from. Most often this will just have one option.
-- tokens = map of token id -> result table. Result table begins empty and is filled by the target. May have a checks list which is a list of indexes into checks that are available to this token.
-- contest = (optional) if true this is a contested roll between the tokens. The tokens map will have a "team" identifier to signal which side of the contest they are on.
--- @class RollRequest: GameType
RollRequest = RegisterGameType("RollRequest")

RollCheck.consequences = ''
RollCheck.explanation = ''

RollRequest.contest = false
RollRequest.dicetower = false

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
		local skillInfo = Skill.SkillsById[self.id]
		if skillInfo == nil then
			printf("WARNING: RollCheck:GetRoll -- unknown skill id '%s' for roll type '%s', returning base roll", tostring(self.id), tostring(self.type))
			return GameSystem.BaseSkillRoll
		end
		return string.format("%s+%d", GameSystem.BaseSkillRoll, creature:SkillMod(skillInfo))
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

	if self.type == "test_power_roll" or self.type == "resistance_power_roll" then
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

        local checkOptions = self:try_get("options", {})
        local modifierOptions = {
            attribute = self.id,
            skills = skills,
            --The ability that started this opposed test, so a modifier can ask
            --questions like "Ability.name is Search for Hidden Creatures".
            ability = checkOptions.ability,
            title = rollRequest ~= nil and rollRequest:try_get("title"),
        }

		--Modifiers for the creature making the roll. An opposed test is still a
		--test, so ask for both kinds: a modifier set to "Tests" and one set to
		--"Opposed Tests" should each show up here.
		local result = creature:GetModifiersForPowerRoll(self:GetRoll(creature), "test_power_roll", modifierOptions)

		--A modifier set to "All" roll types answers both questions, so remember
		--what we already have and don't list it twice.
		local alreadyListed = {}
		for _,mod in ipairs(result) do
			alreadyListed[mod.modifier:try_get("guid") or mod.modifier] = true
		end

		for _,mod in ipairs(creature:GetModifiersForPowerRoll(self:GetRoll(creature), "opposed_power_roll", modifierOptions)) do
			local key = mod.modifier:try_get("guid") or mod.modifier
			if not alreadyListed[key] then
				alreadyListed[key] = true
				result[#result+1] = mod
			end
		end

		if skill ~= nil and creature:ProficientInSkill(skill) then
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
		local skillInfo = Skill.SkillsById[self.id]
		if skillInfo == nil then
			printf("WARNING: RollCheck:GetModifiers -- unknown skill id '%s' for roll type '%s', returning empty modifiers", tostring(self.id), tostring(self.type))
			return {}
		end
		return creature:GetModifiersForSkillCheckRoll(skillInfo, self:try_get("options"))
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
            --Picked from a characteristic multiselect instead of the check list, so a
            --chosen power roll table can fill it in. See SyncCheckIndexesFromCharacteristics.
            characteristics = true,
		},
		{
			name = 'Table',
			group = g_tableGroupSetting,
			groups = tableGroups,
			checks = tableChecks,
		},
	}
end


--A roll request whose checks carry options.parallelWithRollDialog = true is
--allowed to surface its prompt while another roll dialog is on screen. Used by
--triggered tests (e.g. Devilish Charm's Presence test) that must resolve while
--the roll that triggered them is still open and pending. Everything else keeps
--the historical behavior of deferring until no roll dialog is shown. pcall
--guarded so an exotic request payload can never break the listener panel.
local function RequestAllowsParallelPrompt(request)
    local result = false
    pcall(function()
        if request.info.typeName ~= "RollRequest" then
            return
        end
        for _,check in ipairs(request.info.checks or {}) do
            local opts = check:try_get("options")
            if opts ~= nil and opts.parallelWithRollDialog then
                result = true
                return
            end
        end
    end)
    return result
end

local function HaveParallelPromptRequest()
    for _,request in pairs(dmhub.GetPlayerActionRequests() or {}) do
        if RequestAllowsParallelPrompt(request) then
            return true
        end
    end
    return false
end

--Roll types shown in the newer Timeline roller (the one that mounts under the
--ability card) instead of the old floating dialog. Anything not listed here
--keeps the old dialog. Move one type over at a time.
local g_timelineRollTypes = {
    opposed_power_roll = true,
}

--Wraps the old floating dialog so callers can treat both dialogs the same way.
local function LegacyPromptHandle(rollid)
    return {
        rollid = rollid,
        IsShown = function()
            local dialog = gamehud ~= nil and gamehud.rollDialog or nil
            return dialog ~= nil and dialog.valid and dialog.data ~= nil
                and dialog.data.IsShown ~= nil and dialog.data.IsShown()
        end,
        LiveRollId = function()
            local dialog = gamehud ~= nil and gamehud.rollDialog or nil
            return dialog ~= nil and dialog.valid and dialog.data ~= nil and dialog.data.rollid or nil
        end,
        Cancel = function()
            local dialog = gamehud ~= nil and gamehud.rollDialog or nil
            if dialog ~= nil and dialog.valid and dialog.data ~= nil and dialog.data.Cancel ~= nil then
                dialog.data.Cancel()
            end
        end,
    }
end

--Show a requested roll in the Timeline roller. Returns a handle, or nil if we
--could not get a Timeline surface and the caller should use the old dialog.
--
--dialogParams is modified in place on success (we add the header text and wrap
--the finish callbacks), so only call this when we are committed to this route.
local function ShowTimelinePrompt(check, dialogParams)
    if rawget(_G, "CharacterPanel") == nil or CharacterPanel.EmbedPromptRollDialog == nil then
        return nil
    end

    local checkOptions = check:try_get("options", {})

    local casterToken = nil
    if checkOptions.casterid ~= nil then
        casterToken = dmhub.GetTokenById(checkOptions.casterid)
    end

    local mount = CharacterPanel.EmbedPromptRollDialog{
        token = casterToken,
        ability = checkOptions.ability,
    }

    if mount == nil or mount.dialog == nil or not mount.dialog.valid
       or mount.dialog.data == nil or mount.dialog.data.ShowDialog == nil then
        return nil
    end

    --The Timeline roller shows no title of its own, so hand it the same two
    --lines the old dialog printed above the roll.
    local headerLines = {}
    if dialogParams.description ~= nil and dialogParams.description ~= "" then
        headerLines[#headerLines+1] = string.format("<b>%s</b>", dialogParams.description)
    end
    if dialogParams.explanation ~= nil and dialogParams.explanation ~= "" then
        headerLines[#headerLines+1] = dialogParams.explanation
    end
    dialogParams.promptHeader = table.concat(headerLines, "\n")

    --Put the ability card away again if we were the ones who put it up. Nothing
    --else will: only a real ability cast installs a teardown handler.
    local tornDown = false
    local function Teardown()
        if tornDown then
            return
        end
        tornDown = true

        if mount.dialog ~= nil and mount.dialog.valid and mount.dialog.data ~= nil then
            mount.dialog.data.promptPending = nil
        end

        if mount.locked then
            CharacterPanel.UnlockDisplayAbility(mount.lockId)
        end
        if mount.ownedAbility ~= nil then
            --Safe if someone else has since taken the card over; HideAbility
            --only acts when the card is still showing this ability.
            CharacterPanel.HideAbility(mount.ownedAbility)
        end
    end

    local resolved = false
    local origComplete = dialogParams.completeRoll
    local origCancel = dialogParams.cancelRoll

    --Original first so the action request is always written, teardown after.
    dialogParams.completeRoll = function(rollInfo)
        resolved = true
        if origComplete ~= nil then
            origComplete(rollInfo)
        end
        Teardown()
    end

    dialogParams.cancelRoll = function()
        resolved = true
        if origCancel ~= nil then
            origCancel()
        end
        Teardown()
    end

    --Give the freshly mounted dialog time to build itself before the roll goes
    --in; see mount.showDelay. ShowDialog handles this for us: outside a
    --coroutine it picks a roll id, reschedules itself, and hands the id back
    --now, so the request bookkeeping below still gets its id immediately.
    dialogParams.delay = mount.showDelay

    local rollid = mount.dialog.data.ShowDialog(dialogParams)

    if not mount.dialog.valid or rollid == nil then
        --ShowDialog bailed. Undo everything and let the caller fall back.
        dialogParams.completeRoll = origComplete
        dialogParams.cancelRoll = origCancel
        dialogParams.promptHeader = nil
        dialogParams.delay = nil
        Teardown()
        return nil
    end

    --If the panel is destroyed without finishing -- displaced by a new cast, or
    --the card closed from somewhere else -- neither callback fires, which would
    --leave the request stuck waiting on a roll that can no longer happen. Watch
    --for that and release it.
    --
    --Only a DESTROYED panel counts. The dialog hides itself the moment the dice
    --are thrown and stays hidden while they are still in the air, so "hidden" is
    --not "finished" -- and the roll keeps calling into the panel the whole time,
    --so we must never destroy it here either.
    local Watch
    Watch = function()
        if mod.unloaded or tornDown or resolved then
            return
        end

        local dialog = mount.dialog
        if dialog == nil or not dialog.valid then
            resolved = true
            if origCancel ~= nil then
                origCancel()
            end
            Teardown()
            return
        end

        dmhub.Schedule(0.25, Watch)
    end
    dmhub.Schedule(0.25, Watch)

    return {
        rollid = rollid,
        IsShown = function()
            local dialog = mount.dialog
            return dialog ~= nil and dialog.valid and dialog.data ~= nil
                and dialog.data.IsShown ~= nil and dialog.data.IsShown()
        end,
        LiveRollId = function()
            local dialog = mount.dialog
            return dialog ~= nil and dialog.valid and dialog.data ~= nil and dialog.data.rollid or nil
        end,
        Cancel = function()
            local dialog = mount.dialog
            if dialog ~= nil and dialog.valid and dialog.data ~= nil and dialog.data.Cancel ~= nil then
                dialog.data.Cancel()
            end
        end,
    }
end

--Show a requested roll in whichever dialog that roll type uses.
local function ShowRollPrompt(check, dialogParams)
    if check == nil then
        return nil
    end

    local customInfo = check:CustomInfo()
    if customInfo ~= nil and customInfo.ShowDialog ~= nil then
        return LegacyPromptHandle(customInfo.ShowDialog(check, dialogParams))
    end

    if g_timelineRollTypes[check.type] then
        local handle = ShowTimelinePrompt(check, dialogParams)
        if handle ~= nil then
            return handle
        end
        --No Timeline surface available; fall through to the old dialog.
    end

    return LegacyPromptHandle(gamehud.rollDialog.data.ShowDialog(dialogParams))
end

--this is a hidden panel which just listens for required rolls.
function GameHud:RequireRollListenerPanel()

	local autoRollId = nil
	local autoCancelId = nil

	--tracks the ID of the roll dialog we are showing. This way we can cancel that dialog
	--if needed due to the roll request being retracted. showingPrompt is the handle
	--for whichever dialog that turned out to be -- the roll type decides.
	local showingRollId = nil
	local showingPrompt = nil
	local rollRequestId = nil

	--track rolls we currently have ongoing
	local currentRolls = {}

	local resultPanel = gui.Panel{
		floating = true,
		width = 0,
		height = 0,

		monitorGame = "/actionRequests",

		refreshGame = function(element)
			--Defer if ANY roll dialog is on screen, not just the legacy singleton.
			--Otherwise a table roll (e.g. the Conduit prayer, which routes to the
			--standalone host) pops on top of an in-flight ability/ongoing-effect
			--roll shown in the embedded dialog. See CharacterPanel.AnyRollDialogShown.
			--Exception: requests flagged parallelWithRollDialog (see
			--RequestAllowsParallelPrompt above) surface immediately; only the
			--flagged requests are processed in that state, everything else keeps
			--deferring until the blocking dialog closes.
			local dialogShown = CharacterPanel.AnyRollDialogShown()

			if dialogShown and showingPrompt ~= nil and showingPrompt.IsShown()
			   and showingRollId == showingPrompt.LiveRollId() then
				--we requested the current roll dialog that is shown. See if our reason
				--for doing so has been canceled, in which case we want to close that dialog.
				if dmhub.GetPlayerActionRequest(rollRequestId) == nil then
					showingPrompt.Cancel()
				end
			end

			if dialogShown then
				--we are currently blocked by a roll dialog. Try again in a little
				--while. (Also scheduled in the parallel fall-through, so deferred
				--non-flagged requests still surface once the dialog closes.)
				element:ScheduleEvent("refreshGame", 0.2)

				if not HaveParallelPromptRequest() then
					return
				end
			end

			local requests = dmhub.GetPlayerActionRequests()
			for k,request in pairs(requests) do
				if dialogShown and not RequestAllowsParallelPrompt(request) then
					--still deferred behind the open roll dialog.
				elseif request.info.typeName == 'RestRequest' then
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
							--A ghost session (a player who dropped without logging out) reports
							--loggedOut == false forever with a huge timeSinceLastContact. Counting
							--it as online meant the Director was never prompted for a player-owned
							--hero's roll while nobody was actually there, stalling the request.
							--140s is the presence threshold used elsewhere (Audio.lua, Encounter).
							if session ~= nil and session.dm == false and session.loggedOut == false and (session.timeSinceLastContact or 0) < 140 then
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
							--who does this client prompt for: a plain player, anything they control;
							--a DM/host, non-player tokens (or anything with no players online); a
							--player host additionally their OWN tokens -- canControl is host-wide
							--for them, so ownership is the discriminator. (playerHostMode reads
							--nil on engine builds without it, keeping the old behavior exactly.)
							if tok ~= nil and tok.properties and ((info.forceuserid == nil and tok.canControl and (IsDMOrPlayerHost() == false or tok.playerControlled == false or not havePlayersOnline or (dmhub.playerHostMode == true and tok.ownerId == dmhub.loginUserid))) or info.forceuserid == dmhub.loginUserid) and not currentRolls[rollid] then
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
							--who does this client prompt for: a plain player, anything they control;
							--a DM/host, non-player tokens (or anything with no players online); a
							--player host additionally their OWN tokens -- canControl is host-wide
							--for them, so ownership is the discriminator. (playerHostMode reads
							--nil on engine builds without it, keeping the old behavior exactly.)
							if tok ~= nil and tok.properties and ((info.forceuserid == nil and tok.canControl and (IsDMOrPlayerHost() == false or tok.playerControlled == false or not havePlayersOnline or (dmhub.playerHostMode == true and tok.ownerId == dmhub.loginUserid))) or info.forceuserid == dmhub.loginUserid) and not currentRolls[rollid] then

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
									if check == nil then
										--The request asked this token to roll but handed it no
										--checks to roll. Badly authored content can do this;
										--don't take the client down over it.
										printf("WARNING: roll request %s has no check %d for token %s -- nothing to prompt.", tostring(k), checkIndex, tostring(tokid))
										return
									end

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
                                        --Must be the RollOnTableProperties subclass so
                                        --the action log renders table rows; base
                                        --RollProperties has no table-aware CustomPanel.
                                        rollProperties = RollOnTableProperties.new{}
                                        rollProperties.tableRef = check.tableRef
                                    end

									local autoroll = nil
									--While the Monster AI is running it plays the monsters, so a
									--roll requested of a director-run token (e.g. the Hide test a
									--hidden monster makes against Search for Hidden Creatures)
									--should not stop on a prompt: roll it and proceed as the AI
									--would. rawget: the Monster AI module may not be loaded.
									local aiRoll = false
									if IsDMOrPlayerHost() and tok.playerControlled == false then
										local monsterAI = rawget(_G, "MonsterAI")
										if monsterAI ~= nil and monsterAI.IsAIRunning ~= nil and monsterAI.IsAIRunning() then
											aiRoll = true
										end
									end
									if autoRollId == k then
										autoroll = true
										if autoCancelId == k then
											autoroll = "cancel"
										end
									--real hosting check: monster resistance rolls must keep
									--auto-resolving on a player host or the AI stalls on a prompt.
									elseif IsDMOrPlayerHost() and tok.playerControlled == false then
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
										dicetower = request.info.dicetower,

                                        PopulateCustom = PopulateCustom,

										alternateOptions = alternateOptions,
										alternateChosen = checkIndex,
										chooseAlternate = function(alternateIndex)
										    if showingPrompt ~= nil then
										        showingPrompt.Cancel()
										    end
											ShowPromptDialog(alternateIndex, true)
										end,

										numPrompts = numPrompts,
										rollAllPrompts = function()
											rollAllPromptsSet = true
											autoRollId = k
											dmhub.Debug("ROLL:: ALL PROMPTS")
										end,
										autoroll = autoroll,
										aiRoll = aiRoll,
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
											if req ~= nil and req.info.tokens[tokid] ~= nil then
												req:BeginChanges()
												req.info.tokens[tokid].status = 'complete'
												req.info.tokens[tokid].result = rollInfo.total
												req.info.tokens[tokid].naturalRoll = rollInfo.naturalRoll
												req.info.tokens[tokid].boons = rollInfo.boons
												req.info.tokens[tokid].banes = rollInfo.banes
												req.info.tokens[tokid].dice = RollUtils.SortedDice(rollInfo)
												req.info.tokens[tokid].isCrit = RollUtils.IsCrit(rollInfo)
												req.info.tokens[tokid].rollid = rollInfo.key
												req.info.tokens[tokid].modifiersUsed = rollInfo.properties ~= nil and rollInfo.properties:try_get("modifiersUsed", {}) or {}
												if rollType == "test_power_roll" then
													--Keep tier-changing test effects when the result returns to the ability's caster.
													local overrideTier = rollInfo.properties ~= nil and rollInfo.properties:try_get("overrideTier") or nil
													req.info.tokens[tokid].tier = overrideTier or RollUtils.DiceResultToTier(rollInfo)
												end

												if rollInfo.forcedResult then
													req.info.tokens[tokid].forcedResult = rollInfo.autosuccess
												end
												
												if rollInfo.properties then
													local matchingOutcome = rollInfo.properties:try_get("overrideOutcome") or rollInfo.properties:GetOutcome(rollInfo)
													if matchingOutcome and matchingOutcome.outcome ~= nil then
														matchingOutcome.outcome = StringInterpolateGoblinScript(matchingOutcome.outcome, tok.properties)
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


									showingPrompt = ShowRollPrompt(check, dialogParams)
									showingRollId = showingPrompt ~= nil and showingPrompt.rollid or nil
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

	local poolWidth = args.poolWidth
	args.poolWidth = nil
	local poolHeight = args.poolHeight
	args.poolHeight = nil

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
			bgimage = true,
			classes = {"tokenPanel"},
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
		classes = {"bordered"},
		halign = "left",
		lmargin = 12,
		width = poolWidth or 210,
		height = poolHeight or 210,
		cornerRadius = 8,
		pad = 4,
		vscroll = true,
		vmargin = 8,
		flow = "horizontal",
		wrap = true,

		children = tokenPanels
	}

	local tokenPoolSelection = gui.Panel{
		flow = "horizontal",
		halign = "left",
		width = poolWidth or 210,
		height = "auto",

		gui.Label{
			classes = {"tokenPoolShortcut"},
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
			classes = {"shortcutDivider"},
		},
		gui.Label{
			classes = {"tokenPoolShortcut"},
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
			classes = {"shortcutDivider"},
		},
		gui.Label{
			classes = {"tokenPoolShortcut"},
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
		width = 600,
		height = 'auto',
		flow = "vertical",
		styles = ThemeEngine.MergeTokens(g_TokenPoolStyles),

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

--Layout constants for the dialog's three columns. The side columns are equal so the
--middle one -- which takes the remaining width -- ends up centered on its own.
local SIDE_COLUMN_WIDTH = 220
local PICKER_WIDTH = 206
local TOKEN_POOL_WIDTH = 206

function ShowRequireRollDialog(args)

	args = args or {}

	local tokenIdsSelected = {}

	local checkSelectedIndex = -1
	local checkTypeIndex = 1
	local checkTypeName = ''
	local checkTypeIndexes = {checkTypeIndex} --the actual multi-selection of which items we have selected.

    local m_skills = args.skills or {}
    local m_dicetower = false

    --The Test tab's selection lives here rather than in the check list.
    --SyncCheckIndexesFromCharacteristics maps it onto checkTypeIndexes, which Submit reads.
    local m_characteristics = DeepCopy(args.characteristics or {})

    local m_tierInputs = nil
	local specializationChecks = {}

	--gui.Multiselect raises `change` when an item is added but NOT when a chip's X is
	--clicked, so the last change we were told about can be stale. Keep the widgets
	--themselves and read their live selection whenever it actually matters.
	local m_characteristicsPanel = nil
	local m_skillsPanel = nil

	local function LiveSet(panel, fallback)
		if panel ~= nil and panel.valid then
			return panel.data.selected
		end

		return fallback
	end

	--Push a set into a gui.Multiselect from outside. Does what the widget's own
	--SetValue does -- replace data.selected, then repaint chips and dropdown.
	local function SetMultiselectValue(element, valueSet)
		local selected = element.data.selected
		for k in pairs(selected) do
			selected[k] = nil
		end

		for k,v in pairs(valueSet or {}) do
			if v then
				selected[k] = true
			end
		end

		element:FireEventTree("repaint", selected)
	end

	local function SyncCheckIndexesFromCharacteristics()
		local checkInfo = RollCheck.Checks[checkSelectedIndex]
		if checkInfo == nil or not checkInfo.characteristics then
			return
		end

		local selected = LiveSet(m_characteristicsPanel, m_characteristics)

		checkTypeIndexes = {}
		for i,check in ipairs(checkInfo.checks) do
			if selected[check.id] then
				checkTypeIndexes[#checkTypeIndexes+1] = i
				if #checkTypeIndexes == 1 then
					checkTypeIndex = i
					checkTypeName = check.text
				end
			end
		end
	end

	--Choosing e.g. "Gymnastics - Medium: Cross a Crumbling Bridge" fills in the
	--characteristic that test is rolled with and ticks its skill, so the Director
	--doesn't have to restate what the test already knows. Both are still editable.
	local function ApplyPowerTableSuggestions(id, refresh)
		local characteristics, skills = PowerRollTableGroup.GetSuggestions(id)

		if not table.empty(characteristics) then
			m_characteristics = characteristics
		end

		if #skills > 0 then
			m_skills = skills
		end

		if refresh and g_requireRollDialog ~= nil then
			--Push straight into the two widgets. Doing it from their refreshDiceCheck
			--instead would also fire on a tab switch, resurrecting whatever the Director
			--had taken off since.
			if m_characteristicsPanel ~= nil and m_characteristicsPanel.valid then
				SetMultiselectValue(m_characteristicsPanel, m_characteristics)
			end

			if m_skillsPanel ~= nil and m_skillsPanel.valid then
				SetMultiselectValue(m_skillsPanel, table.list_to_set(m_skills))
			end

			g_requireRollDialog:FireEventTree("refreshDiceCheck")
		end
	end

	--A dialog opened without an explicit test (args.powerRollTable) restores the last
	--table the Director chose, so honor that table's suggestions on open too.
	if args.powerRollTable == nil and table.empty(m_characteristics) then
		ApplyPowerTableSuggestions(g_selectedPowerRoll:Get(), false)
	end

	local CreateRollTypeOption = function(options)
		return gui.Button{
			classes = {"sizeM", "rollTypeButton", cond(options.selected, "selected", nil)},
			text = options.text,
			hmargin = 4,
			press = function(element)
				local siblings = element.parent:GetChildrenWithClass("rollTypeButton")
				for i,item in ipairs(siblings) do
					item:SetClass("selected", item == element)
				end

				checkSelectedIndex = options.index
				g_requireRollDialog:FireEventTree("refreshDiceCheck")
			end,
		}
	end

	local rollTypes = {}

	for i,check in ipairs(RollCheck.Checks) do
		if args.checkType == nil or args.checkType == check.name then
			if checkSelectedIndex == -1 then
				checkSelectedIndex = i
			end
			rollTypes[#rollTypes+1] = CreateRollTypeOption{ index = i, text = check.name, selected = (i == checkSelectedIndex) }
		end
	end

	--Nothing named a characteristic -- no explicit test, and no remembered table with a
	--skill on it -- so fall back to the first one, the way the old list picker did.
	if table.empty(m_characteristics) then
		local checkInfo = RollCheck.Checks[checkSelectedIndex]
		if checkInfo ~= nil and checkInfo.characteristics and checkInfo.checks[1] ~= nil then
			m_characteristics = { [checkInfo.checks[1].id] = true }
		end
	end

	dmhub.Debug(string.format("CREATE REQUIRE ROLLS: %s", json(g_requireRollDialog ~= nil)))

	g_requireRollDialog = gui.Panel{
		id = 'require-roll-dialog',
        classes = {"framedPanel"},

		destroy = function(element)
			if g_requireRollDialog == element then
				g_requireRollDialog = nil
			end
		end,

		styles = ThemeEngine.GetStyles(),

		halign = "center",
		valign = "center",

		--Sized to the TYPICAL test, not the longest one: across the 804 imported tier
		--strings the median is ~124 characters, which is two lines at this width. The
		--handful of 300+ character outcomes scroll the middle column instead of forcing
		--a window this big to sit half empty the rest of the time.
		width = 1300,
		height = 680,

		flow = "vertical",

        gui.Label{
            classes = {"modalTitle"},
            tmargin = 16,
            text = args.title or "",
        },

		gui.Panel{
			id = "roll-type-panel",
			flow = "horizontal",
			halign = "center",
			valign = "top",
			width = "auto",
			height = "auto",
			vmargin = 6,
			styles = ThemeEngine.MergeTokens({
				{
					selectors = {"rollTypeButton", "selected"},
					borderWidth = 2,
					borderColor = "@accent",
				},
			}),
            create = function(element)
                element:SetClass("collapsed", args.powerRollTable ~= nil)
            end,

			children = rollTypes,
		},

		--Three columns: the two side columns are fixed and equal, the middle takes
		--whatever is left. Equal sides is what centers the middle -- nothing here
		--positions it explicitly, so widening the dialog keeps it centered.
		gui.Panel{
			id = 'main-check-panel',
			flow = 'horizontal',
			vmargin = 10,
			width = '94%',
			--A share of the dialog rather than "100% available": the latter makes the
			--tier rows' percentage widths resolve against an unknown base and collapse.
			--Leave slack for the tabs above and the button row below -- at 80% the
			--buttons were pushed through the bottom of the frame.
			height = '75%',
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

			--Left column. SIDE_COLUMN_WIDTH wide, matching the party column on the
			--right; its pickers are PICKER_WIDTH so their dropdown triangles clear the
			--edge. Keep these three in step if you resize any of them.
			gui.Panel{
                classes = {cond(args.check ~= nil, "collapsed")},
				height = "100%",
				width = SIDE_COLUMN_WIDTH,
				pad = 4,
				halign = "left",
				flow = "vertical",

				gui.Panel{
					classes = {"collapsed"},
					width = "auto",
					height = "auto",
					refreshDiceCheck = function(element)
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						if checkInfo.group == nil then
							element:SetClass("collapsed", true)
							return
						end

						element:SetClass("collapsed", false)

						element.children = {
							gui.Dropdown{
								classes = {"form"},
								options = checkInfo.groups,
								idChosen = checkInfo.group:Get(),
								width = 160,
								change = function(element)
									---@cast element Dropdown
									checkInfo.group:Set(element.idChosen)
									g_requireRollDialog:FireEventTree('refreshDiceCheck')
								end,
							}
						}

					end,
				},

				--The Test tab's characteristic picker. It stands in for check-type-list
				--(which stays for the Table tab) so a chosen power roll table can fill
				--the characteristic in. Multiselect, because a test may be rollable with
				--either of two characteristics.
				gui.Panel{
					flow = "vertical",
					width = PICKER_WIDTH,
					height = "auto",
					halign = "left",
					valign = "top",
					bmargin = 12,

					refreshDiceCheck = function(element)
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						element:SetClass("collapsed", not checkInfo.characteristics)
					end,

					gui.Label{
						classes = {"fgMuted"},
						width = "auto",
						height = "auto",
						halign = "left",
						fontSize = 14,
						text = "Characteristic",
					},

					gui.Multiselect{
						halign = "left",
						width = PICKER_WIDTH,
						vmargin = 4,
						value = m_characteristics,
						--Short on purpose: the caption above already names the field, and a
						--longer string crowds out the dropdown's own triangle at this width.
						addItemText = "Choose...",
						options = creature.attributeDropdownOptions,

						create = function(element)
							m_characteristicsPanel = element
						end,

						change = function(element, val)
							m_characteristics = val
							SyncCheckIndexesFromCharacteristics()
							g_requireRollDialog:FireEventTree("refreshSkill")
						end,
					},
				},

				--Sits directly under the characteristic picker: the two answer the same
				--question about the roll, and a chosen test fills both in together.
				gui.Panel{
					flow = "vertical",
					width = PICKER_WIDTH,
					height = "auto",
					halign = "left",
					valign = "top",
					bmargin = 12,

					refreshDiceCheck = function(element)
						local checkInfo = RollCheck.Checks[checkSelectedIndex]
						element:SetClass("collapsed", not checkInfo.skills)
					end,

					gui.Label{
						classes = {"fgMuted"},
						width = "auto",
						height = "auto",
						halign = "left",
						fontSize = 14,
						text = "Skill",
					},

					gui.Multiselect{
						halign = "left",
						width = PICKER_WIDTH,
						vmargin = 4,
						options = Skill.skillsDropdownOptions,
						value = table.list_to_set(m_skills),
						addItemText = "Choose...",

						create = function(element)
							m_skillsPanel = element
						end,

						change = function(element, val)
							m_skills = table.set_to_list(val)
						end,
					},
				},

				gui.Panel{
					id = "check-type-list",
					height = "100% available",
					width = PICKER_WIDTH,
					flow = "vertical",
					vscroll = true,

					styles = ThemeEngine.MergeTokens({
						{
							selectors = {"checkTypeItem"},
							bgimage = true,
							bgcolor = "clear",
							fontSize = 16,
							minFontSize = 12,
							textAlignment = "left",
							hpad = 3,
							halign = "left",
							valign = "top",
							width = 200,
							minHeight = 22,
							height = "auto",
						},
						{
							selectors = {"checkTypeItem", "selected"},
							bgcolor = "@bgInverse",
							color = "@fgInverse",
						},
						{
							selectors = {"checkTypeItem", "hover"},
							bgcolor = "@bgInverse",
							color = "@fgInverse",
						},
					}),

					refreshDiceCheck = function(element)
						local children = {}

						local checkInfo = RollCheck.Checks[checkSelectedIndex]

						--The Test tab drives its selection from the characteristic
						--multiselect above instead of this list.
						if checkInfo.characteristics then
							element:SetClass("collapsed", true)
							element.children = {}
							SyncCheckIndexesFromCharacteristics()
							g_requireRollDialog:FireEventTree("refreshSkill")
							return
						end

						element:SetClass("collapsed", false)

						if #checkInfo.checks > 0 and (checkTypeIndex > #checkInfo.checks or checkInfo.checks[checkTypeIndex].text ~= checkTypeName) then
							checkTypeIndex = 1
							checkTypeName = checkInfo.checks[checkTypeIndex].text
							checkTypeIndexes = {checkTypeIndex}
						end

						for i,check in ipairs(checkInfo.checks) do
                            local selected = (i == checkTypeIndex)
							children[#children+1] = gui.Label{
								classes = {"checkTypeItem", cond(selected, "selected"), cond(checkInfo.group ~= nil and checkInfo.group:Get() ~= check.group, "collapsed")},
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

            --Middle column: power table selection. Takes whatever the two side columns
            --leave, which is what keeps it centered.
            gui.Panel{
                flow = 'vertical',
                width = "100% available",
                height = "100%",
                vscroll = true,
                --Gutters either side; also what keeps the middle from sprawling into
                --over-long text lines once it takes the remaining width.
                hmargin = 48,
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
                    width = "100%",
                    --200+ heroic tests live in this list; typing beats scrolling it.
                    hasSearch = true,
                    create = function(element)
                        element:SetClass("collapsed", args.powerRollTable ~= nil)
                    end,
                    options = PowerRollTableGroup.CreateDropdownOptions(),
                    idChosen = g_selectedPowerRoll:Get(),
                    change = function(element)
                        ---@cast element Dropdown
                        g_selectedPowerRoll:Set(element.idChosen)
                        element.parent:FireEventTree("update")
                        ApplyPowerTableSuggestions(element.idChosen, true)
                    end,
                },
                gui.Table{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    --The engine stripes each TableRow (oddRow/evenRow), but a gui.Input
                    --paints its own opaque @bg over it, so the outcome cells stayed one
                    --colour while the tier labels beside them alternated. Clear at rest
                    --lets the stripe run the full row. hover/focus are restated here
                    --rather than left to the theme's {input, hover} rule -- this local
                    --rule out-ranks it, and without them the cell stops reading editable.
                    styles = {
                        {
                            selectors = {"input"},
                            bgcolor = "clear",
                        },
                        {
                            selectors = {"input", "hover"},
                            bgcolor = "@bgRaised",
                        },
                        {
                            selectors = {"input", "focus"},
                            bgcolor = "@bgRaised",
                        },
                    },

                    create = function(element)

                        local children = {}

                        m_tierInputs = {}

                        --Tier labels: the three standard tiers plus an optional 4th "Critical"
                        --tier (natural 19-20). The Critical row stays collapsed unless the
                        --selected power table actually defines a 4th tier, so plain 3-tier
                        --rolls look unchanged.
                        local tierLabels = {}
                        for i=1,#GameSystem.TierNames do
                            tierLabels[i] = GameSystem.TierNames[i]
                        end
                        tierLabels[#tierLabels+1] = "Critical"

                        for i=1,#tierLabels do
                            local name = tierLabels[i]
                            local isCritical = (i > #GameSystem.TierNames)
                            local input = gui.Input{
                                --The label cell takes 30%; trim a gutter off the rest so
                                --wrapped outcome text does not run into the table's edge.
                                --Keep these as percentages -- gui.TableRow resolves neither
                                --"100% available" nor a fixed label width correctly here.
                                width = "70%-16",
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
                                update = isCritical and function(element)
                                    local powerTable = args.powerRollTable or PowerRollTableGroup.GetPowerTable(g_selectedPowerRoll:Get())
                                    element:SetClass("collapsed", powerTable == nil or powerTable.tiers[i] == nil)
                                end or nil,
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

                            if isCritical then
                                panel:FireEvent("update")
                            end

                            children[#children+1] = panel
                        end

                        element.children = children
                    end,
                }


            },

			--Right column. Same width as the left one; that symmetry is what centers
			--the middle column between them.
			gui.Panel{
				flow = "vertical",
				width = SIDE_COLUMN_WIDTH,
				height = "auto",
				valign = "top",
				halign = "right",

				gamehud:CreatePartyTokenPoolSelector{
					poolWidth = TOKEN_POOL_WIDTH,
					initiative = (args.checkType == "Initiative"),
					changeSelection = function(element, tokenids)
						tokenIdsSelected = tokenids
						g_requireRollDialog:FireEventTree('changePartySelection', tokenids)
					end
				}
			},
		},

		gui.Panel{
			flow = "horizontal",
			width = "90%",
			height = "auto",
			halign = "center",
			valign = "bottom",
			--Lift the row off the dialog's bottom edge so it isn't crowding the frame.
			bmargin = 28,

			gui.Panel{
				width = "50%",
				height = "auto",
				halign = "left",
				gui.Check{
					text = "Dice Tower (hide result from players)",
					halign = "left",
					valign = "center",
					value = false,
					fontSize = 14,
					change = function(element)
						m_dicetower = element.value
					end,
				},
			},

			gui.Panel{
				width = "25%",
				height = "auto",
				halign = "center",
				gui.Button{
					classes = {"sizeM"},
					text = "Cancel",
					halign = "right",
					valign = "center",
					escapeActivates = true,
					escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
					click = function(element)
						CloseRequireRollDialog()
					end,
				},
			},

			gui.Panel{
				width = "25%",
				height = "auto",
				halign = "right",
				gui.Button{
					classes = {"sizeM"},
					text = "Submit",
					halign = "right",
					valign = "center",
					create = function(element)
						--Clearing the characteristic multiselect leaves nothing to roll,
						--so there is nothing to submit either.
						local nothingChecked = (args.check == nil and #checkTypeIndexes == 0)
						element:SetClass("hidden", #tokenIdsSelected == 0 or nothingChecked)
					end,
					changePartySelection = function(element)
						element:FireEvent("create")
					end,
					refreshSkill = function(element)
						element:FireEvent("create")
					end,

					click = function(element)

				local ensureInitiativeShown = false

				local checks = {}

                --A chip's X does not raise `change` (see LiveSet), so re-read both widgets
                --here rather than rolling what the Director already took off.
                SyncCheckIndexesFromCharacteristics()
                local skillsChosen = table.set_to_list(LiveSet(m_skillsPanel, table.list_to_set(m_skills)))

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

                        check.options.skills = skillsChosen

                        if m_tierInputs ~= nil then
                            local tiers = {}
                            for i=1,#m_tierInputs do
                                tiers[i] = m_tierInputs[i].text
                            end

                            --Drop an empty trailing "Critical" tier so non-critical rolls stay
                            --3-tier (never send tiers[4] = "").
                            if tiers[4] ~= nil and string.match(tiers[4], "%S") == nil then
                                tiers[4] = nil
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
					dicetower = m_dicetower,
				})

				gamehud:ShowRollSummaryDialog(actionid)
			end,
				},
			},
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

	local closeButton = gui.Button{
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
		classes = {"modalTitle"},
		interactable = false,
	}

	local havePlayersOnline = false
	if #dmhub.users > 1 then
		for _,userid in ipairs(dmhub.users) do
			local session = dmhub.GetSessionInfo(userid)
			--A ghost session (a player who dropped without logging out) reports
			--loggedOut == false forever with a huge timeSinceLastContact. Counting
			--it as online meant the Director was never prompted for a player-owned
			--hero's roll while nobody was actually there, stalling the request.
			--140s is the presence threshold used elsewhere (Audio.lua, Encounter).
			if session ~= nil and session.dm == false and session.loggedOut == false and (session.timeSinceLastContact or 0) < 140 then
				havePlayersOnline = true
			end
		end
	end

    local numTokens = 0
    local numLocal = 0

	local resultsPanels = {}

	local rowIndex = 0
	for k,v in pairs(action.info.tokens) do
		local tok = dmhub.GetCharacterById(k)
		if tok ~= nil then

			rowIndex = rowIndex + 1
            numTokens = numTokens + 1
			if ((v.forceuserid == nil and tok.canControl and (dmhub.isDM == false or tok.playerControlled == false or not havePlayersOnline)) or v.forceuserid == dmhub.loginUserid) then
                numLocal = numLocal + 1
            end

            local checkInfo = action.info.checks[1]

			local outcomeLabel = gui.Label{
				classes = {"sizeL", "resultOutcomeLabel"},
				text = "",
			}

			local consequencesTable = gui.Panel{
				classes = {"resultConsequencesTable"},
			}

			local againButton = nil
			
			if dmhub.isDM then
				againButton = gui.Button{
					classes = {"sizeS"},
					text = "Re-roll",
					halign = "right",
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
				classes = {"sizeS", "hidden"},
				text = "Remove",
				halign = "right",
				margin = 16,
				click = function(element)
					action:BeginChanges()
					action.info.tokens[k] = nil
					action:CompleteChanges("Removed roll")
					panel:DestroySelf()
				end,

			}

			--Shown beside the Take Roll button once the DM takes a roll that is
			--queued behind another dialog (the listener defers while
			--CharacterPanel.AnyRollDialogShown). Gives the click a visible effect
			--even though the actual roll prompt is suppressed until the blocking
			--dialog is resolved.
			local waitingLabel = gui.Label{
				classes = {"sizeS", "hidden"},
				text = "Waiting...",
				halign = "right",
				valign = "center",
				rmargin = 100,
			}

			panel = gui.Panel{
				classes = {"resultPanel", "row", cond(rowIndex % 2 == 1, "evenRow", "oddRow")},

				gui.CreateTokenImage(tok, {
					width = 32,
					height = 32,
					halign = "left",
					valign = "center",
				}),

				gui.Label{
					classes = {"sizeL", "resultStatusLabel"},
					create = function(element)
						element:FireEvent('refreshAction')
					end,

					refreshAction = function(element)
						local actionInfo = action.info.tokens[k]
						if actionInfo ~= nil then
							removeButton:SetClass("hidden", true)
							--Hide by default; the queued-Take-Roll branch below re-shows it.
							waitingLabel:SetClass("hidden", true)
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

								--The DM took this roll (forceuserid is them) but it has
								--not been shown yet -- it is queued behind another dialog.
								--Surface that beside the button so the click reads as acted on.
								if actionInfo.forceuserid == dmhub.loginUserid then
									waitingLabel:SetClass("hidden", false)
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

				waitingLabel,
			}

			resultsPanels[#resultsPanels+1] = panel
		end
	end

    if numLocal == 1 and numTokens == 1 then
        g_requireRollDialog.parent:SetClass("hidden", true)
    end

	local resultPanelScroll = gui.Panel{
		classes = {"resultPanelScroll", "bordered"},
		halign = "center",
		pad = 8,
		vscroll = true,
		children = resultsPanels,

		styles = ThemeEngine.MergeTokens({
			{
				selectors = {"resultPanelScroll"},
				width = "94%",
				height = 340,
				valign = "center",
				flow = "vertical",
			},
			{
				selectors = {"resultPanel"},
				flow = "horizontal",
				width = "100%",
				height = 70,
				valign = "top",
			},
			{
				selectors = {"resultStatusLabel"},
				width = 80,
				textAlignment = "left",
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"resultOutcomeLabel"},
				-- fontSize = 14,
				-- color = "@fgStrong",
				width = 100,
				lmargin = 12,
				textAlignment = "left",
				height = "auto",
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"resultConsequencesTable"},
				width = 140,
				flow = "vertical",
				height = "auto",
				valign = "center",
			},
			{
				selectors = {"consequenceLabel"},
				width = 140,
				fontSize = 14,
				color = "@danger",
				height = "auto",
			},
			{
				selectors = {"consequenceLabel", "avoided"},
				color = "@fgMuted",
			},
		}),

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
