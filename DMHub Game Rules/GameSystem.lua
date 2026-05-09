local mod = dmhub.GetModLoading()

--- @class GameSystem
--- @field rollTypes table[] Registered roll type descriptors for this game system.
--- @field leveledProficiencyTypes table[] Proficiency types that scale with level.
--- @field HitpointsName string Localized term for hit points.
--- @field AttributeName string Localized term for a single attribute.
--- @field AttributeNamePlural string Localized plural for attributes.
--- @field SkillName string Localized term for a single skill.
--- @field SkillNamePlural string Localized plural for skills.
--- @field SavingThrowName string Localized term for a saving throw.
--- @field SavingThrowRollName string Localized name used in roll dialogs.
--- @field SavingThrowNamePlural string Localized plural for saving throws.
--- @field BackgroundName string Localized term for a background.
--- @field BackgroundNamePlural string Localized plural for backgrounds.
--- @field RaceName string Localized term for a race/ancestry.
--- @field RaceNamePlural string Localized plural for races.
--- @field RacesHaveHeights boolean If true, race entries include height fields.
--- @field CRName string Abbreviation for challenge rating.
--- @field ChallengeName string Localized term for challenge.
--- @field ChallengeRatingName string Full localized term for challenge rating.
--- @field UseAttackRolls boolean If false, attacks always hit (no roll needed).
--- @field BaseAttackRoll string Dice expression for a base attack roll.
--- @field BaseSkillRoll string Dice expression for a base skill check.
--- @field BaseInitiativeRoll string Dice expression for a base initiative roll.
--- @field BaseSavingThrowRoll string Dice expression for a base saving throw.
--- @field FlatRoll string Dice expression used for a flat (unmodified) roll.
--- @field UseBoons boolean If true, the game uses boon/bane advantage system.
--- @field CombineNegativesForRolls boolean If true, negative dice in a roll expression are normalized.
--- @field CriticalHitsModifyDamage boolean If true, critical hits add extra damage dice.
--- @field LowerInitiativeIsFaster boolean If true, lower initiative values act first.
--- @field CalculateDeathSavingThrowRoll fun(creature: creature): string Returns the dice expression for death saves.
--- @field CalculateAttributeModifier fun(attributeInfo: table, attributeValue: number): number Converts a raw attribute score to its modifier.
--- @field CalculateInitiativeModifier fun(creature: creature): number Returns the initiative modifier for a creature.
--- @field AllowBoonsForRoll fun(options: table): boolean Returns true if boons/banes apply to the given roll.
GameSystem = RegisterGameType("GameSystem")

--- @class RollRules
--- Settings and overrides for how a specific roll type is executed.
RollRules = RegisterGameType("RollRules")

GameSystem.rollTypes = {}
GameSystem.leveledProficiencyTypes = {}

local defaultCalculationFunction = function() return 0 end

--what this game system calls things.
GameSystem.HitpointsName = "Hitpoints"
GameSystem.AttributeName = "Attribute"
GameSystem.AttributeNamePlural = "Attributes"
GameSystem.SkillName = "Skill"
GameSystem.SkillNamePlural = "Skills"
GameSystem.SavingThrowName = "Saving Throw"
GameSystem.SavingThrowRollName = "Saving Throw"
GameSystem.SavingThrowNamePlural = "Saving Throws"

GameSystem.BackgroundName = "Background"
GameSystem.BackgroundNamePlural = "Backgrounds"
GameSystem.RaceName = "Race"
GameSystem.RaceNamePlural = "Races"
GameSystem.RacesHaveHeights = true
GameSystem.CRName = "CR"
GameSystem.ChallengeName = "Challenge"
GameSystem.ChallengeRatingName = "Challenge Rating"

GameSystem.UseAttackRolls = true

GameSystem.BaseAttackRoll = "1d20"
GameSystem.BaseSkillRoll = "1d20"
GameSystem.BaseInitiativeRoll = "1d20"
GameSystem.BaseSavingThrowRoll = "1d20"
GameSystem.FlatRoll = "1d20"

GameSystem.UseBoons = false
GameSystem.AllowBoonsForRoll = function(options)
	--can use options.type to query the roll type in here if we want to allow boons for a roll.
	return false
end

