local mod = dmhub.GetModLoading()

--- @class CharacterOngoingEffect
CharacterOngoingEffect = RegisterGameType("CharacterOngoingEffect", "CharacterFeature")
CharacterOngoingEffect.tableName = "characterOngoingEffects"
CharacterOngoingEffect.stackable = false
CharacterOngoingEffect.clearStacksWhenApplying = false
CharacterOngoingEffect.transformation = false
CharacterOngoingEffect.canEndWithAction = false
CharacterOngoingEffect.endActionType = "none"
CharacterOngoingEffect.endEffectRequiresSavingThrow = false 
CharacterOngoingEffect.endingEffectSavingThrow = "none"
CharacterOngoingEffect.endingEffectSavingThrowDC = 10
CharacterOngoingEffect.sustainFormula = '' --a formula used to see if this effect keeps going.
CharacterOngoingEffect.emoji = 'none'
CharacterOngoingEffect.condition = 'none' --the underlying condition for this effect.
CharacterOngoingEffect.statusEffect = true --is this a standard status condition?
CharacterOngoingEffect.hiddenOnToken = false
CharacterOngoingEffect.hiddenFromEnemies = false --is this hidden from enemies?
CharacterOngoingEffect.durationUntilEndOfTurn = false
CharacterOngoingEffect.effectsByName = {}
CharacterOngoingEffect.endTrigger = "none"
CharacterOngoingEffect.countsTowardInstanceLimit = true
CharacterOngoingEffect.casterTracking = "none"

CharacterOngoingEffect.allowEditingDisplayInfo = true

CharacterOngoingEffect.CasterTrackingOptions = {
    {
        id = 'none',
        text = 'None',
    },
    {
        id = 'one',
        text = 'One Caster',
    },
    {
        id = 'set',
        text = 'Set of Casters',
    },
    {
        id = 'bond',
        text = 'Bonded Set',
    },
}

CharacterOngoingEffect.durationOptions = {
	{
		id = 'turn',
		text = 'Until End of Turn',
	},
	{
		id = 'endround',
		text = 'Until End of Round',
	},
    {
        id = 'endnextround',
        text = 'Until End of Next Round',
    },
	{
		id = 'rounds',
		text = 'Rounds (From Start of Turn)',
	},
	{
		id = 'rounds_end_turn',
		text = 'Rounds (From End of Turn)',
	},
	{
		id = 'until_rest',
		text = 'Until Respite',
	},
	{
		id = 'indefinite',
		text = 'Indefinitely',
	},
	{
		id = 'save_ends',
		text = 'Save Ends',
	},
	{
		id = 'eoe',
		text = 'End of Encounter',
	},
	{
		id = 'eoe_or_dying',
		text = 'End of Encounter or Dying',
	},
}


function CharacterOngoingEffect.Create(options)
	local args = {
		id = dmhub.GenerateGuid(),
		iconid = "ui-icons/skills/1.png",
		name = 'New Ongoing Effect',
		source = 'Ongoing Effect',
		description = '',
		modifiers = {},
		display = {
			bgcolor = '#ffffffff',
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		}
	}

	--we need guid to be valid since CharacterFeatures are expected to come with them. While objects in tables have ids.
	args.guid = args.id

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return CharacterOngoingEffect.new(args)
end

function CharacterOngoingEffect:FillEditingFields(result)
end

function CharacterOngoingEffect:GetCondition()
	if self.condition == "none" then
		return nil
	end

	local dataTable = dmhub.GetTable(CharacterCondition.tableName)
	return dataTable[self.condition]
end

function CharacterOngoingEffect:GetEndAbility()
	if self.canEndWithAction then
		local resourceid = self.endActionType
		local moveCost = nil
		if resourceid == "halfmove" then
			moveCost = 0.5
			resourceid = nil
		elseif resourceid == "fullmove" then
			moveCost = 1
			resourceid = nil
		end

		local behaviors = {}
		
		if self.endEffectRequiresSavingThrow then 
			behaviors[#behaviors+1] = ActivatedAbilitySavingThrowBehavior.new{
				dc = self.endingEffectSavingThrowDC,
				ability = self.endingEffectSavingThrow,
			}
		end

		behaviors[#behaviors+1] = ActivatedAbilityRemoveOngoingEffectBehavior.new{
			ongoingEffectid = self.id,
		}

		return ActivatedAbility.Create{
			guid = string.format("end-ongoingEffect-%s", self.id),
			name = string.format("End %s", self.name),
			iconid = self.iconid,
			display = self.display,
			actionResourceId = resourceid,
			moveCost = moveCost,
			behaviors = behaviors,
		}
	end

	return nil
