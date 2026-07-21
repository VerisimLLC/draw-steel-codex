local mod = dmhub.GetModLoading()

--This file implements the "Modify Abilities" modifier that allows a modifier to affect
--abilities that a creature has.

CharacterModifier.RegisterType('modifyability', "Modify Abilities")

--------------------------------------------------------------------
--modify ability modifiers can modify the abilities a creature has.
--------------------------------------------------------------------

local abilityModifierOptionsById = {}
local abilityModifierOptions = {}

function CharacterModifier.RegisterAbilityModifier(options)
	abilityModifierOptionsById[options.id] = options

	if options.index == nil then
		options.index = #abilityModifierOptions+1
	end

	abilityModifierOptions[options.index] = options
end

CharacterModifier.RegisterAbilityModifier
	{
		id = "none",
		text = "Add Attribute...",
	}

--[[ CharacterModifier.RegisterAbilityModifier
	{
		id = "numactions",
		text = "Number of Actions",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if operation == "Set" then
				ability.actionNumber = value
				return true
			end

			if type(ability.actionNumber) ~= "number" and type(ability.actionNumber) ~= "string" then
				--Not implemented to modify tables!
				return true
			end

			if operation == "Multiply" then
				ability.actionNumber = string.format("(%s) * (%s)", tostring(ability.actionNumber), value)
			else
				ability.actionNumber = string.format("(%s) + (%s)", tostring(ability.actionNumber), value)
			end
		end,
	} ]]