--if this is true, then if a roll from a dialog ever has e.g. 2d12-1d12 then it will normalize to 1d12.
GameSystem.CombineNegativesForRolls = false

--do critical hits modify damage in this game system?
GameSystem.CriticalHitsModifyDamage = true

GameSystem.CalculateDeathSavingThrowRoll = function(creature)
    return "1d20"
end

GameSystem.LowerInitiativeIsFaster = false

GameSystem.CalculateAttributeModifier = function(attributeInfo, attributeValue)
	local n = attributeValue
	if (n%2 == 1) then
		n = n-1
	end

	return math.tointeger((n/2) - 5)
end

GameSystem.CalculateInitiativeModifier = function(creature)
	return self:GetAttribute('dex'):Modifier()
end

--This calculates which attribute is used to add its modifier for bonus damage
--to an attack. It should return something like 'str', 'dex', etc, nil to not
--apply any bonus. It can also return a number and that amount will be used.
--
--If it does return an attribute, that attribute can be overridden by modifiers
--that override the attribute type to use.
--
--options is in this format: { melee: true/false }
GameSystem.CalculateAttackBonus = function(creature, weapon, options)
	local attrid = 'str'
	if (weapon:HasProperty('finesse') and creature:GetAttribute('dex'):Modifier() > creature:GetAttribute('str'):Modifier()) or ((not options.melee) and not weapon:HasProperty('thrown')) then
		attrid = 'dex'
	end

    return attrid
end

GameSystem.BaseArmorClass = 10
GameSystem.ArmorClassModifierAttrId = "dex"

--function(creature, proficiencyLevel) : number
GameSystem.CalculateProficiencyBonus = defaultCalculationFunction

--function(creature, spell) : number
local defaultSpellSaveDC = function() return 0 end

GameSystem.CalculateSpellSaveDC = defaultCalculationFunction
GameSystem.CalculateSpellAttackModifier = defaultCalculationFunction
GameSystem.CalculateWeaponProficiencyBonus = defaultCalculationFunction
GameSystem.CalculateSavingThrowModifier = defaultCalculationFunction

GameSystem.maxSpellLevel = 9
GameSystem.ApplyToTargetsList = {}
GameSystem.ApplyToTargetsByID = {}

GameSystem.hasAbilityCategorization = false
GameSystem.abilityCategories = {}

function GameSystem.RegisterAbilityCategorization(args)
    local category = args.category
	if rawget(ActivatedAbility, "categorization") == nil then
		ActivatedAbility.categorization = category
	end
	GameSystem.hasAbilityCategorization = true
	GameSystem.abilityCategories[category] = args
end

GameSystem.hasAbilityKeywords = false
GameSystem.abilityKeywords = {}
GameSystem.itemKeywords = {}

--do we trigger abilities at the start of the round?
GameSystem.HaveBeginRoundTrigger = false

function GameSystem.RegisterAbilityKeyword(keyword)
	GameSystem.hasAbilityKeywords = true
	GameSystem.abilityKeywords[keyword] = true
end

function GameSystem.RegisterItemKeyword(keyword)
	GameSystem.itemKeywords[keyword] = true
end

function GameSystem.KeywordsSetToDropdownList(keywords, set)
    keywords = keywords or GameSystem.abilityKeywords
    local result = set or {}
    for k,v in pairs(keywords) do
        if type(v) == "table" then
            GameSystem.KeywordsSetToDropdownList(v, result)
        else
            result[#result+1] = {
                id = k,
                text = k,
            }
        end
    end

    table.sort(result, function(a,b) return a.text < b.text end)

    return result
end

function GameSystem.ClearRules()
    creature.ClearAttributes()
    creature.ClearSavingThrows()
    GameSystem.rollTypes = {}
    creature.ClearProficiencyLevels()
    GameSystem.leveledProficiencyTypes = {}
    GameSystem.CalculateProficiencyBonus = defaultCalculationFunction
    GameSystem.CalculateSpellSaveDC = defaultCalculationFunction
    GameSystem.CalculateSpellAttackModifier = defaultCalculationFunction
    GameSystem.CalculateWeaponProficiencyBonus = defaultCalculationFunction
    GameSystem.CalculateSavingThrowModifier = defaultCalculationFunction

	GameSystem.abilityKeywords = {}
    GameSystem.itemKeywords = {}

	GameSystem.CharacterBuilderShowsHitpoints = true

	GameSystem.registeredConditionRules = {}

    dmhub.ClearRollBonusTypes()