end

--a point in time in the game.
--- @class TimePoint
TimePoint = RegisterGameType("TimePoint")

function TimePoint.Create()
	local initiativeQueue = dmhub.initiativeQueue
	if initiativeQueue ~= nil and (not initiativeQueue.hidden) then
		local initiativeEntry = initiativeQueue:GetFirstInitiativeEntry()
		local initiativeid = nil
		local initiativeord = 0
		if initiativeEntry ~= nil then
			initiativeid = initiativeEntry.initiativeid
			initiativeord = initiativeEntry.initiative + initiativeEntry.dexterity*0.01
		end
		return TimePoint.new{
			time = CalculateGameDateAndTime(),
			queueguid = initiativeQueue.guid,
			round = initiativeQueue.round,
			initiativeid = initiativeid,
			initiativeord = initiativeord,
		}
	else
		return TimePoint.new{
			time = CalculateGameDateAndTime(),
		}
	end
end

local roundsPerDay = 24*60*10

--this function returns an integer or halfway between integers.
--0 = this is the same turn this was created
--0.5 = less than one full round has passed since this was created.
--1 = this is the same turn as this was created, but next round.
-- etc.
function TimePoint:RoundsSince()
	local initiativeQueue = dmhub.initiativeQueue
	if initiativeQueue == nil or initiativeQueue.hidden or self:try_get('queueguid') == nil then
		local t = CalculateGameDateAndTime()
		local timeElapsed = t - self.time
		local roundsElapsed = timeElapsed*roundsPerDay

		if self:try_get("queueguid") ~= nil then
			--this is from a previous combat and we're no longer in combat.
			roundsElapsed = math.max(roundsElapsed, 20)
		end

		return math.floor(roundsElapsed)
	end

	if self.queueguid ~= initiativeQueue.guid then
		--new combat, assume at least a reasonable amount of time, 10 rounds, has passed.
		local t = CalculateGameDateAndTime()
		local timeElapsed = t - self.time
		local roundsElapsed = timeElapsed*roundsPerDay
		return math.max(10, math.floor(roundsElapsed))
	end

	local roundsPassed = initiativeQueue.round - self.round
	local initiativeEntry = initiativeQueue:GetFirstInitiativeEntry()
	local currentlyOurTurn = initiativeEntry ~= nil and initiativeEntry.initiativeid == self:try_get("initiativeid")

	local turnPassed = false
	local turnPending = false

	if self:try_get("initiativeid") ~= nil then
		local hasHadTurn = initiativeQueue:HasHadTurn(self.initiativeid)
		turnPassed = hasHadTurn
		turnPending = (not hasHadTurn) and (not currentlyOurTurn)

	elseif initiativeEntry ~= nil then
		local ord = initiativeEntry.initiative + initiativeEntry.dexterity*0.01
		turnPassed = ord < self.initiativeord
		turnPending = ord > self.initiativeord
	end

	if turnPending then
		roundsPassed = roundsPassed - 0.5
	elseif turnPassed then
		roundsPassed = roundsPassed + 0.5
	end

	return roundsPassed
end

--- @class CharacterOngoingEffectInstance
--- @field ongoingEffectid string
--- @field duration nil|number time in rounds
--- @field time TimePoint time when effect was added.
--- @field endAbility nil|ActivatedAbility which ends the action
--- @field countdowns nil|table<string,number> a map of string -> count which is a trigger id -> number of triggers left. Used to keep track of triggers
---                        which will expire this effect when they hit their limit. If any are 0 then this effect expires.
--- @field casterInfo nil|{tokenid: string, concentrationid: nil|string}
--- @field momentaryDuration boolean
--- @field removeOnLongRest boolean
--- @field removeOnShortRest boolean
--- @field removeAtNextTurnEnd boolean
--- @field removeAtRoundEnd boolean|number
--- @field removeOnSave boolean
--- @field removeOnEoEOrDying boolean
--- @field removeOnEoE boolean
--- @field timestamp string|number
--- @field bondid string|false if this effect tracks casters by bond, this is the bond id.
RegisterGameType("CharacterOngoingEffectInstance")

CharacterOngoingEffectInstance.timestamp = 0
CharacterOngoingEffectInstance.momentaryDuration = false
CharacterOngoingEffectInstance.removeOnLongRest = false
CharacterOngoingEffectInstance.removeOnShortRest = false
CharacterOngoingEffectInstance.removeAtNextTurnEnd = false
CharacterOngoingEffectInstance.removeAtRoundEnd = false
CharacterOngoingEffectInstance.removeOnSave = false
CharacterOngoingEffectInstance.removeOnEoE = false
CharacterOngoingEffectInstance.removeOnEoEOrDying = false
CharacterOngoingEffectInstance.bondid = false

