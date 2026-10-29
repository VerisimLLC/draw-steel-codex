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
--- @field new fun(o?: table): RollCheck
--- @field type string Kind of roll: "test_power_roll", "resistance_power_roll", "skill", "attribute", "initiative", "table", "custom", ...
--- @field id string The characteristic/skill/custom check id being tested.
--- @field text string Textual description of the check.
--- @field options? table Optional flags (tiers, casterid, nocover, specializations, skills, ...); see above.
--- @field tableRef? RollTableReference The table to roll on when type is "table".
--- @field dc? number Difficulty set by the Director in the request dialog.
--- @field modifiers? table[] Roll modifier entries ({modifier = CharacterModifier, hint = ...}) included with the roll.
RollCheck = RegisterGameType("RollCheck")

--A RollRequest instance has the following fields:
-- checks = a list of RollChecks that the token can choose from. Most often this will just have one option.
-- tokens = map of token id -> result table. Result table begins empty and is filled by the target. May have a checks list which is a list of indexes into checks that are available to this token.
-- contest = (optional) if true this is a contested roll between the tokens. The tokens map will have a "team" identifier to signal which side of the contest they are on.
--- @class RollRequest: GameType
--- @field new fun(o?: table): RollRequest
--- @field checks RollCheck[] The checks a token can choose from; most often just one.
--- @field tokens table<string, table> Token id -> result table, filled in by that token (outcome, result, forcedResult, checks, team, ...).
RollRequest = RegisterGameType("RollRequest")

RollCheck.consequences = ''
RollCheck.explanation = ''

RollRequest.contest = false
RollRequest.dicetower = false