end

function GameSystem.ClearWeaponProperties()
    weapon.builtinWeaponProperties = {}
    WeaponProperty.builtins = {}
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:138
function GameSystem.BaseCreatureResources(creature)
    return {
		standardAction = 1,
		movementAction = 1,
		bonusAction = 1,
		reaction = 1,
    }
end
--]==]

GameSystem.spellSlotsTable = {
	{ 2 }, -- level 1
	{ 3 }, -- level 2
	{ 4, 2 }, -- level 3
	{ 4, 3,}, -- level 4
	{ 4, 3, 2 }, -- level 5
	{ 4, 3, 3 }, -- level 6
	{ 4, 3, 3, 1 }, -- level 7
	{ 4, 3, 3, 2 }, -- level 8
	{ 4, 3, 3, 3, 1 }, -- level 9
	{ 4, 3, 3, 3, 2 }, -- level 10
	{ 4, 3, 3, 3, 2, 1 }, -- level 11
	{ 4, 3, 3, 3, 2, 1 }, -- level 12
	{ 4, 3, 3, 3, 2, 1, 1 }, -- level 13
	{ 4, 3, 3, 3, 2, 1, 1 }, -- level 14
	{ 4, 3, 3, 3, 2, 1, 1, 1 }, -- level 15
	{ 4, 3, 3, 3, 2, 1, 1, 1 }, -- level 16
	{ 4, 3, 3, 3, 2, 1, 1, 1, 1 }, -- level 17
	{ 4, 3, 3, 3, 3, 1, 1, 1, 1 }, -- level 18
	{ 4, 3, 3, 3, 3, 2, 1, 1, 1 }, -- level 19
	{ 4, 3, 3, 3, 3, 2, 2, 1, 1 }, -- level 20
}


--this determines what the first level spell slot is. It should match exactly the name in the resources for the first level
--spell slot. Subsequent spell slots will be determined based on resources that improve from that.
GameSystem.firstLevelSpellSlotName = "Spell Slot (level 1)"



function GameSystem.RegisterRollBonusType(name)
    dmhub.RegisterRollBonusType(name)
end

function GameSystem.NotProficientId()
	return GameSystem.NotProficient().id
end

function GameSystem.ProficientId()
	return GameSystem.Proficient().id
end

function GameSystem.NotProficient()
    return creature.proficiencyMultiplierToValue[0]
end

function GameSystem.Proficient()
	return creature.proficiencyMultiplierToValue[1]
end

function GameSystem.SetLeveledProficiency(t)
    GameSystem.leveledProficiencyTypes[t] = true
end

function GameSystem.IsProficiencyTypeLeveled(t)
    return GameSystem.leveledProficiencyTypes[t] == true
end

function GameSystem.RegisterAttribute(info)
    creature.RegisterAttribute(info)
end

function GameSystem.RegisterSavingThrow(info)
    creature.RegisterSavingThrow(info)
end

function GameSystem.RegisterRollType(rollname, fn)
    GameSystem.rollTypes[rollname] = fn
end

function GameSystem.GetRollType(rollname)
    return GameSystem.rollTypes[rollname]
end

function GameSystem.GetRollProperties(name, dc)
	local rollProperties = RollProperties.new{}

    local fn = GameSystem.rollTypes[name]
    if fn ~= nil then
        fn(rollProperties, dc)
    end

    return rollProperties
end

function GameSystem.PrettyAttackOutcomes()
    local props = GameSystem.GetRollProperties("attack", 0)
    local result = {}
    for _,outcome in ipairs(props:Outcomes()) do
        result[#result+1] = outcome.outcome
    end

    return pretty_join_list(result)
end

function GameSystem.RegisterProficiencyLevel(args)
    creature.RegisterProficiency(args)
end

function GameSystem.RegisterGoblinScriptField(args)
	RegisterGoblinScriptSymbol(args.target or creature, args)
end

function GameSystem.RegisterModifiableAttribute(options)
	CustomAttribute.RegisterAttribute(options)
end

GameSystem.RegisterModifiableAttribute{
    id = "ignoreoffhandpenalty",
    text = "Ignore Offhand Damage Penalty",
    attributeType = "number",
    category = "Combat",
}

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:601
function GameSystem.IgnoreOffhandWeaponPenalty(creature, weapon)
	return creature:CalculateAttribute('ignoreoffhandpenalty', 0) > 0
end
--]==]


