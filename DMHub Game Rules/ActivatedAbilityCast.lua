local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCast
--- @field damagedealt number
--- @field damageraw number
--- @field tier number
--- @field naturalattackroll number
--- @field attackroll number
--- @field healing number
--- @field healroll number
--- @field roll number
--- @field spacesMoved number
--- @field numberofaddedcreatures number
--- @field creaturelistsize number
--- @field heroicresourcesgained number
--- @field opportunityAttacksTriggered number
--- @field targets table
--- @field memory table|false
--- @field params table
--- @field damageTable table
--- @field tokenToTier table
--- @field inflictedConditions table
--- @field retargets table
--- @field forcedMovementPaths table
--- @field ability ActivatedAbility
--- @field auraObject false|table
ActivatedAbilityCast = RegisterGameType("ActivatedAbilityCast")

ActivatedAbilityCast.damagedealt = 0
ActivatedAbilityCast.damageraw = 0
ActivatedAbilityCast.tier = 0

ActivatedAbilityCast.naturalattackroll = 0
ActivatedAbilityCast.attackroll = 0
ActivatedAbilityCast.healing = 0
ActivatedAbilityCast.healroll = 0
ActivatedAbilityCast.roll = 0
ActivatedAbilityCast.spacesMoved = 0
ActivatedAbilityCast.numberofaddedcreatures = 0
ActivatedAbilityCast.creaturelistsize = 0
ActivatedAbilityCast.heroicresourcesgained = 0
ActivatedAbilityCast.opportunityAttacksTriggered = 0
ActivatedAbilityCast.targets = {}
ActivatedAbilityCast.auraObject = false

--a table of custom memory for this cast.
ActivatedAbilityCast.memory = false

ActivatedAbilityCast.helpSymbols = {
	__name = "spellcast",
	__sampleFields = {"damagedealt"},

    memory = {
        name = "Memory",
        type = "function",
        desc = "A function which given a name of a memory will return the value of that memory.",
        example = "memory('Damage at Start')",
    },

    firsttarget = {
        name = "First Target",
        type = "creature",
        desc = "The first target of this ability. This is only valid if there is at least one target.",
    },

    opportunityattackstriggered = {
        name = "OpportunityAttacksTriggered",
        type = "number",
        desc = "The number of opportunity attacks triggered while using this ability.",
    },

	heroicresourcesgained = {
		name = "Heroic Resources Gained",
		type = "number",
		desc = "The amount of heroic resources gained while using this ability.",
		examples = {},
	},

    numberofaddedcreatures = {
        name = "Number of Added Creatures",
        type = "number",
        desc = "The number of creatures added to creature lists while using this ability.",
        examples = {"Number of Added Creatures > 0"},
    },

    creaturelistsize = {
        name = "Creature List Size",
        type = "number",
        desc = "The number of creatures in any creature lists manipulated by this ability.",
        examples = {"Creature List Size = 3"},
    },

	damagedealt = {
		name = "Damage Dealt",
		type = "number",
		desc = "The amount of damage dealt while using this ability.",
		examples = {"Damage Dealt > 5"},
	},

	damageraw = {
		name = "Damage Raw",
		type = "number",
		desc = "The amount of raw damage (before resistance modifiers) dealt while using this ability.",
		examples = {"Damage Raw > 5"},
	},

	damagedealtagainst = {
		name = "Damage Dealt Against",
		type = "number",
		desc = "The amount of damage dealt against a specific target while using this ability.",
		examples = {"Damage Dealt Against(self) > 5"},
	},

	damagerawagainst = {
		name = "Damage Raw Against",
		type = "number",
		desc = "The amount of raw damage (before resistance modifiers) dealt against a specific target while using this ability.",
		examples = {"Damage Raw Against(self) > 5"},
	},

	naturalattackroll = {
		name = "Natural Attack Roll",
		type = "number",
		desc = "The unmodified d20 attack roll made while using this ability.",
	},

	attackroll = {
		name = "Attack Roll",
		type = "number",
		desc = "The attack roll made while using this ability.",
	},

	healing = {
		name = "Healing",
		type = "number",
		desc = "The amount of healing made while using this ability.",
	},
	healroll = {
		name = "Heal Roll",
		type = "number",
		desc = "The healing roll made while using this ability.",
	},
	ability = {
		name = "Ability",
		type = "ability",
		desc = "The ability that is being cast.",
	},
	roll = {
		name = "Roll",
		type = "number",
		desc = "The roll made while using this ability.",
	},
    hastarget = {
        name = "HasTarget",
        type = "function",
        desc = "A function which will return true if this ability has the given creature as a target.",
    },
	targetcount = {
		name = "Target Count",
		type = "number",
		desc = "The number of creatures this ability is targeting.",
	},
	spacesmoved = {
		name = "Spaces Moved",
		type = "number",
		desc = "The number of spaces moved while using this ability.",
	},
    hasprimarytarget = {
        name = "Has Primary Target",
        type = "creature",
        desc = "If this ability has at least one target.",
    },
    primarytarget = {
        name = "Primary Target",
        type = "creature",
        desc = "The primary (first) target of this ability. This is only valid if there is at least one target.",
    },
	tier = {
		name = "Tier",
		type = "number",
		desc = "The tier for the result."
	},
	tierfortarget = {
		name = "Tier for Target",
		type = "function",
		desc = "A function which given a target of the roll will return the tier of the result against this target.",
	},
    inflictedconditions = {
        name = "Inflicted Conditions",
        type = "boolean",
        desc = "True if this ability cast has inflicted conditions on creatures.",
    },
	purgedconditions = {
		name = "Purged Conditions",
		type = "number",
		desc = "The number of conditions purged by this ability cast.",
	},
}