--Directorless pause on the group roll board: the Monster AI sets
--awaitingContinue once every roll is in and waits; any player's Continue sets
--continued, and the AI then accepts the rolls.
RollRequest.awaitingContinue = false
RollRequest.continued = false

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
        elseif skill == nil and self.type == "test_power_roll" then
            CharacterModifier.MarkSkilledRollerDecides(result)
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
    resistance_power_roll = true,
    test_power_roll = true,
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

    --cardAbility: a roll whose `ability` option feeds modifier filters (a
    --resistance roll) passes the card to show separately.
    local cardToken = casterToken
    local cardAbility = checkOptions.cardAbility or checkOptions.ability

    --A test with no ability behind it (the Director's Request Roll dialog) is
    --shown like a characteristic clicked on the character panel: a synthetic
    --test card for the creature rolling (creature:ShowCharacteristicRollDialog).
    --A roller that is not on the map has no card, so it keeps the old dialog.
    local rollerToken = nil
    if cardAbility == nil and check.type == "test_power_roll" then
        rollerToken = dmhub.LookupToken(dialogParams.creature)
        if rollerToken == nil then
            return nil
        end
        cardToken = rollerToken
        cardAbility = ActivatedAbility.Create{ isTest = true, name = dialogParams.description }
    end

    local mount = CharacterPanel.EmbedPromptRollDialog{
        token = cardToken,
        ability = cardAbility,
        renderAsAbility = rollerToken ~= nil,
    }

    if mount == nil or mount.dialog == nil or not mount.dialog.valid
       or mount.dialog.data == nil or mount.dialog.data.ShowDialog == nil then
        return nil
    end

    --The roller as its own single target, as on the character panel: the
    --post-roll edge/bane -> tier refresh only runs for a roll with targets.
    if rollerToken ~= nil then
        dialogParams.multitargets = {
            {
                token = rollerToken,
                boons = 0,
                banes = 0,
                modifiers = dialogParams.modifiers,
                triggers = {},
            },
        }
        dialogParams.targetCreature = dialogParams.creature
    end

    --The Timeline roller shows no title of its own, so hand it the same two
    --lines the old dialog printed above the roll.
    --The title ("... for <creature>") names who is rolling, which matters when
    --one player rolls the same request for several heroes.
    local headerLines = {}
    local headline = dialogParams.title
    if headline == nil or headline == "" then
        headline = dialogParams.description
    end
    if headline ~= nil and headline ~= "" then
        headerLines[#headerLines+1] = string.format("<b>%s</b>", headline)
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
        dialogParams.multitargets = nil
        dialogParams.targetCreature = nil
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
        --A custom check moved to the Timeline exposes PrepareDialog: it fills in
        --the options its ShowDialog would, without showing the old dialog.
        if g_timelineRollTypes[check.type] and customInfo.PrepareDialog ~= nil then
            customInfo.PrepareDialog(check, dialogParams)
            local handle = ShowTimelinePrompt(check, dialogParams)
            if handle ~= nil then
                return handle
            end
        end
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

--Whether this client puts up the roll a request asks of `tok`. A plain player
--rolls for what they control; the Director or host rolls for non-player tokens
--(or for anything when no players are online); a player host also rolls for its
--OWN heroes -- ownership is the discriminator there.
--
--tok.canControl is elevation-aware: on a player host (Encounter of the Week) it
--is false for the monsters the machine hosts unless host automation is running.
--This listener runs from a plain UI refresh, so the host test reads
--IsDMOrPlayerHost() directly. Without it nobody rolled a monster's half of a
--roll a hero started (the Hide test against Search for Hidden Creatures) and the
--hero's cast waited on it until the request timed out.
--- @param tok CharacterToken|nil
--- @param info table the request's entry for this token
--- @param havePlayersOnline boolean
--- @return boolean
local function ShouldPromptForToken(tok, info, havePlayersOnline)
	if tok == nil or not tok.properties then
		return false
	end

	if info.forceuserid ~= nil then
		return info.forceuserid == dmhub.loginUserid
	end

	local hostRollsForMonster = IsDMOrPlayerHost() and tok.playerControlled == false
	if not (tok.canControl or hostRollsForMonster) then
		return false
	end

	--(playerHostMode reads nil on engine builds without it, keeping the old behavior exactly.)
	return IsDMOrPlayerHost() == false or tok.playerControlled == false or not havePlayersOnline
		or (dmhub.playerHostMode == true and tok.ownerId == dmhub.loginUserid)
end

--The creature a request names. Off the current map (a hero on a table card or
--in a scene, or a player with no map open) it is the off-board character, so
--its controller is still prompted.
--- @param tokid string
--- @return CharacterToken|nil
local function RequestedToken(tokid)
	return dmhub.GetTokenById(tokid) or dmhub.GetCharacterById(tokid)
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
	---@type string|nil
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
				--rollRequestId is always assigned before showingPrompt is.
				---@cast rollRequestId -nil
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
							local tok = RequestedToken(tokid)
							local rollid = k .. tokid
							if ShouldPromptForToken(tok, info, havePlayersOnline) and not currentRolls[rollid] then
								numPrompts = numPrompts+1
							end
						end
					end


					for tokid_tmp,info_tmp in pairs(request.info.tokens) do
						local tokid = tokid_tmp
						local info = info_tmp
						if info.status == nil then
							local tok = RequestedToken(tokid)
							local rollid = k .. tokid
							if ShouldPromptForToken(tok, info, havePlayersOnline) and not currentRolls[rollid] then
								---@cast tok -nil

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
									--A player host (no Director) has no one to hand a monster's
									--roll to, so it rolls it automatically even with the AI stopped.
									local aiRoll = false
									if IsDMOrPlayerHost() and tok.playerControlled == false then
										local monsterAI = rawget(_G, "MonsterAI")
										if (monsterAI ~= nil and monsterAI.IsAIRunning ~= nil and monsterAI.IsAIRunning()) or dmhub.playerHostMode == true then
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
								--k came from GetPlayerActionRequests() earlier in this same synchronous handler.
								request = dmhub.GetPlayerActionRequest(k) --[[@as LuaPlayerActionRequest]]
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

--- @type Panel?
local g_requireRollDialog = nil

local function CloseRequireRollDialog()
	if g_requireRollDialog ~= nil then
		g_requireRollDialog.parent:FireEvent("close")
	end
end

function GameHud:CreatePartyTokenPoolSelector(args)
	local initiative = args.initiative
	args.initiative = nil
	local offBoardHeroes = args.offBoardHeroes
	args.offBoardHeroes = nil
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

	--Heroes with a card on the table or in an open scene, though not on this
	--map. They are off-board wrappers, so compare them by charid, never with ==.
	if offBoardHeroes then
		local have = {}
		for _,tok in ipairs(candidateTokens) do
			have[tok.charid] = true
		end
		local charids = Tabletop.TableCardCharids()
		for _,target in ipairs(SceneElements.CreatureCardTargets(false, nil)) do
			charids[#charids+1] = target.charid
		end
		for _,charid in ipairs(charids) do
			if not have[charid] then
				have[charid] = true
				local tok = dmhub.GetCharacterById(charid)
				if tok ~= nil and tok.properties ~= nil and tok.playerControlled then
					candidateTokens[#candidateTokens+1] = tok
				end
			end
		end
	end

	local selectedTokens = dmhub.selectedTokens
	for _,tok in ipairs(selectedTokens) do
		local found = false
		for _,existing in ipairs(candidateTokens) do
			if existing.charid == tok.charid then
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
			if selectedTok.charid == tok.charid then
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
				--this button lives in the dialog, so the dialog is open.
				---@cast g_requireRollDialog -nil
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
									---@cast g_requireRollDialog -nil
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
							---@cast g_requireRollDialog -nil
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
						--only fired down the open dialog's tree.
						---@cast g_requireRollDialog -nil
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
					offBoardHeroes = true,
					changeSelection = function(element, tokenids)
						tokenIdsSelected = tokenids
						---@cast g_requireRollDialog -nil
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
--Group roll board -----------------------------------------------------------
--
--When an ability makes creatures roll resistance against it (Goblin Malice's
--Swamp Stink) or make a test against it, every client shows ONE shared board:
--the ability's power table, with each creature's portrait dropping onto the
--tier it rolled. It is drawn entirely from the RollRequest, which every client
--already sees under /actionRequests, so it sends nothing of its own.
--
--Rolling is unchanged: whoever controls a creature still rolls it in the
--Timeline roller (RequireRollListenerPanel above). Before, someone rolling
--several creatures saw each result vanish as the next roller opened; the board
--keeps every result in view.
--
--On the caster's client the board replaces ShowRollSummaryDialog: Proceed /
--Cancel, and right-click a portrait for Re-roll / Take Roll / Remove. A Monster
--AI caster accepts the rolls itself (AwaitAIRequestedActionCoroutine) and the
--board only shows them. With no Director (directorless play, e.g. Encounter of
--the Week) the AI waits for a player to press Continue on the board first, so
--the table can read the results before the ability resolves.

--Checks whose requests go on the board. Both carry the ability's tiers in
--check.info.tiers (ActivatedAbilityPowerRollBehavior:CastResistance).
local g_groupRollCheckIds = {
	resistance_power_roll = true,
	target_test_power_roll = true,
}

--After the last roll is in and the request closes, the board stays up this
--long so the final result can be read.
local GROUP_ROLL_LINGER_SECONDS = 4

--actionid -> resultTable for the requests this client is waiting on (it is
--the caster). Read by the board to show the caster controls.
local g_groupRollAwaiting = {}

--actionid -> true for boards this client closed or cancelled.
local g_groupRollDismissed = {}

--- @type Panel?
local g_groupRollLayer = nil

--The board's check for a request, or nil if the request does not go on the
--board. Silent abilities ask for no UI, so they stay off it.
--- @param info table|nil the request's info (a RollRequest)
--- @return RollCheck|nil
local function GroupRollCheck(info)
	if info == nil or info.typeName ~= "RollRequest" or info:try_get("silent", false) then
		return nil
	end
	local check = info.checks ~= nil and info.checks[1] or nil
	if check == nil or not g_groupRollCheckIds[check.id] then
		return nil
	end
	local checkInfo = check:try_get("info")
	if checkInfo == nil or type(checkInfo.tiers) ~= "table" or #checkInfo.tiers == 0 then
		return nil
	end
	return check
end

--The tier a finished roll landed in, read the way CastResistance reads it so
--the board shows what the ability will apply. nil until the creature has rolled.
--- @param entry table a RollRequest.tokens entry
--- @return number|nil
local function GroupRollTier(entry)
	if entry.status ~= 'complete' or entry.result == nil then
		return nil
	end
	if entry.tier ~= nil then
		return entry.tier
	end
	return RollUtils.DiceResultToTier{ total = entry.result, naturalRoll = entry.naturalRoll, boons = entry.boons, banes = entry.banes }
end

--Same presence rule as RequireRollListenerPanel: a ghost session (dropped
--without logging out) does not count as online.
local function GroupRollHavePlayersOnline()
	if #dmhub.users <= 1 then
		return false
	end
	for _,userid in ipairs(dmhub.users) do
		local session = dmhub.GetSessionInfo(userid)
		if session ~= nil and session.dm == false and session.loggedOut == false and (session.timeSinceLastContact or 0) < 140 then
			return true
		end
	end
	return false
end

--"with an edge", "with a double bane", or "" for a plain roll.
local function DescribeEdgesAndBanes(boons, banes)
	local net = (boons or 0) - (banes or 0)
	if net >= 2 then
		return " with a double edge"
	elseif net == 1 then
		return " with an edge"
	elseif net == -1 then
		return " with a bane"
	elseif net <= -2 then
		return " with a double bane"
	end
	return ""
end

--Snapshot of a request for drawing. Plain data, so the board can keep drawing
--it after the request has closed.
--- @param actionid string
--- @param request LuaPlayerActionRequest
--- @param check RollCheck
--- @return table
local function BuildGroupRollModel(actionid, request, check)
	local options = check:try_get("options", {})
	local ability = options.cardAbility or options.ability
	local title = check.explanation
	if ability ~= nil and type(ability.name) == "string" and ability.name ~= "" then
		title = ability.name
	end

	local model = {
		actionid = actionid,
		title = title,
		subtitle = check:Describe(not dmhub.isDM),
		tiers = check:try_get("info").tiers,
		entries = {},
		total = 0,
		rolled = 0,
		localCount = 0,
		allRolled = true,
		--Every roll is in and the table is waiting on a player's Continue.
		awaitingContinue = request.info.awaitingContinue == true and request.info.continued ~= true,
	}

	local havePlayersOnline = GroupRollHavePlayersOnline()

	for tokid,info in pairs(request.info.tokens) do
		local tok = RequestedToken(tokid)
		model.total = model.total + 1
		local tier = GroupRollTier(info)
		if tier == nil then
			model.allRolled = false
		else
			model.rolled = model.rolled + 1
		end
		if ShouldPromptForToken(tok, info, havePlayersOnline) then
			model.localCount = model.localCount + 1
		end

		--A creature the Director has hidden stays off the players' boards.
		if tok ~= nil and (dmhub.isDM or not tok.invisibleToPlayers) then
			local name = "A creature"
			if (dmhub.isDM or tok.canLocalPlayerSeeName) then
				name = creature.GetTokenDescription(tok)
			end
			model.entries[#model.entries+1] = {
				tokid = tokid,
				token = tok,
				name = name,
				status = info.status,
				userid = info.userid,
				forceuserid = info.forceuserid,
				tier = tier ~= nil and math.min(tier, #model.tiers) or nil,
				result = info.result,
				naturalRoll = info.naturalRoll,
				boons = info.boons,
				banes = info.banes,
			}
		end
	end

	--Stable order: by name, so portraits do not shuffle as rolls come in.
	table.sort(model.entries, function(a,b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.tokid < b.tokid
	end)

	return model
end

local function BuildGroupRollStyles()
	return {
		{
			selectors = {"groupRollBoard"},
			width = "100%",
			height = "auto",
			flow = "vertical",
			pad = 12,
			borderBox = true,
		},
		{
			selectors = {"groupRollTitle"},
			width = 400,
			height = "auto",
			fontSize = 18,
			bold = true,
			color = "@fgStrong",
			textAlignment = "left",
			halign = "left",
		},
		{
			selectors = {"groupRollSubtitle"},
			width = 400,
			height = "auto",
			fontSize = 13,
			color = "@fgMuted",
			textAlignment = "left",
			halign = "left",
			bmargin = 8,
		},
		{
			selectors = {"groupRollTiers"},
			width = "100%",
			height = "auto",
			flow = "vertical",
		},
		{
			selectors = {"groupRollTier"},
			width = "100%",
			height = "auto",
			minHeight = 48,
			flow = "horizontal",
			hpad = 6,
			vpad = 4,
			borderBox = true,
			bgcolor = "clear",
		},
		{
			--A tier someone landed in: the style guide's "current row" fill and edge.
			selectors = {"groupRollTier", "occupied"},
			bgcolor = "@bgAlt",
			borderColor = "@accent",
			--Every side must be given: a side left out draws a frame.
			border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
		},
		{
			selectors = {"groupRollTier", "flash"},
			brightness = 2,
			transitionTime = 1,
		},
		{
			selectors = {"groupRollSeam"},
			width = "100%",
			height = 1,
			bgcolor = "@border",
			opacity = 0.2,
		},
		{
			--Wide enough for the tier badge glyphs ("12-16"), as in the power
			--table's 16% column.
			selectors = {"groupRollGlyph"},
			width = 56,
			height = 30,
			rmargin = 8,
			fontFace = "DrawSteelGlyphs",
			fontSize = 30,
			color = "@fg",
			textAlignment = "left",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"groupRollGlyph", "critical"},
			fontFace = "Berling",
			fontSize = 12,
		},
		{
			selectors = {"groupRollTierText"},
			width = 222,
			height = "auto",
			fontSize = 14,
			color = "@fg",
			textAlignment = "left",
			halign = "left",
			valign = "center",
		},
		{
			--Fixed size: one line of cells (placed by x in BuildStrip), so a
			--row is as tall empty as full.
			selectors = {"groupRollIcons"},
			width = 170,
			height = 66,
			halign = "right",
			valign = "center",
		},
		{
			--vpad leaves room for pop-out portraits, which draw past their frame.
			selectors = {"groupRollIconCell"},
			width = 42,
			height = "auto",
			flow = "vertical",
			vpad = 7,
			bgcolor = "clear",
		},
		{
			--Wide enough for a status caption ("Preparing") under the portrait.
			selectors = {"groupRollIconCell", "waiting"},
			width = 64,
		},
		{
			selectors = {"groupRollIconCell", "hover"},
			brightness = 1.4,
		},
		{
			selectors = {"groupRollIconCell", "landed"},
			brightness = 2.5,
			transitionTime = 0.8,
		},
		{
			selectors = {"groupRollIconCaption"},
			width = "auto",
			height = "auto",
			fontSize = 11,
			color = "@fgMuted",
			halign = "center",
			textAlignment = "center",
		},
		{
			selectors = {"groupRollIconCaption", "total"},
			fontSize = 13,
			bold = true,
			color = "@fg",
		},
		{
			selectors = {"groupRollWaiting"},
			width = "100%",
			height = "auto",
			flow = "vertical",
			tmargin = 10,
		},
		{
			selectors = {"groupRollSectionLabel"},
			width = "auto",
			height = "auto",
			fontSize = 12,
			bold = true,
			color = "@fgMuted",
			halign = "left",
			bmargin = 2,
		},
		{
			selectors = {"groupRollWaitingIcons"},
			width = "100%",
			height = 66,
			halign = "left",
		},
		{
			selectors = {"groupRollWaitingEmpty"},
			width = "auto",
			height = "auto",
			fontSize = 13,
			color = "@fgMuted",
			halign = "left",
			valign = "center",
		},
		{
			--Fixed height, so the caster's buttons coming and going (they
			--drop when the board lingers) do not resize the board.
			selectors = {"groupRollFooter"},
			width = "100%",
			height = 30,
			flow = "horizontal",
			tmargin = 10,
		},
		{
			selectors = {"groupRollStatus"},
			width = 200,
			height = "auto",
			fontSize = 13,
			color = "@fgMuted",
			textAlignment = "left",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"groupRollButton"},
			halign = "right",
			valign = "center",
			lmargin = 6,
		},
	}
end

--The layer holding the board. Mounted once in the HUD (GameHud.lua) beside
--the ability sidebar's roll hosts, so it draws over floating windows and
--under modals, and parked on the left beside the icon rail so the sidebar
--roller on the right stays clear.
function GameHud:CreateGroupRollBoardLayer()
	--The request on the board, and the snapshot drawn for it. The snapshot
	--outlives the request while the board lingers.
	local m_actionid = nil
	local m_model = nil
	--Bumped whenever the board is shown or hidden, so a stale linger timer
	--cannot hide a board that has moved on.
	local m_serial = 0
	--tokid -> tier drawn last time, to flash newly landed portraits.
	local m_landed = {}
	--Built per request: one entry {row, icons} per tier.
	local m_tierRows = {}
	local m_tierRowsFor = nil

	local layer
	local board

	local titleLabel = gui.Label{ classes = {"groupRollTitle"}, text = "" }
	local subtitleLabel = gui.Label{ classes = {"groupRollSubtitle"}, text = "" }
	local tierTable = gui.Panel{ classes = {"groupRollTiers"} }
	local waitingEmptyLabel = gui.Label{ classes = {"groupRollWaitingEmpty"}, text = "Everyone has rolled." }
	local waitingIcons = gui.Panel{ classes = {"groupRollWaitingIcons"}, children = { waitingEmptyLabel } }
	local waitingPanel = gui.Panel{
		classes = {"groupRollWaiting"},
		children = {
			gui.Label{ classes = {"groupRollSectionLabel"}, text = "Still to roll" },
			waitingIcons,
		},
	}
	local statusLabel = gui.Label{ classes = {"groupRollStatus"}, text = "" }

	--Strip geometry. Cells are sized for their caption: a total under a
	--landed portrait, a status word ("Preparing") under a waiting one.
	local GROUP_ROLL_TIER_CELL_WIDTH = 42
	local GROUP_ROLL_TIER_STRIP_WIDTH = 170
	local GROUP_ROLL_WAITING_CELL_WIDTH = 64
	local GROUP_ROLL_WAITING_STRIP_WIDTH = 476

	local function Hide()
		m_serial = m_serial + 1
		m_actionid = nil
		m_model = nil
		m_landed = {}
		board:SetClass("collapsed", true)
	end

	--The caster's answer: accepted (Proceed) or not (Cancel). Closing the
	--request clears it from every client's board.
	local function Finish(accepted)
		local actionid = m_actionid
		local resultTable = actionid ~= nil and g_groupRollAwaiting[actionid] or nil
		if resultTable == nil then
			return
		end
		---@cast actionid string
		g_groupRollAwaiting[actionid] = nil
		resultTable.action = dmhub.GetPlayerActionRequest(actionid)
		resultTable.result = accepted and resultTable.action ~= nil
		if not accepted then
			--Our own Cancel closes our board at once; others still linger.
			g_groupRollDismissed[actionid] = true
		end
		dmhub.CancelActionRequest(actionid)
	end

	--Rewrite one creature's entry in the request (the old summary's per-row buttons).
	local function EditEntry(actionid, tokid, description, newEntry)
		local action = dmhub.GetPlayerActionRequest(actionid)
		if action == nil or action.info.tokens[tokid] == nil then
			return
		end
		action:BeginChanges()
		action.info.tokens[tokid] = newEntry
		action:CompleteChanges(description)
	end

	--Right-click menu on a portrait, for the caster only.
	local function EntryMenu(entry)
		local actionid = m_actionid
		if actionid == nil or g_groupRollAwaiting[actionid] == nil then
			return nil
		end
		local entries = {}
		if dmhub.isDM and (entry.status == nil or entry.status == 'dialog') and entry.forceuserid ~= dmhub.loginUserid then
			entries[#entries+1] = {
				text = "Take Roll",
				click = function()
					EditEntry(actionid, entry.tokid, "Request roll again", { forceuserid = dmhub.loginUserid })
				end,
			}
		end
		if dmhub.isDM and (entry.status == 'complete' or entry.status == 'cancel') then
			entries[#entries+1] = {
				text = "Re-roll",
				click = function()
					EditEntry(actionid, entry.tokid, "Request roll again", {})
				end,
			}
		end
		if entry.status == 'cancel' then
			entries[#entries+1] = {
				text = "Remove",
				click = function()
					EditEntry(actionid, entry.tokid, "Removed roll", nil)
				end,
			}
		end
		if #entries == 0 then
			return nil
		end
		return entries
	end

	local function EntryStatusText(entry)
		if entry.status == 'dialog' then
			if entry.userid ~= nil then
				return string.format("%s is preparing to roll", dmhub.GetDisplayName(entry.userid)), "Preparing"
			end
			return "Preparing to roll", "Preparing"
		elseif entry.status == 'rolling' then
			return "Rolling", "Rolling"
		elseif entry.status == 'cancel' then
			return "Declined to roll", "Declined"
		elseif entry.forceuserid == dmhub.loginUserid then
			return "Waiting for you to roll", "Waiting"
		end
		return "Waiting to roll", "Waiting"
	end

	--One portrait at x within its strip. Landed ones show the total under the
	--portrait; waiting ones show their status.
	local function CreateEntryCell(entry, x)
		local tooltip
		local caption
		local captionClasses = {"groupRollIconCaption"}
		if entry.tier ~= nil then
			tooltip = string.format("%s rolled %d", entry.name, entry.result)
			if entry.naturalRoll ~= nil then
				tooltip = string.format("%s (%d on the dice%s)", tooltip, entry.naturalRoll, DescribeEdgesAndBanes(entry.boons, entry.banes))
			end
			caption = tostring(entry.result)
			captionClasses[#captionClasses+1] = "total"
		else
			local statusText
			statusText, caption = EntryStatusText(entry)
			tooltip = string.format("%s: %s", entry.name, statusText)
		end

		local menu = EntryMenu(entry)
		if menu ~= nil then
			tooltip = tooltip .. "\nRight-click for options."
		end

		return gui.Panel{
			classes = {"groupRollIconCell", cond(entry.tier == nil, "waiting", nil)},
			bgimage = "panels/square.png",
			floating = true,
			halign = "left",
			valign = "top",
			x = x,
			hover = gui.Tooltip(tooltip),
			rightClick = function(element)
				local items = EntryMenu(entry)
				if items == nil then
					return
				end
				for _,item in ipairs(items) do
					local click = item.click
					item.click = function()
						element.popup = nil
						click()
					end
				end
				element.popup = gui.ContextMenu{ entries = items }
			end,
			children = {
				gui.CreateTokenImage(entry.token, {
					width = 34,
					height = 34,
					halign = "center",
					valign = "top",
				}),
				gui.Label{ classes = captionClasses, text = caption },
			},
		}
	end

	--A strip of portraits is always one line, so the board keeps its size as
	--rolls come in: past what fits side by side, the portraits overlap.
	local function BuildStrip(entries, cellWidth, stripWidth)
		local step = cellWidth
		if #entries > 1 and #entries * cellWidth > stripWidth then
			step = (stripWidth - cellWidth) / (#entries - 1)
		end
		local cells = {}
		for i,entry in ipairs(entries) do
			cells[i] = CreateEntryCell(entry, (i - 1) * step)
		end
		return cells
	end

	--The tier rows depend only on the request's tiers, so they are built once
	--per request; each render just refills their portraits.
	local function EnsureTierRows(model)
		if m_tierRowsFor == model.actionid then
			return
		end
		m_tierRowsFor = model.actionid
		m_tierRows = {}

		local children = {}
		local tierNames = ActivatedAbilityPowerRollBehavior.tierNames
		for i,tierText in ipairs(model.tiers) do
			if i > 1 then
				children[#children+1] = gui.Panel{ classes = {"groupRollSeam"}, bgimage = true }
			end

			local glyph
			if i > #tierNames then
				glyph = gui.Label{ classes = {"groupRollGlyph", "critical"}, text = "Critical" }
			else
				glyph = gui.Label{ classes = {"groupRollGlyph"}, text = tierNames[i] }
			end

			local icons = gui.Panel{ classes = {"groupRollIcons"} }
			local row = gui.Panel{
				classes = {"groupRollTier"},
				bgimage = "panels/square.png",
				children = {
					glyph,
					gui.Label{
						classes = {"groupRollTierText"},
						text = ActivatedAbilityPowerRollBehavior.FormatTierTextForDisplay(tierText, nil, i),
					},
					icons,
				},
			}
			children[#children+1] = row
			m_tierRows[i] = { row = row, icons = icons }
		end
		tierTable.children = children
	end

	local cancelButton = gui.Button{
		classes = {"sizeS", "groupRollButton"},
		text = "Cancel",
		click = function(element)
			Finish(false)
		end,
	}

	local proceedButton = gui.Button{
		classes = {"sizeS", "groupRollButton"},
		text = "Proceed",
		click = function(element)
			if m_model ~= nil and m_model.allRolled then
				Finish(true)
			end
		end,
	}

	--Any player's answer to the directorless pause (see RollRequest.awaitingContinue).
	local continueButton
	continueButton = gui.Button{
		classes = {"sizeS", "groupRollButton", "collapsed"},
		text = "Continue",
		click = function(element)
			local action = m_actionid ~= nil and dmhub.GetPlayerActionRequest(m_actionid) or nil
			if action == nil or action.info.continued then
				return
			end
			continueButton:SetClass("disabled", true)
			action:BeginChanges()
			action.info.continued = true
			action:CompleteChanges("Continue after rolls")
		end,
	}

	local closeButton = gui.Button{
		classes = {"closeButton"},
		floating = true,
		halign = "right",
		valign = "top",
		click = function(element)
			if m_actionid ~= nil then
				g_groupRollDismissed[m_actionid] = true
			end
			Hide()
		end,
	}

	--finished: the request has closed and this is its last snapshot.
	local function Render(model, finished)
		local newRequest = m_tierRowsFor ~= model.actionid
		EnsureTierRows(model)

		titleLabel.text = model.title
		subtitleLabel.text = model.subtitle

		local perTier = {}
		local waiting = {}
		local landedNow = {}
		for _,entry in ipairs(model.entries) do
			if entry.tier ~= nil then
				perTier[entry.tier] = perTier[entry.tier] or {}
				table.insert(perTier[entry.tier], entry)
				landedNow[entry.tokid] = entry.tier
			elseif not finished then
				waiting[#waiting+1] = entry
			end
		end

		--Portraits that just landed; flashed once they are in their rows.
		local justLanded = {}
		for i,tierRow in ipairs(m_tierRows) do
			local entries = perTier[i] or {}
			local cells = BuildStrip(entries, GROUP_ROLL_TIER_CELL_WIDTH, GROUP_ROLL_TIER_STRIP_WIDTH)
			for n,entry in ipairs(entries) do
				if (not newRequest) and m_landed[entry.tokid] ~= entry.tier then
					justLanded[#justLanded+1] = { cell = cells[n], row = tierRow.row }
				end
			end
			tierRow.icons.children = cells
			tierRow.row:SetClass("occupied", #cells > 0)
		end
		m_landed = landedNow

		for _,landed in ipairs(justLanded) do
			landed.cell:PulseClass("landed")
			landed.row:PulseClass("flash")
		end

		--The strip keeps its space when empty, so the board does not shrink
		--as the last creature rolls.
		--The label stays a child throughout; a label first parented into an
		--already laid-out panel is never laid out.
		local waitingChildren = BuildStrip(waiting, GROUP_ROLL_WAITING_CELL_WIDTH, GROUP_ROLL_WAITING_STRIP_WIDTH)
		table.insert(waitingChildren, 1, waitingEmptyLabel)
		waitingEmptyLabel:SetClass("hidden", #waiting > 0)
		waitingIcons.children = waitingChildren

		--The footer has a fixed height, so showing or dropping the buttons
		--does not resize the board.
		local isCaster = (not finished) and g_groupRollAwaiting[model.actionid] ~= nil
		cancelButton:SetClass("collapsed", not isCaster)
		proceedButton:SetClass("collapsed", not isCaster)
		proceedButton:SetClass("disabled", not model.allRolled)
		--No close while the table waits on Continue: closing would only hide
		--the one button that lets the game go on.
		local awaitingContinue = (not finished) and model.awaitingContinue
		continueButton:SetClass("collapsed", not awaitingContinue)
		continueButton:SetClass("disabled", false)
		closeButton:SetClass("collapsed", isCaster or awaitingContinue)

		statusLabel.text = string.format("%d of %d rolled", model.rolled, model.total)
		if awaitingContinue then
			statusLabel.text = "Everyone has rolled. Press Continue."
		end
	end

	--Pick the request to show: one this client is waiting on first, then the
	--one already on the board, then any other.
	local function ChooseRequest()
		local best = nil
		local bestRank = nil
		for k,request in pairs(dmhub.GetPlayerActionRequests() or {}) do
			--A board closed mid-roll comes back when the table needs its Continue.
			local dismissed = g_groupRollDismissed[k] and not (request.info.awaitingContinue == true and request.info.continued ~= true)
			if not dismissed and GroupRollCheck(request.info) ~= nil then
				local rank = 3
				if g_groupRollAwaiting[k] ~= nil then
					rank = 1
				elseif k == m_actionid then
					rank = 2
				end
				if best == nil or rank < bestRank or (rank == bestRank and k < best) then
					best = k
					bestRank = rank
				end
			end
		end
		if best == nil then
			return nil, nil
		end
		return best, dmhub.GetPlayerActionRequest(best)
	end

	local function Refresh()
		--A request we were waiting on that closed without our answer (someone
		--else cancelled it): the cast reads that as cancelled, as it did with
		--the summary dialog.
		for actionid,resultTable in pairs(g_groupRollAwaiting) do
			if dmhub.GetPlayerActionRequest(actionid) == nil then
				g_groupRollAwaiting[actionid] = nil
				if resultTable.result == nil then
					resultTable.result = false
				end
			end
		end

		local actionid, request = ChooseRequest()
		if request == nil then
			--A board paused for Continue has already been read: no linger.
			if m_actionid ~= nil and m_model ~= nil and m_model.allRolled and not m_model.awaitingContinue and not g_groupRollDismissed[m_actionid] then
				--The request closed with every roll in. Keep the final board up
				--for a moment.
				local model = m_model
				m_actionid = nil
				m_serial = m_serial + 1
				local serial = m_serial
				Render(model, true)
				dmhub.Schedule(GROUP_ROLL_LINGER_SECONDS, function()
					if mod.unloaded or serial ~= m_serial or board == nil or not board.valid then
						return
					end
					Hide()
				end)
			elseif m_actionid ~= nil then
				Hide()
			end
			return
		end
		---@cast actionid string

		local check = GroupRollCheck(request.info)
		---@cast check -nil
		local model = BuildGroupRollModel(actionid, request, check)

		if actionid ~= m_actionid then
			m_serial = m_serial + 1
		end
		m_actionid = actionid
		m_model = model
		Render(model, false)
		board:SetClass("collapsed", false)

		--One creature, rolled right here: nothing for the caster to review, so
		--answer as soon as it is rolled or declined, as the summary dialog did.
		if g_groupRollAwaiting[actionid] ~= nil and model.total == 1 and model.localCount == 1 then
			local entry = request.info.tokens[next(request.info.tokens)]
			if entry ~= nil and entry.status == 'complete' then
				Finish(true)
			elseif entry ~= nil and entry.status == 'cancel' then
				Finish(false)
			end
		end
	end

	board = gui.Panel{
		classes = {"framedPanel", "groupRollBoard", "collapsed"},
		bgimage = true,
		children = {
			titleLabel,
			subtitleLabel,
			tierTable,
			waitingPanel,
			gui.Panel{
				classes = {"groupRollFooter"},
				children = {
					statusLabel,
					cancelButton,
					proceedButton,
					continueButton,
				},
			},
			closeButton,
		},
	}

	layer = gui.Panel{
		styles = ThemeEngine.MergeStyles(BuildGroupRollStyles()),
		width = 500,
		height = "auto",
		halign = "left",
		--Anchored by its top edge: the board grows and shrinks as rolls come
		--in, and a centred board would jump each time.
		valign = "top",
		tmargin = 200,
		lmargin = 76,
		interactable = false,
		children = { board },

		monitorGame = "/actionRequests",
		refreshGame = function(element)
			Refresh()
		end,

		--A request already open when the HUD is built (a rebuild mid-roll).
		create = function(element)
			Refresh()
		end,

		destroy = function(element)
			--A HUD rebuild mid-wait: the cast reads it as cancelled, as it did
			--when the summary dialog was torn down.
			for _,resultTable in pairs(g_groupRollAwaiting) do
				if resultTable.result == nil then
					resultTable.result = false
				end
			end
			g_groupRollAwaiting = {}
			if g_groupRollLayer == element then
				g_groupRollLayer = nil
			end
		end,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if layer ~= nil and layer.valid then
			layer.styles = ThemeEngine.MergeStyles(BuildGroupRollStyles())
		end
	end)

	g_groupRollLayer = layer
	return layer
end

--Wait for a request's rolls on the group roll board when it goes there.
--Returns false (and does nothing) when it does not, so the caller shows the
--summary dialog instead.
--- @param actionid string
--- @param resultTable table
--- @return boolean
local function AwaitOnGroupRollBoard(actionid, resultTable)
	local action = dmhub.GetPlayerActionRequest(actionid)
	if action == nil or GroupRollCheck(action.info) == nil then
		return false
	end
	if g_groupRollLayer == nil or not g_groupRollLayer.valid then
		return false
	end
	g_groupRollAwaiting[actionid] = resultTable
	g_groupRollDismissed[actionid] = nil
	g_groupRollLayer:FireEvent("refreshGame")
	return true
end

function GameHud:ShowRollSummaryDialog(actionid, resultTable)
	if resultTable == nil then
		resultTable = {}
	end

	if AwaitOnGroupRollBoard(actionid, resultTable) then
		return
	end


	local iscomplete = false

	local closeButton = gui.Button{
			classes = {"sizeS"},
			text = 'Cancel',
			halign = 'right',
			valign = 'bottom',
			margin = 12,
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
		classes = {"sizeL"},
		bold = true,
		width = "100%",
		height = "auto",
		textAlignment = "center",
		tmargin = 14,
		bmargin = 6,
		hpad = 16,
		borderBox = true,
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
				classes = {"sizeM", "resultOutcomeLabel"},
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
					valign = "center",
					hmargin = 6,
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
				valign = "center",
				hmargin = 6,
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
				width = "auto",
				height = "auto",
				halign = "left",
				valign = "center",
				lmargin = 8,
			}

			panel = gui.Panel{
				classes = {"resultPanel", "row", cond(rowIndex % 2 == 1, "evenRow", "oddRow")},

				gui.CreateTokenImage(tok, {
					width = 32,
					height = 32,
					halign = "left",
					valign = "center",
					rmargin = 8,
				}),

				--Status and result on the first line, what it did to the creature below.
				gui.Panel{
					classes = {"resultInfoColumn"},

				gui.Panel{
					classes = {"resultStatusRow"},

				gui.Label{
					classes = {"sizeM", "resultStatusLabel"},
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
									--damageEntry is set in the same loop step that sets damageCalc.
									---@cast damageEntry -nil
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
									--damageEntry is set in the same loop step that sets damageCalc.
									---@cast damageEntry -nil
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

				waitingLabel,
				},

				consequencesTable,
				},

				againButton,

				removeButton,
			}

			resultsPanels[#resultsPanels+1] = panel
		end
	end

    --GetOrLaunchPanel("Request Rolls") above created the dialog.
    ---@cast g_requireRollDialog -nil
    if numLocal == 1 and numTokens == 1 then
        g_requireRollDialog.parent:SetClass("hidden", true)
    end

    --The summary is a status panel, not the Director's full Request Rolls
    --window: keep it narrow and park it on the left, beside the icon rail, so
    --the map and the roll sidebar on the right stay visible.
    g_requireRollDialog.selfStyle.width = 440
    g_requireRollDialog.selfStyle.height = "auto"
    local window = g_requireRollDialog.parent
    if window ~= nil then
        window.selfStyle.halign = "left"
        window.selfStyle.valign = "center"
        window.selfStyle.lmargin = 76
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
				height = "auto",
				maxHeight = 360,
				valign = "top",
				flow = "vertical",
			},
			{
				selectors = {"resultPanel"},
				flow = "horizontal",
				width = "100%",
				height = "auto",
				vpad = 6,
				hpad = 4,
				borderBox = true,
				valign = "top",
			},
			{
				selectors = {"resultInfoColumn"},
				flow = "vertical",
				width = "100% available",
				height = "auto",
				valign = "center",
			},
			{
				selectors = {"resultStatusRow"},
				flow = "horizontal",
				width = "100%",
				height = "auto",
			},
			{
				selectors = {"resultStatusLabel"},
				width = "auto",
				height = "auto",
				textAlignment = "left",
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"resultOutcomeLabel"},
				width = "auto",
				lmargin = 8,
				textAlignment = "left",
				height = "auto",
				halign = "left",
				valign = "center",
			},
			{
				selectors = {"resultConsequencesTable"},
				width = "100%",
				flow = "vertical",
				height = "auto",
				halign = "left",
			},
			{
				selectors = {"consequenceLabel"},
				width = "100%",
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
		width = "100%",
		height = "auto",
		fontSize = 14,
		halign = "center",
		hpad = 16,
		tmargin = 6,
		borderBox = true,
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

--Rolls a Monster AI cast requests ---------------------------------------
--
--When the Monster AI casts an ability that makes heroes roll (Swamp Stink's
--Might resistance roll for every hero), its host never opens the Director's
--summary dialog above. The AI accepts the rolls itself once every target has
--rolled, and meanwhile tells the whole table why it has paused through its
--waiting notice (MonsterAI.SetWaiting). Like the AI's other player waits this
--has no timer. A declined roll is asked for again. If the AI is stopped while
--it waits, the request goes to the summary dialog so a person can finish it.
--In directorless play it also waits, once every roll is in, for a player to
--press Continue on the group roll board.

--A declined roll is asked for again at most this often. A player who chose
--"roll all" and then cancelled has every later prompt of the request
--auto-cancelled, so without this the re-ask would churn every poll.
local AI_REASK_SECONDS = 2

--The waiting notice names at most this many heroes who still have to roll.
local AI_NOTICE_MAX_NAMES = 3

--True while the Monster AI process is running on this client. rawget: the
--Monster AI module may not be loaded.
local function MonsterAIRunning()
	local monsterAI = rawget(_G, "MonsterAI")
	return monsterAI ~= nil and monsterAI.active == true
		and monsterAI.IsAIRunning ~= nil and monsterAI.IsAIRunning()
end

--True when the Monster AI is driving this caster's actions right now: it holds
--the caster (MonsterAI:BeginTokenControl), or it has an activity open on this
--client (MonsterAI:ExecuteAbility holds one for the whole cast) and the caster
--is not a player's. The activity check was added while the AI's control could
--be wiped mid-cast (fixed: the control now lives in Creature.lua, off the
--token's properties); it stays as a safety net for a cast the AI drives
--without holding the caster.
--- @param casterToken CharacterToken?
--- @return boolean
function RollRequestIsForAICaster(casterToken)
	if casterToken == nil or casterToken.properties == nil or not MonsterAIRunning() then
		return false
	end
	if creature.IsTokenAIControlled(casterToken.charid) then
		return true
	end
	return creature.GetAIActivityInProgress() ~= nil and not casterToken.playerControlled
end

--"Waiting for resistance rolls to be processed before proceeding (Shadow,
--Rook)". Only heroes are named: monster rolls are rolled automatically on the
--host, and naming a monster could reveal a name the players cannot see.
local function AIRollWaitNotice(action, outstandingHeroes)
	local check = action.info.checks[1]
	local rollType = check ~= nil and check.type or nil
	local noun = "rolls"
	if rollType == "resistance_power_roll" then
		noun = "resistance rolls"
	elseif rollType == "test_power_roll" then
		noun = "tests"
	end

	local text = string.format("Waiting for %s to be processed before proceeding", noun)
	if #outstandingHeroes > 0 then
		table.sort(outstandingHeroes)
		local names = {}
		for i,name in ipairs(outstandingHeroes) do
			if i <= AI_NOTICE_MAX_NAMES then
				names[#names+1] = name
			end
		end
		local list = table.concat(names, ", ")
		if #outstandingHeroes > AI_NOTICE_MAX_NAMES then
			list = string.format("%s and %d more", list, #outstandingHeroes - AI_NOTICE_MAX_NAMES)
		end
		text = string.format("%s (%s)", text, list)
	end
	return text
end

--The Monster AI's version of ShowRollSummaryDialog / AwaitRequestedActionCoroutine.
--Run from the cast's coroutine. Sets resultTable.result true and
--resultTable.action once every target has rolled; false if the request
--disappears. Returns resultTable, whose result is still nil if the wait was
--handed to the summary dialog (the caller keeps waiting on it as usual).
--- @param actionid string
--- @param resultTable table?
--- @return table
function AwaitAIRequestedActionCoroutine(actionid, resultTable)
	resultTable = resultTable or {}
	local monsterAI = rawget(_G, "MonsterAI")
	local noticeSet = false
	local handOver = false
	local reaskedAt = {}
	--True once this wait has paused the board for Continue (directorless play).
	local awaitingContinueSet = false

	print("AWAIT:: AI accepting rolls for request", actionid)

	local ok, err = pcall(function()
		while true do
			if mod.unloaded then
				if dmhub.GetPlayerActionRequest(actionid) ~= nil then
					dmhub.CancelActionRequest(actionid)
				end
				resultTable.result = false
				return
			end

			local action = dmhub.GetPlayerActionRequest(actionid)
			if action == nil then
				resultTable.result = false
				return
			end

			if not MonsterAIRunning() then
				handOver = true
				return
			end

			local now = dmhub.Time()
			local outstanding = 0
			local outstandingHeroes = {}
			local reask = {}
			local remove = {}
			for k,info in pairs(action.info.tokens) do
				local tok = dmhub.GetTokenById(k)
				if tok == nil or not tok.valid then
					--Nobody can roll for a creature that has left the map; drop it
					--so the cast skips it, as the dialog's Remove button would.
					remove[#remove+1] = k
				elseif info.status ~= 'complete' then
					outstanding = outstanding + 1
					if tok.playerControlled then
						outstandingHeroes[#outstandingHeroes+1] = tok.name or "a hero"
					end
					if info.status == 'cancel' and now - (reaskedAt[k] or -math.huge) >= AI_REASK_SECONDS then
						reaskedAt[k] = now
						reask[#reask+1] = k
					end
				end
			end

			if #reask > 0 or #remove > 0 then
				action:BeginChanges()
				for _,k in ipairs(remove) do
					action.info.tokens[k] = nil
				end
				for _,k in ipairs(reask) do
					--Back to "not yet prompted", which makes the rolling client
					--prompt again. team/checks/forceuserid are kept.
					local entry = action.info.tokens[k]
					entry.status = nil
					entry.userid = nil
				end
				action:CompleteChanges("Monster AI: ask for declined rolls again")
			end

			--With no Director, hold the finished board until a player presses
			--Continue on it, so the table can see what was rolled.
			local holdForContinue = false
			if outstanding == 0 and #remove == 0 and dmhub.directorlessPlay
					and GroupRollCheck(action.info) ~= nil and action.info.continued ~= true then
				holdForContinue = true
				if action.info.awaitingContinue ~= true then
					action:BeginChanges()
					action.info.awaitingContinue = true
					action:CompleteChanges("Monster AI: wait for Continue")
					awaitingContinueSet = true
				end
			end

			if outstanding == 0 and #remove == 0 and not holdForContinue then
				resultTable.result = true
				resultTable.action = action
				dmhub.CancelActionRequest(actionid)
				return
			end

			if monsterAI ~= nil then
				if holdForContinue then
					monsterAI.SetWaiting("rolls", "Waiting for a player to press Continue on the rolls")
				else
					monsterAI.SetWaiting("rolls", AIRollWaitNotice(action, outstandingHeroes))
				end
				noticeSet = true
			end

			coroutine.yield(0.2)
		end
	end)

	if noticeSet and monsterAI ~= nil then
		pcall(monsterAI.ClearWaiting)
	end

	if not ok then
		print("AWAIT:: AI roll wait failed, handing the request to the summary dialog:", tostring(err))
		handOver = true
	end

	if handOver and resultTable.result == nil then
		--Nobody listens for Continue now; the summary's Proceed takes over.
		local action = dmhub.GetPlayerActionRequest(actionid)
		if awaitingContinueSet and action ~= nil and action.info.awaitingContinue then
			action:BeginChanges()
			action.info.awaitingContinue = false
			action:CompleteChanges("Monster AI stopped")
		end
		print("AWAIT:: Monster AI no longer running; showing the summary dialog for request", actionid)
		gamehud:ShowRollSummaryDialog(actionid, resultTable)
	end

	return resultTable
end

--Wait for the rolls a cast requested of its targets: the Monster AI accepts
--them itself when it is the caster (see above), a silent ability waits
--without a dialog, otherwise the Director gets the summary dialog. Sets
--resultTable.result (true = rolls accepted) and resultTable.action; the
--caller waits until result is set. Run from the cast's coroutine.
--- @param casterToken CharacterToken?
--- @param actionid string
--- @param resultTable table
--- @param silent boolean?
function AwaitCastRollRequest(casterToken, actionid, resultTable, silent)
	if RollRequestIsForAICaster(casterToken) then
		AwaitAIRequestedActionCoroutine(actionid, resultTable)
	elseif silent then
		AwaitRequestedActionCoroutine(actionid, resultTable)
	else
		gamehud:ShowRollSummaryDialog(actionid, resultTable)
	end
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