function GameSystem.RegisterBuiltinWeaponProperty(properties)

    --remove any existing entry if one exists.
    for i,builtin in ipairs(weapon.builtinWeaponProperties) do
        if builtin.attr == properties.attr then
            table.remove(weapon.builtinWeaponProperties, i)
            break
        end
    end

    weapon.builtinWeaponProperties[#weapon.builtinWeaponProperties+1] = properties
    WeaponProperty.builtins[properties.attr] = WeaponProperty.new{
        name = properties.text,
        id = properties.attr,
    }
end

GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Ammo'), attr = 'ammo' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Range'), attr = 'range' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Thrown'), attr = 'thrown' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Loading'), attr = 'loading' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Light'), attr = 'light' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Heavy'), attr = 'heavy' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Finesse'), attr = 'finesse' }
GameSystem.RegisterBuiltinWeaponProperty{ text = tr('Reach'), attr = 'reach' }

-- HITPOINTS

GameSystem.GenerateClassHitpointsRulesText = function(class)
    return string.format(tr([[<size=120%%><smallcaps><b>Hit Points</b></smallcaps></size>
<b>Hit Dice:</b> 1d%d per %s level
<b>Hit Points at 1st Level:</b> %d + your Constitution modifier
<b>Hit Points at Higher Levels:</b> 1d%d (or %d) + your Constitution modifier per %s level after 1st]]),
        class.hit_die, string.lower(class.name), class.hit_die, class.hit_die, math.ceil(class.hit_die/2) + 1, string.lower(class.name))
end

GameSystem.allowRollForHitpoints = true

GameSystem.allowNegativeHitpoints = false

--the number of hitpoints gained each level when using fixed hitpoints
GameSystem.FixedHitpointsForLevel = function(class, firstLevel)
    if firstLevel then
        return class.hit_die
    else
        return round(1 + class.hit_die/2)
    end
end

GameSystem.BonusHitpointsForLevel = function(creature)
    return creature:AttributeMod("con")
end

GameSystem.bonusHitpointsForLevelRulesText = tr("Con. Mod.")

--does this game system use hit dice?
GameSystem.haveHitDice = true

--does this game system have temporary hitpoints?
GameSystem.haveTemporaryHitpoints = true

--do races list features for each and every level?
GameSystem.racesHaveLeveling = false

GameSystem.numLevels = 20

--if true, then ranged attacks will have a 'near' and 'far' range, the far range being made at disadvantage.
GameSystem.attacksAtLongRangeHaveDisadvantage = true

--if this is true, then attack behaviors can have weapon properties.
GameSystem.attacksCanHaveWeaponProperties = false

--how do we describe an attack?
GameSystem.DescribeAttack = function(ranged, offhand, hit, reach, damage, propertyDescription)
	return string.format("%s%s: %s to hit, %s, %s damage.%s", cond(ranged, "Ranged Attack", "Melee Attack"), offhand, hit, reach, damage, propertyDescription)
end

--standard modifiers in various combat situations.

--Create some "standard modifiers" that we use in a variety of situation that use d20 modifiers.
CharacterModifier.StandardModifiers.RangedAttackWithEnemiesNearby = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "Ranged Attack With Nearby Enemies",
	source = "Ranged Attack",
	description = "When making a ranged attack when there are enemies nearby, you have disadvantage on the attack.",
}

CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.RangedAttackWithEnemiesNearby)
CharacterModifier.StandardModifiers.RangedAttackWithEnemiesNearby.modifyType = 'disadvantage'

CharacterModifier.StandardModifiers.RangedAttackDistant = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "Outside Attack Range",
	source = "Ranged Attack",
	description = "When making an attack with a ranged weapon against enemies outside of the normal attack range, you have disadvantage on the attack roll.",
}

CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.RangedAttackDistant)
CharacterModifier.StandardModifiers.RangedAttackDistant.modifyType = 'disadvantage'