--all new ongoing effect instances should have ID's.
CharacterOngoingEffectInstance.id = "deprecated"
CharacterOngoingEffectInstance.stacks = 1

--all new ongoing effect instances should have a seq to keep track of the order they were added.
CharacterOngoingEffectInstance.seq = 1

function CharacterOngoingEffectInstance.Create(options)
	options = DeepCopy(options or {})

	options.id = dmhub.GenerateGuid()
	options.time = TimePoint.Create()

	if options.duration == "until_rest" then
		options.duration = nil
		options.removeOnShortRest = true
		options.removeOnLongRest = true
	elseif options.duration == "until_long_rest" then
		options.duration = nil
		options.removeOnLongRest = true
	elseif options.duration == "end_of_next_turn" then
		options.duration = nil
		options.removeAtNextTurnEnd = true
    elseif options.duration == "endround" then
		options.duration = nil
		options.removeAtRoundEnd = true
    elseif options.duration == "endnextround" then
		options.duration = nil
		options.removeAtRoundEnd = 2
	elseif options.duration == "save_ends" then
		options.duration = nil
		options.removeOnSave = true
	elseif options.duration == "eoe_or_dying" then
		options.duration = nil
		options.removeOnEoEOrDying = true
	elseif options.duration == "eoe" then
		options.duration = nil
		options.removeOnEoE = true
	end

	print("OngoingEffect::", options)
	return CharacterOngoingEffectInstance.new(options)
end

function CharacterOngoingEffectInstance:CountdownResource(effectid, maxcount)
	local t = self:get_or_add("countdowns", {})
	local count = t[effectid]
	if count == nil then
		count = maxcount
	end

	if count > 0 then
		count = count-1
	end

	t[effectid] = count
end

function CharacterOngoingEffectInstance:Refresh(duration)
    self.timestamp = ServerTimestamp()

	if duration == nil or self:try_get("duration") == nil then
		--at least one of them is indefinite duration so don't do anything.
		return
	end

    if type(duration) == "string" then
        --override the existing duration with this codified duration string.
        self.id = dmhub.GenerateGuid()
        self.time = TimePoint.Create()

        if duration == "until_rest" then
            self.duration = nil
            self.removeOnShortRest = true
            self.removeOnLongRest = true
        elseif duration == "until_long_rest" then
            self.duration = nil
            self.removeOnLongRest = true
        elseif duration == "end_of_next_turn" then
            self.duration = nil
            self.removeAtNextTurnEnd = true
        elseif duration == "endround" then
            self.duration = nil
            self.removeAtRoundEnd = true
        elseif duration == "endnextround" then
            self.duration = nil
            self.removeAtRoundEnd = 2
		elseif duration == "save_ends" then		
			self.duration = nil
			self.removeOnSave = true
        elseif duration == "eoe_or_dying" then
            self.duration = nil
            self.removeOnEoEOrDying = true
        elseif duration == "eoe" then
            self.duration = nil
            self.removeOnEoE = true
        end

        return
    end

	local roundsSince = self.time:RoundsSince()
	local remaining = self.duration - roundsSince

	if duration >= remaining then
		self.time = TimePoint.Create()
		self.duration = duration
	end
end

function CharacterOngoingEffectInstance:Expired()
	if self:has_key("countdowns") then
		for _,v in pairs(self.countdowns) do
			if v == 0 then
				return true
			end
		end
	end

	if self:has_key('casterInfo') and self.casterInfo.concentrationid then
		local casterToken = game.GetCharacterById(self.casterInfo.tokenid)
		if casterToken == nil or casterToken.properties == nil then
			--caster doesn't even exist anymore, so expired.
			return true
		end

		local found = false
		for _,concentration in ipairs(casterToken.properties:try_get("concentrationList", {})) do
			if concentration.id == self.casterInfo.concentrationid then
				found = true
				if concentration:HasExpired() then
					return true
				end
			end
		end

		if not found then
			return true
		end
	end

	if self:has_key('duration') then
		return self.time:RoundsSince() > self.duration
	end

	return false
end

function CharacterOngoingEffectInstance:DescribeCaster()
	local casterInfo = self:try_get("casterInfo")
	if casterInfo == nil then
		return nil
	end

	local c = dmhub.GetCharacterById(casterInfo.tokenid)
	if c ~= nil then
		local result = creature.GetTokenDescription(c)
		if casterInfo.abilityName ~= nil then
			result = string.format("%s using %s", result, casterInfo.abilityName)
		end
		if casterInfo.concentrationid then
			result = string.format("%s (concentrating)", result)
		end

		return result
	end

	return nil
