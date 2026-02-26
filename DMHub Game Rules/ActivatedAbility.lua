local mod = dmhub.GetModLoading()

--This file implements *activated abilities*. Note that spells are a type of activated ability (though see the spells
--file, since they override some behavior). Attacks are also a type of activated ability.
--Activated abilities have different behaviors and you can use the examples in here to define your own.

--- @alias AbilityTarget {loc: Loc, token = nil|CharacterToken}
--- @alias Symbols table|function

--- @class ActivatedAbility
--- @field description string Rules text shown to players.
--- @field flavor string Flavor/lore text shown in the ability tooltip.
--- @field range number Targeting range in world units.
--- @field lineDistance number Length for line-area targeting.
--- @field rangeDisadvantage string GoblinScript: if truthy, ranged attacks have disadvantage.
--- @field selfTarget boolean If true, the ability always targets the caster.
--- @field castImmediately boolean If true, auto-casts when there are no targeting choices.
--- @field recharge boolean|number Recharge roll threshold (false = no recharge mechanic).
--- @field legendary boolean If true, this is a legendary action.
--- @field categorization string Ability category string (e.g. "none", "action", "maneuver").
--- @field multipleModes boolean If true, the ability has multiple selectable modes.
--- @field domains table<string, boolean> Domain set this ability belongs to.
--- @field isSpell boolean If true, this ability is treated as a spell.
--- @field abilityModification boolean If true, this is a modification of another ability rather than a standalone ability.
--- @field usesSpellSlots boolean If true, casting consumes a spell slot.
--- @field projectileObject string Asset id of the object to use as a projectile visual ("none" if unused).
--- @field durationType string Duration unit: "instant", "rounds", "minutes", "hours", or "days".
--- @field durationLength number Numeric duration in durationType units.
--- @field concentration boolean If true, maintaining this effect requires concentration.
--- @field silent boolean If true, the ability is triggered by the system and does not show a dialog.
--- @field castingTime string DEPRECATED. Use actionResourceId instead.
--- @field actionResourceId string The resource id consumed to cast (e.g. the action resource guid).
--- @field actionNumber number Number of action resources consumed.
--- @field resourceCost string Secondary resource id cost ("none" if free).
--- @field resourceNumber number Amount of the secondary resource cost.
--- @field targetFilter string GoblinScript formula to filter valid targets.
--- @field channeledResource string Resource id that can be channeled into this ability for variable power ("none" if unused).
--- @field channelDescription string Description shown when channeling resource into the ability.
--- @field channelIncrement number|string Minimum channel increment (number or GoblinScript formula).
--- @field proximityTargeting boolean If true, targeting uses proximity range instead of ability range.
--- @field proximityRange string Range in world units for proximity targeting.
--- @field behaviors ActivatedAbilityBehavior[] The list of behaviors that execute when the ability is cast.
ActivatedAbility = RegisterGameType("ActivatedAbility")

--- @class ActivatedAbilityBehavior
--- @field instant boolean If true, executes immediately (not in a coroutine).
--- @field customOngoingEffect boolean If true, uses a custom ongoing effect rather than the default.
--- @field duration string Duration type for the effect ("none" by default).
--- @field filterTarget string GoblinScript: if falsy for a target, skip it.
--- @field summary string Short display name shown in the ability editor.
--- @field applyto string Which targets receive this behavior ("targets" or other filter).
--- @field stacks boolean|string Whether the behavior stacks ("1" or false).
--- @field damageType string Default damage type for behaviors that deal damage.
--- @field durationUntilEndOfTurn boolean If true, the effect lasts until end of caster's turn.
--- @field mono boolean If true, only one of these behaviors can be in an ability's list at a time.
ActivatedAbilityBehavior = RegisterGameType("ActivatedAbilityBehavior")