CharacterModifier.StandardModifiers.SavingThrowNoCover = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "No Cover",
	source = "Cover",
	description = "This creature has no cover from the effect causing the saving throw.",
}
CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.SavingThrowNoCover)
CharacterModifier.StandardModifiers.SavingThrowNoCover.modifyType = 'roll'
CharacterModifier.StandardModifiers.SavingThrowNoCover.modifyRoll = ' + 0'

CharacterModifier.StandardModifiers.SavingThrowHalfCover = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "Half Cover",
	source = "Cover",
	description = "This creature has half cover from the effect causing the saving throw.",
}
CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.SavingThrowHalfCover)
CharacterModifier.StandardModifiers.SavingThrowHalfCover.modifyType = 'roll'
CharacterModifier.StandardModifiers.SavingThrowHalfCover.modifyRoll = ' + 2'

CharacterModifier.StandardModifiers.SavingThrowThreeQuartersCover = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "Three-quarters Cover",
	source = "Cover",
	description = "This creature has three-quarters cover from the effect causing the saving throw.",
}

CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.SavingThrowThreeQuartersCover)
CharacterModifier.StandardModifiers.SavingThrowThreeQuartersCover.modifyType = 'roll'
CharacterModifier.StandardModifiers.SavingThrowThreeQuartersCover.modifyRoll = ' + 5'

CharacterModifier.StandardModifiers.RangedAttackNoCover = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "No Cover",
	source = "Cover",
	description = "This creature has no cover from the attack.",
}
CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.RangedAttackNoCover)
CharacterModifier.StandardModifiers.RangedAttackNoCover.modifyType = 'roll'
CharacterModifier.StandardModifiers.RangedAttackNoCover.modifyRoll = ' + 0'

CharacterModifier.StandardModifiers.RangedAttackHalfCover = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "Half Cover",
	source = "Cover",
	description = "This creature has half cover from the attack.",
}
CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.RangedAttackHalfCover)
CharacterModifier.StandardModifiers.RangedAttackHalfCover.modifyType = 'roll'
CharacterModifier.StandardModifiers.RangedAttackHalfCover.modifyRoll = ' - 2'

CharacterModifier.StandardModifiers.RangedAttackThreeQuartersCover = CharacterModifier.new{
	behavior = 'd20',
	guid = dmhub.GenerateGuid(),
	name = "Three-quarters Cover",
	source = "Cover",
	description = "This creature has three-quarters cover from the attack.",
}

CharacterModifier.TypeInfo.d20.init(CharacterModifier.StandardModifiers.RangedAttackThreeQuartersCover)
CharacterModifier.StandardModifiers.RangedAttackThreeQuartersCover.modifyType = 'roll'
CharacterModifier.StandardModifiers.RangedAttackThreeQuartersCover.modifyRoll = ' - 5'

GameSystem.AllowMultipleConcentration = false

--This calculates the concentration saving throw that will be made when receiving damage.
GameSystem.ConcentrationSavingThrow = function(creature, damageAmount)
	return {
		dc = math.floor(math.max(10, damageAmount/2)), --10, or half damage amount, whichever is higher.
		type = "save",
		id = "con", --id of the saving throw to use.
		autosuccess = false,
		autofailure = false,
	}
end

--Calculates the spellcasting methods that are available for this game system.
GameSystem.CalculateSpellcastingMethods = function()
	local result = {}

	--we make a spellcasting method for each class.
	local classesTable = dmhub.GetTable(Class.tableName)
    for k,v in pairs(classesTable) do
        if not v:try_get("hidden", false) then
            result[#result+1] = {
                id = k,
                text = v.name,
            }
        end
    end


	--example: suppose you wanted a special spellcasting method using a "Focus".
	--result[#result+1] = {
	--	id = "focus",
	--	text = "Focus",
	--}

	return result
end

function GameSystem.GetApplyToInfo(id)
	return GameSystem.ApplyToTargetsByID[id] or {}
end