CharacterModifier.RegisterAbilityModifier
	{
		id = "cost",
		text = "Heroic Resource Cost",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if not ability:has_key("resourceCost") then
				if creature:IsHero() then
					ability.resourceCost = "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca" --Heroic Resource
				else
					ability.resourceCost = "101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8" --Malice Resource
				end
				--When we add a resourceCost, a value of 1 is implied.
				value = string.format("(%s) - 1", value)
			end

			if operation == "Set" then
				ability.resourceNumber = value
			elseif operation == "Multiply" then
				ability.resourceNumber = string.format("(%s) * (%s)", ability.resourceNumber, value)
			else
				ability.resourceNumber = string.format("(%s) + (%s)", ability.resourceNumber, value)
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
{
	id = "modkeywords",
	text = "Modify Keywords",
	operations = { "Add", "Set", "Remove" },
	set = function(modifier, creature, ability, attr)
		if attr.operation == "Set" then
			ability.keywords = attr.keywords
			return true
		elseif attr.operation == "Remove" then
			local keywords = attr.keywords or {}
			local abilityKeywords = ability:get_or_add("keywords", {})
			for keyword, _ in pairs(keywords) do
				abilityKeywords[keyword] = nil
			end
			return true
		else
			local keywords = attr.keywords or {}
			local abilityKeywords = ability:get_or_add("keywords", {})

			--Once an ability has been split into its Melee/Ranged action bar
			--variations, each variation must stay single-keyword: a Ranged
			--variation gaining Melee back (or vice versa) would make the
			--action bar's own melee/ranged split logic treat it as a fresh
			--dual-keyword ability again.
			local isMeleeVariation = ability:try_get("isMeleeVariation", false)
			local isRangedVariation = ability:try_get("isRangedVariation", false)

			for keyword, _ in pairs(keywords) do
				local blocked = (keyword == "Ranged" and isMeleeVariation)
					or (keyword == "Melee" and isRangedVariation)
				if not blocked then
					abilityKeywords[keyword] = true
				end
			end
			return true
		end
	end,
}

CharacterModifier.RegisterAbilityModifier
{
	id = "modproperties",
	text = "Modify Special Properties",
	operations = { "Add", "Set", "Remove" },
	set = function(modifier, creature, ability, attr)
		if attr.operation == "Set" then
			ability.properties = attr.properties
			return true
		elseif attr.operation == "Remove" then
			local properties = attr.properties or {}
			local abilityProperties = ability:get_or_add("properties", {})
			for property, _ in pairs(properties) do
				abilityProperties[property] = nil
			end
			return true
		else
			local properties = attr.properties or {}
			local abilityProperties = ability:get_or_add("properties", {})
			for property, _ in pairs(properties) do
				abilityProperties[property] = true
			end
			return true
		end
	end,
}

CharacterModifier.RegisterAbilityModifier
{
	id = "targettype",
	text = "Target Type",
	operations = { "targeting" },
	set = function(modifier, creature, ability, attributes)
		ability.targetType = attributes.targeting
		if attributes.allegiance == "all" then
			ability.objectTarget = false
			ability.targetAllegiance = nil
		elseif attributes.allegiance == "all_and_objects" then
			ability.objectTarget = true
			ability.targetAllegiance = nil
		elseif attributes.allegiance == "ally" then
			ability.objectTarget = false
			ability.targetAllegiance = "ally"
		elseif attributes.allegiance == "enemy" then
			ability.objectTarget = false
			ability.targetAllegiance = "enemy"
		else
			ability.objectTarget = false
			ability.targetAllegiance = nil
		end
		ability.radius = attributes.radius
		return true
	end,
}

CharacterModifier.RegisterAbilityModifier
{
	id = "reasonfilter",
	text = "Reasoned Filter",
	operations = { "reasonfilter" },
	set = function(modifier, creature, ability, attributes)
		local reasonedFilters = attributes.reasonedFilters or {}

		local existingFilters = ability:get_or_add("reasonedFilters", {})

		for _, filter in pairs(reasonedFilters) do
			existingFilters[#existingFilters + 1] = filter
		end

		ability.reasonedFilters = existingFilters

		return true
	end,
}


CharacterModifier.RegisterAbilityModifier
	{
		id = "numtargets",
		text = "Number of Targets",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if operation == "Set" then
				ability.numTargets = value
			elseif operation == "Multiply" then
				ability.numTargets = string.format("(%s) * (%s)", ability.numTargets, value)
			else
				ability.numTargets = string.format("(%s) + (%s)", ability.numTargets, value)
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "range",
		text = "Range",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			-- Burst abilities use ability.range as burst radius, not as a distance.
			-- The "Burst Size" attribute handles those.
			if ability.targetType == "all" then
				return true
			end

			value = dmhub.EvalGoblinScript(value, GenerateSymbols(creature, modifier:try_get("_tmp_symbols")), "Calculate Range Modifier")

			-- For line abilities, "range" means the within-distance (ability.lineDistance),
			-- not the line length (ability.range). Cube abilities already store their
			-- within-distance in ability.range, so no special case is needed there.
			if ability.targetType == "line" then
				local cur = ability.lineDistance
				if operation == "Set" then
					ability.lineDistance = tonumber(value)
				elseif operation == "Multiply" then
					ability.lineDistance = tonum(cur) * tonum(value)
				else
					if type(cur) == "string" and tonumber(cur) == nil then
						ability.lineDistance = string.format("(%s) + (%s)", cur, value)
					else
						ability.lineDistance = tonum(cur) + tonum(value)
					end
				end
				return true
			end

			local val = nil
			if operation == "Set" then
				val = tonumber(value)
			elseif operation == "Multiply" then
				val = tonum(ability.range) * tonum(value)
			else
				if type(ability.range) == "string" and tonumber(ability.range) == nil then
					val = string.format("(%s) + (%s)", ability.range, value)
				else
					val = tonum(ability.range) + tonum(value)
				end
			end

			if val ~= nil then
				ability.range = val
			end
			return true
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to the range for abilities this modifier affects."),
			output = "number",
			examples = {
				{
					script = "1",
					text = "1 is added to the range.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the range, or 4 when the attacking creature is above level 10.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with the ability.",
					examples = {
						"2 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "proximitytargeting",
		text = "Set Proximity Targeting",
		operations = { "Bool" },
		set = function(modifier, creature, ability, operation, value)
			ability.proximityTargeting = true
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "proximityrange",
		text = "Proximity Range",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if operation == "Set" then
				ability.proximityRange = value
			elseif operation == "Multiply" then
				ability.proximityRange = string.format("%s * (%s)", ability.proximityRange, value)
			else
				ability.proximityRange = string.format("%s + (%s)", ability.proximityRange, value)
			end
			return true
		end,
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "burstsize",
		text = "Burst Size",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if ability.targetType ~= "all" then
				return true
			end
			local val = nil
			value = dmhub.EvalGoblinScript(value, GenerateSymbols(creature, modifier:try_get("_tmp_symbols")), "Calculate Burst Size Modifier")
			if operation == "Set" then
				val = tonumber(value)
			elseif operation == "Multiply" then
				val = tonum(ability.range) * tonum(value)
			else
				if type(ability.range) == "string" and tonumber(ability.range) == nil then
					val = string.format("(%s) + (%s)", ability.range, value)
				else
					val = tonum(ability.range) + tonum(value)
				end
			end

			if val ~= nil then
				ability.range = val
			end
			return true
		end,
		documentation = {
			help = "This GoblinScript is applied to the burst radius of burst-type (Area: All) abilities this modifier affects.",
			output = "number",
			examples = {
				{
					script = "1",
					text = "1 is added to the burst radius.",
				},
				{
					script = "2 when level > 5",
					text = "2 is added to the burst radius when the creature is above level 5.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "cubeedge",
		text = "Cube Edge",
		operations = { "Add", "Multiply", "Set" },
		set = function(modifier, creature, ability, operation, value)
			if ability.targetType ~= "cube" then
				return true
			end
			local val = nil
			value = dmhub.EvalGoblinScript(value, GenerateSymbols(creature, modifier:try_get("_tmp_symbols")), "Calculate Cube Edge Modifier")
			local currentRadius = ability:try_get("radius")
			if operation == "Set" then
				val = tonumber(value)
			elseif operation == "Multiply" then
				val = tonum(currentRadius) * tonum(value)
			else
				if type(currentRadius) == "string" and tonumber(currentRadius) == nil then
					val = string.format("(%s) + (%s)", currentRadius, value)
				else
					val = tonum(currentRadius) + tonum(value)
				end
			end

			if val ~= nil then
				ability.radius = val
			end
			return true
		end,
		documentation = {
			help = "This GoblinScript is applied to the edge length of cube-type abilities this modifier affects.",
			output = "number",
			examples = {
				{
					script = "1",
					text = "1 is added to the cube edge length.",
				},
				{
					script = "2 when level > 5",
					text = "2 is added to the cube edge length when the creature is above level 5.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	}

CharacterModifier.RegisterAbilityModifier
{
	id = "linedimensions",
	text = "Line Dimensions",
	operations = { "Add", "Multiply", "Set" },
	set = function(modifier, creature, ability, attr)
		if ability.targetType ~= "line" then
			return true
		end
		local symbols = GenerateSymbols(creature, modifier:try_get("_tmp_symbols"))
		local operation = attr.operation or "Add"

		local lengthValue = attr.lengthValue or ""
		if lengthValue ~= "" then
			local length = tonum(dmhub.EvalGoblinScript(lengthValue, symbols, "Calculate Line Length Modifier"))
			if operation == "Set" then
				ability.range = length
			elseif operation == "Multiply" then
				ability.range = tonum(ability.range) * length
			else
				if type(ability.range) == "string" and tonumber(ability.range) == nil then
					ability.range = string.format("(%s) + (%s)", ability.range, lengthValue)
				else
					ability.range = tonum(ability.range) + length
				end
			end
		end

		local widthValue = attr.widthValue or ""
		if widthValue ~= "" then
			local width = tonum(dmhub.EvalGoblinScript(widthValue, symbols, "Calculate Line Width Modifier"))
			local currentRadius = ability:try_get("radius")
			if operation == "Set" then
				ability.radius = width
			elseif operation == "Multiply" then
				ability.radius = tonum(currentRadius) * width
			else
				if type(currentRadius) == "string" and tonumber(currentRadius) == nil then
					ability.radius = string.format("(%s) + (%s)", currentRadius, widthValue)
				else
					ability.radius = tonum(currentRadius) + width
				end
			end
		end

		return true
	end,
}

CharacterModifier.RegisterAbilityModifier
	{
		id = "healroll",
		text = "Healing Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityHealBehavior" then
					behavior.roll = string.format("%s+(%s)", behavior.roll, value)
				end
			end
		end,
	}

--[[ CharacterModifier.RegisterAbilityModifier
	{
		id = "attackroll",
		text = "Attack Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityAttackBehavior" then
					behavior:AppendHitModification(ability, tostring(value), modifier:try_get("_tmp_symbols"))
				end
			end
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to attack rolls for attacks this modifier affects."),
			output = "roll",
			examples = {
				{
					script = "1",
					text = "1 is added to the attack roll.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the attack roll, or 4 when the attacking creature is above level 10.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with damage.",
					examples = {
						"2 when Target.Hitpoints < Target.Maximum Hitpoints",
						"5 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	} ]]


--[[ CharacterModifier.RegisterAbilityModifier
	{
		id = "attackdamageroll",
		text = "Attack Damage Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityAttackBehavior" then
					if type(value) == "table" then
						value = value:ToText()
					end
					behavior:AppendDamageModification(ability, tostring(value), modifier:try_get("_tmp_symbols"), {
						name = modifier.name,
						description = modifier:try_get("modifyDescription", ""),
					})
				end
			end
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to attack damage rolls for attacks this modifier affects."),
			output = "roll",
			examples = {
				{
					script = "1",
					text = "1 is added to the damage.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the damage, or 4 when the attacking creature is above level 10.",
				},
				{
					script = "1d6 [fire]",
					text = "1d6 Fire damage is added to the damage.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with damage.",
					examples = {
						"1d6 + 1d6 when Target.Hitpoints < Target.Maximum Hitpoints",
						"1d8 + 2d8 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	} ]]

--Top-level roll flags (minroll/reroll/exploding/critical/...) must be appended to the whole
--roll as trailing tokens. Wrapping them in +(...) like an additive damage term makes the roll
--parser treat them as an added sub-expression and silently drop the flag -- e.g. "1d6+(minroll 3)"
--parses as plain "1d6". Detect a flag-led value and append it directly instead.
local g_directDamageRollFlags = {
	"minroll", "reroll", "exploding", "critical", "autocritical",
	"autosuccess", "autofailure", "nottierone", "nottierthree",
	"tierup", "tierdown", "extradie", "extradice",
}

local function DirectDamageRollValueIsFlag(value)
	local trimmed = string.lower(string.trim(value or ""))
	for _,keyword in ipairs(g_directDamageRollFlags) do
		if string.find(trimmed, "^" .. keyword) then
			return true
		end
	end
	return false
end

CharacterModifier.RegisterAbilityModifier
	{
		id = "directdamageroll",
		text = "Direct Damage Rolls",
		operations = { "Add" },
		set = function(modifier, creature, ability, operation, value)
			local isFlag = DirectDamageRollValueIsFlag(value)
			for i,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityDamageBehavior" then
					if isFlag then
						--append as a trailing top-level roll flag, not an added damage term.
						behavior.roll = string.format("%s %s", behavior.roll, value)
					else
						behavior.roll = string.format("%s+(%s)", behavior.roll, value)
					end
				end
			end
		end,
		documentation = {
			help = string.format("This GoblinScript is appended to direct damage rolls for abilities this modifier affects."),
			output = "roll",
			examples = {
				{
					script = "1",
					text = "1 is added to the damage.",
				},
				{
					script = "3 + 1 when level > 10",
					text = "3 is added to the damage, or 4 when the attacking creature is above level 10.",
				},
				{
					script = "1d6 [fire]",
					text = "1d6 Fire damage is added to the damage.",
				},
			},
			subject = creature.helpSymbols,
			subjectDescription = "The creature that is affected by this modifier",
			symbols = {
				target = {
					name = "Target",
					type = "creature",
					desc = "The creature targeted with damage.",
					examples = {
						"1d6 + 1d6 when Target.Hitpoints < Target.Maximum Hitpoints",
						"1d8 + 2d8 when Target.Type is undead",
					},
				},
				ability = {
					name = "Ability",
					type = "ability",
					desc = "The ability being modified",
				},
			},
		},
	}

CharacterModifier.RegisterAbilityModifier
	{
		id = "damagetype",
		text = "Damage Type",
		operations = { "Set" },
		set = function(modifier, creature, ability, operation, value)
			if value == nil or value == "" then
				return true
			end
			value = string.lower(value)

			for _,behavior in ipairs(ability.behaviors) do
				if behavior.typeName == "ActivatedAbilityDamageBehavior" then
					--Direct damage behaviors (e.g. monster free strikes) store the
					--damage type directly. This is the case Raining Cinders hits.
					behavior.damageType = value
				elseif behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
					--Power roll tiers store damage as text like "5 fire damage" or
					--"5 damage". Rewrite the first damage clause of each tier to the
					--new type. Mirrors the tier rewrite in MCDModifyPowerRolls.lua.
					local tiers = behavior:try_get("tiers")
					if tiers ~= nil then
						for i=1,#tiers do
							local m = regex.MatchGroups(tiers[i], "^(?<prefix>.*?)(?<damage>\\d+)\\s+([a-zA-Z]+\\s+)?damage(?<suffix>.*)$")
							if m ~= nil then
								tiers[i] = m.prefix .. m.damage .. " " .. value .. " damage" .. m.suffix
							end
						end
					end
				end
			end
			return true
		end,
	}

--The "replaceBehavior" used to be false (default) for placing new behaviors at the end, and true for replacing behaviors.
--Now it has three modes, "after", "before", and "replace". This converts an old modifier to the new mode.
local function ReplaceBehaviorToEnum(mode)
	if mode == false then
		return "after"
	end

	if mode == true then
		return "before"
	end

	return mode
end

--a 'modifyability' modifier has the following properties:
--modifyDescription (string): a string to add to the ability's description describing what was changed.
--filterAbility (string) optional: GoblinScript to determine if an ability gets modified.
--attributes (list of { id = string, operation = string|nil, value = string}): List of attributes we modify
--ability: ActivatedAbility -- we use it for the behaviors.
--actionResourceId: (optional) -- if set, this overrides the action resource id.
--cannotModifyAction: (optional) -- if set this modifier can't override actions. Used in ActivatedAbilityAugmentAbilityBehavior
--unconditional: (optional) -- if set then filter condition won't be shown. This is for when the modification always applies, e.g. for ammo.
CharacterModifier.TypeInfo.modifyability = {
	init = function(modifier)
		modifier.attributes = {}
		modifier.ability = ActivatedAbility.Create{
			abilityModification = true,
		}
	end,

	willModifyAbility = function(modifier, creature, ability)
        local keywords = modifier:try_get("keywords", {})

        for keyword,_ in pairs(keywords) do
            if not ability:HasKeyword(keyword) then
                return false
            end
        end
		if modifier:try_get("filterAbility", "") ~= '' then
			modifier._tmp_symbols = modifier:get_or_add("_tmp_symbols", {})
			modifier._tmp_symbols.ability = GenerateSymbols(ability)
			local result = ExecuteGoblinScript(modifier.filterAbility, GenerateSymbols(creature, modifier._tmp_symbols), 0, string.format("Should modify ability: %s", ability.name))
			if result == 0 then
				return false
			end
		end

		return true
	end,

	modifyAbility = function(modifier, creature, ability)
        local keywords = modifier:try_get("keywords", {})
        for keyword,_ in pairs(keywords) do
            if not ability:HasKeyword(keyword) then
                return ability
            end
        end
		if modifier:try_get("filterAbility", "") ~= '' then
			modifier._tmp_symbols = modifier:get_or_add("_tmp_symbols", {})
			modifier._tmp_symbols.ability = GenerateSymbols(ability)
			local result = ExecuteGoblinScript(modifier.filterAbility, GenerateSymbols(creature, modifier._tmp_symbols), 0, string.format("Should modify ability: %s", ability.name))
			if result == 0 then
				return ability
			end
		end

		ability = ability:MakeTemporaryClone()

		if modifier:has_key("actionResourceId") then
			ability.actionResourceId = modifier.actionResourceId
		end

		for i,attr in ipairs(modifier.attributes) do
			local info = abilityModifierOptionsById[attr.id]
			if info ~= nil then
				if attr.id == "targettype" or attr.id == "modkeywords" or attr.id == "reasonfilter" or attr.id == "modproperties" or attr.id == "linedimensions" then
					info.set(modifier, creature, ability, attr)
				else
					info.set(modifier, creature, ability, attr.operation, attr.value, attr.condition)
				end
			end
		end

		if modifier:has_key("ability") then
			local replacementMode = ReplaceBehaviorToEnum(modifier:try_get("replaceBehaviors", false))

			local atend = {}
			if replacementMode == "before" then
				atend = ability.behaviors
				ability.behaviors = {}
			elseif replacementMode == "replaceAll" then
				ability.behaviors = {}
			end

			local nstarting = #ability.behaviors
			for i,behavior in ipairs(modifier.ability.behaviors) do
				local replaced = false
				if replacementMode == "replace" then
					for j=1,nstarting do
						if ability.behaviors[j].typeName == behavior.typeName then
							ability.behaviors[j] = DeepCopy(behavior)
							replaced = true
							break
						end
					end
				end

				if not replaced then
					ability.behaviors[#ability.behaviors+1] = DeepCopy(behavior)
				end
			end

			for _,b in ipairs(atend) do
				ability.behaviors[#ability.behaviors+1] = b
			end
		end

		if modifier:try_get("modifyDescription", "") ~= "" then
			local modifyDescriptions = ability:get_or_add("modifyDescriptions", {})
			modifyDescriptions[#modifyDescriptions+1] = modifier.modifyDescription
		end

		return ability
	end,

	createEditor = function(modifier, element)
		local Refresh
		local firstRefresh = true
		Refresh = function()
			if firstRefresh then
				firstRefresh = false
			else
				element:FireEvent("refreshModifier")
			end

			local children = {}

			if not modifier:try_get("unconditional") then
				children[#children+1] = modifier:FilterConditionEditor("filterAbility", Refresh)
			end

			children[#children+1] = gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Modify Description:",
				},
				gui.Input{
					width = 300,
					fontSize = 16,
					height = "auto",
					minHeight = 22,
					maxHeight = 60,
					multiline = true,
					characterLimit = 2000,
					placeholderText = "Enter text to add to ability...",
					text = modifier:try_get("modifyDescription"),
					change = function(element)
						modifier.modifyDescription = element.text
						Refresh()
					end,
				}
			}

            children[#children+1] = gui.Check{
				styles = ThemeEngine.GetStyles(),
                text = "Must Pay Resource Cost",
                value = modifier:try_get("mustPayResourceCost", false),
                change = function(element)
                    modifier.mustPayResourceCost = element.value
                    Refresh()
                end,
            }

            children[#children+1] = gui.Check{
				styles = ThemeEngine.GetStyles(),
                text = "Apply to Triggered Abilities",
                value = modifier:try_get("applyToTriggeredAbilities", false),
                change = function(element)
                    modifier.applyToTriggeredAbilities = element.value
                    Refresh()
                end,
            }

            --Power roll triggers can't honor the filterAbility GoblinScript
            --(no ability to evaluate it against), so hide the toggle when a
            --filter is set. Re-renders on the next Refresh() after the filter
            --field changes.
            if modifier:try_get("filterAbility", "") == "" then
                children[#children+1] = gui.Check{
                    styles = ThemeEngine.GetStyles(),
                    text = "Apply to Power Roll Triggers",
                    value = modifier:try_get("applyToPowerRollTriggers", false),
                    change = function(element)
                        modifier.applyToPowerRollTriggers = element.value
                        Refresh()
                    end,
                }
            end

			local actions = DeepCopy(CharacterResource.GetActionOptions())
			actions[#actions+1] = {
				id = "nochange",
				text = "(Unchanged)",
			}

            local keywords = modifier:try_get("keywords", {})
            children[#children+1] = gui.KeywordSelector{
				styles = ThemeEngine.GetStyles(),
                keywords = keywords,
                change = function()
                    modifier.keywords = keywords
                    Refresh()
                end,
            }

			if modifier:try_get("cannotModifyAction", false) == false then
				children[#children+1] = gui.Panel{
					classes = "formPanel",
					gui.Label{
						classes = "formLabel",
						text = "Change Action:",
					},
					gui.Dropdown{
						styles = ThemeEngine.GetStyles(),
						classes = "formDropdown",
						idChosen = modifier:try_get("actionResourceId", "nochange"),
						options = actions,
						change = function(element)
							if element.idChosen == "nochange" then
								modifier.actionResourceId = nil
							else
								modifier.actionResourceId = element.idChosen
							end
							Refresh()
						end,
					},
				}
			end
			

			for i,attr in ipairs(modifier.attributes) do
				local info = abilityModifierOptionsById[attr.id]
				if info ~= nil then
					children[#children+1] = gui.Panel{
						classes = {"formPanel", "formPanel-inline"},
						gui.Label{
							classes = {"formLabel"},
							width = 400,
							text = info.text,
						},
						gui.Button{
							classes = {"deleteButton", "sizeXs"},
							valign = 'center',
							halign = 'right',
							click = function(element)
								table.remove(modifier.attributes, i)
								Refresh()
							end,
						},
					}

					if info.operations ~= nil then
						if #info.operations > 1 then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"formLabel"},
									text = "Operation:",
								},
								gui.Dropdown{
									styles = ThemeEngine.GetStyles(),
									height = 30,
									width = 260,
									fontSize = 16,
									optionChosen = attr.operation,
									options = info.operations,
									change = function(element)
										modifier.attributes[i].operation = element.optionChosen
										Refresh()
									end,
								},
							}
						end

						if attr.operation == "Bool" then
							children[#children+1] = gui.Check{
								styles = ThemeEngine.GetStyles(),
								text = info.text,
								style = {
									height = 30,
									width = 260,
									fontSize = 18,
								},

								value = cond(tonumber(attr.value), true, false),
								change = function(element)
									attr.value = cond(element.value, "1", "0")
									Refresh()
								end,
							}
						elseif attr.operation == "targeting" then
							local dummyAbility = ActivatedAbility.Create{}
							local radiusItems = {sphere = true, cylinder = true, line = true, cube = true}
							children[#children+1] = gui.Panel{
								classes = "formPanel",
								gui.Label{
									classes = "formLabel",
									text = "Target Type:",
								},
								gui.Dropdown{
									styles = ThemeEngine.GetStyles(),
									classes = "formDropdown",
									options = dummyAbility:GetDisplayedTargetTypeOptions(),
									idChosen = attr.targeting or "self",
									change = function(element)
										attr.targeting = element.idChosen
										Refresh()
									end,
								},
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = "formLabel",
									text = "Affects:",
								},
								gui.Dropdown{
									styles = ThemeEngine.GetStyles(),
									classes = "formDropdown",
									options = {
										{
											id = "all",
											text = "Creatures",
										},
										{
											id = "all_and_objects",
											text = "Creatures and Objects",
										},
										{
											id = "ally",
											text = "Allied Creatures",
										},
										{
											id = "enemy",
											text = "Enemy Creatures",
										},
									},
									idChosen = attr.allegiance or "all",
									change = function(element)
										attr.allegiance = element.idChosen
										Refresh()
									end,
								},
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel", cond(not radiusItems[attr.targeting], 'collapsed-anim')},
								gui.Label{
									classes = "formLabel",
									text = "Radius:",
									create = function(element)
										if attr.targeting == 'line' then
											element.text = 'Width:'
										elseif attr.targeting == 'cube' then
											element.text = 'Edge:'
										else
											element.text = 'Radius:'
										end
									end,
								},

								gui.GoblinScriptInput{
									classes = "formInput",
									value = attr.radius or "",
									change = function(element)
										attr.radius = element.value
										Refresh()
									end,
									documentation = {
										domains = modifier:Domains(),
										help = " This GoblinScript is used to determine the radius of this <color=#00FFFF><link=ability>ability</link></color>. It produces a number which is used as the range of the ability, given in feet. If left empty, the ability will have a range of 5.",
										output = "number",
										examples = {
											{
												script = "2",
												text = "The ability will have a radius of 2 squares.",
											},
											{
												script = "2 + level",
												text = "The ability will have a range of 2 squares plus 1 for each level of the caster.",
											},
										},

										subject = creature.helpSymbols,
										subjectDescription = "The creature using the ability",
										symbols = table.union({
											ability = {
												name = "Ability",
												type = "ability",
												desc = "The ability being used.",
											},
										}, ActivatedAbility.helpCasting),
									}
								},
							}
						-- This creates both a condition and value input, both goblin script values
						elseif attr.operation == "reasonfilter" then
							local reasonedFilters = attr.reasonedFilters or {}
							if not attr.reasonedFilters then
								attr.reasonedFilters = reasonedFilters
							end
							children[#children+1] = gui.Button{
								text = "Add Reasoned Filter",
								width = "auto",
								height = "auto",
								pad = 4,
								press = function(element)
									reasonedFilters[#reasonedFilters+1] = {
										formula = "",
										reason = "",
									}
									attr.reasonedFilters = reasonedFilters
									Refresh()
								end,
							}

							for filterIndex,filter in ipairs(reasonedFilters) do
								children[#children+1] = gui.Panel{
									classes = {"formPanel", "formPanel-inline"},
									gui.Label{
										classes = "formLabel",
										text = "Formula:",
									},
									gui.GoblinScriptInput{
										classes = "formInput",
										value = filter.formula,
										change = function(element)
											filter.formula = element.value
											Refresh()
										end,

										documentation = {
											domains = modifier:Domains(),
											help = "This GoblinScript is used when you use an <color=#00FFFF><link=ability>ability</link></color>. It determines whether a creature included in the ability's area of effect should be affected by the ability. The script is evaluated once for each creature in the ability's area of effect. Creatures for whom the script produces a result of <b>true</b> are affected by the ability, while creatures for whom the script produces a result of <b>false</b> are not. If left empty, all creatures in the area of effect will be affected.",
											output = "boolean",
											examples = {
												{
													script = "enemy",
													text = "Make the ability affect creatures that are enemies of the ability's caster.",
												},
												{
													script = "not enemy and type is not undead",
													text = "Make the ability affect creatures that are not enemies of the ability's caster. The ability won't affect undead creatures.",
												},
												{
													script = "Target Number = 2",
													text = "Make this behavior affect only the second target of the spell.",
												},
											},
											subject = creature.helpSymbols,
											subjectDescription = "A creature in the ability's area of effect ",
											symbols = {
												caster = {
													name = "Caster",
													type = "creature",
													desc = "The caster of this spell.",
												},
												enemy = {
													name = "Enemy",
													type = "boolean",
													desc = "True if the subject is an enemy of the creature casting the ability. Otherwise this is False.",
												},
												target = {
													name = "Target",
													type = "creature",
													desc = "The target of this spell. This is the same as the subject of this GoblinScript.",
												},
												targetnumber = {
													name = "Target Number",
													type = "number",
													desc = "1 for the first target, 2 for the second target, etc.",
												},
												numberoftargets = {
													name = "Number of Targets",
													type = "number",
													desc = "The number of creatures this spell is targeting.",
												},
											},
										},
									},

									gui.Button{
										classes = {"deleteButton", "sizeS"},
										halign = "right",
										click = function(element)
											table.remove(reasonedFilters, filterIndex)
											Refresh()
										end
									}
								}

								children[#children+1] = gui.Panel{
									classes = {"formPanel"},
									gui.Input{
										classes = "formInput",
										width = 360,
										text = filter.reason,
										lmargin = 60,
										change = function(element)
											filter.reason = element.text
											Refresh()
										end,
										placeholderText = "Enter reason for this filter...",
									}
								}
							end
						elseif attr.operation == "Condition" then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"formLabel"},
									text = "Condition:",
								},
								gui.GoblinScriptInput{
									height = 22,
									width = 360,
									fontSize = 16,
									value = attr.condition,

									change = function(element)
										modifier.attributes[i].condition = element.value
										Refresh()
									end,
									documentation = info.conditionDocumentation,
								}
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Value:",
								},
								gui.GoblinScriptInput{
									height = "auto",
									width = 360,
									fontSize = 16,
									value = attr.value,

									change = function(element)
										modifier.attributes[i].value = element.value
										Refresh()
									end,
									documentation = info.documentation,
								},
							}
						elseif info.documentation ~= nil then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Value:",
								},
								gui.GoblinScriptInput{
									height = "auto",
									width = 360,
									fontSize = 16,
									value = attr.value,

									change = function(element)
										modifier.attributes[i].value = element.value
										Refresh()
									end,
									documentation = info.documentation,
								},
							}
						elseif attr.id == "modkeywords" then
							local keywords = attr and attr.keywords or {}

							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.KeywordSelector{
									keywords = keywords,
									change = function()
										attr.keywords = keywords
										Refresh()
									end,
								},
							}
						elseif attr.id == "modproperties" then
							local properties = attr and attr.properties or {}

							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Multiselect{
									styles = ThemeEngine.GetStyles(),
									value = properties,
									addItemText = "Add Special Property...",
									options = ActivatedAbility.registeredProperties,
									change = function(element, value)
										attr.properties = value
										Refresh()
									end,
								},
							}
						elseif attr.id == "damagetype" then
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								gui.Label{
									classes = {"formLabel"},
									text = "Damage Type:",
								},
								gui.Dropdown{
									styles = ThemeEngine.GetStyles(),
									classes = "formDropdown",
									options = rules.damageTypesAvailable,
									idChosen = attr.value,
									change = function(element)
										modifier.attributes[i].value = element.idChosen
										Refresh()
									end,
								},
							}
						elseif attr.id == "linedimensions" then
							local lineLengthDoc = {
								domains = modifier:Domains(),
								help = "This GoblinScript is applied to the length of line-type abilities this modifier affects.",
								output = "number",
								examples = {
									{
										script = "1",
										text = "1 is added to the line length.",
									},
									{
										script = "2 when level > 5",
										text = "2 is added to the line length when the creature is above level 5.",
									},
								},
								subject = creature.helpSymbols,
								subjectDescription = "The creature that is affected by this modifier",
								symbols = {
									ability = {
										name = "Ability",
										type = "ability",
										desc = "The ability being modified",
									},
								},
							}
							local lineWidthDoc = {
								domains = modifier:Domains(),
								help = "This GoblinScript is applied to the width of line-type abilities this modifier affects.",
								output = "number",
								examples = {
									{
										script = "1",
										text = "1 is added to the line width.",
									},
									{
										script = "2 when level > 5",
										text = "2 is added to the line width when the creature is above level 5.",
									},
								},
								subject = creature.helpSymbols,
								subjectDescription = "The creature that is affected by this modifier",
								symbols = {
									ability = {
										name = "Ability",
										type = "ability",
										desc = "The ability being modified",
									},
								},
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Length:",
								},
								gui.GoblinScriptInput{
									height = "auto",
									width = 360,
									fontSize = 16,
									value = attr.lengthValue or "",
									change = function(element)
										modifier.attributes[i].lengthValue = element.value
										Refresh()
									end,
									documentation = lineLengthDoc,
								},
							}
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Width:",
								},
								gui.GoblinScriptInput{
									height = "auto",
									width = 360,
									fontSize = 16,
									value = attr.widthValue or "",
									change = function(element)
										modifier.attributes[i].widthValue = element.value
										Refresh()
									end,
									documentation = lineWidthDoc,
								},
							}
						else
							children[#children+1] = gui.Panel{
								classes = {"formPanel"},
								height = "auto",
								gui.Label{
									classes = {"formLabel"},
									text = "Value:",
								},
								gui.Input{
									height = 22,
									width = 360,
									fontSize = 16,
									text = attr.value,

									change = function(element)
										modifier.attributes[i].value = element.text
										Refresh()
									end,
								},
							}
						end
					end
				end
			end

			children[#children+1] = gui.Dropdown{
				styles = ThemeEngine.GetStyles(),
				options = abilityModifierOptions,
				idChosen = "none",
				height = 30,
				width = 260,
				fontSize = 16,

				change = function(element)
					if element.idChosen == "none" then
						return
					end

					local op = nil
					local info = abilityModifierOptionsById[element.idChosen]
					if info.operations ~= nil then
						op = info.operations[1]
					end

					modifier.attributes[#modifier.attributes+1] = {
						id = element.idChosen,
						operation = op,
						value = "",
					}
					Refresh()
				end,
			}

			if modifier:try_get("ability") ~= nil then
				children[#children+1] = modifier.ability:BehaviorEditor{ behaviorOnly = true }

				children[#children+1] = gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						text = "Behaviors Mode:",
					},
					gui.Dropdown{
						styles = ThemeEngine.GetStyles(),
						options = {
							{
								id = "after",
								text = "Place After",
							},
							{
								id = "before",
								text = "Place Before",
							},
							{
								id = "replace",
								text = "Replace Matching Behaviors",
							},
							{
								id = "replaceAll",
								text = "Replace All Behaviors"
							}
						},
						idChosen = ReplaceBehaviorToEnum(modifier:try_get("replaceBehaviors", false)),
						change = function(element)
							modifier.replaceBehaviors = element.idChosen
						end,
					}
				}

			end

			element.children = children
		end

		Refresh()
	end,

}