--- @class ActivatedAbilityAttackBehavior:ActivatedAbilityBehavior
ActivatedAbilityAttackBehavior = RegisterGameType("ActivatedAbilityAttackBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityDamageBehavior:ActivatedAbilityBehavior
ActivatedAbilityDamageBehavior = RegisterGameType("ActivatedAbilityDamageBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityHealBehavior:ActivatedAbilityBehavior
ActivatedAbilityHealBehavior = RegisterGameType("ActivatedAbilityHealBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityAugmentedAbilityBehavior:ActivatedAbilityBehavior
ActivatedAbilityAugmentedAbilityBehavior = RegisterGameType("ActivatedAbilityAugmentedAbilityBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityCastSpellBehavior:ActivatedAbilityBehavior
ActivatedAbilityCastSpellBehavior = RegisterGameType("ActivatedAbilityCastSpellBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityApplyOngoingEffectBehavior:ActivatedAbilityBehavior
ActivatedAbilityApplyOngoingEffectBehavior = RegisterGameType("ActivatedAbilityApplyOngoingEffectBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityRemoveOngoingEffectBehavior:ActivatedAbilityBehavior
ActivatedAbilityRemoveOngoingEffectBehavior = RegisterGameType("ActivatedAbilityRemoveOngoingEffectBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityAbilityAuraBehavior:ActivatedAbilityBehavior
ActivatedAbilityAuraBehavior = RegisterGameType("ActivatedAbilityAuraBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityMoveAuraBehavior:ActivatedAbilityBehavior
ActivatedAbilityMoveAuraBehavior = RegisterGameType("ActivatedAbilityMoveAuraBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityTransformBehavior:ActivatedAbilityBehavior
ActivatedAbilityTransformBehavior = RegisterGameType("ActivatedAbilityTransformBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityContestedAttackBehavior:ActivatedAbilityBehavior
ActivatedAbilityContestedAttackBehavior = RegisterGameType("ActivatedAbilityContestedAttackBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityForcedMovementBehavior:ActivatedAbilityBehavior
ActivatedAbilityForcedMovementBehavior = RegisterGameType("ActivatedAbilityForcedMovementBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityModifiersBehavior:ActivatedAbilityBehavior
ActivatedAbilityModifiersBehavior = RegisterGameType("ActivatedAbilityModifiersBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityApplyMomentaryEffectBehavior:ActivatedAbilityBehavior
ActivatedAbilityApplyMomentaryEffectBehavior = RegisterGameType("ActivatedAbilityApplyMomentaryEffectBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.description = ""

ActivatedAbility.flavor = ""

ActivatedAbility.range = dmhub.unitsPerSquare
ActivatedAbility.lineDistance = 1
ActivatedAbility.rangeDisadvantage = ""
ActivatedAbility.selfTarget = false
ActivatedAbility.castImmediately = false --auto-casts immediately if there are no targeting choices.
ActivatedAbility.recharge = false --roll number for recharging this ability.

ActivatedAbility.legendary = false

ActivatedAbility.categorization = "none"

--indicates that this behavior occurs instantly, not in a co-routine.
ActivatedAbilityBehavior.instant = false
ActivatedAbilityBehavior.customOngoingEffect = true
ActivatedAbilityBehavior.duration = "none"
ActivatedAbilityApplyMomentaryEffectBehavior.instant = true
ActivatedAbilityModifiersBehavior.instant = true

ActivatedAbilityBehavior.filterTarget = "" --GoblinScript which determines if we are going to include this target.

ActivatedAbilityBehavior.summary = 'None'
ActivatedAbilityAttackBehavior.summary = 'Attack'
ActivatedAbilityHealBehavior.summary = 'Heal'
ActivatedAbilityAugmentedAbilityBehavior.summary = 'Augment Ability'
ActivatedAbilityCastSpellBehavior.summary = 'Cast Spell'
ActivatedAbilityApplyOngoingEffectBehavior.summary = 'Apply Ongoing Effect'
ActivatedAbilityRemoveOngoingEffectBehavior.summary = 'Remove Ongoing Effect'
ActivatedAbilityAuraBehavior.summary = 'Create an Aura'
ActivatedAbilityMoveAuraBehavior.summary = 'Move an Aura'
ActivatedAbilityApplyMomentaryEffectBehavior.summary = 'Apply Momentary Effect'
ActivatedAbilityContestedAttackBehavior.summary = 'Contested Attack'
ActivatedAbilityForcedMovementBehavior.summary = 'Forced Movement'
ActivatedAbilityModifiersBehavior.summary = 'Modify this Ability'

--what the behavior applies to. By default it is executed on all targets.
ActivatedAbilityBehavior.applyto = 'targets'

--indicates this behavior doesn't have stacks.
ActivatedAbilityBehavior.stacks = false

--a default damage type for those behaviors that have a damage type.
ActivatedAbilityBehavior.damageType = "force"

ActivatedAbilityApplyOngoingEffectBehavior.repeatSave = false
ActivatedAbilityApplyOngoingEffectBehavior.hasTemporaryHitpoints = false
ActivatedAbilityApplyOngoingEffectBehavior.temporaryHitpoints = "5"
ActivatedAbilityApplyOngoingEffectBehavior.stacks = "1"
ActivatedAbilityBehavior.durationUntilEndOfTurn = false

ActivatedAbility.multipleModes = false

ActivatedAbility.domains = {}
ActivatedAbility.isSpell = false

ActivatedAbilityBehavior.mono = false
ActivatedAbilityAugmentedAbilityBehavior.mono = true
ActivatedAbilityCastSpellBehavior.mono = true

--if this isn't a real ability but a modification of an ability.
ActivatedAbility.abilityModification = false

ActivatedAbility.usesSpellSlots = false

--id of object used for projectiles.
ActivatedAbility.projectileObject = "none"

ActivatedAbility.durationType = "instant"
ActivatedAbility.durationLength = 0
ActivatedAbility.concentration = false

--- @return nil|number
function ActivatedAbility:GetDurationInRounds()
	if self.durationType == "instant" then
		return 0
	elseif self.durationType == "rounds" then
		return self.durationLength
	elseif self.durationType == "minutes" then
		return self.durationLength*10
	elseif self.durationType == "hours" then
		return self.durationLength*10*60
	elseif self.durationType == "days" then
		return self.durationLength*10*60*24
	else
		return nil
	end
end

--- Replaces this ability's domain set with a copy of the given domains table.
--- @param domains table<string, boolean>
function ActivatedAbility:SetDomains(domains)
	self.domains = DeepCopy(domains)
end

--- Called after deserialization to migrate legacy single-behavior data to the behaviors list.
function ActivatedAbility:OnDeserialize()
	if self:has_key("behavior") then
		local behaviors = self:get_or_add("behaviors", {})
		behaviors[#behaviors+1] = self.behavior
		self.behavior = nil
	end

	if not self:has_key("behaviors") then
		self.behaviors = {}
	end

	if self.targetType == 'point' then
		self.targetType = 'target'
	end
end

--- @return string
function ActivatedAbility:BehaviorSummary()
	if self.behaviors[1] then
		return self.behaviors[1].summary
	end

	return "None"
end

--if this is set, the ability got triggered by the local player but it's from the game, not them, so
--it doesn't trigger a dialog for them or anything like that.
ActivatedAbility.silent = false

ActivatedAbility.castingTime = "action" --DEPRECATED. Use actionResourceId instead.
ActivatedAbility.actionResourceId = "none"
ActivatedAbility.actionNumber = 1 --number of actions this consumes
ActivatedAbility.resourceCost = "none"
ActivatedAbility.resourceNumber = 1
ActivatedAbility.targetFilter = ''

--is there a variable resource cost that can be channeled into this?
ActivatedAbility.channeledResource = "none"
ActivatedAbility.channelDescription = ""
ActivatedAbility.channelIncrement = 1

--- Returns the minimum channel increment as an integer (at least 1).
--- @return number
function ActivatedAbility:ChannelIncrement()
	return math.max(1, round(tonumber(self.channelIncrement) or 1))
end

ActivatedAbility.proximityTargeting = false
ActivatedAbility.proximityRange = "5"

ActivatedAbility.sequentialTargeting = false

--for emptyspace targetType, this is the type of targeting used.
ActivatedAbility.targeting = "direct"

--for line type targeting.
ActivatedAbility.canChooseLowerRange = false

--if this is a temporary clone that doesn't get serialized etc.
ActivatedAbility._tmp_temporaryClone = false

ActivatedAbility.displayOrder = 1

--- @return number
function ActivatedAbility:DisplayOrder()
    return self.displayOrder
end

--- @return ActivatedAbility
function ActivatedAbility:MakeTemporaryClone()
	if self._tmp_temporaryClone then
		return self
	else
		local result = DeepCopy(self)
		result._tmp_temporaryClone = true
		return result
	end
end

--- @field ActivatedAbility.keywords table<string,boolean>
ActivatedAbility.keywords = {}

--- @param keyword string
function ActivatedAbility:AddKeyword(keyword)
	if self.keywords == ActivatedAbility.keywords then
		self.keywords = {}
	end
	self.keywords[keyword] = true
end

--- @param keyword string
--- @return boolean
function ActivatedAbility:HasKeyword(keyword)
	return self.keywords[keyword] == true
end

--- @param keyword string
function ActivatedAbility:RemoveKeyword(keyword)
	self.keywords[keyword] = nil
end

--- @return boolean
function ActivatedAbility:RequiresConcentration()
	return cond(self:try_get("concentration"), true, false)
end

function ActivatedAbility:GetTypeIconForActionBar()
    return nil
end

--- @field ActivatedAbility.TargetTypes DropdownOption[]
ActivatedAbility.TargetTypes = {
	{
		id = 'self',
		text = 'None/Self',
	},
	{
		id = 'all',
		text = 'Burst',
	},
	{
		id = 'target',
		text = 'Creature',
	},
	{
		id = 'sphere',
		text = 'Sphere',
        hidden = true,
	},
	{
		id = 'cylinder',
		text = 'Cylinder',
        hidden = true,
	},
	{
		id = 'line',
		text = 'Line',
	},
	{
		id = 'cube',
		text = 'Cube',
	},
	{
		id = 'cone',
		text = 'Cone',
        hidden = true,
	},
	{
		id = 'emptyspace',
		text = 'Empty Space',
	},
	{
		id = 'emptyspacefriend',
		text = 'Empty Space or Friend',
	},
	{
		id = 'anyspace',
		text = 'Any Space',
	},
    {
        id = 'map',
        text = "All Creatures in Encounter",
    },
    {
        id = "areatemplate",
        text = "Area Template on Map",
    }
}

--- @param targetType nil|string
--- @return boolean
function ActivatedAbility:IsTargetTypeAOE(targetType)
    targetType = targetType or self.targetType
    return targetType == "all" or targetType == "sphere" or targetType == "cylinder" or targetType == "line" or targetType == "cube" or targetType == "cone" or targetType == "areatemplate"
end

--- @return DropdownOption[]
function ActivatedAbility:GetTargetTypes()
	local result = {}
	for _,item in ipairs(self.TargetTypes) do
		if item.condition == nil or item.condition(self) then
			result[#result+1] = item
		end
	end

	return result
end

ActivatedAbility.TargetTypesById = GetDropdownEnumById(ActivatedAbility.TargetTypes)

ActivatedAbility.targetType = 'self'
ActivatedAbility.objectTarget = false

--- @field ActivatedAbility.targetAllegiance false|'ally'|'enemy'
ActivatedAbility.targetAllegiance = false

--- @field ActivatedAbility.Types DropdownOption[]
ActivatedAbility.Types = {
	{
		id = 'none',
		text = 'None',
	},

}

ActivatedAbility.TypesById = {}

--a hook for triggered abilities to grab to update their types.
ActivatedAbility.OnTypeRegistered = function() end

--- Registers a new ability behavior type. Adds it to ActivatedAbility.Types and ActivatedAbility.TypesById.
--- @param args {id: string, text: string, createBehavior: fun(): ActivatedAbilityBehavior}
function ActivatedAbility.RegisterType(args)
    args.index = #ActivatedAbility.Types+1
    local doc = ActivatedAbility.TypesById[args.id]
    if doc ~= nil then
        args.index = doc.index
    end

    ActivatedAbility.Types[args.index] = args
    ActivatedAbility.TypesById[args.id] = args

	ActivatedAbility.OnTypeRegistered()
end

--- Hides an ability type from the UI by id or display text.
--- @param nameOrId string
function ActivatedAbility.SuppressType(nameOrId)
	for i,t in ipairs(ActivatedAbility.Types) do
		if t.id == nameOrId or t.text == nameOrId then
			t.hidden = true
		end
	end
end

--- @return boolean
function ActivatedAbility:HasAttack()
	for _,behavior in ipairs(self.behaviors) do
		if behavior.typeName == "ActivatedAbilityAttackBehavior" then
			return true
		end
	end

	return false
end

--- @return boolean
function ActivatedAbility:HasSavingThrow()
	for _,behavior in ipairs(self.behaviors) do
		if behavior:HasSavingThrow() then
			return true
		end
	end
end

--- @return boolean
function ActivatedAbilityBehavior:HasSavingThrow()
	return self:try_get("dc", "none") ~= "none"
end

--- @return table[]
function ActivatedAbility:GetShareableRolls()
	local result = {}
	for _,behavior in ipairs(self.behaviors) do
		behavior:FillShareableRolls(result)
	end
	return result
end

function ActivatedAbilityBehavior:FillShareableRolls(result)
end

ActivatedAbility.GetTypesWithoutMono = function()
    local result = {}
    for _,t in ipairs(ActivatedAbility.Types) do
        if not t.mono then
            result[#result+1] = t
        end
    end

    return result
end


ActivatedAbility.RegisterType
{
	id = 'ongoingEffect',
	text = 'Apply Ongoing Effect',
	createBehavior = function()
		return ActivatedAbilityApplyOngoingEffectBehavior.new{
		}
	end
}

ActivatedAbility.RegisterType
{
	id = 'attack',
	text = 'Attack',
	createBehavior = function()
		return ActivatedAbilityAttackBehavior.new{
			roll = "1d6",
		}
	end
}

ActivatedAbility.RegisterType
{
	id = 'aura',
	text = 'Create Aura',
	createBehavior = function()
		return ActivatedAbilityAuraBehavior.new{
		}
	end
}

ActivatedAbility.RegisterType
{
	id = 'heal',
	text = 'Healing',
	createBehavior = function()
		return ActivatedAbilityHealBehavior.new{
			roll = "1d6",
		}
	end
}

ActivatedAbility.RegisterType
{
	id = 'augmentedability',
	text = 'Augmented Ability',
	mono = true, --must be alone on an ability.
	createBehavior = function()

		local modifier = CharacterModifier.new{
			behavior = "modifyability",
			description = "",
			guid = dmhub.GenerateGuid(),
			name = "Modify Attack",
			source = "",
			cannotModifyAction = true,
		}

		CharacterModifier.TypeInfo.modifyability.init(modifier)

		return ActivatedAbilityAugmentedAbilityBehavior.new{
			modifier = modifier,
		}

	end
}

ActivatedAbility.RegisterType
{
	id = 'castspell',
	text = 'Cast Spell',
	mono = true, --must be used alone on an ability.
	createBehavior = function()

		local modifier = CharacterModifier.new{
			behavior = "modifyability",
			description = "",
			guid = dmhub.GenerateGuid(),
			name = "Modify Attack",
			source = "",
			cannotModifyAction = true,
		}

		CharacterModifier.TypeInfo.modifyability.init(modifier)

		return ActivatedAbilityCastSpellBehavior.new{
			modifier = modifier,
			spells = {},
		}

	end,
}

ActivatedAbility.RegisterType
{
	id = 'contestedattack',
	text = 'Contested Attack',
	createBehavior = function()
		return ActivatedAbilityContestedAttackBehavior.new{
			attackAttributes = {"str"},
			defenseAttributes = {"str"},
		}
	end
}

ActivatedAbility.RegisterType
{
	id = 'forcedmovement',
	text = 'Forced Movement',
	createBehavior = function()
		return ActivatedAbilityForcedMovementBehavior.new{
			distance = tostring(dmhub.unitsPerSquare),
		}
	end
}




ActivatedAbility.numTargets = "1"

ActivatedAbility.usageLimitOptions = {
	resourceRefreshType = 'none',
	charges = "0",
	resourceid = "none",
}

function ActivatedAbility.StandardArgs()
	return {
		guid = dmhub.GenerateGuid(),
		iconid = "ui-icons/skills/1.png",
		name = 'New Ability',
		description = '',
		modifiers = {},
		display = {
			bgcolor = '#ffffffff',
			hueshift = 0,
			saturation = 1,
			brightness = 1,
		},

		range = dmhub.unitsPerSquare,
		numTargets = "1",
		repeatTargets = false,

		abilityType = 'none',
		targetType = 'self',

		behaviors = {},
	}
end

--- Creates a new ActivatedAbility with optional field overrides.
--- @param options nil|table Field overrides to apply on top of StandardArgs defaults.
--- @return ActivatedAbility
function ActivatedAbility.Create(options)

	local args = ActivatedAbility.StandardArgs()

	if options ~= nil then
		for k,v in pairs(options) do
			args[k] = v
		end
	end

	return ActivatedAbility.new(args)
end

--- Returns the unique id of this ability (uses guid or id field).
--- @return nil|string
function ActivatedAbility:GetID()
	--ugh, spells and abilities have a different field for their id.
	return self:try_get("guid", self:try_get("id"))
end

--- Returns the id of the primary condition inflicted by this ability (from its first behavior).
--- Creatures immune to this condition are unaffected; creatures with advantage on saves against it get advantage.
--- @return nil|string
--the ID of the primary condition that this spell is trying to inflict.
--Creatures immune from the primary condition will not be affected by the spell.
--Creatures with advantage on saving throws against the primary condition will
--get advantage on their saving throw against it.
function ActivatedAbility:PrimaryConditionID()
	local behaviors = self:try_get("behaviors", {})
	if #behaviors >= 1 then
		return behaviors[1]:ConditionID()
	end

	return nil
end

--- @param caster creature
--- @return boolean
function ActivatedAbility:AffectedByCover(caster)
	local behaviors = self:try_get("behaviors", {})
	for _,behavior in ipairs(behaviors) do
		if behavior:AffectedByCover(caster, self) then
			return true
		end
	end

	return false
end

--- @return nil|ActivatedAbilityAttackBehavior
function ActivatedAbility:GetAttackBehavior()
	for _,behavior in ipairs(self.behaviors) do
		if behavior.summary == "Attack" then
			return behavior
		end
	end

	return nil
end

--- @param casterToken CharacterToken
--- @param behavior nil|ActivatedAbilityBehavior
--- @param symbols table
--- @return number
function ActivatedAbility:SaveDC(casterToken, behavior, symbols)
	if behavior ~= nil and behavior:has_key("dcvalue") and behavior.dcvalue ~= '' then
		return ExecuteGoblinScript(behavior.dcvalue, casterToken.properties:LookupSymbol(symbols), 0, string.format("Calculate DC: %s", self.name))
	end

	local result = casterToken.properties:SpellSaveDC(self)
	return result
end

--- @param casterCreature nil|creature
--- @return string
function ActivatedAbility:DescribeAOE(casterCreature)
	if type(self.range) == "string" and string.lower(self.range) == "touch" then
		return "Touch"
	end
	
	if self.targetType == "self" then
		return "Self"
	end

	local range = self:GetRange(casterCreature)

	if self.targetType == "all" then
		return string.format("Within %s%s", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
	end

	local radius = self:GetRadius(casterCreature, {})


	if self.targetType == "target" then
		return string.format("%s%s", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
	end

	if self.targetType == "line" then
		return string.format("%sx%s%s Line", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.Abbrev())
	end

	if self.targetType == "cone" then
		return string.format("%s%s Cone", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
	end

	if self.targetType == "cube" then
		return string.format("%s%s (%s%s Cube)", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev(), MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.Abbrev())
	end

	if self.targetType == "sphere" then
		return string.format("%s%s (%s%s Sphere)", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev(), MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.Abbrev())
	end

	if self.targetType == "cylinder" then
		return string.format("%s%s (%s%s Cylinder)", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev(), MeasurementSystem.NativeToDisplayString(radius), MeasurementSystem.Abbrev())
	end

	if self.targetType == "emptyspace" then
		return string.format("%s%s (Empty Space)", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
	end

	if self.targetType == "emptyspacefriend" then
		return string.format("%s%s (Empty Space or Friend)", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
	end

	if self.targetType == "anyspace" then
		return string.format("%s%s (Any Space)", MeasurementSystem.NativeToDisplayString(range), MeasurementSystem.Abbrev())
	end

	return '--'
end

--- Returns the token to use as the origin for range calculations (invoker override or caster).
--- @param token CharacterToken
--- @return CharacterToken
function ActivatedAbility:GetRangeSource(token)
	if self:has_key("invoker") and self:try_get("rangeUsesInvoker") then
		local tok = dmhub.LookupToken(self.invoker)

		if tok ~= nil then
			return tok
		end
	end

	return token
end

--- Returns the AoE radius in world units (evaluates GoblinScript if needed).
--- @param casterCreature nil|creature
--- @param castingSymbols nil|table
--- @return number
function ActivatedAbility:GetRadius(casterCreature, castingSymbols)
    local radius = self:try_get("radius")
    if tonumber(radius) ~= nil then
        return tonumber(radius)
    end

    if radius == nil then
        return 0
    end

	castingSymbols = castingSymbols or {}
	local symbols = {
		ability = self,
		mode = castingSymbols.mode or 1,
		charges = castingSymbols.charges or 1,
		upcast = castingSymbols.upcast or 0,
	}

	local caster = casterCreature or self:try_get("_tmp_boundCaster")
    if caster == nil then
        if type(radius) == "string" then
            local m = regex.MatchGroups(radius, "^(?<range>%d+)")
            if m ~= nil then
                return tonumber(m.range)
            end
        end

        return 0
    end
	return ExecuteGoblinScript(radius, caster:LookupSymbol(symbols))
end

--- @param casterCreature Creature
--- @param castingSymbols table
--- @param selfRange nil|string|number
--- @return number
function ActivatedAbility:GetRange(casterCreature, castingSymbols, selfRange)
	if selfRange == nil or selfRange == "" then
		selfRange = self.range
	end

	local result = nil
	if type(selfRange) == "string" and string.lower(selfRange) == "touch" then
		result = dmhub.unitsPerSquare
	elseif type(selfRange) == "number" then
		result = selfRange
	elseif type(selfRange) == "string" then
		local n = tonumber(selfRange)
		if n ~= nil then
			result = n
		else
			local _,_,range = string.find(selfRange, "^(%d+) feet$")
			if range ~= nil then
				result = tonumber(range)
			end
		end
	end

	if result == nil then
		local caster = casterCreature or self:try_get("_tmp_boundCaster")
		if caster == nil then
			if type(selfRange) == "string" then
				local _,_,range = string.find(selfRange, "^(%d+)")
				if range ~= nil then
					result = tonumber(range)
				end
			end

			--this means we really couldn't work out the range.
			if result == nil then
				result = dmhub.unitsPerSquare
			end
		else

			castingSymbols = castingSymbols or {}
			local symbols = {
				ability = self,
				mode = castingSymbols.mode or 1,
				charges = castingSymbols.charges or 1,
				upcast = castingSymbols.upcast or 0,
			}
			result = ExecuteGoblinScript(selfRange, caster:LookupSymbol(symbols))
		end
	end

	if result == nil then
		result = dmhub.unitsPerSquare
	end

	return result
end

function ActivatedAbility:GetRangeDisadvantage(casterCreature, castingSymbols)
	return self:GetRange(casterCreature, castingSymbols, self.rangeDisadvantage)
end

--- @param casterToken CharacterToken
--- @param symbols table
--- @return integer
function ActivatedAbility:GetNumTargets(casterToken, symbols)
    symbols = symbols or {}
    if symbols.numtargetsoverride ~= nil then
        return symbols.numtargetsoverride
    end
	if self.targetType ~= "target" and self.targetType ~= "emptyspace" and self.targetType ~= "anyspace" then
		return 1
	end

    if casterToken == nil then
        if tonumber(self.numTargets) ~= nil then
            return tonumber(self.numTargets)
        end

        local m = regex.MatchGroups(self.numTargets, "^(?<num>%d+)")
        if m ~= nil then
            return tonumber(m.num)
        end

        return 1
    end
	local targets = ExecuteGoblinScript(self.numTargets, casterToken.properties:LookupSymbol(symbols))
	return targets
end

--- May return a Loc table or nil. If not nil, it will describe the targeted shape.
--- @param casterToken CharacterToken
--- @param range number
--- @param symbols table
--- @return nil|Loc
function ActivatedAbility:CustomTargetShape(casterToken, range, symbols)
    return nil
end

--- @return boolean
function ActivatedAbility:IsForcedMovement()
    return self:try_get("targeting") == "straightline"
end

--- @return nil|string
function ActivatedAbility:ForcedMovementType()
    if self:IsForcedMovement() then
        return self:try_get("forcedMovement", "slide")
    else
        return nil
    end
end

--- @return boolean
function ActivatedAbility:VerticalTargeting()
    local forcedMovement = self:try_get("forcedMovement")
    if string.starts_with(forcedMovement, "vertical_") then
        return true
    end

    return false
end

function ActivatedAbility:TargetLocMaxElevationChangeFunction(casterToken, symbols)
    if self:try_get("targeting") == "straightline" and (self.targetType == "emptyspace" or self.targetType == "anyspace") and symbols.invoker ~= nil then
        local invoker = symbols.invoker
        if type(invoker) == "function" then
            invoker = invoker("self")
        end

        if type(invoker) == "table" then
            invoker = dmhub.LookupToken(invoker)
        else
            invoker = nil
        end

        if invoker ~= nil then
            local startingAltitudeDelta = casterToken.loc.altitude - invoker.loc.altitude

            local originLoc = symbols.forcedMovementOrigin

            if originLoc == nil then
                originLoc = invoker.loc
            end


            local forcedMovement = symbols.forcedmovement or self:try_get("forcedMovement")
            if originLoc ~= nil then
 
                local distanceStart = math.max(startingAltitudeDelta, originLoc:DistanceInTiles(casterToken.loc))

                if forcedMovement == "vertical_push" or forcedMovement == "vertical_pull" then
                    return function(loc)
                        local min = nil
                        local max = nil
                        for i=-symbols.range,symbols.range do
                            local moveDistance = loc:DistanceInTiles(casterToken.loc)
                            local distanceFromPusher = loc:DistanceInTiles(originLoc)
                            local altitudeDelta = (casterToken.loc.altitude + i) - invoker.loc.altitude
                            distanceFromPusher = math.max(altitudeDelta, distanceFromPusher)
                            moveDistance = math.max(moveDistance, math.abs(i))

                            local allowed
                            if forcedMovement == "vertical_pull" then
                                allowed = distanceFromPusher <= (distanceStart - moveDistance)
                            else
                                allowed = distanceFromPusher >= (distanceStart + moveDistance)
                            end

                            if allowed then
                                if min == nil then
                                    min = i
                                end

                                max = i
                            end

                        end
                        return (min or 0), (max or 0)
                    end
                elseif forcedMovement == "vertical_slide" then
                    return function(loc)
                        return -symbols.range, symbols.range
                    end
                end
            end
        end
    end

    return nil

end

--returns a predicate function saying if a target loc passes the filter.
function ActivatedAbility:TargetLocPassesFilterPredicate(casterToken, symbols)

    print("MARKER:: PASSES FILTER...")
    if self:try_get("targeting") == "straightline" and (self.targetType == "emptyspace" or self.targetType == "anyspace") and symbols.invoker ~= nil then
        local originLoc = symbols.forcedMovementOrigin

        if originLoc == nil then
            local invoker = symbols.invoker
            if type(invoker) == "function" then
                invoker = invoker("self")
            end

            if type(invoker) == "table" then
                invoker = dmhub.LookupToken(invoker)
            else
                invoker = nil
            end
            
            if invoker ~= nil then
                originLoc = invoker.loc
            end
        end

        if originLoc ~= nil then
            local distanceStart = originLoc:DistanceInTiles(casterToken.loc)
            local forcedMovement = symbols.forcedmovement or self:try_get("forcedMovement")
            if forcedMovement == "push" or forcedMovement == "pull" or forcedMovement == "vertical_push" or forcedMovement == "vertical_pull" then
                return function(loc)
                    local moveDistance = loc:DistanceInTiles(casterToken.loc)
                    local distanceFromPusher = loc:DistanceInTiles(originLoc)
                    if forcedMovement == "push" or forcedMovement == "vertical_push" then
                        return distanceFromPusher >= (distanceStart + moveDistance)
                    else
                        return distanceFromPusher <= (distanceStart - moveDistance)
                    end
                end
            end
        end
    end

    if self.targetType == "emptyspace" then
		if symbols.compeltoward ~= nil then
			print("MARKER:: COMPEL...")
			local tok = dmhub.LookupToken(symbols.compeltoward)
			if tok ~= nil then
				return function(loc) 
					local distanceNow = tok:Distance(casterToken.loc)
					local distanceThen = tok:Distance(loc)
					local distanceMoved = loc:DistanceInTiles(casterToken.loc)
					local movedCloser = distanceNow - distanceThen
					return movedCloser >= distanceMoved
				end
			end
		elseif symbols.compeladjacent ~= nil then
			print("MARKER:: COMPEL ADJACENT...")
			local tok = dmhub.LookupToken(symbols.compeladjacent)
			if tok ~= nil then
				return function(loc) 
					return loc:DistanceInTiles(tok.loc) <= MeasurementSystem.NativeSystem().tileSize
				end
			end

		end
    end

	if (self.targetType ~= 'emptyspace' and self.targetType ~= 'anyspace') or self.targetFilter == "" then
        print("MARKER:: ALL TRUE")
		return function(loc) return true end
	end

	local symbolsCopy = shallow_copy_table(symbols)

    print("MARKER:: GENERAL", self.targetType, "X (", self.targetFilter, ")")
	return function(loc)
		local symbolizedLoc = Loc.Create(loc)
		symbolsCopy.target = symbolizedLoc

		local result = GoblinScriptTrue(ExecuteGoblinScript(self.targetFilter, casterToken.properties:LookupSymbol(symbolsCopy), 0, string.format("Target location filter for %s", self.name)))
		return result
	end
end


function ActivatedAbility:AbilityFilterFailureMessage(casterCreature)
    local filters = self:try_get("abilityFilters", {})

    for _,filter in ipairs(filters) do
        local result = ExecuteGoblinScript(filter.formula, casterCreature:LookupSymbol{}, 1, "Test ability filter")
        if not GoblinScriptTrue(result) then
            return StringInterpolateGoblinScript(filter.reason, casterCreature)
        end
    end

    return nil
end


--- @param casterToken CharacterToken
--- @param targetToken CharacterToken
--- @param symbols table
--- @param filterOverride nil|string
--- @return boolean, nil|string The first value is true if the target passes the filter, false otherwise. The second value can be a reason why the target does not match the filter.
function ActivatedAbility:TargetPassesFilter(casterToken, targetToken, symbols, filterOverride)

	local conditionid = self:PrimaryConditionID()

	--if spell cannot target self.
	if (not self.selfTarget) and casterToken.properties == targetToken.properties then
		return false
	end

	if not GameSystem.AllowTargeting(casterToken, targetToken, self) then
		return false
	end

	if targetToken.properties:CalculateNamedCustomAttribute("Untargetable") > 0 then
		return false
	end

    if self.targetType == "all" and casterToken:GetLineOfSight(targetToken) <= 0 then
        return false
    elseif symbols.targetArea ~= nil and targetToken:GetLineOfSight(symbols.targetArea.origin) <= 0 then
        return false
    end

    if self.targetAllegiance == "dead" then
        print("Dead:: isCorpse =", targetToken.isCorpse)
        if not targetToken.isCorpse then
            return false
        end

        print("Dead:: Trying target...")

        local objectInstance = targetToken.objectInstance

        if objectInstance == nil then
            print("Dead:: No object instance")
            return false
        end

        local corpseComponent = objectInstance:GetComponent("Corpse")
        if corpseComponent == nil then
            print("Dead:: No corpse component")
            return false
        end

        targetToken = corpseComponent.properties:DeadCreatureToken()
        print("Dead:: targetToken =", targetToken)
        if targetToken == nil then
            return false
        end
    else

        if (not self.objectTarget) and targetToken.isObject then
            return false
        elseif self.objectTarget and targetToken.isObject and (not targetToken.isAttackableObject) then
            return false
        end

        if self.targetAllegiance == "none" and (not targetToken.isObject) then
            return false
        end

        if self.targetAllegiance == 'enemy' and casterToken:IsFriend(targetToken) and (not targetToken.isObject) then
            return false
        end

        if self.targetAllegiance == 'ally' and (not casterToken:IsFriend(targetToken)) and (not targetToken.isObject) then
            return false
        end
    end

    if filterOverride == nil then
        for _,filter in ipairs(self:try_get("customTargetFilters", {})) do
            local passes = self:TargetPassesFilter(casterToken, targetToken, symbols, filter)
            if not passes then
                return false
            end
        end
    end

    local filter = filterOverride or self.targetFilter
    local reasonedFilters = self:try_get("reasonedFilters", {})
    if filter == "" and #reasonedFilters == 0 then
        return true
    end

    local caster = GenerateSymbols(casterToken.properties)

    symbols = table.shallow_copy(symbols or {})
    symbols.invoker = symbols.invoker or caster
    symbols.caster = caster
    symbols.enemy = not casterToken:IsFriend(targetToken)
	symbols.target = GenerateSymbols(targetToken.properties)

	local result = filter == "" or GoblinScriptTrue(ExecuteGoblinScript(filter, targetToken.properties:LookupSymbol(symbols), 0, string.format("Target filter for %s", self.name)))
    if not result then
        return false
    end

    for _,reasonedFilter in ipairs(reasonedFilters) do
        local result = GoblinScriptTrue(ExecuteGoblinScript(reasonedFilter.formula, targetToken.properties:LookupSymbol(symbols), 0, string.format("Target reasoned filter for %s", self.name)))
        if not result then
            return false, StringInterpolateGoblinScript(reasonedFilter.reason, symbols)
        end
    end

    return result
end

--- @return boolean
function ActivatedAbility:CanDuplicateTargets()
	return self.repeatTargets
end

--- @param casterToken CharacterToken
--- @param targets AbilityTarget[]
--- @param symbols table
--- @return boolean
function ActivatedAbility:CanSelectMoreTargets(casterToken, targets, symbols)
	local numTargets = self:GetNumTargets(casterToken, symbols)
	if self.sequentialTargeting and #targets == 1 then
		return false
	end
    print("ABILITY::", self.name, "MORE TARGETS =", numTargets, ">", #targets)
	return numTargets > #targets
end

--- @param casterToken CharacterToken
--- @param targets AbilityTarget[]
--- @param symbols Symbols
--- @return boolean
function ActivatedAbility:CanCastAsIs(casterToken, targets, symbols)
	if self.targetType == 'all' or self.targetType == 'map' or self.targetType == 'areatemplate' then
		return true
	end
	if self.targetType == 'self' then
		return true
	end
	local numTargets = self:GetNumTargets(casterToken, symbols)
	if self.sequentialTargeting and #targets == 1 then
		return true
	end
	return numTargets == 0 or #targets > 0
end

--- @param casterToken CharacterToken
--- @param targets AbilityTargets[]
--- @param symbols Symbols
--- @param synthesizedSpells nil|(ActivatedAbility[])
--- @return string
function ActivatedAbility:PromptText(casterToken, targets, symbols, synthesizedSpells)
	if self:try_get("promptOverride") ~= nil then
		return self.promptOverride
	end

	if synthesizedSpells ~= nil then
		if #synthesizedSpells == 0 then
			return "No valid abilities"
		else
			return "Choose an ability"
		end
	end

	if self:try_get("attackOverride") ~= nil and self.attackOverride:try_get("ammoType") ~= nil then
		return ""
	end

	if self.targetType == 'all' then
		return ""
	end

	local numTargets = self:GetNumTargets(casterToken, symbols)
	if numTargets == 0 then
		return ""
	end

	if numTargets == 1 and #targets == 0 then
		return "Choose a target"
	end

	if numTargets >= 99 then
		return "Choose Targets"
	end

	if self.sequentialTargeting and symbols.targetnumber ~= nil and symbols.targetcount ~= nil then
		return string.format("Choose Target %d/%d", symbols.targetnumber, symbols.targetcount)
	end

	return string.format("Choose Target %d/%d", #targets+1, numTargets)
	
end

--- if this ability can be cast with these targets.
--- @param casterToken CharacterToken
--- @param targets AbilityTarget[]
--- @param symbols Symbols
--- @return boolean
function ActivatedAbility:CanCast(casterToken, targets, symbols)
	local numTargets = self:GetNumTargets(casterToken, symbols)
	if numTargets == 0 then
		return #targets == 0
	else
		return #targets > 0 and #targets <= numTargets
	end
end

--- @return integer
function ActivatedAbility:NumberOfResources()
	return 1
end

--- @return string|nil
function ActivatedAbility:ActionResource()
	if self:has_key("actionResourceId") then
		if self.actionResourceId == 'none' then
			return nil
		end

		return self.actionResourceId
	end

	if self.castingTime == "action" then
		return "standardAction"
	elseif self.castingTime == "bonus" then
		return "bonusAction"
	elseif self.castingTime == "reaction" then
		return "reaction"
	end

	return nil
end

--- @return boolean
function ActivatedAbility:MultiCharge()
	return self.usageLimitOptions.multicharge == true
end

--given a cost being paid to use this ability, calculates the "Dice Faces" symbol.
function ActivatedAbility.CalculateDiceFaces(cost)
	if cost ~= nil then
		local resourceTable = dmhub.GetTable("characterResources")
		for i,entry in ipairs(cost.details) do
			local resource = resourceTable[entry.cost]
			if resource ~= nil and resource.diceType ~= "none" then
				if entry.paymentOptions[1].resourceid == entry.cost then
					return tonumber(resource.diceType) or 0
				elseif #entry.paymentOptions == 0 then
					--we generally allow expended options to just cast if they are forced
					--so return the expended option if there is one.
					if #entry.expendedOptions > 0 then
						local otherResource = resourceTable[entry.expendedOptions[1].resourceid]
						return tonumber(otherResource.diceType) or 0
					end

					return tonumber(resource.diceType)
				else
					local otherResource = resourceTable[entry.paymentOptions[1].resourceid]
					return tonumber(otherResource.diceType) or 0
				end
			end
		end
	end

	return 0
end

--- Returns a temporary clone of this ability switched to mode i, or self if unchanged.
--- @param i integer
--- @return ActivatedAbility
function ActivatedAbility:SwitchModes(i)
    if (not self:has_key("modeList")) or self.modeList[i] == nil or (not self.modeList[i].hasAbility) or self.modeList[i].variation == nil then
        return self
    end

    local result = self.modeList[i].variation:MakeTemporaryClone()
    result.OnBeginCast = self:try_get("OnBeginCast")
    result.OnFinishCast = self:try_get("OnFinishCast")
    result.multipleModes = self.multipleModes

    -- Preserve invoke-specific fields through mode switch.
    result.invoker = self:try_get("invoker")
    result.skippable = self:try_get("skippable")
    result.countsAsCast = self:try_get("countsAsCast")
    result.promptOverride = self:try_get("promptOverride")

    if result.resourceCost == "none" then
        result.resourceCost = self.resourceCost
        result.resourceNumber = self.resourceNumber
    end

    result.actionNumber = self.actionNumber
    result.actionResourceId = self.actionResourceId
    local modeList = DeepCopy(self.modeList)
    for i=1,#modeList do
        if (not modeList[i].hasAbility) or modeList[i].variation == nil then
            modeList[i].hasAbility = true
            modeList[i].variation = self
        end
    end

    result.modeList = modeList
    return result
end


--- Returns the number of action resources this ability costs (evaluates GoblinScript if needed).
--- @param caster nil|creature
--- @param symbols nil|table
--- @return number
function ActivatedAbility:GetNumberOfActionsCost(caster, symbols)
	if type(self.actionNumber) == "number" then
		return self.actionNumber
	end

	if caster ~= nil then
		local result = ExecuteGoblinScript(self.actionNumber, caster:LookupSymbol(symbols or {mode = 1}), 1)
		return result
	else
		if tonumber(self.actionNumber) ~= nil then
			return tonumber(self.actionNumber)
		end
	end

	return 1
end

--- @return number
function ActivatedAbility:DefaultCharges()
	if self.channeledResource ~= "none" then
		return 0
	else
		return 1
	end
end

--- @param caster creature
--- @param symbols nil|table
--- @return number
function ActivatedAbility:MaxChannel(caster, symbols)
	local maxChannel = self:try_get("maxChannel", "")
	if trim(maxChannel) == "" then
		return 999
	end

	return ExecuteGoblinScript(maxChannel, caster:LookupSymbol(symbols or {mode = 1}), 999)
end

function ActivatedAbility:CommitToPaying(casterToken, options)
    options.pay = true
	self:FireUseAbility(casterToken, options)
end

function ActivatedAbility:FireUseAbility(casterToken, options)
	if (not options.firedUseAbility) and self:CountsAsRegularAbilityCast() then
		options.firedUseAbility = true

		local persistence = self:Persistence()
		if persistence ~= nil and persistence.enabled and dmhub.initiativeQueue ~= nil and (not dmhub.initiativeQueue.hidden) then
			local q = dmhub.initiativeQueue
			
			local targets = {}
			for _,target in ipairs(options.targets or {}) do
				if target.token ~= nil then
					targets[#targets+1] = target.token.charid
				end
			end

			local newEntry = Persistence.new{
				guid = dmhub.GenerateGuid(),
				combatid = q.guid,
				abilityName = self.name,
				ability = self,
				targets = targets,
				cost = persistence.cost or 1,
				round = q.round,
				turn = q.turn,
			}

			casterToken:ModifyProperties{
				description = "Persistent Ability",
				undoable = false,

				execute = function()
					local persistenceEntries = casterToken.properties:get_or_add("persistentAbilities", {})
					for i=#persistenceEntries,1,-1 do
						if persistenceEntries[i].combatid ~= q.guid then
							table.remove(persistenceEntries, i)
						end
					end

					persistenceEntries[#persistenceEntries+1] = newEntry
				end,
			}
		end

        casterToken.properties:DispatchEvent("useability", {usedability = self, cast = options.cast})

        for _,target in ipairs(options.targets or {}) do
            if target.token ~= nil then
                casterToken.properties:DispatchEvent("targetwithability", {usedability = self, cast = options.cast, target = target.token.properties})
            end
        end
	end
end

--returns a { canAfford = bool, moveCost (optional) = number, cannotMove (optional) = true, details = list, consumables (optional) = { itemid -> quantity }, outOfAmmo (optional) = true }, each item in the list representing a cost that needs to be paid.
--an item in the details list is the form { cost = string resourceid, quantity = (optional) number, canAfford = bool, paymentOptions = {{resourceid = string, quantity = number}}, expendedOptions = {{resourceid = string, quantity = number}}, refreshType (optional) = string resource refresh frequency, description = optional string describing resource available/max, maxCharges (optional) = int, availableCharges (optional) = int }
--the cost gives the listed resource id cost, but paymentOptions is a list of resources the token has which it could use, in preferred order.
--expendedOptions is a list of resources the token has expended which could normally be used to pay.
function ActivatedAbility:GetCost(casterToken, options)
	options = options or {}

	options.charges = options.charges or self:DefaultCharges()

	if self.usesSpellSlots then
		return Spell.GetCost(self, casterToken, options)
	end

	local creature = casterToken:GetCreature()
	if creature == nil then
		return { canAfford = false, details = {}}
	end
	local resourcesTable = dmhub.GetTable("characterResources")
	local resourcesAvailable = creature:GetResources()

	local result = { canAfford = true, details = {} }
	
	if self:has_key("moveCost") then
		local moveCost = math.floor(creature:CurrentMovementSpeed()*self.moveCost)
		result.moveCost = moveCost or nil

		local currentMoveSpeed = creature:CurrentMovementSpeed()
		if creature:DistanceMovedThisTurnInFeet() + moveCost > currentMoveSpeed or currentMoveSpeed <= 0 then
			canAfford = false
			result.cannotMove = true
		end
	end

	if self:has_key("consumables") then
		result.consumables = self.consumables
	elseif self:has_key("attackOverride") and self.attackOverride:has_key("consumeAmmo") then
		result.consumables = self.attackOverride.consumeAmmo
	end

	if self:has_key("attackOverride") and self.attackOverride:try_get("outOfAmmo") then
		result.outOfAmmo = true
		result.canAfford = false
	end

	local actionResource = self:ActionResource()
	if actionResource ~= nil and actionResource ~= "none" and resourcesTable[actionResource] ~= nil then
		local max = resourcesAvailable[actionResource] or 0
		local usage = creature:GetResourceUsage(actionResource, "round")
		local available = max - usage

		local numberOfActions = self:GetNumberOfActionsCost(creature, { mode = (options or {}).mode or 1 })

		local canAfford = available >= numberOfActions
		result.canAfford = result.canAfford and canAfford

		result.details[#result.details+1] = {
			cost = actionResource,
			quantity = numberOfActions,
			canAfford = result.canAfford,
			paymentOptions = cond(result.canAfford, {{resourceid = actionResource, quantity = numberOfActions}}, {}),
			expendedOptions = cond(result.canAfford, {}, {{resourceid = actionResource, quantity = numberOfActions}}),
		}
	end

	if self.usageLimitOptions.resourceRefreshType ~= 'none' then
		local usage = creature:GetResourceUsage(self.usageLimitOptions.resourceid, self.usageLimitOptions.resourceRefreshType)
		local maxCharges = ExecuteGoblinScript(self.usageLimitOptions.charges, creature:LookupSymbol(), 0)
		local hasResources = usage < maxCharges
		local availableCharges = math.max(0, maxCharges - usage)
		result.details[#result.details+1] = {
			cost = self.usageLimitOptions.resourceid,
			canAfford = hasResources,
			maxCharges = maxCharges,
			quantity = options.charges,
			availableCharges = availableCharges,
			description = string.format("%d/%d", availableCharges, maxCharges),
			refreshType = self.usageLimitOptions.resourceRefreshType,
			paymentOptions = cond(hasResources, {{resourceid = self.usageLimitOptions.resourceid, quantity = options.charges}}, {}),
			expendedOptions = cond(not hasResources, {{resourceid = self.usageLimitOptions.resourceid, quantity = options.charges}}, {}),
		}

		result.canAfford = result.canAfford and hasResources
	end

	if self.channeledResource ~= "none" and options.charges > 0 then
		local resourceInfo = resourcesTable[self.channeledResource]
		if resourceInfo ~= nil then
			local max = resourcesAvailable[self.channeledResource] or 0
			local usage = creature:GetResourceUsage(self.channeledResource, resourceInfo.usageLimit)
			local available = max - usage
            if self.resourceCost == self.channeledResource then
				local mode = options.mode or 1
                local resourceNum = ExecuteGoblinScript(self.resourceNumber, casterToken.properties:LookupSymbol{mode = mode}, 0, "Determine resource number for " .. self.name)
                available = available - resourceNum
            end
            local resourceCost = self.channelIncrement*options.charges
			local canAfford = available >= resourceCost
			result.details[#result.details+1] = {
				cost = self.channeledResource,
				quantity = resourceCost,
				canAfford = canAfford,
				paymentOptions = cond(canAfford, {{resourceid = self.channeledResource, quantity = resourceCost}}, {}),
				expendedOptions = cond(not canAfford, {{resourceid = self.channeledResource, quantity = resourceCost}}, {}),
			}
		end
	end

	if self.resourceCost ~= 'none' then
		local resourceDetails = nil

		--look for any resources of this type in the level progression and spend the first one we find.
		--the common case is for the progression to just be one resource.
		local resourceLevels = CharacterResource.GetLevelProgression(self.resourceCost)
		for levelNum,resourceCost in ipairs(resourceLevels) do
			local resourceInfo = resourcesTable[resourceCost]
			if resourceInfo ~= nil then
				local max = resourcesAvailable[resourceCost] or 0
				local usage = creature:GetResourceUsage(resourceCost, resourceInfo.usageLimit)
				local available = (max - usage) + resourceInfo:AllowResourceBelowZero(casterToken.properties)

				local mode = options.mode or 1
                local resourceNum = ExecuteGoblinScript(self.resourceNumber, casterToken.properties:LookupSymbol{mode = mode}, 0, "Determine resource number for " .. self.name)

				if resourceNum == 0 then
					resourceDetails = nil
					break
				end
				local canAfford = available >= resourceNum

				--note that we set resourceDetails to the first found, but prefer to
				--set to the highest resource we have, and being affordable we short-circuit immediately.
				if resourceDetails == nil or max > 0 or canAfford then
					resourceDetails = {
						cost = self.resourceCost,
						quantity = resourceNum,
						canAfford = canAfford,
						paymentOptions = cond(canAfford, {{resourceid = resourceCost, quantity = resourceNum}}, {}),
						expendedOptions = cond(not canAfford, {resourceid = resourceCost, quantity = resourceNum}, {}),
					}

					if canAfford then
						break
					end
				end
			end
		end

		if resourceDetails ~= nil then
			result.canAfford = result.canAfford and resourceDetails.canAfford
			result.details[#result.details+1] = resourceDetails
		end
	end

	return result
end

function ActivatedAbility:CanAfford(casterToken, options)
    if casterToken == nil then
        return false
    end
	return self:GetCost(casterToken, options).canAfford
end

function ActivatedAbility.ExpectedResourceConsumptionFromCurrentCast()
    local info = ActivatedAbility.CurrentCastInfo()
    if info == nil or info.options == nil then
        return nil
    end

    if info.options.alreadyPaid then
        return nil
    end

    local result = {}
    local cost = info.options.costOverride or info.ability:GetCost(info.casterToken)
	for i,entry in ipairs(cost.details) do
		if #entry.paymentOptions > 0 then
			local resourceid = entry.paymentOptions[1].resourceid
            local quantity = entry.paymentOptions[1].quantity or 1
            result[resourceid] = (result[resourceid] or 0) + quantity
        end
    end

    return result
end

function ActivatedAbility:WillBecomeStrained(casterToken, options)
    local totalCost = 0
	local cost = options.costOverride or self:GetCost(casterToken)
	for i,entry in ipairs(cost.details) do
		if #entry.paymentOptions > 0 then
			local resourceid = entry.paymentOptions[1].resourceid
            if resourceid == CharacterResource.heroicResourceId then
                local quantity = entry.paymentOptions[1].quantity or 1
                totalCost = totalCost + quantity
            end
        end
    end

    return totalCost > casterToken.properties:GetHeroicOrMaliceResources()
end

function ActivatedAbility:ConsumeResources(casterToken, options)
    local tokens = {casterToken}
    if options.symbols and options.symbols.targetPairs then
        --if this is a minion ability all the minions in the squad use their resource.
        for _,pair in ipairs(options.symbols.targetPairs) do
            local charid = pair.a
            local alreadyAdded = false
            for _,tok in ipairs(tokens) do
                if tok.charid == charid then
                    --this is the caster token, so we don't add it again.
                    alreadyAdded = true
                    break
                end
            end

            if not alreadyAdded then
                local newTok = dmhub.GetTokenById(charid)
                if newTok ~= nil and newTok.valid then
                    tokens[#tokens+1] = newTok
                end
            end
        end
    end

    for _,tok in ipairs(tokens) do
        tok:ModifyProperties{
            description = "Consume Action Resources",

            execute = function()
                local cost = options.costOverride or self:GetCost(tok)
                print("COST:: CONSUME", cost)

                local resourceTable = dmhub.GetTable("characterResources")

                if cost.moveCost then
                    tok.properties:SpendMovementInFeet(cost.moveCost)
                end

                for i,entry in ipairs(cost.details) do
                    if #entry.paymentOptions > 0 then
                        local resourceid = entry.paymentOptions[1].resourceid
                        local refreshType = entry.refreshType
                        if refreshType == nil then
                            local resourceInfo = resourceTable[resourceid]
                            if resourceInfo ~= nil then
                                refreshType = resourceInfo.usageLimit
                            end
                        end

                        if refreshType ~= nil then
                            tok.properties:ConsumeResource(resourceid, refreshType, entry.paymentOptions[1].quantity or 1, self.name)
                        end
                    end
                end

                if cost.consumables and not options.meleeAttack then
                    local itemTable = dmhub.GetTable(equipment.tableName)
                    for k,quantity in pairs(cost.consumables) do
                        local itemInfo = itemTable[k]

                        if itemInfo ~= nil and itemInfo:HasCharges() and itemInfo:RemainingCharges() > quantity then
                            itemInfo:ConsumeCharges(quantity)
                            dmhub.SetAndUploadTableItem(equipment.tableName, itemInfo)
                        else
                            tok.properties:GiveItem(k,-quantity)
                        end
                    end
                end
            end
        }
    end
end

function ActivatedAbility:CastInstantPortion(casterToken, targets, options)

    --strained abilities cannot cast instantly, must be in co-routine.
    if self:IsStrain() then
        return true
    end

	local haveNonInstant = false
	for i,behavior in ipairs(self.behaviors) do
		if behavior.instant then
            --I don't think we should filter this just because we're already in a coroutine?
			--if (not options.alreadyInCoroutine) and (not behavior:IsFiltered(self, casterToken, options)) then
			if (not behavior:IsFiltered(self, casterToken, options)) then
				behavior:Cast(self, casterToken, behavior:ApplyToTargets(self, casterToken, targets, options), options)
			end
		else
			haveNonInstant = true
		end
	end

	return haveNonInstant
end

function ActivatedAbility:SynthesizeAbilities(creature)
	
	if #self.behaviors > 0 then
		return self.behaviors[1]:SynthesizeAbilities(self, creature)
	end

	return nil
end

function ActivatedAbilityBehavior:SynthesizeAbilities(ability, creature)
	return nil
end

function ActivatedAbilityCastSpellBehavior:SynthesizeAbilities(ability, creature)

	local typeInfo = CharacterModifier.TypeInfo[self.modifier.behavior]
	local filterFunction = typeInfo.willModifyAbility
	local modifierFunction = typeInfo.modifyAbility

	local spells = self.spells

	local spellsTable = dmhub.GetTable(Spell.tableName)
	local result = {}

	for spellid,_ in pairs(spells) do
		local spellInfo = spellsTable[spellid]
		if spellInfo ~= nil and filterFunction(self.modifier, creature, spellInfo) then
			local synth = DeepCopy(spellInfo)
			synth._tmp_temporaryClone = true

			--we copy some casting time and resource usage aspects of the synthesizer into the synthesized
			--ability. Note that we must take care to make sure that it's still a valid instance of
			--the target type.
			synth.actionResourceId = ability:try_get("actionResourceId")
			synth.actionNumber = ability.actionNumber
			synth.castingTime = ability.castingTime
			synth.castingTimeDuration = ability:try_get("castingTimeDuration")
			synth.resourceCost = ability.resourceCost
			synth.resourceNumber = ability.resourceNumber
			synth.usesSpellSlots = ability.usesSpellSlots

			local consumables = synth:try_get("consumables")
			if ability:has_key("consumables") then
				consumables = consumables or {}
				for k,v in pairs(ability.consumables) do
					consumables[k] = v
				end
			end
			synth.consumables = consumables
			if ability:has_key("level") then
				synth.level = ability.level
			end
			synth = modifierFunction(self.modifier, creature, synth)

			result[#result+1] = synth
		end
	end

	table.sort(result, function(a,b) return a.name < b.name end)

	return result

end

local function DestroyLineOfSight(options)
	if options.markLineOfSight ~= nil then
        if type(options.markLineOfSight) == "table" then
            for _,mark in pairs(options.markLineOfSight) do
                mark:DestroyLineOfSight()
            end
        else
		    options.markLineOfSight:DestroyLineOfSight()
        end
	end

    options.markLineOfSight = nil
end

function ActivatedAbility:RecordAbilityUsage(casterToken, options)
    local params = {
        type = "use_ability",
        userid = dmhub.userid,
        gameid = dmhub.gameid,
        ability = self.name,
        mapid = game.currentMapId,
        loc = casterToken.loc.str,
        usercount = CountLoggedInUsers(),
    }


    if options.symbols.cast ~= nil then
        local cast = options.symbols.cast
        if cast.tier > 0 then
            params.tier = cast.tier
        end

        if cast.damagedealt > 0 then
            params.damage = cast.damagedealt
        end

        if cast.spacesMoved > 0 then
            params.spacesMoved = cast.spacesMoved
        end
    end

    if dmhub.isDM then
        params.director = true
    end

    if casterToken.properties:IsHero() then
        local classInfo = casterToken.properties:GetClass()
        if classInfo ~= nil then
            params.class = classInfo.name
        end

        local ancestryName = casterToken.properties:RaceOrMonsterType()
        params.ancestry = ancestryName

        local subclasses = casterToken.properties:GetSubclasses()
        for i, entry in ipairs(subclasses) do
            if params.subclass then
                params.subclass = params.subclass .. "/" .. entry.name
            else
                params.subclass = entry.name
            end
        end

    elseif casterToken.properties:IsMonster() then
        params.monster = casterToken.properties:try_get("monster_type")
    end

    analytics.Event(params)
end

function ActivatedAbility:FinishCast(casterToken, options)
    if options.executedFinish then
        return
    end
    options.executedFinish = true
    DestroyLineOfSight(options)

	if options ~= nil then
		for i,handler in ipairs(options.OnFinishCastHandlers or {}) do
			handler(self, casterToken, options)
		end

        if options.chatMessage ~= nil then
            if options.atexit then
                options.chatMessage.status = "error"
            elseif options.abort then
                options.chatMessage.status = "aborted"
            else
                options.chatMessage.status = "complete"
                self:RecordAbilityUsage(casterToken, options)
            end

            chat.UpdateCustom(options.chatMessageKey, options.chatMessage)
        end
	end

	if self:has_key("OnFinishCast") then
		self.OnFinishCast(self, options)
	end

	GameSystem.OnEndCastActivatedAbility(casterToken, self, options)
end


--carefully count if we are currently casting an ability.
local g_currentCastingDepth = 0
local g_closeCurrentCastingDepthMeta = {
	__close = function()
		g_currentCastingDepth = g_currentCastingDepth - 1
	print("RemoteInvoke: exit depth = ", g_currentCastingDepth)
	end
}

local function CountCastingDepth()
	g_currentCastingDepth = g_currentCastingDepth + 1
	local result = {}
	setmetatable(result, g_closeCurrentCastingDepthMeta)
	return result
end

ActivatedAbility.IsCasting = function()
	return g_currentCastingDepth > 0
end

ActivatedAbility.recordTargets = false

--- @class CastActivatedAbilityChatMessage
--- @field ability ActivatedAbility
CastActivatedAbilityChatMessage = RegisterGameType("CastActivatedAbilityChatMessage")

CastActivatedAbilityChatMessage.status = "complete"

function CastActivatedAbilityChatMessage.Render(self, message)
    local resultPanel

    local m_status = self.status

    local token = self:GetCasterToken()
    local ability = self:GetAbility()

    if token == nil or (not token.valid) or ability == nil then
        return gui.Panel{
            width = 0, height = 0,
        }
    end

    local targetTokenPanels = {}
    for _,tok in ipairs(self:GetTargetTokens()) do
        targetTokenPanels[#targetTokenPanels+1] = gui.CreateTokenImage(tok, {
            width = 32,
            height = 32,
            valign = "center",
            halign = "left",

            interactable = true,
            hover = function(element)
                local text = string.format("<b>%s</b>", tok.name)
                local messages = self:try_get("tokenMessages", {})
                local messageLog = messages[tok.charid] or {}
                if messageLog ~= nil then
                    for _,msg in ipairs(messageLog) do
                        text = text .. "\n" .. msg
                    end
                end
                gui.Tooltip(text)(element)
            end
        })
    end

    local m_statusCount = 0
    local statusLabel = gui.Label{
        floating = true,
        fontSize = 12,
        width = 70,
        height = "auto",
        halign = "right",
        valign = "top",
        text = "Executing",
        textAlignment = "left",

        think = function(element)
            m_statusCount = m_statusCount + 1
            if m_statusCount > 3 then
                m_statusCount = 0
            end

            element:FireEvent("updateMessage")
        end,

        updateMessage = function(element)
            if m_status == "executing" then
                local text = "Executing"
                for i=1,m_statusCount do
                    text = text .. "."
                end

                element.text = text
            elseif m_status == "aborted" then
                element.text = "Aborted"
            elseif m_status == "error" then
                element.text = "Error"
            else
                element.text = "Complete"
            end
        end,
    }

    statusLabel:FireEvent("updateMessage")


    local tokenPanel = gui.CreateTokenImage(token,{
        scale = 0.9,
        valign = "center",
        halign = "left",

        interactable = true,
        hover = function(element)
            local tok = token
            local text = string.format("<b>%s</b>", tok.name)
            local messages = self:try_get("tokenMessages", {})
            local messageLog = messages[tok.charid] or {}
            if messageLog ~= nil then
                for _,msg in ipairs(messageLog) do
                    text = text .. "\n" .. msg
                end
            end
            gui.Tooltip(text)(element)
        end
    })


    resultPanel = gui.Panel{
        classes = {"chat-message-panel"},

        data = {
            --advertise that we are willing to adopt roll panels using this castid.
            castid = self:try_get("castid"),
        },
 
        flow = "vertical",
        width = "100%",
        height = "auto",

        refreshMessage = function(element, message)
            self = message.properties
            m_status = message.properties.status
            if m_status == "executing" then
                statusLabel.thinkTime = 0.25
            else
                statusLabel.thinkTime = nil
            end

            statusLabel:FireEvent("updateMessage")
        end,

        gui.Panel{
			classes = {'separator'},
		},

        gui.Panel{

            width = "100%",
            height = "auto",
            flow = "horizontal",

            tokenPanel,

            gui.Panel{
                flow = "vertical",
                width = "100%-80",
                height = "auto",
                halign = "right",
                valign = "top",

                gui.Label{
                    fontSize = 14,
                    width = "auto",
                    height = "auto",
                    maxWidth = 420,
                    halign = "left",
                    valign = "top",
                    text = string.format("<b>%s</b>", ability.name),
                    hover = function(element)
                        local token = self:GetCasterToken()
                        if token == nil then
                            return
                        end
	                    local dock = element:FindParentWithClass("dock")
	                    element.tooltipParent = dock

					    local tooltip = CreateAbilityTooltip(ability, {halign = dock.data.TooltipAlignment(), token = token, width = 540})
                        print("HOVER ABILITY::", ability)
                        element.tooltip = tooltip
                    end,
                },

                statusLabel,

                gui.Panel{
                    width = "50%",
                    height = "auto",
                    halign = "left",
                    flow = "horizontal",
                    wrap = true,
                    children = targetTokenPanels,
                }
            },
        },
    }

    return resultPanel
end

--- @return ActivatedAbility
function CastActivatedAbilityChatMessage:GetAbility()
    return self.ability
end

--- @return CharacterToken
function CastActivatedAbilityChatMessage:GetCasterToken()
    return dmhub.GetCharacterById(self.casterid)
end

--- @return CharacterToken[]
function CastActivatedAbilityChatMessage:GetTargetTokens()
    local result = {}
    for i,tokenid in ipairs(self.targetids) do
        result[#result+1] = dmhub.GetCharacterById(tokenid)
    end
    return result
end

function CastActivatedAbilityChatMessage:RecordTokenMessage(targetToken, message)
    local messages = self:get_or_add("tokenMessages", {})
    local messageLog = messages[targetToken.charid] or {}
    messages[targetToken.charid] = messageLog
    messageLog[#messageLog+1] = message
end

function ActivatedAbility.RecordTokenMessage(targetToken, options, message)
    if options.chatMessage == nil then
        return
    end

    options.chatMessage:RecordTokenMessage(targetToken, message)
    chat.UpdateCustom(options.chatMessageKey, options.chatMessage)
end

--casterToken: a token representing the caster.
--targets: a list of { loc = (loc object), token = (optional)token }
--- @param casterToken CharacterToken
--- @param targets { loc = Loc, token = CharacterToken }[]
--- @param options table
function ActivatedAbility:Cast(casterToken, targets, options)
	options = options or {}
	options.symbols = options.symbols or {}
    options.symbols.castid = dmhub.GenerateGuid()


    local targetTokenIds = {}
    for i,target in ipairs(targets) do
        if target.token ~= nil then
            targetTokenIds[#targetTokenIds+1] = target.token.charid
        end
    end

    if options.chatMessage == nil and self:ShowChatMessageOnCast() then
        local abilityClone = table.shallow_copy(self)
        setmetatable(abilityClone, getmetatable(self))
        abilityClone.invoker = nil
        local message = CastActivatedAbilityChatMessage.new{
            castid = options.symbols.castid,
            status = "executing",
            ability = abilityClone,
            casterid = casterToken.charid,
            targetids = targetTokenIds,
        }

        options.chatMessageKey = chat.SendCustom(message)

        options.chatMessage = message
    end


	options.alreadyInCoroutine = dmhub.inCoroutine
	options.symbols.ability = self
    options.symbols.caster = options.symbols.caster or casterToken.properties

	if self.targetType == 'self' and #targets == 0 then
		targets[#targets+1] = { loc = casterToken.loc, token = casterToken }
	end

	if self.recordTargets then
		self.recordedTargets = targets
	end

	if options.symbols.cast == nil then
		--keep any original cast, meaning this is an invoked ability.
		options.symbols.cast = ActivatedAbilityCast.new{
			ability = self,
			targets = targets,
            mode = options.symbols.mode or 1,
		}
	end

	if self:has_key("OnBeginCast") then
		self.OnBeginCast(self)
	end

	if self:has_key("castingLevel") and type(self.castingLevel) == "number" and self.castingLevel >= self:try_get("level", 1) then
		options.symbols.upcast = self.castingLevel - self:try_get("level", 1)
	end

	local continueCasting = nil
	casterToken:ModifyProperties{
		description = "Cast Spell",
		execute = function()

			if self:RequiresConcentration() then
				local concentration = casterToken.properties:BeginConcentration(self.name)
				concentration.duration = self:GetDurationInRounds()
			end

			if #self.behaviors == 0 then
				--consume resources because no behaviors generally means they have their own behavior and just want to record resource usage.
				self:ConsumeResources(casterToken, {
					costOverride = options.costOverride,
				})
				continueCasting = function()
					self:FinishCast(casterToken, options)
				end
				return
			end

			local haveNonInstant = self:CastInstantPortion(casterToken, targets, options)

			if haveNonInstant == false then
				if options.pay and not options.alreadyPaid then
					self:ConsumeResources(casterToken, {
						costOverride = options.costOverride,
					})
					options.alreadyPaid = true
				end
				continueCasting = function()
					self:FinishCast(casterToken, options)
				end
				return
			end

			if options.alreadyInCoroutine and dmhub.canSafelyYield then
				continueCasting = function()
					ActivatedAbility.CastCoroutine(self, casterToken, targets, options)
				end
			else
				continueCasting = function()
					dmhub.Coroutine(ActivatedAbility.CastCoroutine, self, casterToken, targets, options)
				end
			end
		end
	}

	if continueCasting ~= nil then
		continueCasting()
	end
end

--- @return boolean Returns true if this ability requires some kind of player prompt when cast. It can't auto-target if invoked. Used with augmented abilities etc.
function ActivatedAbility:RequiresPromptWhenCast()
    -- Multi-mode abilities need a prompt so the user can choose a mode.
    if self.multipleModes and self:has_key("modeList") then
        return true
    end

    for _,behavior in ipairs(self.behaviors) do
        if behavior.mono then
            return true
        end
    end

    return false
end

--- Returns a human-readable description of the action taken when targeting (e.g. "Shift", "Push").
--- @param symbols table
--- @return nil|string
--when targeting with this ability, describe what action will take place.
function ActivatedAbility:DescribeTargetText(symbols)

    if (self.targetType == "emptyspace" or self.targetType == "anyspace") and self.targeting == "straightline" then
        local movementType = symbols.forcedmovement or self:try_get("forcedMovement", "slide")
        return Utils.DropdownIdToText(movementType, ActivatedAbility.ForcedMovementTypes)
    end

    for _,behavior in ipairs(self.behaviors) do
        if behavior.typeName == "ActivatedAbilityRelocateCreatureBehavior" then
            if behavior.movementType == "move" then
                return "Movement"
            end
            return string.upper_first(behavior.movementType)
        end
    end

end

ActivatedAbilityBehavior.hasCast = true
--- Returns true if this ability can be cast directly without synthesizing sub-abilities.
--- @return boolean
function ActivatedAbility:IsDirectlyCastable()
    --if this is directly castable -- i.e. doesn't synthesize abilities etc.
    for _,behavior in ipairs(self.behaviors) do
        if not behavior.hasCast then
            return false
        end
    end

    return true
end

ActivatedAbility.coroutineStorage = {}

function ActivatedAbility.GetActiveCastSnapshot()
    local result = {}
    for co,_ in pairs(ActivatedAbility.coroutineStorage) do
        result[co] = true
    end

    return result
end

function ActivatedAbility.HasCoroutinesNotInSnapshot(snapshot)
    for co,_ in pairs(ActivatedAbility.coroutineStorage) do
        if coroutine.status(co) ~= "dead" and (snapshot == nil or snapshot[co] == nil) then
            return true
        end
    end
    return false
end

function ActivatedAbility.CountActiveCasts()
    local count = 0
    for co,_ in pairs(ActivatedAbility.coroutineStorage) do
        if coroutine.status(co) ~= "dead" then
            count = count + 1
        end
    end

    return count
end

--- Returns the movement type for relocate-creature behaviors ("move", "shift", etc.), or nil if none.
--- @param token CharacterToken
--- @param symbols nil|table
--- @return nil|string
function ActivatedAbility:GetMovementType(token, symbols)
    for _,behavior in ipairs(self.behaviors) do
        if behavior.typeName == "ActivatedAbilityRelocateCreatureBehavior" then
            if symbols ~= nil and symbols.shiftingOverride ~= nil then
                if behavior.movementType == "shift" and (not symbols.shiftingOverride) then
                    return "move"
                end
            end
            return behavior.movementType
        end
    end

    return nil
end

--- @return {ability: ActivatedAbility, casterToken: CharacterToken, targets: {token: CharacterToken}[], options: table}|nil
function ActivatedAbility.CurrentCastInfo()
    local co = coroutine.running()
    if co ~= nil then
        return ActivatedAbility.coroutineStorage[co]
    end

    return nil
end

function ActivatedAbility.CountActiveCasts(excludeActivities)
    local count = 0
    for k,info in pairs(ActivatedAbility.coroutineStorage) do
        if coroutine.status(k) ~= "dead" and (excludeActivities == nil or info.activity == nil or excludeActivities[info.activity] == nil) then
            count = count + 1
        end
    end
    return count
end

function ActivatedAbility.TokenHasOtherActiveCasts(token)
    for k,info in pairs(ActivatedAbility.coroutineStorage) do
        if info.casterToken ~= nil and info.casterToken.valid and info.casterToken.charid == token.charid and k ~= coroutine.running() then
            return true
        end
    end

    return false
end

function ActivatedAbility.CastCoroutine(self, casterToken, targets, options)
	local castingDepthTracker <close> = CountCastingDepth()


    local co = coroutine.running()
    coroutine.atexit(function()
        if co ~= nil then
            ActivatedAbility.coroutineStorage[co] = nil
        end
        options.atexit = true
	    self:FinishCast(casterToken, options)
    end)

    if co ~= nil then
        ActivatedAbility.coroutineStorage[co] = {
            ability = self,
            casterToken = casterToken,
            targets = targets,
            options = options,
        }
    end

	options.symbols = options.symbols or {}

	options.symbols.numberoftargets = #targets

    local restoreTargets = nil

    if options.symbols.cast ~= nil then
        restoreTargets = options.symbols.cast.targets
        options.symbols.cast.targets = targets
    end


    if self:IsStrain() and self:WillBecomeStrained(casterToken, options) then
        local strainedAbility = DeepCopy(MCDMUtils.GetStandardAbility("Strained During Ability"))
        if strainedAbility == nil then
            return
        end

        for _,behavior in ipairs(strainedAbility.behaviors) do
            behavior:Cast(self, casterToken, {{ token = casterToken }}, options)
        end
    end

	--allow behaviors to modify the targets if needed.
	options.targets = targets

	for i,behavior in ipairs(self.behaviors) do
		print("CastCoroutine:: behavior " .. i .. "/" .. #self.behaviors .. " type=" .. tostring(behavior.typeName) .. " instant=" .. tostring(behavior.instant) .. " filtered=" .. tostring(behavior:IsFiltered(self, casterToken, options)) .. " abort=" .. tostring(options.abort) .. " stopProcessing=" .. tostring(options.stopProcessing))
		if not behavior.instant and (not behavior:IsFiltered(self, casterToken, options)) then
            if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
                CharacterPanel.HighlightAbilitySection{
                    ability = self,
                    section = "main",
                }
            else
                CharacterPanel.HighlightAbilitySection{
                    ability = self,
                    section = "effects",
                }
            end

			behavior:Cast(self, casterToken, behavior:ApplyToTargets(self, casterToken, targets, options), options)
            if options.abort and (not options.pay) then
                break
            end
            if options.stopProcessing then
                break
            end
		end
	end

    if restoreTargets ~= nil then
        options.symbols.cast.targets = restoreTargets
    end

	if (options.pay or (options.payIfNotAborted and (not options.abort))) and not options.alreadyPaid then
		self:ConsumeResources(casterToken, options)
		options.alreadyPaid = true
	end

    if options.abort and (not options.pay) then
        if options.resourcesToRefundOnAbort ~= nil then
            casterToken:ModifyProperties{
                description = "Refund Resources",
                execute = function()
                    for key,value in pairs(options.resourcesToRefundOnAbort) do
                        local t = dmhub.GetTable(CharacterResource.tableName)
                        local resourceInfo = t[key]
                        if value > 0 then
                            casterToken.properties:ConsumeResource(key, resourceInfo.usageLimit, -value, "Cancel ability")
                        else
                            casterToken.properties:RefreshResource(key, resourceInfo.usageLimit, value, "Cancel ability")
                        end
                    end
                end,
            }
        end
    end

	if self.sequentialTargeting and options.symbols.targetnumber ~= nil and options.symbols.targetcount ~= nil and options.symbols.targetnumber < options.symbols.targetcount then
		options.symbols.targetnumber = options.symbols.targetnumber + 1

		if not self:CanDuplicateTargets() then
			options.symbols.forbiddentargets = options.symbols.forbiddentargets or {}
			for _,target in ipairs(targets) do
				if target.token ~= nil then
					options.symbols.forbiddentargets[target.token.charid] = true
				end
			end
		end
		
		gamehud.actionBarPanel:FireEventTree("invokeAbility", casterToken, self, options.symbols)
		return
	end

	if self.keywords["Strike"] then
		local castInfo = options.symbols.cast
		for _, target in ipairs(castInfo.targets or {}) do
			if target.token ~= nil then
				local targetToken = target.token
                if targetToken ~= nil and targetToken.valid then
                    local tier = castInfo.tier or 0
                    if castInfo:has_key("tokenToTier") and type(castInfo.tokenToTier) == "table" then
                        tier = castInfo.tokenToTier[targetToken.charid] or 0
                    end
                    targetToken.properties:TriggerEvent("attacked", {
                        outcome = tier,
                        roll = castInfo:try_get("total", 0),
                        attacker = GenerateSymbols(casterToken.properties),
                    })
                end
			end
		end
	end

	self:FinishCast(casterToken, options)
end

ActivatedAbility.countsAsCast = true

--- Returns true if using this ability should be recorded as a regular ability cast.
--- @return boolean
--if this counts as casting an ability when used.
function ActivatedAbility:CountsAsRegularAbilityCast()
    return self.countsAsCast and self.categorization ~= "Hidden"
end

--- @return boolean
function ActivatedAbility:ShowChatMessageOnCast()
    return self.countsAsCast and self.categorization ~= "Hidden"
end

function ActivatedAbility.GetTokenIds(targets)
	local tokenids = {}
	for i,target in ipairs(targets) do
		if target.token ~= nil and target.token.properties ~= nil then
			tokenids[#tokenids+1] = target.token.charid
		end
	end

	return tokenids
end

function ActivatedAbility:RequireSavingThrowsCo(behavior, casterToken, tokenids, options)
	if options.have_dc then
		--we already ran saving throws for this cast.
		return options.dcaction
	end

	if #tokenids == 0 then
		return nil
	end

	local tokenInfo = {}
	for i,tokid in ipairs(tokenids) do
		tokenInfo[tokid] = {}
	end

	local dc_options = DeepCopy(options.dc_options) or {}

	dc_options.casterid = casterToken.id

	local conditionid = self:PrimaryConditionID()
	if conditionid ~= nil then
		dc_options.condition = conditionid
	end

	dc_options.magic = self.isSpell

	local checks = {}

	local attrids = options.id
	if type(attrids) == "string" then
		attrids = {attrids}
	end

	for _,attrid in ipairs(attrids) do
		checks[#checks+1] = RollCheck.new{
			type = options.rollType or "save",
			id = attrid,
			dc = self:SaveDC(casterToken, behavior, options.symbols),
			tableRef = options.tableRef,
			info = options.info,
			explanation = options.explanation or string.format("%s against %s's %s %s", GameSystem.SavingThrowRollName, casterToken.description, self.name, cond(self.isSpell, 'spell', 'ability')),
			consequences = self:AccumulateSavingThrowConsquences(behavior, casterToken, options.targets, options),
			roll = options.roll,
			text = options.text or creature.savingThrowInfo[attrid].description,
			silent = self.silent,
			options = dc_options,
		}
	end

	local actionid = dmhub.SendActionRequest(RollRequest.new{
		checks = checks,
		silent = self.silent,
		tokens = tokenInfo,
	})

	local dcresult = {}

	if self.silent then
        print("AWAIT:: silent requested...")
		AwaitRequestedActionCoroutine(actionid, dcresult)
	else
        print("AWAIT:: show summary...")
		gamehud:ShowRollSummaryDialog(actionid, dcresult)
	end

	while dcresult.result == nil do
		coroutine.yield(0.1)
	end

    print("AWAIT:: FINI")

	options.have_dc = true

	if dcresult.result == false then
		options.dcaction = nil
	else
		options.dcaction = dcresult.action
	end

	return options.dcaction
end

--- @return boolean
function ActivatedAbility:IsMelee()
	for _,behavior in ipairs(self.behaviors) do
		if behavior.typeName == "ActivatedAbilityAttackBehavior" then
			local attack = behavior:GetAttack(self, nil, {})
			if attack ~= nil then
				return not attack:IsRanged()
			end
		end
	end

	return false
end

function ActivatedAbilityBehavior:AffectedByCover(caster, ability)
	return false
end

function ActivatedAbilityAttackBehavior:AffectedByCover(caster, ability)
	local attack = self:GetAttack(ability, caster, {})
	if attack == nil then
		return false
	end

	return attack:IsRanged() or attack:IsRangedOrMelee()
end

function ActivatedAbilityBehavior:GenerateDescription(ability, creature)
	return nil
end

function ActivatedAbilityAttackBehavior:GenerateDescription(ability, creature)
	local attack = self:GetAttack(ability, creature, {})
	if attack == nil then
		return nil
	end

	local hit = tonumber(attack.hit) or 0
	if hit >= 0 then
		hit = string.format("+%d", tonumber(hit))
	else
		hit = string.format("%d", tonumber(hit))
	end

	local ranged = attack:IsRanged()

	local reach
	if ranged then
		if attack:RangeDisadvantage() ~= nil then
			reach = string.format("range %s/%s%s.", MeasurementSystem.NativeToDisplayString(attack:RangeNormal()), MeasurementSystem.NativeToDisplayString(attack:RangeDisadvantage()), MeasurementSystem.Abbrev())
		else
			reach = string.format("range %s%s.", MeasurementSystem.NativeToDisplayString(attack:RangeNormal()), MeasurementSystem.Abbrev())
		end
	elseif attack:has_key("meleeRange") and attack:RangeDisadvantage() ~= nil then
		reach = string.format("thrown %s/%s%s.", MeasurementSystem.NativeToDisplayString(attack:RangeNormal()), MeasurementSystem.NativeToDisplayString(attack:RangeDisadvantage()), MeasurementSystem.Abbrev())
	else
		reach = string.format("reach %s%s.", MeasurementSystem.NativeToDisplayString(attack:RangeNormal()), MeasurementSystem.Abbrev())
	end

	local damage = attack:DescribeDamage()

	local offhand = ""
	if attack:try_get("offhand", false) then
		offhand = " (Offhand)"
	end

	local propertyDescription = ""
	if attack:has_key("properties") then
		for k,v in pairs(attack.properties) do
			local propertyInfo = WeaponProperty.Get(k)
			if propertyInfo ~= nil then
				propertyDescription = string.format("%s %s", propertyDescription, propertyInfo.name)
				if propertyInfo.hasValue then
					local n = 1
					if type(v) == "table" then
						n = v.value or n
					end

					propertyDescription = string.format("%s %d", propertyDescription, n)
				end
			end
		end
	end

	return GameSystem.DescribeAttack(ranged, offhand,  hit, reach, damage, propertyDescription)

end

ActivatedAbilityBehavior.roll = "1d6"
ActivatedAbilityBehavior.summaryImportance = 1
ActivatedAbilityModifiersBehavior.summaryImportance = 0

--- Returns a short summary string for the most important behavior of this ability.
--- @param creatureLookup table
--- @return string
function ActivatedAbility:SummarizeBehavior(creatureLookup)
	if #self.behaviors == 0 then
		return "--"
	end

	local importance = -1000
	local result = "--"
	for _,behavior in ipairs(self.behaviors) do
		if behavior.summaryImportance > importance then
			result = behavior:SummarizeBehavior(self, creatureLookup)
			importance = behavior.summaryImportance
		end
	end

	return result
end

function ActivatedAbilityBehavior:RecordOutcomeToApplyToTable(token, options, outcome)
	if outcome == nil or outcome.applyto == nil then
		return
	end

	if options.applytoStates == nil then
		options.applytoStates = {}
	end

	for _,applyto in ipairs(outcome.applyto) do
		options.applytoStates[applyto] = options.applytoStates[applyto] or {}
		options.applytoStates[applyto][token.charid] = { token = token }
	end
end

function ActivatedAbilityBehavior:RecordHitTarget(token, options, args)
	args = args or {}
	if options.hit_targets == nil then
		options.hit_targets = {}
	end

	for _,entry in ipairs(options.hit_targets) do
		if entry.token == token then
			if args.failedSave then
				entry.failedSave = true
			end
			return
		end
	end

	options.hit_targets[#options.hit_targets+1] = { token = token, failedSave = args.failedSave }
end

--- @param ability ActivatedAbility
--- @param casterToken nil|CharacterToken
--- @param options nil|table
function ActivatedAbilityBehavior:IsFiltered(ability, casterToken, options)

    if casterToken ~= nil and self:has_key("strainSelection") then
        local strainSelection = self.strainSelection
        local isStrained = casterToken.properties:IsStrained()
        if strainSelection == "strained" and (not isStrained) then
            return true
        end

        if strainSelection == "unstrained" and isStrained then
            return true
        end
    end

    if options ~= nil and ability.multipleModes and self:has_key("modesSelected") and #self.modesSelected > 0 then
        if not table.contains(self.modesSelected, options.symbols.mode) then
            return true
        end
    end

	if options and options.symbols and options.symbols.cast and options.symbols.cast.tier ~= 0 and #self:try_get("tiersSelected", {}) > 0 then
        --see if the tier filter filters it out.
        if not table.contains(self.tiersSelected, options.symbols.cast.tier) then
            return true
        end
    end

    return false
end

function ActivatedAbilityBehavior:ApplyToTargets(ability, casterToken, targets, options)

    if self:has_key("tiersSelected") and options.symbols.cast ~= nil and options.symbols.cast:has_key("tokenToTier") then
        --if we have a tier selected, then we need to filter out any targets that don't match.
        local filteredTargets = {}
        for _,target in ipairs(targets) do
            local passes = false  -- Start with false - only pass if tier matches
            if target.token ~= nil then
                local tier = options.symbols.cast.tokenToTier[target.token.charid]
                if tier ~= nil and table.contains(self.tiersSelected, tier) then
                    passes = true
                end
            end

            if passes then
                filteredTargets[#filteredTargets+1] = target
            end
        end

        targets = filteredTargets
    end

	local result = {}

    if self.applyto == "none" then
        --none -- don't apply to any targets.
	elseif self.applyto == 'targets' then
		result = targets
	elseif self.applyto == 'first_target' then
		if #targets == 0 then
			result = {}
		else
			result = {targets[1]}
		end
	elseif self.applyto == 'other_than_first_target' then
		result = {}
		for i=2,#targets do
			result[#result+1] = targets[i]
		end
	elseif self.applyto == 'target_proximity' or self.applyto == 'proximity_only' then
		local tokens = {}

		for _,target in ipairs(targets) do
            if self.applyto == 'target_proximity' then
			    tokens[#tokens+1] = target.token
            end

            local proximityRange = tonumber(self:try_get("target_proximity_range", tostring(dmhub.unitsPerSquare)))
			local nearbyTokens
            
            if target.token ~= nil and target.token.valid then
                nearbyTokens = target.token:GetNearbyTokens(proximityRange)
            elseif target.loc ~= nil then
                nearbyTokens = {}
                local tokens = dmhub.allTokens
                for _,tok in ipairs(tokens) do
                    if tok:Distance(target.loc) <= proximityRange then
                        nearbyTokens[#nearbyTokens+1] = tok
                    end
                end
            else
                nearbyTokens = {}
            end

			for _,tok in ipairs(nearbyTokens) do
				tokens[#tokens+1] = tok
			end
		end

		local seen = {}
		for _,tok in ipairs(tokens) do
			if seen[tok.charid] == nil then
				seen[tok.charid] = true
				result[#result+1] =
				{
					token = tok
				}
			end
		end

	elseif self.applyto == "caster" then
        if options.symbols.targetPairs ~= nil then
            --minion signature abilities have a list of target pairs, so we
            --use that to find the list of casters in the squad.
            result = {}
            for _,pair in ipairs(options.symbols.targetPairs) do
                local casterToken = dmhub.GetTokenById(pair.a)
                if casterToken ~= nil and casterToken.valid then
                    result[#result+1] = {
                        token = casterToken,
                    }
                end
            end
        else
            result = {
                {
                    token = casterToken,
                },
            }
        end

        print("Cast:: apply to targets ->", #result)

    elseif self.applyto == "caster_and_targets" then

            result = {
                {
                    token = casterToken,
                },
            }

            for _,target in ipairs(targets) do
                result[#result+1] = table.shallow_copy(target)
            end

    elseif self.applyto == 'caster_riders' then
        result = {}

        local charid = casterToken.charid

        for _,tok in ipairs(dmhub.allTokens) do
            if tok.mountedOn == charid then
                result[#result+1] = { token = tok }
            end
        end
    elseif self.applyto == 'caster_including_squad' then
        result = {
            {
                token = casterToken,
            },
        }

        if casterToken.properties.minion then
            local squad = casterToken.properties:MinionSquad()
            if squad ~= nil then

                for _,tok in ipairs(dmhub.allTokens) do
                    if tok.charid ~= casterToken.charid and tok.properties.minion and tok.properties:MinionSquad() == squad then
                        result[#result+1] = { token = tok }
                    end
                end
            end
        end
    elseif self.applyto == 'caster_minions' then
        result = {}

        local squad = casterToken.properties:MinionSquad()
        if squad ~= nil then

            for _,tok in ipairs(dmhub.allTokens) do
                if tok.charid ~= casterToken.charid and tok.properties.minion and tok.properties:MinionSquad() == squad then
                    result[#result+1] = { token = tok }
                end
            end
        end
    elseif self.applyto == "original_targets" then
		result = options.originalTargets or targets
    elseif self.applyto == "subject" then
        result = {}
        if options.symbols.subject ~= nil then
            local subject = options.symbols.subject
            if type(subject) == "function" then
                subject = subject("self")
            end
            local subjectToken = dmhub.LookupToken(subject)
            if subjectToken ~= nil then
                result[#result+1] = {
                    token = subjectToken
                }
            end
        end
	elseif self.applyto == 'hit_targets' then
		result = options.hit_targets or {}
	elseif self.applyto == 'failed_save_targets' then
		local items = options.hit_targets or {}
		result = {}
		for _,item in ipairs(items) do
			if item.failedSave or options.forceFailedSave then
				result[#result+1] = item
			end
		end
		
	elseif self.applyto == 'passed_save_targets' then
		local hit_targets = options.hit_targets or {}
		result = {}
		for _,item in ipairs(targets) do
			if item.token ~= nil then
				local passed_save = true
				for _,hit_target in ipairs(hit_targets) do
					if hit_target.token == item.token and (hit_target.failedSave or hit_target.forceFailedSave) then
						passed_save = false
					end
				end

				if passed_save then
					result[#result+1] = item
				end
			end
		end 
	elseif self.applyto == "winner_opposed" then
		local hit_targets = options.hit_targets or {}
		if #hit_targets > 0 then
			result = {
                {
                    token = casterToken,
                },
            }
		else
			result = options.targets
		end
    elseif self.applyto == 'all_creatures' then
        --this is a special applyto that returns all creatures in combat.
        result = {}
		local initQueue = dmhub.initiativeQueue
		if initQueue ~= nil and not initQueue.hidden then
			for initiativeid,_ in pairs(initQueue.entries) do
				local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
				for i,tok in ipairs(tokens) do
					if tok and tok.properties ~= nil then
						result[#result+1] = { token = tok }
					end
				end
			end
		end
	elseif GameSystem.ApplyToTargetsByID[self.applyto] ~= nil then

		--these are custom roll groups. When calling RegisterRollType in the GameSystem we define applyto in the outcomes
		--to determine which lists targets go into.

		local applyto = self.applyto
		local inverse = false

		if GameSystem.ApplyToTargetsByID[self.applyto].inverse ~= nil then
			applyto = GameSystem.ApplyToTargetsByID[self.applyto].inverse
			inverse = true
		end

		result = {}

		local tokenset = (options.applytoStates or {})[applyto]
		if tokenset ~= nil then
			for k,v in pairs(tokenset) do
				result[#result+1] = { token = v.token }
			end
		end

		if inverse then
			local exclude = result
			result = {}
			for _,target in ipairs(targets) do
				if target.token ~= nil then
					local excluded = false
					for _,excludeTarget in ipairs(exclude) do
						if excludeTarget.token.charid == target.token.charid then
							excluded = true
							break
						end
					end

					if not excluded then
						result[#result+1] = target
					end
				end
			end
		end
	else
		result = targets
	end

	if trim(self.filterTarget) ~= "" then
		local filteredResult = {}

		local symbols = {}
		for k,v in pairs(options.symbols or {}) do
			symbols[k] = v
		end


		for i,item in ipairs(result) do
            if item.token ~= nil then
                symbols.target = item.token.properties
                symbols.caster = casterToken.properties
                symbols.targetnumber = i
                symbols.numberoftargets = #result
                local passFilter = nil

                --find out if the user got to choose to select whether this applies with the attack roll.
                for _,override in ipairs(options.passFilterOverrides or {}) do
                    if override.target == symbols.target and override.behavior == self then
                        passFilter = override.value
                    end
                end
                
                if passFilter == nil then
                    passFilter = GoblinScriptTrue(ExecuteGoblinScript(self.filterTarget, item.token.properties:LookupSymbol(symbols), 1, string.format("Filter targets: %s", ability.name)))
                end

                if passFilter then
                    filteredResult[#filteredResult+1] = item
                end
            end
		end

		result = filteredResult
	end

	return result
end

function ActivatedAbilityBehavior:SummarizeBehavior(ability, creatureLookup)
	return self.summary
end

function ActivatedAbilityHealBehavior:SummarizeBehavior(ability, creatureLookup)
	return string.format("%s Healing", dmhub.NormalizeRoll(dmhub.EvalGoblinScript(self.roll, creatureLookup, string.format("Heal roll for %s", ability.name))))
end

function ActivatedAbilityApplyOngoingEffectBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Apply Effect"
end

function ActivatedAbilityApplyMomentaryEffectBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Apply Momentary Effect"
end


function ActivatedAbilityTransformBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Transform Creatures"
end

function ActivatedAbilityBehavior:ConditionID()
	return nil
end

function ActivatedAbilityAuraBehavior:SummarizeBehavior(ability, creatureLookup)
	return "Affect Area"
end

function ActivatedAbility:AccumulateSavingThrowConsquences(behavior, casterToken, targets, options)
	local consequences = {}

	local activated = false
	for _,b in ipairs(self.behaviors) do
		if b == behavior then
			activated = true
		end

		if activated and (b == behavior or b.applyto == 'failed_save_targets' or b.applyto == 'hit_targets') then
			b:AccumulateSavingThrowConsequence(self, casterToken, targets, consequences, options)
		end
	end

	if consequences.damage == nil and consequences.conditions == nil then
		return nil
	end

	return consequences
end

function ActivatedAbility.DescribeSavingThrowConsquences(consequences)

	local str = ""

	if consequences.damage ~= nil then
		for i,damage in ipairs(consequences.damage) do
			str = string.format("%s%s%s", str, cond(str ~= "", ", ", ""), damage.amount, damage.damageType)
		end

		str = string.format("%s damage", str)
	end

	if consequences.conditions ~= nil then
		for _,entry in ipairs(consequences.conditions) do
			local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
			local ongoingEffect = characterOngoingEffects[entry.conditionid]
			if ongoingEffect ~= nil then
				str = string.format("%s%s%s", str, cond(str ~= "", ", ", ""), ongoingEffect.name)
			end
		end
	end

	if consequences.text ~= nil then
		for i,entry in ipairs(consequences.text) do
			str = string.format("%s%s%s", str, cond(str ~= "", ", ", ""), entry.text)
		end
	end

	str = string.format("%s on saving throw failure.", str)
	if consequences.damage then
		if consequences.damage[1].success == "half" then
			str = string.format("%s Half damage on success.", str)
		else
			str = string.format("%s No damage on success.", str)
		end
	end

	return str
end

--which token id's does this apply to? Returns a map of {tokid -> true} or false if it applies to none or nil if it applies to all.
local GetConsequenceTokenIds = function(behavior, ability, casterToken, targets)
	local targetsApplied = behavior:ApplyToTargets(ability, casterToken, targets, {
		hit_targets = targets,
		forceFailedSave = true,
	})

	if targetsApplied == nil or #targetsApplied == 0 then
		return false
	end

	if #targetsApplied == #targets then
		return nil
	end

	local result = {}
	local tokenids = ActivatedAbility.GetTokenIds(targetsApplied)
	for _,tokid in ipairs(tokenids) do
		result[tokid] = true
	end

	return result
end

ActivatedAbility.GetConsequenceTokenIds = GetConsequenceTokenIds

function ActivatedAbilityBehavior:AccumulateSavingThrowConsequence(ability, casterToken, targets, consequences, options)
end

function ActivatedAbilityApplyOngoingEffectBehavior:AccumulateSavingThrowConsequence(ability, casterToken, targets, consequences, options)
	local tokenids = GetConsequenceTokenIds(self, ability, casterToken, targets)
	if tokenids == false then
		return
	end

	consequences.conditions = consequences.conditions or {}
	consequences.conditions[#consequences.conditions+1] = {
		conditionid = self.ongoingEffect,
		tokens = tokenids,
	}
end

function ActivatedAbilityBehavior:DescribeRoll(casterCreature, ability, options)
	if casterCreature == nil then
		--it is entirely acceptable to call this with no creature provided.
		if type(self.roll) == "table" then
			--break down tables into text.
			return self.roll:ToText()
		end
		return self.roll
	end

	return dmhub.EvalGoblinScript(self.roll, casterCreature:LookupSymbol((options or {}).symbols), "Ability or spell roll")
end

function ActivatedAbilityHealBehavior:Cast(ability, casterToken, targets, options)

    --filter out any targets that cannot heal.
    local filteredTargets = {}
    for _,target in ipairs(targets) do
        if target.token ~= nil and target.token.valid then
            local canHeal = (target.token.properties:CalculateNamedCustomAttribute("Cannot Regain Stamina") == 0)

            if canHeal then
                filteredTargets[#filteredTargets+1] = target
            else
                ability.RecordTokenMessage(target.token, options, "Cannot Regain Stamina")
                target.token:ModifyProperties{
                    description = "Cannot Heal",
                    undoable = false,
                    execute = function()
                        target.token.properties:FloatLabel("Cannot Regain Stamina", "#ff0000")
                    end,
                }
            end
        end
    end

    targets = filteredTargets

    print("Heal::", #targets)

	if #targets == 0 then
		return
	end

	local casterName = creature.GetTokenDescription(casterToken)

	local tokenids = ActivatedAbility.GetTokenIds(targets)

	local finished = false
	
	local symbols = DeepCopy(options.symbols or {})

	if #targets == 1 and targets[1].token ~= nil and targets[1].token.properties ~= nil then
		symbols.target = targets[1].token.properties:LookupSymbol()
	end

	local roll = dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(symbols), string.format("Healing roll for %s", ability.name))
	gamehud.rollDialog.data.ShowDialog{
		title = 'Roll for Healing',
		description = string.format("%s Healing", ability.name),
		roll = roll,

		creature = casterToken.properties,
		skipDeterministic = true,
		type = 'healing',
		cancelRoll = function()
			finished = true
		end,
		completeRoll = function(rollInfo)
			finished = true
            ability:CommitToPaying(casterToken, options)
			options.symbols.cast.healroll = rollInfo.total
			for i,target in ipairs(targets) do
				local targetCreature = target.token.properties
				for catName,value in pairs(rollInfo.categories) do
					local healAmount = value

                    local half = (target.token.properties:CalculateNamedCustomAttribute("Stamina Regain Halved") > 0)
                    if half then
                        healAmount = math.floor(healAmount / 2)
                    end

                    ability.RecordTokenMessage(target.token, options, string.format("Regained %d Stamina", healAmount))
					target.token:ModifyProperties{
						description = "Regained Stamina",
						execute = function()
							targetCreature:Heal(healAmount, string.format("%s's %s", casterName, ability.name))
						end,
					}

					options.symbols.cast.healing = options.symbols.cast.healing + healAmount
				end
			end

			if options ~= nil and options.complete ~= nil then
				options.complete()
			end
		end
	}

	while not finished do
		coroutine.yield(0.1)
	end
end

function ActivatedAbilityAttackBehavior:AppendHitModification(ability, str, symbols)
	if ability:has_key("attackOverride") then
		
		ability.attackOverride.hit = string.format("(%s)+(%s)", tostring(ability.attackOverride.hit), str)
		dmhub.Debug(string.format("AUGMENT:: ATTACK -> %s", ability.attackOverride.hit))
	else
		if self:has_key("hitAppend") then
			self.hitAppend = self.hitAppend .. " " .. str
		else
			self.hitAppend = str
		end
		dmhub.Debug(string.format("AUGMENT:: ATTACK APPEND -> %s", self.hitAppend))
	end
end



function ActivatedAbilityAttackBehavior:AppendDamageModification(ability, str, symbols, options)
	options = options or {}
	if ability:has_key("attackOverride") then
		local mod = CharacterModifier.new{
			behavior = 'damage',
			guid = dmhub.GenerateGuid(),
			name = options.name or "Modify Damage",
			description = options.description or "Modify Damage",
			modifyRoll = str,
			_tmp_symbols = symbols,
			force = true, --this won't show up in the dialog, it is just a forced override to the attack.
			hint = {
				result = true,
			}
		}

		local modifiers = ability.attackOverride:get_or_add("modifiers", {})
		modifiers[#modifiers+1] = mod

	else
		self.roll = string.format("%s+(%s)", self.roll, str)
	end
end

function ActivatedAbilityAttackBehavior:GetAttack(ability, creature, options)

	options = options or {}

	if ability:has_key("attackOverride") then
		local result = ability.attackOverride

		if options.modifiers ~= nil and #options.modifiers > 0 then
			result = DeepCopy(ability.attackOverride)
			result.modifiers = result.modifiers or {}
			for _,a in ipairs(options.modifiers) do
				result.modifiers[#result.modifiers+1] = a
			end
		end

		return result
	else
		local hit = self:try_get("hit")
		if hit ~= nil and creature ~= nil then
			hit = dmhub.EvalGoblinScript(hit, creature:LookupSymbol(options.symbols), string.format("Calculate hit modifier for %s", ability.name))
		else
			if creature == nil then
				hit = 0
			else
				hit = creature:SpellAttackModifier(ability)
			end
		end

		if self:has_key("hitAppend") and creature ~= nil then
			hit = dmhub.EvalGoblinScript(tostring(hit) .. " " .. self.hitAppend, creature:LookupSymbol(options.symbols), string.format("Calculate hit modifier for %s with modifications", ability.name))
		end

		local attrid = nil
		if creature ~= nil then
			attrid = creature:GetAttributeUsedForAbility(ability)
			if attrid == "none" then
				attrid = nil
			end
		end

		local damageMod = ""
		if creature ~= nil and self:try_get("attrModDamage", false) then
			local attrMod = creature:SpellcastingAbilityModifier(ability)

			damageMod = ModStr(attrMod)
		end

		local range = tostring(ability:GetRange(creature))
		if ability:GetRangeDisadvantage() ~= ability:GetRange(creature) then
			range = string.format("%s/%s", ability:GetRange(creature), ability:GetRangeDisadvantage(creature))
		end

		return Attack.new{
			iconid = ability.iconid,
			name = ability.name,
			attrid = attrid,
			isSpell = ability.isSpell,
			range = range,
			hit = hit,
			melee = self:try_get("attackType", "Ranged") == "Melee",
			modifiers = options.modifiers, --modifiers from 'modify this ability'.
			damageInstances = {
				DamageInstance.new{
					damage = self:DescribeRoll(creature, ability, options) .. damageMod,
					damageType = self.damageType,
					damageMagical = self:try_get("magicalDamage", ability.isSpell),
				},
			},
		}
	end
end

function ActivatedAbilityAttackBehavior:ExpectedDamageRoll(ability, casterToken, targetToken, options)
	options = options or {}
	local attack = self:GetAttack(ability, casterToken.properties, options)
	local modifiers = casterToken.properties:GetDamageRollModifiers(attack, targetToken, options)

	local roll = dmhub.NormalizeRoll(attack:DescribeDamageRoll(), casterToken.properties:LookupSymbol{ target = GenerateSymbols(targetToken.properties) }, "Calculate Damage Roll")
	for _,mod in ipairs(modifiers) do
		if mod.modifier ~= nil and mod.hint ~= nil and mod.hint.result then
			mod.modifier:InstallSymbolsFromContext{
				ability = GenerateSymbols(ability),
			}

			roll = mod.modifier:ModifyDamageRoll(mod, casterToken.properties, targetToken.properties, roll)
		end
	end

	roll = dmhub.NormalizeRoll(attack:DescribeDamageRoll(), casterToken.properties:LookupSymbol{ target = GenerateSymbols(targetToken.properties) }, "Calculate Damage Roll")
	return roll
end

function ActivatedAbilityAttackBehavior:Cast(ability, casterToken, targets, options)

	for i,target in ipairs(targets) do
		local targetCreature = target.token.properties

		options.symbols = options.symbols or {}
		options.symbols.target = GenerateSymbols(targetCreature)
		local attack = self:GetAttack(ability, casterToken.properties, options)

		if i == 1 and ability:has_key("attackOverride") and ability.attackOverride:has_key("consumeAmmo") and ability.attackOverride:has_key("meleeRange") and (casterToken:DistanceInFeet(target.token) - 2.5) <= ability.attackOverride.meleeRange then
			--this is a melee attack, so make sure we don't consume projectiles to use it.
			options.meleeAttack = true
		end

		local fireObjectArgs = nil

		local beginAttack = nil
		if i == 1 and ability:has_key("attackOverride") and (ability.attackOverride:has_key("consumeAmmo") or ability.attackOverride:try_get("outOfAmmo", false)) and ((not ability.attackOverride:has_key("meleeRange")) or (casterToken:DistanceInFeet(target.token) - 2.5) > ability.attackOverride.meleeRange) then
			local consumeAmmo = ability.attackOverride:try_get("consumeAmmo")

			--we are out of ammo, but just find the mundane ammo for this weapon and use that.
			if consumeAmmo == nil then
				local gearTable = dmhub.GetTable('tbl_Gear')
				for k,gear in pairs(gearTable) do
					if gear:try_get("equipmentCategory") == ability.attackOverride:try_get("ammoType") then
						consumeAmmo = { [k] = 1 }
					end
				end
			end
			for k,_ in pairs(consumeAmmo) do
				if beginAttack == nil then
					--throw a missile at the target.
					beginAttack = function(rollInfo)
						Projectile.Fire{
							rollInfo = rollInfo,
							ability = ability,
							casterToken = casterToken,
							targetToken = target.token,
							missileid = k,
						}

                        DestroyLineOfSight(options)

					end
				end
			end
		elseif attack:try_get("melee") then
			beginAttack = function(rollInfo)
				Anim.MeleeAttack{
					rollInfo = rollInfo,
					attackerToken = casterToken,
					targetToken = target.token,
					damage = dmhub.RollExpectedValue(self:ExpectedDamageRoll(ability, casterToken, target.token, options)),
				}
			end
		elseif ability.projectileObject ~= "none" then
			fireObjectArgs = {
				ability = ability,
				casterToken = casterToken,
				targetToken = target.token,
				objectid = ability.projectileObject,
			}
		end

		--see if there are any other effects that might be triggered by this which we should show checkboxes for.
		--fold effects with the same description into the same checkbox.
		local damageCheckboxes = {}
		local allBehaviors = ability.behaviors
		local damageCheckboxesByText = {}
		for _,behavior in ipairs(allBehaviors) do
			if GameSystem.GetApplyToInfo(behavior.applyto).attack_hit and behavior:try_get("hitDescription", "") ~= "" then
				local symbols = {}
				for k,v in pairs(options.symbols or {}) do
					symbols[k] = v
				end
				symbols.target = target.token.properties
				local passFilter = true
				passFilter = GoblinScriptTrue(ExecuteGoblinScript(behavior.filterTarget, casterToken.properties:LookupSymbol(symbols), 1, string.format("Filter targets: %s", ability.name)))
				local info
				info = {
					check = true,
					text = behavior.hitDescription,
					value = passFilter,
					tooltip = behavior:try_get("hitDetails"),
					target = target.token.properties,
					behavior = behavior,
					additionalInfo = {},
					change = function(val)
						info.value = val
						for _,other in ipairs(info.additionalInfo) do
							other.value = val
						end
					end,
				}

				options.passFilterOverrides = options.passFilterOverrides or {}
				options.passFilterOverrides[#options.passFilterOverrides+1] = info

				local existing = damageCheckboxesByText[info.text]
				if existing ~= nil then
					--another checkbox with the same name, so just add as an additional checkbox to that.
					existing.additionalInfo[#existing.additionalInfo] = info
				else
					damageCheckboxes[#damageCheckboxes+1] = info
					damageCheckboxesByText[info.text] = info
				end
			end
		end

		local canceled = false
		local completed = false
		local attackHit = false

		casterToken.properties:RollAttackHit(attack, target.token, {
			ability = ability,
			damageCheckboxes = damageCheckboxes,
			symbols = options.symbols,
			keywords = ability.keywords,
			beginAttack = function(rollInfo)
				if beginAttack ~= nil then
					beginAttack(rollInfo)
				end

				--go ahead and pay for this ability now so that during the damage phase we have updated resources correctly.
				if not options.alreadyPaid then
					options.alreadyPaid = true
					ability:ConsumeResources(casterToken, options)
				end

				if fireObjectArgs ~= nil then
					Projectile.FireObject(fireObjectArgs)
				end
			end, 

			completeAttackRoll = function(rollInfo)
                ability:CommitToPaying(casterToken, options)
				local outcome = rollInfo.properties:GetOutcome(rollInfo)
				self:RecordOutcomeToApplyToTable(target.token, options, outcome)

				for _,roll in ipairs(rollInfo.rolls) do
					if (not roll.dropped) and roll.numFaces == 20 then
						options.symbols.cast.naturalattackroll = roll.result
					end
				end

				options.symbols.cast.attackroll = rollInfo.total
                DestroyLineOfSight(options)
			end,

			completeAttack = function(hit, completeAttackOptions)
                ability:CommitToPaying(casterToken, options)
				completed = true
				attackHit = hit
				if attackHit then
					self:RecordHitTarget(target.token, options)
				end
			end,
			cancelAttack = function()
				canceled = true
			end,
		})

		while canceled == false and completed == false do
			coroutine.yield(0.1)
		end

		if canceled then
			return
		end

		if attackHit and self:has_key("attackTriggeredAbility") then
			--trigger the ability for this attack.
			self.attackTriggeredAbility:AttackHitWhileInCoroutine(casterToken, target.token)
		end
	end
end

function ActivatedAbilityApplyOngoingEffectBehavior:ConditionID()
	if self:try_get("ongoingEffect") == nil then
		return nil
	end

	local characterOngoingEffects = dmhub.GetTable("characterOngoingEffects")
	local ongoingEffect = characterOngoingEffects[self.ongoingEffect]
	if ongoingEffect == nil then
		return nil
	end

	return ongoingEffect.condition
end

function ActivatedAbilityApplyOngoingEffectBehavior:Cast(ability, casterToken, targets, options)

    local count = 0
    for _,target in ipairs(targets) do
        if target.token ~= nil then
            count = count+1
        end
    end

	local characterOngoingEffectsTable = dmhub.GetTable("characterOngoingEffects")
	if self:try_get("ongoingEffect") == nil or characterOngoingEffectsTable[self.ongoingEffect] == nil then
		return
	end

    local guid = options.symbols.cast:get_or_add("guid", dmhub.GenerateGuid())

	local ongoingEffectInfo = characterOngoingEffectsTable[self.ongoingEffect]

	local dcaction = nil
	local tokenids = ActivatedAbility.GetTokenIds(targets)
	if self:try_get('dc', 'none') ~= 'none' then

		local dc_options = DeepCopy(self:try_get("dc_options", {}))
		dc_options.condition = self:ConditionID()

		dcaction = ability:RequireSavingThrowsCo(self, casterToken, tokenids, {
			id = self.dc,
			dc_options = dc_options,
			targets = targets,
			symbols = options.symbols,
		})

		if dcaction == nil then
			return
		end

		--someone made a saving throw roll, so we should pay for this ability
        ability:CommitToPaying(casterToken, options)

	end

	options.haveOngoingDC = false

	for i,target in ipairs(targets) do
		local skip = false
		if dcaction ~= nil then
			local dcinfo = dcaction.info.tokens[target.token.charid]
			if dcinfo ~= nil then
				local outcome = dcaction.info:GetTokenOutcome(target.token.charid)
				self:RecordOutcomeToApplyToTable(target.token, options, outcome)

				if dcinfo.result >= dcaction.info.checks[1].dc then
					skip = true
				end
				if skip == false then
					self:RecordHitTarget(target.token, options, {failedSave = true})
				end
			end

		end

		if skip == false then

            local casterid = casterToken.id
            local casteridFormula = self:try_get("casteridFormula", "")

            if casteridFormula ~= "" then
                local casteridInt = ExecuteGoblinScript(casteridFormula, casterToken.properties:LookupSymbol(options.symbols), string.format("Caster ID for %s", ability.name))
                print("CasterId: search for " .. casteridFormula .. " = " .. tostring(casteridInt))
                if casteridInt ~= nil then
                    local tokens = dmhub.allTokens
                    for k,token in pairs(tokens) do
                        if Utils.HashGuidToNumber(token.charid) == casteridInt then
                            casterid = token.charid
                            print("CasterId: found caster")
                            break
                        end
                    end
                end
            end

			local casterInfo = {
				tokenid = casterid,
				abilityName = ability.name,
			}

            if casterToken.properties.minion then
                casterInfo.minionSquad = casterToken.properties:MinionSquad()
            end

			if ability:RequiresConcentration() and casterToken.properties:HasConcentration() then
				casterInfo.concentrationid = casterToken.properties:MostRecentConcentrationId()
			end

			local temporary_hitpoints = nil
			if self.hasTemporaryHitpoints then
				temporary_hitpoints = 0

				local finished = false

				gamehud.rollDialog.data.ShowDialog{
					title = 'Roll for Temporary Stamina',
					description = string.format("%s Temporary Stamina", ability.name),
					roll = dmhub.EvalGoblinScript(self.temporaryHitpoints, casterToken.properties:LookupSymbol(options.symbols), string.format("Roll for temporary hitpoints for %s", ability.name)),
					creature = casterToken.properties,
					skipDeterministic = true,
					type = 'temporary_hitpoints',
					cancelRoll = function()
						finished = true
					end,
					completeRoll = function(rollInfo)
						finished = true
                        ability:CommitToPaying(casterToken, options)
						temporary_hitpoints = rollInfo.total
					end
				}

				while not finished do
					coroutine.yield(0.1)
				end

			end


			local ongoingDC = nil

			--Apply Ongoing DC determined by roll ex. Stealth

			local ongoingDCSkill = self:try_get('ongoingDCSkill', nil)

			--some declared variables so we can continue.
			local stacks
			local targetCreature
			local newEffect
			local finished = false

			local continuing = false

			if ongoingDCSkill ~= nil and Skill.SkillsById[ongoingDCSkill] ~= nil then
				local check = RollCheck.new{
					type = "skill",
					id = ongoingDCSkill,
					text = Skill.SkillsById[ongoingDCSkill].name,
					explanation = "Roll skill check",
					silent = false,
					options = {},
				}
	
				local ongoingDCAction = self:try_get('ongoingDCAction', nil)

				if options.haveOngoingDC == false then
					local checks = {}
					checks[#checks+1] = check

					local attackerChecks = {}
					attackerChecks[#attackerChecks+1] = #checks

					local tokenInfo = {}
					tokenInfo[casterToken.charid] = {
						team = "attacker",
						checks = attackerChecks,
					}

					local actionid = dmhub.SendActionRequest(RollRequest.new {
						checks = checks,
						silent = false,
						tokens = tokenInfo,
					})

					local dcresult = {}

					AwaitRequestedActionCoroutine(actionid, dcresult)

					while dcresult.result == nil do
						coroutine.yield(0.1)
					end

					options.haveOngoingDC = true
				
					if dcresult.result == false then
						--we didn't get a result from this dice roll, so skip this target
						--since we probably don't want to apply the ongoing effect at all.
						continuing = true
					else
						ongoingDCAction = dcresult.action
					end

					if not continuing then
						local attackerRoll = ongoingDCAction.info.tokens[casterToken.charid].result
						if attackerRoll == nil then
							--they declined the roll so skip applying the effect.
							continuing = true
						else
							ongoingDC = attackerRoll
						end
					end
				end
			end

			if not continuing then
				--going to apply the effect, so pay for this ability.
                ability:CommitToPaying(casterToken, options)

				gamehud.rollDialog.data.ShowDialog{
					title = string.format("Roll for Stacks of %s Effect", ongoingEffectInfo.name),
					description = string.format("%s Stacks", ability.name),
					roll = dmhub.EvalGoblinScript(self.stacks, casterToken.properties:LookupSymbol(options.symbols), string.format("Number of stacks for %s", ability.name)),
					creature = casterToken.properties,
					skipDeterministic = true,
					type = 'effect_stacks',
					cancelRoll = function()
						finished = true
					end,
					completeRoll = function(rollInfo)
						finished = true
                        ability:CommitToPaying(casterToken, options)
						stacks = rollInfo.total
					end
				}

				while not finished do
					coroutine.yield(0.1)
				end

				if stacks == nil then
					return
				end

                local sourceDescription = string.format("Applied by %s's <b>%s</b> ability", creature.GetTokenDescription(casterToken), ability.name)

                if stacks > 1 then
                    ability.RecordTokenMessage(target.token, options, string.format("Apply %s x %d", ongoingEffectInfo.name, stacks))
                else
                    ability.RecordTokenMessage(target.token, options, string.format("Apply %s", ongoingEffectInfo.name))
                end

				local persistence = ability:Persistence()
				if persistence ~= nil and persistence.enabled then
					casterInfo.persistenceId = casterToken.properties:MostRecentPersistentAbilityId()
				end

				targetCreature = target.token.properties
				target.token:ModifyProperties{
					description = "Applied Ongoing Effect",
					execute = function()
						newEffect = targetCreature:ApplyOngoingEffect(self.ongoingEffect, self:try_get("duration"), casterInfo, {
                            guid = guid,
							temporary_hitpoints = temporary_hitpoints,
							untilEndOfTurn = self.durationUntilEndOfTurn,
							stacks = stacks,
                            sourceDescription = sourceDescription,
						})
						if newEffect ~= nil then
							if ongoingDC ~= nil then
								newEffect.ongoingDC = ongoingDC
							end

							--Apply DC for repeating save
							if self:try_get('dc', 'none') ~= 'none' then
								newEffect.dc = ability:SaveDC(casterToken, self, options.symbols)
								if self.repeatSave then
									newEffect.repeatSaveModifier = CharacterModifier.new{
										behavior = 'trigger',
										guid = dmhub.GenerateGuid(),
										name = "Repeat save",
										description = "Repeat saving throw each round",
										triggeredAbility = TriggeredAbility.Create{
											name = "Repeat save",
											trigger = "endturn",
											silent = true,
											behaviors = {
												ActivatedAbilityRemoveOngoingEffectBehavior.new{
													ongoingEffectid = self.ongoingEffect,
													dc = self.dc,
													dcvalue = ability:SaveDC(casterToken, self, options.symbols),
													dc_options = self:try_get("dc_options"),
												},
											},
										},
									}
								end
							end
						end
					end
				}
			end
		end
	end

    --force the game to refresh with the new game status so later effects take it into consideration.
    game.Refresh{
        tokens = tokenids,
    }
end

function ActivatedAbilityRemoveOngoingEffectBehavior:Cast(ability, casterToken, targets, options)

    ability:CommitToPaying(casterToken, options)

	local dcaction = nil
	local tokenids = ActivatedAbility.GetTokenIds(targets)
	if self:try_get('dc', 'none') ~= 'none' then

		local tokenids = ActivatedAbility.GetTokenIds(targets)
		if self:try_get('dc', 'none') ~= 'none' then

			dcaction = ability:RequireSavingThrowsCo(self, casterToken, tokenids, {
				id = self.dc,
				dc_options = self:try_get("dc_options"),
				targets = targets,
				symbols = options.symbols,
			})

			if dcaction == nil then
				return
			end

		end

		if dcaction == nil then
			return
		end
	end

	for i,target in ipairs(targets) do
		local passedDC = true
		if dcaction ~= nil then
			local dcinfo = dcaction.info.tokens[target.token.charid]
			if dcinfo ~= nil and dcinfo.result ~= nil and dcaction.info.checks[1].dc ~= nil then
				passedDC = dcinfo.result >= dcaction.info.checks[1].dc
			end
		end

		if passedDC then
			local targetCreature = target.token.properties
			target.token:ModifyProperties{
				description = "Applied Ongoing Effect",
				execute = function()
					targetCreature:RemoveOngoingEffect(self.ongoingEffectid)
				end,
			}

		end
	end
	
end

function ActivatedAbilityApplyMomentaryEffectBehavior:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)

	for i,target in ipairs(targets) do
		local targetCreature = target.token.properties
		self.momentaryEffect.iconid = ability.iconid
		self.momentaryEffect.display = ability.display
		targetCreature:ApplyMomentaryEffect(self.momentaryEffect)
	end
end

function ActivatedAbilityContestedAttackBehavior.CheckNameFromId(id)
	if creature.attributesInfo[id] then
		return creature.attributesInfo[id].description
	else
		return Skill.SkillsById[id].name
	end
end

function ActivatedAbilityContestedAttackBehavior:CreateCheck(ability, casterToken, attrid, isattacker)

	local explanation = nil
	if isattacker then
		explanation = string.format("Contested roll to see if your %s is successful", ability.name)
	else
		explanation = string.format("Contested roll against's %s's %s.", casterToken.description, ability.name)
	end

	if creature.attributesInfo[attrid] then
		check = RollCheck.new{
			type = "attribute",
			id = attrid,
			text = ActivatedAbilityContestedAttackBehavior.CheckNameFromId(attrid),
			explanation = explanation,
			silent = false,
			options = {},
		}
	else
		check = RollCheck.new{
			type = "skill",
			id = attrid,
			text = ActivatedAbilityContestedAttackBehavior.CheckNameFromId(attrid),
			explanation = explanation,
			silent = false,
			options = {},
		}
	end

	return check
end

ActivatedAbilityContestedAttackBehavior.silent = true

function ActivatedAbilityContestedAttackBehavior:Cast(ability, casterToken, targets, options)

	local checks = {}

	local attackerChecks = {}
	local defenderChecks = {}

	for _,attr in ipairs(self.attackAttributes) do
		local check = self:CreateCheck(ability, casterToken, attr, true)
		
		checks[#checks+1] = check
		attackerChecks[#attackerChecks+1] = #checks
	end

	for _,attr in ipairs(self.defenseAttributes) do
		local check = self:CreateCheck(ability, casterToken, attr, false)
		checks[#checks+1] = check
		defenderChecks[#defenderChecks+1] = #checks
	end

	local tokenInfo = {}
	tokenInfo[casterToken.charid] = {
		team = "attacker",
		checks = attackerChecks,
	}

	for _,target in ipairs(targets) do
		if target.token ~= nil then
			tokenInfo[target.token.charid] = {
				team = "defender",
				checks = defenderChecks,
			}
		end
	end

	local actionid = dmhub.SendActionRequest(RollRequest.new{
		checks = checks,
		silent = self.silent,
		tokens = tokenInfo,
	})

	local dcresult = {}

	if self.silent then
		AwaitRequestedActionCoroutine(actionid, dcresult)
	else
		gamehud:ShowRollSummaryDialog(actionid, dcresult)
	end

	while dcresult.result == nil do
		coroutine.yield(0.1)
	end

	if dcresult.result == false then
		return
	end

	local dcaction = dcresult.action

	local attackerRoll = dcaction.info.tokens[casterToken.charid].result

	if attackerRoll == nil then
		return
	end

	--mark down as 'hit' anyone who failed against the attacker.
	--TODO: work out how this interacts with the new applyto system.
	for _,target in ipairs(targets) do
		if target.token ~= nil then
			local defenderRoll = dcaction.info.tokens[target.token.charid].result
			if defenderRoll ~= nil and defenderRoll <= attackerRoll then
				self:RecordHitTarget(target.token, options)
			end
		end
	end
end

ActivatedAbilityForcedMovementBehavior.moveTypeOptions = {
	{
		id = "push",
		text = "Push",
	},
	{
		id = "pull",
		text = "Pull",
	},
}

ActivatedAbilityForcedMovementBehavior.moveType = "push"
function ActivatedAbilityForcedMovementBehavior:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)

	local targetsSorted = {}
	for i,target in ipairs(targets) do
		if target.token ~= nil and target.token.properties ~= nil then
			targetsSorted[#targetsSorted+1] = target.token
		end
	end

	local sign = 1
	--when pushing process tokens furthest away first, when pulling process nearest tokens first.
	if self.moveType == "push" then
		table.sort(targetsSorted, function(a,b) return casterToken:DistanceInFeet(a) > casterToken:DistanceInFeet(b) end)
	else
		table.sort(targetsSorted, function(a,b) return casterToken:DistanceInFeet(a) < casterToken:DistanceInFeet(b) end)
		sign = -1
	end

	local symbols = DeepCopy(options.symbols)
	for i,target in ipairs(targetsSorted) do
		symbols.target = GenerateSymbols(target.properties)
		local distance = ExecuteGoblinScript(self.distance, casterToken.properties:LookupSymbol(symbols), 0, string.format("Calculate %s distance: %s", self.moveType, ability.name))
		target:ForcedPush(casterToken, distance*sign)
	end
end

function ActivatedAbilityModifiersBehavior:Cast(ability, casterToken, targets, options)
	options.modifiers = options.modifiers or {}
	for _,mod in ipairs(self.modifiers) do
		options.modifiers[#options.modifiers+1] = mod
	end

end

function ActivatedAbility:RenderTokenDependent(token, result)
end

function ActivatedAbility:GenerateTextDescription(token)
	local description = self.description
	if description == '' and token ~= nil and token.properties ~= nil then
		for i,behavior in ipairs(self:try_get("behaviors", {})) do
			local str = behavior:GenerateDescription(self, token.properties)
			if str ~= nil then
				description = description .. '\n' .. str
			end
		end
	end

	return description
end

function ActivatedAbility:Render(options, params)

	params = params or {}
	options = options or {}

	local summary = options.summary
	options.summary = nil


	--if we have a specific token and there is an aura associated with this ability, add some information about the aura.
	local tokenDependentInfoPanel = nil
	if params.token ~= nil and params.token.properties ~= nil then
		local tokenDependentChildren = {}

		local cost = self:GetCost(params.token)
		if cost.outOfAmmo then
			tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
				color = "#ffaaaa",
				text = "Out of Ammo",
			}
		end

		if cost.moveCost ~= nil then
			local labelColor = cond(cost.cannotMove, "#ffaaaa", "#aaaaaa")
			local text = string.format("Consumes %s %s of movement", MeasurementSystem.NativeToDisplayString(cost.moveCost), MeasurementSystem.Abbrev())
			if params.token.properties:CurrentMovementSpeed() <= 0 then
				text = "Cannot Move"
			end

			tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
				color = labelColor,
				text = text,
			}
		end

		if self:try_get("auraid") ~= nil then
			local aura = params.token.properties:GetAura(self.auraid)
			if aura ~= nil then
				tokenDependentChildren[#tokenDependentChildren+1] = gui.Label{
					id = "auraInfo",
					create = function(element)
						local concentrationText = ""
						if params.token.properties:HasConcentration() and params.token.properties:MostRecentConcentration():try_get("auraid") == self.auraid then
							concentrationText = "\nConcentrating on this spell"
						end

						local roundsSince = aura.time:RoundsSince()
						local castTimeText = "this round"
						if roundsSince == 1 then
							castTimeText = "last round"
						elseif roundsSince > 1 then
							castTimeText = string.format("%d rounds ago", roundsSince)
						end
						if aura:has_key("duration") then
							local remainingRounds = aura.duration - roundsSince
							local expiresText = "this round"
							if remainingRounds == 1 then
								expiresText = "next round"
							elseif remainingRounds > 1 then
								expiresText = string.format("in %d rounds", remainingRounds)
							end

							element.text = string.format("Effect cast %s, expires %s%s", castTimeText, expiresText, concentrationText)

						else
							element.text = string.format("Effect cast %s, lasts indefinitely", castTimeText, concentrationText)
						end
					end,
				}
			end
		end

		self:RenderTokenDependent(params.token, tokenDependentChildren)

		if #tokenDependentChildren > 0 then
			tokenDependentInfoPanel = gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				children = tokenDependentChildren,
			}
		end
	end

	local description = self:GenerateTextDescription(params.token)

	if self:try_get("modifyDescriptions") ~= nil then
		for _,desc in ipairs(self.modifyDescriptions) do
			description = string.format("%s\n<color=#aaaaff>%s</color>", description, desc)
		end
	end


	local args = {
		id = 'spellInfo',
		styles = SpellRenderStyles,

		gui.Panel{
			id = "headerPanel",
			flow = "horizontal",
			valign = "top",
			width = "100%",
			height = "auto",

			gui.Panel{
				flow = "vertical",
				valign = "left",
				width = "75%",
				height = "auto",
				gui.Label{
					width = "100%",
					id = "spellName",
					text = self.name,
				},

				gui.Label{
					width = "100%",
					text = string.format("<b>Range:</b> %s", self:DescribeRange()),
				},

				tokenDependentInfoPanel,
			},

			gui.Panel{
				halign = "right",
				bgimage = self.iconid,
				classes = "icon",
				selfStyle = self.display,
			},
		},

		gui.Panel{
			classes = "divider",
		},

		gui.Label{
			text = description,
			classes = "description",
			markdown = true,
		},
	}

	for k,op in pairs(options) do
		args[k] = op
	end

	return gui.Panel(args)
	
end

function ActivatedAbility:GetCastingEmote()
	if self:try_get("castingEmote") ~= nil then
		return self.castingEmote
	end

	return self:try_get("school")
end

function ActivatedAbilityBehavior:AccumulateDamageTypes(ability, result)
end

function ActivatedAbilityAttackBehavior:AccumulateDamageTypes(ability, result)
	local set = self:GetAttack(ability, nil, {}):GetDamageTypesSet()
	for _,str in ipairs(set.strings) do
		result[#result+1] = str
	end
end


function ActivatedAbility:GetDamageTypesSet()
	local result = {}

	for i,behavior in ipairs(self:try_get("behaviors", {})) do
		behavior:AccumulateDamageTypes(self, result)
	end

	return StringSet.new{
		strings = result
	}
end

local g_lookupSymbols = {
	datatype = function(c)
		return "ability"
	end,

	debuginfo = function(c)
		return string.format("ability: %s", c.name)
	end,

	name = function(c)
		return c.name
	end,

    keywords = function(c)

        local result = StringSet.new()
        for keyword,_ in pairs(c.keywords) do
            result:Add(string.lower(keyword))
        end
        return result
    end,

	action = function(c)
		local cost = c:ActionResource()
		if cost == nil then
			return "None"
		end

		local resourceTable = dmhub.GetTable("characterResources") or {}
		local resourceInfo = resourceTable[cost]
		if resourceInfo ~= nil then
			return resourceInfo.name
		end

		return cost
	end,

	self = function(c)
		return c
	end,

	spell = function(c)
		return c.isSpell
	end,

	level = function(c)
		return c:try_get("level", 0)
	end,

    freestrike = function(c)
        return c.categorization == "Basic Attack"
    end,

    usableasfreestrike = function(c)
        return c.categorization == "Basic Attack" or c:HasProperty("useasstrike")
    end,

    usableassignatureability = function(c)
        return c.categorization == "Basic Attack" or c.categorization == "Signature Ability" or c:HasProperty("useasstrike") or c:HasProperty("useassignature")
    end,

	remainhidden = function(c)
		return c:try_get("remainHidden", false)
	end,

	cantrip = function(c)
		return c.typeName == "Spell" and c:try_get("level", 0) == 0
	end,

	school = function(c)
		return c:try_get("school")
	end,

	numberoftargets = function(c)
		return tonumber(c.numTargets)
	end,


	range = function(c)
		return c:GetRange()
	end,

	damagetypes = function(c)
		return c:GetDamageTypesSet()
	end,

	weaponattack = function(c)
		if c.isSpell then
			return false
		end

		for _,behavior in ipairs(c.behaviors) do
			if behavior.typeName == "ActivatedAbilityAttackBehavior" then
				return true
			end
		end
	end,

	hasattack = function(c)
		return c:HasAttack()
	end,

	hasheal = function(c)
		for _,behavior in ipairs(c.behaviors) do
			if behavior.typeName == "ActivatedAbilityHealBehavior" then
				return true
			end
		end
		return false
	end,

	attack = function(c)
		for _,behavior in ipairs(c.behaviors) do
			if behavior.typeName == "ActivatedAbilityAttackBehavior" then
				return GenerateSymbols(behavior:GetAttack(c, nil, {}))
			end
		end

		return nil
	end,

	inflicts = function(c)
		return function(condition)
			--confirm this is a valid condition
			if CharacterCondition.conditionsByName[condition] == nil then
				return false
			end

			local conditionPattern = string.format("\\b%s\\b", string.lower(condition))
			for _,behavior in ipairs(c.behaviors) do
				if behavior.typeName == "ActivatedAbilityPowerRollBehavior" then
					if behavior.tiers ~= nil then
						for _, tier in ipairs(behavior.tiers) do
							local tierText = string.lower(tier)
							if regex.MatchGroups(tierText, conditionPattern) ~= nil then
								return true
							end
						end
					end
				elseif behavior.typeName == "ActivatedAbilityDrawSteelCommandBehavior" then
					if behavior.rule ~= nil then
						local ruleText = string.lower(behavior.rule)
						if regex.MatchGroups(ruleText, conditionPattern) ~= nil then
							return true
						end
					end
				end
			end
			return false
		end
	end,
}

local g_helpCasting = {
	charges = {
		name = "Charges",
		type = "number",
		desc = "When using an ability that has charges, and allows the user to use multiple charges at once, this is the number of charges used. ",
		examples = {"charges", "1d6 + 2*charges"},
	},
	mode = {
		name = "Mode",
		type = "number",
		desc = "When using an ability that has multiple modes, this is the number of the mode the player chose when using the ability. You can set an ability up with modes on the ability's property page. Mode will be equal to 1 if the player chose the first mode, 2 for the second mode, and so forth. Mode is always 1 for abilities that don't have multiple modes.",
	},
	cast = {
		name = "Cast",
		type = "spellcast",
		desc = "Information about what has happened while casting this spell.",
	},
	invoker = {
		name = "Invoker",
		type = "creature",
		desc = "The creature that caused this ability to be invoked. Only valid for abilities invoked from another ability.",
	},
}

local g_helpSymbols = {
	__name = "ability",
	__sampleFields = {"level", "school"},


	name = {
		name = "Name",
		type = "text",
		desc = "The name of the ability.",
		examples = {"Name is Wild Shape"},
	},

	action = {
		name = "Action",
		type = "text",
		desc = "The name of the action that this ability consumes.",
		examples = {"Action is Standard Action"},
	},

	spell = {
		name = "Spell",
		type = "boolean",
		desc = "True for abilities that are spells. False for other types of abilities.",
	},

    freestrike = {
        name = "Free Strike",
        type = "boolean",
        desc = "Whether this is a free strike.",
    },

    usableasfreestrike = {
        name = "Usable as Free Strike",
        type = "boolean",
        desc = "Whether this ability can be used as a free strike.",
    },

    usableassignatureability = {
        name = "Usable as Signature Ability",
        type = "boolean",
        desc = "Whether this ability can be used as a signature ability.",
    },

	remainhidden = {
		name = "Remain Hidden",
		type = "boolean",
		desc = "Whether creature should remain hidden when using this ability.",
	},

	level = {
		name = "Level",
		type = "number",
		desc = "The level of the spell. 0 for abilities that are not spells.",
	},

    keywords = {
        name = "Keywords",
        type = "set",
        desc = "The keywords the ability has",
        examples = {"Ability.Keywords Has 'Fire'"},
    },

	numberoftargets = {
		name = "Number of Targets",
		type = "number",
		desc = "The number of targets this ability targets. Nothing if the number of targets varies.",
	},

	weaponattack = {
		name = "Weapon Attack",
		type = "boolean",
		desc = "True for abilities that include a weapon attack. All attacks are either weapon attacks or spell attacks.",
		seealso = {"Spell", "Has Attack"},
	},

	hasattack = {
		name = "Has Attack",
		type = "boolean",
		desc = "True for abilities that include an attack.",
	},

	hasheal = {
		name = "Has Heal",
		type = "boolean",
		desc = "True for abilities that include healing.",
	},

	attack = {
		name = "Attack",
		type = "attack",
		desc = "The attack this ability uses. Only available if Has Attack is true.",
	},

	range = {
		name = "Range",
		type = "number",
		desc = "The range of this ability, in feet.",
	},

	damagetypes = {
		name = "Damage Types",
		type = "set",
		desc = "The set of damage types this ability can inflict. Is empty for abilities that inflict no damage.",
		examples = {'Ability.Damage Types Has "Fire"'},
	},

	inflicts = {
		name = "Inflicts",
		type = "function",
		desc = "Returns whether this ability inflicts the provided condition",
		examples = {'Ability.Inflicts("Frightened")'},
	}
}

ActivatedAbility.lookupSymbols = g_lookupSymbols
ActivatedAbility.helpCasting = g_helpCasting
ActivatedAbility.helpSymbols = g_helpSymbols

dmhub.RegisterEventHandler("refreshTables", function(keys)
	if keys ~= nil and (not keys[CustomFieldCollection.tableName]) then
		return
	end

	local table = dmhub.GetTable(CustomFieldCollection.tableName) or {}

    local customFields = table["spells"]
	if customFields == nil then
		return
	end

	ActivatedAbility.lookupSymbols = shallow_copy_table(g_lookupSymbols)
	ActivatedAbility.helpSymbols = shallow_copy_table(g_helpSymbols)

	for k,v in pairs(customFields.fields) do
		local symbol = v:SymbolName()

		printf("Spell Custom Symbol: %s", symbol)

		ActivatedAbility.lookupSymbols[symbol] = function(c)
			local customFields = c:try_get("customFields")
			if customFields == nil then
				return v.default
			end

			return customFields:try_get(k, v.default)
		end

		local documentation = v.documentation
		if documentation == nil or documentation == "" then
			documentation = string.format("The %s custom field", v.name)
		end
		ActivatedAbility.helpSymbols[symbol] = {
			name = v.name,
			type = "number",
			desc = documentation,
		}
	end
end)