ActivatedAbilityCast.lookupSymbols = {
	datatype = function(c)
		return "cast"
	end,

    memory = function(c)
        return function(str)
            if c.memory == false then
                return nil
            end

            return c.memory[str]
        end
    end,

    firsttarget = function(c)
        local t = c.targets[1]
        if t ~= nil and t.token ~= nil then
            return t.token.properties
        end
    end,

    opportunityattackstriggered = function(c)
        return c.opportunityAttacksTriggered
    end,

	heroicresourcesgained = function(c)
        return c.heroicresourcesgained
	end,

    numberofaddedcreatures = function(c)
        return c.numberofaddedcreatures
    end,
    creaturelistsize = function(c)
        return c.creaturelistsize
    end,

    hastarget = function(c)
        return function(target)
            if type(target) == "function" then
                target = target("self")
            end

            if type(target) == "table" then
                local tok = dmhub.LookupToken(target)
                if tok ~= nil then
                    for i,t in ipairs(c.targets) do
                        if t.token ~= nil and t.token.charid == tok.charid then
                            return true
                        end
                    end
                end
            end

            return false
        end
    end,

	ability = function(c)
		return c.ability
	end,

	damagedealt = function(c)
        print("DAMAGE:: LOOKUP", c.damagedealt, c:try_get("_tmp_guid"))
		return c.damagedealt
	end,

	damageraw = function(c)
		return c.damageraw
	end,

	damagedealtagainst = function(c)
		return function(target)
			if type(target) == "function" then
				target = target("self")
			end

			if type(target) == "table" then
				local tok = dmhub.LookupToken(target)
				if tok ~= nil then
					local entry = c.damageTable[tok.charid]
					if entry ~= nil then
						return entry.dealt
					end
				end
			end
		end

	end,

	damagerawagainst = function(c)
		return function(target)
			if type(target) == "function" then
				target = target("self")
			end

			if type(target) == "table" and target.typeName == "creature" then
				local tok = dmhub.LookupToken(target)
				if tok ~= nil then
					local entry = c.damageTable[tok.charid]
					if entry ~= nil then
						return entry.raw
					end
				end
			end

		end
	end,

	naturalattackroll = function(c)
		return c.naturalattackroll
	end,

	attackroll = function(c)
		return c.attackroll
	end,

	healing = function(c)
		return c.healing
	end,

	healroll = function(c)
		return c.healroll
	end,

	roll = function(c)
		return c.roll
	end,

    hasprimarytarget = function(c)
        return c:primarytarget() ~= nil
    end,

    primarytarget = function(c)
        local result = nil
        for i,target in ipairs(c:try_get("targets", {})) do
            if target.token ~= nil then
                result = target.token.properties
                break
            end
        end
        return result
    end,

	targetcount = function(c)
		local result = 0
		for i,target in ipairs(c:try_get("targets", {})) do
			if target.token ~= nil then
				result = result+1
			end
		end

		return result
	end,

	spacesmoved = function(c)
		return c.spacesMoved
	end,

	tier = function(c)
		return c.tier
	end,

	tierfortarget = function(c)
		return function(target)
			if type(target) == "function" then
				target = target("self")
			end

			local targetToken = dmhub.LookupToken(target)
			if targetToken == nil then
				return c.tier
			end

			return c:try_get("tokenToTier", {})[targetToken.charid] or c.tier
		end
	end,

    inflictedconditions = function(c)
        return c:try_get("inflictedConditions") ~= nil
    end,

	purgedconditions = function(c)
		return c:try_get("purgedConditions") or 0
	end,
}