end

function CharacterOngoingEffectInstance:DescribeTimeRemaining()
	if self.removeAtNextTurnEnd then
		return "EoT"
	end
    if self.removeAtRoundEnd then
        if self.removeAtRoundEnd == 2 then
            return "until end of next round"
        end
        return "until end of the round"
    end
	if not self:has_key("duration") then
		if self.removeOnShortRest then
			return "until respite"
		elseif self.removeOnLongRest then
			return "until respite"
		elseif self.removeOnSave then
			return "save ends"
		elseif self.removeOnEoEOrDying then
			return "until eoe/dying"
		elseif self.removeOnEoE then
			return "until eoe"
		end

		return "indefinite"
	end

	local roundsSince = self.time:RoundsSince()
	if roundsSince == self.duration then
		return 'this turn'
	end

	if self.duration - roundsSince <= 1 then
		return 'one round'
	else
		return string.format('%d rounds', math.floor(self.duration - roundsSince))
	end
end

function creature:HasBondForOngoingEffect(effectid, bondid)
	local ongoingEffects = self:try_get('ongoingEffects')
    if ongoingEffects == nil then
        return false
    end

    for _,effect in ipairs(ongoingEffects) do
        if effect.ongoingEffectid == effectid and effect.bondid == bondid then
            return true
        end
    end

    return false
end

---@type table<string, table<string,boolean>> a map of bondid -> map of tokenid -> true
local g_boundEffects = {}
local g_boundEffectsCount = 0

function creature:RefreshBoundOngoingEffects(token)
    g_boundEffectsCount = g_boundEffectsCount + 1
    local found = false
	for i,cond in ipairs(token.properties:ActiveOngoingEffects()) do
        if cond.bondid then
            g_boundEffects[cond.bondid] = g_boundEffects[cond.bondid] or {}
            g_boundEffects[cond.bondid][token.charid] = true

            self:get_or_add("_tmp_boundEffects", {})[cond.bondid] = g_boundEffectsCount
            found = true
        end
    end

    if found then
        for k,v in pairs(self._tmp_boundEffects or {}) do
            if v ~= g_boundEffectsCount then
                --this bondid was not found this time, so remove it.
                if g_boundEffects[k] then
                    g_boundEffects[k][token.charid] = nil
                end

                self._tmp_boundEffects[k] = nil
            end
        end
    else
        self._tmp_boundEffects = nil
    end
end

function creature.GetTokensWithBoundOngoingEffect(bondid)
    local result = {}
    for tokenid, _ in pairs(g_boundEffects[bondid] or {}) do
        local token = dmhub.GetTokenById(tokenid)
        if token and token.valid and token.properties:try_get("_tmp_boundEffects", {})[bondid] then
            result[#result + 1] = token
        end
    end

    return result
end

---@return nil|CharacterToken[] a list of tokens which share recoveries with this creature.
function creature:ShareRecoveriesWith()
	for i,cond in ipairs(self:ActiveOngoingEffects()) do
        if cond.bondid then
            local dataTable = dmhub.GetTable("characterOngoingEffects")
            local ongoingEffect = dataTable[cond.ongoingEffectid]
            if ongoingEffect ~= nil and ongoingEffect:try_get("recoverySharing", false) then
                local result = creature.GetTokensWithBoundOngoingEffect(cond.bondid)
                if result ~= nil and #result > 1 then
                    return result
                end
            end
        end
    end

    return nil
end

CharacterOngoingEffectInstance.lookupSymbols = {
	self = function(c)
		return c
	end,

	debuginfo = function(c)
		return string.format("Ongoing Effect")
	end,

	datatype = function(c)
		return "ongoing effect"
	end,

	caster = function(c)
		local casterInfo = c:try_get("casterInfo")
		if casterInfo == nil then
			return nil
		end

		local c = dmhub.GetCharacterById(casterInfo.tokenid)
		if c == nil then
			return nil
		end

		return c.properties
	end,

}

CharacterOngoingEffectInstance.helpSymbols = {
	__name = "ongoing effect",
	__sampleFields = {"caster"},
	caster = {
		name = "Caster",
		type = "creature",
		desc = "The creature that cast this ongoing effect.",
	},
}

dmhub.RegisterEventHandler("refreshTables", function()
	local dataTable = dmhub.GetTable("characterOngoingEffects")
	for k,v in pairs(dataTable) do
		CharacterOngoingEffect.effectsByName[v.name] = v
	end
end)