function GameSystem.RegisterApplyToTargets(entry)
	if GameSystem.ApplyToTargetsByID[entry.id] ~= nil then
		local newList = {}
		for _,existing in ipairs(GameSystem.ApplyToTargetsList) do
			if entry.id ~= existing.id then
				newList[#newList+1] = existing
			end
		end

		GameSystem.ApplyToTargetsList = newList
	end

	GameSystem.ApplyToTargetsList[#GameSystem.ApplyToTargetsList+1] = entry
	GameSystem.ApplyToTargetsByID[entry.id] = entry
end

--when casting a spell, this is our set of 'target lists' who have different outcomes to what has happened in the spell so far.
--it might include lists of creatures who have been hit, made a save, failed a save, been critically hit, etc.
GameSystem.RegisterApplyToTargets{
	id = "hit_targets",
	text = "Targets Hit",
	attack_hit = true,
}

GameSystem.RegisterApplyToTargets{
	id = "hit_targets_crit",
	text = "Targets Hit Critically",
}

GameSystem.RegisterApplyToTargets{
	id = "failed_save_targets",
	text = "Targets Who Failed Check",
}

GameSystem.RegisterApplyToTargets{
	id = "passed_save_targets",
	text = "Targets Who Didn't Fail Check",
	inverse = "failed_save_targets",
}

--This is the list of possible ways that a spell that does damage and can take a saving throw allows the target to modify the damage
--if they succeed on the saving throw.
GameSystem.SavingThrowDamageSuccessModes = { { id = "half", text = "Half Damage" }, { id = "none", text = "No Damage" } }

--We calculate how saving throw damage is calculated if we succeed or fail a saving throw.
--spellSuccessMode will be one of the id's from SavingThrowDamageSuccessModes.
--rollOutcome will be like {outcome = "Success", success = true, value = 11, degree = 1}
GameSystem.SavingThrowDamageCalculation = function(rollOutcome, spellSuccessMode)
	if rollOutcome.success then
		if spellSuccessMode == "half" then
			return {
				damageMultiplier = 0.5,
				saveText = "Save Succeeded for Half Damage",
				summary = "half damage",
			}
		else
			return {
				damageMultiplier = 0,
				saveText = "Save Succeeded for No Damage",
				summary = "no damage",
				color = "grey",
			}
		end
	else
		return {
			damageMultiplier = 1,
			saveText = "Save Failed, Full Damage",
			summary = "full damage",
			color = "red",
		}
	end
end

GameSystem.CharacterBuilderShowsHitpoints = true

GameSystem.registeredConditionRules = {}

GameSystem.RegisterConditionRule = function(rule)
	GameSystem.registeredConditionRules[rule.id] = rule
end

GameSystem.RegisterConditionRule{
	id = "unconscious",
	conditions = {"Unconscious", "Incapacitated", "Prone"},

	rule = function(targetCreature, modifiers)
		return targetCreature:MaxHitpoints(modifiers) <= targetCreature.damage_taken
	end,
}

GameSystem.OnEndCastActivatedAbility = function(casterToken, ability, options)
end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMRules.lua:1173
function GameSystem.AllowTargeting(casterToken, targetToken, ability)
	return true
end
--]==]

function GameSystem.RegisterCreatureSizes(sizes)

	dmhub.rules.CreatureSizes = sizes

	creature.sizeToNumber = {}
	creature.sizes = {}

	for _,size in ipairs(sizes) do
		creature.sizes[#creature.sizes+1] = size.name
		creature.sizeToNumber[size.name] = #creature.sizes
	end
end

	print("CreatureSize: Calling Registering sizes:")
GameSystem.RegisterCreatureSizes{
	{
		name = "Tiny",
		tiles = 1,
		radius = 0.3,
		creaturesPerTile = 4,
	},
	{
		name = "Small",
		tiles = 1,
		radius = 0.4,
	},
	{
		name = "Medium",
		tiles = 1,
		radius = 0.5,
		defaultSize = true,
	},
	{
		name = "Large",
		tiles = 2,
		radius = 0.9,
	},
	{
		name = "Huge",
		tiles = 3,
		radius = 1.4,
	},
	{
		name = "Gargantuan",
		tiles = 4,
		radius = 2.0,
	},
}

--do abilities have an attribute that they have affinity for.
GameSystem.abilitiesHaveAttribute = true

--do abilities have a duration field by default?
GameSystem.abilitiesHaveDuration = true

GameSystem.GameMasterShortName = "GM"
GameSystem.GameMasterLongName = "Game Master"

GameSystem.encumbrance = false