--- @param tokenid string
--- @param retargetid string
--- @param retargetType 'all'|'forcemove'|'none'
--- @param retarget {casterid: string, tokenid: string, retargetid: string, retargetType: 'all'|'forcemove'|'none'}
function ActivatedAbilityCast:RecordRetarget(retarget)
    local retargets = self:get_or_add("retargets", {})
    retargets[#retargets+1] = retarget
end

function ActivatedAbilityCast:RedirectTarget(target)
    local retargets = self:try_get("retargets")
    if retargets == nil then
        return target
    end

    for i,retarget in ipairs(retargets) do
        if retarget.retargetType == "all" and target.token ~= nil and retarget.tokenid == target.token.charid then
            local newToken = dmhub.GetTokenById(retarget.retargetid)
            if newToken ~= nil then
                local entry = table.shallow_copy(target)
                entry.originalid = target.token.charid
                entry.token = newToken
                entry.loc = newToken.loc
                return entry
            end
        end
    end

    return target
end

function ActivatedAbilityCast:RedirectDamageTarget(targetToken)
    local retargets = self:try_get("retargets", {})

    for i,retarget in ipairs(retargets) do
        if retarget.retargetType == "none" and retarget.tokenid == targetToken.charid then
            local newToken = dmhub.GetTokenById(retarget.retargetid)
            local newCaster = dmhub.GetTokenById(retarget.casterid)
            if newToken ~= nil then
                return newToken
            end
        end
    end
end

function ActivatedAbilityCast:RemapForceMoveTargetAndCaster(targetToken, casterToken)
    local retargets = self:try_get("retargets")
    if retargets == nil then
        return targetToken, casterToken
    end

    for i,retarget in ipairs(retargets) do
        if retarget.retargetType == "forcemove" and retarget.tokenid == targetToken.charid then
            local newToken = dmhub.GetTokenById(retarget.retargetid)
            local newCaster = dmhub.GetTokenById(retarget.casterid)
            if newToken ~= nil then
                return newToken, (newCaster or casterToken)
            end
        end
    end

    return targetToken, casterToken
end

function ActivatedAbilityCast:RecordInflictedCondition(conditionid, charid)
    local inflictedConditions = self:get_or_add("inflictedConditions", {})
    local list = inflictedConditions[conditionid] or {}
    list[#list+1] = charid
    inflictedConditions[conditionid] = list
end

function ActivatedAbilityCast:CountDamage(targetToken, damageDealt, damageRaw)
	self.damagedealt = self.damagedealt + damageDealt
	self.damageraw = self.damageraw + damageRaw
    self._tmp_guid = dmhub.GenerateGuid()
    print("DAMAGE:: COUNT", damageDealt, "->", self.damagedealt, self._tmp_guid)

	self.damageTable = self:try_get("damageTable", {})

	self.damageTable[targetToken.charid] = self.damageTable[targetToken.charid] or { dealt = 0, raw = 0 }
	self.damageTable[targetToken.charid].dealt = self.damageTable[targetToken.charid].dealt + damageDealt
	self.damageTable[targetToken.charid].raw = self.damageTable[targetToken.charid].raw + damageRaw
end

function ActivatedAbilityCast:AddParam(args)
	local params = self:get_or_add("params", {})
	params[args.id] = params[args.id] or {}
	local list = params[args.id]
	list[#list+1] = args
end

function ActivatedAbilityCast:GetParamModifications(id)
	local params = self:try_get("params", {})
	return params[id] or {}
end

function ActivatedAbilityCast:SetTierResult(targetToken, tier)
	self.tier = tier
	self.tokenToTier = self:get_or_add("tokenToTier", {})
	self.tokenToTier[targetToken.charid] = tier
end

function ActivatedAbilityCast:RecordForcedMovementPath(path)
    local paths = self:get_or_add("forcedMovementPaths", {})
    paths[#paths+1] = path
end

function ActivatedAbilityCast:GetVacatedSpaces()
    local result = {}
    local paths = self:try_get("forcedMovementPaths", {})
    for i,path in ipairs(paths) do
        for _,step in ipairs(path.steps) do
            result[#result+1] = step
        end
    end
    return result
end

function ActivatedAbilityCast:StoreMemory(name, value)
    if self.memory == false then
        self.memory = {}
    end

    self.memory[name] = value
end